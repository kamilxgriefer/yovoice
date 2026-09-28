import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';

/// The icon-only create `+` of a feed's chrome as a gradient RING (owner's
/// variant B, 2026-09-28, ADR-229): a 2 px logo-gradient stroke around a
/// 40 px circle, centred in the 48 px target the row reserves, with a bold
/// rounded `+` drawn by a painter.
///
/// * Over footage ([onMedia]) the inside is a blurred black @ .28 glass
///   (hover .38, high contrast .60) over a neutral contact shadow, and the
///   `+` is white — the same in both appearances.
/// * On the page canvas the inside is clear (hover fills it with
///   `surfaceMuted`), the `+` is `textPrimary` and there is no shadow.
/// * Disabled: the ring is `border`, the `+` `textTertiary`.
/// * High contrast: the denser glass, no shadow, and a 1 px outer hairline
///   (white over media, `borderStrong` on the canvas).
///
/// The ring is the one lit thing; nothing is filled with the gradient.
///
/// [AccessibleTapRegion] keeps the button semantics, Enter/Space, the tooltip
/// and the 48 px target, but draws no ring of its own: this button paints its
/// focus ring 2 px outside the 40 px circle (white with a black edge over
/// footage, `palette.focus` on the canvas), only for keyboard focus.
///
/// **The invitation echo.** Each change of [echoes] plays ONE echo: a copy
/// of the ring that grows 1.0 → [echoScale] and fades (1600 ms), while the
/// button itself never moves. The button only ever animates on such an
/// event, so it has no idle loop; the caller owns the schedule (for Yeels,
/// `YeelsCreateInvitation`: about 3 s after the format appears, then every
/// ~40 s, at most three per visit). No echo plays under Reduce Motion,
/// accessible navigation, a paused [TickerMode], high contrast, while
/// disabled, while another route covers this one, or while the button has
/// keyboard focus or a hovering pointer (the echo would otherwise pass
/// through the focus ring and read as a change of focus); focus or hover
/// arriving mid-echo ends it at once.
///
/// The echo repaints inside its own [RepaintBoundary], and the static face
/// (glass, ring and `+`) sits in another, so an echo frame re-records only
/// the echo — not the feed chrome around it nor the backdrop blur.
class YoCreateRingButton extends StatefulWidget {
  const YoCreateRingButton({
    required this.semanticLabel,
    required this.onTap,
    this.tooltip,
    this.onMedia = true,
    this.focusNode,
    this.echoes,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final String? tooltip;

  /// True over footage; false on the page canvas.
  final bool onMedia;
  final FocusNode? focusNode;

  /// Every change plays one invitation echo (see the class docs). Null never
  /// echoes.
  final ValueListenable<int>? echoes;

  /// The layout box and hit target.
  static const double target = 48;

  /// The visible circle.
  static const double diameter = 40;
  static const double ringWidth = 2;

  /// The full span of each bar of the `+`.
  static const double glyphSpan = 16;
  static const double glyphStroke = 2.6;

  /// Media glass: black at these alphas.
  static const double glass = .28;
  static const double glassHover = .38;
  static const double glassHighContrast = .60;
  static const double glassBlur = 12;

  /// The neutral contact shadow under the media circle (black @ .18).
  static const Color contactShadow = Color(0x2E000000);

  // The echo.
  static const Duration echoDuration = Duration(milliseconds: 1600);

  /// The approved render's value (variant B, "deliberately gentle"): at
  /// the peak the echo reads as the ring thickening and glowing 2–3 px
  /// outward, and its bloom stays inside the header row's top padding.
  static const double echoScale = 1.12;
  static const double echoPeakAt = .28;
  static const double echoPeakAlpha = .90;
  static const double echoBloomAlpha = .55;

  /// Whether an echo may play here at all.
  static bool echoAllowed(BuildContext context, {required bool enabled}) =>
      enabled &&
      !MediaQuery.highContrastOf(context) &&
      AppMotion.decorative(context);

  /// The echo's opacity at progress [t] (0..1): up to [echoPeakAlpha] at
  /// [echoPeakAt], then down to zero at the end.
  static double echoAlphaAt(double t) {
    if (t <= echoPeakAt) {
      return echoPeakAlpha * Curves.easeOut.transform(t / echoPeakAt);
    }
    return echoPeakAlpha *
        (1 -
            Curves.easeInOutSine.transform(
              (t - echoPeakAt) / (1 - echoPeakAt),
            ));
  }

  /// The echo's radius scale at progress [t] (0..1).
  static double echoScaleAt(double t) =>
      1 + (echoScale - 1) * Curves.easeOutCubic.transform(t);

  @override
  State<YoCreateRingButton> createState() => _YoCreateRingButtonState();
}

class _YoCreateRingButtonState extends State<YoCreateRingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _echo = AnimationController(
    vsync: this,
    duration: YoCreateRingButton.echoDuration,
  );
  bool _focused = false;
  bool _hovered = false;

  bool get _enabled => widget.onTap != null;

  @override
  void initState() {
    super.initState();
    widget.echoes?.addListener(_playEcho);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void didUpdateWidget(YoCreateRingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.echoes, widget.echoes)) {
      oldWidget.echoes?.removeListener(_playEcho);
      widget.echoes?.addListener(_playEcho);
    }
    _stopEchoIfBarred();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stopEchoIfBarred();
  }

  @override
  void dispose() {
    widget.echoes?.removeListener(_playEcho);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _echo.dispose();
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode _) {
    if (_focused && mounted) setState(() {});
  }

  void _stopEchoIfBarred() {
    if (_echo.isAnimating &&
        !YoCreateRingButton.echoAllowed(context, enabled: _enabled)) {
      _echo
        ..stop()
        ..value = 0;
    }
  }

  void _playEcho() {
    if (!mounted ||
        _focused ||
        _hovered ||
        !YoCreateRingButton.echoAllowed(context, enabled: _enabled) ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _echo.forward(from: 0);
  }

  /// Focus or hover arrived: an echo already playing ends here.
  void _endEcho() {
    if (!_echo.isAnimating && _echo.value == 0) return;
    _echo
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final enabled = _enabled;
    final onMedia = widget.onMedia;
    final hovered = _hovered && enabled;

    final glyph = !enabled
        ? palette.textTertiary
        : onMedia
        ? Colors.white
        : palette.textPrimary;

    Widget face = SizedBox.square(
      dimension: YoCreateRingButton.diameter,
      child: CustomPaint(
        key: const ValueKey<String>('yo-create-ring-face'),
        painter: YoCreateRingPainter(
          enabled: enabled,
          disabledColor: palette.border,
          outerHairline: highContrast
              ? (onMedia ? Colors.white : palette.borderStrong)
              : null,
        ),
        foregroundPainter: YoCreatePlusPainter(color: glyph),
      ),
    );

    if (onMedia) {
      final glassAlpha = highContrast
          ? YoCreateRingButton.glassHighContrast
          : hovered
          ? YoCreateRingButton.glassHover
          : YoCreateRingButton.glass;
      face = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // A neutral contact shadow only: no coloured smudge on footage.
          if (!highContrast)
            const DecoratedBox(
              key: ValueKey<String>('yo-create-ring-shadow'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: YoCreateRingButton.contactShadow,
                    blurRadius: 8,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: SizedBox.square(dimension: YoCreateRingButton.diameter),
            ),
          ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: YoCreateRingButton.glassBlur,
                sigmaY: YoCreateRingButton.glassBlur,
              ),
              child: ColoredBox(
                key: const ValueKey<String>('yo-create-ring-glass'),
                color: Colors.black.withValues(alpha: glassAlpha),
                child: const SizedBox.square(
                  dimension: YoCreateRingButton.diameter,
                ),
              ),
            ),
          ),
          face,
        ],
      );
    } else if (hovered) {
      face = DecoratedBox(
        key: const ValueKey<String>('yo-create-ring-hover'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceMuted,
        ),
        child: face,
      );
    }

    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return YoPressFeedback(
      scale: YoPressFeedback.disc,
      enabled: enabled,
      child: AccessibleTapRegion(
        onTap: widget.onTap,
        semanticLabel: widget.semanticLabel,
        tooltip: widget.tooltip ?? widget.semanticLabel,
        circular: true,
        minimumSize: const Size.square(YoCreateRingButton.target),
        focusNode: widget.focusNode,
        paintsIndicators: false,
        onHover: (value) {
          if (value) _endEcho();
          if (_hovered != value) setState(() => _hovered = value);
        },
        onFocusChange: (value) {
          if (value) _endEcho();
          if (_focused != value) setState(() => _focused = value);
        },
        // The echo repaints every frame for 1.6 s; its own boundary keeps
        // that from re-recording the chrome around it, and the face's
        // boundary keeps the glass blur and the `+` out of it too.
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: YoCreateRingButton.target,
            child: AnimatedBuilder(
              animation: _echo,
              builder: (context, child) => CustomPaint(
                key: const ValueKey<String>('yo-create-ring-echo'),
                painter: YoCreateEchoPainter(
                  t: _echo.isAnimating ? _echo.value : null,
                ),
                foregroundPainter: showsFocus
                    ? YoCreateFocusPainter(
                        ring: onMedia ? Colors.white : palette.focus,
                        contrast: onMedia ? Colors.black : null,
                      )
                    : null,
                child: child,
              ),
              child: Center(child: RepaintBoundary(child: face)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 2 px ring (centreline radius 19 in the 40 px box) in the logo
/// gradient, or [disabledColor]; with an optional 1 px outer hairline.
@visibleForTesting
class YoCreateRingPainter extends CustomPainter {
  const YoCreateRingPainter({
    required this.enabled,
    required this.disabledColor,
    this.outerHairline,
  });

  final bool enabled;
  final Color disabledColor;
  final Color? outerHairline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    const width = YoCreateRingButton.ringWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;
    if (enabled) {
      paint.shader = AppGradients.primary.createShader(rect);
    } else {
      paint.color = disabledColor;
    }
    canvas.drawCircle(center, size.shortestSide / 2 - width / 2, paint);
    final hairline = outerHairline;
    if (hairline != null) {
      canvas.drawCircle(
        center,
        size.shortestSide / 2 + .5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = hairline,
      );
    }
  }

  @override
  bool shouldRepaint(YoCreateRingPainter oldDelegate) =>
      oldDelegate.enabled != enabled ||
      oldDelegate.disabledColor != disabledColor ||
      oldDelegate.outerHairline != outerHairline;
}

/// The bold `+`: two 16 px bars, 2.6 px, round caps.
@visibleForTesting
class YoCreatePlusPainter extends CustomPainter {
  const YoCreatePlusPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const half = YoCreateRingButton.glyphSpan / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = YoCreateRingButton.glyphStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas
      ..drawLine(center.translate(-half, 0), center.translate(half, 0), paint)
      ..drawLine(center.translate(0, -half), center.translate(0, half), paint);
  }

  @override
  bool shouldRepaint(YoCreatePlusPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// One echo of the ring at progress [t] (null paints nothing): a constant
/// 2 px gradient stroke whose radius grows 1.0 → [YoCreateRingButton.echoScale],
/// over a soft 4 px blurred bloom at .55 of its opacity.
@visibleForTesting
class YoCreateEchoPainter extends CustomPainter {
  const YoCreateEchoPainter({required this.t});

  final double? t;

  @override
  void paint(Canvas canvas, Size size) {
    final t = this.t;
    if (t == null) return;
    final alpha = YoCreateRingButton.echoAlphaAt(t);
    if (alpha <= 0) return;
    final center = size.center(Offset.zero);
    const width = YoCreateRingButton.ringWidth;
    final radius =
        (YoCreateRingButton.diameter / 2 - width / 2) *
        YoCreateRingButton.echoScaleAt(t);
    final bounds = Rect.fromCircle(center: center, radius: radius + width);
    final shader = AppGradients.primary.createShader(bounds);
    canvas
      ..saveLayer(
        bounds.inflate(8),
        Paint()
          ..color = Colors.black.withValues(
            alpha: alpha * YoCreateRingButton.echoBloomAlpha,
          ),
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..restore()
      ..saveLayer(
        bounds.inflate(2),
        Paint()..color = Colors.black.withValues(alpha: alpha),
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..isAntiAlias = true,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(YoCreateEchoPainter oldDelegate) => oldDelegate.t != t;
}

/// Keyboard focus: a 2 px ring at radius 22–24 (a 2 px gap outside the
/// 40 px ring), plus a 1.5 px [contrast] edge at 24–25.5 over footage so one
/// edge survives any frame.
@visibleForTesting
class YoCreateFocusPainter extends CustomPainter {
  const YoCreateFocusPainter({required this.ring, this.contrast});

  final Color ring;
  final Color? contrast;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final contrast = this.contrast;
    if (contrast != null) {
      canvas.drawCircle(
        center,
        24.75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = contrast,
      );
    }
    canvas.drawCircle(
      center,
      23,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(YoCreateFocusPainter oldDelegate) =>
      oldDelegate.ring != ring || oldDelegate.contrast != contrast;
}

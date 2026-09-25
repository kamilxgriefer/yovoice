import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';

export 'package:yovoice/core/theme/app_finish.dart' show YoDiscEmphasis;

/// What the disc is doing (the caller's state machine decides).
enum YoDiscStatus { idle, busy, failed, disabled }

/// The disc's fill.
///
/// * [brand] — the logo's gradient ([AppGradients.primary]).
/// * [onBrand] — white @ .22 with no gloss, rim or shadow: a bead sitting on
///   a brand fill (the outgoing chat bubble).
/// * [live] — solid [AppColors.live] with [AppColors.onLive] ink: the
///   recording bead.
enum YoDiscTone { brand, onBrand, live }

/// The round gradient control of YO Voice: the icon-only CTA disc (R6) and
/// the voice bead (R14, "the logo's glass, lit only while a voice plays").
///
/// **Draw-only.** It owns no gesture, key, tooltip or semantics: the caller
/// keeps its `AccessibleTapRegion` / `IconButton`, its `Semantics`, its keys
/// and its callbacks, and wraps this in `YoPressFeedback(scale: .94)`. The
/// whole disc is excluded from semantics so a spinner or glyph never adds a
/// second node.
///
/// The layout box is exactly [size] × [size]; shadows and the focus ring
/// paint outside it and never move a neighbour.
///
/// * **[emphasis]** — [YoDiscEmphasis.rest] (contact shadow),
///   [YoDiscEmphasis.lift] (the one CTA per screen) or [YoDiscEmphasis.lit]
///   (only the clip that is playing). Light fades in over 180 ms and out
///   over 320 ms, instantly under Reduce Motion.
/// * **[gloss]** — a top-left highlight (white @ .28 radial) plus, when
///   [rim] is on, a 1 px inner stroke fading out by 55 % of the height.
/// * **Glyph** — white at .42 × [size] (at least 18). [nudgePlay] shifts a
///   play triangle +.03 × [size] so it reads optically centred.
/// * **[status]** — busy shows a white spinner (20; 18 at ≤ 40), failed a
///   refresh glyph, disabled a flat `surfaceMuted` disc with a
///   `textTertiary` glyph and no light; a 120 ms cross-fade between them.
/// * **High contrast** — the gradient stays; no glow, gloss or rim.
class YoGradientDisc extends StatelessWidget {
  const YoGradientDisc({
    required this.size,
    this.icon,
    this.glyph,
    this.emphasis = YoDiscEmphasis.rest,
    this.gloss = false,
    bool? rim,
    this.status = YoDiscStatus.idle,
    this.tone = YoDiscTone.brand,
    this.nudgePlay = false,
    this.glyphSize,
    this.hovered = false,
    this.focused = false,
    super.key,
  }) : rim = rim ?? gloss;

  final double size;

  /// The glyph as an icon; ignored when [glyph] is set.
  final IconData? icon;

  /// The glyph as a widget (for example an `AnimatedIcon`). It inherits the
  /// disc's white [IconTheme].
  final Widget? glyph;

  final YoDiscEmphasis emphasis;
  final bool gloss;

  /// The 1 px inner rim; defaults to [gloss]. The first thing to drop if a
  /// small bead reads as plastic.
  final bool rim;
  final YoDiscStatus status;
  final YoDiscTone tone;
  final bool nudgePlay;

  /// Overrides the .42 × [size] glyph size.
  final double? glyphSize;

  /// Pointer hover: contact and glow +.06.
  final bool hovered;

  /// Keyboard focus: a 2 px `focus` ring 3 px outside the disc.
  final bool focused;

  /// The busy spinner's size for this disc.
  double get spinnerSize => size <= 40 ? 18 : 20;

  /// The glyph's size for this disc.
  double get resolvedGlyphSize => glyphSize ?? math.max(18, size * .42);

  static const Duration litIn = AppMotion.standard; // 180 ms
  static const Duration litOut = AppMotion.entrance; // 320 ms
  static const Duration statusFade = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final disabled = status == YoDiscStatus.disabled;
    final onBrand = tone == YoDiscTone.onBrand;
    final light = !disabled && !onBrand;
    final showsGloss = gloss && light && !highContrast;
    final showsRim = rim && showsGloss;

    final Color ink;
    if (disabled) {
      ink = palette.textTertiary;
    } else if (tone == YoDiscTone.live) {
      ink = AppColors.onLive;
    } else {
      ink = AppColors.white;
    }

    final List<BoxShadow> shadows;
    if (!light || highContrast) {
      shadows = const <BoxShadow>[];
    } else {
      shadows = AppFinish.discShadow(palette, size, emphasis, hovered: hovered);
    }

    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: disabled
          ? palette.surfaceMuted
          : onBrand
          ? AppColors.white.withValues(alpha: .22)
          : tone == YoDiscTone.live
          ? AppColors.live
          : null,
      // Keep `color` null behind the gradient (see yo_button.dart).
      gradient: !disabled && tone == YoDiscTone.brand
          ? AppGradients.primary
          : null,
      boxShadow: shadows,
    );

    final Widget face = switch (status) {
      YoDiscStatus.busy => SizedBox(
        key: const ValueKey<String>('yo-disc-busy'),
        width: spinnerSize,
        height: spinnerSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: ink,
          // No theme track (surfaceSunken) under a white spinner.
          backgroundColor: Colors.transparent,
        ),
      ),
      YoDiscStatus.failed => Icon(
        Icons.refresh_rounded,
        key: const ValueKey<String>('yo-disc-failed'),
      ),
      YoDiscStatus.idle || YoDiscStatus.disabled => KeyedSubtree(
        key: const ValueKey<String>('yo-disc-glyph'),
        child: Transform.translate(
          offset: Offset(nudgePlay ? size * .03 : 0, 0),
          child: glyph ?? (icon == null ? const SizedBox() : Icon(icon)),
        ),
      ),
    };

    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: AppMotion.resolve(
                context,
                emphasis == YoDiscEmphasis.lit ? litIn : litOut,
              ),
              curve: AppMotion.standardCurve,
              decoration: decoration,
            ),
            if (showsGloss)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppFinish.discGloss,
                  ),
                ),
              ),
            if (showsRim)
              const IgnorePointer(child: CustomPaint(painter: _RimPainter())),
            Center(
              child: IconTheme.merge(
                data: IconThemeData(color: ink, size: resolvedGlyphSize),
                child: AnimatedSwitcher(
                  duration: AppMotion.resolve(context, statusFade),
                  child: face,
                ),
              ),
            ),
            if (focused)
              Positioned(
                left: -5,
                top: -5,
                right: -5,
                bottom: -5,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.focus, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A 1 px inner stroke, white @ .24 at the top fading to nothing by 55 % of
/// the disc's height: the glass edge catching the light.
class _RimPainter extends CustomPainter {
  const _RimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = AppFinish.discRim.createShader(rect);
    canvas.drawOval(rect.deflate(.5), paint);
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) => false;
}

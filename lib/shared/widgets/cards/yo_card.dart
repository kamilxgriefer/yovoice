import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';

/// The one content block of YO Voice 3.x (refine-look R2, with the optional
/// R3 corner tint).
///
/// * **Fill** — the palette's top-lit `blockGradient`; **edge** — a 1 px
///   `hairline` painted as a foreground, so hover, selection and focus never
///   shift the layout by a pixel; **radius** — [AppRadius.block] (20).
/// * **Lift** — Pearl's shadow pair on an OUTER box, so the clip that holds
///   the tint never cuts the shadow; none in Dark. [elevated] false drops it
///   for chip-like blocks.
/// * **[tint]** — the lead block's corner light: a fixed 240 px circle at the
///   top-end corner (mirrored in RTL), under the ink, never hit-testable. At
///   most one per screen (the light budget in `AppFinish`).
/// * **States** — hover swaps the edge to `hairlineHover` (and sinks the
///   Pearl drop); pressed adds a textPrimary wash and a .985 touch scale
///   ([YoPressFeedback]); focus paints a 2 px `focus` ring; selected keeps
///   today's 2 px `interactiveForeground` edge on a focus-nudged fill.
///   There is no ink ripple except InkSparkle on Android, scoped to this
///   primitive.
/// * **High contrast** — flat `surface`, 1 px `borderStrong`, no gradient,
///   tint or shadow.
///
/// Never nest a card in a card, and never use it for dense list rows.
class YoCard extends StatefulWidget {
  const YoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.selected = false,
    this.tint,
    this.radius = AppRadius.block,
    this.minHeight,
    this.semanticButton = true,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool selected;

  /// The R3 corner tint's hue (an identity or brand colour), or null.
  final Color? tint;

  final BorderRadius radius;

  /// A floor for the block's height (content still grows it).
  final double? minHeight;

  /// Whether an interactive card announces itself as one button. A caller
  /// that already wraps the card in its own `Semantics` passes false.
  final bool semanticButton;

  /// Pearl's shadow pair; false for chip-like blocks.
  final bool elevated;

  @override
  State<YoCard> createState() => _YoCardState();
}

class _YoCardState extends State<YoCard> {
  bool _focused = false;
  bool _hovered = false;

  static InteractiveInkFeatureFactory get _splashFactory =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? InkSparkle.splashFactory
      : NoSplash.splashFactory;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final interactive = widget.onTap != null;
    final hovered = _hovered && interactive;
    final duration = AppMotion.resolve(context, AppMotion.quick);

    final fill = AppFinish.blockFill(
      palette,
      radius: widget.radius,
      hovered: hovered,
      elevated: widget.elevated,
      highContrast: highContrast,
    );
    // `copyWith(gradient: null)` would keep the gradient, so the selected
    // fill is built whole: flat, focus-nudged, same radius and lift.
    final decoration = widget.selected
        ? BoxDecoration(
            color: AppFinish.blockSelectedFill(palette),
            borderRadius: fill.borderRadius,
            boxShadow: fill.boxShadow,
          )
        : fill;

    final Border edge;
    if (_focused) {
      edge = Border.all(color: palette.focus, width: 2);
    } else if (widget.selected) {
      edge = Border.all(color: palette.interactiveForeground, width: 2);
    } else {
      edge = AppFinish.blockEdge(
        palette,
        hovered: hovered,
        highContrast: highContrast,
      );
    }

    Widget content = Padding(padding: widget.padding, child: widget.child);
    final minHeight = widget.minHeight;
    if (minHeight != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: content,
      );
    }

    if (interactive) {
      final pressedWash = AppFinish.blockPressedWash(palette);
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          splashFactory: _splashFactory,
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          onHover: (value) {
            if (_hovered != value) setState(() => _hovered = value);
          },
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return pressedWash;
            // Hover and focus are carried by the edge, not a wash.
            return Colors.transparent;
          }),
          child: content,
        ),
      );
    }

    final tint = widget.tint;
    final body = ClipRRect(
      borderRadius: widget.radius,
      child: tint == null || highContrast
          ? content
          : Stack(
              children: [
                YoCornerTint(color: tint),
                content,
              ],
            ),
    );

    Widget card = AnimatedContainer(
      duration: duration,
      curve: AppMotion.standardCurve,
      decoration: decoration,
      foregroundDecoration: BoxDecoration(
        borderRadius: widget.radius,
        border: edge,
      ),
      child: body,
    );

    if (interactive) {
      card = YoPressFeedback(scale: YoPressFeedback.block, child: card);
    }
    card = Padding(padding: widget.margin, child: card);

    if (!interactive || !widget.semanticButton) return card;
    return Semantics(button: true, selected: widget.selected, child: card);
  }
}

/// The R3 corner tint as a `Stack` child: a fixed 240 × 240 circle at
/// `top: -90, end: -70` (mirrored under RTL) holding [AppFinish.cornerTint].
/// It sits under the ink and never takes a pointer. The host clips it.
class YoCornerTint extends StatelessWidget {
  const YoCornerTint({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return PositionedDirectional(
      top: AppFinish.cornerTintTop,
      end: AppFinish.cornerTintEnd,
      width: AppFinish.cornerTintSize,
      height: AppFinish.cornerTintSize,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppFinish.cornerTint(color, palette),
          ),
        ),
      ),
    );
  }
}

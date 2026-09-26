import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';

enum YoButtonVariant { primary, secondary, ghost, danger }

/// The design system's labelled button.
///
/// [YoButtonVariant.primary] is a labelled primary action (refine-look R5):
/// the `AppGradients.primaryAction` fill (the theme's primary into its
/// AA-safe secondary) under the rail CTA's exact lift
/// ([AppFinish.actionLift]: `AppColors.primary` @ .32, blur 18, y 5; hover
/// .40 / blur 22; pressed y 3 at 60 %). A loading primary keeps its gradient
/// and half its lift — whether or not the caller also nulls `onPressed`
/// while it works; a disabled one is a quiet `surfaceSunken` fill with a
/// `textTertiary` label, no outline and no lift (R5). High contrast keeps the
/// gradient — the white label is at least 5.79:1 on both stops, so the fill
/// IS the control's identifier — and drops only the lift. Its hover and press
/// are white washes (.06 / .10) and the stronger lift — no outline.
///
/// The decoration alone owns the edge: the inner [ElevatedButton] never
/// paints a side of its own (the theme's disabled / focused sides would draw
/// a second ring inside this one). Focus is a 2 px ring painted as a
/// foreground over the fill and any 1 px edge, and a secondary / ghost hover
/// edge is painted the same way, so neither state moves the label.
///
/// Every variant scales to .98 under a touch press ([YoPressFeedback]; none
/// under Reduce Motion) and labels at letterSpacing .2.
class YoButton extends StatefulWidget {
  const YoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = YoButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.fullWidth = true,
    this.height = 58,
    this.statesController,
  });

  final String label;
  final VoidCallback? onPressed;
  final YoButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
  final bool fullWidth;

  /// Minimum visual height. The control grows when Dynamic Type makes a
  /// one-line fixed-height button unsafe.
  final double height;

  /// Passed through to the underlying button; the primary lift follows its
  /// pressed state. Optional — the button owns one when this is null.
  final WidgetStatesController? statesController;

  /// The touch press scale (refine-look §7, `YoButton`).
  static const double pressScale = .98;

  @override
  State<YoButton> createState() => _YoButtonState();
}

class _YoButtonState extends State<YoButton> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;
  WidgetStatesController? _ownController;

  bool get _isInteractive => widget.onPressed != null && !widget.isLoading;

  /// A loading button is BUSY, not disabled, even when its caller nulls
  /// [YoButton.onPressed] for the duration (the media review's Send and the
  /// Yeel composer's Publish both do, to refuse a second press). It keeps
  /// its fill and label colour; only presses are refused.
  bool get _isDisabled => widget.onPressed == null && !widget.isLoading;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownController ??= WidgetStatesController());

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
    _pressed = _states.value.contains(WidgetState.pressed);
  }

  @override
  void didUpdateWidget(covariant YoButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statesController != widget.statesController) {
      (oldWidget.statesController ?? _ownController)?.removeListener(
        _statesChanged,
      );
      _states.addListener(_statesChanged);
      _pressed = _states.value.contains(WidgetState.pressed);
    }
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownController?.dispose();
    super.dispose();
  }

  // Only the pressed state moves anything this widget paints (the lift
  // sinks). Hover and focus arrive through the button's own callbacks. The
  // button can report a state while it is being rebuilt (a press cleared
  // because the action was disabled), so a change seen during a build is
  // applied after the frame instead of marking an ancestor dirty mid-build.
  void _statesChanged() {
    if (!mounted) return;
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _statesChanged());
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final foreground = _foregroundColor(palette, colors);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final controlHeight = widget.height < AppSizing.minimumTouchTarget
        ? AppSizing.minimumTouchTarget
        : widget.height;
    final quickDuration = AppMotion.resolve(context, AppMotion.quick);
    final standardDuration = AppMotion.resolve(context, AppMotion.standard);
    final primary = widget.variant == YoButtonVariant.primary;

    Widget button = ConstrainedBox(
      constraints: BoxConstraints(minHeight: controlHeight),
      child: AnimatedContainer(
        duration: quickDuration,
        curve: Curves.easeOut,
        decoration: _decoration(palette, colors, highContrast: highContrast),
        foregroundDecoration: _stateRing(palette, colors),
        child: ElevatedButton(
          onPressed: _isInteractive ? widget.onPressed : null,
          statesController: _states,
          onHover: (value) {
            if (_hovered != value) setState(() => _hovered = value);
          },
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          style: ButtonStyle(
            // The AnimatedContainer's decoration owns the edge and
            // [_stateRing] the focus / hover ring. The theme's
            // `elevatedButtonTheme.side` (1 px `border` when disabled —
            // which a loading button is — and 2 px `onPrimary` when
            // focused) would otherwise draw a second ring inside them.
            side: const WidgetStatePropertyAll(BorderSide.none),
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            foregroundColor: WidgetStatePropertyAll(foreground),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                // R5: the primary action's washes are white @ .10 / .06.
                return foreground.withValues(alpha: primary ? .10 : .16);
              }
              if (states.contains(WidgetState.hovered)) {
                return foreground.withValues(alpha: primary ? .06 : .08);
              }
              if (states.contains(WidgetState.focused)) {
                return palette.focus.withValues(alpha: .12);
              }
              return null;
            }),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            minimumSize: WidgetStatePropertyAll(
              Size(AppSizing.minimumTouchTarget, controlHeight),
            ),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppRadius.lg),
            ),
          ),
          child: AnimatedSwitcher(
            duration: standardDuration,
            // A busy control still has to say what it is busy with. Replacing
            // the whole child with a bare spinner made every caller's label —
            // including a publish footer's live "Publishing 42%" / "Finishing…"
            // stage — invisible to a sighted user, who then read the motionless
            // spinner as a hang. The spinner stays; the label rides beside it,
            // `Flexible` so 320 px at 200% text wraps instead of overflowing.
            child: Row(
              key: ValueKey<String>(widget.isLoading ? 'loading' : 'content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (widget.isLoading) ...<Widget>[
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                      // No theme track (`surfaceSunken`): on the primary
                      // gradient it drew a dark ring around the spinner.
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (widget.icon != null) ...<Widget>[
                  IconTheme(
                    data: IconThemeData(color: foreground, size: 22),
                    child: widget.icon!,
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: textScale >= 1.6 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMedium.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The press scale listens to raw pointers only, so the button keeps
    // every tap, key and semantics action; it is zero under Reduce Motion.
    button = YoPressFeedback(
      scale: YoButton.pressScale,
      enabled: _isInteractive,
      child: button,
    );

    if (widget.fullWidth) {
      button = SizedBox(width: double.infinity, child: button);
    }
    if (!widget.isLoading) return button;
    return Semantics(
      button: true,
      enabled: false,
      label: copy.template(
        '{label}, loading',
        '{label}, trwa ładowanie',
        values: <String, Object>{'label': widget.label},
      ),
      excludeSemantics: true,
      child: button,
    );
  }

  BoxDecoration _decoration(
    AppPalette palette,
    ColorScheme colors, {
    required bool highContrast,
  }) {
    final primary = widget.variant == YoButtonVariant.primary;
    final usesPrimaryGradient = primary && !_isDisabled;

    return BoxDecoration(
      gradient: usesPrimaryGradient ? AppGradients.primaryAction(colors) : null,
      // Keep color null behind an enabled gradient. A transparent paint is
      // not equivalent here: it can suppress the shader on Flutter's raster
      // path and leave only the translucent shadow visible in Pearl.
      color: usesPrimaryGradient ? null : _backgroundColor(palette, colors),
      borderRadius: AppRadius.lg,
      // The resting edge only; focus and hover rings are foregrounds.
      border: _border(palette),
      boxShadow: usesPrimaryGradient && !highContrast
          ? AppFinish.actionLift(
              AppColors.primary,
              hovered: _hovered && _isInteractive,
              pressed: _pressed && _isInteractive,
              // A loading action keeps its gradient and half its lift.
              strength: widget.isLoading ? .5 : 1,
            )
          : const <BoxShadow>[],
    );
  }

  /// The focus ring (2 px) or, for a secondary / ghost / danger action under
  /// a pointer, the 1.5 px hover edge — painted OVER the fill and the resting
  /// edge, so the state never changes the padding or moves the label. The
  /// primary action answers a pointer with its white wash and a stronger
  /// lift, not an outline on the gradient (R5).
  ///
  /// The ring is ALWAYS present and only changes colour (transparent at
  /// rest). A null-to-value foreground would insert a DecoratedBox above the
  /// button the moment focus arrived, rebuild the ElevatedButton from scratch
  /// and destroy the focus node that had just been focused (the pattern and
  /// its history are in `server_template_selector.dart`).
  BoxDecoration _stateRing(AppPalette palette, ColorScheme colors) {
    final primary = widget.variant == YoButtonVariant.primary;
    final (Color color, double width) = _focused
        ? (
            switch (widget.variant) {
              YoButtonVariant.primary => colors.onPrimary,
              YoButtonVariant.danger => colors.onError,
              YoButtonVariant.secondary ||
              YoButtonVariant.ghost => palette.focus,
            },
            2,
          )
        : _hovered && _isInteractive && !primary
        ? (palette.interactiveForeground, 1.5)
        : (Colors.transparent, 2);
    return BoxDecoration(
      borderRadius: AppRadius.lg,
      border: Border.all(color: color, width: width),
    );
  }

  Color _backgroundColor(AppPalette palette, ColorScheme colors) {
    if (_isDisabled) {
      // R5: a disabled primary action is a flat sunken fill; the other
      // variants keep their quiet muted fill and 1 px edge.
      return widget.variant == YoButtonVariant.primary
          ? palette.surfaceSunken
          : palette.surfaceMuted;
    }
    switch (widget.variant) {
      case YoButtonVariant.primary:
        return Colors.transparent;
      case YoButtonVariant.secondary:
        return palette.surfaceRaised;
      case YoButtonVariant.ghost:
        return Colors.transparent;
      case YoButtonVariant.danger:
        return colors.error;
    }
  }

  Color _foregroundColor(AppPalette palette, ColorScheme colors) {
    if (_isDisabled) return palette.textTertiary;
    switch (widget.variant) {
      case YoButtonVariant.primary:
        return colors.onPrimary;
      case YoButtonVariant.danger:
        return colors.onError;
      case YoButtonVariant.secondary:
        return palette.textPrimary;
      case YoButtonVariant.ghost:
        return palette.interactiveForeground;
    }
  }

  Border? _border(AppPalette palette) {
    switch (widget.variant) {
      case YoButtonVariant.primary:
        // No outline in any state: enabled and loading paint the gradient,
        // disabled the sunken fill (R5).
        return null;
      case YoButtonVariant.danger:
        return _isDisabled ? Border.all(color: palette.border) : null;
      case YoButtonVariant.secondary:
        return Border.all(
          color: _isDisabled ? palette.border : palette.borderStrong,
        );
      case YoButtonVariant.ghost:
        return Border.all(
          color: _isDisabled ? palette.border : palette.interactiveForeground,
        );
    }
  }
}

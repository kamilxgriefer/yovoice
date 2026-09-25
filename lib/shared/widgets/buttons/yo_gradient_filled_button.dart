import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// How much a labelled action asks for on its screen (refine-look R5 / R7
/// and the light budget in `AppFinish`).
enum YoActionEmphasis {
  /// The screen's one CTA: the gradient and its coloured lift.
  lifted,

  /// The gradient without the lift, while another action on the same screen
  /// owns it (on desktop, the rail's "Stwórz serwer").
  flat,

  /// The R7 neutral tonal finish — glass fill, control hairline,
  /// `interactiveForeground` label — while another violet fill already owns
  /// the screen (Start's empty-servers invitation).
  neutral,
}

/// The screen's one labelled primary action (refine-look R5).
///
/// It IS a [FilledButton] — keys, `find.byType(FilledButton)`, focus
/// traversal, the semantics node and every existing focus-ring test keep
/// holding — with two additions:
///
/// * the fill is [gradient] (default [AppGradients.primaryAction]: the
///   theme's primary into its AA-safe secondary, the same pair the desktop
///   rail CTA already paints), laid on the button's `Material` through
///   `backgroundBuilder` + `Ink` so the pressed / hover washes still paint
///   over it;
/// * a tight coloured lift ([AppFinish.actionLift], the rail's exact values)
///   on an OUTER box, so the button's own clip never cuts it. The lift is
///   paint only: it changes no measured gap.
///
/// [emphasis] demotes the action without changing the widget: `flat` drops
/// the lift, `neutral` paints the R7 neutral tonal finish instead of the
/// gradient. The [FilledButton] element (and with it keyboard focus) stays
/// the same when a screen promotes or demotes the action under the reader.
///
/// States: hover white @ .06 and a stronger lift; pressed white @ .10 with the
/// lift sunk; focus the existing 2 px `onPrimary` edge; disabled
/// `surfaceSunken` with `textTertiary` and no lift. [busy] keeps the
/// gradient, halves the lift and shows an 18 px white spinner beside the
/// label; the button stays enabled and focusable (a disabled one would drop
/// keyboard focus and be announced as dimmed) but ignores presses, and its
/// semantics value says it is loading. Under high contrast the lift is
/// dropped.
///
/// Never set this through `filledButtonTheme` (84 call sites recolour
/// `FilledButton`s) and never use it for repeated, list, retry or tonal
/// actions: one per screen.
class YoGradientFilledButton extends StatefulWidget {
  const YoGradientFilledButton({
    required this.onPressed,
    required this.child,
    this.icon,
    this.style,
    this.shape = const StadiumBorder(),
    this.minimumSize = const Size(64, 44),
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.gradient,
    this.liftColor,
    this.emphasis = YoActionEmphasis.lifted,
    this.busy = false,
    this.focusNode,
    this.autofocus = false,
    this.statesController,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;

  /// Optional leading glyph (white, 20 px).
  final Widget? icon;

  /// Extra style for the fields this primitive leaves unset (a caller's
  /// text style or visual density). Colours, shape, padding and size always
  /// come from this widget.
  final ButtonStyle? style;
  final OutlinedBorder shape;
  final Size minimumSize;
  final EdgeInsetsGeometry padding;

  /// Defaults to [AppGradients.primaryAction] of the theme's scheme.
  final Gradient? gradient;

  /// Defaults to [AppColors.primary] (the rail's lift colour).
  final Color? liftColor;

  /// Whether this action is the screen's one lifted CTA, a flat gradient
  /// (another action owns the lift) or a neutral tonal action (another
  /// violet fill owns the screen).
  final YoActionEmphasis emphasis;

  final bool busy;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Passed through to the [FilledButton]; the lift follows its states.
  final WidgetStatesController? statesController;

  @override
  State<YoGradientFilledButton> createState() => _YoGradientFilledButtonState();
}

class _YoGradientFilledButtonState extends State<YoGradientFilledButton> {
  WidgetStatesController? _ownController;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownController ??= WidgetStatesController());

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
  }

  @override
  void didUpdateWidget(YoGradientFilledButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statesController != widget.statesController) {
      (oldWidget.statesController ?? _ownController)?.removeListener(
        _statesChanged,
      );
      _states.addListener(_statesChanged);
    }
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownController?.dispose();
    super.dispose();
  }

  bool _hovered = false;
  bool _pressed = false;

  // Only hover and press move the lift. Focus and disabled are reported by
  // the button itself (sometimes while it is being built), and they change
  // nothing this widget paints, so they never trigger a rebuild here.
  void _statesChanged() {
    if (!mounted) return;
    final states = _states.value;
    final hovered = states.contains(WidgetState.hovered);
    final pressed = states.contains(WidgetState.pressed);
    if (hovered == _hovered && pressed == _pressed) return;
    setState(() {
      _hovered = hovered;
      _pressed = pressed;
    });
  }

  /// A busy action keeps focus and its semantics but does nothing on press.
  static void _ignorePress() {}

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final enabled = widget.onPressed != null;
    final busy = enabled && widget.busy;
    final interactive = enabled && !busy;
    final neutral = widget.emphasis == YoActionEmphasis.neutral;
    final gradient = widget.gradient ?? AppGradients.primaryAction(scheme);
    final states = _states.value;
    final hovered = interactive && states.contains(WidgetState.hovered);
    final pressed = interactive && states.contains(WidgetState.pressed);
    _hovered = states.contains(WidgetState.hovered);
    _pressed = states.contains(WidgetState.pressed);

    final lift =
        !enabled || highContrast || widget.emphasis != YoActionEmphasis.lifted
        ? const <BoxShadow>[]
        : AppFinish.actionLift(
            widget.liftColor ?? AppColors.primary,
            hovered: hovered,
            pressed: pressed,
            strength: busy ? .5 : 1,
          );

    Color foreground(Set<WidgetState> s) =>
        enabled ? scheme.onPrimary : palette.textTertiary;

    // Geometry is the same in every emphasis, so demoting the action never
    // moves a neighbour.
    final geometry = ButtonStyle(
      shape: WidgetStatePropertyAll(widget.shape),
      minimumSize: WidgetStatePropertyAll(widget.minimumSize),
      padding: WidgetStatePropertyAll(widget.padding),
      // The visual is at least 44 px, so the tap target is the visual and
      // the outer lift box hugs the painted shape exactly.
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    );

    ButtonStyle neutralStyle() {
      final tonal = AppFinish.tonalNeutral(
        palette,
        shape: widget.shape,
        highContrast: highContrast,
      );
      // The button's Material cross-fades its label style between builds,
      // and a style that inherits cannot be interpolated into the
      // FilledButton default (the theme's `labelLarge`, which does not).
      // The tonal label is therefore laid over that same theme style, so a
      // screen can switch the emphasis under the reader.
      final label = Theme.of(
        context,
      ).textTheme.labelLarge?.merge(tonal.textStyle?.resolve(const {}));
      return tonal
          .copyWith(
            textStyle: label == null ? null : WidgetStatePropertyAll(label),
          )
          .merge(geometry);
    }

    var style = neutral
        ? neutralStyle()
        : ButtonStyle(
            // The gradient is laid by backgroundBuilder; a disabled action
            // is a flat sunken fill. A busy action keeps its gradient.
            backgroundColor: WidgetStatePropertyAll(
              enabled ? Colors.transparent : palette.surfaceSunken,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(foreground),
            iconColor: WidgetStateProperty.resolveWith(foreground),
            overlayColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.pressed)) {
                return AppColors.white.withValues(alpha: .10);
              }
              if (s.contains(WidgetState.hovered)) {
                return AppColors.white.withValues(alpha: .06);
              }
              return null;
            }),
            side: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? BorderSide(color: scheme.onPrimary, width: 2)
                  : BorderSide.none,
            ),
            backgroundBuilder: enabled
                ? (context, states, child) => Ink(
                    // Keep `color` null behind the gradient (see
                    // yo_button.dart).
                    decoration: BoxDecoration(gradient: gradient),
                    child: child,
                  )
                : null,
          ).merge(geometry);
    if (busy) {
      // Enabled for focus and semantics, but a press shows nothing and does
      // nothing while the work runs.
      style = style.copyWith(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
      );
    }

    final label = busy
        ? Semantics(
            // Merges into the button's own node: "Stwórz serwer, Ładowanie".
            value: AppLocalizations.of(context).text('Loading', 'Ładowanie'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: neutral
                        ? palette.interactiveForeground
                        : scheme.onPrimary,
                    // No theme track (surfaceSunken) under the spinner.
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(child: widget.child),
              ],
            ),
          )
        : widget.icon == null
        ? widget.child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: const IconThemeData(size: 20),
                child: widget.icon!,
              ),
              const SizedBox(width: 8),
              Flexible(child: widget.child),
            ],
          );

    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.quick),
      curve: AppMotion.standardCurve,
      decoration: ShapeDecoration(shape: widget.shape, shadows: lift),
      child: FilledButton(
        // FilledButton defaults to Clip.none, which lets the gradient `Ink`
        // paint as a rectangle past a stadium or rounded shape.
        clipBehavior: Clip.antiAlias,
        onPressed: !enabled
            ? null
            : busy
            ? _ignorePress
            : widget.onPressed,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        statesController: _states,
        style: widget.style == null ? style : style.merge(widget.style),
        child: label,
      ),
    );
  }
}

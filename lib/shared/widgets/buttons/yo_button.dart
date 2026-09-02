import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

enum YoButtonVariant { primary, secondary, ghost, danger }

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

  @override
  State<YoButton> createState() => _YoButtonState();
}

class _YoButtonState extends State<YoButton> {
  bool _focused = false;
  bool _hovered = false;

  bool get _isInteractive => widget.onPressed != null && !widget.isLoading;
  bool get _isDisabled => widget.onPressed == null;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final foreground = _foregroundColor(palette, colors);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final controlHeight = widget.height < AppSizing.minimumTouchTarget
        ? AppSizing.minimumTouchTarget
        : widget.height;
    final quickDuration = AppMotion.resolve(context, AppMotion.quick);
    final standardDuration = AppMotion.resolve(context, AppMotion.standard);

    Widget button = ConstrainedBox(
      constraints: BoxConstraints(minHeight: controlHeight),
      child: AnimatedContainer(
        duration: quickDuration,
        curve: Curves.easeOut,
        decoration: _decoration(palette, colors),
        child: ElevatedButton(
          onPressed: _isInteractive ? widget.onPressed : null,
          onHover: (value) {
            if (_hovered != value) setState(() => _hovered = value);
          },
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          style: ButtonStyle(
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            foregroundColor: WidgetStatePropertyAll(foreground),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return foreground.withValues(alpha: .16);
              }
              if (states.contains(WidgetState.hovered)) {
                return foreground.withValues(alpha: .08);
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
            child: widget.isLoading
                ? SizedBox(
                    key: const ValueKey<String>('loading'),
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                    ),
                  )
                : Row(
                    key: const ValueKey<String>('content'),
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (widget.icon != null) ...<Widget>[
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
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
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

  BoxDecoration _decoration(AppPalette palette, ColorScheme colors) {
    final baseBorder = _border(palette);
    final focusedBorderColor = switch (widget.variant) {
      YoButtonVariant.primary => colors.onPrimary,
      YoButtonVariant.danger => colors.onError,
      YoButtonVariant.secondary || YoButtonVariant.ghost => palette.focus,
    };
    final border = _focused
        ? Border.all(color: focusedBorderColor, width: 2)
        : _hovered && _isInteractive
        ? Border.all(color: palette.interactiveForeground, width: 1.5)
        : baseBorder;

    final usesPrimaryGradient =
        widget.variant == YoButtonVariant.primary && !_isDisabled;

    return BoxDecoration(
      gradient: usesPrimaryGradient
          ? LinearGradient(colors: [colors.primary, colors.secondary])
          : null,
      // Keep color null behind an enabled gradient. A transparent paint is
      // not equivalent here: it can suppress the shader on Flutter's raster
      // path and leave only the translucent shadow visible in Pearl.
      color: usesPrimaryGradient ? null : _backgroundColor(palette, colors),
      borderRadius: AppRadius.lg,
      border: border,
      boxShadow: widget.variant == YoButtonVariant.primary && _isInteractive
          ? <BoxShadow>[
              BoxShadow(
                color: colors.primary.withValues(alpha: _hovered ? .32 : .24),
                blurRadius: _hovered ? 22 : 18,
                offset: const Offset(0, 8),
              ),
            ]
          : const <BoxShadow>[],
    );
  }

  Color _backgroundColor(AppPalette palette, ColorScheme colors) {
    if (_isDisabled) return palette.surfaceMuted;
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
    if (_isDisabled) return Border.all(color: palette.border);
    switch (widget.variant) {
      case YoButtonVariant.primary:
      case YoButtonVariant.danger:
        return null;
      case YoButtonVariant.secondary:
        return Border.all(color: palette.borderStrong);
      case YoButtonVariant.ghost:
        return Border.all(color: palette.interactiveForeground);
    }
  }
}

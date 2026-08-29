import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

enum YoButtonVariant { primary, secondary, ghost, danger }

class YoButton extends StatelessWidget {
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
  final double height;

  bool get _isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final background = _backgroundColor(palette, colors);
    final foreground = _foregroundColor(palette, colors);
    final Widget button = SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: variant == YoButtonVariant.primary
              ? LinearGradient(colors: [colors.primary, colors.secondary])
              : null,
          color: background,
          borderRadius: AppRadius.lg,
          border: _border(palette, colors),
          boxShadow: variant == YoButtonVariant.primary && _isEnabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: _isEnabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shadowColor: AppColors.transparent,
            backgroundColor: AppColors.transparent,
            disabledBackgroundColor: AppColors.transparent,
            foregroundColor: foreground,
            disabledForegroundColor: palette.textTertiary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isLoading
                ? SizedBox(
                    key: ValueKey<String>('loading'),
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
                      if (icon != null) ...<Widget>[
                        IconTheme(
                          data: IconThemeData(color: foreground, size: 22),
                          child: icon!,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
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

    if (!fullWidth) {
      return button;
    }

    return SizedBox(width: double.infinity, child: button);
  }

  Color? _backgroundColor(AppPalette palette, ColorScheme colors) {
    switch (variant) {
      case YoButtonVariant.primary:
        return null;
      case YoButtonVariant.secondary:
        return palette.surfaceMuted;
      case YoButtonVariant.ghost:
        return AppColors.transparent;
      case YoButtonVariant.danger:
        return colors.error;
    }
  }

  Color _foregroundColor(AppPalette palette, ColorScheme colors) {
    switch (variant) {
      case YoButtonVariant.primary:
        return AppColors.white;
      case YoButtonVariant.danger:
        return colors.onError;
      case YoButtonVariant.secondary:
        return palette.textPrimary;
      case YoButtonVariant.ghost:
        return colors.primary;
    }
  }

  Border? _border(AppPalette palette, ColorScheme colors) {
    switch (variant) {
      case YoButtonVariant.primary:
      case YoButtonVariant.danger:
        return null;
      case YoButtonVariant.secondary:
        return Border.all(color: palette.borderStrong, width: 1);
      case YoButtonVariant.ghost:
        return Border.all(
          color: colors.primary.withValues(alpha: 0.72),
          width: 1,
        );
    }
  }
}

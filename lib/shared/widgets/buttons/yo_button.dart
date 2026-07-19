import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
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
    final Widget button = SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: variant == YoButtonVariant.primary
              ? AppGradients.primary
              : null,
          color: _backgroundColor,
          borderRadius: AppRadius.lg,
          border: _border,
          boxShadow: variant == YoButtonVariant.primary && _isEnabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
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
            foregroundColor: _foregroundColor,
            disabledForegroundColor: AppColors.textHint,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isLoading
                ? const SizedBox(
                    key: ValueKey<String>('loading'),
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.white,
                    ),
                  )
                : Row(
                    key: const ValueKey<String>('content'),
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        IconTheme(
                          data: IconThemeData(
                            color: _foregroundColor,
                            size: 22,
                          ),
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
                            color: _foregroundColor,
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

  Color? get _backgroundColor {
    switch (variant) {
      case YoButtonVariant.primary:
        return null;
      case YoButtonVariant.secondary:
        return AppColors.surfaceLight;
      case YoButtonVariant.ghost:
        return AppColors.transparent;
      case YoButtonVariant.danger:
        return AppColors.error;
    }
  }

  Color get _foregroundColor {
    switch (variant) {
      case YoButtonVariant.primary:
      case YoButtonVariant.danger:
        return AppColors.white;
      case YoButtonVariant.secondary:
        return AppColors.textPrimary;
      case YoButtonVariant.ghost:
        return AppColors.primary;
    }
  }

  Border? get _border {
    switch (variant) {
      case YoButtonVariant.primary:
      case YoButtonVariant.danger:
        return null;
      case YoButtonVariant.secondary:
        return Border.all(color: AppColors.border, width: 1);
      case YoButtonVariant.ghost:
        return Border.all(
          color: AppColors.primary.withValues(alpha: 0.55),
          width: 1,
        );
    }
  }
}

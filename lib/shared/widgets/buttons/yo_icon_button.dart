import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_radius.dart';

class YoIconButton extends StatelessWidget {
  const YoIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
    this.iconSize = 22,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.isLoading = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool isLoading;

  bool get _enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Tooltip(
        message: tooltip ?? '',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surface,
            borderRadius: AppRadius.md,
            border: Border.all(color: borderColor ?? AppColors.border),
          ),
          child: IconButton(
            onPressed: _enabled ? onPressed : null,
            splashRadius: size / 2,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isLoading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: iconSize,
                      height: iconSize,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      icon,
                      key: const ValueKey('icon'),
                      size: iconSize,
                      color: foregroundColor ?? AppColors.textPrimary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

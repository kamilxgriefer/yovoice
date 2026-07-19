import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_radius.dart';

class YoIconButton extends StatelessWidget {
  const YoIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 46,
    this.iconSize = 22,
    this.backgroundColor,
    this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.surface,
          foregroundColor: foregroundColor ?? AppColors.textPrimary,
          disabledBackgroundColor: (backgroundColor ?? AppColors.surface)
              .withValues(alpha: 0.55),
          disabledForegroundColor: AppColors.textHint,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.md,
            side: BorderSide(color: AppColors.border),
          ),
        ),
        icon: Icon(icon, size: iconSize),
      ),
    );
  }
}

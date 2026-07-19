import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

class YoSocialButton extends StatelessWidget {
  const YoSocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.svgIconPath,
    this.icon,
    this.iconSize = 24,
    this.isLoading = false,
    this.enabled = true,
  }) : assert(
         svgIconPath != null || icon != null,
         'Provide svgIconPath or icon.',
       );

  final String label;
  final VoidCallback? onPressed;
  final String? svgIconPath;
  final IconData? icon;
  final double iconSize;
  final bool isLoading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool canPress = enabled && !isLoading && onPressed != null;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: canPress ? 1 : 0.6,
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: OutlinedButton(
          onPressed: canPress ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            backgroundColor: AppColors.surface,
            disabledForegroundColor: AppColors.textHint,
            disabledBackgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border, width: 1),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 23,
                  height: 23,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.textPrimary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: Center(
                        child: svgIconPath != null
                            ? SvgPicture.asset(
                                svgIconPath!,
                                width: iconSize,
                                height: iconSize,
                              )
                            : Icon(
                                icon,
                                size: iconSize,
                                color: AppColors.textPrimary,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

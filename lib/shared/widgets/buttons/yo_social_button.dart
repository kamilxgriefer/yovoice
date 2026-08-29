import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

class YoSocialButton extends StatelessWidget {
  const YoSocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.svgIconPath,
    this.icon,
    this.iconSize = 28,
    this.isLoading = false,
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

  bool get _enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: _enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          elevation: 0,
          backgroundColor: palette.surfaceRaised,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: palette.textPrimary,
          disabledForegroundColor: palette.textTertiary,
          side: BorderSide(color: palette.borderStrong, width: 1),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isLoading
              ? SizedBox(
                  key: ValueKey('loading'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: palette.textPrimary,
                  ),
                )
              : Row(
                  key: const ValueKey('content'),
                  children: [
                    SizedBox(
                      width: 42,
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
                                color: palette.textPrimary,
                              ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppTypography.titleMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 42),
                  ],
                ),
        ),
      ),
    );
  }
}

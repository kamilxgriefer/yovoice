import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';

class YoGlassCard extends StatelessWidget {
  const YoGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final Widget content = ClipRRect(
      borderRadius: AppRadius.lg,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.84),
            borderRadius: AppRadius.lg,
            border: Border.all(color: palette.border.withValues(alpha: 0.88)),
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(onTap: onTap, borderRadius: AppRadius.lg, child: content);
  }
}

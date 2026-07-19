import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

enum YoBadgeVariant { primary, success, warning, error, info, live }

class YoBadge extends StatelessWidget {
  const YoBadge({
    super.key,
    required this.label,
    this.variant = YoBadgeVariant.primary,
    this.icon,
  });

  final String label;
  final YoBadgeVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color color = _color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(label, style: AppTypography.labelMedium.copyWith(color: color)),
        ],
      ),
    );
  }

  Color get _color {
    switch (variant) {
      case YoBadgeVariant.primary:
        return AppColors.primary;
      case YoBadgeVariant.success:
        return AppColors.success;
      case YoBadgeVariant.warning:
        return AppColors.warning;
      case YoBadgeVariant.error:
        return AppColors.error;
      case YoBadgeVariant.info:
        return AppColors.info;
      case YoBadgeVariant.live:
        return AppColors.live;
    }
  }
}

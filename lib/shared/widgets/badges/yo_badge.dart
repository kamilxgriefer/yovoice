import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
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
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final (:surface, :foreground) = _colors(palette, colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.pill,
        border: Border.all(color: foreground),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }

  ({Color surface, Color foreground}) _colors(
    AppPalette palette,
    ColorScheme colors,
  ) {
    switch (variant) {
      case YoBadgeVariant.primary:
        return (
          surface: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        );
      case YoBadgeVariant.success:
        return (
          surface: palette.successSurface,
          foreground: palette.successForeground,
        );
      case YoBadgeVariant.warning:
        return (
          surface: palette.warningSurface,
          foreground: palette.warningForeground,
        );
      case YoBadgeVariant.error:
        return (
          surface: palette.dangerSurface,
          foreground: palette.dangerForeground,
        );
      case YoBadgeVariant.info:
        return (
          surface: palette.infoSurface,
          foreground: palette.infoForeground,
        );
      case YoBadgeVariant.live:
        return (
          surface: palette.dangerSurface,
          foreground: palette.dangerForeground,
        );
    }
  }
}

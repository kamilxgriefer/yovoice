import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// The "✦ YO VOICE PREMIUM" eyebrow pill that opens every Premium
/// surface (presentation, plans). One widget so the glow treatment and
/// letter-spacing stay identical everywhere it appears.
class PremiumBadgePill extends StatelessWidget {
  const PremiumBadgePill({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('premium-badge-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.primaryContainer,
        border: Border.all(color: colors.primary.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(
            color: context.appPalette.shadow.withValues(alpha: .14),
            blurRadius: 18,
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 4,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 12,
            color: colors.onPrimaryContainer,
          ),
          Text(
            'YO VOICE PREMIUM',
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

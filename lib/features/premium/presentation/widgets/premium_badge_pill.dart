import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

/// The "✦ YO VOICE PREMIUM" eyebrow pill that opens every Premium
/// surface (presentation, plans). One widget so the glow treatment and
/// letter-spacing stay identical everywhere it appears.
class PremiumBadgePill extends StatelessWidget {
  const PremiumBadgePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.secondary.withValues(alpha: .10),
        border: Border.all(color: AppColors.secondary.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: .22),
            blurRadius: 18,
          ),
        ],
      ),
      child: const Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 4,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFFE9B8FF)),
          Text(
            'YO VOICE PREMIUM',
            style: TextStyle(
              color: Color(0xFFE9B8FF),
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

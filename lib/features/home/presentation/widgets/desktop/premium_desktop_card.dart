import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';

/// The desktop right column's Premium card: the three benefit tiles from
/// the Premium presentation, then one full-width gradient "Check plans"
/// CTA into the real plans flow.
///
/// Copy comes from [PremiumPlans.benefits] — the same single source the
/// mobile presentation and the marketing site read, so the three
/// surfaces cannot drift.
class PremiumDesktopCard extends StatelessWidget {
  const PremiumDesktopCard({required this.onCheckPlans, super.key});

  final VoidCallback onCheckPlans;

  static const _icons = [
    Icons.mic_rounded,
    Icons.workspace_premium_rounded,
    Icons.auto_awesome_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColors = <Color>[
      colors.primary,
      isDark ? const Color(0xFFFFC24D) : const Color(0xFF8C5A00),
      palette.focus,
    ];
    return Container(
      key: const ValueKey('desktop-premium-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: palette.surface,
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .08),
            blurRadius: 28,
          ),
        ],
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < PremiumPlans.benefits.length; i++) ...[
                  if (i > 0) const SizedBox(width: 9),
                  Expanded(
                    child: _BenefitTile(
                      icon: _icons[i],
                      iconColor: iconColors[i],
                      title: PremiumPlans.benefits[i].$1,
                      subtitle: PremiumPlans.benefits[i].$2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _CheckPlansButton(onTap: onCheckPlans),
        ],
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: palette.surfaceMuted,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          // The reference's glow sits behind the icon, not on the tile.
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: iconColor.withValues(alpha: .28),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 11.5,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckPlansButton extends StatelessWidget {
  const _CheckPlansButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: .35),
              blurRadius: 22,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Check plans',
                    style: TextStyle(
                      color: colors.onPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: colors.onPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

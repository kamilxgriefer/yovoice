import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/premium/presentation/premium_benefit_icons.dart';
import 'package:yovoice/features/premium/presentation/premium_localized_copy.dart';

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

  /// Below this, a tile's longest title word no longer fits its line.
  static const double _minimumTileWidth = 120;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    // Glyph and tint are keyed on the benefit's title, never its position.
    Color tint(String title) => switch (premiumBenefitKind(title)) {
      PremiumBenefitKind.creator => colors.primary,
      PremiumBenefitKind.servers => palette.warningForeground,
      PremiumBenefitKind.presence => palette.focus,
      PremiumBenefitKind.other => colors.primary,
    };
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
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth =
                  (constraints.maxWidth - 9 * 2) / PremiumPlans.benefits.length;
              // Three side-by-side tiles only while each is wide enough for
              // its longest word at the tile's type size; narrower (the
              // 318 px desktop Home column) they broke "prywatność"
              // mid-word and grew twelve lines tall, so the card lists the
              // benefits as rows instead, as the mobile card does.
              if (tileWidth < _minimumTileWidth) {
                return Column(
                  key: const ValueKey('desktop-premium-benefit-list'),
                  children: [
                    for (final (i, benefit)
                        in PremiumPlans.benefits.indexed) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _BenefitRow(
                        icon: premiumBenefitIcon(benefit.$1),
                        iconColor: tint(benefit.$1),
                        title: localizedPremiumBenefit(copy, benefit).$1,
                        subtitle: localizedPremiumBenefit(copy, benefit).$2,
                      ),
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, benefit)
                        in PremiumPlans.benefits.indexed) ...[
                      if (i > 0) const SizedBox(width: 9),
                      Expanded(
                        child: _BenefitTile(
                          icon: premiumBenefitIcon(benefit.$1),
                          iconColor: tint(benefit.$1),
                          title: localizedPremiumBenefit(copy, benefit).$1,
                          subtitle: localizedPremiumBenefit(copy, benefit).$2,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _CheckPlansButton(onTap: onCheckPlans),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
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
    final copy = AppLocalizations.of(context);
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
                    copy.text('Check plans', 'Sprawdź plany'),
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

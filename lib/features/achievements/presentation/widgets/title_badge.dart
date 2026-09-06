import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';

import '../../data/models/achievement_definition.dart';
import '../achievement_localized_copy.dart';
import '../achievement_style.dart';

class TitleBadge extends StatelessWidget {
  const TitleBadge({
    required this.achievement,
    this.compact = false,
    super.key,
  });

  final AchievementDefinition achievement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = AchievementRarityPalette.forRarity(achievement.rarity);
    final highRarity = achievement.rarity.index >= AchievementRarity.epic.index;

    return Container(
      // Compact achievement titles participate in the same identity rail as
      // account and Premium chips. Keeping the exact 24px compact contract
      // prevents a selected title from turning into a visibly larger block.
      constraints: BoxConstraints(minHeight: compact ? 24 : 34),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 13,
        vertical: compact ? 2 : 7,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.badgeGradient,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.badgeBorder.withValues(alpha: .88)),
        boxShadow: highRarity
            ? [
                BoxShadow(
                  color: palette.glow.withValues(alpha: .26),
                  blurRadius: achievement.rarity == AchievementRarity.mythic
                      ? 18
                      : 12,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (highRarity) ...[
            Icon(
              achievement.rarity == AchievementRarity.mythic
                  ? Icons.auto_awesome_rounded
                  : Icons.workspace_premium_rounded,
              color: palette.badgeForeground,
              size: compact ? 11 : 15,
            ),
            SizedBox(width: compact ? 3 : 6),
          ],
          Flexible(
            child: Text(
              localizedAchievementTitle(copy, achievement),
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.badgeForeground,
                fontSize: compact ? 9.5 : 13,
                height: 1.15,
                fontWeight: highRarity ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: highRarity ? .3 : .1,
                fontStyle: achievement.rarity == AchievementRarity.mythic
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';

import '../../data/models/achievement_definition.dart';
import '../achievement_localized_copy.dart';

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
    final palette = _BadgePalette.forRarity(achievement.rarity);
    final highRarity = achievement.rarity.index >= AchievementRarity.epic.index;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 30 : 34),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 13,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.gradient,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border.withValues(alpha: .88)),
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
              color: palette.foreground,
              size: compact ? 13 : 15,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              localizedAchievementTitle(copy, achievement),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.foreground,
                fontSize: compact ? 11.5 : 13,
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

class _BadgePalette {
  const _BadgePalette({
    required this.gradient,
    required this.border,
    required this.glow,
    required this.foreground,
  });

  final List<Color> gradient;
  final Color border;
  final Color glow;
  final Color foreground;

  static _BadgePalette forRarity(AchievementRarity rarity) {
    return switch (rarity) {
      AchievementRarity.common => const _BadgePalette(
        gradient: [Color(0xFF342A3B), Color(0xFF493A52)],
        border: Color(0xFF65566D),
        glow: Color(0xFF65566D),
        foreground: Color(0xFFF1EAF4),
      ),
      AchievementRarity.uncommon => const _BadgePalette(
        gradient: [Color(0xFF124531), Color(0xFF1B7555)],
        border: Color(0xFF49C894),
        glow: Color(0xFF49C894),
        foreground: Color(0xFFE7FFF5),
      ),
      AchievementRarity.rare => const _BadgePalette(
        gradient: [Color(0xFF15355F), Color(0xFF276FD0)],
        border: Color(0xFF5FAAFF),
        glow: Color(0xFF5FAAFF),
        foreground: Color(0xFFF0F7FF),
      ),
      AchievementRarity.epic => const _BadgePalette(
        gradient: [Color(0xFF4D1767), Color(0xFFA52BFF)],
        border: Color(0xFFD07CFF),
        glow: Color(0xFFC052FF),
        foreground: Color(0xFFFFF4FF),
      ),
      AchievementRarity.legendary => const _BadgePalette(
        gradient: [Color(0xFF7D3A0D), Color(0xFFFF9E24)],
        border: Color(0xFFFFC566),
        glow: Color(0xFFFFA52B),
        foreground: Color(0xFFFFF8E8),
      ),
      AchievementRarity.mythic => const _BadgePalette(
        gradient: [Color(0xFF7E1D76), Color(0xFF5A29C8), Color(0xFFC52DFF)],
        border: Color(0xFFFF77DF),
        glow: Color(0xFFD84CFF),
        foreground: Color(0xFFFFFFFF),
      ),
    };
  }
}

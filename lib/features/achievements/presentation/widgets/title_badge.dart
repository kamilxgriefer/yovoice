import 'package:flutter/material.dart';

import '../../data/models/achievement_definition.dart';

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
    final colors = _colors(achievement.rarity);
    final rare = achievement.rarity.index >= AchievementRarity.epic.index;

    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.last.withValues(alpha: .8)),
        boxShadow: rare
            ? [
                BoxShadow(
                  color: colors.last.withValues(alpha: .34),
                  blurRadius: achievement.rarity == AchievementRarity.mythic
                      ? 24
                      : 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Text(
        achievement.title,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 11 : 13,
          fontWeight: rare ? FontWeight.w900 : FontWeight.w700,
          letterSpacing: rare ? .7 : .15,
          fontStyle: achievement.rarity == AchievementRarity.mythic
              ? FontStyle.italic
              : FontStyle.normal,
        ),
      ),
    );

    if (achievement.rarity != AchievementRarity.mythic) return badge;

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Color(0xFFFFD76A),
          Color(0xFFFF72E1),
          Color(0xFF9A5CFF),
          Color(0xFF52D9FF),
        ],
      ).createShader(bounds),
      child: badge,
    );
  }

  List<Color> _colors(AchievementRarity rarity) {
    return switch (rarity) {
      AchievementRarity.common => const [Color(0xFF30283B), Color(0xFF45384F)],
      AchievementRarity.uncommon => const [
        Color(0xFF144A39),
        Color(0xFF1C7A59),
      ],
      AchievementRarity.rare => const [Color(0xFF173B6B), Color(0xFF276FD0)],
      AchievementRarity.epic => const [Color(0xFF4F176B), Color(0xFFA226FF)],
      AchievementRarity.legendary => const [
        Color(0xFF8B3F0C),
        Color(0xFFFF9D20),
      ],
      AchievementRarity.mythic => const [Color(0xFF5A145F), Color(0xFFC22DFF)],
    };
  }
}

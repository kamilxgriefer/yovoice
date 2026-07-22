enum AchievementRarity { common, uncommon, rare, epic, legendary, mythic }

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.metric,
    required this.threshold,
    required this.rarity,
  });

  final String id;
  final String title;
  final String description;
  final String metric;
  final int threshold;
  final AchievementRarity rarity;
}

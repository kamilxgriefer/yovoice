import 'models/achievement_definition.dart';

class AchievementCatalog {
  AchievementCatalog._();

  static const List<int> _thresholds = [
    1,
    10,
    50,
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10000,
  ];

  static const List<AchievementRarity> _rarities = [
    AchievementRarity.common,
    AchievementRarity.common,
    AchievementRarity.uncommon,
    AchievementRarity.uncommon,
    AchievementRarity.rare,
    AchievementRarity.rare,
    AchievementRarity.epic,
    AchievementRarity.epic,
    AchievementRarity.legendary,
    AchievementRarity.mythic,
  ];

  static List<AchievementDefinition> _track({
    required String metric,
    required String descriptionNoun,
    required List<String> titles,
    List<int>? thresholds,
  }) {
    final values = thresholds ?? _thresholds;

    return List.generate(
      10,
      (index) => AchievementDefinition(
        id: '${metric}_${values[index]}',
        title: titles[index],
        description: 'Reach ${values[index]} $descriptionNoun.',
        metric: metric,
        threshold: values[index],
        rarity: _rarities[index],
      ),
      growable: false,
    );
  }

  static final List<AchievementDefinition> all = [
    ..._track(
      metric: 'messages',
      descriptionNoun: 'written messages',
      titles: const [
        'First Word',
        'Icebreaker',
        'Conversation Starter',
        'Daily Talker',
        'Message Maker',
        'Social Spark',
        'Thousand Voices',
        'Chat Vanguard',
        'Chat Legend',
        'Voice of the Crowd',
      ],
    ),
    ..._track(
      metric: 'followers',
      descriptionNoun: 'followers',
      titles: const [
        'Noticed',
        'Small Circle',
        'Rising Voice',
        'Crowd Magnet',
        'Community Favourite',
        'Voice Influencer',
        'Public Figure',
        'Spotlight',
        'Network Star',
        'YoVoice Icon',
      ],
    ),
    ..._track(
      metric: 'voiceMinutes',
      descriptionNoun: 'voice minutes',
      thresholds: const [1, 30, 120, 300, 600, 1200, 3000, 6000, 12000, 30000],
      titles: const [
        'Mic Check',
        'First Conversation',
        'Open Mic',
        'Night Talker',
        'Voice Regular',
        'Airwave Rider',
        'Voice Veteran',
        'Sound Voyager',
        'Airwave Master',
        'Eternal Voice',
      ],
    ),
    ..._track(
      metric: 'rooms',
      descriptionNoun: 'created rooms',
      titles: const [
        'Room Opener',
        'Gatherer',
        'Room Founder',
        'Social Host',
        'Community Builder',
        'Room Curator',
        'Room Architect',
        'Network Founder',
        'Realm Builder',
        'Realm Founder',
      ],
    ),
    ..._track(
      metric: 'communities',
      descriptionNoun: 'joined communities',
      titles: const [
        'Newcomer',
        'Explorer',
        'Community Hopper',
        'Local',
        'Connector',
        'Networker',
        'Citizen of YoVoice',
        'World Listener',
        'Community Nomad',
        'Everywhere at Once',
      ],
    ),
    ..._track(
      metric: 'friends',
      descriptionNoun: 'friends',
      titles: const [
        'First Connection',
        'Friendly Face',
        'Social Circle',
        'Trusted Contact',
        'People Person',
        'Friend Collector',
        'Social Anchor',
        'Community Heart',
        'Universal Friend',
        'Everyone Knows You',
      ],
    ),
    ..._track(
      metric: 'reactions',
      descriptionNoun: 'received reactions',
      titles: const [
        'First Applause',
        'Well Received',
        'Crowd Pleaser',
        'Good Energy',
        'Reaction Magnet',
        'Fan Favourite',
        'Audience Choice',
        'Standing Ovation',
        'Beloved Voice',
        'Universal Applause',
      ],
    ),
    ..._track(
      metric: 'hostMinutes',
      descriptionNoun: 'hosted voice minutes',
      thresholds: const [1, 30, 120, 300, 600, 1200, 3000, 6000, 12000, 30000],
      titles: const [
        'First Host',
        'Room Guide',
        'Conversation Lead',
        'Voice Captain',
        'Voice Director',
        'Stage Keeper',
        'Broadcast Master',
        'Community Conductor',
        'Grand Host',
        'Grand Voicekeeper',
      ],
    ),
    ..._track(
      metric: 'activeDays',
      descriptionNoun: 'active days',
      thresholds: const [1, 3, 7, 14, 30, 60, 100, 180, 365, 730],
      titles: const [
        'Hello YoVoice',
        'Back Again',
        'Weekly Regular',
        'Two Week Flame',
        'Monthly Regular',
        'Dedicated Voice',
        'Century Streak',
        'Half Year Habit',
        'Year of Voice',
        'Timeless Member',
      ],
    ),
    ..._track(
      metric: 'moments',
      descriptionNoun: 'published Voice Moments',
      titles: const [
        'First Moment',
        'Story Teller',
        'Moment Maker',
        'Voice Journal',
        'Audio Creator',
        'Moment Curator',
        'Voice Publisher',
        'Moment Star',
        'Audio Celebrity',
        'Voice Moment Legend',
      ],
    ),
  ];

  static AchievementDefinition? byId(String? id) {
    if (id == null) return null;
    for (final achievement in all) {
      if (achievement.id == id) return achievement;
    }
    return null;
  }

  static List<AchievementDefinition> unlockedBy(Map<String, int> stats) {
    return all
        .where(
          (achievement) =>
              (stats[achievement.metric] ?? 0) >= achievement.threshold,
        )
        .toList(growable: false);
  }

  static AchievementDefinition? bestUnlocked(Map<String, int> stats) {
    final unlocked = unlockedBy(stats);
    if (unlocked.isEmpty) return null;

    unlocked.sort((first, second) {
      final rarityComparison = second.rarity.index.compareTo(
        first.rarity.index,
      );
      if (rarityComparison != 0) return rarityComparison;
      return second.threshold.compareTo(first.threshold);
    });

    return unlocked.first;
  }
}

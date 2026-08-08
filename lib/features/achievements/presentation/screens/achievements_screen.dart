import 'package:flutter/material.dart';

import '../../../profile/data/models/user_profile.dart';
import '../../../profile/data/services/profile_service.dart';
import '../../data/achievement_catalog.dart';
import '../../data/models/achievement_definition.dart';
import '../../data/services/achievement_service.dart';

/// Self-contained entry point for the Awards / achievements hub reached
/// from the More sheet — streams the current profile itself so callers
/// (like [MoreDestination.achievements]) don't need to thread one through.
class AwardsHubScreen extends StatelessWidget {
  const AwardsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: ProfileService().watchCurrentProfile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFF09050F),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF09050F),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFB348FF)),
            ),
          );
        }
        return AchievementsScreen(profile: profile);
      },
    );
  }
}

enum AchievementCategory { creator, community, voice, friends }

const Map<AchievementCategory, Set<String>> _categoryMetrics = {
  AchievementCategory.creator: {'rooms', 'hostMinutes', 'moments'},
  AchievementCategory.community: {'communities', 'messages', 'reactions'},
  AchievementCategory.voice: {'voiceMinutes', 'activeDays'},
  AchievementCategory.friends: {'friends', 'followers'},
};

String _categoryLabel(AchievementCategory category) => switch (category) {
  AchievementCategory.creator => 'Creator',
  AchievementCategory.community => 'Community',
  AchievementCategory.voice => 'Voice',
  AchievementCategory.friends => 'Friends',
};

IconData _categoryIcon(AchievementCategory category) => switch (category) {
  AchievementCategory.creator => Icons.auto_awesome_rounded,
  AchievementCategory.community => Icons.hub_rounded,
  AchievementCategory.voice => Icons.graphic_eq_rounded,
  AchievementCategory.friends => Icons.people_alt_rounded,
};

int _xpForRarity(AchievementRarity rarity) => switch (rarity) {
  AchievementRarity.common => 10,
  AchievementRarity.uncommon => 25,
  AchievementRarity.rare => 60,
  AchievementRarity.epic => 150,
  AchievementRarity.legendary => 400,
  AchievementRarity.mythic => 1000,
};

const int _xpPerLevel = 300;

/// Derived from real unlocked-achievement rarity — never a fabricated number.
class AwardsProgress {
  AwardsProgress(UserProfile profile)
    : unlocked = profile.unlockedTitleIds
          .map(AchievementCatalog.byId)
          .whereType<AchievementDefinition>()
          .toList(growable: false),
      totalXp = profile.unlockedTitleIds
          .map(AchievementCatalog.byId)
          .whereType<AchievementDefinition>()
          .fold<int>(0, (sum, item) => sum + _xpForRarity(item.rarity)),
      recentUnlocks =
          (profile.unlockedTitleTimestamps.entries
                  .map(
                    (entry) => (
                      achievement: AchievementCatalog.byId(entry.key),
                      unlockedAt: entry.value,
                    ),
                  )
                  .where((item) => item.achievement != null)
                  .toList()
                ..sort((a, b) => b.unlockedAt.compareTo(a.unlockedAt)))
              .map((item) => (item.achievement!, item.unlockedAt))
              .toList(growable: false);

  final List<AchievementDefinition> unlocked;
  final int totalXp;

  /// Only achievements with a real recorded unlock timestamp, newest first.
  /// Achievements unlocked before this tracking existed simply won't appear
  /// here — never backfilled with a guessed date.
  final List<(AchievementDefinition, DateTime)> recentUnlocks;

  int get level => 1 + (totalXp ~/ _xpPerLevel);
  int get xpIntoLevel => totalXp % _xpPerLevel;
  double get levelProgress => xpIntoLevel / _xpPerLevel;
  int get totalCount => AchievementCatalog.all.length;
  int get unlockedCount => unlocked.length;
  int get lockedCount => totalCount - unlockedCount;
  double get completionRatio =>
      totalCount == 0 ? 0 : unlockedCount / totalCount;

  int countForCategory(AchievementCategory category) {
    final metrics = _categoryMetrics[category] ?? const <String>{};
    return unlocked.where((item) => metrics.contains(item.metric)).length;
  }
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _service = AchievementService();
  bool _saving = false;
  AchievementCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final unlockedIds = widget.profile.unlockedTitleIds.toSet();
    final awardsProgress = AwardsProgress(widget.profile);
    final category = _selectedCategory;
    final visibleAchievements = category == null
        ? AchievementCatalog.all
        : AchievementCatalog.all
              .where(
                (item) => (_categoryMetrics[category] ?? const <String>{})
                    .contains(item.metric),
              )
              .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFF09050F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09050F),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${unlockedIds.length}/100 titles',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            const Text(
              'Your progress across YoVoice',
              style: TextStyle(
                color: Color(0xFFA79CAD),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _AwardsHeader(
                  progress: awardsProgress,
                  selectedCategory: _selectedCategory,
                  onSelectCategory: (value) =>
                      setState(() => _selectedCategory = value),
                  isWide: isWide,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 24 : 16,
                  4,
                  isWide ? 24 : 16,
                  40,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isWide ? 560 : 520,
                    mainAxisExtent: 250,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final achievement = visibleAchievements[index];
                    final isUnlocked = unlockedIds.contains(achievement.id);
                    final progress =
                        widget.profile.achievementStats[achievement.metric] ??
                        0;
                    final isSelected =
                        widget.profile.selectedTitleId == achievement.id;

                    return _AchievementCard(
                      achievement: achievement,
                      progress: progress,
                      unlocked: isUnlocked,
                      selected: isSelected,
                      saving: _saving,
                      onSelect: isUnlocked
                          ? () async {
                              final navigator = Navigator.of(context);

                              setState(() => _saving = true);
                              try {
                                await _service.selectTitle(achievement.id);

                                if (!mounted) return;
                                navigator.pop();
                              } finally {
                                if (mounted) {
                                  setState(() => _saving = false);
                                }
                              }
                            }
                          : null,
                    );
                  }, childCount: visibleAchievements.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AwardsHeader extends StatelessWidget {
  const _AwardsHeader({
    required this.progress,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.isWide,
  });

  final AwardsProgress progress;
  final AchievementCategory? selectedCategory;
  final ValueChanged<AchievementCategory?> onSelectCategory;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 10, isWide ? 24 : 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LevelCard(progress: progress),
          const SizedBox(height: 14),
          _StatsRow(progress: progress),
          const SizedBox(height: 18),
          const Text(
            'Categories',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: 'All',
                  icon: Icons.grid_view_rounded,
                  count: progress.unlockedCount,
                  selected: selectedCategory == null,
                  onTap: () => onSelectCategory(null),
                ),
                for (final category in AchievementCategory.values) ...[
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: _categoryLabel(category),
                    icon: _categoryIcon(category),
                    count: progress.countForCategory(category),
                    selected: selectedCategory == category,
                    onTap: () => onSelectCategory(category),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _RecentUnlocks(progress: progress),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.progress});
  final AwardsProgress progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1160), Color(0xFF190B29)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF4B2C63)),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFC466FF), Color(0xFF7A1BFF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB348FF).withValues(alpha: .4),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Text(
              '${progress.level}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Level ${progress.level}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress.levelProgress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF2C2033),
                    color: const Color(0xFFD28AFF),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${progress.xpIntoLevel} / $_xpPerLevel XP to level ${progress.level + 1}',
                  style: const TextStyle(
                    color: Color(0xFFC7BBD1),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.progress});
  final AwardsProgress progress;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _StatTile(
        icon: Icons.lock_open_rounded,
        value: '${progress.unlockedCount}',
        label: 'Unlocked',
        color: const Color(0xFF4DE09E),
      ),
      _StatTile(
        icon: Icons.lock_rounded,
        value: '${progress.lockedCount}',
        label: 'Locked',
        color: const Color(0xFF9F95A6),
      ),
      _StatTile(
        icon: Icons.donut_large_rounded,
        value: '${(progress.completionRatio * 100).round()}%',
        label: 'Complete',
        color: const Color(0xFFD28AFF),
      ),
      _StatTile(
        icon: Icons.bolt_rounded,
        value: '${progress.totalXp}',
        label: 'Total XP',
        color: const Color(0xFFFFA52B),
      ),
    ];

    return Row(
      children: [
        for (var index = 0; index < tiles.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: tiles[index]),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF150C1D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF382741)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFA99DB3), fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFB348FF) : const Color(0xFF17101F),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0xFF382741),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : const Color(0xFFB8ADBF),
              ),
              const SizedBox(width: 6),
              Text(
                '$label · $count',
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFC7BBD1),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentUnlocks extends StatelessWidget {
  const _RecentUnlocks({required this.progress});
  final AwardsProgress progress;

  @override
  Widget build(BuildContext context) {
    final dated = progress.recentUnlocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent unlocks',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (dated.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF150C1D),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF382741)),
            ),
            child: const Text(
              'No achievements unlocked yet. Chat, host rooms and connect with '
              'friends to earn your first title.',
              style: TextStyle(
                color: Color(0xFFA99DB3),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          )
        else
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dated.length > 8 ? 8 : dated.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final (achievement, unlockedAt) = dated[index];
                final palette = _RarityPalette.forRarity(achievement.rarity);
                return Container(
                  width: 150,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surfaceStart,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _iconForMetric(achievement.metric),
                        color: palette.accent,
                        size: 18,
                      ),
                      const Spacer(),
                      Text(
                        achievement.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        _relativeTime(unlockedAt),
                        style: TextStyle(color: palette.accent, fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.achievement,
    required this.progress,
    required this.unlocked,
    required this.selected,
    required this.saving,
    required this.onSelect,
  });

  final AchievementDefinition achievement;
  final int progress;
  final bool unlocked;
  final bool selected;
  final bool saving;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = _RarityPalette.forRarity(achievement.rarity);
    final safeThreshold = achievement.threshold <= 0
        ? 1
        : achievement.threshold;
    final ratio = (progress / safeThreshold).clamp(0.0, 1.0);
    final shownProgress = progress.clamp(0, achievement.threshold);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: palette.accent.withValues(alpha: .34),
              blurRadius: 26,
              spreadRadius: 1,
            )
          else if (unlocked &&
              achievement.rarity.index >= AchievementRarity.epic.index)
            BoxShadow(
              color: palette.accent.withValues(alpha: .13),
              blurRadius: 20,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: saving ? null : onSelect,
          borderRadius: BorderRadius.circular(26),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: unlocked
                    ? [palette.surfaceStart, palette.surfaceEnd]
                    : const [Color(0xFF17111E), Color(0xFF100B16)],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                width: selected ? 2 : 1,
                color: selected
                    ? palette.accent
                    : unlocked
                    ? palette.border
                    : const Color(0xFF3B2D44),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -40,
                  right: -34,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          palette.accent.withValues(
                            alpha: unlocked ? .14 : .06,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Opacity(
                    opacity: unlocked ? 1 : .62,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AchievementIcon(
                              icon: _iconForMetric(achievement.metric),
                              color: palette.accent,
                              unlocked: unlocked,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      achievement.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: unlocked
                                            ? palette.accent
                                            : const Color(0xFFC4BBC9),
                                        fontSize: 19,
                                        height: 1.08,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _RarityChip(
                                      label: palette.label,
                                      color: palette.accent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _StatusIcon(
                              unlocked: unlocked,
                              selected: selected,
                              color: palette.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          achievement.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unlocked
                                ? const Color(0xFFD4CBD9)
                                : const Color(0xFFAAA0B0),
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: ratio),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return _AnimatedProgressBar(
                              value: value,
                              color: palette.accent,
                              mythic:
                                  achievement.rarity ==
                                  AchievementRarity.mythic,
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$shownProgress',
                                      style: TextStyle(
                                        color: unlocked
                                            ? palette.accent
                                            : const Color(0xFFACA2B2),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' / ${achievement.threshold}',
                                      style: const TextStyle(
                                        color: Color(0xFF968B9D),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (selected)
                              const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              )
                            else if (unlocked)
                              Text(
                                'TAP TO USE',
                                style: TextStyle(
                                  color: palette.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .8,
                                ),
                              )
                            else
                              const Text(
                                'LOCKED',
                                style: TextStyle(
                                  color: Color(0xFF8E8397),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .8,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementIcon extends StatelessWidget {
  const _AchievementIcon({
    required this.icon,
    required this.color,
    required this.unlocked,
  });

  final IconData icon;
  final Color color;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: unlocked ? .22 : .10),
            const Color(0xFF100B16),
          ],
        ),
        border: Border.all(
          color: color.withValues(alpha: unlocked ? .75 : .25),
        ),
        boxShadow: unlocked
            ? [BoxShadow(color: color.withValues(alpha: .22), blurRadius: 18)]
            : null,
      ),
      child: Icon(
        icon,
        color: unlocked ? color : const Color(0xFF9F95A6),
        size: 30,
      ),
    );
  }
}

class _RarityChip extends StatelessWidget {
  const _RarityChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({
    required this.value,
    required this.color,
    required this.mythic,
  });

  final double value;
  final Color color;
  final bool mythic;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: const Color(0xFF241B2A),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: mythic
                      ? const [
                          Color(0xFFFF78DD),
                          Color(0xFFC345FF),
                          Color(0xFF775CFF),
                        ]
                      : [color.withValues(alpha: .78), color],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .40),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.unlocked,
    required this.selected,
    required this.color,
  });

  final bool unlocked;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .38), blurRadius: 14),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
      );
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF211927),
        border: Border.all(
          color: unlocked
              ? color.withValues(alpha: .30)
              : const Color(0xFF46384F),
        ),
      ),
      child: Icon(
        unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
        color: unlocked ? color : const Color(0xFF93889A),
        size: 20,
      ),
    );
  }
}

class _RarityPalette {
  const _RarityPalette({
    required this.label,
    required this.accent,
    required this.border,
    required this.surfaceStart,
    required this.surfaceEnd,
  });

  final String label;
  final Color accent;
  final Color border;
  final Color surfaceStart;
  final Color surfaceEnd;

  static _RarityPalette forRarity(AchievementRarity rarity) {
    return switch (rarity) {
      AchievementRarity.common => const _RarityPalette(
        label: 'Common',
        accent: Color(0xFFB8ADBF),
        border: Color(0xFF594A62),
        surfaceStart: Color(0xFF211827),
        surfaceEnd: Color(0xFF15101B),
      ),
      AchievementRarity.uncommon => const _RarityPalette(
        label: 'Uncommon',
        accent: Color(0xFF4DE09E),
        border: Color(0xFF267A5D),
        surfaceStart: Color(0xFF122A22),
        surfaceEnd: Color(0xFF0E1815),
      ),
      AchievementRarity.rare => const _RarityPalette(
        label: 'Rare',
        accent: Color(0xFF4B9DFF),
        border: Color(0xFF2B65A9),
        surfaceStart: Color(0xFF12253C),
        surfaceEnd: Color(0xFF0C1624),
      ),
      AchievementRarity.epic => const _RarityPalette(
        label: 'Epic',
        accent: Color(0xFFC466FF),
        border: Color(0xFF7B35A6),
        surfaceStart: Color(0xFF2B1538),
        surfaceEnd: Color(0xFF180D21),
      ),
      AchievementRarity.legendary => const _RarityPalette(
        label: 'Legendary',
        accent: Color(0xFFFFA52B),
        border: Color(0xFFB2651C),
        surfaceStart: Color(0xFF342010),
        surfaceEnd: Color(0xFF1A100A),
      ),
      AchievementRarity.mythic => const _RarityPalette(
        label: 'Mythic',
        accent: Color(0xFFFF6DDA),
        border: Color(0xFFB53AA8),
        surfaceStart: Color(0xFF341437),
        surfaceEnd: Color(0xFF160E22),
      ),
    };
  }
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  final months = diff.inDays ~/ 30;
  return '${months}mo ago';
}

IconData _iconForMetric(String metric) {
  switch (metric) {
    case 'messages':
      return Icons.chat_bubble_rounded;
    case 'followers':
      return Icons.groups_rounded;
    case 'voiceMinutes':
      return Icons.graphic_eq_rounded;
    case 'rooms':
      return Icons.meeting_room_rounded;
    case 'communities':
      return Icons.hub_rounded;
    case 'friends':
      return Icons.people_alt_rounded;
    case 'reactions':
      return Icons.auto_awesome_rounded;
    case 'hostMinutes':
      return Icons.podcasts_rounded;
    case 'activeDays':
      return Icons.local_fire_department_rounded;
    case 'moments':
      return Icons.mic_rounded;
    default:
      return Icons.workspace_premium_rounded;
  }
}

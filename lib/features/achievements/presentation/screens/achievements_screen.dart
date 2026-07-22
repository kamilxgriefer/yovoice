import 'package:flutter/material.dart';

import '../../../profile/data/models/user_profile.dart';
import '../../data/achievement_catalog.dart';
import '../../data/models/achievement_definition.dart';
import '../../data/services/achievement_service.dart';
import '../widgets/title_badge.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    required this.profile,
    super.key,
  });

  final UserProfile profile;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _service = AchievementService();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final unlocked = widget.profile.unlockedTitleIds.toSet();

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
              '${unlocked.length}/100 titles',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'Choose the title shown on your profile',
              style: TextStyle(
                color: Color(0xFF94889F),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 16 : 22,
              14,
              isCompact ? 16 : 22,
              40,
            ),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: isCompact ? 360 : 390,
              mainAxisExtent: isCompact ? 226 : 218,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: AchievementCatalog.all.length,
            itemBuilder: (context, index) {
              final achievement = AchievementCatalog.all[index];
              final isUnlocked = unlocked.contains(achievement.id);
              final progress =
                  widget.profile.achievementStats[achievement.metric] ?? 0;
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
            },
          );
        },
      ),
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
    final ratio = achievement.threshold <= 0
        ? 0.0
        : (progress / achievement.threshold).clamp(0.0, 1.0);
    final shownProgress = progress.clamp(0, achievement.threshold);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: .35),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ]
            : achievement.rarity.index >= AchievementRarity.legendary.index &&
                    unlocked
                ? [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: .13),
                      blurRadius: 18,
                    ),
                  ]
                : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: saving ? null : onSelect,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: unlocked
                    ? [
                        palette.surfaceStart,
                        palette.surfaceEnd,
                      ]
                    : const [
                        Color(0xFF17111E),
                        Color(0xFF110C17),
                      ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                width: selected ? 2 : 1,
                color: selected
                    ? palette.accent
                    : unlocked
                        ? palette.border.withValues(alpha: .8)
                        : const Color(0xFF3A2C43),
              ),
            ),
            child: Stack(
              children: [
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topRight,
                          radius: 1,
                          colors: [
                            palette.accent.withValues(alpha: .30),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(23),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Opacity(
                    opacity: unlocked ? 1 : .56,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TitleBadge(
                                achievement: achievement,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusIcon(
                              unlocked: unlocked,
                              selected: selected,
                              color: palette.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          palette.label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              achievement.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unlocked
                                    ? const Color(0xFFD1C7D8)
                                    : const Color(0xFFA297A9),
                                fontSize: 14,
                                height: 1.32,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          tween: Tween<double>(
                            begin: 0,
                            end: ratio,
                          ),
                          builder: (context, value, _) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 7,
                                backgroundColor:
                                    const Color(0xFF2A2130),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  unlocked
                                      ? palette.accent
                                      : palette.accent.withValues(alpha: .58),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$shownProgress / ${achievement.threshold}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFA99EB1),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (selected)
                              const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              )
                            else if (unlocked)
                              Text(
                                'TAP TO USE',
                                style: TextStyle(
                                  color: palette.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .8,
                                ),
                              )
                            else
                              const Text(
                                'LOCKED',
                                style: TextStyle(
                                  color: Color(0xFF8E8397),
                                  fontSize: 10,
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
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .38),
              blurRadius: 12,
            ),
          ],
        ),
        child: const Icon(
          Icons.check_rounded,
          color: Colors.white,
          size: 18,
        ),
      );
    }

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unlocked
            ? color.withValues(alpha: .15)
            : const Color(0xFF2A2230),
        border: Border.all(
          color: unlocked
              ? color.withValues(alpha: .35)
              : const Color(0xFF44374D),
        ),
      ),
      child: Icon(
        unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
        color: unlocked ? color : const Color(0xFF918698),
        size: 16,
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
          accent: Color(0xFFB9ADBF),
          border: Color(0xFF5A4A63),
          surfaceStart: Color(0xFF211827),
          surfaceEnd: Color(0xFF17111D),
        ),
      AchievementRarity.uncommon => const _RarityPalette(
          label: 'Uncommon',
          accent: Color(0xFF55E0A8),
          border: Color(0xFF267B5F),
          surfaceStart: Color(0xFF132A24),
          surfaceEnd: Color(0xFF111B18),
        ),
      AchievementRarity.rare => const _RarityPalette(
          label: 'Rare',
          accent: Color(0xFF5CA6FF),
          border: Color(0xFF2E67A8),
          surfaceStart: Color(0xFF14243A),
          surfaceEnd: Color(0xFF101925),
        ),
      AchievementRarity.epic => const _RarityPalette(
          label: 'Epic',
          accent: Color(0xFFC56BFF),
          border: Color(0xFF7D35A8),
          surfaceStart: Color(0xFF2B1538),
          surfaceEnd: Color(0xFF1B1024),
        ),
      AchievementRarity.legendary => const _RarityPalette(
          label: 'Legendary',
          accent: Color(0xFFFFB84D),
          border: Color(0xFFB2651C),
          surfaceStart: Color(0xFF382111),
          surfaceEnd: Color(0xFF21150D),
        ),
      AchievementRarity.mythic => const _RarityPalette(
          label: 'Mythic',
          accent: Color(0xFFFF67D7),
          border: Color(0xFF9E34C7),
          surfaceStart: Color(0xFF35153D),
          surfaceEnd: Color(0xFF17102A),
        ),
    };
  }
}

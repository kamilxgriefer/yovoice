import 'package:flutter/material.dart';

import '../../../profile/data/models/user_profile.dart';
import '../../data/achievement_catalog.dart';
import '../../data/models/achievement_definition.dart';
import '../../data/services/achievement_service.dart';
import '../widgets/title_badge.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({required this.profile, super.key});

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
        title: Text('${unlocked.length}/100 titles'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 330,
          mainAxisExtent: 150,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: AchievementCatalog.all.length,
        itemBuilder: (context, index) {
          final achievement = AchievementCatalog.all[index];
          final isUnlocked = unlocked.contains(achievement.id);
          final progress =
              widget.profile.achievementStats[achievement.metric] ?? 0;
          final selected = widget.profile.selectedTitleId == achievement.id;

          return _AchievementCard(
            achievement: achievement,
            progress: progress,
            unlocked: isUnlocked,
            selected: selected,
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
    final ratio = (progress / achievement.threshold).clamp(0.0, 1.0);

    return Material(
      color: const Color(0xFF17101F),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: saving ? null : onSelect,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFFC13BFF)
                  : const Color(0xFF382844),
            ),
          ),
          child: Opacity(
            opacity: unlocked ? 1 : .52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: TitleBadge(achievement: achievement)),
                    Icon(
                      unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: unlocked
                          ? const Color(0xFFB948FF)
                          : const Color(0xFF81778B),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  achievement.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFC7BDCF)),
                ),
                const Spacer(),
                LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: const Color(0xFF2D2435),
                  color: const Color(0xFFAA2CFF),
                ),
                const SizedBox(height: 7),
                Text(
                  '$progress / ${achievement.threshold}',
                  style: const TextStyle(
                    color: Color(0xFF988DA2),
                    fontSize: 11,
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

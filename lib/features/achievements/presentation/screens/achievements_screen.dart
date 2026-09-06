import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/identity/decorated_user_avatar.dart';
import 'package:yovoice/shared/widgets/identity/identity_name.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

import '../../../profile/data/models/user_profile.dart';
import '../../../profile/data/services/profile_service.dart';
import '../../data/achievement_catalog.dart';
import '../../data/models/achievement_definition.dart';
import '../../data/services/achievement_service.dart';
import '../achievement_localized_copy.dart';
import '../achievement_style.dart';
import '../widgets/title_badge.dart';

const Color _canvas = Color(0xFF09050F);
const Color _panel = Color(0xFF150C1D);
const Color _panelBorder = Color(0xFF382741);
const Color _ink = Colors.white;
const Color _inkMuted = Color(0xFFA99DB3);

/// Self-contained entry point for the Awards / achievements hub reached
/// from the More sheet and from the Profile screen — streams the current
/// profile itself so a selection made here restyles the hero, the cards
/// and the own-identity surfaces live.
///
/// [isRootTab] is true when the desktop shell renders it in a content slot
/// (the shell owns navigation, so the screen draws no app bar); a pushed
/// route carries a real app bar with Back.
class AwardsHubScreen extends StatefulWidget {
  const AwardsHubScreen({this.isRootTab = false, super.key});

  final bool isRootTab;

  @override
  State<AwardsHubScreen> createState() => _AwardsHubScreenState();
}

class _AwardsHubScreenState extends State<AwardsHubScreen> {
  late final ProfileService _profiles;
  late final AchievementService _achievements;

  @override
  void initState() {
    super.initState();
    _profiles = ProfileService();
    _achievements = AchievementService();
    // Counters such as friends/followers are maintained by their source
    // services. Reconcile them with the title catalog whenever Awards opens,
    // so an already-earned title never waits for an unrelated future event.
    _achievements.refreshUnlockedTitles().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final inShellSlot =
        widget.isRootTab && MediaQuery.sizeOf(context).width >= 980;
    final chrome = inShellSlot
        ? null
        : AppBar(
            backgroundColor: _canvas,
            foregroundColor: _ink,
            elevation: 0,
            title: Text(copy.text('Awards', 'Nagrody')),
          );
    final content = StreamBuilder<UserProfile>(
      stream: _profiles.watchCurrentProfile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _canvas,
            appBar: chrome,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  copy.text(
                    'Could not load achievements. Try again.',
                    'Nie udało się wczytać osiągnięć. Spróbuj ponownie.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _ink),
                ),
              ),
            ),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return Scaffold(
            backgroundColor: _canvas,
            appBar: chrome,
            body: const Center(
              child: CircularProgressIndicator(color: Color(0xFFB348FF)),
            ),
          );
        }
        return AchievementsScreen(
          profile: profile,
          achievementService: _achievements,
          isRootTab: widget.isRootTab,
        );
      },
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

enum AchievementCategory { creator, community, voice, friends }

const Map<AchievementCategory, Set<String>> _categoryMetrics = {
  AchievementCategory.creator: {'rooms', 'hostMinutes', 'moments'},
  AchievementCategory.community: {'communities', 'messages', 'reactions'},
  AchievementCategory.voice: {'voiceMinutes', 'activeDays'},
  AchievementCategory.friends: {'friends', 'followers'},
};

String _categoryLabel(AppLocalizations copy, AchievementCategory category) =>
    switch (category) {
      AchievementCategory.creator => copy.text('Creator', 'Twórczość'),
      AchievementCategory.community => copy.text('Community', 'Społeczność'),
      AchievementCategory.voice => copy.text('Voice', 'Głos'),
      AchievementCategory.friends => copy.text('Friends', 'Znajomi'),
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

  int totalForCategory(AchievementCategory category) {
    final metrics = _categoryMetrics[category] ?? const <String>{};
    return AchievementCatalog.all
        .where((item) => metrics.contains(item.metric))
        .length;
  }
}

/// One achievement track: every tier of a metric, the account's real
/// counter for it, and the next tier still to earn.
class AwardsTrack {
  const AwardsTrack({
    required this.metric,
    required this.tiers,
    required this.stat,
    required this.unlockedCount,
    required this.next,
  });

  final String metric;

  /// Ascending threshold, catalog order.
  final List<AchievementDefinition> tiers;
  final int stat;
  final int unlockedCount;

  /// The lowest tier not yet in `unlockedTitleIds`; null when complete.
  final AchievementDefinition? next;

  double get ratio {
    final target = next;
    if (target == null) return 1;
    final threshold = target.threshold <= 0 ? 1 : target.threshold;
    return (stat / threshold).clamp(0.0, 1.0);
  }
}

/// The Awards information architecture, computed once per build from the
/// profile and the active category filter:
///
///  * [selected] — the title in use (shown once, here, never again below);
///  * [unlocked] — every other earned title, best first;
///  * [inProgress] — the next tier of each track the account has started;
///  * [locked] — everything else, catalog order;
///  * [tracks] — the per-metric rollup, real counters only.
class AwardsSections {
  AwardsSections(UserProfile profile, {AchievementCategory? category})
    : this._(profile, _categoryFilter(category));

  AwardsSections._(UserProfile profile, bool Function(String metric) inView)
    : tracks = _buildTracks(profile, inView),
      selected = _selectedIn(profile, inView) {
    final unlockedIds = profile.unlockedTitleIds.toSet();
    final selectedId = selected?.id;
    unlocked =
        profile.unlockedTitleIds
            .map(AchievementCatalog.byId)
            .whereType<AchievementDefinition>()
            .where((item) => item.id != selectedId && inView(item.metric))
            .toList()
          ..sort(AchievementCatalog.compareByPrestige);
    final progressing =
        <AwardsTrack>[
          for (final track in tracks)
            if (track.next != null && track.stat > 0) track,
        ]..sort((a, b) {
          final ratio = b.ratio.compareTo(a.ratio);
          if (ratio != 0) return ratio;
          return a.next!.threshold.compareTo(b.next!.threshold);
        });
    inProgress = progressing
        .map((track) => track.next!)
        .toList(growable: false);
    final progressingIds = inProgress.map((item) => item.id).toSet();
    locked = AchievementCatalog.all
        .where(
          (item) =>
              inView(item.metric) &&
              !unlockedIds.contains(item.id) &&
              item.id != selectedId &&
              !progressingIds.contains(item.id),
        )
        .toList(growable: false);
  }

  final List<AwardsTrack> tracks;
  final AchievementDefinition? selected;
  late final List<AchievementDefinition> unlocked;
  late final List<AchievementDefinition> inProgress;
  late final List<AchievementDefinition> locked;

  static bool Function(String) _categoryFilter(AchievementCategory? category) {
    if (category == null) return (_) => true;
    final metrics = _categoryMetrics[category] ?? const <String>{};
    return metrics.contains;
  }

  static AchievementDefinition? _selectedIn(
    UserProfile profile,
    bool Function(String) inView,
  ) {
    final selected = AchievementCatalog.byId(profile.selectedTitleId);
    if (selected == null || !inView(selected.metric)) return null;
    return selected;
  }

  static List<AwardsTrack> _buildTracks(
    UserProfile profile,
    bool Function(String) inView,
  ) {
    final unlockedIds = profile.unlockedTitleIds.toSet();
    final byMetric = <String, List<AchievementDefinition>>{};
    for (final definition in AchievementCatalog.all) {
      if (!inView(definition.metric)) continue;
      byMetric.putIfAbsent(definition.metric, () => []).add(definition);
    }
    return [
      for (final entry in byMetric.entries)
        AwardsTrack(
          metric: entry.key,
          tiers: List.unmodifiable(
            entry.value..sort((a, b) => a.threshold.compareTo(b.threshold)),
          ),
          stat: profile.achievementStats[entry.key] ?? 0,
          unlockedCount: entry.value
              .where((tier) => unlockedIds.contains(tier.id))
              .length,
          next: entry.value.cast<AchievementDefinition?>().firstWhere(
            (tier) => !unlockedIds.contains(tier!.id),
            orElse: () => null,
          ),
        ),
    ];
  }
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    required this.profile,
    this.achievementService,
    this.isRootTab = false,
    super.key,
  });

  final UserProfile profile;
  final AchievementService? achievementService;

  /// True inside the desktop shell's content slot — no app bar of its own.
  final bool isRootTab;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final AchievementService _service =
      widget.achievementService ?? AchievementService();
  bool _saving = false;
  AchievementCategory? _selectedCategory;

  /// Selects [titleId] (null clears). Never pops the screen: on the desktop
  /// shell the Awards hub is a content slot with nothing to pop, and on a
  /// phone the hero restyles in place, which is the confirmation.
  Future<void> _select(String? titleId) async {
    if (_saving) return;
    final copy = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await _service.selectTitle(titleId);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            titleId == null
                ? copy.text('Title cleared.', 'Tytuł usunięty.')
                : copy.text('Title updated.', 'Tytuł zmieniony.'),
          ),
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            copy.text(
              'Could not update your title. Try again.',
              'Nie udało się zmienić tytułu. Spróbuj ponownie.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openDetail(AchievementDefinition achievement) async {
    final profile = widget.profile;
    final unlocked = profile.unlockedTitleIds.contains(achievement.id);
    final selected = profile.selectedTitleId == achievement.id;
    await _showAwardsSheet(
      context,
      child: _AchievementDetailSheet(
        achievement: achievement,
        profile: profile,
        unlocked: unlocked,
        selected: selected,
        progress: profile.achievementStats[achievement.metric] ?? 0,
        unlockedAt: profile.unlockedTitleTimestamps[achievement.id],
        onUse: unlocked && !selected ? () => _select(achievement.id) : null,
        onClear: selected ? () => _select(null) : null,
      ),
    );
  }

  Future<void> _openPicker(AwardsSections sections) async {
    final profile = widget.profile;
    final options =
        profile.unlockedTitleIds
            .map(AchievementCatalog.byId)
            .whereType<AchievementDefinition>()
            .toList()
          ..sort(AchievementCatalog.compareByPrestige);
    await _showAwardsSheet(
      context,
      child: _TitlePickerSheet(
        options: options,
        selectedId: profile.selectedTitleId,
        onPick: _select,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final profile = widget.profile;
    final unlockedIds = profile.unlockedTitleIds.toSet();
    final awardsProgress = AwardsProgress(profile);
    final sections = AwardsSections(profile, category: _selectedCategory);
    final inShellSlot =
        widget.isRootTab && MediaQuery.sizeOf(context).width >= 980;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final titleCount = copy.text(
      '${unlockedIds.length}/${awardsProgress.totalCount} titles',
      '${unlockedIds.length}/${awardsProgress.totalCount} tytułów',
    );
    final subtitle = copy.text(
      'Your progress across YO Voice',
      'Twoje postępy w YO Voice',
    );

    final content = Scaffold(
      backgroundColor: _canvas,
      // The desktop shell slot owns navigation; a pushed route (phone,
      // tablet, and any direct entry) carries the app bar with Back.
      appBar: inShellSlot
          ? null
          : AppBar(
              backgroundColor: _canvas,
              foregroundColor: _ink,
              elevation: 0,
              toolbarHeight: 58 + ((textScale - 1) * 34),
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleCount,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFA79CAD),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.dashboard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final gutter = isWide ? 24.0 : 16.0;

            Widget card(
              AchievementDefinition achievement, {
              bool compact = false,
            }) {
              return _AchievementCard(
                key: ValueKey('awards-card-${achievement.id}'),
                achievement: achievement,
                progress: profile.achievementStats[achievement.metric] ?? 0,
                unlocked: unlockedIds.contains(achievement.id),
                selected: profile.selectedTitleId == achievement.id,
                compact: compact,
                onOpen: () => _openDetail(achievement),
              );
            }

            List<Widget> section({
              required String id,
              required String title,
              required List<AchievementDefinition> items,
              required IconData icon,
              bool compact = false,
            }) {
              if (items.isEmpty) return const [];
              return [
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    key: ValueKey('awards-section-$id'),
                    icon: icon,
                    title: title,
                    count: items.length,
                    gutter: gutter,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 10),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: compact ? 380 : (isWide ? 560 : 520),
                      mainAxisExtent: compact
                          ? 124 + ((textScale - 1) * 80)
                          : 262 + ((textScale - 1) * 150),
                      crossAxisSpacing: compact ? 10 : 16,
                      mainAxisSpacing: compact ? 10 : 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => card(items[index], compact: compact),
                      childCount: items.length,
                    ),
                  ),
                ),
              ];
            }

            return CustomScrollView(
              slivers: [
                if (inShellSlot)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleCount,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFFA79CAD),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
                    child: _TitleHero(
                      profile: profile,
                      hasUnlocked: unlockedIds.isNotEmpty,
                      saving: _saving,
                      onChange: () => _openPicker(sections),
                      onClear: () => _select(null),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _AwardsHeader(
                    progress: awardsProgress,
                    tracks: sections.tracks,
                    selectedCategory: _selectedCategory,
                    onSelectCategory: (value) =>
                        setState(() => _selectedCategory = value),
                    isWide: isWide,
                  ),
                ),
                ...section(
                  id: 'selected',
                  title: copy.text('Selected', 'Wybrany'),
                  icon: Icons.check_circle_rounded,
                  items: [if (sections.selected != null) sections.selected!],
                ),
                ...section(
                  id: 'unlocked',
                  title: copy.text('Unlocked titles', 'Odblokowane tytuły'),
                  icon: Icons.lock_open_rounded,
                  items: sections.unlocked,
                ),
                ...section(
                  id: 'in-progress',
                  title: copy.text('In progress', 'W trakcie'),
                  icon: Icons.trending_up_rounded,
                  items: sections.inProgress,
                ),
                ...section(
                  id: 'locked',
                  title: copy.text('Still locked', 'Nadal zablokowane'),
                  icon: Icons.lock_rounded,
                  items: sections.locked,
                  compact: true,
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

/// Every Awards modal (detail, picker) is a bottom sheet bounded to 640px
/// on wide windows, and stays inside the screen's dark island.
Future<void> _showAwardsSheet(BuildContext context, {required Widget child}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    builder: (sheetContext) => YoImmersiveDarkSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .88,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF140B1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: _panelBorder)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// "Your title": the selected title at full size, a live preview of the
/// avatar ring and name colour it produces, and Change / Clear.
class _TitleHero extends StatelessWidget {
  const _TitleHero({
    required this.profile,
    required this.hasUnlocked,
    required this.saving,
    required this.onChange,
    required this.onClear,
  });

  final UserProfile profile;
  final bool hasUnlocked;
  final bool saving;
  final VoidCallback onChange;
  final VoidCallback onClear;

  static const Color _surface = Color(0xFF1E0F33);

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final title = AchievementCatalog.byId(profile.selectedTitleId);
    final style = title == null ? null : achievementStyleFor(title, copy: copy);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final avatar = DecoratedUserAvatar(
          key: const ValueKey('awards-hero-avatar'),
          radius: stacked ? 30 : 36,
          userId: profile.uid,
          photoUrl: profile.photoUrl,
          mediaRevision: profile.profileUpdatedAt,
          displayName: profile.displayName,
          premium: profile.premiumIdentity,
          achievementStyle: style,
          surface: _surface,
          ringWidth: 2.4,
          ringGap: 2,
        );
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.text('Your title', 'Twój tytuł').toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFC7BBD1),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            IdentityName(
              profile.displayName,
              key: const ValueKey('awards-hero-name'),
              style: TextStyle(
                color: _ink,
                fontSize: stacked ? 20 : 23,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -.3,
              ),
              achievementStyle: style,
              surface: _surface,
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            if (title != null)
              TitleBadge(achievement: title)
            else
              Text(
                copy.text('No title selected', 'Brak wybranego tytułu'),
                style: const TextStyle(
                  color: _inkMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              title != null
                  ? copy.text(
                      'Colours your avatar ring and name. Visible on your own '
                          'profile for now.',
                      'Koloruje pierścień awatara i Twoje imię. Na razie '
                          'widoczne na Twoim profilu.',
                    )
                  : hasUnlocked
                  ? copy.text(
                      'Choose one of your unlocked titles to decorate your '
                          'avatar ring and name.',
                      'Wybierz jeden z odblokowanych tytułów, aby ozdobić '
                          'pierścień awatara i imię.',
                    )
                  : copy.text(
                      'Unlock a title to choose one.',
                      'Odblokuj tytuł, aby go wybrać.',
                    ),
              style: const TextStyle(
                color: _inkMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('awards-hero-change'),
              onPressed: hasUnlocked && !saving ? onChange : null,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(copy.text('Change', 'Zmień')),
            ),
            if (title != null)
              OutlinedButton.icon(
                key: const ValueKey('awards-hero-clear'),
                onPressed: saving ? null : onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(copy.text('Clear', 'Wyczyść')),
              ),
          ],
        );

        return Container(
          key: const ValueKey('awards-hero'),
          padding: EdgeInsets.all(stacked ? 16 : 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A0F45), _surface],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF4B2C63)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        Expanded(child: identity),
                      ],
                    ),
                    const SizedBox(height: 14),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    const SizedBox(width: 18),
                    Expanded(child: identity),
                    const SizedBox(width: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: actions,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _AwardsHeader extends StatelessWidget {
  const _AwardsHeader({
    required this.progress,
    required this.tracks,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.isWide,
  });

  final AwardsProgress progress;
  final List<AwardsTrack> tracks;
  final AchievementCategory? selectedCategory;
  final ValueChanged<AchievementCategory?> onSelectCategory;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 14, isWide ? 24 : 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LevelCard(progress: progress),
          const SizedBox(height: 14),
          _StatsRow(progress: progress),
          const SizedBox(height: 18),
          Text(
            copy.text('Categories', 'Kategorie'),
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height:
                48 +
                ((MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) -
                        1) *
                    24),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: copy.text('All', 'Wszystkie'),
                  icon: Icons.grid_view_rounded,
                  count: '${progress.unlockedCount}/${progress.totalCount}',
                  selected: selectedCategory == null,
                  onTap: () => onSelectCategory(null),
                ),
                for (final category in AchievementCategory.values) ...[
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: _categoryLabel(copy, category),
                    icon: _categoryIcon(category),
                    count:
                        '${progress.countForCategory(category)}/${progress.totalForCategory(category)}',
                    selected: selectedCategory == category,
                    onTap: () => onSelectCategory(category),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _TrackRollup(tracks: tracks),
          const SizedBox(height: 18),
          _RecentUnlocks(progress: progress),
          const SizedBox(height: 4),
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
    final copy = AppLocalizations.of(context);
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
                color: _ink,
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
                  copy.text(
                    'Level ${progress.level}',
                    'Poziom ${progress.level}',
                  ),
                  style: const TextStyle(
                    color: _ink,
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
                  copy.text(
                    '${progress.xpIntoLevel} / $_xpPerLevel XP to level ${progress.level + 1}',
                    '${progress.xpIntoLevel} / $_xpPerLevel XP do poziomu ${progress.level + 1}',
                  ),
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
    final copy = AppLocalizations.of(context);
    final tiles = [
      _StatTile(
        icon: Icons.lock_open_rounded,
        value: '${progress.unlockedCount}',
        label: copy.text('Unlocked', 'Odblokowane'),
        color: const Color(0xFF4DE09E),
      ),
      _StatTile(
        icon: Icons.lock_rounded,
        value: '${progress.lockedCount}',
        label: copy.text('Locked', 'Zablokowane'),
        color: const Color(0xFF9F95A6),
      ),
      _StatTile(
        icon: Icons.donut_large_rounded,
        value: '${(progress.completionRatio * 100).round()}%',
        label: copy.text('Complete', 'Ukończono'),
        color: const Color(0xFFD28AFF),
      ),
      _StatTile(
        icon: Icons.bolt_rounded,
        value: '${progress.totalXp}',
        label: copy.text('Total XP', 'Łącznie XP'),
        color: const Color(0xFFFFA52B),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 2.0);
        final columns = constraints.maxWidth < 420 || textScale > 1.4 ? 2 : 4;
        const gap = 10.0;
        final tileWidth =
            (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
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
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: _inkMuted, fontSize: 10.5)),
        ],
      ),
    );
  }
}

/// Per-track rollup: one tile per metric with the real counter, how many
/// of its ten tiers are earned and the distance to the next one. A
/// horizontal rail on phones; a grid once the width allows four tiles.
class _TrackRollup extends StatelessWidget {
  const _TrackRollup({required this.tracks});

  final List<AwardsTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final tileHeight = 128 + ((textScale - 1) * 76);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.text('Your tracks', 'Twoje ścieżki'),
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width < 700 || textScale > 1.4) {
              return SizedBox(
                height: tileHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => SizedBox(
                    width: 162,
                    child: _TrackTile(track: tracks[index]),
                  ),
                ),
              );
            }
            final columns = width >= 1000 ? 5 : 4;
            const gap = 10.0;
            final tileWidth = (width - ((columns - 1) * gap)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final track in tracks)
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: _TrackTile(track: track),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final AwardsTrack track;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final next = track.next;
    final palette = AchievementRarityPalette.forRarity(
      (next ?? track.tiers.last).rarity,
    );
    final complete = next == null;
    final label = localizedAchievementMetric(copy, track.metric);
    final tiers = copy.template(
      '{unlocked}/{total} tiers',
      '{unlocked}/{total} poziomów',
      values: <String, Object>{
        'unlocked': track.unlockedCount,
        'total': track.tiers.length,
      },
    );
    final progressText = complete
        ? copy.text('Complete', 'Ukończono')
        : '${track.stat.clamp(0, next.threshold)} / ${next.threshold}';

    return Semantics(
      key: ValueKey('awards-track-${track.metric}'),
      container: true,
      label: '$label, $tiers, $progressText',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _panelBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconForMetric(track.metric),
                  color: palette.accent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                // "3/10 levels" doubles in width at 200% text; let it
                // ellipsize inside the tile instead of overflowing it.
                Expanded(
                  child: Text(
                    tiers,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            _AnimatedProgressBar(
              value: track.ratio,
              color: palette.accent,
              mythic: !complete && next.rarity == AchievementRarity.mythic,
              height: 6,
            ),
            const SizedBox(height: 5),
            Text(
              progressText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _inkMuted, fontSize: 10.5),
            ),
          ],
        ),
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
  final String count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
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
                color: selected ? Colors.transparent : _panelBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? _ink : const Color(0xFFB8ADBF),
                ),
                const SizedBox(width: 6),
                Text(
                  '$label · $count',
                  style: TextStyle(
                    color: selected ? _ink : const Color(0xFFC7BBD1),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
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

class _RecentUnlocks extends StatelessWidget {
  const _RecentUnlocks({required this.progress});
  final AwardsProgress progress;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final dated = progress.recentUnlocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.text('Recent unlocks', 'Ostatnio odblokowane'),
          style: const TextStyle(
            color: _ink,
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
              color: _panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _panelBorder),
            ),
            child: Text(
              copy.text(
                'No achievements unlocked yet. Chat, host rooms and connect with '
                    'friends to earn your first title.',
                'Nie masz jeszcze odblokowanych osiągnięć. Rozmawiaj, prowadź '
                    'pokoje i poznawaj ludzi, aby zdobyć pierwszy tytuł.',
              ),
              style: const TextStyle(
                color: _inkMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          )
        else
          SizedBox(
            height:
                116 +
                ((MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) -
                        1) *
                    54),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dated.length > 8 ? 8 : dated.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final (achievement, unlockedAt) = dated[index];
                final palette = AchievementRarityPalette.forRarity(
                  achievement.rarity,
                );
                return Container(
                  width: 150,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.cardSurfaceStart,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.cardBorder),
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
                        localizedAchievementTitle(copy, achievement),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        _relativeTime(copy, unlockedAt),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.gutter,
    super.key,
  });

  final IconData icon;
  final String title;
  final int count;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 6),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFFC7BBD1)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF17101F),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: _panelBorder),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFFC7BBD1),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
    required this.onOpen,
    this.compact = false,
    super.key,
  });

  final AchievementDefinition achievement;
  final int progress;
  final bool unlocked;
  final bool selected;
  final VoidCallback onOpen;

  /// The dense variant for the long "still locked" tail: title, rarity and
  /// the requirement, without the description and animated bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = AchievementRarityPalette.forRarity(achievement.rarity);
    final safeThreshold = achievement.threshold <= 0
        ? 1
        : achievement.threshold;
    final ratio = (progress / safeThreshold).clamp(0.0, 1.0);
    final shownProgress = progress.clamp(0, achievement.threshold);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final title = localizedAchievementTitle(copy, achievement);
    final rarity = localizedAchievementRarity(copy, achievement.rarity);
    final status = selected
        ? copy.text('ACTIVE', 'AKTYWNY')
        : unlocked
        ? copy.text('UNLOCKED', 'ODBLOKOWANY')
        : copy.text('LOCKED', 'ZABLOKOWANE');
    final semanticLabel =
        '$title, $rarity, $status, $shownProgress / ${achievement.threshold}';

    final body = compact
        ? _compactBody(copy, palette, title, rarity, shownProgress)
        : _fullBody(
            copy,
            palette,
            title,
            rarity,
            status,
            ratio,
            shownProgress,
            largeText,
          );

    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      hint: copy.text('Opens details', 'Otwiera szczegóły'),
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 18 : 26),
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
          borderRadius: BorderRadius.circular(compact ? 18 : 26),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(compact ? 18 : 26),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: unlocked
                      ? [palette.cardSurfaceStart, palette.cardSurfaceEnd]
                      : const [Color(0xFF17111E), Color(0xFF100B16)],
                ),
                borderRadius: BorderRadius.circular(compact ? 18 : 26),
                border: Border.all(
                  width: selected ? 2 : 1,
                  color: selected
                      ? palette.accent
                      : unlocked
                      ? palette.cardBorder
                      : const Color(0xFF3B2D44),
                ),
              ),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactBody(
    AppLocalizations copy,
    AchievementRarityPalette palette,
    String title,
    String rarity,
    int shownProgress,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Opacity(
        opacity: unlocked ? 1 : .72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _AchievementIcon(
              icon: _iconForMetric(achievement.metric),
              color: palette.accent,
              unlocked: unlocked,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unlocked
                          ? palette.accent
                          : const Color(0xFFC4BBC9),
                      fontSize: 14.5,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _RarityChip(label: rarity, color: palette.accent),
                      Text(
                        '$shownProgress / ${achievement.threshold}',
                        style: const TextStyle(
                          color: Color(0xFF968B9D),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.lock_rounded, size: 18, color: const Color(0xFF93889A)),
          ],
        ),
      ),
    );
  }

  Widget _fullBody(
    AppLocalizations copy,
    AchievementRarityPalette palette,
    String title,
    String rarity,
    String status,
    double ratio,
    int shownProgress,
    bool largeText,
  ) {
    return Stack(
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
                  palette.accent.withValues(alpha: unlocked ? .14 : .06),
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
                              title,
                              maxLines: largeText ? 3 : 2,
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
                            _RarityChip(label: rarity, color: palette.accent),
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
                  localizedAchievementDescription(copy, achievement),
                  maxLines: largeText ? 3 : 2,
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
                      mythic: achievement.rarity == AchievementRarity.mythic,
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
                    Text(
                      status,
                      style: TextStyle(
                        color: selected
                            ? _ink
                            : unlocked
                            ? palette.accent
                            : const Color(0xFF8E8397),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: selected ? 1 : .8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AchievementIcon extends StatelessWidget {
  const _AchievementIcon({
    required this.icon,
    required this.color,
    required this.unlocked,
    this.size = 64,
  });

  final IconData icon;
  final Color color;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .31),
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
        size: size * .47,
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
    this.height = 10,
  });

  final double value;
  final Color color;
  final bool mythic;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
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
        child: const Icon(Icons.check_rounded, color: _ink, size: 22),
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

/// The detail sheet behind every card: what the title is, how it looks on
/// the account, when it was earned or how far away it is, and the one
/// action it allows.
class _AchievementDetailSheet extends StatelessWidget {
  const _AchievementDetailSheet({
    required this.achievement,
    required this.profile,
    required this.unlocked,
    required this.selected,
    required this.progress,
    required this.unlockedAt,
    required this.onUse,
    required this.onClear,
  });

  final AchievementDefinition achievement;
  final UserProfile profile;
  final bool unlocked;
  final bool selected;
  final int progress;
  final DateTime? unlockedAt;
  final VoidCallback? onUse;
  final VoidCallback? onClear;

  static const Color _surface = Color(0xFF140B1E);

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = AchievementRarityPalette.forRarity(achievement.rarity);
    final style = achievementStyleFor(achievement, copy: copy);
    final safeThreshold = achievement.threshold <= 0
        ? 1
        : achievement.threshold;
    final ratio = (progress / safeThreshold).clamp(0.0, 1.0);
    final title = localizedAchievementTitle(copy, achievement);
    final unlockedOn = unlockedAt;

    return Column(
      key: const ValueKey('awards-detail-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AchievementIcon(
              icon: _iconForMetric(achievement.metric),
              color: palette.accent,
              unlocked: unlocked,
              size: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: unlocked
                            ? palette.accent
                            : const Color(0xFFE4DCE8),
                        fontSize: 21,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _RarityChip(
                        label: localizedAchievementRarity(
                          copy,
                          achievement.rarity,
                        ),
                        color: palette.accent,
                      ),
                      Text(
                        selected
                            ? copy.text('Active', 'Aktywny')
                            : unlocked
                            ? copy.text('Unlocked', 'Odblokowany')
                            : copy.text('Locked', 'Zablokowany'),
                        style: const TextStyle(
                          color: _inkMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: copy.text('Close', 'Zamknij'),
              icon: const Icon(Icons.close_rounded),
              color: _inkMuted,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          localizedAchievementDescription(copy, achievement),
          style: const TextStyle(
            color: Color(0xFFD4CBD9),
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        // Live preview of the cosmetic — the same widgets the profile header
        // renders, so what is promised here is what appears there.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1026),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _panelBorder),
          ),
          child: Row(
            children: [
              DecoratedUserAvatar(
                radius: 24,
                userId: profile.uid,
                photoUrl: profile.photoUrl,
                mediaRevision: profile.profileUpdatedAt,
                displayName: profile.displayName,
                premium: profile.premiumIdentity,
                achievementStyle: style,
                surface: const Color(0xFF1B1026),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy.text('Preview', 'Podgląd').toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFC7BBD1),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    IdentityName(
                      profile.displayName,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      achievementStyle: style,
                      surface: const Color(0xFF1B1026),
                    ),
                    const SizedBox(height: 6),
                    TitleBadge(achievement: achievement, compact: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (unlocked) ...[
          if (unlockedOn != null)
            Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  size: 16,
                  color: _inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    copy.template(
                      'Unlocked {date}',
                      'Odblokowano {date}',
                      values: <String, Object>{
                        'date': copy.calendarDate(unlockedOn),
                      },
                    ),
                    style: const TextStyle(color: _inkMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
        ] else ...[
          Text(
            copy.text('Requirement', 'Wymaganie').toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFC7BBD1),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedProgressBar(
            value: ratio,
            color: palette.accent,
            mythic: achievement.rarity == AchievementRarity.mythic,
          ),
          const SizedBox(height: 8),
          Text(
            '${progress.clamp(0, achievement.threshold)} / ${achievement.threshold} · '
            '${localizedAchievementMetric(copy, achievement.metric)}',
            style: const TextStyle(
              color: _inkMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (onUse != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('awards-detail-use'),
              onPressed: () {
                Navigator.of(context).pop();
                onUse!();
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(copy.text('Use this title', 'Użyj tego tytułu')),
            ),
          )
        else if (onClear != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('awards-detail-clear'),
              onPressed: () {
                Navigator.of(context).pop();
                onClear!();
              },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(copy.text('Clear title', 'Usuń tytuł')),
            ),
          )
        else if (!unlocked)
          Text(
            copy.text(
              'Keep going — this title unlocks on its own once you reach the '
                  'requirement.',
              'Tak trzymaj — ten tytuł odblokuje się sam po spełnieniu '
                  'wymagania.',
            ),
            style: const TextStyle(
              color: _inkMuted,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        Container(height: 0, color: _surface),
      ],
    );
  }
}

/// "Change" from the hero: every unlocked title, best first, one tap to use.
class _TitlePickerSheet extends StatelessWidget {
  const _TitlePickerSheet({
    required this.options,
    required this.selectedId,
    required this.onPick,
  });

  final List<AchievementDefinition> options;
  final String? selectedId;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('awards-picker-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  copy.text('Choose a title', 'Wybierz tytuł'),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: copy.text('Close', 'Zamknij'),
              icon: const Icon(Icons.close_rounded),
              color: _inkMuted,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final option in options)
          _PickerRow(
            key: ValueKey('awards-picker-${option.id}'),
            achievement: option,
            active: option.id == selectedId,
            onTap: () {
              Navigator.of(context).pop();
              if (option.id != selectedId) onPick(option.id);
            },
          ),
        if (selectedId != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('awards-picker-clear'),
              onPressed: () {
                Navigator.of(context).pop();
                onPick(null);
              },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(copy.text('Clear title', 'Usuń tytuł')),
            ),
          ),
        ],
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.achievement,
    required this.active,
    required this.onTap,
    super.key,
  });

  final AchievementDefinition achievement;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = AchievementRarityPalette.forRarity(achievement.rarity);
    final title = localizedAchievementTitle(copy, achievement);
    final rarity = localizedAchievementRarity(copy, achievement.rarity);
    return Semantics(
      button: true,
      selected: active,
      label: '$title, $rarity',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(child: TitleBadge(achievement: achievement)),
                const SizedBox(width: 10),
                Text(
                  rarity,
                  style: TextStyle(
                    color: palette.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  active
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: active ? palette.accent : const Color(0xFF6E6278),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _relativeTime(AppLocalizations copy, DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return copy.text('Just now', 'Przed chwilą');
  if (diff.inHours < 1) {
    return copy.text('${diff.inMinutes}m ago', '${diff.inMinutes} min temu');
  }
  if (diff.inDays < 1) {
    return copy.text('${diff.inHours}h ago', '${diff.inHours} godz. temu');
  }
  if (diff.inDays < 30) {
    return copy.text('${diff.inDays}d ago', '${diff.inDays} dni temu');
  }
  final months = diff.inDays ~/ 30;
  return copy.text('${months}mo ago', '$months mies. temu');
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/discover/presentation/discover_category_identity.dart';
import 'package:yovoice/features/discover/presentation/discover_localized_copy.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/features/discover/presentation/widgets/hero_live_room.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.isRootTab = false, this.roomService, super.key});

  /// True when this screen IS the shell's current content (the desktop
  /// rail's Discover slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never shows a back button that
  /// would have nothing to pop.
  final bool isRootTab;

  /// Injectable for focused rendering and error-state tests. Production keeps
  /// the same default service and therefore the same live-room data source.
  final RoomService? roomService;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const List<_DiscoverCategory> _categories = [
    _DiscoverCategory(label: 'All', icon: Icons.grid_view_rounded),
    _DiscoverCategory(label: 'Talk', icon: Icons.record_voice_over_rounded),
    _DiscoverCategory(label: 'Music', icon: Icons.music_note_rounded),
    _DiscoverCategory(label: 'Gaming', icon: Icons.sports_esports_rounded),
    _DiscoverCategory(label: 'Chill', icon: Icons.nightlife_rounded),
    _DiscoverCategory(label: 'Study', icon: Icons.school_rounded),
    _DiscoverCategory(label: 'Business', icon: Icons.work_rounded),
  ];

  late final RoomService _roomService = widget.roomService ?? RoomService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  String _query = '';
  String _selectedCategory = 'All';

  bool get _hasFilters =>
      _query.isNotEmpty || _selectedCategory.toLowerCase() != 'all';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _query = value.trim().toLowerCase();
      });
    });
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();

    setState(() {
      _query = '';
      _selectedCategory = 'All';
    });
  }

  Future<void> _openRoom(VoiceRoom room) async {
    final copy = AppLocalizations.of(context);
    try {
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(_readableError(error, copy));
    }
  }

  String _readableError(Object error, AppLocalizations copy) {
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return copy.text(
        "You don't have permission to do that.",
        'Nie masz uprawnień do wykonania tej czynności.',
      );
    }

    if (message.toLowerCase().contains('full')) {
      return copy.text('This room is full.', 'Ten pokój jest pełny.');
    }

    if (message.toLowerCase().contains('no longer live')) {
      return copy.text(
        'This room has already ended.',
        'Ten pokój już się zakończył.',
      );
    }

    if (message.toLowerCase().contains('not live')) {
      return copy.text(
        'Voice is no longer live in this room.',
        'Rozmowa głosowa w tym pokoju już się zakończyła.',
      );
    }

    if (message.toLowerCase().contains('unavailable')) {
      return copy.text(
        'This room is currently unavailable.',
        'Ten pokój jest obecnie niedostępny.',
      );
    }

    return friendlyErrorMessage(
      error,
      copy: copy,
      fallback: copy.text(
        'Could not open this room. Please try again.',
        'Nie udało się otworzyć pokoju. Spróbuj ponownie.',
      ),
    );
  }

  void _showError(String message) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: colors.onError)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.error,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  List<VoiceRoom> _filterRooms(List<VoiceRoom> rooms) {
    final filtered = rooms.where((room) {
      final selectedCategory = _selectedCategory.trim().toLowerCase();
      final roomCategory = room.category.trim().toLowerCase();

      final matchesCategory =
          selectedCategory == 'all' || roomCategory == selectedCategory;

      if (!matchesCategory) {
        return false;
      }

      if (_query.isEmpty) {
        return true;
      }

      final haystack = <String>[
        room.name,
        room.description,
        room.category,
        room.language,
        room.hostName,
        room.experience,
      ].join(' ').toLowerCase();

      return haystack.contains(_query);
    }).toList();

    filtered.sort(_compareTrending);

    return filtered;
  }

  int _compareTrending(VoiceRoom a, VoiceRoom b) {
    final participantComparison = b.participantCount.compareTo(
      a.participantCount,
    );

    if (participantComparison != 0) {
      return participantComparison;
    }

    final memberComparison = b.memberCount.compareTo(a.memberCount);

    if (memberComparison != 0) {
      return memberComparison;
    }

    final aDate =
        a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate =
        b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

    return bDate.compareTo(aDate);
  }

  List<VoiceRoom> _sortRising(List<VoiceRoom> rooms) {
    final sorted = List<VoiceRoom>.of(rooms);

    sorted.sort((a, b) {
      final aDate =
          a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final dateComparison = bDate.compareTo(aDate);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return b.participantCount.compareTo(a.participantCount);
    });

    return sorted;
  }

  _DiscoverSections _createSections(List<VoiceRoom> rooms) {
    if (rooms.isEmpty) {
      return const _DiscoverSections(
        hero: null,
        featured: <VoiceRoom>[],
        trending: <VoiceRoom>[],
        rising: <VoiceRoom>[],
      );
    }

    final trendingOrder = List<VoiceRoom>.of(rooms)..sort(_compareTrending);
    final risingOrder = _sortRising(rooms);

    final hero = trendingOrder.first;
    final usedIds = <String>{hero.id};

    final featured = <VoiceRoom>[];

    for (final room in trendingOrder.skip(1)) {
      if (featured.length >= 4) {
        break;
      }

      if (usedIds.add(room.id)) {
        featured.add(room);
      }
    }

    final trending = <VoiceRoom>[];

    for (final room in trendingOrder) {
      if (trending.length >= 5) {
        break;
      }

      if (usedIds.add(room.id)) {
        trending.add(room);
      }
    }

    final rising = <VoiceRoom>[];

    for (final room in risingOrder) {
      if (rising.length >= 5) {
        break;
      }

      if (usedIds.add(room.id)) {
        rising.add(room);
      }
    }

    if (trending.isEmpty && rooms.length > 1) {
      trending.addAll(
        trendingOrder
            .where((room) => room.id != hero.id)
            .take(math.min(5, rooms.length - 1)),
      );
    }

    if (rising.isEmpty && rooms.length > 2) {
      rising.addAll(
        risingOrder
            .where((room) => room.id != hero.id)
            .skip(1)
            .take(math.min(5, rooms.length - 2)),
      );
    }

    return _DiscoverSections(
      hero: hero,
      featured: featured,
      trending: trending,
      rising: rising,
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const ValueKey('discover-screen'),
      backgroundColor: palette.background,
      body: Container(
        key: const ValueKey('discover-canvas'),
        decoration: BoxDecoration(
          gradient: dark
              ? RadialGradient(
                  center: const Alignment(-0.86, -0.94),
                  radius: 1.28,
                  colors: [
                    Color.lerp(palette.backgroundTop, colors.primary, .16)!,
                    palette.backgroundTop,
                    palette.background,
                  ],
                  stops: const [0, 0.4, 1],
                )
              : palette.backgroundGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.dashboard,
            child: StreamBuilder<List<VoiceRoom>>(
              stream: _roomService.watchLivePublicRooms(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _DiscoverErrorState(
                    message: _readableError(snapshot.error!, copy),
                  );
                }

                final allRooms = snapshot.data ?? const <VoiceRoom>[];
                final filteredRooms = _filterRooms(allRooms);
                final sections = _createSections(filteredRooms);

                return RefreshIndicator(
                  color: colors.primary,
                  backgroundColor: palette.surface,
                  onRefresh: () async {
                    setState(() {});
                    await Future<void>.delayed(
                      const Duration(milliseconds: 350),
                    );
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                          child: _DiscoverHeader(
                            searchController: _searchController,
                            onSearchChanged: _onSearchChanged,
                            liveRoomCount: allRooms.length,
                            isRootTab: widget.isRootTab,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 21),
                          child: _CategorySelector(
                            categories: _categories,
                            selectedCategory: _selectedCategory,
                            onSelected: (category) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                          ),
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _DiscoverLoadingState(),
                        )
                      else if (filteredRooms.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _DiscoverEmptyState(
                            hasFilters: _hasFilters,
                            // With zero live rooms overall, "No matching
                            // rooms" would blame the search phrase for an
                            // empty universe.
                            nothingIsLive: allRooms.isEmpty,
                            onClear: _clearFilters,
                          ),
                        )
                      else if (_hasFilters)
                        ..._buildSearchResults(filteredRooms)
                      else
                        ..._buildPremiumSections(sections),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchResults(List<VoiceRoom> rooms) {
    final copy = AppLocalizations.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 14),
          child: _SectionHeader(
            title: copy.text('Search results', 'Wyniki wyszukiwania'),
            subtitle: localizedLiveRoomCount(copy, rooms.length),
            icon: Icons.search_rounded,
            accent: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
        sliver: SliverList.separated(
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 13),
          itemBuilder: (context, index) {
            final room = rooms[index];

            return _PremiumRoomCard(
              room: room,
              rank: index + 1,
              style: _RoomCardStyle.standard,
              onPressed: () => _openRoom(room),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildPremiumSections(_DiscoverSections sections) {
    final copy = AppLocalizations.of(context);
    final widgets = <Widget>[];
    final hero = sections.hero;

    if (hero != null) {
      widgets.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 27, 18, 0),
            child: HeroLiveRoom(room: hero, onJoin: () => _openRoom(hero)),
          ),
        ),
      );
    }

    if (sections.featured.isNotEmpty) {
      widgets.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 31, 18, 14),
            child: _SectionHeader(
              title: copy.text('Featured', 'Polecane'),
              subtitle: copy.text(
                'Rooms selected for you',
                'Pokoje wybrane dla Ciebie',
              ),
              icon: Icons.auto_awesome_rounded,
              accent: const Color(0xFFFFB84D),
            ),
          ),
        ),
      );

      widgets.add(
        SliverToBoxAdapter(
          child: DiscoverFeaturedRooms(
            rooms: sections.featured,
            onRoomPressed: _openRoom,
          ),
        ),
      );
    }

    if (sections.trending.isNotEmpty) {
      widgets.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 32, 18, 14),
            child: _SectionHeader(
              title: copy.text('Trending', 'Popularne'),
              subtitle: copy.text(
                'The busiest conversations right now',
                'Najbardziej oblegane rozmowy w tej chwili',
              ),
              icon: Icons.local_fire_department_rounded,
              accent: const Color(0xFFFF5C75),
            ),
          ),
        ),
      );

      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          sliver: SliverList.separated(
            itemCount: sections.trending.length,
            separatorBuilder: (_, __) => const SizedBox(height: 13),
            itemBuilder: (context, index) {
              final room = sections.trending[index];

              return _PremiumRoomCard(
                room: room,
                rank: index + 1,
                style: _RoomCardStyle.trending,
                onPressed: () => _openRoom(room),
              );
            },
          ),
        ),
      );
    }

    if (sections.rising.isNotEmpty) {
      widgets.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 32, 18, 14),
            child: _SectionHeader(
              title: copy.text('Rising', 'Na fali'),
              subtitle: copy.text(
                'Fresh rooms gaining momentum',
                'Nowe pokoje, które nabierają tempa',
              ),
              icon: Icons.trending_up_rounded,
              accent: const Color(0xFF57D9A3),
            ),
          ),
        ),
      );

      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
          sliver: SliverList.separated(
            itemCount: sections.rising.length,
            separatorBuilder: (_, __) => const SizedBox(height: 13),
            itemBuilder: (context, index) {
              final room = sections.rising[index];

              return _PremiumRoomCard(
                room: room,
                rank: index + 1,
                style: _RoomCardStyle.rising,
                onPressed: () => _openRoom(room),
              );
            },
          ),
        ),
      );
    } else {
      widgets.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));
    }

    return widgets;
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({
    required this.searchController,
    required this.onSearchChanged,
    required this.liveRoomCount,
    this.isRootTab = false,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final int liveRoomCount;
  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.text('Discover', 'Odkrywaj'),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 31,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.9,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          copy.text(
            'Find voices worth staying for.',
            'Znajdź głosy, przy których warto zostać.',
          ),
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    final back = YoIconButton(
      icon: Icons.arrow_back_ios_new_rounded,
      iconSize: 18,
      size: 40,
      backgroundColor: palette.surface,
      borderColor: palette.border,
      onPressed: () => Navigator.of(context).pop(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (largeText) ...[
          if (!isRootTab) ...[back, const SizedBox(height: 14)],
          title,
          const SizedBox(height: 14),
          _LiveRoomCounter(count: liveRoomCount),
        ] else
          Row(
            children: [
              if (!isRootTab) ...[back, const SizedBox(width: 10)],
              Expanded(child: title),
              _LiveRoomCounter(count: liveRoomCount),
            ],
          ),
        const SizedBox(height: 22),
        TextField(
          key: const ValueKey('discover-search-field'),
          controller: searchController,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          cursorColor: colors.primary,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: copy.text(
              'Search rooms, hosts or topics...',
              'Szukaj pokoi, prowadzących lub tematów…',
            ),
            hintStyle: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: palette.textSecondary,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }

                return IconButton(
                  tooltip: copy.text('Clear search', 'Wyczyść wyszukiwanie'),
                  onPressed: () {
                    searchController.clear();
                    onSearchChanged('');
                  },
                  icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                );
              },
            ),
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(color: palette.focus, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveRoomCounter extends StatelessWidget {
  const _LiveRoomCounter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.dangerSurface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.error.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: colors.error.withValues(alpha: 0.12),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: colors.error, size: 9),
          const SizedBox(width: 7),
          Text(
            copy.text('$count LIVE', '$count NA ŻYWO'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<_DiscoverCategory> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return SizedBox(
      height: largeText ? 64 : 47,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.label == selectedCategory;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.22),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Material(
              key: ValueKey('discover-category-${category.label}'),
              color: selected ? colors.primary : palette.surface,
              borderRadius: BorderRadius.circular(30),
              child: InkWell(
                onTap: () => onSelected(category.label),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: selected ? colors.primary : palette.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        category.icon,
                        color: selected
                            ? colors.onPrimary
                            : palette.textSecondary,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        localizedDiscoverCategory(copy, category.label),
                        style: TextStyle(
                          color: selected
                              ? colors.onPrimary
                              : palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: visuals.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: visuals.border),
          ),
          child: Icon(icon, color: visuals.onSurface, size: 20),
        ),
      ],
    );
  }
}

/// Featured rooms remain a quick horizontal carousel at standard text sizes,
/// then become an intrinsic-height vertical list when accessibility text no
/// longer fits the compact card. The surrounding Discover scroll view owns
/// vertical scrolling in that mode.
class DiscoverFeaturedRooms extends StatelessWidget {
  const DiscoverFeaturedRooms({
    required this.rooms,
    required this.onRoomPressed,
    super.key,
  });

  final List<VoiceRoom> rooms;
  final ValueChanged<VoiceRoom> onRoomPressed;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final useVerticalLayout = textScale > 1.4;

    if (useVerticalLayout) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            for (var index = 0; index < rooms.length; index++) ...[
              _FeaturedRoomCard(
                key: ValueKey('discover-featured-${rooms[index].id}'),
                room: rooms[index],
                expandedLayout: true,
                onPressed: () => onRoomPressed(rooms[index]),
              ),
              if (index != rooms.length - 1) const SizedBox(height: 13),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: 222 + ((textScale - 1) * 60),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        physics: const BouncingScrollPhysics(),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 13),
        itemBuilder: (context, index) {
          final room = rooms[index];
          return SizedBox(
            width: 282 + ((textScale - 1) * 40),
            child: _FeaturedRoomCard(
              key: ValueKey('discover-featured-${room.id}'),
              room: room,
              onPressed: () => onRoomPressed(room),
            ),
          );
        },
      ),
    );
  }
}

class _FeaturedRoomCard extends StatelessWidget {
  const _FeaturedRoomCard({
    required this.room,
    required this.onPressed,
    this.expandedLayout = false,
    super.key,
  });

  final VoiceRoom room;
  final VoidCallback onPressed;
  final bool expandedLayout;

  DiscoverCategoryIdentity get _identity =>
      DiscoverCategoryIdentity.forCategory(
        room.category,
        isBroadcast: room.isBroadcast,
      );

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final accent = _identity.seed;
    final palette = context.appPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      key: ValueKey('discover-featured-surface-${room.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(25),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? (room.isBroadcast
                        ? const [Color(0xFF381326), Color(0xFF17101F)]
                        : const [Color(0xFF301643), Color(0xFF17101F)])
                  : [
                      Color.lerp(palette.surfaceRaised, accent, .07)!,
                      palette.surface,
                    ],
            ),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.1), blurRadius: 22),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -35,
                top: -45,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.2),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  mainAxisSize: expandedLayout
                      ? MainAxisSize.min
                      : MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RoomAvatar(
                          imageUrl: room.imageUrl,
                          fallbackText: room.name,
                          accent: accent,
                          size: 48,
                          icon: room.isBroadcast
                              ? Icons.podcasts_rounded
                              : Icons.groups_rounded,
                        ),
                        const Spacer(),
                        const _SmallLiveBadge(),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      room.name,
                      maxLines: expandedLayout ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 17,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      room.description.isEmpty
                          ? localizedHostedBy(copy, room.hostName)
                          : room.description,
                      maxLines: expandedLayout ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    if (expandedLayout)
                      const SizedBox(height: 17)
                    else
                      const Spacer(),
                    _FeaturedRoomFooter(
                      room: room,
                      accent: accent,
                      expandedLayout: expandedLayout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedRoomFooter extends StatelessWidget {
  const _FeaturedRoomFooter({
    required this.room,
    required this.accent,
    required this.expandedLayout,
  });

  final VoiceRoom room;
  final Color accent;
  final bool expandedLayout;

  Widget _host(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        _HostAvatar(
          photoUrl: room.hostPhotoUrl,
          hostName: room.hostName,
          accent: accent,
          size: 26,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            room.hostName,
            maxLines: expandedLayout ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        UserIdentityBadges(
          uid: room.hostId,
          variant: IdentityBadgeVariant.icon,
        ),
      ],
    );
  }

  Widget _audience(BuildContext context) {
    final palette = context.appPalette;
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          room.isBroadcast
              ? Icons.headphones_rounded
              : Icons.people_alt_rounded,
          color: visuals.foreground,
          size: 15,
        ),
        const SizedBox(width: 5),
        Text(
          '${room.participantCount}',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (expandedLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _host(context),
          const SizedBox(height: 10),
          _audience(context),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: _host(context)),
        const SizedBox(width: 8),
        _audience(context),
      ],
    );
  }
}

class _PremiumRoomCard extends StatelessWidget {
  const _PremiumRoomCard({
    required this.room,
    required this.rank,
    required this.style,
    required this.onPressed,
  });

  final VoiceRoom room;
  final int rank;
  final _RoomCardStyle style;
  final VoidCallback onPressed;

  Color get _accent {
    // Matches RoomCardIdentity's accent system (Rooms 2.0): podcast red,
    // community purple family.
    if (room.isBroadcast) {
      return const Color(0xFFFF3E5F);
    }

    switch (style) {
      case _RoomCardStyle.trending:
        return const Color(0xFFFF5C75);
      case _RoomCardStyle.rising:
        return const Color(0xFF57D9A3);
      case _RoomCardStyle.standard:
        return DiscoverCategoryIdentity.chill.seed;
    }
  }

  String _roomTypeLabel(AppLocalizations copy) {
    return room.isBroadcast
        ? copy.text('PODCAST', 'PODCAST')
        : copy.text('COMMUNITY', 'SPOŁECZNOŚĆ');
  }

  String _peopleLabel(AppLocalizations copy) => localizedDiscoverAudience(
    copy,
    count: room.participantCount,
    isBroadcast: room.isBroadcast,
  );

  IconData get _roomIcon {
    return room.isBroadcast ? Icons.podcasts_rounded : Icons.groups_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final accent = _accent;
    final palette = context.appPalette;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final useAccessibleLayout = textScale > 1.4;
    final maximum = room.maxParticipants;
    final occupancy = maximum == null || maximum <= 0
        ? null
        : (room.participantCount / maximum).clamp(0.0, 1.0);
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        _RoomAvatar(
          imageUrl: room.imageUrl,
          fallbackText: room.name,
          accent: accent,
          size: 66,
          icon: _roomIcon,
        ),
        if (style == _RoomCardStyle.trending)
          Positioned(left: -7, top: -7, child: _RankBadge(rank: rank)),
      ],
    );
    final chevron = Icon(
      Icons.chevron_right_rounded,
      color: DiscoverCategoryVisuals.fromSeed(accent, brightness).foreground,
      size: 27,
    );
    final details = _PremiumRoomDetails(
      room: room,
      accent: accent,
      roomTypeLabel: _roomTypeLabel(copy),
      peopleLabel: _peopleLabel(copy),
      roomIcon: _roomIcon,
      occupancy: occupancy,
      useAccessibleLayout: useAccessibleLayout,
    );

    return Material(
      key: ValueKey('discover-room-surface-${room.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? (room.isBroadcast
                        ? const [Color(0xFF321322), Color(0xFF151020)]
                        : const [Color(0xFF29153B), Color(0xFF151020)])
                  : [
                      Color.lerp(palette.surfaceRaised, accent, .06)!,
                      palette.surface,
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.075), blurRadius: 20),
            ],
          ),
          child: useAccessibleLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        avatar,
                        const Spacer(),
                        Semantics(
                          label: copy.text('Open room', 'Otwórz pokój'),
                          child: chevron,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    details,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                    const SizedBox(width: 7),
                    Padding(
                      padding: const EdgeInsets.only(top: 27),
                      child: chevron,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PremiumRoomDetails extends StatelessWidget {
  const _PremiumRoomDetails({
    required this.room,
    required this.accent,
    required this.roomTypeLabel,
    required this.peopleLabel,
    required this.roomIcon,
    required this.occupancy,
    required this.useAccessibleLayout,
  });

  final VoiceRoom room;
  final Color accent;
  final String roomTypeLabel;
  final String peopleLabel;
  final IconData roomIcon;
  final double? occupancy;
  final bool useAccessibleLayout;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
    final statusBadges = <Widget>[
      _TypeBadge(label: roomTypeLabel, icon: roomIcon, accent: accent),
      const _SmallLiveBadge(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (useAccessibleLayout)
          Wrap(spacing: 8, runSpacing: 8, children: statusBadges)
        else
          Row(
            children: [statusBadges.first, const Spacer(), statusBadges.last],
          ),
        const SizedBox(height: 9),
        Text(
          room.name,
          maxLines: useAccessibleLayout ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          room.description.isEmpty
              ? localizedHostedBy(copy, room.hostName)
              : room.description,
          maxLines: useAccessibleLayout ? 4 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            _HostAvatar(
              photoUrl: room.hostPhotoUrl,
              hostName: room.hostName,
              accent: accent,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      room.hostName,
                      maxLines: useAccessibleLayout ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  UserIdentityBadges(
                    uid: room.hostId,
                    variant: IdentityBadgeVariant.icon,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _RoomTag(
              icon: room.isBroadcast
                  ? Icons.headphones_rounded
                  : Icons.people_alt_rounded,
              label: peopleLabel,
            ),
            _RoomTag(icon: Icons.language_rounded, label: room.language),
            _RoomTag(
              icon: Icons.local_offer_rounded,
              label: localizedDiscoverCategory(copy, room.category),
            ),
          ],
        ),
        if (occupancy != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: LinearProgressIndicator(
              value: occupancy,
              minHeight: 4,
              backgroundColor: palette.surfaceSunken,
              color: occupancy! >= 0.9
                  ? const Color(0xFFFF416C)
                  : visuals.foreground,
            ),
          ),
        ],
      ],
    );
  }
}

class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({
    required this.imageUrl,
    required this.fallbackText,
    required this.accent,
    required this.size,
    required this.icon,
  });

  final String? imageUrl;
  final String fallbackText;
  final Color accent;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim();
    final palette = context.appPalette;
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            visuals.surface,
            Color.lerp(visuals.surface, palette.surface, 0.55)!,
          ],
        ),
        border: Border.all(color: visuals.border),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.14), blurRadius: 16),
        ],
      ),
      child: normalizedUrl != null && normalizedUrl.isNotEmpty
          ? Image.network(
              normalizedUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return _RoomAvatarFallback(
                  fallbackText: fallbackText,
                  accent: accent,
                  icon: icon,
                );
              },
            )
          : _RoomAvatarFallback(
              fallbackText: fallbackText,
              accent: accent,
              icon: icon,
            ),
    );
  }
}

class _RoomAvatarFallback extends StatelessWidget {
  const _RoomAvatarFallback({
    required this.fallbackText,
    required this.accent,
    required this.icon,
  });

  final String fallbackText;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final normalized = fallbackText.trim();
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(icon, color: visuals.foreground.withValues(alpha: 0.42), size: 43),
        Text(
          normalized.isEmpty ? 'YV' : normalized[0].toUpperCase(),
          style: TextStyle(
            color: visuals.foreground,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HostAvatar extends StatelessWidget {
  const _HostAvatar({
    required this.photoUrl,
    required this.hostName,
    required this.accent,
    required this.size,
  });

  final String? photoUrl;
  final String hostName;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = photoUrl?.trim();
    final initial = hostName.trim().isEmpty
        ? 'Y'
        : hostName.trim()[0].toUpperCase();
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: visuals.surface,
        border: Border.all(color: visuals.border),
      ),
      child: normalizedUrl != null && normalizedUrl.isNotEmpty
          ? Image.network(
              normalizedUrl,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) {
                return Text(
                  initial,
                  style: TextStyle(
                    color: visuals.onSurface,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w900,
                  ),
                );
              },
            )
          : Text(
              initial,
              style: TextStyle(
                color: visuals.onSurface,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}

class _SmallLiveBadge extends StatelessWidget {
  const _SmallLiveBadge();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF48162A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF416C).withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Color(0xFFFF416C), size: 7),
          const SizedBox(width: 5),
          Text(
            copy.text('LIVE', 'NA ŻYWO'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
    return Container(
      key: ValueKey('discover-type-badge-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: visuals.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visuals.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: visuals.onSurface, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: visuals.onSurface,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.65,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final topRank = rank <= 3;

    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: topRank ? const Color(0xFFFFB84D) : palette.surfaceRaised,
        border: Border.all(
          color: topRank ? const Color(0xFFFFD58A) : palette.border,
        ),
        boxShadow: [
          if (topRank)
            BoxShadow(
              color: const Color(0xFFFFB84D).withValues(alpha: 0.2),
              blurRadius: 10,
            ),
        ],
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: topRank ? const Color(0xFF2B1700) : palette.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RoomTag extends StatelessWidget {
  const _RoomTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.textSecondary, size: 13),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverLoadingState extends StatelessWidget {
  const _DiscoverLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('discover-loading-state'),
      child: SizedBox(
        width: 31,
        height: 31,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState({
    required this.hasFilters,
    required this.nothingIsLive,
    required this.onClear,
  });

  final bool hasFilters;
  final bool nothingIsLive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('discover-empty-state'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(palette.surfaceRaised, colors.primary, .09)!,
                    palette.surface,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.border),
              ),
              child: Icon(
                Icons.explore_off_rounded,
                color: colors.primary,
                size: 37,
              ),
            ),
            const SizedBox(height: 19),
            Text(
              hasFilters && !nothingIsLive
                  ? copy.text('No matching rooms', 'Brak pasujących pokoi')
                  : copy.text(
                      'No rooms are live right now',
                      'Żaden pokój nie jest teraz aktywny',
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters && !nothingIsLive
                  ? copy.text(
                      'Try another search phrase or clear the selected category.',
                      'Spróbuj innej frazy lub wyczyść wybraną kategorię.',
                    )
                  : copy.text(
                      'Live public Community and Podcast rooms will appear here automatically.',
                      'Aktywne publiczne pokoje społecznościowe i podcasty pojawią się tutaj automatycznie.',
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 19),
              FilledButton.icon(
                onPressed: onClear,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 19,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: Text(
                  copy.text('CLEAR FILTERS', 'WYCZYŚĆ FILTRY'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiscoverErrorState extends StatelessWidget {
  const _DiscoverErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('discover-error-state'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: palette.dangerSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.error.withValues(alpha: 0.45)),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                color: colors.error,
                size: 39,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              copy.text(
                'Could not load Discover',
                'Nie udało się wczytać sekcji Odkrywaj',
              ),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverCategory {
  const _DiscoverCategory({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _DiscoverSections {
  const _DiscoverSections({
    required this.hero,
    required this.featured,
    required this.trending,
    required this.rising,
  });

  final VoiceRoom? hero;
  final List<VoiceRoom> featured;
  final List<VoiceRoom> trending;
  final List<VoiceRoom> rising;
}

enum _RoomCardStyle { standard, trending, rising }

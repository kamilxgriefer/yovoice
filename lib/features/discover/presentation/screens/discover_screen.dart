import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/features/discover/presentation/widgets/hero_live_room.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.isRootTab = false, super.key});

  /// True when this screen IS the shell's current content (the desktop
  /// rail's Discover slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never shows a back button that
  /// would have nothing to pop.
  final bool isRootTab;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF151020);
  static const Color _surfaceLight = Color(0xFF21172D);
  static const Color _border = Color(0xFF392B47);
  static const Color _secondaryText = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFFAE35FF);

  static const List<_DiscoverCategory> _categories = [
    _DiscoverCategory(label: 'All', icon: Icons.grid_view_rounded),
    _DiscoverCategory(label: 'Talk', icon: Icons.record_voice_over_rounded),
    _DiscoverCategory(label: 'Music', icon: Icons.music_note_rounded),
    _DiscoverCategory(label: 'Gaming', icon: Icons.sports_esports_rounded),
    _DiscoverCategory(label: 'Chill', icon: Icons.nightlife_rounded),
    _DiscoverCategory(label: 'Study', icon: Icons.school_rounded),
    _DiscoverCategory(label: 'Business', icon: Icons.work_rounded),
  ];

  final RoomService _roomService = RoomService();
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
    try {
      final joinedRoom = await _roomService.joinRoom(room.id);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RoomEntryScreen(room: joinedRoom),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(_readableError(error));
    }
  }

  String _readableError(Object error) {
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return "You don't have permission to do that.";
    }

    if (message.toLowerCase().contains('full')) {
      return 'This room is full.';
    }

    if (message.toLowerCase().contains('no longer live')) {
      return 'This room has already ended.';
    }

    if (message.toLowerCase().contains('not live')) {
      return 'Voice is no longer live in this room.';
    }

    if (message.toLowerCase().contains('unavailable')) {
      return 'This room is currently unavailable.';
    }

    return message
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '')
        .replaceFirst('Exception: ', '');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF481C30),
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
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.86, -0.94),
            radius: 1.28,
            colors: [Color(0xFF35144D), Color(0xFF170C22), _background],
            stops: [0, 0.4, 1],
          ),
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
                    message: _readableError(snapshot.error!),
                  );
                }

                final allRooms = snapshot.data ?? const <VoiceRoom>[];
                final filteredRooms = _filterRooms(allRooms);
                final sections = _createSections(filteredRooms);

                return RefreshIndicator(
                  color: _primary,
                  backgroundColor: _surface,
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
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 14),
          child: _SectionHeader(
            title: 'Search results',
            subtitle:
                '${rooms.length} live ${rooms.length == 1 ? 'room' : 'rooms'}',
            icon: Icons.search_rounded,
            accent: _primary,
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
              title: 'Featured',
              subtitle: 'Rooms selected for you',
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
              title: 'Trending',
              subtitle: 'The busiest conversations right now',
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
              title: 'Rising',
              subtitle: 'Fresh rooms gaining momentum',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!isRootTab) ...[
              YoIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                size: 40,
                backgroundColor: _DiscoverScreenState._surface,
                borderColor: _DiscoverScreenState._border,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
            ],
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discover',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.9,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Find voices worth staying for.',
                    style: TextStyle(
                      color: _DiscoverScreenState._secondaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _LiveRoomCounter(count: liveRoomCount),
          ],
        ),
        const SizedBox(height: 22),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          cursorColor: _DiscoverScreenState._primary,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Search rooms, hosts or topics...',
            hintStyle: const TextStyle(
              color: _DiscoverScreenState._secondaryText,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: _DiscoverScreenState._secondaryText,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }

                return IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    searchController.clear();
                    onSearchChanged('');
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _DiscoverScreenState._secondaryText,
                  ),
                );
              },
            ),
            filled: true,
            fillColor: _DiscoverScreenState._surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: const BorderSide(color: _DiscoverScreenState._border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: const BorderSide(
                color: _DiscoverScreenState._primary,
                width: 1.5,
              ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF401528),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFFF416C).withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF416C).withValues(alpha: 0.12),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Color(0xFFFF416C), size: 9),
          const SizedBox(width: 7),
          Text(
            '$count LIVE',
            style: const TextStyle(
              color: Colors.white,
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
    return SizedBox(
      height: 47,
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
                        color: _DiscoverScreenState._primary.withValues(
                          alpha: 0.22,
                        ),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: selected
                  ? _DiscoverScreenState._primary
                  : _DiscoverScreenState._surface,
              borderRadius: BorderRadius.circular(30),
              child: InkWell(
                onTap: () => onSelected(category.label),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: selected
                          ? _DiscoverScreenState._primary
                          : _DiscoverScreenState._border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(category.icon, color: Colors.white, size: 17),
                      const SizedBox(width: 7),
                      Text(
                        category.label,
                        style: const TextStyle(
                          color: Colors.white,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _DiscoverScreenState._secondaryText,
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
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: accent, size: 20),
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

  Color get _accent {
    if (room.isBroadcast) {
      return const Color(0xFFFF3F8E);
    }

    final category = room.category.toLowerCase();

    if (category.contains('music')) {
      return const Color(0xFFFFA63D);
    }

    if (category.contains('gaming')) {
      return const Color(0xFF4D8DFF);
    }

    if (category.contains('business')) {
      return const Color(0xFF3FD19B);
    }

    return const Color(0xFFA226FF);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;

    return Material(
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
              colors: room.isBroadcast
                  ? const [Color(0xFF381326), Color(0xFF17101F)]
                  : const [Color(0xFF301643), Color(0xFF17101F)],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      room.description.isEmpty
                          ? 'Hosted by ${room.hostName}'
                          : room.description,
                      maxLines: expandedLayout ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _DiscoverScreenState._secondaryText,
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
            style: const TextStyle(
              color: Colors.white70,
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

  Widget _audience() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          room.isBroadcast
              ? Icons.headphones_rounded
              : Icons.people_alt_rounded,
          color: accent,
          size: 15,
        ),
        const SizedBox(width: 5),
        Text(
          '${room.participantCount}',
          style: const TextStyle(
            color: Colors.white,
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
        children: [_host(context), const SizedBox(height: 10), _audience()],
      );
    }

    return Row(
      children: [
        Expanded(child: _host(context)),
        const SizedBox(width: 8),
        _audience(),
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
        return const Color(0xFFA226FF);
    }
  }

  String get _roomTypeLabel {
    return room.isBroadcast ? 'PODCAST' : 'COMMUNITY';
  }

  String get _peopleLabel {
    if (room.isBroadcast) {
      return '${room.participantCount} listening';
    }

    return '${room.participantCount} inside';
  }

  IconData get _roomIcon {
    return room.isBroadcast ? Icons.podcasts_rounded : Icons.groups_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final maximum = room.maxParticipants;
    final occupancy = maximum == null || maximum <= 0
        ? null
        : (room.participantCount / maximum).clamp(0.0, 1.0);

    return Material(
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
              colors: room.isBroadcast
                  ? const [Color(0xFF321322), Color(0xFF151020)]
                  : const [Color(0xFF29153B), Color(0xFF151020)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.46)),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.075), blurRadius: 20),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
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
                    Positioned(
                      left: -7,
                      top: -7,
                      child: _RankBadge(rank: rank),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeBadge(
                          label: _roomTypeLabel,
                          icon: _roomIcon,
                          accent: accent,
                        ),
                        const Spacer(),
                        const _SmallLiveBadge(),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      room.description.isEmpty
                          ? 'Hosted by ${room.hostName}'
                          : room.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _DiscoverScreenState._secondaryText,
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
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
                          label: _peopleLabel,
                        ),
                        _RoomTag(
                          icon: Icons.language_rounded,
                          label: room.language,
                        ),
                        _RoomTag(
                          icon: Icons.local_offer_rounded,
                          label: room.category,
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
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          color: occupancy >= 0.9
                              ? const Color(0xFFFF416C)
                              : accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Padding(
                padding: const EdgeInsets.only(top: 27),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: accent.withValues(alpha: 0.85),
                  size: 27,
                ),
              ),
            ],
          ),
        ),
      ),
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
            accent.withValues(alpha: 0.36),
            accent.withValues(alpha: 0.1),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.72)),
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

    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.18), size: 43),
        Text(
          normalized.isEmpty ? 'YV' : normalized[0].toUpperCase(),
          style: TextStyle(
            color: Color.lerp(Colors.white, accent, 0.15),
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

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.24),
        border: Border.all(color: accent.withValues(alpha: 0.72)),
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
                    color: Colors.white,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w900,
                  ),
                );
              },
            )
          : Text(
              initial,
              style: TextStyle(
                color: Colors.white,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF48162A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF416C).withValues(alpha: 0.65),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Color(0xFFFF416C), size: 7),
          SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
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
    final topRank = rank <= 3;

    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: topRank
            ? const Color(0xFFFFB84D)
            : _DiscoverScreenState._surfaceLight,
        border: Border.all(
          color: topRank
              ? const Color(0xFFFFD58A)
              : _DiscoverScreenState._border,
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
          color: topRank ? const Color(0xFF2B1700) : Colors.white,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _DiscoverScreenState._secondaryText, size: 13),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
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
    return const Center(
      child: SizedBox(
        width: 31,
        height: 31,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: _DiscoverScreenState._primary,
        ),
      ),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState({required this.hasFilters, required this.onClear});

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2E1740), _DiscoverScreenState._surface],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _DiscoverScreenState._border),
              ),
              child: const Icon(
                Icons.explore_off_rounded,
                color: _DiscoverScreenState._primary,
                size: 37,
              ),
            ),
            const SizedBox(height: 19),
            Text(
              hasFilters ? 'No matching rooms' : 'No live rooms yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try another search phrase or clear the selected category.'
                  : 'Live public Community and Podcast rooms will appear here automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _DiscoverScreenState._secondaryText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 19),
              FilledButton.icon(
                onPressed: onClear,
                style: FilledButton.styleFrom(
                  backgroundColor: _DiscoverScreenState._primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 19,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text(
                  'CLEAR FILTERS',
                  style: TextStyle(
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF311421),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFFF6B81).withValues(alpha: 0.45),
                ),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFFF6B81),
                size: 39,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Could not load Discover',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _DiscoverScreenState._secondaryText,
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

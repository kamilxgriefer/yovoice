import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

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
    _DiscoverCategory('All', Icons.grid_view_rounded),
    _DiscoverCategory('Talk', Icons.record_voice_over_rounded),
    _DiscoverCategory('Music', Icons.music_note_rounded),
    _DiscoverCategory('Gaming', Icons.sports_esports_rounded),
    _DiscoverCategory('Chill', Icons.nightlife_rounded),
    _DiscoverCategory('Study', Icons.school_rounded),
    _DiscoverCategory('Business', Icons.work_rounded),
  ];

  final RoomService _roomService = RoomService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  String _query = '';
  String _selectedCategory = 'All';

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

  Future<void> _openRoom(VoiceRoom room) async {
    try {
      final joinedRoom = await _roomService.joinRoom(room.id);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RoomScreen(room: joinedRoom),
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
      return 'Firestore blocked this action. Final security rules still need to be deployed.';
    }

    if (message.toLowerCase().contains('full')) {
      return 'This room is full.';
    }

    if (message.toLowerCase().contains('no longer live')) {
      return 'This room has already ended.';
    }

    return message
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
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
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  List<VoiceRoom> _filteredRooms(List<VoiceRoom> rooms) {
    final filtered = rooms.where((room) {
      final matchesCategory = _selectedCategory == 'All' ||
          room.category.toLowerCase() == _selectedCategory.toLowerCase();

      if (!matchesCategory) {
        return false;
      }

      if (_query.isEmpty) {
        return true;
      }

      final haystack = [
        room.name,
        room.description,
        room.category,
        room.language,
        room.hostName,
      ].join(' ').toLowerCase();

      return haystack.contains(_query);
    }).toList();

    filtered.sort((a, b) {
      final countComparison =
          b.participantCount.compareTo(a.participantCount);

      if (countComparison != 0) {
        return countComparison;
      }

      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return bDate.compareTo(aDate);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.95),
            radius: 1.25,
            colors: [
              Color(0xFF301346),
              Color(0xFF130C1D),
              _background,
            ],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: StreamBuilder<List<VoiceRoom>>(
            stream: _roomService.watchLivePublicRooms(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _DiscoverErrorState(
                  message: _readableError(snapshot.error!),
                );
              }

              final allRooms = snapshot.data ?? const <VoiceRoom>[];
              final rooms = _filteredRooms(allRooms);

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
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                        child: _DiscoverHeader(
                          searchController: _searchController,
                          onSearchChanged: _onSearchChanged,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20),
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 26, 18, 13),
                        child: _SectionHeader(
                          title: _query.isNotEmpty
                              ? 'Search results'
                              : _selectedCategory == 'All'
                                  ? 'Trending now'
                                  : _selectedCategory,
                          subtitle: _query.isNotEmpty
                              ? '${rooms.length} matching rooms'
                              : 'Live conversations happening right now',
                        ),
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _DiscoverLoadingState(),
                      )
                    else if (rooms.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _DiscoverEmptyState(
                          hasFilters:
                              _query.isNotEmpty || _selectedCategory != 'All',
                          onClear: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _selectedCategory = 'All';
                            });
                          },
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
                        sliver: SliverList.separated(
                          itemCount: rooms.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 13),
                          itemBuilder: (context, index) {
                            final room = rooms[index];

                            return _DiscoverRoomCard(
                              room: room,
                              rank: index + 1,
                              onPressed: () => _openRoom(room),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discover',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Find your next conversation.',
                    style: TextStyle(
                      color: _DiscoverScreenState._secondaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _LiveIndicator(),
          ],
        ),
        const SizedBox(height: 21),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Search rooms, topics, languages...',
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
                  tooltip: 'Clear',
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
              vertical: 17,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: _DiscoverScreenState._border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
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

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF401528),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFF416C)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            color: Color(0xFFFF416C),
            size: 9,
          ),
          SizedBox(width: 7),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
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
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.label == selectedCategory;

          return Material(
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
                    Icon(
                      category.icon,
                      color: Colors.white,
                      size: 17,
                    ),
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
  });

  final String title;
  final String subtitle;

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
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _DiscoverScreenState._secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.auto_awesome_rounded,
          color: Color(0xFFFFB020),
          size: 21,
        ),
      ],
    );
  }
}

class _DiscoverRoomCard extends StatelessWidget {
  const _DiscoverRoomCard({
    required this.room,
    required this.rank,
    required this.onPressed,
  });

  final VoiceRoom room;
  final int rank;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(room.category);
    final icon = _categoryIcon(room.category);
    final max = room.maxParticipants;
    final occupancy = max == null || max <= 0
        ? null
        : (room.participantCount / max).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: _DiscoverScreenState._surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _DiscoverScreenState._border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.17),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  if (rank <= 3)
                    Positioned(
                      left: -7,
                      top: -7,
                      child: Container(
                        width: 23,
                        height: 23,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? const Color(0xFFFFB020)
                              : _DiscoverScreenState._surfaceLight,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _DiscoverScreenState._border,
                          ),
                        ),
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            color: rank == 1
                                ? const Color(0xFF241300)
                                : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
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
                        Expanded(
                          child: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.circle,
                          color: Color(0xFFFF416C),
                          size: 8,
                        ),
                      ],
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
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _RoomTag(
                          icon: Icons.people_alt_rounded,
                          label: '${room.participantCount} listening',
                        ),
                        _RoomTag(
                          icon: Icons.language_rounded,
                          label: room.language,
                        ),
                        _RoomTag(
                          icon: icon,
                          label: _categoryLabel(room.category),
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
                          backgroundColor: _DiscoverScreenState._surfaceLight,
                          color: occupancy >= 0.9
                              ? const Color(0xFFFF416C)
                              : _DiscoverScreenState._primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 7),
              const Padding(
                padding: EdgeInsets.only(top: 17),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: _DiscoverScreenState._secondaryText,
                  size: 27,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _categoryLabel(String category) {
    if (category.trim().isEmpty) {
      return 'Talk';
    }

    final value = category.trim();

    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  static IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return Icons.music_note_rounded;
      case 'gaming':
        return Icons.sports_esports_rounded;
      case 'chill':
        return Icons.nightlife_rounded;
      case 'study':
        return Icons.school_rounded;
      case 'business':
        return Icons.work_rounded;
      case 'talk':
      default:
        return Icons.record_voice_over_rounded;
    }
  }

  static Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return const Color(0xFFFF4C68);
      case 'gaming':
        return const Color(0xFF6682FF);
      case 'chill':
        return const Color(0xFF3ED0A7);
      case 'study':
        return const Color(0xFFFFB04B);
      case 'business':
        return const Color(0xFF4CAEFF);
      case 'talk':
      default:
        return const Color(0xFFB348FF);
    }
  }
}

class _RoomTag extends StatelessWidget {
  const _RoomTag({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: _DiscoverScreenState._surfaceLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: _DiscoverScreenState._secondaryText,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
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
        width: 30,
        height: 30,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: _DiscoverScreenState._primary,
        ),
      ),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState({
    required this.hasFilters,
    required this.onClear,
  });

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 15, 28, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _DiscoverScreenState._surface,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: _DiscoverScreenState._border),
              ),
              child: const Icon(
                Icons.explore_off_rounded,
                color: _DiscoverScreenState._primary,
                size: 35,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters ? 'No matching rooms' : 'No live rooms yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              hasFilters
                  ? 'Try a different search or clear your filters.'
                  : 'Active public rooms will appear here automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _DiscoverScreenState._secondaryText,
                height: 1.4,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onClear,
                style: FilledButton.styleFrom(
                  backgroundColor: _DiscoverScreenState._primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Clear filters',
                  style: TextStyle(fontWeight: FontWeight.w800),
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
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFFF6B81),
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load Discover',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _DiscoverScreenState._secondaryText,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverCategory {
  const _DiscoverCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

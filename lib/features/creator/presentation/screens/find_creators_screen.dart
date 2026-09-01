import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/creator/data/models/creator_search_result.dart';
import 'package:yovoice/features/creator/data/services/creator_directory_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

enum _CreatorFilter { allCreators, verified }

class FindCreatorsScreen extends StatefulWidget {
  const FindCreatorsScreen({
    this.isRootTab = false,
    this.directoryService,
    this.followService,
    this.onOpenCreator,
    super.key,
  });

  final bool isRootTab;
  final CreatorDirectoryService? directoryService;
  final FollowService? followService;
  final ValueChanged<CreatorSearchResult>? onOpenCreator;

  @override
  State<FindCreatorsScreen> createState() => _FindCreatorsScreenState();
}

class _FindCreatorsScreenState extends State<FindCreatorsScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF14101D);
  static const _surfaceRaised = Color(0xFF1B1326);
  static const _border = Color(0xFF342742);
  static const _muted = Color(0xFFA69CAF);
  static const _accent = Color(0xFFB348FF);

  late final CreatorDirectoryService _directory;
  late final FollowService _follows;
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<CreatorSearchResult> _results = const [];
  _CreatorFilter _filter = _CreatorFilter.allCreators;
  bool _searching = false;
  String? _error;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _directory = widget.directoryService ?? CreatorDirectoryService();
    _follows = widget.followService ?? FollowService();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _requestVersion += 1;
    final query = value.trim();
    setState(() {
      _error = null;
      if (query.length < 2) {
        _results = const [];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (query.length < 2) return;
    _debounce = Timer(
      const Duration(milliseconds: 420),
      () => _search(query, _requestVersion),
    );
  }

  Set<CreatorDirectoryAccountType> get _requestedTypes => switch (_filter) {
    _CreatorFilter.allCreators => const {
      CreatorDirectoryAccountType.creator,
      CreatorDirectoryAccountType.official,
    },
    _CreatorFilter.verified => const {CreatorDirectoryAccountType.official},
  };

  Future<void> _search(String query, int requestVersion) async {
    try {
      final results = await _directory.searchCreators(
        query,
        accountTypes: _requestedTypes,
      );
      if (!mounted ||
          _searchController.text.trim() != query ||
          requestVersion != _requestVersion) {
        return;
      }
      setState(() {
        _results = results;
        _searching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted ||
          _searchController.text.trim() != query ||
          requestVersion != _requestVersion) {
        return;
      }
      setState(() {
        _results = const [];
        _searching = false;
        _error = intentionalOrFriendly(
          error,
          fallback: 'Creator search is temporarily unavailable.',
        );
      });
    }
  }

  List<CreatorSearchResult> get _visibleResults => switch (_filter) {
    _CreatorFilter.allCreators => _results,
    _CreatorFilter.verified =>
      _results.where((item) => item.isVerified).toList(growable: false),
  };

  void _openCreator(CreatorSearchResult creator) {
    final injected = widget.onOpenCreator;
    if (injected != null) {
      injected(creator);
      return;
    }
    unawaited(
      showProfilePreview(
        context,
        userId: creator.uid,
        displayName: creator.displayName,
        photoUrl: creator.photoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      backgroundColor: _background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.85, -1),
            radius: 1.15,
            colors: [Color(0xFF26103B), Color(0xFF100A19), _background],
            stops: [0, .42, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => ResponsiveContentFrame(
              width: ResponsiveContentWidth.list,
              alignment: ResponsiveContentAlignment.topLeft,
              padding: ResponsiveContentFrame.adaptivePagePadding(
                constraints.maxWidth,
              ),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          showBack: !widget.isRootTab,
                          onBack: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(height: 12),
                        _SearchPanel(
                          controller: _searchController,
                          searching: _searching,
                          onChanged: _onQueryChanged,
                          onClear: () {
                            _debounce?.cancel();
                            _requestVersion += 1;
                            _searchController.clear();
                            setState(() {
                              _results = const [];
                              _searching = false;
                              _error = null;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _FilterBar(
                          selected: _filter,
                          onSelected: _selectFilter,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  ..._buildResultSlivers(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }

  void _selectFilter(_CreatorFilter value) {
    if (value == _filter) return;
    _debounce?.cancel();
    _requestVersion += 1;
    final requestVersion = _requestVersion;
    final query = _searchController.text.trim();
    setState(() {
      _filter = value;
      _error = null;
      if (query.length >= 2) _searching = true;
    });
    if (query.length >= 2) unawaited(_search(query, requestVersion));
  }

  List<Widget> _buildResultSlivers() {
    final query = _searchController.text.trim();
    if (_searching) {
      return const [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 160,
            child: Center(
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 32),
            child: _DirectoryState(
              icon: Icons.wifi_off_rounded,
              title: 'Search is taking a break',
              subtitle: _error!,
            ),
          ),
        ),
      ];
    }
    if (query.length < 2) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 18, bottom: 32),
            child: _DirectoryState(
              icon: Icons.auto_awesome_rounded,
              title: 'Find a voice worth following',
              subtitle:
                  'Search by display name or @username. Verified creators '
                  'are marked with a YO Voice badge.',
            ),
          ),
        ),
      ];
    }
    final results = _visibleResults;
    if (results.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 32),
            child: _DirectoryState(
              icon: Icons.person_search_rounded,
              title: _filter == _CreatorFilter.verified
                  ? 'No verified creators found'
                  : 'No creators found',
              subtitle: _filter == _CreatorFilter.verified
                  ? 'Try another name or view all creators.'
                  : 'Try another name or @username.',
            ),
          ),
        ),
      ];
    }
    return [
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final useGrid = width >= 760 && textScale <= 1.3;
          if (!useGrid) {
            return SliverPadding(
              padding: const EdgeInsets.only(bottom: 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => index.isOdd
                      ? const SizedBox(height: 10)
                      : _resultCard(results[index ~/ 2]),
                  childCount: results.length * 2 - 1,
                ),
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.only(bottom: 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 228,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _resultCard(results[index]),
                childCount: results.length,
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _resultCard(CreatorSearchResult creator) => _CreatorResultCard(
    key: ValueKey('creator-${creator.uid}'),
    creator: creator,
    followService: _follows,
    onOpen: () => _openCreator(creator),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.showBack, required this.onBack});

  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack) ...[
            IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: Colors.white,
            ),
            const SizedBox(width: 4),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find creators',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Discover people building conversations, shows and communities.',
                  style: TextStyle(
                    color: _FindCreatorsScreenState._muted,
                    fontSize: 14,
                    height: 1.35,
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

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.searching,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool searching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _FindCreatorsScreenState._surfaceRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _FindCreatorsScreenState._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        key: const ValueKey('find-creators-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search creators by name or @username',
          hintStyle: const TextStyle(color: Color(0xFF83798F)),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFFC69BEA),
          ),
          suffixIcon: searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _FindCreatorsScreenState._accent,
                    ),
                  ),
                )
              : controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: _FindCreatorsScreenState._surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: _FindCreatorsScreenState._border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: _FindCreatorsScreenState._accent,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final _CreatorFilter selected;
  final ValueChanged<_CreatorFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChip(
          filterKey: const ValueKey('creator-filter-all'),
          label: 'All creators',
          semanticLabel: 'All creators filter',
          selected: selected == _CreatorFilter.allCreators,
          onTap: () => onSelected(_CreatorFilter.allCreators),
        ),
        _FilterChip(
          filterKey: const ValueKey('creator-filter-verified'),
          label: 'Verified',
          semanticLabel: 'Verified creators filter',
          selected: selected == _CreatorFilter.verified,
          onTap: () => onSelected(_CreatorFilter.verified),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filterKey,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final Key filterKey;
  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AccessibleTapRegion(
      key: filterKey,
      semanticLabel: semanticLabel,
      selected: selected,
      onTap: onTap,
      borderRadius: 999,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: selected
                  ? _FindCreatorsScreenState._accent.withValues(alpha: .18)
                  : _FindCreatorsScreenState._surface,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected
                      ? _FindCreatorsScreenState._accent
                      : _FindCreatorsScreenState._border,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFFE0B9FF)
                        : _FindCreatorsScreenState._muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreatorResultCard extends StatefulWidget {
  const _CreatorResultCard({
    required this.creator,
    required this.followService,
    required this.onOpen,
    super.key,
  });

  final CreatorSearchResult creator;
  final FollowService followService;
  final VoidCallback onOpen;

  @override
  State<_CreatorResultCard> createState() => _CreatorResultCardState();
}

class _CreatorResultCardState extends State<_CreatorResultCard> {
  bool _busy = false;

  Future<void> _toggle(bool following) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (following) {
        await widget.followService.unfollow(widget.creator.uid);
      } else {
        await widget.followService.follow(widget.creator.uid);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback: 'The follow action could not be completed.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creator = widget.creator;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return StreamBuilder<bool>(
      stream: widget.followService.watchIsFollowing(creator.uid),
      initialData: false,
      builder: (context, snapshot) {
        final following = snapshot.data ?? false;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560 || textScale > 1.35;
            final denseGridCard = constraints.hasBoundedHeight;
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  radius: compact ? 25 : 29,
                  userId: creator.uid,
                  photoUrl: creator.photoUrl,
                  displayName: creator.displayName,
                  premium: creator.premiumIdentity,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            creator.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          _CreatorStatusBadge(uid: creator.uid),
                          if (creator.isVerified)
                            _VerifiedCreatorBadge(uid: creator.uid),
                        ],
                      ),
                      if (creator.username.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          '@${creator.username}',
                          style: const TextStyle(
                            color: Color(0xFFC0B6CA),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      SizedBox(height: denseGridCard ? 4 : 7),
                      Text(
                        creator.supportingText,
                        maxLines: denseGridCard ? 1 : (compact ? 3 : 2),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _FindCreatorsScreenState._muted,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: denseGridCard ? 4 : 7),
                      Text(
                        _followersLabel(creator.followerCount),
                        style: const TextStyle(
                          color: Color(0xFFD3A5FF),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final viewProfileButton = OutlinedButton(
              onPressed: widget.onOpen,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                foregroundColor: WidgetStatePropertyAll(
                  _FindCreatorsScreenState._accent,
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(color: _FindCreatorsScreenState._accent),
                ),
              ),
              child: const Text('View profile'),
            );
            final followButton = FilledButton.icon(
              onPressed: _busy ? null : () => _toggle(following),
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 44)),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      following
                          ? Icons.check_rounded
                          : Icons.person_add_alt_1_rounded,
                      size: 18,
                    ),
              label: Text(following ? 'Following' : 'Follow'),
            );
            final actions = textScale > 1.35
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      viewProfileButton,
                      const SizedBox(height: 8),
                      followButton,
                    ],
                  )
                : Row(
                    mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      if (compact)
                        Expanded(child: viewProfileButton)
                      else
                        viewProfileButton,
                      const SizedBox(width: 8),
                      if (compact)
                        Expanded(child: followButton)
                      else
                        followButton,
                    ],
                  );

            return Material(
              color: _FindCreatorsScreenState._surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _FindCreatorsScreenState._border),
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            if (denseGridCard)
                              const Spacer()
                            else
                              const SizedBox(height: 14),
                            actions,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: identity),
                            const SizedBox(width: 18),
                            actions,
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _followersLabel(int count) {
    if (count == 1) return '1 follower';
    return '$count followers';
  }
}

class _CreatorStatusBadge extends StatelessWidget {
  const _CreatorStatusBadge({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return _IdentityBadge(
      key: ValueKey('creator-status-$uid'),
      icon: Icons.auto_awesome_rounded,
      label: 'Creator',
      semanticLabel: 'Creator account',
      color: const Color(0xFFD59BFF),
    );
  }
}

class _VerifiedCreatorBadge extends StatelessWidget {
  const _VerifiedCreatorBadge({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return _IdentityBadge(
      key: ValueKey('verified-status-$uid'),
      icon: Icons.verified_rounded,
      label: 'Verified',
      semanticLabel: 'Verified by YO Voice',
      color: const Color(0xFF67D8FF),
    );
  }
}

class _IdentityBadge extends StatelessWidget {
  const _IdentityBadge({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: enlargedText ? 2 : 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: .55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .25,
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

class _DirectoryState extends StatelessWidget {
  const _DirectoryState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          decoration: BoxDecoration(
            color: _FindCreatorsScreenState._surface.withValues(alpha: .8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _FindCreatorsScreenState._border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _FindCreatorsScreenState._accent, size: 34),
              const SizedBox(height: 13),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _FindCreatorsScreenState._muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

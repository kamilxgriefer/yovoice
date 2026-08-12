import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart'
    show MomentCard;
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The MOBILE Home — "Voice Briefing".
///
/// Same information hierarchy as the desktop Pulse Home, rebuilt at phone
/// proportions per `assets/images/home mobile.png`: compact header, a
/// one-line live briefing, a featured room, a Your circle / Your Moment
/// pair, the recommended list, then the existing Moments feed.
///
/// Every number and face is real:
///  - live rooms + counts → [RoomService.watchLivePublicRooms]
///  - rosters / avatars / speaking → [RoomService.watchParticipants]
///  - friends + presence → [FriendService.watchFriends]
///  - feed → [HomeFeedService.watchSocialMoments] rendered by the shared
///    [MomentCard] (no second feed implementation)
///  - identity → [ProfileService.watchCurrentProfile]
class MobileHome extends StatefulWidget {
  const MobileHome({
    required this.onOpenRoom,
    required this.onOpenDiscover,
    required this.onOpenFriends,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    required this.onCreateMoment,
    required this.onOpenComments,
    this.roomService,
    this.friendService,
    this.profileService,
    this.feedService,
    this.followService,
    this.currentUserId,
    super.key,
  });

  final ValueChanged<VoiceRoom> onOpenRoom;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenFriends;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;
  final VoidCallback onCreateMoment;
  final ValueChanged<VoiceMoment> onOpenComments;

  final RoomService? roomService;
  final FriendService? friendService;
  final ProfileService? profileService;
  final HomeFeedService? feedService;

  /// Injected in tests for the same reason the others are: production
  /// passes nothing and resolves its own, which needs a Firebase app.
  final FollowService? followService;

  /// The signed-in uid. Optional so tests need no Firebase app.
  final String? currentUserId;

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  RoomService? _rooms;
  Stream<List<VoiceRoom>>? _liveRooms;
  Stream<List<FriendUser>>? _friends;
  Stream<UserProfile>? _profile;
  Stream<List<VoiceMoment>>? _feed;
  Stream<List<FollowUser>>? _following;

  /// uids seen in the rosters of the rooms currently on screen — the only
  /// truthful source for "in conversation", since presence documents
  /// carry no room context.
  final Set<String> _peopleInRooms = <String>{};
  final Map<String, StreamSubscription<List<RoomParticipant>>> _rosterSubs =
      <String, StreamSubscription<List<RoomParticipant>>>{};

  int _featuredPage = 0;

  @override
  void initState() {
    super.initState();
    try {
      _rooms = widget.roomService ?? RoomService();
      _liveRooms = _rooms!.watchLivePublicRooms();
    } catch (_) {
      _rooms = null;
    }
    try {
      _friends = (widget.friendService ?? FriendService()).watchFriends();
    } catch (_) {
      _friends = null;
    }
    try {
      _profile = (widget.profileService ?? ProfileService())
          .watchCurrentProfile();
    } catch (_) {
      _profile = null;
    }
    try {
      _feed = (widget.feedService ?? HomeFeedService()).watchSocialMoments();
    } catch (_) {
      _feed = null;
    }
    try {
      final uid = _resolvedUserId;
      _following = uid.isEmpty
          ? null
          : (widget.followService ?? FollowService()).watchFollowing(uid);
    } catch (_) {
      _following = null;
    }
  }

  @override
  void dispose() {
    for (final sub in _rosterSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  void _syncRosters(List<VoiceRoom> shown) {
    final ids = shown.map((room) => room.id).toSet();
    for (final id in _rosterSubs.keys.toList()) {
      if (!ids.contains(id)) _rosterSubs.remove(id)?.cancel();
    }
    for (final room in shown) {
      if (_rosterSubs.containsKey(room.id) || _rooms == null) continue;
      _rosterSubs[room.id] = _rooms!.watchParticipants(room.id).listen((
        participants,
      ) {
        if (!mounted) return;
        setState(() {
          _peopleInRooms.addAll(participants.map((p) => p.userId));
        });
      }, onError: (_) {});
    }
  }

  String get _resolvedUserId {
    final injected = widget.currentUserId;
    if (injected != null) return injected;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  void _openPremium() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
    );
  }

  void _openCreator(FollowUser creator) {
    showProfilePreview(
      context,
      userId: creator.uid,
      displayName: creator.displayName,
      photoUrl: creator.photoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VoiceRoom>>(
      stream: _liveRooms,
      builder: (context, snapshot) {
        final live = snapshot.data ?? const <VoiceRoom>[];
        final featured = live.take(3).toList(growable: false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncRosters(featured);
        });

        return StreamBuilder<List<FriendUser>>(
          stream: _friends,
          builder: (context, friendSnapshot) {
            final friends = friendSnapshot.data ?? const <FriendUser>[];
            final onlineCount = friends.where((f) => f.isOnline).length;
            final inConversation = friends
                .where((f) => _peopleInRooms.contains(f.id))
                .length;

            return ListView(
              // Top inset clears the status bar / notch (the shell's
              // mobile body is not wrapped in a SafeArea), and the bottom
              // inset clears the floating hub bar so the last card is
              // never trapped underneath it.
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + 10,
                16,
                128,
              ),
              children: [
                _MobileHeader(
                  profile: _profile,
                  onNotifications: widget.onOpenNotifications,
                  onProfile: widget.onOpenProfile,
                ),
                const SizedBox(height: 16),
                _BriefingStrip(
                  liveRooms: live.length,
                  friendsOnline: onlineCount,
                  rooms: featured,
                  roomService: _rooms,
                ),
                // Mobile Home mirrors desktop Home's composition in one
                // vertical feed, in mobile-native shapes over the same
                // services.
                StreamBuilder<List<VoiceMoment>>(
                  stream: _feed,
                  builder: (context, momentSnapshot) => MobileMomentsStrip(
                    moments: momentSnapshot.data ?? const <VoiceMoment>[],
                    profile: null,
                    currentUserId: _resolvedUserId,
                    onOpenMoment: widget.onOpenComments,
                    onCreateMoment: widget.onCreateMoment,
                    onDiscover: widget.onOpenDiscover,
                  ),
                ),
                MobileLiveRail(
                  rooms: live,
                  onOpenRoom: widget.onOpenRoom,
                  onSeeAll: widget.onOpenDiscover,
                ),
                const SizedBox(height: 14),
                _FeaturedCarousel(
                  rooms: featured,
                  roomService: _rooms,
                  page: _featuredPage,
                  onPageChanged: (page) => setState(() => _featuredPage = page),
                  onJoin: widget.onOpenRoom,
                  onDiscover: widget.onOpenDiscover,
                ),
                const SizedBox(height: 14),
                _CircleAndMomentRow(
                  friends: friends,
                  onlineCount: onlineCount,
                  inConversation: inConversation,
                  onSeeAll: widget.onOpenFriends,
                  onCreateMoment: widget.onCreateMoment,
                ),
                const SizedBox(height: 20),
                _RecommendedNow(
                  rooms: live,
                  roomService: _rooms,
                  onOpen: widget.onOpenRoom,
                  onSeeAll: widget.onOpenDiscover,
                ),
                const SizedBox(height: 20),
                StreamBuilder<List<FollowUser>>(
                  stream: _following,
                  builder: (context, followSnapshot) {
                    final creators =
                        followSnapshot.data ?? const <FollowUser>[];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MobileVoiceTrending(
                          rooms: live,
                          creators: creators,
                          onOpenRoom: widget.onOpenRoom,
                          onOpenCreator: _openCreator,
                          onSeeAll: widget.onOpenDiscover,
                        ),
                        const SizedBox(height: 14),
                        MobilePremiumCard(onCheckPlans: _openPremium),
                        const SizedBox(height: 14),
                        MobileTopCreators(
                          creators: creators,
                          onOpenCreator: _openCreator,
                          onViewAll: widget.onOpenFriends,
                          onDiscover: widget.onOpenDiscover,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                const SponsoredCard(),
                const SizedBox(height: 20),
                _FeedSection(
                  feed: _feed,
                  onOpenComments: widget.onOpenComments,
                  onFindPeople: widget.onOpenFriends,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ------------------------------------------------------------- header

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.profile,
    required this.onNotifications,
    required this.onProfile,
  });

  final Stream<UserProfile>? profile;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  static String _partOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: profile,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _partOfDay(),
                    style: const TextStyle(
                      color: Color(0xFF9A90AC),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data?.displayName.trim().isNotEmpty == true
                        ? data!.displayName.trim()
                        : 'Welcome',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _CircleIconButton(
              icon: Icons.notifications_none_rounded,
              onTap: onNotifications,
              tooltip: 'Notifications',
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onProfile,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                ),
                child: UserAvatar(
                  radius: 21,
                  photoUrl: data?.photoUrl,
                  displayName: data?.displayName,
                  fallbackIcon: Icons.person_rounded,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E2140)),
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

// ---------------------------------------------------- briefing strip

class _BriefingStrip extends StatelessWidget {
  const _BriefingStrip({
    required this.liveRooms,
    required this.friendsOnline,
    required this.rooms,
    required this.roomService,
  });

  final int liveRooms;
  final int friendsOnline;
  final List<VoiceRoom> rooms;
  final RoomService? roomService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF120C1D).withValues(alpha: .8),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Row(
        children: [
          if (rooms.isNotEmpty)
            _RoomAvatarStack(room: rooms.first, roomService: roomService),
          if (rooms.isNotEmpty) const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$liveRooms ',
                    style: const TextStyle(
                      color: Color(0xFFB07BFF),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: liveRooms == 1 ? 'room live' : 'rooms live',
                    style: const TextStyle(color: Color(0xFFCFC6DC)),
                  ),
                  const TextSpan(
                    text: '  ·  ',
                    style: TextStyle(color: Color(0xFF6C6280)),
                  ),
                  TextSpan(
                    text: '$friendsOnline ',
                    style: const TextStyle(
                      color: Color(0xFFB07BFF),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(
                    text: 'friends online',
                    style: TextStyle(color: Color(0xFFCFC6DC)),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          // Static mark: real per-room audio levels only exist once you
          // are inside a room, so this never pretends to be a live meter.
          _Waveform(bars: 14, height: 18, active: liveRooms > 0),
        ],
      ),
    );
  }
}

/// The first faces actually in a room.
class _RoomAvatarStack extends StatelessWidget {
  const _RoomAvatarStack({required this.room, required this.roomService});

  final VoiceRoom room;
  final RoomService? roomService;

  static const double radius = 13;
  static const int max = 3;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomParticipant>>(
      stream: roomService?.watchParticipants(room.id),
      builder: (context, snapshot) {
        final people = (snapshot.data ?? const <RoomParticipant>[])
            .take(max)
            .toList(growable: false);
        if (people.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: radius * 2,
          width: radius * 2 + (people.length - 1) * radius * 1.3,
          child: Stack(
            children: [
              for (var i = 0; i < people.length; i++)
                Positioned(
                  left: i * radius * 1.3,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0B0713),
                        width: 1.6,
                      ),
                    ),
                    child: UserAvatar(
                      radius: radius,
                      photoUrl: people[i].photoUrl,
                      displayName: people[i].displayName,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({this.bars = 20, this.height = 22, this.active = true});

  final int bars;
  final double height;
  final bool active;

  static const _pattern = <double>[
    .35,
    .7,
    .45,
    .9,
    .5,
    .3,
    .75,
    .55,
    .95,
    .4,
    .65,
    .3,
    .6,
    .8,
    .45,
    .55,
    .35,
    .5,
    .7,
    .4,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: bars * 4.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                width: 2,
                height: height * _pattern[i % _pattern.length],
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: AppColors.primary.withValues(alpha: active ? .6 : .25),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------ featured room

class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({
    required this.rooms,
    required this.roomService,
    required this.page,
    required this.onPageChanged,
    required this.onJoin,
    required this.onDiscover,
  });

  final List<VoiceRoom> rooms;
  final RoomService? roomService;
  final int page;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<VoiceRoom> onJoin;
  final VoidCallback onDiscover;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  final PageController _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rooms.isEmpty) {
      return _FeaturedEmpty(onDiscover: widget.onDiscover);
    }

    return Column(
      children: [
        SizedBox(
          height: 232,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.rooms.length,
            onPageChanged: widget.onPageChanged,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(
                right: index == widget.rooms.length - 1 ? 0 : 8,
              ),
              child: _FeaturedCard(
                room: widget.rooms[index],
                roomService: widget.roomService,
                onJoin: () => widget.onJoin(widget.rooms[index]),
              ),
            ),
          ),
        ),
        if (widget.rooms.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.rooms.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == widget.page ? 18 : 8,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: i == widget.page
                        ? AppColors.primary
                        : const Color(0xFF3A2A52),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.room,
    required this.roomService,
    required this.onJoin,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final VoidCallback onJoin;

  static const _gradients = <List<Color>>[
    [Color(0xFF6D28D9), Color(0xFF9333EA)],
    [Color(0xFF7C3AED), Color(0xFFC026FF)],
    [Color(0xFF4C1D95), Color(0xFF7E22CE)],
  ];

  @override
  Widget build(BuildContext context) {
    final cover = room.imageUrl?.trim();
    final fallback = _gradients[room.id.hashCode.abs() % _gradients.length];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF150E22),
        border: Border.all(color: AppColors.primary.withValues(alpha: .4)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover on the right, faded into the surface so the text side
          // stays readable — a gradient when the room has no cover.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 190,
            child: cover == null || cover.isEmpty
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          fallback.first.withValues(alpha: .85),
                          fallback.last.withValues(alpha: .25),
                        ],
                      ),
                    ),
                  )
                : Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: fallback),
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF150E22),
                    const Color(0xFF150E22).withValues(alpha: .92),
                    const Color(0xFF150E22).withValues(alpha: .18),
                  ],
                  stops: const [0, .45, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: .55),
                        ),
                      ),
                      child: const Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Color(0xFFD3A5FF),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const _LivePill(),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.4,
                        ),
                      ),
                      if (room.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          room.description.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB3A8C4),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                StreamBuilder<List<RoomParticipant>>(
                  stream: roomService?.watchParticipants(room.id),
                  builder: (context, snapshot) {
                    final people = snapshot.data ?? const <RoomParticipant>[];
                    final speaking = people
                        .where((p) => p.isSpeaker && !p.isMuted)
                        .length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FacePile(people: people, total: room.participantCount),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // The counts shrink before the Join action
                            // does — narrow phones must never clip the CTA.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.people_alt_rounded,
                                      size: 14,
                                      color: Color(0xFFB07BFF),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${room.participantCount} listening',
                                      style: const TextStyle(
                                        color: Color(0xFFCFC6DC),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (speaking > 0) ...[
                                      const Text(
                                        '  ·  ',
                                        style: TextStyle(
                                          color: Color(0xFF6C6280),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.graphic_eq_rounded,
                                        size: 14,
                                        color: Color(0xFFB07BFF),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '$speaking speaking',
                                        style: const TextStyle(
                                          color: Color(0xFFCFC6DC),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _JoinPill(onTap: onJoin),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FacePile extends StatelessWidget {
  const _FacePile({required this.people, required this.total});

  final List<RoomParticipant> people;
  final int total;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList(growable: false);
    if (shown.isEmpty) return const SizedBox(height: 34);
    final overflow = total - shown.length;

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            height: 34,
            width: 34 + (shown.length - 1) * 24,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF150E22),
                          width: 2,
                        ),
                      ),
                      child: UserAvatar(
                        radius: 15,
                        photoUrl: shown[i].photoUrl,
                        displayName: shown[i].displayName,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (overflow > 0) ...[
            const SizedBox(width: 6),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .06),
                border: Border.all(color: const Color(0xFF3A2A52)),
              ),
              child: Text(
                '+$overflow',
                style: const TextStyle(
                  color: Color(0xFFCFC6DC),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFFF335C),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _JoinPill extends StatelessWidget {
  const _JoinPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .38),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Join',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedEmpty extends StatelessWidget {
  const _FeaturedEmpty({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF150E22),
        border: Border.all(color: AppColors.primary.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing is live right now',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'When someone opens a room it appears here first.',
            style: TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onDiscover,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: .5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text(
              'Explore Discover',
              style: TextStyle(
                color: Color(0xFFD3A5FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------- circle + moment cards

class _CirclimeCardShell extends StatelessWidget {
  const _CirclimeCardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF120C1D).withValues(alpha: .8),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: child,
    );
  }
}

class _CircleAndMomentRow extends StatelessWidget {
  const _CircleAndMomentRow({
    required this.friends,
    required this.onlineCount,
    required this.inConversation,
    required this.onSeeAll,
    required this.onCreateMoment,
  });

  final List<FriendUser> friends;
  final int onlineCount;
  final int inConversation;
  final VoidCallback onSeeAll;
  final VoidCallback onCreateMoment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final circle = _YourCircleCard(
          friends: friends,
          onlineCount: onlineCount,
          inConversation: inConversation,
          onSeeAll: onSeeAll,
        );
        final moment = _YourMomentCard(onTap: onCreateMoment);

        // Very narrow phones read better stacked than as two thin cards.
        if (constraints.maxWidth < 340) {
          return Column(children: [circle, const SizedBox(height: 12), moment]);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: circle),
              const SizedBox(width: 12),
              Expanded(child: moment),
            ],
          ),
        );
      },
    );
  }
}

class _YourCircleCard extends StatelessWidget {
  const _YourCircleCard({
    required this.friends,
    required this.onlineCount,
    required this.inConversation,
    required this.onSeeAll,
  });

  final List<FriendUser> friends;
  final int onlineCount;
  final int inConversation;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return _CirclimeCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your circle',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                child: const Text(
                  'See all',
                  style: TextStyle(
                    color: Color(0xFFD3A5FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (friends.isEmpty)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'No friends yet — find people to hear what they are in.',
                style: TextStyle(
                  color: Color(0xFF9A90AC),
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                for (final friend in friends.take(4))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        UserAvatar(
                          radius: 18,
                          photoUrl: friend.photoUrl,
                          displayName: friend.displayName,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: friend.isOnline
                                  ? const Color(0xFF35D07F)
                                  : const Color(0xFF564C63),
                              border: Border.all(
                                color: const Color(0xFF120C1D),
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _CircleStat(
              dotColor: const Color(0xFF35D07F),
              text:
                  '$onlineCount ${onlineCount == 1 ? 'friend' : 'friends'} '
                  'online',
            ),
            if (inConversation > 0) ...[
              const SizedBox(height: 5),
              _CircleStat(
                icon: Icons.graphic_eq_rounded,
                text: '$inConversation in conversation',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CircleStat extends StatelessWidget {
  const _CircleStat({required this.text, this.dotColor, this.icon});

  final String text;
  final Color? dotColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (dotColor != null)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          )
        else if (icon != null)
          Icon(icon, size: 13, color: const Color(0xFFB07BFF)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFCFC6DC), fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _YourMomentCard extends StatelessWidget {
  const _YourMomentCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _CirclimeCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your Moment',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: .6),
                    width: 1.6,
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Color(0xFFE879F9),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Share a thought or\nstart a room',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9A90AC),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------- recommended now

class _RecommendedNow extends StatelessWidget {
  const _RecommendedNow({
    required this.rooms,
    required this.roomService,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<VoiceRoom> rooms;
  final RoomService? roomService;
  final ValueChanged<VoiceRoom> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recommended now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                  color: Color(0xFFD3A5FF),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final room in rooms.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RecommendedRow(
              room: room,
              roomService: roomService,
              onTap: () => onOpen(room),
            ),
          ),
      ],
    );
  }
}

class _RecommendedRow extends StatelessWidget {
  const _RecommendedRow({
    required this.room,
    required this.roomService,
    required this.onTap,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final VoidCallback onTap;

  static const _gradients = <List<Color>>[
    [Color(0xFF6D28D9), Color(0xFF9333EA)],
    [Color(0xFF7C3AED), Color(0xFFC026FF)],
    [Color(0xFF4C1D95), Color(0xFF7E22CE)],
    [Color(0xFF9D174D), Color(0xFFC026FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final cover = room.imageUrl?.trim();
    final fallback = _gradients[room.id.hashCode.abs() % _gradients.length];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF120C1D).withValues(alpha: .8),
          border: Border.all(color: const Color(0xFF241A33)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 58,
                height: 58,
                child: cover == null || cover.isEmpty
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: fallback,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      )
                    : Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: fallback),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 11),
            // Two columns, not three: at real phone widths a separate
            // trailing column for counts + Join cannot fit beside the
            // thumbnail and the text, so they sit on their own line.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(child: _CategoryChip(room.category)),
                      if (room.isLive) ...[
                        const SizedBox(width: 6),
                        const _LivePill(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (room.description.trim().isNotEmpty)
                    Text(
                      room.description.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9A90AC),
                        fontSize: 11.5,
                      ),
                    ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<RoomParticipant>>(
                    stream: roomService?.watchParticipants(room.id),
                    builder: (context, snapshot) {
                      final people = snapshot.data ?? const <RoomParticipant>[];
                      final speaking = people
                          .where((p) => p.isSpeaker && !p.isMuted)
                          .length;
                      return Row(
                        children: [
                          const Icon(
                            Icons.people_alt_rounded,
                            size: 12,
                            color: Color(0xFFB07BFF),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${room.participantCount}',
                            style: const TextStyle(
                              color: Color(0xFFCFC6DC),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (speaking > 0) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.graphic_eq_rounded,
                              size: 12,
                              color: Color(0xFFB07BFF),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$speaking',
                              style: const TextStyle(
                                color: Color(0xFFCFC6DC),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const Spacer(),
                          _JoinOutline(onTap: onTap),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.primary.withValues(alpha: .16),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFD3A5FF),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _JoinOutline extends StatelessWidget {
  const _JoinOutline({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.primary.withValues(alpha: .5)),
          ),
          child: const Text(
            'Join',
            style: TextStyle(
              color: Color(0xFFD3A5FF),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------- the feed

class _FeedSection extends StatelessWidget {
  const _FeedSection({
    required this.feed,
    required this.onOpenComments,
    required this.onFindPeople,
  });

  final Stream<List<VoiceMoment>>? feed;
  final ValueChanged<VoiceMoment> onOpenComments;
  final VoidCallback onFindPeople;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VoiceMoment>>(
      stream: feed,
      builder: (context, snapshot) {
        final moments = snapshot.data ?? const <VoiceMoment>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'From your people',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            if (moments.isEmpty)
              // Compact, actionable — not a full-viewport empty panel.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFF120C1D).withValues(alpha: .7),
                  border: Border.all(color: const Color(0xFF241A33)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'No Moments yet from people you follow.',
                        style: TextStyle(
                          color: Color(0xFF9A90AC),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: onFindPeople,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Find people',
                        style: TextStyle(
                          color: Color(0xFFD3A5FF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              // The SHARED card — same playback, reactions and comment
              // action the Moments screen uses. No second feed.
              for (final moment in moments.take(6))
                MomentCard(
                  moment: moment,
                  onComments: () => onOpenComments(moment),
                ),
          ],
        );
      },
    );
  }
}

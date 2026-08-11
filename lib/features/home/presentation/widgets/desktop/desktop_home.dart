import 'dart:async';

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_conversations.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// "Pulse Home" — the DESKTOP Home surface.
///
/// Every module reads existing production data; nothing here invents a
/// user, a room, a message or an activity number:
///  - live rooms           → [RoomService.watchLivePublicRooms]
///  - rosters / avatars     → [RoomService.watchParticipants] per shown room
///  - friends & presence    → [FriendService.watchFriends]
///  - greeting identity     → [ProfileService.watchCurrentProfile]
///  - Moments from the circle → [HomeFeedService.watchSocialMoments]
///  - Conversations         → [MessageService.watchConversations] +
///    [ClubService.watchMyClubs] (see [DesktopConversations])
///
/// Presence in Firestore carries no room context, so "In a room · X" is
/// derived by matching a friend's uid against the rosters this screen
/// already loads — real, or not shown at all.
///
/// Navigation is delegated: the callbacks below are wired by MainShell
/// to the SAME fixed-shell content-slot mechanism the rail uses, so
/// nothing here pushes a route except entering a room, opening a chat or
/// a club — the flows that already own their full-screen route
/// everywhere else in the app.
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    required this.currentUserId,
    required this.onOpenRoom,
    required this.onSeeAllRooms,
    required this.onViewAllFriends,
    required this.onStartRoom,
    required this.onOpenMoment,
    required this.onCreateMoment,
    required this.onSeeAllMoments,
    required this.onOpenConversation,
    required this.onOpenClub,
    required this.onSeeAllChats,
    required this.onOpenClubs,
    this.roomService,
    this.friendService,
    this.profileService,
    this.feedService,
    this.messageService,
    this.clubService,
    this.clubChatService,
    this.globalChatService,
    this.firebaseAuth,
    super.key,
  });

  final String currentUserId;

  final ValueChanged<VoiceRoom> onOpenRoom;

  /// Discover — also the destination behind every "go find something"
  /// action in the empty states.
  final VoidCallback onSeeAllRooms;
  final VoidCallback onViewAllFriends;
  final VoidCallback onStartRoom;

  /// The existing Moment viewer, creation flow and Moments destination.
  final ValueChanged<VoiceMoment> onOpenMoment;
  final VoidCallback onCreateMoment;
  final VoidCallback onSeeAllMoments;

  /// The existing chat screen, club surface, Chats and Clubs destinations.
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<Club> onOpenClub;
  final VoidCallback onSeeAllChats;
  final VoidCallback onOpenClubs;

  final RoomService? roomService;
  final FriendService? friendService;
  final ProfileService? profileService;
  final HomeFeedService? feedService;
  final MessageService? messageService;
  final ClubService? clubService;
  final ClubChatService? clubChatService;
  final GlobalChatService? globalChatService;
  final FirebaseAuth? firebaseAuth;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  RoomService? _rooms;
  Stream<List<VoiceRoom>>? _liveRooms;
  Stream<List<FriendUser>>? _friends;
  Stream<UserProfile>? _profile;

  /// uid → the live room that person is currently in. Filled only from
  /// rosters actually loaded for the rooms on screen.
  final Map<String, String> _friendRoomNames = <String, String>{};
  final Map<String, StreamSubscription<List<RoomParticipant>>> _rosterSubs =
      <String, StreamSubscription<List<RoomParticipant>>>{};

  @override
  void initState() {
    super.initState();
    // Each dependency is optional at runtime: Home must degrade to empty
    // states rather than throw when a service cannot be constructed.
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
  }

  @override
  void dispose() {
    for (final sub in _rosterSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Keeps one roster listener per room currently shown, so the friend
  /// cross-reference costs nothing beyond the avatars already needed.
  void _syncRosters(List<VoiceRoom> shown) {
    final ids = shown.map((room) => room.id).toSet();
    for (final id in _rosterSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _rosterSubs.remove(id)?.cancel();
        _friendRoomNames.removeWhere((_, name) => true);
      }
    }
    for (final room in shown) {
      if (_rosterSubs.containsKey(room.id) || _rooms == null) continue;
      _rosterSubs[room.id] = _rooms!.watchParticipants(room.id).listen((
        participants,
      ) {
        if (!mounted) return;
        setState(() {
          _friendRoomNames.removeWhere((_, name) => name == room.name);
          for (final participant in participants) {
            _friendRoomNames[participant.userId] = room.name;
          }
        });
      }, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VoiceRoom>>(
      stream: _liveRooms,
      builder: (context, snapshot) {
        final live = snapshot.data ?? const <VoiceRoom>[];
        final preview = live.take(3).toList(growable: false);
        final featured = live.isEmpty ? null : live.first;
        final forYou = live.skip(1).take(2).toList(growable: false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncRosters(preview);
        });

        return LayoutBuilder(
          builder: (context, constraints) {
            // Below this the featured panel and Your circle stack
            // instead of squeezing into two thin columns.
            final sideBySide = constraints.maxWidth >= 720;

            final circle = _YourCircle(
              friends: _friends,
              roomNames: _friendRoomNames,
              onViewAll: widget.onViewAllFriends,
              onFindFriends: widget.onSeeAllRooms,
            );

            // One spacing scale for the whole surface, so the section
            // boundaries line up with the right column instead of each
            // module inventing its own rhythm.
            const gap = SizedBox(height: 22);

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 20, 28),
              children: [
                _GreetingHeader(profile: _profile),
                const SizedBox(height: 20),
                DesktopMomentsStrip(
                  profile: _profile,
                  feedService: widget.feedService,
                  onOpenMoment: widget.onOpenMoment,
                  onCreateMoment: widget.onCreateMoment,
                  onSeeAll: widget.onSeeAllMoments,
                  onDiscover: widget.onSeeAllRooms,
                ),
                gap,
                _LiveAroundYou(
                  rooms: preview,
                  roomService: _rooms,
                  onOpen: widget.onOpenRoom,
                  onSeeAll: widget.onSeeAllRooms,
                ),
                const SizedBox(height: 16),
                if (sideBySide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _FeaturedLive(
                            room: featured,
                            roomService: _rooms,
                            onJoin: widget.onOpenRoom,
                            onCreateRoom: widget.onStartRoom,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(width: 316, child: circle),
                      ],
                    ),
                  )
                else ...[
                  _FeaturedLive(
                    room: featured,
                    roomService: _rooms,
                    onJoin: widget.onOpenRoom,
                    onCreateRoom: widget.onStartRoom,
                  ),
                  const SizedBox(height: 16),
                  circle,
                ],
                // "For you" hides entirely when there is nothing to
                // recommend, and takes its gap with it.
                if (forYou.isNotEmpty) ...[
                  gap,
                  _ForYou(
                    rooms: forYou,
                    roomService: _rooms,
                    onOpen: widget.onOpenRoom,
                    onSeeAll: widget.onSeeAllRooms,
                  ),
                ],
                gap,
                DesktopConversations(
                  currentUserId: widget.currentUserId,
                  messageService: widget.messageService,
                  clubService: widget.clubService,
                  clubChatService: widget.clubChatService,
                  friendService: widget.friendService,
                  globalChatService: widget.globalChatService,
                  firebaseAuth: widget.firebaseAuth,
                  onOpenConversation: widget.onOpenConversation,
                  onOpenClub: widget.onOpenClub,
                  onSeeAllChats: widget.onSeeAllChats,
                  onFindFriends: widget.onViewAllFriends,
                  onOpenClubs: widget.onOpenClubs,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------- header

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.profile});

  final Stream<UserProfile>? profile;

  static String _partOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: profile,
      builder: (context, snapshot) {
        final name = snapshot.data?.displayName.trim() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? _partOfDay() : '${_partOfDay()}, $name',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Here is what sounds good right now.',
              style: TextStyle(color: Color(0xFF9A90AC), fontSize: 13.5),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------- section heading

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.subtitle,
    this.onSeeAll,
    this.live = false,
    this.trailingIcon,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final bool live;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE879F9),
                        ),
                      ),
                    ],
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 7),
                      Icon(
                        trailingIcon,
                        size: 14,
                        color: const Color(0xFFD3A5FF),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Color(0xFF9A90AC),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onSeeAll != null) _SeeAllButton(onTap: onSeeAll!),
        ],
      ),
    );
  }
}

class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'See all',
            style: TextStyle(
              color: Color(0xFFD3A5FF),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 3),
          Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFD3A5FF)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------- shared pieces

/// A room's identity tile: its cover when it has one, otherwise a stable
/// gradient derived from the room id — a design-system fallback, never a
/// stock photo.
class _RoomVisual extends StatelessWidget {
  const _RoomVisual({required this.room, this.size = 56, this.radius = 14});

  final VoiceRoom room;
  final double size;
  final double radius;

  static const _gradients = <List<Color>>[
    [Color(0xFF6D28D9), Color(0xFF9333EA)],
    [Color(0xFF7C3AED), Color(0xFFC026FF)],
    [Color(0xFF4C1D95), Color(0xFF7E22CE)],
    [Color(0xFF9D174D), Color(0xFFC026FF)],
  ];

  List<Color> get _fallback =>
      _gradients[room.id.hashCode.abs() % _gradients.length];

  @override
  Widget build(BuildContext context) {
    final cover = room.imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: cover == null || cover.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _fallback,
                  ),
                ),
              )
            : Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _fallback),
                  ),
                ),
              ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFFF335C).withValues(alpha: .16),
        border: Border.all(
          color: const Color(0xFFFF335C).withValues(alpha: .45),
        ),
      ),
      child: Text(
        'LIVE',
        style: TextStyle(
          color: const Color(0xFFFF7A93),
          fontSize: compact ? 9 : 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

/// Overlapping avatars for the people actually in a room.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({
    required this.participants,
    required this.total,
    this.radius = 12,
  });

  final List<RoomParticipant> participants;
  final int total;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shown = participants.take(3).toList(growable: false);
    if (shown.isEmpty) return const SizedBox.shrink();
    final overflow = total - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: radius * 2,
          width: radius * 2 + (shown.length - 1) * (radius * 1.35),
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * radius * 1.35,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0C0814),
                        width: 1.6,
                      ),
                    ),
                    child: UserAvatar(
                      radius: radius,
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
          Text(
            '+$overflow',
            style: const TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

/// Listener count with the product's audio mark.
class _ListenerCount extends StatelessWidget {
  const _ListenerCount({required this.count, this.label = false});

  final int count;
  final bool label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.graphic_eq_rounded,
          size: 14,
          color: Color(0xFFB07BFF),
        ),
        const SizedBox(width: 5),
        Text(
          label ? '$count listening' : '$count',
          style: const TextStyle(
            color: Color(0xFFCFC6DC),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A room's roster, or an empty list when it cannot be read.
class _Roster extends StatelessWidget {
  const _Roster({
    required this.roomId,
    required this.roomService,
    required this.builder,
  });

  final String roomId;
  final RoomService? roomService;
  final Widget Function(BuildContext, List<RoomParticipant>) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomParticipant>>(
      stream: roomService?.watchParticipants(roomId),
      builder: (context, snapshot) =>
          builder(context, snapshot.data ?? const <RoomParticipant>[]),
    );
  }
}

// -------------------------------------------------- 2. Live around you

class _LiveAroundYou extends StatelessWidget {
  const _LiveAroundYou({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: 'Live around you',
          live: true,
          onSeeAll: onSeeAll,
        ),
        if (rooms.isEmpty)
          const _QuietState(text: 'No public rooms are live right now.')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              // Three across the centre column is the intended shape, but
              // near the 1100px shell breakpoint three equal cards would
              // be ~140px each — every room name reduced to an ellipsis.
              // Below that floor the row scrolls at a readable card width
              // instead, so no room is dropped and none is unreadable.
              final perCard = (constraints.maxWidth - gap * 2) / 3;
              if (perCard >= _LivePreviewCard.minWidth) {
                return Row(
                  children: [
                    for (var i = 0; i < rooms.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Expanded(
                        child: _LivePreviewCard(
                          room: rooms[i],
                          roomService: roomService,
                          onTap: () => onOpen(rooms[i]),
                        ),
                      ),
                    ],
                    // Keeps the row's rhythm when fewer than three are
                    // live.
                    for (var i = rooms.length; i < 3; i++) ...[
                      const SizedBox(width: gap),
                      const Expanded(child: SizedBox()),
                    ],
                  ],
                );
              }

              return SizedBox(
                height: _LivePreviewCard.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(width: gap),
                  itemBuilder: (context, index) => SizedBox(
                    width: _LivePreviewCard.minWidth,
                    child: _LivePreviewCard(
                      room: rooms[index],
                      roomService: roomService,
                      onTap: () => onOpen(rooms[index]),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _LivePreviewCard extends StatefulWidget {
  const _LivePreviewCard({
    required this.room,
    required this.roomService,
    required this.onTap,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final VoidCallback onTap;

  /// Below this a room name is nothing but an ellipsis, so the row
  /// scrolls at this width rather than shrinking past it.
  static const double minWidth = 194;

  /// Only used by the scrolling variant, which needs a bounded height.
  static const double height = 98;

  @override
  State<_LivePreviewCard> createState() => _LivePreviewCardState();
}

class _LivePreviewCardState extends State<_LivePreviewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final topic = room.description.trim().isNotEmpty
        ? room.description.trim()
        : room.category;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hover
                ? const Color(0xFF171024).withValues(alpha: .92)
                : const Color(0xFF120C1D).withValues(alpha: .75),
            border: Border.all(
              color: _hover
                  ? AppColors.primary.withValues(alpha: .45)
                  : const Color(0xFF241A33),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoomVisual(room: room, size: 52, radius: 13),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      // Near the 1100px shell breakpoint these three
                      // cards get narrow enough that the pill would eat
                      // the whole title. The section heading already says
                      // "Live around you" and carries the live dot, so
                      // the name wins the space.
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (constraints.maxWidth >= 118) ...[
                            const SizedBox(width: 6),
                            const _LivePill(compact: true),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9A90AC),
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 9),
                    _Roster(
                      roomId: room.id,
                      roomService: widget.roomService,
                      builder: (context, participants) => LayoutBuilder(
                        // Three equal cards get narrow near the 1100px
                        // desktop breakpoint. The count is the fact worth
                        // keeping; the avatar stack steps aside for it
                        // instead of overflowing the card.
                        builder: (context, constraints) => Row(
                          children: [
                            if (constraints.maxWidth >= 108)
                              _AvatarStack(
                                participants: participants,
                                total: room.participantCount,
                                radius: 11,
                              ),
                            const Spacer(),
                            _ListenerCount(count: room.participantCount),
                          ],
                        ),
                      ),
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

// --------------------------------------------------- 3. Featured live

class _FeaturedLive extends StatelessWidget {
  const _FeaturedLive({
    required this.room,
    required this.roomService,
    required this.onJoin,
    required this.onCreateRoom,
  });

  final VoiceRoom? room;
  final RoomService? roomService;
  final ValueChanged<VoiceRoom> onJoin;
  final VoidCallback onCreateRoom;

  @override
  Widget build(BuildContext context) {
    final featured = room;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1030).withValues(alpha: .95),
            const Color(0xFF0E0A18).withValues(alpha: .95),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .10),
            blurRadius: 34,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: featured == null
          ? _FeaturedEmpty(onCreateRoom: onCreateRoom)
          : _FeaturedContent(
              room: featured,
              roomService: roomService,
              onJoin: () => onJoin(featured),
            ),
    );
  }
}

class _FeaturedContent extends StatelessWidget {
  const _FeaturedContent({
    required this.room,
    required this.roomService,
    required this.onJoin,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    // Topic chips only from tags the room actually has.
    final chips = <String>[
      if (room.category.trim().isNotEmpty) room.category.trim(),
      if (room.language.trim().isNotEmpty) room.language.trim(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'FEATURED LIVE',
              style: TextStyle(
                color: Color(0xFFE879F9),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE879F9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                  if (room.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      room.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB3A8C4),
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [for (final chip in chips) _TopicChip(chip)],
                    ),
                  ],
                  const SizedBox(height: 14),
                  _ListenerCount(count: room.participantCount, label: true),
                  const SizedBox(height: 16),
                  _JoinRoomButton(onTap: onJoin),
                ],
              ),
            ),
            const SizedBox(width: 18),
            // The people, not a decorative orb.
            _Roster(
              roomId: room.id,
              roomService: roomService,
              builder: (context, participants) => _SpeakerCluster(
                participants: participants,
                hostId: room.hostId,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: .04),
        border: Border.all(color: const Color(0xFF3A2A52)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFCFC6DC),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Up to four real participants in a loose cluster. Exactly one carries
/// the violet ring: the host if they are unmuted, else the first
/// unmuted speaker — the closest truthful signal available for a room
/// this user has not joined (live audio levels only exist once inside).
class _SpeakerCluster extends StatelessWidget {
  const _SpeakerCluster({required this.participants, required this.hostId});

  final List<RoomParticipant> participants;
  final String hostId;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox(width: 176);

    final ordered = [...participants]
      ..sort((a, b) {
        int rank(RoomParticipant p) => p.isHost ? 0 : (p.isSpeaker ? 1 : 2);
        return rank(a).compareTo(rank(b));
      });
    final shown = ordered.take(4).toList(growable: false);

    final speaking = shown.firstWhere(
      (p) => p.isHost && !p.isMuted,
      orElse: () => shown.firstWhere(
        (p) => p.isSpeaker && !p.isMuted,
        orElse: () => shown.first,
      ),
    );

    // Hand-placed offsets: a group of people, not points on a circle.
    const spots = <Offset>[
      Offset(0, 6),
      Offset(96, 0),
      Offset(12, 84),
      Offset(104, 92),
    ];

    return SizedBox(
      width: 176,
      height: 156,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: spots[i].dx,
              top: spots[i].dy,
              child: _ClusterAvatar(
                participant: shown[i],
                speaking: identical(shown[i], speaking),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Waveform(active: !speaking.isMuted),
          ),
        ],
      ),
    );
  }
}

class _ClusterAvatar extends StatelessWidget {
  const _ClusterAvatar({required this.participant, required this.speaking});

  final RoomParticipant participant;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking
              ? AppColors.primary
              : Colors.white.withValues(alpha: .10),
          width: speaking ? 2.2 : 1.4,
        ),
        boxShadow: speaking
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: .45),
                  blurRadius: 18,
                ),
              ]
            : const [],
      ),
      child: UserAvatar(
        radius: 25,
        photoUrl: participant.photoUrl,
        displayName: participant.displayName,
      ),
    );
  }
}

/// A compact audio-activity mark. Deliberately a fixed silhouette: real
/// per-room amplitude is only available once you are inside the room,
/// and animating an invented one would be fiction.
class _Waveform extends StatelessWidget {
  const _Waveform({this.active = true});

  final bool active;

  static const _bars = <double>[
    .30,
    .55,
    .38,
    .72,
    .48,
    .30,
    .62,
    .44,
    .80,
    .36,
    .58,
    .28,
    .50,
    .68,
    .40,
    .54,
    .32,
    .46,
    .64,
    .34,
    .52,
    .26,
    .44,
    .60,
    .38,
    .48,
    .30,
    .56,
    .42,
    .28,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final bar in _bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: .9),
                child: Container(
                  height: 30 * bar,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: AppColors.primary.withValues(
                      alpha: active ? .55 : .22,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _JoinRoomButton extends StatelessWidget {
  const _JoinRoomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .35),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Join room',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedEmpty extends StatelessWidget {
  const _FeaturedEmpty({required this.onCreateRoom});

  final VoidCallback onCreateRoom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing is live yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Be the first voice today — open a room and your people '
            'will see it here.',
            style: TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onCreateRoom,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: .55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: const Icon(
              Icons.add_rounded,
              size: 17,
              color: Color(0xFFD3A5FF),
            ),
            label: const Text(
              'Create Room',
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

// ----------------------------------------------------- 4. Your circle

class _YourCircle extends StatelessWidget {
  const _YourCircle({
    required this.friends,
    required this.roomNames,
    required this.onViewAll,
    required this.onFindFriends,
  });

  final Stream<List<FriendUser>>? friends;
  final Map<String, String> roomNames;
  final VoidCallback onViewAll;

  /// The empty state's single action — Discover, inside the shell.
  final VoidCallback onFindFriends;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF120C1D).withValues(alpha: .75),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: StreamBuilder<List<FriendUser>>(
        stream: friends,
        builder: (context, snapshot) {
          final people = snapshot.data ?? const <FriendUser>[];
          final online = people.where((person) => person.isOnline).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The header used to share this row with a "Start a room"
              // button that duplicated the rail's Create Room. The
              // recovered width goes to the list instead: a real count of
              // who is actually online, then more of the people
              // themselves.
              Row(
                children: [
                  const Text(
                    'Your circle',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 9),
                  if (people.isNotEmpty)
                    Flexible(
                      child: Text(
                        online > 0 ? '$online online' : '${people.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: online > 0
                              ? const Color(0xFF35D07F)
                              : const Color(0xFF7E7895),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (people.isEmpty)
                _NoFriendsState(onFindFriends: onFindFriends)
              else
                // One more face than before now that the button is gone.
                for (final person in people.take(6))
                  _CirclePerson(person: person, roomName: roomNames[person.id]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all friends',
                        style: TextStyle(
                          color: Color(0xFFD3A5FF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFFD3A5FF),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Nobody in the circle yet. The card says what will land here and
/// offers one existing way to fill it — room creation lives in the rail's
/// Create Room button, not in a second button here.
class _NoFriendsState extends StatelessWidget {
  const _NoFriendsState({required this.onFindFriends});

  final VoidCallback onFindFriends;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: .02),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No friends yet — once you add people, you will see who is '
            'online and which room they are in.',
            style: TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onFindFriends,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: .45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Find people',
              style: TextStyle(
                color: Color(0xFFD3A5FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CirclePerson extends StatelessWidget {
  const _CirclePerson({required this.person, this.roomName});

  final FriendUser person;
  final String? roomName;

  @override
  Widget build(BuildContext context) {
    // Only states the data can actually prove.
    final inRoom = roomName != null;
    final (dotColor, stateLabel) = inRoom
        ? (const Color(0xFF35D07F), 'In a room')
        : person.isOnline
        ? (const Color(0xFF35D07F), 'Online')
        : (const Color(0xFF564C63), 'Offline');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Stack(
            children: [
              UserAvatar(
                radius: 16,
                photoUrl: person.photoUrl,
                displayName: person.displayName,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: Border.all(
                      color: const Color(0xFF120C1D),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  stateLabel,
                  style: const TextStyle(
                    color: Color(0xFF9A90AC),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (inRoom)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    size: 12,
                    color: Color(0xFFB07BFF),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      roomName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB07BFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

// --------------------------------------------------------- 5. For you

class _ForYou extends StatelessWidget {
  const _ForYou({
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
        _SectionHeading(
          title: 'For you',
          subtitle: 'Rooms we think you will enjoy',
          trailingIcon: Icons.auto_awesome_rounded,
          onSeeAll: onSeeAll,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Two columns only while each card stays wide enough for a
            // cover plus a readable text block; below that they stack
            // rather than shrink into unreadable slivers.
            final twoUp = constraints.maxWidth >= 620;
            final cards = [
              for (final room in rooms)
                _ForYouCard(
                  key: ValueKey(room.id),
                  room: room,
                  roomService: roomService,
                  onTap: () => onOpen(room),
                ),
            ];

            if (!twoUp) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: cards[i]),
                ],
                // A single recommendation keeps its column width rather
                // than stretching across the row.
                if (cards.length == 1) ...[
                  const SizedBox(width: 14),
                  const Expanded(child: SizedBox()),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A recommendation, as an editorial card rather than a poster.
///
/// The old version was a 148px slab filled edge-to-edge with the room's
/// fallback gradient, a giant translucent circle and two lines of text —
/// bright, low-information and indistinguishable from the next one. This
/// one is dark glass like the rest of Home, spends its violet on the
/// cover, the LIVE state, the border and the CTA, and carries what
/// actually decides whether you join: who hosts it, what it is about, its
/// category and language, who is already inside and how many are
/// listening. Every one of those is a real field — anything the room
/// does not have is simply not drawn.
class _ForYouCard extends StatefulWidget {
  const _ForYouCard({
    required this.room,
    required this.roomService,
    required this.onTap,
    super.key,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final VoidCallback onTap;

  static const double height = 158;
  static const double coverSize = 130;

  @override
  State<_ForYouCard> createState() => _ForYouCardState();
}

class _ForYouCardState extends State<_ForYouCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final topic = room.description.trim();
    final chips = <String>[
      if (room.category.trim().isNotEmpty) room.category.trim(),
      if (room.language.trim().isNotEmpty) room.language.trim(),
    ];
    final host = room.hostName.trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: _ForYouCard.height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: _hover
                ? const Color(0xFF171024).withValues(alpha: .95)
                : const Color(0xFF120C1D).withValues(alpha: .78),
            border: Border.all(
              color: _hover
                  ? AppColors.primary.withValues(alpha: .50)
                  : const Color(0xFF241A33),
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: .14),
                      blurRadius: 26,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _RoomVisual(
                    room: room,
                    size: _ForYouCard.coverSize,
                    radius: 14,
                  ),
                  if (room.isLive)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: _LivePill(compact: true),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.2,
                      ),
                    ),
                    if (host.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.mic_rounded,
                            size: 12,
                            color: Color(0xFFB07BFF),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB3A8C4),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (topic.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9A90AC),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _ChipRow(chips: chips),
                    ],
                    const Spacer(),
                    _Roster(
                      roomId: room.id,
                      roomService: widget.roomService,
                      builder: (context, participants) => LayoutBuilder(
                        builder: (context, constraints) => Row(
                          children: [
                            if (constraints.maxWidth >= 190)
                              _AvatarStack(
                                participants: participants,
                                total: room.participantCount,
                                radius: 10,
                              ),
                            const Spacer(),
                            _ListenerCount(count: room.participantCount),
                            const SizedBox(width: 10),
                            _JoinChip(hovered: _hover, onTap: widget.onTap),
                          ],
                        ),
                      ),
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

/// Category/language chips on one line — anything that does not fit is
/// dropped rather than wrapped into a second row the card has no height
/// for.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});

  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _MiniChip(chips[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: .04),
        border: Border.all(color: const Color(0xFF3A2A52)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Color(0xFFCFC6DC),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _JoinChip extends StatelessWidget {
  const _JoinChip({required this.hovered, required this.onTap});

  final bool hovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: hovered
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  )
                : null,
            color: hovered ? null : AppColors.primary.withValues(alpha: .16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: hovered ? .0 : .45),
            ),
          ),
          child: Text(
            'Join',
            style: TextStyle(
              color: hovered ? Colors.white : const Color(0xFFD3A5FF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- shared states

class _QuietState extends StatelessWidget {
  const _QuietState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: .02),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9A90AC),
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

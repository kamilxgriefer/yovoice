import 'dart:async';

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// "Pulse Home" — the DESKTOP Home surface.
///
/// Every module reads existing production data; nothing here invents a
/// user, a room, a message or an activity number:
///  - the room board        → [RoomService.watchLivePublicRooms]
///  - face piles / rosters  → [RoomService.watchParticipants] per banner
///  - board ranking         → [FollowService.watchFollowing]
///  - `Your active rooms`   → [RoomService.watchOwnedRooms]
///  - greeting identity     → [ProfileService.watchCurrentProfile]
///  - Moments from the circle → [HomeFeedService.watchSocialMoments]
///  - recent chats preview → [MessageService.watchConversations] plus the
///    current public avatar from [ProfileService.watchProfile]
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
    this.onFindCreators,
    required this.onViewAllFriends,
    required this.onStartRoom,
    required this.onOpenMoment,
    required this.onCreateMoment,
    required this.onSeeAllMoments,
    this.onOpenOwnChain,
    required this.onOpenConversation,
    required this.onOpenClub,
    required this.onSeeAllChats,
    required this.onOpenClubs,
    this.roomService,
    this.friendService,
    this.followService,
    this.profileService,
    this.feedService,
    this.messageService,
    this.clubService,
    this.clubChatService,
    this.firebaseAuth,
    this.capabilityService,
    this.trailingContent,
    super.key,
  });

  final String currentUserId;

  final ValueChanged<VoiceRoom> onOpenRoom;

  /// Discover — also the destination behind every "go find something"
  /// action in the empty states.
  final VoidCallback onSeeAllRooms;
  final VoidCallback? onFindCreators;
  final VoidCallback onViewAllFriends;
  final VoidCallback onStartRoom;

  /// The existing Moment viewer, creation flow and Moments destination.
  final ValueChanged<VoiceMoment> onOpenMoment;
  final VoidCallback onCreateMoment;
  final VoidCallback onSeeAllMoments;

  /// Opens the signed-in user's active chain in the story viewer.
  final ValueChanged<List<VoiceMoment>>? onOpenOwnChain;

  /// The existing chat screen, club surface, Chats and Clubs destinations.
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<Club> onOpenClub;
  final VoidCallback onSeeAllChats;
  final VoidCallback onOpenClubs;

  final RoomService? roomService;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final HomeFeedService? feedService;
  final MessageService? messageService;
  final ClubService? clubService;
  final ClubChatService? clubChatService;
  final FirebaseAuth? firebaseAuth;

  /// Staff capabilities, loaded once per session. Absent or failing, the
  /// board renders the ordinary UI.
  final StaffCapabilityService? capabilityService;

  /// Supplementary Home modules move below the main feed when the desktop
  /// shell is too narrow to keep a useful 344 px right rail. Nothing is
  /// hidden; only the composition changes with available width.
  final Widget? trailingContent;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  RoomService? _rooms;
  Stream<List<VoiceRoom>>? _liveRooms;
  Stream<UserProfile>? _profile;
  Stream<List<VoiceRoom>>? _owned;
  Stream<List<Conversation>>? _conversations;
  ProfileService? _profiles;
  final Map<String, Stream<String>> _recentChatPhotoStreams = {};

  /// Hosts this account follows — the top ranking tier for the board.
  final Set<String> _followedHostIds = <String>{};
  StreamSubscription<List<FollowUser>>? _followingSub;

  StaffCapabilities _capabilities = StaffCapabilities.none;

  @override
  void initState() {
    super.initState();
    // Each dependency is optional at runtime: Home must degrade to empty
    // states rather than throw when a service cannot be constructed.
    try {
      _rooms = widget.roomService ?? RoomService();
      _liveRooms = _rooms!.watchLivePublicRooms();
      _owned = _rooms!.watchOwnedRooms();
    } catch (_) {
      _rooms = null;
      _owned = null;
    }
    try {
      _conversations = (widget.messageService ?? MessageService.live)
          .watchConversations();
    } catch (_) {
      _conversations = null;
    }
    try {
      _profiles = widget.profileService ?? ProfileService();
      _profile = _profiles!.watchCurrentProfile();
    } catch (_) {
      _profiles = null;
      _profile = null;
    }
    // Feeds the board's top ranking tier. One subscription for the whole
    // screen — the previous shape opened a roster listener per visible
    // room to fill a map nothing read.
    try {
      _followingSub = (widget.followService ?? FollowService())
          .watchFollowing(widget.currentUserId)
          .listen((following) {
            if (!mounted) return;
            setState(() {
              _followedHostIds
                ..clear()
                ..addAll(following.map((user) => user.uid));
            });
          }, onError: (_) {});
    } catch (_) {
      _followingSub = null;
    }
    // Failure means the ordinary UI, never a guess.
    (widget.capabilityService ?? StaffCapabilityService())
        .load()
        .then((capabilities) {
          if (mounted) setState(() => _capabilities = capabilities);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _followingSub?.cancel();
    super.dispose();
  }

  Stream<String> _recentChatPhotoStream(String userId) {
    final profiles = _profiles;
    if (profiles == null) return const Stream<String>.empty();
    // At most three of these cold point-read streams are subscribed at once.
    // Caching keeps rebuilds from replacing Firestore listeners, while
    // StreamBuilder owns cancellation when a card leaves the tree.
    return _recentChatPhotoStreams.putIfAbsent(
      userId,
      () => profiles
          .watchProfile(userId)
          .map((profile) => profile.photoUrl?.trim() ?? '')
          .distinct(),
    );
  }

  void _openRoomSettings(VoiceRoom room) {
    // The existing settings screen, which re-checks authorship; rules
    // refuse a non-host write regardless of what the UI offers.
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => RoomSettingsScreen(room: room)),
    );
  }

  Future<void> _deleteOwnedRoom(VoiceRoom room) async {
    final service = _rooms;
    if (service == null) {
      throw StateError('Room management is temporarily unavailable.');
    }
    await service.deleteRoom(room.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VoiceRoom>>(
      stream: _liveRooms,
      builder: (context, snapshot) {
        final live = snapshot.data ?? const <VoiceRoom>[];
        // Every room Home knows about, from the two existing sources.
        final recommended = live;
        // A failed room query is NOT an empty room list. Folding the two
        // together printed "start one and your community will see it here"
        // over a permission denial or a dead connection — advice that
        // cannot help, on a page whose real state is unknown.
        final roomsUnavailable = snapshot.hasError || _liveRooms == null;

        return Builder(
          builder: (context) {
            // ONE room list. Live around you, Featured Live and For
            // you were three presentations over overlapping streams, so
            // the same room could appear three times on one screen.
            final board = rankRoomsForHome(
              live: live,
              recommended: recommended,
              followedHostIds: _followedHostIds,
            );

            const gap = SizedBox(height: 26);

            return ListView(
              // The feed owns its own position and never claims the
              // ambient primary controller. Two bare vertical scrollables
              // under one PrimaryScrollController do NOT scroll together
              // — each keeps its own ScrollPosition — but they DO put two
              // positions on one controller, which `Scrollbar` asserts
              // against and `controller.offset` throws on. This file hit
              // exactly that once already (see _RosterListState below).
              // On desktop targets `shouldInherit` is false anyway; this
              // makes it true on every target, including an Android
              // tablet in landscape, which is the one form factor that
              // reaches the desktop rail with the mobile gate open.
              primary: false,
              padding: const EdgeInsets.fromLTRB(24, 18, 20, 28),
              children: [
                _GreetingHeader(profile: _profile),
                const SizedBox(height: 20),
                // 1. Who can I hear from or open as a profile suggestion?
                DesktopMomentsStrip(
                  profile: _profile,
                  feedService: widget.feedService,
                  friendService: widget.friendService,
                  followService: widget.followService,
                  currentUserId: widget.currentUserId,
                  onOpenMoment: widget.onOpenMoment,
                  onOpenOwnChain: widget.onOpenOwnChain,
                  onCreateMoment: widget.onCreateMoment,
                  onSeeAll: widget.onSeeAllMoments,
                  onDiscover: widget.onFindCreators ?? widget.onSeeAllRooms,
                  onOpenProfile: (userId) =>
                      showProfilePreview(context, userId: userId),
                ),
                gap,
                // 2. Which rooms can I join?
                _HomeSectionTitle(
                  'Rooms for you',
                  onViewAll: widget.onSeeAllRooms,
                ),
                if (roomsUnavailable)
                  const _HomeSectionNote(
                    'Live rooms could not be loaded. Check your connection '
                    'and try again.',
                  )
                else if (board.isEmpty)
                  const _HomeSectionNote(
                    'No rooms to show yet — start one and your community '
                    'will see it here.',
                  )
                else
                  for (final room in board)
                    HomeRoomBanner(
                      room: room,
                      onJoin: widget.onOpenRoom,
                      roomService: _rooms,
                      currentUserId: widget.currentUserId,
                      onManageOwnedRoom: () => _openRoomSettings(room),
                      onDeleteOwnedRoom: () => _deleteOwnedRoom(room),
                      staffCapabilities: _capabilities,
                    ),
                gap,
                // 3. Which rooms belong to me?
                _HomeSectionTitle(
                  'Your active rooms',
                  onViewAll: widget.onSeeAllRooms,
                ),
                StreamBuilder<List<VoiceRoom>>(
                  stream: _owned,
                  builder: (context, ownedSnapshot) => HomeActiveRooms(
                    rooms: ownedSnapshot.data ?? const <VoiceRoom>[],
                    currentUserId: widget.currentUserId,
                    onEnter: widget.onOpenRoom,
                    onEdit: _openRoomSettings,
                    onDelete: _deleteOwnedRoom,
                    onCreateRoom: widget.onStartRoom,
                  ),
                ),
                gap,
                // 4. Who did I speak with most recently?
                _HomeSectionTitle(
                  'Your recent chats',
                  onViewAll: widget.onSeeAllChats,
                ),
                StreamBuilder<List<Conversation>>(
                  stream: _conversations,
                  builder: (context, conversationSnapshot) => RecentChats(
                    snapshot: conversationSnapshot,
                    currentUserId: widget.currentUserId,
                    onOpenConversation: widget.onOpenConversation,
                    onFindFriends: widget.onViewAllFriends,
                    style: RecentChatsStyle.desktopBackdrop,
                    photoStreamForUser: _profiles == null
                        ? null
                        : _recentChatPhotoStream,
                  ),
                ),
                if (widget.trailingContent != null) ...[
                  gap,
                  widget.trailingContent!,
                ],
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

class RoomVisual extends StatelessWidget {
  const RoomVisual({
    required this.room,
    this.size = 56,
    this.radius = 14,
    this.expand = false,
    super.key,
  });

  final VoiceRoom room;
  final double size;
  final double radius;

  /// Fills the incoming constraints instead of the square [size] — how
  /// the room banner uses its cover as a full-bleed background.
  final bool expand;

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
        width: expand ? double.infinity : size,
        height: expand ? double.infinity : size,
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
                // The gradient sits UNDER the decode, so a cover that is
                // still arriving shows the room's own colours rather than
                // a blank hole, and fades into the photo when it lands.
                frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: _fallback),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: child,
                      ),
                    ],
                  );
                },
                // Never a broken-image glyph: a revoked or 404 cover
                // degrades to the same branded gradient as no cover.
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

/// The roster itself. Every row is a real participant document from the
/// room's own stream — the same source the stage reads — so there is
/// nothing here that was invented to fill the list.
class RoomRosterList extends StatefulWidget {
  const RoomRosterList({
    required this.participants,
    required this.hostId,
    required this.onDismiss,
    super.key,
  });

  final List<RoomParticipant> participants;
  final String hostId;
  final VoidCallback onDismiss;

  @override
  State<RoomRosterList> createState() => _RosterListState();
}

class _RosterListState extends State<RoomRosterList> {
  /// Its OWN controller. Falling back to the PrimaryScrollController put
  /// a second ScrollPosition on the same controller as the page beneath,
  /// which Scrollbar asserts against — the roster is an overlay, not part
  /// of the page's scroll.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<RoomParticipant> get participants => widget.participants;
  String get hostId => widget.hostId;
  VoidCallback get onDismiss => widget.onDismiss;

  String _role(RoomParticipant participant) {
    if (participant.isHost || participant.userId == hostId) return 'Host';
    if (participant.role == 'moderator') return 'Moderator';
    if (participant.isSpeaker) return 'Speaker';
    return 'Listening';
  }

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          'Nobody is in this room yet.',
          style: TextStyle(color: Color(0xFF9A90AC), fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
          child: Text(
            '${participants.length} in the room',
            style: const TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 264),
          child: SingleChildScrollView(
            controller: _scroll,
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final participant in participants)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      onDismiss();
                      showProfilePreview(
                        context,
                        userId: participant.userId,
                        displayName: participant.displayName,
                        photoUrl: participant.photoUrl,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            radius: 15,
                            photoUrl: participant.photoUrl,
                            displayName: participant.displayName,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  participant.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _role(participant),
                                  style: const TextStyle(
                                    color: Color(0xFF7E7895),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (participant.isMuted)
                            const Icon(
                              Icons.mic_off_rounded,
                              size: 14,
                              color: Color(0xFF7E7895),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- shared states

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle(this.text, {this.onViewAll});

  final String text;

  /// Every section that can hold more than it shows carries the same way
  /// through to the full list.
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (onViewAll != null) ...[
          const Spacer(),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: const Color(0xFFD3A5FF),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View all',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 19),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _HomeSectionNote extends StatelessWidget {
  const _HomeSectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: const Color(0xFF12101D),
      border: Border.all(color: const Color(0xFF2C253B)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9D95AD),
        fontSize: 13.5,
        height: 1.35,
      ),
    ),
  );
}

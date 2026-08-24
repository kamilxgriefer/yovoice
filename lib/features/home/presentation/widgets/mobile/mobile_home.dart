import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart'
    show MomentCard;
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
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
    this.onOpenFindCreators,
    required this.onOpenFriends,
    required this.onOpenNotifications,
    this.unreadNotificationCount = 0,
    required this.onOpenProfile,
    required this.onCreateMoment,
    required this.onCreateRoom,
    required this.onOpenMoment,
    this.onOpenOwnChain,
    required this.onOpenComments,
    required this.onOpenConversation,
    required this.onSeeAllChats,
    this.roomService,
    this.friendService,
    this.profileService,
    this.feedService,
    this.messageService,
    this.capabilityService,
    this.currentUserId,
    super.key,
  });

  final ValueChanged<VoiceRoom> onOpenRoom;
  final VoidCallback onOpenDiscover;
  final VoidCallback? onOpenFindCreators;
  final VoidCallback onOpenFriends;
  final VoidCallback onOpenNotifications;
  final int unreadNotificationCount;
  final VoidCallback onOpenProfile;
  final VoidCallback onCreateMoment;

  /// Starting a room — a different flow from recording a Moment, which
  /// this used to be wired to by mistake.
  final VoidCallback onCreateRoom;

  /// Opens ONE Moment in the player. Distinct from [onOpenComments] on
  /// purpose: the rail's faces mean "hear this person", and routing them
  /// into the comment thread is why tapping your own avatar on Home never
  /// played anything.
  final ValueChanged<VoiceMoment> onOpenMoment;

  /// Opens the signed-in user's active chain in the story viewer.
  final ValueChanged<List<VoiceMoment>>? onOpenOwnChain;

  final ValueChanged<VoiceMoment> onOpenComments;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onSeeAllChats;

  final RoomService? roomService;
  final FriendService? friendService;
  final ProfileService? profileService;
  final HomeFeedService? feedService;

  /// Injected in tests for the same reason the others are: production
  /// passes nothing and resolves its own, which needs a Firebase app.

  final MessageService? messageService;
  final StaffCapabilityService? capabilityService;

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

  Stream<List<Conversation>>? _conversations;
  Stream<List<VoiceRoom>>? _owned;
  StaffCapabilities _capabilities = StaffCapabilities.none;

  @override
  void initState() {
    super.initState();
    try {
      _rooms = widget.roomService ?? RoomService();
      _liveRooms = _rooms!.watchLivePublicRooms();
      _owned = _rooms!.watchOwnedRooms();
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
      _conversations = (widget.messageService ?? MessageService())
          .watchConversations();
    } catch (_) {
      _conversations = null;
    }
    (widget.capabilityService ?? StaffCapabilityService())
        .load()
        .then((capabilities) {
          if (mounted) setState(() => _capabilities = capabilities);
        })
        .catchError((_) {});
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

  void _openRoomSettings(VoiceRoom room) {
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
        // A failed room query is NOT an empty room list — see the same
        // split in DesktopHome. Without it, "start one and your community
        // will see it here" was printed over a denial or a dead
        // connection, which is advice the reader cannot act on.
        final roomsUnavailable = snapshot.hasError || _liveRooms == null;

        return StreamBuilder<List<FriendUser>>(
          stream: _friends,
          builder: (context, friendSnapshot) {
            // Kept subscribed: the rail and future sections read it.
            friendSnapshot.data;

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
                  unreadNotificationCount: widget.unreadNotificationCount,
                ),
                const SizedBox(height: 16),
                // Home answers four questions, in this order, and nothing
                // is asked twice.
                const SizedBox(height: 4),
                StreamBuilder<List<VoiceMoment>>(
                  stream: _feed,
                  builder: (context, momentSnapshot) =>
                      // The signed-in avatar comes from the SHARED profile
                      // stream the header already reads, not from
                      // FirebaseAuth.currentUser.photoURL — a separate,
                      // staler store. It was hard-coded null here, so your
                      // own tile always fell back to a generic person icon.
                      StreamBuilder<UserProfile>(
                        stream: _profile,
                        builder: (context, profileSnapshot) =>
                            MobileMomentsStrip(
                              moments:
                                  momentSnapshot.data ?? const <VoiceMoment>[],
                              profile: profileSnapshot.data,
                              currentUserId: _resolvedUserId,
                              onOpenMoment: widget.onOpenMoment,
                              onOpenOwnChain: widget.onOpenOwnChain,
                              onCreateMoment: widget.onCreateMoment,
                              onDiscover:
                                  widget.onOpenFindCreators ??
                                  widget.onOpenDiscover,
                            ),
                      ),
                ),
                MobileSectionHeader(
                  title: 'Rooms for you',
                  onSeeAll: widget.onOpenDiscover,
                ),
                if (roomsUnavailable)
                  const _MobileNote(
                    'Live rooms could not be loaded. Check your connection '
                    'and try again.',
                  )
                else if (rankRoomsForHome(
                  live: live,
                  recommended: live,
                ).isEmpty)
                  const _MobileNote(
                    'No rooms to show yet — start one and your community '
                    'will see it here.',
                  )
                else
                  for (final room in rankRoomsForHome(
                    live: live,
                    recommended: live,
                  ))
                    HomeRoomBanner(
                      room: room,
                      onJoin: widget.onOpenRoom,
                      roomService: _rooms,
                      compact: true,
                      currentUserId: _resolvedUserId,
                      onManageOwnedRoom: () => _openRoomSettings(room),
                      onDeleteOwnedRoom: () => _deleteOwnedRoom(room),
                      staffCapabilities: _capabilities,
                    ),
                MobileSectionHeader(
                  title: 'Your active rooms',
                  onSeeAll: widget.onOpenDiscover,
                ),
                StreamBuilder<List<VoiceRoom>>(
                  stream: _owned,
                  builder: (context, ownedSnapshot) => HomeActiveRooms(
                    rooms: ownedSnapshot.data ?? const <VoiceRoom>[],
                    currentUserId: _resolvedUserId,
                    onEnter: widget.onOpenRoom,
                    onEdit: _openRoomSettings,
                    onDelete: _deleteOwnedRoom,
                    onCreateRoom: widget.onCreateRoom,
                    compact: true,
                  ),
                ),
                MobileSectionHeader(
                  title: 'Your recent chats',
                  onSeeAll: widget.onSeeAllChats,
                ),
                StreamBuilder<List<Conversation>>(
                  stream: _conversations,
                  builder: (context, conversationSnapshot) => RecentChats(
                    snapshot: conversationSnapshot,
                    currentUserId: _resolvedUserId,
                    onOpenConversation: widget.onOpenConversation,
                    onFindFriends: widget.onOpenFriends,
                  ),
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
    required this.unreadNotificationCount,
  });

  final Stream<UserProfile>? profile;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final int unreadNotificationCount;

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
              tooltip: unreadNotificationCount > 0
                  ? 'Notifications, $unreadNotificationCount unread'
                  : 'Notifications',
              badgeCount: unreadNotificationCount,
            ),
            const SizedBox(width: 10),
            AccessibleTapRegion(
              onTap: onProfile,
              semanticLabel: 'Open your profile',
              tooltip: 'Profile',
              circular: true,
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
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: tooltip,
      tooltip: tooltip,
      circular: true,
      child: ExcludeSemantics(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E2140)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 21),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE51852),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF080711),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------- briefing strip

class _MobileNote extends StatelessWidget {
  const _MobileNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF12101D),
      border: Border.all(color: const Color(0xFF2C253B)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9D95AD),
        fontSize: 13,
        height: 1.35,
      ),
    ),
  );
}

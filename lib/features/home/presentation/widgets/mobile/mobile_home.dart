import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';

/// Live-first Home: followed Moments, one featured real room, quick routes,
/// social activity, recent conversations and owned-room management.
///
/// Every number and face is real:
///  - live rooms + counts → [RoomService.watchLivePublicRooms]
///  - rosters / avatars / speaking → [RoomService.watchParticipants]
///  - feed → [HomeFeedService.watchSocialMoments], reused by rail and recap
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
    this.onOpenChain,
    required this.onOpenComments,
    required this.onOpenConversation,
    required this.onSeeAllChats,
    this.roomService,
    this.friendService,
    this.followService,
    this.profileService,
    this.profileMediaService,
    this.feedService,
    this.messageService,
    this.capabilityService,
    this.currentUserId,
    this.isVisible,
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

  /// Opens one author's active Voice Moment chain in the story viewer.
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  final ValueChanged<VoiceMoment> onOpenComments;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onSeeAllChats;

  final RoomService? roomService;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final ProfileMediaService? profileMediaService;
  final HomeFeedService? feedService;

  /// Injected in tests for the same reason the others are: production
  /// passes nothing and resolves its own, which needs a Firebase app.

  final MessageService? messageService;
  final StaffCapabilityService? capabilityService;

  /// The signed-in uid. Optional so tests need no Firebase app.
  final String? currentUserId;

  /// Home is retained in the shell. A rising edge requests a fresh v2
  /// projection because Voice Moment reads are intentionally one-shot rather
  /// than foreign Firestore listeners.
  final ValueListenable<bool>? isVisible;

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  RoomService? _rooms;
  Stream<List<VoiceRoom>>? _liveRooms;
  Stream<List<FollowUser>>? _following;

  /// The account's real friends. Home used to take a FriendService and never
  /// read it, so only followed creators appeared.
  Stream<List<FriendUser>>? _friends;
  Stream<UserProfile>? _profile;
  ProfileService? _profiles;
  final Map<String, Stream<String>> _recentChatPhotoStreams = {};
  Stream<List<VoiceMoment>>? _feed;

  /// Last page the feed delivered; shown while a refresh is in flight.
  List<VoiceMoment>? _lastFeedPage;
  HomeFeedService? _feedSource;

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
      _following = (widget.followService ?? FollowService()).watchFollowing(
        _resolvedUserId,
      );
    } catch (_) {
      _following = null;
    }
    try {
      _friends = (widget.friendService ?? FriendService()).watchFriends();
    } catch (_) {
      _friends = null;
    }
    try {
      _profiles = widget.profileService ?? ProfileService();
      _profile = _profiles!.watchCurrentProfile();
    } catch (_) {
      _profiles = null;
      _profile = null;
    }
    _loadFeed();
    widget.isVisible?.addListener(_handleVisibility);
    try {
      _conversations = (widget.messageService ?? MessageService.live)
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

  void _loadFeed() {
    try {
      _feedSource ??= widget.feedService ?? HomeFeedService();
      _feed = _feedSource!.watchSocialMoments();
    } catch (_) {
      _feed = null;
    }
  }

  void _handleVisibility() {
    if (!mounted || widget.isVisible?.value != true) return;
    // The v2 feed is a one-shot projection, so returning to the retained
    // Home is the refresh point. The previous page stays on screen as the
    // StreamBuilder's initial data until the new one arrives — re-creating
    // the stream used to blank Home for a few frames on every tab return,
    // which testers saw as a torn screen.
    setState(_loadFeed);
  }

  @override
  void didUpdateWidget(covariant MobileHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_handleVisibility);
      widget.isVisible?.addListener(_handleVisibility);
    }
    if (oldWidget.feedService != widget.feedService) {
      _feedSource = null;
      setState(_loadFeed);
    }
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    super.dispose();
  }

  Stream<String> _recentChatPhotoStream(String userId) {
    final profiles = _profiles;
    if (profiles == null) return const Stream<String>.empty();
    return _recentChatPhotoStreams.putIfAbsent(
      userId,
      () => profiles
          .watchProfile(userId)
          .map(
            (profile) =>
                profile.profileUpdatedAt?.toUtc().toIso8601String() ??
                'legacy:${profile.uid}',
          )
          .distinct(),
    );
  }

  void _retryLiveRooms() {
    setState(() {
      try {
        _rooms ??= widget.roomService ?? RoomService();
        _liveRooms = _rooms!.watchLivePublicRooms();
        _owned ??= _rooms!.watchOwnedRooms();
      } catch (_) {
        _liveRooms = null;
      }
    });
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
    return YoPageBackground(
      section: YoPageSection.home,
      // MainShell owns the base canvas; retain it beneath the static mark.
      decoration: const BoxDecoration(),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<List<VoiceRoom>>(
      stream: _liveRooms,
      builder: (context, snapshot) {
        final copy = AppLocalizations.of(context);
        final live = snapshot.data ?? const <VoiceRoom>[];
        // A failed room query is NOT an empty room list — see the same
        // split in DesktopHome. Without it, "start one and your community
        // will see it here" was printed over a denial or a dead
        // connection, which is advice the reader cannot act on.
        final roomsUnavailable = snapshot.hasError || _liveRooms == null;
        final roomsLoading = !roomsUnavailable && !snapshot.hasData;
        final board = rankRoomsForHome(live: live, recommended: live);
        return StreamBuilder<List<FollowUser>>(
          stream: _following,
          builder: (context, followingSnapshot) {
            final followedIds = {
              for (final user in followingSnapshot.data ?? const <FollowUser>[])
                user.uid,
            };
            return StreamBuilder<List<VoiceMoment>>(
              stream: _feed,
              initialData: _lastFeedPage,
              builder: (context, momentSnapshot) {
                if (momentSnapshot.hasData &&
                    momentSnapshot.connectionState != ConnectionState.waiting) {
                  _lastFeedPage = momentSnapshot.data;
                }
                final visibleMoments =
                    (momentSnapshot.data ?? const <VoiceMoment>[])
                        .where(
                          (moment) =>
                              moment.authorId == _resolvedUserId ||
                              followedIds.contains(moment.authorId),
                        )
                        .toList(growable: false);
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
                    const SizedBox(height: 22),
                    StreamBuilder<UserProfile>(
                      stream: _profile,
                      builder: (context, profileSnapshot) => MobileMomentsStrip(
                        moments: visibleMoments,
                        profile: profileSnapshot.data,
                        currentUserId: _resolvedUserId,
                        onOpenMoment: widget.onOpenMoment,
                        onOpenChain: widget.onOpenChain,
                        onCreateMoment: widget.onCreateMoment,
                      ),
                    ),
                    MobileSectionHeader(
                      title: copy.homeLiveForYou,
                      onSeeAll: widget.onOpenDiscover,
                    ),
                    if (roomsUnavailable)
                      YoErrorState(
                        message: copy.text(
                          'Live rooms could not be loaded. Check your connection and try again.',
                          'Nie udało się wczytać pokojów na żywo. Sprawdź połączenie i spróbuj ponownie.',
                        ),
                        onRetry: _retryLiveRooms,
                        compact: true,
                      )
                    else if (roomsLoading)
                      const HomeRoomsLoading()
                    else if (board.isEmpty)
                      _MobileNote(
                        copy.text(
                          'No rooms to show yet — start one and your community will see it here.',
                          'Nie ma jeszcze żadnych pokojów — utwórz pierwszy, a zobaczy go Twoja społeczność.',
                        ),
                      )
                    else
                      HomeRoomBanner(
                        key: const ValueKey('home-featured-room'),
                        room: board.first,
                        featured: true,
                        onJoin: widget.onOpenRoom,
                        roomService: _rooms,
                        compact: true,
                        currentUserId: _resolvedUserId,
                        onManageOwnedRoom: () => _openRoomSettings(board.first),
                        onDeleteOwnedRoom: () => _deleteOwnedRoom(board.first),
                        staffCapabilities: _capabilities,
                      ),
                    const SizedBox(height: 2),
                    HomeQuickActions(
                      onCreateRoom: widget.onCreateRoom,
                      onFriends: widget.onOpenFriends,
                    ),
                    HomeCircleActivity(
                      onFriends: widget.onOpenFriends,
                      moments: visibleMoments,
                      currentUserId: _resolvedUserId,
                      onOpenMoment: widget.onOpenMoment,
                      onOpenChain: widget.onOpenChain,
                    ),
                    HomePeopleStrip(
                      friends: _friends,
                      onSeeAll: widget.onOpenFriends,
                    ),
                    MobileSectionHeader(
                      title: copy.text('Your recent chats', 'Ostatnie czaty'),
                      onSeeAll: widget.onSeeAllChats,
                    ),
                    StreamBuilder<List<Conversation>>(
                      stream: _conversations,
                      builder: (context, conversationSnapshot) => RecentChats(
                        snapshot: conversationSnapshot,
                        currentUserId: _resolvedUserId,
                        onOpenConversation: widget.onOpenConversation,
                        onFindFriends: widget.onOpenFriends,
                        photoStreamForUser: _profiles == null
                            ? null
                            : _recentChatPhotoStream,
                        profileMediaService: widget.profileMediaService,
                      ),
                    ),
                    MobileSectionHeader(
                      title: copy.text(
                        'Your active rooms',
                        'Twoje aktywne pokoje',
                      ),
                      onSeeAll: widget.onOpenDiscover,
                    ),
                    StreamBuilder<List<VoiceRoom>>(
                      stream: _owned,
                      builder: (context, ownedSnapshot) =>
                          ownedSnapshot.hasError || _owned == null
                          ? YoErrorState(
                              compact: true,
                              message: copy.text(
                                'Could not load rooms',
                                'Nie udało się wczytać pokojów',
                              ),
                              onRetry: () => setState(
                                () => _owned = _rooms?.watchOwnedRooms(),
                              ),
                            )
                          : !ownedSnapshot.hasData
                          ? const HomeRoomsLoading()
                          : HomeActiveRooms(
                              rooms: ownedSnapshot.data ?? const <VoiceRoom>[],
                              currentUserId: _resolvedUserId,
                              onEnter: widget.onOpenRoom,
                              onEdit: _openRoomSettings,
                              onDelete: _deleteOwnedRoom,
                              onCreateRoom: widget.onCreateRoom,
                              compact: true,
                            ),
                    ),
                    if (board.length > 1 && !roomsUnavailable) ...[
                      MobileSectionHeader(
                        title: copy.text('Rooms for you', 'Pokoje dla Ciebie'),
                        onSeeAll: widget.onOpenDiscover,
                      ),
                      for (final room in board.skip(1))
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
                    ],
                  ],
                );
              },
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

  static String _partOfDay(AppLocalizations copy) {
    final hour = DateTime.now().hour;
    if (hour < 12) return copy.text('Good morning,', 'Dzień dobry,');
    if (hour < 18) return copy.text('Good afternoon,', 'Dzień dobry,');
    return copy.text('Good evening,', 'Dobry wieczór,');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return StreamBuilder<UserProfile>(
      stream: profile,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final enlargedText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final displayName = data?.displayName.trim().isNotEmpty == true
            ? data!.displayName.trim()
            : copy.text('Welcome', 'Witaj');
        final greeting = Text(
          _partOfDay(copy),
          style: TextStyle(color: palette.textSecondary, fontSize: 14),
        );
        final name = Text(
          displayName,
          maxLines: enlargedText ? 2 : 1,
          overflow: enlargedText ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        );
        final notification = _CircleIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onNotifications,
          tooltip: unreadNotificationCount > 0
              ? copy.text(
                  'Notifications, $unreadNotificationCount unread',
                  'Powiadomienia: $unreadNotificationCount nieprzeczytanych',
                )
              : copy.notifications,
          badgeCount: unreadNotificationCount,
        );
        final avatar = AccessibleTapRegion(
          onTap: onProfile,
          semanticLabel: copy.text('Open your profile', 'Otwórz swój profil'),
          tooltip: copy.profile,
          circular: true,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
              ),
            ),
            child: UserAvatar(
              radius: 21,
              userId: data?.uid,
              photoUrl: data?.photoUrl,
              mediaRevision: data?.profileUpdatedAt,
              displayName: data?.displayName,
              fallbackIcon: Icons.person_rounded,
            ),
          ),
        );

        if (enlargedText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: greeting),
                  notification,
                  const SizedBox(width: 10),
                  avatar,
                ],
              ),
              const SizedBox(height: 8),
              name,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [greeting, const SizedBox(height: 2), name],
              ),
            ),
            const SizedBox(width: 10),
            notification,
            const SizedBox(width: 10),
            avatar,
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
    final palette = context.appPalette;
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
            color: palette.surfaceRaised,
            border: Border.all(color: palette.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: palette.textPrimary, size: 21),
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
                      border: Border.all(color: palette.background, width: 2),
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
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}

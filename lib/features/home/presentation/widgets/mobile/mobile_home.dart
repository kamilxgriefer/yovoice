import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/layout/status_bar_scrim.dart';
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
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';

/// Friends-first Home: the account and its friends with their availability
/// rings, one featured real room, quick routes, the followed-Moments rail,
/// recent conversations, a capped room board and owned-room management.
///
/// Every number and face is real:
///  - friends + presence → [FriendService.watchFriends]
///  - live rooms + counts → [RoomService.watchLivePublicRooms]
///  - rosters / avatars / speaking → [RoomService.watchParticipants]
///  - feed → [HomeFeedService.watchSocialMoments]
///  - identity + availability → [ProfileService.watchCurrentProfile]
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
    this.onSeeAllMoments,
    this.roomService,
    this.friendService,
    this.followService,
    this.profileService,
    this.profileMediaService,
    this.feedService,
    this.messageService,
    this.capabilityService,
    this.presenceService,
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

  /// "View all" on the followed-Moments rail — the dock's Your Moments.
  /// Optional so harnesses keep compiling; null hides the button.
  final VoidCallback? onSeeAllMoments;

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

  /// Test seam for the two availability affordances (the header chip and
  /// the "You" tile). Production passes null and the picker constructs a
  /// service only when a choice is actually made, so simply opening Home
  /// never touches presence.
  final PresenceService? presenceService;

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
  final _quickActionsKey = GlobalKey();
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
      _lastFeedPage = null;
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

  void _retryFriends() {
    setState(() {
      try {
        _friends = (widget.friendService ?? FriendService()).watchFriends();
      } catch (_) {
        _friends = null;
      }
    });
  }

  void _retryMoments() {
    setState(() {
      // A failed relationship/media read must not replay a denied cached
      // page while the next read is pending.
      _lastFeedPage = null;
      _loadFeed();
      try {
        _following = (widget.followService ?? FollowService()).watchFollowing(
          _resolvedUserId,
        );
      } catch (_) {
        _following = null;
      }
    });
  }

  void _retryChats() {
    setState(() {
      try {
        _conversations = (widget.messageService ?? MessageService.live)
            .watchConversations();
      } catch (_) {
        _conversations = null;
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
      child: HomeErrorAnnouncementScope(
        isVisible: widget.isVisible,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => StreamBuilder<List<VoiceRoom>>(
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
          // Medium widths (UI.md): 24 px gutters once the body is at least
          // 600 px wide; the featured banner takes its taller variant there.
          // A tablet is NOT a stretched phone: past the 880 px list measure
          // the column stays 880 wide and centres, so a 1024 px slate gets
          // real margins instead of a 976 px phone column.
          final width = constraints.maxWidth;
          final medium = width >= 600;
          final gutter = medium ? AppRhythm.section : AppRhythm.title;
          // The frame the page lives in; rails clip to this, not the screen.
          final frameInset = math.max(
            0.0,
            (width - math.min(width, ResponsiveContentWidth.list.maxWidth)) / 2,
          );
          // The margin every non-rail child's ink starts at.
          final margin = frameInset + gutter;
          return StreamBuilder<List<FollowUser>>(
            stream: _following,
            builder: (context, followingSnapshot) {
              final followedIds = {
                for (final user
                    in followingSnapshot.data ?? const <FollowUser>[])
                  user.uid,
              };
              // The same ranking desktop applies: a followed host's live
              // room leads, so both form factors feature the same room.
              final board = rankRoomsForHome(
                live: live,
                recommended: live,
                followedHostIds: followedIds,
              );
              return StreamBuilder<List<VoiceMoment>>(
                stream: _feed,
                initialData: _lastFeedPage,
                builder: (context, momentSnapshot) {
                  final momentsUnavailable =
                      momentSnapshot.hasError ||
                      followingSnapshot.hasError ||
                      _feed == null ||
                      _following == null;
                  final momentsLoading =
                      !momentsUnavailable &&
                      (!momentSnapshot.hasData || !followingSnapshot.hasData);
                  if (momentsUnavailable) _lastFeedPage = null;
                  if (momentSnapshot.hasData &&
                      !momentsUnavailable &&
                      momentSnapshot.connectionState !=
                          ConnectionState.waiting) {
                    _lastFeedPage = momentSnapshot.data;
                  }
                  final visibleMoments =
                      (momentsUnavailable
                              ? const <VoiceMoment>[]
                              : momentSnapshot.data ?? const <VoiceMoment>[])
                          .where(
                            (moment) =>
                                moment.authorId == _resolvedUserId ||
                                followedIds.contains(moment.authorId),
                          )
                          .toList(growable: false);
                  // "View all" only when there is something to view: at
                  // least one followed author with a playable Moment.
                  final hasFollowedMoments = visibleMoments.any(
                    (moment) =>
                        moment.authorId != _resolvedUserId &&
                        moment.hasMediaReference,
                  );
                  final moreRooms = board
                      .skip(1)
                      .take(3)
                      .toList(growable: false);
                  final roomsEmpty =
                      !roomsUnavailable && !roomsLoading && board.isEmpty;
                  final quickActions = HomeQuickActions(
                    key: _quickActionsKey,
                    onCreateRoom: widget.onCreateRoom,
                    onFriends: widget.onOpenFriends,
                  );
                  return StatusBarScrim(
                    child: ListView(
                      // The gutter is NOT the list's padding any more: the two
                      // rails are full-bleed and carry it inside their own
                      // scroll views, so their tiles scroll under the frame
                      // edge instead of painting past the layout. Every other
                      // child is wrapped in `_Gutter`.
                      //
                      // Top inset clears the status bar / notch (the shell's
                      // mobile body is not wrapped in a SafeArea). The bottom
                      // inset is the page step: MainShell puts the dock in
                      // `bottomNavigationBar` and never sets `extendBody`, so
                      // the body viewport already ends above it and the old
                      // 128 px reservation was 132 px of dead screen.
                      padding: EdgeInsets.fromLTRB(
                        0,
                        MediaQuery.paddingOf(context).top + AppRhythm.title,
                        0,
                        AppRhythm.page,
                      ),
                      children: [
                        _Gutter(
                          margin: margin,
                          child: _MobileHeader(
                            profile: _profile,
                            presenceService: widget.presenceService,
                            onNotifications: widget.onOpenNotifications,
                            onProfile: widget.onOpenProfile,
                            unreadNotificationCount:
                                widget.unreadNotificationCount,
                          ),
                        ),
                        // 1. Who can I talk to right now? Me first, then my
                        // friends, online first.
                        _Rail(
                          frameInset: frameInset,
                          child: HomePeopleStrip(
                            friends: _friends,
                            profile: _profile,
                            presenceService: widget.presenceService,
                            horizontalPadding: gutter,
                            onRetry: _retryFriends,
                            onSeeAll: widget.onOpenFriends,
                          ),
                        ),
                        // 2. What is happening right now?
                        _Gutter(
                          margin: margin,
                          child: HomeSectionHeader(
                            title: roomsEmpty
                                ? copy.homeStartConversation
                                : copy.homeLiveForYou,
                            onSeeAll: widget.onOpenDiscover,
                          ),
                        ),
                        _Gutter(
                          margin: margin,
                          child: roomsUnavailable
                              ? HomeSectionError(
                                  key: const ValueKey('home-rooms-error'),
                                  error: snapshot.error,
                                  message: copy.text(
                                    'Live rooms could not be loaded. Check your connection and try again.',
                                    'Nie udało się wczytać pokojów na żywo. Sprawdź połączenie i spróbuj ponownie.',
                                  ),
                                  onRetry: _retryLiveRooms,
                                )
                              : roomsLoading
                              ? const HomeRoomsLoading()
                              : board.isEmpty
                              ? HomeConversationInvitation(
                                  actions: quickActions,
                                )
                              : HomeRoomBanner(
                                  key: const ValueKey('home-featured-room'),
                                  room: board.first,
                                  featured: true,
                                  onJoin: widget.onOpenRoom,
                                  roomService: _rooms,
                                  compact: !medium,
                                  currentUserId: _resolvedUserId,
                                  onManageOwnedRoom: () =>
                                      _openRoomSettings(board.first),
                                  onDeleteOwnedRoom: () =>
                                      _deleteOwnedRoom(board.first),
                                  staffCapabilities: _capabilities,
                                ),
                        ),
                        if (!roomsEmpty) ...[
                          const SizedBox(height: AppRhythm.item),
                          _Gutter(margin: margin, child: quickActions),
                        ],
                        // 3. Which followed voices have a Moment I can hear?
                        // A section title is a promise about content: with no
                        // followed Moments there is nothing to title, so the
                        // rail's Record affordance becomes a labelled action
                        // in the group above instead of a titled section with
                        // one button in it.
                        if (hasFollowedMoments ||
                            momentsUnavailable ||
                            momentsLoading)
                          _Gutter(
                            margin: margin,
                            child: HomeSectionHeader(
                              title: copy.homeFromPeopleYouFollow,
                              onSeeAll: widget.onSeeAllMoments,
                            ),
                          )
                        else
                          const SizedBox(height: AppRhythm.item),
                        if (momentsUnavailable) ...[
                          _Gutter(
                            margin: margin,
                            child: HomeSectionError(
                              key: const ValueKey('home-moments-error'),
                              error:
                                  momentSnapshot.error ??
                                  followingSnapshot.error,
                              message: copy.text(
                                'Moments could not load',
                                'Nie udało się wczytać Momentów',
                              ),
                              onRetry: _retryMoments,
                            ),
                          ),
                          const SizedBox(height: AppRhythm.item),
                        ] else if (momentsLoading) ...[
                          _Gutter(
                            margin: margin,
                            child: const LinearProgressIndicator(
                              key: ValueKey('home-moments-loading'),
                            ),
                          ),
                          const SizedBox(height: AppRhythm.item),
                        ],
                        _Rail(
                          key: const ValueKey('home-moments-section'),
                          frameInset: frameInset,
                          child: StreamBuilder<UserProfile>(
                            stream: _profile,
                            builder: (context, profileSnapshot) =>
                                MobileMomentsStrip(
                                  moments: visibleMoments,
                                  profile: profileSnapshot.data,
                                  currentUserId: _resolvedUserId,
                                  horizontalPadding: gutter,
                                  onOpenMoment: widget.onOpenMoment,
                                  onOpenChain: widget.onOpenChain,
                                  onCreateMoment: widget.onCreateMoment,
                                  // The own avatar already leads "Your people";
                                  // the Record tile keeps creation on Home.
                                  showOwnTile: false,
                                  trailingRecordTile: true,
                                ),
                          ),
                        ),
                        // 4. Which conversations continue?
                        _Gutter(
                          margin: margin,
                          child: HomeSectionHeader(
                            title: copy.text(
                              'Your recent chats',
                              'Ostatnie czaty',
                            ),
                            onSeeAll: widget.onSeeAllChats,
                          ),
                        ),
                        _Gutter(
                          key: const ValueKey('home-recent-chats'),
                          margin: margin,
                          child: StreamBuilder<List<Conversation>>(
                            stream: _conversations,
                            builder: (context, conversationSnapshot) =>
                                conversationSnapshot.hasError ||
                                    _conversations == null
                                ? HomeSectionError(
                                    key: const ValueKey('home-chats-error'),
                                    error: conversationSnapshot.error,
                                    message: copy.text(
                                      'Your recent chats could not be loaded.',
                                      'Nie udało się wczytać ostatnich czatów.',
                                    ),
                                    onRetry: _retryChats,
                                  )
                                : RecentChats(
                                    snapshot: conversationSnapshot,
                                    currentUserId: _resolvedUserId,
                                    onOpenConversation:
                                        widget.onOpenConversation,
                                    onFindFriends: widget.onOpenFriends,
                                    photoStreamForUser: _profiles == null
                                        ? null
                                        : _recentChatPhotoStream,
                                    profileMediaService:
                                        widget.profileMediaService,
                                  ),
                          ),
                        ),
                        // 5. Three more rooms at most; Rooms owns the rest.
                        if (moreRooms.isNotEmpty && !roomsUnavailable) ...[
                          _Gutter(
                            margin: margin,
                            child: HomeSectionHeader(
                              title: copy.text(
                                'Rooms for you',
                                'Pokoje dla Ciebie',
                              ),
                              onSeeAll: widget.onOpenDiscover,
                            ),
                          ),
                          _Gutter(
                            margin: margin,
                            child: _RoomStack(
                              rooms: moreRooms,
                              // A medium slate has room for two banners side
                              // by side; a phone keeps one column.
                              columns:
                                  medium &&
                                      width - margin * 2 >=
                                          MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(300) *
                                                  2 +
                                              AppRhythm.title
                                  ? 2
                                  : 1,
                              builder: (room) => HomeRoomBanner(
                                key: ValueKey('home-room-${room.id}'),
                                room: room,
                                onJoin: widget.onOpenRoom,
                                roomService: _rooms,
                                compact: true,
                                currentUserId: _resolvedUserId,
                                onManageOwnedRoom: () =>
                                    _openRoomSettings(room),
                                onDeleteOwnedRoom: () => _deleteOwnedRoom(room),
                                staffCapabilities: _capabilities,
                              ),
                            ),
                          ),
                        ],
                        // 6. Owned rooms — hosts only. A non-host used to get a
                        // permanently empty card whose Create Room button
                        // duplicated the pill above. An error is still shown:
                        // it must never read as "no rooms".
                        //
                        // Keyed on purpose: the block above it is variable in
                        // length, and an unkeyed list child that shifts index
                        // is rebuilt from scratch — which re-subscribes to an
                        // already-emitted broadcast stream and leaves a host's
                        // own rooms silently missing from Home.
                        StreamBuilder<List<VoiceRoom>>(
                          key: const ValueKey('home-owned-rooms'),
                          stream: _owned,
                          builder: (context, ownedSnapshot) {
                            final failed =
                                ownedSnapshot.hasError || _owned == null;
                            final owned = failed || !ownedSnapshot.hasData
                                ? const <VoiceRoom>[]
                                : HomeActiveRooms.ownedBy(
                                    ownedSnapshot.data ?? const <VoiceRoom>[],
                                    _resolvedUserId,
                                  );
                            if (!failed && owned.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _Gutter(
                              margin: margin,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  HomeSectionHeader(
                                    title: copy.text(
                                      'Your active rooms',
                                      'Twoje aktywne pokoje',
                                    ),
                                    onSeeAll: widget.onOpenDiscover,
                                  ),
                                  if (failed)
                                    HomeSectionError(
                                      error: ownedSnapshot.error,
                                      message: copy.text(
                                        'Could not load rooms',
                                        'Nie udało się wczytać pokojów',
                                      ),
                                      onRetry: () => setState(
                                        () =>
                                            _owned = _rooms?.watchOwnedRooms(),
                                      ),
                                    )
                                  else
                                    HomeActiveRooms(
                                      rooms: owned,
                                      currentUserId: _resolvedUserId,
                                      onEnter: widget.onOpenRoom,
                                      onEdit: _openRoomSettings,
                                      onDelete: _deleteOwnedRoom,
                                      onCreateRoom: widget.onCreateRoom,
                                      compact: true,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- layout

/// One page child, inset to the page margin.
///
/// The margin lives here rather than on the ListView so the rails beside
/// these children can be full-bleed. Every non-rail child on Home is
/// wrapped in exactly one of these: forget it and the child goes
/// edge-to-edge, which is why the rhythm test measures EVERY child's ink,
/// not a sample.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.margin, required this.child, super.key});

  final double margin;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: margin),
    child: child,
  );
}

/// A full-bleed horizontal rail, inset to the content FRAME but not to the
/// gutter — the rail carries the gutter inside its own scroll view, so its
/// first tile starts at the margin and the rest scroll under the frame's
/// edge. On a phone the frame is the screen; on a slate it is the 880 px
/// column, so nothing paints into a tablet's page margin.
class _Rail extends StatelessWidget {
  const _Rail({required this.frameInset, required this.child, super.key});

  final double frameInset;
  final Widget child;

  @override
  Widget build(BuildContext context) => frameInset <= 0
      ? child
      : Padding(
          padding: EdgeInsets.symmetric(horizontal: frameInset),
          child: child,
        );
}

/// The stacked room banners under "Rooms for you".
///
/// One column on a phone; two on a medium slate, where a full-width banner
/// is a stretched phone card. The banners themselves carry no margin — the
/// gap between siblings is one declared [AppRhythm.item].
class _RoomStack extends StatelessWidget {
  const _RoomStack({
    required this.rooms,
    required this.columns,
    required this.builder,
  });

  final List<VoiceRoom> rooms;
  final int columns;
  final Widget Function(VoiceRoom room) builder;

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < rooms.length; index++) ...[
            if (index > 0) const SizedBox(height: AppRhythm.item),
            builder(rooms[index]),
          ],
        ],
      );
    }
    final rows = <List<VoiceRoom>>[
      for (var index = 0; index < rooms.length; index += columns)
        rooms.sublist(index, math.min(index + columns, rooms.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < rows.length; row++) ...[
          if (row > 0) const SizedBox(height: AppRhythm.item),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: AppRhythm.section),
                Expanded(
                  child: column < rows[row].length
                      ? builder(rows[row][column])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------- header

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.profile,
    required this.presenceService,
    required this.onNotifications,
    required this.onProfile,
    required this.unreadNotificationCount,
  });

  final Stream<UserProfile>? profile;
  final PresenceService? presenceService;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final int unreadNotificationCount;

  /// The control row's height: the 46 px discs, which are the tallest
  /// members. The 44 px availability band centres inside it.
  static const double _controlHeight = 46;

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
            : copy.text('Welcome back', 'Witaj ponownie');
        final greeting = Text(
          _partOfDay(copy),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.textSecondary, fontSize: 14),
        );
        final name = LayoutBuilder(
          builder: (context, constraints) => Text(
            displayName,
            // Identity is primary content, not a preview. The narrower
            // heading token gives 320px phones a readable word measure;
            // platform scaling is still applied in full, including 200%.
            softWrap: true,
            style:
                (constraints.maxWidth < 320
                        ? AppTypography.headlineMedium
                        : AppTypography.headlineLarge)
                    .copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
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
        // The readable availability affordance: "● Available ▾", now the
        // LEADING member of the header's control row rather than a lone
        // object floating in whitespace under the name. Only once the
        // profile has emitted — never a guessed state.
        final chip = data == null
            ? null
            : AvailabilityChip(
                availability: data.availability,
                presenceService: presenceService,
                hitTargetSize: 44,
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

        // One row of three controls, all on one centre line. The discs set
        // the row's height, so the header is exactly as tall before the
        // profile arrives as it is after — the cold start no longer jumps
        // ~50 px when the chip appears.
        final controlRow = enlargedText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chip != null) ...[
                    chip,
                    const SizedBox(height: AppRhythm.tight),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        notification,
                        const SizedBox(width: AppRhythm.tight),
                        avatar,
                      ],
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: _controlHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // One Expanded, not a Flexible chip beside a Spacer:
                    // those two split the free width evenly, and half of a
                    // 320 px phone is not enough for a Polish status pill.
                    Expanded(
                      child: chip == null
                          ? const SizedBox.shrink()
                          : Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: chip,
                            ),
                    ),
                    notification,
                    const SizedBox(width: AppRhythm.tight),
                    avatar,
                  ],
                ),
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            greeting,
            const SizedBox(height: AppRhythm.hairline),
            name,
            const SizedBox(height: AppRhythm.item),
            controlRow,
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

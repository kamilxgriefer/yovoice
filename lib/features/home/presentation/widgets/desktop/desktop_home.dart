import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
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
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';

/// "Pulse Home" — the DESKTOP Home surface, friends first.
///
/// Every module reads existing production data; nothing here invents a
/// user, a room, a message or an activity number:
///  - `Your people` + rings → [FriendService.watchFriends]
///  - the room board        → [RoomService.watchLivePublicRooms]
///  - face piles / rosters  → [RoomService.watchParticipants] per banner
///  - board ranking         → [FollowService.watchFollowing]
///  - `Your active rooms`   → [RoomService.watchOwnedRooms]
///  - greeting + availability → [ProfileService.watchCurrentProfile]
///  - followed Moments      → [HomeFeedService.watchSocialMoments]
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
    this.onOpenChain,
    required this.onOpenConversation,
    required this.onOpenClub,
    required this.onSeeAllChats,
    required this.onOpenClubs,
    this.roomService,
    this.friendService,
    this.followService,
    this.profileService,
    this.profileMediaService,
    this.feedService,
    this.messageService,
    this.clubService,
    this.clubChatService,
    this.firebaseAuth,
    this.capabilityService,
    this.presenceService,
    this.trailingContent,
    this.isVisible,
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

  /// Opens one author's active Voice Moment chain in the story viewer.
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  /// The existing chat screen, club surface, Chats and Clubs destinations.
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<Club> onOpenClub;
  final VoidCallback onSeeAllChats;
  final VoidCallback onOpenClubs;

  final RoomService? roomService;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final ProfileMediaService? profileMediaService;
  final HomeFeedService? feedService;
  final MessageService? messageService;
  final ClubService? clubService;
  final ClubChatService? clubChatService;
  final FirebaseAuth? firebaseAuth;

  /// Staff capabilities, loaded once per session. Absent or failing, the
  /// board renders the ordinary UI.
  final StaffCapabilityService? capabilityService;

  /// Test seam for the two availability affordances (the greeting chip and
  /// the "You" tile). Production passes null and the picker constructs a
  /// service only when a choice is actually made, so simply opening Home
  /// never touches presence.
  final PresenceService? presenceService;

  /// Supplementary Home modules move below the main feed when the desktop
  /// shell is too narrow to keep a useful 344 px right rail. Nothing is
  /// hidden; only the composition changes with available width.
  final Widget? trailingContent;

  /// Retained-shell visibility used by one-shot Voice Moment projections.
  final ValueListenable<bool>? isVisible;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  // Responsive reflow moves these sections, never their subscriptions or
  // expiry-recovery focus nodes. Global keys reparent the existing elements
  // in the same frame when the available content width crosses a boundary.
  final _peopleKey = GlobalKey();
  final _conversationKey = GlobalKey();
  final _momentsKey = GlobalKey();
  final _chatsKey = GlobalKey();
  final _quickActionsKey = GlobalKey();

  /// See HomePeopleStrip: the desktop Home also took a FriendService
  /// without ever reading it.
  Stream<List<FriendUser>>? _friends;
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
    try {
      _friends = (widget.friendService ?? FriendService()).watchFriends();
    } catch (_) {
      _friends = null;
    }
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
    // The existing settings screen, which re-checks authorship; rules
    // refuse a non-host write regardless of what the UI offers.
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => RoomSettingsScreen(room: room)),
    );
  }

  Future<void> _deleteOwnedRoom(VoiceRoom room) async {
    final service = _rooms;
    if (service == null) {
      throw StateError(
        AppLocalizations.of(context).text(
          'Room management is temporarily unavailable.',
          'Zarządzanie pokojem jest chwilowo niedostępne.',
        ),
      );
    }
    await service.deleteRoom(room.id);
  }

  @override
  Widget build(BuildContext context) {
    return YoPageBackground(
      section: YoPageSection.home,
      // DesktopShell owns the base canvas and surrounding columns.
      decoration: const BoxDecoration(),
      child: HomeErrorAnnouncementScope(
        isVisible: widget.isVisible,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.workbench,
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
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

            return LayoutBuilder(
              builder: (context, constraints) {
                // UI.md: 32 px gutters in the wide band, 24 below it. The
                // old padding was asymmetric (24 left, 20 right).
                final gutter = constraints.maxWidth >= 1100
                    ? AppSpacing.xl
                    : constraints.maxWidth >= 600
                    ? AppSpacing.lg
                    : AppSpacing.md;
                return ListView(
                  // The feed owns its own position and never claims the
                  // ambient primary controller. Two bare vertical
                  // scrollables under one PrimaryScrollController do NOT
                  // scroll together — each keeps its own ScrollPosition —
                  // but they DO put two positions on one controller, which
                  // `Scrollbar` asserts against and `controller.offset`
                  // throws on. This file hit exactly that once already
                  // (see _RosterListState below). On desktop targets
                  // `shouldInherit` is false anyway; this makes it true on
                  // every target, including an Android tablet in
                  // landscape, which is the one form factor that reaches
                  // the desktop rail with the mobile gate open.
                  primary: false,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppRhythm.title,
                    gutter,
                    AppRhythm.page,
                  ),
                  children: [
                    _GreetingHeader(
                      profile: _profile,
                      presenceService: widget.presenceService,
                    ),
                    // No ad hoc gap: every section heading below owns the
                    // 24 px above it and the 16 px under it, on both
                    // platforms, from one component.
                    // 1. Who can I talk to right now? Me first, then
                    // friends.
                    _buildOverview(
                      context,
                      board: board,
                      roomsUnavailable: roomsUnavailable,
                      roomsLoading: !roomsUnavailable && !snapshot.hasData,
                      roomsError: snapshot.error,
                    ),
                    if (widget.trailingContent != null) ...[
                      const SizedBox(height: AppRhythm.section),
                      widget.trailingContent!,
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

  Widget _buildOverview(
    BuildContext context, {
    required List<VoiceRoom> board,
    required bool roomsUnavailable,
    required bool roomsLoading,
    required Object? roomsError,
  }) {
    final copy = AppLocalizations.of(context);
    // 3. Which followed voices have a Moment I can hear? The strip owns the
    // feed / following / momentViews subscriptions and hands the resolved
    // list back, so the whole overview is composed from ONE subscription
    // and the Record affordance can be placed by what the data actually
    // says — beside the other real actions when there is no followed
    // Moment, in its own titled section when there is. The strip never
    // gates the rest of the page: it calls this builder on every frame,
    // including the first, so rooms and chats are never waiting on the
    // Moments feed.
    return DesktopMomentsStrip(
      avatarOnly: true,
      showOwnTile: false,
      trailingRecordTile: true,
      isVisible: widget.isVisible,
      profile: _profile,
      feedService: widget.feedService,
      friendService: widget.friendService,
      followService: widget.followService,
      currentUserId: widget.currentUserId,
      onOpenMoment: widget.onOpenMoment,
      onOpenChain: widget.onOpenChain,
      onCreateMoment: widget.onCreateMoment,
      onSeeAll: widget.onSeeAllMoments,
      contentBuilder: (context, rail, moments) => _overview(
        context,
        board: board,
        roomsUnavailable: roomsUnavailable,
        roomsLoading: roomsLoading,
        roomsError: roomsError,
        copy: copy,
        rail: rail,
        // "View all" — and the heading itself — only when there is
        // something to view: a followed author with a playable Moment.
        hasFollowedMoments: moments.any(
          (moment) =>
              moment.authorId != widget.currentUserId &&
              moment.hasMediaReference,
        ),
      ),
    );
  }

  Widget _overview(
    BuildContext context, {
    required List<VoiceRoom> board,
    required bool roomsUnavailable,
    required bool roomsLoading,
    required Object? roomsError,
    required AppLocalizations copy,
    required Widget rail,
    required bool hasFollowedMoments,
  }) {
    final roomsEmpty = !roomsUnavailable && !roomsLoading && board.isEmpty;
    final quickActions = HomeQuickActions(
      key: _quickActionsKey,
      onCreateRoom: widget.onStartRoom,
      onFriends: widget.onViewAllFriends,
    );
    final peopleSection = HomePeopleStrip(
      key: _peopleKey,
      friends: _friends,
      profile: _profile,
      presenceService: widget.presenceService,
      onRetry: _retryFriends,
      onSeeAll: widget.onViewAllFriends,
      horizontalPadding: 0,
      expandedLabels: true,
    );
    // One conversation entry, whether a real room exists or not.
    final liveSection = Column(
      key: _conversationKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: roomsEmpty ? copy.homeStartConversation : copy.homeLiveForYou,
          scale: HomeSectionHeaderScale.expanded,
          onSeeAll: widget.onSeeAllRooms,
        ),
        if (roomsUnavailable)
          HomeSectionError(
            key: const ValueKey('home-rooms-error'),
            error: roomsError,
            message: copy.text(
              'Live rooms could not be loaded. Check your connection and try again.',
              'Nie udało się wczytać pokojów na żywo. Sprawdź połączenie i spróbuj ponownie.',
            ),
            onRetry: _retryLiveRooms,
          )
        else if (roomsLoading)
          const HomeRoomsLoading()
        else if (board.isEmpty)
          HomeConversationInvitation(actions: quickActions)
        else
          _roomBanner(board.first, featured: true),
        if (!roomsEmpty) ...[
          const SizedBox(height: AppRhythm.item),
          quickActions,
        ],
      ],
    );
    // A single new-content preview stays in the main column, including its
    // empty Record/recovery control. It never jumps to the people column
    // when the last active chain expires.
    final momentsSection = ClipRect(
      key: _momentsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFollowedMoments)
            HomeSectionHeader(
              title: copy.homeFromPeopleYouFollow,
              scale: HomeSectionHeaderScale.expanded,
              onSeeAll: widget.onSeeAllMoments,
            )
          else
            const SizedBox(height: AppRhythm.item),
          rail,
        ],
      ),
    );
    final chatsSection = ClipRect(
      key: _chatsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeader(
            title: copy.text('Your recent chats', 'Ostatnie czaty'),
            scale: HomeSectionHeaderScale.expanded,
            onSeeAll: widget.onSeeAllChats,
          ),
          StreamBuilder<List<Conversation>>(
            stream: _conversations,
            builder: (context, conversationSnapshot) =>
                conversationSnapshot.hasError || _conversations == null
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
                    currentUserId: widget.currentUserId,
                    onOpenConversation: widget.onOpenConversation,
                    onFindFriends: widget.onViewAllFriends,
                    style: RecentChatsStyle.desktopBackdrop,
                    photoStreamForUser: _profiles == null
                        ? null
                        : _recentChatPhotoStream,
                    profileMediaService: widget.profileMediaService,
                  ),
          ),
        ],
      ),
    );
    // 5. Three more rooms at most; Discover owns the full list.
    final moreRooms = board.skip(1).take(3).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final extraScale = (scale - 1).clamp(0.0, 2.0);
        final minimumMain = 420 + extraScale * 180;
        final minimumSecondary = 320 + extraScale * 80;
        final twoColumns =
            constraints.maxWidth >=
            minimumMain + minimumSecondary + AppRhythm.section;
        final secondaryWidth = (constraints.maxWidth * .34).clamp(
          minimumSecondary,
          minimumSecondary + 80,
        );
        final roomsGrid =
            constraints.maxWidth >=
            (MediaQuery.textScalerOf(context).scale(280) * 3) +
                AppRhythm.title * 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (twoColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      key: const ValueKey('home-main-column'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [liveSection, momentsSection],
                    ),
                  ),
                  const SizedBox(width: AppRhythm.section),
                  SizedBox(
                    key: const ValueKey('home-secondary-column'),
                    width: secondaryWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [peopleSection, chatsSection],
                    ),
                  ),
                ],
              )
            else ...[
              peopleSection,
              liveSection,
              momentsSection,
              chatsSection,
            ],
            if (moreRooms.isNotEmpty && !roomsUnavailable) ...[
              HomeSectionHeader(
                title: copy.text('Rooms for you', 'Pokoje dla Ciebie'),
                scale: HomeSectionHeaderScale.expanded,
                onSeeAll: widget.onSeeAllRooms,
              ),
              if (roomsGrid)
                // Three ~330–370 px cells: phone density, side by side.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: AppRhythm.title),
                      Expanded(
                        child: i < moreRooms.length
                            ? _roomBanner(moreRooms[i], compact: true)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                )
              else
                for (var i = 0; i < moreRooms.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppRhythm.item),
                  _roomBanner(moreRooms[i]),
                ],
            ],
            // 6. Owned rooms — hosts only. A non-host used to get a
            // permanently empty card whose Create Room button duplicated
            // the pill above. An error is still shown: it must never read
            // as "no rooms". Loading renders nothing (no heading flash).
            // Keyed for the same reason mobile Home keys it: the rooms
            // block above is variable in length, and an unkeyed child that
            // shifts position is rebuilt from scratch — re-subscribing to
            // an already-emitted broadcast stream and losing the data.
            StreamBuilder<List<VoiceRoom>>(
              key: const ValueKey('home-owned-rooms'),
              stream: _owned,
              builder: (context, ownedSnapshot) {
                final failed = ownedSnapshot.hasError || _owned == null;
                final owned = failed || !ownedSnapshot.hasData
                    ? const <VoiceRoom>[]
                    : HomeActiveRooms.ownedBy(
                        ownedSnapshot.data ?? const <VoiceRoom>[],
                        widget.currentUserId,
                      );
                if (!failed && owned.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HomeSectionHeader(
                      title: copy.text(
                        'Your active rooms',
                        'Twoje aktywne pokoje',
                      ),
                      scale: HomeSectionHeaderScale.expanded,
                      onSeeAll: widget.onSeeAllRooms,
                    ),
                    if (failed)
                      HomeSectionError(
                        error: ownedSnapshot.error,
                        message: copy.text(
                          'Could not load rooms',
                          'Nie udało się wczytać pokojów',
                        ),
                        onRetry: () =>
                            setState(() => _owned = _rooms?.watchOwnedRooms()),
                      )
                    else
                      HomeActiveRooms(
                        rooms: owned,
                        currentUserId: widget.currentUserId,
                        onEnter: widget.onOpenRoom,
                        onEdit: _openRoomSettings,
                        onDelete: _deleteOwnedRoom,
                        onCreateRoom: widget.onStartRoom,
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _roomBanner(
    VoiceRoom room, {
    bool featured = false,
    bool compact = false,
  }) => HomeRoomBanner(
    key: featured
        ? const ValueKey('home-featured-room')
        : ValueKey('home-room-${room.id}'),
    room: room,
    featured: featured,
    compact: compact,
    onJoin: widget.onOpenRoom,
    roomService: _rooms,
    currentUserId: widget.currentUserId,
    onManageOwnedRoom: () => _openRoomSettings(room),
    onDeleteOwnedRoom: () => _deleteOwnedRoom(room),
    staffCapabilities: _capabilities,
  );
}

// ---------------------------------------------------------------- header

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.profile, required this.presenceService});

  final Stream<UserProfile>? profile;
  final PresenceService? presenceService;

  static String _partOfDay(AppLocalizations copy) {
    final hour = DateTime.now().hour;
    if (hour < 12) return copy.text('Good morning', 'Dzień dobry');
    if (hour < 18) return copy.text('Good afternoon', 'Dzień dobry');
    return copy.text('Good evening', 'Dobry wieczór');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return StreamBuilder<UserProfile>(
      stream: profile,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final name = data?.displayName.trim() ?? '';
        final nameLine = Text(
          name.isEmpty ? copy.text('Welcome back', 'Witaj ponownie') : name,
          style: AppTypography.headlineLarge.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        );
        final greeting = Text(
          _partOfDay(copy),
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
          ),
        );
        // The readable availability affordance, on the NAME's line — the
        // same decision mobile Home makes. Centring it across the whole
        // two-line greeting is what made it read as floating. Only once
        // the profile has emitted; never a guessed state.
        final chip = data == null
            ? null
            : AvailabilityChip(
                availability: data.availability,
                presenceService: presenceService,
                hitTargetSize: 44,
              );
        return LayoutBuilder(
          builder: (context, constraints) {
            final inline =
                constraints.maxWidth >=
                MediaQuery.textScalerOf(context).scale(420);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                greeting,
                const SizedBox(height: AppRhythm.hairline),
                if (chip != null && inline)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: nameLine),
                      const SizedBox(width: AppRhythm.item),
                      chip,
                    ],
                  )
                else
                  nameLine,
                if (chip != null && !inline) ...[
                  const SizedBox(height: AppRhythm.tight),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: chip,
                  ),
                ],
              ],
            );
          },
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
    this.fallbackAsset,
    super.key,
  });

  final VoiceRoom room;
  final double size;
  final double radius;

  /// Fills the incoming constraints instead of the square [size] — how
  /// the room banner uses its cover as a full-bleed background.
  final bool expand;
  final String? fallbackAsset;

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
    Widget fallback() {
      final gradient = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _fallback,
          ),
        ),
      );
      if (fallbackAsset == null) return gradient;
      return Image.asset(
        fallbackAsset!,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => gradient,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: expand ? double.infinity : size,
        height: expand ? double.infinity : size,
        child: cover == null || cover.isEmpty
            ? fallback()
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
                      fallback(),
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
                errorBuilder: (_, __, ___) => fallback(),
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

  String _role(RoomParticipant participant, AppLocalizations copy) {
    if (participant.isHost || participant.userId == hostId) {
      return copy.text('Host', 'Prowadzący');
    }
    if (participant.role == 'moderator') {
      return copy.text('Moderator', 'Moderator');
    }
    if (participant.isSpeaker) return copy.text('Speaker', 'Mówca');
    return copy.text('Listening', 'Słucha');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    if (participants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          copy.text(
            'Nobody is in this room yet.',
            'W tym pokoju nikogo jeszcze nie ma.',
          ),
          style: TextStyle(color: palette.textSecondary, fontSize: 12),
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
            copy.text(
              '${participants.length} in the room',
              '${participants.length} w pokoju',
            ),
            style: TextStyle(
              color: palette.textSecondary,
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
                            userId: participant.userId,
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
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _role(participant, copy),
                                  style: TextStyle(
                                    color: palette.textTertiary,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (participant.isMuted)
                            Icon(
                              Icons.mic_off_rounded,
                              size: 14,
                              color: palette.textTertiary,
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

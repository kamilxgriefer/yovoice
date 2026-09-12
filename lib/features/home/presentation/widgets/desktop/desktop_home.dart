import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_lounge_watcher.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_card.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_record_moment_card.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart'
    show MomentViewedIds;
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';

/// "Tu i teraz" — the WIDE Home surface.
///
/// The same facts as the phone Home, from the same streams and the same
/// components, in a deliberately different composition: a rail (owned by the
/// shell) beside a greeting card, one full-width friends row, and below it a
/// main column carrying the conversation the reader can walk into, with a
/// narrow context column of doors beside it.
///
/// Every module reads existing production data; nothing here invents a user,
/// a room, a message or an activity number:
///  - greeting, avatar, availability → [ProfileService.watchCurrentProfile]
///  - friends, presence, rings       → [FriendService.watchFriends] plus the
///    existing social page, gated by real friendship
///  - the featured room, its roster  → [RoomService] through [HomeRosterCache]
///  - places and their live lounges  → [ClubService.watchMyClubs] +
///    [RoomService.watchClubLounge]
///  - recent chats, owned rooms      → the same flows as everywhere else
///
/// Opening this screen joins no audio, requests no microphone and writes no
/// roster row. Every way into a room ends at the existing pre-join screen,
/// which is the single consent boundary for both room products.
///
/// Navigation is delegated: the callbacks below are wired by MainShell to the
/// SAME fixed-shell content-slot mechanism the rail uses, so nothing here
/// pushes a route except entering a room, opening a chat or a club — the
/// flows that already own their full-screen route everywhere else.
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
    this.onOpenNotifications,
    this.onOpenProfile,
    this.onOpenServers,
    this.onEnterClubLounge,
    this.unreadNotificationCount = 0,
    this.roomService,
    this.friendService,
    this.followService,
    this.profileService,
    this.profileMediaService,
    this.feedService,
    this.messageService,
    this.clubService,
    this.clubChatService,
    this.momentViewsService,
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

  /// Opens one author's active Voice Moment chain in the story viewer — what
  /// a friend tile with a new Voice Moment taps through to.
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  /// The existing chat screen, club surface, Chats and Clubs destinations.
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<Club> onOpenClub;
  final VoidCallback onSeeAllChats;
  final VoidCallback onOpenClubs;

  /// The notifications feed and the profile, behind the greeting card's own
  /// bell and avatar. They call the SAME shell handlers the rail's bell and
  /// profile card call — one destination, two doors, never two states.
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenProfile;

  /// The Serwery destination: "Zobacz wszystkie" beside "W Twoich serwerach",
  /// the places card's "Stwórz serwer" and its overflow row. Creation is
  /// gated inside that feature, which is where its own honest copy lives.
  final VoidCallback? onOpenServers;

  /// Resolves a member's club lounge and opens the pre-join screen. Never
  /// joins audio here — `prepareClubLounge` only checks membership.
  final ValueChanged<Club>? onEnterClubLounge;

  /// The shell's real unread count, printed on the greeting card's bell.
  final int unreadNotificationCount;

  final RoomService? roomService;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final ProfileMediaService? profileMediaService;
  final HomeFeedService? feedService;
  final MessageService? messageService;
  final ClubService? clubService;
  final ClubChatService? clubChatService;

  /// Test seam for the ONE `momentViews` listener behind the friend badges.
  final MomentViewsService? momentViewsService;
  final FirebaseAuth? firebaseAuth;

  /// Staff capabilities, loaded once per session. Absent or failing, the
  /// board renders the ordinary UI.
  final StaffCapabilityService? capabilityService;

  /// Test seam for the availability affordance on the own tile. Production
  /// passes null and the picker constructs a service only when a choice is
  /// actually made, so simply opening Home never touches presence.
  final PresenceService? presenceService;

  /// Supplementary shell modules, appended under the feed. Home itself no
  /// longer has a tenant here (the Premium and Sponsored cards moved to the
  /// destinations that own them), but the seam stays for the dev preview and
  /// for any future shell-level card.
  final Widget? trailingContent;

  /// Retained-shell visibility used by one-shot Voice Moment projections.
  final ValueListenable<bool>? isVisible;

  /// The slot width at which the context column earns its place. Below it
  /// the same modules continue down the single column — nothing is hidden,
  /// only rearranged.
  static const double twoColumnThreshold = 1000;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  // Responsive reflow moves these sections, never their subscriptions or
  // expiry-recovery focus nodes. Global keys reparent the existing elements
  // in the same frame when the available content width crosses a boundary.
  final _peopleKey = GlobalKey();
  final _conversationKey = GlobalKey();
  final _chatsKey = GlobalKey();
  final _quickActionsKey = GlobalKey();
  final _placesKey = GlobalKey();
  final _recordKey = GlobalKey();

  Stream<List<FriendUser>>? _friends;
  RoomService? _rooms;
  Stream<List<VoiceRoom>>? _liveRooms;
  Stream<UserProfile>? _profile;
  Stream<List<VoiceRoom>>? _owned;
  Stream<List<Conversation>>? _conversations;
  Stream<List<FollowUser>>? _following;
  ProfileService? _profiles;
  final Map<String, Stream<String>> _recentChatPhotoStreams = {};

  Stream<List<VoiceMoment>>? _feed;

  /// Last page the feed delivered; shown while a refresh is in flight.
  List<VoiceMoment>? _lastFeedPage;
  HomeFeedService? _feedSource;

  ClubService? _clubs;
  Stream<List<Club>>? _myClubs;

  /// Bumped by the places retry so the lounge watcher re-subscribes.
  int _loungeGeneration = 0;

  StaffCapabilities _capabilities = StaffCapabilities.none;

  /// THE bounded roster pool: at most four `watchParticipants` listeners for
  /// the whole screen, shared by the hero, the live server rows and the
  /// friend intersection that decides which room the hero features.
  late final HomeRosterCache _rosters;

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
    _rosters = HomeRosterCache(service: _rooms)..addListener(_onRosters);
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
      _following = (widget.followService ?? FollowService()).watchFollowing(
        widget.currentUserId,
      );
    } catch (_) {
      _following = null;
    }
    _loadClubs();
    _loadFeed();
    widget.isVisible?.addListener(_handleVisibility);
    // Failure means the ordinary UI, never a guess.
    (widget.capabilityService ?? StaffCapabilityService())
        .load()
        .then((capabilities) {
          if (mounted) setState(() => _capabilities = capabilities);
        })
        .catchError((_) {});
  }

  void _onRosters() {
    if (mounted) setState(() {});
  }

  void _loadClubs() {
    try {
      _clubs ??= widget.clubService ?? ClubService();
      _myClubs = _clubs!.watchMyClubs();
    } catch (_) {
      _myClubs = null;
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
    // StreamBuilder's initial data until the new one arrives.
    setState(_loadFeed);
  }

  @override
  void didUpdateWidget(covariant DesktopHome oldWidget) {
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
    if (oldWidget.clubService != widget.clubService) {
      _clubs = null;
      setState(_loadClubs);
    }
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    _rosters
      ..removeListener(_onRosters)
      ..dispose();
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

  /// Re-creates `watchMyClubs` AND every lounge child, because a denial on
  /// the membership mirror usually means the lounge reads failed too.
  void _retryPlaces() {
    setState(() {
      _clubs = null;
      _loungeGeneration++;
      _loadClubs();
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

  void _openCandidate(HomeLiveCandidate candidate) {
    final club = candidate.club;
    if (club != null) {
      final enter = widget.onEnterClubLounge;
      if (enter != null) {
        enter(club);
        return;
      }
    }
    widget.onOpenRoom(candidate.room);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // UI.md: 32 px gutters in the wide band. This surface only ever
        // renders inside the desktop shell, which exists from a 1100 px
        // VIEWPORT — so it is always in that band, however much of the
        // viewport the 264 px rail has taken. Reading the band off the slot
        // instead gave a 1280 px desktop the 24 px gutters of a tablet.
        // The narrow step survives for harnesses that pump this widget in a
        // small box.
        final slot = constraints.maxWidth;
        final gutter = slot >= 600 ? AppSpacing.xl : AppSpacing.md;
        return StreamBuilder<List<VoiceRoom>>(
          stream: _liveRooms,
          builder: (context, roomSnapshot) => StreamBuilder<List<FriendUser>>(
            stream: _friends,
            builder: (context, friendSnapshot) => StreamBuilder<List<Club>>(
              stream: _myClubs,
              builder: (context, clubSnapshot) => HomeLoungeWatcher(
                clubs: (clubSnapshot.data ?? const <Club>[])
                    .take(HomeLoungeWatcher.budget)
                    .toList(growable: false),
                rooms: _rooms,
                generation: _loungeGeneration,
                builder: (context, lounges) => MomentViewedIds(
                  service: widget.momentViewsService,
                  builder: (context, viewedIds) => _buildPage(
                    context,
                    slot: slot,
                    gutter: gutter,
                    roomSnapshot: roomSnapshot,
                    friendSnapshot: friendSnapshot,
                    clubSnapshot: clubSnapshot,
                    lounges: lounges,
                    viewedIds: viewedIds,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(
    BuildContext context, {
    required double slot,
    required double gutter,
    required AsyncSnapshot<List<VoiceRoom>> roomSnapshot,
    required AsyncSnapshot<List<FriendUser>> friendSnapshot,
    required AsyncSnapshot<List<Club>> clubSnapshot,
    required Map<String, HomePlace> lounges,
    required Set<String> viewedIds,
  }) {
    final copy = AppLocalizations.of(context);
    final live = roomSnapshot.data ?? const <VoiceRoom>[];
    // A failed room query is NOT an empty room list. Folding the two
    // together printed "start one and your community will see it here" over
    // a permission denial or a dead connection — advice that cannot help on
    // a page whose real state is unknown.
    final roomsUnavailable = roomSnapshot.hasError || _liveRooms == null;
    final roomsLoading = !roomsUnavailable && !roomSnapshot.hasData;

    final friendIds = {
      for (final friend in friendSnapshot.data ?? const <FriendUser>[])
        friend.id,
    };

    final clubs = clubSnapshot.data ?? const <Club>[];
    final clubsUnavailable = clubSnapshot.hasError || _myClubs == null;
    final clubsLoading = !clubsUnavailable && !clubSnapshot.hasData;
    final places = [
      for (final club in clubs) lounges[club.id] ?? HomePlace(club: club),
    ];

    return StreamBuilder<List<FollowUser>>(
      stream: _following,
      builder: (context, followingSnapshot) {
        final followedIds = {
          for (final user in followingSnapshot.data ?? const <FollowUser>[])
            user.uid,
        };
        return StreamBuilder<List<VoiceRoom>>(
          stream: _owned,
          builder: (context, ownedSnapshot) {
            final ownedFailed = ownedSnapshot.hasError || _owned == null;
            final owned = ownedFailed || !ownedSnapshot.hasData
                ? const <VoiceRoom>[]
                : HomeActiveRooms.ownedBy(
                    ownedSnapshot.data ?? const <VoiceRoom>[],
                    widget.currentUserId,
                  );
            final candidates = homeLiveCandidates(
              places: places,
              owned: owned,
              live: live,
              followedIds: followedIds,
              friendIds: friendIds,
            );
            // Ask for exactly the rosters the page can use, in priority
            // order, and never more than the pool's budget.
            _rosters.request(candidates.map((candidate) => candidate.roomId));
            final featured = selectHereNowCandidate(
              candidates: candidates,
              rosters: _rosters,
              friendIds: friendIds,
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
                if (momentsUnavailable) _lastFeedPage = null;
                if (momentSnapshot.hasData &&
                    !momentsUnavailable &&
                    momentSnapshot.connectionState != ConnectionState.waiting) {
                  _lastFeedPage = momentSnapshot.data;
                }
                // A failed page renders presence only — never a stale badge
                // claiming there is something new to hear.
                final voiceByFriend = momentsUnavailable
                    ? const <String, HomeFriendVoice>{}
                    : homeFriendVoiceByAuthor(
                        page: momentSnapshot.data ?? const <VoiceMoment>[],
                        friendIds: friendIds,
                        viewedMomentIds: viewedIds,
                        now: DateTime.now(),
                      );
                return _buildList(
                  context,
                  copy: copy,
                  slot: slot,
                  gutter: gutter,
                  friendSnapshot: friendSnapshot,
                  roomsUnavailable: roomsUnavailable,
                  roomsLoading: roomsLoading,
                  roomsError: roomSnapshot.error,
                  featured: featured,
                  friendIds: friendIds,
                  voiceByFriend: voiceByFriend,
                  places: places,
                  clubsUnavailable: clubsUnavailable,
                  clubsLoading: clubsLoading,
                  clubError: clubSnapshot.error,
                  owned: owned,
                  ownedFailed: ownedFailed,
                  ownedError: ownedSnapshot.error,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context, {
    required AppLocalizations copy,
    required double slot,
    required double gutter,
    required AsyncSnapshot<List<FriendUser>> friendSnapshot,
    required bool roomsUnavailable,
    required bool roomsLoading,
    required Object? roomsError,
    required HomeLiveCandidate? featured,
    required Set<String> friendIds,
    required Map<String, HomeFriendVoice> voiceByFriend,
    required List<HomePlace> places,
    required bool clubsUnavailable,
    required bool clubsLoading,
    required Object? clubError,
    required List<VoiceRoom> owned,
    required bool ownedFailed,
    required Object? ownedError,
  }) {
    // The lounge watcher only ever receives the head of this list, so only
    // the head may be spoken about: a membership Home never looked at is not
    // a quiet membership. The rail below still shows every place — it makes
    // no activity claim — and the remainder is counted so the quiet card can
    // say what it actually checked.
    final checkedPlaces = places
        .take(HomeLoungeWatcher.budget)
        .toList(growable: false);
    final uncheckedPlaces = places.length - checkedPlaces.length;

    final openServers = widget.onOpenServers ?? widget.onSeeAllRooms;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final extraScale = (scale - 1).clamp(0.0, 2.0);
    // A context column is only worth its 300 px while the main column keeps
    // a hero that still reads as a stage. At large text scale that costs
    // more width, so the threshold moves with the type rather than against
    // it — and below it the SAME modules continue down one column.
    final twoColumns =
        slot >= DesktopHome.twoColumnThreshold + extraScale * 260;
    final contextWidth = (300 + extraScale * 40).clamp(280.0, 344.0);

    final quickActions = HomeQuickActions(
      key: _quickActionsKey,
      onCreateRoom: widget.onStartRoom,
      onFriends: widget.onViewAllFriends,
    );

    // ------------------------------------------------------ main column
    final conversationSection = Column(
      key: _conversationKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: copy.homeHereNow,
          scale: HomeSectionHeaderScale.expanded,
          live: featured != null,
        ),
        _hereNow(
          context,
          copy: copy,
          featured: featured,
          friendIds: friendIds,
          roomsUnavailable: roomsUnavailable,
          roomsLoading: roomsLoading,
          error: roomsError,
          quickActions: quickActions,
        ),
        // The invitation card embeds these actions itself; every other
        // state keeps them under the section. A failed room read must not
        // also cost the reader the way to start a room of their own.
        if (!(featured == null && !roomsUnavailable && !roomsLoading)) ...[
          const SizedBox(height: AppRhythm.item),
          quickActions,
        ],
      ],
    );

    // ONE card per failed read, in the column that owns the subject. In the
    // two-column layout "Twoje miejsca" lives in the context column, so the
    // denial is reported there; in the single column this section is where
    // the reader meets it first. Never both — two cards about one read is
    // the noise a reader cannot attribute.
    final placesError = HomeSectionError(
      key: const ValueKey('home-places-error'),
      error: clubError,
      message: copy.text(
        "Couldn't load your places.",
        'Nie udało się wczytać Twoich miejsc.',
      ),
      onRetry: _retryPlaces,
    );

    final serversSection = clubsUnavailable
        ? (twoColumns
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppRhythm.section),
                  child: placesError,
                ))
        : clubsLoading || places.isEmpty
        ? const SizedBox.shrink()
        : HomeServerActivitySection(
            places: checkedPlaces,
            uncheckedPlaces: uncheckedPlaces,
            rosters: _rosters,
            onSeeAll: openServers,
            onOpenPlace: (club) => widget.onOpenClub(club),
            onEnterLounge: (place) =>
                widget.onEnterClubLounge?.call(place.club),
            onRetryPlace: (_) => _retryPlaces(),
          );

    final ownedSection = KeyedSubtree(
      key: const ValueKey('home-owned-rooms'),
      child: ownedFailed || owned.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeSectionHeader(
                  title: copy.text('Your active rooms', 'Twoje aktywne pokoje'),
                  scale: HomeSectionHeaderScale.expanded,
                  onSeeAll: widget.onSeeAllRooms,
                ),
                if (ownedFailed)
                  HomeSectionError(
                    error: ownedError,
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
            )
          : const SizedBox.shrink(),
    );

    // --------------------------------------------------- context column
    final recordCard = KeyedSubtree(
      key: _recordKey,
      child: HomeRecordMomentCard(onCreateMoment: widget.onCreateMoment),
    );

    final chatsSection = ClipRect(
      key: _chatsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeader(
            title: copy.text('Your recent chats', 'Ostatnie czaty'),
            // The context column is 300 px wide and its neighbours are
            // cards with 16 px titles. A 19 px heading with a "See all"
            // beside it wraps to two lines there, which is a worse reading
            // of "one ramp" than matching the column it lives in.
            scale: twoColumns
                ? HomeSectionHeaderScale.compact
                : HomeSectionHeaderScale.expanded,
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

    // "Twoje miejsca": a card of rows in the context column, the phone's
    // tile rail when the page is one column. The same memberships, the same
    // stream, the same destination — a different shape for a different box.
    final placesModule = KeyedSubtree(
      key: _placesKey,
      child: clubsUnavailable
          // A denial is never an absence. This column owns "Twoje miejsca",
          // so in the two-column layout it is where the failed read is
          // reported, with the same retry, instead of the section silently
          // disappearing. The single column reports it above instead.
          ? (twoColumns ? placesError : const SizedBox.shrink())
          : clubsLoading
          ? (twoColumns
                ? const HomePlacesCardLoading()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HomeSectionHeader(
                        title: copy.homeYourPlaces,
                        scale: HomeSectionHeaderScale.expanded,
                      ),
                      const HomePlacesLoading(horizontalPadding: 0),
                    ],
                  ))
          : places.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeSectionHeader(
                  title: copy.homeYourPlaces,
                  // The same ramp its populated and loading siblings use:
                  // the 300 px context column runs compact, the single
                  // column runs the page's own expanded ramp.
                  scale: twoColumns
                      ? HomeSectionHeaderScale.compact
                      : HomeSectionHeaderScale.expanded,
                ),
                HomePlacesEmptyCard(
                  onCreateServer: openServers,
                  onDiscover: widget.onSeeAllRooms,
                ),
              ],
            )
          : twoColumns
          ? HomePlacesCard(
              places: places,
              onOpenPlace: (club) => widget.onOpenClub(club),
              onCreateServer: openServers,
              onSeeAll: openServers,
            )
          // The rail draws its own heading — one promise, one title.
          : HomePlacesRail(
              places: places,
              horizontalPadding: 0,
              headerScale: HomeSectionHeaderScale.expanded,
              onOpenPlace: (club) => widget.onOpenClub(club),
              onCreateServer: openServers,
            ),
    );

    final peopleSection = HomePeopleStrip(
      key: _peopleKey,
      // The list is already resolved above (the hero needs the same ids):
      // the strip renders it rather than opening a second listener on the
      // same query.
      friendsSnapshot: _friends == null ? null : friendSnapshot,
      friends: _friends,
      profile: _profile,
      presenceService: widget.presenceService,
      horizontalPadding: 0,
      avatarRadius: 40,
      expandedLabels: true,
      voiceByFriendId: voiceByFriend,
      onOpenVoice: widget.onOpenChain,
      onRetry: _retryFriends,
      onSeeAll: widget.onViewAllFriends,
    );

    return ListView(
      // The feed owns its own position and never claims the ambient primary
      // controller. Two bare vertical scrollables under one
      // PrimaryScrollController do NOT scroll together — each keeps its own
      // ScrollPosition — but they DO put two positions on one controller,
      // which `Scrollbar` asserts against and `controller.offset` throws on.
      primary: false,
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppRhythm.title,
        gutter,
        AppRhythm.page,
      ),
      children: [
        _GreetingCard(
          profile: _profile,
          unreadNotificationCount: widget.unreadNotificationCount,
          onOpenNotifications:
              widget.onOpenNotifications ?? widget.onSeeAllChats,
          onOpenProfile: widget.onOpenProfile ?? widget.onViewAllFriends,
        ),
        // 1. Who can I talk to right now? Me first, then my friends — one
        //    full-width row above the split, as the reference draws it.
        peopleSection,
        // 2. The conversation I can walk into, and the doors beside it.
        if (twoColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  key: const ValueKey('home-main-column'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [conversationSection, serversSection, ownedSection],
                ),
              ),
              const SizedBox(width: AppRhythm.section),
              SizedBox(
                key: const ValueKey('home-secondary-column'),
                width: contextWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The context column starts level with the hero, not
                    // with the heading above it.
                    const SizedBox(height: AppRhythm.section),
                    placesModule,
                    const SizedBox(height: AppRhythm.section),
                    recordCard,
                    chatsSection,
                  ],
                ),
              ),
            ],
          )
        else ...[
          conversationSection,
          serversSection,
          placesModule,
          const SizedBox(height: AppRhythm.section),
          recordCard,
          chatsSection,
          ownedSection,
        ],
        if (widget.trailingContent != null) ...[
          const SizedBox(height: AppRhythm.section),
          widget.trailingContent!,
        ],
      ],
    );
  }

  Widget _hereNow(
    BuildContext context, {
    required AppLocalizations copy,
    required HomeLiveCandidate? featured,
    required Set<String> friendIds,
    required bool roomsUnavailable,
    required bool roomsLoading,
    required Object? error,
    required Widget quickActions,
  }) {
    if (roomsUnavailable) {
      return HomeSectionError(
        key: const ValueKey('home-rooms-error'),
        error: error,
        message: copy.text(
          'Live rooms could not be loaded. Check your connection and try again.',
          'Nie udało się wczytać pokojów na żywo. Sprawdź połączenie i spróbuj ponownie.',
        ),
        onRetry: _retryLiveRooms,
      );
    }
    if (roomsLoading) return const HomeRoomsLoading();
    if (featured == null) {
      return HomeConversationInvitation(
        actions: quickActions,
        onDiscover: widget.onSeeAllRooms,
      );
    }
    final room = featured.room;
    final service = _rooms;
    final ownsRoom =
        widget.currentUserId.isNotEmpty && room.hostId == widget.currentUserId;
    final hasStaffActions = _capabilities.hasRoomModeration;
    final trailing = ownsRoom || hasStaffActions
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ownsRoom)
                HomeOwnedRoomMenu(
                  key: ValueKey('owned-room-menu-${room.id}'),
                  room: room,
                  onManage: () => _openRoomSettings(room),
                  onDelete: () => _deleteOwnedRoom(room),
                  currentUserId: widget.currentUserId,
                  clubService: _clubs,
                ),
              if (hasStaffActions)
                RoomStaffMenu(room: room, capabilities: _capabilities),
            ],
          )
        : null;
    return HomeHereNowHero(
      key: const ValueKey('home-featured-room'),
      candidate: featured,
      roster: _rosters.entryFor(room.id),
      friendIds: friendIds,
      compact: false,
      expanded: true,
      trailing: trailing,
      onJoin: () => _openCandidate(featured),
      onOpenRoster: service == null
          ? null
          : () => openHomeRoomRoster(context, room, service, compact: false),
    );
  }
}

// ---------------------------------------------------------------- header

/// The greeting, as a card spanning the whole content width.
///
/// The bell and the avatar are the SAME destinations the rail's bell and
/// profile card open (O13) — one handler each, so the count on one can never
/// disagree with the count on the other. The availability chip is not here:
/// it lives on the "Ty" tile at the head of the friends row, in the More
/// sheet and on the rail's profile card (C2).
class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.profile,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.onOpenProfile,
  });

  final Stream<UserProfile>? profile;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      key: const ValueKey('home-greeting-card'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppRhythm.title,
        ),
        child: HomeGreetingHeader(
          profile: profile,
          expanded: true,
          unreadNotificationCount: unreadNotificationCount,
          onOpenNotifications: onOpenNotifications,
          onOpenProfile: onOpenProfile,
        ),
      ),
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

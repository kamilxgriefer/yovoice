import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_lounge_watcher.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_record_moment_card.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/shared/widgets/layout/status_bar_scrim.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart'
    show MomentViewedIds;
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';

/// Mobile Home — "Tu i teraz".
///
/// The shortest path from opening the app to being in a conversation, built
/// only from facts the client already holds:
///
///  - the account's own name, avatar and availability → [ProfileService]
///  - friends, their presence and their unheard Voice Moments →
///    [FriendService] + the existing social page, gated by real friendship
///  - one live room worth walking into, its real roster and its real cover →
///    [RoomService]
///  - the account's own places and their live voice rooms → [ClubService]
///  - recent conversations and owned rooms → the same flows as everywhere else
///
/// Opening this screen joins no audio, requests no microphone and writes no
/// roster row. Every way into a room from here ends at the existing pre-join
/// screen, which is the single consent boundary for both room products.
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
    this.onOpenServers,
    this.onOpenClub,
    this.onEnterClubLounge,
    this.roomService,
    this.clubService,
    this.friendService,
    this.followService,
    this.profileService,
    this.profileMediaService,
    this.feedService,
    this.messageService,
    this.capabilityService,
    this.presenceService,
    this.momentViewsService,
    this.currentUserId,
    this.isVisible,
    this.createRoomKey,
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

  /// Opens ONE Moment in the player. Retained: the shell owns this route and
  /// the Moments program consumes it; Home's own followed rail now lives in
  /// the Momenty destination.
  final ValueChanged<VoiceMoment> onOpenMoment;

  /// Opens one author's active Voice Moment chain in the story viewer — what
  /// a friend tile with a new Voice Moment taps through to.
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  /// Retained shell route (the comment thread of a Moment).
  final ValueChanged<VoiceMoment> onOpenComments;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onSeeAllChats;

  /// Retained shell route to the Momenty destination, which now owns the
  /// followed-Moments rail this screen used to draw.
  final VoidCallback? onSeeAllMoments;

  /// The Serwery destination: "Zobacz wszystkie" beside "W Twoich serwerach",
  /// and the rail's "+ Stwórz serwer" tile. Creation is gated inside that
  /// feature, which is where its own honest copy lives.
  final VoidCallback? onOpenServers;

  /// Opens one place (the existing club overview).
  final ValueChanged<Club>? onOpenClub;

  /// Resolves a member's club lounge and opens the pre-join screen. Never
  /// joins audio here — `prepareClubLounge` only checks membership.
  final ValueChanged<Club>? onEnterClubLounge;

  final RoomService? roomService;
  final ClubService? clubService;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final ProfileMediaService? profileMediaService;
  final HomeFeedService? feedService;

  final MessageService? messageService;
  final StaffCapabilityService? capabilityService;

  /// Test seam for the availability affordance on the own tile. Production
  /// passes null and the picker constructs a service only when a choice is
  /// actually made, so simply opening Home never touches presence.
  final PresenceService? presenceService;

  /// Test seam for the ONE `momentViews` listener behind the friend badges.
  final MomentViewsService? momentViewsService;

  /// The signed-in uid. Optional so tests need no Firebase app.
  final String? currentUserId;

  /// The guided tour's mobile Create anchor, forwarded to the quick-actions
  /// create pill (`home-quick-create-room`). The shell owns the key; Home
  /// only places it, so replaying the tour spotlights a real control.
  final GlobalKey? createRoomKey;

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
      _rooms = widget.roomService ?? RoomService();
      _liveRooms = _rooms!.watchLivePublicRooms();
      _owned = _rooms!.watchOwnedRooms();
    } catch (_) {
      _rooms = null;
    }
    _rosters = HomeRosterCache(service: _rooms)..addListener(_onRosters);
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
    _loadClubs();
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
      builder: (context, constraints) {
        // Medium widths (UI.md): 24 px gutters once the body is at least
        // 600 px wide. A tablet is NOT a stretched phone: past the 880 px
        // list measure the column stays 880 wide and centres.
        final width = constraints.maxWidth;
        final medium = width >= 600;
        final gutter = medium ? AppRhythm.section : AppRhythm.title;
        final frameInset = math.max(
          0.0,
          (width - math.min(width, ResponsiveContentWidth.list.maxWidth)) / 2,
        );
        final margin = frameInset + gutter;
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
                    margin: margin,
                    frameInset: frameInset,
                    gutter: gutter,
                    medium: medium,
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
    required double margin,
    required double frameInset,
    required double gutter,
    required bool medium,
    required AsyncSnapshot<List<VoiceRoom>> roomSnapshot,
    required AsyncSnapshot<List<FriendUser>> friendSnapshot,
    required AsyncSnapshot<List<Club>> clubSnapshot,
    required Map<String, HomePlace> lounges,
    required Set<String> viewedIds,
  }) {
    final copy = AppLocalizations.of(context);
    final live = roomSnapshot.data ?? const <VoiceRoom>[];
    // A failed room query is NOT an empty room list. Without this split,
    // "start one and your community will see it here" was printed over a
    // denial or a dead connection — advice the reader cannot act on.
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
                    _resolvedUserId,
                  );
            final candidates = _candidates(
              places: places,
              owned: owned,
              live: live,
              followedIds: followedIds,
              friendIds: friendIds,
            );
            // Ask for exactly the rosters the page can use, in priority
            // order, and never more than the pool's budget.
            _rosters.request(candidates.map((c) => c.roomId));
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
                  friendSnapshot: friendSnapshot,
                  margin: margin,
                  frameInset: frameInset,
                  gutter: gutter,
                  medium: medium,
                  roomSnapshot: roomSnapshot,
                  roomsUnavailable: roomsUnavailable,
                  roomsLoading: roomsLoading,
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

  /// The hero's candidate list — the shared rule, so the phone and the
  /// desktop can never disagree about which room "Tu i teraz" is about.
  List<HomeLiveCandidate> _candidates({
    required List<HomePlace> places,
    required List<VoiceRoom> owned,
    required List<VoiceRoom> live,
    required Set<String> followedIds,
    required Set<String> friendIds,
  }) => homeLiveCandidates(
    places: places,
    owned: owned,
    live: live,
    followedIds: followedIds,
    friendIds: friendIds,
  );

  Widget _buildList(
    BuildContext context, {
    required AppLocalizations copy,
    required double margin,
    required double frameInset,
    required double gutter,
    required bool medium,
    required AsyncSnapshot<List<VoiceRoom>> roomSnapshot,
    required AsyncSnapshot<List<FriendUser>> friendSnapshot,
    required bool roomsUnavailable,
    required bool roomsLoading,
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
    final quickActions = HomeQuickActions(
      key: _quickActionsKey,
      createRoomKey: widget.createRoomKey,
      onCreateRoom: widget.onCreateRoom,
      onFriends: widget.onOpenFriends,
    );
    final openServers = widget.onOpenServers ?? widget.onOpenDiscover;

    // The lounge watcher only ever receives the head of this list, so only
    // the head may be spoken about: a membership Home never looked at is not
    // a quiet membership. The rail below still shows every place — it makes
    // no activity claim — and the remainder is counted so the quiet card can
    // say what it actually checked.
    final checkedPlaces = places
        .take(HomeLoungeWatcher.budget)
        .toList(growable: false);
    final uncheckedPlaces = places.length - checkedPlaces.length;

    return StatusBarScrim(
      child: ListView(
        // The gutter is NOT the list's padding: the rails are full-bleed and
        // carry it inside their own scroll views, so their tiles scroll under
        // the frame edge instead of painting past the layout. Every other
        // child is wrapped in `_Gutter`.
        padding: EdgeInsets.fromLTRB(
          0,
          MediaQuery.paddingOf(context).top + AppRhythm.title,
          0,
          AppRhythm.page,
        ),
        children: [
          _Gutter(
            margin: margin,
            child: HomeGreetingHeader(
              profile: _profile,
              onOpenNotifications: widget.onOpenNotifications,
              onOpenProfile: widget.onOpenProfile,
              unreadNotificationCount: widget.unreadNotificationCount,
            ),
          ),
          // 1. Who can I talk to right now? Me first, then my friends,
          //    online first, then the way to add more.
          _Rail(
            frameInset: frameInset,
            child: HomePeopleStrip(
              // The list is already resolved above (the hero needs the same
              // ids): the strip renders it rather than opening a second
              // listener on the same query.
              friendsSnapshot: _friends == null ? null : friendSnapshot,
              friends: _friends,
              profile: _profile,
              presenceService: widget.presenceService,
              horizontalPadding: gutter,
              avatarRadius: 28,
              voiceByFriendId: voiceByFriend,
              onOpenVoice: widget.onOpenChain,
              onRetry: _retryFriends,
              onSeeAll: widget.onOpenFriends,
            ),
          ),
          // 2. What is happening right now, in my world?
          _Gutter(
            margin: margin,
            child: HomeSectionHeader(
              title: copy.homeHereNow,
              live: featured != null,
            ),
          ),
          _Gutter(
            margin: margin,
            child: _hereNow(
              context,
              copy: copy,
              featured: featured,
              friendIds: friendIds,
              roomsUnavailable: roomsUnavailable,
              roomsLoading: roomsLoading,
              error: roomSnapshot.error,
              quickActions: quickActions,
              medium: medium,
            ),
          ),
          // The invitation card embeds these actions itself; every other
          // state keeps them under the section. A failed room read must not
          // also cost the reader the way to start a room of their own — the
          // desktop composition has always said so, and the phone is the one
          // that carries the guided tour's Create anchor.
          if (!(featured == null && !roomsUnavailable && !roomsLoading)) ...[
            const SizedBox(height: AppRhythm.item),
            _Gutter(margin: margin, child: quickActions),
          ],
          // 3. Where my own places are talking.
          if (clubsUnavailable) ...[
            // The gap is a sibling, never padding inside the child: a page
            // child's layout box is its ink box, which is what keeps Home's
            // rhythm the number the source declares.
            const SizedBox(height: AppRhythm.section),
            _Gutter(
              margin: margin,
              child: HomeSectionError(
                key: const ValueKey('home-places-error'),
                error: clubError,
                message: copy.text(
                  "Couldn't load your places.",
                  'Nie udało się wczytać Twoich miejsc.',
                ),
                onRetry: _retryPlaces,
              ),
            ),
          ] else if (clubsLoading) ...[
            _Gutter(
              margin: margin,
              child: HomeSectionHeader(title: copy.homeYourPlaces),
            ),
            _Rail(
              frameInset: frameInset,
              child: HomePlacesLoading(horizontalPadding: gutter),
            ),
          ] else ...[
            if (places.isNotEmpty)
              _Gutter(
                margin: margin,
                child: HomeServerActivitySection(
                  places: checkedPlaces,
                  uncheckedPlaces: uncheckedPlaces,
                  rosters: _rosters,
                  onSeeAll: openServers,
                  onOpenPlace: (club) => widget.onOpenClub?.call(club),
                  onEnterLounge: (place) =>
                      widget.onEnterClubLounge?.call(place.club),
                  onRetryPlace: (_) => _retryPlaces(),
                ),
              ),
            // 4. Every place I belong to, as one row of doors.
            if (places.isEmpty) ...[
              _Gutter(
                margin: margin,
                child: HomeSectionHeader(title: copy.homeYourPlaces),
              ),
              _Gutter(
                margin: margin,
                child: HomePlacesEmptyCard(
                  onCreateServer: openServers,
                  onDiscover: widget.onOpenDiscover,
                ),
              ),
            ] else
              _Rail(
                frameInset: frameInset,
                child: HomePlacesRail(
                  places: places,
                  horizontalPadding: gutter,
                  onOpenPlace: (club) => widget.onOpenClub?.call(club),
                  onCreateServer: openServers,
                ),
              ),
          ],
          // 5. The one way to record, now that the followed rail lives in
          //    the Momenty destination.
          const SizedBox(height: AppRhythm.section),
          _Gutter(
            margin: margin,
            child: HomeRecordMomentCard(onCreateMoment: widget.onCreateMoment),
          ),
          // 6. Which conversations continue?
          _Gutter(
            margin: margin,
            child: HomeSectionHeader(
              title: copy.text('Your recent chats', 'Ostatnie czaty'),
              onSeeAll: widget.onSeeAllChats,
            ),
          ),
          _Gutter(
            key: const ValueKey('home-recent-chats'),
            margin: margin,
            child: StreamBuilder<List<Conversation>>(
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
                      currentUserId: _resolvedUserId,
                      onOpenConversation: widget.onOpenConversation,
                      onFindFriends: widget.onOpenFriends,
                      photoStreamForUser: _profiles == null
                          ? null
                          : _recentChatPhotoStream,
                      profileMediaService: widget.profileMediaService,
                    ),
            ),
          ),
          // 7. Owned rooms — hosts only. A non-host used to get a permanently
          //    empty card whose Create Room button duplicated the pill above.
          //    An error is still shown: it must never read as "no rooms".
          //
          //    Keyed on purpose: the block above it is variable in length, and
          //    an unkeyed list child that shifts index is rebuilt from scratch
          //    — which re-subscribes to an already-emitted broadcast stream and
          //    leaves a host's own rooms silently missing from Home.
          KeyedSubtree(
            key: const ValueKey('home-owned-rooms'),
            child: ownedFailed || owned.isNotEmpty
                ? _Gutter(
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
                        if (ownedFailed)
                          HomeSectionError(
                            error: ownedError,
                            message: copy.text(
                              'Could not load rooms',
                              'Nie udało się wczytać pokojów',
                            ),
                            onRetry: () => setState(
                              () => _owned = _rooms?.watchOwnedRooms(),
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
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
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
    required bool medium,
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
        onDiscover: widget.onOpenDiscover,
      );
    }
    final room = featured.room;
    final service = _rooms;
    final ownsRoom =
        _resolvedUserId.isNotEmpty && room.hostId == _resolvedUserId;
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
                  currentUserId: _resolvedUserId,
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
      compact: !medium,
      trailing: trailing,
      onJoin: () => _openCandidate(featured),
      onOpenRoster: service == null
          ? null
          : () => openHomeRoomRoster(context, room, service, compact: !medium),
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
  const _Rail({required this.frameInset, required this.child});

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

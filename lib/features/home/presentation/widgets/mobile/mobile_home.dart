import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_live_now.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_record_moment_card.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_server_overview.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart'
    show MomentViewedIds;
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/layout/status_bar_scrim.dart';

/// Mobile Home — the server-first “Tu i teraz” surface.
///
/// Friends remain the first content row. Every space and conversation entry
/// below it comes from [ServerRepository]; opening Home never subscribes to the
/// legacy public-room directory or presents a Club route. Legacy constructor
/// seams remain temporarily source-compatible for previews while the internal
/// Firestore room/club schema is migrated behind the Server facade.
class MobileHome extends StatefulWidget {
  const MobileHome({
    this.onOpenRoom,
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
    this.onOpenServer,
    this.onOpenClub,
    this.onEnterClubLounge,
    this.roomService,
    this.clubService,
    this.serverRepository,
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

  /// Retained only for source compatibility. Home no longer opens standalone
  /// rooms; all creation and discovery callbacks below land in Servers.
  final ValueChanged<VoiceRoom>? onOpenRoom;
  final VoidCallback onOpenDiscover;
  final VoidCallback? onOpenFindCreators;
  final VoidCallback onOpenFriends;
  final VoidCallback onOpenNotifications;
  final int unreadNotificationCount;
  final VoidCallback onOpenProfile;
  final VoidCallback onCreateMoment;

  /// The historical name is kept so older preview/test callers still compile.
  /// Product wiring passes the Servers destination here.
  final VoidCallback onCreateRoom;
  final ValueChanged<VoiceMoment> onOpenMoment;
  final ValueChanged<List<VoiceMoment>>? onOpenChain;
  final ValueChanged<VoiceMoment> onOpenComments;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onSeeAllChats;
  final VoidCallback? onSeeAllMoments;
  final VoidCallback? onOpenServers;
  final ValueChanged<Server>? onOpenServer;

  /// Inert compatibility seams. No current Home control invokes either one.
  final ValueChanged<Club>? onOpenClub;
  final ValueChanged<Club>? onEnterClubLounge;
  final RoomService? roomService;
  final ClubService? clubService;

  final ServerRepository? serverRepository;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final ProfileMediaService? profileMediaService;
  final HomeFeedService? feedService;
  final MessageService? messageService;
  final StaffCapabilityService? capabilityService;
  final PresenceService? presenceService;
  final MomentViewsService? momentViewsService;
  final String? currentUserId;
  final GlobalKey? createRoomKey;
  final ValueListenable<bool>? isVisible;

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  Stream<List<FriendUser>>? _friends;
  Stream<UserProfile>? _profile;
  ProfileService? _profiles;
  Stream<List<VoiceMoment>>? _feed;
  List<VoiceMoment>? _lastFeedPage;
  HomeFeedService? _feedSource;
  Stream<List<Conversation>>? _conversations;
  Stream<List<Server>>? _servers;
  ServerRepository? _serverRepository;
  final Map<String, Stream<String>> _recentChatPhotoStreams = {};
  bool _brandWarmed = false;

  String get _resolvedUserId {
    final injected = widget.currentUserId;
    if (injected != null) return injected;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  VoidCallback get _openServers =>
      widget.onOpenServers ?? widget.onOpenDiscover;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _loadProfile();
    _loadFeed();
    _loadChats();
    _loadServers();
    widget.isVisible?.addListener(_handleVisibility);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm the real logo and its pre-baked bloom so the Start lockup has its
    // mark on the first frame (refine-look §4). The mark decodes at its own
    // `cacheWidth`, which is part of the image cache key, so the warm-up
    // asks for exactly the sizes the lockup will paint. A failed warm-up is
    // not an error here: the mark's own errorBuilder owns a missing asset.
    if (_brandWarmed) return;
    _brandWarmed = true;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final mark = YoBrandLockup.markSizeFor(
      MediaQuery.sizeOf(context).width >= 600
          ? HomeGreetingHeader.brandMarkSizeMedium
          : HomeGreetingHeader.brandMarkSize,
      MediaQuery.textScalerOf(context),
    );
    for (final (asset, logical) in [
      (YoBrandMark.markAsset, mark),
      (YoBrandMark.bloomAsset, mark * 1.6),
    ]) {
      final image = ResizeImage.resizeIfNeeded(
        YoBrandMark.cacheWidthFor(logical, dpr),
        null,
        AssetImage(asset),
      );
      unawaited(precacheImage(image, context, onError: (_, _) {}));
    }
  }

  void _loadFriends() {
    try {
      _friends = (widget.friendService ?? FriendService()).watchFriends();
    } catch (error) {
      _friends = Stream<List<FriendUser>>.error(error);
    }
  }

  void _loadProfile() {
    try {
      _profiles = widget.profileService ?? ProfileService();
      _profile = _profiles!.watchCurrentProfile();
    } catch (error) {
      _profiles = null;
      _profile = Stream<UserProfile>.error(error);
    }
  }

  void _loadFeed() {
    try {
      _feedSource ??= widget.feedService ?? HomeFeedService();
      _feed = _feedSource!.watchSocialMoments();
    } catch (error) {
      _feed = Stream<List<VoiceMoment>>.error(error);
    }
  }

  void _loadChats() {
    try {
      _conversations = (widget.messageService ?? MessageService.live)
          .watchConversations();
    } catch (error) {
      _conversations = Stream<List<Conversation>>.error(error);
    }
  }

  void _loadServers() {
    try {
      _serverRepository ??= widget.serverRepository ?? ServerService();
      _servers = _serverRepository!.watchMyServers();
    } catch (error) {
      _servers = Stream<List<Server>>.error(error);
    }
  }

  void _handleVisibility() {
    if (widget.isVisible?.value != true || !mounted) return;
    setState(_loadFeed);
  }

  void _retryFriends() => setState(_loadFriends);
  void _retryChats() => setState(_loadChats);
  void _retryServers() => setState(_loadServers);

  Stream<String> _recentChatPhotoStream(String userId) =>
      _recentChatPhotoStreams.putIfAbsent(
        userId,
        () =>
            _profiles
                ?.watchProfile(userId)
                .map(
                  (profile) =>
                      profile.profileUpdatedAt?.toUtc().toIso8601String() ??
                      'legacy:${profile.uid}',
                )
                .distinct() ??
            Stream<String>.value(''),
      );

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoPageBackground(
      section: YoPageSection.home,
      decoration: const BoxDecoration(),
      child: HomeErrorAnnouncementScope(
        isVisible: widget.isVisible,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final medium = width >= 600;
            final gutter = medium ? AppRhythm.section : AppRhythm.title;
            final frameInset = math.max(
              0.0,
              (width - math.min(width, ResponsiveContentWidth.list.maxWidth)) /
                  2,
            );
            final margin = frameInset + gutter;
            return StreamBuilder<List<FriendUser>>(
              stream: _friends,
              builder: (context, friendSnapshot) => StreamBuilder<List<Server>>(
                stream: _servers,
                builder: (context, serverSnapshot) =>
                    StreamBuilder<List<VoiceMoment>>(
                      stream: _feed,
                      initialData: _lastFeedPage,
                      builder: (context, momentSnapshot) {
                        if (momentSnapshot.hasData &&
                            !momentSnapshot.hasError &&
                            momentSnapshot.connectionState !=
                                ConnectionState.waiting) {
                          _lastFeedPage = momentSnapshot.data;
                        }
                        return MomentViewedIds(
                          service: widget.momentViewsService,
                          builder: (context, viewedIds) => _buildPage(
                            context,
                            margin: margin,
                            frameInset: frameInset,
                            gutter: gutter,
                            friendSnapshot: friendSnapshot,
                            serverSnapshot: serverSnapshot,
                            momentSnapshot: momentSnapshot,
                            viewedIds: viewedIds,
                          ),
                        );
                      },
                    ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context, {
    required double margin,
    required double frameInset,
    required double gutter,
    required AsyncSnapshot<List<FriendUser>> friendSnapshot,
    required AsyncSnapshot<List<Server>> serverSnapshot,
    required AsyncSnapshot<List<VoiceMoment>> momentSnapshot,
    required Set<String> viewedIds,
  }) {
    final copy = AppLocalizations.of(context);
    final friendIds = {
      for (final friend in friendSnapshot.data ?? const <FriendUser>[])
        friend.id,
    };
    final voiceByFriend = momentSnapshot.hasError
        ? const <String, HomeFriendVoice>{}
        : homeFriendVoiceByAuthor(
            page: momentSnapshot.data ?? const <VoiceMoment>[],
            friendIds: friendIds,
            viewedMomentIds: viewedIds,
            now: DateTime.now(),
          );
    // With no server yet the empty invitation carries the page's one lifted
    // "Stwórz serwer"; the quick action keeps its gradient without a lift.
    final serversEmpty =
        serverSnapshot.hasData &&
        !serverSnapshot.hasError &&
        (serverSnapshot.data?.isEmpty ?? false);
    final quickActions = HomeQuickActions(
      createRoomKey: widget.createRoomKey,
      onCreateRoom: _openServers,
      onFriends: widget.onOpenFriends,
      liftCreate: !serversEmpty,
    );

    return _BottomSeamFade(
      child: StatusBarScrim(
        child: ListView(
          key: const ValueKey('mobile-home-server-first'),
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
            _Rail(
              frameInset: frameInset,
              child: HomePeopleStrip(
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
            // Slim phase 1: live channels of the viewer's own servers, only
            // when a channel document says live. Absent otherwise.
            _Rail(
              frameInset: frameInset,
              child: HomeLiveNowSection(
                servers: serverSnapshot.hasError
                    ? const <Server>[]
                    : serverSnapshot.data ?? const <Server>[],
                repository: _serverRepository,
                onOpenServer: (server) {
                  final openServer = widget.onOpenServer;
                  if (openServer != null) {
                    openServer(server);
                  } else {
                    _openServers();
                  }
                },
                horizontalPadding: gutter,
              ),
            ),
            _Gutter(
              margin: margin,
              child: HomeSectionHeader(title: copy.homeHereNow),
            ),
            _Gutter(
              margin: margin,
              child: HomeServerConversationCard(
                snapshot: serverSnapshot,
                onOpenServers: _openServers,
                onOpenServer: widget.onOpenServer,
                onRetry: _retryServers,
                expanded: MediaQuery.sizeOf(context).width >= 600,
              ),
            ),
            const SizedBox(height: AppRhythm.item),
            _Gutter(margin: margin, child: quickActions),
            if (serverSnapshot.hasData &&
                !serverSnapshot.hasError &&
                (serverSnapshot.data?.isNotEmpty ?? false)) ...[
              const SizedBox(height: AppRhythm.section),
              _Gutter(
                margin: margin,
                child: HomeServersOverview(
                  snapshot: serverSnapshot,
                  onOpenServers: _openServers,
                  onOpenServer: widget.onOpenServer,
                ),
              ),
            ],
            const SizedBox(height: AppRhythm.section),
            _Gutter(
              margin: margin,
              child: HomeRecordMomentCard(
                onCreateMoment: widget.onCreateMoment,
              ),
            ),
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
                builder: (context, snapshot) => snapshot.hasError
                    ? HomeSectionError(
                        key: const ValueKey('home-chats-error'),
                        error: snapshot.error,
                        message: copy.text(
                          'Your recent chats could not be loaded.',
                          'Nie udało się wczytać ostatnich czatów.',
                        ),
                        onRetry: _retryChats,
                      )
                    : RecentChats(
                        snapshot: snapshot,
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
          ],
        ),
      ),
    );
  }
}

/// The page's lower edge above the dock (refine-look §8.1, "seam").
///
/// While there is more of Start below the fold, the last 24 px of the list
/// dissolve into the canvas instead of ending on a hard horizontal cut. At
/// the end of the page the fade is gone, so the last block is never dimmed.
/// Decoration only: it never takes a pointer or a semantics node, and it
/// listens to the page's own vertical scroll (depth 0) — never to the
/// horizontal rails inside it. The dock and the shell are untouched.
class _BottomSeamFade extends StatefulWidget {
  const _BottomSeamFade({required this.child});

  final Widget child;

  static const double height = 24;

  @override
  State<_BottomSeamFade> createState() => _BottomSeamFadeState();
}

class _BottomSeamFadeState extends State<_BottomSeamFade> {
  final ValueNotifier<bool> _moreBelow = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _moreBelow.dispose();
    super.dispose();
  }

  bool _track(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return false;
    final moreBelow = metrics.extentAfter > .5;
    if (moreBelow == _moreBelow.value) return false;
    // A scroll position can notify from inside layout (new content
    // dimensions start a ballistic settle); the fade then follows on the
    // next frame instead of rebuilding in the middle of this one.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moreBelow.value = moreBelow;
      });
    } else {
      _moreBelow.value = moreBelow;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final canvas = context.appPalette.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _track(n.metrics, n.depth),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _track(n.metrics, n.depth),
            child: widget.child,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _BottomSeamFade.height,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ValueListenableBuilder<bool>(
                valueListenable: _moreBelow,
                builder: (context, moreBelow, _) => AnimatedOpacity(
                  key: const ValueKey('mobile-home-seam-fade'),
                  opacity: moreBelow ? 1 : 0,
                  duration: AppMotion.resolve(context, AppMotion.quick),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [canvas.withValues(alpha: 0), canvas],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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

class _Rail extends StatelessWidget {
  const _Rail({required this.frameInset, required this.child});

  final double frameInset;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: frameInset),
    child: child,
  );
}

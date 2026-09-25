import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
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
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Wide, server-first Home surface. Friends stay immediately below the
/// greeting; all space entries below that row come from [ServerRepository].
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    required this.currentUserId,
    this.onOpenRoom,
    required this.onSeeAllRooms,
    this.onFindCreators,
    required this.onViewAllFriends,
    required this.onStartRoom,
    required this.onOpenMoment,
    required this.onCreateMoment,
    required this.onSeeAllMoments,
    this.onOpenChain,
    required this.onOpenConversation,
    this.onOpenClub,
    required this.onSeeAllChats,
    required this.onOpenClubs,
    this.onOpenNotifications,
    this.onOpenProfile,
    this.onOpenServers,
    this.onOpenServer,
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
    this.serverRepository,
    this.momentViewsService,
    this.firebaseAuth,
    this.capabilityService,
    this.presenceService,
    this.trailingContent,
    this.isVisible,
    super.key,
  });

  final String currentUserId;
  final ValueChanged<VoiceRoom>? onOpenRoom;
  final VoidCallback onSeeAllRooms;
  final VoidCallback? onFindCreators;
  final VoidCallback onViewAllFriends;
  final VoidCallback onStartRoom;
  final ValueChanged<VoiceMoment> onOpenMoment;
  final VoidCallback onCreateMoment;
  final VoidCallback onSeeAllMoments;
  final ValueChanged<List<VoiceMoment>>? onOpenChain;
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<Club>? onOpenClub;
  final VoidCallback onSeeAllChats;
  final VoidCallback onOpenClubs;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenServers;
  final ValueChanged<Server>? onOpenServer;
  final ValueChanged<Club>? onEnterClubLounge;
  final int unreadNotificationCount;

  // Legacy service seams stay source-compatible while the schema remains.
  final RoomService? roomService;
  final FriendService? friendService;
  final FollowService? followService;
  final ProfileService? profileService;
  final ProfileMediaService? profileMediaService;
  final HomeFeedService? feedService;
  final MessageService? messageService;
  final ClubService? clubService;
  final ClubChatService? clubChatService;
  final ServerRepository? serverRepository;
  final MomentViewsService? momentViewsService;
  final FirebaseAuth? firebaseAuth;
  final StaffCapabilityService? capabilityService;
  final PresenceService? presenceService;
  final Widget? trailingContent;
  final ValueListenable<bool>? isVisible;

  static const double twoColumnThreshold = 1000;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  final _peopleKey = GlobalKey();
  final _conversationKey = GlobalKey();
  final _chatsKey = GlobalKey();
  final _quickActionsKey = GlobalKey();
  final _placesKey = GlobalKey();
  final _recordKey = GlobalKey();

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

  VoidCallback get _openServers => widget.onOpenServers ?? widget.onSeeAllRooms;

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
  Widget build(BuildContext context) => YoPageBackground(
    section: YoPageSection.home,
    decoration: const BoxDecoration(),
    child: HomeErrorAnnouncementScope(
      isVisible: widget.isVisible,
      child: ResponsiveContentFrame(
        width: ResponsiveContentWidth.workbench,
        child: LayoutBuilder(
          builder: (context, constraints) => StreamBuilder<List<FriendUser>>(
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
                          slot: constraints.maxWidth,
                          friendSnapshot: friendSnapshot,
                          serverSnapshot: serverSnapshot,
                          momentSnapshot: momentSnapshot,
                          viewedIds: viewedIds,
                        ),
                      );
                    },
                  ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildPage(
    BuildContext context, {
    required double slot,
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
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final extraScale = (scale - 1).clamp(0.0, 2.0);
    final twoColumns =
        slot >= DesktopHome.twoColumnThreshold + extraScale * 260;
    final contextWidth = (300 + extraScale * 40).clamp(280.0, 344.0);

    // Desktop Start always sits beside the rail, whose own "Stwórz serwer"
    // is the screen's one lifted CTA: Start's create keeps the matching
    // gradient without a second lift. With no server yet the empty
    // invitation carries Start's violet "Stwórz serwer", so the quick action
    // steps down to the same neutral glass as "Znajomi".
    final serversEmpty =
        serverSnapshot.hasData &&
        !serverSnapshot.hasError &&
        (serverSnapshot.data?.isEmpty ?? false);
    final quickActions = HomeQuickActions(
      key: _quickActionsKey,
      onCreateRoom: _openServers,
      onFriends: widget.onViewAllFriends,
      createEmphasis: serversEmpty
          ? YoActionEmphasis.neutral
          : YoActionEmphasis.flat,
    );
    final conversationSection = Column(
      key: _conversationKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: copy.homeHereNow,
          scale: HomeSectionHeaderScale.expanded,
        ),
        HomeServerConversationCard(
          snapshot: serverSnapshot,
          onOpenServers: _openServers,
          onOpenServer: widget.onOpenServer,
          onRetry: _retryServers,
          expanded: true,
          // The rail owns the screen's one lift (see the quick actions).
          liftCreate: false,
        ),
        const SizedBox(height: AppRhythm.item),
        quickActions,
      ],
    );
    final serversSection = KeyedSubtree(
      key: _placesKey,
      child: HomeServersOverview(
        snapshot: serverSnapshot,
        onOpenServers: _openServers,
        onOpenServer: widget.onOpenServer,
        expandedHeading: true,
      ),
    );
    final recordCard = KeyedSubtree(
      key: _recordKey,
      child: HomeRecordMomentCard(onCreateMoment: widget.onCreateMoment),
    );
    final chatsSection = ClipRect(
      key: _chatsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSectionHeader(
            title: copy.text('Your recent chats', 'Ostatnie czaty'),
            scale: twoColumns
                ? HomeSectionHeaderScale.compact
                : HomeSectionHeaderScale.expanded,
            onSeeAll: widget.onSeeAllChats,
          ),
          StreamBuilder<List<Conversation>>(
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
    final peopleSection = HomePeopleStrip(
      key: _peopleKey,
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

    // Slim phase 1: live channels of the viewer's own servers, only when a
    // channel document says live; it heads the main column so the
    // secondary column keeps its top line.
    final liveSection = HomeLiveNowSection(
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
      expanded: true,
    );

    return ListView(
      key: const ValueKey('desktop-home-server-first'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppRhythm.title,
        AppSpacing.xl,
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
        peopleSection,
        if (twoColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  key: const ValueKey('home-main-column'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    liveSection,
                    conversationSection,
                    const SizedBox(height: AppRhythm.section),
                    serversSection,
                  ],
                ),
              ),
              const SizedBox(width: AppRhythm.section),
              SizedBox(
                key: const ValueKey('home-secondary-column'),
                width: contextWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppRhythm.section),
                    recordCard,
                    chatsSection,
                  ],
                ),
              ),
            ],
          )
        else ...[
          liveSection,
          conversationSection,
          const SizedBox(height: AppRhythm.section),
          serversSection,
          const SizedBox(height: AppRhythm.section),
          recordCard,
          chatsSection,
        ],
        if (widget.trailingContent != null) ...[
          const SizedBox(height: AppRhythm.section),
          widget.trailingContent!,
        ],
      ],
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
    // Slim: the greeting is chrome, so it sits on the canvas without a card
    // behind it (no hero banner that carries no data). The key stays on the
    // same box, and the vertical rhythm is unchanged.
    return KeyedSubtree(
      key: const ValueKey('home-greeting-card'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppRhythm.title),
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

/// Compatibility roster for a server-bound voice channel. Every row is a
/// real participant document from the legacy session stream, so there is
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
            'Nobody is in this channel yet.',
            'Na tym kanale nikogo jeszcze nie ma.',
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
              '${participants.length} in the channel',
              '${participants.length} na kanale',
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

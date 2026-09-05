import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/from_your_clubs.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/discover_clubs_rail.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/live_now_hero.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_card.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({this.onOpenDiscover, super.key});

  final VoidCallback? onOpenDiscover;

  static VoidCallback? openDiscoverTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeFeedService _feedService = HomeFeedService();
  final FriendService _friendService = FriendService();
  final RoomService _roomService = RoomService();
  final MomentService _momentService = MomentService();
  final NotificationService _notificationService = NotificationService();
  final ProfileService _profileService = ProfileService();

  late final Stream<List<VoiceMoment>> _moments;
  late final Stream<List<FriendUser>> _friends;
  late final Stream<List<VoiceRoom>> _rooms;

  /// Not `final`: a Firestore snapshot subscription is terminated by its
  /// first error, so the rail's "Try again" has to hand the StreamBuilder a
  /// freshly subscribed stream rather than the dead one.
  late Stream<List<Club>> _clubs;
  late final Stream<UserProfile> _profile;

  @override
  void initState() {
    super.initState();
    _moments = _feedService.watchSocialMoments();
    _friends = _friendService.watchFriends();
    _rooms = _roomService.watchLivePublicRooms();
    _clubs = _feedService.watchSuggestedClubs();
    _profile = _profileService.watchCurrentProfile();
  }

  void _reloadSuggestedClubs() {
    if (!mounted) return;
    setState(() => _clubs = _feedService.watchSuggestedClubs());
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _openComments(VoiceMoment moment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(moment: moment),
      ),
    );
  }

  Future<void> _recordMoment({VoiceMoment? replyTo}) async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecordVoiceMomentScreen(
          replyToMomentId: replyTo?.id,
          replyToAuthorName: replyTo?.authorName,
        ),
      ),
    );

    if (!mounted || published != true) {
      return;
    }

    if (replyTo != null) {
      await _openComments(replyTo);
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).text(
              'Voice Moment posted to your feed.',
              'Voice Moment został opublikowany na Twojej tablicy.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Creates or resolves the deterministic lounge for preview. Membership is
  /// checked here, but roster/audio entry remains RoomEntryScreen's one job.
  Future<void> _joinClubLounge(Club club, VoiceRoom lounge) async {
    try {
      final room = await _roomService.prepareClubLounge(
        clubId: club.id,
        clubName: club.name,
        clubDescription: club.description,
        language: club.defaultLanguage,
        ownerId: club.ownerId,
        ownerName: club.ownerName,
        imageUrl: club.avatarUrl,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              intentionalOrFriendly(
                error,
                fallback: AppLocalizations.of(context).text(
                  "Couldn't open this club room. Please try again.",
                  'Nie udało się otworzyć pokoju klubu. Spróbuj ponownie.',
                ),
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openRoom(VoiceRoom room) async {
    try {
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              intentionalOrFriendly(
                error,
                fallback: AppLocalizations.of(context).text(
                  "Couldn't open this room. Please try again.",
                  'Nie udało się otworzyć pokoju. Spróbuj ponownie.',
                ),
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _deleteMoment(VoiceMoment moment) async {
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surfaceRaised,
        title: Text(
          copy.text('Delete Voice Moment?', 'Usunąć Voice Moment?'),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          copy.text(
            'This removes the recording, likes, and all comments permanently.',
            'Nagranie, polubienia i wszystkie komentarze zostaną trwale '
                'usunięte.',
          ),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(copy.text('Delete', 'Usuń')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _momentService.deleteMoment(moment);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              copy.text(
                'Voice Moment deleted.',
                'Voice Moment został usunięty.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                fallback: copy.text(
                  'Could not delete the Voice Moment. Please try again.',
                  'Nie udało się usunąć Voice Momentu. Spróbuj ponownie.',
                ),
                copy: copy,
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final fallbackFullName = user?.displayName?.trim();
    final fallbackName = fallbackFullName?.isNotEmpty == true
        ? fallbackFullName!.split(' ').first
        : user?.email?.split('@').first ?? copy.text('there', 'Cześć');

    return Scaffold(
      backgroundColor: palette.background,
      body: YoPageBackground(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.9, -1),
            radius: 1.35,
            colors: [
              Color.alphaBlend(
                colorScheme.primary.withValues(alpha: .18),
                palette.backgroundTop,
              ),
              palette.backgroundTop,
              palette.background,
            ],
            stops: const [0, .35, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.feed,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: StreamBuilder<UserProfile>(
                    stream: _profile,
                    builder: (context, snapshot) {
                      final profile = snapshot.data;
                      // Firestore's profile doc is the single source of truth
                      // other screens (Settings, Creator Studio) already read
                      // from -- FirebaseAuth's own currentUser.photoURL/
                      // displayName are a non-reactive snapshot that only
                      // updates on full sign-in, so a freshly-uploaded avatar
                      // never appeared here until the next cold start. Fall
                      // back to the Auth snapshot only for the first frame,
                      // before the stream has emitted.
                      final name = profile != null
                          ? (profile.displayName.trim().isNotEmpty
                                ? profile.displayName.trim().split(' ').first
                                : fallbackName)
                          : fallbackName;
                      // Single source of truth: the Firestore profile doc.
                      // This used to fall back to FirebaseAuth's own
                      // currentUser.photoURL whenever profile.photoUrl was
                      // null, which meant Home could show a stale Google
                      // avatar (or nothing) while Profile showed the real
                      // one. Before the stream's first emission `profile` is
                      // null and the avatar simply renders its placeholder.
                      return _header(
                        name,
                        profile?.photoUrl,
                        userId: profile?.uid,
                        mediaRevision: profile?.profileUpdatedAt,
                        premium: profile?.premiumIdentity ?? false,
                      );
                    },
                  ),
                ),
                // Mockup order: LIVE NOW hero → Your people → Rooms for
                // you → From your Clubs; Moments/feed follow below. The
                // hero absorbs the old Live Pulse stat card (same _rooms
                // stream, presented as a place instead of a number).
                SliverToBoxAdapter(
                  child: StreamBuilder<List<VoiceRoom>>(
                    stream: _rooms,
                    builder: (context, snapshot) {
                      final live = snapshot.data ?? const <VoiceRoom>[];
                      return LiveNowHero(
                        room: live.isEmpty ? null : live.first,
                        onJoin: _openRoom,
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(child: _activeFriends()),
                SliverToBoxAdapter(child: _liveRooms()),
                SliverToBoxAdapter(
                  child: FromYourClubs(onJoinLounge: _joinClubLounge),
                ),
                SliverToBoxAdapter(child: _voiceStories()),
                SliverToBoxAdapter(
                  child: _sectionTitle(copy.text('Your feed', 'Twoja tablica')),
                ),
                SliverToBoxAdapter(child: _feed()),
                SliverToBoxAdapter(child: _suggestedClubs()),
                SliverToBoxAdapter(child: _trending()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timeOfDayGreeting() {
    final copy = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    if (hour < 5) return copy.text('Up late,', 'Jeszcze nie śpisz,');
    if (hour < 12) return copy.text('Good morning,', 'Dzień dobry,');
    if (hour < 18) return copy.text('Good afternoon,', 'Dzień dobry,');
    return copy.text('Good evening,', 'Dobry wieczór,');
  }

  Widget _header(
    String name,
    String? photoUrl, {
    String? userId,
    Object? mediaRevision,
    bool premium = false,
  }) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _timeOfDayGreeting(),
                  style: TextStyle(color: palette.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '$name 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.text(
                    'Ready to hear something real?',
                    'Masz ochotę posłuchać czegoś prawdziwego?',
                  ),
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          StreamBuilder<int>(
            stream: _notificationService.watchUnreadCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton.outlined(
                    onPressed: _openNotifications,
                    tooltip: unreadCount > 0
                        ? copy.text(
                            'Notifications. New: $unreadCount',
                            'Powiadomienia. Nowe: $unreadCount',
                          )
                        : copy.notifications,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      side: BorderSide(color: palette.borderStrong),
                    ),
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.background,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: AppColors.onLive,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 10),
          // Your own avatar is always a door to your Profile — Profile
          // left the primary navigation when Friends took its tab.
          Semantics(
            button: true,
            label: copy.text('Open your profile', 'Otwórz swój profil'),
            child: Tooltip(
              message: copy.text('Open your profile', 'Otwórz swój profil'),
              child: InkResponse(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                ),
                radius: 28,
                child: UserAvatar(
                  radius: 24,
                  userId: userId,
                  photoUrl: photoUrl,
                  mediaRevision: mediaRevision,
                  fallbackIcon: Icons.person_rounded,
                  premium: premium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The one thing that makes YO Voice YO Voice: real, currently-live rooms
  // you can join in one tap. Previously only surfaced as a count inside the
  // Live Pulse banner (tap-through to Discover); that made rooms feel like
  // a statistic instead of a place. Reuses the same _rooms stream the
  // banner already subscribes to and the same join-then-enter flow
  // Discover uses (RoomService.joinRoom -> RoomEntryScreen) — no new data
  // source, no fabricated activity.
  Widget _liveRooms() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<VoiceRoom>>(
      stream: _rooms,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const <VoiceRoom>[];
        if (rooms.isEmpty) return const SizedBox.shrink();
        final visible = rooms.take(10).toList(growable: false);

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 0, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    copy.text('Rooms for you', 'Pokoje dla Ciebie'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.live,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 174,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 18),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 11),
                  itemBuilder: (context, index) {
                    final room = visible[index];
                    return _LiveRoomCard(
                      room: room,
                      onTap: () => _openRoom(room),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _voiceStories() {
    return StreamBuilder<List<VoiceMoment>>(
      stream: _moments,
      builder: (context, snapshot) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
        final allMoments = snapshot.data ?? const <VoiceMoment>[];

        VoiceMoment? myLatestMoment;
        final unique = <String, VoiceMoment>{};
        for (final moment in allMoments) {
          if (moment.authorId == currentUserId) {
            myLatestMoment ??= moment;
            continue;
          }
          unique.putIfAbsent(moment.authorId, () => moment);
        }

        final stories = unique.values.take(12).toList(growable: false);

        return SizedBox(
          height: 122,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            children: [
              // Reads the shared profile stream rather than
              // FirebaseAuth.currentUser.photoURL, which is a separate,
              // non-reactive store that never updates after an avatar
              // change. The moment's own authorPhotoUrl still wins when
              // present — it is a snapshot of how the moment was posted.
              StreamBuilder<UserProfile>(
                stream: _profile,
                builder: (context, profileSnapshot) => _StoryBubble(
                  label: 'YO Moments',
                  photoUrl:
                      myLatestMoment?.authorPhotoUrl ??
                      profileSnapshot.data?.photoUrl,
                  isAdd: myLatestMoment == null,
                  showAddBadge: myLatestMoment != null,
                  onTap: () {
                    final moment = myLatestMoment;
                    if (moment == null) {
                      _recordMoment();
                    } else {
                      _showMomentPlayer(moment);
                    }
                  },
                  onAddTap: () => _recordMoment(),
                ),
              ),
              ...stories.map(
                (moment) => _StoryBubble(
                  label: moment.authorName,
                  photoUrl: moment.authorPhotoUrl,
                  onTap: () => _showMomentPlayer(moment),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 10),
      child: Text(
        title,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _feed() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<VoiceMoment>>(
      stream: _moments,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(34),
            child: Center(
              child: CircularProgressIndicator(
                color: palette.interactiveForeground,
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _empty(
            copy.text(
              'Could not load your feed.',
              'Nie udało się wczytać Twojej tablicy.',
            ),
          );
        }
        final moments = snapshot.data ?? const <VoiceMoment>[];
        if (moments.isEmpty) {
          return _empty(
            copy.text(
              'Follow people or add friends to build your voice feed.',
              'Obserwuj innych lub dodaj znajomych, aby zbudować swoją '
                  'tablicę głosową.',
            ),
          );
        }
        return Column(
          children: moments.take(10).map((moment) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: _VoiceMomentCard(
                moment: moment,
                feedService: _feedService,
                onReply: () => _recordMoment(replyTo: moment),
                onComment: () => _openComments(moment),
                onDelete: () => _deleteMoment(moment),
                onShare: () => SharePlus.instance.share(
                  ShareParams(
                    text: copy.text(
                      'Listen to ${moment.authorName} on YO Voice: '
                          'https://yovoice.app/?moment=${moment.id}',
                      'Posłuchaj ${moment.authorName} w YO Voice: '
                          'https://yovoice.app/?moment=${moment.id}',
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // YOUR PEOPLE (mockup): horizontal status-ring row — online friends
  // first, ring language centralized in PeopleStatus. Tap opens the
  // profile preview (Message lives there); richer statuses (Speaking /
  // In a room / In a club) light up once presence carries room context —
  // never faked before then.
  Widget _activeFriends() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<FriendUser>>(
      stream: _friends,
      builder: (context, snapshot) {
        final friends = [...(snapshot.data ?? const <FriendUser>[])]
          ..sort((a, b) => (b.isOnline ? 1 : 0) - (a.isOnline ? 1 : 0));
        if (friends.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  copy.text('Your people', 'Twoi znajomi'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 124,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return PeopleStatusAvatar(
                      displayName: friend.displayName,
                      userId: friend.id,
                      photoUrl: friend.photoUrl,
                      status: friend.isOnline
                          ? PeopleStatus.online
                          : PeopleStatus.away,
                      onTap: () => showProfilePreview(
                        context,
                        userId: friend.id,
                        displayName: friend.displayName,
                        photoUrl: friend.photoUrl,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// "Discover clubs". Every state the stream can be in is rendered by
  /// [DiscoverClubsRail] — including the two this section used to collapse
  /// into an invisible `SizedBox.shrink()`, which is how a permission
  /// denial on `clubs` stayed hidden for the whole life of the product.
  Widget _suggestedClubs() {
    return StreamBuilder<List<Club>>(
      stream: _clubs,
      builder: (context, snapshot) => DiscoverClubsRail(
        snapshot: snapshot,
        onOpenClub: (club) => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ClubOverviewScreen(clubId: club.id),
          ),
        ),
        onRetry: _reloadSuggestedClubs,
      ),
    );
  }

  Widget _trending() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<VoiceMoment>>(
      stream: _moments,
      builder: (context, snapshot) {
        final allMoments = snapshot.data ?? const <VoiceMoment>[];
        // Excludes whatever "Your feed" above already rendered (its first
        // 10, same stream) so this surfaces genuinely different content
        // instead of the same handful of cards re-sorted by like count.
        final alreadyShown = allMoments
            .take(10)
            .map((moment) => moment.id)
            .toSet();
        final moments =
            allMoments
                .where((moment) => !alreadyShown.contains(moment.id))
                .toList()
              ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
        if (moments.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Trending Voice', 'Popularne głosy'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 11),
              ...moments
                  .take(3)
                  .map(
                    (moment) => ListTile(
                      onTap: () => _showMomentPlayer(moment),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      tileColor: palette.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                        side: BorderSide(color: palette.border),
                      ),
                      leading: Icon(
                        Icons.graphic_eq_rounded,
                        color: palette.interactiveForeground,
                      ),
                      title: Text(
                        moment.authorName,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        moment.caption.isEmpty
                            ? copy.text('Voice Moment', 'Voice Moment')
                            : moment.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.textSecondary),
                      ),
                      trailing: Text(
                        '❤ ${moment.likeCount}',
                        style: TextStyle(
                          color: palette.dangerForeground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(String message) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary),
        ),
      ),
    );
  }

  Future<void> _showMomentPlayer(VoiceMoment moment) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 720,
      ),
      builder: (_) => _MomentPlayerSheet(moment: moment),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.label,
    required this.onTap,
    this.photoUrl,
    this.isAdd = false,
    this.showAddBadge = false,
    this.onAddTap,
  });

  final String label;
  final String? photoUrl;
  final bool isAdd;
  final bool showAddBadge;
  final VoidCallback onTap;
  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: 82,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.primary,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: palette.surfaceRaised,
                    backgroundImage: photoUrl?.isNotEmpty == true
                        ? NetworkImage(photoUrl!)
                        : null,
                    child: isAdd
                        ? Icon(
                            Icons.add_rounded,
                            color: palette.interactiveForeground,
                            size: 30,
                          )
                        : photoUrl?.isNotEmpty == true
                        ? null
                        : Icon(
                            Icons.graphic_eq_rounded,
                            color: palette.interactiveForeground,
                          ),
                  ),
                ),
              ),
              if (showAddBadge)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: InkWell(
                    onTap: onAddTap,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.background, width: 3),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _VoiceMomentCard extends StatefulWidget {
  const _VoiceMomentCard({
    required this.moment,
    required this.feedService,
    required this.onReply,
    required this.onComment,
    required this.onShare,
    required this.onDelete,
  });
  final VoiceMoment moment;
  final HomeFeedService feedService;
  final VoidCallback onReply;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  State<_VoiceMomentCard> createState() => _VoiceMomentCardState();
}

class _VoiceMomentCardState extends State<_VoiceMomentCard> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _playing = false;
  late bool _liked;
  late int _likeCount;
  bool _likePending = false;
  bool _hasLocalLikeOverride = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.moment.callerLiked;
    _likeCount = widget.moment.likeCount;
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  @override
  void didUpdateWidget(covariant _VoiceMomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id) {
      _liked = widget.moment.callerLiked;
      _likeCount = widget.moment.likeCount;
      _likePending = false;
      _hasLocalLikeOverride = false;
    } else if (!_likePending &&
        (!_hasLocalLikeOverride || widget.moment.callerLiked == _liked)) {
      _liked = widget.moment.callerLiked;
      _likeCount = widget.moment.likeCount;
      _hasLocalLikeOverride = false;
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final url = widget.moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).text(
              'This moment does not have uploaded audio yet.',
              'Ten Moment nie ma jeszcze przesłanego nagrania.',
            ),
          ),
        ),
      );
      return;
    }
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(url));
    }
  }

  Future<void> _toggleLike() async {
    if (_likePending) return;
    final previousLiked = _liked;
    final previousCount = _likeCount;
    final desiredLiked = !previousLiked;
    setState(() {
      _liked = desiredLiked;
      _likeCount = (previousCount + (desiredLiked ? 1 : -1)).clamp(0, 1 << 31);
      _likePending = true;
      _hasLocalLikeOverride = true;
    });
    try {
      await widget.feedService.setLike(widget.moment.id, liked: desiredLiked);
      if (!mounted) return;
      setState(() => _likePending = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = previousLiked;
        _likeCount = previousCount;
        _likePending = false;
        _hasLocalLikeOverride = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              AppLocalizations.of(context).text(
                'Your like could not be saved. Try again.',
                'Nie udało się zapisać polubienia. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final time = moment.createdAt == null
        ? copy.text('now', 'teraz')
        : copy.relativeCompactTime(moment.createdAt!);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundImage: moment.authorPhotoUrl?.isNotEmpty == true
                    ? NetworkImage(moment.authorPhotoUrl!)
                    : null,
                child: moment.authorPhotoUrl?.isNotEmpty == true
                    ? null
                    : Text(
                        moment.authorName.isEmpty
                            ? '?'
                            : moment.authorName[0].toUpperCase(),
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moment.authorName,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: copy.text('Moment options', 'Opcje Momentu'),
                color: palette.surfaceRaised,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: palette.textTertiary,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'comments':
                      widget.onComment();
                    case 'share':
                      widget.onShare();
                    case 'delete':
                      widget.onDelete();
                  }
                },
                itemBuilder: (context) {
                  final isOwner =
                      FirebaseAuth.instance.currentUser?.uid == moment.authorId;
                  return [
                    PopupMenuItem<String>(
                      value: 'comments',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: palette.textPrimary,
                        ),
                        title: Text(
                          copy.text('View comments', 'Zobacz komentarze'),
                          style: TextStyle(color: palette.textPrimary),
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'share',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.share_outlined,
                          color: palette.textPrimary,
                        ),
                        title: Text(
                          copy.text('Share', 'Udostępnij'),
                          style: TextStyle(color: palette.textPrimary),
                        ),
                      ),
                    ),
                    if (isOwner)
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: palette.dangerForeground,
                          ),
                          title: Text(
                            copy.text(
                              'Delete Voice Moment',
                              'Usuń Voice Moment',
                            ),
                            style: TextStyle(color: palette.dangerForeground),
                          ),
                        ),
                      ),
                  ];
                },
              ),
            ],
          ),
          if (moment.caption.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              moment.caption,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          InkWell(
            onTap: _togglePlay,
            borderRadius: BorderRadius.circular(19),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primaryContainer, palette.surfaceRaised],
                ),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: palette.borderStrong),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: colorScheme.onPrimary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: _MiniWaveform()),
                  const SizedBox(width: 10),
                  Text(
                    moment.durationLabel,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _Action(
                  icon: _liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '$_likeCount',
                  active: _liked,
                  onTap: _likePending ? null : _toggleLike,
                ),
              ),
              Expanded(
                child: _Action(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${moment.commentCount}',
                  onTap: widget.onComment,
                ),
              ),
              Expanded(
                child: _Action(
                  icon: Icons.share_outlined,
                  label: copy.text('Share', 'Udostępnij'),
                  onTap: widget.onShare,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: widget.onReply,
              icon: const Icon(Icons.mic_rounded, size: 19),
              label: Text(copy.text('Reply with voice', 'Odpowiedz głosem')),
              style: TextButton.styleFrom(
                foregroundColor: palette.interactiveForeground,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniWaveform extends StatelessWidget {
  const _MiniWaveform();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        24,
        (index) => Expanded(
          child: Container(
            height: (10 + ((index * 13) % 24)).toDouble(),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: context.appPalette.interactiveForeground,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: active
            ? palette.dangerForeground
            : palette.textSecondary,
      ),
    );
  }
}

class _LiveRoomCard extends StatelessWidget {
  const _LiveRoomCard({required this.room, required this.onTap});

  final VoiceRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Rooms 2.0 identity card — cover-forward, type-differentiated
    // (Community / Podcast / Club read differently at a glance).
    return RoomCard(room: room, onTap: onTap, width: 224, height: 172);
  }
}

class _MomentPlayerSheet extends StatefulWidget {
  const _MomentPlayerSheet({required this.moment});
  final VoiceMoment moment;
  @override
  State<_MomentPlayerSheet> createState() => _MomentPlayerSheetState();
}

class _MomentPlayerSheetState extends State<_MomentPlayerSheet> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(url));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 34),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoModalSheetChrome(
            sheetLabel: copy.text('Moment player', 'Odtwarzacz Momentu'),
            surfaceColor: palette.surfaceRaised,
          ),
          const SizedBox(height: 4),
          CircleAvatar(
            radius: 42,
            backgroundImage: widget.moment.authorPhotoUrl?.isNotEmpty == true
                ? NetworkImage(widget.moment.authorPhotoUrl!)
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            widget.moment.authorName,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.moment.caption,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: _toggle,
            customBorder: const CircleBorder(),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: colorScheme.onPrimary,
                size: 42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

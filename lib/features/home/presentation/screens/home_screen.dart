import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({this.onOpenDiscover, super.key});

  final VoidCallback? onOpenDiscover;

  static VoidCallback? openDiscoverTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF14101D);
  static const _border = Color(0xFF352642);
  static const _muted = Color(0xFFA79DAF);
  static const _primary = Color(0xFFA51FFF);

  final HomeFeedService _feedService = HomeFeedService();
  final FriendService _friendService = FriendService();
  final RoomService _roomService = RoomService();
  final MessageService _messageService = MessageService();
  final MomentService _momentService = MomentService();
  final NotificationService _notificationService = NotificationService();
  final ProfileService _profileService = ProfileService();

  late final Stream<List<VoiceMoment>> _moments;
  late final Stream<List<FriendUser>> _friends;
  late final Stream<List<VoiceRoom>> _rooms;
  late final Stream<List<Club>> _clubs;
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
        const SnackBar(
          content: Text('Voice Moment posted to your feed.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _startChat(FriendUser friend) async {
    try {
      final conversationId = await _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: friend.email,
        otherPhotoUrl: friend.photoUrl ?? '',
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: friend.id,
            otherDisplayName: friend.displayName,
            otherEmail: friend.email,
            otherPhotoUrl: friend.photoUrl ?? '',
          ),
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
              intentionalOrFriendly(
                error,
                fallback: "Couldn't open this chat. Please try again.",
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openRoom(VoiceRoom room) async {
    try {
      final joinedRoom = await _roomService.joinRoom(room.id);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RoomEntryScreen(room: joinedRoom),
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
              intentionalOrFriendly(
                error,
                fallback: "Couldn't open this room. Please try again.",
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _deleteMoment(VoiceMoment moment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171020),
        title: const Text(
          'Delete Voice Moment?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This removes the recording, likes, and all comments permanently.',
          style: TextStyle(color: Color(0xFFB8AFC0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF416C),
            ),
            child: const Text('Delete'),
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
          const SnackBar(
            content: Text('Voice Moment deleted.'),
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
            content: Text('Could not delete Voice Moment: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fallbackFullName = user?.displayName?.trim();
    final fallbackName = fallbackFullName?.isNotEmpty == true
        ? fallbackFullName!.split(' ').first
        : user?.email?.split('@').first ?? 'there';

    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.9, -1),
            radius: 1.35,
            colors: [Color(0xFF291041), Color(0xFF100A18), _background],
            stops: [0, .35, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
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
                      premium: profile?.premiumIdentity ?? false,
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(child: _livePulse()),
              SliverToBoxAdapter(child: _liveRooms()),
              SliverToBoxAdapter(child: _voiceStories()),
              SliverToBoxAdapter(child: _activeFriends()),
              SliverToBoxAdapter(child: _sectionTitle('Your feed')),
              SliverToBoxAdapter(child: _feed()),
              SliverToBoxAdapter(child: _suggestedClubs()),
              SliverToBoxAdapter(child: _trending()),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String name, String? photoUrl, {bool premium = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $name! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'See what your people are saying right now.',
                  style: TextStyle(color: _muted, fontSize: 13),
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
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      side: const BorderSide(color: _border),
                    ),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.white,
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
                          color: const Color(0xFFFF426F),
                          shape: BoxShape.circle,
                          border: Border.all(color: _background, width: 2),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
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
          UserAvatar(
            radius: 24,
            photoUrl: photoUrl,
            fallbackIcon: Icons.person_rounded,
            premium: premium,
          ),
        ],
      ),
    );
  }

  Widget _livePulse() {
    return StreamBuilder<List<VoiceRoom>>(
      stream: _rooms,
      builder: (context, roomSnapshot) {
        final rooms = roomSnapshot.data ?? const <VoiceRoom>[];
        final people = rooms.fold<int>(
          0,
          (sum, room) => sum + room.participantCount,
        );
        return StreamBuilder<List<VoiceMoment>>(
          stream: _moments,
          builder: (context, momentSnapshot) {
            final moments = momentSnapshot.data ?? const <VoiceMoment>[];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: InkWell(
                onTap: widget.onOpenDiscover ?? HomeScreen.openDiscoverTab,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF54126F), Color(0xFF24112F)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF8B2CB5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF416C),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wifi_tethering_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LIVE PULSE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${rooms.length} live rooms  •  $people people talking  •  ${moments.length} fresh moments',
                              style: const TextStyle(
                                color: Color(0xFFDCCBE4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
                  const Text(
                    'Live right now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF416C),
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
                  label: 'Your Moment',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _feed() {
    return StreamBuilder<List<VoiceMoment>>(
      stream: _moments,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(34),
            child: Center(child: CircularProgressIndicator(color: _primary)),
          );
        }
        if (snapshot.hasError) return _empty('Could not load your feed.');
        final moments = snapshot.data ?? const <VoiceMoment>[];
        if (moments.isEmpty) {
          return _empty(
            'Follow people or add friends to build your voice feed.',
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
                    text:
                        'Listen to ${moment.authorName} on YO Voice: https://yovoice.app/?moment=${moment.id}',
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _activeFriends() {
    return StreamBuilder<List<FriendUser>>(
      stream: _friends,
      builder: (context, snapshot) {
        final active = (snapshot.data ?? const <FriendUser>[])
            .where((friend) => friend.isOnline)
            .take(8)
            .toList();
        if (active.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Friends active now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 11),
              Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: active
                      .map(
                        (friend) => ListTile(
                          onTap: () => _startChat(friend),
                          leading: CircleAvatar(
                            backgroundImage: friend.photoUrl?.isNotEmpty == true
                                ? NetworkImage(friend.photoUrl!)
                                : null,
                            child: friend.photoUrl?.isNotEmpty == true
                                ? null
                                : Text(friend.initial),
                          ),
                          title: Text(
                            friend.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Online now',
                            style: TextStyle(color: Color(0xFF43D980)),
                          ),
                          trailing: IconButton(
                            tooltip: 'Open chat',
                            onPressed: () => _startChat(friend),
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _primary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _suggestedClubs() {
    return StreamBuilder<List<Club>>(
      stream: _clubs,
      builder: (context, snapshot) {
        final clubs = snapshot.data ?? const <Club>[];
        if (clubs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 0, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Discover clubs',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 174,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 18),
                  itemCount: clubs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 11),
                  itemBuilder: (context, index) {
                    final club = clubs[index];
                    return _ClubCard(
                      club: club,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => ClubOverviewScreen(clubId: club.id),
                        ),
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

  Widget _trending() {
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
              const Text(
                'Trending Voice',
                style: TextStyle(
                  color: Colors.white,
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
                      tileColor: _surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                        side: const BorderSide(color: _border),
                      ),
                      leading: const Icon(
                        Icons.graphic_eq_rounded,
                        color: _primary,
                      ),
                      title: Text(
                        moment.authorName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        moment.caption.isEmpty
                            ? 'Voice Moment'
                            : moment.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted),
                      ),
                      trailing: Text(
                        '❤ ${moment.likeCount}',
                        style: const TextStyle(
                          color: Color(0xFFFF6D91),
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

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted),
      ),
    ),
  );

  Future<void> _showMomentPlayer(VoiceMoment moment) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
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
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF416C),
                        Color(0xFFB42DFF),
                        Color(0xFF5D00D7),
                      ],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF25152E),
                    backgroundImage: photoUrl?.isNotEmpty == true
                        ? NetworkImage(photoUrl!)
                        : null,
                    child: isAdd
                        ? const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 30,
                          )
                        : photoUrl?.isNotEmpty == true
                        ? null
                        : const Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.white,
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
                        color: const Color(0xFF9D20FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF080711),
                          width: 3,
                        ),
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
            style: const TextStyle(color: Colors.white70, fontSize: 11),
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

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
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
        const SnackBar(
          content: Text('This moment does not have uploaded audio yet.'),
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

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final time = _relative(moment.createdAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14101D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF352642)),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Color(0xFFA79DAF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Moment options',
                color: const Color(0xFF21172B),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Color(0xFFA79DAF),
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
                    const PopupMenuItem<String>(
                      value: 'comments',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                        ),
                        title: Text(
                          'View comments',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'share',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.share_outlined,
                          color: Colors.white,
                        ),
                        title: Text(
                          'Share',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    if (isOwner)
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFFF6688),
                          ),
                          title: Text(
                            'Delete Voice Moment',
                            style: TextStyle(color: Color(0xFFFF6688)),
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
              style: const TextStyle(
                color: Colors.white,
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF351447), Color(0xFF1D1228)],
                ),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFF643180)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFA51FFF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: _MiniWaveform()),
                  const SizedBox(width: 10),
                  Text(
                    moment.durationLabel,
                    style: const TextStyle(
                      color: Colors.white,
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
                child: StreamBuilder<bool>(
                  stream: widget.feedService.watchLiked(moment.id),
                  builder: (context, snapshot) {
                    final liked = snapshot.data ?? false;
                    return _Action(
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: '${moment.likeCount}',
                      active: liked,
                      onTap: () => widget.feedService.toggleLike(moment.id),
                    );
                  },
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
                  label: 'Share',
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
              label: const Text('Reply with voice'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC76DFF),
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime? date) {
    if (date == null) return 'now';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
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
              color: const Color(0xFFB94DFF),
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
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: active
            ? const Color(0xFFFF5F86)
            : const Color(0xFFA79DAF),
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.onTap});
  final Club club;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 155,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14101D),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF352642)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: club.avatarUrl?.isNotEmpty == true
                    ? NetworkImage(club.avatarUrl!)
                    : null,
                child: club.avatarUrl?.isNotEmpty == true
                    ? null
                    : Text(club.initial),
              ),
              const Spacer(),
              Text(
                club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${club.memberCount} members',
                style: const TextStyle(color: Color(0xFFA79DAF), fontSize: 11),
              ),
              const SizedBox(height: 10),
              const Text(
                'View club',
                style: TextStyle(
                  color: Color(0xFFC76DFF),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
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
    return SizedBox(
      width: 168,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF33144A), Color(0xFF14101D)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF432D5A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF64258E),
                    backgroundImage: room.imageUrl?.isNotEmpty == true
                        ? NetworkImage(room.imageUrl!)
                        : null,
                    child: room.imageUrl?.isNotEmpty == true
                        ? null
                        : Text(
                            room.name.isEmpty
                                ? '?'
                                : room.name[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF416C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Hosted by ${room.hostName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFA79DAF), fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.headset_rounded,
                    color: Color(0xFFC76DFF),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${room.participantCount} listening',
                    style: const TextStyle(
                      color: Color(0xFFC76DFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 34),
      decoration: const BoxDecoration(
        color: Color(0xFF151020),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF5A5063),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 42,
            backgroundImage: widget.moment.authorPhotoUrl?.isNotEmpty == true
                ? NetworkImage(widget.moment.authorPhotoUrl!)
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            widget.moment.authorName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.moment.caption,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB8ADBF)),
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: _toggle,
            customBorder: const CircleBorder(),
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Color(0xFFA51FFF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

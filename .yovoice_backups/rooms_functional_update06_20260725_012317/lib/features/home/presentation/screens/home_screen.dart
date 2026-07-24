import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

class HomeScreen extends StatelessWidget {
  static VoidCallback? openDiscoverTab;

  const HomeScreen({super.key});

  static const Color background = Color(0xFF080711);
  static const Color surface = Color(0xFF12101D);
  static const Color surface2 = Color(0xFF1B1627);
  static const Color border = Color(0xFF30263F);
  static const Color muted = Color(0xFF9D95AD);
  static const Color primary = Color(0xFF9D20FF);
  static const Color pink = Color(0xFFFF416C);

  static Future<void> openCreateRoom(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CreateRoomScreen()),
    );
  }

  static Future<void> openVoiceMoment(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const RecordVoiceMomentScreen()),
    );
  }

  static Future<void> openNotifications(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  static Future<void> openAddFriend(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AddFriendScreen()),
    );
  }

  static Future<void> openFriendProfile(
    BuildContext context,
    FriendUser friend,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(friend: friend),
      ),
    );
  }

  static Future<void> openRoom(BuildContext context, VoiceRoom room) async {
    final service = RoomService();

    try {
      final joined = await service.joinRoom(room.id);

      if (!context.mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: joined)),
      );
    } catch (error) {
      if (!context.mounted) return;
      showError(context, error.toString());
    }
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Invalid argument(s): ', ''),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF481C30),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final rawName = user?.displayName?.trim();
    final displayName = rawName != null && rawName.isNotEmpty
        ? rawName.split(' ').first
        : user?.email?.split('@').first ?? 'YoVoice user';

    return Scaffold(
      backgroundColor: background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.88, -.96),
            radius: 1.3,
            colors: [Color(0xFF25103C), Color(0xFF100B1B), background],
            stops: [0, .38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: _FriendRequestNotifier(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 1120) {
                  return _DesktopHome(displayName: displayName);
                }

                return _CompactHome(displayName: displayName);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopHome extends StatelessWidget {
  const _DesktopHome({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 116),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeHeader(displayName: displayName),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 3, child: _MainHomeContent()),
                  const SizedBox(width: 22),
                  SizedBox(
                    width: 340,
                    child: _DesktopSidePanel(displayName: displayName),
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

class _CompactHome extends StatelessWidget {
  const _CompactHome({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeHeader(displayName: displayName, compact: true),
          const SizedBox(height: 20),
          const _MainHomeContent(compact: true),
        ],
      ),
    );
  }
}

class _MainHomeContent extends StatelessWidget {
  const _MainHomeContent({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CreateActions(compact: compact),
        const SizedBox(height: 24),
        const _SectionHeader(
          title: 'Voice Moments for you',
          actionLabel: 'See all',
        ),
        const SizedBox(height: 12),
        const _VoiceMomentsSection(),
        const SizedBox(height: 25),
        const _SectionHeader(
          title: 'Friends speaking now',
          actionLabel: 'Find friends',
        ),
        const SizedBox(height: 12),
        const _FriendsSpeakingSection(),
        const SizedBox(height: 25),
        const _SectionHeader(
          title: 'Live rooms for you',
          actionLabel: 'See all',
        ),
        const SizedBox(height: 12),
        const _LiveRoomsSection(),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.displayName, this.compact = false});

  final String displayName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $displayName! 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 26 : 31,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'What do you want to share today?',
                style: TextStyle(
                  color: HomeScreen.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const _NotificationButton(),
        const SizedBox(width: 10),
        InkWell(
          onTap: () => HomeScreen.showInfo(
            context,
            'Open the Profile tab to manage your account.',
          ),
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: compact ? 23 : 25,
            backgroundColor: const Color(0xFF6B2398),
            backgroundImage: user?.photoURL?.trim().isNotEmpty == true
                ? NetworkImage(user!.photoURL!)
                : null,
            child: user?.photoURL?.trim().isNotEmpty == true
                ? null
                : Text(
                    displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton();

  @override
  Widget build(BuildContext context) {
    final friendService = FriendService();

    return StreamBuilder<int>(
      stream: friendService.watchPendingFriendRequestCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return InkWell(
          onTap: () => HomeScreen.openNotifications(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: HomeScreen.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HomeScreen.border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                if (count > 0)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        color: HomeScreen.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
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
        );
      },
    );
  }
}

class _CreateActions extends StatelessWidget {
  const _CreateActions({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _CreateActionCard(
        icon: Icons.graphic_eq_rounded,
        eyebrow: 'Record a',
        title: 'Voice Moment',
        subtitle: 'Share your voice\nwith the world',
        colors: const [Color(0xFF7417B6), Color(0xFF3B0C63)],
        borderColor: const Color(0xFFA82DFF),
        onTap: () => HomeScreen.openVoiceMoment(context),
      ),
      _CreateActionCard(
        icon: Icons.podcasts_rounded,
        eyebrow: 'Start a',
        title: 'Live Room',
        subtitle: 'Talk with others\nin real time',
        colors: const [Color(0xFF29113E), Color(0xFF171021)],
        borderColor: const Color(0xFF4C315E),
        onTap: () => HomeScreen.openCreateRoom(context),
      ),
    ];

    if (compact) {
      return Column(children: [cards[0], const SizedBox(height: 12), cards[1]]);
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 14),
        Expanded(child: cards[1]),
      ],
    );
  }
}

class _CreateActionCard extends StatelessWidget {
  const _CreateActionCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 140,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22100020),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFC33BFF), Color(0xFF7200EC)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Color(0xFFD8CFE1),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: HomeScreen.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: HomeScreen.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            if (actionLabel == 'Find friends') {
              HomeScreen.openAddFriend(context);
              return;
            }

            if (title == 'Live rooms for you') {
              HomeScreen.openDiscoverTab?.call();
              return;
            }

            HomeScreen.showInfo(
              context,
              'The full feed will be added in the next Voice Moments stage.',
            );
          },
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC64BFF)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right_rounded, size: 19),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceMomentsSection extends StatelessWidget {
  const _VoiceMomentsSection();

  @override
  Widget build(BuildContext context) {
    final service = MomentService();

    return StreamBuilder<List<VoiceMoment>>(
      stream: service.watchPublishedMoments(limit: 10),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MomentEmptyCard(
            onPressed: () => HomeScreen.openVoiceMoment(context),
          );
        }

        final moments = snapshot.data ?? const <VoiceMoment>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            moments.isEmpty) {
          return const SizedBox(
            height: 190,
            child: Center(
              child: CircularProgressIndicator(
                color: HomeScreen.primary,
                strokeWidth: 2.4,
              ),
            ),
          );
        }

        if (moments.isEmpty) {
          return _MomentEmptyCard(
            onPressed: () => HomeScreen.openVoiceMoment(context),
          );
        }

        return SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: moments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 300,
                child: _VoiceMomentCard(moment: moments[index]),
              );
            },
          ),
        );
      },
    );
  }
}

class _MomentEmptyCard extends StatelessWidget {
  const _MomentEmptyCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: HomeScreen.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomeScreen.border),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: HomeScreen.primary.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Color(0xFFC55AFF),
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your feed starts with a voice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Be the first person in your community to publish a Voice Moment.',
                  style: TextStyle(
                    color: HomeScreen.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: onPressed,
            style: IconButton.styleFrom(backgroundColor: HomeScreen.primary),
            icon: const Icon(Icons.mic_rounded),
          ),
        ],
      ),
    );
  }
}

class _VoiceMomentCard extends StatelessWidget {
  const _VoiceMomentCard({required this.moment});

  final VoiceMoment moment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: HomeScreen.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: HomeScreen.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF662092),
                backgroundImage:
                    moment.authorPhotoUrl?.trim().isNotEmpty == true
                    ? NetworkImage(moment.authorPhotoUrl!)
                    : null,
                child: moment.authorPhotoUrl?.trim().isNotEmpty == true
                    ? null
                    : Text(
                        moment.authorName.isEmpty
                            ? '?'
                            : moment.authorName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _relativeTime(moment.createdAt),
                      style: const TextStyle(
                        color: HomeScreen.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded, color: HomeScreen.muted),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              InkWell(
                onTap: () => HomeScreen.showInfo(
                  context,
                  moment.audioUrl == null
                      ? 'This Voice Moment has no uploaded audio yet.'
                      : 'Audio playback integration is the next stage.',
                ),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFB83BFF),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _Waveform(seed: moment.id.hashCode, height: 46)),
              const SizedBox(width: 8),
              Text(
                moment.durationLabel,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            moment.caption.isEmpty ? 'Voice Moment' : moment.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: HomeScreen.pink,
                size: 18,
              ),
              const SizedBox(width: 5),
              Text(
                '${moment.likeCount}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                color: HomeScreen.muted,
                size: 18,
              ),
              const SizedBox(width: 5),
              Text(
                '${moment.commentCount}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const Spacer(),
              const Icon(
                Icons.bookmark_border_rounded,
                color: HomeScreen.muted,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime? date) {
    if (date == null) return 'now';

    final difference = DateTime.now().difference(date);

    if (difference.inMinutes < 1) return 'now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.seed, required this.height});

  final int seed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(28, (index) {
          final raw = ((seed.abs() + index * 19) % 31) + 9;

          return Expanded(
            child: Container(
              height: raw.toDouble(),
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF6A00FF), Color(0xFFBF3BFF)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _FriendsSpeakingSection extends StatelessWidget {
  const _FriendsSpeakingSection();

  @override
  Widget build(BuildContext context) {
    final service = FriendService();

    return StreamBuilder<List<FriendUser>>(
      stream: service.watchFriends(),
      builder: (context, snapshot) {
        final friends = (snapshot.data ?? const <FriendUser>[])
            .where((friend) => friend.isOnline)
            .toList(growable: false);

        if (snapshot.connectionState == ConnectionState.waiting &&
            friends.isEmpty) {
          return const SizedBox(
            height: 92,
            child: Center(
              child: CircularProgressIndicator(
                color: HomeScreen.primary,
                strokeWidth: 2.4,
              ),
            ),
          );
        }

        if (friends.isEmpty) {
          return _InlineEmptyCard(
            icon: Icons.people_outline_rounded,
            title: 'Nobody is online right now',
            subtitle: 'Add friends and their live status will appear here.',
            actionLabel: 'Add friend',
            onPressed: () => HomeScreen.openAddFriend(context),
          );
        }

        return SizedBox(
          height: 102,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: friends.length,
            separatorBuilder: (_, __) => const SizedBox(width: 15),
            itemBuilder: (context, index) {
              final friend = friends[index];

              return _SpeakingFriend(
                friend: friend,
                onTap: () => HomeScreen.openFriendProfile(context, friend),
              );
            },
          ),
        );
      },
    );
  }
}

class _SpeakingFriend extends StatelessWidget {
  const _SpeakingFriend({required this.friend, required this.onTap});

  final FriendUser friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFC43BFF), Color(0xFF5D00D7)],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 29,
                    backgroundColor: const Color(0xFF25152F),
                    backgroundImage: friend.photoUrl?.trim().isNotEmpty == true
                        ? NetworkImage(friend.photoUrl!)
                        : null,
                    child: friend.photoUrl?.trim().isNotEmpty == true
                        ? null
                        : Text(
                            friend.initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  right: 1,
                  bottom: 3,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: const Color(0xFF20D66B),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: HomeScreen.background,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              friend.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveRoomsSection extends StatelessWidget {
  const _LiveRoomsSection();

  @override
  Widget build(BuildContext context) {
    final service = RoomService();

    return StreamBuilder<List<VoiceRoom>>(
      stream: service.watchLivePublicRooms(),
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const <VoiceRoom>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            rooms.isEmpty) {
          return const SizedBox(
            height: 160,
            child: Center(
              child: CircularProgressIndicator(
                color: HomeScreen.primary,
                strokeWidth: 2.4,
              ),
            ),
          );
        }

        if (snapshot.hasError || rooms.isEmpty) {
          return _InlineEmptyCard(
            icon: Icons.podcasts_rounded,
            title: 'No public rooms are live',
            subtitle: 'Start one and invite your community to join.',
            actionLabel: 'Start room',
            onPressed: () => HomeScreen.openCreateRoom(context),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;

            if (!desktop) {
              return SizedBox(
                height: 166,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    return SizedBox(
                      width: 300,
                      child: _LiveRoomCard(room: rooms[index]),
                    );
                  },
                ),
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: rooms
                  .take(6)
                  .map((room) {
                    return SizedBox(
                      width: (constraints.maxWidth - 24) / 3,
                      child: _LiveRoomCard(room: room),
                    );
                  })
                  .toList(growable: false),
            );
          },
        );
      },
    );
  }
}

class _LiveRoomCard extends StatelessWidget {
  const _LiveRoomCard({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => HomeScreen.openRoom(context, room),
        borderRadius: BorderRadius.circular(19),
        child: Container(
          height: 166,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF29123D), Color(0xFF12101D)],
            ),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: HomeScreen.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB71E4D),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    room.language,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                room.description.isEmpty
                    ? 'Hosted by ${room.hostName}'
                    : room.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomeScreen.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(
                    Icons.people_alt_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${room.participantCount}/${room.maxParticipants ?? '∞'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: HomeScreen.surface2,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      room.category,
                      style: const TextStyle(
                        color: Color(0xFFD5A1FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
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

class _InlineEmptyCard extends StatelessWidget {
  const _InlineEmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HomeScreen.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: HomeScreen.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: HomeScreen.surface2,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: const Color(0xFFC25AFF)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: HomeScreen.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _DesktopSidePanel extends StatelessWidget {
  const _DesktopSidePanel({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: HomeScreen.surface.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: HomeScreen.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SideTitle(
            icon: Icons.auto_awesome_rounded,
            title: 'Quick tips',
          ),
          const SizedBox(height: 18),
          const _SideRow(
            icon: Icons.graphic_eq_rounded,
            color: Color(0xFFB23AFF),
            title: 'Voice Moments',
            subtitle: 'Share short audio clips',
          ),
          const SizedBox(height: 14),
          const _SideRow(
            icon: Icons.podcasts_rounded,
            color: Color(0xFFFF416C),
            title: 'Live Rooms',
            subtitle: 'Talk in real time',
          ),
          const SizedBox(height: 14),
          const _SideRow(
            icon: Icons.people_alt_rounded,
            color: Color(0xFFFFB020),
            title: 'Connect',
            subtitle: 'Find and meet new people',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Divider(color: HomeScreen.border),
          ),
          const _SideTitle(
            icon: Icons.insights_rounded,
            title: 'Your activity',
          ),
          const SizedBox(height: 18),
          const _SideRow(
            icon: Icons.graphic_eq_rounded,
            color: Color(0xFFB23AFF),
            title: 'Voice Moments',
            subtitle: 'Ready for your first post',
          ),
          const SizedBox(height: 14),
          const _SideRow(
            icon: Icons.chat_bubble_outline_rounded,
            color: Color(0xFF667BFF),
            title: 'Messages',
            subtitle: 'Your chats are waiting',
          ),
          const SizedBox(height: 14),
          const _SideRow(
            icon: Icons.groups_2_rounded,
            color: Color(0xFFFF4D8C),
            title: 'Rooms joined',
            subtitle: 'Discover live conversations',
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF35134F), Color(0xFF20142D)],
              ),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFF4C2A63)),
            ),
            child: Text(
              'Welcome, $displayName. Your YoVoice journey starts with one authentic voice.',
              style: const TextStyle(
                color: Color(0xFFD9D1E3),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideTitle extends StatelessWidget {
  const _SideTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 23),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: HomeScreen.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FriendRequestNotifier extends StatefulWidget {
  const _FriendRequestNotifier({required this.child});

  final Widget child;

  @override
  State<_FriendRequestNotifier> createState() => _FriendRequestNotifierState();
}

class _FriendRequestNotifierState extends State<_FriendRequestNotifier> {
  final FriendService _friendService = FriendService();

  StreamSubscription<List<FriendRequest>>? _subscription;
  Set<String>? _previousRequestIds;

  @override
  void initState() {
    super.initState();

    _subscription = _friendService.watchFriendRequests().listen(
      _handleRequests,
    );
  }

  void _handleRequests(List<FriendRequest> requests) {
    final currentIds = requests.map((request) => request.senderId).toSet();
    final previousIds = _previousRequestIds;

    _previousRequestIds = currentIds;

    if (!mounted || previousIds == null) {
      return;
    }

    final newRequests = requests
        .where((request) => !previousIds.contains(request.senderId))
        .toList(growable: false);

    if (newRequests.isEmpty) {
      return;
    }

    final FriendRequest newestRequest = newRequests.first;
    final senderName = newestRequest.senderName.trim().isNotEmpty
        ? newestRequest.senderName.trim()
        : newestRequest.senderEmail.split('@').first;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final message = newRequests.length == 1
          ? '$senderName sent you a friend request.'
          : 'You have ${newRequests.length} new friend requests.';

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Open',
              textColor: const Color(0xFFD7A1FF),
              onPressed: () => HomeScreen.openNotifications(context),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2A1939),
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF2C253B);
  static const Color _secondaryText = Color(0xFF9D95AD);

  static void showComingSoon(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A1939),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static void showError(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF481C30),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static Future<void> openCreateRoom(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const CreateRoomScreen();
        },
      ),
    );
  }


  static Future<void> openAddFriend(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AddFriendScreen(),
      ),
    );
  }

  static Future<void> openFriendRequests(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _FriendRequestsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final rawDisplayName = user?.displayName?.trim();

    final displayName = rawDisplayName != null && rawDisplayName.isNotEmpty
        ? rawDisplayName.split(' ').first
        : user?.email?.split('@').first ?? 'YoVoice user';

    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
            radius: 1.25,
            colors: [Color(0xFF24103B), Color(0xFF100B1B), _background],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: _FriendRequestNotifier(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                if (isWide) {
                  return _DesktopHome(displayName: displayName);
                }

                return _MobileHome(displayName: displayName);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileHome extends StatelessWidget {
  const _MobileHome({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeHeader(displayName: displayName, compact: true),
          const SizedBox(height: 22),
          const _CreateRoomCard(),
          const SizedBox(height: 26),
          _FriendsHeader(
            onAddFriend: () => HomeScreen.openAddFriend(context),
            onRequests: () => HomeScreen.openFriendRequests(context),
          ),
          const SizedBox(height: 14),
          const _FriendsRow(),
          const SizedBox(height: 26),
          const _SectionTitle(
            title: 'Active rooms',
            actionLabel: 'Refresh',
            actionMessage: 'Rooms update automatically in real time.',
          ),
          const SizedBox(height: 14),
          const _LiveRoomsSection(desktop: false),
        ],
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
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeHeader(displayName: displayName, compact: false),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        const _CreateRoomCard(),
                        const SizedBox(height: 26),
                        _FriendsHeader(
                          onAddFriend: () => HomeScreen.openAddFriend(context),
                          onRequests: () => HomeScreen.openFriendRequests(context),
                        ),
                        const SizedBox(height: 14),
                        const _FriendsRow(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    flex: 4,
                    child: _QuickActivityCard(displayName: displayName),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const _SectionTitle(
                title: 'Active rooms',
                actionLabel: 'Refresh',
                actionMessage: 'Rooms update automatically in real time.',
              ),
              const SizedBox(height: 14),
              const _LiveRoomsSection(desktop: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.displayName, required this.compact});

  final String displayName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $displayName 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 24 : 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Ready to connect?',
                style: TextStyle(
                  color: HomeScreen._secondaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const _FriendRequestsHeaderButton(),
        const SizedBox(width: 10),
        if (!compact)
          _HeaderIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: () {
              HomeScreen.showComingSoon(context, 'Settings are coming soon.');
            },
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
  StreamSubscription<int>? _subscription;
  int? _previousCount;

  @override
  void initState() {
    super.initState();
    _subscription = _friendService.watchPendingFriendRequestCount().listen(
      _handleCount,
    );
  }

  void _handleCount(int count) {
    final previousCount = _previousCount;
    _previousCount = count;

    if (!mounted || previousCount == null || count <= previousCount) {
      return;
    }

    final added = count - previousCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final label = added == 1
          ? 'You have a new friend request.'
          : 'You have $added new friend requests.';
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(label),
          action: SnackBarAction(
            label: 'Open',
            textColor: const Color(0xFFD7A1FF),
            onPressed: () => HomeScreen.openFriendRequests(context),
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

class _FriendRequestsHeaderButton extends StatefulWidget {
  const _FriendRequestsHeaderButton();

  @override
  State<_FriendRequestsHeaderButton> createState() =>
      _FriendRequestsHeaderButtonState();
}

class _FriendRequestsHeaderButtonState
    extends State<_FriendRequestsHeaderButton> {
  final FriendService _friendService = FriendService();
  late final Stream<int> _countStream;

  @override
  void initState() {
    super.initState();
    _countStream = _friendService.watchPendingFriendRequestCount();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return _HeaderIconButton(
          icon: count > 0
              ? Icons.notifications_active_outlined
              : Icons.notifications_none_rounded,
          showBadge: count > 0,
          badgeCount: count,
          tooltip: count > 0 ? '$count friend requests' : 'Notifications',
          onPressed: () => HomeScreen.openFriendRequests(context),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showBadge = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool showBadge;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: HomeScreen._surface,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: HomeScreen._border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                if (showBadge)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _RequestBadge(count: badgeCount),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateRoomCard extends StatelessWidget {
  const _CreateRoomCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF52117D), Color(0xFF39105E), Color(0xFF20122E)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF762AB0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332A0050),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HomeScreen.openCreateRoom(context);
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start a voice room',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Talk about anything',
                        style: TextStyle(
                          color: Color(0xFFD5C8DE),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 18),
                      _CreateRoomLabel(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFC13BFF), Color(0xFF7B18F7)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x668D20FF),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateRoomLabel extends StatelessWidget {
  const _CreateRoomLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none_rounded, color: Colors.white, size: 18),
          SizedBox(width: 7),
          Text(
            'Create room',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActivityCard extends StatelessWidget {
  const _QuickActivityCard({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: HomeScreen._surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: HomeScreen._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          const _ActivityRow(
            icon: Icons.graphic_eq_rounded,
            iconColor: Color(0xFFB134FF),
            title: 'Voice Moments',
            subtitle: 'No new moments yet',
          ),
          const SizedBox(height: 16),
          const _ActivityRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: Color(0xFF6175FF),
            title: 'Messages',
            subtitle: 'Your chats are up to date',
          ),
          const SizedBox(height: 16),
          const _ActivityRow(
            icon: Icons.groups_2_outlined,
            iconColor: Color(0xFFFF4D8C),
            title: 'Rooms joined',
            subtitle: 'Discover your first room',
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
              'Welcome, $displayName. Your YoVoice journey starts here.',
              style: const TextStyle(
                color: Color(0xFFD9D1E3),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: iconColor, size: 22),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: HomeScreen._secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.actionLabel,
    required this.actionMessage,
  });

  final String title;
  final String actionLabel;
  final String actionMessage;

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
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            HomeScreen.showComingSoon(context, actionMessage);
          },
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFBE4BFF),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          child: Text(
            actionLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _FriendsHeader extends StatelessWidget {
  const _FriendsHeader({this.onAddFriend, this.onRequests});

  final VoidCallback? onAddFriend;
  final VoidCallback? onRequests;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Friends online',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _FriendsActionButton(
          icon: Icons.person_add_alt_1_rounded,
          tooltip: 'Add friend',
          onPressed: onAddFriend ?? () => HomeScreen.openAddFriend(context),
        ),
        const SizedBox(width: 8),
        _FriendRequestsActionButton(
          onPressed: onRequests ?? () => HomeScreen.openFriendRequests(context),
        ),
      ],
    );
  }
}


class _FriendRequestsActionButton extends StatefulWidget {
  const _FriendRequestsActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_FriendRequestsActionButton> createState() =>
      _FriendRequestsActionButtonState();
}

class _FriendRequestsActionButtonState
    extends State<_FriendRequestsActionButton> {
  final FriendService _friendService = FriendService();
  late final Stream<int> _countStream;

  @override
  void initState() {
    super.initState();
    _countStream = _friendService.watchPendingFriendRequestCount();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Tooltip(
          message: count > 0 ? '$count pending friend requests' : 'Friend requests',
          child: Material(
            color: HomeScreen._surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HomeScreen._border),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      count > 0
                          ? Icons.mark_email_unread_rounded
                          : Icons.mail_outline_rounded,
                      color: const Color(0xFFC05AFF),
                      size: 20,
                    ),
                    if (count > 0)
                      Positioned(
                        top: -5,
                        right: -5,
                        child: _RequestBadge(count: count),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequestBadge extends StatelessWidget {
  const _RequestBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF426F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HomeScreen._surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _FriendsActionButton extends StatelessWidget {
  const _FriendsActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: HomeScreen._surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomeScreen._border),
            ),
            child: Icon(icon, color: const Color(0xFFC05AFF), size: 20),
          ),
        ),
      ),
    );
  }
}

class _FriendsRow extends StatefulWidget {
  const _FriendsRow();

  @override
  State<_FriendsRow> createState() => _FriendsRowState();
}

class _FriendsRowState extends State<_FriendsRow> {
  final FriendService _friendService = FriendService();
  late final Stream<List<FriendUser>> _friendsStream;

  @override
  void initState() {
    super.initState();
    _friendsStream = _friendService.watchFriends();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendUser>>(
      stream: _friendsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox(
            height: 92,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFFB348FF),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return _FriendsMessage(
            icon: Icons.error_outline_rounded,
            message: _friendError(snapshot.error),
          );
        }

        final friends = snapshot.data ?? const <FriendUser>[];
        final onlineFriends = friends.where((friend) => friend.isOnline).toList();

        if (onlineFriends.isEmpty) {
          return _FriendsMessage(
            icon: Icons.people_outline_rounded,
            message: friends.isEmpty
                ? 'Add friends to see them here.'
                : 'None of your friends are online right now.',
            actionLabel: friends.isEmpty ? 'Add friend' : null,
            onAction: friends.isEmpty
                ? () => HomeScreen.openAddFriend(context)
                : null,
          );
        }

        return SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: onlineFriends.length,
            separatorBuilder: (_, __) => const SizedBox(width: 17),
            itemBuilder: (context, index) {
              final friend = onlineFriends[index];
              return _FriendAvatar(friend: friend);
            },
          ),
        );
      },
    );
  }

  String _friendError(Object? error) {
    final message = error.toString();
    if (message.contains('permission-denied')) {
      return 'Firestore permission denied for friends.';
    }
    if (message.contains('unavailable')) {
      return 'Friends are temporarily unavailable.';
    }
    return 'Could not load friends.';
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.friend});

  final FriendUser friend;

  @override
  Widget build(BuildContext context) {
    final name = friend.displayName.trim().isNotEmpty
        ? friend.displayName.trim()
        : friend.email.split('@').first;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoUrl = friend.photoUrl?.trim();

    return SizedBox(
      width: 58,
      child: InkWell(
        onTap: () => HomeScreen.showComingSoon(
          context,
          '$name profile is coming soon.',
        ),
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
                    ),
                  ),
                  child: ClipOval(
                    child: Container(
                      color: const Color(0xFF30203F),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _InitialAvatar(
                                initial: initial,
                              ),
                            )
                          : _InitialAvatar(initial: initial),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFF42D47D),
                      shape: BoxShape.circle,
                      border: Border.all(color: HomeScreen._background, width: 3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD9D2E1),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9F75D9), Color(0xFF3C2868)],
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FriendsMessage extends StatelessWidget {
  const _FriendsMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: HomeScreen._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HomeScreen._border),
      ),
      child: Row(
        children: [
          Icon(icon, color: HomeScreen._secondaryText, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: HomeScreen._secondaryText,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _FriendRequestsSheet extends StatefulWidget {
  const _FriendRequestsSheet();

  @override
  State<_FriendRequestsSheet> createState() => _FriendRequestsSheetState();
}

class _FriendRequestsSheetState extends State<_FriendRequestsSheet> {
  final FriendService _friendService = FriendService();
  late final Stream<List<FriendRequest>> _requestsStream;
  final Set<String> _processingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _requestsStream = _friendService.watchFriendRequests();
  }

  Future<void> _accept(FriendRequest request) async {
    await _process(
      request.senderId,
      () => _friendService.acceptFriendRequest(request),
      'Friend request accepted.',
    );
  }

  Future<void> _decline(FriendRequest request) async {
    await _process(
      request.senderId,
      () => _friendService.declineFriendRequest(request.senderId),
      'Friend request declined.',
    );
  }

  Future<void> _process(
    String senderId,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_processingIds.contains(senderId)) return;
    setState(() => _processingIds.add(senderId));

    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      HomeScreen.showError(context, _requestError(error));
    } finally {
      if (mounted) setState(() => _processingIds.remove(senderId));
    }
  }

  String _requestError(Object error) {
    final message = error.toString();
    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }
    if (message.contains('not-found')) {
      return 'This friend request no longer exists.';
    }
    return 'Could not update the friend request.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF12101D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xFF3A284A))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF51475E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Friend requests',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Flexible(
            child: StreamBuilder<List<FriendRequest>>(
              stream: _requestsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(36),
                    child: CircularProgressIndicator(
                      color: Color(0xFFB348FF),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Could not load friend requests.',
                      style: TextStyle(color: Color(0xFFFF8AA2)),
                    ),
                  );
                }

                final requests = snapshot.data ?? const <FriendRequest>[];
                if (requests.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(24, 18, 24, 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          color: Color(0xFF8F849D),
                          size: 46,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'No pending friend requests',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'New requests will appear here.',
                          style: TextStyle(color: Color(0xFF9D95AD)),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final processing = _processingIds.contains(request.senderId);
                    return _FriendRequestTile(
                      request: request,
                      processing: processing,
                      onAccept: () => _accept(request),
                      onDecline: () => _decline(request),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.request,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
  });

  final FriendRequest request;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final name = request.senderName.trim().isNotEmpty
        ? request.senderName.trim()
        : request.senderEmail.split('@').first;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoUrl = request.senderPhotoUrl?.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191624),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HomeScreen._border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _InitialAvatar(initial: initial),
                    )
                  : _InitialAvatar(initial: initial),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  request.senderEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomeScreen._secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (processing)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFFB348FF),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Decline',
              onPressed: onDecline,
              icon: const Icon(Icons.close_rounded, color: Color(0xFFFF6F8E)),
            ),
            IconButton(
              tooltip: 'Accept',
              onPressed: onAccept,
              icon: const Icon(Icons.check_rounded, color: Color(0xFF54DB8C)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveRoomsSection extends StatefulWidget {
  const _LiveRoomsSection({required this.desktop});

  final bool desktop;

  @override
  State<_LiveRoomsSection> createState() => _LiveRoomsSectionState();
}

class _LiveRoomsSectionState extends State<_LiveRoomsSection> {
  final RoomService _roomService = RoomService();

  late final Stream<List<VoiceRoom>> _roomsStream;

  @override
  void initState() {
    super.initState();
    _roomsStream = _roomService.watchLivePublicRooms();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VoiceRoom>>(
      stream: _roomsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _RoomsLoadingState();
        }

        if (snapshot.hasError) {
          return _RoomsErrorState(
            message: _getReadableStreamError(snapshot.error),
          );
        }

        final rooms = snapshot.data ?? const <VoiceRoom>[];

        if (rooms.isEmpty) {
          return const _EmptyRoomsState();
        }

        if (!widget.desktop) {
          return Column(
            children: [
              for (var index = 0; index < rooms.length; index++) ...[
                _LiveRoomCard(room: rooms[index]),
                if (index != rooms.length - 1) const SizedBox(height: 13),
              ],
            ],
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 15.0;
            const columns = 3;

            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: rooms.map((room) {
                return SizedBox(
                  width: cardWidth,
                  child: _LiveRoomCard(room: room),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  String _getReadableStreamError(Object? error) {
    final message = error.toString();

    if (message.contains('failed-precondition') || message.contains('index')) {
      return 'Firestore needs an index for active rooms. Open the Firebase link shown in the debug console and create the index.';
    }

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }

    if (message.contains('unavailable')) {
      return 'Rooms are temporarily unavailable. Check your internet connection.';
    }

    return 'Could not load active rooms.';
  }
}

class _LiveRoomCard extends StatefulWidget {
  const _LiveRoomCard({required this.room});

  final VoiceRoom room;

  @override
  State<_LiveRoomCard> createState() => _LiveRoomCardState();
}

class _LiveRoomCardState extends State<_LiveRoomCard> {
  final RoomService _roomService = RoomService();

  bool _isJoining = false;

  Future<void> _joinRoom() async {
    if (_isJoining) {
      return;
    }

    setState(() {
      _isJoining = true;
    });

    try {
      final joinedRoom = await _roomService.joinRoom(widget.room.id);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) {
            return RoomScreen(room: joinedRoom);
          },
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      HomeScreen.showError(context, _getReadableJoinError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  String _getReadableJoinError(Object error) {
    final message = error.toString();

    if (message.contains('no longer live')) {
      return 'This room is no longer live.';
    }

    if (message.contains('room is full')) {
      return 'This room is full.';
    }

    if (message.contains('private')) {
      return 'This room is private.';
    }

    if (message.contains('does not exist')) {
      return 'This room no longer exists.';
    }

    if (message.contains('signed in')) {
      return 'You must be signed in before joining a room.';
    }

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your Firebase security rules.';
    }

    return 'Could not join the room. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final accent = _categoryColor(room.category);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isHost = currentUserId == room.hostId;

    return Material(
      color: HomeScreen._surface,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: _isJoining ? null : _joinRoom,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: HomeScreen._border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.15),
                HomeScreen._surface,
                HomeScreen._surface,
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 53,
                height: 53,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.32)),
                ),
                child: Icon(
                  _categoryIcon(room.category),
                  color: accent,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF315D),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          _categoryIcon(room.category),
                          color: HomeScreen._secondaryText,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _categoryLabel(room.category),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HomeScreen._secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          '•',
                          style: TextStyle(
                            color: Color(0xFF625A6F),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            room.language,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HomeScreen._secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.people_alt_outlined,
                          color: Color(0xFFB8B0C4),
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _participantText(room),
                          style: const TextStyle(
                            color: Color(0xFFB8B0C4),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          '•',
                          style: TextStyle(
                            color: Color(0xFF625A6F),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            isHost ? 'Your room' : 'Hosted by ${room.hostName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isHost
                                  ? const Color(0xFFC05AFF)
                                  : const Color(0xFFB8B0C4),
                              fontSize: 11,
                              fontWeight: isHost
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isJoining)
                const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFFB348FF),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF766D82),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _participantText(VoiceRoom room) {
    final maximum = room.maxParticipants;

    if (maximum == null) {
      return '${room.participantCount} joined';
    }

    return '${room.participantCount}/$maximum joined';
  }

  static String _categoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return 'Music';
      case 'gaming':
        return 'Gaming';
      case 'chill':
        return 'Chill';
      case 'study':
        return 'Study';
      case 'business':
        return 'Business';
      case 'talk':
      default:
        return 'Talk';
    }
  }

  static IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return Icons.music_note_rounded;
      case 'gaming':
        return Icons.sports_esports_rounded;
      case 'chill':
        return Icons.nightlife_rounded;
      case 'study':
        return Icons.school_outlined;
      case 'business':
        return Icons.work_outline_rounded;
      case 'talk':
      default:
        return Icons.record_voice_over_rounded;
    }
  }

  static Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return const Color(0xFFFF4C68);
      case 'gaming':
        return const Color(0xFF5977FF);
      case 'chill':
        return const Color(0xFF3EC7A5);
      case 'study':
        return const Color(0xFFFFA63D);
      case 'business':
        return const Color(0xFF4BA9FF);
      case 'talk':
      default:
        return const Color(0xFF9C42FF);
    }
  }
}

class _RoomsLoadingState extends StatelessWidget {
  const _RoomsLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: HomeScreen._surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: HomeScreen._border),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFFB348FF),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading active rooms...',
            style: TextStyle(
              color: HomeScreen._secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoomsState extends StatelessWidget {
  const _EmptyRoomsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      decoration: BoxDecoration(
        color: HomeScreen._surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: HomeScreen._border),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF9C42FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Color(0xFFB348FF),
              size: 29,
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'No active rooms yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Be the first person to start a conversation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HomeScreen._secondaryText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 17),
          TextButton.icon(
            onPressed: () {
              HomeScreen.openCreateRoom(context);
            },
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text(
              'Create room',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC05AFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsErrorState extends StatelessWidget {
  const _RoomsErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF21121B),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: const Color(0xFF5B293C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF6785),
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Could not load rooms',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFCDB3BD),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

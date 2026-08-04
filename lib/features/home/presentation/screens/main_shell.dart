import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/features/home/presentation/screens/home_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const Color _background = Color(0xFF080711);
  static const Color _navigationBackground = Color(0xFF151020);
  static const Color _primary = Color(0xFF9D20FF);
  static const Color _inactive = Color(0xFF8B8299);

  final MessageService _messageService = MessageService();
  final RoomService _roomService = RoomService();
  final AuthService _authService = AuthService();
  bool _handledInitialRoomLink = false;

  Timer? _verificationCheckTimer;
  bool _showVerificationBanner =
      FirebaseAuth.instance.currentUser?.emailVerified == false;

  late final Stream<List<Conversation>> _conversationsStream;
  StreamSubscription<List<Conversation>>? _conversationSubscription;

  final Map<String, int> _previousUnreadCounts = <String, int>{};

  OverlayEntry? _messageOverlay;
  Timer? _messageOverlayTimer;

  int _selectedIndex = 0;
  int _unreadConversationCount = 0;
  bool _hasInitialConversationSnapshot = false;

  static const List<Widget> _screens = [
    HomeScreen(),
    MessagesScreen(),
    ProfileScreen(),
  ];

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();

    _conversationsStream = _messageService.watchConversations(
      includeArchived: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialRoomLink();
    });

    _conversationSubscription = _conversationsStream.listen(
      _handleConversations,
      onError: (_) {
        // The Chats screen displays Firestore errors directly.
      },
    );

    if (_showVerificationBanner) {
      // Soft reminder, not the active "waiting room" VerifyEmailScreen is —
      // a slower interval is enough here since this just needs to notice
      // "verified elsewhere" eventually, not drive a live countdown.
      _verificationCheckTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkVerification(),
      );
    }
  }

  Future<void> _checkVerification() async {
    final verified = await _authService.reloadCurrentUser();
    if (verified && mounted) {
      _verificationCheckTimer?.cancel();
      setState(() => _showVerificationBanner = false);
    }
  }

  Future<void> _openVerifyEmail() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const VerifyEmailScreen()),
    );
    if (mounted) unawaited(_checkVerification());
  }

  Future<void> _openInitialRoomLink() async {
    if (_handledInitialRoomLink) {
      return;
    }
    _handledInitialRoomLink = true;

    final roomId = Uri.base.queryParameters['room']?.trim();
    if (roomId == null || roomId.isEmpty) {
      return;
    }

    try {
      final room = await _roomService.getRoom(roomId);
      if (!mounted || !room.isLive || !room.isActive) {
        return;
      }
      final joined = await _roomService.joinRoom(roomId);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: joined)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  void dispose() {
    _conversationSubscription?.cancel();
    _verificationCheckTimer?.cancel();
    _removeMessageOverlay();
    super.dispose();
  }

  void _handleConversations(List<Conversation> conversations) {
    final currentUserId = _currentUserId;

    if (currentUserId.isEmpty) {
      return;
    }

    final unreadConversations = conversations.where(
      (conversation) => conversation.unreadCountFor(currentUserId) > 0,
    );

    final newUnreadConversationCount = unreadConversations.length;

    Conversation? newestIncomingConversation;
    int largestIncrease = 0;

    for (final conversation in conversations) {
      final currentUnread = conversation.unreadCountFor(currentUserId);
      final previousUnread = _previousUnreadCounts[conversation.id] ?? 0;
      final increase = currentUnread - previousUnread;

      if (_hasInitialConversationSnapshot &&
          increase > 0 &&
          conversation.lastMessageSenderId != currentUserId &&
          increase > largestIncrease) {
        newestIncomingConversation = conversation;
        largestIncrease = increase;
      }

      _previousUnreadCounts[conversation.id] = currentUnread;
    }

    final activeConversationIds = conversations
        .map((conversation) => conversation.id)
        .toSet();

    _previousUnreadCounts.removeWhere(
      (conversationId, _) => !activeConversationIds.contains(conversationId),
    );

    if (mounted && newUnreadConversationCount != _unreadConversationCount) {
      setState(() {
        _unreadConversationCount = newUnreadConversationCount;
      });
    }

    if (_hasInitialConversationSnapshot &&
        newestIncomingConversation != null &&
        _selectedIndex != 1) {
      _showIncomingMessageOverlay(newestIncomingConversation, currentUserId);
    }

    _hasInitialConversationSnapshot = true;
  }

  void _showIncomingMessageOverlay(
    Conversation conversation,
    String currentUserId,
  ) {
    final otherUserId = conversation.otherUserId(currentUserId);
    final senderName = conversation.displayNameFor(otherUserId);
    final photoUrl = conversation.photoUrlFor(otherUserId);
    final preview = conversation.previewFor(currentUserId);

    _removeMessageOverlay();

    final overlay = Overlay.of(context, rootOverlay: true);

    _messageOverlay = OverlayEntry(
      builder: (overlayContext) {
        final topPadding = MediaQuery.paddingOf(overlayContext).top;

        return Positioned(
          top: topPadding + 10,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: -1, end: 0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value * 90),
                  child: Opacity(opacity: 1 + value, child: child),
                );
              },
              child: _IncomingMessageBanner(
                senderName: senderName,
                photoUrl: photoUrl,
                preview: preview,
                onTap: () {
                  _removeMessageOverlay();

                  if (mounted) {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  }
                },
                onClose: _removeMessageOverlay,
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_messageOverlay!);

    _messageOverlayTimer = Timer(
      const Duration(seconds: 4),
      _removeMessageOverlay,
    );
  }

  void _removeMessageOverlay() {
    _messageOverlayTimer?.cancel();
    _messageOverlayTimer = null;

    _messageOverlay?.remove();
    _messageOverlay = null;
  }

  void _onDestinationSelected(int index) {
    if (_selectedIndex == index) {
      return;
    }

    _removeMessageOverlay();

    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _openVoiceAction() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (sheetContext) {
        return const _VoiceActionSheet();
      },
    );
  }

  Future<void> _openMoreMenu() async {
    final destination = await showMoreSheet(context);
    if (!mounted || destination == null) {
      return;
    }

    await _openMoreDestination(destination);
  }

  Future<void> _openMoreDestination(MoreDestination destination) async {
    final screen = moreDestinationScreen(destination);

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            MoreDestinationPage(destination: destination, child: screen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    HomeScreen.openDiscoverTab = () {
      unawaited(_openMoreDestination(MoreDestination.discover));
    };

    return Scaffold(
      backgroundColor: _background,
      body: Column(
        children: [
          if (_showVerificationBanner)
            _VerificationBanner(onTap: _openVerifyEmail),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNavigation(
        selectedIndex: _selectedIndex,
        unreadConversationCount: _unreadConversationCount,
        onDestinationSelected: _onDestinationSelected,
        onVoicePressed: _openVoiceAction,
        onMorePressed: _openMoreMenu,
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2E2410),
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFFFFC94D),
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Your email isn't verified yet.",
                    style: TextStyle(
                      color: Color(0xFFFFE1A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Text(
                  'Verify now',
                  style: TextStyle(
                    color: Color(0xFFFFC94D),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFFFC94D),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingMessageBanner extends StatelessWidget {
  const _IncomingMessageBanner({
    required this.senderName,
    required this.photoUrl,
    required this.preview,
    required this.onTap,
    required this.onClose,
  });

  final String senderName;
  final String photoUrl;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.trim().isNotEmpty;
    final initial = senderName.trim().isEmpty
        ? '?'
        : senderName.trim()[0].toUpperCase();

    return Material(
      color: const Color(0xFF181120),
      elevation: 18,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF513065)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF251432), Color(0xFF17101F)],
            ),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: const Color(0xFF7526B4),
                    backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                    child: hasPhoto
                        ? null
                        : Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9D20FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF181120),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        color: Colors.white,
                        size: 9,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Text(
                          'now',
                          style: TextStyle(
                            color: Color(0xFF9D95AD),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFC8C0D0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9D95AD),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
  });

  final int selectedIndex;
  final int unreadConversationCount;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: 104 + safeBottom,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 84 + safeBottom,
              decoration: const BoxDecoration(
                color: _MainShellState._navigationBackground,
                border: Border(
                  top: BorderSide(color: Color(0xFF2B2436), width: 1),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 8,
                  bottom: safeBottom + 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Home',
                        isSelected: selectedIndex == 0,
                        onPressed: () => onDestinationSelected(0),
                      ),
                    ),
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        selectedIcon: Icons.chat_bubble_rounded,
                        label: 'Chats',
                        badgeCount: unreadConversationCount,
                        isSelected: selectedIndex == 1,
                        onPressed: () => onDestinationSelected(1),
                      ),
                    ),
                    const SizedBox(width: 88),
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        label: 'Profile',
                        isSelected: selectedIndex == 2,
                        onPressed: () => onDestinationSelected(2),
                      ),
                    ),
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.grid_view_rounded,
                        selectedIcon: Icons.grid_view_rounded,
                        label: 'More',
                        isSelected: false,
                        onPressed: onMorePressed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: _VoiceActionButton(onPressed: onVoicePressed),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected ? Colors.white : _MainShellState._inactive;

    return Semantics(
      button: true,
      selected: isSelected,
      label: badgeCount > 0
          ? '$label, $badgeCount unread conversations'
          : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: isSelected ? 52 : 42,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _MainShellState._primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: isSelected
                              ? const [
                                  BoxShadow(
                                    color: Color(0x559D20FF),
                                    blurRadius: 18,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          isSelected ? selectedIcon : icon,
                          color: color,
                          size: 24,
                        ),
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -5,
                          right: -7,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3F72),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _MainShellState._navigationBackground,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66FF3F72),
                                  blurRadius: 8,
                                ),
                              ],
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
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Use your voice',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFC73AFF),
                  Color(0xFF981DFF),
                  Color(0xFF6A00FF),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x779D20FF),
                  blurRadius: 26,
                  spreadRadius: 2,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: const Center(child: _WaveformIcon()),
          ),
        ),
      ),
    );
  }
}

class _WaveformIcon extends StatelessWidget {
  const _WaveformIcon();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _WaveBar(height: 14),
        SizedBox(width: 4),
        _WaveBar(height: 25),
        SizedBox(width: 4),
        _WaveBar(height: 35),
        SizedBox(width: 4),
        _WaveBar(height: 25),
        SizedBox(width: 4),
        _WaveBar(height: 14),
      ],
    );
  }
}

class _WaveBar extends StatelessWidget {
  const _WaveBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _VoiceActionSheet extends StatelessWidget {
  const _VoiceActionSheet();

  Future<void> _openCreateRoom(BuildContext context) async {
    final navigator = Navigator.of(context);

    navigator.pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!navigator.mounted) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const RoomTypeSelectorScreen()),
    );
  }

  Future<void> _openVoiceMoment(BuildContext context) async {
    final navigator = Navigator.of(context);

    navigator.pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!navigator.mounted) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const RecordVoiceMomentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF151020),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Color(0xFF3A284A))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF51475E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Use your voice',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Choose what you want to create.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9D95AD), fontSize: 14),
          ),
          const SizedBox(height: 24),
          _VoiceOption(
            icon: Icons.mic_rounded,
            title: 'Create Voice Moment',
            subtitle: 'Record and share a short voice update',
            colors: const [Color(0xFF9F22FF), Color(0xFF6A00FF)],
            onPressed: () {
              _openVoiceMoment(context);
            },
          ),
          const SizedBox(height: 13),
          _VoiceOption(
            icon: Icons.groups_2_rounded,
            title: 'Start Voice Room',
            subtitle: 'Open a live room and invite people',
            colors: const [Color(0xFFFF3E81), Color(0xFF9C1DFF)],
            onPressed: () {
              _openCreateRoom(context);
            },
          ),
        ],
      ),
    );
  }
}

class _VoiceOption extends StatelessWidget {
  const _VoiceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C1627),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF382A47)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: Colors.white, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9D95AD),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF81768E)),
            ],
          ),
        ),
      ),
    );
  }
}

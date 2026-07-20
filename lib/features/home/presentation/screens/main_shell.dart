import 'package:flutter/material.dart';

import 'package:yovoice/features/home/presentation/screens/home_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';

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

  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    HomeScreen(),
    DiscoverScreen(),
    MessagesScreen(),
    ProfileScreen(),
  ];

  void _onDestinationSelected(int index) {
    if (_selectedIndex == index) {
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: _BottomNavigation(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        onVoicePressed: _openVoiceAction,
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onVoicePressed,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

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
                  left: 8,
                  right: 8,
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
                        onPressed: () {
                          onDestinationSelected(0);
                        },
                      ),
                    ),
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.explore_outlined,
                        selectedIcon: Icons.explore_rounded,
                        label: 'Discover',
                        isSelected: selectedIndex == 1,
                        onPressed: () {
                          onDestinationSelected(1);
                        },
                      ),
                    ),
                    const SizedBox(width: 84),
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        selectedIcon: Icons.chat_bubble_rounded,
                        label: 'Chats',
                        isSelected: selectedIndex == 2,
                        onPressed: () {
                          onDestinationSelected(2);
                        },
                      ),
                    ),
                    Expanded(
                      child: _NavigationItem(
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        label: 'Profile',
                        isSelected: selectedIndex == 3,
                        onPressed: () {
                          onDestinationSelected(3);
                        },
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
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected ? Colors.white : _MainShellState._inactive;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
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
    final NavigatorState navigator = Navigator.of(context);

    navigator.pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!navigator.mounted) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const CreateRoomScreen();
        },
      ),
    );
  }

  Future<void> _openVoiceMoment(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    navigator.pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!messenger.mounted) {
      return;
    }

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: const Text('Voice Moments recording is coming next.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A1939),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
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
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF81768E),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

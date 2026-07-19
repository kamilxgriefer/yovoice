import 'package:flutter/material.dart';

import 'package:yovoice/features/chats/presentation/screens/chats_screen.dart';
import 'package:yovoice/features/home/presentation/screens/home_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';

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
    ChatsScreen(),
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

  void _openVoiceAction() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) {
        return const _VoiceActionSheet();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _VoiceActionButton(onPressed: _openVoiceAction),
      bottomNavigationBar: _BottomNavigation(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 86,
      padding: EdgeInsets.zero,
      color: _MainShellState._navigationBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      notchMargin: 10,
      shape: const CircularNotchedRectangle(),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
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
            const SizedBox(width: 72),
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
    final color = isSelected ? Colors.white : _MainShellState._inactive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceActionButton extends StatefulWidget {
  const _VoiceActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_VoiceActionButton> createState() => _VoiceActionButtonState();
}

class _VoiceActionButtonState extends State<_VoiceActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1, end: 1.06).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: widget.onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 66,
            height: 66,
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
                  blurRadius: 25,
                  spreadRadius: 2,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: const _WaveformIcon(),
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
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _WaveBar(height: 13),
        SizedBox(width: 3),
        _WaveBar(height: 23),
        SizedBox(width: 3),
        _WaveBar(height: 32),
        SizedBox(width: 3),
        _WaveBar(height: 23),
        SizedBox(width: 3),
        _WaveBar(height: 13),
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
      width: 3,
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
              Navigator.of(context).pop();

              _showComingSoon(
                context,
                'Voice Moments recording is coming next.',
              );
            },
          ),
          const SizedBox(height: 13),
          _VoiceOption(
            icon: Icons.groups_2_rounded,
            title: 'Start Voice Room',
            subtitle: 'Open a live room and invite people',
            colors: const [Color(0xFFFF3E81), Color(0xFF9C1DFF)],
            onPressed: () {
              Navigator.of(context).pop();

              _showComingSoon(context, 'Voice Room creation is coming next.');
            },
          ),
        ],
      ),
    );
  }

  static void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A1939),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

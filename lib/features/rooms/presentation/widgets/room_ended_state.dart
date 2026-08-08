import 'package:flutter/material.dart';

import 'package:yovoice/features/home/presentation/screens/home_screen.dart';

/// The polished full-screen state a participant lands on when the room
/// they were in ends (host closed it, or they were removed after it shut
/// down) — instead of an empty stage or a snackbar-and-eject.
class RoomEndedState extends StatelessWidget {
  const RoomEndedState({
    required this.roomName,
    this.accent = const Color(0xFF9D20FF),
    super.key,
  });

  final String roomName;

  /// Matches the room's visual system (purple for community, red for
  /// broadcast) so the ending still feels like the room it belonged to.
  final Color accent;

  void _backToHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _discoverRooms(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    // The shell wires this static hook to open Discover over itself.
    HomeScreen.openDiscoverTab?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF20A0710),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .14),
              border: Border.all(color: accent.withValues(alpha: .45)),
            ),
            child: Icon(Icons.podcasts_rounded, color: accent, size: 38),
          ),
          const SizedBox(height: 22),
          const Text(
            'This room has ended',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thanks for listening to "$roomName".',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 14),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => _discoverRooms(context),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              minimumSize: const Size(230, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Discover more rooms',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _backToHome(context),
            child: const Text(
              'Back to Home',
              style: TextStyle(color: Color(0xFFB9AECB)),
            ),
          ),
        ],
      ),
    );
  }
}

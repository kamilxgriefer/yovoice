import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';

class BroadcastTopBar extends StatelessWidget {
  const BroadcastTopBar({
    super.key,
    required this.title,
    required this.count,
    required this.isHost,
    required this.onBack,
    required this.onPeople,
    required this.onMenu,
    required this.onShare,
  });

  final String title;
  final int count;
  final bool isHost;
  final VoidCallback onBack;
  final VoidCallback onPeople;
  final VoidCallback onMenu;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            color: Colors.white,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'BROADCAST ROOM',
                  style: TextStyle(
                    color: BroadcastRoomColors.accentSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Share room',
            onPressed: onShare,
            color: Colors.white,
            icon: const Icon(Icons.ios_share_rounded, size: 21),
          ),
          TextButton.icon(
            onPressed: onPeople,
            icon: const Icon(Icons.groups_rounded, size: 18),
            label: Text('$count'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          if (isHost)
            IconButton(
              tooltip: 'Manage broadcast',
              onPressed: onMenu,
              color: Colors.white,
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
    );
  }
}

class BroadcastLiveBadge extends StatelessWidget {
  const BroadcastLiveBadge({super.key, required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x33FF314F),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0x88FF314F)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 4,
              backgroundColor: BroadcastRoomColors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              isLive ? 'LIVE BROADCAST' : 'OFFLINE',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BroadcastHostStage extends StatelessWidget {
  const BroadcastHostStage({
    super.key,
    required this.participant,
    required this.fallbackName,
    required this.pulse,
  });

  final RoomParticipant? participant;
  final String fallbackName;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final name = participant?.displayName ?? fallbackName;
    final initial = name.trim().isEmpty ? 'H' : name.trim()[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xCC1A0B0F),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF772635)),
        boxShadow: const [
          BoxShadow(color: Color(0x44FF314F), blurRadius: 28, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.podcasts_rounded,
            color: BroadcastRoomColors.accent,
            size: 30,
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) =>
                Transform.scale(scale: 1 + pulse.value * .025, child: child),
            child: CircleAvatar(
              radius: 61,
              backgroundColor: const Color(0xFF7A1C2D),
              backgroundImage: participant?.photoUrl == null
                  ? null
                  : NetworkImage(participant!.photoUrl!),
              child: participant?.photoUrl == null
                  ? Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'HOST • ON AIR',
            style: TextStyle(
              color: BroadcastRoomColors.accentSoft,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class BroadcastSectionHeader extends StatelessWidget {
  const BroadcastSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: BroadcastRoomColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF6D1D2B),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';

class BroadcastOwnerQuickActions extends StatelessWidget {
  const BroadcastOwnerQuickActions({
    super.key,
    required this.raisedHands,
    required this.onParticipants,
    required this.onHands,
    required this.onManage,
    required this.onShare,
  });

  final int raisedHands;
  final VoidCallback onParticipants;
  final VoidCallback onHands;
  final VoidCallback onManage;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xE61A0B0F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: BroadcastRoomColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: BroadcastQuickAction(
              icon: Icons.groups_rounded,
              label: 'Guests',
              onTap: onParticipants,
            ),
          ),
          Expanded(
            child: BroadcastQuickAction(
              icon: Icons.back_hand_rounded,
              label: raisedHands > 0 ? 'Hands $raisedHands' : 'Hands',
              onTap: onHands,
              highlighted: raisedHands > 0,
            ),
          ),
          Expanded(
            child: BroadcastQuickAction(
              icon: Icons.tune_rounded,
              label: 'Manage',
              onTap: onManage,
            ),
          ),
          Expanded(
            child: BroadcastQuickAction(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: onShare,
            ),
          ),
        ],
      ),
    );
  }
}

class BroadcastQuickAction extends StatelessWidget {
  const BroadcastQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: highlighted
                    ? BroadcastRoomColors.accent
                    : const Color(0xFF37141B),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BroadcastClickableStats extends StatelessWidget {
  const BroadcastClickableStats({
    super.key,
    required this.speakers,
    required this.listeners,
    required this.raisedHands,
    required this.onSpeakers,
    required this.onListeners,
    required this.onHands,
  });

  final int speakers;
  final int listeners;
  final int raisedHands;
  final VoidCallback onSpeakers;
  final VoidCallback onListeners;
  final VoidCallback onHands;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: BroadcastStatTile(
            label: 'Speaking',
            value: speakers,
            icon: Icons.graphic_eq_rounded,
            onTap: onSpeakers,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: BroadcastStatTile(
            label: 'Listeners',
            value: listeners,
            icon: Icons.headphones_rounded,
            onTap: onListeners,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: BroadcastStatTile(
            label: 'Hands',
            value: raisedHands,
            icon: Icons.back_hand_rounded,
            onTap: onHands,
          ),
        ),
      ],
    );
  }
}

class BroadcastStatTile extends StatelessWidget {
  const BroadcastStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BroadcastRoomColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(
                icon,
                color: BroadcastRoomColors.accentSoft,
                size: 20,
              ),
              const SizedBox(height: 5),
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: BroadcastRoomColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

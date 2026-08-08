import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';

class OwnerMenuSheet extends StatelessWidget {
  const OwnerMenuSheet({
    super.key,
    required this.onShare,
    required this.onParticipants,
    required this.onHands,
    required this.onSettings,
    required this.onAnalytics,
    required this.onEnd,
    required this.onDelete,
  });

  final VoidCallback onShare;
  final VoidCallback onParticipants;
  final VoidCallback onHands;
  final VoidCallback onSettings;
  final VoidCallback onAnalytics;
  final VoidCallback onEnd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                child: Text(
                  'Manage broadcast',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            OwnerMenuItem(
              icon: Icons.ios_share_rounded,
              title: 'Share room',
              subtitle: 'Copy the invitation link or room ID',
              onTap: onShare,
            ),
            OwnerMenuItem(
              icon: Icons.groups_rounded,
              title: 'Participants',
              subtitle: 'Manage stage, audience, mute and removal',
              onTap: onParticipants,
            ),
            OwnerMenuItem(
              icon: Icons.back_hand_rounded,
              title: 'Raised hands',
              subtitle: 'Review listeners requesting the stage',
              onTap: onHands,
            ),
            OwnerMenuItem(
              icon: Icons.settings_rounded,
              title: 'Room settings',
              subtitle: 'Edit details, capacity and moderation options',
              onTap: onSettings,
            ),
            OwnerMenuItem(
              icon: Icons.analytics_rounded,
              title: 'Live analytics',
              subtitle: 'View the current broadcast snapshot',
              onTap: onAnalytics,
            ),
            const Divider(color: Color(0xFF3B171E), height: 22),
            OwnerMenuItem(
              icon: Icons.stop_circle_rounded,
              title: 'End broadcast',
              subtitle: 'Disconnect everyone and close this broadcast',
              onTap: onEnd,
              destructive: true,
            ),
            OwnerMenuItem(
              icon: Icons.delete_forever_rounded,
              title: 'Delete room permanently',
              subtitle: 'Remove the room and its messages from YO Voice',
              onTap: onDelete,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerMenuItem extends StatelessWidget {
  const OwnerMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? BroadcastRoomColors.accentSoft : Colors.white;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xFF45151F)
              : const Color(0xFF301219),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: BroadcastRoomColors.muted, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: color),
    );
  }
}

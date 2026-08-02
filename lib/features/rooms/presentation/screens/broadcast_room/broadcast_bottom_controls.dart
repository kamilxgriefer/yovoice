import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';

class BroadcastBottomControls extends StatelessWidget {
  const BroadcastBottomControls({
    super.key,
    required this.isHost,
    required this.joining,
    required this.ending,
    required this.handRaised,
    required this.canRaiseHand,
    required this.onJoin,
    required this.onRaiseHand,
    required this.onShare,
    required this.onParticipants,
    required this.onEnd,
  });

  final bool isHost;
  final bool joining;
  final bool ending;
  final bool handRaised;
  final bool canRaiseHand;
  final VoidCallback onJoin;
  final VoidCallback onRaiseHand;
  final VoidCallback onShare;
  final VoidCallback onParticipants;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF21A0B0F),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: BroadcastRoomColors.border),
      ),
      child: isHost
          ? Row(
              children: [
                Expanded(
                  child: BroadcastHostBottomAction(
                    icon: Icons.headphones_rounded,
                    label: joining ? 'Joining…' : 'Enter',
                    onTap: joining || ending ? null : onJoin,
                  ),
                ),
                Expanded(
                  child: BroadcastHostBottomAction(
                    icon: Icons.groups_rounded,
                    label: 'Guests',
                    onTap: ending ? null : onParticipants,
                  ),
                ),
                Expanded(
                  child: BroadcastHostBottomAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: ending ? null : onShare,
                  ),
                ),
                Expanded(
                  child: BroadcastHostBottomAction(
                    icon: Icons.stop_circle_rounded,
                    label: 'End',
                    destructive: true,
                    onTap: ending ? null : onEnd,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: joining ? null : onJoin,
                    icon: const Icon(Icons.headphones_rounded),
                    label: Text(joining ? 'Joining…' : 'Join broadcast'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BroadcastRoomColors.accent,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: canRaiseHand ? onRaiseHand : null,
                  style: IconButton.styleFrom(
                    backgroundColor: handRaised
                        ? const Color(0xFFFF6A76)
                        : const Color(0xFF37141B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: Icon(
                    handRaised
                        ? Icons.pan_tool_alt_rounded
                        : Icons.back_hand_outlined,
                  ),
                  tooltip: handRaised ? 'Lower hand' : 'Raise hand',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onShare,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF37141B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Share room',
                ),
              ],
            ),
    );
  }
}

class BroadcastHostBottomAction extends StatelessWidget {
  const BroadcastHostBottomAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onTap == null
                  ? Colors.white30
                  : destructive
                  ? BroadcastRoomColors.accentSoft
                  : Colors.white,
              size: 23,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: onTap == null
                    ? Colors.white30
                    : destructive
                    ? BroadcastRoomColors.accentSoft
                    : Colors.white,
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

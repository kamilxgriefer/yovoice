import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';

/// The broadcast room's one stable control bar. Live audio is connected
/// the moment the room opens, so there is no "Enter" button anymore —
/// the bar holds the actions a participant actually uses, in fixed
/// positions: mic (or raise-hand for the audience), participants, share,
/// and an explicit Leave (End for the host).
class BroadcastBottomControls extends StatelessWidget {
  const BroadcastBottomControls({
    super.key,
    required this.isHost,
    required this.ending,
    required this.connected,
    required this.micMuted,
    required this.micBusy,
    required this.canSpeak,
    required this.handRaised,
    required this.canRaiseHand,
    required this.onMic,
    required this.onRaiseHand,
    required this.onShare,
    required this.onParticipants,
    required this.onEnd,
    required this.onLeave,
    required this.onChat,
  });

  final bool isHost;
  final bool ending;
  final bool connected;
  final bool micMuted;
  final bool micBusy;

  /// Host or promoted speaker — the only people whose mic button works.
  /// The server-minted LiveKit token enforces the same rule; this just
  /// keeps the UI honest about it.
  final bool canSpeak;
  final bool handRaised;
  final bool canRaiseHand;
  final VoidCallback onMic;
  final VoidCallback onRaiseHand;
  final VoidCallback onShare;
  final VoidCallback onParticipants;
  final VoidCallback onEnd;
  final VoidCallback onLeave;
  final VoidCallback onChat;

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
      child: Row(
        children: [
          if (canSpeak)
            Expanded(
              child: BroadcastHostBottomAction(
                icon: micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: micMuted ? 'Unmute' : 'Mute',
                highlighted: !micMuted,
                onTap: ending || micBusy || !connected ? null : onMic,
              ),
            )
          else
            Expanded(
              child: BroadcastHostBottomAction(
                icon: handRaised
                    ? Icons.pan_tool_alt_rounded
                    : Icons.back_hand_outlined,
                label: handRaised ? 'Lower hand' : 'Raise hand',
                highlighted: handRaised,
                onTap: ending || !canRaiseHand ? null : onRaiseHand,
              ),
            ),
          Expanded(
            child: BroadcastHostBottomAction(
              icon: Icons.forum_rounded,
              label: 'Chat',
              onTap: ending ? null : onChat,
            ),
          ),
          Expanded(
            child: BroadcastHostBottomAction(
              icon: Icons.groups_rounded,
              label: 'People',
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
              icon: isHost
                  ? Icons.stop_circle_rounded
                  : Icons.logout_rounded,
              label: isHost ? 'End' : 'Leave',
              destructive: true,
              onTap: ending ? null : (isHost ? onEnd : onLeave),
            ),
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
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? Colors.white30
        : destructive
        ? BroadcastRoomColors.accentSoft
        : highlighted
        ? const Color(0xFFFFB3BD)
        : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
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

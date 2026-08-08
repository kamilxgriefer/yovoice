import 'package:flutter/material.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

/// The persistent mini-player: when the user navigates away from a live
/// room while still connected, this bar (hosted by the shell, directly
/// above the bottom navigation) keeps the room one tap away — with mute
/// and an explicit leave — instead of the audio silently continuing with
/// no UI attached to it, which is exactly what used to happen.
///
/// Renders nothing when no room connection exists, so the shell can
/// mount it unconditionally.
class RoomMiniBar extends StatelessWidget {
  const RoomMiniBar({super.key});

  static final RoomService _rooms = RoomService();

  Future<void> _returnToRoom(BuildContext context, String roomId) async {
    try {
      final room = await _rooms.getRoom(roomId);
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
      );
    } catch (_) {
      // Room doc gone (ended while minimized): drop the stale session.
      await VoiceCallService.instance.disconnect();
    }
  }

  Future<void> _leave(String roomId) async {
    final voice = VoiceCallService.instance;
    await voice.disconnect();
    try {
      await _rooms.leaveRoom(roomId);
    } catch (_) {
      // Best effort — the audio is already gone, and the participant doc
      // is cleaned up by moderation/room-end flows if this write failed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = VoiceCallService.instance;
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final roomId = voice.roomId;
        final active =
            roomId != null &&
            (voice.status == VoiceCallStatus.connected ||
                voice.status == VoiceCallStatus.connecting ||
                voice.status == VoiceCallStatus.reconnecting);
        if (!active) return const SizedBox.shrink();

        final reconnecting = voice.status != VoiceCallStatus.connected;

        return Material(
          color: const Color(0xFF1D1329),
          child: InkWell(
            onTap: () => _returnToRoom(context, roomId),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 9, 6, 9),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF3A2C49)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reconnecting
                          ? const Color(0xFFFFB547)
                          : const Color(0xFFFF3F72),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          voice.roomName ?? 'Live room',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          reconnecting ? 'Reconnecting…' : 'Live · tap to return',
                          style: const TextStyle(
                            color: Color(0xFFA69CAF),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: voice.isMuted ? 'Unmute' : 'Mute',
                    visualDensity: VisualDensity.compact,
                    onPressed: voice.muteChangeInProgress
                        ? null
                        : voice.toggleMute,
                    icon: Icon(
                      voice.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: voice.isMuted
                          ? const Color(0xFF9C90A8)
                          : Colors.white,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Leave room',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _leave(roomId),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFFF6A76),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

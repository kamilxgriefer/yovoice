import 'package:flutter/material.dart';

import '../../data/services/voice_call_service.dart';
import '../screens/voice_call_screen.dart';

class ActiveVoiceBar extends StatefulWidget {
  const ActiveVoiceBar({super.key});

  @override
  State<ActiveVoiceBar> createState() => _ActiveVoiceBarState();
}

class _ActiveVoiceBarState extends State<ActiveVoiceBar> {
  final _voice = VoiceCallService.instance;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_refresh);
  }

  @override
  void dispose() {
    _voice.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final roomId = _voice.roomId;
    final roomName = _voice.roomName;

    if (roomId == null ||
        roomName == null ||
        _voice.status == VoiceCallStatus.disconnected) {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFF251332),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  VoiceCallScreen(roomId: roomId, roomName: roomName),
            ),
          );
        },
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _voice.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.graphic_eq_rounded,
                  color: const Color(0xFFC66CFF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _voice.status == VoiceCallStatus.reconnecting
                      ? 'Reconnecting…'
                      : 'Voice connected',
                  style: const TextStyle(
                    color: Color(0xFFB8ADBF),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

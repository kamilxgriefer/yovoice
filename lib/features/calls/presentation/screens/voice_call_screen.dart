import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/services/voice_call_service.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    required this.roomId,
    required this.roomName,
    super.key,
  });

  final String roomId;
  final String roomName;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final _voice = VoiceCallService.instance;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_refresh);
    _connect();
  }

  @override
  void dispose() {
    _voice.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _connect() async {
    if (_voice.roomId == widget.roomId && _voice.isConnected) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final participantName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YoVoice user';

    try {
      await _voice.join(
        roomId: widget.roomId,
        roomName: widget.roomName,
        participantName: participantName,
      );
    } catch (_) {
      if (!mounted) return;
      final message = _voice.errorMessage ?? 'Could not join voice chat.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    await _voice.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final participants = _voice.participants;

    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080711),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Minimize voice chat',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.roomName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              _statusText(_voice.status),
              style: const TextStyle(
                color: Color(0xFF9D95AD),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: participants.isEmpty
                  ? _EmptyState(
                      status: _voice.status,
                      errorMessage: _voice.errorMessage,
                      onRetry: _connect,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: participants.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            mainAxisExtent: 174,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                      itemBuilder: (context, index) {
                        return _ParticipantCard(
                          participant: participants[index],
                        );
                      },
                    ),
            ),
            _Controls(
              status: _voice.status,
              isMuted: _voice.isMuted,
              onMute: _voice.toggleMute,
              onLeave: _leave,
              onRetry: _connect,
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(VoiceCallStatus status) {
    return switch (status) {
      VoiceCallStatus.disconnected => 'Disconnected',
      VoiceCallStatus.connecting => 'Connecting…',
      VoiceCallStatus.connected => 'Voice connected',
      VoiceCallStatus.reconnecting => 'Reconnecting…',
      VoiceCallStatus.failed => 'Connection failed',
    };
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({required this.participant});

  final VoiceParticipantViewData participant;

  @override
  Widget build(BuildContext context) {
    final initial = participant.displayName.trim().isEmpty
        ? '?'
        : participant.displayName.trim()[0].toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          width: participant.isSpeaking ? 2 : 1,
          color: participant.isSpeaking
              ? const Color(0xFFB63EFF)
              : const Color(0xFF3A2C46),
        ),
        boxShadow: participant.isSpeaking
            ? [
                BoxShadow(
                  color: const Color(0xFFA226FF).withValues(alpha: .24),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: participant.isSpeaking
                ? const Color(0xFF7623A8)
                : const Color(0xFF32133E),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            participant.isLocal
                ? 'You'
                : participant.isSpeaking
                    ? 'Speaking'
                    : 'Listening',
            style: TextStyle(
              color: participant.isSpeaking
                  ? const Color(0xFFC66CFF)
                  : const Color(0xFF9D95AD),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.status,
    required this.errorMessage,
    required this.onRetry,
  });

  final VoiceCallStatus status;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = status == VoiceCallStatus.failed;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.graphic_eq_rounded,
              color: failed
                  ? const Color(0xFFFF6685)
                  : const Color(0xFFB63EFF),
              size: 58,
            ),
            const SizedBox(height: 16),
            Text(
              failed ? 'Could not connect' : 'Joining voice chat…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (failed) ...[
              const SizedBox(height: 10),
              Text(
                errorMessage ?? 'Unknown connection error.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9D95AD)),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.status,
    required this.isMuted,
    required this.onMute,
    required this.onLeave,
    required this.onRetry,
  });

  final VoiceCallStatus status;
  final bool isMuted;
  final Future<void> Function() onMute;
  final Future<void> Function() onLeave;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final connected = status == VoiceCallStatus.connected;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF110C18),
        border: Border(top: BorderSide(color: Color(0xFF2E2138))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            label: isMuted ? 'Unmute' : 'Mute',
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            active: isMuted,
            onPressed: connected ? onMute : null,
          ),
          const SizedBox(width: 16),
          _ControlButton(
            label: 'Leave',
            icon: Icons.call_end_rounded,
            danger: true,
            onPressed: onLeave,
          ),
          if (status == VoiceCallStatus.failed) ...[
            const SizedBox(width: 16),
            _ControlButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () async => onRetry(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final Future<void> Function()? onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFFF416C)
        : active
            ? const Color(0xFF4A1B5A)
            : const Color(0xFF24182E);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed == null
              ? null
              : () {
                  onPressed!();
                },
          style: IconButton.styleFrom(
            backgroundColor: background,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF241D2A),
            minimumSize: const Size(58, 58),
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFB8ADBF),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

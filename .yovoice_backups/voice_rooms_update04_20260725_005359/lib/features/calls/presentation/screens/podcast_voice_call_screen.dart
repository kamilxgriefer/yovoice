import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

class PodcastVoiceCallScreen extends StatefulWidget {
  const PodcastVoiceCallScreen({
    required this.roomId,
    required this.roomName,
    required this.hostId,
    super.key,
  });

  final String roomId;
  final String roomName;
  final String hostId;

  @override
  State<PodcastVoiceCallScreen> createState() => _PodcastVoiceCallScreenState();
}

class _PodcastVoiceCallScreenState extends State<PodcastVoiceCallScreen>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF07050D);
  static const _surface = Color(0xFF171020);
  static const _border = Color(0xFF4A2740);
  static const _accent = Color(0xFFFF3F8E);
  static const _muted = Color(0xFFA69CAF);

  final VoiceCallService _voice = VoiceCallService.instance;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _voice.addListener(_refresh);
    _connect();
  }

  @override
  void dispose() {
    _voice.removeListener(_refresh);
    _pulse.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_voice.errorMessage ?? 'Could not join podcast.'),
        ),
      );
    }
  }

  Future<void> _leave() async {
    await _voice.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final participants = _voice.participants;
    final host =
        participants
            .where((person) => person.identity == widget.hostId)
            .firstOrNull ??
        (participants.isNotEmpty ? participants.first : null);
    final speakers = participants
        .where((person) => person.identity != host?.identity)
        .toList();

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _PodcastTopBar(
              title: widget.roomName,
              participantCount: participants.length,
              onBack: _leave,
            ),
            Expanded(
              child: _voice.status == VoiceCallStatus.failed
                  ? _ConnectionError(
                      message: _voice.errorMessage,
                      onRetry: _connect,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                      children: [
                        _HostCenter(
                          participant: host,
                          pulse: _pulse,
                          connected: _voice.isConnected,
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'On stage',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _CountBadge(count: speakers.length),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (speakers.isEmpty)
                          const _EmptyStage()
                        else
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: speakers
                                .map(
                                  (speaker) =>
                                      _SpeakerCard(participant: speaker),
                                )
                                .toList(growable: false),
                          ),
                      ],
                    ),
            ),
            _PodcastControls(
              connected: _voice.isConnected,
              isMuted: _voice.isMuted,
              muteBusy: _voice.muteChangeInProgress,
              onMute: _voice.toggleMute,
              onLeave: _leave,
            ),
          ],
        ),
      ),
    );
  }
}

class _PodcastTopBar extends StatelessWidget {
  const _PodcastTopBar({
    required this.title,
    required this.participantCount,
    required this.onBack,
  });

  final String title;
  final int participantCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            color: Colors.white,
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
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'PODCAST ROOM',
                  style: TextStyle(
                    color: _PodcastVoiceCallScreenState._accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _PodcastVoiceCallScreenState._surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _PodcastVoiceCallScreenState._border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.headphones_rounded,
                  color: Colors.white,
                  size: 17,
                ),
                const SizedBox(width: 6),
                Text(
                  '$participantCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HostCenter extends StatelessWidget {
  const _HostCenter({
    required this.participant,
    required this.pulse,
    required this.connected,
  });

  final VoiceParticipantViewData? participant;
  final Animation<double> pulse;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final person = participant;
    final name = person?.displayName ?? 'Host';
    final initial = name.trim().isEmpty ? 'H' : name.trim()[0].toUpperCase();
    final speaking = person?.isSpeaking ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF351225), Color(0xFF171020)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF6A304E)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.podcasts_rounded,
            color: _PodcastVoiceCallScreenState._accent,
            size: 34,
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final scale = speaking ? 1 + pulse.value * .055 : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFFF5AA3),
                    Color(0xFF7D174A),
                    Color(0xFF310D22),
                  ],
                ),
                border: Border.all(
                  color: speaking
                      ? const Color(0xFFFF85B7)
                      : const Color(0xFF7B3557),
                  width: speaking ? 4 : 2,
                ),
                boxShadow: speaking
                    ? const [
                        BoxShadow(
                          color: Color(0x99FF3F8E),
                          blurRadius: 34,
                          spreadRadius: 7,
                        ),
                      ]
                    : const [
                        BoxShadow(color: Color(0x55000000), blurRadius: 24),
                      ],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
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
            'HOST',
            style: TextStyle(
              color: _PodcastVoiceCallScreenState._accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            connected
                ? (speaking ? 'Speaking now' : 'Hosting live')
                : 'Connecting…',
            style: const TextStyle(color: _PodcastVoiceCallScreenState._muted),
          ),
        ],
      ),
    );
  }
}

class _SpeakerCard extends StatelessWidget {
  const _SpeakerCard({required this.participant});

  final VoiceParticipantViewData participant;

  @override
  Widget build(BuildContext context) {
    final initial = participant.displayName.trim().isEmpty
        ? 'Y'
        : participant.displayName.trim()[0].toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PodcastVoiceCallScreenState._surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: participant.isSpeaking
              ? _PodcastVoiceCallScreenState._accent
              : _PodcastVoiceCallScreenState._border,
          width: participant.isSpeaking ? 2 : 1,
        ),
        boxShadow: participant.isSpeaking
            ? const [BoxShadow(color: Color(0x55FF3F8E), blurRadius: 18)]
            : null,
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: const Color(0xFF6D214C),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            participant.isLocal ? 'You' : participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Icon(
            participant.isMuted
                ? Icons.mic_off_rounded
                : Icons.graphic_eq_rounded,
            color: participant.isMuted
                ? _PodcastVoiceCallScreenState._muted
                : _PodcastVoiceCallScreenState._accent,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFF6E214F),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _PodcastVoiceCallScreenState._surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _PodcastVoiceCallScreenState._border),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.chair_alt_rounded,
            color: _PodcastVoiceCallScreenState._accent,
            size: 34,
          ),
          SizedBox(height: 10),
          Text(
            'The host is live. Speakers invited to the stage will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _PodcastVoiceCallScreenState._muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PodcastControls extends StatelessWidget {
  const _PodcastControls({
    required this.connected,
    required this.isMuted,
    required this.muteBusy,
    required this.onMute,
    required this.onLeave,
  });

  final bool connected;
  final bool isMuted;
  final bool muteBusy;
  final Future<void> Function() onMute;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xF0171020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _PodcastVoiceCallScreenState._border),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: connected && !muteBusy ? () => onMute() : null,
              icon: Icon(isMuted ? Icons.mic_off_rounded : Icons.mic_rounded),
              label: Text(
                muteBusy
                    ? 'Changing…'
                    : isMuted
                    ? 'Unmute'
                    : 'Mute',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _PodcastVoiceCallScreenState._accent,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: () => onLeave(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFF416C),
            ),
            icon: const Icon(Icons.call_end_rounded),
            tooltip: 'Leave',
          ),
        ],
      ),
    );
  }
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFFF5C7B),
              size: 58,
            ),
            const SizedBox(height: 14),
            const Text(
              'Could not connect to podcast',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message ?? 'Unknown connection error.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _PodcastVoiceCallScreenState._muted,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

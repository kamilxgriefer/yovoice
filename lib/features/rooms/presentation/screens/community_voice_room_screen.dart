import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';

class CommunityVoiceRoomScreen extends StatefulWidget {
  const CommunityVoiceRoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<CommunityVoiceRoomScreen> createState() =>
      _CommunityVoiceRoomScreenState();
}

class _CommunityVoiceRoomScreenState extends State<CommunityVoiceRoomScreen>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF05030A);

  final _voice = VoiceCallService.instance;
  final _rooms = RoomService();
  late final AnimationController _motion;
  // Single shared stream instance -- both the manual subscription below and
  // the StreamBuilder in build() listen to this same Stream, instead of
  // each calling watchParticipants() independently. Firestore's snapshots()
  // streams are broadcast, so this is safe, and it means only one live
  // listener is registered instead of two (and previously, since the
  // StreamBuilder called watchParticipants() inline in build(), every
  // setState() in this screen was tearing down and re-registering its
  // listener on every rebuild).
  late final Stream<List<RoomParticipant>> _participants;
  StreamSubscription<List<RoomParticipant>>? _participantSubscription;
  bool _joinedDocumentSeen = false;
  bool _leaving = false;
  bool _roomOver = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isHost => _uid == widget.room.hostId;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
    _voice.addListener(_refresh);
    _participants = _rooms.watchParticipants(widget.room.id);
    _participantSubscription = _participants.listen(_handleParticipantState);
    unawaited(_connect());
  }

  @override
  void dispose() {
    _participantSubscription?.cancel();
    _voice.removeListener(_refresh);
    _motion.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YO Voice user';
    try {
      if (_voice.roomId != widget.room.id || !_voice.isConnected) {
        await _voice.join(
          roomId: widget.room.id,
          roomName: widget.room.name,
          participantName: name,
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_voice.errorMessage ?? 'Could not join voice.')),
      );
    }
  }

  Future<void> _handleParticipantState(
    List<RoomParticipant> participants,
  ) async {
    final own = participants.where((participant) => participant.userId == _uid);
    if (own.isNotEmpty) {
      _joinedDocumentSeen = true;
      final participant = own.first;
      if (participant.isMuted != _voice.isMuted && _voice.isConnected) {
        await _voice.setMuted(participant.isMuted);
      }
      return;
    }

    if (_joinedDocumentSeen && mounted && !_leaving) {
      // Removed by the host, or the room ended: cut the audio and show
      // the ended state instead of ejecting with a snackbar.
      _leaving = true;
      await _voice.disconnect();
      if (!mounted) return;
      setState(() => _roomOver = true);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _voice.disconnect();
    await _rooms.leaveRoom(widget.room.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _toggleMute() async {
    await _voice.toggleMute();
    await _rooms.setMuted(roomId: widget.room.id, isMuted: _voice.isMuted);
  }

  /// The mic can't publish right now — say why instead of a dead tap.
  void _explainMicState() {
    final message = switch (_voice.micState) {
      MicState.connecting => 'Connecting to live audio…',
      MicState.listenOnly =>
        "You're listening — the host controls who can speak here.",
      MicState.unavailable =>
        _voice.errorMessage ??
            'Live audio is not connected. Leave and rejoin to retry.',
      MicState.on || MicState.muted => '',
    };
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openParticipants(
    List<RoomParticipant> participants, {
    required bool speakersOnly,
  }) {
    final visible = speakersOnly
        ? participants.where((participant) => participant.isSpeaker).toList()
        : participants.where((participant) => !participant.isSpeaker).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ParticipantsSheet(
        title: speakersOnly ? 'Speaking now' : 'Listeners',
        participants: visible,
        hostId: widget.room.hostId,
        currentUserId: _uid,
        canModerate: _isHost,
        onMute: (participant, muted) async {
          await _rooms.moderateParticipantMute(
            roomId: widget.room.id,
            participantId: participant.userId,
            isMuted: muted,
          );
        },
        onRemove: (participant) async {
          await _rooms.removeParticipant(
            roomId: widget.room.id,
            participantId: participant.userId,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomParticipant>>(
      stream: _participants,
      builder: (context, snapshot) {
        final roomParticipants = snapshot.data ?? const <RoomParticipant>[];
        final speaking = roomParticipants
            .where((participant) => participant.isSpeaker)
            .length;
        final listeners = roomParticipants.length - speaking;

        if (_roomOver) {
          return Scaffold(
            backgroundColor: _background,
            body: SafeArea(
              child: RoomEndedState(roomName: widget.room.name),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  roomName: widget.room.name,
                  status: _voice.status,
                  speaking: speaking,
                  listeners: listeners,
                  onBack: () => Navigator.of(context).pop(),
                  onSpeakingTap: () =>
                      _openParticipants(roomParticipants, speakersOnly: true),
                  onListenersTap: () =>
                      _openParticipants(roomParticipants, speakersOnly: false),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _motion,
                    builder: (context, _) => _CosmicStage(
                      participants: _voice.participants,
                      energy: _voice.roomEnergy,
                      progress: _motion.value,
                      status: _voice.status,
                      roomName: widget.room.name,
                    ),
                  ),
                ),
                _BottomControls(
                  micState: _voice.micState,
                  busy: _voice.muteChangeInProgress,
                  onMute: _toggleMute,
                  onLeave: _leave,
                  onMicBlocked: _explainMicState,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.roomName,
    required this.status,
    required this.speaking,
    required this.listeners,
    required this.onBack,
    required this.onSpeakingTap,
    required this.onListenersTap,
  });

  final String roomName;
  final VoiceCallStatus status;
  final int speaking;
  final int listeners;
  final VoidCallback onBack;
  final VoidCallback onSpeakingTap;
  final VoidCallback onListenersTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 6),
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
                  roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  _statusText(status),
                  style: const TextStyle(
                    color: Color(0xFFB6A9C2),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _CounterPill(
            label: 'Speaking',
            value: speaking,
            onTap: onSpeakingTap,
          ),
          const SizedBox(width: 8),
          _CounterPill(
            label: 'Listeners',
            value: listeners,
            onTap: onListenersTap,
          ),
        ],
      ),
    );
  }

  static String _statusText(VoiceCallStatus status) => switch (status) {
    VoiceCallStatus.connected => 'COMMUNITY LIVE',
    VoiceCallStatus.connecting => 'CONNECTING…',
    VoiceCallStatus.reconnecting => 'RECONNECTING…',
    VoiceCallStatus.failed => 'CONNECTION FAILED',
    VoiceCallStatus.disconnected => 'OFFLINE',
  };
}

class _CounterPill extends StatelessWidget {
  const _CounterPill({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF171020).withValues(alpha: .86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF4B315F)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFAFA3BA),
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CosmicStage extends StatelessWidget {
  const _CosmicStage({
    required this.participants,
    required this.energy,
    required this.progress,
    required this.status,
    required this.roomName,
  });

  final List<VoiceParticipantViewData> participants;
  final double energy;
  final double progress;
  final VoiceCallStatus status;
  final String roomName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size.width / 2, size.height / 2);
        final coreSize = math.min(size.width, size.height) * .31;

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SpacePainter(progress: progress, energy: energy),
                ),
              ),
              Positioned(
                left: center.dx - coreSize / 2,
                top: center.dy - coreSize / 2,
                child: _CommunityHeart(
                  size: coreSize,
                  energy: energy,
                  connected: status == VoiceCallStatus.connected,
                  roomName: roomName,
                ),
              ),
              ..._buildOrbitingPeople(size, center, coreSize),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildOrbitingPeople(Size size, Offset center, double coreSize) {
    if (participants.isEmpty) return const [];
    final avatarSize = size.width < 600 ? 70.0 : 82.0;
    final availableRadius = math.min(size.width, size.height) / 2;
    final innerRadius = math.max(coreSize * .82, availableRadius * .58);
    final outerRadius = math.min(
      availableRadius - avatarSize * .65,
      innerRadius + avatarSize * .72,
    );

    return List.generate(participants.length, (index) {
      final participant = participants[index];
      final ring = index % 2;
      final radius = ring == 0 ? innerRadius : outerRadius;
      final slots = math.max(1, (participants.length / 2).ceil());
      final base = 2 * math.pi * (index ~/ 2) / slots;
      final direction = ring == 0 ? 1.0 : -.72;
      final angle = base + progress * math.pi * 2 * direction - math.pi / 2;
      final x = center.dx + math.cos(angle) * radius - avatarSize / 2;
      final y = center.dy + math.sin(angle) * radius - avatarSize / 2;

      return Positioned(
        left: x.clamp(4, size.width - avatarSize - 4).toDouble(),
        top: y.clamp(4, size.height - avatarSize - 34).toDouble(),
        child: _CosmicAvatar(participant: participant, size: avatarSize),
      );
    });
  }
}

class _CommunityHeart extends StatelessWidget {
  const _CommunityHeart({
    required this.size,
    required this.energy,
    required this.connected,
    required this.roomName,
  });

  final double size;
  final double energy;
  final bool connected;
  final String roomName;

  @override
  Widget build(BuildContext context) {
    final glow = .25 + energy * .55;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFFFF88FF),
            Color(0xFFB42BFF),
            Color(0xFF5512B8),
            Color(0xFF160429),
            Color(0xFF06030B),
          ],
          stops: [0, .18, .48, .78, 1],
        ),
        border: Border.all(
          color: Color.lerp(
            const Color(0xFF8D35D3),
            const Color(0xFFFFA1FF),
            energy,
          )!,
          width: 2.5 + energy * 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFBF2DFF).withValues(alpha: glow),
            blurRadius: 40 + energy * 55,
            spreadRadius: 4 + energy * 10,
          ),
          BoxShadow(
            color: const Color(0xFF5B25FF).withValues(alpha: .25),
            blurRadius: 90,
            spreadRadius: 18,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: size * .22,
            ),
            const SizedBox(height: 4),
            const Text(
              'HEART OF THE\nCOMMUNITY',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              connected
                  ? energy > .55
                        ? 'The room is alive'
                        : energy > .16
                        ? 'Voices are connecting'
                        : 'Listening for voices'
                  : 'Connecting…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE7CFF2),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CosmicAvatar extends StatelessWidget {
  const _CosmicAvatar({required this.participant, required this.size});

  final VoiceParticipantViewData participant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final level = participant.audioLevel.clamp(0.0, 1.0);
    final speaking = participant.isSpeaking;
    final aura = participant.isLocal
        ? const Color(0xFF5BE7FF)
        : speaking
        ? Color.lerp(const Color(0xFF8F42FF), const Color(0xFFFF64EF), level)!
        : const Color(0xFF7D39B5);
    final initial = participant.displayName.trim().isEmpty
        ? '?'
        : participant.displayName.trim()[0].toUpperCase();

    return SizedBox(
      width: size + 24,
      height: size + 38,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: size,
            height: size,
            transformAlignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              speaking ? 1.04 + level * .12 : 1,
              speaking ? 1.04 + level * .12 : 1,
              1,
            ),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  aura,
                  const Color(0xFF351048),
                  const Color(0xFF08040E),
                ],
              ),
              border: Border.all(
                color: aura,
                width: speaking ? 3 + level * 3 : 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: aura.withValues(alpha: speaking ? .75 : .25),
                  blurRadius: speaking ? 24 + 34 * level : 11,
                  spreadRadius: speaking ? 3 + 5 * level : 0,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * .36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (participant.isMuted)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFF160C1C),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_off_rounded,
                        size: 13,
                        color: Color(0xFFFF8BE9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            participant.isLocal
                ? '${participant.displayName} (you)'
                : participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: speaking ? Colors.white : const Color(0xFFD4C7DC),
              fontSize: 11,
              fontWeight: speaking ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  _SpacePainter({required this.progress, required this.energy});

  final double progress;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.45, -.7),
          radius: 1.25,
          colors: [Color(0xFF32124B), Color(0xFF11091B), Color(0xFF05030A)],
          stops: [0, .45, 1],
        ).createShader(rect),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * .47;
    for (var i = 0; i < 3; i++) {
      final radius = maxRadius * (.48 + i * .22);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 1.4 : 1
          ..color = const Color(0xFFB240FF).withValues(alpha: .18 - i * .035),
      );
    }

    final wave = maxRadius * (.34 + ((progress * 2) % 1) * .72);
    canvas.drawCircle(
      center,
      wave,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3 + energy * 2
        ..color = const Color(
          0xFFE15AFF,
        ).withValues(alpha: (.18 + energy * .25) * (1 - ((progress * 2) % 1))),
    );

    final starPaint = Paint();
    for (var i = 0; i < 100; i++) {
      final seed = i * 17.173;
      final x = (math.sin(seed) * .5 + .5) * size.width;
      final baseY = (math.cos(seed * 1.71) * .5 + .5) * size.height;
      final y = (baseY + progress * (8 + i % 7)) % size.height;
      final twinkle =
          .25 + .55 * (math.sin(progress * math.pi * 2 + seed).abs());
      starPaint.color = Colors.white.withValues(alpha: twinkle);
      canvas.drawCircle(Offset(x, y), i % 13 == 0 ? 1.35 : .65, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpacePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.energy != energy;
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.micState,
    required this.busy,
    required this.onMute,
    required this.onLeave,
    required this.onMicBlocked,
  });

  final MicState micState;
  final bool busy;
  final Future<void> Function() onMute;
  final Future<void> Function() onLeave;

  /// Tapping the mic while it genuinely can't publish explains WHY
  /// instead of silently doing nothing.
  final VoidCallback onMicBlocked;

  @override
  Widget build(BuildContext context) {
    // Every MicState is a visually distinct button — the mic must never
    // look "permanently pressed" or dead while it actually works.
    final (icon, label, style, tappable) = switch (micState) {
      MicState.on => (
        Icons.mic_rounded,
        'Mute',
        _MicStyle.live,
        true,
      ),
      MicState.muted => (
        Icons.mic_off_rounded,
        'Unmute',
        _MicStyle.muted,
        true,
      ),
      MicState.connecting => (
        Icons.mic_rounded,
        'Connecting…',
        _MicStyle.waiting,
        false,
      ),
      MicState.listenOnly => (
        Icons.headphones_rounded,
        'Listening',
        _MicStyle.info,
        true,
      ),
      MicState.unavailable => (
        Icons.mic_off_rounded,
        'Audio off',
        _MicStyle.error,
        true,
      ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF09050F).withValues(alpha: .96),
        border: const Border(top: BorderSide(color: Color(0xFF2B1937))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundControl(
            icon: icon,
            label: label,
            enabled: tappable && !busy,
            micStyle: style,
            showSpinner: micState == MicState.connecting,
            onTap: micState == MicState.on || micState == MicState.muted
                ? onMute
                : () async => onMicBlocked(),
          ),
          const SizedBox(width: 28),
          _RoundControl(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            enabled: true,
            micStyle: _MicStyle.danger,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

enum _MicStyle { live, muted, waiting, info, error, danger }

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.micStyle,
    this.showSpinner = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onTap;
  final _MicStyle micStyle;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    // Muted is a bright, obviously-tappable amber — never the old
    // near-background dark that read as a disabled button.
    final color = switch (micStyle) {
      _MicStyle.live => const Color(0xFFB62CFF),
      _MicStyle.muted => const Color(0xFFB3801A),
      _MicStyle.waiting => const Color(0xFF3A2C49),
      _MicStyle.info => const Color(0xFF2A5A8A),
      _MicStyle.error => const Color(0xFF7A2436),
      _MicStyle.danger => const Color(0xFFFF3C68),
    };
    return Opacity(
      // Even "waiting" stays near-opaque: a briefly-connecting mic must
      // not read as a permanently dead control.
      opacity: enabled ? 1 : .8,
      child: InkWell(
        onTap: () => onTap(),
        borderRadius: BorderRadius.circular(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: micStyle == _MicStyle.live
                    ? const [
                        BoxShadow(
                          color: Color(0x88B62CFF),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: showSpinner
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white70,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantsSheet extends StatefulWidget {
  const _ParticipantsSheet({
    required this.title,
    required this.participants,
    required this.hostId,
    required this.currentUserId,
    required this.canModerate,
    required this.onMute,
    required this.onRemove,
  });

  final String title;
  final List<RoomParticipant> participants;
  final String hostId;
  final String currentUserId;
  final bool canModerate;
  final Future<void> Function(RoomParticipant participant, bool muted) onMute;
  final Future<void> Function(RoomParticipant participant) onRemove;

  @override
  State<_ParticipantsSheet> createState() => _ParticipantsSheetState();
}

class _ParticipantsSheetState extends State<_ParticipantsSheet> {
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF120B18),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xFF503064))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF5D4C66),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.title} · ${widget.participants.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Flexible(
            child: widget.participants.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(36),
                    child: Text(
                      'Nobody is here yet.',
                      style: TextStyle(color: Color(0xFFB6A9C2)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
                    itemCount: widget.participants.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Color(0xFF2E2037), height: 1),
                    itemBuilder: (context, index) {
                      final participant = widget.participants[index];
                      final host = participant.userId == widget.hostId;
                      final self = participant.userId == widget.currentUserId;
                      final canAct = widget.canModerate && !host && !self;
                      final busy = _busyId == participant.userId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          radius: 23,
                          backgroundColor: const Color(0xFF7135A5),
                          child: Text(
                            participant.displayName.isEmpty
                                ? '?'
                                : participant.displayName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: Text(
                          self
                              ? '${participant.displayName} (you)'
                              : participant.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          host
                              ? 'Community owner'
                              : participant.isMuted
                              ? 'Muted'
                              : participant.isSpeaker
                              ? 'Speaking'
                              : 'Listening',
                          style: const TextStyle(color: Color(0xFFB6A9C2)),
                        ),
                        trailing: canAct
                            ? PopupMenuButton<String>(
                                enabled: !busy,
                                color: const Color(0xFF21142A),
                                icon: busy
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.more_vert_rounded,
                                        color: Colors.white,
                                      ),
                                onSelected: (action) async {
                                  setState(() => _busyId = participant.userId);
                                  try {
                                    if (action == 'mute') {
                                      await widget.onMute(
                                        participant,
                                        !participant.isMuted,
                                      );
                                    } else if (action == 'remove') {
                                      await widget.onRemove(participant);
                                      if (!context.mounted) return;
                                      Navigator.of(context).pop();
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busyId = null);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'mute',
                                    child: Text(
                                      participant.isMuted
                                          ? 'Allow microphone'
                                          : 'Mute participant',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text(
                                      'Remove from room',
                                      style: TextStyle(
                                        color: Color(0xFFFF6688),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Icon(
                                participant.isMuted
                                    ? Icons.mic_off_rounded
                                    : participant.isSpeaker
                                    ? Icons.graphic_eq_rounded
                                    : Icons.headphones_rounded,
                                color: const Color(0xFFC277FF),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

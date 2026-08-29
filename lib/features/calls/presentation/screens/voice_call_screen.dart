import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

import '../../data/services/voice_call_service.dart';
import '../../../rooms/data/services/room_service.dart';

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

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  final _voice = VoiceCallService.instance;
  final _rooms = RoomService();
  late final AnimationController _motion;

  final List<_FloatingReaction> _reactions = [];
  Timer? _reactionTimer;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _voice.addListener(_refresh);
    _connect();
  }

  @override
  void dispose() {
    _reactionTimer?.cancel();
    _motion.dispose();
    _voice.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _connect() async {
    if (_voice.roomId == widget.roomId && _voice.isConnected) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
      return;
    }

    final participantName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YO Voice user';

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
    try {
      await _rooms.leaveRoom(widget.roomId);
    } catch (_) {
      // The Firestore participant may already have been removed.
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _sendReaction(String emoji) {
    setState(() {
      _reactions.add(
        _FloatingReaction(
          emoji: emoji,
          createdAt: DateTime.now(),
          angle: math.Random().nextDouble() * math.pi * 2,
        ),
      );
    });

    _reactionTimer?.cancel();
    _reactionTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() {
        _reactions.removeWhere(
          (reaction) =>
              DateTime.now().difference(reaction.createdAt).inSeconds >= 4,
        );
      });
      if (_reactions.isEmpty) {
        _reactionTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final participants = _voice.participants;

    final content = Scaffold(
      backgroundColor: const Color(0xFF05030A),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              roomName: widget.roomName,
              status: _voice.status,
              participantCount: participants.length,
              onBack: () => Navigator.of(context).pop(),
              onReaction: _sendReaction,
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (_voice.status == VoiceCallStatus.failed) {
                        return _ConnectionError(
                          message: _voice.errorMessage,
                          onRetry: _connect,
                        );
                      }

                      return _OrbitalStage(
                        participants: participants,
                        energy: _voice.roomEnergy,
                        animationValue: _motion.value,
                        reactions: _reactions,
                        status: _voice.status,
                      );
                    },
                  );
                },
              ),
            ),
            _VoiceControls(
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
    return YoImmersiveDarkSurface(child: content);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.roomName,
    required this.status,
    required this.participantCount,
    required this.onBack,
    required this.onReaction,
  });

  final String roomName;
  final VoiceCallStatus status;
  final int participantCount;
  final VoidCallback onBack;
  final ValueChanged<String> onReaction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
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
                  _statusLabel(status),
                  style: const TextStyle(
                    color: Color(0xFFAAA0B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF171020),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF372742)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
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
          PopupMenuButton<String>(
            tooltip: 'Send reaction',
            color: const Color(0xFF171020),
            icon: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFC864FF),
            ),
            onSelected: onReaction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: '😂', child: Text('😂  Laugh')),
              PopupMenuItem(value: '🔥', child: Text('🔥  Fire')),
              PopupMenuItem(value: '❤️', child: Text('❤️  Love')),
              PopupMenuItem(value: '👏', child: Text('👏  Applause')),
              PopupMenuItem(value: '😡', child: Text('😡  Angry eyes')),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(VoiceCallStatus status) {
    return switch (status) {
      VoiceCallStatus.disconnected => 'Disconnected',
      VoiceCallStatus.connecting => 'Connecting to voice…',
      VoiceCallStatus.connected => 'Live voice room',
      VoiceCallStatus.reconnecting => 'Reconnecting…',
      VoiceCallStatus.failed => 'Connection failed',
    };
  }
}

class _OrbitalStage extends StatelessWidget {
  const _OrbitalStage({
    required this.participants,
    required this.energy,
    required this.animationValue,
    required this.reactions,
    required this.status,
  });

  final List<VoiceParticipantViewData> participants;
  final double energy;
  final double animationValue;
  final List<_FloatingReaction> reactions;
  final VoiceCallStatus status;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size.width / 2, size.height / 2);
        final compact = size.width < 600;
        final coreSize =
            math.min(size.width, size.height) * (compact ? .31 : .28);

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _OrbitalBackgroundPainter(
                    progress: animationValue,
                    energy: energy,
                  ),
                ),
              ),
              Positioned(
                left: center.dx - coreSize / 2,
                top: center.dy - coreSize / 2,
                child: _VoiceEnergyCore(
                  size: coreSize,
                  energy: energy,
                  status: status,
                ),
              ),
              ..._buildParticipants(size, center, coreSize),
              ..._buildReactions(size, center, coreSize),
              if (participants.isEmpty &&
                  status != VoiceCallStatus.connecting &&
                  status != VoiceCallStatus.reconnecting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 240),
                    child: Text(
                      'Waiting for voices…',
                      style: TextStyle(
                        color: Color(0xFFACA1B7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildParticipants(Size size, Offset center, double coreSize) {
    final count = participants.length;
    if (count == 0) return const [];

    final compact = size.width < 600;
    final avatarSize = compact ? 72.0 : 84.0;
    final availableRadius = math.min(size.width, size.height) / 2;
    final baseRadius = math.max(coreSize * .75, availableRadius * .58);
    final maxRadius = math.max(baseRadius, availableRadius - avatarSize * .7);

    return List.generate(count, (index) {
      final participant = participants[index];
      final ring = index % 2;
      final radius = math.min(maxRadius, baseRadius + ring * avatarSize * .55);
      final baseAngle = math.pi * 2 * index / math.max(count, 1);
      final orbitSpeed = ring == 0 ? 1.0 : -0.72;
      final angle =
          baseAngle + animationValue * math.pi * 2 * orbitSpeed - math.pi / 2;

      final x = center.dx + math.cos(angle) * radius - avatarSize / 2;
      final y = center.dy + math.sin(angle) * radius - avatarSize / 2;

      return Positioned(
        left: x.clamp(4, size.width - avatarSize - 4).toDouble(),
        top: y.clamp(4, size.height - avatarSize - 38).toDouble(),
        child: _OrbitingParticipant(participant: participant, size: avatarSize),
      );
    });
  }

  List<Widget> _buildReactions(Size size, Offset center, double coreSize) {
    return reactions
        .map((reaction) {
          final ageMs = DateTime.now()
              .difference(reaction.createdAt)
              .inMilliseconds;
          final progress = (ageMs / 4000).clamp(0.0, 1.0);
          final radius = coreSize * .7 + progress * coreSize * .9;
          final angle = reaction.angle + progress * .9;
          final x = center.dx + math.cos(angle) * radius - 20;
          final y = center.dy + math.sin(angle) * radius - 20 - progress * 45;

          return Positioned(
            left: x,
            top: y,
            child: Opacity(
              opacity: 1 - progress,
              child: Transform.scale(
                scale: .8 + (1 - progress) * .35,
                child: Text(
                  reaction.emoji,
                  style: const TextStyle(fontSize: 34),
                ),
              ),
            ),
          );
        })
        .toList(growable: false);
  }
}

class _VoiceEnergyCore extends StatelessWidget {
  const _VoiceEnergyCore({
    required this.size,
    required this.energy,
    required this.status,
  });

  final double size;
  final double energy;
  final VoiceCallStatus status;

  @override
  Widget build(BuildContext context) {
    final connected = status == VoiceCallStatus.connected;
    final percent = connected ? (energy * 100).round().clamp(4, 100) : 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFFB72BFF),
            Color(0xFF6514C8),
            Color(0xFF26084E),
            Color(0xFF0A0612),
          ],
          stops: [0, .4, .78, 1],
        ),
        border: Border.all(
          color: Color.lerp(
            const Color(0xFF6E25A2),
            const Color(0xFFF164FF),
            energy,
          )!,
          width: 2 + energy * 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFFB024FF,
            ).withValues(alpha: .22 + energy * .35),
            blurRadius: 32 + energy * 44,
            spreadRadius: 3 + energy * 7,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'VOICE\nENERGY',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: .95,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              connected ? '$percent%' : '…',
              style: const TextStyle(
                color: Color(0xFFEF58FF),
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              connected
                  ? energy > .65
                        ? 'The room is on fire 🔥'
                        : energy > .25
                        ? 'The room is vibing ✨'
                        : 'Listening for voices'
                  : 'Connecting…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD1C5DA),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitingParticipant extends StatelessWidget {
  const _OrbitingParticipant({required this.participant, required this.size});

  final VoiceParticipantViewData participant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final level = participant.audioLevel.clamp(0.0, 1.0);
    final speaking = participant.isSpeaking;
    final shouting = participant.isShouting;
    final initial = participant.displayName.trim().isEmpty
        ? '?'
        : participant.displayName.trim()[0].toUpperCase();

    final aura = _auraFor(level, speaking, participant.isLocal);
    final scale = speaking ? 1.05 + level * .16 : 1.0;

    return SizedBox(
      width: size + 26,
      height: size + 58,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -13,
            child: CustomPaint(
              size: Size.square(size + 26),
              painter: _VoiceAuraPainter(
                color: aura,
                audioLevel: level,
                speaking: speaking,
                shouting: shouting,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
            width: size,
            height: size,
            transformAlignment: Alignment.center,
            transform: Matrix4.diagonal3Values(scale, scale, 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  aura.withValues(alpha: .98),
                  Color.lerp(const Color(0xFF28113B), aura, .18)!,
                  const Color(0xFF09050F),
                ],
                stops: const [0, .58, 1],
              ),
              border: Border.all(
                color: aura,
                width: speaking ? 3.5 + level * 2.5 : 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: aura.withValues(
                    alpha: speaking ? .48 + level * .42 : .2,
                  ),
                  blurRadius: speaking ? 24 + level * 42 : 10,
                  spreadRadius: speaking ? 3 + level * 7 : 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * .37,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (shouting)
            Positioned(
              top: -28,
              child: Transform.rotate(
                angle: math.sin(level * 20) * .04,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xE8A9001A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF3652)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xCCFF173F),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Text(
                    'ಠ益ಠ',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          if (speaking && level >= .32 && !shouting)
            Positioned(
              right: -5,
              top: 4,
              child: Text(
                level >= .48 ? '⚡' : '✨',
                style: TextStyle(fontSize: 20 + level * 10),
              ),
            ),
          Positioned(
            top: size - 2,
            child: Container(
              constraints: BoxConstraints(maxWidth: size + 42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xEE0B0711),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: aura.withValues(alpha: .82)),
                boxShadow: [
                  BoxShadow(color: aura.withValues(alpha: .2), blurRadius: 12),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      participant.isLocal ? 'You' : participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    participant.isMuted
                        ? Icons.mic_off_rounded
                        : speaking
                        ? Icons.graphic_eq_rounded
                        : Icons.mic_rounded,
                    size: 14,
                    color: participant.isMuted
                        ? const Color(0xFF8E8398)
                        : speaking
                        ? aura
                        : const Color(0xFFC5B8CF),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _auraFor(double level, bool speaking, bool isLocal) {
    if (!speaking) {
      return isLocal ? const Color(0xFF7A4DFF) : const Color(0xFF2E9DFF);
    }
    if (level >= .58) return const Color(0xFFFF203E);
    if (level >= .42) return const Color(0xFFFF8A1E);
    if (level >= .24) return const Color(0xFFFFD84D);
    if (level >= .10) return const Color(0xFFC545FF);
    return const Color(0xFF38D9FF);
  }
}

class _VoiceAuraPainter extends CustomPainter {
  const _VoiceAuraPainter({
    required this.color,
    required this.audioLevel,
    required this.speaking,
    required this.shouting,
  });

  final Color color;
  final double audioLevel;
  final bool speaking;
  final bool shouting;

  @override
  void paint(Canvas canvas, Size size) {
    if (!speaking) return;
    final center = size.center(Offset.zero);
    final base = size.shortestSide * .34;
    final waveCount = shouting ? 4 : 3;

    for (var i = 0; i < waveCount; i++) {
      final radius = base + 7 + i * (7 + audioLevel * 8);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shouting ? 2.4 : 1.5
        ..color = color.withValues(alpha: (.42 - i * .08).clamp(.10, .42));
      canvas.drawCircle(center, radius, paint);
    }

    if (shouting) {
      final boltPaint = Paint()
        ..color = const Color(0xFFFF3150)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final angle = math.pi * 2 * i / 8;
        final inner = Offset(
          center.dx + math.cos(angle) * (base + 12),
          center.dy + math.sin(angle) * (base + 12),
        );
        final outer = Offset(
          center.dx + math.cos(angle) * (base + 23 + audioLevel * 8),
          center.dy + math.sin(angle) * (base + 23 + audioLevel * 8),
        );
        canvas.drawLine(inner, outer, boltPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceAuraPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.audioLevel != audioLevel ||
        oldDelegate.speaking != speaking ||
        oldDelegate.shouting != shouting;
  }
}

class _VoiceControls extends StatelessWidget {
  const _VoiceControls({
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
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xE8120B1C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF3B284A)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundControl(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: muteBusy
                ? 'Changing…'
                : isMuted
                ? 'Unmute'
                : 'Mute',
            emphasized: !isMuted,
            onTap: connected && !muteBusy ? () => onMute() : null,
          ),
          _RoundControl(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            danger: true,
            onTap: () => onLeave(),
          ),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasized;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFFF3D68)
        : emphasized
        ? const Color(0xFF9F27FF)
        : const Color(0xFF23172E);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: emphasized ? 64 : 55,
              height: emphasized ? 64 : 55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onTap == null ? const Color(0xFF241D29) : background,
                boxShadow: emphasized
                    ? const [
                        BoxShadow(color: Color(0x779F27FF), blurRadius: 20),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: emphasized ? 31 : 25,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: danger
                    ? const Color(0xFFFF7593)
                    : const Color(0xFFBFB4C9),
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
              'Could not connect to voice',
              textAlign: TextAlign.center,
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
              style: const TextStyle(color: Color(0xFFAAA0B8)),
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

class _OrbitalBackgroundPainter extends CustomPainter {
  const _OrbitalBackgroundPainter({
    required this.progress,
    required this.energy,
  });

  final double progress;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * .48;

    final background = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF1C0732), Color(0xFF08040E), Color(0xFF030205)],
        stops: [0, .58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    for (var i = 0; i < 4; i++) {
      final radius = maxRadius * (.42 + i * .17);
      final orbitPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 1.4 : .8
        ..color = const Color(
          0xFFB42FFF,
        ).withValues(alpha: .22 - i * .025 + energy * .08);
      canvas.drawCircle(center, radius, orbitPaint);
    }

    final random = math.Random(21);
    for (var i = 0; i < 80; i++) {
      final angle = random.nextDouble() * math.pi * 2 + progress * .08;
      final radius = random.nextDouble() * maxRadius * 1.2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final star = Paint()
        ..color =
            (i % 4 == 0 ? const Color(0xFF4FA8FF) : const Color(0xFFC44DFF))
                .withValues(alpha: .18 + random.nextDouble() * .5);
      canvas.drawCircle(point, .5 + random.nextDouble() * 1.4, star);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.energy != energy;
  }
}

class _FloatingReaction {
  const _FloatingReaction({
    required this.emoji,
    required this.createdAt,
    required this.angle,
  });

  final String emoji;
  final DateTime createdAt;
  final double angle;
}

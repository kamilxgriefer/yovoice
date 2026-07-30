import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

class HeroLiveRoom extends StatefulWidget {
  const HeroLiveRoom({required this.room, required this.onJoin, super.key});

  final VoiceRoom room;
  final VoidCallback onJoin;

  @override
  State<HeroLiveRoom> createState() => _HeroLiveRoomState();
}

class _HeroLiveRoomState extends State<HeroLiveRoom>
    with SingleTickerProviderStateMixin {
  static const Color _purple = Color(0xFF9D20FF);
  static const Color _pink = Color(0xFFFF3F8E);
  static const Color _red = Color(0xFFFF416C);
  static const Color _muted = Color(0xFFC9BDD5);

  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color get _accent {
    final category = widget.room.category.trim().toLowerCase();

    if (widget.room.isBroadcast) {
      return _pink;
    }

    if (category.contains('music')) {
      return const Color(0xFFFFA63D);
    }

    if (category.contains('gaming')) {
      return const Color(0xFF4D8DFF);
    }

    if (category.contains('business')) {
      return const Color(0xFF3FD19B);
    }

    if (category.contains('study')) {
      return const Color(0xFF6E7CFF);
    }

    if (category.contains('tech')) {
      return const Color(0xFF37D6E8);
    }

    return _purple;
  }

  String get _roomTypeLabel {
    return widget.room.isBroadcast
        ? 'FEATURED BROADCAST'
        : 'FEATURED COMMUNITY';
  }

  String get _peopleLabel {
    final count = widget.room.participantCount;

    return widget.room.isBroadcast ? '$count listening' : '$count inside';
  }

  double? get _occupancy {
    final maximum = widget.room.maxParticipants;

    if (maximum == null || maximum <= 0) {
      return null;
    }

    return (widget.room.participantCount / maximum).clamp(0.0, 1.0);
  }

  String get _occupancyLabel {
    final occupancy = _occupancy;

    if (occupancy == null) {
      return 'Open room';
    }

    if (occupancy >= 0.9) {
      return 'Almost full';
    }

    if (occupancy >= 0.65) {
      return 'Filling fast';
    }

    if (occupancy >= 0.3) {
      return 'Growing now';
    }

    return 'Join early';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final accent = _accent;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final animationValue = _animationController.value;
        final pulse = 0.5 + math.sin(animationValue * math.pi * 2) * 0.5;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.11 + pulse * 0.1),
                blurRadius: 30 + pulse * 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              onTap: widget.onJoin,
              borderRadius: BorderRadius.circular(30),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(const Color(0xFF39164D), accent, 0.17)!,
                      const Color(0xFF1B1028),
                      const Color(0xFF100A19),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.7)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -55,
                      top: -70,
                      child: _GlowOrb(
                        size: 190,
                        color: accent.withValues(alpha: 0.17),
                      ),
                    ),
                    Positioned(
                      left: -70,
                      bottom: -100,
                      child: _GlowOrb(
                        size: 210,
                        color: _pink.withValues(alpha: 0.1),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _HeroPatternPainter(
                            accent: accent,
                            animationValue: animationValue,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _LiveBadge(pulse: pulse),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _roomTypeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.15,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xFFFFC05A),
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 21),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RoomArtwork(
                                room: room,
                                accent: accent,
                                pulse: pulse,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      room.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        height: 1.08,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.55,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      room.description.trim().isEmpty
                                          ? 'Hosted by ${room.hostName}'
                                          : room.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                        height: 1.42,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HeroInfoChip(
                                icon: room.isBroadcast
                                    ? Icons.headphones_rounded
                                    : Icons.people_alt_rounded,
                                label: _peopleLabel,
                              ),
                              _HeroInfoChip(
                                icon: Icons.language_rounded,
                                label: room.language,
                              ),
                              _HeroInfoChip(
                                icon: room.isBroadcast
                                    ? Icons.podcasts_rounded
                                    : Icons.groups_rounded,
                                label: room.category,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _HostAndSpeakersPreview(room: room, accent: accent),
                          if (_occupancy != null) ...[
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: _occupancy,
                                      minHeight: 5,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.09,
                                      ),
                                      color: _occupancy! >= 0.9 ? _red : accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Text(
                                  '${room.participantCount}/${room.maxParticipants}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 11),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _occupancyLabel,
                                  style: TextStyle(
                                    color:
                                        _occupancy != null && _occupancy! >= 0.9
                                        ? const Color(0xFFFF829D)
                                        : _muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: widget.onJoin,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                icon: Icon(
                                  room.isBroadcast
                                      ? Icons.headphones_rounded
                                      : Icons.login_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'JOIN ROOM',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF4A172B),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFFF416C).withValues(alpha: 0.7 + pulse * 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 0.88 + pulse * 0.22,
            child: const Icon(Icons.circle, color: Color(0xFFFF416C), size: 9),
          ),
          const SizedBox(width: 7),
          const Text(
            'LIVE NOW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomArtwork extends StatelessWidget {
  const _RoomArtwork({
    required this.room,
    required this.accent,
    required this.pulse,
  });

  final VoiceRoom room;
  final Color accent;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final imageUrl = room.imageUrl?.trim();

    return Container(
      width: 82,
      height: 82,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.42),
            accent.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.82)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.17 + pulse * 0.11),
            blurRadius: 19,
          ),
        ],
      ),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return _RoomArtworkFallback(room: room);
              },
            )
          : _RoomArtworkFallback(room: room),
    );
  }
}

class _RoomArtworkFallback extends StatelessWidget {
  const _RoomArtworkFallback({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Icon(
      room.isBroadcast ? Icons.podcasts_rounded : Icons.graphic_eq_rounded,
      color: Colors.white,
      size: 39,
    );
  }
}

class _HeroInfoChip extends StatelessWidget {
  const _HeroInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _HeroLiveRoomState._muted, size: 14),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 135),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostAndSpeakersPreview extends StatelessWidget {
  const _HostAndSpeakersPreview({required this.room, required this.accent});

  final VoiceRoom room;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final visiblePeople = math.min(math.max(room.participantCount, 1), 4);

    return Row(
      children: [
        SizedBox(
          width: 34 + (visiblePeople - 1) * 21,
          height: 36,
          child: Stack(
            children: List.generate(visiblePeople, (index) {
              return Positioned(
                left: index * 21,
                child: index == 0
                    ? _HostAvatar(
                        photoUrl: room.hostPhotoUrl,
                        hostName: room.hostName,
                        accent: accent,
                      )
                    : _SpeakerPlaceholder(index: index, accent: accent),
              );
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.hostName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                room.isBroadcast
                    ? 'Host and active listeners'
                    : 'Host and active speakers',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _HeroLiveRoomState._muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (room.participantCount > visiblePeople)
          Text(
            '+${room.participantCount - visiblePeople}',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class _HostAvatar extends StatelessWidget {
  const _HostAvatar({
    required this.photoUrl,
    required this.hostName,
    required this.accent,
  });

  final String? photoUrl;
  final String hostName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = photoUrl?.trim();
    final initial = hostName.trim().isEmpty
        ? 'Y'
        : hostName.trim()[0].toUpperCase();

    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.28),
        border: Border.all(color: const Color(0xFF160D20), width: 2),
      ),
      child: normalizedUrl != null && normalizedUrl.isNotEmpty
          ? Image.network(
              normalizedUrl,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                );
              },
            )
          : Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}

class _SpeakerPlaceholder extends StatelessWidget {
  const _SpeakerPlaceholder({required this.index, required this.accent});

  final int index;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(accent, const Color(0xFF22152E), index * 0.17),
        border: Border.all(color: const Color(0xFF160D20), width: 2),
      ),
      child: Icon(
        index.isEven ? Icons.graphic_eq_rounded : Icons.person_rounded,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _HeroPatternPainter extends CustomPainter {
  const _HeroPatternPainter({
    required this.accent,
    required this.animationValue,
  });

  final Color accent;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width * 0.88, size.height * 0.24);

    for (var index = 0; index < 3; index++) {
      final progress = (animationValue + index / 3) % 1;
      final radius = 18 + progress * 85;

      linePaint.color = accent.withValues(alpha: (1 - progress) * 0.1);

      canvas.drawCircle(center, radius, linePaint);
    }

    const dotCount = 18;

    for (var index = 0; index < dotCount; index++) {
      final angle = index / dotCount * math.pi * 2;
      final radius = 65 + (index % 4) * 18;

      final offset = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

      canvas.drawCircle(offset, index.isEven ? 1.3 : 0.8, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeroPatternPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.accent != accent;
  }
}

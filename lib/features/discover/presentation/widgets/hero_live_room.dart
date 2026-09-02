import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/discover/presentation/discover_category_identity.dart';
import 'package:yovoice/features/discover/presentation/discover_localized_copy.dart';
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
  static const Color _red = Color(0xFFFF416C);
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

  DiscoverCategoryIdentity get _identity =>
      DiscoverCategoryIdentity.forCategory(
        widget.room.category,
        isBroadcast: widget.room.isBroadcast,
      );

  String _roomTypeLabel(AppLocalizations copy) {
    return widget.room.isBroadcast
        ? copy.text('FEATURED BROADCAST', 'WYRÓŻNIONY PODCAST')
        : copy.text('FEATURED COMMUNITY', 'WYRÓŻNIONY POKÓJ SPOŁECZNOŚCIOWY');
  }

  String _peopleLabel(AppLocalizations copy) => localizedDiscoverAudience(
    copy,
    count: widget.room.participantCount,
    isBroadcast: widget.room.isBroadcast,
  );

  double? get _occupancy {
    final maximum = widget.room.maxParticipants;

    if (maximum == null || maximum <= 0) {
      return null;
    }

    return (widget.room.participantCount / maximum).clamp(0.0, 1.0);
  }

  String _occupancyLabel(AppLocalizations copy) {
    final occupancy = _occupancy;

    if (occupancy == null) {
      return copy.text('Open room', 'Pokój otwarty');
    }

    if (occupancy >= 0.9) {
      return copy.text('Almost full', 'Prawie pełny');
    }

    if (occupancy >= 0.65) {
      return copy.text('Filling fast', 'Szybko się zapełnia');
    }

    if (occupancy >= 0.3) {
      return copy.text('Growing now', 'Przybywa uczestników');
    }

    return copy.text('Join early', 'Dołącz jako jedna z pierwszych osób');
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final room = widget.room;
    final palette = context.appPalette;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final identity = _identity;
    final accent = identity.seed;
    final identityVisuals = identity.resolve(brightness);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final occupancyStatus = Text(
      _occupancyLabel(copy),
      style: TextStyle(
        color: _occupancy != null && _occupancy! >= 0.9
            ? Theme.of(context).colorScheme.error
            : palette.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
    final joinButton = FilledButton.icon(
      onPressed: widget.onJoin,
      style: FilledButton.styleFrom(
        backgroundColor: identityVisuals.action,
        foregroundColor: identityVisuals.onAction,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      icon: Icon(
        room.isBroadcast ? Icons.headphones_rounded : Icons.login_rounded,
        size: 18,
      ),
      label: Text(
        copy.text('JOIN ROOM', 'DOŁĄCZ DO POKOJU'),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final animationValue = _animationController.value;
        final pulse = 0.5 + math.sin(animationValue * math.pi * 2) * 0.5;

        return Container(
          key: ValueKey('discover-hero-${room.id}'),
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
                    colors: dark
                        ? [
                            Color.lerp(const Color(0xFF39164D), accent, 0.17)!,
                            const Color(0xFF1B1028),
                            const Color(0xFF100A19),
                          ]
                        : [
                            Color.lerp(palette.surfaceRaised, accent, .08)!,
                            palette.surface,
                            palette.surfaceRaised,
                          ],
                    stops: const [0, 0.5, 1],
                  ),
                  border: Border.all(color: identityVisuals.border),
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
                        color: DiscoverCategoryIdentity.broadcast.seed
                            .withValues(alpha: 0.1),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _HeroPatternPainter(
                            accent: accent,
                            dotColor: palette.textPrimary,
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
                                  _roomTypeLabel(copy),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: identityVisuals.foreground,
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
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 24,
                                        height: 1.08,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.55,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      room.description.trim().isEmpty
                                          ? localizedHostedBy(
                                              copy,
                                              room.hostName,
                                            )
                                          : room.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textSecondary,
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
                                label: _peopleLabel(copy),
                              ),
                              _HeroInfoChip(
                                icon: Icons.language_rounded,
                                label: room.language,
                              ),
                              _HeroInfoChip(
                                icon: room.isBroadcast
                                    ? Icons.podcasts_rounded
                                    : Icons.groups_rounded,
                                label: localizedDiscoverCategory(
                                  copy,
                                  room.category,
                                ),
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
                                      backgroundColor: palette.surfaceSunken,
                                      color: _occupancy! >= 0.9
                                          ? _red
                                          : identityVisuals.foreground,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Text(
                                  '${room.participantCount}/${room.maxParticipants}',
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 11),
                          if (largeText)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                occupancyStatus,
                                const SizedBox(height: 11),
                                joinButton,
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(child: occupancyStatus),
                                joinButton,
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
    final copy = AppLocalizations.of(context);
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
          Text(
            copy.text('LIVE NOW', 'TERAZ NA ŻYWO'),
            style: const TextStyle(
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
    final palette = context.appPalette;
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );

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
            visuals.surface,
            Color.lerp(visuals.surface, palette.surface, .55)!,
          ],
        ),
        border: Border.all(color: visuals.border),
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
                return _RoomArtworkFallback(room: room, accent: accent);
              },
            )
          : _RoomArtworkFallback(room: room, accent: accent),
    );
  }
}

class _RoomArtworkFallback extends StatelessWidget {
  const _RoomArtworkFallback({required this.room, required this.accent});

  final VoiceRoom room;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
    return Icon(
      room.isBroadcast ? Icons.podcasts_rounded : Icons.graphic_eq_rounded,
      color: visuals.foreground,
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
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.textSecondary, size: 14),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 135),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
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
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                room.isBroadcast
                    ? copy.text(
                        'Host and active listeners',
                        'Prowadzący i aktywni słuchacze',
                      )
                    : copy.text(
                        'Host and active speakers',
                        'Prowadzący i aktywni rozmówcy',
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
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
              color: visuals.foreground,
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
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );

    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: visuals.surface,
        border: Border.all(color: visuals.border, width: 2),
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
                  style: TextStyle(
                    color: visuals.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                );
              },
            )
          : Text(
              initial,
              style: TextStyle(
                color: visuals.onSurface,
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
    final visuals = DiscoverCategoryVisuals.fromSeed(
      accent,
      Theme.of(context).brightness,
    );
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: visuals.surface,
        border: Border.all(color: visuals.border, width: 2),
      ),
      child: Icon(
        index.isEven ? Icons.graphic_eq_rounded : Icons.person_rounded,
        color: visuals.onSurface,
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
    required this.dotColor,
    required this.animationValue,
  });

  final Color accent;
  final Color dotColor;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = dotColor.withValues(alpha: 0.1)
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
        oldDelegate.accent != accent ||
        oldDelegate.dotColor != dotColor;
  }
}

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_card.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/voice/voice_core.dart';

/// The Home mockup's LIVE NOW module: one featured live room presented
/// as a place — Voice Core centerpiece, the real people around it, live
/// counts, and a single Join CTA. Fully data-driven: featured room, its
/// participants, and every count come from Firestore; when no room is
/// live it renders the empty state, never invented people.
class LiveNowHero extends StatelessWidget {
  const LiveNowHero({required this.room, required this.onJoin, super.key});

  /// Null renders the polished empty state.
  final VoiceRoom? room;
  final ValueChanged<VoiceRoom> onJoin;

  static final RoomService _rooms = RoomService();

  @override
  Widget build(BuildContext context) {
    final featured = room;
    final palette = context.appPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.surfaceRaised, palette.surface],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: .12),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: featured == null
            ? _EmptyState(onStart: () {})
            : _FeaturedRoom(room: featured, service: _rooms, onJoin: onJoin),
      ),
    );
  }
}

class _FeaturedRoom extends StatelessWidget {
  const _FeaturedRoom({
    required this.room,
    required this.service,
    required this.onJoin,
  });

  final VoiceRoom room;
  final RoomService service;
  final ValueChanged<VoiceRoom> onJoin;

  @override
  Widget build(BuildContext context) {
    final identity = RoomCardIdentity.of(room);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;

    return StreamBuilder<List<RoomParticipant>>(
      stream: service.watchParticipants(room.id),
      builder: (context, snapshot) {
        final participants = snapshot.data ?? const <RoomParticipant>[];
        final speaking = participants.where((p) => p.isSpeaker).length;
        final around = participants.take(5).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'LIVE NOW',
                  style: TextStyle(
                    color: palette.interactiveForeground,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.live,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.live,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: AppColors.onLive,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              identity == RoomCardIdentity.podcast
                  ? 'Podcast Room'
                  : identity == RoomCardIdentity.club
                  ? 'Club Room'
                  : 'Community Room',
              style: TextStyle(
                color: identity.accent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
              ),
            ),
            if (room.category.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  room.category,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            // Voice Core with the room's REAL people orbiting it — up to
            // five, count-capped like the stage (never one avatar per
            // listener).
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const VoiceCore(size: 96),
                  for (var i = 0; i < around.length; i++)
                    Align(
                      alignment: _slotAlignment(i),
                      child: _OrbitingParticipant(participant: around[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.people_alt_rounded,
                  size: 15,
                  color: identity.accent,
                ),
                const SizedBox(width: 5),
                Text(
                  '${participants.length} people',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 15,
                  color: palette.interactiveForeground,
                ),
                const SizedBox(width: 5),
                Text(
                  '$speaking speaking',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => onJoin(room),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Join room',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Five stable orbit slots around the core (mockup composition).
  static Alignment _slotAlignment(int index) => switch (index) {
    0 => const Alignment(-.05, -1),
    1 => const Alignment(-.92, -.45),
    2 => const Alignment(.92, -.35),
    3 => const Alignment(-.75, .85),
    _ => const Alignment(.8, .9),
  };
}

class _OrbitingParticipant extends StatelessWidget {
  const _OrbitingParticipant({required this.participant});

  final RoomParticipant participant;

  @override
  Widget build(BuildContext context) {
    final speaking = participant.isSpeaker;
    final palette = context.appPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: speaking
                  ? palette.interactiveForeground
                  : palette.borderStrong,
              width: speaking ? 2 : 1.2,
            ),
          ),
          child: UserAvatar(
            radius: 21,
            photoUrl: participant.photoUrl,
            displayName: participant.displayName,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          participant.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      children: [
        const SizedBox(height: 6),
        Text(
          'LIVE NOW',
          style: TextStyle(
            color: palette.interactiveForeground,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        const VoiceCore(size: 84),
        const SizedBox(height: 12),
        Text(
          "It's quiet right now",
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Start a room and your people will hear about it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

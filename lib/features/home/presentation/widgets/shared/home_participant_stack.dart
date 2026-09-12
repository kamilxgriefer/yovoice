import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// A small overlapping run of REAL participants, with an honest overflow
/// disc.
///
/// One image per person: the caller hands in a roster that already contains
/// each `userId` once, so nobody appears twice in one stack. When the room
/// holds more people than [maxAvatars], the extra discs are replaced by a
/// single "+N" — a count of people the stack did not draw, never a count the
/// screen invented.
///
/// Decorative by contract: the stack carries no semantics of its own so the
/// row or card around it can describe the whole thing in one sentence.
class HomeParticipantStack extends StatelessWidget {
  const HomeParticipantStack({
    required this.participants,
    this.radius = 16,
    this.maxAvatars = 3,
    this.overlap = 10,
    super.key,
  });

  final List<RoomParticipant> participants;
  final double radius;
  final int maxAvatars;

  /// How much each disc slides over its left neighbour.
  final double overlap;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();
    final palette = context.appPalette;
    final shown = participants.take(maxAvatars).toList(growable: false);
    final overflow = participants.length - shown.length;
    final diameter = radius * 2;
    final step = diameter - overlap;
    final discCount = shown.length + (overflow > 0 ? 1 : 0);
    final width = diameter + (discCount - 1) * step;

    Widget ringed(Widget child) => Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.background,
        border: Border.all(color: palette.background, width: 2),
      ),
      child: ClipOval(child: child),
    );

    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: diameter,
        child: Stack(
          children: [
            for (var index = 0; index < shown.length; index++)
              PositionedDirectional(
                start: index * step,
                child: ringed(
                  UserAvatar(
                    radius: radius - 2,
                    userId: shown[index].userId,
                    photoUrl: shown[index].photoUrl,
                    displayName: shown[index].displayName,
                  ),
                ),
              ),
            if (overflow > 0)
              PositionedDirectional(
                start: shown.length * step,
                child: ringed(
                  ColoredBox(
                    color: palette.surfaceRaised,
                    child: Center(
                      child: Text(
                        '+$overflow',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

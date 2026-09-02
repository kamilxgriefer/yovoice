import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';

class BroadcastSpeakerTile extends StatelessWidget {
  const BroadcastSpeakerTile({
    super.key,
    required this.participant,
    required this.isHostView,
    required this.onManage,
  });

  final RoomParticipant participant;
  final bool isHostView;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final initial = participant.displayName.trim().isEmpty
        ? 'Y'
        : participant.displayName.trim()[0].toUpperCase();

    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BroadcastRoomColors.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF64212D)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF812033),
            backgroundImage: participant.photoUrl == null
                ? null
                : NetworkImage(participant.photoUrl!),
            child: participant.photoUrl == null
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 9),
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
          // Icon dots on the tile: full labels live in the tooltip and
          // in the participants sheet — never hidden, never overflowing
          // a 150px card.
          UserIdentityBadges(
            uid: participant.userId,
            variant: IdentityBadgeVariant.icon,
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: participant.isMuted
                    ? BroadcastRoomColors.muted
                    : BroadcastRoomColors.accentSoft,
                size: 17,
              ),
              if (isHostView) ...[
                const SizedBox(width: 5),
                InkWell(
                  onTap: onManage,
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class BroadcastEmptyStage extends StatelessWidget {
  const BroadcastEmptyStage({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BroadcastRoomColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BroadcastRoomColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.chair_alt_rounded,
            color: BroadcastRoomColors.accentSoft,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              copy.text(
                'No guest speakers yet. Raised hands will appear in the participant panel.',
                'Nie ma jeszcze zaproszonych mówców. Zgłoszenia pojawią się w panelu uczestników.',
              ),
              style: const TextStyle(
                color: BroadcastRoomColors.muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BroadcastAudiencePreview extends StatelessWidget {
  const BroadcastAudiencePreview({
    super.key,
    required this.listeners,
    required this.onOpen,
  });

  final List<RoomParticipant> listeners;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Material(
      color: BroadcastRoomColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 42,
                child: Stack(
                  children: [
                    for (
                      var index = 0;
                      index < listeners.take(4).length;
                      index++
                    )
                      Positioned(
                        left: index * 28,
                        child: CircleAvatar(
                          radius: 21,
                          backgroundColor: const Color(0xFF69202C),
                          backgroundImage: listeners[index].photoUrl == null
                              ? null
                              : NetworkImage(listeners[index].photoUrl!),
                          child: listeners[index].photoUrl == null
                              ? Text(
                                  listeners[index].displayName.isEmpty
                                      ? 'Y'
                                      : listeners[index].displayName[0]
                                            .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  listeners.isEmpty
                      ? copy.text('Audience is waiting', 'Publiczność czeka')
                      : copy.text(
                          '${listeners.length} listening now',
                          '${listeners.length} słucha teraz',
                        ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: BroadcastRoomColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

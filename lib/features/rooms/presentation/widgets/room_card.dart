import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Which visual family a room belongs to. Users must be able to tell
/// these apart in under a second while scrolling — by color system,
/// icon, and composition, not by reading a tiny label.
enum RoomCardIdentity {
  community,
  podcast,
  club;

  static RoomCardIdentity of(VoiceRoom room) {
    // Club lounges inherit the club's identity: they are created with a
    // deterministic `club_lounge_{clubId}` id and carry the club's own
    // name/cover on the room doc itself.
    if (room.id.startsWith('club_lounge_')) return RoomCardIdentity.club;
    return room.roomExperience == RoomExperience.broadcast
        ? RoomCardIdentity.podcast
        : RoomCardIdentity.community;
  }

  Color get accent => switch (this) {
    RoomCardIdentity.community => const Color(0xFF9D20FF),
    RoomCardIdentity.podcast => const Color(0xFFFF3E5F),
    RoomCardIdentity.club => const Color(0xFF2FC6A8),
  };

  IconData get icon => switch (this) {
    RoomCardIdentity.community => Icons.forum_rounded,
    RoomCardIdentity.podcast => Icons.podcasts_rounded,
    RoomCardIdentity.club => Icons.groups_2_rounded,
  };

  String get label => switch (this) {
    RoomCardIdentity.community => 'COMMUNITY',
    RoomCardIdentity.podcast => 'PODCAST',
    RoomCardIdentity.club => 'CLUB',
  };

  /// Fallback backdrop when the room has no cover — still unmistakably
  /// typed, never a generic dark box.
  List<Color> get fallbackGradient => switch (this) {
    RoomCardIdentity.community => const [Color(0xFF3A1657), Color(0xFF150F20)],
    RoomCardIdentity.podcast => const [Color(0xFF4A0F1E), Color(0xFF1C0B10)],
    RoomCardIdentity.club => const [Color(0xFF0E3A33), Color(0xFF0B1614)],
  };
}

/// The one room card for Home and Discover: the cover IS the card, with
/// a scrim for text; type identity carried by accent color, icon chip
/// and composition; host and live counts always visible. Feels like
/// content, not a database row.
class RoomCard extends StatelessWidget {
  const RoomCard({
    required this.room,
    required this.onTap,
    this.width = 236,
    this.height = 168,
    super.key,
  });

  final VoiceRoom room;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final identity = RoomCardIdentity.of(room);
    final hasCover = room.imageUrl?.trim().isNotEmpty == true;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: identity.fallbackGradient,
              ),
              border: Border.all(
                color: identity.accent.withValues(alpha: .38),
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasCover)
                  Image.network(
                    room.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                else
                  // Oversized ghost icon: typed identity even bare.
                  Positioned(
                    right: -18,
                    bottom: -14,
                    child: Icon(
                      identity.icon,
                      size: 110,
                      color: identity.accent.withValues(alpha: .12),
                    ),
                  ),
                // Scrim so text survives any cover.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .45, 1],
                      colors: [
                        Colors.black.withValues(alpha: .18),
                        Colors.black.withValues(alpha: hasCover ? .30 : 0),
                        Colors.black.withValues(alpha: .78),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _TypeChip(identity: identity),
                          const Spacer(),
                          if (room.isLive) const _LivePill(),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        room.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.3,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          UserAvatar(
                            radius: 10,
                            photoUrl: room.hostPhotoUrl,
                            displayName: room.hostName,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              room.hostName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFCFC5D8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.headset_rounded,
                            size: 13,
                            color: identity.accent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${room.participantCount}',
                            style: TextStyle(
                              color: identity.accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
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
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.identity});

  final RoomCardIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: identity.accent.withValues(alpha: .6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(identity.icon, size: 11, color: identity.accent),
          const SizedBox(width: 4),
          Text(
            identity.label,
            style: TextStyle(
              color: identity.accent,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF416C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

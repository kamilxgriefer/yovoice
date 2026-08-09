import 'package:flutter/material.dart';

import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Centralized status-ring language from the Home mockup — one place
/// defines what each ring color means, instead of ad-hoc colors per
/// widget.
///
/// Only statuses derivable from REAL data exist here. `speaking` /
/// `inRoom` / `inClub` are defined for when presence carries room
/// context (schema extension tracked in Roadmap) — nothing may pass
/// them speculatively.
enum PeopleStatus {
  speaking,
  inRoom,
  inClub,
  online,
  away;

  Color get ringColor => switch (this) {
    PeopleStatus.speaking => const Color(0xFFB44BFF),
    PeopleStatus.inRoom => const Color(0xFF35D07F),
    PeopleStatus.inClub => const Color(0xFFFFA94D),
    PeopleStatus.online => const Color(0xFF35D07F),
    PeopleStatus.away => const Color(0xFF564C63),
  };

  String get label => switch (this) {
    PeopleStatus.speaking => 'Speaking',
    PeopleStatus.inRoom => 'In a room',
    PeopleStatus.inClub => 'In a club',
    PeopleStatus.online => 'Online',
    PeopleStatus.away => 'Away',
  };
}

/// Avatar + status ring + name + status label, as one column — the
/// "Your people" row unit.
class PeopleStatusAvatar extends StatelessWidget {
  const PeopleStatusAvatar({
    required this.displayName,
    required this.status,
    required this.onTap,
    this.photoUrl,
    this.radius = 30,
    super.key,
  });

  final String displayName;
  final PeopleStatus status;
  final VoidCallback onTap;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final active = status != PeopleStatus.away;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2.6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: status.ringColor,
                  width: active ? 2.2 : 1.4,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: status.ringColor.withValues(alpha: .35),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: UserAvatar(
                radius: radius,
                photoUrl: photoUrl,
                displayName: displayName,
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              width: radius * 2.4,
              child: Column(
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active
                          ? status.ringColor
                          : const Color(0xFF9C90A8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

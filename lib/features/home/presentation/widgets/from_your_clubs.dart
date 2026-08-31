import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The Home mockup's FROM YOUR CLUBS section — the user's REAL club
/// memberships with their real lounge state. Three honest states per
/// club: lounge live (Join room CTA), idle (member count + open arrow),
/// and nothing at all when the user has no clubs (section hides; no
/// fabricated Cyber Lounge rows).
class FromYourClubs extends StatefulWidget {
  const FromYourClubs({required this.onJoinLounge, super.key});

  /// Handed the live lounge room; the shell owns the join flow.
  final void Function(Club club, VoiceRoom lounge) onJoinLounge;

  @override
  State<FromYourClubs> createState() => _FromYourClubsState();
}

class _FromYourClubsState extends State<FromYourClubs> {
  final _clubs = ClubService();
  final _rooms = RoomService();

  late final Stream<List<Club>> _myClubs = _clubs.watchMyClubs();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return StreamBuilder<List<Club>>(
      stream: _myClubs,
      builder: (context, snapshot) {
        // Checked BEFORE `data`, and given its own visible state. Hiding
        // the section on failure is what makes a broken read look like
        // "you are in no clubs" — the same collapse that kept Home's
        // Discover rail invisible for the life of the product. Genuinely
        // having no clubs still hides the section, which is the documented
        // behaviour above and unchanged.
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From your Clubs',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: palette.dangerForeground,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your clubs could not be loaded. '
                          '${friendlyErrorMessage(snapshot.error!, fallback: 'Check your connection and try again.')}',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final clubs = snapshot.data ?? const <Club>[];
        if (clubs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From your Clubs',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              for (final club in clubs.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ClubActivityCard(
                    club: club,
                    loungeStream: _rooms.watchClubLounge(club.id),
                    onJoinLounge: widget.onJoinLounge,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ClubActivityCard extends StatelessWidget {
  const _ClubActivityCard({
    required this.club,
    required this.loungeStream,
    required this.onJoinLounge,
  });

  final Club club;
  final Stream<VoiceRoom?> loungeStream;
  final void Function(Club club, VoiceRoom lounge) onJoinLounge;

  void _openClub(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ClubOverviewScreen(clubId: club.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return StreamBuilder<VoiceRoom?>(
      stream: loungeStream,
      builder: (context, snapshot) {
        final lounge = snapshot.data;
        final live = lounge != null && lounge.isLive;

        return Material(
          key: ValueKey('home-club-activity-${club.id}'),
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => _openClub(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: live
                      ? palette.successForeground.withValues(alpha: .55)
                      : palette.border,
                ),
              ),
              child: Row(
                children: [
                  // Club artwork through the canonical avatar component
                  // (same loading/error behavior as every avatar).
                  UserAvatar(
                    radius: 24,
                    photoUrl: club.avatarUrl,
                    displayName: club.name,
                    backgroundColor: const Color(0xFF0E3A33),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                club.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.groups_2_rounded,
                              size: 14,
                              color: palette.successForeground,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          live
                              ? 'Live now · ${lounge.participantCount} in the lounge'
                              : club.memberCount == 1
                              ? '1 member'
                              : '${club.memberCount} members',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: live
                                ? palette.successForeground
                                : palette.textSecondary,
                            fontSize: 12,
                            fontWeight: live
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (live)
                    FilledButton(
                      onPressed: () => onJoinLounge(club, lounge),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Join room',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';

import 'package:yovoice/features/clubs/data/models/club.dart' show ClubType;
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class RoomTypeSelectorScreen extends StatelessWidget {
  const RoomTypeSelectorScreen({
    this.entitlementService,
    this.clubService,
    super.key,
  });

  final EntitlementService? entitlementService;
  final ClubService? clubService;

  static const _background = Color(0xFF080711);
  static const _muted = Color(0xFFA69CAF);

  /// Kept as the names the existing tests use; the values now come from
  /// the one identity system rather than being restated here.
  static final familyAccent = SpaceIdentity.family.primary;
  static final familyGlow = SpaceIdentity.family.accent;
  static final familySurface = SpaceIdentity.family.surface;
  static final familyBorder = SpaceIdentity.family.border;

  void _openRoom(BuildContext context, RoomExperience experience) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CreateRoomScreen(experience: experience),
      ),
    );
  }

  Future<void> _openClub(BuildContext context) async {
    if (!await PremiumGates.ensureCanCreateClub(
      context,
      entitlementService: entitlementService,
      clubService: clubService,
    )) {
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const CreateClubScreen()),
    );
  }

  void _openFamilyRoom(BuildContext context) {
    // Same navigation pattern as the other three: pushReplacement onto
    // the creation screen. A Family Room IS a club, so it reuses that
    // screen's flow in its family template.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const CreateClubScreen(type: ClubType.family),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = <Widget>[
      _RoomChoice(
        title: 'Community Room',
        eyebrow: 'OPEN CONVERSATION',
        subtitle: 'A relaxed live room where everyone can speak.',
        identity: SpaceIdentity.community,
        features: const [
          'Free-flowing voice conversation',
          'Live chat and reactions',
          'Calm stage with speaker tiles',
        ],
        onTap: () => _openRoom(context, RoomExperience.community),
      ),
      _RoomChoice(
        title: 'Podcast Room',
        eyebrow: 'HOST + AUDIENCE',
        subtitle: 'A hosted show with a stage, audience and requests.',
        identity: SpaceIdentity.podcast,
        features: const [
          'Host and speaker stage',
          'Audience raise-hand queue',
          'Invite to stage and moderation',
        ],
        onTap: () => _openRoom(context, RoomExperience.broadcast),
      ),
      _RoomChoice(
        title: 'Club',
        eyebrow: 'PERMANENT COMMUNITY',
        subtitle: 'Members, roles, chat, announcements and a Club Lounge.',
        identity: SpaceIdentity.club,
        highlighted: true,
        features: const [
          'Invite friends and manage members',
          'Owner, Co-owner, Admin and more',
          'Persistent chat and private voice lounge',
        ],
        onTap: () => _openClub(context),
      ),
      _RoomChoice(
        title: 'Family Room',
        eyebrow: 'PRIVATE FAMILY SPACE',
        subtitle:
            'A permanent, invite-only space for the people closest to you.',
        identity: SpaceIdentity.family,
        features: const [
          'Always-open family voice lounge',
          'Private chat, announcements and quick check-ins',
          'Organizer and Member roles',
        ],
        onTap: () => _openFamilyRoom(context),
      ),
    ];

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text(
          'Create',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.feed,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = 20.0;
            const gap = 16.0;
            final innerWidth = constraints.maxWidth - horizontalPadding * 2;
            final useTwoColumns = constraints.maxWidth >= 900;
            final cardWidth = useTwoColumns
                ? (innerWidth - gap) / 2
                : innerWidth;

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                40,
              ),
              children: [
                const Text(
                  'What do you want to build?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start a conversation, host an audience or build a permanent home for your people.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final choice in choices)
                      SizedBox(width: cardWidth, child: choice),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoomChoice extends StatelessWidget {
  const _RoomChoice({
    required this.title,
    required this.eyebrow,
    required this.subtitle,
    required this.identity,
    required this.features,
    required this.onTap,
    this.highlighted = false,
  });

  final String title;
  final String eyebrow;
  final String subtitle;

  /// Where every colour on this card comes from. Shape, padding, radius,
  /// icon box, type scale and hover stay shared across all four — only
  /// the identity differs.
  final SpaceIdentity identity;

  final List<String> features;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: identity.surface,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: identity.outline,
              width: highlighted ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(color: identity.glow, blurRadius: 24, spreadRadius: 1),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: identity.wash,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      identity.icon,
                      color: identity.primary,
                      size: 30,
                    ),
                  ),
                  const Spacer(),
                  if (highlighted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: identity.wash,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: identity.primary.withValues(alpha: .55),
                        ),
                      ),
                      child: Text(
                        'NEW',
                        style: TextStyle(
                          color: identity.onSurfaceAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                eyebrow,
                style: TextStyle(
                  color: identity.onSurfaceAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: identity.primary),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFFA69CAF), height: 1.4),
              ),
              const SizedBox(height: 17),
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: identity.primary,
                        size: 17,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(
                            color: Color(0xFFD7D0DE),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

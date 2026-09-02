import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/space_identity.dart';

import 'package:yovoice/features/clubs/data/models/club.dart' show ClubType;
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

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
    final copy = AppLocalizations.of(context);
    final choices = <Widget>[
      _RoomChoice(
        title: copy.text('Community Room', 'Pokój społecznościowy'),
        eyebrow: copy.text('OPEN CONVERSATION', 'OTWARTA ROZMOWA'),
        subtitle: copy.text(
          'A relaxed live room where everyone can speak.',
          'Swobodny pokój na żywo, w którym każdy może zabrać głos.',
        ),
        identity: SpaceIdentity.community,
        features: [
          copy.text(
            'Free-flowing voice conversation',
            'Swobodna rozmowa głosowa',
          ),
          copy.text('Live chat and reactions', 'Czat na żywo i reakcje'),
          copy.text(
            'Calm stage with speaker tiles',
            'Przejrzysta scena z mówcami',
          ),
        ],
        onTap: () => _openRoom(context, RoomExperience.community),
      ),
      _RoomChoice(
        title: copy.text('Podcast Room', 'Pokój podcastowy'),
        eyebrow: copy.text('HOST + AUDIENCE', 'GOSPODARZ + PUBLICZNOŚĆ'),
        subtitle: copy.text(
          'A hosted show with a stage, audience and requests.',
          'Prowadzona audycja ze sceną, publicznością i zgłoszeniami.',
        ),
        identity: SpaceIdentity.podcast,
        features: [
          copy.text('Host and speaker stage', 'Scena dla gospodarza i mówców'),
          copy.text(
            'Audience raise-hand queue',
            'Kolejka zgłoszeń od publiczności',
          ),
          copy.text(
            'Invite to stage and moderation',
            'Zapraszanie na scenę i moderacja',
          ),
        ],
        onTap: () => _openRoom(context, RoomExperience.broadcast),
      ),
      _RoomChoice(
        title: copy.text('Club', 'Klub'),
        eyebrow: copy.text('PERMANENT COMMUNITY', 'STAŁA SPOŁECZNOŚĆ'),
        subtitle: copy.text(
          'Members, roles, chat, announcements and a Club Lounge.',
          'Członkowie, role, czat, ogłoszenia i klubowy pokój głosowy.',
        ),
        identity: SpaceIdentity.club,
        highlighted: true,
        features: [
          copy.text(
            'Invite friends and manage members',
            'Zaproś znajomych i zarządzaj członkami',
          ),
          copy.text(
            'Owner, Co-owner, Admin and more',
            'Właściciel, współwłaściciel, administrator i inne role',
          ),
          copy.text(
            'Persistent chat and private voice lounge',
            'Stały czat i prywatny pokój głosowy',
          ),
        ],
        onTap: () => _openClub(context),
      ),
      _RoomChoice(
        title: copy.text('Family Room', 'Pokój rodzinny'),
        eyebrow: copy.text(
          'PRIVATE FAMILY SPACE',
          'PRYWATNA PRZESTRZEŃ RODZINNA',
        ),
        subtitle: copy.text(
          'A permanent, invite-only space for the people closest to you.',
          'Stała przestrzeń tylko na zaproszenie dla najbliższych Ci osób.',
        ),
        identity: SpaceIdentity.family,
        features: [
          copy.text(
            'Always-open family voice lounge',
            'Zawsze dostępny rodzinny pokój głosowy',
          ),
          copy.text(
            'Private chat, announcements and quick check-ins',
            'Prywatny czat, ogłoszenia i szybkie meldunki',
          ),
          copy.text(
            'Organizer and Member roles',
            'Role organizatora i członka',
          ),
        ],
        onTap: () => _openFamilyRoom(context),
      ),
    ];

    final content = Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: Text(
          copy.text('Create', 'Utwórz'),
          style: const TextStyle(fontWeight: FontWeight.w900),
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
                Text(
                  copy.text(
                    'What do you want to build?',
                    'Co chcesz utworzyć?',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.text(
                    'Start a conversation, host an audience or build a permanent home for your people.',
                    'Rozpocznij rozmowę, poprowadź audycję lub stwórz stałą przestrzeń dla swoich osób.',
                  ),
                  style: const TextStyle(color: _muted, height: 1.45),
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
    return YoImmersiveDarkSurface(child: content);
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
    final copy = AppLocalizations.of(context);
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
                        copy.text('NEW', 'NOWOŚĆ'),
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

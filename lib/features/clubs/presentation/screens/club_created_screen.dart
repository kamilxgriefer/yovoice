import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class ClubCreatedScreen extends StatelessWidget {
  const ClubCreatedScreen({required this.club, super.key});

  final Club club;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isFamily = club.isFamilyRoom;
    final identity = isFamily ? SpaceIdentity.family : SpaceIdentity.club;
    final identityVisuals = identity.resolve(colors.brightness);
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('club-created-screen'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    minHeight: math.max(0, constraints.maxHeight - 50),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        key: const ValueKey('space-identity-created-hero'),
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          gradient: identityVisuals.heroGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: identityVisuals.heroGlow,
                              blurRadius: 34,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          club.initial,
                          key: const ValueKey(
                            'space-identity-created-hero-label',
                          ),
                          style: TextStyle(
                            color: identityVisuals.heroForeground,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        isFamily
                            ? copy.text(
                                'Your Family Room is ready',
                                'Twój pokój rodzinny jest gotowy',
                              )
                            : copy.text(
                                'Your Club is ready',
                                'Twój klub jest gotowy',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        club.name,
                        key: const ValueKey('space-identity-created-name'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: identityVisuals.foreground,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isFamily
                            ? copy.text(
                                'Family chat, announcements and Family Lounge have been created. You are the Organizer.',
                                'Utworzono czat rodzinny, ogłoszenia i rodzinny pokój głosowy. Jesteś organizatorem.',
                              )
                            : copy.text(
                                'General chat, announcements and Club Lounge have been created. You are the Owner.',
                                'Utworzono czat ogólny, ogłoszenia i klubowy pokój głosowy. Jesteś właścicielem.',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: palette.border),
                        ),
                        child: Column(
                          children: [
                            _SummaryRow(
                              icon: Icons.workspace_premium_rounded,
                              label: copy.text('Your role', 'Twoja rola'),
                              value: isFamily
                                  ? copy.text('Organizer', 'Organizator')
                                  : copy.text('Owner', 'Właściciel'),
                              accent: identityVisuals.foreground,
                            ),
                            Divider(color: palette.border, height: 25),
                            _SummaryRow(
                              icon: Icons.language_rounded,
                              label: copy.text('Language', 'Język'),
                              value: _languageLabel(club.defaultLanguage, copy),
                              accent: identityVisuals.foreground,
                            ),
                            Divider(color: palette.border, height: 25),
                            _SummaryRow(
                              icon: Icons.lock_outline_rounded,
                              label: copy.text('Privacy', 'Prywatność'),
                              value: _privacyLabel(club.privacy, copy),
                              accent: identityVisuals.foreground,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('space-identity-created-cta'),
                          onPressed: () =>
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ClubOverviewScreen(clubId: club.id),
                                ),
                              ),
                          style: FilledButton.styleFrom(
                            backgroundColor: identityVisuals.cta,
                            foregroundColor: identityVisuals.onCta,
                            minimumSize: const Size.fromHeight(58),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          icon: Icon(
                            isFamily
                                ? Icons.family_restroom_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                          label: Text(
                            isFamily
                                ? copy.text(
                                    'Open Family Room',
                                    'Otwórz pokój rodzinny',
                                  )
                                : copy.text('Open Club', 'Otwórz klub'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _privacyLabel(ClubPrivacy privacy, AppLocalizations copy) {
    return switch (privacy) {
      ClubPrivacy.public => copy.text('Public', 'Publiczny'),
      ClubPrivacy.private => copy.text('Private', 'Prywatny'),
      ClubPrivacy.inviteOnly => copy.text(
        'Invite only',
        'Tylko na zaproszenie',
      ),
    };
  }

  static String _languageLabel(String language, AppLocalizations copy) {
    if (!copy.isPolish) return language;
    return switch (language) {
      'English' => 'Angielski',
      'Polish' => 'Polski',
      'Dutch' => 'Niderlandzki',
      'German' => 'Niemiecki',
      'Spanish' => 'Hiszpański',
      'French' => 'Francuski',
      'Italian' => 'Włoski',
      'Portuguese' => 'Portugalski',
      'Japanese' => 'Japoński',
      'Korean' => 'Koreański',
      _ => language,
    };
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        Icon(icon, color: accent, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: palette.textSecondary)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

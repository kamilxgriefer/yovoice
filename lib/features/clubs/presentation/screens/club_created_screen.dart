import 'dart:math' as math;

import 'package:flutter/material.dart';

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
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [identity.accent, identity.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: identity.primary.withValues(alpha: .45),
                              blurRadius: 34,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          club.initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        isFamily
                            ? 'Your Family Room is ready'
                            : 'Your Club is ready',
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
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: identity.accent,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isFamily
                            ? 'Family chat, announcements and Family Lounge have been created. You are the Organizer.'
                            : 'General chat, announcements and Club Lounge have been created. You are the Owner.',
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
                              label: 'Your role',
                              value: isFamily ? 'Organizer' : 'Owner',
                              accent: identity.accent,
                            ),
                            Divider(color: palette.border, height: 25),
                            _SummaryRow(
                              icon: Icons.language_rounded,
                              label: 'Language',
                              value: club.defaultLanguage,
                              accent: identity.accent,
                            ),
                            Divider(color: palette.border, height: 25),
                            _SummaryRow(
                              icon: Icons.lock_outline_rounded,
                              label: 'Privacy',
                              value: _privacyLabel(club.privacy),
                              accent: identity.accent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ClubOverviewScreen(clubId: club.id),
                                ),
                              ),
                          style: FilledButton.styleFrom(
                            backgroundColor: identity.primary,
                            foregroundColor: colors.onPrimary,
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
                            isFamily ? 'Open Family Room' : 'Open Club',
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

  static String _privacyLabel(ClubPrivacy privacy) {
    return switch (privacy) {
      ClubPrivacy.public => 'Public',
      ClubPrivacy.private => 'Private',
      ClubPrivacy.inviteOnly => 'Invite only',
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

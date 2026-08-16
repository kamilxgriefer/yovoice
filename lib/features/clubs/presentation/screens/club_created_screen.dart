import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class ClubCreatedScreen extends StatelessWidget {
  const ClubCreatedScreen({required this.club, super.key});

  final Club club;

  static const _background = Color(0xFF080711);
  static const _primary = Color(0xFFA226FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC14DFF), Color(0xFF6C18E8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withValues(alpha: .45),
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
                      const Text(
                        'Your Club is ready',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        club.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFC56CFF),
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'General chat, announcements and Club Lounge have been created. You are the Owner.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFA69CAF),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171121),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFF3A2C49)),
                        ),
                        child: Column(
                          children: [
                            _SummaryRow(
                              icon: Icons.workspace_premium_rounded,
                              label: 'Your role',
                              value: 'Owner',
                            ),
                            const Divider(color: Color(0xFF35283F), height: 25),
                            _SummaryRow(
                              icon: Icons.language_rounded,
                              label: 'Language',
                              value: club.defaultLanguage,
                            ),
                            const Divider(color: Color(0xFF35283F), height: 25),
                            _SummaryRow(
                              icon: Icons.lock_outline_rounded,
                              label: 'Privacy',
                              value: _privacyLabel(club.privacy),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            minimumSize: const Size.fromHeight(58),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'The full Clubs tab arrives in Stage 6.3.',
                        style: TextStyle(
                          color: Color(0xFF716679),
                          fontSize: 12,
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFB94DFF), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFFA69CAF))),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

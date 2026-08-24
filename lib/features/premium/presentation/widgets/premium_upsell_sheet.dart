import 'package:flutter/material.dart';

import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// The contextual Premium moments — what a free member sees when they
/// reach for a Premium capability. One component, two voices, so the
/// Creator and Club upsells can't drift apart. Never a dead button,
/// never a generic "Coming soon".
enum PremiumUpsellContext { creator, creatorStudio, clubs, clubCreation }

Future<void> showPremiumUpsellSheet(
  BuildContext context, {
  required PremiumUpsellContext upsellContext,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 560,
    ),
    builder: (_) => _PremiumUpsellSheet(upsellContext: upsellContext),
  );
}

class _PremiumUpsellSheet extends StatelessWidget {
  const _PremiumUpsellSheet({required this.upsellContext});

  final PremiumUpsellContext upsellContext;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (upsellContext) {
      PremiumUpsellContext.creator => (
        Icons.auto_awesome_rounded,
        'Creator is included with YO Voice Premium',
        'Build a public Creator identity, grow followers and unlock '
            'Creator tools with a Premium subscription.',
      ),
      PremiumUpsellContext.creatorStudio => (
        Icons.auto_graph_rounded,
        'Creator Studio is a Premium feature',
        'Activate your Premium identity to open your creator dashboard, '
            'publishing tools and community insights.',
      ),
      PremiumUpsellContext.clubs => (
        Icons.groups_2_rounded,
        'Clubs are included with YO Voice Premium',
        'Activate your Premium identity to open the Clubs hub and build '
            'your own communities.',
      ),
      PremiumUpsellContext.clubCreation => (
        Icons.workspace_premium_rounded,
        'Create your own space',
        'Club creation is included with YO Voice Premium. Joining and '
            'participating in Clubs stays free for everyone.',
      ),
    };

    return Material(
      color: const Color(0xFF120D1A),
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const YoModalSheetChrome(
                sheetLabel: 'Premium offer',
                surfaceColor: Color(0xFF120D1A),
              ),
              const SizedBox(height: 6),
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF7B2FF7).withValues(alpha: .25),
                      const Color(0xFFC026FF).withValues(alpha: .12),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFC026FF).withValues(alpha: .45),
                  ),
                ),
                child: Icon(icon, color: const Color(0xFFE9B8FF), size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF9D95AD),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumScreen(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B2FF7),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Explore Premium',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Not now',
                  style: TextStyle(color: Color(0xFF9D95AD)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

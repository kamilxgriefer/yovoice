import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final (icon, title, body) = switch (upsellContext) {
      PremiumUpsellContext.creator => (
        Icons.auto_awesome_rounded,
        copy.text(
          'Creator is included with YO Voice Premium',
          'Funkcje twórcy są dostępne w YO Voice Premium',
        ),
        copy.text(
          'Build a public Creator identity, grow followers and unlock Creator tools with a Premium subscription.',
          'Zbuduj publiczną tożsamość twórcy, rozwijaj grono obserwujących i odblokuj narzędzia twórcy dzięki subskrypcji Premium.',
        ),
      ),
      PremiumUpsellContext.creatorStudio => (
        Icons.auto_graph_rounded,
        copy.text(
          'Creator Studio is a Premium feature',
          'Studio twórcy jest funkcją Premium',
        ),
        copy.text(
          'Activate your Premium identity to open your creator dashboard, publishing tools and community insights.',
          'Aktywuj tożsamość Premium, aby otworzyć panel twórcy, narzędzia publikowania i statystyki społeczności.',
        ),
      ),
      PremiumUpsellContext.clubs => (
        Icons.groups_2_rounded,
        copy.text(
          'Clubs are included with YO Voice Premium',
          'Kluby są dostępne w YO Voice Premium',
        ),
        copy.text(
          'Activate your Premium identity to open the Clubs hub and build your own communities.',
          'Aktywuj tożsamość Premium, aby otworzyć centrum klubów i budować własne społeczności.',
        ),
      ),
      PremiumUpsellContext.clubCreation => (
        Icons.workspace_premium_rounded,
        copy.text('Create your own space', 'Stwórz własną przestrzeń'),
        copy.text(
          'Club creation is included with YO Voice Premium. Joining and participating in Clubs stays free for everyone.',
          'Tworzenie klubów jest dostępne w YO Voice Premium. Dołączanie do klubów i udział w nich pozostają bezpłatne dla wszystkich.',
        ),
      ),
    };

    return Material(
      key: const ValueKey('premium-upsell-surface'),
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.text('Premium offer', 'Oferta Premium'),
                  surfaceColor: palette.surfaceRaised,
                ),
                const SizedBox(height: 6),
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primaryContainer,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: .65),
                    ),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
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
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      copy.text('Explore Premium', 'Poznaj Premium'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    copy.text('Not now', 'Nie teraz'),
                    style: TextStyle(color: palette.textSecondary),
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

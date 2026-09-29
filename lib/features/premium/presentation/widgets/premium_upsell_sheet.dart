import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/features/likers/presentation/show_likers.dart'
    show showLikersUpsell;
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_upsell_sheet.dart';

/// The contextual Premium moments — what a free member sees when they
/// reach for a Premium capability. One component, two voices, so the
/// Creator and Club upsells can't drift apart. Never a dead button,
/// never a generic "Coming soon".
enum PremiumUpsellContext {
  creator,
  creatorStudio,
  clubs,
  clubCreation,

  /// "See who liked" (ADR-230). Opens the owner-chosen U1 sheet, which is
  /// billing-aware: it offers "Explore Premium" only where a purchase can
  /// complete and otherwise says honestly that Premium can't be bought yet.
  seeWhoLiked,

  /// Premium Pages (ADR-233, R11): running a Page needs YO Voice VIP, which
  /// is given to testers for now. Opens the honest not-for-sale sheet.
  pages,
}

Future<void> showPremiumUpsellSheet(
  BuildContext context, {
  required PremiumUpsellContext upsellContext,
}) {
  if (upsellContext == PremiumUpsellContext.pages) {
    return showPagesUpsellSheet(
      context,
      // Full screen over the shell: the upsell opens from Treści, whose
      // own navigator would otherwise hold Premium under the dock.
      onSeePremium: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const PremiumScreen())),
    );
  }
  if (upsellContext == PremiumUpsellContext.seeWhoLiked) {
    // No particular Moment, Yeel or message here, so no public count line.
    return showLikersUpsell(context, null, totalCount: 0);
  }
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
          'Premium unlocks Creator tools. Age verification and your opt-in are still required before people can Follow your Creator profile.',
          'Premium odblokowuje narzędzia twórcy. Zanim inni będą mogli obserwować Twój profil twórcy, nadal potrzebne są potwierdzenie wieku i Twoja zgoda.',
        ),
      ),
      PremiumUpsellContext.creatorStudio => (
        Icons.auto_graph_rounded,
        copy.text(
          'Creator Studio is a Premium feature',
          'Studio twórcy jest funkcją Premium',
        ),
        copy.text(
          'Activate Premium to open your creator dashboard, publishing tools and community insights.',
          'Aktywuj Premium, aby otworzyć panel twórcy, narzędzia publikowania i statystyki społeczności.',
        ),
      ),
      PremiumUpsellContext.clubs => (
        Icons.hub_rounded,
        copy.text(
          'Your spaces are now in Servers',
          'Twoje przestrzenie są teraz w Serwerach',
        ),
        copy.text(
          'Open Servers to manage channels, members and conversations.',
          'Otwórz Serwery, aby zarządzać kanałami, członkami i rozmowami.',
        ),
      ),
      PremiumUpsellContext.clubCreation => (
        Icons.workspace_premium_rounded,
        copy.text('Create your own space', 'Stwórz własną przestrzeń'),
        copy.text(
          'Create and manage your space from the Servers tab.',
          'Twórz swoją przestrzeń i zarządzaj nią w karcie Serwery.',
        ),
      ),
      // showPremiumUpsellSheet routes this context to the billing-aware U1
      // sheet; the copy is kept identical here so the two can never differ.
      PremiumUpsellContext.seeWhoLiked => (
        Icons.favorite_rounded,
        LikersCopy(copy).upsellTitle,
        LikersCopy(copy).upsellBody,
      ),
      // showPremiumUpsellSheet routes this context to the Pages sheet; the
      // copy is kept identical here so the two can never differ.
      PremiumUpsellContext.pages => (
        Icons.article_outlined,
        PagePostCopy(copy).upsellTitle,
        PagePostCopy(copy).upsellBody,
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

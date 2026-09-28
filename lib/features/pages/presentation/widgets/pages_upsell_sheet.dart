import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// The honest Pages upsell (R11, `PremiumUpsellContext.pages`): running a
/// Page needs YO Voice VIP, VIP is given to testers for now, Premium can't
/// be bought yet, and following and reading Pages is free (O7). The
/// primary action only closes the sheet; the secondary one opens Premium.
Future<void> showPagesUpsellSheet(
  BuildContext context, {
  required VoidCallback onSeePremium,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  showDragHandle: false,
  constraints: ResponsiveContentFrame.adaptiveModalConstraints(
    context,
    maxWidth: 560,
  ),
  builder: (sheetContext) => PagesUpsellSheet(
    onSeePremium: () {
      Navigator.of(sheetContext).pop();
      onSeePremium();
    },
  ),
);

class PagesUpsellSheet extends StatelessWidget {
  const PagesUpsellSheet({required this.onSeePremium, super.key});

  final VoidCallback onSeePremium;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = PagePostCopy(AppLocalizations.of(context));
    Widget fact(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 18, color: color ?? palette.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.textPrimary.withValues(alpha: .88),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
    return Material(
      key: const ValueKey('pages-upsell'),
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: MediaQuery.highContrastOf(context)
            ? BorderSide(color: palette.borderStrong)
            : BorderSide.none,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.premiumOffer,
                  surfaceColor: palette.surfaceRaised,
                ),
                const SizedBox(height: 6),
                ExcludeSemantics(
                  child: Container(
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
                    child: Icon(
                      Icons.article_outlined,
                      color: colors.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  child: Text(
                    copy.upsellTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.upsellBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    children: [
                      fact(Icons.info_outline_rounded, copy.upsellNotForSale),
                      fact(
                        Icons.check_rounded,
                        copy.upsellFree,
                        color: palette.interactiveForeground,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('pages-upsell-got-it'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      copy.gotIt,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('pages-upsell-premium'),
                  onPressed: onSeePremium,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text(
                    copy.seePremium,
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

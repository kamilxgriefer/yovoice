import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// The widest the sheet grows on tablets and desktop; phones get the full
/// width (the shared adaptive-modal rule).
const double kVipMeaningSheetMaxWidth = 480;

/// Opens [VipMeaningSheet]: what the purple rosette beside a name means.
///
/// Reached from a header's rosette ([NameWithVipMark.explainOnTap]), the
/// 44×44 target of premium-pages R14. It only explains; it never offers a
/// purchase and never implies verification (spec §5 honesty rules).
Future<void> showVipMeaningSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: kVipMeaningSheetMaxWidth,
    ),
    builder: (_) => const VipMeaningSheet(),
  );
}

/// "VIP nie oznacza weryfikacji" (approved render P_rozeta-vip): the rosette,
/// the statement that VIP is a membership and not verification, a two-row
/// legend (VIP rosette versus the Official account mark) and one neutral
/// "Rozumiem" button.
class VipMeaningSheet extends StatelessWidget {
  const VipMeaningSheet({super.key});

  static const ValueKey<String> surfaceKey = ValueKey<String>(
    'vip-meaning-sheet',
  );
  static const ValueKey<String> closeKey = ValueKey<String>(
    'vip-meaning-sheet-close',
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return Material(
      key: surfaceKey,
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.vertical(top: AppRadius.xl.topLeft),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YoModalSheetChrome(
                  sheetLabel: VipBadge.label,
                  surfaceColor: palette.surfaceRaised,
                ),
                const SizedBox(height: 6),
                const Center(
                  child: YoVipRosette(diameter: 56, excludeSemantics: true),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    copy.text(
                      "VIP doesn't mean verified",
                      'VIP nie oznacza weryfikacji',
                    ),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: palette.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.text(
                    "VIP is a YO Voice membership. It doesn't mean the account "
                        "is verified. YO Voice doesn't check identities or "
                        'business details.',
                    'VIP to członkostwo YO Voice. Nie oznacza, że konto jest '
                        'zweryfikowane. YO Voice nie sprawdza tożsamości ani '
                        'danych firm.',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadius.md,
                    border: Border.all(
                      color: highContrast
                          ? palette.borderStrong
                          : palette.border,
                    ),
                  ),
                  child: Column(
                    children: [
                      _LegendRow(
                        key: const ValueKey('vip-meaning-legend-vip'),
                        mark: const YoVipRosette(
                          diameter: 22,
                          excludeSemantics: true,
                        ),
                        title: VipBadge.label,
                        body: copy.text(
                          'YO Voice membership',
                          'Członkostwo YO Voice',
                        ),
                      ),
                      Container(height: 1, color: palette.hairline),
                      _LegendRow(
                        key: const ValueKey('vip-meaning-legend-official'),
                        mark: Icon(
                          Icons.verified_rounded,
                          size: 24,
                          color: palette.infoForeground,
                        ),
                        title: copy.contextualText(
                          'identity.officialLegend',
                          'Official',
                          'Oficjalne',
                        ),
                        body: copy.text(
                          'Account run by the YO Voice team',
                          'Konto prowadzone przez zespół YO Voice',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  key: closeKey,
                  onPressed: () => Navigator.of(context).maybePop(),
                  style:
                      AppFinish.tonalNeutral(
                        palette,
                        highContrast: highContrast,
                      ).copyWith(
                        minimumSize: const WidgetStatePropertyAll(
                          Size(double.infinity, 52),
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ),
                  child: Text(copy.text('Got it', 'Rozumiem')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.mark,
    required this.title,
    required this.body,
    super.key,
  });

  final Widget mark;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SizedBox(width: 28, child: Center(child: mark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

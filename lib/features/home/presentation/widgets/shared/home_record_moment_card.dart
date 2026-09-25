import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';

/// "Masz chwilę? / Nagraj Voice Moment" — the one way to record from Home.
///
/// It replaces the followed-Moments rail that used to sit here: that rail's
/// content now lives in the Momenty destination, but the CREATE affordance
/// it carried is a real route the reader would otherwise lose, so it survives
/// as this row card. One ink, one target, one destination — the existing
/// recorder screen.
///
/// Refine-look §8.1: a plain R2 block (no tint — Start's one tint belongs to
/// "Tu i teraz"), and the mic is the voice bead at rest: the logo's glass at
/// 48 px with only a contact shadow. It lights only where a voice actually
/// plays, never here.
class HomeRecordMomentCard extends StatelessWidget {
  const HomeRecordMomentCard({required this.onCreateMoment, super.key});

  final VoidCallback onCreateMoment;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: '${copy.homeGotAMinute} ${copy.homeRecordVoiceMoment}',
      onTap: onCreateMoment,
      child: YoCard(
        key: const ValueKey('home-record-moment'),
        padding: const EdgeInsets.all(AppRhythm.item),
        semanticButton: false,
        onTap: onCreateMoment,
        child: Row(
          children: [
            const YoGradientDisc(
              key: ValueKey('home-record-moment-bead'),
              size: 48,
              icon: Icons.mic_rounded,
              gloss: true,
            ),
            const SizedBox(width: AppRhythm.item),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.homeGotAMinute,
                    maxLines: 2,
                    style: AppTypography.titleMedium.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    copy.homeRecordVoiceMoment,
                    maxLines: 2,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppRhythm.tight),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

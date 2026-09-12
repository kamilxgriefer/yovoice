import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/core/theme/place_identity.dart';

/// "Masz chwilę? / Nagraj Voice Moment" — the one way to record from Home.
///
/// It replaces the followed-Moments rail that used to sit here: that rail's
/// content now lives in the Momenty destination, but the CREATE affordance
/// it carried is a real route the reader would otherwise lose, so it survives
/// as this row card. One ink, one target, one destination — the existing
/// recorder screen.
class HomeRecordMomentCard extends StatelessWidget {
  const HomeRecordMomentCard({required this.onCreateMoment, super.key});

  final VoidCallback onCreateMoment;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = PlaceIdentity.community.resolve(
      Theme.of(context).brightness,
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: '${copy.homeGotAMinute} ${copy.homeRecordVoiceMoment}',
      onTap: onCreateMoment,
      child: Material(
        key: const ValueKey('home-record-moment'),
        color: palette.surface,
        borderRadius: AppRadius.lg,
        child: InkWell(
          onTap: onCreateMoment,
          excludeFromSemantics: true,
          borderRadius: AppRadius.lg,
          child: Container(
            padding: const EdgeInsets.all(AppRhythm.item),
            decoration: BoxDecoration(
              borderRadius: AppRadius.lg,
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: visuals.iconSurface,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: visuals.iconBorder),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    size: 26,
                    color: visuals.foreground,
                  ),
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
        ),
      ),
    );
  }
}

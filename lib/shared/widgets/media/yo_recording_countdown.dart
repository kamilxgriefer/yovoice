import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// How long before a capped recorder stops itself the person is warned.
const int recordingLimitWarningSeconds = 10;

/// Whole seconds left before [cap], counted up (50.2 s of a 60 s cap is 10),
/// or null outside the final [recordingLimitWarningSeconds] and once the cap
/// is reached.
int? recordingSecondsLeft(Duration elapsed, Duration cap) {
  final leftMs = cap.inMilliseconds - elapsed.inMilliseconds;
  if (leftMs <= 0) return null;
  final seconds = (leftMs + 999) ~/ 1000;
  return seconds <= recordingLimitWarningSeconds ? seconds : null;
}

/// The cues a capped recorder gives around its automatic stop: one light
/// haptic and one polite announcement when the final
/// [recordingLimitWarningSeconds] begin, and again when it stops itself.
///
/// The visible countdown is [YoRecordingCountdown]; it is deliberately not a
/// live region, because a per-second update would flood the screen reader.
class RecordingLimitCues {
  bool _warned = false;

  /// Forget the warning, for a fresh take.
  void reset() => _warned = false;

  /// Call on every recorder tick. Fires the warning once per take.
  void onTick(BuildContext context, Duration elapsed, Duration cap) {
    if (_warned || recordingSecondsLeft(elapsed, cap) == null) return;
    _warned = true;
    final copy = AppLocalizations.of(context);
    _cue(
      context,
      copy.text(
        'Ten seconds left. Recording stops by itself at the limit.',
        'Zostało dziesięć sekund. Nagrywanie zatrzyma się samo na limicie.',
      ),
    );
  }

  /// Call once the recorder stopped itself at the cap and the take is kept.
  void onAutomaticStop(BuildContext context, String message) =>
      _cue(context, message);

  static void _cue(BuildContext context, String message) {
    unawaited(HapticFeedback.lightImpact());
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }
}

/// The visible countdown in a capped recorder's final seconds.
///
/// It always occupies its space while the recorder is running, so the stop
/// control never shifts under a finger in the last seconds; it is shown only
/// when [secondsLeft] is set (see [recordingSecondsLeft]). The fade follows
/// the platform Reduce Motion setting through [AppMotion.resolve].
class YoRecordingCountdown extends StatelessWidget {
  const YoRecordingCountdown({super.key, required this.secondsLeft});

  final int? secondsLeft;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final shown = secondsLeft != null;
    final label = copy.template(
      '{seconds} s left',
      'Zostało {seconds} s',
      values: <String, Object>{
        'seconds': secondsLeft ?? recordingLimitWarningSeconds,
      },
    );
    return ExcludeSemantics(
      excluding: !shown,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: AppMotion.resolve(context, AppMotion.quick),
        curve: AppMotion.standardCurve,
        child: Container(
          key: shown ? const ValueKey('yo-recording-countdown') : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppRhythm.item,
            vertical: AppRhythm.hairline,
          ),
          decoration: BoxDecoration(
            color: palette.warningSurface,
            borderRadius: AppRadius.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 16,
                color: palette.warningForeground,
              ),
              const SizedBox(width: AppRhythm.hairline),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: palette.warningForeground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

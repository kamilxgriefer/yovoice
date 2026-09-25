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

/// How long a capped recorder's record control ignores taps after the
/// recorder stopped itself at the limit.
///
/// Stop and "Record again" share one control in the same place, so a Stop
/// aimed at the last second — a screen reader's double-tap, a slower or
/// unsteady hand after the ten-second warning — can land just after the
/// automatic stop and would otherwise start a new take over the kept one.
const Duration recordingAutoStopTapGrace = Duration(milliseconds: 1500);

/// Asks before a new take replaces the recording that is kept. Returns true
/// only when "Record again" was chosen; dismissing keeps the recording.
///
/// "Keep it" takes the initial focus, so a late or repeated activation lands
/// on the safe answer.
Future<bool> confirmReplaceRecording(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.appPalette;
      final copy = AppLocalizations.of(dialogContext);
      return AlertDialog(
        key: const ValueKey('recording-replace-dialog'),
        backgroundColor: palette.surfaceRaised,
        scrollable: true,
        title: Text(
          copy.text('Record again?', 'Nagrać ponownie?'),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          copy.text(
            'The recording you have now will be deleted and replaced by the '
                'new one.',
            'Obecne nagranie zostanie usunięte i zastąpione nowym.',
          ),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            key: const ValueKey('recording-replace-keep'),
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(copy.text('Keep it', 'Zachowaj')),
          ),
          FilledButton(
            key: const ValueKey('recording-replace-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(copy.text('Record again', 'Nagraj ponownie')),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

/// The spoken form of the countdown: the unit in full and, in Polish, in the
/// right plural form ("6 s" reads as a letter to a screen reader).
String recordingSecondsLeftSpoken(AppLocalizations copy, int seconds) {
  if (seconds == 1) return copy.text('1 second left', 'Została 1 sekunda');
  final values = <String, Object>{'seconds': seconds};
  final lastDigit = seconds % 10;
  final lastTwo = seconds % 100;
  final polishFew =
      lastDigit >= 2 && lastDigit <= 4 && (lastTwo < 12 || lastTwo > 14);
  return polishFew
      ? copy.template(
          '{seconds} seconds left',
          'Zostały {seconds} sekundy',
          values: values,
        )
      : copy.template(
          '{seconds} seconds left',
          'Zostało {seconds} sekund',
          values: values,
        );
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
                  semanticsLabel: recordingSecondsLeftSpoken(
                    copy,
                    secondsLeft ?? recordingLimitWarningSeconds,
                  ),
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

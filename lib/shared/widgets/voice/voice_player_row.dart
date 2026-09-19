import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

/// What the row's transport is doing right now.
///
/// [paused] draws exactly what [idle] draws — a play affordance — and exists
/// so a caller can hand over its own state without flattening it first;
/// [failed] is the retry affordance and only surfaces where the caller has a
/// retry path (the direct-message bubble; a voice reply answers a refused
/// grant with a snackbar and returns to [idle]).
enum VoicePlayerRowStatus { idle, loading, playing, paused, failed }

/// The inline voice-clip row (Slim redesign, phase 0, ADR-209).
///
/// One drawing for "an audio clip you can play here": the play/pause disc,
/// the waveform and the m:ss clock, in the message bubble, in the shared-media
/// Voice tab and under every voice reply in a Moment or Yeel thread. It is
/// **presentation only**. Everything that makes sound stays with the caller:
/// the `AudioPlayer`, its factory seam, the media grant (`resolveMediaUri`,
/// `prepareDirectVoiceSource`), the playback arbitration and its stale-grant
/// tokens, the retry and snackbar paths, and the mapping from that state to a
/// [status]. The row never allocates, subscribes or decides; it draws.
///
/// The caller also owns every word. This file is under `lib/shared/`, which
/// `test/localization_source_guard_test.dart` forbids raw English copy in, and
/// the labels belong to the feature anyway ("voice message" vs "voice reply
/// from {name}"), so [semanticsLabel] arrives already localized.
///
/// Honesty rule, inherited from [YoWaveform]: no per-clip amplitude is
/// recorded anywhere, so the bars are a fixed silhouette. [progress] is the
/// player's REAL reported position or nothing at all — a row whose player
/// exposes no position (the direct-message bubble reports play / pause /
/// loading / failed only) passes null and gets a still silhouette rather than
/// a fill invented from a duration.
///
/// Two shapes, one row, through [VoicePlayerRowStyle]:
///
/// * [VoicePlayerRowStyle.contained] — the thread row: its own
///   `surfaceMuted` card, a bordered 40 px disc, a position-swept waveform.
/// * [VoicePlayerRowStyle.inline] — the chat bubble: no surface of its own
///   (the bubble supplies it), a bare 44 px icon box, and colours injected by
///   the caller because the same row sits on a brand gradient (white ink) and
///   on a neutral incoming bubble (`textPrimary`).
class VoicePlayerRow extends StatelessWidget {
  const VoicePlayerRow({
    required this.status,
    required this.durationSeconds,
    required this.semanticsLabel,
    required this.onTap,
    required this.style,
    this.progress,
    this.tapKey,
    this.semanticsContainer = false,
    this.excludeChildSemantics = false,
    this.toggled,
    super.key,
  });

  /// Drives the icon: [VoicePlayerRowStatus.loading] wins over everything and
  /// spins, [VoicePlayerRowStatus.failed] retries,
  /// [VoicePlayerRowStatus.playing] pauses, the rest play.
  final VoicePlayerRowStatus status;

  /// The clip's real length, rendered by [formatVoiceClock]. Never a
  /// remaining or elapsed time: the row has no clock of its own.
  final int durationSeconds;

  /// Already localized by the caller, including the duration when the
  /// surface's label carries one.
  final String semanticsLabel;

  /// `null` disables the row.
  final VoidCallback? onTap;

  final VoicePlayerRowStyle style;

  /// The player's reported position, 0..1, or null for a still silhouette.
  /// A caller without a position stream must pass null, never a value
  /// derived from the duration.
  final ValueListenable<double>? progress;

  /// Goes on the `InkWell` that spans the whole row, so a test that finds the
  /// row by key also measures its touch target and long-presses it through to
  /// the caller's context-action wrapper.
  final Key? tapKey;

  /// `true` keeps the row its own semantics node where an ancestor fragment
  /// would otherwise absorb it (a thread below a 1200 px slot).
  final bool semanticsContainer;

  /// `true` replaces the children's semantics with this node's. It also moves
  /// the tap action onto the node, because excluding the children takes the
  /// `InkWell`'s action with them and a screen reader must still be able to
  /// activate the row.
  final bool excludeChildSemantics;

  /// `Semantics.toggled`; null leaves the flag off for surfaces whose node
  /// shape does not carry it.
  final bool? toggled;

  bool get _loading => status == VoicePlayerRowStatus.loading;
  bool get _failed => status == VoicePlayerRowStatus.failed;
  bool get _playing => status == VoicePlayerRowStatus.playing;

  @override
  Widget build(BuildContext context) {
    final border = style.borderColor;
    Widget row = InkWell(
      key: tapKey,
      onTap: onTap,
      borderRadius: style.borderRadius,
      child: Container(
        constraints: BoxConstraints(minHeight: style.minHeight),
        decoration: border == null
            ? null
            : BoxDecoration(
                borderRadius: style.borderRadius,
                border: Border.all(color: border),
              ),
        padding: style.padding == EdgeInsets.zero ? null : style.padding,
        child: Row(
          mainAxisSize: style.waveformConstraints == null
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            _control(),
            SizedBox(width: style.controlGap),
            _waveform(),
            SizedBox(width: style.clockGap),
            Text(
              formatVoiceClock(durationSeconds),
              maxLines: 1,
              style: AppTypography.bodySmall.copyWith(
                color: style.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );

    final surface = style.surface;
    if (surface != null) {
      row = Material(
        color: surface,
        borderRadius: style.borderRadius,
        child: row,
      );
    }

    return Semantics(
      container: semanticsContainer,
      button: true,
      toggled: toggled,
      label: semanticsLabel,
      onTap: excludeChildSemantics ? onTap : null,
      excludeSemantics: excludeChildSemantics,
      child: row,
    );
  }

  Widget _control() {
    Widget content = Center(
      child: _loading
          ? SizedBox.square(
              dimension: style.spinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: style.progressIndicator,
              ),
            )
          : Icon(
              _failed
                  ? Icons.refresh_rounded
                  : _playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: style.iconSize,
              color: _failed ? style.errorForeground : style.foreground,
            ),
    );
    final fill = style.controlFill;
    final border = style.controlBorderColor;
    if (fill != null || border != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: border == null ? null : Border.all(color: border),
        ),
        child: content,
      );
    }
    return SizedBox.square(dimension: style.controlSize, child: content);
  }

  Widget _waveform() {
    final constraints = style.waveformConstraints;
    final source = progress;
    final bars = source == null
        ? _silhouette(0)
        : ValueListenableBuilder<double>(
            valueListenable: source,
            builder: (context, value, _) => _silhouette(value),
          );
    return constraints == null
        ? Expanded(child: bars)
        : Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(constraints: constraints, child: bars),
          );
  }

  /// A row with a position source draws the Moment player's [StoryWaveform]
  /// (the position contract other surfaces pin by type); a row without one
  /// draws the still [YoWaveform] silhouette in the caller's ink. Both are
  /// the one painter — `StoryWaveform` is a `YoWaveform` with the player's
  /// defaults.
  Widget _silhouette(double value) => progress == null
      ? YoWaveform(
          color: style.waveformColor,
          height: style.waveformHeight,
          barWidth: style.waveformBarWidth,
          barCount: style.waveformBarCount,
          barGap: style.waveformBarGap,
          barRadius: style.waveformBarRadius,
        )
      : StoryWaveform(
          progress: value,
          height: style.waveformHeight,
          barWidth: style.waveformBarWidth,
          barGap: style.waveformBarGap,
          barRadius: style.waveformBarRadius ?? 2,
          playedGradient: style.playedGradient,
        );
}

/// Where the row is drawn: its surface, its ink and the size of its parts.
///
/// Colours are roles or caller-injected inks, never literals: the bubble's
/// row sits on a brand gradient in one direction and on `surfaceRaised` in
/// the other, so only the caller knows what is readable there.
@immutable
class VoicePlayerRowStyle {
  const VoicePlayerRowStyle({
    required this.foreground,
    required this.mutedForeground,
    required this.errorForeground,
    required this.progressIndicator,
    required this.waveformColor,
    this.playedGradient,
    this.surface,
    this.borderColor,
    this.borderRadius = AppRadius.md,
    this.padding = EdgeInsets.zero,
    this.minHeight = 56,
    this.controlSize = 40,
    this.controlFill,
    this.controlBorderColor,
    this.iconSize = 20,
    this.spinnerSize = 18,
    this.controlGap = AppRhythm.item,
    this.clockGap = AppRhythm.item,
    this.waveformHeight = 20,
    this.waveformBarWidth = 2,
    this.waveformBarCount,
    this.waveformBarGap = 3,
    this.waveformBarRadius = 1,
    this.waveformConstraints,
  });

  /// The thread row: its own card, a bordered disc and a swept waveform.
  ///
  /// The three measurements are parameters because the surface that mounts
  /// the row publishes them (`VoiceReplyMiniPlayer.height` / `.discSize` /
  /// `.waveformHeight`) for the layouts that reserve space for it; the
  /// defaults are those same numbers.
  factory VoicePlayerRowStyle.contained(
    AppPalette palette,
    ColorScheme colors, {
    double minHeight = 56,
    double controlSize = 40,
    double waveformHeight = 20,
  }) => VoicePlayerRowStyle(
    minHeight: minHeight,
    controlSize: controlSize,
    waveformHeight: waveformHeight,
    foreground: colors.onSurface,
    mutedForeground: palette.textSecondary,
    errorForeground: colors.error,
    progressIndicator: palette.audioAccent,
    waveformColor: StoryWaveform.unplayedColor(),
    playedGradient: palette.audioProgressGradient,
    surface: palette.surfaceMuted,
    borderColor: palette.border,
    controlFill: palette.surfaceRaised,
    controlBorderColor: palette.border,
    padding: const EdgeInsets.symmetric(
      horizontal: AppRhythm.item,
      vertical: AppRhythm.tight,
    ),
  );

  /// The chat bubble's row: no surface of its own, a bare icon box, and every
  /// ink injected because the same row is drawn white on the outgoing
  /// gradient and `textPrimary` on an incoming bubble.
  ///
  /// The waveform is bounded rather than [Expanded] so the bubble keeps
  /// shrink-wrapping its content: a full-width row would widen every voice
  /// bubble and push the reaction pill over the clock at 200 % text scale.
  factory VoicePlayerRowStyle.inline({
    required Color foreground,
    required Color mutedForeground,
    required Color errorForeground,
  }) => VoicePlayerRowStyle(
    foreground: foreground,
    mutedForeground: mutedForeground,
    errorForeground: errorForeground,
    progressIndicator: foreground,
    waveformColor: foreground.withValues(alpha: .82),
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    minHeight: 44,
    controlSize: 44,
    iconSize: 27,
    spinnerSize: 24,
    controlGap: 2,
    clockGap: AppRhythm.tight,
    waveformHeight: 32,
    waveformBarWidth: null,
    waveformBarCount: 24,
    waveformBarGap: 2,
    waveformBarRadius: 20,
    waveformConstraints: const BoxConstraints(minWidth: 48, maxWidth: 126),
  );

  /// Play / pause / retry ink.
  final Color foreground;

  /// The clock.
  final Color mutedForeground;

  /// The retry glyph of [VoicePlayerRowStatus.failed].
  final Color errorForeground;

  /// The busy spinner. Its own role because the bubble spins in the injected
  /// [foreground] (so it stays readable on the brand gradient) while the
  /// thread row spins in `audioAccent`.
  final Color progressIndicator;

  /// Unplayed bars of a still row; ignored where [VoicePlayerRow.progress] is
  /// given, because [StoryWaveform] carries the player's own pair.
  final Color waveformColor;

  /// Sweeps the played run where there is a position to sweep with.
  final LinearGradient? playedGradient;

  /// `null` draws no surface: the host (a message bubble) supplies it.
  final Color? surface;

  /// `null` draws no border.
  final Color? borderColor;

  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final double minHeight;

  /// The transport's box; at least 44 with the row's own height, because the
  /// whole row is the target.
  final double controlSize;
  final Color? controlFill;
  final Color? controlBorderColor;
  final double iconSize;
  final double spinnerSize;
  final double controlGap;
  final double clockGap;

  final double waveformHeight;

  /// Set = the tiled layout (fixed pitch); null = the flex layout, where
  /// [waveformBarCount] bars share the width.
  final double? waveformBarWidth;
  final int? waveformBarCount;
  final double waveformBarGap;
  final double? waveformBarRadius;

  /// `null` lets the waveform take the rest of the row ([Expanded]);
  /// otherwise the row shrink-wraps and the bars live inside these bounds.
  final BoxConstraints? waveformConstraints;
}

/// `m:ss`, with no leading zero on the minutes and a negative length read as
/// zero. One formatter so a clip is never `0:07` in a thread and `00:07` in a
/// bubble.
String formatVoiceClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

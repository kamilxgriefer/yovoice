import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc_button.dart';
import 'package:yovoice/shared/widgets/voice/yo_voice_finish.dart';

/// How far the two skip controls move the playhead.
///
/// Fifteen seconds is what the accepted board prints INSIDE the glyph, and
/// the copy, the label and the seek must agree — a control that says 15 and
/// moves 10 is a small lie that costs trust.
const Duration kMomentSkipStep = Duration(seconds: 15);

/// The expanded player's transport: the accessible position slider, the
/// elapsed / total labels, ⟲15, the dominant play-pause disc and ⟳15.
///
/// Every control routes through ONE position value and ONE seek callback,
/// so the ring, the waveform, the slider and the clock can never disagree.
/// The skips are deliberately *not* a play command: they move the playhead
/// and nothing else, they are disabled until this recording is actually
/// loaded, and they are clamped before they reach the player — seeking past
/// the end simply lands on the end and lets the normal completion fire.
///
/// There is no playback-speed chip: `setPlaybackRate` exists in the engine
/// but nothing in this app drives it yet, and a static "1×" that does
/// nothing would be a dummy control.
class MomentTransportControls extends StatelessWidget {
  const MomentTransportControls({
    required this.position,
    required this.total,
    required this.isPlaying,
    required this.busy,
    required this.canSeek,
    required this.compact,
    required this.onTogglePlay,
    required this.onSeek,
    this.keyPrefix = 'moment-detail',
    super.key,
  });

  /// The confirmed playhead.
  final Duration position;

  /// The recording's length: the player's duration once known, the
  /// document's `durationSeconds` before that.
  final Duration total;

  final bool isPlaying;
  final bool busy;

  /// False until this recording is loaded in this surface's player: the
  /// skips and the slider are then visibly disabled, never hidden.
  final bool canSeek;

  /// Below 600 the disc is the compact 64; from 600 up it is the dominant
  /// 72 of the accepted board.
  final bool compact;

  final VoidCallback onTogglePlay;

  /// Absolute target; already clamped by this widget.
  final ValueChanged<Duration> onSeek;

  final String keyPrefix;

  double get discSize =>
      compact ? AppSizing.audioControlCompact : AppSizing.audioControl;

  Duration _clamp(Duration target) {
    final max = total.inMilliseconds;
    if (max <= 0) return Duration.zero;
    return Duration(milliseconds: target.inMilliseconds.clamp(0, max));
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final maxMs = total.inMilliseconds;
    final positionMs = position.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : 0);
    final elapsedLabel = _clock(positionMs ~/ 1000);
    final totalLabel = _clock(total.inSeconds);
    final seekable = canSeek && !busy && maxMs > 0;
    // One playback position, one colour system: the slider's played run is
    // the waveform's own variant-B sweep (spread over the whole track and
    // revealed up to the thumb, exactly as the bars above it are), its
    // unplayed run the bars' `waveUnplayed`, and the thumb the sweep's
    // colour at the playhead (the B5 review, V2). The listening ring keeps
    // `audioAccent` — the separate "listening" accent spec §9 leaves as is.
    final played = AppGradients.voicePlayed(
      Theme.of(context).colorScheme,
      palette,
    );
    final fraction = maxMs > 0 ? positionMs / maxMs : 0.0;
    final playhead = Color.lerp(
      played.colors.first,
      played.colors.last,
      fraction,
    )!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          slider: true,
          enabled: seekable,
          label: copy.contextualText(
            'yoMoments.playbackPosition',
            'Playback position',
            'Pozycja odtwarzania',
          ),
          value: copy.template(
            '{position} of {total}',
            '{position} z {total}',
            values: <String, Object>{
              'position': elapsedLabel,
              'total': totalLabel,
            },
          ),
          increasedValue: copy.template(
            '{position} of {total}',
            '{position} z {total}',
            values: <String, Object>{
              'position': _clock(
                _clamp(position + const Duration(seconds: 5)).inSeconds,
              ),
              'total': totalLabel,
            },
          ),
          decreasedValue: copy.template(
            '{position} of {total}',
            '{position} z {total}',
            values: <String, Object>{
              'position': _clock(
                _clamp(position - const Duration(seconds: 5)).inSeconds,
              ),
              'total': totalLabel,
            },
          ),
          onIncrease: seekable
              ? () => onSeek(_clamp(position + const Duration(seconds: 5)))
              : null,
          onDecrease: seekable
              ? () => onSeek(_clamp(position - const Duration(seconds: 5)))
              : null,
          excludeSemantics: true,
          child: SizedBox(
            height: AppSizing.standardControlHeight,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: playhead,
                inactiveTrackColor: palette.waveUnplayed,
                disabledActiveTrackColor: palette.borderStrong,
                disabledInactiveTrackColor: palette.border,
                thumbColor: playhead,
                disabledThumbColor: palette.borderStrong,
                overlayColor: playhead.withValues(alpha: .12),
                trackShape: PlayedSweepTrackShape(played),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 8,
                  disabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                key: ValueKey('$keyPrefix-position'),
                value: positionMs.toDouble(),
                max: maxMs > 0 ? maxMs.toDouble() : 1,
                padding: EdgeInsets.zero,
                onChanged: seekable
                    ? (value) =>
                          onSeek(_clamp(Duration(milliseconds: value.round())))
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppRhythm.hairline),
        Row(
          children: [
            Text(
              elapsedLabel,
              key: ValueKey('$keyPrefix-elapsed'),
              maxLines: 1,
              style: _timeStyle(palette),
            ),
            const Spacer(),
            Text(
              totalLabel,
              key: ValueKey('$keyPrefix-total'),
              maxLines: 1,
              style: _timeStyle(palette),
            ),
          ],
        ),
        const SizedBox(height: AppRhythm.title),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SkipButton(
              buttonKey: ValueKey('$keyPrefix-skip-back'),
              forward: false,
              enabled: seekable,
              label: copy.text('Skip back 15 seconds', 'Cofnij o 15 sekund'),
              onPressed: () => onSeek(_clamp(position - kMomentSkipStep)),
            ),
            const SizedBox(width: AppRhythm.section),
            _PlayDisc(
              buttonKey: ValueKey('$keyPrefix-play'),
              diameter: discSize,
              isPlaying: isPlaying,
              busy: busy,
              onPressed: onTogglePlay,
            ),
            const SizedBox(width: AppRhythm.section),
            _SkipButton(
              buttonKey: ValueKey('$keyPrefix-skip-forward'),
              forward: true,
              enabled: seekable,
              label: copy.text(
                'Skip forward 15 seconds',
                'Przewiń o 15 sekund',
              ),
              onPressed: () => onSeek(_clamp(position + kMomentSkipStep)),
            ),
          ],
        ),
      ],
    );
  }

  TextStyle _timeStyle(AppPalette palette) => AppTypography.bodyMedium.copyWith(
    color: palette.textSecondary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// ⟲15 / ⟳15 — Material ships `replay_10`, never a 15, so the glyph is the
/// rounded replay arrow with the real step printed inside it. The forward
/// control mirrors the arrow; it is NOT mirrored again in RTL, because a
/// media transport keeps its direction.
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.buttonKey,
    required this.forward,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final bool forward;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  /// The glyph's box and its printed step at the ordinary text size.
  static const double glyphSize = 32;
  static const double stepFontSize = 9;

  /// How far the whole glyph follows the reader's text size.
  static const double maxGlyphScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final tint = enabled
        ? palette.textPrimary
        : palette.textPrimary.withValues(alpha: .38);
    // The step is part of the glyph, not running text: a "15" scaled on its
    // own spilled over the arrow at 200 %. So the arrow AND the step scale
    // together with the reader's text size, clamped at 1.5× (48 px arrow,
    // 13.5 px step), and never apart. The tooltip and the semantics label
    // carry the words at the reader's full size.
    final scale = MediaQuery.textScalerOf(
      context,
    ).clamp(minScaleFactor: 1, maxScaleFactor: maxGlyphScale).scale(1);
    final box = glyphSize * scale;
    final glyph = SizedBox.square(
      dimension: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: forward
                ? Matrix4.diagonal3Values(-1, 1, 1)
                : Matrix4.identity(),
            child: Icon(Icons.replay_rounded, size: box, color: tint),
          ),
          Text(
            '15',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: AppTypography.labelSmall.copyWith(
              color: tint,
              fontSize: stepFontSize * scale,
              height: 1,
            ),
          ),
        ],
      ),
    );
    return IconButton(
      key: buttonKey,
      onPressed: enabled ? onPressed : null,
      tooltip: label,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppSizing.standardControlHeight),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: ExcludeSemantics(child: glyph),
    );
  }
}

/// The slider track of the expanded player: the active run painted with
/// the waveform's played sweep ([AppGradients.voicePlayed]) spread over the
/// WHOLE track and revealed up to the thumb, so the colour at any x matches
/// the bars above it and nothing shimmers as the thumb moves. The inactive
/// run, the geometry and the disabled colours are the Material rounded
/// track's; a disabled slider paints its solid disabled colours.
@visibleForTesting
class PlayedSweepTrackShape extends RoundedRectSliderTrackShape {
  const PlayedSweepTrackShape(this.sweep);

  final Gradient sweep;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // The base shape paints the inactive run and, while the slider is
    // disabled, the solid disabled active run; the enabled active run is
    // the sweep below, never a solid colour under it.
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme.copyWith(activeTrackColor: Colors.transparent),
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (!isEnabled || enableAnimation.value <= 0) return;
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final ltr = textDirection == TextDirection.ltr;
    final half = track.height / 2;
    final left = ltr ? track.left : thumbCenter.dx - half;
    final right = ltr ? thumbCenter.dx + half : track.right;
    if (right - left <= track.height) return;
    final active = Rect.fromLTRB(
      left,
      track.top - additionalActiveTrackHeight / 2,
      right,
      track.bottom + additionalActiveTrackHeight / 2,
    );
    final paint = Paint()
      ..shader = sweep.createShader(track, textDirection: textDirection)
      ..color = Colors.black.withValues(alpha: enableAnimation.value);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(active, Radius.circular(active.height / 2)),
      paint,
    );
  }
}

/// The one dominant control of the expanded player: the voice bead
/// (refine-look R14, W3) at 64 / 72 — the logo's glass with its gloss and
/// rim, lit with the brand glow only while this recording plays, a white
/// spinner while the grant resolves.
///
/// The semantics wrapper is unchanged: one toggled button node that carries
/// the tap action, over an excluded `InkWell` that keeps the key the tests
/// and the harness address. The bead is drawn inside that `InkWell` and
/// follows its hover and keyboard focus.
class _PlayDisc extends StatelessWidget {
  const _PlayDisc({
    required this.buttonKey,
    required this.diameter,
    required this.isPlaying,
    required this.busy,
    required this.onPressed,
  });

  final Key buttonKey;
  final double diameter;
  final bool isPlaying;
  final bool busy;
  final VoidCallback onPressed;

  void _toggle() {
    if (!isPlaying) YoGradientDiscButton.playHaptic();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = busy
        ? copy.contextualText('yoMoments.loading', 'Loading', 'Wczytywanie')
        : isPlaying
        ? copy.contextualText('yoMoments.pause', 'Pause', 'Pauza')
        : copy.contextualText('yoMoments.play', 'Play', 'Odtwórz');
    return Semantics(
      container: true,
      button: true,
      toggled: isPlaying,
      label: label,
      // The InkWell below is excluded from the tree, so its tap action would
      // never reach the accessibility bridge. Forward it here: without this
      // the node is a button that TalkBack, Switch Access and
      // `accessibilityActivate` cannot operate.
      onTap: busy ? null : _toggle,
      excludeSemantics: true,
      child: YoGradientDiscButton(
        disc: (hovered, focused) => YoGradientDisc(
          size: diameter,
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          glyphSize: YoVoiceBead.glyphSize(diameter),
          nudgePlay: !isPlaying,
          gloss: true,
          // Lit only once the recording actually sounds, never while its
          // grant is still resolving.
          emphasis: isPlaying && !busy
              ? YoDiscEmphasis.lit
              : YoDiscEmphasis.rest,
          status: busy ? YoDiscStatus.busy : YoDiscStatus.idle,
          hovered: hovered,
          focused: focused,
        ),
        builder: (context, states, disc) => Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: buttonKey,
            statesController: states,
            customBorder: const CircleBorder(),
            // The bead carries hover, press and focus itself.
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            onTap: busy ? null : _toggle,
            child: disc,
          ),
        ),
      ),
    );
  }
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

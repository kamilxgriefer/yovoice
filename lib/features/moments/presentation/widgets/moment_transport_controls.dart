import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart'
    show VoiceBeadGlyph, voiceBeadStartHaptic;

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
    // The played part of the slider is the played ink of the waveform above
    // it (variant B, the logo violet), so the two position readers look like
    // one — as in the look Kamil approved (the Mac reference frames of the
    // detail). The rest of the track keeps its `borderStrong` boundary.
    //
    // WCAG 1.4.11: the THUMB carries the slider's state. It is the played
    // ink at 8 px radius and holds ≥ 6.2:1 on the Dark block (#B082FA on
    // #1C1626) and ≥ 7.5:1 on Pearl's white. The played / unplayed track
    // pair alone is ~1.8:1 in Dark (it was ~3.2:1 in cyan), so the track is
    // never the only cue; the clock under it and the slider's value
    // semantics say the same position in words.
    final played = AppGradients.voicePlayed(
      Theme.of(context).colorScheme,
      palette,
    ).colors.first;
    final maxMs = total.inMilliseconds;
    final positionMs = position.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : 0);
    final elapsedLabel = _clock(positionMs ~/ 1000);
    final totalLabel = _clock(total.inSeconds);
    final seekable = canSeek && !busy && maxMs > 0;

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
                activeTrackColor: played,
                inactiveTrackColor: palette.borderStrong,
                disabledActiveTrackColor: palette.borderStrong,
                disabledInactiveTrackColor: palette.border,
                thumbColor: played,
                disabledThumbColor: palette.borderStrong,
                overlayColor: played.withValues(alpha: .12),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final tint = enabled
        ? palette.textPrimary
        : palette.textPrimary.withValues(alpha: .38);
    final glyph = SizedBox.square(
      dimension: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: forward
                ? Matrix4.diagonal3Values(-1, 1, 1)
                : Matrix4.identity(),
            child: Icon(Icons.replay_rounded, size: 32, color: tint),
          ),
          Text(
            '15',
            textAlign: TextAlign.center,
            // Part of the 32 px glyph, which does not scale: a scaled "15"
            // overprinted the arrow at 200 % text. The control's name is
            // its tooltip and semantics, which do scale and are read.
            textScaler: TextScaler.noScaling,
            style: AppTypography.labelSmall.copyWith(
              color: tint,
              fontSize: 9,
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

/// The one dominant control of the expanded player: the R14 voice bead at
/// 64 / 72 — the logo's glass, lit only while this Moment plays, a white
/// spinner while the grant resolves. The Semantics wrapper and the keyed
/// ink well are the ones the transport always had; the bead is draw-only.
class _PlayDisc extends StatefulWidget {
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

  @override
  State<_PlayDisc> createState() => _PlayDiscState();
}

class _PlayDiscState extends State<_PlayDisc> {
  bool _hovered = false;
  bool _focused = false;

  void _press() {
    if (!widget.isPlaying) voiceBeadStartHaptic();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final busy = widget.busy;
    final isPlaying = widget.isPlaying;
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
      onTap: busy ? null : _press,
      excludeSemantics: true,
      child: YoPressFeedback(
        scale: YoPressFeedback.disc,
        enabled: !busy,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          child: InkWell(
            key: widget.buttonKey,
            customBorder: const CircleBorder(),
            onTap: busy ? null : _press,
            // The bead carries hover, press and focus itself.
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            onHover: (value) {
              if (value != _hovered) setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (value != _focused) setState(() => _focused = value);
            },
            child: YoGradientDisc(
              size: widget.diameter,
              emphasis: isPlaying && !busy
                  ? YoDiscEmphasis.lit
                  : YoDiscEmphasis.rest,
              gloss: true,
              status: busy ? YoDiscStatus.busy : YoDiscStatus.idle,
              hovered: _hovered,
              focused: _focused,
              nudgePlay: !isPlaying,
              glyph: VoiceBeadGlyph(playing: isPlaying),
            ),
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

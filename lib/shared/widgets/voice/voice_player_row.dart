import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

export 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart'
    show YoDiscTone;

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
///   `surfaceMuted` card, the 40 px voice bead (refine-look R14) lit only
///   while this clip plays, and the R13 waveform poured toward the real
///   position.
/// * [VoicePlayerRowStyle.inline] — the chat bubble: no surface of its own
///   (the bubble supplies it), a bare 44 px icon box, and colours injected by
///   the caller because the same row sits on a brand gradient (white ink) and
///   on a neutral incoming bubble (`textPrimary`). The bubble opts into the
///   34 px bead and the R13 inks through the factory's additive parameters;
///   without them it draws exactly what it drew before.
///
/// **Wiring the chat voice bubble (refine-look §8.3, R13 / R14).** Every
/// piece is additive; a bubble that passes none of it is unchanged.
///
/// * **Style** — [VoicePlayerRowStyle.bubble] with `outgoing` set from the
///   bubble's side. Incoming: the 34 px brand bead (gloss, lit — brand
///   glow — only while [status] is [VoicePlayerRowStatus.playing]),
///   `waveUnplayed` bars and the variant-B played sweep
///   (`AppGradients.voicePlayed`). Outgoing: the 34 px bead in
///   [YoDiscTone.onBrand] (white @ .22, no gloss, rim or shadow, never lit —
///   the bubble's own gradient is already the brand), white played bars
///   (`AppFinish.outgoingWavePlayed`) over `AppFinish.outgoingWaveUnplayed`
///   (white @ .35, the ≥ 3:1 value B1 measured; @ .50 held only 2.3-2.6:1).
///   The pour ([VoicePlayerRowStyle.continuousProgress]) is on for both.
///   The same knobs are on [VoicePlayerRowStyle.inline] for a caller that
///   needs to mix them differently.
/// * **Position** — [progress]: a `ValueListenable<double?>` the bubble
///   feeds from its player's REAL `onPositionChanged` (position ÷ duration,
///   0..1). Set it to `null` on completion and on a source change, and the
///   bars go back to a still silhouette; never set it from a duration or a
///   timer. A bubble without a position source passes no listenable at all.
/// * **Seek** — none in a bubble; the pour snaps by itself on any backwards
///   jump (a restart), so no snap key is needed.
class VoicePlayerRow extends StatefulWidget {
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
  /// derived from the duration. A listenable whose VALUE is null (a clip
  /// that completed, a changed source) also draws the still silhouette, so
  /// a caller can keep one notifier for the bubble's whole life. A
  /// `ValueListenable<double>` is accepted as it always was.
  final ValueListenable<double?>? progress;

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

  @override
  State<VoicePlayerRow> createState() => _VoicePlayerRowState();
}

/// Keyboard focus draws a 2 px ring over the row's own shape. The theme's
/// focus tint alone is about 1.25:1 against `surfaceMuted` and
/// `surfaceRaised` in both palettes, so a desktop or web user tabbing through
/// a thread could not see which clip Enter would play (WCAG 2.4.7).
class _VoicePlayerRowState extends State<VoicePlayerRow> {
  bool _focused = false;
  bool _hovered = false;

  VoicePlayerRowStatus get status => widget.status;
  VoicePlayerRowStyle get style => widget.style;
  int get durationSeconds => widget.durationSeconds;
  ValueListenable<double?>? get progress => widget.progress;

  bool get _loading => status == VoicePlayerRowStatus.loading;
  bool get _failed => status == VoicePlayerRowStatus.failed;
  bool get _playing => status == VoicePlayerRowStatus.playing;

  @override
  Widget build(BuildContext context) {
    final border = style.borderColor;
    final onTap = _withHaptic(widget.onTap);
    Widget row = InkWell(
      key: widget.tapKey,
      onTap: onTap,
      borderRadius: style.borderRadius,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      onHover: style.beadTone == null
          ? null
          : (hovered) {
              if (hovered != _hovered) setState(() => _hovered = hovered);
            },
      child: Stack(
        // The row keeps exactly the constraints it had without the ring.
        fit: StackFit.passthrough,
        children: [
          _content(border),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: style.borderRadius,
                  border: Border.all(
                    color: _focused
                        ? style.focusRing ?? context.appPalette.focus
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
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
      container: widget.semanticsContainer,
      button: true,
      toggled: widget.toggled,
      label: widget.semanticsLabel,
      onTap: widget.excludeChildSemantics ? onTap : null,
      excludeSemantics: widget.excludeChildSemantics,
      child: row,
    );
  }

  /// The bead's light impact when a tap is about to START a clip (R14),
  /// on the phones only. The legacy control keeps its silent tap.
  VoidCallback? _withHaptic(VoidCallback? onTap) {
    if (onTap == null || style.beadTone == null) return onTap;
    return () {
      if (!_playing && !_loading) voiceBeadStartHaptic();
      onTap();
    };
  }

  Widget _content(Color? border) => Container(
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
  );

  Widget _control() {
    final tone = style.beadTone;
    if (tone != null) return _bead(tone);
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

  /// The R14 voice bead in the transport's box: gloss on the brand tone,
  /// lit only while this clip plays, a white spinner while loading, the
  /// refresh glyph on failure and a flat disc when the row is disabled. It
  /// is draw-only: the row's own ink well keeps the tap, the key, the focus
  /// ring and the semantics.
  Widget _bead(YoDiscTone tone) {
    final size = style.beadSize ?? style.controlSize;
    final enabled = widget.onTap != null;
    final status = _loading
        ? YoDiscStatus.busy
        : _failed
        ? YoDiscStatus.failed
        : enabled
        ? YoDiscStatus.idle
        : YoDiscStatus.disabled;
    final brand = tone == YoDiscTone.brand;
    return SizedBox.square(
      dimension: style.controlSize,
      child: Center(
        child: YoPressFeedback(
          scale: YoPressFeedback.disc,
          enabled: enabled,
          child: YoGradientDisc(
            size: size,
            tone: tone,
            emphasis: brand && _playing
                ? YoDiscEmphasis.lit
                : YoDiscEmphasis.rest,
            gloss: brand,
            status: status,
            hovered: _hovered && enabled,
            nudgePlay: !_playing,
            glyph: VoiceBeadGlyph(playing: _playing),
          ),
        ),
      ),
    );
  }

  Widget _waveform() {
    final constraints = style.waveformConstraints;
    final source = progress;
    final bars = source == null
        ? _silhouette(null)
        : ValueListenableBuilder<double?>(
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
  ///
  /// A style with an [VoicePlayerRowStyle.unplayed] ink draws the R13
  /// waveform instead: its own idle ink at rest and while playing, the
  /// played sweep revealed across the whole run, and — with
  /// [VoicePlayerRowStyle.continuousProgress] — poured toward each real
  /// position ([VoicePourWaveform]). A null position (no source, or a
  /// source reset after completion) is a still silhouette in that ink.
  Widget _silhouette(double? value) {
    if (progress == null) {
      return YoWaveform(
        color: style.waveformColor,
        height: style.waveformHeight,
        barWidth: style.waveformBarWidth,
        barCount: style.waveformBarCount,
        barGap: style.waveformBarGap,
        barRadius: style.waveformBarRadius,
      );
    }
    final unplayed = style.unplayed;
    if (unplayed == null) {
      return StoryWaveform(
        progress: value ?? 0,
        height: style.waveformHeight,
        barWidth: style.waveformBarWidth,
        barGap: style.waveformBarGap,
        barRadius: style.waveformBarRadius ?? 2,
        playedGradient: style.playedGradient,
      );
    }
    return VoicePourWaveform(
      progress: value,
      pour: style.continuousProgress,
      color: unplayed,
      playedColor: style.playedColor ?? AppColors.secondary,
      playedGradient: style.playedGradient,
      height: style.waveformHeight,
      barWidth: style.waveformBarWidth,
      barCount: style.waveformBarCount,
      barGap: style.waveformBarGap,
      barRadius: style.waveformBarRadius,
    );
  }
}

/// The bead's play / pause glyph: a 200 ms easeInOut cross-fade between the
/// two rounded icons, instant under Reduce Motion, accessible navigation or
/// a paused ticker ([AppMotion.decorative]). Plain [Icon]s rather than an
/// `AnimatedIcon`, so every surface and test that finds its transport by
/// icon keeps finding it.
class VoiceBeadGlyph extends StatelessWidget {
  const VoiceBeadGlyph({required this.playing, super.key});

  final bool playing;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.decorative(context)
        ? const Duration(milliseconds: 200)
        : Duration.zero,
    switchInCurve: Curves.easeInOut,
    switchOutCurve: Curves.easeInOut,
    child: Icon(
      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      key: ValueKey<bool>(playing),
    ),
  );
}

/// The R13 "pour": a [YoWaveform] whose played run follows the player's
/// REAL position, tweened linearly toward each reported position over
/// [pourDuration] so the fill flows instead of stepping.
///
/// It never extrapolates: every frame sits between the last painted value
/// and the newest real position. A jump backwards (a seek back, a restart),
/// a change of [snapKey] (the caller's seek) or a first position snaps
/// instead of pouring, and under Reduce Motion, accessible navigation or a
/// paused [TickerMode] ([AppMotion.decorative]) the fill moves only on
/// position events. Bar heights never change — the silhouette is fixed.
///
/// Paints with `continuousProgress` and the played gradient spread across
/// the whole run ([YoWaveformGradientSpan.full]), so a bar keeps one colour
/// for the whole play-through. [pour] false draws the same waveform without
/// the tween.
class VoicePourWaveform extends StatefulWidget {
  const VoicePourWaveform({
    required this.progress,
    required this.color,
    this.playedColor = AppColors.secondary,
    this.playedGradient,
    this.pour = true,
    this.snapKey,
    this.height = 24,
    this.width,
    this.barWidth,
    this.barCount,
    this.barGap = 3,
    this.barRadius,
    this.silhouette = YoWaveform.bars,
    super.key,
  });

  /// The player's real position, 0..1, or null for a still silhouette.
  final double? progress;
  final Color color;
  final Color playedColor;
  final LinearGradient? playedGradient;

  /// False paints each position as it arrives (no tween).
  final bool pour;

  /// Changes when the caller seeks: the fill then snaps to the new position.
  final Object? snapKey;

  final double height;
  final double? width;
  final double? barWidth;
  final int? barCount;
  final double barGap;
  final double? barRadius;
  final List<double> silhouette;

  /// How long the fill takes to reach a new real position (~ the player's
  /// position-event period).
  static const Duration pourDuration = Duration(milliseconds: 200);

  @override
  State<VoicePourWaveform> createState() => _VoicePourWaveformState();
}

class _VoicePourWaveformState extends State<VoicePourWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pour = AnimationController(
    vsync: this,
    duration: VoicePourWaveform.pourDuration,
  );
  double? _from;
  double? _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.progress;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Motion switched off mid-pour: land on the real position at once.
    if (!AppMotion.decorative(context) && _pour.isAnimating) _snap(_to);
  }

  @override
  void didUpdateWidget(VoicePourWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.progress;
    if (next == _to && widget.snapKey == oldWidget.snapKey) return;
    final shown = _shown;
    final pours =
        widget.pour &&
        next != null &&
        shown != null &&
        next > shown &&
        widget.snapKey == oldWidget.snapKey &&
        AppMotion.decorative(context);
    if (!pours) {
      _snap(next);
      return;
    }
    _from = shown;
    _to = next;
    _pour.forward(from: 0);
  }

  void _snap(double? value) {
    _pour.stop();
    _pour.value = 1;
    _from = _to = value;
  }

  double? get _shown {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return to;
    return from + (to - from) * _pour.value;
  }

  @override
  void dispose() {
    _pour.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pour,
    builder: (context, _) => YoWaveform(
      progress: _shown,
      color: widget.color,
      playedColor: widget.playedColor,
      playedGradient: widget.playedGradient,
      continuousProgress: true,
      gradientSpan: YoWaveformGradientSpan.full,
      height: widget.height,
      width: widget.width,
      barWidth: widget.barWidth,
      barCount: widget.barCount,
      barGap: widget.barGap,
      barRadius: widget.barRadius,
      silhouette: widget.silhouette,
    ),
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
    this.focusRing,
    this.beadTone,
    this.beadSize,
    this.unplayed,
    this.playedColor,
    this.continuousProgress = false,
  });

  /// The thread row: its own card, the 40 px voice bead and the R13 waveform
  /// (`waveUnplayed` bars, the variant-B played sweep, poured).
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
    waveformColor: palette.waveUnplayed,
    playedGradient: AppGradients.voicePlayed(colors, palette),
    surface: palette.surfaceMuted,
    borderColor: palette.border,
    controlFill: palette.surfaceRaised,
    controlBorderColor: palette.border,
    padding: const EdgeInsets.symmetric(
      horizontal: AppRhythm.item,
      vertical: AppRhythm.tight,
    ),
    beadTone: YoDiscTone.brand,
    unplayed: palette.waveUnplayed,
    continuousProgress: true,
  );

  /// The chat bubble's row: no surface of its own, a bare icon box, and every
  /// ink injected because the same row is drawn white on the outgoing
  /// gradient and `textPrimary` on an incoming bubble.
  ///
  /// The waveform is bounded rather than [Expanded] so the bubble keeps
  /// shrink-wrapping its content: a full-width row would widen every voice
  /// bubble and push the reaction pill over the clock at 200 % text scale.
  ///
  /// Every parameter after the three inks is additive and off by default, so
  /// an existing bubble keeps drawing exactly what it drew. [beadTone] puts
  /// the R14 bead ([beadSize], 34 by default) in the 44 px box —
  /// [YoDiscTone.brand] on an incoming bubble, [YoDiscTone.onBrand] on the
  /// outgoing gradient; [unplayed] / [playedColor] / [playedGradient] give a
  /// row that has a real position the R13 inks (outgoing:
  /// `AppFinish.outgoingWaveUnplayed` / `outgoingWavePlayed`), and
  /// [continuousProgress] pours it.
  factory VoicePlayerRowStyle.inline({
    required Color foreground,
    required Color mutedForeground,
    required Color errorForeground,
    YoDiscTone? beadTone,
    double beadSize = 34,
    Color? unplayed,
    Color? playedColor,
    LinearGradient? playedGradient,
    bool continuousProgress = false,
  }) => VoicePlayerRowStyle(
    beadTone: beadTone,
    beadSize: beadTone == null ? null : beadSize,
    unplayed: unplayed,
    playedColor: playedColor,
    playedGradient: playedGradient,
    continuousProgress: continuousProgress,
    foreground: foreground,
    mutedForeground: mutedForeground,
    errorForeground: errorForeground,
    progressIndicator: foreground,
    waveformColor: unplayed ?? foreground.withValues(alpha: .82),
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
    // The focus ring takes the bubble's own ink: violet `focus` would vanish
    // on the outgoing brand gradient, the injected foreground never does.
    focusRing: foreground,
  );

  /// The chat voice bubble in the refine-look finish (§8.3, R13 / R14): the
  /// [VoicePlayerRowStyle.inline] row with the 34 px voice bead and the
  /// poured R13 waveform, inked for the bubble's side.
  ///
  /// * **Incoming** ([outgoing] false, a `blockGradient` bubble): the brand
  ///   bead — gloss, lit only while the clip plays — `waveUnplayed` bars and
  ///   the variant-B played sweep ([AppGradients.voicePlayed]).
  /// * **Outgoing** (on `AppGradients.primaryAction`): the [YoDiscTone.onBrand]
  ///   bead — white @ .22, no gloss, rim or shadow, never lit — with
  ///   [AppFinish.outgoingWavePlayed] over [AppFinish.outgoingWaveUnplayed].
  ///
  /// [foreground], [mutedForeground] and [errorForeground] stay the bubble's
  /// own inks (the clock, the focus ring and a legacy retry glyph read
  /// them). The waveform only fills where [VoicePlayerRow.progress] carries
  /// a real position; without one it is the still silhouette in the
  /// unplayed ink.
  factory VoicePlayerRowStyle.bubble({
    required bool outgoing,
    required AppPalette palette,
    required ColorScheme colors,
    required Color foreground,
    required Color mutedForeground,
    required Color errorForeground,
  }) => VoicePlayerRowStyle.inline(
    foreground: foreground,
    mutedForeground: mutedForeground,
    errorForeground: errorForeground,
    beadTone: outgoing ? YoDiscTone.onBrand : YoDiscTone.brand,
    unplayed: outgoing ? AppFinish.outgoingWaveUnplayed : palette.waveUnplayed,
    playedColor: outgoing ? AppFinish.outgoingWavePlayed : null,
    playedGradient: outgoing ? null : AppGradients.voicePlayed(colors, palette),
    continuousProgress: true,
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

  /// The 2 px keyboard-focus ring. `null` takes [AppPalette.focus].
  final Color? focusRing;

  /// The R14 voice bead's tone, or `null` for the legacy control (the icon
  /// box / bordered disc drawn from [controlFill], [controlBorderColor],
  /// [iconSize] and [progressIndicator]). The bead spins white and retries
  /// with a white refresh glyph whatever the row's inks.
  final YoDiscTone? beadTone;

  /// The bead's diameter inside the [controlSize] box; defaults to it.
  final double? beadSize;

  /// The R13 unplayed ink for a row WITH a real position. `null` keeps the
  /// Moment player's [StoryWaveform] pair (the legacy contract).
  final Color? unplayed;

  /// A solid played ink (the outgoing bubble's white); [playedGradient]
  /// wins when both are set.
  final Color? playedColor;

  /// Pour the played run toward each real position ([VoicePourWaveform]).
  /// Read only with [unplayed].
  final bool continuousProgress;
}

/// `m:ss`, with no leading zero on the minutes and a negative length read as
/// zero. One formatter so a clip is never `0:07` in a thread and `00:07` in a
/// bubble.
String formatVoiceClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

/// The voice bead's light impact (R14) for a tap that is about to START a
/// clip — on the phones only (iOS and Android), never on the web or a
/// desktop. Every bead calls it the same way: `if (!playing)` before the
/// caller's own tap handler.
void voiceBeadStartHaptic() {
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (mobile) unawaited(HapticFeedback.lightImpact());
}

/// A play / pause transport drawn as the R14 voice bead, for surfaces that
/// already expose their transport as an [IconButton] (the Głos feed card's
/// 48 px bead, the wide detail panel's 54): the keyed widget stays that
/// [IconButton] — its `onPressed`, `tooltip`, focus and semantics are
/// unchanged — and only its face becomes the bead.
///
/// * lit (emitted brand light) only while [playing] — the one clip that
///   plays — and at rest otherwise;
/// * a white spinner while [busy] (which wins over a null [onPressed]), the
///   refresh glyph when [failed], a flat `surfaceMuted` disc when disabled;
/// * `YoPressFeedback` .94 on touch, hover +.06 on the contact and glow, a
///   2 px `focus` ring 3 px outside the disc;
/// * a light haptic when a tap is about to START playback, on the phones.
class VoiceBeadButton extends StatefulWidget {
  const VoiceBeadButton({
    required this.size,
    required this.playing,
    required this.onPressed,
    this.busy = false,
    this.failed = false,
    this.tooltip,
    this.buttonKey,
    this.lit,
    super.key,
  });

  final double size;
  final bool playing;

  /// `null` disables the transport.
  final VoidCallback? onPressed;
  final bool busy;
  final bool failed;
  final String? tooltip;

  /// Goes on the [IconButton], where the surface's finders look for it.
  final Key? buttonKey;

  /// Whether the bead emits light; defaults to [playing].
  final bool? lit;

  @override
  State<VoiceBeadButton> createState() => _VoiceBeadButtonState();
}

class _VoiceBeadButtonState extends State<VoiceBeadButton> {
  final WidgetStatesController _states = WidgetStatesController();
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
  }

  void _statesChanged() {
    if (!mounted) return;
    final hovered = _states.value.contains(WidgetState.hovered);
    final focused = _states.value.contains(WidgetState.focused);
    if (hovered == _hovered && focused == _focused) return;
    // States can be reported while the button builds; defer to the next
    // frame in that case.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _statesChanged());
      return;
    }
    setState(() {
      _hovered = hovered;
      _focused = focused;
    });
  }

  @override
  void dispose() {
    _states
      ..removeListener(_statesChanged)
      ..dispose();
    super.dispose();
  }

  VoidCallback? get _onPressed {
    final onPressed = widget.onPressed;
    if (onPressed == null) return null;
    return () {
      if (!widget.playing) voiceBeadStartHaptic();
      onPressed();
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final status = widget.busy
        ? YoDiscStatus.busy
        : widget.failed
        ? YoDiscStatus.failed
        : enabled
        ? YoDiscStatus.idle
        : YoDiscStatus.disabled;
    final size = widget.size;
    return YoPressFeedback(
      scale: YoPressFeedback.disc,
      enabled: enabled,
      child: IconButton(
        key: widget.buttonKey,
        onPressed: _onPressed,
        tooltip: widget.tooltip,
        statesController: _states,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(Size.square(size)),
          shape: const WidgetStatePropertyAll(CircleBorder()),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          // The bead carries hover, press and focus itself.
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
        icon: YoGradientDisc(
          size: size,
          emphasis: (widget.lit ?? widget.playing) && enabled
              ? YoDiscEmphasis.lit
              : YoDiscEmphasis.rest,
          gloss: true,
          status: status,
          hovered: _hovered && enabled,
          focused: _focused,
          nudgePlay: !widget.playing,
          glyph: VoiceBeadGlyph(playing: widget.playing),
        ),
      ),
    );
  }
}

/// W3's lit block: the R2 content block that holds a voice clip, lit only
/// while that clip is actually playing (refine-look §5 W3, the feed's and
/// the detail's "playing card").
///
/// * **At rest** — the R2 finish: the top-lit `blockGradient`, a 1 px
///   `hairline` edge (`hairlineHover` under a pointer), Pearl's lift on the
///   outside so the clip never cuts it, radius [radius].
/// * **Lit** — the edge turns `AppColors.primary` @ .45 Dark / .35 Pearl
///   and the block gains the R3 corner tint in the same primary. Light
///   comes in over 180 ms and leaves over 320 ms; under Reduce Motion,
///   accessible navigation or a paused ticker it switches instantly.
///   Nothing moves: the edge is painted as a foreground and the tint sits
///   under the ink, so lighting a block never shifts a pixel of layout.
/// * **High contrast** — a flat `surface` with a `borderStrong` edge; lit
///   is a 1.5 px `interactiveForeground` edge and no tint.
/// * **Focused** (R2) — a 2 px `palette.focus` ring at the block's radius,
///   painted as a foreground over the edge in every mode, so a keyboard
///   user sees which card Enter opens and nothing moves. The ring's box is
///   always in the tree (transparent when unfocused): a wrapper that came
///   and went would re-parent the content and drop its focus node.
///
/// The caller decides [lit] from a notifier that changes only on play,
/// pause or a switch of clip — never from position ticks — and passes the
/// block's content as [child], so lighting rebuilds this shell only.
class VoiceLitBlock extends StatelessWidget {
  const VoiceLitBlock({
    required this.lit,
    required this.child,
    this.hovered = false,
    this.focused = false,
    this.radius = AppRadius.block,
    this.edgeKey,
    super.key,
  });

  final bool lit;
  final bool hovered;

  /// Keyboard focus is on the block's own target (the caller tracks it).
  final bool focused;
  final BorderRadius radius;
  final Widget child;

  /// Goes on the box that paints the edge, so a test can read it.
  final Key? edgeKey;

  static const Duration litIn = YoGradientDisc.litIn;
  static const Duration litOut = YoGradientDisc.litOut;

  /// The corner tint's [Opacity], so a test can read how lit a block is.
  @visibleForTesting
  static const Key tintKey = ValueKey<String>('voice-lit-block-tint');

  /// The box that paints the focus ring, so a test can read it.
  @visibleForTesting
  static const Key focusRingKey = ValueKey<String>('voice-lit-block-focus');

  /// The focus ring's width.
  static const double focusRingWidth = 2;

  /// The lit edge colour for [palette].
  static Color litEdge(AppPalette palette) =>
      AppColors.primary.withValues(alpha: palette.isDark ? .45 : .35);

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final duration = AppMotion.decorative(context)
        ? (lit ? litIn : litOut)
        : Duration.zero;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: lit ? 1 : 0),
      duration: duration,
      curve: AppMotion.standardCurve,
      child: child,
      builder: (context, t, content) {
        final Border edge;
        if (highContrast) {
          edge = t > 0
              ? Border.all(color: palette.interactiveForeground, width: 1.5)
              : Border.all(color: palette.borderStrong);
        } else {
          final rest = hovered ? palette.hairlineHover : palette.hairline;
          edge = Border.all(color: Color.lerp(rest, litEdge(palette), t)!);
        }
        return DecoratedBox(
          // Pearl's lift outside the clip, so it is never cut.
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: AppFinish.blockShadows(
              palette,
              hovered: hovered,
              highContrast: highContrast,
            ),
          ),
          child: DecoratedBox(
            key: focusRingKey,
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: focused ? palette.focus : Colors.transparent,
                width: focusRingWidth,
              ),
            ),
            child: DecoratedBox(
              key: edgeKey,
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(borderRadius: radius, border: edge),
              child: ClipRRect(
                borderRadius: radius,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Keep `color` null behind the gradient (see yo_button.dart).
                    color: highContrast ? palette.surface : null,
                    gradient: highContrast ? null : palette.blockGradient,
                  ),
                  // The tint is always in the tree (at opacity 0 at rest), so
                  // lighting the block never changes the structure above the
                  // content — its focus nodes and ink stay where they are.
                  child: Stack(
                    children: [
                      if (!highContrast)
                        PositionedDirectional(
                          top: AppFinish.cornerTintTop,
                          end: AppFinish.cornerTintEnd,
                          width: AppFinish.cornerTintSize,
                          height: AppFinish.cornerTintSize,
                          child: IgnorePointer(
                            child: Opacity(
                              key: tintKey,
                              opacity: t.clamp(0.0, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppFinish.cornerTint(
                                    AppColors.primary,
                                    palette,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      content!,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

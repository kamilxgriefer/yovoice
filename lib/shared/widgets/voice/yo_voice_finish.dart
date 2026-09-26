import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';

/// The voice bead's glyph (refine-look R14, amended by the B5 review).
///
/// R14 sized the glyph at .42 of the bead, but the play, pause and refresh
/// glyphs are Material icons that carry about a fifth of their box as
/// padding: at 48 px the triangle shrank to ≈ 9 × 10 px against build 36's
/// ≈ 10 × 12 and read as a small dot on a big sphere. Every bead site
/// before this pass drew its glyph at half the disc (24 in 48, 22 in 44,
/// 20 in 40, 32 in 64), so the bead keeps that proportion at every size,
/// never below the primitive's 18 px floor.
abstract final class YoVoiceBead {
  /// Glyph size as a share of the bead's diameter.
  static const double glyphRatio = .5;

  /// The glyph size for a bead of [diameter] px.
  static double glyphSize(double diameter) =>
      math.max(18, diameter * glyphRatio);
}

/// The pour of a voice waveform (refine-look R13, W3): the played run moves
/// smoothly between two REAL position events instead of jumping a bar at a
/// time.
///
/// The player reports its position about every 200 ms. Each report becomes a
/// linear tween of [step] from the value on screen to the reported one, so
/// what is drawn always lies between two positions the player actually
/// reported — it interpolates, it never extrapolates past the last report.
/// A report that is not the next small step forward is a seek, a restart or
/// a new clip, and it SNAPS: backwards, a jump of more than [seekThreshold]
/// of audio, the first value, `null` (no position source) or an unknown
/// length. Under Reduce Motion, accessible navigation or a paused
/// [TickerMode] ([AppMotion.decorative]) every report snaps, so the pour
/// only ever moves on a real position event.
///
/// It animates nothing else: bar heights, colours and the widget the
/// [builder] returns (a `YoWaveform` with `continuousProgress`) are the
/// caller's. Nothing ticks while no report is arriving.
class YoVoicePour extends StatefulWidget {
  const YoVoicePour({
    required this.progress,
    required this.total,
    required this.builder,
    super.key,
  });

  /// The player's REAL reported position as a fraction 0..1, or `null` for
  /// a still silhouette.
  final double? progress;

  /// The clip's length: what tells a playhead step from a seek.
  final Duration total;

  /// Builds the waveform for the value to draw now.
  final Widget Function(BuildContext context, double? progress) builder;

  /// One position interval of the player.
  static const Duration step = Duration(milliseconds: 200);

  /// A forward move longer than this (in audio) is a seek, not a step.
  static const Duration seekThreshold = Duration(milliseconds: 600);

  @override
  State<YoVoicePour> createState() => _YoVoicePourState();
}

class _YoVoicePourState extends State<YoVoicePour>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tween = AnimationController(
    vsync: this,
    duration: YoVoicePour.step,
    value: 1,
  );
  double? _from;
  double? _to;

  double? get _shown {
    final to = _to;
    final from = _from;
    if (to == null || from == null) return to;
    return lerpDouble(from, to, _tween.value);
  }

  @override
  void initState() {
    super.initState();
    _from = widget.progress;
    _to = widget.progress;
  }

  @override
  void didUpdateWidget(YoVoicePour oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) _retarget(widget.progress);
  }

  void _retarget(double? next) {
    final shown = _shown;
    if (next == null ||
        shown == null ||
        !AppMotion.decorative(context) ||
        !_isStep(shown, next)) {
      _tween.stop();
      _from = next;
      _to = next;
      _tween.value = 1;
      return;
    }
    _from = shown;
    _to = next;
    _tween.forward(from: 0);
  }

  bool _isStep(double from, double to) {
    final delta = to - from;
    if (delta <= 0) return false;
    final totalMs = widget.total.inMilliseconds;
    if (totalMs <= 0) return false;
    return delta * totalMs <= YoVoicePour.seekThreshold.inMilliseconds;
  }

  @override
  void dispose() {
    _tween.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _tween,
    builder: (context, _) => widget.builder(context, _shown),
  );
}

/// The R2 block of a clip that can play (refine-look W3: "in any feed or
/// thread, exactly one thing glows — the clip that is playing").
///
/// At rest it is exactly the block finish: `blockGradient` fill, a 1 px
/// `hairline` painted as a foreground, radius [AppRadius.block], Pearl's
/// shadow pair on the OUTER box. While [lit] — only while this block's own
/// voice really plays — the edge turns [AppColors.primary] @ .45 (Dark) /
/// .35 (Pearl) and the R3 corner tint of [tint] fades in: in over 180 ms,
/// out over 320 ms, instantly when motion is off. Nothing moves: the edge
/// is a foreground and the tint sits inside the clip under the ink, so
/// lighting a block never shifts a pixel of layout.
///
/// [hovered] moves the edge to `hairlineHover` and sinks Pearl's drop;
/// [focused] paints the 2 px `focus` ring. Under high contrast the block is
/// flat `surface` with a `borderStrong` edge and no tint; a lit block then
/// carries a 1.5 px `textPrimary` edge instead of any light — NOT
/// `interactiveForeground`, which is the same violet as `focus` in both
/// themes, so a playing card and a keyboard-focused one would differ by
/// half a pixel of width (the B5 review, A11Y-B5-03; a spec amendment to
/// W3).
///
/// The light, edge and hover transitions are decorative motion: they snap
/// under Reduce Motion, accessible navigation or a paused [TickerMode]
/// ([AppMotion.decorative], spec §5).
///
/// The child is laid on a transparent [Material] inside the clip, so an
/// `InkWell` in it paints its washes under the edge and inside the radius.
/// Hand the block a child that is built ONCE per card build: a lit change
/// then rebuilds this finish and never the card's content.
class YoVoiceBlock extends StatefulWidget {
  const YoVoiceBlock({
    required this.child,
    this.lit = false,
    this.hovered = false,
    this.focused = false,
    this.radius = AppRadius.block,
    this.tint = AppColors.primary,
    super.key,
  });

  final Widget child;

  /// True only while this block's own clip is playing.
  final bool lit;
  final bool hovered;
  final bool focused;
  final BorderRadius radius;

  /// The hue of the corner light while [lit].
  final Color tint;

  /// The lit edge's alpha on each side.
  static double litEdgeAlpha(AppPalette palette) => palette.isDark ? .45 : .35;

  /// The block's edge for these states (see the class doc).
  static Border edgeFor(
    AppPalette palette, {
    required bool lit,
    bool hovered = false,
    bool focused = false,
    bool highContrast = false,
  }) {
    if (focused) return Border.all(color: palette.focus, width: 2);
    if (lit && highContrast) {
      return Border.all(color: palette.textPrimary, width: 1.5);
    }
    if (lit) {
      return Border.all(
        color: AppColors.primary.withValues(alpha: litEdgeAlpha(palette)),
      );
    }
    return AppFinish.blockEdge(
      palette,
      hovered: hovered,
      highContrast: highContrast,
    );
  }

  @override
  State<YoVoiceBlock> createState() => _YoVoiceBlockState();
}

class _YoVoiceBlockState extends State<YoVoiceBlock> {
  // A change of light fades at the lit timings; hover and focus at the quick
  // block timing.
  bool _litChanged = false;

  @override
  void didUpdateWidget(YoVoiceBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _litChanged = oldWidget.lit != widget.lit;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final lit = widget.lit;
    final animate = AppMotion.decorative(context);
    final lightDuration = !animate
        ? Duration.zero
        : lit
        ? YoGradientDisc.litIn
        : YoGradientDisc.litOut;
    final quick = animate ? AppMotion.quick : Duration.zero;
    final fill = AppFinish.blockFill(
      palette,
      radius: widget.radius,
      hovered: widget.hovered,
      highContrast: highContrast,
    );
    final edge = YoVoiceBlock.edgeFor(
      palette,
      lit: lit,
      hovered: widget.hovered,
      focused: widget.focused,
      highContrast: highContrast,
    );

    return Stack(
      fit: StackFit.passthrough,
      children: [
        AnimatedContainer(
          duration: quick,
          curve: AppMotion.standardCurve,
          decoration: fill,
          child: ClipRRect(
            borderRadius: widget.radius,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (!highContrast)
                  PositionedDirectional(
                    top: AppFinish.cornerTintTop,
                    end: AppFinish.cornerTintEnd,
                    width: AppFinish.cornerTintSize,
                    height: AppFinish.cornerTintSize,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: lit ? 1 : 0,
                        duration: lightDuration,
                        curve: AppMotion.standardCurve,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppFinish.cornerTint(
                              widget.tint,
                              palette,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Material(type: MaterialType.transparency, child: widget.child),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: _litChanged ? lightDuration : quick,
              curve: AppMotion.standardCurve,
              decoration: BoxDecoration(
                borderRadius: widget.radius,
                border: edge,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

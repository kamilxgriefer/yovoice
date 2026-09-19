import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

/// The one bar waveform (Slim redesign, phase 0, ADR-209).
///
/// Every row of rounded bars that stands for audio in the app is this widget:
/// the Start hero's motif, the play rows of Voice Moments and voice messages,
/// the story stage, the Moment detail transport and the podcast stage's
/// speaking mark. The rule it enforces is the product's honesty rule: **a
/// waveform without real amplitude is static and never pretends to be live
/// audio.** No per-Moment amplitude is recorded anywhere, so the bar shape is
/// always a fixed [silhouette] — decoration, not data — and the widget owns no
/// `AnimationController`, no `Timer` and no randomness. The only thing it ever
/// draws from a real value is the played run: when [progress] is non-null it
/// is the player's reported position (0..1) and the bars behind the playhead
/// take [playedColor] or [playedGradient]. A caller without a position source
/// passes no [progress] and gets a still silhouette; it must never derive a
/// fake one. Real amplitude meters (`RoomEnergyWave`, the recorder's level
/// meter, `VoiceCore`) are a different state and are not this widget.
///
/// Two layouts, one painter:
///
/// * **flex** ([barWidth] null): [barCount] bars (default the silhouette's
///   length) share the width, each centred in its slot with [barGap] between
///   them — what a `Row` of `Expanded` containers used to draw.
/// * **tiled** ([barWidth] set): bars at the fixed pitch `barWidth + barGap`,
///   as many as fit, the run centred so a leftover fraction of a pitch never
///   leaves one side heavier, cycling the silhouette.
///
/// Both read from the leading edge (mirrored under RTL, played edge included),
/// paint a bar as played only once `(index + 0.5) / count <= progress` so the
/// fill advances one whole bar at a time, and size exactly to [height] and
/// [width] with no padding of their own (tests measure the box). The widget
/// is excluded from semantics — it says nothing a reader needs; a caller that
/// wants a label wraps it in `Semantics` — and carries no key of its own, so
/// marker keys pass through `key:`. The caller also keeps every colour choice
/// (a palette role, an `AppColors` constant or an identity visual), the
/// play/pause state machine, the seek gesture and any slider overlay.
class YoWaveform extends StatelessWidget {
  const YoWaveform({
    required this.color,
    this.progress,
    this.playedColor = AppColors.secondary,
    this.playedGradient,
    this.silhouette = bars,
    this.height = 24,
    this.width,
    this.barWidth,
    this.barCount,
    this.barGap = 3,
    this.barRadius,
    super.key,
  });

  /// The idle (unplayed) bar colour. Callers derive it from a palette role
  /// (`palette.interactiveForeground`), an `AppColors` constant at an alpha
  /// (`AppColors.primary.withValues(alpha: .32)`) or an identity visual.
  final Color color;

  /// `null` = a static silhouette (the honest default). Otherwise the REAL
  /// playback position, 0..1, painted as a played run from the leading edge.
  final double? progress;

  /// Solid played colour; read only while [progress] is non-null and
  /// [playedGradient] is null.
  final Color playedColor;

  /// When set, the played bars are painted with this gradient swept across the
  /// PLAYED width (the palette's `audioProgressGradient`); wins over
  /// [playedColor].
  final LinearGradient? playedGradient;

  /// Bar heights as fractions 0..1 of [height]; cycled when there are more
  /// bars than entries. Defaults to [bars], the 30-entry story silhouette.
  final List<double> silhouette;

  /// Exact box height; the bars are centred vertically inside it.
  final double height;

  /// Exact box width, or `null` to fill the parent. Intrinsic hosts (a
  /// `Stack`, a `Row` without `Expanded`) must pass one.
  final double? width;

  /// Fixed bar width = tiled layout. `null` = flex layout.
  final double? barWidth;

  /// Flex layout only: how many bars share the width (default
  /// `silhouette.length`).
  final int? barCount;

  /// Gap between bars: the slot's spare space in flex, part of the pitch in
  /// tiled.
  final double barGap;

  /// Corner radius; default half the bar width (flex) or 2 (tiled). Always
  /// clamped to a pill so an oversized radius cannot distort a bar.
  final double? barRadius;

  /// The 30-entry story silhouette: one source for every decorative waveform.
  static const bars = <double>[
    .3,
    .55,
    .4,
    .75,
    .5,
    .85,
    .45,
    .6,
    .35,
    .7,
    .5,
    .9,
    .4,
    .65,
    .3,
    .55,
    .8,
    .45,
    .6,
    .35,
    .5,
    .7,
    .4,
    .85,
    .55,
    .3,
    .65,
    .5,
    .75,
    .4,
  ];

  /// The deterministic Start ramp `(10 + (i * 13) % 24) / 34` the Home hero
  /// and the legacy Home Moment row draw, for any bar count.
  static List<double> ramp(int count) => List<double>.generate(
    count,
    (index) => (10 + (index * 13) % 24) / 34,
    growable: false,
  );

  @override
  Widget build(BuildContext context) {
    final box = RepaintBoundary(
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: CustomPaint(
          painter: _YoWaveformPainter(
            color: color,
            progress: progress?.clamp(0.0, 1.0),
            playedColor: playedColor,
            playedGradient: playedGradient,
            silhouette: silhouette,
            barWidth: barWidth,
            barCount: barCount,
            barGap: barGap,
            barRadius: barRadius,
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      // An explicit width is a promise about the run (five bars at 30 px, a
      // motif as wide as a portrait); a parent that forces a wider box gets
      // the same run centred instead of extra bars.
      child: width == null
          ? box
          : Center(widthFactor: 1, heightFactor: 1, child: box),
    );
  }
}

class _YoWaveformPainter extends CustomPainter {
  const _YoWaveformPainter({
    required this.color,
    required this.progress,
    required this.playedColor,
    required this.playedGradient,
    required this.silhouette,
    required this.barWidth,
    required this.barCount,
    required this.barGap,
    required this.barRadius,
    required this.textDirection,
  });

  final Color color;
  final double? progress;
  final Color playedColor;
  final LinearGradient? playedGradient;
  final List<double> silhouette;
  final double? barWidth;
  final int? barCount;
  final double barGap;
  final double? barRadius;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (silhouette.isEmpty || size.width <= 0 || size.height <= 0) return;
    final int count;
    final double pitch;
    final double bar;
    final double defaultRadius;
    final fixedBarWidth = barWidth;
    if (fixedBarWidth != null) {
      pitch = fixedBarWidth + barGap;
      if (pitch <= 0) return;
      count = (size.width / pitch).floor();
      bar = fixedBarWidth;
      defaultRadius = 2;
    } else {
      count = barCount ?? silhouette.length;
      if (count <= 0) return;
      pitch = size.width / count;
      bar = pitch - barGap;
      defaultRadius = bar / 2;
    }
    if (count <= 0 || bar <= 0) return;
    final runWidth = count * pitch - barGap;
    final start = (size.width - runWidth) / 2;
    final rtl = textDirection == TextDirection.rtl;
    final playedFraction = progress;
    final playedWidth = playedFraction == null ? 0.0 : runWidth * playedFraction;
    final playedRect = rtl
        ? Rect.fromLTWH(
            start + runWidth - playedWidth,
            0,
            playedWidth,
            size.height,
          )
        : Rect.fromLTWH(start, 0, playedWidth, size.height);
    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final gradient = playedGradient;
    if (gradient != null && playedWidth > 0) {
      playedPaint.shader = LinearGradient(
        begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
        end: rtl ? Alignment.centerLeft : Alignment.centerRight,
        colors: gradient.colors,
        stops: gradient.stops,
      ).createShader(playedRect);
    }
    final idlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radius = barRadius ?? defaultRadius;
    for (var i = 0; i < count; i++) {
      final logical = rtl ? count - 1 - i : i;
      final amplitude = silhouette[logical % silhouette.length].clamp(0.0, 1.0);
      final barHeight = size.height * amplitude;
      final rect = Rect.fromLTWH(
        start + i * pitch,
        (size.height - barHeight) / 2,
        bar,
        barHeight,
      );
      // A bar is played once its leading edge is behind the playhead, so the
      // fill advances one bar at a time and never paints a half bar.
      final played =
          playedFraction != null && (logical + 0.5) / count <= playedFraction;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(radius, math.min(bar, barHeight) / 2)),
        ),
        played ? playedPaint : idlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_YoWaveformPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.playedGradient != playedGradient ||
      !listEquals(oldDelegate.silhouette, silhouette) ||
      oldDelegate.barWidth != barWidth ||
      oldDelegate.barCount != barCount ||
      oldDelegate.barGap != barGap ||
      oldDelegate.barRadius != barRadius ||
      oldDelegate.textDirection != textDirection;
}

/// The Moment player's waveform: [YoWaveform] with a REAL [progress] (the
/// player's reported position), `AppColors.secondary` played bars and the
/// quiet `AppColors.primary` wash for the rest, in both themes.
///
/// Kept as a named subclass rather than a call-site rename because the
/// position contract is pinned by type: `test/moment_position_single_source_test.dart`
/// and `test/moment_feed_card_redesign_test.dart` find it with
/// `find.byType(StoryWaveform)` and read `progress`, `barWidth`, `barGap` and
/// `playedGradient`. `moment_story_viewer.dart` re-exports it so every
/// existing import keeps resolving. Defaults are the story stage's: 44 px,
/// flex layout, gap 3, radius 2.
class StoryWaveform extends YoWaveform {
  StoryWaveform({
    required double progress,
    double height = 44,
    LinearGradient? playedGradient,
    double? barWidth,
    double barGap = 3,
    double barRadius = 2,
    Key? key,
  }) : super(
         color: unplayedColor(),
         progress: progress,
         playedColor: AppColors.secondary,
         playedGradient: playedGradient,
         height: height,
         barWidth: barWidth,
         barGap: barGap,
         barRadius: barRadius,
         key: key,
       );

  /// Always the player's position here; never null.
  @override
  double get progress => super.progress!;

  /// The 30-entry silhouette every Moment player shares.
  static const bars = YoWaveform.bars;

  /// The unplayed silhouette colour in both themes.
  static Color unplayedColor() => AppColors.primary.withValues(alpha: .32);
}

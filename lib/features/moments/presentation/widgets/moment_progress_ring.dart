import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// The listening progress of ONE recording, drawn as a ring around the
/// author's avatar with the percentage under it.
///
/// The arc is the player's position divided by the recording's duration and
/// nothing else. It is **not** a presence, live or "listening now" signal —
/// YO Voice has no server-side listener counter and this ring must never be
/// read as one: no red, no pulse, no animation of its own. It repaints from
/// the same position value the waveform, the slider and the time labels
/// read, under a [RepaintBoundary], so a position tick never rebuilds the
/// page around it.
///
/// A clock is not mirrored: in RTL the arc still starts at twelve o'clock
/// and still runs clockwise.
class MomentProgressRing extends StatelessWidget {
  const MomentProgressRing({
    required this.progress,
    required this.child,
    this.avatarDiameter = expandedAvatar,
    this.strokeWidth = stroke,
    super.key,
  });

  /// 0…1. Values outside are clamped rather than refused: a late position
  /// tick must not throw on a screen that is already showing the end.
  final double progress;

  /// The avatar (or any identity mark) the ring is drawn around.
  final Widget child;

  final double avatarDiameter;
  final double strokeWidth;

  /// Board 07: avatar 120 with a 6-px ring at ≥ 600, 96 below it.
  static const double expandedAvatar = 120;
  static const double compactAvatar = 96;
  static const double stroke = 6;

  /// The dark breath between the avatar and the ring.
  static const double gap = 4;

  /// Twelve o'clock. A clock is not mirrored, so this is the start angle in
  /// every reading direction — RTL included.
  static const double startAngle = -math.pi / 2;

  /// The played arc, clockwise. Clamped rather than asserted: a late
  /// position tick must not throw on a screen already showing the end.
  static double sweepFor(double progress) =>
      2 * math.pi * progress.clamp(0.0, 1.0);

  double get diameter => avatarDiameter + 2 * (gap + strokeWidth);

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final media = MediaQuery.maybeOf(context);
    // The "controlled glow" is decoration: it is dropped under Reduce
    // Motion and in high contrast, where the arc alone must carry the
    // value (it does — length plus the printed percentage).
    final glow =
        !(media?.disableAnimations ?? false) && !(media?.highContrast ?? false);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: diameter,
        child: CustomPaint(
          painter: _MomentProgressRingPainter(
            progress: progress.clamp(0.0, 1.0),
            strokeWidth: strokeWidth,
            playedColors: <Color>[
              palette.audioAccent,
              palette.interactiveForeground,
            ],
            trackColor: AppColors.primary.withValues(alpha: .32),
            glowColor: glow ? palette.audioAccent.withValues(alpha: .35) : null,
          ),
          child: Center(
            child: SizedBox.square(dimension: avatarDiameter, child: child),
          ),
        ),
      ),
    );
  }
}

class _MomentProgressRingPainter extends CustomPainter {
  const _MomentProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.playedColors,
    required this.trackColor,
    required this.glowColor,
  });

  final double progress;
  final double strokeWidth;
  final List<Color> playedColors;
  final Color trackColor;
  final Color? glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    if (progress <= 0) return;
    const start = MomentProgressRing.startAngle;
    final sweep = MomentProgressRing.sweepFor(progress);
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: playedColors,
      transform: const GradientRotation(start),
    ).createShader(rect);

    final glow = glowColor;
    if (glow != null) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_MomentProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.glowColor != glowColor ||
      !listEquals(oldDelegate.playedColors, playedColors);
}

/// The hero lockup of board 07: the progress ring around the author's
/// avatar with the percentage printed under it.
///
/// The percentage and the ring are ONE announcement ("Listening progress,
/// 40 %"); the printed number is excluded from semantics so a screen reader
/// does not read it twice.
class MomentListeningProgress extends StatelessWidget {
  const MomentListeningProgress({
    required this.progress,
    required this.avatar,
    this.compact = false,
    super.key,
  });

  final double progress;
  final Widget avatar;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final clamped = progress.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();
    final percentText = copy.template(
      '{percent}%',
      '{percent} %',
      values: <String, Object>{'percent': percent},
    );
    return Semantics(
      label: copy.text('Listening progress', 'Postęp odsłuchu'),
      value: percentText,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MomentProgressRing(
              progress: clamped,
              avatarDiameter: compact
                  ? MomentProgressRing.compactAvatar
                  : MomentProgressRing.expandedAvatar,
              child: avatar,
            ),
            const SizedBox(height: AppRhythm.tight),
            Text(
              percentText,
              key: const ValueKey('moment-detail-progress-percent'),
              maxLines: 1,
              style: AppTypography.labelLarge.copyWith(
                color: palette.audioAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

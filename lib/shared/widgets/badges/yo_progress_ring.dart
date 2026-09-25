import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small determinate ring (refine-look R12): round caps, starting at 12
/// o'clock and running clockwise.
///
/// Draw-only and excluded from semantics — the caller's text carries the
/// value ("23 godz."). Used by the Moment expiry pill (14 px, stroke 2,
/// track `border`, arc `interactiveForeground`, `warningForeground` only
/// under one hour). `MomentProgressRing` (the listening ring) is a
/// different widget and is unchanged.
class YoProgressRing extends StatelessWidget {
  const YoProgressRing({
    required this.value,
    required this.trackColor,
    required this.arcColor,
    this.size = 14,
    this.stroke = 2,
    super.key,
  });

  /// 0..1; clamped.
  final double value;
  final double size;
  final double stroke;
  final Color trackColor;
  final Color arcColor;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: value.clamp(0.0, 1.0),
            stroke: stroke,
            trackColor: trackColor,
            arcColor: arcColor,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.stroke,
    required this.trackColor,
    required this.arcColor,
  });

  final double value;
  final double stroke;
  final Color trackColor;
  final Color arcColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    if (rect.isEmpty) return;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawOval(rect, track);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.stroke != stroke ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor;
}

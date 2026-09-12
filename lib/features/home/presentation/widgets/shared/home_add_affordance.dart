import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The dashed outline both of Home's "add" slots wear.
///
/// A solid ring reads as a disabled avatar or an empty place tile — the one
/// place on Home where "this is a slot you can fill" has to be legible
/// without colour. The board and the visual contract (§2.2 / §2.6 / §3.3)
/// both draw it dashed with a `+`, and this is the single painter so the
/// friends rail and the places rail can never drift apart.
class HomeDashedOutline extends StatelessWidget {
  const HomeDashedOutline({
    required this.size,
    required this.color,
    required this.child,
    this.borderRadius,
    this.strokeWidth = 1.5,
    this.dashLength = 5,
    this.gapLength = 4,
    super.key,
  });

  /// The outline's width and height. Both slots are square.
  final double size;
  final Color color;

  /// Null paints a circle (the friends rail); a radius paints a rounded
  /// square (the places rail, whose tiles are rounded squares).
  final BorderRadius? borderRadius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _DashedOutlinePainter(
        color: color,
        borderRadius: borderRadius,
        strokeWidth: strokeWidth,
        dashLength: dashLength,
        gapLength: gapLength,
      ),
      child: Center(child: child),
    ),
  );
}

class _DashedOutlinePainter extends CustomPainter {
  const _DashedOutlinePainter({
    required this.color,
    required this.borderRadius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final BorderRadius? borderRadius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final radius = borderRadius;
    final path = Path();
    if (radius == null) {
      path.addOval(rect);
    } else {
      path.addRRect(radius.toRRect(rect));
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final step = dashLength + gapLength;
    for (final metric in path.computeMetrics()) {
      // Distribute the remainder across the dashes rather than leaving one
      // short dash where the outline closes on itself.
      final count = math.max(1, (metric.length / step).round());
      final span = metric.length / count;
      final dash = span * (dashLength / step);
      for (var i = 0; i < count; i++) {
        final start = i * span;
        canvas.drawPath(metric.extractPath(start, start + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.gapLength != gapLength;
}

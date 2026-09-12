import 'package:flutter/material.dart';

/// A STATIC waveform motif.
///
/// Home never joins audio and never subscribes to a room's signal, so there
/// is no amplitude to draw here and there never will be on this surface.
/// Rendering a moving waveform would claim a fact the screen does not hold,
/// which is precisely the kind of invented activity this product forbids.
/// The bar heights are a fixed deterministic pattern, the widget paints once,
/// and it is excluded from semantics because it says nothing a reader needs.
class HomeStaticWaveform extends StatelessWidget {
  const HomeStaticWaveform({
    required this.color,
    this.width = 96,
    this.height = 24,
    this.barCount = 13,
    super.key,
  });

  final Color color;
  final double width;
  final double height;
  final int barCount;

  /// The same deterministic ramp the retired Home hero drew, kept so the
  /// motif reads identically wherever it appears. Values are 0..1 of the
  /// available height.
  static double barFactor(int index) => (10 + (index * 13) % 24) / 34;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _StaticWaveformPainter(color: color, barCount: barCount),
      ),
    ),
  );
}

class _StaticWaveformPainter extends CustomPainter {
  const _StaticWaveformPainter({required this.color, required this.barCount});

  final Color color;
  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount <= 0 || size.width <= 0 || size.height <= 0) return;
    // Bars and gaps share the width so the motif keeps its proportions at
    // any size the caller asks for (96 x 24 on a phone, 160 x 40 wide).
    final slot = size.width / barCount;
    final barWidth = slot * 0.58;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var index = 0; index < barCount; index++) {
      final factor = HomeStaticWaveform.barFactor(index).clamp(0.0, 1.0);
      final barHeight = size.height * factor;
      final left = slot * index + (slot - barWidth) / 2;
      final top = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StaticWaveformPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.barCount != barCount;
}

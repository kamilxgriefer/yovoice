import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';

/// A subtle waveform driven by the REAL room audio meter
/// (`VoiceCallService.roomEnergy`, 0..1). When the room is silent the bars
/// rest flat — the wave never invents activity, it only renders the
/// energy value the audio session actually reports.
class RoomEnergyWave extends StatelessWidget {
  const RoomEnergyWave({
    required this.energy,
    required this.color,
    this.height = 26,
    super.key,
  });

  /// Already-smoothed 0..1 meter from the live audio session.
  final double energy;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      label: copy.text('Live audio level', 'Poziom dźwięku na żywo'),
      child: TweenAnimationBuilder<double>(
        // Eases between meter emissions so the bars breathe instead of
        // snapping; the TARGET is always the real value.
        tween: Tween(begin: 0, end: energy.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, value, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: _WavePainter(energy: value, color: color),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.energy, required this.color});

  final double energy;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 4.0;
    final count = math.max(1, (size.width / (barWidth + gap)).floor());
    final paint = Paint()
      ..color = color.withValues(alpha: .35 + .5 * energy)
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final mid = size.height / 2;
    for (var i = 0; i < count; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      // A fixed spatial envelope shaped by the LIVE energy value. With
      // energy 0 every bar collapses to a resting dot.
      final envelope =
          (.35 + .65 * math.sin(i * .55).abs()) *
          math.sin((i / count) * math.pi);
      final half = math.max(1.2, mid * envelope * energy);
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.energy != energy || oldDelegate.color != color;
}

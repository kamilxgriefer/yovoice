import 'package:flutter/material.dart';

/// The YO Voice centerpiece from the Rooms 2.0 mockups: a violet core
/// with concentric rings and a restrained glow around the voice symbol.
///
/// Deliberately static unless [energy] > 0 — the mockup's calm look, and
/// the product rule that nothing pretends to be live audio: pass real
/// speaking energy (0..1) where a connection exists, or leave it at 0.
class VoiceCore extends StatelessWidget {
  const VoiceCore({
    this.size = 108,
    this.energy = 0,
    this.icon = Icons.mic_none_rounded,
    super.key,
  });

  final double size;

  /// 0..1 — real audio energy only. Widens the outer glow slightly.
  final double energy;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final clamped = energy.clamp(0.0, 1.0);
    return SizedBox(
      width: size * 1.6,
      height: size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final (factor, alpha) in const [(1.6, .10), (1.3, .18)])
            Container(
              width: size * factor,
              height: size * factor,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF9D20FF).withValues(alpha: alpha),
                  width: 1.2,
                ),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB44BFF), Color(0xFF7A16D8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9D20FF)
                      .withValues(alpha: .45 + .30 * clamped),
                  blurRadius: 34 + 18 * clamped,
                  spreadRadius: 2 + 4 * clamped,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * .42),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class BroadcastBackground extends StatelessWidget {
  const BroadcastBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.42),
          radius: 1.15,
          colors: [Color(0xFF391018), Color(0xFF13070A), Color(0xFF090305)],
        ),
      ),
      child: CustomPaint(painter: BroadcastSpotlightPainter()),
    );
  }
}

class BroadcastSpotlightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x33FF314F), Color(0x00FF314F)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(size.width * .2, 0)
      ..lineTo(size.width * .46, size.height)
      ..lineTo(size.width * .58, size.height)
      ..lineTo(size.width * .78, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

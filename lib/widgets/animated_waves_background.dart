import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AnimatedWavesBackground extends StatefulWidget {
  const AnimatedWavesBackground({super.key});

  @override
  State<AnimatedWavesBackground> createState() =>
      _AnimatedWavesBackgroundState();
}

class _AnimatedWavesBackgroundState extends State<AnimatedWavesBackground>
    with TickerProviderStateMixin {
  late final AnimationController _auroraController;
  late final AnimationController _particlesController;

  @override
  void initState() {
    super.initState();

    _auroraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _auroraController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _auroraController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _MinimalAuroraPainter(
                          progress: _auroraController.value,
                        ),
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _particlesController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _SoftParticlesPainter(
                          progress: _particlesController.value,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimalAuroraPainter extends CustomPainter {
  const _MinimalAuroraPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = progress * math.pi * 2;

    _drawAuroraBlob(
      canvas: canvas,
      center: Offset(
        size.width * 0.18 + math.sin(angle) * size.width * 0.045,
        size.height * 0.22 + math.cos(angle * 0.8) * size.height * 0.035,
      ),
      width: size.width * 0.72,
      height: size.height * 0.44,
      rotation: -0.35 + math.sin(angle * 0.6) * 0.08,
      colors: const [
        Color(0x003E00A8),
        Color(0x335E12CC),
        Color(0x226A00FF),
        Color(0x00A52CFF),
      ],
      blurSigma: 76,
    );

    _drawAuroraBlob(
      canvas: canvas,
      center: Offset(
        size.width * 0.88 + math.cos(angle * 0.85) * size.width * 0.05,
        size.height * 0.36 + math.sin(angle * 0.65) * size.height * 0.045,
      ),
      width: size.width * 0.62,
      height: size.height * 0.46,
      rotation: 0.42 + math.cos(angle * 0.55) * 0.07,
      colors: const [
        Color(0x00C026FF),
        Color(0x2BC026FF),
        Color(0x287B24D1),
        Color(0x003D007A),
      ],
      blurSigma: 82,
    );

    _drawAuroraBlob(
      canvas: canvas,
      center: Offset(
        size.width * 0.48 + math.sin(angle * 0.7) * size.width * 0.055,
        size.height * 0.88 + math.cos(angle * 0.5) * size.height * 0.035,
      ),
      width: size.width * 0.92,
      height: size.height * 0.42,
      rotation: -0.08 + math.sin(angle * 0.45) * 0.05,
      colors: const [
        Color(0x000D0618),
        Color(0x1F6A00FF),
        Color(0x245A17A8),
        Color(0x000D0618),
      ],
      blurSigma: 90,
    );

    _drawCenterGlow(canvas: canvas, size: size, angle: angle);
  }

  void _drawAuroraBlob({
    required Canvas canvas,
    required Offset center,
    required double width,
    required double height,
    required double rotation,
    required List<Color> colors,
    required double blurSigma,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: height,
    );

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        math.max(width, height) * 0.52,
        colors,
        const [0.0, 0.34, 0.7, 1.0],
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..blendMode = BlendMode.screen;

    canvas.drawOval(rect, paint);
    canvas.restore();
  }

  void _drawCenterGlow({
    required Canvas canvas,
    required Size size,
    required double angle,
  }) {
    final center = Offset(
      size.width * 0.5 + math.sin(angle * 0.45) * size.width * 0.018,
      size.height * 0.23 + math.cos(angle * 0.4) * size.height * 0.012,
    );

    final radius = math.min(size.width, size.height) * 0.24;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        const [
          Color(0x226E20C9),
          Color(0x147B24D1),
          Color(0x086A00FF),
          Colors.transparent,
        ],
        const [0.0, 0.35, 0.7, 1.0],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46)
      ..blendMode = BlendMode.screen;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _MinimalAuroraPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _SoftParticlesPainter extends CustomPainter {
  const _SoftParticlesPainter({required this.progress});

  final double progress;

  static const List<_ParticleData> _particles = [
    _ParticleData(
      x: 0.08,
      y: 0.18,
      radius: 2.2,
      opacity: 0.32,
      speed: 0.8,
      phase: 0.2,
    ),
    _ParticleData(
      x: 0.19,
      y: 0.42,
      radius: 1.6,
      opacity: 0.26,
      speed: 1.1,
      phase: 1.4,
    ),
    _ParticleData(
      x: 0.31,
      y: 0.12,
      radius: 2.0,
      opacity: 0.28,
      speed: 0.7,
      phase: 2.1,
    ),
    _ParticleData(
      x: 0.43,
      y: 0.34,
      radius: 1.4,
      opacity: 0.22,
      speed: 1.0,
      phase: 0.9,
    ),
    _ParticleData(
      x: 0.58,
      y: 0.16,
      radius: 1.8,
      opacity: 0.27,
      speed: 0.85,
      phase: 2.8,
    ),
    _ParticleData(
      x: 0.71,
      y: 0.29,
      radius: 2.3,
      opacity: 0.30,
      speed: 0.65,
      phase: 1.7,
    ),
    _ParticleData(
      x: 0.84,
      y: 0.13,
      radius: 1.5,
      opacity: 0.24,
      speed: 1.15,
      phase: 0.5,
    ),
    _ParticleData(
      x: 0.92,
      y: 0.44,
      radius: 1.8,
      opacity: 0.25,
      speed: 0.9,
      phase: 2.4,
    ),
    _ParticleData(
      x: 0.13,
      y: 0.68,
      radius: 1.4,
      opacity: 0.20,
      speed: 0.75,
      phase: 1.0,
    ),
    _ParticleData(
      x: 0.28,
      y: 0.82,
      radius: 2.0,
      opacity: 0.24,
      speed: 0.95,
      phase: 2.0,
    ),
    _ParticleData(
      x: 0.52,
      y: 0.73,
      radius: 1.5,
      opacity: 0.19,
      speed: 1.2,
      phase: 0.4,
    ),
    _ParticleData(
      x: 0.69,
      y: 0.88,
      radius: 1.8,
      opacity: 0.22,
      speed: 0.8,
      phase: 1.8,
    ),
    _ParticleData(
      x: 0.87,
      y: 0.74,
      radius: 1.4,
      opacity: 0.21,
      speed: 1.05,
      phase: 2.6,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final baseAngle = progress * math.pi * 2;

    for (final particle in _particles) {
      final angle = baseAngle * particle.speed + particle.phase;

      final horizontalMovement = math.sin(angle) * 7;
      final verticalMovement = math.cos(angle * 0.85) * 9;

      final center = Offset(
        size.width * particle.x + horizontalMovement,
        size.height * particle.y + verticalMovement,
      );

      final pulse = 0.72 + ((math.sin(angle) + 1) * 0.14);
      final currentOpacity = particle.opacity * pulse;

      final glowPaint = Paint()
        ..color = const Color(
          0xFFA02BFF,
        ).withValues(alpha: currentOpacity * 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      final particlePaint = Paint()
        ..color = const Color(0xFFC05CFF).withValues(alpha: currentOpacity);

      canvas.drawCircle(center, particle.radius * 4.2, glowPaint);

      canvas.drawCircle(center, particle.radius, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoftParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ParticleData {
  const _ParticleData({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.speed,
    required this.phase,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
  final double speed;
  final double phase;
}

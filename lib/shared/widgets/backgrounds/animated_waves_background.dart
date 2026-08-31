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
  late final AnimationController _backgroundController;
  late final AnimationController _particlesController;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();

    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    )..repeat();

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final disabled =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    if (disabled == _motionDisabled) return;

    _motionDisabled = disabled;
    if (disabled) {
      _backgroundController
        ..stop()
        ..value = 0;
      _particlesController
        ..stop()
        ..value = 0;
    } else {
      _backgroundController.repeat();
      _particlesController.repeat();
    }
  }

  @override
  void dispose() {
    _backgroundController.dispose();
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
                    animation: _backgroundController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _MinimalAuroraPainter(
                          progress: _backgroundController.value,
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
        size.width * 0.08 + math.sin(angle) * size.width * 0.045,
        size.height * 0.20 + math.cos(angle) * size.height * 0.025,
      ),
      width: size.width * 0.72,
      height: size.height * 0.44,
      rotation: -0.32 + math.sin(angle) * 0.05,
      colors: const [
        Color(0x003E00A8),
        Color(0x285E12CC),
        Color(0x1C6A00FF),
        Color(0x00A52CFF),
      ],
      blurSigma: 78,
    );

    _drawAuroraBlob(
      canvas: canvas,
      center: Offset(
        size.width * 0.94 + math.cos(angle) * size.width * 0.05,
        size.height * 0.33 + math.sin(angle) * size.height * 0.035,
      ),
      width: size.width * 0.66,
      height: size.height * 0.48,
      rotation: 0.38 + math.cos(angle) * 0.05,
      colors: const [
        Color(0x00C026FF),
        Color(0x24C026FF),
        Color(0x207B24D1),
        Color(0x003D007A),
      ],
      blurSigma: 84,
    );

    _drawAuroraBlob(
      canvas: canvas,
      center: Offset(
        size.width * 0.48 + math.sin(angle * 2) * size.width * 0.035,
        size.height * 0.93 + math.cos(angle * 2) * size.height * 0.02,
      ),
      width: size.width * 0.98,
      height: size.height * 0.46,
      rotation: -0.06 + math.sin(angle * 2) * 0.035,
      colors: const [
        Color(0x000D0618),
        Color(0x186A00FF),
        Color(0x1C5A17A8),
        Color(0x000D0618),
      ],
      blurSigma: 92,
    );

    _drawLogoGlow(canvas: canvas, size: size, angle: angle);
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
        const [0.0, 0.34, 0.70, 1.0],
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..blendMode = BlendMode.screen;

    canvas.drawOval(rect, paint);
    canvas.restore();
  }

  void _drawLogoGlow({
    required Canvas canvas,
    required Size size,
    required double angle,
  }) {
    final center = Offset(
      size.width * 0.5 + math.sin(angle) * size.width * 0.012,
      size.height * 0.22 + math.cos(angle) * size.height * 0.008,
    );

    final radius = math.min(size.width, size.height) * 0.25;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        const [
          Color(0x206E20C9),
          Color(0x127B24D1),
          Color(0x076A00FF),
          Colors.transparent,
        ],
        const [0.0, 0.35, 0.70, 1.0],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48)
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
      x: 0.07,
      y: 0.18,
      radius: 1.8,
      opacity: 0.24,
      orbitX: 6,
      orbitY: 8,
      frequency: 1,
      phase: 0.20,
    ),
    _ParticleData(
      x: 0.18,
      y: 0.39,
      radius: 1.3,
      opacity: 0.19,
      orbitX: 8,
      orbitY: 5,
      frequency: 2,
      phase: 1.20,
    ),
    _ParticleData(
      x: 0.29,
      y: 0.13,
      radius: 1.7,
      opacity: 0.22,
      orbitX: 5,
      orbitY: 9,
      frequency: 1,
      phase: 2.10,
    ),
    _ParticleData(
      x: 0.41,
      y: 0.31,
      radius: 1.2,
      opacity: 0.18,
      orbitX: 7,
      orbitY: 6,
      frequency: 3,
      phase: 0.80,
    ),
    _ParticleData(
      x: 0.57,
      y: 0.15,
      radius: 1.5,
      opacity: 0.21,
      orbitX: 6,
      orbitY: 7,
      frequency: 2,
      phase: 2.70,
    ),
    _ParticleData(
      x: 0.72,
      y: 0.28,
      radius: 1.9,
      opacity: 0.24,
      orbitX: 8,
      orbitY: 6,
      frequency: 1,
      phase: 1.60,
    ),
    _ParticleData(
      x: 0.84,
      y: 0.12,
      radius: 1.3,
      opacity: 0.18,
      orbitX: 5,
      orbitY: 8,
      frequency: 3,
      phase: 0.40,
    ),
    _ParticleData(
      x: 0.93,
      y: 0.43,
      radius: 1.5,
      opacity: 0.20,
      orbitX: 7,
      orbitY: 5,
      frequency: 2,
      phase: 2.30,
    ),
    _ParticleData(
      x: 0.12,
      y: 0.68,
      radius: 1.2,
      opacity: 0.16,
      orbitX: 5,
      orbitY: 7,
      frequency: 2,
      phase: 1.00,
    ),
    _ParticleData(
      x: 0.27,
      y: 0.82,
      radius: 1.6,
      opacity: 0.19,
      orbitX: 8,
      orbitY: 6,
      frequency: 1,
      phase: 2.00,
    ),
    _ParticleData(
      x: 0.51,
      y: 0.74,
      radius: 1.2,
      opacity: 0.15,
      orbitX: 6,
      orbitY: 8,
      frequency: 3,
      phase: 0.30,
    ),
    _ParticleData(
      x: 0.69,
      y: 0.88,
      radius: 1.5,
      opacity: 0.18,
      orbitX: 7,
      orbitY: 5,
      frequency: 2,
      phase: 1.80,
    ),
    _ParticleData(
      x: 0.87,
      y: 0.73,
      radius: 1.2,
      opacity: 0.17,
      orbitX: 5,
      orbitY: 7,
      frequency: 1,
      phase: 2.60,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final baseAngle = progress * math.pi * 2;

    for (final particle in _particles) {
      final angle = (baseAngle * particle.frequency) + particle.phase;

      final center = Offset(
        size.width * particle.x + math.sin(angle) * particle.orbitX,
        size.height * particle.y + math.cos(angle) * particle.orbitY,
      );

      final pulse = 0.78 + ((math.sin(angle) + 1) * 0.11);
      final opacity = particle.opacity * pulse;

      final glowPaint = Paint()
        ..color = const Color(0xFFA02BFF).withValues(alpha: opacity * 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);

      final particlePaint = Paint()
        ..color = const Color(0xFFC05CFF).withValues(alpha: opacity);

      canvas.drawCircle(center, particle.radius * 4, glowPaint);

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
    required this.orbitX,
    required this.orbitY,
    required this.frequency,
    required this.phase,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
  final double orbitX;
  final double orbitY;
  final int frequency;
  final double phase;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

/// The single app-owned startup surface. It has no minimum duration: it is
/// visible only while Firebase Auth resolves, then the real destination
/// replaces it immediately.
class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({super.key});

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.18;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 420;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Semantics(
        liveRegion: true,
        label: 'Opening YO Voice',
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _StartupBackdrop(),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 24 : 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          final progress = reduceMotion
                              ? 0.18
                              : _controller.value;
                          return SizedBox(
                            width: compact ? 190 : 224,
                            height: compact ? 190 : 224,
                            child: CustomPaint(
                              painter: _VoiceRingsPainter(progress),
                              child: Center(child: child),
                            ),
                          );
                        },
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: compact ? 116 : 136,
                          height: compact ? 116 : 136,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 20),
                      Text(
                        'YO VOICE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 27 : 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: compact ? 8 : 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Create your space',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: compact ? 30 : 38),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => CustomPaint(
                          key: const ValueKey('startup-sound-wave'),
                          size: Size(compact ? 220 : 286, 54),
                          painter: _SoundWavePainter(
                            reduceMotion ? 0.18 : _controller.value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupBackdrop extends StatelessWidget {
  const _StartupBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color(0xFF1B0C31), AppColors.background],
          stops: [0, 0.72],
        ),
      ),
    );
  }
}

class _VoiceRingsPainter extends CustomPainter {
  const _VoiceRingsPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide * 0.31;
    for (var index = 0; index < 3; index++) {
      final local = (progress + index / 3) % 1;
      final radius = base + local * size.shortestSide * 0.18;
      final opacity = (1 - local) * 0.34;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 - local
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF7B2FF7).withValues(alpha: opacity),
            const Color(0xFFE64DFF).withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_VoiceRingsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SoundWavePainter extends CustomPainter {
  const _SoundWavePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 19;
    const barWidth = 5.0;
    final gap = (size.width - bars * barWidth) / (bars - 1);
    final centerY = size.height / 2;
    final phase = progress * math.pi * 2;

    for (var index = 0; index < bars; index++) {
      final distance = (index - (bars - 1) / 2).abs() / (bars / 2);
      final envelope = math.pow(1 - distance * 0.58, 1.7).toDouble();
      final pulse = 0.46 + 0.54 * math.sin(phase + index * 0.72).abs();
      final height = 8 + (size.height - 8) * envelope * pulse;
      final x = index * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - height / 2, barWidth, height),
        const Radius.circular(barWidth / 2),
      );
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF6D28D9), Color(0xFFE64DFF)],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_SoundWavePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

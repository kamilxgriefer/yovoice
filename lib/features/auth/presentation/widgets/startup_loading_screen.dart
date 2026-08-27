import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

@visibleForTesting
double startupRingOpacity(double localProgress) =>
    math.pow(math.sin(math.pi * localProgress), 2).toDouble() * 0.34;

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
        excludeSemantics: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _StartupBackdrop(),
            // The native launch mark is screen-centred. Keep the animated
            // Flutter mark in its own centred layer so font metrics, text
            // scaling and the waveform can never shift it during hand-off.
            Center(
              child: SizedBox(
                key: const ValueKey('startup-logo-title-stage'),
                width: compact ? 250 : 300,
                height: compact ? 250 : 300,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final progress = reduceMotion
                            ? 0.18
                            : _controller.value;
                        return SizedBox.expand(
                          child: CustomPaint(
                            painter: _VoiceRingsPainter(progress),
                            child: Center(child: child),
                          ),
                        );
                      },
                      child: Image.asset(
                        'assets/images/logo.png',
                        key: const ValueKey('startup-logo'),
                        // Match the 170 pt/dp native and web launch assets at
                        // every width. Changing size on Flutter's
                        // first frame reads as a jump even when both marks
                        // share the exact same centre.
                        width: 170,
                        height: 170,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    Positioned(
                      top: compact ? 184 : 226,
                      child: Text(
                        'YO VOICE',
                        key: const ValueKey('startup-title'),
                        textAlign: TextAlign.center,
                        // A wordmark is graphic identity, not body copy. The
                        // surrounding live-region label remains available to
                        // assistive technology, while the fixed mark avoids
                        // spilling off a 320 px launch screen at 200% text.
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 27 : 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: compact ? 8 : 10,
                          shadows: const [
                            Shadow(color: Color(0xD90D0618), blurRadius: 14),
                            Shadow(color: Color(0x992B0A44), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Transform.translate(
                // Place the supporting copy directly below the independent
                // centred stage. The offset targets this column's centre.
                offset: Offset(0, compact ? 186 : 214),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 24 : 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Create your space',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: compact ? 28 : 34),
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
      // The radius wraps from large back to small at local == 1. The old
      // linear fade reset from ~0 straight to .34 on that frame, which read
      // as a pop. A sine-squared envelope is zero on BOTH sides of the wrap,
      // so the reset happens while the ring is invisible.
      final opacity = startupRingOpacity(local);
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
      final pulse = 0.56 + 0.44 * (0.5 + 0.5 * math.sin(phase + index * 0.72));
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

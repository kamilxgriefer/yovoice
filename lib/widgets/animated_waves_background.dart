import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AnimatedWavesBackground extends StatefulWidget {
  const AnimatedWavesBackground({super.key});

  @override
  State<AnimatedWavesBackground> createState() =>
      _AnimatedWavesBackgroundState();
}

class _AnimatedWavesBackgroundState extends State<AnimatedWavesBackground>
    with TickerProviderStateMixin {
  late final AnimationController _backWaveController;
  late final AnimationController _middleWaveController;
  late final AnimationController _frontWaveController;
  late final AnimationController _particlesController;

  @override
  void initState() {
    super.initState();

    _backWaveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();

    _middleWaveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();

    _frontWaveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _backWaveController.dispose();
    _middleWaveController.dispose();
    _frontWaveController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final screenWidth = constraints.maxWidth;

            /*
             * Fale zajmują tylko środkowy fragment ekranu.
             * Kończą się przed napisem OR i przyciskami społecznościowymi.
             */
            final wavesTop = screenHeight * 0.38;
            final wavesHeight = math.min(screenHeight * 0.27, 280.0);

            return ClipRect(
              child: Stack(
                children: [
                  _AnimatedParticles(controller: _particlesController),

                  Positioned(
                    left: -220,
                    right: -220,
                    top: wavesTop,
                    height: wavesHeight,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.18, 0.68, 1.0],
                        ).createShader(bounds);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _AnimatedWave(
                            controller: _backWaveController,
                            assetPath:
                                'assets/animations/welcome/wave_back.svg',
                            width: math.max(screenWidth * 1.8, 1500),
                            horizontalDistance: 26,
                            verticalDistance: 5,
                            opacity: 0.42,
                          ),

                          _AnimatedWave(
                            controller: _middleWaveController,
                            assetPath:
                                'assets/animations/welcome/wave_middle.svg',
                            width: math.max(screenWidth * 1.75, 1480),
                            horizontalDistance: -20,
                            verticalDistance: 7,
                            opacity: 0.50,
                            phaseOffset: math.pi / 2,
                          ),

                          _AnimatedWave(
                            controller: _frontWaveController,
                            assetPath:
                                'assets/animations/welcome/wave_front.svg',
                            width: math.max(screenWidth * 1.7, 1450),
                            horizontalDistance: 15,
                            verticalDistance: 4,
                            opacity: 0.60,
                            phaseOffset: math.pi,
                          ),
                        ],
                      ),
                    ),
                  ),

                  /*
                   * Subtelna poświata łącząca logo z falami.
                   */
                  Positioned(
                    top: screenHeight * 0.08,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _particlesController,
                        builder: (context, child) {
                          final pulse =
                              0.92 + (_particlesController.value * 0.08);

                          return Transform.scale(
                            scale: pulse,
                            child: Opacity(
                              opacity:
                                  0.16 + (_particlesController.value * 0.06),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          width: 260,
                          height: 260,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Color(0x668A2BE2),
                                Color(0x22C026FF),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.48, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnimatedParticles extends StatelessWidget {
  const _AnimatedParticles({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: controller,
        child: SvgPicture.asset(
          'assets/animations/welcome/particles.svg',
          fit: BoxFit.cover,
        ),
        builder: (context, child) {
          final progress = controller.value;
          final verticalOffset = math.sin(progress * math.pi * 2) * 6;

          return Transform.translate(
            offset: Offset(0, verticalOffset),
            child: Opacity(opacity: 0.38 + (progress * 0.20), child: child),
          );
        },
      ),
    );
  }
}

class _AnimatedWave extends StatelessWidget {
  const _AnimatedWave({
    required this.controller,
    required this.assetPath,
    required this.width,
    required this.horizontalDistance,
    required this.verticalDistance,
    required this.opacity,
    this.phaseOffset = 0,
  });

  final AnimationController controller;
  final String assetPath;
  final double width;
  final double horizontalDistance;
  final double verticalDistance;
  final double opacity;
  final double phaseOffset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: SvgPicture.asset(assetPath, width: width, fit: BoxFit.fitWidth),
      builder: (context, child) {
        final angle = controller.value * math.pi * 2 + phaseOffset;

        final horizontalOffset = math.sin(angle) * horizontalDistance;
        final verticalOffset = math.cos(angle) * verticalDistance;

        return Transform.translate(
          offset: Offset(horizontalOffset, verticalOffset),
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}

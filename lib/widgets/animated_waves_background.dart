import 'dart:math';

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
  late final AnimationController _slowController;
  late final AnimationController _mediumController;
  late final AnimationController _fastController;

  @override
  void initState() {
    super.initState();

    _slowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();

    _mediumController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _fastController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _slowController.dispose();
    _mediumController.dispose();
    _fastController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          SvgPicture.asset(
            "assets/animations/welcome/particles.svg",
            fit: BoxFit.cover,
          ),

          AnimatedBuilder(
            animation: _slowController,
            builder: (_, child) {
              return Transform.translate(
                offset: Offset(sin(_slowController.value * pi * 2) * 35, 0),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SvgPicture.asset(
                "assets/animations/welcome/wave_back.svg",
                width: 1700,
              ),
            ),
          ),

          AnimatedBuilder(
            animation: _mediumController,
            builder: (_, child) {
              return Transform.translate(
                offset: Offset(cos(_mediumController.value * pi * 2) * 25, -8),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SvgPicture.asset(
                "assets/animations/welcome/wave_middle.svg",
                width: 1700,
              ),
            ),
          ),

          AnimatedBuilder(
            animation: _fastController,
            builder: (_, child) {
              return Transform.translate(
                offset: Offset(sin(_fastController.value * pi * 2) * 18, -15),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SvgPicture.asset(
                "assets/animations/welcome/wave_front.svg",
                width: 1700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

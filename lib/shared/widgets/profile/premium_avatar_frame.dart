import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The canonical Premium identity treatment: a slow, subtle violet→magenta
/// halo ring around an avatar. One implementation, used everywhere a
/// premium ring appears, so the effect cannot drift per screen.
///
/// Design constraints (deliberate):
///  - subtle: thin gradient ring + soft outer glow, no gold, no crowns
///  - slow: one full sweep every 6 seconds, nothing strobing
///  - performance-conscious: a single AnimationController driving one
///    CustomPaint; the child avatar is NOT rebuilt per frame (it's passed
///    through untouched under a RepaintBoundary)
///  - accessibility: with reduced motion (MediaQuery.disableAnimations)
///    the ring renders as a static gradient — identity stays visible,
///    movement stops.
class PremiumAvatarFrame extends StatefulWidget {
  const PremiumAvatarFrame({
    required this.child,
    this.enabled = true,
    this.ringWidth = 2.5,
    this.gap = 2.0,
    super.key,
  });

  /// Typically a [UserAvatar]. Rendered unchanged when [enabled] is false.
  final Widget child;
  final bool enabled;
  final double ringWidth;

  /// Space between the avatar edge and the ring.
  final double gap;

  @override
  State<PremiumAvatarFrame> createState() => _PremiumAvatarFrameState();
}

class _PremiumAvatarFrameState extends State<PremiumAvatarFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    final inset = widget.ringWidth + widget.gap;

    return Padding(
      padding: EdgeInsets.all(inset),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            left: -inset,
            top: -inset,
            right: -inset,
            bottom: -inset,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _PremiumRingPainter(
                    progress: reduceMotion ? 0 : _controller.value,
                    ringWidth: widget.ringWidth,
                  ),
                ),
              ),
            ),
          ),
          // The avatar itself never rebuilds with the animation.
          RepaintBoundary(child: widget.child),
        ],
      ),
    );
  }
}

class _PremiumRingPainter extends CustomPainter {
  const _PremiumRingPainter({required this.progress, required this.ringWidth});

  final double progress;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - ringWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final rotation = progress * 2 * math.pi;

    // Brand violet→magenta with a soft moving highlight — the shimmer is
    // the gradient rotating, not opacity flicker.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..shader = SweepGradient(
        transform: GradientRotation(rotation),
        colors: const [
          Color(0xFF7B2FF7),
          Color(0xFFC026FF),
          Color(0xFFE879F9),
          Color(0xFF7B2FF7),
        ],
        stops: const [0.0, 0.45, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, ring);

    // Small controlled glow, fixed alpha — cheap and non-distracting.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth * 2.4
      ..color = const Color(0xFFC026FF).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius, glow);
  }

  @override
  bool shouldRepaint(_PremiumRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.ringWidth != ringWidth;
}

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// Visual states owned by the production Frame Echo Clean navigation mark.
enum YoMomentsIconState { inactive, active, pressed, disabled }

/// The YO Moments destination mark: a rounded frame with one centred play
/// symbol. It deliberately contains no waveform strokes, text or decorative
/// lines, so it stays legible at compact navigation sizes.
///
/// Hover never changes geometry. Pressed feedback is a uniform scale only,
/// which prevents the tilt/skew regression the former icon exhibited.
class YoMomentsIcon extends StatelessWidget {
  const YoMomentsIcon({
    required this.state,
    this.size = 24,
    this.color,
    this.animationDuration = const Duration(milliseconds: 160),
    super.key,
  });

  final YoMomentsIconState state;
  final double size;
  final Color? color;
  final Duration animationDuration;

  bool get _disabled => state == YoMomentsIconState.disabled;
  bool get _pressed => state == YoMomentsIconState.pressed;
  bool get _active =>
      state == YoMomentsIconState.active || state == YoMomentsIconState.pressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final resolvedColor =
        color ??
        (_active
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : palette.navigationInactive);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : animationDuration;

    return ExcludeSemantics(
      child: AnimatedOpacity(
        duration: duration,
        opacity: _disabled ? .38 : 1,
        child: AnimatedScale(
          key: const ValueKey<String>('yo-moments-frame-echo-scale'),
          duration: duration,
          curve: Curves.easeOutCubic,
          scale: _pressed ? .92 : 1,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              key: const ValueKey<String>('yo-moments-frame-echo-clean'),
              painter: FrameEchoCleanPainter(
                color: resolvedColor,
                active: _active,
                pressed: _pressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vector authority for [YoMomentsIcon]. Keeping the painter public makes the
/// exact geometry and state contract independently testable without exposing
/// navigation internals.
@immutable
class FrameEchoCleanPainter extends CustomPainter {
  const FrameEchoCleanPainter({
    required this.color,
    required this.active,
    required this.pressed,
  });

  final Color color;
  final bool active;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final shortest = size.shortestSide;
    final strokeWidth = shortest * (active ? .09 : .075);
    final frameRect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final frameRadius = Radius.circular(shortest * .27);

    if (active) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(frameRect, frameRadius),
        Paint()
          ..color = color.withValues(alpha: pressed ? .25 : .17)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, frameRadius),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final playWidth = shortest * .28;
    final playHeight = shortest * .36;
    final center = Offset(size.width / 2 + shortest * .015, size.height / 2);
    final play = Path()
      ..moveTo(center.dx - playWidth * .46, center.dy - playHeight / 2)
      ..quadraticBezierTo(
        center.dx - playWidth * .58,
        center.dy - playHeight * .43,
        center.dx - playWidth * .58,
        center.dy - playHeight * .30,
      )
      ..lineTo(center.dx - playWidth * .58, center.dy + playHeight * .30)
      ..quadraticBezierTo(
        center.dx - playWidth * .58,
        center.dy + playHeight * .43,
        center.dx - playWidth * .46,
        center.dy + playHeight / 2,
      )
      ..lineTo(center.dx + playWidth * .58, center.dy + playHeight * .08)
      ..quadraticBezierTo(
        center.dx + playWidth * .72,
        center.dy,
        center.dx + playWidth * .58,
        center.dy - playHeight * .08,
      )
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(FrameEchoCleanPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.active != active ||
      oldDelegate.pressed != pressed;
}

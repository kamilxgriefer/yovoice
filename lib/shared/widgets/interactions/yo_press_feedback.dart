import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_motion.dart';

/// A small, honest press scale around any tappable surface (refine-look §7).
///
/// It listens to raw pointers through a [Listener], so it never joins the
/// gesture arena: the child's own `InkWell` / `AccessibleTapRegion` /
/// button keeps every tap, long press, key and semantics action exactly as
/// before, and a scroll that starts on the surface is not delayed.
///
/// The scale settles in over [AppMotion.press] (90 ms) and lets go over
/// [AppMotion.release] (240 ms, [AppMotion.releaseCurve]). It is purely
/// decorative, so it is **zero** — no scale at all — under Reduce Motion,
/// accessible navigation or a paused [TickerMode] ([AppMotion.decorative]).
/// By default only touch and stylus presses scale: a mouse click on desktop
/// already has hover and pressed washes.
///
/// Scales: [block] .985 (content blocks), [tile] .97 (tiles, friend
/// bubbles), [disc] .94 (voice beads and icon discs).
class YoPressFeedback extends StatefulWidget {
  const YoPressFeedback({
    required this.child,
    this.scale = block,
    this.enabled = true,
    this.touchOnly = true,
    super.key,
  });

  static const double block = .985;
  static const double tile = .97;
  static const double disc = .94;

  final Widget child;

  /// The pressed scale (1 = none).
  final double scale;

  /// A disabled control does not react.
  final bool enabled;

  /// Only touch and stylus pointers scale (the default).
  final bool touchOnly;

  @override
  State<YoPressFeedback> createState() => _YoPressFeedbackState();
}

class _YoPressFeedbackState extends State<YoPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.press,
    reverseDuration: AppMotion.release,
  );
  // Forward eases in; the release runs easeOutBack, flipped so the
  // overshoot lands just past rest (a hair above 1) before settling.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: AppMotion.releaseCurve.flipped,
  );
  late final Animation<double> _scale = _curve.drive(
    _PressCurveTween(scaleOf: () => widget.scale),
  );
  int _pointers = 0;

  bool _accepts(PointerDownEvent event) {
    if (!widget.enabled || widget.scale == 1) return false;
    if (!widget.touchOnly) return true;
    return event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  void _down(PointerDownEvent event) {
    if (!_accepts(event) || !AppMotion.decorative(context)) return;
    _pointers++;
    _controller.forward();
  }

  void _up(PointerEvent event) {
    if (_pointers == 0) return;
    _pointers--;
    if (_pointers == 0) _controller.reverse();
  }

  @override
  void didUpdateWidget(YoPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _controller.value != 0) {
      _pointers = 0;
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion switched on mid-press: drop the scale at once.
    if (!AppMotion.decorative(context) && _controller.value != 0) {
      _controller.value = 0;
      _pointers = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// 0 → 1 of the curved controller maps to 1 → [scaleOf]; read live so a
/// rebuilt [YoPressFeedback.scale] applies to the next press.
class _PressCurveTween extends Animatable<double> {
  _PressCurveTween({required this.scaleOf});

  final double Function() scaleOf;

  @override
  double transform(double t) {
    final target = scaleOf();
    return 1 - (1 - target) * t;
  }
}

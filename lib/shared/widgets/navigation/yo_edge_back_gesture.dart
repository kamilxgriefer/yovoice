import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// Leading-edge Back for retained root tabs, which have no Navigator route to
/// pop. Pushed pages keep Flutter's native Cupertino gesture and pop guards.
/// The recognizer never enters the arena for center/dock/mouse gestures.
class YoEdgeBackGesture extends StatefulWidget {
  const YoEdgeBackGesture({
    required this.enabled,
    required this.navigationIdentity,
    required this.onBack,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Object navigationIdentity;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<YoEdgeBackGesture> createState() => _YoEdgeBackGestureState();
}

class _YoEdgeBackGestureState extends State<YoEdgeBackGesture> {
  double _distance = 0;
  bool _tracking = false;
  int? _pointer;
  Object? _startedIdentity;
  late final HorizontalDragGestureRecognizer _recognizer;
  double get _direction =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;
  bool get _available =>
      widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = (_) {
        _tracking = _available && _startedIdentity == widget.navigationIdentity;
        _distance = 0;
      }
      ..onUpdate = (details) {
        if (!_tracking || !_available) return;
        setState(
          () => _distance = math.max(
            0,
            _distance + (details.primaryDelta ?? 0) * _direction,
          ),
        );
      }
      ..onEnd = _end
      ..onCancel = _reset;
  }

  @override
  void dispose() {
    _tracking = false;
    _recognizer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(YoEdgeBackGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        oldWidget.navigationIdentity != widget.navigationIdentity) {
      _tracking = false;
      _startedIdentity = null;
      _distance = 0;
    }
  }

  void _pointerDown(PointerDownEvent event) {
    if (!_available ||
        event.kind != PointerDeviceKind.touch ||
        _pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _startedIdentity = widget.navigationIdentity;
    _recognizer.addPointer(event);
  }

  void _reset() {
    _tracking = false;
    _pointer = null;
    if (mounted) setState(() => _distance = 0);
  }

  void _end(DragEndDetails details) {
    final width = (context.findRenderObject() as RenderBox).size.width;
    final threshold = (width * .22).clamp(56.0, 100.0);
    final velocity = (details.primaryVelocity ?? 0) * _direction;
    final commit =
        _tracking &&
        _available &&
        _startedIdentity == widget.navigationIdentity &&
        velocity > -650 &&
        (_distance >= threshold || (_distance >= 24 && velocity >= 650));
    _reset();
    if (commit) widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final safe = MediaQuery.paddingOf(context);
    final leadingSafe = _direction < 0 ? safe.right : safe.left;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Like the native Cupertino detector, this translucent edge
        // listener joins the horizontal arena before underlying media,
        // while leaving taps and vertical scrolling in the child intact.
        PositionedDirectional(
          start: 0,
          width: math.max(24, leadingSafe),
          top: 0,
          bottom: 0,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _pointerDown,
            onPointerCancel: (event) {
              if (event.pointer == _pointer) _reset();
            },
          ),
        ),
        if (_distance > 0)
          PositionedDirectional(
            start: leadingSafe + 8,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Center(
                  child: Opacity(
                    opacity: (_distance / 56).clamp(0.0, 1.0),
                    child: DecoratedBox(
                      key: const ValueKey('edge-back-indicator'),
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.borderStrong),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 22,
                          color: palette.interactiveForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports actual localized overlay geometry after layout. Only stickers use
/// these insets; the media/player ancestry and its full viewport never change.
class ReelOverlayMeasure extends SingleChildRenderObjectWidget {
  const ReelOverlayMeasure({
    required this.onSize,
    required super.child,
    super.key,
  });
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureOverlay(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureOverlay renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _MeasureOverlay extends RenderProxyBox {
  _MeasureOverlay(this.onSize);
  ValueChanged<Size> onSize;
  Size? _reported;
  Size? _pending;
  bool _scheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    _pending = size;
    if (_scheduled || _reported == size) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || _pending == _reported) return;
      _reported = _pending;
      onSize(_reported!);
    });
  }
}

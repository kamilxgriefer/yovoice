import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';

/// The avatar/banner crop editor: pinch to zoom, drag to reposition,
/// fixed-frame crop with a live preview of exactly what will be visible.
///
/// Consumer-app mechanics, not developer chrome: the crop frame is fixed
/// and the IMAGE moves under it (like Instagram/WhatsApp/Discord), the
/// minimum zoom is the cover scale so the frame can never show empty
/// space, and avatars preview through a circular mask while the stored
/// asset stays a clean square. Returns the processed JPEG bytes, or null
/// on cancel.
class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({required this.image, required this.kind, super.key});

  final ui.Image image;
  final ProfileImageKind kind;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  bool _processing = false;

  ProfileImageRules get _rules => ProfileImageRules.of(widget.kind);
  bool get _isAvatar => widget.kind == ProfileImageKind.avatar;
  double get _imageWidth => widget.image.width.toDouble();
  double get _imageHeight => widget.image.height.toDouble();

  /// Smallest scale at which the image still covers the crop frame —
  /// the floor that guarantees no empty space inside the final crop.
  double _coverScale(Size viewport) {
    return [
      viewport.width / _imageWidth,
      viewport.height / _imageHeight,
    ].reduce((a, b) => a > b ? a : b);
  }

  void _resetTo(Size viewport) {
    final scale = _coverScale(viewport);
    // Center the covered image inside the frame.
    final dx = (viewport.width - _imageWidth * scale) / 2;
    final dy = (viewport.height - _imageHeight * scale) / 2;
    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      // InteractiveViewer reads getMaxScaleOnAxis(), including Z, when it
      // clamps a pinch. Keeping Z at 1 while X/Y are below 1 makes it think
      // the covered image is still at 1x; the first pinch-out then applies
      // the cover scale a second time and shrinks the photo into a corner.
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _setTransform({required double scale, required Offset translation}) {
    if (_viewport == Size.zero) return;
    final rawMinX = _viewport.width - (_imageWidth * scale);
    final rawMinY = _viewport.height - (_imageHeight * scale);
    final minX = rawMinX < 0 ? rawMinX : 0.0;
    final minY = rawMinY < 0 ? rawMinY : 0.0;
    final dx = translation.dx.clamp(minX, 0.0).toDouble();
    final dy = translation.dy.clamp(minY, 0.0).toDouble();
    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _adjustZoom(double factor) {
    if (_viewport == Size.zero) return;
    final cover = _coverScale(_viewport);
    final current = _controller.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(cover, cover * 6).toDouble();
    if ((next - current).abs() < 1e-9) return;

    // Keep the source point under the frame centre stationary while the
    // single-tap/keyboard zoom changes scale.
    final sourceAtCentre = MatrixUtils.transformPoint(
      Matrix4.inverted(_controller.value),
      _viewport.center(Offset.zero),
    );
    _setTransform(
      scale: next,
      translation: Offset(
        _viewport.width / 2 - sourceAtCentre.dx * next,
        _viewport.height / 2 - sourceAtCentre.dy * next,
      ),
    );
    if (mounted) setState(() {});
  }

  void _nudge(Offset delta) {
    if (_viewport == Size.zero) return;
    final matrix = _controller.value;
    final translation = matrix.getTranslation();
    _setTransform(
      scale: matrix.getMaxScaleOnAxis(),
      translation: Offset(translation.x, translation.y) + delta,
    );
    if (mounted) setState(() {});
  }

  Widget _cropControls() {
    final ready = _viewport != Size.zero;
    final cover = ready ? _coverScale(_viewport) : 1.0;
    final matrix = _controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final rawMinX = _viewport.width - (_imageWidth * scale);
    final rawMinY = _viewport.height - (_imageHeight * scale);
    final minX = rawMinX < 0 ? rawMinX : 0.0;
    final minY = rawMinY < 0 ? rawMinY : 0.0;
    const epsilon = .1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _CropControlButton(
          key: const ValueKey('crop-zoom-out'),
          tooltip: 'Zoom out',
          icon: Icons.remove_rounded,
          onPressed: ready && !_processing && scale > cover + epsilon
              ? () => _adjustZoom(1 / 1.2)
              : null,
        ),
        _CropControlButton(
          key: const ValueKey('crop-zoom-in'),
          tooltip: 'Zoom in',
          icon: Icons.add_rounded,
          onPressed: ready && !_processing && scale < cover * 6 - epsilon
              ? () => _adjustZoom(1.2)
              : null,
        ),
        _CropControlButton(
          key: const ValueKey('crop-move-left'),
          tooltip: 'Move photo left',
          icon: Icons.arrow_left_rounded,
          onPressed: ready && !_processing && translation.x > minX + epsilon
              ? () => _nudge(const Offset(-20, 0))
              : null,
        ),
        _CropControlButton(
          key: const ValueKey('crop-move-up'),
          tooltip: 'Move photo up',
          icon: Icons.arrow_drop_up_rounded,
          onPressed: ready && !_processing && translation.y > minY + epsilon
              ? () => _nudge(const Offset(0, -20))
              : null,
        ),
        _CropControlButton(
          key: const ValueKey('crop-move-down'),
          tooltip: 'Move photo down',
          icon: Icons.arrow_drop_down_rounded,
          onPressed: ready && !_processing && translation.y < -epsilon
              ? () => _nudge(const Offset(0, 20))
              : null,
        ),
        _CropControlButton(
          key: const ValueKey('crop-move-right'),
          tooltip: 'Move photo right',
          icon: Icons.arrow_right_rounded,
          onPressed: ready && !_processing && translation.x < -epsilon
              ? () => _nudge(const Offset(20, 0))
              : null,
        ),
      ],
    );
  }

  Future<void> _confirm() async {
    if (_processing || _viewport == Size.zero) return;
    setState(() => _processing = true);
    try {
      final sourceRect = ImageCrop.sourceRectFor(
        matrix: _controller.value,
        viewport: _viewport,
        imageSize: Size(_imageWidth, _imageHeight),
      );
      final outputWidth = _rules.maxOutputEdge;
      final outputHeight = (_rules.maxOutputEdge / _rules.aspectRatio).round();
      final bytes = await ImageCrop.renderCroppedJpeg(
        image: widget.image,
        sourceRect: sourceRect,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
      );
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } on ProfileImageException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _processing = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We couldn't process this image. Try another one."),
        ),
      );
      setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0618),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0618),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: _processing ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(_isAvatar ? 'Adjust your avatar' : 'Adjust your banner'),
        actions: [
          TextButton(
            onPressed: _processing
                ? null
                : () => setState(() => _resetTo(_viewport)),
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Fixed crop frame sized to the REAL final aspect
                    // ratio; the image moves beneath it.
                    final maxWidth = constraints.maxWidth;
                    final maxHeight = constraints.maxHeight;
                    var frameWidth = maxWidth;
                    var frameHeight = frameWidth / _rules.aspectRatio;
                    if (frameHeight > maxHeight) {
                      frameHeight = maxHeight;
                      frameWidth = frameHeight * _rules.aspectRatio;
                    }
                    final viewport = Size(frameWidth, frameHeight);
                    if (_viewport != viewport) {
                      _viewport = viewport;
                      _resetTo(viewport);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _viewport == viewport) setState(() {});
                      });
                    }
                    final cover = _coverScale(viewport);
                    final percent =
                        (_controller.value.getMaxScaleOnAxis() / cover * 100)
                            .round();

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(_isAvatar ? 0 : 22),
                      child: SizedBox(
                        width: frameWidth,
                        height: frameHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Semantics(
                              container: true,
                              label: _isAvatar
                                  ? 'Avatar crop preview'
                                  : 'Banner crop preview',
                              value: 'Zoom $percent percent',
                              child: InteractiveViewer(
                                transformationController: _controller,
                                constrained: false,
                                boundaryMargin: EdgeInsets.zero,
                                minScale: cover,
                                maxScale: cover * 6,
                                clipBehavior: Clip.hardEdge,
                                onInteractionUpdate: (_) {
                                  if (mounted) setState(() {});
                                },
                                child: SizedBox(
                                  width: _imageWidth,
                                  height: _imageHeight,
                                  child: RawImage(
                                    image: widget.image,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                            ),
                            // Avatar: circular mask preview — everything
                            // outside the circle is dimmed exactly as the
                            // app will crop it visually, while the stored
                            // square stays intact underneath.
                            if (_isAvatar)
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _CircleMaskPainter(),
                                ),
                              ),
                            IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .35),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    _isAvatar ? 0 : 22,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Crop controls',
              child: _cropControls(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Text(
              'Pinch or use controls · drag or use arrows',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .55),
                fontSize: 12.5,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processing
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3A3151)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _processing ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7B2FF7),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _processing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Use photo',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropControlButton extends StatelessWidget {
  const _CropControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        minimumSize: const Size(44, 44),
        maximumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 22),
      color: const Color(0xFFD7A8FF),
      disabledColor: const Color(0xFF62586C),
    );
  }
}

/// Dims everything outside the inscribed circle so the user sees the
/// exact final circular presentation.
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addOval(
        Rect.fromCircle(
          center: size.center(Offset.zero),
          radius: size.shortestSide / 2,
        ),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = const Color(0xB30D0618));
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: .5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

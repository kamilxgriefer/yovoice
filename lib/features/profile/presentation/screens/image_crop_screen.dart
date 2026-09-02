import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

/// The shared image crop editor: pinch to zoom, drag to reposition,
/// fixed-frame crop with a live preview of exactly what will be visible.
///
/// Consumer-app mechanics, not developer chrome: the crop frame is fixed
/// and the IMAGE moves under it (like Instagram/WhatsApp/Discord), the
/// minimum zoom is the cover scale so the frame can never show empty
/// space, and avatars preview through a circular mask while the stored
/// asset stays a clean square. Returns the processed JPEG bytes, or null
/// on cancel.
class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({
    required this.image,
    required ProfileImageKind kind,
    super.key,
  }) : _kind = kind,
       roomCover = false;

  /// Room covers have their own 21:9 composition. Keeping this as a named
  /// constructor preserves the established profile API while letting room
  /// creation/settings reuse the exact same gesture, keyboard and export
  /// pipeline without pretending a room cover is a profile banner.
  const ImageCropScreen.roomCover({required this.image, super.key})
    : _kind = null,
      roomCover = true;

  final ui.Image image;
  final ProfileImageKind? _kind;
  final bool roomCover;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  bool _processing = false;

  AppLocalizations get _copy => AppLocalizations.of(context);

  ProfileImageRules? get _profileRules =>
      widget.roomCover ? null : ProfileImageRules.of(widget._kind!);
  bool get _isAvatar => widget._kind == ProfileImageKind.avatar;
  bool get _isRoomCover => widget.roomCover;
  double get _aspectRatio => _isRoomCover ? 21 / 9 : _profileRules!.aspectRatio;
  int get _outputWidth => _isRoomCover ? 1600 : _profileRules!.maxOutputEdge;
  String get _title => switch ((widget._kind, widget.roomCover)) {
    // Keep the visual title readable beside Close and Reset on narrow phones.
    // Semantics below still announces the full room-cover task.
    (_, true) => _copy.text('Adjust cover', 'Dopasuj okładkę'),
    (ProfileImageKind.avatar, false) => _copy.text(
      'Adjust your avatar',
      'Dopasuj awatar',
    ),
    _ => _copy.text('Adjust your banner', 'Dopasuj baner'),
  };
  String get _previewLabel => switch ((widget._kind, widget.roomCover)) {
    (_, true) => _copy.text(
      'Room cover crop preview',
      'Podgląd kadru okładki pokoju',
    ),
    (ProfileImageKind.avatar, false) => _copy.text(
      'Avatar crop preview',
      'Podgląd kadru awatara',
    ),
    _ => _copy.text('Banner crop preview', 'Podgląd kadru banera'),
  };
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
    _announceCropAdjustment();
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
    _announceCropAdjustment();
  }

  String _cropSemanticValue() {
    if (_viewport == Size.zero) {
      return _copy.text('Crop preview loading', 'Ładowanie podglądu kadru');
    }
    final cover = _coverScale(_viewport);
    final scale = _controller.value.getMaxScaleOnAxis();
    final source = ImageCrop.sourceRectFor(
      matrix: _controller.value,
      viewport: _viewport,
      imageSize: Size(_imageWidth, _imageHeight),
    );
    final zoom = (scale / cover * 100).round();
    final horizontal = (source.center.dx / _imageWidth * 100).round();
    final vertical = (source.center.dy / _imageHeight * 100).round();
    return _copy.text(
      'Zoom $zoom percent. Position $horizontal percent horizontal, '
          '$vertical percent vertical.',
      'Powiększenie: $zoom procent. Pozycja: $horizontal procent w poziomie '
          'i $vertical procent w pionie.',
    );
  }

  void _announceCropAdjustment() {
    if (!mounted || _viewport == Size.zero) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        _cropSemanticValue(),
        Directionality.of(context),
      ),
    );
  }

  void _explainBlockedBack() {
    if (!_processing || !mounted) return;
    final message = _copy.text(
      'Processing cover. Please wait.',
      'Przetwarzanie okładki. Poczekaj chwilę.',
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
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

    final zoomControls = <Widget>[
      _CropControlButton(
        key: const ValueKey('crop-zoom-out'),
        tooltip: _copy.text('Zoom out', 'Pomniejsz'),
        icon: Icons.remove_rounded,
        onPressed: ready && !_processing && scale > cover + epsilon
            ? () => _adjustZoom(1 / 1.2)
            : null,
      ),
      _CropControlButton(
        key: const ValueKey('crop-zoom-in'),
        tooltip: _copy.text('Zoom in', 'Powiększ'),
        icon: Icons.add_rounded,
        onPressed: ready && !_processing && scale < cover * 6 - epsilon
            ? () => _adjustZoom(1.2)
            : null,
      ),
    ];
    final positionControls = <Widget>[
      _CropControlButton(
        key: const ValueKey('crop-move-left'),
        tooltip: _copy.text('Move photo left', 'Przesuń zdjęcie w lewo'),
        icon: Icons.arrow_left_rounded,
        onPressed: ready && !_processing && translation.x > minX + epsilon
            ? () => _nudge(const Offset(-20, 0))
            : null,
      ),
      _CropControlButton(
        key: const ValueKey('crop-move-up'),
        tooltip: _copy.text('Move photo up', 'Przesuń zdjęcie w górę'),
        icon: Icons.arrow_drop_up_rounded,
        onPressed: ready && !_processing && translation.y > minY + epsilon
            ? () => _nudge(const Offset(0, -20))
            : null,
      ),
      _CropControlButton(
        key: const ValueKey('crop-move-down'),
        tooltip: _copy.text('Move photo down', 'Przesuń zdjęcie w dół'),
        icon: Icons.arrow_drop_down_rounded,
        onPressed: ready && !_processing && translation.y < -epsilon
            ? () => _nudge(const Offset(0, 20))
            : null,
      ),
      _CropControlButton(
        key: const ValueKey('crop-move-right'),
        tooltip: _copy.text('Move photo right', 'Przesuń zdjęcie w prawo'),
        icon: Icons.arrow_right_rounded,
        onPressed: ready && !_processing && translation.x < -epsilon
            ? () => _nudge(const Offset(20, 0))
            : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBody = MediaQuery.textScalerOf(context).scale(14);
        final stackGroups = constraints.maxWidth <= 360 || scaledBody >= 21;
        final zoom = _CropControlGroup(
          semanticsLabel: _copy.text(
            'Zoom controls',
            'Sterowanie powiększeniem',
          ),
          children: zoomControls,
        );
        final position = _CropControlGroup(
          semanticsLabel: _copy.text(
            'Position controls',
            'Sterowanie położeniem',
          ),
          children: positionControls,
        );
        if (stackGroups) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [zoom, const SizedBox(height: 4), position],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [zoom, const SizedBox(width: 18), position],
        );
      },
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
      final outputWidth = _outputWidth;
      final outputHeight = (_outputWidth / _aspectRatio).round();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizedImageError(error.message))),
      );
      setState(() => _processing = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy.text(
              "We couldn't process this image. Try another one.",
              'Nie udało się przetworzyć obrazu. Wybierz inny.',
            ),
          ),
        ),
      );
      setState(() => _processing = false);
    }
  }

  String _localizedImageError(String message) {
    if (!_copy.isPolish) return message;
    if (message.contains('too large to process safely')) {
      return 'Obraz jest zbyt duży, aby bezpiecznie go przetworzyć. Wybierz inny.';
    }
    return 'Nie udało się przetworzyć obrazu. Wybierz inny.';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final content = PopScope(
      // Encoding reads the decoded native image asynchronously. System Back
      // or Escape must not dispose that image underneath the renderer; the
      // route becomes dismissible again as soon as processing finishes.
      canPop: !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _explainBlockedBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0618),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0618),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: copy.text('Cancel', 'Anuluj'),
            onPressed: _processing ? null : () => Navigator.of(context).pop(),
          ),
          title: Text(
            _title,
            semanticsLabel: _isRoomCover
                ? copy.text('Adjust room cover', 'Dopasuj okładkę pokoju')
                : null,
          ),
          actions: [
            TextButton(
              onPressed: _processing
                  ? null
                  : () => setState(() => _resetTo(_viewport)),
              child: Text(copy.text('Reset', 'Resetuj')),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, pageConstraints) => Column(
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
                        if (maxWidth <= 0 || maxHeight <= 0) {
                          return const SizedBox.shrink();
                        }
                        var frameWidth = maxWidth;
                        var frameHeight = frameWidth / _aspectRatio;
                        if (frameHeight > maxHeight) {
                          frameHeight = maxHeight;
                          frameWidth = frameHeight * _aspectRatio;
                        }
                        final viewport = Size(frameWidth, frameHeight);
                        if (_viewport != viewport) {
                          _viewport = viewport;
                          _resetTo(viewport);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _viewport == viewport) {
                              setState(() {});
                            }
                          });
                        }
                        final cover = _coverScale(viewport);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(
                            _isAvatar ? 0 : 22,
                          ),
                          child: SizedBox(
                            width: frameWidth,
                            height: frameHeight,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Semantics(
                                  container: true,
                                  label: _previewLabel,
                                  value: _cropSemanticValue(),
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
                                        color: Colors.white.withValues(
                                          alpha: .35,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        _isAvatar ? 0 : 22,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_isRoomCover)
                                  const IgnorePointer(
                                    child: _RoomCoverSafeAreaOverlay(),
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
              ConstrainedBox(
                constraints: BoxConstraints(
                  // At extreme text sizes the footer becomes independently
                  // scrollable instead of collapsing the crop frame to zero.
                  maxHeight: pageConstraints.maxHeight * .75,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Semantics(
                              container: true,
                              explicitChildNodes: true,
                              label: copy.text(
                                'Crop controls',
                                'Sterowanie kadrem',
                              ),
                              child: _cropControls(),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                            child: Text(
                              _isRoomCover
                                  ? copy.text(
                                      'Everything in the frame appears on wide covers. '
                                          'Keep faces, logos and text inside the center '
                                          'guide for compact cards.',
                                      'Cały kadr będzie widoczny na szerokich okładkach. '
                                          'Twarze, logo i tekst umieść w środkowym obszarze, '
                                          'aby pozostały widoczne na małych kartach.',
                                    )
                                  : copy.text(
                                      'Pinch or use controls · drag or use arrows',
                                      'Uszczypnij lub użyj przycisków · przeciągnij albo użyj strzałek',
                                    ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .68),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _processing
                                          ? null
                                          : () => Navigator.of(context).pop(),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: Color(0xFF3A3151),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        copy.text('Cancel', 'Anuluj'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _processing ? null : _confirm,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF7B2FF7,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: _processing
                                          ? Semantics(
                                              liveRegion: true,
                                              label: copy.text(
                                                'Processing cover. Please wait.',
                                                'Przetwarzanie okładki. Poczekaj chwilę.',
                                              ),
                                              child: ExcludeSemantics(
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Flexible(
                                                      child: Text(
                                                        copy.text(
                                                          'Processing…',
                                                          'Przetwarzanie…',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : Text(
                                              _isRoomCover
                                                  ? copy.text(
                                                      'Use cover',
                                                      'Użyj okładki',
                                                    )
                                                  : copy.text(
                                                      'Use photo',
                                                      'Użyj zdjęcia',
                                                    ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

/// The wide crop is the canonical room-cover asset, but compact Home and
/// Discover cards use a taller viewport. This guide marks the central area
/// that survives both presentations so hosts can keep faces, logos and text
/// away from the outer edges without storing display-time crop metadata.
class _RoomCoverSafeAreaOverlay extends StatelessWidget {
  const _RoomCoverSafeAreaOverlay();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          children: [
            const Expanded(
              flex: 6,
              child: ColoredBox(color: Color(0x520D0618)),
            ),
            const Spacer(flex: 9),
            const Expanded(
              flex: 6,
              child: ColoredBox(color: Color(0x520D0618)),
            ),
          ],
        ),
        Center(
          child: FractionallySizedBox(
            // 9/21 of the wide frame is a centred square — the most
            // restrictive shape used by mobile room thumbnails.
            widthFactor: 9 / 21,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(color: Color(0xFF0D0618), width: 5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border.symmetric(
                      vertical: BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xD90D0618),
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            copy.text('COMPACT SAFE', 'BEZPIECZNY KADR'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .35,
                            ),
                          ),
                        ),
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

class _CropControlGroup extends StatelessWidget {
  const _CropControlGroup({
    required this.semanticsLabel,
    required this.children,
  });

  final String semanticsLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF171023),
          border: Border.all(color: const Color(0xFF3A3151)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
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

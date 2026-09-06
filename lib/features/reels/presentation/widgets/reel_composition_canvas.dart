import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/reel_visuals.dart';

typedef ReelLinkOpener = Future<void> Function(ReelLinkOverlay overlay);

/// Maps a drag on the composition canvas back to a normalized overlay
/// position — the exact inverse of `_NormalizedOverlayDelegate`: one full
/// safe-area width is 1.0 in x, one full safe-area height is 1.0 in y.
/// [canvas] is the design canvas the recognizer reports in (the
/// [ReelCompositionFrame.designSize] space inside the FittedBox). Results
/// clamp to 0..1 so a far drag can never make the composition invalid.
({double x, double y}) reelOverlayPositionFromGesture({
  required double startX,
  required double startY,
  required Offset startFocalPoint,
  required Offset focalPoint,
  required Size canvas,
  required EdgeInsets safeInsets,
}) {
  final safeWidth = math.max(1.0, canvas.width - safeInsets.horizontal);
  final safeHeight = math.max(1.0, canvas.height - safeInsets.vertical);
  final delta = focalPoint - startFocalPoint;
  return (
    x: (startX + delta.dx / safeWidth).clamp(0.0, 1.0),
    y: (startY + delta.dy / safeHeight).clamp(0.0, 1.0),
  );
}

/// Pinch scale for a text overlay, bounded to the model's contract.
double reelTextOverlayScaleFromGesture({
  required double startScale,
  required double gestureScale,
}) => (startScale * gestureScale).clamp(.75, 2.0);

/// The editing recipe has one design canvas regardless of preview size. Native
/// playback controls belong outside this frame so their hit areas never shrink.
class ReelCompositionFrame extends StatelessWidget {
  const ReelCompositionFrame({
    required this.composition,
    required this.media,
    this.mediaForeground,
    this.onOpenLink,
    this.onTextOverlayChanged,
    this.onLinkOverlayChanged,
    this.overlaySafeInsets = const EdgeInsets.fromLTRB(16, 16, 16, 132),
    super.key,
  });

  final ReelComposition composition;
  final Widget media;
  final Widget? mediaForeground;
  final ReelLinkOpener? onOpenLink;

  /// Composer-only: when set, text pills can be dragged (and pinched) on
  /// the canvas. Null — the feed — keeps pills paint-only exactly as before.
  final ValueChanged<ReelTextOverlay>? onTextOverlayChanged;

  /// Composer-only: when set, link pills can be dragged on the canvas.
  final ValueChanged<ReelLinkOverlay>? onLinkOverlayChanged;
  final EdgeInsets overlaySafeInsets;

  static const designSize = Size(390, 390 * 16 / 9);

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 9 / 16,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / designSize.width,
          constraints.maxHeight / designSize.height,
        );
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: designSize,
            child: ReelCompositionCanvas(
              composition: composition,
              media: media,
              mediaForeground: mediaForeground,
              onOpenLink: onOpenLink,
              onTextOverlayChanged: onTextOverlayChanged,
              onLinkOverlayChanged: onLinkOverlayChanged,
              overlaySafeInsets: overlaySafeInsets,
              minimumLinkExtent: onOpenLink == null || scale <= 0
                  ? 44
                  : math.max(44, 44 / scale),
            ),
          ),
        );
      },
    ),
  );
}

Offset reelCropTranslation(Size size, ReelCropTransform crop) {
  final scale = crop.scale.clamp(1.0, 8.0).toDouble();
  final maxPanX = math.max(0.0, (size.width * (scale - 1)) / 2);
  final maxPanY = math.max(0.0, (size.height * (scale - 1)) / 2);
  return Offset(
    crop.offsetX.clamp(-1.0, 1.0).toDouble() * maxPanX,
    crop.offsetY.clamp(-1.0, 1.0).toDouble() * maxPanY,
  );
}

/// Canonical non-destructive renderer used by both the local composer and the
/// published feed.
///
/// The media child must fill its incoming bounds (normally with BoxFit.cover).
/// Crop offsets are normalized to the actual spare pixels introduced by zoom,
/// so every valid recipe remains edge-to-edge at every viewport size. Overlay
/// positions are also normalized, then clamped after measuring the real child
/// to keep text and links inside the safe canvas at 200% text scale.
class ReelCompositionCanvas extends StatelessWidget {
  const ReelCompositionCanvas({
    required this.composition,
    required this.media,
    this.mediaForeground,
    this.onOpenLink,
    this.onTextOverlayChanged,
    this.onLinkOverlayChanged,
    this.overlaySafeInsets = const EdgeInsets.fromLTRB(16, 16, 16, 132),
    this.minimumLinkExtent = 44,
    super.key,
  });

  final ReelComposition composition;
  final Widget media;
  final Widget? mediaForeground;
  final ReelLinkOpener? onOpenLink;
  final ValueChanged<ReelTextOverlay>? onTextOverlayChanged;
  final ValueChanged<ReelLinkOverlay>? onLinkOverlayChanged;
  final EdgeInsets overlaySafeInsets;
  final double minimumLinkExtent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = composition.crop.scale.clamp(1.0, 8.0).toDouble();
        final pan = reelCropTranslation(size, composition.crop);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Transform.translate(
                key: const ValueKey('reel-composition-media-translation'),
                offset: pan,
                child: Transform.scale(
                  key: const ValueKey('reel-composition-media-scale'),
                  scale: scale,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(
                      reelFilterMatrix(composition.filter),
                    ),
                    child: SizedBox.expand(child: media),
                  ),
                ),
              ),
              ?mediaForeground,
              for (final overlay in composition.textOverlays)
                _MeasuredOverlay(
                  x: overlay.x,
                  y: overlay.y,
                  safeInsets: overlaySafeInsets,
                  child: onTextOverlayChanged == null
                      ? _ReelTextOverlayPill(overlay: overlay)
                      : _EditableOverlay(
                          key: ValueKey<String>(
                            'reel-text-overlay-handle-${overlay.id}',
                          ),
                          canvas: size,
                          safeInsets: overlaySafeInsets,
                          x: overlay.x,
                          y: overlay.y,
                          scale: overlay.scale,
                          onChanged: (x, y, scale) => onTextOverlayChanged!(
                            ReelTextOverlay(
                              id: overlay.id,
                              text: overlay.text,
                              x: x,
                              y: y,
                              scale: scale,
                              color: overlay.color,
                            ),
                          ),
                          child: _ReelTextOverlayPill(overlay: overlay),
                        ),
                ),
              for (final overlay in composition.linkOverlays)
                _MeasuredOverlay(
                  x: overlay.x,
                  y: overlay.y,
                  safeInsets: overlaySafeInsets,
                  child: onLinkOverlayChanged == null
                      ? _ReelLinkOverlayPill(
                          overlay: overlay,
                          onOpen: onOpenLink,
                          minimumExtent: minimumLinkExtent,
                        )
                      : _EditableOverlay(
                          key: ValueKey<String>(
                            'reel-link-overlay-handle-${overlay.id}',
                          ),
                          canvas: size,
                          safeInsets: overlaySafeInsets,
                          x: overlay.x,
                          y: overlay.y,
                          onChanged: (x, y, _) => onLinkOverlayChanged!(
                            ReelLinkOverlay(
                              id: overlay.id,
                              label: overlay.label,
                              uri: overlay.uri,
                              x: x,
                              y: y,
                            ),
                          ),
                          child: _ReelLinkOverlayPill(
                            overlay: overlay,
                            onOpen: null,
                            minimumExtent: minimumLinkExtent,
                          ),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One-finger drag moves a pill, two fingers pinch a text pill. The pill
/// itself stays paint-only (IgnorePointer inside), so this wrapper is the
/// single hit target; a focus-coloured outline shows while a gesture is live.
class _EditableOverlay extends StatefulWidget {
  const _EditableOverlay({
    required this.canvas,
    required this.safeInsets,
    required this.x,
    required this.y,
    required this.onChanged,
    required this.child,
    this.scale,
    super.key,
  });

  final Size canvas;
  final EdgeInsets safeInsets;
  final double x;
  final double y;

  /// Null for links, which have no scale in the model.
  final double? scale;
  final void Function(double x, double y, double scale) onChanged;
  final Widget child;

  @override
  State<_EditableOverlay> createState() => _EditableOverlayState();
}

class _EditableOverlayState extends State<_EditableOverlay> {
  double? _startX, _startY, _startScale;
  Offset? _startFocal;
  bool _active = false;

  void _start(ScaleStartDetails details) {
    _startX = widget.x;
    _startY = widget.y;
    _startScale = widget.scale;
    _startFocal = details.focalPoint;
    setState(() => _active = true);
  }

  void _update(ScaleUpdateDetails details) {
    final startX = _startX, startY = _startY, startFocal = _startFocal;
    if (startX == null || startY == null || startFocal == null) return;
    final position = reelOverlayPositionFromGesture(
      startX: startX,
      startY: startY,
      startFocalPoint: startFocal,
      focalPoint: details.focalPoint,
      canvas: widget.canvas,
      safeInsets: widget.safeInsets,
    );
    final startScale = _startScale;
    final scale = startScale == null
        ? 1.0
        : reelTextOverlayScaleFromGesture(
            startScale: startScale,
            gestureScale: details.pointerCount > 1 ? details.scale : 1,
          );
    widget.onChanged(position.x, position.y, scale);
  }

  void _end() {
    _startX = _startY = _startScale = null;
    _startFocal = null;
    if (mounted) setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    final focus = Theme.of(context).colorScheme.primary;
    // Eager: a pointer that lands on a pill belongs to the pill. Otherwise
    // the composer's scroll view wins any mostly-vertical drag and the pill
    // never moves — exactly the "cannot drag it" report.
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _EagerScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EagerScaleGestureRecognizer>(
              _EagerScaleGestureRecognizer.new,
              (recognizer) => recognizer
                ..onStart = _start
                ..onUpdate = _update
                ..onEnd = (_) => _end(),
            ),
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _active ? focus : focus.withValues(alpha: 0),
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _MeasuredOverlay extends StatelessWidget {
  const _MeasuredOverlay({
    required this.x,
    required this.y,
    required this.safeInsets,
    required this.child,
  });

  final double x;
  final double y;
  final EdgeInsets safeInsets;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _NormalizedOverlayDelegate(
        x: x.clamp(0.0, 1.0),
        y: y.clamp(0.0, 1.0),
        safeInsets: safeInsets,
      ),
      child: child,
    );
  }
}

class _NormalizedOverlayDelegate extends SingleChildLayoutDelegate {
  const _NormalizedOverlayDelegate({
    required this.x,
    required this.y,
    required this.safeInsets,
  });

  final double x;
  final double y;
  final EdgeInsets safeInsets;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - safeInsets.horizontal),
      maxHeight: math.max(0, constraints.maxHeight - safeInsets.vertical),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = safeInsets.left.clamp(0.0, size.width);
    final maxX = math.max(
      minX,
      size.width - safeInsets.right - childSize.width,
    );
    final minY = safeInsets.top.clamp(0.0, size.height);
    final maxY = math.max(
      minY,
      size.height - safeInsets.bottom - childSize.height,
    );
    final safeWidth = math.max(0.0, size.width - safeInsets.horizontal);
    final safeHeight = math.max(0.0, size.height - safeInsets.vertical);
    final wantedX = safeInsets.left + (safeWidth * x) - (childSize.width / 2);
    final wantedY = safeInsets.top + (safeHeight * y) - (childSize.height / 2);
    return Offset(wantedX.clamp(minX, maxX), wantedY.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(covariant _NormalizedOverlayDelegate oldDelegate) =>
      oldDelegate.x != x ||
      oldDelegate.y != y ||
      oldDelegate.safeInsets != safeInsets;
}

class _ReelTextOverlayPill extends StatelessWidget {
  const _ReelTextOverlayPill({required this.overlay});

  final ReelTextOverlay overlay;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final foreground = reelOverlayColor(overlay.color);
    return IgnorePointer(
      child: Semantics(
        key: ValueKey<String>('reel-text-overlay-${overlay.id}'),
        label: copy.template(
          'Text overlay: {text}',
          'Tekst na Reelu: {text}',
          values: <String, Object>{'text': overlay.text},
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: reelTextOverlaySurface(overlay.color),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: reelTextOverlayOutline(overlay.color),
              width: 1.5,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x66000000), blurRadius: 10),
            ],
          ),
          child: Text(
            overlay.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 18 * overlay.scale,
              height: 1.12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReelLinkOverlayPill extends StatelessWidget {
  const _ReelLinkOverlayPill({
    required this.overlay,
    required this.onOpen,
    required this.minimumExtent,
  });

  final ReelLinkOverlay overlay;
  final ReelLinkOpener? onOpen;
  final double minimumExtent;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = copy.template(
      'Open link: {label}',
      'Otwórz link: {label}',
      values: <String, Object>{'label': overlay.label},
    );
    final content = ConstrainedBox(
      key: ValueKey<String>('reel-link-overlay-${overlay.id}'),
      constraints: BoxConstraints(
        minHeight: minimumExtent,
        minWidth: minimumExtent,
        maxWidth: math.max(260, minimumExtent),
      ),
      child: Material(
        color: reelLinkOverlaySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: reelLinkOverlayOutline, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onOpen == null ? null : () => unawaited(onOpen!(overlay)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.link_rounded,
                  size: 18,
                  color: reelLinkOverlayForeground,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    overlay.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: reelLinkOverlayForeground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: reelLinkOverlayForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (onOpen == null) {
      return ExcludeSemantics(child: IgnorePointer(child: content));
    }
    return Semantics(link: true, button: true, label: label, child: content);
  }
}

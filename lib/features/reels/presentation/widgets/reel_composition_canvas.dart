import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/reel_visuals.dart';

typedef ReelLinkOpener = Future<void> Function(ReelLinkOverlay overlay);

@visibleForTesting
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
    this.overlaySafeInsets = const EdgeInsets.fromLTRB(16, 16, 16, 132),
    super.key,
  });

  final ReelComposition composition;
  final Widget media;
  final Widget? mediaForeground;
  final ReelLinkOpener? onOpenLink;
  final EdgeInsets overlaySafeInsets;

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
                  child: _ReelTextOverlayPill(overlay: overlay),
                ),
              for (final overlay in composition.linkOverlays)
                _MeasuredOverlay(
                  x: overlay.x,
                  y: overlay.y,
                  safeInsets: overlaySafeInsets,
                  child: _ReelLinkOverlayPill(
                    overlay: overlay,
                    onOpen: onOpenLink,
                  ),
                ),
            ],
          ),
        );
      },
    );
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
  const _ReelLinkOverlayPill({required this.overlay, required this.onOpen});

  final ReelLinkOverlay overlay;
  final ReelLinkOpener? onOpen;

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
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 260),
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

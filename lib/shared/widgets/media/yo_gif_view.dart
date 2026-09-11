import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';

/// Renders one GIF at a KNOWN HEIGHT, in every state it can be in.
///
/// ## Why the height is fixed before anything loads
///
/// The asset is always the provider's fixed-height rendition, so its height is
/// known from the record and never measured from the image. That is what stops
/// a chat list reflowing — and jumping under the reader's thumb — the moment a
/// remote image lands. Width follows from the intrinsic ratio and is clamped to
/// the bubble; nothing here waits on a byte to decide its layout.
///
/// ## Every degradation is a state, not a blank
///
///  * **loading** — a shimmer at the final size, so nothing moves when it
///    resolves;
///  * **dead URL** — a same-height placeholder carrying the stored title and
///    "This GIF is no longer available". The message keeps its meaning because
///    the title was stored, not just the URL;
///  * **auto-load off** — a placeholder with the title and a tap to load, and
///    NO PROVIDER CONTACT AT ALL until the person chooses. This is the control
///    that matters: rendering a GIF necessarily shows the viewer's IP address
///    to a third party they never chose to talk to.
class YoGifView extends StatefulWidget {
  const YoGifView({
    required this.asset,
    super.key,
    this.height = 160,
    this.maxWidth = 260,
    this.autoLoad = true,
    this.borderRadius = 14,
    this.showTitle = false,
    this.retryOnTap = true,
  });

  final GifAsset asset;

  /// Logical height at 100% text scale. Scaled with the reader's text size up
  /// to a cap, because a picture is not text: it should grow enough to stay
  /// comfortable without swallowing the conversation around it.
  final double height;

  final double maxWidth;

  /// `AppPreferences.gifAutoLoadEnabled`. False means no network request is
  /// made until the person taps.
  final bool autoLoad;

  final double borderRadius;

  /// Shows the title under the image. Used in the picker's recents row, where
  /// a grid of unlabelled squares is hard to scan; off in chat bubbles, where
  /// the image is the message.
  final bool showTitle;

  /// Received messages own the retry action. Picker cells instead own their
  /// tap-to-select and long-press-to-report gestures, including failed previews.
  final bool retryOnTap;

  @override
  State<YoGifView> createState() => _YoGifViewState();
}

class _YoGifViewState extends State<YoGifView> {
  bool _manuallyLoaded = false;
  int _imageRevision = 0;

  bool get _shouldLoad => widget.autoLoad || _manuallyLoaded;

  @override
  void didUpdateWidget(covariant YoGifView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _manuallyLoaded = false;
      _imageRevision = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // Capped growth: at 200% text scale an uncapped image would push the
    // conversation off a short screen entirely.
    final height = math.min(scaler.scale(widget.height), widget.height * 1.5);
    final width = math.min(
      widget.asset.widthForHeight(height),
      widget.maxWidth,
    );
    final radius = BorderRadius.circular(widget.borderRadius);

    final Widget body;
    if (!_shouldLoad) {
      body = Semantics(
        button: true,
        // A stable literal key with the title substituted afterwards; see
        // test/localization_source_guard_test.dart.
        label: copy.template(
          'Load GIF: {title}',
          'Wczytaj GIF: {title}',
          values: <String, Object>{'title': widget.asset.title},
        ),
        child: InkWell(
          key: const ValueKey('gif-view-load'),
          onTap: () => setState(() => _manuallyLoaded = true),
          borderRadius: radius,
          child: ExcludeSemantics(
            child: _GifPlaceholder(
              palette: palette,
              icon: Icons.play_circle_outline_rounded,
              title: widget.asset.title,
              message: copy.text('Tap to load', 'Dotknij, aby wczytać'),
            ),
          ),
        ),
      );
    } else {
      body = Image.network(
        widget.asset.url,
        key: ValueKey('gif-image-${widget.asset.id}-$_imageRevision'),
        width: width,
        height: height,
        fit: BoxFit.cover,
        // The label names the medium as well as the content: a screen reader
        // user has no other way to know this is an animation.
        semanticLabel: copy.template(
          'GIF: {title}',
          'GIF: {title}',
          values: <String, Object>{'title': widget.asset.title},
        ),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          // The shimmer is the SAME SIZE as the image it replaces, so the
          // handoff moves nothing.
          return _GifShimmer(palette: palette);
        },
        errorBuilder: (context, error, stackTrace) {
          final placeholder = _GifPlaceholder(
            palette: palette,
            icon: Icons.refresh_rounded,
            title: widget.asset.title,
            message: copy.text(
              'This GIF is no longer available',
              'Ten GIF nie jest już dostępny',
            ),
          );
          if (!widget.retryOnTap) return placeholder;
          return Tooltip(
            message: copy.text('Retry', 'Spróbuj ponownie'),
            child: InkWell(
              key: const ValueKey('gif-view-retry'),
              onTap: () async {
                final url = widget.asset.url;
                await NetworkImage(url).evict();
                if (mounted && widget.asset.url == url) {
                  setState(() => _imageRevision++);
                }
              },
              child: placeholder,
            ),
          );
        },
      );
    }

    final framed = SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceSunken,
            borderRadius: radius,
          ),
          child: body,
        ),
      ),
    );

    if (!widget.showTitle) return framed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        framed,
        const SizedBox(height: 4),
        SizedBox(
          width: width,
          child: Text(
            widget.asset.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textTertiary, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _GifShimmer extends StatelessWidget {
  const _GifShimmer({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.surfaceSunken,
            palette.surfaceMuted,
            palette.surfaceSunken,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _GifPlaceholder extends StatelessWidget {
  const _GifPlaceholder({
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    // THE PLACEHOLDER FITS THE BOX IT IS GIVEN.
    //
    // The same widget serves a 94 px picker cell and a 160 px chat bubble, and
    // the first visual capture of the picker showed "This GIF is no longer
    // available" clipped mid-word inside a cell. So the lines are dropped in
    // priority order as the box shrinks: the TITLE is what carries the
    // message's meaning when the bytes are gone, so it is the last thing to
    // go; the explanation is the first; the icon alone is the floor.
    // Thresholds are compared against SCALED heights, not raw pixels: at 200%
    // text scale the same 116 px cell holds half as many lines, and comparing
    // raw numbers left "This GIF is no" clipped mid-word in the 320 px capture.
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final showMessage = height >= scaler.scale(104);
        final showTitle = height >= scaler.scale(56);
        final titleLines = height >= scaler.scale(128) ? 2 : 1;
        final showIcon = height >= scaler.scale(40);

        return Padding(
          padding: EdgeInsets.all(height >= 80 ? 8 : 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showIcon) Icon(icon, size: 22, color: palette.textTertiary),
              if (showIcon && showTitle) const SizedBox(height: 4),
              if (showTitle)
                Flexible(
                  child: Text(
                    title,
                    maxLines: titleLines,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (showMessage) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textTertiary, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

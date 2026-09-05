import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// Optional locally bundled scenery for the five normal product destinations.
/// These are decorative environments, not user uploads or live-room covers.
enum YoPageSection {
  home('home-lounge'),
  rooms('rooms-lounge'),
  chats('chats-lounge'),
  moments('moments-studio'),
  more('more-study');

  const YoPageSection(this._file);
  final String _file;
  String get asset => 'assets/images/atmospheres/$_file.webp';
}

/// A static, hit-test-free environment. Decode size and contrast are bounded;
/// no network fetch, animation, blur pass or background media player is used.
class YoAtmosphereArt extends StatelessWidget {
  const YoAtmosphereArt({required this.section, super.key});

  static const darkOpacity = .18;
  static const pearlOpacity = .07;
  final YoPageSection section;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final decodeWidth =
                    (constraints.maxWidth *
                            MediaQuery.devicePixelRatioOf(context))
                        .ceil()
                        .clamp(320, 864);
                return Image.asset(
                  section.asset,
                  key: ValueKey('yo-atmosphere-${section.name}'),
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  cacheWidth: decodeWidth,
                  fit: BoxFit.cover,
                  alignment: const Alignment(.15, .2),
                  opacity: AlwaysStoppedAnimation(
                    dark ? darkOpacity : pearlOpacity,
                  ),
                  filterQuality: FilterQuality.low,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The normal-product canvas, with the official YO mark behind its content.
///
/// Use once around a full page, outside its scroll view. Immersive viewers,
/// camera/crop surfaces, calls and branded authentication stages intentionally
/// keep their own backgrounds. This is decoration, never a foreground overlay.
class YoPageBackground extends StatelessWidget {
  const YoPageBackground({
    required this.child,
    this.decoration,
    this.section,
    super.key,
  });

  static const logoAsset = 'assets/images/yo-voice-favicon-512.png';

  final Widget child;
  final YoPageSection? section;

  /// Preserve a destination's established semantic gradient when it has one.
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    final inheritedCanvas = context
        .dependOnInheritedWidgetOfExactType<_YoPageCanvasScope>();
    // Embedded feeds may also be opened alone. Their nearest full-page owner
    // paints the mark; nesting must not multiply the opacity or cover it.
    if (inheritedCanvas != null) return child;

    final highContrast = MediaQuery.highContrastOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _YoPageCanvasScope(
      child: DecoratedBox(
        decoration:
            decoration ?? BoxDecoration(color: context.appPalette.background),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!highContrast && section != null)
              Positioned.fill(child: YoAtmosphereArt(section: section!)),
            if (!highContrast && section == null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      child: ClipRect(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final side = math.min(
                              980.0,
                              math.min(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  ) *
                                  1.12,
                            );
                            return Align(
                              alignment: const Alignment(.28, .24),
                              child: OverflowBox(
                                minWidth: side,
                                maxWidth: side,
                                minHeight: side,
                                maxHeight: side,
                                child: Image.asset(
                                  logoAsset,
                                  key: const ValueKey('yo-page-watermark'),
                                  width: side,
                                  height: side,
                                  fit: BoxFit.contain,
                                  opacity: AlwaysStoppedAnimation(
                                    dark ? .025 : .018,
                                  ),
                                  filterQuality: FilterQuality.low,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class _YoPageCanvasScope extends InheritedWidget {
  const _YoPageCanvasScope({required super.child});

  @override
  bool updateShouldNotify(_YoPageCanvasScope oldWidget) => false;
}

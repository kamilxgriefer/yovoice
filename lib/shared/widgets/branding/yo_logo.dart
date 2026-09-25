import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// Which light the bare logo carries (refine-look §4).
///
/// * [auto] — a bloom in Dark; a plum contact shadow in Pearl, so the glossy
///   object sits on the paper instead of glowing on it.
/// * [bloom] — forced bloom, for immersive (always-dark) surfaces.
/// * [none] — bare, for lists and small slots.
enum YoBrandLight { auto, bloom, none }

/// The real YO Voice logo, always bare: never boxed, never redrawn, never a
/// flat "YO" square.
///
/// * Paints only `assets/images/logo.png` ([markAsset]) plus its pre-baked
///   blur ([bloomAsset], the logo at 320 px on a transparent 512 canvas,
///   Gaussian σ 24). The bloom is drawn at 1.6 × the mark box so its inner
///   footprint equals the mark. `logo-glow.png` and `app-store-icon.png` are
///   opaque plates and are never used in-app.
/// * The layout box is ALWAYS exactly [size] × [size]: the bloom and the
///   contact shadow are `Stack` siblings with `clipBehavior: none`, so light
///   never moves a neighbour.
/// * Decodes at `(size × dpr).ceil()` clamped to 64..512 with
///   `FilterQuality.high`. If the asset fails, a `graphic_eq` glyph at .6 ×
///   [size] in `interactiveForeground` keeps the slot intentional.
/// * The images are excluded from semantics; the host (e.g.
///   [YoBrandLockup]) says "YO Voice" once.
/// * Under high contrast there is no bloom and no shadow.
///
/// The widget's own [key] passes through (`home-brand-mark`, `startup-logo`,
/// `totp-logo`); [bloomKey] marks the bloom layer (`startup-logo-bloom`).
class YoBrandMark extends StatelessWidget {
  const YoBrandMark({
    required this.size,
    this.light = YoBrandLight.auto,
    this.bloomOpacity = .45,
    this.bloomScale = 1.6,
    this.bloomKey,
    super.key,
  });

  static const String markAsset = 'assets/images/logo.png';
  static const String bloomAsset = 'assets/images/logo-bloom.png';

  /// Pearl's contact shadow: the bloom tinted `palette.shadow` at this alpha
  /// and dropped by [contactOffset].
  static const double contactAlpha = .16;
  static const Offset contactOffset = Offset(0, 2);

  final double size;
  final YoBrandLight light;

  /// Bloom opacity (static .45 on Start / Auth; the startup breath drives it
  /// from its own existing animation).
  final double bloomOpacity;

  /// Bloom box relative to the mark box.
  final double bloomScale;
  final Key? bloomKey;

  /// Warms both images so the first frame already has the mark (call from
  /// `didChangeDependencies` of a screen that shows it).
  static Future<void> precache(BuildContext context) => Future.wait<void>([
    precacheImage(const AssetImage(markAsset), context),
    precacheImage(const AssetImage(bloomAsset), context),
  ]);

  static int cacheWidthFor(double logicalSize, double devicePixelRatio) =>
      (logicalSize * devicePixelRatio).ceil().clamp(64, 512);

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final dark = palette.isDark;
    final showsBloom =
        !highContrast &&
        (light == YoBrandLight.bloom || (light == YoBrandLight.auto && dark));
    final showsContact = !highContrast && light == YoBrandLight.auto && !dark;
    final bloomBox = size * bloomScale;
    final inset = (bloomBox - size) / 2;
    final bloomCache = cacheWidthFor(bloomBox, dpr);

    Widget bloomImage() => Image.asset(
      bloomAsset,
      width: bloomBox,
      height: bloomBox,
      cacheWidth: bloomCache,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (showsBloom)
            Positioned(
              key: bloomKey,
              left: -inset,
              top: -inset,
              width: bloomBox,
              height: bloomBox,
              child: IgnorePointer(
                child: Opacity(
                  opacity: bloomOpacity.clamp(0.0, 1.0),
                  child: bloomImage(),
                ),
              ),
            ),
          if (showsContact)
            Positioned(
              left: -inset + contactOffset.dx,
              top: -inset + contactOffset.dy,
              width: bloomBox,
              height: bloomBox,
              child: IgnorePointer(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    palette.shadow.withValues(alpha: contactAlpha),
                    BlendMode.srcIn,
                  ),
                  child: bloomImage(),
                ),
              ),
            ),
          Positioned.fill(
            child: Image.asset(
              markAsset,
              width: size,
              height: size,
              cacheWidth: cacheWidthFor(size, dpr),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Center(
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: size * .6,
                  color: palette.interactiveForeground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bare mark before the unchanged "YO Voice" wordmark, as one semantics
/// node that reads the product name once (the name is not localized).
///
/// * The mark is [size] (32 on phones, 36 up to the desktop shell), 10 px
///   before the wordmark (`titleMedium` w800 — one of the two places w800
///   stays), which ellipsizes rather than wraps.
/// * At ≥ 1.6 × text the mark follows the wordmark: 1.1 × its line height,
///   clamped to [size]..48, so the pair never looks mismatched.
/// * [markKey] passes to the mark (`home-brand-mark`), the widget's own key
///   to the semantics node (`home-brand-lockup`).
class YoBrandLockup extends StatelessWidget {
  const YoBrandLockup({
    this.size = 32,
    this.light = YoBrandLight.auto,
    this.markKey,
    super.key,
  });

  static const double gap = 10;
  static const double maxMarkSize = 48;

  final double size;
  final YoBrandLight light;
  final Key? markKey;

  static TextStyle wordmarkStyle(AppPalette palette) =>
      AppTypography.titleMedium.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        height: 1.2,
      );

  /// The mark size at a given text scale.
  static double markSizeFor(double size, TextScaler scaler) {
    final wordmark = AppTypography.titleMedium;
    final line = scaler.scale(wordmark.fontSize!) * 1.2;
    if (scaler.scale(1) < 1.6) return size;
    return (line * 1.1).clamp(size, math.max(size, maxMarkSize));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final markSize = markSizeFor(size, MediaQuery.textScalerOf(context));
    return Semantics(
      container: true,
      label: 'YO Voice',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoBrandMark(key: markKey, size: markSize, light: light),
          const SizedBox(width: gap),
          Flexible(
            child: Text(
              'YO Voice',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: wordmarkStyle(palette),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kept for source compatibility: the old widget pointed at an SVG that was
/// never shipped (a crash path) and had no callers. It now renders the real
/// lockup; [width], when set, caps the lockup's width.
class YoLogo extends StatelessWidget {
  const YoLogo({super.key, this.markSize = 32, this.width});

  final double markSize;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final lockup = YoBrandLockup(size: markSize);
    final cap = width;
    if (cap == null) return lockup;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: cap),
      child: lockup,
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

/// The one source of the full-bleed profile hero's sizes.
///
/// The banner is the background of the whole profile header: edge to edge,
/// starting at y = 0 under the status bar, with the toolbar floating over it
/// and the identity row sitting in its bottom melt. Every number the own
/// profile, the friend profile, the edit-profile preview and the crop
/// editor's "always visible" guide need is derived here, so they cannot
/// drift apart the way the old inset card and the crop guide once did.
///
/// Height, for a backdrop `W` wide under a status bar `T` tall:
///
/// * ideal: `T + toolbarExtent + band`, with the band chosen by the
///   backdrop's own width (124 below 600, 156 below 1100, 176 above);
/// * never narrower than the stored 16:9 — the height is capped at
///   `W × 9 / 16`, so a phone shows the WHOLE banner (edge to edge, nothing
///   cropped at the sides) and wider tiers crop only top and bottom, around
///   the centre;
/// * never more than [maxViewportShare] of a short (landscape) viewport;
/// * never less than the toolbar plus a [minimumClearBand] of clear photo
///   plus the part of the melt above the text line.
@immutable
class ProfileHeroGeometry {
  const ProfileHeroGeometry({
    required this.width,
    required this.backdropLeft,
    required this.backdropWidth,
    required this.height,
    required this.topInset,
    required this.fade,
    required this.sideFade,
  });

  /// Resolves the hero for a host [width] wide (the content column the route
  /// actually gets — beside the desktop sidebar, never the window).
  ///
  /// [windowWidth] only decides whether the backdrop, capped at
  /// [maxBackdropWidth], has page canvas beside it and therefore needs its
  /// side melt; [viewportHeight] caps a landscape phone.
  factory ProfileHeroGeometry.resolve({
    required double width,
    double topInset = 0,
    double? viewportHeight,
    double? windowWidth,
  }) {
    final safeWidth = width.isFinite ? math.max(0.0, width) : 0.0;
    final backdropWidth = math.min(safeWidth, maxBackdropWidth);
    final (band, fade) = switch (backdropWidth) {
      < mediumBreakpoint => (narrowBand, narrowFade),
      < wideBreakpoint => (mediumBand, mediumFade),
      _ => (wideBand, wideFade),
    };
    final ideal = topInset + toolbarExtent + band;
    var cap = backdropWidth / ProfileImageRules.banner.aspectRatio;
    if (viewportHeight != null &&
        viewportHeight.isFinite &&
        viewportHeight > 0) {
      cap = math.min(cap, viewportHeight * maxViewportShare);
    }
    final floor =
        topInset + toolbarExtent + minimumClearBand + fade * textFadeShare;
    final height = math.max(floor, math.min(ideal, cap));
    final sideFade =
        backdropWidth >= maxBackdropWidth &&
            windowWidth != null &&
            windowWidth > backdropWidth + .5
        ? sideFadeExtent
        : 0.0;
    return ProfileHeroGeometry(
      width: safeWidth,
      backdropLeft: (safeWidth - backdropWidth) / 2,
      backdropWidth: backdropWidth,
      height: height,
      topInset: topInset,
      fade: fade,
      sideFade: sideFade,
    );
  }

  /// The edit-profile preview: what a [previewReferenceWidth] phone under a
  /// [previewReferenceTopInset] status bar shows, scaled to [width]. That
  /// phone hits the 16:9 cap, so the preview is exactly the stored banner.
  factory ProfileHeroGeometry.preview({required double width}) {
    final reference = ProfileHeroGeometry.resolve(
      width: previewReferenceWidth,
      topInset: previewReferenceTopInset,
    );
    final scale = width / previewReferenceWidth;
    return ProfileHeroGeometry(
      width: width,
      backdropLeft: 0,
      backdropWidth: width,
      height: reference.height * scale,
      topInset: reference.topInset * scale,
      fade: reference.fade * scale,
      sideFade: 0,
    );
  }

  /// Toolbar row: 6 px air, a 44 px target row, 6 px air.
  static const double toolbarExtent = 56;

  /// The hero never grows wider than the workbench measure; past it the
  /// photo is centred and melts into the canvas at both sides.
  static final double maxBackdropWidth =
      ResponsiveContentWidth.workbench.maxWidth;

  static const double mediumBreakpoint = 600;
  static const double wideBreakpoint = 1100;
  static const double narrowBand = 124;
  static const double mediumBand = 156;
  static const double wideBand = 176;
  static const double narrowFade = 96;
  static const double mediumFade = 104;
  static const double wideFade = 112;

  /// Clear photo kept between the toolbar and the melt, whatever caps apply.
  static const double minimumClearBand = 48;

  /// A landscape phone must not spend more than this share of its height on
  /// imagery before any identity is drawn.
  static const double maxViewportShare = .45;

  static const double sideFadeExtent = 48;

  /// Share of the melt that sits below the text line. At that line the photo
  /// is down to 10% alpha, i.e. text stands on at least 90% page canvas.
  static const double textFadeShare = .4;

  /// How far below the status bar the top scrim reaches.
  static const double topScrimReach = 72;

  static const double previewReferenceWidth = 390;
  static const double previewReferenceTopInset = 47;

  /// The host width the hero was resolved for.
  final double width;
  final double backdropLeft;
  final double backdropWidth;

  /// Backdrop height, from y = 0 (under the status bar).
  final double height;

  /// The status-bar inset the toolbar clears (0 on desktop and web).
  final double topInset;

  /// Height of the bottom melt into the page canvas.
  final double fade;

  /// Width of the left/right melt; 0 unless the backdrop is capped and has
  /// canvas beside it.
  final double sideFade;

  /// The first y at which text may stand: the photo is at most 10% opaque
  /// from here down.
  double get textLine => height - fade * textFadeShare;

  /// Height of the top scrim that keeps status icons and the toolbar
  /// legible over a bright photo.
  double get topScrimExtent => math.min(height, topInset + topScrimReach);

  /// The hero's height at its widest presentation (desktop, no status bar).
  static double get widestHeight => toolbarExtent + wideBand;

  /// Share of the stored 16:9 banner's height that is on screen at the
  /// widest presentation — and therefore at every width, since narrower
  /// heroes show more of the height and phones show all of it.
  static double get alwaysVisibleFraction =>
      ProfileImageRules.banner.aspectRatio /
      (maxBackdropWidth / widestHeight);

  @override
  bool operator ==(Object other) =>
      other is ProfileHeroGeometry &&
      other.width == width &&
      other.backdropLeft == backdropLeft &&
      other.backdropWidth == backdropWidth &&
      other.height == height &&
      other.topInset == topInset &&
      other.fade == fade &&
      other.sideFade == sideFade;

  @override
  int get hashCode => Object.hash(
    width,
    backdropLeft,
    backdropWidth,
    height,
    topInset,
    fade,
    sideFade,
  );
}

/// Where the hero's readable content goes: the screen's content measure,
/// centred in the host and pushed clear of landscape safe-area insets, while
/// the photo alone runs full bleed.
@immutable
class ProfileHeroFrame {
  const ProfileHeroFrame({
    required this.geometry,
    required this.columnLeft,
    required this.columnWidth,
  });

  final ProfileHeroGeometry geometry;
  final double columnLeft;
  final double columnWidth;

  double get width => geometry.width;
  double get columnRight => math.max(0, width - columnLeft - columnWidth);

  /// Horizontal padding that puts a child on the content column, with
  /// [start]/[end] extra gutter inside it.
  EdgeInsets inset({double start = 0, double end = 0}) =>
      EdgeInsets.only(left: columnLeft + start, right: columnRight + end);

  /// The content column for a host [width] wide: at most [maxWidth], centred,
  /// never under a horizontal safe-area inset.
  static ({double left, double width}) measure({
    required double width,
    required double maxWidth,
    EdgeInsets safe = EdgeInsets.zero,
  }) {
    final usable = math.max(0.0, width - safe.left - safe.right);
    final column = math.min(maxWidth, usable);
    final centred = math.max(safe.left, (width - column) / 2);
    final left = math.min(centred, math.max(0.0, width - safe.right - column));
    return (left: left, width: column);
  }
}

typedef ProfileHeroSlotBuilder =
    Widget Function(BuildContext context, ProfileHeroFrame frame);

/// The full-bleed profile header: the backdrop behind everything, then the
/// toolbar, the identity row on the text line, and an optional footer.
///
/// The Stack is sized by its (non-positioned) Column, never by the
/// backdrop, so it cannot reproduce the collapsed-Stack avatar clipping the
/// old header once shipped. The backdrop scrolls away 1:1 with the header —
/// no parallax. The only motion is an iOS overscroll stretch that keeps the
/// photo under the status bar while the list bounces; Reduce Motion drops it.
class ProfileHeroLayout extends StatelessWidget {
  const ProfileHeroLayout({
    required this.contentMaxWidth,
    required this.backdrop,
    required this.toolbar,
    required this.identity,
    this.footer,
    super.key,
  });

  /// The screen's reading measure (1040 own profile, 880 friend profile).
  final double contentMaxWidth;

  /// Usually a `ProfileBannerButton` around a [ProfileHeroBackdrop].
  final ProfileHeroSlotBuilder backdrop;

  /// Laid out in a [ProfileHeroGeometry.toolbarExtent] tall row.
  final ProfileHeroSlotBuilder toolbar;

  /// Starts on [ProfileHeroGeometry.textLine]. Opaque to hit tests, so a tap
  /// between its words never falls through to the banner viewer.
  final ProfileHeroSlotBuilder identity;

  final ProfileHeroSlotBuilder? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safe = MediaQuery.paddingOf(context);
        final window = MediaQuery.sizeOf(context);
        final geometry = ProfileHeroGeometry.resolve(
          width: constraints.maxWidth,
          topInset: safe.top,
          viewportHeight: window.height,
          windowWidth: window.width,
        );
        final column = ProfileHeroFrame.measure(
          width: geometry.width,
          maxWidth: contentMaxWidth,
          safe: safe,
        );
        final frame = ProfileHeroFrame(
          geometry: geometry,
          columnLeft: column.left,
          columnWidth: column.width,
        );
        final footer = this.footer;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _StretchingBackdropSlot(
              geometry: geometry,
              child: backdrop(context, frame),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: geometry.topInset),
                SizedBox(
                  height: ProfileHeroGeometry.toolbarExtent,
                  child: toolbar(context, frame),
                ),
                SizedBox(
                  height:
                      geometry.textLine -
                      geometry.topInset -
                      ProfileHeroGeometry.toolbarExtent,
                ),
                MetaData(
                  behavior: HitTestBehavior.opaque,
                  child: identity(context, frame),
                ),
                if (footer != null) footer(context, frame),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Places the backdrop and, while an iOS list bounces past its top, grows it
/// upward by the overscroll so no strip of canvas opens under the status bar.
class _StretchingBackdropSlot extends StatelessWidget {
  const _StretchingBackdropSlot({required this.geometry, required this.child});

  final ProfileHeroGeometry geometry;
  final Widget child;

  Widget _place(double stretch, Widget child) => Positioned(
    left: geometry.backdropLeft,
    width: geometry.backdropWidth,
    top: -stretch,
    height: geometry.height + stretch,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final position = MediaQuery.disableAnimationsOf(context)
        ? null
        : Scrollable.maybeOf(context)?.position;
    if (position == null) return _place(0, child);
    return AnimatedBuilder(
      animation: position,
      child: child,
      builder: (context, child) {
        var stretch = 0.0;
        if (position.hasPixels &&
            position.hasContentDimensions &&
            position.axis == Axis.vertical &&
            position.pixels < position.minScrollExtent) {
          stretch = position.minScrollExtent - position.pixels;
        }
        return _place(stretch, child!);
      },
    );
  }
}

/// The profile banner drawn as the header's full-bleed background.
///
/// Drawing only — the caller owns placement, the tap target and copy. Layers,
/// bottom to top:
///
/// 1. the no-photo base, shown while the grant is pending, when there is no
///    banner and when it failed: Dark keeps the brand fallback gradient;
///    Pearl gets a light theme wash, so a Pearl profile without a banner
///    never flashes a dark slab first;
/// 2. the photo (`BoxFit.cover`, [imageAlignment]), fading in over the base
///    (instantly under Reduce Motion) together with everything that belongs
///    to it:
///    * a blurred copy of the same image — `ImageFiltered` on the image, not
///      a `BackdropFilter` over live content — masked in over the bottom melt
///      (off under high contrast, or when [softFocus] is false);
///    * a top scrim for the toolbar and the status bar;
///    * a sized light status-bar region, only while the photo is on screen;
/// 3. an alpha melt: the whole stack dissolves into whatever page canvas is
///    underneath over the bottom [ProfileHeroGeometry.fade] (and the sides
///    when capped), so there is no seam against a tinted canvas.
///
/// All of it sits in one [RepaintBoundary]: scrolling moves the recorded
/// layer instead of repainting the photo, its blur or its masks.
class ProfileHeroBackdrop extends StatelessWidget {
  const ProfileHeroBackdrop({
    required this.geometry,
    this.userId,
    this.mediaRevision,
    this.mediaService,
    this.imageProvider,
    this.localImage,
    this.softFocus = true,
    super.key,
  });

  final ProfileHeroGeometry geometry;
  final String? userId;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;

  /// Test/preview seam for the grant-resolved photo.
  final ProfileMediaImageProvider? imageProvider;

  /// A photo that is not published yet (the edit-profile preview of a
  /// pending pick). Replaces the grant path entirely when set.
  final ImageProvider<Object>? localImage;

  /// The blurred bottom. High contrast always turns it off.
  final bool softFocus;

  /// Phones get the whole 16:9 banner; wider heroes crop only top and bottom,
  /// symmetrically, so the crop editor's centred guide stays the truth.
  static const Alignment imageAlignment = Alignment.center;

  static const double softFocusSigma = 14;

  /// Top-scrim strength at the status bar: white icons stay ≥ 4:1 over a
  /// pure-white photo in both themes (0.45 would fall to ~3:1).
  static const double topScrimAlpha = .55;
  static const double highContrastTopScrimAlpha = .72;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final blur = softFocus && !highContrast;

    final base = DecoratedBox(
      key: const ValueKey('profile-hero-base'),
      decoration: BoxDecoration(
        gradient: isDark
            ? kProfileBannerFallbackGradient
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(palette.backgroundTop, colors.primary, .16)!,
                  Color.lerp(palette.backgroundTop, colors.secondary, .07)!,
                  palette.backgroundTop,
                ],
              ),
      ),
    );

    Widget layers(
      BuildContext context,
      Widget image,
      ImageProvider<Object> provider,
    ) => _PhotoLayers(
      geometry: geometry,
      image: image,
      provider: provider,
      blur: blur,
      scrimAlpha: highContrast ? highContrastTopScrimAlpha : topScrimAlpha,
    );

    final local = localImage;
    final Widget photo = local != null
        ? _LocalHeroPhoto(image: local, fallback: base, layers: layers)
        : ProfileBanner(
            userId: userId,
            mediaRevision: mediaRevision,
            mediaService: mediaService,
            imageProvider: imageProvider,
            alignment: imageAlignment,
            fallback: base,
            imageLayerBuilder: layers,
          );

    Widget melted = ShaderMask(
      key: const ValueKey('profile-hero-melt'),
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => _bottomMelt(bounds, geometry.fade),
      child: photo,
    );
    if (geometry.sideFade > 0) {
      melted = ShaderMask(
        key: const ValueKey('profile-hero-side-melt'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => _sideMelt(bounds, geometry.sideFade),
        child: melted,
      );
    }
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.expand(child: ClipRect(child: melted)),
      ),
    );
  }

  static Shader _bottomMelt(Rect bounds, double fade) {
    final h = math.max(bounds.height, 1.0);
    double at(double fromBottom) => ((h - fromBottom) / h).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, at(fade), at(fade * .65), at(fade * .4), 1],
      colors: [
        _opaque,
        _opaque,
        _opaque.withValues(alpha: .45),
        _opaque.withValues(alpha: .10),
        _opaque.withValues(alpha: 0),
      ],
    ).createShader(bounds);
  }

  static Shader _sideMelt(Rect bounds, double extent) {
    final w = math.max(bounds.width, 1.0);
    final edge = (extent / w).clamp(0.0, .5);
    return LinearGradient(
      stops: [0, edge, 1 - edge, 1],
      colors: [
        _opaque.withValues(alpha: 0),
        _opaque,
        _opaque,
        _opaque.withValues(alpha: 0),
      ],
    ).createShader(bounds);
  }

  static const Color _opaque = _maskInk;
}

/// Ink for the `BlendMode.dstIn` alpha masks. Only its alpha channel is read,
/// so it is a paint atom, never a colour that reaches the screen.
const Color _maskInk = AppColors.black;

class _PhotoLayers extends StatelessWidget {
  const _PhotoLayers({
    required this.geometry,
    required this.image,
    required this.provider,
    required this.blur,
    required this.scrimAlpha,
  });

  final ProfileHeroGeometry geometry;
  final Widget image;
  final ImageProvider<Object> provider;
  final bool blur;
  final double scrimAlpha;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (blur)
          Positioned.fill(
            child: ShaderMask(
              key: const ValueKey('profile-hero-soft-focus'),
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => _softFocusRamp(bounds),
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: ProfileHeroBackdrop.softFocusSigma,
                    sigmaY: ProfileHeroBackdrop.softFocusSigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: Image(
                    image: provider,
                    fit: BoxFit.cover,
                    alignment: ProfileHeroBackdrop.imageAlignment,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: geometry.topScrimExtent,
          child: DecoratedBox(
            key: const ValueKey('profile-hero-top-scrim'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.scrim.withValues(alpha: scrimAlpha),
                  palette.scrim.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        // Light status icons while — and only while — the photo is under the
        // status bar. Sized, so scrolling the hero away hands the bar back to
        // the theme's own style.
        AnnotatedRegion<SystemUiOverlayStyle>(
          sized: true,
          value: AppTheme.systemOverlayStyle(Brightness.dark, palette),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }

  /// The blurred copy is invisible above the melt and fully in by the text
  /// line's upper half; the melt itself then dissolves it into the canvas.
  Shader _softFocusRamp(Rect bounds) {
    final h = math.max(bounds.height, 1.0);
    final fade = geometry.fade;
    final from = ((h - fade - 24) / h).clamp(0.0, 1.0);
    final to = ((h - fade * .55) / h).clamp(from, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, from, to, 1],
      colors: [
        _maskInk.withValues(alpha: 0),
        _maskInk.withValues(alpha: 0),
        _maskInk,
        _maskInk,
      ],
    ).createShader(bounds);
  }
}

/// The hero's photo when it is a local, not-yet-published pick.
class _LocalHeroPhoto extends StatelessWidget {
  const _LocalHeroPhoto({
    required this.image,
    required this.fallback,
    required this.layers,
  });

  final ImageProvider<Object> image;
  final Widget fallback;
  final ProfileMediaImageLayerBuilder layers;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        Image(
          image: image,
          fit: BoxFit.cover,
          alignment: ProfileHeroBackdrop.imageAlignment,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, synchronous) {
            final layered = layers(context, child, image);
            if (synchronous) return layered;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: AppMotion.resolve(context, AppMotion.standard),
              child: layered,
            );
          },
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// A sliver's content on the profile's reading measure while the scroll view
/// itself runs full width for the hero: [padding] is applied inside the
/// centred [maxWidth] column, which also stays clear of landscape safe-area
/// insets.
class ProfileMeasuredSliverPadding extends StatelessWidget {
  const ProfileMeasuredSliverPadding({
    required this.maxWidth,
    required this.padding,
    required this.sliver,
    super.key,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final column = ProfileHeroFrame.measure(
          width: width,
          maxWidth: maxWidth,
          safe: MediaQuery.paddingOf(context),
        );
        final right = math.max(0.0, width - column.left - column.width);
        return SliverPadding(
          padding: padding.copyWith(
            left: column.left + padding.left,
            right: right + padding.right,
          ),
          sliver: sliver,
        );
      },
    );
  }
}

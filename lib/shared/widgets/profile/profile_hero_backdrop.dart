import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// and the identity row (avatar, name, handle, presence) standing ON the
/// photo, which continues behind it as a blurred copy under a veil that
/// strengthens under the text (see [textLine], [nameLine] and [extent]).
/// Every number the own profile, the friend profile, the edit-profile
/// preview and the crop editor's "always visible" guide need is derived
/// here, so they cannot drift apart the way the old inset card and the crop
/// guide once did.
///
/// Height, for a backdrop `W` wide under a status bar `T` tall:
///
/// * ideal: `T + toolbarExtent + band`, with the band chosen by the
///   backdrop's own width (124 below 600, 156 below 1100, 176 above); past
///   [wideReferenceWidth] the height grows with the width, so a 2560 desktop
///   keeps the same share of the photo as a 1440 one instead of a sliver;
/// * never more than [maxViewportShare] of a short (landscape) viewport;
/// * never less than the toolbar plus a [minimumClearBand] of photo down to
///   the text line;
/// * never less than [alwaysVisibleFraction] of the photo's own height, so
///   the crop editor's guide is true in short windows too;
/// * and, above all of those, never narrower than the stored 16:9: the
///   height is capped at `W × 9 / 16`, so a phone shows the WHOLE banner
///   (nothing is ever cropped at the sides) and wider tiers crop only top
///   and bottom, around the centre.
///
/// That height is the PHOTO's box: where the sharp 16:9 image is drawn, the
/// banner's tap target and the crop guide's truth. The picture does not stop
/// there. The identity row starts on [textLine], inside the photo (on a
/// phone most of the avatar stands on it), its text on [nameLine], and the
/// backdrop keeps painting below the box — a blurred continuation of the
/// same image — down to [extent], under a veil that dissolves it into the
/// page (see [ProfileHeroBackdrop]).
///
/// The photo stays fully opaque down to `height − fade` and only then starts
/// to melt ([fade]). The melt never takes a larger share of the hero than it
/// does at the widest reference ([maxFadeShare]). Together with the floor
/// above that keeps the upper part of the crop guide
/// ([alwaysClearFraction]) above the melt at every size.
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
    required this.textLine,
    required this.nameLine,
    required this.extent,
  });

  /// Resolves the hero for a host [width] wide (the content column the route
  /// actually gets — beside the desktop sidebar, never the window).
  ///
  /// The backdrop always spans the whole host. [sideCanvas] is the page
  /// canvas actually left beside the host on each side (see
  /// [ResponsiveContentFrame.sideCanvasOf]); the photo melts into it only
  /// when there is at least [sideFadeExtent] of it, so it never fades
  /// against the desktop sidebar or the window edge. Without it, a host
  /// capped at the workbench width is compared against [windowWidth].
  /// [viewportHeight] caps a landscape phone.
  factory ProfileHeroGeometry.resolve({
    required double width,
    double topInset = 0,
    double? viewportHeight,
    double? windowWidth,
    double? sideCanvas,
  }) {
    final safeWidth = width.isFinite ? math.max(0.0, width) : 0.0;
    final backdropWidth = safeWidth;
    final (band, tierFade) = switch (backdropWidth) {
      < mediumBreakpoint => (narrowBand, narrowFade),
      < wideBreakpoint => (mediumBand, mediumFade),
      _ => (wideBand, wideFade),
    };
    final growth = math.max(1.0, backdropWidth / wideReferenceWidth);
    final ideal = topInset + (toolbarExtent + band) * growth;
    // The height at which the 16:9 photo exactly fills the width.
    final coverHeight = backdropWidth / ProfileImageRules.banner.aspectRatio;
    var cap = coverHeight;
    if (viewportHeight != null &&
        viewportHeight.isFinite &&
        viewportHeight > 0) {
      cap = math.min(cap, viewportHeight * maxViewportShare);
    }
    final floor =
        topInset + toolbarExtent + minimumClearBand + tierFade * textFadeShare;
    var height = math.max(floor, math.min(ideal, cap));
    height = math.max(height, coverHeight * alwaysVisibleFraction);
    height = math.min(height, coverHeight);
    final fade = math.min(tierFade, height * maxFadeShare);
    final veilTail = switch (backdropWidth) {
      < mediumBreakpoint => narrowVeilTail,
      < wideBreakpoint => mediumVeilTail,
      _ => wideVeilTail,
    };
    // The text keeps the line it has always had — the header is never
    // taller than before — but the photo no longer melts away above it: it
    // runs on behind the text under the veil (see ProfileHeroBackdrop).
    final nameLine = height - fade * textFadeShare;
    // The avatar rises beside it, [nameDrop] into the unveiled photo — but
    // never into the toolbar's clear band, and never below the text.
    final clearTop = topInset + toolbarExtent + minimumClearBand;
    final textLine = math.min(
      nameLine,
      math.max(nameLine - nameDrop, clearTop),
    );

    final double gap;
    if (sideCanvas != null && sideCanvas.isFinite) {
      gap = sideCanvas;
    } else if (windowWidth != null &&
        windowWidth.isFinite &&
        backdropWidth >= wideReferenceWidth) {
      gap = (windowWidth - backdropWidth) / 2;
    } else {
      gap = 0;
    }
    return ProfileHeroGeometry(
      width: safeWidth,
      backdropLeft: (safeWidth - backdropWidth) / 2,
      backdropWidth: backdropWidth,
      height: height,
      topInset: topInset,
      fade: fade,
      sideFade: gap >= sideFadeExtent ? sideFadeExtent : 0.0,
      textLine: textLine,
      nameLine: nameLine,
      extent: math.max(height, nameLine + veilTail),
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
      textLine: reference.textLine * scale,
      nameLine: reference.nameLine * scale,
      extent: reference.extent * scale,
    );
  }

  /// Toolbar row: 6 px air, a 44 px target row, 6 px air.
  static const double toolbarExtent = 56;

  /// The widest width at which the wide tier keeps its fixed height; wider
  /// heroes scale their height with the width (same visible share of the
  /// photo). Also the desktop shell's widest content column.
  static final double wideReferenceWidth =
      ResponsiveContentWidth.workbench.maxWidth;

  static const double mediumBreakpoint = 600;
  static const double wideBreakpoint = 1100;
  static const double narrowBand = 124;
  static const double mediumBand = 156;
  static const double wideBand = 176;
  static const double narrowFade = 96;
  static const double mediumFade = 104;
  static const double wideFade = 112;

  /// Photo kept between the toolbar and the text line (the avatar's top).
  ///
  /// This is NOT a promise of unaltered photo: part of the band is the top
  /// scrim. It is the air that keeps the avatar off the floating Back / Edit
  /// controls now that the avatar stands on the photo (it was 48 while the
  /// identity stood below the photo). The 16:9 cap wins over the height
  /// floor built on it, so on a very narrow phone under a tall status bar
  /// the band is smaller still; the text line never rises into the toolbar
  /// from 280 pt up.
  static const double minimumClearBand = 24;

  /// Over how much height above [nameLine] the veil closes, from the fully
  /// opaque photo to [ProfileHeroBackdrop.nameVeilPhotoAlpha] (never
  /// starting above the photo's melt, `height − fade`).
  static const double nameLead = 28;

  /// How far the avatar's top rises above the text, into the photo: over a
  /// third of a phone avatar, so the avatar clearly stands on the picture
  /// while the name sits beside it on the veil. The avatar's centre still
  /// sits in the lower half of the header (profile_header_layout_test).
  static const double nameDrop = 30;

  /// How far below [nameLine] the photo keeps going before it has fully
  /// dissolved into the page ([extent]): through the name, the handle, the
  /// presence chip and the rest of the avatar.
  static const double narrowVeilTail = 112;
  static const double mediumVeilTail = 120;
  static const double wideVeilTail = 128;

  /// A landscape phone must not spend more than this share of its height on
  /// imagery before any identity is drawn.
  static const double maxViewportShare = .45;

  static const double sideFadeExtent = 48;

  /// The largest share of the hero's height the bottom melt may take: its
  /// share at the widest reference (112 of 232). Heroes squeezed by a short
  /// viewport or a narrow window shorten the melt instead of letting it eat
  /// the photo's middle.
  static const double maxFadeShare = wideFade / (toolbarExtent + wideBand);

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

  /// Width of the left/right melt; 0 unless the host capped the column and
  /// left canvas beside it.
  final double sideFade;

  /// Where the identity row starts — the top of the avatar, standing on the
  /// photo. Nothing readable is drawn above [nameLine].
  final double textLine;

  /// Where the identity's text starts (the display name, and a Follow
  /// button beside it) — the line the whole identity started on while it
  /// stood below the photo, where that photo had melted to 10%. Now the
  /// photo runs on behind it, and from here down the veil keeps text
  /// legible: the photo is at most [ProfileHeroBackdrop.nameVeilPhotoAlpha]
  /// opaque on this line and at most [ProfileHeroBackdrop.textVeilPhotoAlpha]
  /// from [ProfileHeroBackdrop.nameVeilBand] below it.
  final double nameLine;

  /// How far the identity's text column starts below the avatar's top: the
  /// top padding hosts give the column beside the avatar.
  double get nameOffset => nameLine - textLine;

  /// Where the backdrop ends: the blurred continuation of the photo below
  /// its box has fully dissolved into the page canvas here. Never above
  /// [height]; the backdrop paints below its box down to this line.
  final double extent;

  /// Height of the top scrim that keeps status icons and the toolbar
  /// legible over a bright photo.
  double get topScrimExtent => math.min(height, topInset + topScrimReach);

  /// The hero's height at [wideReferenceWidth] on a desktop (no status bar).
  static double get widestHeight => toolbarExtent + wideBand;

  /// Share of the stored 16:9 banner's height that is on screen at every
  /// width: its share at [wideReferenceWidth], where it is smallest.
  /// Narrower heroes show more of the height, phones show all of it, wider
  /// heroes grow in proportion, and short windows are held at it by a floor.
  /// The band is centred (the photo is drawn with `Alignment.center`).
  static double get alwaysVisibleFraction =>
      ProfileImageRules.banner.aspectRatio /
      (wideReferenceWidth / widestHeight);

  /// The upper part of the [alwaysVisibleFraction] band that stays above the
  /// bottom melt at every width — the part a face or text can rely on. The
  /// rest of the band, below it, is on screen but fades into the page at the
  /// widest sizes.
  static double get alwaysClearFraction =>
      alwaysVisibleFraction * (widestHeight - wideFade) / widestHeight;

  @override
  bool operator ==(Object other) =>
      other is ProfileHeroGeometry &&
      other.width == width &&
      other.backdropLeft == backdropLeft &&
      other.backdropWidth == backdropWidth &&
      other.height == height &&
      other.topInset == topInset &&
      other.fade == fade &&
      other.sideFade == sideFade &&
      other.textLine == textLine &&
      other.nameLine == nameLine &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(
    width,
    backdropLeft,
    backdropWidth,
    height,
    topInset,
    fade,
    sideFade,
    textLine,
    nameLine,
    extent,
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

  /// Where the banner button draws its keyboard focus ring: inside the photo
  /// the user actually sees — below the status bar, above the text line and
  /// on the content column — so the ring never runs under the notch or as a
  /// hard line through the handle and presence row.
  EdgeInsets get bannerFocusInsets => EdgeInsets.fromLTRB(
    columnLeft + focusRingInset,
    geometry.topInset,
    columnRight + focusRingInset,
    math.max(0, geometry.height - geometry.textLine + focusRingInset),
  );

  static const double focusRingInset = 4;

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
///
/// The backdrop is painted first but read and focused LAST: it is one big
/// button from (0, 0) that would otherwise win both the geometric semantics
/// sort and the reading-order focus traversal. The order is pinned instead —
/// toolbar (Back, the page name, Edit), identity, footer, then the banner.
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

  /// Starts on [ProfileHeroGeometry.textLine] (the avatar's top); its text
  /// column starts [ProfileHeroGeometry.nameOffset] lower, on
  /// [ProfileHeroGeometry.nameLine]. Opaque to hit tests, so a tap
  /// between its words never falls through to the banner viewer.
  final ProfileHeroSlotBuilder identity;

  final ProfileHeroSlotBuilder? footer;

  /// Semantics and keyboard order of the hero's parts.
  static const double toolbarOrder = 0;
  static const double identityOrder = 1;
  static const double footerOrder = 2;
  static const double backdropOrder = 3;

  static Widget _ordered(double order, Widget child) => Semantics(
    container: true,
    explicitChildNodes: true,
    sortKey: OrdinalSortKey(order),
    child: FocusTraversalOrder(order: NumericFocusOrder(order), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final sideCanvas = ResponsiveContentFrame.sideCanvasOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final safe = MediaQuery.paddingOf(context);
        final window = MediaQuery.sizeOf(context);
        final geometry = ProfileHeroGeometry.resolve(
          width: constraints.maxWidth,
          topInset: safe.top,
          viewportHeight: window.height,
          windowWidth: window.width,
          sideCanvas: sideCanvas,
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
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _StretchingBackdropSlot(
                  geometry: geometry,
                  child: _ordered(backdropOrder, backdrop(context, frame)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: geometry.topInset),
                    SizedBox(
                      height: ProfileHeroGeometry.toolbarExtent,
                      child: _ordered(toolbarOrder, toolbar(context, frame)),
                    ),
                    SizedBox(
                      // Zero only on a hero narrower than any phone, where
                      // the 16:9 cap leaves no photo below the toolbar.
                      height: math.max(
                        0.0,
                        geometry.textLine -
                            geometry.topInset -
                            ProfileHeroGeometry.toolbarExtent,
                      ),
                    ),
                    _ordered(
                      identityOrder,
                      MetaData(
                        behavior: HitTestBehavior.opaque,
                        child: identity(context, frame),
                      ),
                    ),
                    if (footer != null)
                      _ordered(footerOrder, footer(context, frame)),
                  ],
                ),
              ],
            ),
          ),
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
/// Drawing only — the caller owns placement, the tap target and copy. The
/// widget's own box is the PHOTO's box ([ProfileHeroGeometry.height], plus
/// any bounce stretch); it paints on below that box, down to
/// [ProfileHeroGeometry.extent], so the picture stands behind the avatar,
/// the name and the handle while the box — the banner's tap target, and
/// the 16:9 the crop guide describes — stays the photo itself. Hosts must
/// not clip right under the box (the profile hero's Stack does not).
///
/// Layers, bottom to top:
///
/// 1. the no-photo base, shown while the grant is pending, when there is no
///    banner and when it failed: Dark keeps the brand fallback gradient;
///    Pearl gets a light theme wash, so a Pearl profile without a banner
///    never flashes a dark slab first. It fills the whole extent, so the
///    identity stands on the same veil in every state;
/// 2. the photo (`BoxFit.cover`, [imageAlignment]) in its box, fading in
///    over the base (instantly under Reduce Motion) together with everything
///    that belongs to it:
///    * a soft-focus copy of the same image (off under high contrast, or
///      when [softFocus] is false), masked in over the photo's bottom melt
///      and then CONTINUED below the box behind the identity — a mirrored
///      extension of the same blurred pixels, so there is no seam. It is
///      rendered ONCE per photo and width into a tiny pre-blurred bitmap
///      (one texel per [softFocusTexel] points) and simply drawn scaled up —
///      never an `ImageFiltered` or a `BackdropFilter` that a renderer
///      without a raster cache (Impeller, web CanvasKit) would re-run on
///      every scroll frame;
///    * a top scrim for the toolbar and the status bar, held at full
///      strength across the whole status-bar inset;
///    * a sized light status-bar region, only while the photo is on screen;
/// 3. the veil: an alpha mask that dissolves the whole stack into whatever
///    page canvas is underneath. The photo is fully opaque down to the start
///    of its melt — behind the top of the avatar — then
///    [nameVeilPhotoAlpha] on the name line, [textVeilPhotoAlpha] from
///    [nameVeilBand] below it (the handle and everything smaller), and gone
///    at the extent. That keeps the name at ≥ 3:1 (large text) and every
///    smaller text colour of the theme at ≥ 4.5:1 over a white or a black
///    photo in Dark and Pearl. Under high contrast the photo is gone before
///    the identity row: nothing of it stands on the photo. Hosts that
///    capped the column also get a side melt.
///
/// All of it sits in one [RepaintBoundary], so scrolling never rebuilds or
/// repaints the photo. The two alpha masks are still composited per frame on
/// renderers without a raster cache; nothing in the stack filters per frame.
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

  /// The blurred bottom and its continuation behind the identity. High
  /// contrast always turns it off. Without it the photo dissolves within its
  /// own box.
  final bool softFocus;

  /// Phones get the whole 16:9 banner; wider heroes crop only top and bottom,
  /// symmetrically, so the crop editor's centred guide stays the truth.
  static const Alignment imageAlignment = Alignment.center;

  /// Blur radius of the soft focus, in points.
  static const double softFocusSigma = 14;

  /// Points per texel of the pre-blurred soft-focus copy. Drawing that copy
  /// scaled up by this factor is most of the softness; [softFocusSigma] /
  /// [softFocusTexel] texels of blur, applied once, smooth the rest.
  static const double softFocusTexel = 7;

  /// How far above the melt the soft focus starts ramping in. Inside the
  /// photo's box the copy is drawn only over `fade + softFocusLead`.
  static const double softFocusLead = 24;

  /// Top-scrim strength, held across the whole status-bar inset and then
  /// faded out over [ProfileHeroGeometry.topScrimReach]. White status icons
  /// and the clock stay at least 4.5:1 over a pure-white photo: about 5.8:1
  /// on the Dark scrim and 5.2:1 on the Pearl one (0.55 gave Pearl 4.1:1 at
  /// the top pixel and under 3:1 lower in the bar, where it was fading).
  static const double topScrimAlpha = .62;
  static const double highContrastTopScrimAlpha = .72;

  /// Photo opacity left on [ProfileHeroGeometry.nameLine], where the display
  /// name starts. The name is large text (22–27 pt, w800), which needs 3:1;
  /// over a pure-white photo on the Dark canvas, or a pure-black one on the
  /// Pearl canvas, `textPrimary` keeps ≥ 3.6:1 here even on the friend
  /// profile's tinted canvas (≥ 4.1:1 on the plain one), and more below,
  /// where the veil keeps closing.
  static const double nameVeilPhotoAlpha = .45;

  /// Photo opacity from [nameVeilBand] below the name line down: the handle,
  /// the presence chip, the badges. `textSecondary` keeps ≥ 4.5:1 over a
  /// white photo in Dark and a black one in Pearl, on both canvases.
  static const double textVeilPhotoAlpha = .15;

  /// The name's first line: the handle never starts higher than this below
  /// the name line (a 22 pt name at line height 1.02, plus its 2 pt gap).
  static const double nameVeilBand = 22;

  /// Under high contrast the photo is gone this far above the identity row
  /// (the avatar's top), after a short melt: nothing of the identity stands
  /// on it.
  static const double highContrastTextGap = 8;
  static const double highContrastMelt = 24;

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

    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The photo's box: the geometry's height, plus the bounce stretch
          // when the host grows it upward.
          final box = constraints.biggest;
          final shift = box.height - geometry.height;
          // Below the box the soft copy continues the photo down to the
          // extent; without it the photo dissolves inside its own box.
          final below = blur ? geometry.extent - geometry.height : 0.0;
          final painted = Size(box.width, box.height + below);

          Widget layers(
            BuildContext context,
            Widget image,
            ImageProvider<Object> provider,
          ) => _PhotoLayers(
            geometry: geometry,
            photoHeight: box.height,
            image: image,
            provider: provider,
            blur: blur,
            scrimAlpha: highContrast
                ? highContrastTopScrimAlpha
                : topScrimAlpha,
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
            shaderCallback: (bounds) => _veil(
              bounds,
              meltStart: geometry.height - geometry.fade + shift,
              textLine: geometry.textLine + shift,
              nameLine: geometry.nameLine + shift,
              end: painted.height,
              highContrast: highContrast,
            ),
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
          return OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: painted.width,
            maxWidth: painted.width,
            minHeight: painted.height,
            maxHeight: painted.height,
            child: RepaintBoundary(child: ClipRect(child: melted)),
          );
        },
      ),
    );
  }

  /// The veil, in the painted box's coordinates (see the class doc).
  static Shader _veil(
    Rect bounds, {
    required double meltStart,
    required double textLine,
    required double nameLine,
    required double end,
    required bool highContrast,
  }) {
    final h = math.max(bounds.height, 1.0);
    var last = 0.0;
    // Stops must never run backwards, whatever a squeezed hero does.
    double at(double y) => last = (y / h).clamp(last, 1.0);
    final List<double> stops;
    final List<double> alphas;
    if (highContrast) {
      final gone = textLine - highContrastTextGap;
      stops = [0, at(gone - highContrastMelt), at(gone), 1];
      alphas = const [1, 1, 0, 0];
    } else {
      // Fully opaque down to the melt — never shorter than the crop guide's
      // clear part promises — then the veil keyed to the text.
      stops = [
        0,
        at(math.max(meltStart, nameLine - ProfileHeroGeometry.nameLead)),
        at(nameLine),
        at(nameLine + nameVeilBand),
        at(end),
        1,
      ];
      alphas = const [1, 1, nameVeilPhotoAlpha, textVeilPhotoAlpha, 0, 0];
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: stops,
      colors: [for (final alpha in alphas) _opaque.withValues(alpha: alpha)],
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
    required this.photoHeight,
    required this.image,
    required this.provider,
    required this.blur,
    required this.scrimAlpha,
  });

  final ProfileHeroGeometry geometry;

  /// Height of the photo's box (the top of this layer stack); the rest of
  /// the stack is the continuation below it.
  final double photoHeight;
  final Widget image;
  final ImageProvider<Object> provider;
  final bool blur;
  final double scrimAlpha;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scrimExtent = geometry.topScrimExtent;
    final hold = scrimExtent > 0
        ? (geometry.topInset / scrimExtent).clamp(0.0, 1.0)
        : 0.0;
    final softBand = math.min(
      photoHeight,
      geometry.fade + ProfileHeroBackdrop.softFocusLead,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final below = math.max(0.0, constraints.maxHeight - photoHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: photoHeight,
              child: image,
            ),
            if (blur && softBand > 0)
              _SoftFocusSource(
                provider: provider,
                texelWidth: math.max(
                  1,
                  (geometry.backdropWidth / ProfileHeroBackdrop.softFocusTexel)
                      .ceil(),
                ),
                builder: (context, soft) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: photoHeight - softBand,
                      height: softBand,
                      child: ShaderMask(
                        key: const ValueKey('profile-hero-soft-focus'),
                        blendMode: BlendMode.dstIn,
                        shaderCallback: _softFocusRamp,
                        child: ClipRect(
                          // The copy is laid out at the photo's box and
                          // bottom-aligned, so its pixels line up with the
                          // photo above it; only the band is drawn.
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            minWidth: width,
                            maxWidth: width,
                            minHeight: photoHeight,
                            maxHeight: photoHeight,
                            child: RawImage(
                              key: const ValueKey(
                                'profile-hero-soft-focus-copy',
                              ),
                              image: soft,
                              fit: BoxFit.cover,
                              alignment: ProfileHeroBackdrop.imageAlignment,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (below > 0 && soft != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        // Overlaps the band by a few rows of identical
                        // pixels: two anti-aliased edges meeting on a
                        // fractional row would let the base show through as
                        // a hairline.
                        top: photoHeight - _seamOverlap,
                        height: below + _seamOverlap,
                        child: CustomPaint(
                          key: const ValueKey('profile-hero-soft-extension'),
                          painter: _SoftExtensionPainter(
                            image: soft,
                            photoBox: Size(width, photoHeight),
                            top: photoHeight - _seamOverlap,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: scrimExtent,
              child: DecoratedBox(
                key: const ValueKey('profile-hero-top-scrim'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Full strength under the whole status bar, where the
                    // clock and the battery sit; only then fading out.
                    stops: [0, hold, 1],
                    colors: [
                      palette.scrim.withValues(alpha: scrimAlpha),
                      palette.scrim.withValues(alpha: scrimAlpha),
                      palette.scrim.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // Light status icons while — and only while — the photo is under
            // the status bar. Sized, so scrolling the hero away hands the bar
            // back to the theme's own style.
            AnnotatedRegion<SystemUiOverlayStyle>(
              sized: true,
              value: AppTheme.systemOverlayStyle(Brightness.dark, palette),
              child: const SizedBox.expand(),
            ),
          ],
        );
      },
    );
  }

  static const double _seamOverlap = 2;

  /// The soft copy is invisible at the top of its band and fully in by the
  /// old text line's upper half, so at the bottom of the photo's box it is
  /// all that is left and its continuation below starts without a seam.
  Shader _softFocusRamp(Rect bounds) {
    final h = math.max(bounds.height, 1.0);
    final fade = geometry.fade;
    final from = ((h - fade - ProfileHeroBackdrop.softFocusLead) / h).clamp(
      0.0,
      1.0,
    );
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

/// Continues the soft-focus copy below the photo's box: the same pre-blurred
/// bitmap, mapped exactly as `RawImage(fit: cover, alignment: center)` maps
/// it into the box, so at the box's bottom edge the pixels match. Where the
/// box cropped the photo (wide heroes) the rows it cut off come next; past
/// the image's own edge it is mirrored, which for a blur reads as the photo
/// simply going on. One shader draw, no filter.
class _SoftExtensionPainter extends CustomPainter {
  _SoftExtensionPainter({
    required this.image,
    required this.photoBox,
    required this.top,
  });

  final ui.Image image;
  final Size photoBox;

  /// Where this canvas starts, measured from the top of the photo's box.
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || photoBox.isEmpty) return;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, imageSize, photoBox);
    final source = ProfileHeroBackdrop.imageAlignment.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    final destination = ProfileHeroBackdrop.imageAlignment.inscribe(
      fitted.destination,
      Offset.zero & photoBox,
    );
    final scaleX = destination.width / source.width;
    final scaleY = destination.height / source.height;
    // Image pixels → this canvas, whose origin is [top] below the box's top.
    final matrix = Matrix4.identity()
      ..translateByDouble(
        destination.left - source.left * scaleX,
        destination.top - source.top * scaleY - top,
        0,
        1,
      )
      ..scaleByDouble(scaleX, scaleY, 1, 1);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..shader = ImageShader(
          image,
          TileMode.mirror,
          TileMode.mirror,
          matrix.storage,
          filterQuality: FilterQuality.medium,
        ),
    );
  }

  @override
  bool shouldRepaint(_SoftExtensionPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.photoBox != photoBox ||
      oldDelegate.top != top;
}

/// Resolves the hero photo's provider (an image-cache hit — no second fetch
/// or decode) and renders it once into a [texelWidth] wide, pre-blurred
/// bitmap for [builder]: the soft band inside the photo's box and its
/// continuation below share that one bitmap.
///
/// The one-off render is a few thousand pixels; every later frame is a plain
/// scaled image draw, whatever the renderer caches.
class _SoftFocusSource extends StatefulWidget {
  const _SoftFocusSource({
    required this.provider,
    required this.texelWidth,
    required this.builder,
  });

  final ImageProvider<Object> provider;
  final int texelWidth;
  final Widget Function(BuildContext context, ui.Image? soft) builder;

  @override
  State<_SoftFocusSource> createState() => _SoftFocusSourceState();
}

class _SoftFocusSourceState extends State<_SoftFocusSource> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _source;
  ui.Image? _soft;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(_SoftFocusSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _listen();
    } else if (oldWidget.texelWidth != widget.texelWidth) {
      _render();
    }
  }

  void _listen() {
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_stream?.key == stream.key) return;
    _stopListening();
    _stream = stream;
    final listener = _listener ??= ImageStreamListener(_onImage);
    stream.addListener(listener);
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    _source?.dispose();
    _source = info;
    _render();
  }

  void _render() {
    final source = _source?.image;
    if (source == null) return;
    final soft = renderProfileHeroSoftFocus(source, widget.texelWidth);
    if (!mounted) {
      soft.dispose();
      return;
    }
    setState(() {
      _soft?.dispose();
      _soft = soft;
    });
  }

  @override
  void dispose() {
    _stopListening();
    _source?.dispose();
    _soft?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _soft);
}

/// Renders [source] into a [texelWidth] wide copy with the source's aspect
/// ratio, blurred by [ProfileHeroBackdrop.softFocusSigma] expressed in
/// texels. Visible for tests; the caller owns (and disposes) the result.
@visibleForTesting
ui.Image renderProfileHeroSoftFocus(ui.Image source, int texelWidth) {
  final width = math.max(1, texelWidth);
  final height = math.max(1, (width * source.height / source.width).round());
  final sigma =
      ProfileHeroBackdrop.softFocusSigma / ProfileHeroBackdrop.softFocusTexel;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()
      ..filterQuality = FilterQuality.medium
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(width, height);
  } finally {
    picture.dispose();
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

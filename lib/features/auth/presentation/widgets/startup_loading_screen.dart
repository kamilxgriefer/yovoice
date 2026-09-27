import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

import 'startup_launch_copy.dart';

/// The app-owned startup surface, visible only while authentication resolves.
/// Its entrance and ambient motion never impose a minimum loading duration.
class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({this.headlineKey, super.key});

  /// An optional startup catalog key for deterministic previews and tests.
  /// Production uses the phrase selected once for this app launch.
  final String? headlineKey;

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entrance;
  late final Animation<double> _settle;
  late final AnimationController _ambient;
  bool _staticMotion = false;
  bool _tickersEnabled = true;
  bool _isForeground = true;

  /// This surface's part of the launch glint (refine-look W1): it waits for
  /// the backdrop light to reach the logo, follows it across the glass once
  /// and is then done for good. [_glintX] is the band's centre across the
  /// mark (−1 left edge, 1 right edge) while it crosses, `null` otherwise.
  _StartupGlintPhase _glintPhase = _StartupGlintPhase.pending;
  final ValueNotifier<double?> _glintX = ValueNotifier<double?>(null);

  /// Where the settled logo sits, recorded by the last layout so the glint
  /// can follow the artwork's light across it.
  _LogoPlacement? _logoPlacement;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _isForeground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      animationBehavior: AnimationBehavior.preserve,
    );
    _settle = _entrance.drive(CurveTween(curve: Curves.easeOutCubic));
    _ambient = AnimationController(
      vsync: this,
      // One shared clock: 6s drift, 4.5s light pass, 3.6s breathing and
      // 1.8s hairline sweeps all meet seamlessly at the end of this cycle.
      duration: const Duration(seconds: 18),
      animationBehavior: AnimationBehavior.preserve,
    )..addListener(_trackGlint);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _staticMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.highContrastOf(context);
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (_staticMotion) _endGlint();
    _updateAnimationState();
    // Warm the exact decode sizes of the mark and its bloom (refine-look §4)
    // for this viewport, so a resize or a rebuilt startup finds them ready.
    unawaited(
      YoBrandMark.precache(
        context,
        size: _StartupGeometry.logoSizeFor(
          MediaQuery.sizeOf(context),
          MediaQuery.textScalerOf(context),
        ),
        bloomScale: _StartupLight.bloomScale,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _updateAnimationState();
  }

  void _updateAnimationState() {
    if (_staticMotion) {
      _ambient.stop();
      _entrance.stop();
      _entrance.value = 1;
      return;
    }
    if (!_isForeground || !_tickersEnabled) {
      _ambient.stop();
      _entrance.stop();
      return;
    }
    if (!_entrance.isCompleted && !_entrance.isAnimating) {
      _entrance.forward();
    }
    if (!_ambient.isAnimating) _ambient.repeat();
  }

  /// Runs on the existing ambient clock (no ticker of its own).
  ///
  /// * A pass begins only as the light arrives at the logo's leading edge,
  ///   so a clock resumed half-way across (after a pause) waits for the
  ///   next pass instead of flashing mid-glass.
  /// * It claims the launch's one glint ([LaunchGlint]) only when the band
  ///   reaches the logo's centre. Until then it yields: if the sign-in
  ///   screen claims first — which is what happens when this surface is the
  ///   one being cross-faded away as the 1.4 s hold ends — the band is
  ///   withdrawn and the glint plays on the screen that stays.
  void _trackGlint() {
    if (_glintPhase == _StartupGlintPhase.done || _staticMotion) return;
    final placement = _logoPlacement;
    if (placement == null) return;
    final x = _StartupLight.logoGlintX(_ambient.value, placement);
    final onLogo = x.abs() <= LaunchGlint.reach;
    if (_glintPhase == _StartupGlintPhase.pending) {
      if (LaunchGlint.spent) {
        _glintPhase = _StartupGlintPhase.done;
        return;
      }
      if (!onLogo || x > -LaunchGlint.reach + LaunchGlint.entryWindow) return;
      _glintPhase = _StartupGlintPhase.crossing;
    }
    if (_glintPhase == _StartupGlintPhase.crossing) {
      if (LaunchGlint.spent) {
        _endGlint();
        return;
      }
      if (x >= 0 && LaunchGlint.claim()) {
        _glintPhase = _StartupGlintPhase.committed;
      }
    }
    if (onLogo) {
      _glintX.value = x;
    } else {
      _endGlint();
    }
  }

  /// Ends a pass on the logo (it crossed, it yielded, or motion became
  /// static). A pass that never began stays pending; one that began is
  /// never repeated.
  void _endGlint() {
    if (_glintPhase != _StartupGlintPhase.crossing &&
        _glintPhase != _StartupGlintPhase.committed) {
      return;
    }
    _glintPhase = _StartupGlintPhase.done;
    _glintX.value = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ambient.removeListener(_trackGlint);
    _entrance.dispose();
    _ambient.dispose();
    _glintX.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YoImmersiveDarkSurface(
    // Resolve typography and semantic colors inside the immersive theme.
    child: Builder(builder: _buildSurface),
  );

  Widget _buildSurface(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final key = widget.headlineKey ?? StartupLaunchCopy.headlineKey;
    final headline = _localizedStartupHeadline(copy, key);
    final status = copy.text('Opening YO Voice', 'Otwieranie YO Voice');
    final palette = AppPalette.of(context);
    final highContrast = MediaQuery.highContrastOf(context);

    return Semantics(
      localeForSubtree: copy.locale,
      child: Scaffold(
        backgroundColor: AppImmersiveColors.background,
        body: LayoutBuilder(
          builder: (context, viewport) => Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: _StartupBackdrop(
                  animation: _ambient,
                  staticMotion: _staticMotion,
                  highContrast: highContrast,
                ),
              ),
              ResponsiveContentFrame(
                key: const ValueKey('startup-content-frame'),
                width: ResponsiveContentWidth.form,
                padding: ResponsiveContentFrame.adaptivePagePadding(
                  viewport.maxWidth,
                ),
                child: LayoutBuilder(
                  builder: (context, frame) {
                    final media = MediaQuery.of(context);
                    final narrow = viewport.maxWidth < 600;
                    final wide = viewport.maxWidth >= 1100;
                    final viewportSize = Size(
                      viewport.maxWidth,
                      viewport.maxHeight,
                    );
                    final compact = _StartupGeometry.isCompact(
                      viewportSize,
                      media.textScaler,
                    );
                    final headlineWidth = math.min(
                      frame.maxWidth,
                      narrow ? 340.0 : (wide ? 560.0 : 520.0),
                    );
                    final wordmarkStyle = Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(
                          color: AppImmersiveColors.textPrimary,
                          fontSize: compact ? 28 : 36,
                          height: 1.2,
                          fontWeight: media.boldText
                              ? FontWeight.w700
                              : FontWeight.w800,
                          letterSpacing: 2.2,
                        );
                    final headlineStyle = Theme.of(context)
                        .textTheme
                        .displayLarge!
                        .copyWith(
                          color: AppImmersiveColors.textPrimary,
                          fontSize: narrow ? (compact ? 18 : 20) : 22,
                          height: 1.35,
                          // Text applies w700 for the system Bold Text
                          // setting. Measure that same weight before layout.
                          fontWeight: media.boldText
                              ? FontWeight.w700
                              : FontWeight.w500,
                          letterSpacing: 0,
                        );
                    final statusStyle = Theme.of(context).textTheme.bodySmall!
                        .copyWith(
                          color: highContrast
                              ? AppImmersiveColors.textPrimary
                              : AppImmersiveColors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: media.boldText
                              ? FontWeight.w700
                              : FontWeight.w400,
                        );
                    final direction = Directionality.of(context);
                    final geometry = _StartupGeometry.resolve(
                      viewportHeight: viewport.maxHeight,
                      safePadding: media.padding,
                      compact: compact,
                      logoSize: _StartupGeometry.logoSizeFor(
                        viewportSize,
                        media.textScaler,
                      ),
                      wordmarkHeight: _textHeight(
                        'YO VOICE',
                        wordmarkStyle,
                        frame.maxWidth,
                        TextScaler.noScaling,
                        direction,
                        copy.locale,
                      ),
                      headlineHeight: _textHeight(
                        headline,
                        headlineStyle,
                        headlineWidth,
                        media.textScaler,
                        direction,
                        copy.locale,
                      ),
                      statusHeight: _textHeight(
                        status,
                        statusStyle,
                        headlineWidth,
                        media.textScaler,
                        direction,
                        copy.locale,
                      ),
                    );
                    // A cache of the last layout for the glint, read on the
                    // next ambient tick; it never triggers a rebuild.
                    _logoPlacement = _LogoPlacement(
                      viewport: viewportSize,
                      centerY: geometry.logoTop + geometry.logoSize / 2,
                      size: geometry.logoSize,
                    );

                    return SingleChildScrollView(
                      key: const ValueKey('startup-content-scroll'),
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: frame.maxWidth,
                        height: geometry.contentHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              top: geometry.logoTop,
                              left: (frame.maxWidth - geometry.logoSize) / 2,
                              child: ExcludeSemantics(
                                child: AnimatedBuilder(
                                  animation: _settle,
                                  builder: (context, child) {
                                    final progress = _settle.value;
                                    final nativeOffset =
                                        viewport.maxHeight / 2 -
                                        geometry.logoTop -
                                        geometry.logoSize / 2;
                                    return Transform.translate(
                                      offset: Offset(
                                        0,
                                        nativeOffset * (1 - progress),
                                      ),
                                      child: Transform.scale(
                                        scale:
                                            170 / geometry.logoSize +
                                            (1 - 170 / geometry.logoSize) *
                                                progress,
                                        child: child,
                                      ),
                                    );
                                  },
                                  // The bloom and the glint ride inside
                                  // the same fly-in transform as the mark.
                                  child: RepaintBoundary(
                                    child: _StartupLogo(
                                      size: geometry.logoSize,
                                      ambient: _ambient,
                                      settle: _settle,
                                      staticMotion: _staticMotion,
                                      glintX: _glintX,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: FadeTransition(
                                opacity: _settle,
                                alwaysIncludeSemantics: true,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: geometry.wordmarkTop,
                                      left: 0,
                                      right: 0,
                                      child: ExcludeSemantics(
                                        child: RepaintBoundary(
                                          child: Text(
                                            'YO VOICE',
                                            key: const ValueKey(
                                              'startup-title',
                                            ),
                                            textAlign: TextAlign.center,
                                            textScaler: TextScaler.noScaling,
                                            style: wordmarkStyle,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: geometry.headlineTop,
                                      left:
                                          (frame.maxWidth - headlineWidth) / 2,
                                      width: headlineWidth,
                                      child: RepaintBoundary(
                                        child: Semantics(
                                          header: true,
                                          child: _StartupHeadline(
                                            text: headline,
                                            locale: copy.locale,
                                            style: headlineStyle,
                                            lilac:
                                                palette.interactiveForeground,
                                            highContrast: highContrast,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: geometry.statusTop,
                                      left:
                                          (frame.maxWidth - headlineWidth) / 2,
                                      width: headlineWidth,
                                      child: Semantics(
                                        key: const ValueKey('startup-status'),
                                        liveRegion: true,
                                        label: status,
                                        excludeSemantics: true,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            RepaintBoundary(
                                              child: CustomPaint(
                                                key: const ValueKey(
                                                  'startup-bottom-hairline',
                                                ),
                                                size: Size(
                                                  narrow ? 120 : 160,
                                                  20,
                                                ),
                                                painter: _StartupHairlinePainter(
                                                  animation: _ambient,
                                                  staticMotion: _staticMotion,
                                                  highContrast: highContrast,
                                                  lilac: palette
                                                      .interactiveForeground,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            RepaintBoundary(
                                              child: Text(
                                                status,
                                                locale: copy.locale,
                                                key: const ValueKey(
                                                  'startup-status-label',
                                                ),
                                                textAlign: TextAlign.center,
                                                style: statusStyle,
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localizedStartupHeadline(AppLocalizations copy, String key) =>
      switch (key) {
        'Your voice brings us closer.' => copy.text(
          'Your voice brings us closer.',
          'Twój głos nas zbliża.',
        ),
        'Good to hear you.' => copy.text(
          'Good to hear you.',
          'Dobrze Cię słyszeć.',
        ),
        'Every connection starts with a hello.' => copy.text(
          'Every connection starts with a hello.',
          'Każda znajomość zaczyna się od „cześć”.',
        ),
        _ => copy.text('Where conversation begins.', 'Tu zaczyna się rozmowa.'),
      };
}

double _textHeight(
  String text,
  TextStyle style,
  double width,
  TextScaler textScaler,
  TextDirection direction,
  Locale locale,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textAlign: TextAlign.center,
    textScaler: textScaler,
    locale: locale,
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Measures whole localized paragraphs before placing either text block. If
/// larger type needs more room, the complete composition becomes scrollable.
class _StartupGeometry {
  const _StartupGeometry({
    required this.logoSize,
    required this.logoTop,
    required this.wordmarkTop,
    required this.headlineTop,
    required this.statusTop,
    required this.contentHeight,
  });

  final double logoSize;
  final double logoTop;
  final double wordmarkTop;
  final double headlineTop;
  final double statusTop;
  final double contentHeight;

  /// Short viewports, and large text on phones, use the compact rhythm.
  static bool isCompact(Size viewport, TextScaler textScaler) =>
      viewport.height < 700 ||
      (viewport.width < 600 && textScaler.scale(34) > 46);

  /// The mark: 208 regular, 160 compact, 128 on very short viewports or at
  /// very large text.
  static double logoSizeFor(Size viewport, TextScaler textScaler) {
    if (!isCompact(viewport, textScaler)) return 208;
    return viewport.height < 620 || textScaler.scale(34) > 60 ? 128 : 160;
  }

  factory _StartupGeometry.resolve({
    required double viewportHeight,
    required EdgeInsets safePadding,
    required bool compact,
    required double logoSize,
    required double wordmarkHeight,
    required double headlineHeight,
    required double statusHeight,
  }) {
    // The canonical PNG has transparent lower padding. This tucks the
    // wordmark near the visible mark without overlapping the logo's ink.
    final logoToWordmark = compact ? -2.0 : -6.0;
    final headlineGap = compact ? 12.0 : 16.0;
    final footerGap = compact ? 24.0 : 32.0;
    final heroHeight =
        logoSize +
        logoToWordmark +
        wordmarkHeight +
        headlineGap +
        headlineHeight;
    final statusBlockHeight = 20 + 8 + statusHeight;
    final bottomSpace = math.max(safePadding.bottom + 32, viewportHeight * .09);
    final preferredStatusTop = viewportHeight - bottomSpace - statusBlockHeight;
    final minimumTop = safePadding.top + 16;
    final preferredLogoTop = viewportHeight * .43 - logoSize / 2;
    final logoTop = math.max(
      minimumTop,
      math.min(preferredLogoTop, preferredStatusTop - footerGap - heroHeight),
    );
    final wordmarkTop = logoTop + logoSize + logoToWordmark;
    final headlineTop = wordmarkTop + wordmarkHeight + headlineGap;
    final statusTop = math.max(
      preferredStatusTop,
      headlineTop + headlineHeight + footerGap,
    );
    return _StartupGeometry(
      logoSize: logoSize,
      logoTop: logoTop,
      wordmarkTop: wordmarkTop,
      headlineTop: headlineTop,
      statusTop: statusTop,
      contentHeight: math.max(
        viewportHeight,
        statusTop + statusBlockHeight + bottomSpace,
      ),
    );
  }
}

class _StartupHeadline extends StatelessWidget {
  const _StartupHeadline({
    required this.text,
    required this.locale,
    required this.style,
    required this.lilac,
    required this.highContrast,
  });

  final String text;
  final Locale locale;
  final TextStyle style;
  final Color lilac;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      locale: locale,
      key: const ValueKey('startup-headline'),
      textAlign: TextAlign.center,
      style: style,
    );
    if (highContrast) return label;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppImmersiveColors.textPrimary,
          AppImmersiveColors.textPrimary,
          lilac,
        ],
        stops: const [0, .4, 1],
      ).createShader(bounds),
      child: label,
    );
  }
}

class _StartupBackdrop extends StatelessWidget {
  const _StartupBackdrop({
    required this.animation,
    required this.staticMotion,
    required this.highContrast,
  });

  final Animation<double> animation;
  final bool staticMotion;
  final bool highContrast;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      key: const ValueKey('startup-background'),
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = animation.value;
            final brightness = _StartupLight.brightness(t, staticMotion);
            final lightCenter = _StartupLight.lightCenter(t);
            return Transform.translate(
              key: const ValueKey('startup-background-drift'),
              offset: staticMotion ? Offset.zero : _StartupLight.drift(t),
              child: Transform.scale(
                key: const ValueKey('startup-background-scale'),
                scale: staticMotion ? 1 : _StartupLight.scale(t),
                child: ShaderMask(
                  key: const ValueKey('startup-background-light'),
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment(lightCenter - .7, -.3),
                    end: Alignment(lightCenter + .7, .3),
                    // Lighting changes alpha only, never exceeding the
                    // contrast-safe brightness of the original artwork.
                    colors: staticMotion
                        ? const [Colors.white, Colors.white]
                        : [
                            Colors.white.withValues(alpha: .82 * brightness),
                            Colors.white.withValues(alpha: brightness),
                            Colors.white.withValues(alpha: .82 * brightness),
                          ],
                  ).createShader(bounds),
                  child: child,
                ),
              ),
            );
          },
          // Overscan covers both axes throughout the visible 6-second drift.
          // Only transforms change per frame; the decoded artwork is cached.
          child: OverflowBox(
            minWidth: constraints.maxWidth + _StartupLight.overscan,
            maxWidth: constraints.maxWidth + _StartupLight.overscan,
            minHeight: constraints.maxHeight + _StartupLight.overscan,
            maxHeight: constraints.maxHeight + _StartupLight.overscan,
            child: Opacity(
              // The glass edge can pass behind scaled or scrolled copy. Keep
              // a constant dark underlay so contrast survives every phase,
              // without adding a per-frame blur or a visible text panel.
              opacity: highContrast ? .16 : .62,
              child: RepaintBoundary(
                child: Image.asset(
                  'assets/images/startup_voice_glass_v1.webp',
                  key: const ValueKey('startup-background-art'),
                  width: constraints.maxWidth + _StartupLight.overscan,
                  height: constraints.maxHeight + _StartupLight.overscan,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _StartupHairlinePainter extends CustomPainter {
  _StartupHairlinePainter({
    required this.animation,
    required this.staticMotion,
    required this.highContrast,
    required this.lilac,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool staticMotion;
  final bool highContrast;
  final Color lilac;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final line = Rect.fromLTWH(0, centerY - .6, size.width, 1.2);
    final primary = highContrast ? AppImmersiveColors.textPrimary : lilac;
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: [
            primary.withValues(alpha: 0),
            primary.withValues(alpha: highContrast ? 1 : .65),
            primary,
            primary.withValues(alpha: highContrast ? 1 : .65),
            primary.withValues(alpha: 0),
          ],
          stops: const [0, .22, .5, .78, 1],
        ).createShader(line),
    );
    if (highContrast) return;

    final progress = staticMotion ? .5 : (animation.value * 10) % 1;
    final strength = math.pow(math.sin(math.pi * progress), 2).toDouble();
    final highlightWidth = size.width * .5;
    final highlightX =
        -highlightWidth / 2 + (size.width + highlightWidth) * progress;
    final glow = Rect.fromCenter(
      center: Offset(highlightX, centerY),
      width: highlightWidth,
      height: 6,
    );
    // A small painted gradient supplies the glow without a per-frame blur.
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.secondary.withValues(alpha: 0),
            AppColors.secondary.withValues(alpha: .65 * strength),
            AppColors.secondary.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    final highlight = Rect.fromCenter(
      center: Offset(highlightX, centerY),
      width: highlightWidth,
      height: 1.2,
    );
    canvas.drawRect(
      highlight,
      Paint()
        ..shader = LinearGradient(
          colors: [
            lilac.withValues(alpha: 0),
            AppImmersiveColors.textPrimary.withValues(alpha: strength),
            lilac.withValues(alpha: 0),
          ],
        ).createShader(highlight),
    );
  }

  @override
  bool shouldRepaint(_StartupHairlinePainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.staticMotion != staticMotion ||
      oldDelegate.highContrast != highContrast ||
      oldDelegate.lilac != lilac;
}

/// pending → crossing (on the logo, not yet claimed) → committed (claimed
/// at the logo's centre) → done.
enum _StartupGlintPhase { pending, crossing, committed, done }

/// The settled logo in the startup viewport: [centerY] from the top of the
/// viewport, [size] the mark box. The logo is always horizontally centred.
@immutable
class _LogoPlacement {
  const _LogoPlacement({
    required this.viewport,
    required this.centerY,
    required this.size,
  });

  final Size viewport;
  final double centerY;
  final double size;
}

/// The one ambient clock of the startup composition (ADR-052), read by the
/// artwork and by the logo so the bloom breathes with the art and the glint
/// rides the art's own light. `t` is the 18 s ambient cycle, 0..1.
abstract final class _StartupLight {
  /// The artwork overscan that covers its drift on both axes.
  static const double overscan = 64;

  /// The startup bloom box relative to the mark (312 / 240 / 192 px).
  static const double bloomScale = 1.5;

  /// Bloom opacity when motion is static (Reduce Motion, accessible
  /// navigation): the middle of the breath.
  static const double staticBloomOpacity = .42;

  static double _phase(double t) => t * math.pi * 6;

  /// The 6 s drift of the artwork.
  static Offset drift(double t) {
    final wave = math.sin(_phase(t));
    return Offset(wave * 12, wave * 20);
  }

  static double scale(double t) => 1.06 + math.sin(_phase(t)) * .02;

  /// The 3.6 s breath of the artwork's brightness.
  static double brightness(double t, bool staticMotion) =>
      staticMotion ? 1.0 : .91 + .09 * math.sin(t * math.pi * 10);

  /// The same breath as 0..1.
  static double breath(double t) => (math.sin(t * math.pi * 10) + 1) / 2;

  /// The 4.5 s light pass: the centre of the artwork's bright band, as an
  /// alignment x across the artwork (−2.4 → 2.4).
  static double lightCenter(double t) => -2.4 + ((t * 4) % 1) * 4.8;

  /// Bloom opacity: .34 + .16 × the breath, or a static .42.
  static double bloomOpacity(double t, bool staticMotion) =>
      staticMotion ? staticBloomOpacity : .34 + .16 * breath(t);

  /// Where the artwork's light crosses the settled logo, as an x alignment
  /// across the mark (−1 its left edge, 1 its right edge).
  ///
  /// The artwork's light is the peak of a linear gradient from
  /// `Alignment(c − .7, −.3)` to `Alignment(c + .7, .3)` over the overscanned
  /// artwork, drawn inside the drift and scale transforms. Its peak line is
  /// perpendicular to that direction, so it is followed down to the logo's
  /// own height before it is mapped into the mark's box.
  static double logoGlintX(double t, _LogoPlacement logo) {
    final art = Size(
      logo.viewport.width + overscan,
      logo.viewport.height + overscan,
    );
    final drift = _StartupLight.drift(t);
    final scale = _StartupLight.scale(t);
    final yOnArt = (logo.centerY - logo.viewport.height / 2 - drift.dy) / scale;
    final xOnArt =
        lightCenter(t) * art.width / 2 -
        yOnArt * (.3 * art.height) / (.7 * art.width);
    final xOnScreen = drift.dx + xOnArt * scale;
    return xOnScreen / (logo.size / 2);
  }
}

/// The startup mark: the real logo with its pre-baked bloom (W1) and, once
/// per launch, the glint that follows the artwork's light. The bloom
/// breathes with the artwork (no ticker of its own) and fades in with the
/// fly-in, so the first frame is exactly the native splash's bare mark.
class _StartupLogo extends StatelessWidget {
  const _StartupLogo({
    required this.size,
    required this.ambient,
    required this.settle,
    required this.staticMotion,
    required this.glintX,
  });

  final double size;
  final Animation<double> ambient;
  final Animation<double> settle;
  final bool staticMotion;
  final ValueListenable<double?> glintX;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([ambient, settle]),
              builder: (context, _) => YoBrandMark(
                key: const ValueKey('startup-logo'),
                size: size,
                light: YoBrandLight.bloom,
                bloomScale: _StartupLight.bloomScale,
                bloomOpacity:
                    _StartupLight.bloomOpacity(ambient.value, staticMotion) *
                    settle.value,
                bloomKey: const ValueKey('startup-logo-bloom'),
              ),
            ),
          ),
          Positioned.fill(
            child: ValueListenableBuilder<double?>(
              valueListenable: glintX,
              builder: (context, x, _) => x == null
                  ? const SizedBox.shrink()
                  : _LaunchGlintBand(
                      key: const ValueKey('startup-logo-glint'),
                      size: size,
                      x: x,
                      alpha:
                          LaunchGlint.peakAlpha *
                          _StartupLight.brightness(ambient.value, staticMotion),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The launch glint of refine-look W1: one pass of light across the real
/// logo's glass, at most once per app launch.
///
/// The startup surface glints when its artwork's light first crosses the
/// logo and claims the launch as the band passes the logo's centre; the auth
/// chain ([LaunchGlintMark]) claims at first paint and glints only if
/// startup has not. A startup band that has not reached the centre yields
/// to an auth claim (the startup is then the surface being cross-faded
/// away). Everyone after the claim shows the bloom alone. The band is drawn on the logo's alpha only:
/// white 0 → [peakAlpha] → 0, [bandWidth] of the mark wide, tilted [tilt].
/// There is never a glint under Reduce Motion, accessible navigation, a
/// paused [TickerMode] or high contrast.
abstract final class LaunchGlint {
  static bool _spent = false;

  /// The band's width relative to the mark.
  static const double bandWidth = .35;

  /// The band's lean from vertical ("/"), 20°.
  static const double tilt = 20 * math.pi / 180;

  /// The band's peak (white), before the startup breath scales it.
  static const double peakAlpha = .42;

  /// The band exists only while its centre is within ± [reach] of the
  /// mark's centre (in mark-width alignment units); beyond that it is off
  /// the logo's ink.
  static const double reach = 1.4;

  /// How far past the leading edge a pass may still begin (a few dropped
  /// frames on a fast desktop pass).
  static const double entryWindow = .5;

  /// Whether this launch's one glint has already run (or is running).
  static bool get spent => _spent;

  /// Claims this launch's glint; `false` once someone already has.
  static bool claim() {
    if (_spent) return false;
    _spent = true;
    return true;
  }

  /// A new launch, for tests and capture harnesses only.
  @visibleForTesting
  static void debugReset({bool spent = false}) => _spent = spent;

  /// The band's shader over a mark of [bounds], centred at [x] (−1..1 across
  /// the mark).
  static Shader band(Rect bounds, {required double x, required double alpha}) {
    final centre = bounds.center + Offset(x * bounds.width / 2, 0);
    final half = bounds.width * bandWidth / 2;
    final across = Offset(math.cos(tilt), math.sin(tilt)) * half;
    const light = AppColors.white;
    return ui.Gradient.linear(
      centre - across,
      centre + across,
      [
        light.withValues(alpha: 0),
        light.withValues(alpha: alpha.clamp(0.0, 1.0)),
        light.withValues(alpha: 0),
      ],
      const [0, .5, 1],
    );
  }
}

/// The real logo with its bloom that carries the launch glint when the
/// startup surface did not already spend it (refine-look §4, the auth
/// compact header and the wide brand panel).
///
/// The layout box is exactly [size] × [size] ([YoBrandMark]). One pass runs
/// [delay] after first paint over [AppMotion.glint] with
/// [AppMotion.glintCurve]; the whole run is [duration] (1.1 s), so a screen
/// that shows this mark settles within 1.2 s. The controller is released
/// after the run. The glint never starts under Reduce Motion, accessible
/// navigation, a paused [TickerMode] or high contrast, and one in flight
/// stops if any of them turns on.
class LaunchGlintMark extends StatefulWidget {
  const LaunchGlintMark({
    required this.size,
    this.glintKey = const ValueKey('auth-logo-glint'),
    super.key,
  });

  final double size;

  /// Marks the band while it is on the logo.
  final Key glintKey;

  /// The pause between first paint and the band setting off.
  static const Duration delay = Duration(milliseconds: 200);

  /// The whole run: [delay] then one [AppMotion.glint] pass.
  static const Duration duration = Duration(milliseconds: 1100);

  /// The band's centre across the mark at run progress [t] (0..1 over
  /// [duration]), or `null` while the run is still in its [delay].
  static double? bandX(double t) {
    final start = delay.inMicroseconds / duration.inMicroseconds;
    if (t < start) return null;
    final pass = ((t - start) / (1 - start)).clamp(0.0, 1.0);
    return -LaunchGlint.reach +
        2 * LaunchGlint.reach * AppMotion.glintCurve.transform(pass);
  }

  @override
  State<LaunchGlintMark> createState() => _LaunchGlintMarkState();
}

class _LaunchGlintMarkState extends State<LaunchGlintMark>
    with SingleTickerProviderStateMixin {
  AnimationController? _run;
  bool _considered = false;

  bool _motionAllowed() =>
      AppMotion.decorative(context) && !MediaQuery.highContrastOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = _motionAllowed();
    if (!_considered) {
      // Decided once, at first paint: a mark that could not glint then
      // (static motion, offstage) never glints later.
      _considered = true;
      if (allowed && LaunchGlint.claim()) {
        _run = AnimationController(
          vsync: this,
          duration: LaunchGlintMark.duration,
        )..addStatusListener(_handleStatus);
        _run!.forward();
      }
    } else if (!allowed) {
      _finish(rebuild: false);
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status.isCompleted) _finish();
  }

  /// Ends the run and releases its controller after this frame.
  void _finish({bool rebuild = true}) {
    final run = _run;
    if (run == null) return;
    run.stop();
    if (rebuild) {
      setState(() => _run = null);
    } else {
      _run = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => run.dispose());
  }

  @override
  void dispose() {
    _run?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: YoBrandMark(size: widget.size, light: YoBrandLight.bloom),
          ),
          if (run != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: run,
                builder: (context, _) {
                  final x = LaunchGlintMark.bandX(run.value);
                  if (x == null) return const SizedBox.shrink();
                  return _LaunchGlintBand(
                    key: widget.glintKey,
                    size: widget.size,
                    x: x,
                    alpha: LaunchGlint.peakAlpha,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The band itself: a second, bare copy of the mark whose alpha masks the
/// band (`srcIn`), laid exactly over the lit mark. That is the logo's own
/// glass catching the light, with nothing painted on the bloom; it repaints
/// in its own layer so the lit mark underneath never does.
class _LaunchGlintBand extends StatelessWidget {
  const _LaunchGlintBand({
    required this.size,
    required this.x,
    required this.alpha,
    super.key,
  });

  final double size;
  final double x;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            LaunchGlint.band(bounds, x: x, alpha: alpha),
        child: YoBrandMark(size: size, light: YoBrandLight.none),
      ),
    ),
  );
}

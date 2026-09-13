import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _staticMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.highContrastOf(context);
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _updateAnimationState();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entrance.dispose();
    _ambient.dispose();
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
                    final compact =
                        viewport.maxHeight < 700 ||
                        (narrow && media.textScaler.scale(34) > 46);
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
                      logoSize: compact
                          ? (viewport.maxHeight < 620 ||
                                    media.textScaler.scale(34) > 60
                                ? 128
                                : 160)
                          : 208,
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
                                  child: RepaintBoundary(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      key: const ValueKey('startup-logo'),
                                      width: geometry.logoSize,
                                      height: geometry.logoSize,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
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
            final phase = (staticMotion ? 0.0 : animation.value) * math.pi * 6;
            final brightness = staticMotion
                ? 1.0
                : .91 + .09 * math.sin(animation.value * math.pi * 10);
            final lightPosition = (animation.value * 4) % 1;
            final lightCenter = -2.4 + lightPosition * 4.8;
            return Transform.translate(
              key: const ValueKey('startup-background-drift'),
              offset: staticMotion
                  ? Offset.zero
                  : Offset(math.sin(phase) * 12, math.sin(phase) * 20),
              child: Transform.scale(
                key: const ValueKey('startup-background-scale'),
                scale: staticMotion ? 1 : 1.06 + math.sin(phase) * .02,
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
            minWidth: constraints.maxWidth + 64,
            maxWidth: constraints.maxWidth + 64,
            minHeight: constraints.maxHeight + 64,
            maxHeight: constraints.maxHeight + 64,
            child: Opacity(
              // The glass edge can pass behind scaled or scrolled copy. Keep
              // a constant dark underlay so contrast survives every phase,
              // without adding a per-frame blur or a visible text panel.
              opacity: highContrast ? .16 : .62,
              child: RepaintBoundary(
                child: Image.asset(
                  'assets/images/startup_voice_glass_v1.webp',
                  key: const ValueKey('startup-background-art'),
                  width: constraints.maxWidth + 64,
                  height: constraints.maxHeight + 64,
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

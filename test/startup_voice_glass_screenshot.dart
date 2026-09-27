// Explicit visual harness, intentionally outside the *_test.dart discovery.
// flutter test --concurrency=1 test/startup_voice_glass_screenshot.dart \
//   --dart-define=STARTUP_SCREENSHOT_DIR=/private/tmp/yovoice-startup-visual
//
// It renders the real StartupLoadingScreen with real fonts and writes PNGs
// named `startup_<width>_<dark|pearl>_<locale>_<text>_<state>[-hc]`. Startup
// is an immersive dark atom, so `dark` and `pearl` (the app theme around it)
// must look identical.
//
// Host independence: the output directory is the STARTUP_SCREENSHOT_DIR
// define, else the STARTUP_SCREENSHOT_DIR environment variable, else the old
// macOS default. Every named fallback family of `AppTypography` is backed by
// the first installed font that covers its script (macOS system fonts, then
// common Linux fonts), and 'Arial Unicode MS' by the STARTUP_FALLBACK_FONT
// define or environment variable when set. A family left unregistered falls
// through to the test font, which draws some Arabic and Han code points as
// solid boxes, so each one is registered rather than only the first found.
// The harness used to throw in setUpAll on any host without the macOS font;
// a host with none of the candidates now still renders (Inter covers Latin)
// and says which scripts may show boxes.
//
// The test framework paints every BoxShadow as a hard, unblurred block
// (`debugDisableShadows`); it is switched off while a frame is captured and
// restored before the case ends, so any shadow renders as on a device.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/translations_startup.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';

const _definedDirectory = String.fromEnvironment('STARTUP_SCREENSHOT_DIR');
const _defaultDirectory = '/private/tmp/yovoice-startup-visual';

String get _directory {
  if (_definedDirectory.isNotEmpty) return _definedDirectory;
  final environment = Platform.environment['STARTUP_SCREENSHOT_DIR'];
  if (environment != null && environment.isNotEmpty) return environment;
  return _defaultDirectory;
}

const _definedFallbackFont = String.fromEnvironment('STARTUP_FALLBACK_FONT');

String get _configuredFallbackFont {
  if (_definedFallbackFont.isNotEmpty) return _definedFallbackFont;
  return Platform.environment['STARTUP_FALLBACK_FONT'] ?? '';
}

const _macArialUnicode = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
const _dejaVuSans = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
const _freeSans = '/usr/share/fonts/truetype/freefont/FreeSans.ttf';
const _freeSerif = '/usr/share/fonts/truetype/freefont/FreeSerif.ttf';
const _wenQuanYi = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
const _unifont = '/usr/share/fonts/opentype/unifont/unifont.otf';

/// Each named fallback family of `AppTypography.fontFamilyFallback`, backed
/// by the first installed font that covers its script.
Map<String, List<String>> get _fallbackFamilies => {
  'Noto Sans Arabic': [
    '/System/Library/Fonts/SFArabic.ttf',
    '/System/Library/Fonts/GeezaPro.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
    _dejaVuSans,
    _macArialUnicode,
  ],
  'Noto Sans Hebrew': [
    '/System/Library/Fonts/SFHebrew.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf',
    _dejaVuSans,
    _freeSans,
    _macArialUnicode,
  ],
  'Noto Sans Devanagari': [
    '/System/Library/Fonts/Kohinoor.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf',
    _freeSans,
    _macArialUnicode,
  ],
  'Noto Sans Bengali': [
    '/System/Library/Fonts/KohinoorBangla.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansBengali-Regular.ttf',
    _freeSans,
    _macArialUnicode,
  ],
  'Noto Sans Thai': [
    '/System/Library/Fonts/Supplemental/Thonburi.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf',
    '/usr/share/fonts/opentype/tlwg/Loma.otf',
    _freeSerif,
    _macArialUnicode,
  ],
  for (final family in const [
    'Noto Sans SC',
    'Noto Sans TC',
    'Noto Sans JP',
    'Noto Sans KR',
  ])
    family: [
      '/System/Library/Fonts/PingFang.ttc',
      '/System/Library/Fonts/Hiragino Sans GB.ttc',
      _wenQuanYi,
      _unifont,
      _macArialUnicode,
    ],
  'Arial Unicode MS': [
    _configuredFallbackFont,
    _macArialUnicode,
    _freeSans,
    _dejaVuSans,
    _unifont,
  ],
};

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(
      File(path).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  await loader.load();
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
  await inter.load();
  // Back the same named fallbacks present in AppTypography with the host's
  // fonts. Do not ship a copy of a system font.
  final missing = <String>[];
  for (final MapEntry(key: family, value: paths) in _fallbackFamilies.entries) {
    final path = paths
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .firstOrNull;
    if (path == null) {
      missing.add(family);
      continue;
    }
    await _loadFont(family, path);
    // ignore: avoid_print
    print('fallback $family: $path');
  }
  if (missing.isNotEmpty) {
    // ignore: avoid_print
    print(
      'No font found for ${missing.join(', ')}; those scripts may show '
      'boxes. Set STARTUP_FALLBACK_FONT to a real multilingual font.',
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

/// The startup preview's host (`lib/dev/startup_voice_glass_preview.dart`)
/// with the app theme around it selectable, so Dark and Pearl are both
/// rendered rather than assumed.
class _StartupHost extends StatelessWidget {
  const _StartupHost({
    required this.locale,
    required this.headlineIndex,
    required this.textScale,
    required this.reducedMotion,
    required this.highContrast,
    required this.pearl,
    required this.safePadding,
    required this.repaintKey,
  });

  final Locale locale;
  final int headlineIndex;
  final double textScale;
  final bool reducedMotion;
  final bool highContrast;
  final bool pearl;
  final EdgeInsets safePadding;
  final Key repaintKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: resolveAppLocale,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => RepaintBoundary(
      key: repaintKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          accessibleNavigation: reducedMotion,
          highContrast: highContrast,
          textScaler: TextScaler.linear(textScale),
          padding: safePadding,
        ),
        child: child!,
      ),
    ),
    home: StartupLoadingScreen(
      headlineKey:
          startupHeadlineTranslationKeys[headlineIndex.clamp(
            0,
            startupHeadlineTranslationKeys.length - 1,
          )],
    ),
  );
}

typedef _Shot = ({
  Size size,
  Locale locale,
  int headline,
  double scale,
  bool reduced,
  bool contrast,
  bool pearl,
  String state,
  bool firstFrame,
  bool glint,
  bool sequence,
});

_Shot _shot(
  Size size, {
  Locale locale = const Locale('pl'),
  int headline = 0,
  double scale = 1,
  bool reduced = false,
  bool contrast = false,
  bool pearl = false,
  String? state,
  bool firstFrame = false,
  bool glint = false,
  bool sequence = false,
}) => (
  size: size,
  locale: locale,
  headline: headline,
  scale: scale,
  reduced: reduced,
  contrast: contrast,
  pearl: pearl,
  state:
      state ??
      (_compact(size, scale) ? 'compact' : 'regular') +
          (reduced ? '-reduced-motion' : ''),
  firstFrame: firstFrame,
  glint: glint,
  sequence: sequence,
);

/// The startup's own compact rule (short viewport, or large text on phones).
bool _compact(Size size, double scale) =>
    size.height < 700 || (size.width < 600 && 34 * scale > 46);

String _name(_Shot shot) {
  final theme = shot.pearl ? 'pearl' : 'dark';
  final locale = shot.locale.countryCode == null
      ? shot.locale.languageCode
      : '${shot.locale.languageCode}-${shot.locale.countryCode}';
  final text = (shot.scale * 100).round();
  return 'startup_${shot.size.width.toInt()}_${theme}_${locale}_${text}_'
      '${shot.state}${shot.contrast ? '-hc' : ''}';
}

final _shots = <_Shot>[
  // The matrix: 390 / 768 / 1440, Dark and Pearl, 100 and 200 %.
  for (final pearl in const [false, true]) ...[
    _shot(const Size(390, 844), pearl: pearl),
    _shot(const Size(390, 844), pearl: pearl, scale: 2),
    _shot(const Size(768, 1024), pearl: pearl),
    _shot(const Size(1440, 900), pearl: pearl),
    _shot(const Size(1440, 900), pearl: pearl, scale: 2),
  ],
  _shot(const Size(768, 1024), scale: 2),
  // Compact rhythms (160 and 128 marks).
  _shot(const Size(390, 667)),
  _shot(const Size(320, 568), headline: 3, scale: 2),
  // Frame 0 must be the native splash (170 px bare mark, centred).
  _shot(const Size(390, 844), state: 'frame0', firstFrame: true),
  _shot(const Size(1440, 900), state: 'frame0', firstFrame: true),
  // The launch's one glint, mid-pass (UNVERIFIED until seen on a device).
  _shot(const Size(390, 844), state: 'glint', glint: true),
  _shot(const Size(1440, 900), state: 'glint', glint: true),
  // The startup glint in motion (a launch whose startup stays up, e.g. a
  // signed-in bootstrap): 33 ms frames from just before the band reaches
  // the logo until just after it leaves, under `sequence/`.
  _shot(
    const Size(390, 844),
    state: 'glint-sequence',
    glint: true,
    sequence: true,
  ),
  _shot(
    const Size(1440, 900),
    state: 'glint-sequence',
    glint: true,
    sequence: true,
  ),
  // Static motion and high contrast.
  _shot(const Size(390, 844), reduced: true),
  _shot(const Size(390, 844), contrast: true),
  _shot(const Size(1440, 900), contrast: true),
  // Script and length spot checks kept from the original harness.
  _shot(
    const Size(390, 844),
    locale: const Locale('ar'),
    headline: 3,
    scale: 2,
  ),
  _shot(const Size(390, 844), locale: const Locale('he'), headline: 3),
  _shot(const Size(390, 844), locale: const Locale('hi'), headline: 3),
  _shot(const Size(390, 844), locale: const Locale('zh', 'CN'), headline: 3),
  _shot(
    const Size(430, 932),
    locale: const Locale('fil'),
    headline: 3,
    scale: 2,
  ),
  _shot(const Size(768, 1024), locale: const Locale('de'), headline: 3),
  _shot(const Size(1100, 850), headline: 1),
  _shot(const Size(1440, 900), locale: const Locale('en'), headline: 2),
  _shot(const Size(2560, 1440), locale: const Locale('en')),
];

/// How long the artwork's light takes to cross the settled mark: the light
/// moves 4.8 artwork half-widths per 4.5 s pass (the startup light clock).
Duration _estimatedGlintWindow(Size size, double markSize) {
  final unitsPerSecond =
      (4.8 / 4.5) * ((size.width + 64) / 2 * 1.06) / (markSize / 2);
  final seconds = 2 * LaunchGlint.reach / unitsPerSecond;
  return Duration(microseconds: (seconds * 1e6).round());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  for (final shot in _shots) {
    final name = _name(shot);
    testWidgets('renders $name with real fonts', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = shot.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      // Only the glint frames may glint; every other frame shows the bloom.
      LaunchGlint.debugReset(spent: !shot.glint);
      addTearDown(LaunchGlint.debugReset);
      debugDisableShadows = false;
      try {
        await _captureShot(tester, shot, name);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

Future<void> _captureShot(WidgetTester tester, _Shot shot, String name) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    _StartupHost(
      locale: shot.locale,
      headlineIndex: shot.headline,
      textScale: shot.scale,
      reducedMotion: shot.reduced,
      highContrast: shot.contrast,
      pearl: shot.pearl,
      safePadding: shot.size.width < 600
          ? const EdgeInsets.only(top: 44, bottom: 34)
          : EdgeInsets.zero,
      repaintKey: key,
    ),
  );
  final markSize = tester
      .getSize(find.byKey(const ValueKey('startup-logo')))
      .width;
  await tester.runAsync(() async {
    final context = key.currentContext!;
    await YoBrandMark.precache(context, size: markSize, bloomScale: 1.5);
    await precacheImage(
      const AssetImage('assets/images/startup_voice_glass_v1.webp'),
      context,
    );
  });
  if (shot.sequence) {
    tester.binding.scheduleFrame();
    await tester.pump(Duration.zero);
    await _captureGlintSequence(tester, key, name);
    await tester.pumpWidget(const SizedBox.shrink());
    return;
  }
  if (shot.firstFrame) {
    // Paint the first frame again, with no time elapsed, now that the
    // decoded images are in place.
    tester.binding.scheduleFrame();
    await tester.pump(Duration.zero);
    final mark = tester.getRect(find.byKey(const ValueKey('startup-logo')));
    // ignore: avoid_print
    print('$name: layout mark ${mark.size}');
    await _capture(tester, key, name);
    await tester.pumpWidget(const SizedBox.shrink());
    return;
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  expect(tester.takeException(), isNull);
  if (shot.glint) {
    final glint = find.byKey(const ValueKey('startup-logo-glint'));
    var waited = Duration.zero;
    while (glint.evaluate().isEmpty && waited < const Duration(seconds: 6)) {
      await tester.pump(const Duration(milliseconds: 16));
      waited += const Duration(milliseconds: 16);
    }
    expect(glint, findsOneWidget, reason: 'the first light pass glints');
    final window = _estimatedGlintWindow(shot.size, markSize);
    await tester.pump(
      Duration(microseconds: math.max(0, window.inMicroseconds ~/ 2)),
    );
    // ignore: avoid_print
    print(
      '$name: glint after ${waited.inMilliseconds} ms, window '
      '${window.inMilliseconds} ms, on screen: '
      '${glint.evaluate().isNotEmpty}',
    );
  }
  await _capture(tester, key, name);
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
  if (scroll.position.maxScrollExtent > 0) {
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await _capture(tester, key, '$name-scrolled');
  }
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
}

/// Steps the startup 33 ms at a time from its first frame and writes the
/// frames from four steps before the glint band reaches the logo until four
/// steps after it leaves, named `sequence/<name>_t<ms since first frame>ms`.
Future<void> _captureGlintSequence(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  const step = Duration(milliseconds: 33);
  const lead = 4;
  final glint = find.byKey(const ValueKey('startup-logo-glint'));
  final waiting = <(int, ui.Image)>[];
  var elapsed = 0;
  var seen = false;
  var trailing = 0;

  Future<void> write(int ms, ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final stamp = ms.toString().padLeft(4, '0');
      final file = File('$_directory/sequence/${name}_t${stamp}ms.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  while (elapsed < 8000 && trailing < lead) {
    await tester.pump(step);
    elapsed += step.inMilliseconds;
    final on = glint.evaluate().isNotEmpty;
    final image = (await tester.runAsync(() {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: 1);
    }))!;
    if (!seen && !on) {
      waiting.add((elapsed, image));
      if (waiting.length > lead) waiting.removeAt(0).$2.dispose();
      continue;
    }
    if (on && !seen) {
      seen = true;
      // ignore: avoid_print
      print('$name: band reaches the logo ${elapsed}ms after first frame');
    }
    if (seen && !on) trailing++;
    await tester.runAsync(() async {
      for (final (ms, frame) in waiting) {
        await write(ms, frame);
      }
      waiting.clear();
      await write(elapsed, image);
    });
  }
  for (final (_, frame) in waiting) {
    frame.dispose();
  }
  expect(seen, isTrue, reason: 'the startup glint plays once');
  // ignore: avoid_print
  print('$name: band gone ${elapsed}ms after first frame');
}

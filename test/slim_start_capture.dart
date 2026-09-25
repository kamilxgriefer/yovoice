// Developer-only "before/after" capture harness for Slim redesign phase 1
// (Start / Home). Not a *_test.dart file, so the regular suite ignores it.
//
// It boots the approved development harness lib/dev/redesign_preview.dart
// (real MobileHome / DesktopHome / DesktopSidebar / dock, in-memory fixtures
// through constructor seams) at exact logical viewports. Data state, locale
// and long names are the preview's own compile-time switches; theme and text
// scale are driven through the test platform dispatcher (the preview's
// YO_PREVIEW_THEME=system / YO_PREVIEW_TEXT=100 defaults follow the
// platform), so one compile covers the whole populated matrix.
//
//   flutter test test/slim_start_capture.dart --concurrency=1 \
//     --dart-define=YO_PREVIEW_TAB=home \
//     --dart-define=YO_PREVIEW_STATE=populated|empty|loading|error \
//     --dart-define=YO_PREVIEW_LOCALE=pl|en \
//     --dart-define=YO_PREVIEW_LONG_NAMES=true|false \
//     --dart-define=SLIM_CAPTURE_OUT=<dir> \
//     --dart-define=SLIM_CAPTURE_STATE=<file-name state label> \
//     --dart-define=SLIM_CAPTURE_MATRIX=full|pair|wide|single \
//     --dart-define=SLIM_CAPTURE_PAGES=<n> \\
//     --dart-define=SLIM_CAPTURE_SETTLE_MS=<ms, 2000+ for error> \\
//     --dart-define=YO_PREVIEW_LIVE_TYPE=friends|community|podcast|family|company
//     --dart-define=SLIM_CAPTURE_HC=true            (system high contrast)
//     --dart-define=SLIM_CAPTURE_FOCUS=<key>[,<key>] (keyboard-focus frames)
//
// YO_PREVIEW_LOCALE=ar renders the RTL spot check (the file name carries
// the locale). SLIM_CAPTURE_FOCUS moves keyboard focus to each keyed control
// after the page shots, with the keyboard highlight mode on, and writes
// `<base>-focus-<key>.png` — e.g. the "Tu i teraz" continue card
// (`home-server-continue-preview-friends`) and the live card
// (`home-live-preview-podcast-studio`).
//
// Refine-look additions (B2): the macOS colour-emoji font is registered when
// the host has it, so the greeting's wave never draws as a tofu box; and the
// test framework's default of painting every BoxShadow as a hard, unblurred
// block (`debugDisableShadows`, meant for golden stability) is switched off
// while a frame is captured and restored before the case ends, so the
// Pearl block shadows, the CTA lift and the LIVE under-glow render as they
// do on a device.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/dev/redesign_preview.dart' as preview;
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';

import 'support/material_icons_font.dart';

const _out = String.fromEnvironment('SLIM_CAPTURE_OUT');
const _stateLabel = String.fromEnvironment(
  'SLIM_CAPTURE_STATE',
  defaultValue: 'populated',
);
const _matrix = String.fromEnvironment(
  'SLIM_CAPTURE_MATRIX',
  defaultValue: 'single',
);
const _locale = String.fromEnvironment('YO_PREVIEW_LOCALE', defaultValue: 'pl');
const _pages = int.fromEnvironment('SLIM_CAPTURE_PAGES', defaultValue: 1);
// Extra real-clock wait before the first shot. The preview's error state
// delivers content first and fails the streams on a real 1.5 s timer, so an
// error capture needs SLIM_CAPTURE_SETTLE_MS >= 2000 or its first page still
// shows the populated data.
const _settleMs = int.fromEnvironment('SLIM_CAPTURE_SETTLE_MS');
const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';
const _arabicFont = '/System/Library/Fonts/SFArabic.ttf';
const _highContrast = bool.fromEnvironment('SLIM_CAPTURE_HC');
const _focusKeys = String.fromEnvironment('SLIM_CAPTURE_FOCUS');

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))
    ..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final bytes = ByteData.sublistView(emoji.readAsBytesSync());
    // The test renderer has no system font fallback, which a phone always
    // has for emoji. Register the host's colour-emoji font under its own
    // name and under the generic 'sans-serif' family that closes the app's
    // own `AppTypography.fontFamilyFallback` list, so a glyph Inter lacks
    // (the greeting's wave) falls back to it exactly as it would on a
    // device. The app's text styles are not touched.
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      final loader = FontLoader(family)..addFont(Future.value(bytes));
      await loader.load();
    }
    // ignore: avoid_print
    print('emoji font registered: $_emojiFont');
  } else {
    // ignore: avoid_print
    print('emoji font NOT available on this host: the greeting may show tofu');
  }
  // The RTL spot check (YO_PREVIEW_LOCALE=ar): Inter has no Arabic, and a
  // phone resolves the app's first fallback family ('Noto Sans Arabic') to
  // a system Arabic face. The host's Arabic system font stands in for it
  // under that name, so Arabic copy is drawn instead of tofu boxes.
  final arabic = File(_arabicFont);
  if (arabic.existsSync()) {
    final loader = FontLoader('Noto Sans Arabic')
      ..addFont(Future.value(ByteData.sublistView(arabic.readAsBytesSync())));
    await loader.load();
    // ignore: avoid_print
    print('arabic font registered: $_arabicFont');
  }
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(WidgetTester tester, Size size, String name) async {
  await tester.runAsync(() async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final warm = await layer.toImage(Offset.zero & size);
    warm.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await layer.toImage(Offset.zero & size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(_loadFonts);

  final heights = <int, double>{390: 844, 768: 1024, 1440: 900};
  final cells = <(int, Brightness, int)>[
    if (_matrix == 'full')
      for (final width in heights.keys)
        for (final brightness in [Brightness.dark, Brightness.light])
          for (final text in [100, 200]) (width, brightness, text)
    else if (_matrix == 'pair')
      // One phone cell per theme, for single-state evidence.
      for (final brightness in [Brightness.dark, Brightness.light])
        (390, brightness, 100)
    else if (_matrix == 'wide')
      // One desktop cell per theme (e.g. the keyboard-focus frames).
      for (final brightness in [Brightness.dark, Brightness.light])
        (1440, brightness, 100)
    else
      (390, Brightness.dark, 100),
  ];

  for (final (width, brightness, text) in cells) {
    final theme = brightness == Brightness.dark ? 'dark' : 'pearl';
    final base = 'start_${width}_${theme}_${_locale}_${text}_$_stateLabel';
    testWidgets(base, (tester) async {
      final size = Size(width.toDouble(), heights[width]!);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      tester.platformDispatcher.textScaleFactorTestValue = text / 100;
      if (_highContrast) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
      }
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      debugDisableShadows = false;
      try {
        await _capture(tester, size, base);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

/// One cell: boot the preview, settle, shoot page 1 and any further pages.
Future<void> _capture(WidgetTester tester, Size size, String base) async {
  await tester.runAsync(preview.main);
  await _pumpFrames(tester, 20);
  // Asset decodes (the atmosphere art, the brand mark) complete on the
  // real event loop; give them several real turns so the first frame is
  // not captured before the page background has painted.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await _pumpFrames(tester, 2);
  }
  if (_settleMs > 0) {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: _settleMs)),
    );
    await _pumpFrames(tester, 6);
  }

  final home = size.width >= 1100
      ? find.byType(DesktopHome)
      : find.byType(MobileHome);
  // ignore: avoid_print
  print('$base home-found=${home.evaluate().length}');
  final exception = tester.takeException();
  if (exception != null) {
    // ignore: avoid_print
    print('$base EXCEPTION: $exception');
  }
  await _shoot(tester, size, base);

  for (var page = 2; page <= _pages; page++) {
    final scrollables = find.descendant(
      of: home,
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    if (scrollables.evaluate().isEmpty) break;
    final state = tester.state<ScrollableState>(scrollables.first);
    final position = state.position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + size.height - 200).clamp(0, position.maxScrollExtent),
    );
    await _pumpFrames(tester, 4);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await _pumpFrames(tester, 2);
    await _shoot(tester, size, '$base-p$page');
  }

  for (final key in _focusKeys.split(',').where((k) => k.isNotEmpty)) {
    await _shootFocus(tester, size, base, key);
  }

  // Tear the preview down so its fixtures dispose before the next cell.
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpFrames(tester, 2);
}

/// Keyboard focus on the control keyed [key], in the keyboard highlight
/// mode, scrolled into view: `<base>-focus-<key>.png`.
Future<void> _shootFocus(
  WidgetTester tester,
  Size size,
  String base,
  String key,
) async {
  final target = find.byKey(ValueKey(key), skipOffstage: false);
  if (target.evaluate().isEmpty) {
    // ignore: avoid_print
    print('$base focus target not found: $key');
    return;
  }
  final strategy = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  try {
    await tester.ensureVisible(target);
    await _pumpFrames(tester, 4);
    final label = find
        .descendant(
          of: target,
          matching: find.byType(Text),
          skipOffstage: false,
        )
        .first;
    Focus.of(tester.element(label)).requestFocus();
    await _pumpFrames(tester, 4);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await _pumpFrames(tester, 2);
    await _shoot(tester, size, '$base-focus-$key');
  } finally {
    FocusManager.instance.highlightStrategy = strategy;
  }
}

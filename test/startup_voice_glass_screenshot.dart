// Explicit visual harness, intentionally outside the *_test.dart discovery.
// flutter test --concurrency=1 test/startup_voice_glass_screenshot.dart \
//   --dart-define=STARTUP_SCREENSHOT_DIR=/private/tmp/yovoice-startup-visual
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/dev/startup_voice_glass_preview.dart';

const _directory = String.fromEnvironment(
  'STARTUP_SCREENSHOT_DIR',
  defaultValue: '/private/tmp/yovoice-startup-visual',
);

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
  await inter.load();
  // Use the same named fallback present in AppTypography. Do not ship a copy
  // of the system font. For Linux CI supply a compatible installed font path.
  const fallback = String.fromEnvironment(
    'STARTUP_FALLBACK_FONT',
    defaultValue: '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  );
  if (!File(fallback).existsSync()) {
    throw StateError('Set STARTUP_FALLBACK_FONT to a real multilingual font.');
  }
  final loader = FontLoader('Arial Unicode MS')
    ..addFont(
      File(fallback).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  await loader.load();
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
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  final configurations =
      <
        ({
          String name,
          Size size,
          Locale locale,
          int headline,
          double scale,
          bool reduced,
          bool contrast,
        })
      >[
        (
          name: 'phone-390-pl',
          size: const Size(390, 844),
          locale: const Locale('pl'),
          headline: 0,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-320-pl-200',
          size: const Size(320, 568),
          locale: const Locale('pl'),
          headline: 3,
          scale: 2,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-390-ar-200',
          size: const Size(390, 844),
          locale: const Locale('ar'),
          headline: 3,
          scale: 2,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-390-he',
          size: const Size(390, 844),
          locale: const Locale('he'),
          headline: 3,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-390-hi',
          size: const Size(390, 844),
          locale: const Locale('hi'),
          headline: 3,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-390-zh',
          size: const Size(390, 844),
          locale: const Locale('zh', 'CN'),
          headline: 3,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-430-fil-200',
          size: const Size(430, 932),
          locale: const Locale('fil'),
          headline: 3,
          scale: 2,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'tablet-768-de',
          size: const Size(768, 1024),
          locale: const Locale('de'),
          headline: 3,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'wide-1100-pl',
          size: const Size(1100, 850),
          locale: const Locale('pl'),
          headline: 1,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'desktop-1440-en',
          size: const Size(1440, 900),
          locale: const Locale('en'),
          headline: 2,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'desktop-2560-en',
          size: const Size(2560, 1440),
          locale: const Locale('en'),
          headline: 0,
          scale: 1,
          reduced: false,
          contrast: false,
        ),
        (
          name: 'phone-reduced-motion',
          size: const Size(390, 844),
          locale: const Locale('pl'),
          headline: 0,
          scale: 1,
          reduced: true,
          contrast: false,
        ),
        (
          name: 'phone-high-contrast',
          size: const Size(390, 844),
          locale: const Locale('pl'),
          headline: 0,
          scale: 1,
          reduced: false,
          contrast: true,
        ),
      ];
  for (final shot in configurations) {
    testWidgets('renders ${shot.name} with real fonts', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = shot.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final key = GlobalKey();
      await tester.pumpWidget(
        StartupVoiceGlassPreview(
          locale: shot.locale,
          headlineIndex: shot.headline,
          textScale: shot.scale,
          reducedMotion: shot.reduced,
          highContrast: shot.contrast,
          safePadding: shot.size.width < 600
              ? const EdgeInsets.only(top: 44, bottom: 34)
              : EdgeInsets.zero,
          repaintKey: key,
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/images/logo.png'),
          key.currentContext!,
        );
        await precacheImage(
          const AssetImage('assets/images/startup_voice_glass_v1.webp'),
          key.currentContext!,
        );
      });
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _capture(tester, key, shot.name);
      if (shot.name == 'phone-390-pl') {
        await tester.pump(const Duration(milliseconds: 700));
        await _capture(tester, key, '${shot.name}-motion');
      }
      if (shot.name == 'phone-320-pl-200') {
        // Sample bright ribbon positions after the final typography/motion
        // change, not just the first frame, for the contrast review.
        for (var phase = 3; phase <= 15; phase += 3) {
          await tester.pump(const Duration(seconds: 3));
          await _capture(tester, key, '${shot.name}-phase-$phase');
        }
      }
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      if (scroll.position.maxScrollExtent > 0) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        await _capture(tester, key, '${shot.name}-scrolled');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

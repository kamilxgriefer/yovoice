// Developer-only VISUAL QA harness for YoFloatingNavigationDock.
//
// This intentionally is not a golden test: platform font rasterisation is not
// stable enough for a pixel baseline. It renders the production dock at the
// three shipping phone widths in Dark and Pearl, plus the 200% text-scale /
// 99+ unread edge case. Run explicitly:
//
//   flutter test test/dock_visual_qa_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).
//
// BASELINES (two docks, both production):
//
//  * `dock-*`  — the five-tab dock (Start · Serwery · Czaty · Momenty ·
//    Więcej), unchanged since 3.4.0. It remains the dock for every account
//    Premium Pages are not enabled for, so its frames and assertions stay.
//  * `dock6-*` — ADR-232, added 2026-09-28 with Premium Pages package C1:
//    six tabs (Treści between Czaty and Momenty), the whole dock at ×0.9,
//    the spec premium-pages §4.1.2 width regimes and the §4.1.3 expanded
//    mode. The reference is the owner-approved R1 render set
//    (`pages-r/dock/P_dock_*`); the frames cover 320 (Narrow B, 3 px margin,
//    39.6 bead), 340 (Narrow B), 360 and 390 (Regular, 43.2 bead), 430,
//    200 % text at 320 (expanded, 138.6 px, 12 px caption) and the RTL 99+
//    badge at 360. The six-tab geometry is asserted numerically in
//    test/yo_floating_navigation_dock_six_tab_test.dart; these frames are
//    for looking at.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';

const _officialLogo = 'assets/images/yo-voice-favicon-512.png';
const _momentsTabIndex = 5;

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

const _contentTabIndex = 14;

class _DockPreview extends StatelessWidget {
  const _DockPreview({
    required this.unreadConversationCount,
    this.sixTabs = false,
  });

  final int unreadConversationCount;
  final bool sixTabs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: YoFloatingNavigationDock(
        selectedTabIndex: sixTabs ? _contentTabIndex : _momentsTabIndex,
        roomsTabIndex: 13,
        momentsTabIndex: _momentsTabIndex,
        contentTabIndex: sixTabs ? _contentTabIndex : null,
        unreadConversationCount: unreadConversationCount,
        onDestinationSelected: (_) {},
        onVoicePressed: () {},
        onMorePressed: () {},
      ),
    );
  }
}

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required ThemeData theme,
  required double textScale,
  required int unreadConversationCount,
  bool sixTabs = false,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: textDirection,
            child: _DockPreview(
              unreadConversationCount: unreadConversationCount,
              sixTabs: sixTabs,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.runAsync(
    () => precacheImage(
      const AssetImage(_officialLogo),
      captureKey.currentContext!,
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(tester.takeException(), isNull);
}

Future<File> _shoot(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required String name,
}) async {
  late File file;
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
  return file;
}

void main() {
  setUpAll(_loadRealFonts);

  for (final (themeName, theme) in [
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    for (final width in [320.0, 390.0, 430.0]) {
      final label = 'dock-$themeName-resting-${width.toInt()}';
      testWidgets(label, (tester) async {
        final captureKey = GlobalKey();
        await _render(
          tester,
          captureKey: captureKey,
          size: Size(width, 180),
          theme: theme,
          textScale: 1,
          unreadConversationCount: 7,
        );

        final dockSize = tester.getSize(
          find.byKey(const ValueKey('yo-floating-navigation-dock')),
        );
        expect(dockSize.width, closeTo(math.min(460, width - 28), .01));
        expect(dockSize.height, YoFloatingNavigationDock.visualHeight);

        final file = await _shoot(tester, captureKey: captureKey, name: label);
        expect(file.existsSync(), isTrue);
      });
    }

    final label = 'dock-$themeName-resting-320-scale2-unread99plus';
    testWidgets(label, (tester) async {
      final captureKey = GlobalKey();
      await _render(
        tester,
        captureKey: captureKey,
        size: const Size(320, 260),
        theme: theme,
        textScale: 2,
        unreadConversationCount: 123,
      );

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('Moments'), findsOneWidget);
      final dockSize = tester.getSize(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      expect(dockSize.width, closeTo(292, .01));
      expect(dockSize.height, YoFloatingNavigationDock.accessibleVisualHeight);

      final file = await _shoot(tester, captureKey: captureKey, name: label);
      expect(file.existsSync(), isTrue);
    });

    for (final width in [320.0, 340.0, 360.0, 390.0, 430.0]) {
      final label = 'dock6-$themeName-content-${width.toInt()}';
      testWidgets(label, (tester) async {
        final captureKey = GlobalKey();
        await _render(
          tester,
          captureKey: captureKey,
          size: Size(width, 180),
          theme: theme,
          textScale: 1,
          unreadConversationCount: 2,
          sixTabs: true,
        );

        final regime = YoFloatingNavigationDock.sixTabRegimeFor(width);
        final dockSize = tester.getSize(
          find.byKey(const ValueKey('yo-floating-navigation-dock')),
        );
        expect(
          dockSize.width,
          closeTo(math.min(460, width - 2 * regime.margin), .01),
        );
        expect(dockSize.height, closeTo(82.8, .01));
        expect(
          tester.getSize(find.byKey(const ValueKey('yo-destination-0'))).width,
          greaterThanOrEqualTo(48),
        );

        final file = await _shoot(tester, captureKey: captureKey, name: label);
        expect(file.existsSync(), isTrue);
      });
    }

    final label6 = 'dock6-$themeName-content-320-scale2-unread99plus';
    testWidgets(label6, (tester) async {
      final captureKey = GlobalKey();
      await _render(
        tester,
        captureKey: captureKey,
        size: const Size(320, 240),
        theme: theme,
        textScale: 2,
        unreadConversationCount: 123,
        sixTabs: true,
      );

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      final dockSize = tester.getSize(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      expect(dockSize.width, closeTo(314, .01));
      expect(dockSize.height, greaterThanOrEqualTo(138.6 - .01));

      final file = await _shoot(tester, captureKey: captureKey, name: label6);
      expect(file.existsSync(), isTrue);
    });
  }

  testWidgets('dock6-dark-rtl-360-unread99plus', (tester) async {
    final captureKey = GlobalKey();
    await _render(
      tester,
      captureKey: captureKey,
      size: const Size(360, 180),
      theme: AppTheme.darkTheme,
      textScale: 1,
      unreadConversationCount: 123,
      sixTabs: true,
      textDirection: TextDirection.rtl,
    );
    expect(find.text('99+'), findsOneWidget);
    final file = await _shoot(
      tester,
      captureKey: captureKey,
      name: 'dock6-dark-rtl-360-unread99plus',
    );
    expect(file.existsSync(), isTrue);
  });
}

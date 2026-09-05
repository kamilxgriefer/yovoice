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

import 'dart:io';
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

class _DockPreview extends StatelessWidget {
  const _DockPreview({required this.unreadConversationCount});

  final int unreadConversationCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: YoFloatingNavigationDock(
        selectedTabIndex: 0,
        momentsTabIndex: _momentsTabIndex,
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
          child: _DockPreview(unreadConversationCount: unreadConversationCount),
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
        expect(dockSize.width, closeTo(width - 28, .01));
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
      expect(find.text('Home'), findsOneWidget);
      final dockSize = tester.getSize(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      expect(dockSize.width, closeTo(292, .01));
      expect(dockSize.height, YoFloatingNavigationDock.accessibleVisualHeight);

      final file = await _shoot(tester, captureKey: captureKey, name: label);
      expect(file.existsSync(), isTrue);
    });
  }
}

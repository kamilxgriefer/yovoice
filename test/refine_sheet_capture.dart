// Developer-only capture harness for the refine-look PRIMITIVES SAMPLE SHEET
// (lib/dev/refine_sheet_preview.dart). Not a *_test.dart file, so the regular
// suite ignores it; run it explicitly:
//
//   flutter test test/refine_sheet_capture.dart --concurrency=1 \
//     --dart-define=REFINE_SHEET_OUT=<dir>
//
// It renders the real widgets at a logical width of 430 and a device pixel
// ratio of 2 in Dark and Pearl at 100 % text, plus Dark at 200 % text, with
// the real Inter and Material Icons fonts. When the macOS colour-emoji font
// is present it is registered too, so an emoji never draws as a tofu box.
// Long sheets are split on SECTION boundaries into pages of at most 1800
// logical px: <name>-p1.png, <name>-p2.png, …

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/dev/refine_sheet_preview.dart';

import 'support/material_icons_font.dart';

const _out = String.fromEnvironment(
  'REFINE_SHEET_OUT',
  defaultValue: 'test/.screenshots/refine-sheet',
);
const double _width = 430;
const double _dpr = 2;
const double _maxPage = 1800;
const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';

final _capture = GlobalKey();

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))
    ..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final loader = FontLoader('Apple Color Emoji')
      ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync())));
    await loader.load();
    // ignore: avoid_print
    print('emoji font registered: $_emojiFont');
  } else {
    // ignore: avoid_print
    print('emoji font NOT available on this host');
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  // Asset decodes (the logo, its bloom) finish on the real event loop.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<double> _pumpSheet(
  WidgetTester tester, {
  required Brightness brightness,
  required double textScale,
  required double height,
  List<int>? sections,
  int page = 1,
  int pageCount = 1,
}) async {
  tester.view.physicalSize = Size(_width * _dpr, height * _dpr);
  tester.view.devicePixelRatio = _dpr;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: RefineSheetApp(
        key: ValueKey('$brightness-$textScale-$page-$sections'),
        brightness: brightness,
        textScale: textScale,
        sections: sections,
        page: page,
        pageCount: pageCount,
        scrollable: false,
      ),
    ),
  );
  await _settle(tester);
  return tester.getSize(find.byKey(RefineSheet.contentKey)).height;
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path} (${image.width}x${image.height})');
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final (name, brightness, textScale) in const [
    ('sheet_dark_100', Brightness.dark, 1.0),
    ('sheet_pearl_100', Brightness.light, 1.0),
    ('sheet_dark_200', Brightness.dark, 2.0),
  ]) {
    testWidgets(name, (tester) async {
      addTearDown(tester.view.reset);
      // The test binding replaces every BoxShadow with an unblurred solid
      // block (for golden stability). The whole point of this sheet is the
      // light, so draw real shadows and restore the flag before the test
      // ends (the binding verifies it).
      debugDisableShadows = false;
      try {
        // 1. Lay the whole sheet out once on a tall canvas and measure every
        //    section, then the running header of a continuation page.
        final count = RefineSheet.sectionCount;
        await _pumpSheet(
          tester,
          brightness: brightness,
          textScale: textScale,
          height: 20000,
        );
        final heights = <double>[
          for (var i = 0; i < count; i++)
            tester.getSize(find.byKey(RefineSheet.sectionKey(i))).height,
        ];
        final firstHeader = await _pumpSheet(
          tester,
          brightness: brightness,
          textScale: textScale,
          height: 4000,
          sections: const [],
        );
        final runningHeader = await _pumpSheet(
          tester,
          brightness: brightness,
          textScale: textScale,
          height: 4000,
          sections: const [],
          page: 2,
          pageCount: 9,
        );

        // 2. Pack whole sections into pages of at most 1800 logical px.
        final pages = <List<int>>[];
        var current = <int>[];
        var used = firstHeader;
        for (var i = 0; i < count; i++) {
          if (current.isNotEmpty && used + heights[i] > _maxPage) {
            pages.add(current);
            current = <int>[];
            used = runningHeader;
          }
          current.add(i);
          used += heights[i];
        }
        if (current.isNotEmpty) pages.add(current);
        // ignore: avoid_print
        print('$name pages: $pages');

        // 3. Render and capture each page at its exact height.
        for (var p = 0; p < pages.length; p++) {
          final measured = await _pumpSheet(
            tester,
            brightness: brightness,
            textScale: textScale,
            height: 4000,
            sections: pages[p],
            page: p + 1,
            pageCount: pages.length,
          );
          final height = measured.ceilToDouble();
          await _pumpSheet(
            tester,
            brightness: brightness,
            textScale: textScale,
            height: height,
            sections: pages[p],
            page: p + 1,
            pageCount: pages.length,
          );
          final exception = tester.takeException();
          if (exception != null) {
            // ignore: avoid_print
            print('$name-p${p + 1} EXCEPTION: $exception');
          }
          expect(exception, isNull);
          expect(height, lessThanOrEqualTo(_maxPage));
          await _shoot(tester, '$name-p${p + 1}');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

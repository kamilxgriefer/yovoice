// Developer-only visual capture for the More sheet's launcher tiles (R-10).
//
// Run explicitly:
//   flutter test test/more_sheet_tile_capture.dart
//
// PNGs land in test/.screenshots/more-sheet/ (git-ignored). The filename
// deliberately does not end in `_test.dart`, so the regular suite never
// writes screenshot artifacts.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

final _captureKey = GlobalKey();

class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

Future<ByteData> _read(String path) async {
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(_read('assets/fonts/InterVariable.ttf'))
    ..addFont(_read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(_read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _capturePng(WidgetTester tester, String filename) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;

    // Prime the font and icon atlases. Without this first raster pass a
    // headless engine can intermittently omit one glyph from the evidence.
    final warmup = await boundary.toImage(pixelRatio: 2);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/more-sheet/$filename.png');
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

  for (final (size, scale, name) in const <(Size, double, String)>[
    (Size(392.7, 844), 1.0, 'redmi-392dp-1x'),
    (Size(392.7, 844), 1.3, 'redmi-392dp-1.3x'),
    (Size(360, 800), 1.0, 'narrow-360dp-1x'),
    (Size(360, 800), 1.3, 'narrow-360dp-1.3x'),
    (Size(320, 640), 1.3, 'tiny-320dp-1.3x'),
    (Size(834, 1112), 1.0, 'tablet-834dp-1x'),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pl'),
          theme: AppTheme.darkTheme,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: _captureKey,
                child: Scaffold(
                  body: SizedBox.expand(
                    child: MoreSheet(
                      capabilityService: _NoStaffCapabilities(),
                      currentUid: 'ordinary-user',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capturePng(tester, name);
      expect(tester.takeException(), isNull);
    });
  }
}

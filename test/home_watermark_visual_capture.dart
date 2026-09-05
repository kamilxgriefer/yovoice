// Optional real-owner captures: flutter test --no-pub
// --dart-define=YO_CAPTURE_HOME_WATERMARK=true test/mobile_home_test.dart
// test/desktop_home_test.dart --plain-name 'production Home watermark'
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const captureHomeWatermark = bool.fromEnvironment('YO_CAPTURE_HOME_WATERMARK');

Future<void> loadHomeWatermarkFonts() async {
  if (!captureHomeWatermark) return;
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
  final icons = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ].map(File.new).firstWhere((file) => file.existsSync());
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
      .load();
}

Future<void> captureHomeWatermarkFrame(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!captureHomeWatermark) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

// Explicit visual capture of the production Moments feed and branded canvas.
// Run: flutter test --no-pub test/yo_page_background_visual_qa.dart
// Uses an honestly empty local discovery fixture, never a production write.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

class _EmptyDiscovery implements MomentDiscoveryService {
  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: const [],
    fetchedCount: 0,
    drops: const {},
    seed: seed ?? 1,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await inter.load();
    final iconFile = [
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '/usr/local/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ].map(File.new).firstWhere((file) => file.existsSync());
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
    await icons.load();
  });

  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 640), 2.0),
      (const Size(1440, 900), 1.0),
    ]) {
      testWidgets('$name ${size.width} x $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  appBar: AppBar(title: const Text('Your Moments')),
                  body: YoPageBackground(
                    section: YoPageSection.moments,
                    child: MomentsFeedView(
                      onRecord: () {},
                      discoveryService: _EmptyDiscovery(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            AssetImage(YoPageSection.moments.asset),
            capture.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('yo-atmosphere-moments')), findsOneWidget);
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'test/.screenshots/yo-watermark-$name-${size.width.toInt()}-${scale.toInt()}x.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      });
    }
  }
}

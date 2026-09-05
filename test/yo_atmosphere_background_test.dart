import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

Future<void> pumpScene(
  WidgetTester tester,
  YoPageSection section, {
  Brightness brightness = Brightness.dark,
  bool highContrast = false,
  Size size = const Size(390, 844),
  Widget child = const Text('Real page content'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          highContrast: highContrast,
          textScaler: const TextScaler.linear(2),
          disableAnimations: true,
        ),
        child: Scaffold(
          body: YoPageBackground(section: section, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('five local artworks fit a small total download budget', () {
    final assets = YoPageSection.values.map((section) => section.asset).toSet();
    expect(assets, hasLength(5));
    var bytes = 0;
    for (final asset in assets) {
      final file = File(asset);
      expect(file.existsSync(), isTrue, reason: asset);
      expect(file.lengthSync(), lessThan(100 * 1024));
      bytes += file.lengthSync();
    }
    expect(bytes, lessThan(300 * 1024));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/images/atmospheres/'),
    );
    expect(YoPageSection.rooms.asset, endsWith('rooms-lounge.webp'));
  });

  for (final brightness in Brightness.values) {
    test(
      'worst artwork pixel preserves text contrast in ${brightness.name}',
      () {
        final dark = brightness == Brightness.dark;
        final palette = dark ? AppPalette.dark : AppPalette.light;
        final opacity = dark
            ? YoAtmosphereArt.darkOpacity
            : YoAtmosphereArt.pearlOpacity;
        final pixel = dark ? Colors.white : Colors.black;
        for (final base in [
          palette.background,
          palette.backgroundTop,
          palette.surfaceRaised,
        ]) {
          final blended = Color.alphaBlend(
            pixel.withValues(alpha: opacity),
            base,
          );
          for (final foreground in [
            palette.textPrimary,
            palette.textSecondary,
          ]) {
            final values = [
              blended.computeLuminance(),
              foreground.computeLuminance(),
            ]..sort();
            expect(
              (values.last + .05) / (values.first + .05),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
      },
    );

    for (final section in YoPageSection.values) {
      testWidgets(
        '${section.name} ${brightness.name} one quiet bundled scene',
        (tester) async {
          await pumpScene(tester, section, brightness: brightness);
          final image = tester.widget<Image>(
            find.byKey(ValueKey('yo-atmosphere-${section.name}')),
          );
          expect(image.image, isA<ResizeImage>());
          final provider = image.image as ResizeImage;
          expect(provider.width, lessThanOrEqualTo(864));
          expect(
            (provider.imageProvider as AssetImage).assetName,
            section.asset,
          );
          expect(image.excludeFromSemantics, isTrue);
          expect(image.fit, BoxFit.cover);
          expect(find.byKey(const ValueKey('yo-page-watermark')), findsNothing);
          expect(find.text('Real page content'), findsOneWidget);
          expect(tester.binding.hasScheduledFrame, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('high contrast omits scenery rather than hiding content', (
    tester,
  ) async {
    await pumpScene(tester, YoPageSection.rooms, highContrast: true);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Real page content'), findsOneWidget);
  });

  testWidgets(
    'scenery does not block touches and nested feeds do not duplicate it',
    (tester) async {
      var taps = 0;
      await pumpScene(
        tester,
        YoPageSection.moments,
        child: YoPageBackground(
          section: YoPageSection.chats,
          child: Center(
            child: FilledButton(
              onPressed: () => taps++,
              child: const Text('Open real content'),
            ),
          ),
        ),
      );
      expect(find.byType(YoAtmosphereArt), findsOneWidget);
      expect(find.byKey(const ValueKey('yo-atmosphere-chats')), findsNothing);
      await tester.tap(find.text('Open real content'));
      expect(taps, 1);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('yo-atmosphere-moments')),
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('wide canvas bounds decoding and stays fixed during scroll', (
    tester,
  ) async {
    await pumpScene(
      tester,
      YoPageSection.home,
      size: const Size(2560, 1440),
      child: ListView.builder(
        itemCount: 80,
        itemExtent: 80,
        itemBuilder: (_, index) => Text('Item $index'),
      ),
    );
    final finder = find.byKey(const ValueKey('yo-atmosphere-home'));
    final before = tester.getRect(finder);
    expect((tester.widget<Image>(finder).image as ResizeImage).width, 864);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.getRect(finder), before);
    expect(tester.takeException(), isNull);
  });
}

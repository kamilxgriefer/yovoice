import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

const _mark = ValueKey('yo-page-watermark');

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Brightness brightness = Brightness.dark,
  bool highContrast = false,
  Size size = const Size(390, 844),
  Decoration? decoration,
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
          textScaler: const TextScaler.linear(2),
          highContrast: highContrast,
          disableAnimations: true,
        ),
        child: Scaffold(
          body: YoPageBackground(decoration: decoration, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final size in const [
      Size(320, 640),
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1100, 800),
      Size(1440, 900),
      Size(2560, 1440),
    ]) {
      testWidgets(
        'static ${brightness.name} canvas ${size.width} at 200% text',
        (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            size: size,
            child: const Center(child: Text('YO Voice')),
          );
          final image = tester.widget<Image>(find.byKey(_mark));
          expect(
            (image.image as AssetImage).assetName,
            YoPageBackground.logoAsset,
          );
          expect(
            image.opacity!.value,
            brightness == Brightness.dark ? .025 : .018,
          );
          expect(image.excludeFromSemantics, isTrue);
          expect(tester.getSize(find.byType(YoPageBackground)), size);
          expect(
            tester.getSize(find.byKey(_mark)).width,
            lessThanOrEqualTo(980),
          );
          expect(tester.binding.hasScheduledFrame, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }

    test('watermark preserves body-copy contrast in ${brightness.name}', () {
      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;
      final opacity = brightness == Brightness.dark ? .025 : .018;
      // Worst-case logo pixel: white on Dark, black on Pearl. Actual brand
      // pixels cannot cause a greater canvas luminance shift at this opacity.
      final pixel = brightness == Brightness.dark ? Colors.white : Colors.black;
      for (final base in [palette.background, palette.backgroundTop]) {
        final background = Color.alphaBlend(
          pixel.withValues(alpha: opacity),
          base,
        );
        for (final foreground in [palette.textPrimary, palette.textSecondary]) {
          final luminances = [
            foreground.computeLuminance(),
            background.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + .05) / (luminances.first + .05),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    });
  }

  testWidgets(
    'decoration is behind content and never intercepts taps or semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        child: Center(
          child: FilledButton(
            onPressed: () => taps++,
            child: const Text('Continue'),
          ),
        ),
      );
      expect(
        find.ancestor(
          of: find.byKey(_mark),
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(_mark),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Continue'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('embedded normal pages share one full-viewport mark', (
    tester,
  ) async {
    await _pump(
      tester,
      child: const YoPageBackground(
        child: Center(child: Text('Embedded feed')),
      ),
    );
    expect(find.byType(YoPageBackground), findsNWidgets(2));
    expect(find.byKey(_mark), findsOneWidget);
    expect(find.text('Embedded feed'), findsOneWidget);
  });

  testWidgets('high contrast omits nonessential artwork', (tester) async {
    await _pump(
      tester,
      highContrast: true,
      child: const Text('Readable content'),
    );
    expect(find.byKey(_mark), findsNothing);
    expect(find.text('Readable content'), findsOneWidget);
  });

  testWidgets(
    'preserves screen gradient and stays fixed while content scrolls',
    (tester) async {
      final decoration = BoxDecoration(
        gradient: AppPalette.dark.backgroundGradient,
      );
      await _pump(
        tester,
        decoration: decoration,
        child: ListView.builder(
          itemCount: 60,
          itemExtent: 80,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      );
      final canvas = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(YoPageBackground),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(canvas.decoration, same(decoration));
      final before = tester.getRect(find.byKey(_mark));
      await tester.drag(find.byType(ListView), const Offset(0, -380));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_mark)), before);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

void main() {
  Future<Rect> pumpFrame(
    WidgetTester tester, {
    required Size viewport,
    required ResponsiveContentWidth width,
    ResponsiveContentAlignment alignment = ResponsiveContentAlignment.topCenter,
  }) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResponsiveContentFrame(
            width: width,
            alignment: alignment,
            child: ColoredBox(
              key: const ValueKey('content'),
              color: Colors.purple,
              child: Column(
                children: const [Expanded(child: SizedBox.expand())],
              ),
            ),
          ),
        ),
      ),
    );

    return tester.getRect(find.byKey(const ValueKey('content')));
  }

  testWidgets('uses the full phone width and height', (tester) async {
    final rect = await pumpFrame(
      tester,
      viewport: const Size(390, 844),
      width: ResponsiveContentWidth.list,
    );

    expect(rect, const Rect.fromLTWH(0, 0, 390, 844));
  });

  testWidgets('centres bounded content on a wide desktop', (tester) async {
    final rect = await pumpFrame(
      tester,
      viewport: const Size(2560, 1440),
      width: ResponsiveContentWidth.feed,
    );

    expect(rect.width, 1040);
    expect(rect.left, 760);
    expect(rect.height, 1440);
  });

  testWidgets('keeps a bounded list aligned to the left', (tester) async {
    final rect = await pumpFrame(
      tester,
      viewport: const Size(1440, 900),
      width: ResponsiveContentWidth.list,
      alignment: ResponsiveContentAlignment.topLeft,
    );

    expect(rect, const Rect.fromLTWH(0, 0, 880, 900));
  });

  testWidgets('declares the shared responsive gutters', (tester) async {
    expect(
      ResponsiveContentFrame.adaptivePagePadding(390),
      const EdgeInsets.symmetric(horizontal: 16),
    );
    expect(
      ResponsiveContentFrame.adaptivePagePadding(768),
      const EdgeInsets.symmetric(horizontal: 24),
    );
    expect(
      ResponsiveContentFrame.adaptivePagePadding(1440),
      const EdgeInsets.symmetric(horizontal: 32),
    );
  });

  testWidgets(
    'shrink-wraps intrinsic bottom content when fillHeight is false',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(key: ValueKey('body')),
            bottomNavigationBar: ResponsiveContentFrame(
              fillHeight: false,
              width: ResponsiveContentWidth.form,
              child: SizedBox(key: ValueKey('bottom-content'), height: 60),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('bottom-content'))).height,
        60,
      );
      expect(tester.getSize(find.byKey(const ValueKey('body'))).height, 784);
    },
  );
}

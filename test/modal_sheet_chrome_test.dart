import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

Future<void> _pumpChrome(
  WidgetTester tester, {
  required Size size,
  required VoidCallback onClose,
  ThemeData? theme,
  Color surfaceColor = const Color(0xFF120D1A),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: surfaceColor,
            child: YoModalSheetChrome(
              sheetLabel: 'test sheet',
              surfaceColor: surfaceColor,
              onClose: onClose,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows one attached handle below the desktop breakpoint', (
    tester,
  ) async {
    await _pumpChrome(tester, size: const Size(390, 844), onClose: () {});

    expect(
      find.byKey(const ValueKey('modal-sheet-drag-handle')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('test sheet'), findsOneWidget);
    expect(find.bySemanticsLabel('Close test sheet'), findsOneWidget);
  });

  testWidgets('desktop uses a close action without a drag cue', (tester) async {
    await _pumpChrome(tester, size: const Size(1440, 900), onClose: () {});

    expect(find.byKey(const ValueKey('modal-sheet-drag-handle')), findsNothing);
    expect(find.bySemanticsLabel('Close test sheet'), findsOneWidget);
  });

  testWidgets('Close is a 44px named keyboard action', (tester) async {
    var closes = 0;
    await _pumpChrome(
      tester,
      size: const Size(390, 844),
      onClose: () => closes += 1,
    );

    final close = find.byKey(const ValueKey('modal-sheet-close'));
    final closeSize = tester.getSize(close);
    expect(closeSize.width, greaterThanOrEqualTo(44));
    expect(closeSize.height, greaterThanOrEqualTo(44));

    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Close test sheet'),
    );
    expect(
      semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(closes, 1);

    await tester.tap(close);
    await tester.pump();
    expect(closes, 2);
  });

  testWidgets('handle and Close contrast follow the real sheet surface', (
    tester,
  ) async {
    final cases = <(ThemeData, Color)>[
      (AppTheme.darkTheme, const Color(0xFF120D1A)),
      (AppTheme.lightTheme, const Color(0xFF120D1A)),
      (AppTheme.lightTheme, Colors.white),
    ];

    for (final (theme, surface) in cases) {
      await _pumpChrome(
        tester,
        size: const Size(390, 844),
        onClose: () {},
        theme: theme,
        surfaceColor: surface,
      );

      final handle = tester.widget<Container>(
        find.byKey(const ValueKey('modal-sheet-drag-handle')),
      );
      final handleColor = (handle.decoration! as BoxDecoration).color!;
      final paintedHandle = Color.alphaBlend(handleColor, surface);
      expect(_contrastRatio(paintedHandle, surface), greaterThanOrEqualTo(3));

      final close = tester.widget<IconButton>(
        find.byKey(const ValueKey('modal-sheet-close')),
      );
      final closeColor = close.style!.foregroundColor!.resolve({})!;
      expect(_contrastRatio(closeColor, surface), greaterThanOrEqualTo(3));
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';

void main() {
  testWidgets('keeps a 44px target while preserving a smaller visual size', (
    tester,
  ) async {
    var presses = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: YoIconButton(
              icon: Icons.settings_rounded,
              tooltip: 'Open settings',
              size: 30,
              focusNode: focusNode,
              onPressed: () => presses += 1,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(YoIconButton)), const Size(44, 44));
    expect(tester.getSize(find.byType(IconButton)), const Size(44, 44));
    expect(find.bySemanticsLabel('Open settings'), findsOneWidget);

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 1);
  });

  testWidgets('common navigation icons receive an inferred tooltip and label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YoIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            size: 40,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    await tester.longPress(find.byType(YoIconButton));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Back'), findsOneWidget);
  });
}

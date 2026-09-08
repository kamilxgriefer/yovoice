import 'dart:ui' as ui show Tristate;
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/inputs/yo_segmented_pill.dart';

const _first = ValueKey<String>('pill-first');
const _second = ValueKey<String>('pill-second');

Future<List<int>> _pump(
  WidgetTester tester, {
  int selectedIndex = 0,
  double? width,
  double textScale = 1,
  ThemeData? theme,
  Size viewport = const Size(390, 844),
}) async {
  final taps = <int>[];
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: viewport,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: YoSegmentedPill(
              width: width,
              segments: const <YoSegmentedPillSegment>[
                YoSegmentedPillSegment(
                  key: _first,
                  label: 'Discover',
                  icon: Icons.explore_outlined,
                ),
                YoSegmentedPillSegment(
                  key: _second,
                  label: 'Your Reels',
                  icon: Icons.person_outline_rounded,
                ),
              ],
              selectedIndex: selectedIndex,
              onSelected: taps.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  testWidgets('each segment is a button that reports its own selected state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    final first = tester.getSemantics(find.byKey(_first)).getSemanticsData();
    expect(first.label, 'Discover');
    expect(first.flagsCollection.isButton, isTrue);
    expect(first.flagsCollection.isSelected, ui.Tristate.isTrue);

    final second = tester.getSemantics(find.byKey(_second)).getSemanticsData();
    expect(second.label, 'Your Reels');
    expect(second.flagsCollection.isButton, isTrue);
    expect(second.flagsCollection.isSelected, ui.Tristate.isFalse);
    // A selected-looking button that assistive technology cannot press is not
    // a control; both segments keep their activation.
    expect(second.hasAction(SemanticsAction.tap), isTrue);
    expect(first.hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
  });

  testWidgets('assistive activation selects the segment it names', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final taps = await _pump(tester);

    tester.semantics.tap(find.semantics.byLabel('Your Reels'));
    await tester.pumpAndSettle();

    expect(taps, <int>[1]);
    semantics.dispose();
  });

  testWidgets('the keyboard can reach and activate a segment', (tester) async {
    final taps = await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(taps, <int>[1]);
  });

  testWidgets('both segments keep a 44 px target at a 200% text size', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.darkTheme, AppTheme.lightTheme]) {
      await _pump(
        tester,
        theme: theme,
        textScale: 2,
        width: double.infinity,
        viewport: const Size(390, 844),
      );

      for (final key in <Key>[_first, _second]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a tap on the selected segment changes nothing', (tester) async {
    final taps = await _pump(tester, selectedIndex: 1);

    await tester.tap(find.byKey(_second));
    await tester.pumpAndSettle();

    expect(taps, isEmpty);
  });

  testWidgets('segments share one width so the thumb slides', (tester) async {
    await _pump(tester);

    final first = tester.getSize(find.byKey(_first));
    final second = tester.getSize(find.byKey(_second));
    expect(first.width, closeTo(second.width, .01));
  });
}

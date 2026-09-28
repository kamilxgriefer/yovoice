// The additive AccessibleTapRegion API for ADR-230 (spec §5.0): with
// `onLongPress` and `customSemanticsActions` left null the region is exactly
// what it was — same size, same semantics — and when set they work.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

void main() {
  Future<void> pumpRegion(
    WidgetTester tester, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Map<CustomSemanticsAction, VoidCallback>? actions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AccessibleTapRegion(
              key: const ValueKey('region'),
              onTap: onTap ?? () {},
              semanticLabel: 'Like. Likes: 3',
              tooltip: 'Like',
              onLongPress: onLongPress,
              customSemanticsActions: actions,
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      ),
    );
  }

  SemanticsData dataOf(WidgetTester tester) => tester
      .getSemantics(find.bySemanticsLabel('Like. Likes: 3'))
      .getSemanticsData();

  testWidgets('null params: same size and the same semantics as before', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRegion(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('region'))),
        const Size(44, 44),
      );
      final data = dataOf(tester);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isFalse);
      expect(data.hasAction(SemanticsAction.customAction), isFalse);
      expect(data.customSemanticsActionIds ?? const <int>[], isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('onLongPress fires on a long press and leaves tap alone', (
    tester,
  ) async {
    var taps = 0;
    var longPresses = 0;
    await pumpRegion(
      tester,
      onTap: () => taps++,
      onLongPress: () => longPresses++,
    );
    await tester.longPress(find.byKey(const ValueKey('region')));
    await tester.pump();
    expect(longPresses, 1);
    expect(taps, 0);
    await tester.tap(find.byKey(const ValueKey('region')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });

  testWidgets('custom semantics actions are offered and performed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var opened = 0;
      const action = CustomSemanticsAction(label: 'See who liked');
      await pumpRegion(tester, actions: {action: () => opened++});
      final node = tester.getSemantics(find.bySemanticsLabel('Like. Likes: 3'));
      final ids = node.getSemanticsData().customSemanticsActionIds!;
      expect(
        ids.map((id) => CustomSemanticsAction.getAction(id)!.label),
        <String>['See who liked'],
      );
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        ids.single,
      );
      await tester.pump();
      expect(opened, 1);
    } finally {
      semantics.dispose();
    }
  });
}

// "See who liked" on the Yeel engagement bar (ADR-230, owner variant A):
// the rail's like COUNT is its own target that opens the list, the heart
// still only toggles, the panel gains a "Likes · N" entry, the footer keeps
// its fused control and offers the list as a screen-reader action. With no
// likes, or no host callback, every variant draws what it always did.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';

import 'support/likers_fixtures.dart';

const _like = ValueKey<String>('reel-like-action');
const _likers = ValueKey<String>('reel-likers-action');

void main() {
  late int likes;
  late int opens;

  setUp(() {
    likes = 0;
    opens = 0;
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required ReelEngagementBarVariant variant,
    Axis axis = Axis.vertical,
    int likeCount = 12,
    bool withLikers = true,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 700) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      likersHost(
        textScale: textScale,
        Scaffold(
          backgroundColor: Colors.blueGrey,
          body: Center(
            child: SizedBox(
              width: width - 20,
              child: Align(
                alignment: Alignment.centerRight,
                child: ReelEngagementBar(
                  likeCount: likeCount,
                  commentCount: 3,
                  liked: false,
                  variant: variant,
                  railAxis: axis,
                  onLike: () => likes++,
                  onComments: () {},
                  onShowLikers: withLikers ? () => opens++ : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The like control's own node, found by its spoken label (a tooltip
  /// above the region contributes no node, so the widget key would resolve
  /// to the enclosing one).
  SemanticsNode likeNode(WidgetTester tester) =>
      tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Like\. Likes:')));

  bool hasLikersAction(WidgetTester tester) {
    final data = likeNode(tester).getSemanticsData();
    return data.customSemanticsActionIds?.any((id) {
          final action = CustomSemanticsAction.getAction(id);
          return action?.label == 'See who liked';
        }) ??
        false;
  }

  group('rail, vertical', () {
    testWidgets('the heart toggles and the count opens the list', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(tester, variant: ReelEngagementBarVariant.rail);

      // The count moved out of the heart into its own target.
      expect(
        find.descendant(of: find.byKey(_like), matching: find.text('12')),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byKey(_likers), matching: find.text('12')),
        findsOneWidget,
      );
      final heart = tester.getRect(find.byKey(_like));
      final count = tester.getRect(find.byKey(_likers));
      expect(heart.size, const Size(48, 48));
      expect(count.width, greaterThanOrEqualTo(44));
      expect(count.height, greaterThanOrEqualTo(44));
      expect(count.top, greaterThanOrEqualTo(heart.bottom - .01));

      await tester.tap(find.byKey(_like));
      expect(likes, 1);
      expect(opens, 0);
      await tester.tap(find.byKey(_likers));
      expect(opens, 1);
      expect(likes, 1);

      final node = tester.getSemantics(
        find.bySemanticsLabel('See who liked. Likes: 12'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // One stop: the compact digits are not a second, action-less node
      // under the region (its label already carries the exact count).
      final labelledChildren = <String>[];
      node.visitChildren((child) {
        void collect(SemanticsNode n) {
          final label = n.getSemanticsData().label;
          if (label.isNotEmpty) labelledChildren.add(label);
          n.visitChildren((grandchild) {
            collect(grandchild);
            return true;
          });
        }

        collect(child);
        return true;
      });
      expect(labelledChildren, isEmpty);
      expect(find.bySemanticsLabel('12'), findsNothing);
      expect(hasLikersAction(tester), isTrue);
      semantics.dispose();
    });

    testWidgets('no likes: one fused control, no count target, no action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(
        tester,
        variant: ReelEngagementBarVariant.rail,
        likeCount: 0,
      );
      expect(find.byKey(_likers), findsNothing);
      expect(
        find.descendant(of: find.byKey(_like), matching: find.text('0')),
        findsOneWidget,
      );
      expect(tester.getSize(find.byKey(_like)), const Size(48, 68));
      expect(hasLikersAction(tester), isFalse);
      semantics.dispose();
    });

    testWidgets('no host callback: the rail is unchanged', (tester) async {
      await pumpBar(
        tester,
        variant: ReelEngagementBarVariant.rail,
        withLikers: false,
      );
      expect(find.byKey(_likers), findsNothing);
      expect(
        find.descendant(of: find.byKey(_like), matching: find.text('12')),
        findsOneWidget,
      );
      expect(tester.getSize(find.byKey(_like)), const Size(48, 68));
    });

    testWidgets('200 % text lays out without overflow', (tester) async {
      await pumpBar(
        tester,
        variant: ReelEngagementBarVariant.rail,
        likeCount: 2400,
        textScale: 2,
      );
      expect(find.text('2.4K'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('rail, horizontal', () {
    testWidgets('with room: the count sits beside the heart as its own '
        'target', (tester) async {
      await pumpBar(
        tester,
        variant: ReelEngagementBarVariant.rail,
        axis: Axis.horizontal,
      );
      final heart = tester.getRect(find.byKey(_like));
      final count = tester.getRect(find.byKey(_likers));
      expect(count.left, greaterThanOrEqualTo(heart.right - .01));
      expect((count.center.dy - heart.center.dy).abs(), lessThan(1));
      await tester.tap(find.byKey(_like));
      await tester.tap(find.byKey(_likers));
      expect(likes, 1);
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without room (showCounts false): plates only, the list is '
        'still a semantics action', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(
        tester,
        variant: ReelEngagementBarVariant.rail,
        axis: Axis.horizontal,
        width: 200,
      );
      expect(find.byKey(_likers), findsNothing);
      expect(find.text('12'), findsNothing);
      expect(hasLikersAction(tester), isTrue);
      await tester.tap(find.byKey(_like));
      expect(likes, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  });

  testWidgets('footer: heart and count stay one toggle; the list is a '
      'semantics action', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBar(tester, variant: ReelEngagementBarVariant.footer);
    expect(find.byKey(_likers), findsNothing);
    expect(
      find.descendant(of: find.byKey(_like), matching: find.text('12')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_like));
    expect(likes, 1);
    expect(hasLikersAction(tester), isTrue);
    semantics.dispose();
  });

  testWidgets('panel: the pills are unchanged and "Likes · N" opens the '
      'list', (tester) async {
    await pumpBar(tester, variant: ReelEngagementBarVariant.panel, width: 900);
    expect(find.byKey(_like), findsOneWidget);
    expect(find.text('Likes · 12'), findsOneWidget);
    await tester.tap(find.byKey(_like));
    expect(likes, 1);
    expect(opens, 0);
    await tester.tap(find.byKey(_likers));
    expect(opens, 1);

    await pumpBar(
      tester,
      variant: ReelEngagementBarVariant.panel,
      width: 900,
      likeCount: 0,
    );
    expect(find.byKey(_likers), findsNothing);
  });
}

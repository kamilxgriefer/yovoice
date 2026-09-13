// Board 06 — what the overview card and its columns hand to the platform.
//
// The accessibility audit found the largest target on the screen announcing
// no role and a name assembled from whatever loose text had not claimed a
// node (P1-4), a seek slider with no name at all (P1-5), and Tab crossing
// between the three columns seven times inside one card (P1-6). None of the
// existing suites could see any of it: they assert on labels and flags, and a
// pointer tap does not go through the accessibility bridge.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

import 'moments_overview_test_support.dart';

/// The rendered semantics tree, flattened. `tester.getSemantics` walks UP
/// from a widget's render object, so a node produced by a `Semantics` INSIDE
/// a keyed widget is not reachable through it; these cases look the node up
/// by what it announces, which is what a screen reader does too.
List<SemanticsData> _semanticsTree(WidgetTester tester) {
  final found = <SemanticsData>[];
  void visit(SemanticsNode node) {
    found.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  SemanticsNode? root;
  void visitOwner(PipelineOwner owner) {
    root ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(visitOwner);
  }

  visitOwner(tester.binding.rootPipelineOwner);
  expect(root, isNotNull, reason: 'semantics were not enabled');
  visit(root!);
  return found;
}

SemanticsData _nodeWhere(
  WidgetTester tester,
  bool Function(SemanticsData data) test,
  String what,
) {
  final matches = _semanticsTree(tester).where(test).toList();
  expect(matches, isNotEmpty, reason: 'no semantics node $what');
  return matches.first;
}

void main() {
  late VoidCallback restoreIdentity;

  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  Future<void> pumpFeed(
    WidgetTester tester, {
    required double slot,
    double height = 900,
    double textScale = 1,
  }) async {
    final size = Size(slot, height);
    useSurface(tester, size);
    final auth = authAs();
    final firestore = fakeFirestore();
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            onCreate: () {},
            discoveryService: StaticDiscovery(populatedPool()),
            feedService: QuietFeed(firestore: firestore, auth: auth),
            viewsService: StaticViews(const <String>{}),
            friendService: StaticFriends(
              firestore: firestore,
              auth: auth,
              friends: [friend('ola'), friend('bartek')],
            ),
            followService: FollowService(firestore: firestore, auth: auth),
            playerFactory: SilentPlayer.new,
          ),
        ),
        textScale: textScale,
        size: size,
      ),
    );
    await settleOverview(tester);
  }

  testWidgets('the card body is a named button, not the leftovers of the '
      'card', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFeed(tester, slot: 1200);

    expect(find.byKey(const ValueKey<String>('moment-row-m4')), findsOneWidget);
    final data = _nodeWhere(
      tester,
      (node) => node.label.startsWith('Open Voice Moment: '),
      'names the card the way the visual contract §7 asks — caption, author, '
      'relative time — instead of the loose text that did not claim a '
      'node of its own',
    );

    expect(
      data.flagsCollection.isButton,
      isTrue,
      reason: 'the 520x402 target used to carry no role at all',
    );
    expect(
      data.tooltip,
      isNot(contains('Reply with voice')),
      reason: 'nor the REPLY button tooltip it had borrowed',
    );
    handle.dispose();
  });

  testWidgets('the card seek slider carries its own name and both numbers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpFeed(tester, slot: 1200);

    expect(
      find.byKey(const ValueKey<String>('moment-row-progress-m4')),
      findsOneWidget,
    );
    final data = _nodeWhere(
      tester,
      (node) => node.flagsCollection.isSlider,
      'is a slider at all',
    );

    expect(
      data.label,
      'Playback position',
      reason:
          'the label used to merge into the card node, leaving the slider to '
          'reach the bridge unnamed and announcing only "0:00"',
    );
    expect(
      data.value,
      contains(' of '),
      reason:
          'a bare position tells a screen-reader user nothing about what '
          'is left',
    );
    handle.dispose();
  });

  testWidgets('the like control announces its liked state and the exact '
      'total', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFeed(tester, slot: 1200);

    final like = find.byKey(const ValueKey<String>('moment-row-like-m4'));
    expect(like, findsOneWidget);
    final data = _nodeWhere(
      tester,
      (node) =>
          node.flagsCollection.isButton &&
          (node.label == 'Like' || node.label.startsWith('Likes: ')),
      'names the like control with the exact total',
    );

    expect(
      data.flagsCollection.isSelected,
      isNot(Tristate.none),
      reason:
          'the glyph swap alone never announced the liked state; Reels has '
          'carried it since board 08',
    );
    // The row itself draws the number, which is what the board shows.
    expect(
      find.descendant(of: like, matching: find.byType(Text)),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('keyboard focus finishes a column before it moves to the next', (
    tester,
  ) async {
    await pumpFeed(tester, slot: 1200);

    // Walk the traversal and record which column each stop belongs to.
    final columns = <int>[];
    for (var step = 0; step < 18; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      final context = focused?.context;
      if (context == null) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final x = box.localToGlobal(Offset.zero).dx;
      // 0 = local panel, 1 = main column, 2 = calm panel.
      columns.add(x < 264 ? 0 : (x < 872 ? 1 : 2));
    }

    expect(columns, isNotEmpty, reason: 'nothing took focus at all');
    var crossings = 0;
    for (var i = 1; i < columns.length; i++) {
      if (columns[i] != columns[i - 1]) crossings++;
    }
    expect(
      crossings,
      lessThanOrEqualTo(2),
      reason:
          'one traversal group per column: the walk may leave a column once, '
          'never ping-pong between them (it crossed seven times inside a '
          'single card before). Visited: $columns',
    );
  });
}

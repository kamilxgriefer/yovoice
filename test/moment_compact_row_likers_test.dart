// "See who liked" on the Głos compact row (ADR-230, spec §5.1): the meta
// line's count stays inert (it is a span inside the row's one merged label,
// G4), so the list is reached from the ⋯ menu and from a screen-reader
// action. VIP → list, others → U1 upsell. No likes: neither is offered.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_compact_row.dart';

import 'support/likers_fixtures.dart';

VoiceMoment _moment({int likes = 3, bool published = true}) => VoiceMoment(
  id: 'm4',
  authorId: 'bartek',
  authorName: 'Bartek',
  authorPhotoUrl: null,
  caption: 'Krótko.',
  audioUrl: 'https://cdn.example/m4.m4a',
  durationSeconds: 12,
  likeCount: likes,
  commentCount: 0,
  isPublished: published,
  createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
);

void main() {
  late int likeTaps;

  setUp(() => likeTaps = 0);

  Future<ScriptedLikers> pumpRow(
    WidgetTester tester, {
    required bool vip,
    int likes = 3,
  }) async {
    tester.view.physicalSize = const Size(390, 400) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    void noop() {}
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: MomentCompactRow(
            key: const ValueKey('moment-row-m4'),
            moment: _moment(likes: likes),
            seen: false,
            isOwn: false,
            canInteract: true,
            canLike: true,
            likePending: false,
            current: ValueNotifier<String?>(null),
            playback: ValueNotifier<MomentFeedPlayback>(
              const MomentFeedPlayback(),
            ),
            lit: ValueNotifier<String?>(null),
            inset: 16,
            onRowBuild: (_, _) {},
            onRowDispose: (_, _) {},
            onTap: noop,
            onPlay: noop,
            onSeek: (_) {},
            onLike: () => likeTaps++,
            onComments: noop,
            onOpenChain: noop,
            onOpenDetail: noop,
            onShare: noop,
            onReport: noop,
            onDelete: noop,
            onReplyVoice: noop,
            onOpenProfile: noop,
            likersLauncher: testLikersLauncher(allowed: vip, script: script),
          ),
        ),
      ),
    );
    await tester.pump();
    return script;
  }

  Finder body() => find.byKey(const ValueKey('moment-row-body-m4'));

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  SemanticsNode rowNode(WidgetTester tester) =>
      tester.getSemantics(find.byKey(const ValueKey('moment-row-m4')));

  List<String> actionLabels(SemanticsNode node) => <String>[
    for (final id
        in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
      CustomSemanticsAction.getAction(id)!.label!,
  ];

  testWidgets('the ⋯ menu offers "See who liked"; a VIP gets the list', (
    tester,
  ) async {
    final script = await pumpRow(tester, vip: true);
    await tester.longPress(body());
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('moment-row-likers-m4'));
    expect(item, findsOneWidget);
    expect(find.text('See who liked'), findsOneWidget);
    await tester.tap(item);
    await settle(tester);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls.single.name, 'listVoiceMomentLikersV1');
    expect(script.calls.single.payload, <String, Object?>{'momentId': 'm4'});
    expect(likeTaps, 0);
  });

  testWidgets('a non-VIP choosing it gets the U1 upsell', (tester) async {
    final script = await pumpRow(tester, vip: false);
    await tester.longPress(body());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('moment-row-likers-m4')));
    await settle(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('the screen-reader action opens the flow; Like is still the '
      'like', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRow(tester, vip: true);
      final node = rowNode(tester);
      expect(
        actionLabels(node),
        containsAll(<String>['Like this Moment', 'See who liked']),
      );
      int idOf(String label) =>
          node.getSemanticsData().customSemanticsActionIds!.firstWhere(
            (id) => CustomSemanticsAction.getAction(id)!.label == label,
          );

      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        idOf('Like this Moment'),
      );
      await tester.pump();
      expect(likeTaps, 1);
      expect(find.byKey(kLikersListSurface), findsNothing);

      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        idOf('See who liked'),
      );
      await settle(tester);
      expect(find.byKey(kLikersListSurface), findsOneWidget);
      expect(likeTaps, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('no likes: neither the item nor the action exists', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRow(tester, vip: true, likes: 0);
      expect(actionLabels(rowNode(tester)), isNot(contains('See who liked')));
      await tester.longPress(body());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-details-m4')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moment-row-likers-m4')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}

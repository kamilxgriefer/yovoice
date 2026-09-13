import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';

import 'reel_stage_test_support.dart';

/// Board 08's footer bar: who published this Reel, whether you follow them,
/// what they wrote, and the four things you can do about it.
void main() {
  testWidgets('the author row opens the same profile seam as everywhere else', (
    tester,
  ) async {
    final opened = <Reel>[];
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(900, 1000),
      onOpenAuthor: (reel) => opened.add(reel as Reel),
    );

    expect(
      find.descendant(
        of: find.byKey(reelStageFooterKey),
        matching: find.text('Creator 1'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(reelStageFooterKey),
        matching: find.text('Creator 1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.authorId, 'creator_1');
  });

  testWidgets('four actions, each a 48 target, and no bookmark', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(tester, players: players, size: const Size(900, 1000));

    for (final key in <Key>[
      reelLikeKey,
      reelCommentsKey,
      reelShareKey,
      reelMoreKey,
    ]) {
      final finder = find.descendant(
        of: find.byKey(reelStageFooterKey),
        matching: find.byKey(key),
      );
      expect(finder, findsOneWidget, reason: '$key');
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
    }
    // D6: nothing saves a Reel, so nothing offers to.
    expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
    expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
    // The counts belong to the controls that count them.
    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(reelLikeKey),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data,
      '12',
    );
    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(reelCommentsKey),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data,
      '3',
    );
  });

  testWidgets('a long caption opens in place and says it is expanded', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(tester, players: players, size: const Size(900, 1000));

    final caption = find.byKey(reelStageCaptionKey);
    expect(caption, findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: caption, matching: find.byType(Text)),
          )
          .maxLines,
      2,
    );

    await tester.tap(caption);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.descendant(of: caption, matching: find.byType(Text)),
          )
          .maxLines,
      8,
    );
    // Reading a caption never disturbs the Reel.
    expect(players.of('reel_1').playing, isTrue);
    expect(players.of('reel_1').playCount, 1);
  });

  group('Obserwuj (D2)', () {
    testWidgets('is a real follow, guarded against a double submit', (
      tester,
    ) async {
      final gate = Completer<void>();
      final follows = reelFollowService(viewerUid: 'viewer', gate: gate);
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        followService: follows.service,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-follow-creator_1'),
      );
      expect(button, findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      // A second tap while the first is in flight must not reach the graph.
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(follows.mutations, hasLength(1));
      expect(follows.mutations.single['targetUserId'], 'creator_1');
      expect(follows.mutations.single['following'], isTrue);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets('reads the real edge for a creator you already follow', (
      tester,
    ) async {
      final follows = reelFollowService(
        viewerUid: 'viewer',
        following: const <String>{'creator_1'},
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        followService: follows.service,
      );

      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('an ineligible author exposes no new Follow action', (
      tester,
    ) async {
      final follows = reelFollowService(viewerUid: 'viewer');
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        followService: follows.service,
        creatorAudienceVisible: false,
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reel-follow-creator_1')),
          matching: find.byType(OutlinedButton),
        ),
        findsNothing,
      );
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('an audience projection error fails closed', (tester) async {
      final follows = reelFollowService(viewerUid: 'viewer');
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        followService: follows.service,
        creatorAudienceFails: true,
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reel-follow-creator_1')),
          matching: find.byType(OutlinedButton),
        ),
        findsNothing,
      );
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('an ineligible author keeps only reliable Following/Unfollow', (
      tester,
    ) async {
      final follows = reelFollowService(
        viewerUid: 'viewer',
        following: const <String>{'creator_1'},
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        followService: follows.service,
        creatorAudienceVisible: false,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-follow-creator_1'),
      );
      expect(button, findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Follow'), findsNothing);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(follows.mutations, [
        {'targetUserId': 'creator_1', 'following': false},
      ]);
    });

    testWidgets('is absent on your own Reel', (tester) async {
      final follows = reelFollowService(viewerUid: 'creator_1');
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        service: reelStageService(count: 2, viewerUid: 'creator_1'),
        followService: follows.service,
      );

      expect(
        find.byKey(const ValueKey<String>('reel-follow-creator_1')),
        findsNothing,
      );
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('is absent where the follow graph is unavailable', (
      tester,
    ) async {
      // A host with no graph draws no control rather than a button whose only
      // possible answer is a failure.
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
      );

      expect(find.text('Follow'), findsNothing);
      expect(find.byKey(reelStageFooterKey), findsOneWidget);
    });
  });
}

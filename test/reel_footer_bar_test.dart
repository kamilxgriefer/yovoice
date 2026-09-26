import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';

import 'reel_stage_test_support.dart';

/// Board 08's footer bar: who published this Reel, whether you can add them,
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

  testWidgets('photo cards omit the numeric clock but keep progress', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(900, 1000),
      photo: true,
    );

    expect(find.byKey(reelProgressBarKey), findsOneWidget);
    expect(find.byKey(reelProgressTimesKey), findsNothing);
  });

  testWidgets('video cards retain the numeric playback clock', (tester) async {
    final players = FakeReelPlayers();
    await pumpReelStage(tester, players: players, size: const Size(900, 1000));

    expect(find.byKey(reelProgressBarKey), findsOneWidget);
    expect(find.byKey(reelProgressTimesKey), findsOneWidget);
  });

  group('Add friend', () {
    testWidgets('shares one sent state across two Yeels by the same author', (
      tester,
    ) async {
      final friends = reelFriendService(viewerUid: 'viewer');
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        count: 2,
        sameAuthor: true,
        immersive: true,
        friendService: friends.service,
      );

      final firstCard = find.byKey(const ValueKey<String>('reel_1'));
      final firstButton = find.descendant(
        of: firstCard,
        matching: find.byKey(const ValueKey<String>('reel-friend-creator')),
      );
      expect(firstButton, findsOneWidget);
      await tester.tap(firstButton);
      await tester.pumpAndSettle();
      expect(friends.mutations, hasLength(1));

      await tester.drag(find.byType(PageView), const Offset(0, -700));
      await tester.pumpAndSettle();

      final secondCard = find.byKey(const ValueKey<String>('reel_2'));
      final secondButton = find.descendant(
        of: secondCard,
        matching: find.byKey(const ValueKey<String>('reel-friend-creator')),
      );
      expect(secondButton, findsOneWidget);
      expect(
        find.descendant(of: secondCard, matching: find.text('Requested')),
        findsOneWidget,
      );
      expect(tester.widget<OutlinedButton>(secondButton).onPressed, isNull);
      await tester.tap(secondButton, warnIfMissed: false);
      await tester.pump();
      expect(friends.mutations, hasLength(1));
      expect(friends.relationshipReads, <String>['creator']);
    });

    testWidgets('names a relationship read error in Polish and retries', (
      tester,
    ) async {
      var read = 0;
      final retryGate = Completer<void>();
      final friends = reelFriendService(
        viewerUid: 'viewer',
        relationshipStatusInvoker: (_) async {
          read++;
          if (read == 1) throw StateError('temporary read failure');
          await retryGate.future;
          return FriendRelationshipStatus.none;
        },
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
        locale: const Locale('pl'),
      );

      final retry = find.byKey(const ValueKey<String>('reel-friend-creator_1'));
      expect(retry, findsOneWidget);
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Nie udało się sprawdzić relacji z Creator 1. Spróbuj ponownie.',
        ),
        findsOneWidget,
      );
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

      await tester.tap(retry);
      await tester.pump();
      expect(find.text('Sprawdzanie…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(retry).onPressed, isNull);

      retryGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Dodaj znajomego'), findsOneWidget);
      expect(friends.relationshipReads, <String>['creator_1', 'creator_1']);

      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Wysłano zaproszenie'), findsOneWidget);
      expect(friends.mutations, hasLength(1));
    });

    testWidgets('sends one real request and guards against a double submit', (
      tester,
    ) async {
      final gate = Completer<void>();
      final friends = reelFriendService(viewerUid: 'viewer', gate: gate);
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-friend-creator_1'),
      );
      expect(button, findsOneWidget);
      expect(find.text('Add friend'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      // A second tap while the first is in flight must not reach the graph.
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(friends.mutations, hasLength(1));
      expect(friends.mutations.single.name, 'sendFriendRequest');
      expect(friends.mutations.single.data['targetUserId'], 'creator_1');

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Requested'), findsOneWidget);
    });

    testWidgets('busy request is announced once by the disabled action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final gate = Completer<void>();
      final friends = reelFriendService(viewerUid: 'viewer', gate: gate);
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-friend-creator_1'),
      );
      await tester.tap(button);
      await tester.pump();

      const busyLabel = 'Updating friend request for Creator 1';
      final busy = find.bySemanticsLabel(busyLabel);
      expect(
        busy,
        findsOneWidget,
        reason: 'One node must announce the state without a duplicate region.',
      );
      final data = tester.getSemantics(busy).getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
      expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(data.hasAction(ui.SemanticsAction.tap), isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(busyLabel), findsNothing);
      semantics.dispose();
    });

    testWidgets('a pending request is clear and cannot be sent twice', (
      tester,
    ) async {
      final friends = reelFriendService(
        viewerUid: 'viewer',
        relationship: FriendRelationshipStatus.requestSent,
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-friend-creator_1'),
      );
      expect(find.text('Requested'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(friends.mutations, isEmpty);
    });

    testWidgets('an existing friendship hides the action', (tester) async {
      final friends = reelFriendService(
        viewerUid: 'viewer',
        relationship: FriendRelationshipStatus.friends,
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
      );

      expect(
        find.byKey(const ValueKey<String>('reel-friend-creator_1')),
        findsNothing,
      );
      expect(find.text('Add friend'), findsNothing);
    });

    // Changed deliberately (friend-request consent, fix round): the chip over
    // a playing Yeel used to accept on one tap. It now opens the labelled
    // Accept / Decline prompt, and only Accept inside it answers.
    testWidgets('an incoming request opens the explicit prompt; only its '
        'Accept answers', (tester) async {
      final friends = reelFriendService(
        viewerUid: 'viewer',
        relationship: FriendRelationshipStatus.requestReceived,
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-friend-creator_1'),
      );
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.text('Respond')),
        findsOneWidget,
      );
      expect(find.text('Accept'), findsNothing);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        friends.mutations,
        isEmpty,
        reason: 'the chip opens the decision; it never answers it',
      );
      expect(
        find.byKey(const ValueKey('friend-request-prompt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('friend-request-prompt-decline')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('friend-request-prompt-accept')),
      );
      await tester.pumpAndSettle();
      expect(friends.mutations, hasLength(1));
      expect(friends.mutations.single.name, 'respondToFriendRequest');
      expect(friends.mutations.single.data, {
        'senderId': 'creator_1',
        'accept': true,
      });

      await tester.tap(
        find.byKey(const ValueKey('friend-request-prompt-close')),
      );
      await tester.pumpAndSettle();
      expect(friends.mutations, hasLength(1));
      expect(button, findsNothing);
    });

    testWidgets('closing the incoming-request prompt without an answer '
        'changes nothing', (tester) async {
      final friends = reelFriendService(
        viewerUid: 'viewer',
        relationship: FriendRelationshipStatus.requestReceived,
      );
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        friendService: friends.service,
      );

      final button = find.byKey(
        const ValueKey<String>('reel-friend-creator_1'),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('friend-request-prompt-close')),
      );
      await tester.pumpAndSettle();

      expect(friends.mutations, isEmpty);
      expect(
        find.descendant(of: button, matching: find.text('Respond')),
        findsOneWidget,
        reason: 'a second tap opens the prompt again, never a one-tap accept',
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(friends.mutations, isEmpty);
      expect(
        find.byKey(const ValueKey('friend-request-prompt')),
        findsOneWidget,
      );
    });

    testWidgets('is absent on your own Yeel', (tester) async {
      final friends = reelFriendService(viewerUid: 'creator_1');
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        service: reelStageService(count: 2, viewerUid: 'creator_1'),
        friendService: friends.service,
      );

      expect(
        find.byKey(const ValueKey<String>('reel-friend-creator_1')),
        findsNothing,
      );
      expect(find.text('Add friend'), findsNothing);
    });

    testWidgets('is absent where the friends graph is unavailable', (
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

      expect(find.text('Add friend'), findsNothing);
      expect(find.text('Follow'), findsNothing);
      expect(find.byKey(reelStageFooterKey), findsOneWidget);
    });
  });
}

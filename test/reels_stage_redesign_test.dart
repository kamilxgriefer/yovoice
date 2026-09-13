import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reels_toolbar.dart';

import 'reel_stage_test_support.dart';

/// Board 08's stage: what the card is made of at each width, and the one
/// control a pointer needs that a thumb does not.
void main() {
  group('the card', () {
    testWidgets('is the frame with a real footer under it, at radius 20', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
      );

      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey('reel-viewport')),
        ),
      );
      // The card is 20; its clip is the hairline inside it.
      expect((clip.borderRadius as BorderRadius).topLeft.x, 19);

      final footer = tester.getRect(find.byKey(reelStageFooterKey));
      final card = tester.getRect(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey('reel-viewport')),
        ),
      );
      // Under the media, flush with the card, and never shorter than the
      // 88 the board measures.
      expect(footer.height, greaterThanOrEqualTo(88));
      expect(footer.bottom, closeTo(card.bottom, .5));
      expect(footer.width, closeTo(card.width, .5));

      // The media frame above it keeps the authored 9:16 composition.
      final media = card.height - footer.height;
      expect(card.width / media, closeTo(9 / 16, .02));
    });

    testWidgets('the frame is height-bound, not width-bound', (tester) async {
      final players = FakeReelPlayers();
      // A wide, short window: the Reel must shrink to the height it has
      // instead of taking the width and running off the bottom.
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(1000, 700),
      );

      final card = tester.getRect(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey('reel-viewport')),
        ),
      );
      expect(card.height, lessThanOrEqualTo(700));
      expect(card.width, lessThan(600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('never wider than the 600 the board measures', (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(1000, 2000),
      );

      final card = tester.getRect(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey('reel-viewport')),
        ),
      );
      expect(card.width, lessThanOrEqualTo(600.5));
    });
  });

  group('the › next affordance', () {
    testWidgets('is on screen at pointer widths and acts as a swipe does', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        count: 2,
      );

      expect(find.byKey(reelNextKey), findsOneWidget);
      expect(find.bySemanticsLabel('Next Yeel'), findsOneWidget);
      final target = tester.getSize(find.byKey(reelNextKey));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(reelNextKey));
      await tester.pumpAndSettle();

      // The next Reel follows the existing autoplay policy on its own.
      expect(players.of('reel_2').playing, isTrue);
      expect(players.of('reel_2').volume, 0);
      expect(players.of('reel_1').playing, isFalse);
    });

    testWidgets('is absent on the last loaded Yeel', (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        count: 2,
      );
      await tester.tap(find.byKey(reelNextKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(reelNextKey),
        findsNothing,
        reason: 'a control that cannot act is worse than no control',
      );
    });

    testWidgets('is absent on the phone stage, where the swipe is the path', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        count: 2,
        immersive: true,
      );

      expect(find.byKey(reelNextKey), findsNothing);
    });

    testWidgets('mirrors to the leading edge in RTL', (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        count: 2,
        textDirection: TextDirection.rtl,
      );

      final next = tester.getRect(find.byKey(reelNextKey));
      expect(next.center.dx, lessThan(900 / 2));
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(reelNextKey),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.chevron_left_rounded);
    });
  });

  group('the columns', () {
    testWidgets('1100: card and a 360 conversation, no local panel', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(1100, 900),
      );

      final panel = find.byKey(const ValueKey<String>('reels-thread-slot'));
      expect(tester.getSize(panel).width, 360);
      expect(
        find.byKey(const ValueKey<String>('yo-moments-local-panel')),
        findsNothing,
      );
      expect(find.byType(ReelsToolbar), findsOneWidget);
    });

    testWidgets('1440: local panel, card and a 400 conversation', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(1440, 900),
        onCreate: () async {},
      );

      expect(
        find.byKey(const ValueKey<String>('yo-moments-local-panel')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('reels-thread-slot'))),
        const Size(400, 900),
      );
      // The pool filters live in exactly one place at a time.
      expect(find.byType(ReelsToolbar), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('reels-discover-filter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('reels-create-persistent')),
        findsOneWidget,
      );
    });

    testWidgets('768: one centred card and a sheet for the conversation', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(768, 1024),
      );

      expect(
        find.byKey(const ValueKey<String>('yo-moments-local-panel')),
        findsNothing,
      );
      expect(find.byType(ReelCommentsView), findsNothing);
      await tester.tap(find.byKey(reelCommentsKey));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}

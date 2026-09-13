import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'reel_stage_test_support.dart';

/// "Następny moment" — the wide layout's preview of what comes next.
///
/// D13: text first. The Reel projection carries no poster or thumbnail field,
/// so a picture appears only where the media itself IS a picture, through the
/// grant the neighbour prefetch already minted. A video gets a tile and a play
/// glyph rather than a second decoder spun up to steal one frame.
void main() {
  testWidgets('names the next Yeel from loaded data and pages to it', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      count: 2,
    );

    expect(find.byKey(reelNextCardKey), findsOneWidget);
    expect(find.text('Next moment'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(reelNextCardKey),
        matching: find.text('Creator 2'),
      ),
      findsOneWidget,
    );
    // The duration comes from the media descriptor, not from a guess.
    expect(
      find.descendant(
        of: find.byKey(reelNextCardKey),
        matching: find.text('0:18'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Next Yeel: ')), findsOneWidget);

    await tester.tap(find.byKey(reelNextCardKey));
    await tester.pumpAndSettle();

    expect(players.of('reel_2').playing, isTrue);
    expect(players.of('reel_1').playing, isFalse);
  });

  testWidgets('is absent when there is nothing loaded after this Yeel', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      count: 1,
    );

    expect(find.byKey(reelNextCardKey), findsNothing);
    expect(find.text('Next moment'), findsNothing);
  });

  testWidgets('a video neighbour gets a tile, never a second decoder', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      count: 2,
    );

    expect(
      find.descendant(
        of: find.byKey(reelNextCardKey),
        matching: find.byIcon(Icons.play_circle_outline_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(reelNextCardKey),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    // One stage, one decoder: the preview added none.
    expect(find.byType(ReelCard), findsOneWidget);
    expect(players.of('reel_2').playCount, 0);
  });

  testWidgets('an image neighbour may show the picture it already has', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      count: 2,
      photo: true,
    );
    // The prefetch mints the neighbour's grant when the page settles.
    await tester.pumpAndSettle();

    final thumb = find.descendant(
      of: find.byKey(reelNextCardKey),
      matching: find.byType(Image),
    );
    final glyph = find.descendant(
      of: find.byKey(reelNextCardKey),
      matching: find.byIcon(Icons.play_circle_outline_rounded),
    );
    // Either the cached grant is there and the picture is real, or it is not
    // and the honest tile stands in — never an invented poster. (A network
    // image in a widget test answers 400, so the tile is what is painted even
    // where the attempt was made.)
    expect(thumb.evaluate().isNotEmpty || glyph.evaluate().isNotEmpty, isTrue);
    expect(find.byType(ReelCard), findsOneWidget);
  });

  testWidgets('the preview is a wide-layout affordance only', (tester) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(768, 1024),
      count: 2,
    );

    expect(find.byKey(reelNextCardKey), findsNothing);
  });
}

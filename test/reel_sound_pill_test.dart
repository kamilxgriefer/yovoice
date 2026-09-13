import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'reel_stage_test_support.dart';

/// Mute is not pause.
///
/// They are two states of two different things — the audio, and the timeline —
/// and board 08 draws both. This file holds them apart in every combination:
/// the pill's words, its glyph, its spoken name and toggled state, and what
/// the engine is actually doing must agree, and changing one must never
/// change the other.
void main() {
  testWidgets('the pill names the state while its label names the action', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(tester, players: players, size: const Size(900, 1000));
    final handle = tester.ensureSemantics();

    // Autoplay is silent, so the Reel starts muted and playing.
    expect(players.of('reel_1').playing, isTrue);
    expect(players.of('reel_1').volume, 0);
    expect(find.text('Sound off'), findsOneWidget);
    expect(find.bySemanticsLabel('Turn sound on'), findsOneWidget);
    _expectToggled(tester, 'Turn sound on', on: false);

    await tester.tap(find.byKey(reelSoundKey));
    await tester.pumpAndSettle();

    // Sound changed; playback did not.
    expect(find.text('Sound on'), findsOneWidget);
    expect(find.bySemanticsLabel('Turn sound off'), findsOneWidget);
    _expectToggled(tester, 'Turn sound off', on: true);
    expect(players.of('reel_1').volume, 1);
    expect(players.of('reel_1').playing, isTrue);
    expect(players.of('reel_1').playCount, 1);
    handle.dispose();
  });

  testWidgets('pausing the frame leaves the sound state alone', (tester) async {
    final players = FakeReelPlayers();
    await pumpReelStage(tester, players: players, size: const Size(900, 1000));

    await tester.tap(find.byKey(reelSoundKey));
    await tester.pumpAndSettle();
    expect(find.text('Sound on'), findsOneWidget);

    await tester.tap(find.byKey(reelPlaybackSurfaceKey));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Paused, and still unmuted: the pill did not quietly change meaning.
    expect(players.of('reel_1').playing, isFalse);
    expect(find.text('Sound on'), findsOneWidget);
    expect(find.bySemanticsLabel('Turn sound off'), findsOneWidget);

    await tester.tap(find.byKey(reelPlaybackSurfaceKey));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(players.of('reel_1').playing, isTrue);
    expect(find.text('Sound on'), findsOneWidget);
    expect(players.of('reel_1').volume, 1);
  });

  testWidgets('muting while paused changes neither the pause nor the frame', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(tester, players: players, size: const Size(900, 1000));

    await tester.tap(find.byKey(reelPlaybackSurfaceKey));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(players.of('reel_1').playing, isFalse);

    await tester.tap(find.byKey(reelSoundKey));
    await tester.pumpAndSettle();

    expect(find.text('Sound on'), findsOneWidget);
    expect(players.of('reel_1').volume, 1);
    expect(
      players.of('reel_1').playing,
      isFalse,
      reason: 'turning sound on must never restart a deliberately paused Yeel',
    );
    expect(players.of('reel_1').playCount, 1);
  });

  testWidgets('the preference is the feed’s, and it survives paging', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(900, 1000),
      count: 3,
    );

    await tester.tap(find.byKey(reelSoundKey));
    await tester.pumpAndSettle();
    expect(find.text('Sound on'), findsOneWidget);

    await tester.tap(find.byKey(reelNextKey));
    await tester.pumpAndSettle();

    expect(players.of('reel_2').playing, isTrue);
    expect(players.of('reel_2').volume, 1);
    expect(find.text('Sound on'), findsOneWidget);
    expect(players.of('reel_1').playing, isFalse);
  });

  testWidgets('a photo Yeel has no mute, because its track is the content', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(900, 1000),
      count: 1,
      photo: true,
    );

    expect(find.byKey(reelSoundKey), findsNothing);
    // The backing track still has its own, labelled, transport.
    expect(find.byTooltip('Play backing audio'), findsOneWidget);
  });

  testWidgets(
    'the compact phone sound control keeps its target and semantics',
    (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        immersive: true,
      );

      final pill = find.byKey(reelSoundKey);
      expect(pill, findsOneWidget);
      final size = tester.getSize(pill);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.text('Sound off'), findsNothing);
      expect(find.bySemanticsLabel('Turn sound on'), findsOneWidget);

      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(find.text('Sound on'), findsNothing);
      expect(find.bySemanticsLabel('Turn sound off'), findsOneWidget);
      expect(players.of('reel_1').volume, 1);
    },
  );

  testWidgets('a card is not a second sound preference', (tester) async {
    // Two cards are alive in the pager at once; the preference is the feed's,
    // so the Reel that is not on screen cannot disagree with the one that is.
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(900, 1000),
      count: 2,
    );
    await tester.tap(find.byKey(reelSoundKey));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<ReelCard>(find.byType(ReelCard));
    final preferences = cards.map((card) => card.soundOn).toSet();
    expect(preferences, hasLength(1));
    expect(preferences.single!.value, isTrue);
  });
}

void _expectToggled(WidgetTester tester, String label, {required bool on}) {
  final flags = tester
      .getSemantics(find.bySemanticsLabel(label))
      .getSemanticsData()
      .flagsCollection;
  // A toggled flag is tri-state: a control that is not toggleable at all
  // reports neither true nor false, which is exactly what this must not be.
  expect(flags.isToggled.name, on ? 'isTrue' : 'isFalse');
}

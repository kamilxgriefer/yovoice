import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'reel_stage_test_support.dart';

/// The phone stage of board 08.
///
/// The app keeps its immersive stage below 600 — the board's inset frame
/// would leave a 9:16 video about 240 px wide on a 390 phone once the real
/// chrome is present, the opposite of what the spec asks for — so the board's
/// phone composition is reproduced as the ORDER of the bottom stack.
///
/// From the bottom edge up: the action bar, the caption, the author row, the
/// progress track, and the [mute pill … times] line above it.
void main() {
  Finder inCard(Finder finder) =>
      find.descendant(of: find.byType(ReelCard), matching: finder);

  testWidgets('the bottom stack is in the board’s order', (tester) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
    );

    final pill = tester.getRect(inCard(find.byKey(reelSoundKey)));
    final bar = tester.getRect(inCard(find.byKey(reelProgressBarKey)));
    final author = tester.getRect(inCard(find.text('Creator 1')));
    final caption = tester.getRect(inCard(find.text(reelStageCaption)));
    final like = tester.getRect(inCard(find.byKey(reelLikeKey)));

    expect(pill.bottom, lessThanOrEqualTo(bar.top + .01));
    expect(bar.bottom, lessThanOrEqualTo(author.top + .01));
    expect(author.bottom, lessThanOrEqualTo(caption.top + .01));
    expect(caption.bottom, lessThanOrEqualTo(like.top + .01));
  });

  testWidgets('the action bar clears the bottom of the stage and the subject '
      'band', (tester) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
    );

    final stage = tester.getRect(find.byKey(const ValueKey('reels-stage')));
    final frame = tester.getRect(
      inCard(find.byKey(const ValueKey('reel-viewport'))),
    );
    for (final key in <Key>[
      reelLikeKey,
      reelCommentsKey,
      reelShareKey,
      reelMoreKey,
    ]) {
      final rect = tester.getRect(inCard(find.byKey(key)));
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$key');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$key');
      // Reserved space below the bar, so the shell's dock never sits on it.
      expect(
        rect.bottom,
        lessThanOrEqualTo(stage.bottom - 12 + .01),
        reason: '$key',
      );
      // The middle third of the frame is the subject; nothing covers it.
      expect(
        rect.top,
        greaterThan(frame.top + frame.height * 2 / 3),
        reason: '$key',
      );
    }
  });

  testWidgets('a short stage keeps every control and drops the words first', (
    tester,
  ) async {
    // A phone in landscape, or a keyboard-squeezed window: the identity block
    // gives way before any control does.
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(560, 300),
      immersive: true,
    );

    for (final key in <Key>[
      reelLikeKey,
      reelCommentsKey,
      reelShareKey,
      reelMoreKey,
      reelSoundKey,
    ]) {
      expect(inCard(find.byKey(key)), findsOneWidget, reason: '$key');
      expect(
        tester.getSize(inCard(find.byKey(key))).shortestSide,
        greaterThanOrEqualTo(44),
        reason: '$key',
      );
    }
    expect(inCard(find.byKey(reelProgressBarKey)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 200 % text nothing is clipped and the bar still fits', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final stage = tester.getRect(find.byKey(const ValueKey('reels-stage')));
    for (final key in <Key>[reelLikeKey, reelMoreKey]) {
      final rect = tester.getRect(inCard(find.byKey(key)));
      expect(rect.bottom, lessThanOrEqualTo(stage.bottom + .01));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('the frame itself is the play control, and the bar is not', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
    );

    expect(players.of('reel_1').playing, isTrue);
    // Tapping the media pauses; tapping a control in the stack does not.
    await tester.tap(find.byKey(reelPlaybackSurfaceKey));
    await tester.pumpAndSettle();
    expect(players.of('reel_1').playing, isFalse);

    await tester.tap(inCard(find.byKey(reelLikeKey)));
    await tester.pumpAndSettle();
    expect(players.of('reel_1').playing, isFalse);
  });
}

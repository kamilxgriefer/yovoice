// Board 08 — the frame, its footer and the affordance that advances it.
//
// The visual review failed board 08 on three measurements, all of them
// geometry rather than colour:
//
//   S5  the "›" next plate was anchored to the stage COLUMN, so on a
//       height-bound frame it landed ~157 px of open background to the right
//       of the Reel it advances (~370 px at 1920);
//   S6  the footer bar took ~246 px against a budget of 88, because the
//       author row and the follow control took a line each even at ×1;
//   S13 the footer panel was therefore wider than the media above it — the
//       frame shrank to fit the height the over-tall footer left, while the
//       card kept the width the footer had been budgeted for.
//
// S6 and S13 are one cause: `ReelStageFooterBar.heightFor` assumed the shared
// line that the widget did not draw. These cases pin the geometry rather than
// the pixels, so they hold at every width and text size the boards use.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';

import 'reel_stage_test_support.dart';

/// Two rects are the same surface when every edge agrees to within half a
/// logical pixel; `Rect ==` is exact and a fitted layer lands on fractions.
void _expectSameRect(Rect actual, Rect expected, {required String reason}) {
  expect(actual.left, closeTo(expected.left, 0.5), reason: reason);
  expect(actual.top, closeTo(expected.top, 0.5), reason: reason);
  expect(actual.right, closeTo(expected.right, 0.5), reason: reason);
  expect(actual.bottom, closeTo(expected.bottom, 0.5), reason: reason);
}

void main() {
  // Every claim in this file is a width or a height in logical pixels, so it
  // is laid out in the typeface that will paint it. In `flutter_test`'s
  // default font a digit is one em wide — twice Inter's — which decides
  // "do the four totals fit this row" differently from every real device.
  setUpAll(loadStageFonts);

  group('the next affordance is anchored to the frame', () {
    for (final size in <Size>[
      Size(768, 1024),
      Size(1100, 900),
      Size(1440, 900),
      Size(1920, 1000),
    ]) {
      testWidgets('at ${size.width.toInt()} the "›" plate sits inside the '
          'card, inset 16', (tester) async {
        final players = FakeReelPlayers();
        await pumpReelStage(tester, players: players, size: size, count: 3);

        final plate = find.byKey(reelNextKey);
        expect(plate, findsOneWidget, reason: 'pointer widths have no swipe');
        final plateRect = tester.getRect(plate);
        final card = tester.getRect(
          find.byKey(const ValueKey<String>('reel-viewport')),
        );

        expect(
          plateRect.right,
          lessThanOrEqualTo(card.right),
          reason:
              'the plate must be ON the Reel it advances, not in the open '
              'background beside it',
        );
        expect(
          card.right - plateRect.right,
          closeTo(16, 1.5),
          reason: 'visual contract §9.3: "› plate 48 inset 16"',
        );
        expect(plateRect.width, greaterThanOrEqualTo(44));
        expect(
          plateRect.center.dy,
          closeTo(card.center.dy, card.height / 2),
          reason: 'and vertically within the frame',
        );
      });
    }
  });

  group('the footer bar and the media it belongs to', () {
    for (final size in <Size>[
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('at ${size.width.toInt()} the footer is flush with the '
          'media and holds one identity row', (tester) async {
        final players = FakeReelPlayers();
        await pumpReelStage(tester, players: players, size: size, count: 2);

        final footer = tester.getRect(find.byKey(reelStageFooterKey));
        final card = tester.getRect(
          find.byKey(const ValueKey<String>('reel-viewport')),
        );

        expect(
          footer.width,
          closeTo(card.width, 1),
          reason:
              'a footer wider than its own media reads as a ledge around the '
              'Reel; the board has them flush',
        );
        // One identity row plus a two-line caption plus the action row, at
        // 16/16 padding — never the extra 48-px run an unnecessary wrap adds.
        expect(
          footer.height,
          lessThanOrEqualTo(
            ReelStageFooterBar.heightFor(
                  tester.element(find.byKey(reelStageFooterKey)),
                  hasCaption: true,
                  sideBySide:
                      footer.width >= ReelStageFooterBar.sideBySideWidth,
                ) +
                2,
          ),
          reason:
              'the derived budget and the widget have to agree, or the frame '
              'is sized against a footer that does not exist',
        );
        expect(footer.height, lessThanOrEqualTo(210));
      });
    }

    testWidgets('at 200 % text the author and the follow control take a line '
        'each again', (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(1440, 900),
        textScale: 2,
        count: 2,
      );
      // Squeezing the name to nothing so a button can keep its width is not
      // a layout: above 1.6 the Wrap is the right policy and stays.
      expect(find.byKey(reelStageFooterKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // S13, measured rather than asserted. The footer-vs-card width this suite
  // used to compare CANNOT disagree: `reel-stage-footer-bar` and
  // `reel-viewport` are both inside one `crossAxisAlignment: stretch`
  // Column, so those two widths are equal by construction. What S13 named is
  // the MEDIA being narrower than the card it sits in: when the footer draws
  // taller than `heightFor` budgeted, the 9:16 frame loses height, and a
  // 9:16 frame that loses height loses width — leaving `surfaceSunken`
  // ledges down both sides. That only happens at a text size the ×1 cases
  // never reach, which is why every one of them passed while the 200 % frame
  // painted an 11 px ledge per side.
  group('the media fills the card it sits in', () {
    for (final textScale in <double>[1, 1.6, 2]) {
      for (final size in <Size>[
        Size(768, 1024),
        Size(1440, 900),
        Size(1920, 1000),
      ]) {
        testWidgets('at ${size.width.toInt()} and ${(textScale * 100).toInt()} '
            '% text the media is exactly as wide as its card', (tester) async {
          final players = FakeReelPlayers();
          await pumpReelStage(
            tester,
            players: players,
            size: size,
            textScale: textScale,
            count: 2,
            // The board has the inline follow control on the footer; a
            // footer measured without it is a row shorter than production's.
            followService: stageFollowService(),
          );

          final card = tester.getRect(
            find.byKey(const ValueKey<String>('reel-viewport')),
          );
          final band = tester.getRect(
            find.byKey(const ValueKey<String>('reel-media-band')),
          );
          final media = tester.getRect(find.byType(ReelCompositionCanvas));
          final footer = tester.getRect(find.byKey(reelStageFooterKey));
          final element = tester.element(find.byKey(reelStageFooterKey));
          final budget = ReelStageFooterBar.heightFor(
            element,
            hasCaption: true,
            sideBySide:
                footer.width >= ReelStageFooterBar.sideBySideWidthFor(element),
          );

          expect(
            footer.height,
            lessThanOrEqualTo(budget),
            reason:
                'the frame is sized from what this budget leaves, so a footer '
                'taller than it is height the media does not get — and the '
                'budget has to hold at the READER\'s text size, not only at '
                '×1 (it was 36 px short at 200 %)',
          );
          expect(
            media.width,
            closeTo(card.width, 0.5),
            reason:
                'the media letterboxed inside a band that kept the card\'s '
                'width: ${((card.width - media.width) / 2).toStringAsFixed(1)} '
                'px of `surfaceSunken` down each side of the Reel',
          );
          _expectSameRect(
            band,
            media,
            reason: 'and the sunken well is the media, never a ledge round it',
          );
        });
      }
    }

    testWidgets('an expanded caption insets the media on the card surface, '
        'never on a sunken ledge', (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(1440, 900),
        textScale: 2,
        count: 2,
        followService: stageFollowService(),
      );

      // The one case no closed-form budget can predict: the reader expands
      // the caption from two lines to eight, and the footer grows past what
      // the frame was sized against.
      await tester.tap(find.byKey(reelStageCaptionKey));
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find.byKey(const ValueKey<String>('reel-viewport')),
      );
      final band = tester.getRect(
        find.byKey(const ValueKey<String>('reel-media-band')),
      );
      final media = tester.getRect(find.byType(ReelCompositionCanvas));

      _expectSameRect(
        band,
        media,
        reason:
            'the band gives up WIDTH rather than keeping the card\'s and '
            'letterboxing inside it, so what shows beside the frame is the '
            'card\'s own surface and not a `surfaceSunken` ledge',
      );
      expect(
        band.width / band.height,
        closeTo(9 / 16, 0.01),
        reason: 'and it is still a 9:16 Reel',
      );
      expect(
        band.center.dx,
        closeTo(card.center.dx, 0.5),
        reason: 'centred in the card, not pinned to one edge',
      );
      expect(band.width, lessThanOrEqualTo(card.width + 0.5));
    });
  });

  group('the phone action bar keeps the board counts', () {
    // 390 x 844 is the canonical phone the boards were drawn at. 320 x 568 is
    // deliberately NOT here: §9.3 allows icons-only on a frame under 560 px
    // of height, and the phone stack's own suite pins that fold.
    for (final width in <double>[390]) {
      testWidgets('at ${width.toInt()} the four actions still show their '
          'totals', (tester) async {
        final players = FakeReelPlayers();
        await pumpReelStage(
          tester,
          players: players,
          size: Size(width, 844),
          immersive: true,
          count: 2,
        );

        // `reelWire` publishes 12 likes and 3 comments.
        expect(
          find.descendant(
            of: find.byKey(reelLikeKey),
            matching: find.text('12'),
          ),
          findsOneWidget,
          reason:
              'budgeting every rail item at the widest possible total ("1.2K") '
              'cost a 390 phone its counts entirely: 4 × 94 + 30 = 406 px '
              'against the 358 the inset leaves',
        );
        expect(
          find.descendant(
            of: find.byKey(reelCommentsKey),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

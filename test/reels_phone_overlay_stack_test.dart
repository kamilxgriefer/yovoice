import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'reel_stage_test_support.dart';

/// The immersive Yeels stage keeps the footage as the dominant surface.
/// Controls may occupy the trailing edge and the lower information band, but
/// the middle of the frame must remain clear at every supported phone state.
void main() {
  setUpAll(loadStageFonts);

  Finder inCard(Finder finder) =>
      find.descendant(of: find.byType(ReelCard), matching: finder);

  Finder keyed(String value) => inCard(find.byKey(ValueKey<String>(value)));

  testWidgets('the canonical phone leaves one large uninterrupted media band', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
    );

    final frame = tester.getRect(
      inCard(find.byKey(const ValueKey('reel-viewport'))),
    );
    final footer = tester.getRect(
      inCard(find.byKey(const ValueKey('reel-footer'))),
    );
    final rail = tester.getRect(keyed('reel-action-rail'));
    final identity = tester.getRect(keyed('reel-identity-block'));
    final scrim = tester.getRect(keyed('reel-bottom-scrim'));
    final sound = tester.getRect(inCard(find.byKey(reelSoundKey)));
    final progress = tester.getRect(inCard(find.byKey(reelProgressBarKey)));

    expect(footer.left, frame.left);
    expect(footer.right, frame.right);
    expect(footer.bottom, frame.bottom);
    expect(
      footer.top,
      greaterThanOrEqualTo(frame.top),
      reason: 'the host chrome remains above the immersive controls',
    );
    expect(rail.left, greaterThan(frame.right - 80));
    expect(identity.right, lessThanOrEqualTo(rail.left));
    expect(sound.left, greaterThan(frame.right - 80));
    expect(sound.top, lessThanOrEqualTo(footer.top + 12));
    expect(progress.bottom, closeTo(frame.bottom, .01));
    expect(scrim.height, lessThanOrEqualTo(frame.height * .40));

    final clearMedia = Rect.fromLTRB(
      frame.left + 16,
      frame.top + 64,
      rail.left - 8,
      scrim.top,
    );
    expect(clearMedia.width, greaterThan(frame.width * .60));
    expect(clearMedia.height, greaterThan(frame.height * .50));
    for (final occupied in <Rect>[rail, identity, sound, progress]) {
      expect(
        occupied.overlaps(clearMedia),
        isFalse,
        reason: '$occupied must stay outside the uninterrupted media band',
      );
    }
    expect(inCard(find.byKey(reelProgressTimesKey)), findsNothing);
  });

  for (final width in <double>[320, 390, 430, 560]) {
    testWidgets('the ${width.toInt()} px phone keeps actions on the edge', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: Size(width, 844),
        immersive: true,
      );

      final frame = tester.getRect(
        inCard(find.byKey(const ValueKey('reel-viewport'))),
      );
      final rail = tester.getRect(keyed('reel-action-rail'));
      expect(rail.width, lessThanOrEqualTo(64));
      expect(rail.right, closeTo(frame.right - 12, .01));
      for (final key in <Key>[
        reelLikeKey,
        reelCommentsKey,
        reelShareKey,
        reelMoreKey,
      ]) {
        final rect = tester.getRect(inCard(find.byKey(key)));
        expect(rect.width, greaterThanOrEqualTo(48), reason: '$key');
        expect(rect.height, greaterThanOrEqualTo(48), reason: '$key');
        expect(rect.left, greaterThanOrEqualTo(rail.left), reason: '$key');
        expect(rect.right, lessThanOrEqualTo(frame.right), reason: '$key');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('at 200 percent text the rail and identity remain separate', (
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

    final frame = tester.getRect(
      inCard(find.byKey(const ValueKey('reel-viewport'))),
    );
    final rail = tester.getRect(keyed('reel-action-rail'));
    final identity = tester.getRect(keyed('reel-identity-block'));
    expect(identity.right, lessThanOrEqualTo(rail.left));
    for (final key in <Key>[
      reelLikeKey,
      reelCommentsKey,
      reelShareKey,
      reelMoreKey,
      reelSoundKey,
    ]) {
      final rect = tester.getRect(inCard(find.byKey(key)));
      expect(frame.contains(rect.topLeft), isTrue, reason: '$key top-left');
      expect(
        frame.contains(rect.bottomRight - const Offset(.01, .01)),
        isTrue,
        reason: '$key bottom-right',
      );
      expect(rect.shortestSide, greaterThanOrEqualTo(48), reason: '$key');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('large totals cannot widen the rail into authored content', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
      textScale: 2,
      service: reelStageService(
        likeCount: 999999,
        commentCount: 999999,
        linkOverlays: <ReelLinkOverlay>[
          ReelLinkOverlay(
            id: 'trailing-safe',
            label: 'Trailing safe link',
            uri: Uri.parse('https://example.com/trailing-safe'),
            x: 1,
            y: .5,
          ),
        ],
      ),
    );

    final rail = tester.getRect(keyed('reel-action-rail'));
    final link = tester.getRect(inCard(find.text('Trailing safe link')));
    expect(rail.width, lessThanOrEqualTo(64));
    expect(link.right, lessThanOrEqualTo(rail.left));
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 390, 430, 560]) {
    for (final scale in <double>[1, 2]) {
      testWidgets('bottom authored content clears identity at '
          '${width.toInt()} px and ${scale.toInt()}00 percent text', (
        tester,
      ) async {
        final players = FakeReelPlayers();
        await pumpReelStage(
          tester,
          players: players,
          size: Size(width, 844),
          immersive: true,
          textScale: scale,
          friendService: stageFriendService(),
          service: reelStageService(
            authorName:
                'A deliberately long creator display name that still truncates safely',
            linkOverlays: <ReelLinkOverlay>[
              ReelLinkOverlay(
                id: 'bottom-safe',
                label: 'Bottom safe link',
                uri: Uri.parse('https://example.com/bottom-safe'),
                x: .5,
                y: 1,
              ),
            ],
          ),
        );

        final link = inCard(find.text('Bottom safe link').hitTestable());
        final identity = tester.getRect(keyed('reel-identity-block'));
        final linkRect = tester.getRect(link);
        expect(
          linkRect.bottom,
          lessThanOrEqualTo(identity.top),
          reason: 'authored content must stop before wrapped author/friend',
        );
        expect(
          tester
              .getSize(
                inCard(
                  find.byKey(
                    const ValueKey<String>('reel-link-overlay-bottom-safe'),
                  ),
                ),
              )
              .shortestSide,
          greaterThanOrEqualTo(44),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a landscape-height stage uses a shallow action row', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(560, 300),
      immersive: true,
    );

    final rail = tester.getRect(keyed('reel-action-rail'));
    expect(rail.width, greaterThan(rail.height * 3));
    expect(keyed('reel-identity-block'), findsNothing);
    for (final key in <Key>[
      reelLikeKey,
      reelCommentsKey,
      reelShareKey,
      reelMoreKey,
      reelSoundKey,
    ]) {
      expect(
        tester.getSize(inCard(find.byKey(key))).shortestSide,
        greaterThanOrEqualTo(44),
        reason: '$key',
      );
    }
    expect(inCard(find.byKey(reelProgressBarKey)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shallow landscape action row never covers identity', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(560, 420),
      immersive: true,
    );

    final rail = tester.getRect(keyed('reel-action-rail'));
    expect(rail.width, greaterThan(rail.height * 3));
    final identity = keyed('reel-identity-block');
    if (identity.evaluate().isNotEmpty) {
      expect(
        tester.getRect(identity).overlaps(rail),
        isFalse,
        reason:
            'a short landscape frame cannot stack identity on its action row',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('shallow photo Yeels retain backing-audio playback', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(560, 420),
      immersive: true,
      photo: true,
    );

    expect(keyed('reel-identity-block'), findsNothing);
    final audio = inCard(
      find.byKey(const ValueKey<String>('reel-playback-toggle')),
    );
    expect(audio, findsOneWidget);
    expect(tester.getSize(audio).shortestSide, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[600, 768]) {
    for (final scale in <double>[1, 2]) {
      testWidgets('the ${width.toInt()} px desktop card is intact at '
          '${scale.toInt()}00 percent text', (tester) async {
        final players = FakeReelPlayers();
        await pumpReelStage(
          tester,
          players: players,
          size: Size(width, 900),
          textScale: scale,
          service: reelStageService(
            linkOverlays: <ReelLinkOverlay>[
              ReelLinkOverlay(
                id: 'desktop-bottom',
                label: 'Desktop bottom link',
                uri: Uri.parse('https://example.com/desktop-bottom'),
                x: .5,
                y: 1,
              ),
            ],
          ),
        );

        final viewport = tester.getRect(
          inCard(find.byKey(const ValueKey('reel-viewport'))),
        );
        final media = tester.getRect(
          inCard(find.byKey(const ValueKey<String>('reel-media-band'))),
        );
        final footer = tester.getRect(
          inCard(find.byKey(const ValueKey<String>('reel-stage-footer'))),
        );
        final link = tester.getRect(inCard(find.text('Desktop bottom link')));
        expect(media.width, closeTo(viewport.width, .01));
        expect(media.bottom, lessThanOrEqualTo(footer.top + .01));
        expect(link.bottom, lessThanOrEqualTo(media.bottom));
        for (final key in <Key>[
          reelLikeKey,
          reelCommentsKey,
          reelShareKey,
          reelMoreKey,
        ]) {
          final rect = tester.getRect(inCard(find.byKey(key)));
          expect(rect.shortestSide, greaterThanOrEqualTo(44), reason: '$key');
          expect(viewport.contains(rect.topLeft), isTrue, reason: '$key');
          expect(
            viewport.contains(rect.bottomRight - const Offset(.01, .01)),
            isTrue,
            reason: '$key',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('RTL mirrors rail, sound and information safe zones', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
      textScale: 2,
      textDirection: TextDirection.rtl,
      service: reelStageService(
        likeCount: 999999,
        commentCount: 999999,
        linkOverlays: <ReelLinkOverlay>[
          ReelLinkOverlay(
            id: 'rtl-trailing',
            label: 'RTL trailing link',
            uri: Uri.parse('https://example.com/rtl-trailing'),
            x: 0,
            y: .5,
          ),
        ],
      ),
    );

    final frame = tester.getRect(
      inCard(find.byKey(const ValueKey('reel-viewport'))),
    );
    final rail = tester.getRect(keyed('reel-action-rail'));
    final identity = tester.getRect(keyed('reel-identity-block'));
    final sound = tester.getRect(inCard(find.byKey(reelSoundKey)));
    final link = tester.getRect(inCard(find.text('RTL trailing link')));
    expect(rail.left, closeTo(frame.left + 12, .01));
    expect(identity.left, greaterThanOrEqualTo(rail.right));
    expect(sound.left, lessThan(frame.left + 80));
    expect(link.left, greaterThanOrEqualTo(rail.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('media, sound and engagement taps keep independent functions', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
    );

    final engine = players.of('reel_1');
    expect(engine.playing, isTrue);
    expect(engine.volume, 0);

    await tester.tap(inCard(find.byKey(reelSoundKey)));
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    expect(engine.volume, 1);

    await tester.tap(find.byKey(reelPlaybackSurfaceKey));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(engine.playing, isFalse);

    await tester.tap(inCard(find.byKey(reelLikeKey)));
    await tester.pumpAndSettle();
    expect(engine.playing, isFalse);
  });
}

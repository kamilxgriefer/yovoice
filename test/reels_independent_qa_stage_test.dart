// Independent QA — the Reels stage (board 08): autoplay and mute as separate
// facts, one decoder per Reel, the destination coexisting with a live room,
// account changes, pagination stability and listener ownership.
//
// The feed under test is the real `ReelsFeedScreen` over the real
// `ReelService` reading a fake callable transport. Only the video/audio
// engines and the identity are stand-ins, because no widget test may start a
// platform decoder.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'reel_stage_test_support.dart';

const _soundKey = ValueKey<String>('reel-sound-toggle');
const _commentsKey = ValueKey<String>('reel-comments-action');
const _nextKey = ValueKey<String>('reel-next-action');

/// A paging transport: page one carries a cursor, page two closes it. When
/// [failPageTwo] is set the second page refuses the way a callable does.
ReelService _pagingService({
  required MockFirebaseAuth auth,
  required List<String> calls,
  bool failPageTwo = false,
  bool photo = false,
}) => ReelService(
  auth: auth,
  callableInvoker: (name, payload) async {
    calls.add(name);
    switch (name) {
      case 'listReelsV2':
        final cursor = payload['cursor'];
        if (cursor == null) {
          return <Object?, Object?>{
            'schemaVersion': 2,
            'items': <Object?>[
              reelWire(1, photo: photo),
              reelWire(2, photo: photo),
            ],
            'nextCursor': 'page-2',
          };
        }
        if (failPageTwo) {
          throw StateError('reel page unavailable');
        }
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[reelWire(3, photo: photo)],
          'nextCursor': null,
        };
      case 'getReelMediaAccessV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url':
              'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '7',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      case 'getReelViewV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'reel': reelWire(1, photo: photo),
          'comments': const <Object?>[],
          'commentsTruncated': false,
          'nextCommentCursor': null,
        };
      case 'listReelCommentsV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': const <Object?>[],
          'nextCursor': null,
        };
    }
    throw StateError('Unexpected callable $name');
  },
);

Future<void> _pumpFeed(
  WidgetTester tester, {
  required FakeReelPlayers players,
  Size size = const Size(1440, 900),
  ReelService? service,
  ValueListenable<bool>? isVisible,
  bool immersive = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: ReelsFeedScreen(
          embedded: true,
          immersive: immersive,
          isVisible: isVisible,
          service: service ?? reelStageService(count: 2),
          audioPlaybackFactory: FakeReelAudioPlayback.new,
          videoPlaybackFactory: (uri, reel) => players.of(reel.id),
          videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder _onCard(Key key) =>
    find.descendant(of: find.byType(ReelCard), matching: find.byKey(key));

void main() {
  group('mute is not pause', () {
    testWidgets(
      'muting, pausing and unmuting are four independent states and none of '
      'them restarts the decoder',
      (tester) async {
        final players = FakeReelPlayers();
        await _pumpFeed(tester, players: players);
        final engine = players.of('reel_1');

        // Autoplay starts silent: the policy is "video plays, sound waits".
        expect(engine.playing, isTrue);
        expect(engine.playCount, 1);
        expect(engine.volume, 0);

        // 1. Sound on while playing.
        await tester.tap(_onCard(_soundKey));
        await tester.pumpAndSettle();
        expect(engine.playing, isTrue, reason: 'unmuting is not a transport');
        expect(engine.volume, greaterThan(0));
        expect(engine.playCount, 1, reason: 'and it never restarts the Yeel');

        // 2. Pause while the sound is on.
        await tester.tap(
          find.byKey(const ValueKey<String>('reel-video-playback-surface')),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(engine.playing, isFalse);
        expect(
          engine.volume,
          greaterThan(0),
          reason: 'pausing never changes the sound state',
        );

        // 3. Mute while paused.
        await tester.tap(_onCard(_soundKey));
        await tester.pumpAndSettle();
        expect(
          engine.playing,
          isFalse,
          reason: 'muting a paused Yeel must not start it',
        );
        expect(engine.volume, 0);
        expect(engine.playCount, 1);

        // 4. Resume.
        await tester.tap(
          find.byKey(const ValueKey<String>('reel-video-playback-surface')),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(engine.playing, isTrue);
        expect(
          engine.volume,
          0,
          reason: 'resuming restores no sound of its own',
        );
      },
    );

    testWidgets('the sound preference is the feed\'s and survives paging', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await _pumpFeed(tester, players: players);

      await tester.tap(_onCard(_soundKey));
      await tester.pumpAndSettle();
      expect(players.of('reel_1').volume, greaterThan(0));

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();

      expect(
        players.of('reel_2').volume,
        greaterThan(0),
        reason:
            'one preference for the destination — the next Yeel does not ask '
            'for sound again',
      );
      expect(
        players.of('reel_1').playing,
        isFalse,
        reason: 'the Yeel that left the stage stops',
      );
    });

    testWidgets(
      'a photo Yeel offers no mute, because its track is its content',
      (tester) async {
        final players = FakeReelPlayers();
        await _pumpFeed(
          tester,
          players: players,
          service: reelStageService(count: 2, photo: true),
        );
        expect(_onCard(_soundKey), findsNothing);
      },
    );
  });

  group('one decoder per Yeel', () {
    testWidgets(
      'a responsive reflow and an opened conversation leave exactly one '
      'engine playing',
      (tester) async {
        final players = FakeReelPlayers();
        await _pumpFeed(tester, players: players);
        expect(players.playing, 1);
        final engine = players.of('reel_1');
        expect(engine.playCount, 1);

        // Wide-3 → wide-2 → phone and back: the stage changes shape around
        // the same media.
        for (final size in <Size>[
          const Size(1200, 900),
          const Size(1100, 900),
          const Size(1440, 900),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(
            players.playing,
            1,
            reason: 'a reflow reparents one decoder, it never builds a second',
          );
        }
        expect(
          engine.playCount,
          1,
          reason: 'and the same decoder is never restarted by a reflow',
        );

        await tester.tap(_onCard(_commentsKey));
        await tester.pumpAndSettle();
        expect(
          players.playing,
          1,
          reason:
              'the docked conversation sits beside the media (D5) and adds no '
              'second engine',
        );
        expect(engine.playCount, 1);
      },
    );
  });

  group('coexistence with a live room or call', () {
    testWidgets(
      'the host hiding the destination suspends the Yeel, and returning '
      'resumes it without restarting the decoder',
      (tester) async {
        final visible = ValueNotifier<bool>(true);
        addTearDown(visible.dispose);
        final players = FakeReelPlayers();
        await _pumpFeed(tester, players: players, isVisible: visible);
        final engine = players.of('reel_1');
        expect(engine.playing, isTrue);

        // The viewer joins a room: the shell keeps Reels mounted and hides it.
        visible.value = false;
        await tester.pumpAndSettle();
        expect(
          engine.playing,
          isFalse,
          reason:
              'a Yeel must not keep decoding, or sounding, into a live room',
        );
        expect(engine.pauseCount, greaterThanOrEqualTo(1));

        visible.value = true;
        await tester.pumpAndSettle();
        expect(engine.playing, isTrue);
        expect(
          engine.playCount,
          greaterThanOrEqualTo(1),
          reason: 'coming back resumes the same decoder',
        );
      },
    );
  });

  group('account change', () {
    testWidgets(
      'an identity change clears the loaded Yeels, closes the conversation '
      'and leaves no engine playing for the previous account',
      (tester) async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
        );
        final calls = <String>[];
        final players = FakeReelPlayers();
        await _pumpFeed(
          tester,
          players: players,
          service: _pagingService(auth: auth, calls: calls),
        );
        expect(players.of('reel_1').playing, isTrue);

        await tester.tap(_onCard(_commentsKey));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('reel-comments-panel-view')),
          findsOneWidget,
        );

        final listsBefore = calls.where((c) => c == 'listReelsV2').length;
        await auth.signOut();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          players.playing,
          0,
          reason: 'no media of the signed-out account keeps decoding on screen',
        );
        expect(
          find.byKey(const ValueKey<String>('reel-comments-panel-view')),
          findsNothing,
          reason: 'an open thread belongs to the account that opened it',
        );
        expect(
          find.byType(ReelCard),
          findsNothing,
          reason:
              'the previous account\'s Yeels are cleared, not left on screen '
              'for the next viewer',
        );
        expect(
          calls.where((c) => c == 'listReelsV2').length,
          greaterThanOrEqualTo(listsBefore),
        );
      },
    );
  });

  group('pagination stability', () {
    testWidgets('a second page appends and never rebuilds the first decoder', (
      tester,
    ) async {
      final calls = <String>[];
      final players = FakeReelPlayers();
      await _pumpFeed(
        tester,
        players: players,
        service: _pagingService(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
          ),
          calls: calls,
        ),
      );
      expect(players.of('reel_1').playCount, 1);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();

      expect(
        calls.where((c) => c == 'listReelsV2').length,
        greaterThanOrEqualTo(2),
        reason: 'reaching the end of the loaded page fetches the next one',
      );
      expect(
        players.playing,
        lessThanOrEqualTo(1),
        reason: 'paging never leaves two decoders running',
      );
      expect(
        players.of('reel_1').playCount,
        1,
        reason:
            'a Yeel that scrolled away is not restarted by the arrival of a '
            'later page',
      );
    });

    testWidgets(
      'a refused second page keeps the loaded Yeels on screen and offers one '
      'retry',
      (tester) async {
        final calls = <String>[];
        final players = FakeReelPlayers();
        await _pumpFeed(
          tester,
          players: players,
          service: _pagingService(
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
            ),
            calls: calls,
            failPageTwo: true,
          ),
        );

        await tester.tap(find.byKey(_nextKey));
        await tester.pumpAndSettle();

        expect(
          find.byType(ReelCard),
          findsWidgets,
          reason: 'a paging failure never blanks what is already readable',
        );
        expect(
          find.byKey(const ValueKey<String>('reels-load-more-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('reels-load-more-retry')),
          findsOneWidget,
          reason: 'the failure carries a way out, not a dead end',
        );
      },
    );
  });

  group('listener ownership', () {
    testWidgets(
      'disposing the destination stops the decoder and drops the identity '
      'subscription',
      (tester) async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
        );
        final calls = <String>[];
        final players = FakeReelPlayers();
        await _pumpFeed(
          tester,
          players: players,
          service: _pagingService(auth: auth, calls: calls),
        );
        expect(players.of('reel_1').playing, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(
          players.playing,
          0,
          reason: 'nothing keeps decoding once the destination is gone',
        );

        final listsBefore = calls.where((c) => c == 'listReelsV2').length;
        await auth.signOut();
        await tester.pump();
        expect(
          calls.where((c) => c == 'listReelsV2').length,
          listsBefore,
          reason:
              'a disposed feed must not still be listening to identity and '
              'reloading itself',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

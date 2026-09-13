import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card_skeleton.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// Reels play by themselves.
///
/// The policy this file holds in place: a video Reel starts as soon as it is
/// the active page and its decoder is ready — no tap, on the first open and on
/// every scroll — but it starts SILENT, only ever one at a time, and it stops
/// whenever the viewer's attention demonstrably moved somewhere else (another
/// destination, another route, an open thread, the app in the background).
///
/// The video engine is injected, so this coverage is about the timing policy
/// and never starts a platform decoder.
void main() {
  group('coordinator', () {
    test('a video Yeel starts itself on attach, silently', () async {
      final video = _FakeVideoPlayback();
      final audio = _FakeAudioPlayback();
      final coordinator = _coordinator(
        _videoReel(),
        video: video,
        audio: audio,
        autoplay: true,
        muted: true,
      );
      addTearDown(coordinator.dispose);

      await coordinator.attachVideo(video);

      expect(coordinator.isPlaying, isTrue);
      expect(video.playCount, 1);
      // Silent means silent on both engines, not just the video track.
      expect(coordinator.isMuted, isTrue);
      expect(video.volume, 0);
      expect(audio.volume, 0);
      // The trim is still honoured: autoplay is the published timeline, not a
      // different one.
      expect(video.seekPositions.last, const Duration(seconds: 5));
      expect(audio.seekPositions.last, const Duration(seconds: 2));
    });

    test(
      'turning sound on restores the published mix without a restart',
      () async {
        final video = _FakeVideoPlayback();
        final audio = _FakeAudioPlayback();
        final coordinator = _coordinator(
          _videoReel(),
          video: video,
          audio: audio,
          autoplay: true,
          muted: true,
        );
        addTearDown(coordinator.dispose);
        await coordinator.attachVideo(video);

        await coordinator.setMuted(false);

        expect(coordinator.isMuted, isFalse);
        expect(video.volume, .35);
        expect(audio.volume, .65);
        // Nothing was stopped and started again to change the volume.
        expect(coordinator.isPlaying, isTrue);
        expect(video.playCount, 1);
        expect(audio.playCount, 1);
      },
    );

    test('a photo Yeel never starts itself and is never muted', () async {
      final audio = _FakeAudioPlayback();
      final coordinator = _coordinator(
        _photoReel(),
        audio: audio,
        autoplay: true,
        muted: true,
      );
      addTearDown(coordinator.dispose);

      expect(coordinator.autoplayEnabled, isFalse);
      await coordinator.autoplay();
      expect(coordinator.isPlaying, isFalse);
      expect(audio.playCount, 0);

      // Its backing track is the content, so a hand-start plays it aloud even
      // while the feed's sound preference is off.
      await coordinator.toggle();
      expect(coordinator.isPlaying, isTrue);
      expect(coordinator.isMuted, isFalse);
      expect(audio.volume, .7);
    });

    test('a composer preview still never starts itself', () async {
      final video = _FakeVideoPlayback();
      final source = _videoReel();
      final coordinator = ReelPlaybackCoordinator.draft(
        mediaKind: ReelMediaKind.video,
        composition: source.composition,
        backingAudioDurationMs: source.backingAudio!.durationMs,
        resolveBackingAudioUri: () async => Uri(scheme: 'memory', path: 'a'),
        audioPlaybackFactory: _FakeAudioPlayback.new,
      );
      addTearDown(coordinator.dispose);

      await coordinator.attachVideo(video);

      expect(coordinator.autoplayEnabled, isFalse);
      expect(coordinator.isPlaying, isFalse);
      expect(video.playCount, 0);
    });

    test('a hand-pause outranks autoplay until the page is left', () async {
      final video = _FakeVideoPlayback();
      final coordinator = _coordinator(
        _videoReel(),
        video: video,
        autoplay: true,
        muted: true,
      );
      addTearDown(coordinator.dispose);
      await coordinator.attachVideo(video);
      expect(coordinator.isPlaying, isTrue);

      await coordinator.toggle();
      expect(coordinator.isPlaying, isFalse);

      // Nothing that merely re-arms autoplay may undo it.
      await coordinator.autoplay();
      await coordinator.setAutoplaySuspended(true);
      await coordinator.setAutoplaySuspended(false);
      expect(coordinator.isPlaying, isFalse);
      expect(video.playCount, 1);

      // Scrolling away and back is a fresh visit, and a fresh visit plays.
      await coordinator.setActive(false);
      await coordinator.setActive(true);
      expect(coordinator.isPlaying, isTrue);
      expect(video.playCount, 2);
    });

    test('suspension stops playback and releasing it starts again', () async {
      final video = _FakeVideoPlayback();
      final coordinator = _coordinator(
        _videoReel(),
        video: video,
        autoplay: true,
        muted: true,
      );
      addTearDown(coordinator.dispose);

      await coordinator.setAutoplaySuspended(true);
      await coordinator.attachVideo(video);
      expect(coordinator.isPlaying, isFalse);
      expect(video.playCount, 0);

      await coordinator.setAutoplaySuspended(false);
      expect(coordinator.isPlaying, isTrue);
      expect(video.playCount, 1);

      await coordinator.setAutoplaySuspended(true);
      expect(coordinator.isPlaying, isFalse);
      expect(video.pauseCount, greaterThanOrEqualTo(1));
    });

    test('an inactive page never starts, however ready it becomes', () async {
      final video = _FakeVideoPlayback();
      final coordinator = _coordinator(
        _videoReel(),
        video: video,
        autoplay: true,
        muted: true,
      );
      addTearDown(coordinator.dispose);

      await coordinator.setActive(false);
      await coordinator.attachVideo(video);

      expect(coordinator.isPlaying, isFalse);
      expect(video.playCount, 0);
    });
  });

  group('feed', () {
    testWidgets('the first Yeel plays on open with no tap at all', (
      tester,
    ) async {
      final players = _Players();
      await _pumpFeed(tester, players: players, count: 2);

      expect(players.of('reel_1').playCount, 1);
      expect(players.of('reel_1').playing, isTrue);
      // Silent: the tab was opened, not asked for sound.
      expect(players.of('reel_1').volume, 0);
      expect(
        find.bySemanticsLabel('Turn sound on'),
        findsOneWidget,
        reason: 'a silent autoplay must offer the way back to sound',
      );
      // Nothing was tapped to get here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling to the next Yeel plays it and stops the last one', (
      tester,
    ) async {
      final players = _Players();
      await _pumpFeed(tester, players: players, count: 3);
      expect(players.of('reel_1').playing, isTrue);

      await _swipeToNextReel(tester, players);

      expect(players.of('reel_2').playCount, 1);
      expect(players.of('reel_2').playing, isTrue);
      expect(players.of('reel_1').playing, isFalse);

      await _swipeToNextReel(tester, players);

      expect(players.of('reel_3').playing, isTrue);
      expect(players.of('reel_2').playing, isFalse);
      expect(players.of('reel_1').playing, isFalse);
    });

    testWidgets('leaving the Yeels tab stops playback', (tester) async {
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final players = _Players();
      await _pumpFeed(tester, players: players, count: 2, isVisible: visible);
      expect(players.of('reel_1').playing, isTrue);

      visible.value = false;
      await tester.pumpAndSettle();

      expect(players.of('reel_1').playing, isFalse);
      expect(tester.widget<ReelCard>(find.byType(ReelCard)).isActive, isTrue);
      expect(
        tester.widget<ReelCard>(find.byType(ReelCard)).isHostVisible,
        isFalse,
      );

      // Coming back to the tab starts it again, still with no tap.
      visible.value = true;
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isTrue);
    });

    testWidgets('backgrounding the app stops playback and resuming restarts '
        'it', (tester) async {
      final players = _Players();
      await _pumpFeed(tester, players: players, count: 2);
      expect(players.of('reel_1').playing, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isTrue);
    });

    testWidgets('opening the comment thread stops playback, closing it '
        'resumes', (tester) async {
      final players = _Players();
      await _pumpFeed(tester, players: players, count: 2);
      expect(players.of('reel_1').playing, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey<String>('reel-comments-action')),
        ),
      );
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isFalse);

      Navigator.of(tester.element(find.byType(ReelCard))).pop();
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isTrue);
    });

    // D5, the ADR-170 amendment. The rule the two tests below hold in place
    // is not "a thread suspends playback" but "anything IN FRONT of the Reel
    // suspends playback": the phone sheet covers the media, the docked panel
    // stands beside it and covers nothing. Reading the conversation while the
    // Reel keeps playing is the entire reason the wide layout has a column
    // for it.
    testWidgets('the docked wide panel keeps the Yeel playing', (tester) async {
      final players = _Players();
      await _pumpFeed(
        tester,
        players: players,
        count: 2,
        size: const Size(1440, 900),
      );
      expect(players.of('reel_1').playing, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey<String>('reel-comments-action')),
        ),
      );
      await tester.pumpAndSettle();

      // The panel is docked, not pushed: nothing covers the media.
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('reel-comments-panel-view')),
        findsOneWidget,
      );
      expect(players.of('reel_1').playing, isTrue);
      // And it was never stopped and started again to get there.
      expect(players.of('reel_1').playCount, 1);
    });

    testWidgets('the phone sheet still suspends playback while it covers the '
        'Yeel', (tester) async {
      final players = _Players();
      await _pumpFeed(
        tester,
        players: players,
        count: 2,
        size: const Size(390, 844),
      );
      expect(players.of('reel_1').playing, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(ReelCard),
          matching: find.byKey(const ValueKey<String>('reel-comments-action')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(players.of('reel_1').playing, isFalse);

      Navigator.of(tester.element(find.byType(ReelCard))).pop();
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isTrue);
    });

    testWidgets('a tap still pauses, and autoplay does not fight it', (
      tester,
    ) async {
      final players = _Players();
      final likes = <Map<String, Object?>>[];
      await _pumpFeed(tester, players: players, count: 2, likeCalls: likes);
      expect(players.of('reel_1').playing, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-video-playback-surface')),
      );
      // The media now distinguishes one tap from the Instagram-style
      // double-tap, so the single-tap transport intent resolves after that
      // short gesture window.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isFalse);
      expect(likes, isEmpty, reason: 'one tap controls playback only');

      // A rebuild is not a reason to start playing again.
      await tester.pump();
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isFalse);
      expect(players.of('reel_1').playCount, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-video-playback-surface')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(players.of('reel_1').playing, isTrue);
    });

    testWidgets('a video double-tap likes once without pausing autoplay', (
      tester,
    ) async {
      final players = _Players();
      final likes = <Map<String, Object?>>[];
      await _pumpFeed(tester, players: players, count: 1, likeCalls: likes);
      final player = players.of('reel_1');
      expect(player.playing, isTrue);

      final media = find.byKey(
        const ValueKey<String>('reel-media-like-surface'),
      );
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 50));

      expect(likes, hasLength(1));
      expect(likes.single['liked'], isTrue);
      expect(player.playing, isTrue);
      expect(player.pauseCount, 0);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('reel-media-like-heart-effect'),
          ),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('sound is turned on once and carries to the next Yeel', (
      tester,
    ) async {
      final players = _Players();
      await _pumpFeed(tester, players: players, count: 2);
      expect(players.of('reel_1').volume, 0);

      await tester.tap(find.byKey(const ValueKey<String>('reel-sound-toggle')));
      await tester.pumpAndSettle();

      expect(players.of('reel_1').volume, .35);
      expect(find.bySemanticsLabel('Turn sound off'), findsOneWidget);
      // Still playing — sound is a volume change, not a restart.
      expect(players.of('reel_1').playing, isTrue);
      expect(players.of('reel_1').playCount, 1);

      await _swipeToNextReel(tester, players);

      expect(players.of('reel_2').playing, isTrue);
      expect(
        players.of('reel_2').volume,
        .35,
        reason: 'the preference belongs to the feed, not to one card',
      );
    });

    testWidgets('the sound switch follows the responsive media chrome at '
        'every width', (tester) async {
      for (final size in const <Size>[
        Size(320, 568),
        Size(390, 844),
        Size(768, 1024),
        Size(1100, 800),
        Size(1440, 900),
        // Short enough to fold the rail into a row, and short enough to drop
        // the identity column: the switch survives both.
        Size(560, 466),
        Size(320, 380),
      ]) {
        final players = _Players();
        await _pumpFeed(tester, players: players, count: 1, size: size);

        final card = find.byType(ReelCard);
        Finder inCard(Finder finder) =>
            find.descendant(of: card, matching: finder);
        final toggle = inCard(
          find.byKey(const ValueKey<String>('reel-sound-toggle')),
        );
        expect(toggle, findsOneWidget, reason: 'missing at $size');
        final target = tester.getSize(toggle);
        expect(target.width, greaterThanOrEqualTo(44), reason: '$size');
        expect(target.height, greaterThanOrEqualTo(44), reason: '$size');

        final viewport = inCard(
          find.byKey(const ValueKey<String>('reel-viewport')),
        );
        expect(viewport, findsOneWidget, reason: '$size');
        final frame = tester.getRect(viewport);
        final rect = tester.getRect(toggle);
        expect(rect.left, greaterThanOrEqualTo(frame.left), reason: '$size');
        expect(rect.top, greaterThanOrEqualTo(frame.top), reason: '$size');
        expect(rect.right, lessThanOrEqualTo(frame.right), reason: '$size');
        expect(rect.bottom, lessThanOrEqualTo(frame.bottom), reason: '$size');

        final rail = inCard(
          find.byKey(const ValueKey<String>('reel-action-rail')),
        );
        if (rail.evaluate().isNotEmpty) {
          // The media-first mobile fallback owns one trailing rail. Sound is
          // a separate top/end target, so neither it nor any action can mask
          // the other even when the viewport is very short.
          final overlay = tester.getRect(
            inCard(find.byKey(const ValueKey<String>('reel-footer'))),
          );
          final railRect = tester.getRect(rail);
          expect(rect.center.dx, greaterThan(frame.center.dx), reason: '$size');
          expect(rect.top, closeTo(overlay.top + 8, .01), reason: '$size');
          expect(rect.right, closeTo(frame.right - 12, .01), reason: '$size');
          expect(rect.overlaps(railRect), isFalse, reason: '$size');
          for (final key in const <String>[
            'reel-like-action',
            'reel-comments-action',
            'reel-share-action',
            'reel-more-action',
          ]) {
            final action = tester.getRect(
              inCard(find.byKey(ValueKey<String>(key))),
            );
            expect(rect.overlaps(action), isFalse, reason: '$key at $size');
          }
        } else {
          // A wide card keeps sound inside the authored media band, directly
          // above its progress bar. Engagement lives in the keyed footer
          // below the media and must remain independently tappable.
          final media = tester.getRect(
            inCard(find.byKey(const ValueKey<String>('reel-media-band'))),
          );
          final footer = tester.getRect(
            inCard(find.byKey(const ValueKey<String>('reel-stage-footer'))),
          );
          final bar = tester.getRect(
            inCard(find.byKey(const ValueKey<String>('reel-progress-bar'))),
          );
          expect(rect.left, closeTo(media.left + 16, .01), reason: '$size');
          expect(rect.center.dx, lessThan(media.center.dx), reason: '$size');
          expect(
            rect.bottom,
            lessThanOrEqualTo(bar.top + .01),
            reason: '$size',
          );
          expect(rect.overlaps(footer), isFalse, reason: '$size');
          for (final key in const <String>[
            'reel-like-action',
            'reel-comments-action',
            'reel-share-action',
            'reel-more-action',
          ]) {
            final action = tester.getRect(
              inCard(find.byKey(ValueKey<String>(key))),
            );
            expect(rect.overlaps(action), isFalse, reason: '$key at $size');
          }
        }
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('loading and failing media never fake playback', (
      tester,
    ) async {
      final players = _Players();
      await _pumpFeed(
        tester,
        players: players,
        count: 1,
        grant: _Grant.pending,
        idPrefix: 'pending',
        settle: false,
      );
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Either loading shape is correct here — the stage skeleton before the
      // page lands, the in-frame indicator while the grant is outstanding.
      // What matters is that neither one plays anything.
      expect(
        find.byType(YoLoadingIndicator).evaluate().isNotEmpty ||
            find.byType(ReelCardSkeleton).evaluate().isNotEmpty,
        isTrue,
      );
      expect(players.of('pending_1').playing, isFalse);

      final failed = _Players();
      await _pumpFeed(
        tester,
        players: failed,
        count: 1,
        grant: _Grant.bad,
        idPrefix: 'bad',
      );
      expect(find.text('This Yeel is unavailable right now.'), findsOneWidget);
      expect(failed.playing, 0);
      // A Reel that cannot be fetched must not pretend to be playing.
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('reel-playback-toggle')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a photo Yeel in the feed still waits to be asked', (
      tester,
    ) async {
      final players = _Players();
      final audio = _FakeAudioPlayback();
      final likes = <Map<String, Object?>>[];
      await _pumpFeed(
        tester,
        players: players,
        count: 1,
        photo: true,
        likeCalls: likes,
        audioPlaybackFactory: () => audio,
      );

      expect(audio.playCount, 0);
      expect(find.byTooltip('Play backing audio'), findsOneWidget);
      // And a photo carries no sound switch, because its track is content.
      expect(
        find.byKey(const ValueKey<String>('reel-sound-toggle')),
        findsNothing,
      );

      final media = find.byKey(
        const ValueKey<String>('reel-media-like-surface'),
      );
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 50));
      expect(likes, hasLength(1));
      expect(likes.single['liked'], isTrue);
      expect(
        audio.playCount,
        0,
        reason: 'liking a photo never starts its audio',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });
  });
}

/// Drags one page up and asserts, on every frame of the gesture, that no two
/// Reels are ever playing at the same time.
Future<void> _swipeToNextReel(WidgetTester tester, _Players players) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ReelCard)),
  );
  for (var step = 0; step < 12; step++) {
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      players.playing,
      lessThanOrEqualTo(1),
      reason: 'only one Yeel may hold the player, mid-scroll included',
    );
  }
  await gesture.up();
  await tester.pumpAndSettle();
  expect(players.playing, lessThanOrEqualTo(1));
}

ReelPlaybackCoordinator _coordinator(
  Reel reel, {
  _FakeVideoPlayback? video,
  _FakeAudioPlayback? audio,
  required bool autoplay,
  required bool muted,
}) {
  final backing = audio ?? _FakeAudioPlayback();
  return ReelPlaybackCoordinator(
    reel: reel,
    resolveBackingAudioUri: () async =>
        Uri.parse('https://storage.googleapis.com/yovoice/audio.mp3'),
    audioPlaybackFactory: () => backing,
    autoplay: autoplay,
    muted: muted,
  );
}

enum _Grant { ok, pending, bad }

Future<void> _pumpFeed(
  WidgetTester tester, {
  required _Players players,
  required int count,
  Size size = const Size(390, 844),
  bool photo = false,
  bool settle = true,
  _Grant grant = _Grant.ok,
  // ReelService._grantCache is static, so a Reel id already granted earlier
  // in this process resolves instantly. Cases that need an outstanding or a
  // failing grant must therefore use ids of their own.
  String idPrefix = 'reel',
  ValueListenable<bool>? isVisible,
  ReelAudioPlaybackFactory? audioPlaybackFactory,
  List<Map<String, Object?>>? likeCalls,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: ReelsFeedScreen(
          // A fresh state per pump: without a key the screen's State — and
          // its `late final` service — is reused across pumpWidget calls.
          key: ValueKey<Object>(<Object>[size, count, photo, grant]),
          embedded: true,
          service: _service(
            count: count,
            photo: photo,
            grant: grant,
            idPrefix: idPrefix,
            likeCalls: likeCalls,
          ),
          isVisible: isVisible,
          onOpenAuthor: (_) {},
          // Every Reel here carries a backing track, so the engine must be
          // injected: the real one reaches for a platform audio player.
          audioPlaybackFactory: audioPlaybackFactory ?? _FakeAudioPlayback.new,
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

ReelService _service({
  required int count,
  required bool photo,
  required _Grant grant,
  required String idPrefix,
  List<Map<String, Object?>>? likeCalls,
}) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    if (name == 'listReelsV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'items': <Object?>[
          for (var index = 1; index <= count; index++)
            photo ? _photoWire(index, idPrefix) : _videoWire(index, idPrefix),
        ],
        'nextCursor': null,
      };
    }
    if (name == 'getReelMediaAccessV2') {
      if (grant == _Grant.bad) throw StateError('grant refused');
      if (grant == _Grant.pending) {
        await Completer<void>().future;
      }
      final isAudio = payload['asset'] == 'backingAudio';
      return <Object?, Object?>{
        'schemaVersion': 2,
        'url': isAudio
            ? 'https://storage.googleapis.com/yovoice/audio.mp3'
            : 'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
        'expiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'generation': '7',
        'availabilityHours': 'permanent',
        'contentExpiresAtMillis': null,
      };
    }
    if (name == 'listReelCommentsV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'items': <Object?>[],
        'nextCursor': null,
      };
    }
    if (name == 'setReelLike') {
      likeCalls?.add(Map<String, Object?>.from(payload));
      return <Object?, Object?>{
        'reelId': payload['reelId'],
        'liked': true,
        'changed': true,
        'likeCount': 1,
      };
    }
    throw StateError('Unexpected callable $name with $payload');
  },
);

Map<String, Object?> _videoWire(int index, [String idPrefix = 'reel']) {
  final millis = 1725000000000 + index;
  return <String, Object?>{
    'id': '${idPrefix}_$index',
    'authorId': 'creator_$index',
    'authorName': 'Creator $index',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 20000,
    },
    'backingAudio': <String, Object?>{
      'contentType': 'audio/mpeg',
      'size': 4096,
      'generation': '8',
      'durationMs': 12000,
    },
    'composition': const ReelComposition(
      trimStartMs: 5000,
      trimEndMs: 15000,
      originalAudioVolume: 35,
      backingAudioVolume: 65,
      audioTrimStartMs: 2000,
      audioRightsAttested: true,
      caption: 'Night shift stories.',
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_${idPrefix}_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 0,
    'commentCount': 0,
    'callerLiked': false,
  };
}

Map<String, Object?> _photoWire(int index, [String idPrefix = 'reel']) =>
    Map<String, Object?>.of(_videoWire(index, idPrefix))
      ..['media'] = <String, Object?>{
        'kind': 'image',
        'contentType': 'image/jpeg',
        'size': 4096,
        'generation': '7',
        'durationMs': 0,
      }
      ..['composition'] = const ReelComposition(
        originalAudioVolume: 0,
        backingAudioVolume: 70,
        audioTrimStartMs: 1000,
        audioRightsAttested: true,
        caption: 'Night shift stories.',
      ).toWire();

Reel _videoReel() => Reel(
  id: 'video_reel',
  authorId: 'creator',
  authorName: 'Creator',
  media: const ReelMediaDescriptor(
    kind: ReelMediaKind.video,
    contentType: 'video/mp4',
    size: 4096,
    generation: '1',
    durationMs: 20000,
  ),
  backingAudio: const ReelBackingAudioDescriptor(
    contentType: 'audio/mpeg',
    size: 4096,
    generation: '2',
    durationMs: 12000,
  ),
  composition: const ReelComposition(
    trimStartMs: 5000,
    trimEndMs: 15000,
    originalAudioVolume: 35,
    backingAudioVolume: 65,
    audioTrimStartMs: 2000,
    audioRightsAttested: true,
  ),
  publishedAt: DateTime.utc(2026, 9, 3),
  sortKey: '1788408000000_video_reel',
);

Reel _photoReel() => Reel(
  id: 'photo_reel',
  authorId: 'creator',
  authorName: 'Creator',
  media: const ReelMediaDescriptor(
    kind: ReelMediaKind.image,
    contentType: 'image/jpeg',
    size: 4096,
    generation: '3',
    durationMs: 0,
  ),
  backingAudio: const ReelBackingAudioDescriptor(
    contentType: 'audio/mpeg',
    size: 4096,
    generation: '4',
    durationMs: 3000,
  ),
  composition: const ReelComposition(
    originalAudioVolume: 0,
    backingAudioVolume: 70,
    audioTrimStartMs: 1000,
    audioRightsAttested: true,
  ),
  publishedAt: DateTime.utc(2026, 9, 3),
  sortKey: '1788408000000_photo_reel',
);

/// One engine per Reel id, kept across mounts so a page that is scrolled away
/// and back is still observable.
class _Players {
  final Map<String, _FakeVideoPlayback> _byReel =
      <String, _FakeVideoPlayback>{};

  _FakeVideoPlayback of(String reelId) =>
      _byReel.putIfAbsent(reelId, _FakeVideoPlayback.new);

  int get playing => _byReel.values.where((player) => player.playing).length;
}

class _FakeVideoPlayback implements ReelVideoPlayback {
  bool playing = false;
  @override
  Duration position = Duration.zero;
  double volume = 1;
  int playCount = 0;
  int pauseCount = 0;
  final List<Duration> seekPositions = <Duration>[];

  @override
  bool get isPlaying => playing;

  @override
  Future<void> pause() async {
    pauseCount += 1;
    playing = false;
  }

  @override
  Future<void> play() async {
    playCount += 1;
    playing = true;
  }

  @override
  Future<void> seek(Duration value) async {
    seekPositions.add(value);
    position = value;
  }

  @override
  Future<void> setVolume(double value) async => volume = value;
}

class _FakeAudioPlayback implements ReelAudioPlayback {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );

  double volume = 1;
  int playCount = 0;
  int pauseCount = 0;
  final List<Uri> loaded = <Uri>[];
  final List<Duration> seekPositions = <Duration>[];

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Duration> get positionChanges => _positions.stream;

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _completions.close();
  }

  @override
  Future<void> load(Uri uri) async => loaded.add(uri);

  @override
  Future<void> pause() async => pauseCount += 1;

  @override
  Future<void> play() async => playCount += 1;

  @override
  Future<void> seek(Duration position) async => seekPositions.add(position);

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> stop() async {}
}

import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

void main() {
  testWidgets(
    'a late decoder initialization cannot replace or mutate the current player',
    (tester) async {
      final reel = _videoReel();
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'reel-controller-race-viewer'),
        ),
        callableInvoker: (name, payload) async {
          expect(name, 'getReelMediaAccessV2');
          expect(payload['reelId'], reel.id);
          return <Object?, Object?>{
            'schemaVersion': 2,
            'url': 'https://storage.googleapis.com/yovoice/race.mp4',
            'expiresAtMillis': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
            'generation': '1',
            'availabilityHours': 'permanent',
            'contentExpiresAtMillis': null,
          };
        },
      );
      await service.resolveMediaUri(reel.id);

      final first = _ControlledVideoController('first');
      final second = _ControlledVideoController('second');
      VideoPlayerController firstFactory(Uri _) => first;
      VideoPlayerController secondFactory(Uri _) => second;

      Widget host(ReelNetworkVideoControllerFactory factory) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 700,
            child: ReelCard(
              key: const ValueKey('retained-race-card'),
              reel: reel,
              service: service,
              autoplay: false,
              videoControllerFactory: factory,
            ),
          ),
        ),
      );

      await tester.pumpWidget(host(firstFactory));
      expect(first.initializeStarted.isCompleted, isTrue);
      final retainedCardState = tester.state(find.byType(ReelCard));

      await tester.pumpWidget(host(secondFactory));
      expect(tester.state(find.byType(ReelCard)), same(retainedCardState));
      expect(second.initializeStarted.isCompleted, isTrue);
      expect(first.disposed, isTrue);
      expect(first.disposeCount, 1);

      // The replacement finishes first and becomes the only attached player.
      second.finishInitialization();
      await _pumpAsyncWork(tester);
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(second),
      );
      expect(second.calls, containsAll(<String>['looping', 'volume', 'seek']));

      // The retired controller then completes out of order. It must be
      // discarded before setLooping, setVolume, seekTo or coordinator attach.
      first.finishInitialization();
      await _pumpAsyncWork(tester);
      expect(first.mutationsAfterDispose, isEmpty);
      expect(first.disposeCount, 1);
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(second),
      );
      tester
          .widget<ReelPlaybackSurface>(find.byType(ReelPlaybackSurface))
          .onToggle();
      await _pumpAsyncWork(tester);
      expect(second.calls, contains('play'));
      expect(first.calls, isNot(contains('play')));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpAsyncWork(tester);
      expect(second.disposeCount, 1);
    },
  );

  testWidgets(
    'an attach in flight finishes before the stale controller is disposed',
    (tester) async {
      final reel = _videoReel();
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'reel-attach-race-viewer'),
        ),
        callableInvoker: (name, payload) async {
          expect(name, 'getReelMediaAccessV2');
          expect(payload['reelId'], reel.id);
          return <Object?, Object?>{
            'schemaVersion': 2,
            'url': 'https://storage.googleapis.com/yovoice/attach-race.mp4',
            'expiresAtMillis': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
            'generation': '2',
            'availabilityHours': 'permanent',
            'contentExpiresAtMillis': null,
          };
        },
      );
      await service.resolveMediaUri(reel.id);

      final first = _ControlledVideoController(
        'attaching-first',
        blockVolumeCall: 2,
        failPause: true,
      );
      final second = _ControlledVideoController('replacement-second');
      VideoPlayerController firstFactory(Uri _) => first;
      VideoPlayerController secondFactory(Uri _) => second;

      Widget host(ReelNetworkVideoControllerFactory factory) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 700,
            child: ReelCard(
              key: const ValueKey('retained-attach-race-card'),
              reel: reel,
              service: service,
              autoplay: false,
              videoControllerFactory: factory,
            ),
          ),
        ),
      );

      await tester.pumpWidget(host(firstFactory));
      first.finishInitialization();
      await _pumpAsyncWork(tester);
      expect(first.blockedVolumeStarted.isCompleted, isTrue);
      expect(first.disposed, isFalse);

      // Keep the ReelCard and coordinator, but replace the decoder while the
      // old coordinator attach is suspended inside setVolume.
      await tester.pumpWidget(host(secondFactory));
      expect(second.initializeStarted.isCompleted, isTrue);
      second.finishInitialization();
      await _pumpAsyncWork(tester);
      expect(second.calls, containsAll(<String>['looping', 'volume', 'seek']));
      expect(
        first.disposed,
        isFalse,
        reason: 'an in-flight platform mutation must finish before dispose',
      );

      first.releaseBlockedVolume();
      await _pumpAsyncWork(tester);

      expect(first.disposed, isTrue);
      expect(first.disposeCount, 1);
      expect(first.mutationsAfterDispose, isEmpty);
      expect(first.calls, contains('pause-error'));
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(second),
      );
      tester
          .widget<ReelPlaybackSurface>(find.byType(ReelPlaybackSurface))
          .onToggle();
      await _pumpAsyncWork(tester);
      expect(second.calls, contains('play'));
      expect(first.calls, isNot(contains('play')));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpAsyncWork(tester);
      expect(second.disposeCount, 1);
    },
  );
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame += 1) {
    await tester.pump();
  }
}

Reel _videoReel() => Reel(
  id: 'reel_controller_initialization_race',
  authorId: 'creator',
  authorName: 'Creator',
  media: const ReelMediaDescriptor(
    kind: ReelMediaKind.video,
    contentType: 'video/mp4',
    size: 4096,
    generation: '1',
    durationMs: 20000,
  ),
  composition: const ReelComposition(
    trimStartMs: 2000,
    trimEndMs: 18000,
    originalAudioVolume: 80,
  ),
  publishedAt: DateTime.utc(2026, 9, 14),
  sortKey: '1789344000000_reel_controller_initialization_race',
);

class _ControlledVideoController implements VideoPlayerController {
  _ControlledVideoController(
    this.name, {
    this.blockVolumeCall,
    this.failPause = false,
  });

  final String name;
  final int? blockVolumeCall;
  final bool failPause;
  final Completer<void> initializeStarted = Completer<void>();
  final Completer<void> _initializeGate = Completer<void>();
  final Completer<void> blockedVolumeStarted = Completer<void>();
  final Completer<void> _blockedVolumeRelease = Completer<void>();
  final List<VoidCallback> _listeners = <VoidCallback>[];
  final List<String> calls = <String>[];
  final List<String> mutationsAfterDispose = <String>[];
  VideoPlayerValue _value = const VideoPlayerValue(
    duration: Duration(seconds: 20),
  );
  bool disposed = false;
  int disposeCount = 0;
  int _volumeCalls = 0;

  void finishInitialization() => _initializeGate.complete();

  void releaseBlockedVolume() => _blockedVolumeRelease.complete();

  void _mutate(String operation, VideoPlayerValue next) {
    calls.add(operation);
    if (disposed) mutationsAfterDispose.add(operation);
    _value = next;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  VideoPlayerValue get value => _value;

  @override
  set value(VideoPlayerValue value) => _mutate('value', value);

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    if (!initializeStarted.isCompleted) initializeStarted.complete();
    await _initializeGate.future;
    _value = _value.copyWith(isInitialized: true, size: const Size(720, 1280));
  }

  @override
  Future<void> setLooping(bool looping) async {
    _mutate('looping', _value.copyWith(isLooping: looping));
  }

  @override
  Future<void> setVolume(double volume) async {
    _volumeCalls += 1;
    if (_volumeCalls == blockVolumeCall) {
      blockedVolumeStarted.complete();
      await _blockedVolumeRelease.future;
    }
    _mutate('volume', _value.copyWith(volume: volume));
  }

  @override
  Future<void> seekTo(Duration position) async {
    _mutate('seek', _value.copyWith(position: position));
  }

  @override
  Future<void> play() async {
    _mutate('play', _value.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    if (failPause) {
      calls.add('pause-error');
      if (disposed) mutationsAfterDispose.add('pause-error');
      throw StateError('$name pause failed');
    }
    _mutate('pause', _value.copyWith(isPlaying: false));
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  String toString() => '_ControlledVideoController($name)';
}

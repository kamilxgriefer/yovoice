import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

void main() {
  group('ReelPlaybackCoordinator', () {
    test(
      'starts, pauses and loops video and backing audio on one timeline',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _videoReel(),
          resolveBackingAudioUri: () async => Uri.parse(
            'https://storage.googleapis.com/yovoice/reel-audio.mp3',
          ),
          audioPlaybackFactory: () => audio,
        );
        addTearDown(coordinator.dispose);

        await coordinator.attachVideo(video);
        await coordinator.toggle();

        expect(coordinator.isPlaying, isTrue);
        expect(video.seekPositions, contains(const Duration(seconds: 5)));
        expect(audio.seekPositions, contains(const Duration(seconds: 2)));
        expect(video.volume, .35);
        expect(audio.volume, .65);
        expect(video.playCount, 1);
        expect(audio.playCount, 1);

        await coordinator.toggle();
        expect(coordinator.isPlaying, isFalse);
        expect(video.pauseCount, greaterThanOrEqualTo(1));
        expect(audio.pauseCount, greaterThanOrEqualTo(1));

        await coordinator.toggle();
        video
          ..position = const Duration(seconds: 15)
          ..playing = true;
        await coordinator.synchronizeVideoTick();

        expect(coordinator.isPlaying, isTrue);
        expect(video.seekPositions.last, const Duration(seconds: 5));
        expect(audio.seekPositions.last, const Duration(seconds: 2));
        expect(video.playCount, 3);
        expect(audio.playCount, 3);
      },
    );

    test(
      'corrects only material backing-track drift inside a bounded window',
      () async {
        var now = DateTime.utc(2026, 9, 3, 4);
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _videoReel(),
          resolveBackingAudioUri: () async => Uri.parse(
            'https://storage.googleapis.com/yovoice/reel-audio.mp3',
          ),
          audioPlaybackFactory: () => audio,
          now: () => now,
        );
        addTearDown(coordinator.dispose);

        await coordinator.attachVideo(video);
        await coordinator.toggle();
        video
          ..position = const Duration(seconds: 7)
          ..playing = true;
        audio.emitPosition(const Duration(milliseconds: 2400));
        await coordinator.synchronizeVideoTick();
        expect(audio.seekPositions.last, const Duration(seconds: 4));

        final corrections = audio.seekPositions.length;
        video.position = const Duration(seconds: 8);
        audio.emitPosition(const Duration(seconds: 2));
        await coordinator.synchronizeVideoTick();
        expect(audio.seekPositions, hasLength(corrections));

        now = now.add(const Duration(milliseconds: 751));
        await coordinator.synchronizeVideoTick();
        expect(audio.seekPositions.last, const Duration(seconds: 5));
      },
    );

    test('photo backing audio stops at its selected end and resets', () async {
      final audio = _FakeAudioPlayback();
      final coordinator = ReelPlaybackCoordinator(
        reel: _photoReel(),
        resolveBackingAudioUri: () async =>
            Uri.parse('https://storage.googleapis.com/yovoice/photo-audio.mp3'),
        audioPlaybackFactory: () => audio,
      );
      addTearDown(coordinator.dispose);

      expect(coordinator.timelineDuration, const Duration(seconds: 2));
      await coordinator.toggle();
      expect(coordinator.isPlaying, isTrue);

      audio.emitPosition(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isPlaying, isFalse);
      expect(audio.pauseCount, greaterThanOrEqualTo(1));
      expect(audio.seekPositions.last, const Duration(seconds: 1));
    });

    test('deactivation prevents a delayed grant from starting media', () async {
      final grant = Completer<Uri>();
      final audio = _FakeAudioPlayback();
      final video = _FakeVideoPlayback();
      final coordinator = ReelPlaybackCoordinator(
        reel: _videoReel(),
        resolveBackingAudioUri: () => grant.future,
        audioPlaybackFactory: () => audio,
      );
      addTearDown(coordinator.dispose);

      await coordinator.attachVideo(video);
      final play = coordinator.toggle();
      await Future<void>.delayed(Duration.zero);
      final inactive = coordinator.setActive(false);
      grant.complete(
        Uri.parse('https://storage.googleapis.com/yovoice/reel-audio.mp3'),
      );
      await play;
      await inactive;

      expect(coordinator.isPlaying, isFalse);
      expect(video.playCount, 0);
      expect(audio.playCount, 0);
      expect(video.seekPositions.last, const Duration(seconds: 5));
      expect(audio.seekPositions.last, const Duration(seconds: 2));
    });
  });

  testWidgets('video playback surface supports Enter and Space', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReelPlaybackSurface(
            isPlaying: false,
            onToggle: () => toggles += 1,
            child: const SizedBox(
              width: 240,
              height: 320,
              child: Center(child: Text('Video frame')),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Play video'), findsOneWidget);
    Focus.of(tester.element(find.text('Video frame'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(toggles, 2);
  });

  testWidgets('photo Reel exposes a clear finite play and pause action', (
    tester,
  ) async {
    final audio = _FakeAudioPlayback();
    final service = ReelService(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      callableInvoker: (name, payload) async {
        expect(name, 'getReelMediaAccess');
        final isAudio = payload['asset'] == 'backingAudio';
        return <Object?, Object?>{
          'schemaVersion': 1,
          'url': isAudio
              ? 'https://storage.googleapis.com/yovoice/photo-audio.mp3'
              : 'https://storage.googleapis.com/yovoice/photo.jpg',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': isAudio ? '4' : '3',
        };
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 700,
            child: ReelCard(
              reel: _photoReel(),
              service: service,
              audioPlaybackFactory: () => audio,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final toggle = find.byKey(const ValueKey('reel-playback-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.byTooltip('Play backing audio'), findsOneWidget);
    expect(tester.getSize(toggle).shortestSide, greaterThanOrEqualTo(44));

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Pause backing audio'), findsOneWidget);
    expect(audio.playCount, 1);

    audio.emitPosition(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Play backing audio'), findsOneWidget);
    expect(audio.seekPositions.last, const Duration(seconds: 1));
  });
}

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
  int stopCount = 0;
  final List<Uri> loaded = <Uri>[];
  final List<Duration> seekPositions = <Duration>[];

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Duration> get positionChanges => _positions.stream;

  void emitPosition(Duration position) => _positions.add(position);

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
  Future<void> stop() async => stopCount += 1;
}

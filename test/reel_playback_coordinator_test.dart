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
      'local draft uses published trim, mix and loop semantics without a Yeel',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final source = _videoReel();
        final coordinator = ReelPlaybackCoordinator.draft(
          mediaKind: ReelMediaKind.video,
          composition: source.composition,
          backingAudioDurationMs: source.backingAudio!.durationMs,
          resolveBackingAudioUri: () async =>
              Uri(scheme: 'memory', path: 'audio'),
          audioPlaybackFactory: () => audio,
        );
        addTearDown(coordinator.dispose);
        expect(coordinator.reel, isNull);
        await coordinator.attachVideo(video);
        await coordinator.toggle();
        expect(video.seekPositions.last, const Duration(seconds: 5));
        expect(audio.seekPositions.last, const Duration(seconds: 2));
        expect(video.volume, .35);
        expect(audio.volume, .65);
        video
          ..position = const Duration(seconds: 15)
          ..playing = true;
        await coordinator.synchronizeVideoTick();
        expect(video.seekPositions.last, const Duration(seconds: 5));
        expect(audio.seekPositions.last, const Duration(seconds: 2));
        await coordinator.setActive(false);
        expect(coordinator.isPlaying, isFalse);
        expect(video.playing, isFalse);
      },
    );

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
      'a detached attach operation cannot seek after its volume call returns',
      () async {
        final first = _FakeVideoPlayback();
        final replacement = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _videoReel(),
          resolveBackingAudioUri: () async =>
              Uri.parse('https://storage.googleapis.com/yovoice/audio.mp3'),
          audioPlaybackFactory: _FakeAudioPlayback.new,
        );
        addTearDown(coordinator.dispose);

        final blockedVolume = first.blockNextVolume();
        final blockedPause = first.blockNextPause();
        final firstAttach = coordinator.attachVideo(first);
        await blockedVolume.started.future;

        final firstDetachment = coordinator.detachVideo(first);
        final replacementAttach = coordinator.attachVideo(replacement);
        blockedVolume.release.complete();
        await firstAttach;
        await blockedPause.started.future;
        expect(
          replacement.volume,
          1,
          reason: 'replacement attach must wait for the old decoder to pause',
        );
        blockedPause.release.complete();
        await firstDetachment;
        await replacementAttach;

        expect(blockedVolume.returned.isCompleted, isTrue);
        expect(blockedPause.returned.isCompleted, isTrue);
        expect(
          first.seekPositions,
          isEmpty,
          reason: 'the stale queued attach must stop after its awaited call',
        );
        expect(replacement.volume, .35);
        expect(replacement.seekPositions, <Duration>[
          const Duration(seconds: 5),
        ]);

        await coordinator.toggle();
        expect(first.playCount, 0);
        expect(replacement.playCount, 1);
      },
    );

    test(
      'a rejected video pause still stops backing audio on detach',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _videoReel(),
          resolveBackingAudioUri: () async =>
              Uri.parse('https://storage.googleapis.com/yovoice/audio.mp3'),
          audioPlaybackFactory: () => audio,
        );
        addTearDown(coordinator.dispose);

        await coordinator.attachVideo(video);
        await coordinator.toggle();
        final audioPausesBeforeDetach = audio.pauseCount;
        video.pauseError = StateError('decoder rejected pause');

        await expectLater(coordinator.detachVideo(video), throwsStateError);

        expect(audio.pauseCount, audioPausesBeforeDetach + 1);
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

    test(
      'short backing audio completion wraps from the video clock without touching video playback',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _shortBackingAudioVideoReel(),
          resolveBackingAudioUri: () async => Uri.parse(
            'https://storage.googleapis.com/yovoice/short-reel-audio.mp3',
          ),
          audioPlaybackFactory: () => audio,
        );
        addTearDown(coordinator.dispose);

        await coordinator.attachVideo(video);
        await coordinator.toggle();
        video
          ..position = const Duration(milliseconds: 14500)
          ..playing = true;
        final videoPlayCount = video.playCount;
        final videoPauseCount = video.pauseCount;
        final videoSeekCount = video.seekPositions.length;
        final audioPlayCount = audio.playCount;
        final restarted = audio.waitForNextPlay();

        audio.emitCompletion();
        await restarted;

        // The four-second backing-audio window starts at 2s. At 14.5s on a
        // video trimmed from 5s, the expected audio clock is 2s + (9.5s % 4s).
        expect(audio.seekPositions.last, const Duration(milliseconds: 3500));
        expect(audio.playCount, audioPlayCount + 1);
        expect(video.playCount, videoPlayCount);
        expect(video.pauseCount, videoPauseCount);
        expect(video.seekPositions, hasLength(videoSeekCount));
        expect(video.position, const Duration(milliseconds: 14500));
        expect(video.isPlaying, isTrue);
        expect(coordinator.isPlaying, isTrue);
      },
    );

    test(
      'pause during completion seek prevents a late audio restart',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _shortBackingAudioVideoReel(),
          resolveBackingAudioUri: () async =>
              Uri.parse('https://storage.googleapis.com/yovoice/audio.mp3'),
          audioPlaybackFactory: () => audio,
        );
        addTearDown(coordinator.dispose);

        await coordinator.attachVideo(video);
        await coordinator.toggle();
        video
          ..position = const Duration(milliseconds: 14500)
          ..playing = true;
        final audioPlayCount = audio.playCount;
        final blockedSeek = audio.blockNextSeek();

        audio.emitCompletion();
        await blockedSeek.started.future;
        final paused = coordinator.pause();
        blockedSeek.release.complete();
        await blockedSeek.returned.future;
        await paused;

        expect(audio.playCount, audioPlayCount);
        expect(audio.pauseCount, greaterThanOrEqualTo(1));
        expect(video.isPlaying, isFalse);
        expect(coordinator.isPlaying, isFalse);
      },
    );

    test(
      'deactivation during completion seek prevents a late audio restart',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _shortBackingAudioVideoReel(),
          resolveBackingAudioUri: () async =>
              Uri.parse('https://storage.googleapis.com/yovoice/audio.mp3'),
          audioPlaybackFactory: () => audio,
        );
        addTearDown(coordinator.dispose);

        await coordinator.attachVideo(video);
        await coordinator.toggle();
        video
          ..position = const Duration(milliseconds: 14500)
          ..playing = true;
        final audioPlayCount = audio.playCount;
        final blockedSeek = audio.blockNextSeek();

        audio.emitCompletion();
        await blockedSeek.started.future;
        final deactivated = coordinator.setActive(false);
        blockedSeek.release.complete();
        await blockedSeek.returned.future;
        await deactivated;

        expect(audio.playCount, audioPlayCount);
        expect(audio.pauseCount, greaterThanOrEqualTo(1));
        expect(video.isPlaying, isFalse);
        expect(coordinator.isPlaying, isFalse);
      },
    );

    test(
      'dispose during completion seek prevents a late audio restart',
      () async {
        final audio = _FakeAudioPlayback();
        final video = _FakeVideoPlayback();
        final coordinator = ReelPlaybackCoordinator(
          reel: _shortBackingAudioVideoReel(),
          resolveBackingAudioUri: () async =>
              Uri.parse('https://storage.googleapis.com/yovoice/audio.mp3'),
          audioPlaybackFactory: () => audio,
        );

        await coordinator.attachVideo(video);
        await coordinator.toggle();
        video
          ..position = const Duration(milliseconds: 14500)
          ..playing = true;
        final audioPlayCount = audio.playCount;
        final blockedSeek = audio.blockNextSeek();

        audio.emitCompletion();
        await blockedSeek.started.future;
        coordinator.dispose();
        blockedSeek.release.complete();
        await blockedSeek.returned.future;
        coordinator.dispose();
        await coordinator.retirement;
        await Future<void>.delayed(Duration.zero);

        expect(audio.playCount, audioPlayCount);
        expect(audio.stopCount, 1);
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

  testWidgets('photo Yeel exposes a clear finite play and pause action', (
    tester,
  ) async {
    final audio = _FakeAudioPlayback();
    final service = ReelService(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      callableInvoker: (name, payload) async {
        expect(name, 'getReelMediaAccessV2');
        final isAudio = payload['asset'] == 'backingAudio';
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url': isAudio
              ? 'https://storage.googleapis.com/yovoice/photo-audio.mp3'
              : 'https://storage.googleapis.com/yovoice/photo.jpg',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': isAudio ? '4' : '3',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
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

Reel _shortBackingAudioVideoReel() => Reel(
  id: 'short_audio_video_reel',
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
    durationMs: 6000,
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
  sortKey: '1788408000000_short_audio_video_reel',
);

class _FakeVideoPlayback implements ReelVideoPlayback {
  bool playing = false;
  @override
  Duration position = Duration.zero;
  double volume = 1;
  int playCount = 0;
  int pauseCount = 0;
  Object? pauseError;
  final List<Duration> seekPositions = <Duration>[];
  _BlockedVolume? _nextBlockedVolume;
  _BlockedPause? _nextBlockedPause;

  _BlockedVolume blockNextVolume() {
    final blocked = _BlockedVolume();
    _nextBlockedVolume = blocked;
    return blocked;
  }

  _BlockedPause blockNextPause() {
    final blocked = _BlockedPause();
    _nextBlockedPause = blocked;
    return blocked;
  }

  @override
  bool get isPlaying => playing;

  @override
  Future<void> pause() async {
    pauseCount += 1;
    final blocked = _nextBlockedPause;
    _nextBlockedPause = null;
    if (blocked != null) {
      blocked.started.complete();
      await blocked.release.future;
    }
    final error = pauseError;
    pauseError = null;
    if (error != null) throw error;
    playing = false;
    if (blocked != null) blocked.returned.complete();
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
  Future<void> setVolume(double value) async {
    final blocked = _nextBlockedVolume;
    _nextBlockedVolume = null;
    if (blocked != null) {
      blocked.started.complete();
      await blocked.release.future;
    }
    volume = value;
    if (blocked != null) blocked.returned.complete();
  }
}

class _BlockedVolume {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  final Completer<void> returned = Completer<void>();
}

class _BlockedPause {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  final Completer<void> returned = Completer<void>();
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
  Completer<void>? _nextPlay;
  _BlockedSeek? _nextBlockedSeek;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Duration> get positionChanges => _positions.stream;

  void emitPosition(Duration position) => _positions.add(position);

  void emitCompletion() => _completions.add(null);

  Future<void> waitForNextPlay() {
    final pending = _nextPlay;
    if (pending != null && !pending.isCompleted) {
      throw StateError('Already waiting for the next audio play');
    }
    final next = Completer<void>();
    _nextPlay = next;
    return next.future;
  }

  _BlockedSeek blockNextSeek() {
    final existing = _nextBlockedSeek;
    if (existing != null && !existing.returned.isCompleted) {
      throw StateError('An audio seek is already blocked');
    }
    final blocked = _BlockedSeek();
    _nextBlockedSeek = blocked;
    return blocked;
  }

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
  Future<void> play() async {
    playCount += 1;
    final next = _nextPlay;
    _nextPlay = null;
    if (next != null && !next.isCompleted) next.complete();
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
    final blocked = _nextBlockedSeek;
    _nextBlockedSeek = null;
    if (blocked == null) return;
    blocked.started.complete();
    await blocked.release.future;
    blocked.returned.complete();
  }

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> stop() async => stopCount += 1;
}

class _BlockedSeek {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  final Completer<void> returned = Completer<void>();
}

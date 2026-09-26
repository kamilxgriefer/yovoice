import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

/// Drag-to-seek on the Yeel timeline (ADR-211): the coordinator's scrub
/// session. Video trim 5 s → 15 s (a 10 s timeline); the backing track is
/// 6 s long and starts at 2 s, so its window is 4 s and it wraps.
void main() {
  late _Video video;
  late _Audio audio;
  late List<Duration> watched;

  ReelPlaybackCoordinator videoCoordinator({bool autoplay = true}) {
    watched = <Duration>[];
    final coordinator = ReelPlaybackCoordinator(
      reel: _videoReel(),
      resolveBackingAudioUri: () async => Uri(scheme: 'memory', path: 'a'),
      audioPlaybackFactory: () => audio,
      autoplay: autoplay,
      onVideoProgress: watched.add,
    );
    addTearDown(coordinator.dispose);
    return coordinator;
  }

  Future<ReelPlaybackCoordinator> playingVideo() async {
    final coordinator = videoCoordinator();
    await coordinator.attachVideo(video);
    await pumpEventQueue();
    expect(coordinator.isPlaying, isTrue);
    return coordinator;
  }

  setUp(() {
    video = _Video();
    audio = _Audio();
  });

  test('a drag holds a playing Yeel, previews, commits and resumes', () async {
    final coordinator = await playingVideo();
    expect(coordinator.canSeek, isTrue);

    final begun = coordinator.beginScrub();
    expect(coordinator.isScrubbing, isTrue);
    await begun;
    expect(video.playing, isFalse);
    expect(audio.pauseCount, greaterThan(0));
    expect(coordinator.isPlaying, isFalse);

    coordinator.scrubTo(const Duration(seconds: 6));
    expect(coordinator.position.value, const Duration(seconds: 6));
    await coordinator.endScrub();
    await pumpEventQueue();

    expect(coordinator.isScrubbing, isFalse);
    expect(video.seeks.last, const Duration(seconds: 11));
    // 2 s + (6 s mod the 4 s window).
    expect(audio.seeks.last, const Duration(seconds: 4));
    expect(coordinator.isPlaying, isTrue);
    expect(video.playing, isTrue);
  });

  test(
    'a scrub that starts paused stays paused, and is no hand-pause',
    () async {
      final coordinator = videoCoordinator(autoplay: false);
      await coordinator.attachVideo(video);
      expect(coordinator.isPlaying, isFalse);

      await coordinator.beginScrub();
      coordinator.scrubTo(const Duration(seconds: 3));
      await coordinator.endScrub();
      await pumpEventQueue();

      expect(coordinator.isPlaying, isFalse);
      expect(video.playing, isFalse);
      expect(video.seeks.last, const Duration(seconds: 8));
      expect(coordinator.position.value, const Duration(seconds: 3));
      // Play afterwards continues from the scrubbed frame, not the start.
      await coordinator.toggle();
      expect(video.seeks.last, const Duration(seconds: 8));
      expect(video.playing, isTrue);
    },
  );

  test(
    'a burst of targets keeps one native seek in flight, newest wins',
    () async {
      final coordinator = await playingVideo();
      await coordinator.beginScrub();
      final before = video.seeks.length;
      final gate = video.gateNextSeek();

      for (var i = 1; i <= 20; i++) {
        coordinator.scrubTo(Duration(milliseconds: i * 400));
      }
      await pumpEventQueue();
      expect(video.seeks.length - before, 1);
      gate.complete();
      await pumpEventQueue();

      final previews = video.seeks.sublist(before);
      expect(previews.length, lessThanOrEqualTo(2));
      expect(previews.last, const Duration(milliseconds: 5000 + 8000));
      expect(coordinator.position.value, const Duration(seconds: 8));
      await coordinator.endScrub();
    },
  );

  test('a release past the end stays short of the trim end', () async {
    final coordinator = await playingVideo();
    await coordinator.beginScrub();
    coordinator.scrubTo(const Duration(seconds: 30));
    expect(
      coordinator.position.value,
      const Duration(milliseconds: 10000 - 40),
    );
    await coordinator.endScrub();
    await pumpEventQueue();

    expect(video.seeks.last, const Duration(milliseconds: 14960));
    expect(video.playing, isTrue);
    // A tick at the committed position neither loops nor rewinds.
    final seeks = video.seeks.length;
    await coordinator.synchronizeVideoTick();
    await pumpEventQueue();
    expect(video.seeks.length, seeks);
  });

  test('engine ticks never pull the bar away from the finger', () async {
    final coordinator = await playingVideo();
    await coordinator.beginScrub();
    coordinator.scrubTo(const Duration(seconds: 7));
    await pumpEventQueue();

    video.position = const Duration(seconds: 6);
    await coordinator.synchronizeVideoTick();
    expect(coordinator.position.value, const Duration(seconds: 7));
    await coordinator.endScrub();
  });

  test('autoplay cannot start playback under the finger', () async {
    final coordinator = await playingVideo();
    await coordinator.beginScrub();
    await coordinator.autoplay();
    await pumpEventQueue();
    expect(coordinator.isPlaying, isFalse);
    expect(video.playing, isFalse);
    await coordinator.endScrub();
  });

  group('whatever interrupts the finger wins', () {
    test('deactivation', () async {
      final coordinator = await playingVideo();
      await coordinator.beginScrub();
      coordinator.scrubTo(const Duration(seconds: 4));
      await coordinator.setActive(false);
      expect(coordinator.isScrubbing, isFalse);
      await coordinator.endScrub();
      await pumpEventQueue();
      expect(video.playing, isFalse);
      expect(coordinator.position.value, Duration.zero);
    });

    test('a suspension', () async {
      final coordinator = await playingVideo();
      await coordinator.beginScrub();
      coordinator.scrubTo(const Duration(seconds: 4));
      await coordinator.setAutoplaySuspended(true);
      expect(coordinator.isScrubbing, isFalse);
      await coordinator.endScrub();
      await pumpEventQueue();
      expect(video.playing, isFalse);
      expect(coordinator.isPlaying, isFalse);
    });

    test('a detached decoder', () async {
      final coordinator = await playingVideo();
      await coordinator.beginScrub();
      await coordinator.detachVideo(video);
      expect(coordinator.isScrubbing, isFalse);
      expect(coordinator.canSeek, isFalse);
      await coordinator.endScrub();
      await pumpEventQueue();
      expect(video.playing, isFalse);
    });

    test('disposal', () async {
      final coordinator = ReelPlaybackCoordinator(
        reel: _videoReel(),
        resolveBackingAudioUri: () async => Uri(scheme: 'memory', path: 'a'),
        audioPlaybackFactory: () => audio,
        autoplay: true,
      );
      await coordinator.attachVideo(video);
      await pumpEventQueue();
      await coordinator.beginScrub();
      final plays = video.playCount;
      coordinator.dispose();
      expect(coordinator.isScrubbing, isFalse);
      await coordinator.endScrub();
      await pumpEventQueue();
      expect(video.playCount, plays);
    });
  });

  test('a scrub and a seekBy produce no watch time', () async {
    final coordinator = await playingVideo();
    video.position = const Duration(milliseconds: 5500);
    await coordinator.synchronizeVideoTick();
    video.position = const Duration(milliseconds: 5900);
    await coordinator.synchronizeVideoTick();
    expect(watched, <Duration>[const Duration(milliseconds: 400)]);

    await coordinator.beginScrub();
    for (final ms in <int>[6200, 6600, 7000]) {
      coordinator.scrubTo(Duration(milliseconds: ms - 5000));
      await pumpEventQueue();
      await coordinator.synchronizeVideoTick();
    }
    await coordinator.endScrub();
    await pumpEventQueue();
    await coordinator.synchronizeVideoTick();
    await coordinator.seekBy(const Duration(seconds: 5));
    await pumpEventQueue();
    await coordinator.synchronizeVideoTick();
    expect(watched, <Duration>[const Duration(milliseconds: 400)]);
  });

  test('seekBy moves five seconds and keeps the play state', () async {
    final coordinator = await playingVideo();
    await coordinator.seekBy(const Duration(seconds: 5));
    await pumpEventQueue();
    expect(coordinator.position.value, const Duration(seconds: 5));
    expect(video.seeks.last, const Duration(seconds: 10));
    expect(coordinator.isPlaying, isTrue);

    await coordinator.toggle();
    await coordinator.seekBy(const Duration(seconds: -8));
    await pumpEventQueue();
    expect(coordinator.position.value, Duration.zero);
    expect(video.seeks.last, const Duration(seconds: 5));
    expect(coordinator.isPlaying, isFalse);
  });

  test('a finger back down before the commit keeps one hold', () async {
    final coordinator = await playingVideo();
    await coordinator.beginScrub();
    coordinator.scrubTo(const Duration(seconds: 2));
    final gate = video.gateNextSeek();
    final firstRelease = coordinator.endScrub();
    unawaited(coordinator.beginScrub());
    expect(coordinator.isScrubbing, isTrue);
    gate.complete();
    await firstRelease;
    expect(coordinator.isScrubbing, isTrue);
    coordinator.scrubTo(const Duration(seconds: 9));
    await coordinator.endScrub();
    await pumpEventQueue();
    expect(coordinator.isScrubbing, isFalse);
    expect(video.seeks.last, const Duration(seconds: 14));
    expect(coordinator.isPlaying, isTrue, reason: 'the original resume holds');
  });

  test('a failing seek leaves the Yeel paused and released', () async {
    final coordinator = await playingVideo();
    await coordinator.beginScrub();
    video.seekError = StateError('decoder gone');
    coordinator.scrubTo(const Duration(seconds: 3));
    await pumpEventQueue();
    // The preview failure is absorbed; the commit's is reported.
    video.seekError = StateError('decoder gone');
    await expectLater(coordinator.endScrub(), throwsStateError);
    expect(coordinator.isScrubbing, isFalse);
    expect(coordinator.isPlaying, isFalse);
    expect(video.playing, isFalse);
  });

  test('a photo Yeel scrubbed before its first play starts there', () async {
    final timers = <Duration>[];
    final coordinator = ReelPlaybackCoordinator(
      reel: _photoReel(),
      resolveBackingAudioUri: () async => Uri(scheme: 'memory', path: 'a'),
      audioPlaybackFactory: () => audio,
      timerFactory: (duration, callback) {
        timers.add(duration);
        return Timer(const Duration(days: 1), callback);
      },
    );
    addTearDown(coordinator.dispose);
    expect(coordinator.canSeek, isTrue);

    await coordinator.beginScrub();
    coordinator.scrubTo(const Duration(seconds: 6));
    await coordinator.endScrub();
    expect(coordinator.position.value, const Duration(seconds: 6));
    expect(coordinator.isPlaying, isFalse);

    await coordinator.toggle();
    // Loaded at the trim start (1 s), then moved to the scrubbed offset.
    expect(audio.seeks, <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 7),
    ]);
    expect(coordinator.isPlaying, isTrue);
    // 13 s track − 7 s = 6 s left, not the full 12 s timeline.
    expect(timers.last, const Duration(seconds: 6));
  });
}

Reel _videoReel() => Reel(
  id: 'scrub_video_reel',
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
  sortKey: '1788408000000_scrub_video_reel',
);

Reel _photoReel() => Reel(
  id: 'scrub_photo_reel',
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
    durationMs: 13000,
  ),
  composition: const ReelComposition(
    originalAudioVolume: 0,
    backingAudioVolume: 70,
    audioTrimStartMs: 1000,
    audioRightsAttested: true,
  ),
  publishedAt: DateTime.utc(2026, 9, 3),
  sortKey: '1788408000000_scrub_photo_reel',
);

class _Video implements ReelVideoPlayback {
  bool playing = false;
  @override
  Duration position = Duration.zero;
  int playCount = 0;
  final List<Duration> seeks = <Duration>[];
  Completer<void>? _gate;
  Object? seekError;

  Completer<void> gateNextSeek() => _gate = Completer<void>();

  @override
  bool get isPlaying => playing;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> play() async {
    playCount += 1;
    playing = true;
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    final gate = _gate;
    _gate = null;
    if (gate != null) await gate.future;
    final error = seekError;
    seekError = null;
    if (error != null) throw error;
    position = value;
  }

  @override
  Future<void> setVolume(double value) async {}
}

class _Audio implements ReelAudioPlayback {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );
  int pauseCount = 0;
  final List<Duration> seeks = <Duration>[];

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
  Future<void> load(Uri uri) async {}

  @override
  Future<void> pause() async => pauseCount += 1;

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double value) async {}

  @override
  Future<void> stop() async {}
}

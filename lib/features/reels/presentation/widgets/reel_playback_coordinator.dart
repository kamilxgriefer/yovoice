import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';

/// The small media surface needed by the Reel timeline.
///
/// The production implementation wraps [VideoPlayerController]. Keeping this
/// contract independent from the plugin makes the timing policy deterministic
/// to test without a platform decoder.
abstract interface class ReelVideoPlayback {
  bool get isPlaying;
  Duration get position;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
}

/// The backing-track surface used by the synchronized Reel timeline.
abstract interface class ReelAudioPlayback {
  Stream<Duration> get positionChanges;
  Stream<void> get completions;

  Future<void> load(Uri uri);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

typedef ReelAudioPlaybackFactory = ReelAudioPlayback Function();
typedef ReelPlaybackTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// One authoritative playback clock for a Reel's video and backing track.
///
/// Video position is the master clock. A backing track follows the selected
/// video trim, is corrected only after a bounded drift, and is reset together
/// with the video on every composition loop. Photo Reels use the selected
/// backing-audio interval as their finite timeline and never loop by surprise.
class ReelPlaybackCoordinator extends ChangeNotifier {
  ReelPlaybackCoordinator({
    required this.reel,
    required Future<Uri> Function() resolveBackingAudioUri,
    ReelAudioPlaybackFactory? audioPlaybackFactory,
    DateTime Function()? now,
    ReelPlaybackTimerFactory? timerFactory,
    this.driftTolerance = const Duration(milliseconds: 180),
    this.driftCorrectionInterval = const Duration(milliseconds: 750),
  }) : _resolveBackingAudioUri = resolveBackingAudioUri,
       _audioPlaybackFactory =
           audioPlaybackFactory ?? _AudioplayersReelAudioPlayback.new,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  final Reel reel;
  final Future<Uri> Function() _resolveBackingAudioUri;
  final ReelAudioPlaybackFactory _audioPlaybackFactory;
  final DateTime Function() _now;
  final ReelPlaybackTimerFactory _timerFactory;
  final Duration driftTolerance;
  final Duration driftCorrectionInterval;

  ReelVideoPlayback? _video;
  ReelAudioPlayback? _audio;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<void>? _audioCompletionSubscription;
  Duration _audioPosition = Duration.zero;
  Future<void> _operations = Future<void>.value();
  Timer? _photoEndTimer;
  DateTime? _lastDriftCorrection;
  bool _audioLoaded = false;
  bool _active = true;
  bool _desiredPlaying = false;
  bool _playing = false;
  bool _loading = false;
  bool _loopQueued = false;
  bool _photoFinishQueued = false;
  bool _disposed = false;
  int _epoch = 0;
  int _commandVersion = 0;

  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  bool get isActive => _active;
  bool get _hasPlayableBackingAudio {
    final audio = reel.backingAudio;
    return audio != null &&
        reel.composition.audioTrimStartMs < audio.durationMs;
  }

  bool get canToggle {
    if (!_active) return false;
    if (reel.media.kind == ReelMediaKind.video) return _video != null;
    return _hasPlayableBackingAudio;
  }

  Duration get timelineDuration {
    if (reel.media.kind == ReelMediaKind.video) {
      return Duration(
        milliseconds: math.max(
          0,
          reel.composition.trimEndMs - reel.composition.trimStartMs,
        ),
      );
    }
    final audio = reel.backingAudio;
    if (audio == null) return Duration.zero;
    return Duration(
      milliseconds: math.max(
        0,
        audio.durationMs - reel.composition.audioTrimStartMs,
      ),
    );
  }

  Duration get _videoStart =>
      Duration(milliseconds: reel.composition.trimStartMs);
  Duration get _videoEnd => Duration(milliseconds: reel.composition.trimEndMs);
  Duration get _audioStart =>
      Duration(milliseconds: reel.composition.audioTrimStartMs);
  Duration get _audioEnd => Duration(
    milliseconds:
        reel.backingAudio?.durationMs ?? reel.composition.audioTrimStartMs,
  );

  Future<void> attachVideo(ReelVideoPlayback video) {
    final previous = _video;
    _video = video;
    _notify();
    return _enqueue(() async {
      if (previous != null && !identical(previous, video)) {
        await previous.pause();
      }
      await video.setVolume(reel.composition.originalAudioVolume / 100);
      final position = video.position;
      if (position < _videoStart || position >= _videoEnd) {
        await video.seek(_videoStart);
      }
    });
  }

  void detachVideo(ReelVideoPlayback video) {
    if (!identical(_video, video)) return;
    _video = null;
    _commandVersion += 1;
    _desiredPlaying = false;
    _setPlaying(false);
    _cancelPhotoEndTimer();
    unawaited(
      _enqueue(() async {
        await video.pause();
        if (_audioLoaded) await _audio?.pause();
      }).catchError((Object _) {}),
    );
    _notify();
  }

  /// Activating a neighbouring page never resumes it implicitly. Deactivation
  /// is immediate so a slow media grant cannot start sound after a swipe.
  Future<void> setActive(bool active) {
    if (_active == active) return Future<void>.value();
    _active = active;
    if (!active) {
      _commandVersion += 1;
      _desiredPlaying = false;
      _setPlaying(false);
      _cancelPhotoEndTimer();
    }
    _notify();
    if (active) return Future<void>.value();
    return _enqueue(() => _pauseEngines(reset: true));
  }

  Future<void> toggle() {
    if (!_active || !canToggle) return Future<void>.value();
    final shouldPlay = !_desiredPlaying;
    final command = ++_commandVersion;
    _desiredPlaying = shouldPlay;
    return _enqueue(() async {
      if (command != _commandVersion) return;
      if (shouldPlay) {
        await _playNow(command);
      } else {
        await _pauseNow();
      }
    });
  }

  Future<void> pause({bool reset = false}) {
    final command = ++_commandVersion;
    _desiredPlaying = false;
    return _enqueue(() async {
      if (command != _commandVersion) return;
      await _pauseNow(reset: reset);
    });
  }

  /// Called by the video driver's listener. It enforces the trim boundary and
  /// performs no more than one backing-track correction per correction window.
  Future<void> synchronizeVideoTick() async {
    final video = _video;
    if (_disposed || !_active || video == null) return;
    if (_playing && video.position >= _videoEnd) {
      if (_loopQueued) return;
      _loopQueued = true;
      try {
        await _enqueue(_loopVideo);
      } finally {
        _loopQueued = false;
      }
      return;
    }
    final audio = _audio;
    if (!_playing || audio == null || !_audioLoaded || !video.isPlaying) {
      return;
    }
    final now = _now();
    final previous = _lastDriftCorrection;
    if (previous != null &&
        now.difference(previous) < driftCorrectionInterval) {
      return;
    }
    final expected = _expectedAudioPosition(video.position);
    final drift = (expected - _audioPosition).abs();
    if (drift <= driftTolerance) return;
    _lastDriftCorrection = now;
    await _enqueue(() async {
      if (!_playing || !_active || !identical(video, _video)) return;
      await audio.seek(expected);
      _audioPosition = expected;
    });
  }

  Future<void> _playNow(int command) async {
    if (!_active || !canToggle || _loading || !_desiredPlaying) return;
    _setLoading(true);
    try {
      final video = _video;
      if (reel.media.kind == ReelMediaKind.video && video == null) return;

      if (video != null) {
        await video.setVolume(reel.composition.originalAudioVolume / 100);
        if (video.position < _videoStart || video.position >= _videoEnd) {
          await video.seek(_videoStart);
        }
      }

      final audio = await _ensureAudio();
      if (!_active ||
          !_desiredPlaying ||
          _disposed ||
          command != _commandVersion) {
        await _pauseEngines(reset: true);
        return;
      }
      if (audio != null) {
        await audio.setVolume(reel.composition.backingAudioVolume / 100);
        final expected = video == null
            ? _validPhotoAudioPosition(_audioPosition)
            : _expectedAudioPosition(video.position);
        if ((_audioPosition - expected).abs() >
            const Duration(milliseconds: 20)) {
          await audio.seek(expected);
          _audioPosition = expected;
        }
      }

      await Future.wait<void>(<Future<void>>[
        if (video != null) video.play(),
        if (audio != null) audio.play(),
      ]);
      if (!_active ||
          !_desiredPlaying ||
          _disposed ||
          command != _commandVersion) {
        await _pauseEngines(reset: true);
        return;
      }
      _setPlaying(true);
      _schedulePhotoEnd();
    } catch (_) {
      if (command == _commandVersion) _desiredPlaying = false;
      _setPlaying(false);
      await _pauseEngines();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _pauseNow({bool reset = false}) async {
    _desiredPlaying = false;
    _cancelPhotoEndTimer();
    await _pauseEngines(reset: reset);
    _setPlaying(false);
  }

  Future<void> _pauseEngines({bool reset = false}) async {
    final video = _video;
    final audio = _audio;
    await Future.wait<void>(<Future<void>>[
      if (video != null) video.pause(),
      if (audio != null && _audioLoaded) audio.pause(),
    ]);
    if (!reset) return;
    await Future.wait<void>(<Future<void>>[
      if (video != null) video.seek(_videoStart),
      if (audio != null && _audioLoaded) audio.seek(_audioStart),
    ]);
    _audioPosition = _audioStart;
  }

  Future<void> _loopVideo() async {
    final video = _video;
    if (video == null || !_playing || !_active) return;
    final audio = _audio;
    await Future.wait<void>(<Future<void>>[
      video.pause(),
      if (audio != null) audio.pause(),
    ]);
    await Future.wait<void>(<Future<void>>[
      video.seek(_videoStart),
      if (audio != null) audio.seek(_audioStart),
    ]);
    _audioPosition = _audioStart;
    _lastDriftCorrection = null;
    if (!_active || !_desiredPlaying || _disposed) {
      _setPlaying(false);
      return;
    }
    await Future.wait<void>(<Future<void>>[
      video.play(),
      if (audio != null) audio.play(),
    ]);
  }

  Future<ReelAudioPlayback?> _ensureAudio() async {
    if (!_hasPlayableBackingAudio) return null;
    final existing = _audio;
    if (existing != null && _audioLoaded) return existing;
    final audio = existing ?? _audioPlaybackFactory();
    if (existing == null) {
      _audio = audio;
      _audioPositionSubscription = audio.positionChanges.listen(
        _onAudioPosition,
      );
      _audioCompletionSubscription = audio.completions.listen((_) {
        unawaited(_enqueue(_handleAudioCompletion).catchError((Object _) {}));
      });
    }
    final uri = await _resolveBackingAudioUri();
    if (_disposed) return audio;
    await audio.load(uri);
    await audio.setVolume(reel.composition.backingAudioVolume / 100);
    await audio.seek(_audioStart);
    _audioPosition = _audioStart;
    _audioLoaded = true;
    return audio;
  }

  void _onAudioPosition(Duration position) {
    if (_disposed) return;
    _audioPosition = position;
    if (reel.media.kind == ReelMediaKind.image &&
        _playing &&
        position >= _audioEnd) {
      unawaited(_finishPhoto().catchError((Object _) {}));
    }
  }

  Future<void> _handleAudioCompletion() async {
    if (_disposed || !_playing) return;
    if (reel.media.kind == ReelMediaKind.image) {
      _commandVersion += 1;
      _desiredPlaying = false;
      _setPlaying(false);
      _cancelPhotoEndTimer();
      await _finishPhotoNow();
      return;
    }
    final video = _video;
    final audio = _audio;
    if (video == null || audio == null || !_active || !_desiredPlaying) return;
    final expected = _expectedAudioPosition(video.position);
    await audio.seek(expected);
    _audioPosition = expected;
    if (_disposed || !_active || !_desiredPlaying || !_playing) return;
    await audio.play();
  }

  Future<void> _finishPhoto() {
    if (_photoFinishQueued || _disposed) return Future<void>.value();
    _photoFinishQueued = true;
    _commandVersion += 1;
    _desiredPlaying = false;
    _setPlaying(false);
    _cancelPhotoEndTimer();
    return _enqueue(_finishPhotoNow).whenComplete(() {
      _photoFinishQueued = false;
    });
  }

  Future<void> _finishPhotoNow() async {
    final audio = _audio;
    if (audio != null && _audioLoaded) {
      await audio.pause();
      await audio.seek(_audioStart);
    }
    _audioPosition = _audioStart;
    _setPlaying(false);
  }

  void _schedulePhotoEnd() {
    _cancelPhotoEndTimer();
    if (reel.media.kind != ReelMediaKind.image || !_playing) return;
    final remaining = _audioEnd - _validPhotoAudioPosition(_audioPosition);
    if (remaining <= Duration.zero) {
      unawaited(_finishPhoto().catchError((Object _) {}));
      return;
    }
    _photoEndTimer = _timerFactory(remaining, () {
      unawaited(_finishPhoto().catchError((Object _) {}));
    });
  }

  Duration _validPhotoAudioPosition(Duration position) {
    if (position < _audioStart || position >= _audioEnd) return _audioStart;
    return position;
  }

  Duration _expectedAudioPosition(Duration videoPosition) {
    final audioWindow = _audioEnd - _audioStart;
    if (audioWindow <= Duration.zero) return _audioStart;
    final rawOffset = math.max(
      0,
      videoPosition.inMilliseconds - _videoStart.inMilliseconds,
    );
    final offset = rawOffset % audioWindow.inMilliseconds;
    return _audioStart + Duration(milliseconds: offset);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final epoch = _epoch;
    final next = _operations.then((_) async {
      if (_disposed || epoch != _epoch) return;
      await operation();
    });
    _operations = next.catchError((Object _) {});
    return next;
  }

  void _setPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    _notify();
  }

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    _notify();
  }

  void _cancelPhotoEndTimer() {
    _photoEndTimer?.cancel();
    _photoEndTimer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _desiredPlaying = false;
    _playing = false;
    _epoch += 1;
    _commandVersion += 1;
    _cancelPhotoEndTimer();
    unawaited(_audioPositionSubscription?.cancel());
    unawaited(_audioCompletionSubscription?.cancel());
    final audio = _audio;
    _audio = null;
    if (audio != null) {
      unawaited(_stopAndDisposeAudio(audio));
    }
    super.dispose();
  }

  Future<void> _stopAndDisposeAudio(ReelAudioPlayback audio) async {
    try {
      await audio.stop();
    } catch (_) {
      // Disposal must still release the native player after a failed stop.
    }
    try {
      await audio.dispose();
    } catch (_) {
      // The coordinator is already disposed; there is no UI error surface.
    }
  }
}

class _AudioplayersReelAudioPlayback implements ReelAudioPlayback {
  _AudioplayersReelAudioPlayback() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Stream<Duration> get positionChanges => _player.onPositionChanged;

  @override
  Future<void> load(Uri uri) async {
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setSource(UrlSource(uri.toString()));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

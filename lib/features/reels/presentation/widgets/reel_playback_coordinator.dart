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

/// Supplies the video engine for one resolved Reel media URL.
///
/// The feed leaves this null and the card builds a real
/// [VideoPlayerController]. A host that already owns a decoder — and the
/// deterministic coverage of the autoplay policy, which must not spin up a
/// platform decoder — supplies its own, exactly as [ReelAudioPlaybackFactory]
/// does for the backing track.
typedef ReelVideoPlaybackFactory =
    ReelVideoPlayback Function(Uri uri, Reel reel);
typedef ReelPlaybackTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// One authoritative playback clock for a Reel's video and backing track.
///
/// Video position is the master clock. A backing track follows the selected
/// video trim, is corrected only after a bounded drift, and is reset together
/// with the video on every composition loop. Photo Reels use the selected
/// backing-audio interval as their finite timeline and never loop by surprise.
///
/// Autoplay is opt-in and video-only. See [autoplay] for the exact policy and
/// the reasons a Reel refuses to start itself.
class ReelPlaybackCoordinator extends ChangeNotifier {
  ReelPlaybackCoordinator({
    required Reel reel,
    required Future<Uri> Function() resolveBackingAudioUri,
    ReelAudioPlaybackFactory? audioPlaybackFactory,
    DateTime Function()? now,
    ReelPlaybackTimerFactory? timerFactory,
    bool autoplay = false,
    bool muted = false,
    this.onVideoProgress,
    this.driftTolerance = const Duration(milliseconds: 180),
    this.driftCorrectionInterval = const Duration(milliseconds: 750),
  }) : reel = reel,
       _mediaKind = reel.media.kind,
       _composition = reel.composition,
       _backingAudioDurationMs = reel.backingAudio?.durationMs,
       _resolveBackingAudioUri = resolveBackingAudioUri,
       _audioPlaybackFactory =
           audioPlaybackFactory ?? _AudioplayersReelAudioPlayback.new,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       _autoplayEnabled = autoplay,
       _muted = muted;

  /// Local drafts reuse the exact timeline without inventing server IDs,
  /// author identities, grants or published content.
  ReelPlaybackCoordinator.draft({
    required ReelMediaKind mediaKind,
    required ReelComposition composition,
    required int? backingAudioDurationMs,
    required Future<Uri> Function() resolveBackingAudioUri,
    required ReelAudioPlaybackFactory audioPlaybackFactory,
    DateTime Function()? now,
    ReelPlaybackTimerFactory? timerFactory,
    this.driftTolerance = const Duration(milliseconds: 180),
    this.driftCorrectionInterval = const Duration(milliseconds: 750),
  }) : reel = null,
       onVideoProgress = null,
       _mediaKind = mediaKind,
       _composition = composition,
       _backingAudioDurationMs = backingAudioDurationMs,
       _resolveBackingAudioUri = resolveBackingAudioUri,
       _audioPlaybackFactory = audioPlaybackFactory,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       // A composer preview belongs to the person editing it: it starts when
       // they ask for it and never on its own.
       _autoplayEnabled = false,
       _muted = false;

  final Reel? reel;
  final ValueChanged<Duration>? onVideoProgress;
  Duration? _lastViewedPosition;
  final ReelMediaKind _mediaKind;
  final ReelComposition _composition;
  final int? _backingAudioDurationMs;
  final Future<Uri> Function() _resolveBackingAudioUri;
  final ReelAudioPlaybackFactory _audioPlaybackFactory;
  final DateTime Function() _now;
  final ReelPlaybackTimerFactory _timerFactory;
  final bool _autoplayEnabled;
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
  bool _muted;

  /// Set only by [toggle] turning playback off — a deliberate hand-pause.
  /// Autoplay stands down for as long as this Reel stays the active page, and
  /// the flag is cleared when the viewer scrolls away from it.
  bool _viewerPaused = false;

  /// Set by the host while something outside the timeline stands in front of
  /// this Reel: an open thread, a sheet or a pushed route above the feed, or
  /// the app in the background.
  bool _autoplaySuspended = false;
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

  /// Whether this Reel is allowed to start itself. False for photo Reels and
  /// for every composer preview.
  bool get autoplayEnabled =>
      _autoplayEnabled && _mediaKind == ReelMediaKind.video;

  /// True while both engines are held at zero. Mute is a viewing preference,
  /// not a property of the Reel: the composition's own mix is restored the
  /// moment the viewer turns sound on.
  bool get isMuted => _effectiveMuted;

  /// A photo Reel's backing track *is* its content, so muting one would leave
  /// nothing at all. Mute is therefore a video-only state.
  bool get _effectiveMuted => _muted && _mediaKind == ReelMediaKind.video;

  double get _videoVolume =>
      _effectiveMuted ? 0 : _composition.originalAudioVolume / 100;
  double get _backingAudioVolume =>
      _effectiveMuted ? 0 : _composition.backingAudioVolume / 100;

  bool get _hasPlayableBackingAudio {
    final duration = _backingAudioDurationMs;
    return duration != null && _composition.audioTrimStartMs < duration;
  }

  bool get canToggle {
    if (!_active) return false;
    if (_mediaKind == ReelMediaKind.video) return _video != null;
    return _hasPlayableBackingAudio;
  }

  Duration get timelineDuration {
    if (_mediaKind == ReelMediaKind.video) {
      return Duration(
        milliseconds: math.max(
          0,
          _composition.trimEndMs - _composition.trimStartMs,
        ),
      );
    }
    final duration = _backingAudioDurationMs;
    if (duration == null) return Duration.zero;
    return Duration(
      milliseconds: math.max(0, duration - _composition.audioTrimStartMs),
    );
  }

  Duration get _videoStart => Duration(milliseconds: _composition.trimStartMs);
  Duration get _videoEnd => Duration(milliseconds: _composition.trimEndMs);
  Duration get _audioStart =>
      Duration(milliseconds: _composition.audioTrimStartMs);
  Duration get _audioEnd => Duration(
    milliseconds: _backingAudioDurationMs ?? _composition.audioTrimStartMs,
  );

  /// The decoder is ready. This is the earliest moment a video Reel can play,
  /// so it is also where autoplay is armed — [canToggle] needs a player, which
  /// is why arming on [setActive] alone would miss the very first card.
  Future<void> attachVideo(ReelVideoPlayback video) async {
    final previous = _video;
    _video = video;
    try {
      // The player is recorded synchronously so canToggle is true at once, but
      // listeners are told only after the first await: a host may attach from
      // initState, and notifying there would rebuild during a build.
      await _enqueue(() async {
        if (previous != null && !identical(previous, video)) {
          await previous.pause();
        }
        await video.setVolume(_videoVolume);
        final position = video.position;
        if (position < _videoStart || position >= _videoEnd) {
          await video.seek(_videoStart);
        }
      });
    } finally {
      _notify();
    }
    await autoplay();
  }

  void detachVideo(ReelVideoPlayback video) {
    if (!identical(_video, video)) return;
    _video = null;
    _commandVersion += 1;
    _desiredPlaying = false;
    _setPlaying(false);
    _cancelPhotoEndTimer();
    // Straight to the player, not through the queue: a page being scrolled
    // away is detached and then disposed in the same frame, and a queued
    // command is dropped by disposal. Nothing else can reach this player any
    // more — every queued operation reads _video when it runs, and it is
    // already null.
    unawaited(video.pause().catchError((Object _) {}));
    unawaited(
      _enqueue(() async {
        if (_audioLoaded) await _audio?.pause();
      }).catchError((Object _) {}),
    );
    _notify();
  }

  /// Becoming the active page starts an autoplaying Reel and nothing else: a
  /// coordinator with autoplay off still never resumes implicitly, and a
  /// suspended one waits for whatever is in front of it to go away.
  /// Deactivation is immediate so a slow media grant cannot start sound after
  /// a swipe.
  Future<void> setActive(bool active) {
    if (_active == active) return Future<void>.value();
    _active = active;
    if (!active) {
      _commandVersion += 1;
      _desiredPlaying = false;
      // The hand-pause belonged to that visit. Scrolling back to this Reel
      // later starts it again, the same as reaching it for the first time.
      _viewerPaused = false;
      _setPlaying(false);
      _cancelPhotoEndTimer();
    }
    _notify();
    if (active) return autoplay();
    return _enqueue(() => _pauseEngines(reset: true));
  }

  /// Starts this Reel without a tap.
  ///
  /// Safe to call from anywhere that could make autoplay newly possible — it
  /// refuses unless every one of these holds: autoplay is enabled for this
  /// coordinator, the media is video, this is the active page, nothing is
  /// suspending playback, the viewer has not paused it by hand, and there is
  /// a player to drive. Only one coordinator in a feed is ever active, so the
  /// single-player invariant is unchanged.
  Future<void> autoplay() {
    final blocked =
        !autoplayEnabled ||
        _disposed ||
        !_active ||
        _autoplaySuspended ||
        _viewerPaused ||
        _desiredPlaying ||
        !canToggle;
    if (blocked) return Future<void>.value();
    final command = ++_commandVersion;
    _desiredPlaying = true;
    return _enqueue(() async {
      if (command != _commandVersion) return;
      await _playNow(command);
    });
  }

  /// Holds autoplay off while something outside the timeline stands in front
  /// of this Reel — an open thread, a sheet or a pushed route, or the app in
  /// the background. Suspending always pauses, whether or not this Reel
  /// autoplays, so a hand-started photo Reel stops too. Releasing restarts
  /// only what autoplay would have started on its own.
  Future<void> setAutoplaySuspended(bool suspended) {
    if (_autoplaySuspended == suspended) return Future<void>.value();
    _autoplaySuspended = suspended;
    if (!suspended) return autoplay();
    return pause();
  }

  /// Applies the viewer's sound preference to both engines live, without
  /// interrupting playback.
  Future<void> setMuted(bool muted) {
    if (_muted == muted) return Future<void>.value();
    _muted = muted;
    _notify();
    return _enqueue(() async {
      if (_disposed) return;
      final video = _video;
      if (video != null) await video.setVolume(_videoVolume);
      final audio = _audio;
      if (audio != null && _audioLoaded) {
        await audio.setVolume(_backingAudioVolume);
      }
    });
  }

  Future<void> toggle() {
    if (!_active || !canToggle) return Future<void>.value();
    final shouldPlay = !_desiredPlaying;
    final command = ++_commandVersion;
    _desiredPlaying = shouldPlay;
    // A hand-pause outranks autoplay: it must not be undone by the next
    // attach, tick or suspension release on this same page.
    _viewerPaused = !shouldPlay;
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
    final position = _playing && !_autoplaySuspended && video.isPlaying
        ? video.position
        : null;
    final previousPosition = _lastViewedPosition;
    _lastViewedPosition = position;
    if (position != null && previousPosition != null) {
      final delta = position - previousPosition;
      // Readiness, buffering and a seek do not constitute an eligible watch.
      if (delta > Duration.zero && delta <= const Duration(seconds: 1)) {
        onVideoProgress?.call(delta);
      }
    }
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
      if (_mediaKind == ReelMediaKind.video && video == null) return;

      if (video != null) {
        await video.setVolume(_videoVolume);
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
        await audio.setVolume(_backingAudioVolume);
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
    await audio.setVolume(_backingAudioVolume);
    await audio.seek(_audioStart);
    _audioPosition = _audioStart;
    _audioLoaded = true;
    return audio;
  }

  void _onAudioPosition(Duration position) {
    if (_disposed) return;
    _audioPosition = position;
    if (_mediaKind == ReelMediaKind.image &&
        _playing &&
        position >= _audioEnd) {
      unawaited(_finishPhoto().catchError((Object _) {}));
    }
  }

  Future<void> _handleAudioCompletion() async {
    if (_disposed || !_playing) return;
    if (_mediaKind == ReelMediaKind.image) {
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
    if (_mediaKind != ReelMediaKind.image || !_playing) return;
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
    if (!value) _lastViewedPosition = null;
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

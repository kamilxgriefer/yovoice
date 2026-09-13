import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../preferences/app_preferences.dart';
import 'call_tone.dart';

abstract interface class CallTonePlayer {
  /// Starts looping until [stop] is requested.
  ///
  /// Implementations must make a concurrent [stop] authoritative even when a
  /// platform start command is still pending.
  Future<void> startLoop(String assetPath, {required double volume});
  Future<void> stop();
  Future<void> dispose();
}

/// Narrow seam around [AudioPlayer], so loop configuration and cancellation
/// races can be verified without a platform audio engine.
abstract interface class CallTonePlaybackEngine {
  Future<void> configureAndroidCallToneContext();
  Future<void> setLooping();
  Future<void> playAsset(String assetPath, {required double volume});
  Future<void> stopAndRelease();
  Future<void> dispose();
}

class _AudioplayersCallToneEngine implements CallTonePlaybackEngine {
  _AudioplayersCallToneEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> configureAndroidCallToneContext() => _player.setAudioContext(
    AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationCommunicationRequest,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
    ),
  );

  @override
  Future<void> setLooping() => _player.setReleaseMode(ReleaseMode.loop);

  @override
  Future<void> playAsset(String assetPath, {required double volume}) =>
      _player.play(AssetSource(assetPath), volume: volume);

  @override
  Future<void> stopAndRelease() => _player.release();

  @override
  Future<void> dispose() => _player.dispose();
}

class AudioplayersCallTonePlayer implements CallTonePlayer {
  AudioplayersCallTonePlayer({CallTonePlaybackEngine? engine})
    : _engine = engine ?? _AudioplayersCallToneEngine();

  final CallTonePlaybackEngine _engine;
  bool _stopRequested = false;
  bool _disposed = false;
  Future<void>? _startFuture;
  Future<void>? _stopFuture;
  Future<void>? _disposeFuture;

  @override
  Future<void> startLoop(String assetPath, {required double volume}) =>
      _startFuture ??= _start(assetPath, volume: volume);

  Future<void> _start(String assetPath, {required double volume}) async {
    if (_stopRequested || _disposed) return;

    // AVAudioSession is process-global and remains under LiveKit/recording
    // control on iOS. Android needs a finite communication-request focus while
    // the call is ringing; releasing the player gives that focus back before
    // the real call session starts.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _engine.configureAndroidCallToneContext();
    }
    if (_stopRequested || _disposed) return;

    await _engine.setLooping();
    if (_stopRequested || _disposed) return;

    await _engine.playAsset(assetPath, volume: volume);
    if (_stopRequested || _disposed) {
      // stop() may have completed while a slow platform start was still in
      // flight. A second release closes that late completion deterministically.
      await _engine.stopAndRelease();
    }
  }

  @override
  Future<void> stop() {
    _stopRequested = true;
    return _stopFuture ??= _engine.stopAndRelease();
  }

  @override
  Future<void> dispose() {
    _stopRequested = true;
    _disposed = true;
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    // Start the graceful release, but never make disposal depend on that same
    // platform Future settling. A wedged release is exactly when the stronger
    // player disposal must still be attempted.
    unawaited(stop().catchError((Object _) {}));
    await _engine.dispose();
  }
}

/// Creates a fresh, single-use player for every new tone command.
typedef CallTonePlayerFactory = CallTonePlayer Function();

enum CallToneStartResult { started, disabled, failed, superseded }

/// Owns the single audible ringing loop used by private calls.
///
/// Every command invalidates older work synchronously. A stop therefore wins
/// even when the platform is still opening an asset, requesting audio focus or
/// returning from a plugin call. Superseded players are released separately so
/// a slow teardown cannot be reused by the next call.
class CallToneService {
  CallToneService({
    bool Function()? enabled,
    CallTonePlayerFactory? playerFactory,
    Duration startTimeout = const Duration(seconds: 2),
    Duration stopTimeout = const Duration(milliseconds: 600),
    Duration disposeTimeout = const Duration(seconds: 1),
  }) : assert(startTimeout > Duration.zero),
       assert(stopTimeout > Duration.zero),
       assert(disposeTimeout > Duration.zero),
       _enabled =
           enabled ??
           (() => AppPreferencesController.instance.value.soundEffectsEnabled),
       _playerFactory = playerFactory ?? AudioplayersCallTonePlayer.new,
       _startTimeout = startTimeout,
       _stopTimeout = stopTimeout,
       _disposeTimeout = disposeTimeout;

  static final instance = CallToneService();

  final bool Function() _enabled;
  final CallTonePlayerFactory _playerFactory;
  final Duration _startTimeout;
  final Duration _stopTimeout;
  final Duration _disposeTimeout;
  final Set<CallTonePlayer> _players = <CallTonePlayer>{};
  final Expando<Future<bool>> _playerStops = Expando<Future<bool>>();
  final Expando<Future<void>> _playerDisposals = Expando<Future<void>>();

  int _generation = 0;
  bool _disposed = false;
  CallTone? _desiredTone;
  CallTone? _activeTone;
  CallTonePlayer? _currentPlayer;
  Future<CallToneStartResult>? _currentStart;
  Future<void>? _disposeFuture;
  Future<bool> _retirementBarrier = Future<bool>.value(true);
  bool _playbackQuarantined = false;

  CallTone? get activeTone => _activeTone;
  bool get isPlaying => _activeTone != null;

  /// True while a player is starting or active and may still own audio focus.
  bool get mayHoldAudioFocus =>
      _desiredTone != null || _activeTone != null || _currentPlayer != null;

  Future<bool> start(CallTone tone) async =>
      await startWithResult(tone) == CallToneStartResult.started;

  Future<CallToneStartResult> startWithResult(CallTone tone) {
    if (_disposed) {
      return Future<CallToneStartResult>.value(CallToneStartResult.superseded);
    }
    if (_playbackQuarantined) {
      return Future<CallToneStartResult>.value(CallToneStartResult.failed);
    }
    bool enabled;
    try {
      enabled = _enabled();
    } catch (error) {
      unawaited(stop());
      debugPrint(
        'CallToneService: sound preference could not be read '
        '(${error.runtimeType}).',
      );
      return Future<CallToneStartResult>.value(CallToneStartResult.failed);
    }
    if (!enabled) {
      unawaited(stop());
      return Future<CallToneStartResult>.value(CallToneStartResult.disabled);
    }
    if (_desiredTone == tone && _currentStart != null) {
      return _currentStart!;
    }

    final generation = ++_generation;
    _desiredTone = tone;
    _activeTone = null;
    final previous = _currentPlayer;
    late final CallTonePlayer player;
    try {
      player = _playerFactory();
      if (_players.contains(player)) {
        throw StateError('CallTonePlayerFactory reused a single-use player.');
      }
    } catch (error) {
      final stopping = stop();
      debugPrint(
        'CallToneService: ${tone.name} player could not be created '
        '(${error.runtimeType}).',
      );
      return stopping.then((_) => CallToneStartResult.failed);
    }
    _currentPlayer = player;
    _players.add(player);

    final safeToStart = previous == null
        ? _retirementBarrier
        : _appendRetirement(<CallTonePlayer>[previous]);

    final start = _startPlayer(
      tone: tone,
      player: player,
      generation: generation,
      safeToStart: safeToStart,
    );
    _currentStart = start;
    return start;
  }

  Future<CallToneStartResult> _startPlayer({
    required CallTone tone,
    required CallTonePlayer player,
    required int generation,
    required Future<bool> safeToStart,
  }) async {
    final retiredSafely = await safeToStart;
    if (!_isCurrent(generation, tone, player)) {
      unawaited(_disposePlayer(player));
      return CallToneStartResult.superseded;
    }
    if (!retiredSafely) {
      _desiredTone = null;
      _currentPlayer = null;
      _currentStart = null;
      unawaited(_disposePlayer(player));
      return CallToneStartResult.failed;
    }

    try {
      await player
          .startLoop(tone.assetPath, volume: tone.volume)
          .timeout(_startTimeout);
    } catch (error) {
      final superseded = !_isCurrent(generation, tone, player);
      if (!superseded) {
        _desiredTone = null;
        _currentPlayer = null;
        _currentStart = null;
      }
      await _stopPlayer(player);
      unawaited(_disposePlayer(player));
      if (!superseded) {
        debugPrint(
          'CallToneService: ${tone.name} could not start '
          '(${error.runtimeType}).',
        );
      }
      return superseded
          ? CallToneStartResult.superseded
          : CallToneStartResult.failed;
    }

    if (!_isCurrent(generation, tone, player)) {
      await _stopPlayer(player);
      unawaited(_disposePlayer(player));
      return CallToneStartResult.superseded;
    }
    _activeTone = tone;
    return CallToneStartResult.started;
  }

  bool _isCurrent(int generation, CallTone tone, CallTonePlayer player) =>
      !_disposed &&
      _generation == generation &&
      _desiredTone == tone &&
      identical(_currentPlayer, player);

  Future<void> stop() async {
    ++_generation;
    _desiredTone = null;
    _activeTone = null;
    _currentPlayer = null;
    _currentStart = null;
    final players = _players.toList(growable: false);
    await _appendRetirement(players);
  }

  Future<bool> _stopPlayer(CallTonePlayer player) => _playerStops[player] ??=
      _runBounded(player.stop, timeout: _stopTimeout, label: 'stop');

  Future<bool> _appendRetirement(Iterable<CallTonePlayer> players) {
    final retiring = players.toSet();
    if (retiring.isEmpty) return _retirementBarrier;
    final previousBarrier = _retirementBarrier;
    final stopResults = Future.wait(retiring.map(_stopPlayer));
    for (final player in retiring) {
      unawaited(_disposePlayer(player));
    }
    final barrier = () async {
      final previousSafe = await previousBarrier;
      final currentResults = await stopResults;
      final currentSafe = currentResults.every((stopped) => stopped);
      final safe = previousSafe && currentSafe;
      if (!safe) _playbackQuarantined = true;
      return safe;
    }();
    _retirementBarrier = barrier;
    return barrier;
  }

  Future<void> _disposePlayer(CallTonePlayer player) =>
      _playerDisposals[player] ??= () async {
        await _stopPlayer(player);
        await _runBounded(
          player.dispose,
          timeout: _disposeTimeout,
          label: 'dispose',
        );
        _players.remove(player);
      }();

  Future<bool> _runBounded(
    Future<void> Function() action, {
    required Duration timeout,
    required String label,
  }) async {
    try {
      await action().timeout(timeout);
      return true;
    } catch (error) {
      // Call control remains authoritative even when the optional sound engine
      // fails. The generation guard prevents a late completion becoming active.
      debugPrint('CallToneService: $label failed (${error.runtimeType}).');
      return false;
    }
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    ++_generation;
    _desiredTone = null;
    _activeTone = null;
    _currentPlayer = null;
    _currentStart = null;
    final players = _players.toList(growable: false);
    await Future.wait(players.map(_disposePlayer));
  }
}

/// Tests replace this to keep widget suites independent of platform audio.
@visibleForTesting
CallToneService? debugCallToneServiceOverride;

CallToneService get defaultCallToneService =>
    debugCallToneServiceOverride ?? CallToneService.instance;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../preferences/app_preferences.dart';
import 'ui_sound.dart';

abstract interface class UiSoundPlayer {
  /// Completes only after the cue has finished playing.
  ///
  /// The service uses this contract to serialize a channel without cutting
  /// off the tail that is already audible.
  Future<void> play(String assetPath, {required double volume});
  Future<void> dispose();
}

/// Narrow seam around [AudioPlayer], so completion ordering and timeout
/// recovery can be tested without a platform audio engine.
abstract interface class UiSoundPlaybackEngine {
  Stream<void> get onPlayerComplete;
  Future<void> configureAndroidUiSoundContext();
  Future<void> playAsset(String assetPath, {required double volume});
  Future<void> stop();
  Future<void> dispose();
}

class _AudioplayersUiSoundEngine implements UiSoundPlaybackEngine {
  _AudioplayersUiSoundEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> configureAndroidUiSoundContext() => _player.setAudioContext(
    AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.none,
      ),
    ),
  );

  @override
  Future<void> playAsset(String assetPath, {required double volume}) =>
      _player.play(AssetSource(assetPath), volume: volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class AudioplayersUiSoundPlayer implements UiSoundPlayer {
  AudioplayersUiSoundPlayer({
    UiSoundPlaybackEngine? engine,
    Duration completionTimeout = const Duration(seconds: 2),
  }) : assert(completionTimeout > Duration.zero),
       _engine = engine ?? _AudioplayersUiSoundEngine(),
       _completionTimeout = completionTimeout;

  final UiSoundPlaybackEngine _engine;
  final Duration _completionTimeout;
  bool _androidContextReady = false;
  Future<void>? _disposeFuture;

  @override
  Future<void> play(String assetPath, {required double volume}) async {
    // A 100 ms product cue is sonification, not media. Taking full audio
    // focus for it can duck LiveKit or interrupt whatever the user was
    // already hearing. Configure this only on Android: AVAudioSession is
    // process-global on iOS and must remain under LiveKit/recording control.
    if (!_androidContextReady &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      await _engine.configureAndroidUiSoundContext();
      _androidContextReady = true;
    }

    // Subscribe before starting: very short or mocked engines may publish
    // completion synchronously from playAsset(). AudioPlayer.play() itself
    // resolves once the platform command starts, not when the WAV ends.
    final completed = Completer<void>();
    Object? completionError;
    StackTrace? completionStackTrace;
    late final StreamSubscription<void> completionSubscription;
    completionSubscription = _engine.onPlayerComplete.listen(
      (_) {
        if (!completed.isCompleted) completed.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completed.isCompleted) {
          completionError = error;
          completionStackTrace = stackTrace;
          completed.complete();
        }
      },
      onDone: () {
        if (!completed.isCompleted) {
          completionError = StateError(
            'UI sound completion stream closed early.',
          );
          completionStackTrace = StackTrace.current;
          completed.complete();
        }
      },
    );

    try {
      await (() async {
        await _engine.playAsset(assetPath, volume: volume);
        await completed.future;
        if (completionError != null) {
          Error.throwWithStackTrace(
            completionError!,
            completionStackTrace ?? StackTrace.current,
          );
        }
      })().timeout(_completionTimeout);
    } catch (_) {
      // A platform engine that never reports completion must not wedge this
      // channel forever. Stopping is recovery-only, after failure/timeout;
      // the normal path always lets the audible tail finish naturally.
      try {
        await _engine.stop();
      } catch (_) {
        // Preserve the original playback failure.
      }
      rethrow;
    } finally {
      await completionSubscription.cancel();
    }
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _engine.dispose();
}

typedef UiSoundPlayerFactory = UiSoundPlayer Function(UiSoundChannel channel);
typedef UiSoundClock = DateTime Function();

/// A small, failure-isolated sound layer for meaningful product events.
///
/// Players are created lazily (at most one per channel), so simply enabling
/// sounds allocates no audio engine or decoded buffers. Rapid repeated room
/// events are intentionally coalesced to avoid a noisy join/leave cascade.
class UiSoundService {
  UiSoundService({
    bool Function()? enabled,
    UiSoundPlayerFactory? playerFactory,
    UiSoundClock? clock,
  }) : _enabled =
           enabled ??
           (() => AppPreferencesController.instance.value.soundEffectsEnabled),
       _playerFactory = playerFactory ?? ((_) => AudioplayersUiSoundPlayer()),
       _clock = clock ?? DateTime.now;

  static final instance = UiSoundService();

  final bool Function() _enabled;
  final UiSoundPlayerFactory _playerFactory;
  final UiSoundClock _clock;
  final Map<UiSoundChannel, UiSoundPlayer> _players = {};
  final Map<UiSound, DateTime> _lastPlayed = {};
  final Map<UiSoundChannel, DateTime> _lastChannelPlayed = {};
  final Map<UiSoundChannel, Future<void>> _channelTails = {};
  final Map<UiSoundChannel, int> _channelGenerations = {};
  bool _disposed = false;
  Future<void>? _disposeFuture;

  Future<void> play(UiSound sound) async {
    if (_disposed || !_enabled()) return;

    final now = _clock();
    final lastSound = _lastPlayed[sound];
    if (lastSound != null && _inside(now, lastSound, sound.cooldown)) {
      return;
    }
    final lastChannel = _lastChannelPlayed[sound.channel];
    if (lastChannel != null &&
        _inside(now, lastChannel, _channelCooldown(sound.channel))) {
      return;
    }

    _lastPlayed[sound] = now;
    _lastChannelPlayed[sound.channel] = now;
    // Calls originate from unawaited LiveKit and notification callbacks. Run
    // one command at a time per channel, and let the newest queued command
    // supersede an older one that has not started yet. The active cue keeps
    // its full tail; only stale work still waiting behind it is discarded.
    final generation = (_channelGenerations[sound.channel] ?? 0) + 1;
    _channelGenerations[sound.channel] = generation;
    final previous = _channelTails[sound.channel] ?? Future<void>.value();
    final scheduled = previous.then((_) async {
      if (_disposed || _channelGenerations[sound.channel] != generation) {
        return;
      }
      try {
        final player = _players.putIfAbsent(
          sound.channel,
          () => _playerFactory(sound.channel),
        );
        await player.play(sound.assetPath, volume: sound.volume);
      } catch (error) {
        // Audio feedback must never make the underlying user action fail.
        debugPrint(
          'UiSoundService: ${sound.name} could not play '
          '(${error.runtimeType}).',
        );
      }
    });
    _channelTails[sound.channel] = scheduled;
    await scheduled;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    for (final channel in UiSoundChannel.values) {
      _channelGenerations[channel] = (_channelGenerations[channel] ?? 0) + 1;
    }
    await Future.wait(_channelTails.values);
    final players = _players.values.toList(growable: false);
    _players.clear();
    await Future.wait(players.map((player) => player.dispose()));
  }

  Duration _channelCooldown(UiSoundChannel channel) => switch (channel) {
    UiSoundChannel.room => const Duration(milliseconds: 150),
    UiSoundChannel.controls => const Duration(milliseconds: 70),
    UiSoundChannel.notification => const Duration(milliseconds: 650),
  };

  bool _inside(DateTime now, DateTime then, Duration window) {
    final elapsed = now.difference(then);
    // Wall clocks can move backwards after a network/time-zone correction.
    // Treat that as a fresh epoch instead of muting the app until it catches
    // back up to a timestamp from the future.
    return !elapsed.isNegative && elapsed < window;
  }
}

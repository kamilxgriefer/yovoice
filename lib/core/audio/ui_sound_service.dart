import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../preferences/app_preferences.dart';
import 'ui_sound.dart';

abstract interface class UiSoundPlayer {
  Future<void> play(String assetPath, {required double volume});
  Future<void> dispose();
}

class AudioplayersUiSoundPlayer implements UiSoundPlayer {
  AudioplayersUiSoundPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(String assetPath, {required double volume}) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath), volume: volume);
  }

  @override
  Future<void> dispose() => _player.dispose();
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

  Future<void> play(UiSound sound) async {
    if (!_enabled()) return;

    final now = _clock();
    final lastSound = _lastPlayed[sound];
    if (lastSound != null && now.difference(lastSound) < sound.cooldown) {
      return;
    }
    final lastChannel = _lastChannelPlayed[sound.channel];
    if (lastChannel != null &&
        now.difference(lastChannel) < _channelCooldown(sound.channel)) {
      return;
    }

    _lastPlayed[sound] = now;
    _lastChannelPlayed[sound.channel] = now;
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
  }

  Future<void> dispose() async {
    final players = _players.values.toList(growable: false);
    _players.clear();
    for (final player in players) {
      await player.dispose();
    }
  }

  Duration _channelCooldown(UiSoundChannel channel) => switch (channel) {
    UiSoundChannel.room => const Duration(milliseconds: 120),
    UiSoundChannel.controls => const Duration(milliseconds: 55),
    UiSoundChannel.notification => const Duration(milliseconds: 500),
  };
}

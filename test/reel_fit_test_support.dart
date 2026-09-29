// Doubles for the Yeel fit / rotation suites (ADR-235): a local decoder with
// a chosen display size for the composer preview, and a video platform whose
// initialization event reports a chosen size for the feed's real
// VideoPlayerController. No native decoder is ever started.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
// The installed video_player plugin owns this locked test-only platform seam.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A composer-preview decoder whose initialized size is [size].
class FakeSizedVideoController implements VideoPlayerController {
  FakeSizedVideoController(this.size);

  final Size size;
  int initializeCount = 0;
  final ValueNotifier<VideoPlayerValue> _state = ValueNotifier(
    const VideoPlayerValue(duration: Duration(seconds: 20)),
  );

  @override
  VideoPlayerValue get value => _state.value;

  @override
  set value(VideoPlayerValue value) => _state.value = value;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
    value = value.copyWith(isInitialized: true, size: size);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Future<void> dispose() async => _state.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The feed's decoder boundary: every player initializes at [size].
class SizedVideoPlatform extends VideoPlayerPlatform {
  SizedVideoPlatform(this.size);

  Size size;
  int _next = 1;
  final Map<int, StreamController<VideoEvent>> _events = {};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    final events = StreamController<VideoEvent>(onCancel: () async {});
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 18),
        size: size,
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events[playerId]?.close();

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
    key: ValueKey<String>('sized-video-view-${options.playerId}'),
    color: const Color(0xFF527B83),
  );
}

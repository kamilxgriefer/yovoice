import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/audio/realtime_audio_session_registry.dart';

typedef DirectVideoAudioPreparer = Future<void> Function();
typedef DirectVideoNativeAudioSessionPreparer = Future<void> Function();

const MethodChannel _directVideoAudioChannel = MethodChannel(
  'app.yovoice/direct_video_audio',
);

Future<void> _prepareNativeMoviePlayback() async {
  await _directVideoAudioChannel.invokeMethod<bool>('prepareMoviePlayback');
}

/// Restores the platform's normal media route before a user-started DM video.
///
/// LiveKit and the recorder legitimately leave a process-wide communication
/// audio session behind. On iOS that can route AVPlayer through the receiver or
/// keep the session in a category silenced by the hardware switch; on Android
/// it can leave AudioManager in communication mode. A video controller cannot
/// repair either state by changing its own volume.
///
/// An active or still-tearing-down realtime session always wins. Its audio
/// route is process-global, so a chat video must never replace it.
Future<void> prepareDirectVideoAudioPlayback() async {
  await configureDirectVideoAudioPlayback();
}

@visibleForTesting
Future<bool> configureDirectVideoAudioPlayback({
  TargetPlatform? platform,
  bool Function()? realtimeSessionIsActive,
  RealtimeAudioSessionRegistry? audioSessions,
  DirectVideoNativeAudioSessionPreparer? prepareNativeAudioSession,
}) async {
  if (kIsWeb) return false;
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  if (resolvedPlatform != TargetPlatform.iOS &&
      resolvedPlatform != TargetPlatform.android) {
    return false;
  }

  if (realtimeSessionIsActive?.call() ?? false) return false;
  final registry = audioSessions ?? RealtimeAudioSessionRegistry.instance;
  try {
    return await registry.configureMediaWhenRealtimeIdle(() async {
      // Both platforms use the native bridge because the installed Android
      // audioplayers global setter records the requested context only after
      // applying its previous AudioManager mode. A DM video uses video_player,
      // so no later audioplayers instance exists to apply MODE_NORMAL for it.
      // iOS needs the same bridge for the atomic category + moviePlayback mode.
      await (prepareNativeAudioSession ?? _prepareNativeMoviePlayback)();
    });
  } catch (_) {
    // Audio routing is recovery for an inherited platform state. A routing
    // plugin failure must not turn a still-playable video into an error tile.
    return false;
  }
}

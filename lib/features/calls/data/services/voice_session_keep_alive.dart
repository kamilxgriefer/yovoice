import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the process alive while a voice session is connected.
///
/// Android silences a backgrounded process's microphone and freezes it once
/// it is cached. With one party minimised the other keeps publishing, so
/// audio still flows and the minimised app stays awake; with BOTH minimised
/// nothing flows, both processes freeze and both LiveKit participants time
/// out — the reported "call drops when both minimise the app". A foreground
/// service of type `microphone` (or `mediaPlayback` for a listener) is what
/// Android requires to keep that from happening.
///
/// iOS needs no equivalent: `UIBackgroundModes: audio` plus the LiveKit
/// audio session already keep a connected call running, and adding `voip`
/// without CallKit would be an App Store rejection.
abstract interface class VoiceSessionKeepAlive {
  /// Called from the join path while the app is still foregrounded — Android
  /// 12 and later refuse a foreground service started from the background.
  Future<void> start({
    required String title,
    required String body,
    required bool canPublish,
  });

  Future<void> stop();
}

/// Does nothing: iOS, web, tests, and any platform without the service.
class NoopVoiceSessionKeepAlive implements VoiceSessionKeepAlive {
  const NoopVoiceSessionKeepAlive();

  @override
  Future<void> start({
    required String title,
    required String body,
    required bool canPublish,
  }) async {}

  @override
  Future<void> stop() async {}
}

/// Drives `VoiceSessionService` through a method channel. Failures are
/// swallowed on purpose: a refused foreground start (OEM policy, a race with
/// backgrounding) must never break the call that is otherwise fine.
class AndroidVoiceSessionKeepAlive implements VoiceSessionKeepAlive {
  const AndroidVoiceSessionKeepAlive({
    MethodChannel channel = const MethodChannel('app.yo_voice/voice_session'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> start({
    required String title,
    required String body,
    required bool canPublish,
  }) async {
    try {
      await _channel.invokeMethod<bool>('start', <String, Object?>{
        'title': title,
        'body': body,
        'canPublish': canPublish,
      });
    } catch (error) {
      debugPrint('Voice session keep-alive could not start: $error');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (error) {
      debugPrint('Voice session keep-alive could not stop: $error');
    }
  }
}

/// The implementation for the running platform.
VoiceSessionKeepAlive defaultVoiceSessionKeepAlive() {
  if (kIsWeb) return const NoopVoiceSessionKeepAlive();
  return defaultTargetPlatform == TargetPlatform.android
      ? const AndroidVoiceSessionKeepAlive()
      : const NoopVoiceSessionKeepAlive();
}

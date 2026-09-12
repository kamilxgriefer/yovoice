import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show AudioManager;
import 'package:yovoice/features/calls/data/services/voice_session_keep_alive.dart';

/// The device-level half of a server conversation: which speaker it comes out
/// of, and keeping the process alive while it is up.
///
/// Both are process-global platform state that this slice consumes and does
/// not own — `AudioManager` is `livekit_client`'s own singleton and the
/// keep-alive is the single foreground service the voice stack already
/// declares. They are behind one interface so a widget test can observe the
/// calls instead of reaching a method channel that is not there.
abstract interface class ServerVoiceDevice {
  /// A server conversation is a social surface at every template, so it plays
  /// on the speaker.
  ///
  /// This has to be asserted per session rather than assumed: the preference
  /// is a process-global that `VoiceCallService` writes to *earpiece* on every
  /// teardown of a private call, and `Room.connect` re-applies whatever it
  /// finds. Without this a Salon opened after any call came out of the
  /// earpiece, on every template, with no output control anywhere to fix it.
  Future<void> preferSpeakerOutput();

  /// Android silences and then freezes a backgrounded process that holds a
  /// microphone without a foreground service — the documented "call drops
  /// when both minimise the app". Started from the foreground, on connect,
  /// because Android 12 and later refuse a background start.
  Future<void> startKeepAlive({
    required String title,
    required String body,
    required bool canPublish,
  });

  Future<void> stopKeepAlive();
}

/// Test seam. Set it in a test's setup and clear it in its teardown; null (the
/// production value) uses the real platform services.
@visibleForTesting
ServerVoiceDevice? debugServerVoiceDeviceOverride;

ServerVoiceDevice serverVoiceDevice() =>
    debugServerVoiceDeviceOverride ?? PlatformServerVoiceDevice();

/// The production implementation.
///
/// Every call is guarded and swallowed: a refused foreground start (OEM
/// policy, a race with backgrounding) or an unavailable route must never break
/// a conversation that is otherwise fine, which is the rule the keep-alive
/// itself already follows.
class PlatformServerVoiceDevice implements ServerVoiceDevice {
  PlatformServerVoiceDevice({VoiceSessionKeepAlive? keepAlive})
    : _keepAlive = keepAlive ?? defaultVoiceSessionKeepAlive();

  final VoiceSessionKeepAlive _keepAlive;
  bool _keepAliveActive = false;

  @override
  Future<void> preferSpeakerOutput() async {
    try {
      if (!AudioManager.instance.canSwitchSpeakerphone) return;
      if (AudioManager.instance.isSpeakerOutputPreferred) return;
      await AudioManager.instance.setSpeakerOutputPreferred(true);
    } catch (error) {
      debugPrint('Server conversation could not prefer the speaker: $error');
    }
  }

  @override
  Future<void> startKeepAlive({
    required String title,
    required String body,
    required bool canPublish,
  }) async {
    if (_keepAliveActive) return;
    _keepAliveActive = true;
    await _keepAlive.start(title: title, body: body, canPublish: canPublish);
  }

  @override
  Future<void> stopKeepAlive() async {
    if (!_keepAliveActive) return;
    _keepAliveActive = false;
    await _keepAlive.stop();
  }
}

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

/// What the room's primary control is ALLOWED to be right now.
///
/// The affordance must match the authority. A mute/unmute control implies a
/// live voice session and a token that already exists; offering one in a
/// dormant room produces exactly the failure this whole change is about — the
/// user presses unmute and the server answers "This room is not currently
/// live." Deriving the control from a single enum, rather than from a
/// combination of guessed booleans at four call sites, is what makes that
/// state unrepresentable.
enum RoomMicAffordance {
  /// Publishing and audible — tapping mutes.
  live,

  /// Can publish, currently muted — tapping unmutes.
  muted,

  /// The audio session is still being established.
  connecting,

  /// Connected with no publish rights (a broadcast audience member).
  listenOnly,

  /// The room has no voice session, and this account may start one. The one
  /// state in which a start control is offered.
  startVoice,

  /// The room has no voice session and this account may not start one.
  /// Tapping explains why; it never fails silently and never raises a
  /// permission error.
  waitingForHost,

  /// Connected audio is genuinely broken (permission refused, transport
  /// failure). Tapping surfaces the reason.
  unavailable;

  /// The two states — and the only two — in which a mute toggle may be sent.
  bool get isMuteControl =>
      this == RoomMicAffordance.live || this == RoomMicAffordance.muted;

  bool get isStartControl => this == RoomMicAffordance.startVoice;
}

/// Resolves the control from room liveness first and the audio session
/// second.
///
/// Liveness LEADS on purpose. [MicState] describes the LiveKit session, which
/// knows nothing about the room document; in a dormant room there is no
/// session at all, so every [MicState] value it could report — including
/// `unavailable`, which reads as "audio is broken" — would misdescribe a room
/// that is simply not live yet.
RoomMicAffordance roomMicAffordance({
  required bool roomIsLive,
  required bool canStartVoice,
  required MicState micState,
}) {
  if (!roomIsLive) {
    return canStartVoice
        ? RoomMicAffordance.startVoice
        : RoomMicAffordance.waitingForHost;
  }
  return switch (micState) {
    MicState.on => RoomMicAffordance.live,
    MicState.muted => RoomMicAffordance.muted,
    MicState.connecting => RoomMicAffordance.connecting,
    MicState.listenOnly => RoomMicAffordance.listenOnly,
    MicState.unavailable => RoomMicAffordance.unavailable,
  };
}

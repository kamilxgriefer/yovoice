import 'dart:async';

/// Serializes a room mute change across the roster and LiveKit.
///
/// The roster must be updated first. Room screens listen to that roster and
/// enforce `isMuted == true` on the local microphone. Enabling LiveKit before
/// clearing the roster therefore lets a stale `true` snapshot immediately
/// mute the microphone again.
class RoomMuteSync {
  RoomMuteSync({this.onBusyChanged});

  final void Function()? onBusyChanged;
  bool _busy = false;

  bool get isBusy => _busy;

  Future<bool> toggle({
    required bool currentMuted,
    required Future<void> Function(bool muted) persistRosterState,
    required Future<void> Function(bool muted) applyMicrophoneState,
  }) async {
    if (_busy) return false;

    final targetMuted = !currentMuted;
    _busy = true;
    onBusyChanged?.call();
    try {
      await persistRosterState(targetMuted);
      await applyMicrophoneState(targetMuted);
      return true;
    } finally {
      _busy = false;
      onBusyChanged?.call();
    }
  }
}

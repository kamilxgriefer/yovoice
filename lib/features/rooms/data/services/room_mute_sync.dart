import 'dart:async';

/// Serializes a room mute change across LiveKit and the roster.
///
/// Muting is privacy-sensitive and must feel immediate, so the local track is
/// disabled before any network round trip. Unmuting keeps the opposite order:
/// server authority clears the roster flag first, then LiveKit is enabled.
/// This asymmetry makes Mute instant without creating a window that could
/// bypass a moderator/server mute.
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
      if (targetMuted) {
        await applyMicrophoneState(true);
        await persistRosterState(true);
      } else {
        await persistRosterState(false);
        await applyMicrophoneState(false);
      }
      return true;
    } finally {
      _busy = false;
      onBusyChanged?.call();
    }
  }
}

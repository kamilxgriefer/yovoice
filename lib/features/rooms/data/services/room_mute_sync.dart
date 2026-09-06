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

  /// Roster writes are chained so they land in the order the user acted,
  /// even when a mute's write is still in flight while the next toggle
  /// starts (see [toggle]).
  Future<void> _rosterTail = Future<void>.value();

  bool get isBusy => _busy;

  Future<void> _persistInOrder(Future<void> Function() persist) {
    final next = _rosterTail.then((_) => persist());
    _rosterTail = next.catchError((Object _) {});
    return next;
  }

  void _setBusy(bool busy) {
    if (_busy == busy) return;
    _busy = busy;
    onBusyChanged?.call();
  }

  Future<bool> toggle({
    required bool currentMuted,
    required Future<void> Function(bool muted) persistRosterState,
    required Future<void> Function(bool muted) applyMicrophoneState,
    bool Function()? isOperationCurrent,
  }) async {
    if (_busy) return false;

    bool isCurrent() => isOperationCurrent?.call() ?? true;
    if (!isCurrent()) return false;

    final targetMuted = !currentMuted;
    _setBusy(true);
    try {
      if (targetMuted) {
        if (!isCurrent()) return false;
        await applyMicrophoneState(true);
        if (!isCurrent()) return false;
        // The microphone is off: the privacy-critical half is done and the
        // icon already shows it. Holding the control busy for the roster
        // mirror's round trip (seconds on a cold callable) read as "mute
        // lags". Release now; the write still completes, still in order,
        // and its failure still reaches the coordinator below.
        _setBusy(false);
        await _persistInOrder(() => persistRosterState(true));
      } else {
        if (!isCurrent()) return false;
        await _persistInOrder(() => persistRosterState(false));
        // The room can be replaced while the authority write is in flight.
        // Never enable the process-wide microphone for that newer session.
        if (!isCurrent()) return false;
        await applyMicrophoneState(false);
      }
      return true;
    } finally {
      _setBusy(false);
    }
  }
}

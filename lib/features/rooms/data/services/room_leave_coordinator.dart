import 'dart:async';

/// Leaves the visible room immediately and finishes server bookkeeping later.
///
/// A failed or slow participant cleanup must never trap someone in the room
/// screen after they pressed Leave. Audio is disconnected first, navigation is
/// then completed exactly once, and the idempotent backend cleanup continues in
/// the background.
class RoomLeaveCoordinator {
  bool _leaving = false;

  bool get isLeaving => _leaving;

  Future<bool> leave({
    required Future<void> Function() disconnectAudio,
    required void Function() navigateAway,
    required Future<void> Function() cleanupParticipant,
    void Function(Object error, StackTrace stackTrace)? onCleanupError,
  }) async {
    if (_leaving) return false;
    _leaving = true;

    try {
      await disconnectAudio();
    } catch (_) {
      // Navigation is still mandatory. The connection service also clears its
      // local state defensively, so a transport error cannot hold the UI open.
    }

    navigateAway();
    unawaited(
      _cleanup(cleanupParticipant, onCleanupError),
    );
    return true;
  }

  Future<void> _cleanup(
    Future<void> Function() cleanupParticipant,
    void Function(Object error, StackTrace stackTrace)? onCleanupError,
  ) async {
    try {
      await cleanupParticipant();
    } catch (error, stackTrace) {
      onCleanupError?.call(error, stackTrace);
    }
  }
}

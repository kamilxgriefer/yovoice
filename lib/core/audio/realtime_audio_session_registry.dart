import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// The realtime surfaces that can own the process-wide native audio session.
enum RealtimeAudioSessionOwnerKind { directOrLegacyCall, serverConversation }

/// One idempotently releasable claim in [RealtimeAudioSessionRegistry].
///
/// A claim stays alive through native teardown. Releasing it earlier would let
/// ordinary media switch the shared AVAudioSession/AudioManager route while
/// LiveKit is still disconnecting in the background.
final class RealtimeAudioSessionLease {
  RealtimeAudioSessionLease._(this._registry, this._owner, this.kind);

  final RealtimeAudioSessionRegistry _registry;
  final Object _owner;
  final RealtimeAudioSessionOwnerKind kind;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _registry._release(this, _owner);
  }
}

/// Process-wide arbitration between LiveKit and ordinary media playback.
///
/// iOS AVAudioSession and Android audio focus/routing are global to the app,
/// even though YO Voice has separate controllers for private calls and Server
/// conversations. Both therefore publish their complete joining/connected/
/// cleanup lifecycle here. A DM video can reserve one short configuration
/// operation only while that set is empty.
///
/// Realtime claims wait for an already-started media configuration to finish.
/// New media configuration refuses while a realtime claim is active *or being
/// acquired*. That small handshake removes the check-then-act race where a
/// call could start between the Dart guard and a native route write.
final class RealtimeAudioSessionRegistry extends ChangeNotifier {
  RealtimeAudioSessionRegistry();

  static final RealtimeAudioSessionRegistry instance =
      RealtimeAudioSessionRegistry();

  final Map<Object, RealtimeAudioSessionLease> _leases =
      HashMap<Object, RealtimeAudioSessionLease>.identity();
  int _pendingRealtimeAcquisitions = 0;
  Future<void>? _mediaConfigurationBarrier;

  /// Includes callers that have declared join intent but are briefly waiting
  /// for an already-started media configuration to finish.
  bool get hasActiveOrJoiningSession =>
      _leases.isNotEmpty || _pendingRealtimeAcquisitions > 0;

  @visibleForTesting
  int get activeLeaseCount => _leases.length;

  @visibleForTesting
  int get pendingAcquisitionCount => _pendingRealtimeAcquisitions;

  @visibleForTesting
  Set<RealtimeAudioSessionOwnerKind> get activeKinds =>
      _leases.values.map((lease) => lease.kind).toSet();

  /// Acquires (or reuses) this controller's realtime claim.
  ///
  /// Different realtime controllers may overlap for the few milliseconds in
  /// which the established call/server handoff resolves; the registry's job is
  /// to keep non-RTC media away from all of them. Reusing a claim for the same
  /// [owner] makes rapid retries and channel replacement safe without a gap.
  Future<RealtimeAudioSessionLease> acquire({
    required Object owner,
    required RealtimeAudioSessionOwnerKind kind,
  }) async {
    final existing = _leases[owner];
    if (existing != null) return existing;

    _pendingRealtimeAcquisitions++;
    notifyListeners();
    try {
      while (true) {
        final barrier = _mediaConfigurationBarrier;
        if (barrier == null) break;
        await barrier;
      }

      final claimedWhileWaiting = _leases[owner];
      if (claimedWhileWaiting != null) return claimedWhileWaiting;
      final lease = RealtimeAudioSessionLease._(this, owner, kind);
      _leases[owner] = lease;
      notifyListeners();
      return lease;
    } finally {
      _pendingRealtimeAcquisitions--;
      notifyListeners();
    }
  }

  /// Runs one short process-audio configuration only when no RTC join owns or
  /// is acquiring the platform session. Returns false when realtime wins.
  Future<bool> configureMediaWhenRealtimeIdle(
    Future<void> Function() configure,
  ) async {
    while (true) {
      final inFlight = _mediaConfigurationBarrier;
      if (inFlight == null) break;
      await inFlight;
    }
    if (hasActiveOrJoiningSession) return false;

    final completion = Completer<void>();
    _mediaConfigurationBarrier = completion.future;
    try {
      await configure();
      return true;
    } finally {
      if (identical(_mediaConfigurationBarrier, completion.future)) {
        _mediaConfigurationBarrier = null;
      }
      completion.complete();
    }
  }

  void _release(RealtimeAudioSessionLease lease, Object owner) {
    if (!identical(_leases[owner], lease)) return;
    _leases.remove(owner);
    notifyListeners();
  }
}

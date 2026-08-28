import 'dart:async';

import 'package:flutter/foundation.dart';

/// Process-local guard against stacking the same private call route from two
/// delivery paths (the foreground Firestore stream and an FCM notification
/// tap racing during app resume).
class DirectCallRouteRegistry {
  DirectCallRouteRegistry._();

  static final Set<String> _claimedCallIds = <String>{};

  static bool claim(String callId) => _claimedCallIds.add(callId);

  static void release(String callId) => _claimedCallIds.remove(callId);
}

enum DirectCallAlertOwner { coordinator, push }

/// Result of racing the Firestore signaling path with foreground FCM.
///
/// Both transports can observe the same ringing call in either order. The
/// winner owns the one audible alert; the loser can wait for the winner's
/// presentation result and take over only when that presentation failed.
class DirectCallAlertClaim {
  const DirectCallAlertClaim._({
    required this.callId,
    required this.owner,
    required this.ownsAlert,
    required this.result,
    required Object token,
  }) : _token = token;

  final String callId;
  final DirectCallAlertOwner owner;
  final bool ownsAlert;
  final Future<bool> result;
  final Object _token;
}

class _DirectCallAlertEntry {
  _DirectCallAlertEntry(this.owner, this.claimedAt)
    : result = Completer<bool>();

  final DirectCallAlertOwner owner;
  final DateTime claimedAt;
  final Completer<bool> result;
  final Object token = Object();
  Timer? activeTimeout;
  DateTime? completedAt;
}

/// Process-local exactly-one arbiter for foreground incoming-call sound.
class DirectCallAlertRegistry {
  DirectCallAlertRegistry._();

  static const int _defaultMaximumEntries = 64;
  static const Duration _defaultCompletedRetention = Duration(minutes: 5);
  static const Duration _defaultActiveClaimTimeout = Duration(seconds: 30);

  static final Map<String, _DirectCallAlertEntry> _entries =
      <String, _DirectCallAlertEntry>{};
  static DateTime Function() _clock = DateTime.now;
  static int _maximumEntries = _defaultMaximumEntries;
  static Duration _completedRetention = _defaultCompletedRetention;
  static Duration _activeClaimTimeout = _defaultActiveClaimTimeout;

  static DirectCallAlertClaim claim(String callId, DirectCallAlertOwner owner) {
    final now = _clock();
    _prune(now);
    final existing = _entries[callId];
    if (existing != null) {
      return DirectCallAlertClaim._(
        callId: callId,
        owner: owner,
        ownsAlert: false,
        result: existing.result.future,
        token: existing.token,
      );
    }
    _makeCapacityForOne();
    final created = _DirectCallAlertEntry(owner, now);
    _entries[callId] = created;
    created.activeTimeout = Timer(_activeClaimTimeout, () {
      final current = _entries[callId];
      if (current == null ||
          !identical(current.token, created.token) ||
          current.completedAt != null) {
        return;
      }
      _evict(callId, expectedToken: created.token);
    });
    return DirectCallAlertClaim._(
      callId: callId,
      owner: owner,
      ownsAlert: true,
      result: created.result.future,
      token: created.token,
    );
  }

  static void complete(DirectCallAlertClaim claim, {required bool presented}) {
    if (!claim.ownsAlert) return;
    final current = _entries[claim.callId];
    if (current == null ||
        current.owner != claim.owner ||
        !identical(current.token, claim._token)) {
      return;
    }
    if (current.result.isCompleted) return;
    current.activeTimeout?.cancel();
    current.activeTimeout = null;
    current.result.complete(presented);
    current.completedAt = _clock();
    if (!presented) _entries.remove(claim.callId);
  }

  static void release(String callId) => _evict(callId);

  static void clear() {
    for (final entry in _entries.values) {
      entry.activeTimeout?.cancel();
      if (!entry.result.isCompleted) entry.result.complete(false);
    }
    _entries.clear();
  }

  static void _prune(DateTime now) {
    final expired = <String>[];
    for (final entry in _entries.entries) {
      final completedAt = entry.value.completedAt;
      final expiry = completedAt == null
          ? entry.value.claimedAt.add(_activeClaimTimeout)
          : completedAt.add(_completedRetention);
      if (!expiry.isAfter(now)) expired.add(entry.key);
    }
    for (final callId in expired) {
      _evict(callId);
    }
  }

  static void _makeCapacityForOne() {
    while (_entries.length >= _maximumEntries) {
      MapEntry<String, _DirectCallAlertEntry>? oldestCompleted;
      MapEntry<String, _DirectCallAlertEntry>? oldestActive;
      for (final entry in _entries.entries) {
        final completedAt = entry.value.completedAt;
        if (completedAt != null) {
          if (oldestCompleted == null ||
              completedAt.isBefore(oldestCompleted.value.completedAt!)) {
            oldestCompleted = entry;
          }
        } else if (oldestActive == null ||
            entry.value.claimedAt.isBefore(oldestActive.value.claimedAt)) {
          oldestActive = entry;
        }
      }
      _evict((oldestCompleted ?? oldestActive)!.key);
    }
  }

  static void _evict(String callId, {Object? expectedToken}) {
    final current = _entries[callId];
    if (current == null ||
        (expectedToken != null && !identical(current.token, expectedToken))) {
      return;
    }
    final removed = _entries.remove(callId);
    removed?.activeTimeout?.cancel();
    if (removed != null && !removed.result.isCompleted) {
      removed.result.complete(false);
    }
  }

  @visibleForTesting
  static int get debugEntryCount => _entries.length;

  @visibleForTesting
  static void configureForTesting({
    required DateTime Function() clock,
    int maximumEntries = _defaultMaximumEntries,
    Duration completedRetention = _defaultCompletedRetention,
    Duration activeClaimTimeout = _defaultActiveClaimTimeout,
  }) {
    if (maximumEntries < 1) {
      throw ArgumentError.value(maximumEntries, 'maximumEntries');
    }
    clear();
    _clock = clock;
    _maximumEntries = maximumEntries;
    _completedRetention = completedRetention;
    _activeClaimTimeout = activeClaimTimeout;
  }

  @visibleForTesting
  static void resetTestingConfiguration() {
    clear();
    _clock = DateTime.now;
    _maximumEntries = _defaultMaximumEntries;
    _completedRetention = _defaultCompletedRetention;
    _activeClaimTimeout = _defaultActiveClaimTimeout;
  }
}

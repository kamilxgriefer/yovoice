import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/direct_call.dart';

class PendingDirectCallStartRequest {
  const PendingDirectCallStartRequest({
    required this.callerId,
    required this.calleeId,
    required this.conversationId,
    required this.requestId,
    required this.createdAt,
    this.mediaType = DirectCallMediaType.audio,
  });

  final String callerId;
  final String calleeId;
  final String conversationId;
  final DirectCallMediaType mediaType;
  final String requestId;
  final DateTime createdAt;

  Map<String, Object> toJson() => <String, Object>{
    'callerId': callerId,
    'calleeId': calleeId,
    'conversationId': conversationId,
    'mediaType': mediaType.name,
    'requestId': requestId,
    'createdAtMillis': createdAt.millisecondsSinceEpoch,
  };

  static PendingDirectCallStartRequest? fromJson(Object? value) {
    if (value is! Map) return null;
    final callerId = value['callerId'];
    final calleeId = value['calleeId'];
    final conversationId = value['conversationId'];
    final requestId = value['requestId'];
    final createdAtMillis = value['createdAtMillis'];
    if (callerId is! String ||
        callerId.isEmpty ||
        calleeId is! String ||
        calleeId.isEmpty ||
        conversationId is! String ||
        conversationId.isEmpty ||
        requestId is! String ||
        requestId.isEmpty ||
        createdAtMillis is! int) {
      return null;
    }
    return PendingDirectCallStartRequest(
      callerId: callerId,
      calleeId: calleeId,
      conversationId: conversationId,
      mediaType: DirectCallMediaType.fromName(value['mediaType'] as String?),
      requestId: requestId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }
}

abstract interface class DirectCallStartRequestStore {
  /// Atomically returns the live request for this account/pair or persists
  /// [candidate] as the new request before any network write can begin.
  ///
  /// Implementations must serialize this with [clear]. Two service instances
  /// can otherwise both observe an empty scope and destroy lost-ACK recovery
  /// by overwriting each other's idempotency key.
  Future<PendingDirectCallStartRequest> acquire({
    required PendingDirectCallStartRequest candidate,
    required DateTime now,
    required Duration ttl,
  });

  Future<PendingDirectCallStartRequest?> load({
    required String callerId,
    required String calleeId,
    required String conversationId,
    required DateTime now,
    required Duration ttl,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  });

  Future<void> save(PendingDirectCallStartRequest request);

  Future<void> clear({
    required String callerId,
    required String calleeId,
    required String expectedRequestId,
  });
}

/// Durable, account-and-peer scoped idempotency state for starting a call.
///
/// The record is committed before the callable runs. A process that loses the
/// callable response can therefore replay the same request id after restart.
class SharedPreferencesDirectCallStartRequestStore
    implements DirectCallStartRequestStore {
  SharedPreferencesDirectCallStartRequestStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _storageKey = 'yovoice.directCall.startRequests.v1';
  static Future<void> _mutationTail = Future<void>.value();

  final Future<SharedPreferences> Function() _preferences;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<PendingDirectCallStartRequest> acquire({
    required PendingDirectCallStartRequest candidate,
    required DateTime now,
    required Duration ttl,
  }) => _serialize(() async {
    final preferences = await _preferences();
    final entries = _readEntries(preferences);
    var changed = _pruneStale(entries, now: now, ttl: ttl);
    final scope = _scope(candidate.callerId, candidate.calleeId);
    final current = PendingDirectCallStartRequest.fromJson(entries[scope]);
    if (current != null) {
      if (current.callerId != candidate.callerId ||
          current.calleeId != candidate.calleeId) {
        throw StateError('Pending direct-call identity is inconsistent.');
      }
      if (current.conversationId != candidate.conversationId) {
        // Preserve the uncertain operation instead of replacing the only key
        // capable of recovering a call that may already be ringing.
        throw StateError(
          'Another pending call already exists for this conversation pair.',
        );
      }
      if (current.mediaType != candidate.mediaType) {
        // A lost response may already have created the earlier media type.
        // Never rotate that operation into a different grant under the same
        // pair-scoped idempotency record.
        throw StateError(
          'Another pending call already exists for this conversation pair.',
        );
      }
      if (changed) await _writeEntries(preferences, entries);
      return current;
    }
    entries[scope] = candidate.toJson();
    changed = true;
    if (changed) await _writeEntries(preferences, entries);
    return candidate;
  });

  @override
  Future<PendingDirectCallStartRequest?> load({
    required String callerId,
    required String calleeId,
    required String conversationId,
    required DateTime now,
    required Duration ttl,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) => _serialize(() async {
    final preferences = await _preferences();
    final entries = _readEntries(preferences);
    var changed = _pruneStale(entries, now: now, ttl: ttl);
    final scope = _scope(callerId, calleeId);
    final request = PendingDirectCallStartRequest.fromJson(entries[scope]);
    if (request == null ||
        request.callerId != callerId ||
        request.calleeId != calleeId ||
        request.conversationId != conversationId ||
        request.mediaType != mediaType) {
      changed = entries.remove(scope) != null || changed;
      if (changed) await _writeEntries(preferences, entries);
      return null;
    }
    if (changed) await _writeEntries(preferences, entries);
    return request;
  });

  @override
  Future<void> save(PendingDirectCallStartRequest request) =>
      _serialize(() async {
        final preferences = await _preferences();
        final entries = _readEntries(preferences);
        entries[_scope(request.callerId, request.calleeId)] = request.toJson();
        await _writeEntries(preferences, entries);
      });

  @override
  Future<void> clear({
    required String callerId,
    required String calleeId,
    required String expectedRequestId,
  }) => _serialize(() async {
    final preferences = await _preferences();
    final entries = _readEntries(preferences);
    final scope = _scope(callerId, calleeId);
    final current = PendingDirectCallStartRequest.fromJson(entries[scope]);
    if (current?.requestId != expectedRequestId) return;
    entries.remove(scope);
    await _writeEntries(preferences, entries);
  });

  static String _scope(String callerId, String calleeId) =>
      base64Url.encode(utf8.encode('$callerId\u0000$calleeId'));

  static Map<String, Object?> _readEntries(SharedPreferences preferences) {
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return <String, Object?>{};
    }
  }

  static bool _pruneStale(
    Map<String, Object?> entries, {
    required DateTime now,
    required Duration ttl,
  }) {
    var changed = false;
    entries.removeWhere((_, value) {
      final request = PendingDirectCallStartRequest.fromJson(value);
      final remove =
          request == null || !request.createdAt.add(ttl).isAfter(now);
      changed = changed || remove;
      return remove;
    });
    return changed;
  }

  static Future<void> _writeEntries(
    SharedPreferences preferences,
    Map<String, Object?> entries,
  ) async {
    final saved = await preferences.setString(_storageKey, jsonEncode(entries));
    if (!saved) {
      throw StateError('The pending direct-call request could not be saved.');
    }
  }
}

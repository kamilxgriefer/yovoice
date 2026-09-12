import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_creation.dart';
import '../models/server_type.dart';

/// Durable, owner-and-template scoped idempotency state for creating a server.
///
/// `createServerV1` deduplicates on `requestId`, so an interrupted attempt is
/// only safe to resend if the *same* id and the *same* payload survive
/// everything that can happen between two taps — including the person leaving
/// the screen, the shell swapping its content slot, or the process dying. A
/// request that lived only in widget state kept that promise exactly as long
/// as the widget did; this store keeps it across the boundary.
///
/// The record is committed before the callable runs and cleared only once the
/// backend has definitively answered for that id (success, or a refusal that
/// happened before any write). An uncertain outcome — offline, timed out,
/// unknown — keeps it, so re-entering the configuration step for the same
/// template resumes the identical submission instead of allocating a new one.
///
/// Same shape as the direct-call start-request store: one scope per
/// owner + template, JSON in a single preference key, stale records pruned by
/// a TTL, and every mutation serialised so two screens cannot race each other
/// into overwriting the one key capable of recovering a lost acknowledgement.
abstract interface class ServerCreationRequestStore {
  /// The unresolved submission for this owner and template, if any.
  Future<ServerCreationRequest?> load({
    required String ownerId,
    required ServerType type,
    required DateTime now,
    required Duration ttl,
  });

  /// Commits [request] as the pending submission for its owner and template
  /// before any network write begins. Overwrites nothing: if an unresolved
  /// request already exists for that scope, it is returned and [request] is
  /// discarded, because the earlier id may already have committed a server.
  Future<ServerCreationRequest> remember({
    required String ownerId,
    required ServerCreationRequest request,
    required DateTime now,
  });

  /// Clears the pending record for the scope, but only if it still holds
  /// [expectedRequestId] — a newer submission must never be cleared by an
  /// older screen finishing late.
  Future<void> forget({
    required String ownerId,
    required ServerType type,
    required String expectedRequestId,
  });
}

/// One stored entry: the request plus when it was first committed.
class PendingServerCreation {
  const PendingServerCreation({required this.request, required this.createdAt});

  final ServerCreationRequest request;
  final DateTime createdAt;

  Map<String, Object> toJson() => <String, Object>{
    'request': request.toCallableData(),
    'createdAtMillis': createdAt.millisecondsSinceEpoch,
  };

  static PendingServerCreation? fromJson(Object? value) {
    if (value is! Map) return null;
    final request = ServerCreationRequest.fromCallableData(value['request']);
    final createdAtMillis = value['createdAtMillis'];
    if (request == null || createdAtMillis is! int) return null;
    return PendingServerCreation(
      request: request,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }
}

class SharedPreferencesServerCreationRequestStore
    implements ServerCreationRequestStore {
  SharedPreferencesServerCreationRequestStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const storageKey = 'yovoice.servers.pendingCreations.v1';
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
  Future<ServerCreationRequest?> load({
    required String ownerId,
    required ServerType type,
    required DateTime now,
    required Duration ttl,
  }) => _serialize(() async {
    final preferences = await _preferences();
    final entries = _readEntries(preferences);
    var changed = _pruneStale(entries, now: now, ttl: ttl);
    final scope = _scope(ownerId, type);
    final pending = PendingServerCreation.fromJson(entries[scope]);
    if (pending == null || pending.request.serverType != type) {
      changed = entries.remove(scope) != null || changed;
      if (changed) await _writeEntries(preferences, entries);
      return null;
    }
    if (changed) await _writeEntries(preferences, entries);
    return pending.request;
  });

  @override
  Future<ServerCreationRequest> remember({
    required String ownerId,
    required ServerCreationRequest request,
    required DateTime now,
  }) => _serialize(() async {
    final preferences = await _preferences();
    final entries = _readEntries(preferences);
    final scope = _scope(ownerId, request.serverType);
    final current = PendingServerCreation.fromJson(entries[scope]);
    if (current != null && current.request.serverType == request.serverType) {
      // Preserve the uncertain operation instead of replacing the only key
      // capable of recovering a server that may already exist.
      return current.request;
    }
    entries[scope] = PendingServerCreation(
      request: request,
      createdAt: now,
    ).toJson();
    await _writeEntries(preferences, entries);
    return request;
  });

  @override
  Future<void> forget({
    required String ownerId,
    required ServerType type,
    required String expectedRequestId,
  }) => _serialize(() async {
    final preferences = await _preferences();
    final entries = _readEntries(preferences);
    final scope = _scope(ownerId, type);
    final current = PendingServerCreation.fromJson(entries[scope]);
    if (current?.request.requestId != expectedRequestId) return;
    entries.remove(scope);
    await _writeEntries(preferences, entries);
  });

  static String _scope(String ownerId, ServerType type) =>
      base64Url.encode(utf8.encode('$ownerId\u0000${type.name}'));

  static Map<String, Object?> _readEntries(SharedPreferences preferences) {
    final encoded = preferences.getString(storageKey);
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
      final pending = PendingServerCreation.fromJson(value);
      final remove =
          pending == null || !pending.createdAt.add(ttl).isAfter(now);
      changed = changed || remove;
      return remove;
    });
    return changed;
  }

  static Future<void> _writeEntries(
    SharedPreferences preferences,
    Map<String, Object?> entries,
  ) async {
    final saved = await preferences.setString(storageKey, jsonEncode(entries));
    if (!saved) {
      throw StateError('The pending server creation could not be saved.');
    }
  }
}

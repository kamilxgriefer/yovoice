import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';

enum DirectAttachmentOutboxStatus { queued, retrying, failed }

class DirectAttachmentReservationRecord {
  const DirectAttachmentReservationRecord({
    required this.conversationId,
    required this.messageId,
    required this.storagePath,
    required this.type,
    required this.expiresAt,
    required this.clientExpiresAt,
  });

  final String conversationId;
  final String messageId;
  final String storagePath;
  final MessageType type;
  final DateTime? expiresAt;
  final DateTime? clientExpiresAt;

  static const _expectedLeaseDuration = Duration(minutes: 15);
  static const _minimumPlausibleLease = Duration(minutes: 10);
  static const _maximumPlausibleLease = Duration(minutes: 20);

  bool expiresBefore(DateTime instant) {
    final serverExpiry = expiresAt;
    if (serverExpiry == null) return true;
    final localExpiry = clientExpiresAt;
    if (localExpiry == null) return !serverExpiry.isAfter(instant);

    // Server expiry is authoritative when the two clocks roughly agree. If
    // the device is far ahead/behind, use elapsed client time for proactive
    // rotation and let a failed-precondition from the server settle the real
    // boundary. This prevents a freshly issued lease from being discarded in
    // a tight loop solely because the wall clocks differ.
    final localReceivedAt = localExpiry.subtract(_expectedLeaseDuration);
    final apparentLease = serverExpiry.difference(localReceivedAt);
    final clocksRoughlyAgree =
        apparentLease >= _minimumPlausibleLease &&
        apparentLease <= _maximumPlausibleLease;
    final effectiveExpiry = clocksRoughlyAgree
        ? (serverExpiry.isBefore(localExpiry) ? serverExpiry : localExpiry)
        : localExpiry;
    return !effectiveExpiry.isAfter(instant);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'conversationId': conversationId,
    'messageId': messageId,
    'storagePath': storagePath,
    'type': type.name,
    'expiresAtMillis': expiresAt?.millisecondsSinceEpoch,
    'clientExpiresAtMillis': clientExpiresAt?.millisecondsSinceEpoch,
  };

  factory DirectAttachmentReservationRecord.fromJson(
    Map<Object?, Object?> json,
  ) {
    final conversationId = json['conversationId'];
    final messageId = json['messageId'];
    final storagePath = json['storagePath'];
    final typeName = json['type'];
    final expiresAtMillis = json['expiresAtMillis'];
    final clientExpiresAtMillis = json['clientExpiresAtMillis'];
    final types = MessageType.values.where((item) => item.name == typeName);
    if (conversationId is! String ||
        conversationId.isEmpty ||
        messageId is! String ||
        messageId.isEmpty ||
        storagePath is! String ||
        storagePath.isEmpty ||
        (expiresAtMillis != null && expiresAtMillis is! int) ||
        (clientExpiresAtMillis != null && clientExpiresAtMillis is! int) ||
        types.isEmpty ||
        types.first == MessageType.text) {
      throw const FormatException('Invalid attachment reservation.');
    }
    return DirectAttachmentReservationRecord(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
      type: types.first,
      expiresAt: expiresAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis as int),
      clientExpiresAt: clientExpiresAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(clientExpiresAtMillis as int),
    );
  }
}

class DirectAttachmentOutboxEntry {
  const DirectAttachmentOutboxEntry({
    required this.id,
    required this.fingerprint,
    required this.conversationId,
    required this.type,
    required this.contentType,
    required this.durationSeconds,
    required this.byteLength,
    required this.reserveRequestId,
    required this.finalizeRequestId,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.nextAttemptAt,
    this.lastError,
    this.reservation,
    this.generation,
    this.finalizeAttempted = false,
  });

  final String id;
  final String fingerprint;
  final String conversationId;
  final MessageType type;
  final String contentType;
  final int? durationSeconds;
  final int byteLength;
  final String reserveRequestId;
  final String finalizeRequestId;
  final DirectAttachmentOutboxStatus status;
  final int attempts;
  final DateTime createdAt;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DirectAttachmentReservationRecord? reservation;
  final String? generation;
  final bool finalizeAttempted;

  bool isDue(DateTime now) =>
      status != DirectAttachmentOutboxStatus.failed &&
      (nextAttemptAt == null || !nextAttemptAt!.isAfter(now));

  DirectAttachmentOutboxEntry copyWith({
    String? reserveRequestId,
    String? finalizeRequestId,
    DirectAttachmentOutboxStatus? status,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    String? lastError,
    bool clearLastError = false,
    DirectAttachmentReservationRecord? reservation,
    bool clearReservation = false,
    String? generation,
    bool clearGeneration = false,
    bool? finalizeAttempted,
  }) => DirectAttachmentOutboxEntry(
    id: id,
    fingerprint: fingerprint,
    conversationId: conversationId,
    type: type,
    contentType: contentType,
    durationSeconds: durationSeconds,
    byteLength: byteLength,
    reserveRequestId: reserveRequestId ?? this.reserveRequestId,
    finalizeRequestId: finalizeRequestId ?? this.finalizeRequestId,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    createdAt: createdAt,
    nextAttemptAt: clearNextAttemptAt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    lastError: clearLastError ? null : (lastError ?? this.lastError),
    reservation: clearReservation ? null : (reservation ?? this.reservation),
    generation: clearGeneration ? null : (generation ?? this.generation),
    finalizeAttempted: finalizeAttempted ?? this.finalizeAttempted,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 3,
    'id': id,
    'fingerprint': fingerprint,
    'conversationId': conversationId,
    'type': type.name,
    'contentType': contentType,
    'durationSeconds': durationSeconds,
    'byteLength': byteLength,
    'reserveRequestId': reserveRequestId,
    'finalizeRequestId': finalizeRequestId,
    'status': status.name,
    'attempts': attempts,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'nextAttemptAt': nextAttemptAt?.millisecondsSinceEpoch,
    'lastError': lastError,
    'reservation': reservation?.toJson(),
    'generation': generation,
    'finalizeAttempted': finalizeAttempted,
  };

  factory DirectAttachmentOutboxEntry.fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    final fingerprint = json['fingerprint'];
    final conversationId = json['conversationId'];
    final typeName = json['type'];
    final contentType = json['contentType'];
    final durationSeconds = json['durationSeconds'];
    final byteLength = json['byteLength'];
    final reserveRequestId = json['reserveRequestId'];
    final finalizeRequestId = json['finalizeRequestId'];
    final statusName = json['status'];
    final attempts = json['attempts'];
    final createdAt = json['createdAt'];
    final nextAttemptAt = json['nextAttemptAt'];
    final reservationJson = json['reservation'];
    final generation = json['generation'];
    final finalizeAttempted = json['finalizeAttempted'];
    final types = MessageType.values.where((item) => item.name == typeName);
    final statuses = DirectAttachmentOutboxStatus.values.where(
      (item) => item.name == statusName,
    );
    final schemaVersion = json['schemaVersion'];
    if ((schemaVersion != 1 && schemaVersion != 2 && schemaVersion != 3) ||
        id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(id) ||
        fingerprint is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ||
        conversationId is! String ||
        conversationId.isEmpty ||
        types.isEmpty ||
        types.first == MessageType.text ||
        contentType is! String ||
        contentType.isEmpty ||
        (durationSeconds != null && durationSeconds is! int) ||
        byteLength is! int ||
        byteLength <= 0 ||
        reserveRequestId is! String ||
        reserveRequestId.isEmpty ||
        finalizeRequestId is! String ||
        finalizeRequestId.isEmpty ||
        statuses.isEmpty ||
        attempts is! int ||
        attempts < 0 ||
        createdAt is! int ||
        (nextAttemptAt != null && nextAttemptAt is! int) ||
        (generation != null && generation is! String) ||
        (finalizeAttempted != null && finalizeAttempted is! bool) ||
        (reservationJson != null && reservationJson is! Map)) {
      throw const FormatException('Invalid attachment outbox entry.');
    }
    final reservation = reservationJson == null
        ? null
        : DirectAttachmentReservationRecord.fromJson(
            Map<Object?, Object?>.from(reservationJson as Map),
          );
    if (reservation != null &&
        (reservation.conversationId != conversationId ||
            reservation.type != types.first)) {
      throw const FormatException('Attachment reservation does not match.');
    }
    return DirectAttachmentOutboxEntry(
      id: id,
      fingerprint: fingerprint,
      conversationId: conversationId,
      type: types.first,
      contentType: contentType,
      durationSeconds: durationSeconds as int?,
      byteLength: byteLength,
      reserveRequestId: reserveRequestId,
      finalizeRequestId: finalizeRequestId,
      status: statuses.first,
      attempts: attempts,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      nextAttemptAt: nextAttemptAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextAttemptAt as int),
      lastError: json['lastError'] as String?,
      reservation: reservation,
      generation: generation as String?,
      finalizeAttempted: finalizeAttempted as bool? ?? false,
    );
  }
}

class DirectAttachmentOutboxFullException implements Exception {
  const DirectAttachmentOutboxFullException();

  @override
  String toString() =>
      'Pending media storage is full. Wait for an upload or discard it.';
}

/// Small durable manifest coordinating app-private media payloads.
class DirectAttachmentOutbox {
  DirectAttachmentOutbox({
    required this.ownerId,
    SharedPreferences? preferences,
    DirectAttachmentPayloadStore? payloadStore,
    DateTime Function()? clock,
    String Function()? idFactory,
    this.capacity = 12,
    this.maxPayloadBytes = 64 * 1024 * 1024,
    this.maxAttempts = 8,
  }) : _preferences = preferences,
       payloadStore = payloadStore ?? DirectAttachmentPayloadStore(),
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? _newId,
       accountNamespace = sha256.convert(utf8.encode(ownerId)).toString();

  final String ownerId;
  final String accountNamespace;
  final DirectAttachmentPayloadStore payloadStore;
  final SharedPreferences? _preferences;
  final DateTime Function() _clock;
  final String Function() _idFactory;
  final int capacity;
  final int maxPayloadBytes;
  final int maxAttempts;
  final List<DirectAttachmentOutboxEntry> _entries = [];
  final StreamController<List<DirectAttachmentOutboxEntry>> _changesController =
      StreamController<List<DirectAttachmentOutboxEntry>>.broadcast(sync: true);
  Future<void> _tail = Future<void>.value();
  bool _loaded = false;

  String get _storageKey => 'messages.attachment_outbox.v1.$accountNamespace';
  List<DirectAttachmentOutboxEntry> get entries => List.unmodifiable(_entries);
  Stream<List<DirectAttachmentOutboxEntry>> get changes =>
      _changesController.stream;
  DateTime get now => _clock();

  void _notify() {
    if (!_changesController.isClosed) {
      _changesController.add(List.unmodifiable(_entries));
    }
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final suffix = base64UrlEncode(bytes).replaceAll('=', '');
    return 'attachment_$suffix';
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SharedPreferences> _prefs() async =>
      _preferences ?? SharedPreferences.getInstance();

  Future<void> load() => _serialize(_ensureLoaded);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final restored = <DirectAttachmentOutboxEntry>[];
    final encoded = (await _prefs()).getString(_storageKey);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! List) throw const FormatException('Invalid manifest.');
        for (final item in decoded) {
          if (item is! Map) continue;
          try {
            restored.add(DirectAttachmentOutboxEntry.fromJson(item));
          } catch (_) {
            // One corrupt record cannot strand valid pending uploads.
          }
        }
      } catch (_) {
        await (await _prefs()).remove(_storageKey);
      }
    }

    var changed = false;
    final valid = <DirectAttachmentOutboxEntry>[];
    for (final entry in restored.take(capacity)) {
      if (entry.generation != null ||
          await payloadStore.exists(accountNamespace, entry.id)) {
        valid.add(entry);
      } else {
        changed = true;
      }
    }
    if (valid.length != restored.length) changed = true;
    _entries
      ..clear()
      ..addAll(valid);

    final referenced = _entries.map((entry) => entry.id).toSet();
    for (final key in await payloadStore.keys(accountNamespace)) {
      if (!referenced.contains(key)) {
        await payloadStore.delete(accountNamespace, key);
      }
    }
    if (changed) await _persist();
    // A plugin/storage failure must leave this retryable. Marking the queue
    // loaded before all durability checks finish would strand a manifest in
    // memory after one transient path-provider or Cache Storage error.
    _loaded = true;
    _notify();
  }

  Future<void> _persist() async {
    final value = jsonEncode(_entries.map((entry) => entry.toJson()).toList());
    final saved = await (await _prefs()).setString(_storageKey, value);
    if (!saved) throw StateError('Pending media could not be saved safely.');
  }

  Future<DirectAttachmentOutboxEntry> enqueue({
    required String fingerprint,
    required String conversationId,
    required MessageType type,
    required String contentType,
    required int? durationSeconds,
    required Uint8List bytes,
    required String reserveRequestId,
    required String finalizeRequestId,
  }) => _serialize(() async {
    await _ensureLoaded();
    final existingIndex = _entries.indexWhere(
      (entry) =>
          entry.fingerprint == fingerprint &&
          entry.conversationId == conversationId &&
          entry.type == type,
    );
    if (existingIndex >= 0) {
      final existing = _entries[existingIndex];
      if (existing.contentType != contentType ||
          existing.durationSeconds != durationSeconds ||
          existing.byteLength != bytes.lengthInBytes) {
        throw StateError('Pending media no longer matches its saved upload.');
      }
      final retried = existing.copyWith(
        status: DirectAttachmentOutboxStatus.queued,
        attempts: 0,
        clearNextAttemptAt: true,
        clearLastError: true,
      );
      _entries[existingIndex] = retried;
      try {
        await _persist();
      } catch (_) {
        _entries[existingIndex] = existing;
        rethrow;
      }
      _notify();
      return retried;
    }

    final totalBytes = _entries.fold<int>(
      0,
      (sum, entry) => sum + entry.byteLength,
    );
    if (_entries.length >= capacity ||
        totalBytes + bytes.lengthInBytes > maxPayloadBytes) {
      throw const DirectAttachmentOutboxFullException();
    }
    final entry = DirectAttachmentOutboxEntry(
      id: _idFactory(),
      fingerprint: fingerprint,
      conversationId: conversationId,
      type: type,
      contentType: contentType,
      durationSeconds: durationSeconds,
      byteLength: bytes.lengthInBytes,
      reserveRequestId: reserveRequestId,
      finalizeRequestId: finalizeRequestId,
      status: DirectAttachmentOutboxStatus.queued,
      attempts: 0,
      createdAt: _clock(),
    );
    await payloadStore.write(accountNamespace, entry.id, bytes);
    _entries.add(entry);
    try {
      await _persist();
      _notify();
    } catch (_) {
      _entries.removeLast();
      await payloadStore.delete(accountNamespace, entry.id);
      rethrow;
    }
    return entry;
  });

  DirectAttachmentOutboxEntry? entry(String id) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    return index < 0 ? null : _entries[index];
  }

  List<DirectAttachmentOutboxEntry> due() {
    final now = _clock();
    return _entries.where((entry) => entry.isDue(now)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  bool reservationNeedsRefresh(
    DirectAttachmentOutboxEntry entry, {
    Duration safetyWindow = Duration.zero,
  }) {
    final reservation = entry.reservation;
    return reservation != null &&
        reservation.expiresBefore(_clock().add(safetyWindow));
  }

  Future<DirectAttachmentOutboxEntry?> setReservation(
    String id,
    DirectAttachmentReservationRecord reservation,
  ) => _replace(id, (entry) => entry.copyWith(reservation: reservation));

  Future<DirectAttachmentOutboxEntry?> setGeneration(
    String id,
    String generation,
  ) => _replace(id, (entry) => entry.copyWith(generation: generation));

  Future<DirectAttachmentOutboxEntry?> markFinalizeAttempted(String id) =>
      _replace(id, (entry) => entry.copyWith(finalizeAttempted: true));

  /// Atomically retires an expired server reservation while retaining the
  /// durable bytes. Both idempotency IDs rotate because the new message/path
  /// changes the reserve and finalize inputs.
  Future<DirectAttachmentOutboxEntry?> rotateExpiredReservation(
    String id, {
    required String expectedMessageId,
    required String reserveRequestId,
    required String finalizeRequestId,
    Duration safetyWindow = Duration.zero,
  }) => _serialize(() async {
    await _ensureLoaded();
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return null;
    final current = _entries[index];
    final reservation = current.reservation;
    if (reservation == null || reservation.messageId != expectedMessageId) {
      return current;
    }
    if (!reservationNeedsRefresh(current, safetyWindow: safetyWindow)) {
      return current;
    }
    final rotated = current.copyWith(
      reserveRequestId: reserveRequestId,
      finalizeRequestId: finalizeRequestId,
      status: DirectAttachmentOutboxStatus.queued,
      attempts: 0,
      clearNextAttemptAt: true,
      clearLastError: true,
      clearReservation: true,
      clearGeneration: true,
      finalizeAttempted: false,
    );
    _entries[index] = rotated;
    try {
      await _persist();
    } catch (_) {
      _entries[index] = current;
      rethrow;
    }
    _notify();
    return rotated;
  });

  /// Retires a reservation/request after the server authoritatively rejects
  /// it as invalid or expired. Unlike proactive rotation this deliberately
  /// ignores the device clock, which may be skewed.
  Future<DirectAttachmentOutboxEntry?> rotateRejectedReservation(
    String id, {
    required String expectedReserveRequestId,
    required String reserveRequestId,
    required String finalizeRequestId,
  }) => _serialize(() async {
    await _ensureLoaded();
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return null;
    final current = _entries[index];
    if (current.reserveRequestId != expectedReserveRequestId) return current;
    final rotated = current.copyWith(
      reserveRequestId: reserveRequestId,
      finalizeRequestId: finalizeRequestId,
      status: DirectAttachmentOutboxStatus.queued,
      attempts: 0,
      clearNextAttemptAt: true,
      clearLastError: true,
      clearReservation: true,
      clearGeneration: true,
      finalizeAttempted: false,
    );
    _entries[index] = rotated;
    try {
      await _persist();
    } catch (_) {
      _entries[index] = current;
      rethrow;
    }
    _notify();
    return rotated;
  });

  Future<DirectAttachmentOutboxEntry?> markRetry(String id, Object error) =>
      _replace(id, (entry) {
        final attempts = entry.attempts + 1;
        final failed = attempts >= maxAttempts;
        final exponent = min(attempts - 1, 5);
        return entry.copyWith(
          status: failed
              ? DirectAttachmentOutboxStatus.failed
              : DirectAttachmentOutboxStatus.retrying,
          attempts: attempts,
          nextAttemptAt: failed
              ? null
              : _clock().add(Duration(seconds: 1 << exponent)),
          clearNextAttemptAt: failed,
          lastError: error.runtimeType.toString(),
        );
      });

  Future<DirectAttachmentOutboxEntry?> markFailed(String id, Object error) =>
      _replace(
        id,
        (entry) => entry.copyWith(
          status: DirectAttachmentOutboxStatus.failed,
          attempts: entry.attempts + 1,
          clearNextAttemptAt: true,
          lastError: error.runtimeType.toString(),
        ),
      );

  Future<DirectAttachmentOutboxEntry?> retryNow(String id) =>
      _replace(id, (entry) {
        if (entry.status != DirectAttachmentOutboxStatus.failed) {
          throw StateError('Only a failed attachment can be retried.');
        }
        return entry.copyWith(
          status: DirectAttachmentOutboxStatus.queued,
          attempts: 0,
          clearNextAttemptAt: true,
          clearLastError: true,
        );
      });

  Future<DirectAttachmentOutboxEntry?> _replace(
    String id,
    DirectAttachmentOutboxEntry Function(DirectAttachmentOutboxEntry) update,
  ) => _serialize(() async {
    await _ensureLoaded();
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return null;
    final original = _entries[index];
    final changed = update(original);
    _entries[index] = changed;
    try {
      await _persist();
    } catch (_) {
      _entries[index] = original;
      rethrow;
    }
    _notify();
    return changed;
  });

  Future<void> complete(String id) => _remove(id, requireFailed: false);

  Future<void> discard(String id) => _remove(id, requireFailed: true);

  Future<void> _remove(String id, {required bool requireFailed}) =>
      _serialize(() async {
        await _ensureLoaded();
        final index = _entries.indexWhere((entry) => entry.id == id);
        if (index < 0) return;
        if (requireFailed &&
            _entries[index].status != DirectAttachmentOutboxStatus.failed) {
          throw StateError('Only a failed attachment can be discarded.');
        }
        final removed = _entries.removeAt(index);
        try {
          await _persist();
        } catch (_) {
          _entries.insert(index, removed);
          rethrow;
        }
        _notify();
        await payloadStore.delete(accountNamespace, removed.id);
      });
}

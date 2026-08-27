import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Where a queued direct message stands.
///
/// These are the only three states a caller ever has to reason about.
/// `retrying` is deliberately distinct from `pending`: a message that has
/// never been attempted and a message that failed twice and is waiting out
/// its backoff are the same to the transport and very different to the
/// person who wrote it.
enum OutboxState {
  /// Queued, never attempted, or attempted and still in flight.
  pending,

  /// At least one attempt failed transiently. Waiting for [OutboxEntry.nextAttemptAt]
  /// or for connectivity to return, whichever comes first.
  retrying,

  /// Terminal. Either the server refused it outright, or the retry budget
  /// ran out. Never sent automatically again; the caller decides whether to
  /// retry it by hand or discard it.
  failed,
}

/// One queued direct message.
///
/// [requestId] is the load-bearing field. It is generated ONCE, when the
/// message is first queued, and reused verbatim on every retry. The
/// `sendDirectMessage` callable records it in a server-side idempotency
/// ledger (`functions/messaging/direct_integrity.js`, via `operationIdentity`
/// and `assertLedgerReplay`), so a retry of a request that actually landed —
/// the classic "response lost on the way back" case — is recognised as a
/// replay and returns the original result instead of writing a second
/// message. Regenerating it per attempt would turn every ambiguous failure
/// into a duplicate.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.requestId,
    required this.conversationId,
    required this.recipientId,
    required this.text,
    required this.queuedAt,
    this.replyToMessageId,
    this.state = OutboxState.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  final String id;
  final String requestId;
  final String conversationId;
  final String recipientId;
  final String text;
  final String? replyToMessageId;
  final OutboxState state;
  final int attempts;
  final DateTime queuedAt;
  final DateTime? nextAttemptAt;
  final String? lastError;

  bool get isTerminal => state == OutboxState.failed;

  /// Whether this entry is due for another attempt at [now].
  bool isDue(DateTime now) {
    if (isTerminal) {
      return false;
    }
    final next = nextAttemptAt;
    return next == null || !now.isBefore(next);
  }

  OutboxEntry copyWith({
    OutboxState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
    bool clearNextAttempt = false,
  }) {
    return OutboxEntry(
      id: id,
      requestId: requestId,
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
      replyToMessageId: replyToMessageId,
      queuedAt: queuedAt,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: clearNextAttempt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'requestId': requestId,
    'conversationId': conversationId,
    'recipientId': recipientId,
    'text': text,
    'replyToMessageId': replyToMessageId,
    'state': state.name,
    'attempts': attempts,
    'queuedAt': queuedAt.toIso8601String(),
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'lastError': lastError,
  };

  /// Returns null rather than throwing on a malformed record.
  ///
  /// The queue is persisted across app versions; one unreadable entry must
  /// not make the whole outbox unreadable and strand every other message in
  /// it. Callers drop the nulls.
  static OutboxEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    final requestId = value['requestId'];
    final conversationId = value['conversationId'];
    final recipientId = value['recipientId'];
    final text = value['text'];
    final queuedAt = DateTime.tryParse('${value['queuedAt']}');
    if (id is! String ||
        requestId is! String ||
        conversationId is! String ||
        recipientId is! String ||
        text is! String ||
        queuedAt == null) {
      return null;
    }
    final stateName = value['state'];
    final state = OutboxState.values
        .where((candidate) => candidate.name == stateName)
        .firstOrNull;
    final replyTo = value['replyToMessageId'];
    final lastError = value['lastError'];
    final attempts = value['attempts'];
    return OutboxEntry(
      id: id,
      requestId: requestId,
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
      replyToMessageId: replyTo is String ? replyTo : null,
      state: state ?? OutboxState.pending,
      attempts: attempts is int && attempts >= 0 ? attempts : 0,
      queuedAt: queuedAt,
      nextAttemptAt: DateTime.tryParse('${value['nextAttemptAt']}'),
      lastError: lastError is String ? lastError : null,
    );
  }
}

/// Thrown when the outbox is full.
///
/// The queue is bounded on purpose. An unbounded one turns a long offline
/// stretch into unbounded local storage growth and, worse, into a burst of
/// hundreds of sends the moment connectivity returns — which the server's
/// own rate limiter would then reject, converting a queue into a pile of
/// permanent failures. Refusing the send while the person is still looking
/// at what they typed is the honest failure.
class OutboxFullException implements Exception {
  const OutboxFullException(this.capacity);

  final int capacity;

  @override
  String toString() =>
      'The message queue is full ($capacity messages waiting to send).';
}

/// A bounded, persisted queue of direct messages awaiting the
/// `sendDirectMessage` callable.
///
/// This exists because the callable being unavailable must not mean losing
/// the message, and because writing the message straight to Firestore
/// instead — which this class replaces — bypassed every server-side
/// moderation check (`activeProfile`, `assertNotRestricted`, `assertNotBlocked`
/// and the rate limiter all run INSIDE the callable). The rules now refuse a
/// client-authored message document outright, so this queue is the only way
/// a send survives a failure.
class MessageOutbox {
  MessageOutbox({
    SharedPreferences? preferences,
    String? storageKey = legacyStorageKey,
    this.ownerId,
    Iterable<String> retiredStorageKeys = const <String>[],
    this.capacity = 50,
    this.maxAttempts = 6,
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    DateTime Function()? clock,
    Random? random,
  }) : _preferences = preferences,
       _storageKey = storageKey,
       _retiredStorageKeys = List<String>.unmodifiable(retiredStorageKeys),
       _baseBackoff = baseBackoff,
       _maxBackoff = maxBackoff,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  /// The pre-account-scoping key used by older app builds and by isolated
  /// tests that construct their own outbox.
  static const String legacyStorageKey = 'messages.outbox.v1';

  static final Map<String, MessageOutbox> _sharedByOwner =
      <String, MessageOutbox>{};

  /// The process-wide production queue for one authenticated account.
  ///
  /// Multiple screens create lightweight [MessageService] facades. They must
  /// still observe and mutate one queue, or two chats can overwrite the same
  /// preference value. The owner is part of both the in-memory registry and
  /// the storage key so an account switch can never flush somebody else's
  /// unsent text.
  static MessageOutbox sharedForUser(String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    return _sharedByOwner.putIfAbsent(
      userId,
      () => MessageOutbox(
        storageKey: 'messages.outbox.v2.$userId',
        ownerId: userId,
        // v1 had no sender/owner field. Assigning it to whichever account
        // happens to open the upgraded app would expose one account's draft
        // to another on a shared device, so retire it instead of guessing.
        retiredStorageKeys: const <String>[legacyStorageKey],
      ),
    );
  }

  /// The largest number of messages that may wait at once.
  final int capacity;

  /// How many transient failures an entry survives before becoming [OutboxState.failed].
  final int maxAttempts;

  /// Auth uid that owns this queue. Null only for isolated legacy/test
  /// instances; live app queues are always account-scoped.
  final String? ownerId;

  final SharedPreferences? _preferences;
  final String? _storageKey;
  final List<String> _retiredStorageKeys;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final DateTime Function() _clock;
  final Random _random;

  final List<OutboxEntry> _entries = [];
  final StreamController<List<OutboxEntry>> _changes =
      StreamController<List<OutboxEntry>>.broadcast();
  final StreamController<OutboxEntry> _delivered =
      StreamController<OutboxEntry>.broadcast();

  Future<void>? _loadFuture;
  Future<void> _mutationTail = Future<void>.value();
  bool _deliveryActive = false;

  /// Every queued message, oldest first.
  List<OutboxEntry> get entries => List.unmodifiable(_entries);

  /// Entries a person would want to see marked as not-yet-delivered.
  List<OutboxEntry> get unsent =>
      _entries.where((entry) => !entry.isTerminal).toList(growable: false);

  List<OutboxEntry> get failed =>
      _entries.where((entry) => entry.isTerminal).toList(growable: false);

  /// Emits the full queue whenever it changes, so a chat view can render
  /// pending and failed messages without polling.
  Stream<List<OutboxEntry>> get changes => _changes.stream;

  /// Emits an entry after the server accepted it but before the chat's
  /// Firestore listener necessarily rendered the canonical message.
  ///
  /// HTTPS callable responses and Firestore snapshots travel over separate
  /// streams, so either can arrive first. Keeping this tiny hand-off signal
  /// prevents an optimistic bubble from disappearing for a frame between
  /// the outbox removal and the committed message snapshot.
  Stream<OutboxEntry> get delivered => _delivered.stream;

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) {
      return _preferences;
    }
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      // No platform binding (unit tests, previews). The queue still works
      // in memory for the life of the process; it simply does not survive
      // a restart. Losing persistence is not a reason to lose the send.
      return null;
    }
  }

  /// Loads once and shares the exact in-flight Future with every caller.
  ///
  /// Setting a boolean before awaiting SharedPreferences lets an enqueue race
  /// ahead, only to be cleared when the older load completes. Sharing the
  /// Future makes every first mutation wait for the same completed load.
  Future<void> load() => _loadFuture ??= _loadFromPreferences();

  Future<void> _loadFromPreferences() async {
    final prefs = await _prefs();
    final storageKey = _storageKey;
    if (prefs == null || storageKey == null) {
      return;
    }
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      await _retireUnscopedStorage(prefs);
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      _entries
        ..clear()
        ..addAll(
          decoded
              .map(OutboxEntry.fromJson)
              .whereType<OutboxEntry>()
              .take(capacity),
        );
      _notify();
    } catch (_) {
      // A corrupt queue is dropped rather than propagated. It is a cache of
      // unsent work, not a source of truth.
    } finally {
      await _retireUnscopedStorage(prefs);
    }
  }

  Future<void> _retireUnscopedStorage(SharedPreferences prefs) async {
    for (final key in _retiredStorageKeys) {
      if (key == _storageKey) continue;
      try {
        await prefs.remove(key);
      } catch (_) {
        // Privacy cleanup is retried on the next process start. Failure to
        // remove a retired key must not make the scoped queue unusable.
      }
    }
  }

  Future<void> _persist() async {
    final storageKey = _storageKey;
    if (storageKey == null) {
      return;
    }
    final prefs = await _prefs();
    if (prefs == null) {
      return;
    }
    try {
      await prefs.setString(
        storageKey,
        jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Best effort: an unwritable preference store must not fail the send.
    }
  }

  Future<T> _serialize<T>(Future<T> Function() mutation) {
    final result = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        result.complete(await mutation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(entries);
    }
  }

  String _newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${_clock().millisecondsSinceEpoch.toRadixString(16)}-$hex';
  }

  /// Queues a message and returns its entry.
  ///
  /// Throws [OutboxFullException] when [capacity] unsent messages are already
  /// waiting. Terminal ([OutboxState.failed]) entries are evicted oldest-first
  /// to make room before the cap is enforced, so a pile of old failures never
  /// blocks a fresh send.
  Future<OutboxEntry> enqueue({
    required String conversationId,
    required String recipientId,
    required String text,
    String? replyToMessageId,
  }) => _serialize(() async {
    await load();

    if (_entries.length >= capacity) {
      final firstFailed = _entries.indexWhere((entry) => entry.isTerminal);
      if (firstFailed >= 0) {
        _entries.removeAt(firstFailed);
      }
    }
    if (_entries.length >= capacity) {
      throw OutboxFullException(capacity);
    }

    final entry = OutboxEntry(
      id: _newId(),
      requestId: _newId(),
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
      replyToMessageId: replyToMessageId,
      queuedAt: _clock(),
    );
    _entries.add(entry);
    await _persist();
    _notify();
    return entry;
  });

  int _indexOf(String id) => _entries.indexWhere((entry) => entry.id == id);

  /// Removes a delivered message from the queue.
  Future<void> markSent(String id) => _serialize(() async {
    await load();
    final index = _indexOf(id);
    if (index < 0) {
      return;
    }
    final delivered = _entries.removeAt(index);
    await _persist();
    if (!_delivered.isClosed) {
      _delivered.add(delivered);
    }
    _notify();
  });

  /// Records a transient failure and schedules the next attempt.
  ///
  /// Returns the updated entry, which becomes [OutboxState.failed] once
  /// [maxAttempts] is reached — a retry loop that never gives up is how a
  /// permanently-broken send becomes a permanent battery and quota drain.
  Future<OutboxEntry?> markRetry(String id, String error) =>
      _serialize(() async {
        await load();
        final index = _indexOf(id);
        if (index < 0) {
          return null;
        }
        final current = _entries[index];
        final attempts = current.attempts + 1;
        final OutboxEntry updated;
        if (attempts >= maxAttempts) {
          updated = current.copyWith(
            state: OutboxState.failed,
            attempts: attempts,
            lastError: error,
            clearNextAttempt: true,
          );
        } else {
          updated = current.copyWith(
            state: OutboxState.retrying,
            attempts: attempts,
            lastError: error,
            nextAttemptAt: _clock().add(_backoffFor(attempts)),
          );
        }
        _entries[index] = updated;
        await _persist();
        _notify();
        return updated;
      });

  /// Records a refusal the server will give again for the same input.
  Future<OutboxEntry?> markFailed(String id, String error) =>
      _serialize(() async {
        await load();
        final index = _indexOf(id);
        if (index < 0) {
          return null;
        }
        final updated = _entries[index].copyWith(
          state: OutboxState.failed,
          lastError: error,
          clearNextAttempt: true,
        );
        _entries[index] = updated;
        await _persist();
        _notify();
        return updated;
      });

  /// Moves a failed entry back into the queue at the caller's request.
  ///
  /// The attempt counter resets because this is a deliberate human decision,
  /// not the automatic loop; the requestId does NOT change, so a manual retry
  /// is still deduplicated against an attempt that secretly succeeded.
  Future<OutboxEntry?> retryNow(String id) => _serialize(() async {
    await load();
    final index = _indexOf(id);
    if (index < 0) {
      return null;
    }
    final updated = _entries[index].copyWith(
      state: OutboxState.pending,
      attempts: 0,
      clearNextAttempt: true,
    );
    _entries[index] = updated;
    await _persist();
    _notify();
    return updated;
  });

  Future<void> discard(String id) => _serialize(() async {
    await load();
    final index = _indexOf(id);
    if (index < 0) {
      return;
    }
    _entries.removeAt(index);
    await _persist();
    _notify();
  });

  /// Claims the delivery loop shared by every service facade for this queue.
  bool tryBeginDelivery() {
    if (_deliveryActive) return false;
    _deliveryActive = true;
    return true;
  }

  void endDelivery() {
    _deliveryActive = false;
  }

  /// Entries due for another attempt, oldest first.
  ///
  /// Ordering matters: messages must arrive in the order they were written.
  List<OutboxEntry> due() {
    final now = _clock();
    final blockedConversations = <String>{};
    final due = <OutboxEntry>[];
    for (final entry in _entries) {
      if (entry.isTerminal) {
        // A terminal entry needs a human decision and must not freeze every
        // later send forever. It is visibly retained, but no longer belongs
        // to the automatic delivery order.
        continue;
      }
      if (blockedConversations.contains(entry.conversationId)) {
        continue;
      }
      if (!entry.isDue(now)) {
        // Preserve order within one conversation. A later message in the
        // same chat must never overtake an older one during its backoff, but
        // an unrelated chat remains free to drain.
        blockedConversations.add(entry.conversationId);
        continue;
      }
      due.add(entry);
    }
    return due;
  }

  Duration _backoffFor(int attempts) {
    // A configured zero means zero — the next attempt is due immediately.
    // Rounding it up to a millisecond instead would make "no backoff"
    // untestable, because a retry issued in the same tick would never be
    // due.
    if (_baseBackoff == Duration.zero || _maxBackoff == Duration.zero) {
      return Duration.zero;
    }
    // Exponential with full jitter. Without the jitter every client that
    // lost connectivity at the same moment retries at the same moment.
    final exponent = min(attempts, 10);
    final ceiling = min(
      _baseBackoff.inMilliseconds * pow(2, exponent).toInt(),
      _maxBackoff.inMilliseconds,
    );
    return Duration(milliseconds: _random.nextInt(max(ceiling, 1)) + 1);
  }

  Future<void> clear() => _serialize(() async {
    await load();
    _entries.clear();
    await _persist();
    _notify();
  });

  Future<void> dispose() async {
    await _mutationTail;
    await _changes.close();
    await _delivered.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

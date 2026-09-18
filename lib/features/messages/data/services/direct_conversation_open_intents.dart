import 'dart:math';

/// One person's attempt to open a chat with one other person.
///
/// The [requestId] is the load-bearing field, exactly as it is in
/// `OutboxEntry`: `openDirectConversation` runs `beginAttemptPreflight`
/// (`functions/messaging/direct_integrity.js`) in its OWN transaction before
/// the main one, and that preflight `transaction.create`s a row in
/// `integrityPreflightLedgers` and COMMITS it — even when the main
/// transaction then rolls back. A fresh request id per attempt therefore
/// leaks one ledger row per failure and makes a lost acknowledgement
/// impossible to recognise as a replay. One intent keeps one id until it
/// succeeds.
class DirectConversationOpenIntent {
  DirectConversationOpenIntent({required this.requestId});

  final String requestId;

  /// How many attempts this intent has already spent.
  int attempts = 0;

  /// When the next attempt may reach the network.
  DateTime? nextAttemptAt;

  /// The failure the last attempt produced, replayed verbatim to a caller
  /// that arrives inside the backoff window.
  Object? lastError;
  StackTrace? lastStackTrace;
}

/// Thrown by [DirectConversationOpenIntents.beginAttempt] when the previous
/// failure has not yet cooled down and no previous error was recorded.
///
/// In practice the recorded error is replayed instead; this exists so the
/// "inside the window" path can never silently fall through to the network.
class DirectConversationOpenThrottled implements Exception {
  const DirectConversationOpenThrottled();

  @override
  String toString() => 'Opening this conversation was attempted very recently.';
}

/// Process-wide, account-scoped store of in-flight chat-open intents.
///
/// Every screen that can start a chat builds its own lightweight
/// `MessageService` facade — `messages_screen.dart`, `friends_screen.dart`,
/// `friend_profile_screen.dart`, `invite_to_room_sheet.dart` and
/// `profile_preview_sheet.dart` — so the store has to outlive any one of
/// them or "the same intent" would mean "the same screen". Built on the
/// same static registry pattern as `MessageOutbox.sharedForUser`.
class DirectConversationOpenIntents {
  DirectConversationOpenIntents({
    DateTime Function()? clock,
    Random? random,
    Duration baseBackoff = const Duration(seconds: 1),
    Duration maxBackoff = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       _baseBackoff = baseBackoff,
       _maxBackoff = maxBackoff;

  static final Map<String, DirectConversationOpenIntents> _sharedByOwner =
      <String, DirectConversationOpenIntents>{};

  /// The shared store for one authenticated account.
  static DirectConversationOpenIntents sharedForUser(String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    return _sharedByOwner.putIfAbsent(
      userId,
      DirectConversationOpenIntents.new,
    );
  }

  /// Drops everything this account was in the middle of.
  ///
  /// An intent names a person the account tried to message, so it is local
  /// personal data and leaves with the session.
  static void forgetUser(String userId) {
    _sharedByOwner.remove(userId);
  }

  final DateTime Function() _clock;
  final Random _random;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final Map<String, DirectConversationOpenIntent> _intents =
      <String, DirectConversationOpenIntent>{};

  /// The live intent for [targetUserId], or null when none is pending.
  DirectConversationOpenIntent? intentFor(String targetUserId) =>
      _intents[targetUserId];

  /// Returns the intent whose [DirectConversationOpenIntent.requestId] this
  /// attempt must send.
  ///
  /// Throws the previous failure — with its original stack — when the
  /// caller is still inside the backoff window, WITHOUT touching the
  /// network. That is the half of RC-9 the stable id cannot fix on its own:
  /// `consumeRateLimit` runs unconditionally once `assertLedgerReplay`
  /// finds no committed result, so twelve impatient taps produce twelve
  /// quota events and then a 429 no matter how stable the id is.
  DirectConversationOpenIntent beginAttempt(
    String targetUserId, {
    required String Function() newRequestId,
  }) {
    final existing = _intents[targetUserId];
    if (existing == null) {
      final created = DirectConversationOpenIntent(requestId: newRequestId());
      _intents[targetUserId] = created;
      return created;
    }
    final next = existing.nextAttemptAt;
    if (next != null && _clock().isBefore(next)) {
      final error = existing.lastError;
      final stackTrace = existing.lastStackTrace;
      if (error == null) throw const DirectConversationOpenThrottled();
      if (stackTrace == null) throw error;
      Error.throwWithStackTrace(error, stackTrace);
    }
    return existing;
  }

  /// The server committed (or replayed) this intent: nothing is left to
  /// replay, so the next open for the same person starts fresh.
  void recordSuccess(String targetUserId) {
    _intents.remove(targetUserId);
  }

  /// Records a failed attempt and schedules when another may be made.
  void recordFailure(
    String targetUserId,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    final intent = _intents[targetUserId];
    if (intent == null) return;
    intent.attempts += 1;
    intent.lastError = error;
    intent.lastStackTrace = stackTrace;
    intent.nextAttemptAt = _clock().add(_backoffFor(intent.attempts));
  }

  /// Exponential with full jitter, mirroring `MessageOutbox._backoffFor`
  /// rather than inventing a second backoff shape for the same problem.
  Duration _backoffFor(int attempts) {
    if (_baseBackoff == Duration.zero || _maxBackoff == Duration.zero) {
      return Duration.zero;
    }
    final exponent = min(attempts, 10);
    final ceiling = min(
      _baseBackoff.inMilliseconds * pow(2, exponent).toInt(),
      _maxBackoff.inMilliseconds,
    );
    return Duration(milliseconds: _random.nextInt(max(ceiling, 1)) + 1);
  }
}

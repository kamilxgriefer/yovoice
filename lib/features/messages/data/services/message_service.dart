import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

class ChatPresence {
  const ChatPresence({required this.isOnline, required this.lastSeen});

  final bool isOnline;
  final DateTime? lastSeen;
}

class _DirectAttachmentReservation {
  const _DirectAttachmentReservation({
    required this.conversationId,
    required this.messageId,
    required this.storagePath,
    required this.type,
    required this.expiresAt,
  });

  final String conversationId;
  final String messageId;
  final String storagePath;
  final MessageType type;
  final DateTime expiresAt;

  factory _DirectAttachmentReservation.fromResponse(
    Map<Object?, Object?> data,
  ) {
    final conversationId = data['conversationId'];
    final messageId = data['messageId'];
    final storagePath = data['storagePath'];
    final typeValue = data['type'];
    final expiresAtMillis = data['expiresAtMillis'];
    final type = MessageType.values.where((item) => item.name == typeValue);
    if (conversationId is! String ||
        conversationId.isEmpty ||
        messageId is! String ||
        messageId.isEmpty ||
        storagePath is! String ||
        storagePath.isEmpty ||
        expiresAtMillis is! int ||
        type.isEmpty ||
        type.first == MessageType.text) {
      throw StateError('Malformed attachment reservation from YO Voice.');
    }
    return _DirectAttachmentReservation(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
      type: type.first,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
    );
  }
}

class MessageService {
  static const int _maxReadReceiptPagesPerPass = 100;
  static const Duration _directAttachmentLeaseDuration = Duration(minutes: 15);

  /// The single production facade. Screens share its connectivity listener,
  /// retry timers and account-scoped outbox; tests keep using the injectable
  /// constructor below.
  static final MessageService live = MessageService();

  MessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    // Compatibility injection for existing previews/tests. Notification
    // delivery is now derived by the backend from the committed message.
    NotificationService? notificationService,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    MessageOutbox? outbox,
    DirectAttachmentOutbox? attachmentOutbox,
    DirectAttachmentPayloadStore? attachmentPayloadStore,
    Connectivity? connectivity,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _legacyNotificationService = notificationService,
       _functionsOverride = functions,
       _storageOverride = storage,
       _outboxOverride = outbox,
       _attachmentOutboxOverride = attachmentOutbox,
       _attachmentPayloadStoreOverride = attachmentPayloadStore,
       _connectivityOverride = connectivity,
       _useSharedLiveOutbox =
           firestore == null &&
           auth == null &&
           notificationService == null &&
           functions == null &&
           storage == null &&
           outbox == null &&
           attachmentOutbox == null &&
           attachmentPayloadStore == null &&
           connectivity == null;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService? _legacyNotificationService;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage? _storageOverride;
  final MessageOutbox? _outboxOverride;
  final DirectAttachmentOutbox? _attachmentOutboxOverride;
  final DirectAttachmentPayloadStore? _attachmentPayloadStoreOverride;
  final Connectivity? _connectivityOverride;
  final bool _useSharedLiveOutbox;
  MessageOutbox? _outbox;
  String? _outboxOwnerId;
  StreamSubscription<Object?>? _connectivitySubscription;
  final Map<MessageOutbox, Timer> _drainTimers = <MessageOutbox, Timer>{};
  final Map<DirectAttachmentOutbox, Timer> _attachmentDrainTimers =
      <DirectAttachmentOutbox, Timer>{};
  final Map<String, Future<void>> _attachmentDeliveries = {};
  DirectAttachmentOutbox? _attachmentOutbox;
  String? _attachmentOutboxOwnerId;

  /// The queue of messages written but not yet accepted by the server.
  ///
  /// Exposed so a chat view can render pending, retrying and failed messages
  /// — the whole point of queueing rather than dropping is that someone can
  /// see what has not gone out yet.
  MessageOutbox get outbox {
    final override = _outboxOverride;
    if (override != null) return override;

    final ownerId = _auth.currentUser?.uid;
    if (_useSharedLiveOutbox && ownerId != null && ownerId.isNotEmpty) {
      return MessageOutbox.sharedForUser(ownerId);
    }

    // Injection-backed services stay isolated for deterministic tests and
    // previews, but still rotate queues when their fake/live auth identity
    // changes. Signed-out queues are memory-only.
    if (_outbox == null || _outboxOwnerId != ownerId) {
      _outboxOwnerId = ownerId;
      _outbox = MessageOutbox(
        storageKey: ownerId == null ? null : 'messages.outbox.v2.$ownerId',
        ownerId: ownerId,
      );
    }
    return _outbox!;
  }

  /// Account-scoped durable queue for photo and voice-message payloads.
  DirectAttachmentOutbox get attachmentOutbox {
    final override = _attachmentOutboxOverride;
    if (override != null) return override;
    final ownerId = _currentUserId;
    if (_attachmentOutbox == null || _attachmentOutboxOwnerId != ownerId) {
      final previousQueue = _attachmentOutbox;
      if (previousQueue != null) {
        _attachmentDrainTimers.remove(previousQueue)?.cancel();
      }
      _attachmentOutboxOwnerId = ownerId;
      _attachmentOutbox = DirectAttachmentOutbox(
        ownerId: ownerId,
        payloadStore: _attachmentPayloadStoreOverride,
      );
    }
    return _attachmentOutbox!;
  }

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  FirebaseFunctions? get _functions {
    if (_functionsOverride != null) {
      return _functionsOverride;
    }

    try {
      return FirebaseFunctions.instanceFor(region: 'europe-west1');
    } on FirebaseException catch (error) {
      if (error.code == 'no-app') {
        return null;
      }
      rethrow;
    }
  }

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  CollectionReference<Map<String, dynamic>> get _socialPresence =>
      _firestore.collection('socialPresence');

  String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }

  /// Whether the callable is genuinely ABSENT — as opposed to present and
  /// refusing.
  ///
  /// `not-found` used to count here and must never count again. The server
  /// itself throws it, routinely, as a legitimate refusal:
  /// `functions/integrity/guards.js:157` (`activeProfile` — "Your profile
  /// does not exist."), `functions/messaging/direct_integrity.js:83`
  /// (`conversationParticipants` — "The direct conversation does not
  /// exist.") and `functions/messaging/direct_integrity.js:223`
  /// (`validateMessage`). A user whose `users/{uid}` document was missing
  /// therefore made every callable answer `not-found`, which the client
  /// misread as "not deployed" and bypassed — silently — `assertNotBlocked`,
  /// `assertNotRestricted` and the rate limits, across send, edit, delete,
  /// react, mark-read and typing.
  ///
  /// The ambiguity is irreducible at the wire: an undeployed callable is
  /// also HTTP 404 -> NOT_FOUND, so `not-found` cannot carry deployment
  /// meaning in either direction. `unimplemented` (HTTP 501) is thrown by
  /// no handler in this codebase and stays a safe absence signal. See
  /// ADR-062.
  bool _isCallableUnavailable(Object error) {
    if (error is FirebaseException && error.code == 'no-app') {
      return true;
    }
    return error is FirebaseFunctionsException && error.code == 'unimplemented';
  }

  bool _isAmbiguousTransportFailure(Object error) =>
      error is FirebaseFunctionsException &&
      const <String>{
        'aborted',
        'cancelled',
        'deadline-exceeded',
        'internal',
        'unknown',
        'unavailable',
      }.contains(error.code);

  bool get _preferLegacyBehaviour => _legacyNotificationService != null;

  Future<bool> _tryCallable(String name, Map<String, Object?> data) async {
    if (_preferLegacyBehaviour) {
      return false;
    }

    final functions = _functions;

    if (functions == null) {
      return false;
    }

    try {
      await functions.httpsCallable(name).call(data);
      return true;
    } catch (error) {
      if (_isCallableUnavailable(error)) {
        return false;
      }
      rethrow;
    }
  }

  String get _currentUserId {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in to use messages.');
    }

    return user.uid;
  }

  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    final currentUserId = _currentUserId;

    return _conversations
        .where('participantIds', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map(Conversation.fromFirestore)
              .where(
                (conversation) =>
                    includeArchived ||
                    !conversation.isArchivedFor(currentUserId),
              )
              .toList(growable: false);

          items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return items;
        });
  }

  Stream<List<Message>> watchMessages(String conversationId) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(250)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(Message.fromFirestore).toList(growable: false),
        );
  }

  Stream<ChatPresence> watchUserPresence(String userId) {
    // Presence is intentionally not part of the public profile. The
    // server-owned socialPresence projection is readable only for self and
    // canonical friends; a non-friend chat therefore fails closed to the
    // StreamBuilder's offline state instead of exposing a private user doc.
    return _socialPresence.doc(userId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final lastSeenValue = data['lastSeen'];

      return ChatPresence(
        isOnline: data['isOnline'] as bool? ?? false,
        lastSeen: lastSeenValue is Timestamp ? lastSeenValue.toDate() : null,
      );
    });
  }

  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) {
    return Stream<bool>.multi((controller) {
      Timer? expiryTimer;
      late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
      subscription;

      subscription = _conversations
          .doc(conversationId)
          .snapshots()
          .listen(
            (snapshot) {
              expiryTimer?.cancel();
              final typing = snapshot.data()?['typing'] as Map?;
              final value = typing?[otherUserId] as Map?;
              final isTyping = value?['isTyping'] as bool? ?? false;
              final updatedAt = value?['updatedAt'];

              if (!isTyping || updatedAt is! Timestamp) {
                controller.add(false);
                return;
              }

              final remaining =
                  const Duration(seconds: 8) -
                  DateTime.now().difference(updatedAt.toDate());
              if (remaining <= Duration.zero) {
                controller.add(false);
                return;
              }

              controller.add(true);
              // Firestore will not emit another snapshot merely because time
              // passed. Expire the indicator locally instead of leaving someone
              // "typing" forever after a client disappears.
              expiryTimer = Timer(remaining, () => controller.add(false));
            },
            onError: controller.addError,
            onDone: () {
              expiryTimer?.cancel();
              controller.close();
            },
          );
      controller.onCancel = () {
        expiryTimer?.cancel();
        unawaited(subscription.cancel());
      };
    }).distinct();
  }

  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {
    final called = await _tryCallable('setDirectTyping', {
      'conversationId': conversationId,
      'isTyping': isTyping,
      'requestId': _newRequestId(),
    });

    if (called) return;

    final userId = _currentUserId;
    await _conversations.doc(conversationId).set({
      'typing': {
        userId: {
          'isTyping': isTyping,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  Future<String> openOrCreateConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String otherEmail,
    required String otherPhotoUrl,
  }) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be signed in to start a conversation.');
    }

    if (otherUserId == currentUser.uid) {
      throw ArgumentError('You cannot start a conversation with yourself.');
    }

    // `openDirectConversation` is the ONLY production path, and when it
    // answers — success OR failure — its answer stands. There is
    // deliberately no `_isCallableUnavailable` escape here: unlike a
    // message, a conversation root is not something the client is entitled
    // to author, so "the server said no" can never mean "write it
    // yourself". See ADR-062.
    final functions = _preferLegacyBehaviour ? null : _functions;

    if (functions != null) {
      final callable = functions.httpsCallable('openDirectConversation');
      final response = await callable.call<Map<Object?, Object?>>({
        'targetUserId': otherUserId,
        'requestId': _newRequestId(),
      });
      final conversationId = response.data['conversationId'];

      if (conversationId is String && conversationId.isNotEmpty) {
        return conversationId;
      }

      throw StateError('Malformed server response for opening conversation.');
    }

    // Reached only when there is no Firebase app at all (unit tests,
    // previews) or under the legacy notification harness.
    //
    // This transaction writes a conversation root the client is NOT
    // entitled to author, and it may only ever run where no server exists.
    // Against a real backend it is worse than useless: the client cannot
    // write `directConversationPairs/{pairKey}` — that collection has no
    // rules match block, on purpose — so the pair guard is missing, and
    // `validateConversation` (direct_integrity.js:125) then fails this
    // root with `data-loss`/"The canonical conversation is missing." on
    // EVERY subsequent server call, permanently. The document is also
    // non-canonical by key set (12 keys against the server's 18: no
    // `pairKey`, `schemaVersion`, `readSequences`, `participantEmails`,
    // `lastMessageId`, `lastMessageSequence`). Legacy roots already in the
    // wild are healed in place by `migrateDirectIntegrityConversation`,
    // never forked — which is why nothing here tries to adopt one.
    final conversationId = buildConversationId(currentUser.uid, otherUserId);
    final reference = _conversations.doc(conversationId);
    final now = Timestamp.now();

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);

      if (existing.exists) {
        transaction.update(reference, {
          'archivedBy': FieldValue.arrayRemove([currentUser.uid]),
        });
        return;
      }

      transaction.set(reference, {
        'participantIds': [currentUser.uid, otherUserId],
        'participantNames': {
          currentUser.uid: _currentDisplayName(
            currentUser.displayName,
            currentUser.email,
          ),
          otherUserId: otherDisplayName.trim().isEmpty
              ? 'YO Voice user'
              : otherDisplayName.trim(),
        },
        'participantPhotoUrls': {
          currentUser.uid: currentUser.photoURL ?? '',
          otherUserId: otherPhotoUrl,
        },
        'unreadCounts': {currentUser.uid: 0, otherUserId: 0},
        'typing': <String, dynamic>{},
        'archivedBy': <String>[],
        'mutedBy': <String>[],
        'lastMessage': '',
        'lastMessageType': MessageType.text.name,
        'lastMessageSenderId': '',
        'createdAt': now,
        'updatedAt': now,
      });
    });

    return conversationId;
  }

  /// Sends a direct message through `sendDirectMessage`, queueing it in the
  /// local outbox if the callable cannot be reached.
  ///
  /// There is deliberately NO client-direct Firestore write here, and the
  /// rules refuse one (`conversations/{id}/messages/{id}` is
  /// `allow create: if false`). Every moderation check that matters —
  /// `activeProfile`, `assertNotRestricted`, `assertNotBlocked`, the
  /// recipient's `messagePrivacy` and the rate limiter — runs inside the
  /// callable. A fallback that wrote the message itself did not merely skip
  /// one check; it skipped all of them, which is how a banned or
  /// communication-muted account kept full direct messaging (ADR-105).
  ///
  /// "The callable is unavailable" must not mean losing what someone wrote,
  /// so the message is queued FIRST and only then attempted. A transient
  /// failure leaves it in the outbox to be retried when connectivity
  /// returns; a refusal marks it failed and rethrows so the person finds
  /// out. Either way the text survives the failure.
  Future<void> sendTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return;
    }

    // Queued before the first attempt, not after a failure: a process death
    // mid-send would otherwise lose the message in the one window where it
    // exists nowhere but memory.
    final queue = outbox;
    final entry = await queue.enqueue(
      conversationId: conversationId,
      recipientId: recipientId,
      text: trimmed,
      replyToMessageId: replyTo?.id,
    );

    _listenForConnectivity();
    await _attemptDelivery(entry, queue: queue, rethrowRefusal: true);
  }

  /// Persists a text message locally and returns as soon as it is safely in
  /// the outbox. Delivery continues in the strict, oldest-first drain.
  ///
  /// ChatScreen uses this path so a slow or cold callable never freezes the
  /// composer. [sendTextMessage] remains the await-the-first-attempt API for
  /// callers and tests that explicitly need the server outcome.
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Message cannot be empty.');
    }

    final queue = outbox;
    final entry = await queue.enqueue(
      conversationId: conversationId,
      recipientId: recipientId,
      text: trimmed,
      replyToMessageId: replyTo?.id,
    );
    _listenForConnectivity();
    unawaited(_flushOutbox(queue));
    return entry;
  }

  /// Mirrors the backend's deterministic direct-message id. It lets the chat
  /// replace an optimistic outbox bubble with the exact committed document,
  /// without guessing by text or timestamp (both can legitimately repeat).
  String messageIdForQueuedText(OutboxEntry entry, {String? senderId}) {
    final actorId = senderId ?? _currentUserId;
    final body = <String>[
      'direct-message',
      entry.conversationId,
      actorId,
      entry.requestId,
    ].join('\u0000');
    final value = sha256.convert(utf8.encode(body)).toString();
    return 'm_${value.substring(0, 40)}';
  }

  /// Attempts one outbox entry.
  ///
  /// Returns true when the message is gone from the queue because it landed.
  /// `rethrowRefusal` is set for the interactive send so a refusal surfaces
  /// immediately in the UI, and cleared for background draining, where there
  /// is no call site to throw at.
  Future<bool> _attemptDelivery(
    OutboxEntry entry, {
    required MessageOutbox queue,
    bool rethrowRefusal = false,
  }) async {
    final ownerId = queue.ownerId;
    if (ownerId != null && _auth.currentUser?.uid != ownerId) {
      // The account changed after this queue was captured. Keep the entry in
      // its owner's queue; never submit it under the new Firebase session.
      return false;
    }
    final functions = _functions;

    if (functions == null) {
      // No Firebase app at all. Transient by definition — the queue waits.
      await queue.markRetry(entry.id, 'The messaging service is unavailable.');
      return false;
    }

    try {
      await functions.httpsCallable('sendDirectMessage').call({
        'conversationId': entry.conversationId,
        'text': entry.text,
        // The SAME requestId on every attempt. The callable's idempotency
        // ledger keys on it, so a retry of a request that actually landed is
        // recognised as a replay instead of writing a second message.
        'requestId': entry.requestId,
        'replyToMessageId': entry.replyToMessageId,
      });
      await queue.markSent(entry.id);
      return true;
    } catch (error) {
      if (_isRetryable(error)) {
        await queue.markRetry(entry.id, _describeError(error));
        _scheduleDrain(queue);
        return false;
      }
      await queue.markFailed(entry.id, _describeError(error));
      if (rethrowRefusal) {
        rethrow;
      }
      return false;
    }
  }

  /// Whether a failure is worth trying again with identical input.
  ///
  /// The default is NOT to retry. A refusal repeated on a timer is just a
  /// slower refusal, and for the moderation refusals this path exists to
  /// honour — blocked, restricted, privacy — retrying would be an attempt to
  /// wear the server down. Only genuine transport failures and a genuinely
  /// absent callable qualify.
  bool _isRetryable(Object error) {
    if (_isCallableUnavailable(error)) {
      return true;
    }
    if (error is FirebaseFunctionsException) {
      return const {
        'unavailable',
        'deadline-exceeded',
        'internal',
        'aborted',
        'cancelled',
      }.contains(error.code);
    }
    // A raw socket/DNS failure never reaches a FirebaseFunctionsException.
    return error is TimeoutException;
  }

  String _describeError(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message;
      return message == null || message.isEmpty ? error.code : message;
    }
    return error.toString();
  }

  /// Subscribes to connectivity changes so a queue drains the moment the
  /// network comes back, rather than on the next thing the person types.
  ///
  /// Idempotent and lazy: a service that never sends never subscribes, and
  /// previews with no platform channels degrade to timer-driven retries
  /// rather than throwing.
  void _listenForConnectivity() {
    if (_connectivitySubscription != null) {
      return;
    }
    // A platform EventChannel throws from inside its own onListen when no
    // binding exists, which lands ASYNCHRONOUSLY and escapes the try below.
    // Unit tests and previews run without one, so check before subscribing
    // rather than trying to catch it afterwards.
    if (_connectivityOverride == null && !_platformChannelsAvailable) {
      return;
    }
    try {
      final connectivity = _connectivityOverride ?? Connectivity();
      _connectivitySubscription = connectivity.onConnectivityChanged.listen((
        result,
      ) {
        final offline = result.isEmpty || result.every(_isNoNetwork);
        if (!offline) {
          unawaited(flushOutbox());
          unawaited(flushAttachmentOutbox());
        }
      }, onError: (_) {});
    } catch (_) {
      // No connectivity plugin available (unit tests, previews). The backoff
      // timer still drives retries; this listener only makes them prompt.
    }
  }

  bool _isNoNetwork(Object? result) =>
      result is ConnectivityResult && result == ConnectivityResult.none;

  /// Whether platform channels can be used at all.
  ///
  /// False in plain unit tests and previews. The outbox still retries on its
  /// backoff timer there; only the prompt connectivity-triggered drain is
  /// unavailable.
  static bool get _platformChannelsAvailable {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleDrain(MessageOutbox queue) {
    if (_drainTimers[queue]?.isActive ?? false) {
      return;
    }
    final pending = queue.unsent;
    if (pending.isEmpty) {
      return;
    }
    final now = DateTime.now();
    // Wake for the soonest due entry, with a floor so a burst of failures
    // cannot spin the timer.
    var delay = const Duration(seconds: 30);
    for (final entry in pending) {
      final next = entry.nextAttemptAt;
      if (next == null) {
        delay = const Duration(seconds: 1);
        break;
      }
      final until = next.difference(now);
      if (until < delay) {
        delay = until;
      }
    }
    if (delay < const Duration(seconds: 1)) {
      delay = const Duration(seconds: 1);
    }
    _drainTimers[queue] = Timer(delay, () {
      _drainTimers.remove(queue);
      unawaited(_flushOutbox(queue));
    });
  }

  /// Attempts every queued message that is due, oldest first.
  ///
  /// Ordering is strict and sequential: direct messages must arrive in the
  /// order they were written, so one entry's failure stops the drain rather
  /// than letting a later message overtake an earlier one.
  Future<void> flushOutbox() => _flushOutbox(outbox);

  /// Restores and resumes persisted work when the authenticated shell starts.
  /// No new message is required to wake a queue left by an earlier process.
  Future<void> resumeOutbox() async {
    final queue = outbox;
    await queue.load();
    final mediaQueue = attachmentOutbox;
    await mediaQueue.load();
    _listenForConnectivity();
    await _flushOutbox(queue);
    await _flushAttachmentOutbox(mediaQueue);
  }

  Future<void> _flushOutbox(MessageOutbox queue) async {
    final ownerId = queue.ownerId;
    if (ownerId != null && _auth.currentUser?.uid != ownerId) {
      return;
    }
    if (!queue.tryBeginDelivery()) return;
    try {
      await queue.load();
      final blockedThisPass = <String>{};
      while (true) {
        if (ownerId != null && _auth.currentUser?.uid != ownerId) {
          break;
        }
        // Re-read after every delivery. A second message can be queued while
        // the first callable is in flight; taking one snapshot here would
        // strand it until the one-second retry timer despite being online.
        final due = queue
            .due()
            .where((entry) => !blockedThisPass.contains(entry.conversationId))
            .toList(growable: false);
        if (due.isEmpty) {
          break;
        }
        final delivered = await _attemptDelivery(due.first, queue: queue);
        if (!delivered) {
          // Preserve FIFO in this conversation, but do not make an unrelated
          // healthy chat wait behind its backoff. The failed conversation is
          // retried by the scheduled drain/connectivity listener.
          blockedThisPass.add(due.first.conversationId);
        }
      }
    } finally {
      queue.endDelivery();
    }
    if (ownerId == null || _auth.currentUser?.uid == ownerId) {
      _scheduleDrain(queue);
    }
  }

  /// Retries a message the automatic loop gave up on.
  ///
  /// Keeps the original requestId, so a manual retry of a send that secretly
  /// succeeded is still deduplicated by the server ledger.
  Future<void> retryFailedMessage(String entryId) async {
    final queue = outbox;
    final entry = await queue.retryNow(entryId);
    if (entry == null) {
      return;
    }
    await _attemptDelivery(entry, queue: queue, rethrowRefusal: true);
  }

  /// Drops a queued message the person no longer wants sent.
  Future<void> discardQueuedMessage(String entryId) {
    final queue = outbox;
    return queue.discard(entryId);
  }

  /// Releases the connectivity subscription and retry timer.
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    for (final timer in _drainTimers.values) {
      timer.cancel();
    }
    _drainTimers.clear();
    for (final timer in _attachmentDrainTimers.values) {
      timer.cancel();
    }
    _attachmentDrainTimers.clear();
  }

  /// Sends an image through the server-reserved private attachment flow.
  ///
  /// There is intentionally no client-direct fallback: only the backend may
  /// bind an upload to a canonical conversation/message pair. The Storage
  /// object is immutable and readable only by the two live participants.
  Future<void> sendImageMessage({
    required String conversationId,
    required XFile image,
  }) async {
    final bytes = await image.readAsBytes();
    if (bytes.lengthInBytes < 128 || bytes.lengthInBytes > 8 * 1024 * 1024) {
      throw StateError('Choose a photo smaller than 8 MB.');
    }
    final contentType = _imageContentType(image);
    final queue = attachmentOutbox;
    final entry = await queue.enqueue(
      fingerprint: sha256.convert(bytes).toString(),
      conversationId: conversationId,
      type: MessageType.image,
      contentType: contentType,
      durationSeconds: null,
      bytes: bytes,
      reserveRequestId: _newRequestId(),
      finalizeRequestId: _newRequestId(),
    );
    _listenForConnectivity();
    await _deliverAttachment(entry.id, queue: queue);
  }

  /// Publishes an already-finished AAC/MP4 recording as a private voice DM.
  /// The caller keeps ownership of [audio] so a failed finalize can be retried
  /// without forcing the person to record again.
  Future<void> sendVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) async {
    final problem = validateRecordedAudio(audio);
    if (problem != null) throw problem;
    if (durationSeconds < 1 || durationSeconds > 60) {
      throw StateError('Voice messages must be between 1 and 60 seconds.');
    }
    final contentType = normalizeAudioContentType(audio.contentType);
    final bytes = await audio.readBytes();
    if (bytes.lengthInBytes != audio.byteLength) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The recording changed before it could be saved safely.',
        action: 'Record it again.',
      );
    }
    final queue = attachmentOutbox;
    final entry = await queue.enqueue(
      fingerprint: sha256.convert(bytes).toString(),
      conversationId: conversationId,
      type: MessageType.voice,
      contentType: contentType,
      durationSeconds: durationSeconds,
      bytes: bytes,
      reserveRequestId: _newRequestId(),
      finalizeRequestId: _newRequestId(),
    );
    _listenForConnectivity();
    await _deliverAttachment(entry.id, queue: queue);
  }

  Future<void> flushAttachmentOutbox() =>
      _flushAttachmentOutbox(attachmentOutbox);

  Future<void> discardQueuedAttachment(String entryId) =>
      attachmentOutbox.discard(entryId);

  Future<void> retryFailedAttachment(String entryId) async {
    final queue = attachmentOutbox;
    final entry = await queue.retryNow(entryId);
    if (entry == null) return;
    await _deliverAttachment(entry.id, queue: queue);
  }

  Future<void> _flushAttachmentOutbox(DirectAttachmentOutbox queue) async {
    if (_auth.currentUser?.uid != queue.ownerId) return;
    await queue.load();
    for (final entry in queue.due()) {
      try {
        await _deliverAttachment(entry.id, queue: queue);
      } catch (_) {
        // Interactive sends already surface their error. Background resume is
        // intentionally quiet and leaves a durable retry/failed state.
      }
    }
    _scheduleAttachmentDrain(queue);
  }

  void _scheduleAttachmentDrain(DirectAttachmentOutbox queue) {
    if (_auth.currentUser?.uid != queue.ownerId ||
        (_attachmentDrainTimers[queue]?.isActive ?? false)) {
      return;
    }
    final pending = queue.entries.where(
      (entry) => entry.status != DirectAttachmentOutboxStatus.failed,
    );
    if (pending.isEmpty) return;
    final now = DateTime.now();
    var delay = const Duration(seconds: 30);
    for (final entry in pending) {
      final next = entry.nextAttemptAt;
      final until = next == null
          ? const Duration(seconds: 1)
          : next.difference(now);
      if (until < delay) delay = until;
    }
    if (delay < const Duration(seconds: 1)) delay = const Duration(seconds: 1);
    _attachmentDrainTimers[queue] = Timer(delay, () {
      _attachmentDrainTimers.remove(queue);
      unawaited(_flushAttachmentOutbox(queue));
    });
  }

  Future<void> _deliverAttachment(
    String entryId, {
    required DirectAttachmentOutbox queue,
  }) async {
    final deliveryKey = _attachmentDeliveryKey(queue, entryId);
    final existing = _attachmentDeliveries[deliveryKey];
    if (existing != null) return existing;
    final delivery = _performAttachmentDelivery(entryId, queue: queue);
    _attachmentDeliveries[deliveryKey] = delivery;
    try {
      await delivery;
    } finally {
      _attachmentDeliveries.remove(deliveryKey);
    }
  }

  Future<void> _performAttachmentDelivery(
    String entryId, {
    required DirectAttachmentOutbox queue,
  }) async {
    if (_auth.currentUser?.uid != queue.ownerId) return;
    var entry = queue.entry(entryId);
    if (entry == null) return;
    try {
      // A lease can expire while the process is offline or between upload and
      // finalize. Rotation is bounded and atomic in the manifest; the durable
      // bytes never move and every new server input gets fresh idempotency IDs.
      for (var rotations = 0; rotations < 3; rotations++) {
        entry = queue.entry(entryId);
        if (entry == null || _auth.currentUser?.uid != queue.ownerId) return;

        var reservation = entry.reservation == null
            ? null
            : _reservationFromRecord(entry.reservation!);
        if (reservation != null &&
            queue.reservationNeedsRefresh(
              entry,
              safetyWindow: const Duration(seconds: 30),
            )) {
          // A previously-started finalize may have committed before its ACK
          // was lost. Reconcile that stable request once before abandoning the
          // old path; the backend ledger replays it even after lease expiry.
          if (entry.finalizeAttempted &&
              entry.generation != null &&
              entry.generation!.isNotEmpty) {
            try {
              await _finalizeDirectAttachment(
                reservation,
                entry.generation!,
                requestId: entry.finalizeRequestId,
              );
              if (_auth.currentUser?.uid != queue.ownerId) return;
              await queue.complete(entry.id);
              return;
            } on FirebaseFunctionsException catch (error) {
              if (error.code != 'failed-precondition' ||
                  !queue.reservationNeedsRefresh(entry)) {
                rethrow;
              }
            }
          }
          entry = (await queue.rotateExpiredReservation(
            entry.id,
            expectedMessageId: reservation.messageId,
            reserveRequestId: _newRequestId(),
            finalizeRequestId: _newRequestId(),
            safetyWindow: const Duration(seconds: 30),
          ))!;
          continue;
        }

        if (reservation == null) {
          try {
            reservation = await _reserveDirectAttachment(
              conversationId: entry.conversationId,
              type: entry.type,
              contentType: entry.contentType,
              durationSeconds: entry.durationSeconds,
              requestId: entry.reserveRequestId,
            );
          } catch (error) {
            if (!_isAuthoritativeReservationInvalid(error)) rethrow;
            await queue.rotateRejectedReservation(
              entry.id,
              expectedReserveRequestId: entry.reserveRequestId,
              reserveRequestId: _newRequestId(),
              finalizeRequestId: _newRequestId(),
            );
            continue;
          }
          if (_auth.currentUser?.uid != queue.ownerId) return;
          entry = (await queue.setReservation(
            entry.id,
            _reservationRecord(reservation, queue: queue),
          ))!;
          if (queue.reservationNeedsRefresh(
            entry,
            safetyWindow: const Duration(seconds: 30),
          )) {
            entry = (await queue.rotateExpiredReservation(
              entry.id,
              expectedMessageId: reservation.messageId,
              reserveRequestId: _newRequestId(),
              finalizeRequestId: _newRequestId(),
              safetyWindow: const Duration(seconds: 30),
            ))!;
            continue;
          }
        }

        var generation = entry.generation;
        if (generation == null || generation.isEmpty) {
          try {
            generation = await _uploadDirectAttachment(
              reservation,
              contentType: entry.contentType,
              upload: (reference, metadata) => queue.payloadStore.upload(
                queue.accountNamespace,
                entry!.id,
                reference,
                metadata,
              ),
            );
          } catch (error) {
            if (_isAuthoritativeReservationInvalid(error)) {
              await queue.rotateRejectedReservation(
                entry.id,
                expectedReserveRequestId: entry.reserveRequestId,
                reserveRequestId: _newRequestId(),
                finalizeRequestId: _newRequestId(),
              );
            } else {
              if (!queue.reservationNeedsRefresh(entry)) rethrow;
              await queue.rotateExpiredReservation(
                entry.id,
                expectedMessageId: reservation.messageId,
                reserveRequestId: _newRequestId(),
                finalizeRequestId: _newRequestId(),
              );
            }
            continue;
          }
          if (_auth.currentUser?.uid != queue.ownerId) return;
          entry = (await queue.setGeneration(entry.id, generation))!;
        }

        if (queue.reservationNeedsRefresh(
          entry,
          safetyWindow: const Duration(seconds: 30),
        )) {
          entry = (await queue.rotateExpiredReservation(
            entry.id,
            expectedMessageId: reservation.messageId,
            reserveRequestId: _newRequestId(),
            finalizeRequestId: _newRequestId(),
            safetyWindow: const Duration(seconds: 30),
          ))!;
          continue;
        }

        entry = (await queue.markFinalizeAttempted(entry.id))!;
        try {
          await _finalizeDirectAttachment(
            reservation,
            generation,
            requestId: entry.finalizeRequestId,
          );
        } catch (error) {
          if (_isAuthoritativeReservationInvalid(error)) {
            await queue.rotateRejectedReservation(
              entry.id,
              expectedReserveRequestId: entry.reserveRequestId,
              reserveRequestId: _newRequestId(),
              finalizeRequestId: _newRequestId(),
            );
          } else {
            if (error is! FirebaseFunctionsException ||
                error.code != 'failed-precondition' ||
                !queue.reservationNeedsRefresh(entry)) {
              rethrow;
            }
            await queue.rotateExpiredReservation(
              entry.id,
              expectedMessageId: reservation.messageId,
              reserveRequestId: _newRequestId(),
              finalizeRequestId: _newRequestId(),
            );
          }
          continue;
        }
        if (_auth.currentUser?.uid != queue.ownerId) return;
        await queue.complete(entry.id);
        return;
      }
      throw StateError('The attachment reservation kept expiring. Try again.');
    } catch (error) {
      if (_isAmbiguousAttachmentFailure(error)) {
        await queue.markRetry(entryId, error);
        _scheduleAttachmentDrain(queue);
      } else {
        await queue.markFailed(entryId, error);
      }
      rethrow;
    }
  }

  String _attachmentDeliveryKey(DirectAttachmentOutbox queue, String entryId) =>
      '${queue.accountNamespace}:$entryId';

  DirectAttachmentReservationRecord _reservationRecord(
    _DirectAttachmentReservation reservation, {
    required DirectAttachmentOutbox queue,
  }) => DirectAttachmentReservationRecord(
    conversationId: reservation.conversationId,
    messageId: reservation.messageId,
    storagePath: reservation.storagePath,
    type: reservation.type,
    expiresAt: reservation.expiresAt,
    clientExpiresAt: queue.now.add(_directAttachmentLeaseDuration),
  );

  _DirectAttachmentReservation _reservationFromRecord(
    DirectAttachmentReservationRecord reservation,
  ) => _DirectAttachmentReservation(
    conversationId: reservation.conversationId,
    messageId: reservation.messageId,
    storagePath: reservation.storagePath,
    type: reservation.type,
    expiresAt: reservation.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  bool _isAmbiguousAttachmentFailure(Object error) {
    if (error is FirebaseFunctionsException) {
      return const {
        'unavailable',
        'deadline-exceeded',
        'aborted',
      }.contains(error.code);
    }
    if (error is FirebaseException) {
      return const {
        'unknown',
        'retry-limit-exceeded',
        'unavailable',
        'deadline-exceeded',
        'network-request-failed',
      }.contains(error.code);
    }
    return false;
  }

  bool _isAuthoritativeReservationInvalid(Object error) {
    if (error is! FirebaseException || error.code != 'failed-precondition') {
      return false;
    }
    final message = (error.message ?? '').toLowerCase();
    if (!message.contains('reservation')) return false;
    return message.contains('expired') ||
        message.contains('invalid') ||
        message.contains('changed');
  }

  String _imageContentType(XFile image) {
    final declared = image.mimeType?.split(';').first.trim().toLowerCase();
    if (declared == 'image/jpeg' ||
        declared == 'image/png' ||
        declared == 'image/webp') {
      return declared!;
    }
    final lower = image.name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    throw StateError('Choose a JPG, PNG, or WebP photo.');
  }

  Future<_DirectAttachmentReservation> _reserveDirectAttachment({
    required String conversationId,
    required MessageType type,
    required String contentType,
    int? durationSeconds,
    required String requestId,
  }) async {
    final functions = _functions;
    if (functions == null) {
      throw StateError('Private media sharing needs a connection to YO Voice.');
    }
    final response = await functions
        .httpsCallable('reserveDirectMessageAttachment')
        .call<Map<Object?, Object?>>({
          'conversationId': conversationId,
          'type': type.name,
          'contentType': contentType,
          'durationSeconds': durationSeconds,
          'requestId': requestId,
        });
    return _DirectAttachmentReservation.fromResponse(response.data);
  }

  SettableMetadata _attachmentMetadata(
    _DirectAttachmentReservation reservation, {
    required String contentType,
  }) {
    return SettableMetadata(
      contentType: contentType,
      customMetadata: _attachmentCustomMetadata(reservation),
    );
  }

  /// Uploads to one immutable server reservation even when the Storage SDK
  /// loses the response after committing the object. A retry never reserves a
  /// second path: first it asks Storage whether the exact object/metadata is
  /// already present, then it retries the same upload target. This avoids both
  /// duplicate messages and abandoned objects on ambiguous network failures.
  Future<String> _uploadDirectAttachment(
    _DirectAttachmentReservation reservation, {
    required String contentType,
    required Future<String> Function(
      Reference reference,
      SettableMetadata metadata,
    )
    upload,
  }) async {
    final reference = _storage.ref(reservation.storagePath);
    final metadata = _attachmentMetadata(reservation, contentType: contentType);
    Object? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final generation = await upload(reference, metadata);
        if (generation.isEmpty) {
          throw StateError('The uploaded attachment could not be verified.');
        }
        return generation;
      } catch (error) {
        lastError = error;
        try {
          return await _committedAttachmentGeneration(
            reference,
            reservation,
            contentType: contentType,
          );
        } catch (_) {
          if (attempt == 2) throw error;
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }

    throw lastError ?? StateError('The attachment could not be uploaded.');
  }

  Future<String> _committedAttachmentGeneration(
    Reference reference,
    _DirectAttachmentReservation reservation, {
    required String contentType,
  }) async {
    final stored = await reference.getMetadata();
    final expected = _attachmentCustomMetadata(reservation);
    final actual = stored.customMetadata ?? const <String, String>{};
    final exactMetadata =
        actual.length == expected.length &&
        expected.entries.every((entry) => actual[entry.key] == entry.value);
    final generation = stored.generation;

    if (stored.contentType != contentType ||
        !exactMetadata ||
        generation == null ||
        generation.isEmpty) {
      throw StateError('The stored attachment identity could not be verified.');
    }
    return generation;
  }

  Map<String, String> _attachmentCustomMetadata(
    _DirectAttachmentReservation reservation,
  ) {
    return {
      'yovoiceConversationId': reservation.conversationId,
      'yovoiceMessageId': reservation.messageId,
      'yovoiceMessagePath':
          'conversations/${reservation.conversationId}/messages/${reservation.messageId}',
      'yovoiceMediaType': reservation.type.name,
      'yovoiceOwnerUid': _currentUserId,
    };
  }

  Future<void> _finalizeDirectAttachment(
    _DirectAttachmentReservation reservation,
    String generation, {
    required String requestId,
  }) async {
    final functions = _functions;
    if (functions == null) {
      throw StateError('Private media sharing needs a connection to YO Voice.');
    }
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await functions.httpsCallable('finalizeDirectMessageAttachment').call({
          'conversationId': reservation.conversationId,
          'messageId': reservation.messageId,
          'objectGeneration': generation,
          'requestId': requestId,
        });
        return;
      } catch (error) {
        lastError = error;
        final retryable =
            error is FirebaseFunctionsException &&
            const {
              'unavailable',
              'deadline-exceeded',
              'aborted',
            }.contains(error.code);
        if (!retryable || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('The attachment could not be published.');
  }

  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String text,
  }) async {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return;
    }

    final called = await _tryCallable('editDirectMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
      'text': trimmed,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

    final reference = _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await reference.get();

    if (snapshot.data()?['senderId'] != _currentUserId) {
      throw StateError('You can only edit your own messages.');
    }

    await reference.update({
      'content': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });

    final conversation = await _conversations.doc(conversationId).get();
    final lastMessage = conversation.data()?['lastMessage'] as String? ?? '';

    if (lastMessage == snapshot.data()?['content']) {
      await conversation.reference.update({'lastMessage': trimmed});
    }
  }

  Future<void> toggleReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    final userId = _currentUserId;
    final reference = _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await reference.get();
    final reactions = Map<String, dynamic>.from(
      snapshot.data()?['reactions'] as Map? ?? const <String, dynamic>{},
    );
    final current = reactions[userId] as String?;
    final nextEmoji = current == emoji ? null : emoji;

    final called = await _tryCallable('setDirectMessageReaction', {
      'conversationId': conversationId,
      'messageId': messageId,
      'emoji': nextEmoji,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

    if (current == emoji) {
      await reference.update({'reactions.$userId': FieldValue.delete()});
    } else {
      await reference.update({'reactions.$userId': emoji});
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    if (!_preferLegacyBehaviour) {
      final functions = _functions;
      if (functions == null) {
        throw StateError('Read receipts need a connection to YO Voice.');
      }
      try {
        int? previousReadSequence;
        for (var page = 0; page < _maxReadReceiptPagesPerPass; page++) {
          // One page owns one idempotency id. A lost response retries that
          // exact operation; only a confirmed cursor advance receives a new
          // id for the following page.
          final requestId = _newRequestId();
          HttpsCallableResult<Map<Object?, Object?>>? response;
          for (var attempt = 0; attempt < 2; attempt++) {
            try {
              response = await functions
                  .httpsCallable('markDirectConversationRead')
                  .call<Map<Object?, Object?>>({
                    'conversationId': conversationId,
                    'requestId': requestId,
                  });
              break;
            } catch (error) {
              if (attempt == 0 && _isAmbiguousTransportFailure(error)) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                continue;
              }
              rethrow;
            }
          }
          if (response == null) {
            throw StateError('The read-receipt service did not respond.');
          }
          final completed = response.data['completed'];
          if (completed is! bool) {
            throw StateError(
              'The read-receipt service returned a malformed result.',
            );
          }
          if (completed) return;

          final nextReadSequence = response.data['nextReadSequence'];
          if (nextReadSequence is! num ||
              nextReadSequence < 0 ||
              nextReadSequence != nextReadSequence.roundToDouble() ||
              (previousReadSequence != null &&
                  nextReadSequence <= previousReadSequence)) {
            throw StateError(
              'The read-receipt service did not advance its cursor.',
            );
          }
          previousReadSequence = nextReadSequence.toInt();
        }
        throw StateError(
          'The read-receipt service exceeded its safe page limit.',
        );
      } catch (error) {
        if (_isCallableUnavailable(error)) {
          throw StateError(
            'This build cannot update read receipts safely. Update YO Voice.',
          );
        }
        rethrow;
      }
    }

    // Test/legacy-only behavior. Production roots and message documents are
    // server-authoritative and Rules intentionally reject this path.
    final currentUserId = _currentUserId;
    final conversation = _conversations.doc(conversationId);
    final latest = await conversation
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(150)
        .get();
    final batch = _firestore.batch();

    batch.update(conversation, {'unreadCounts.$currentUserId': 0});

    for (final document in latest.docs) {
      final data = document.data();
      final senderId = data['senderId'] as String? ?? '';
      final readBy = List<String>.from(
        data['readBy'] as List<dynamic>? ?? const <dynamic>[],
      );

      if (senderId != currentUserId && !readBy.contains(currentUserId)) {
        batch.update(document.reference, {
          'readBy': FieldValue.arrayUnion([currentUserId]),
        });
      }
    }

    await batch.commit();
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final called = await _tryCallable('deleteDirectMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

    final reference = _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await reference.get();

    if (snapshot.data()?['senderId'] != _currentUserId) {
      throw StateError('You can only delete your own messages.');
    }

    await reference.update({
      'content': '',
      'mediaUrl': null,
      'isDeleted': true,
      'editedAt': FieldValue.serverTimestamp(),
      'reactions': <String, String>{},
    });
  }

  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {
    final called = await _tryCallable('setDirectConversationPreference', {
      'conversationId': conversationId,
      'preference': 'muted',
      'enabled': muted,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

    final userId = _currentUserId;

    await _conversations.doc(conversationId).update({
      'mutedBy': muted
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> archiveConversation(String conversationId) async {
    final called = await _tryCallable('setDirectConversationPreference', {
      'conversationId': conversationId,
      'preference': 'archived',
      'enabled': true,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

    final userId = _currentUserId;

    await _conversations.doc(conversationId).update({
      'archivedBy': FieldValue.arrayUnion([userId]),
      'unreadCounts.$userId': 0,
    });
  }

  Future<void> unarchiveConversation(String conversationId) async {
    final called = await _tryCallable('setDirectConversationPreference', {
      'conversationId': conversationId,
      'preference': 'archived',
      'enabled': false,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

    final userId = _currentUserId;

    await _conversations.doc(conversationId).update({
      'archivedBy': FieldValue.arrayRemove([userId]),
    });
  }

  static String buildConversationId(String firstId, String secondId) {
    final ids = [firstId, secondId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  static String _currentDisplayName(String? name, String? email) {
    final value = name?.trim() ?? '';

    return value.isNotEmpty ? value : _displayNameFromEmail(email ?? '');
  }

  static String _displayNameFromEmail(String email) {
    final value = email.trim();

    return value.isEmpty ? 'YO Voice user' : value.split('@').first;
  }
}

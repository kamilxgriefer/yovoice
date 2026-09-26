import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/helpers/callable_failure_reporter.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/models/premium_messaging_privacy.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_delivery_progress.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/direct_conversation_open_intents.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';

class ChatPresence {
  const ChatPresence({
    required this.isOnline,
    required this.lastSeen,
    this.availability,
  });

  final bool isOnline;
  final DateTime? lastSeen;

  /// Projected availability ('available' | 'away' | 'busy' | 'offline'),
  /// null when the projection predates the field.
  final String? availability;
}

/// One stable, newest-first page of media messages from a private chat.
///
/// [cursor] is deliberately opaque to presentation code. It is only handed
/// back to [MessageService.loadSharedMediaPage], keeping Firestore pagination
/// details out of the UI while still allowing the complete archive to be
/// loaded without reading every text message into memory.
class SharedMediaPage {
  const SharedMediaPage({
    required this.messages,
    required this.cursor,
    required this.hasMore,
    this.hiddenMessageIds = const <String>{},
  });

  final List<Message> messages;
  final Object? cursor;
  final bool hasMore;

  /// Message documents observed by the live page that must no longer be
  /// presented as shared media (for example after a soft-delete). Keeping
  /// these ids separate lets the UI retain an item that merely moved beyond
  /// the first-page boundary without resurrecting a deleted attachment from
  /// its pagination cache.
  final Set<String> hiddenMessageIds;
}

class _DirectConversationUnreadState {
  const _DirectConversationUnreadState({
    required this.conversationId,
    required this.unreadCount,
  });

  final String conversationId;
  final int unreadCount;

  factory _DirectConversationUnreadState.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String ownerId,
  }) {
    final data = snapshot.data();
    const expected = <String>{
      'schemaVersion',
      'ownerId',
      'conversationId',
      'unreadCount',
      'updatedAt',
    };
    final keys = data?.keys.toSet() ?? const <String>{};
    final conversationId = data?['conversationId'];
    final unreadCount = data?['unreadCount'];
    final canonical =
        data != null &&
        keys.length == expected.length &&
        keys.containsAll(expected) &&
        data['schemaVersion'] == 1 &&
        data['ownerId'] == ownerId &&
        conversationId is String &&
        conversationId.isNotEmpty &&
        unreadCount is int &&
        unreadCount >= 0 &&
        data['updatedAt'] is Timestamp;
    if (!canonical) {
      throw const FormatException(
        'Malformed private direct-message unread projection.',
      );
    }
    return _DirectConversationUnreadState(
      conversationId: conversationId,
      unreadCount: unreadCount,
    );
  }
}

/// Combines two live sources while remaining safe to listen, cancel and listen
/// again. Lazy Sliver children do exactly that as they leave and re-enter the
/// viewport, so every downstream listener owns fresh upstream subscriptions.
Stream<R> _combineLatest2<A, B, R>(
  Stream<A> Function() firstSource,
  Stream<B> Function() secondSource,
  R Function(A first, B second) combine,
) {
  return Stream<R>.multi((controller) {
    StreamSubscription<A>? firstSubscription;
    StreamSubscription<B>? secondSubscription;
    A? latestFirst;
    B? latestSecond;
    var hasFirst = false;
    var hasSecond = false;
    var firstDone = false;
    var secondDone = false;

    void emit() {
      if (controller.isClosed || !hasFirst || !hasSecond) return;
      try {
        controller.add(combine(latestFirst as A, latestSecond as B));
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    void closeIfDone() {
      if (!controller.isClosed && firstDone && secondDone) {
        unawaited(controller.close());
      }
    }

    controller.onPause = () {
      firstSubscription?.pause();
      secondSubscription?.pause();
    };
    controller.onResume = () {
      firstSubscription?.resume();
      secondSubscription?.resume();
    };
    controller.onCancel = () async {
      await firstSubscription?.cancel();
      await secondSubscription?.cancel();
    };

    try {
      firstSubscription = firstSource().listen(
        (value) {
          latestFirst = value;
          hasFirst = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          firstDone = true;
          closeIfDone();
        },
      );
      secondSubscription = secondSource().listen(
        (value) {
          latestSecond = value;
          hasSecond = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          secondDone = true;
          closeIfDone();
        },
      );
    } catch (error, stackTrace) {
      unawaited(firstSubscription?.cancel());
      unawaited(secondSubscription?.cancel());
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    }
  });
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
        (type.first == MessageType.text || type.first == MessageType.gif)) {
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

/// Direct-message attachment limits. The same values are enforced by
/// `functions/messaging/direct_integrity.js` and `storage.rules`; the picked
/// media review (ADR-212) reads these so it can never disagree with them.
const int directImageMaxBytes = 8 * 1024 * 1024;
const int directVideoMaxBytes = 64 * 1024 * 1024;

/// The one product limit for a direct voice or video message (and a server
/// channel video), `DIRECT_MEDIA_MAX_SECONDS` in `direct_integrity.js`.
/// Every declared and stored duration stays inside 1..this.
const int directMediaMaxSeconds = 60;
const int directVideoMaxSeconds = directMediaMaxSeconds;
const int directVoiceMaxSeconds = directMediaMaxSeconds;

/// How far a take's *measured* length may run past [directMediaMaxSeconds]
/// and still be a full-length take: `DIRECT_MEDIA_DURATION_GRACE_MS` in
/// `direct_integrity.js`. A recorder or camera that stops itself at the cap
/// always produces a file slightly longer than the cap (capture starts before
/// the stopwatch and ends after it), and the server accepts that and stores
/// the cap.
const int directMediaDurationGraceMs = 2000;

/// The whole seconds to declare for a take its recorder or camera capped at
/// [directMediaMaxSeconds]: the measured length rounded up, except that a
/// take running past the cap by no more than [directMediaDurationGraceMs] is
/// declared as the cap itself. Anything longer keeps its real length, so the
/// 1..60 checks downstream still refuse it.
int directCappedTakeSeconds(Duration measured) {
  final milliseconds = measured.inMilliseconds;
  final seconds = (milliseconds + 999) ~/ 1000;
  if (seconds > directMediaMaxSeconds &&
      milliseconds <=
          directMediaMaxSeconds * 1000 + directMediaDurationGraceMs) {
    return directMediaMaxSeconds;
  }
  return seconds;
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
    DirectConversationOpenIntents? openIntents,
    Connectivity? connectivity,
    Stream<Map<String, int>>? directUnreadOverridesForTesting,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _legacyNotificationService = notificationService,
       _functionsOverride = functions,
       _storageOverride = storage,
       _outboxOverride = outbox,
       _attachmentOutboxOverride = attachmentOutbox,
       _attachmentPayloadStoreOverride = attachmentPayloadStore,
       _openIntentsOverride = openIntents,
       _connectivityOverride = connectivity,
       _directUnreadOverridesForTesting = directUnreadOverridesForTesting,
       _useSharedLiveOutbox =
           firestore == null &&
           auth == null &&
           notificationService == null &&
           functions == null &&
           storage == null &&
           outbox == null &&
           attachmentOutbox == null &&
           attachmentPayloadStore == null &&
           openIntents == null &&
           connectivity == null &&
           directUnreadOverridesForTesting == null;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService? _legacyNotificationService;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage? _storageOverride;
  final MessageOutbox? _outboxOverride;
  final DirectAttachmentOutbox? _attachmentOutboxOverride;
  final DirectAttachmentPayloadStore? _attachmentPayloadStoreOverride;
  final DirectConversationOpenIntents? _openIntentsOverride;
  final Connectivity? _connectivityOverride;
  final Stream<Map<String, int>>? _directUnreadOverridesForTesting;
  final bool _useSharedLiveOutbox;
  MessageOutbox? _outbox;
  String? _outboxOwnerId;
  DirectConversationOpenIntents? _openIntents;
  String? _openIntentsOwnerId;
  StreamSubscription<Object?>? _connectivitySubscription;

  /// The last connectivity verdict this service observed, or null when it
  /// never got to subscribe (unit tests, previews). Null is "unknown", which
  /// is deliberately NOT "offline".
  bool? _offlineObserved;
  final Map<MessageOutbox, Timer> _drainTimers = <MessageOutbox, Timer>{};
  final Map<DirectAttachmentOutbox, Timer> _attachmentDrainTimers =
      <DirectAttachmentOutbox, Timer>{};
  final Map<String, Future<void>> _attachmentDeliveries = {};
  DirectAttachmentOutbox? _attachmentOutbox;
  String? _attachmentOutboxOwnerId;

  /// Which phase each in-flight attachment delivery is in, right now.
  ///
  /// Live process state, not queue state: the durable manifest keeps saying
  /// what survives a restart, and this says what is happening this second so a
  /// queued card can show a real percentage instead of an endless "Sending…".
  final DirectAttachmentDeliveryProgress attachmentDelivery =
      DirectAttachmentDeliveryProgress();

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

  /// In-flight `openDirectConversation` intents for the signed-in account.
  ///
  /// Scoped and shared exactly like [outbox]: five screens build their own
  /// facades, and they must agree on which request id is already in play
  /// for a given person.
  DirectConversationOpenIntents get openIntents {
    final override = _openIntentsOverride;
    if (override != null) return override;

    final ownerId = _auth.currentUser?.uid;
    if (_useSharedLiveOutbox && ownerId != null && ownerId.isNotEmpty) {
      return DirectConversationOpenIntents.sharedForUser(ownerId);
    }
    if (_openIntents == null || _openIntentsOwnerId != ownerId) {
      _openIntentsOwnerId = ownerId;
      _openIntents = DirectConversationOpenIntents();
    }
    return _openIntents!;
  }

  /// Account-scoped durable queue for photo, video and voice payloads.
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

  ({String ownerId, DirectAttachmentOutbox queue})
  _captureAttachmentQueueOwner() {
    final ownerId = _currentUserId;
    final queue = attachmentOutbox;
    if (queue.ownerId != ownerId) {
      throw StateError('The attachment queue belongs to another account.');
    }
    return (ownerId: ownerId, queue: queue);
  }

  bool _stillOwnsAttachmentQueue(
    ({String ownerId, DirectAttachmentOutbox queue}) capture,
  ) =>
      capture.queue.ownerId == capture.ownerId &&
      _auth.currentUser?.uid == capture.ownerId;

  void _requireAttachmentQueueOwner(
    ({String ownerId, DirectAttachmentOutbox queue}) capture,
  ) {
    if (!_stillOwnsAttachmentQueue(capture)) {
      throw StateError(
        'The signed-in account changed while the attachment was being saved.',
      );
    }
  }

  Future<void> _rejectAttachmentAfterOwnerChange(
    ({String ownerId, DirectAttachmentOutbox queue}) capture,
    DirectAttachmentOutboxEntry entry, {
    required bool created,
  }) async {
    if (created) {
      // `complete` is the unconditional private-byte removal primitive. The
      // user-facing `discard` action deliberately accepts failed entries only.
      await capture.queue.complete(entry.id);
    }
    throw StateError(
      'The signed-in account changed while the attachment was being saved.',
    );
  }

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  /// Clears plaintext retry state at the account boundary. Sign-out calls this
  /// before Firebase Auth is cleared so no active delivery loop can retain a
  /// reference to another account's pending text, image, video or voice data.
  Future<void> clearLocalSensitiveStateForUser(String userId) async {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('The local message owner changed before cleanup.');
    }
    final textQueue = outbox;
    final mediaQueue = attachmentOutbox;
    _drainTimers.remove(textQueue)?.cancel();
    _attachmentDrainTimers.remove(mediaQueue)?.cancel();
    // An open intent names a person this account tried to message. That is
    // local personal data and leaves with the session.
    DirectConversationOpenIntents.forgetUser(userId);
    _openIntents = null;
    _openIntentsOwnerId = null;
    await Future.wait<void>([textQueue.clear(), mediaQueue.clear()]);
  }

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

  /// Whether a callable failure leaves the outcome genuinely unknown, so
  /// replaying the SAME request id is the right move.
  ///
  /// Public because it is the one definition of "not an answer" this
  /// codebase has, and background bookkeeping outside this class — read
  /// receipts in `ChatScreen`, for instance — must not invent a second one.
  /// A `permission-denied` repeated on a 30 s timer is still
  /// `permission-denied`; it just also spends the integrity limiter.
  static bool isAmbiguousTransportFailure(Object error) =>
      error is FirebaseFunctionsException &&
      transientCallableCodes.contains(error.code);

  bool _isAmbiguousTransportFailure(Object error) =>
      isAmbiguousTransportFailure(error);

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

  /// Retries one idempotent callable only when its first acknowledgement is
  /// ambiguous: the server may already have committed the operation, but the
  /// response did not reach the client.
  ///
  /// [data] is deliberately reused unchanged so its request id reaches the
  /// backend ledger again. A refusal such as permission-denied or
  /// invalid-argument is never retried. If the endpoint appears absent on the
  /// second attempt, the original transport error wins instead of dropping
  /// into a client write after the server may already have committed.
  Future<bool> _tryIdempotentCallableAfterAmbiguousTransport(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      return await _tryCallable(name, data);
    } catch (error, stackTrace) {
      if (!_isAmbiguousTransportFailure(error)) {
        rethrow;
      }

      try {
        final retried = await _tryCallable(name, data);
        if (retried) {
          return true;
        }
      } catch (_) {
        // The second result is definitive (or still ambiguous), so preserve
        // it for the caller's existing actionable error presentation.
        rethrow;
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  String get _currentUserId {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in to use messages.');
    }

    return user.uid;
  }

  /// Watches ONE conversation root.
  ///
  /// The screen is handed only a `conversationId`, so without this it had
  /// no document to read its own state from and kept mute as a local
  /// boolean that started at false on every open — showing "Mute" for a
  /// thread the account had already muted, and un-muting it on the next
  /// tap. `Conversation.mutedBy` has always carried the truth.
  ///
  /// No rules change: `firestore.rules` already allows `get` on
  /// `conversations/{id}` for a participant, which is the same read
  /// [watchConversations] performs today. Emits null when the root is
  /// missing.
  Stream<Conversation?> watchConversation(String conversationId) {
    return _conversations
        .doc(conversationId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? Conversation.fromFirestore(snapshot) : null,
        );
  }

  /// Every conversation this account can see, newest activity first.
  ///
  /// A root exists for BOTH participants from the moment either of them opens
  /// the other's profile (`openDirectConversation`,
  /// `functions/messaging/direct_integrity.js`), with blank preview fields
  /// and `updatedAt = createdAt = now`. Streaming every root sorted by
  /// `updatedAt` therefore hoisted people who had never written a word to
  /// the top of Chats and Home. The list now shows a thread only once it
  /// carries a message ([Conversation.hasMessages]) — except the empty thread
  /// THIS account opened from this device, which stays visible so the
  /// new-message flow still lands somewhere — and orders by
  /// [Conversation.lastActivityAt], never by a bare root touch.
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    final currentUserId = _currentUserId;
    final intents = openIntents;
    return _combineLatest2(
      () => _combineLatest2(
        () => _conversations
            .where('participantIds', arrayContains: currentUserId)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(Conversation.fromFirestore).toList(),
            ),
        () => _watchDirectUnreadOverrides(currentUserId),
        (roots, overrides) => roots
            .map(
              (conversation) => overrides.containsKey(conversation.id)
                  ? conversation.withUnreadCountFor(
                      currentUserId,
                      overrides[conversation.id]!,
                    )
                  : conversation,
            )
            .toList(growable: false),
      ),
      intents.watchOpenedHere,
      (roots, openedHere) {
        final items = roots
            // A conversation this account deleted is gone from every list,
            // archived included — `includeArchived` is about a tab, not about
            // seeing everything.
            .where(
              (conversation) =>
                  !conversation.isDeletedFor(currentUserId) &&
                  (includeArchived ||
                      !conversation.isArchivedFor(currentUserId)) &&
                  (conversation.hasMessages ||
                      openedHere.contains(conversation.id)),
            )
            .toList(growable: false);

        items.sort(Conversation.compareByRecentActivity);
        return items;
      },
    );
  }

  Stream<Map<String, int>> _watchDirectUnreadOverrides(String currentUserId) {
    final override = _directUnreadOverridesForTesting;
    if (override != null) return _unreadOverridesFailSoft(override);

    late final StreamController<Map<String, int>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    Timer? retryTimer;
    var retryScheduled = false;
    var disposed = false;
    late void Function() subscribe;

    Map<String, int> parse(QuerySnapshot<Map<String, dynamic>> snapshot) {
      final states = snapshot.docs.map(
        (document) => _DirectConversationUnreadState.fromFirestore(
          document,
          ownerId: currentUserId,
        ),
      );
      return <String, int>{
        for (final state in states) state.conversationId: state.unreadCount,
      };
    }

    void scheduleRetry() {
      if (disposed || retryScheduled) return;
      retryScheduled = true;
      retryTimer = Timer(const Duration(seconds: 30), () {
        retryScheduled = false;
        subscribe();
      });
    }

    subscribe = () {
      if (disposed) return;
      unawaited(subscription?.cancel());
      try {
        subscription = _firestore
            .collection('directConversationUnreadStates')
            .where('ownerId', isEqualTo: currentUserId)
            .snapshots()
            .listen(
              (snapshot) {
                if (controller.isClosed) return;
                try {
                  controller.add(parse(snapshot));
                } catch (_) {
                  // Malformed owner projections must never blank the public
                  // conversation list. The backend refuses to trust them and
                  // a later canonical rewrite naturally repairs this stream.
                  controller.add(const <String, int>{});
                }
              },
              onError: (Object _, StackTrace __) {
                // Tester builds can precede the new Rules deploy. Legacy
                // counters keep chat lists usable, and this listener retries
                // until the owner-only projection becomes readable.
                if (!controller.isClosed) {
                  controller.add(const <String, int>{});
                }
                scheduleRetry();
              },
              onDone: scheduleRetry,
            );
      } catch (_) {
        if (!controller.isClosed) controller.add(const <String, int>{});
        scheduleRetry();
      }
    };

    controller = StreamController<Map<String, int>>(
      onListen: subscribe,
      onCancel: () async {
        disposed = true;
        retryTimer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<Map<String, int>> _unreadOverridesFailSoft(
    Stream<Map<String, int>> source,
  ) async* {
    try {
      await for (final value in source) {
        yield value;
      }
    } catch (_) {
      yield const <String, int>{};
    }
  }

  /// Effective owner privacy for the chat composer. Stored switches are
  /// combined with the time-valid server-written entitlement so an expired
  /// subscription cannot keep suppressing local typing. The backend still
  /// rechecks both documents on every mutation and remains authoritative.
  Stream<PremiumMessagingPrivacy> watchPremiumMessagingPrivacy() {
    final uid = _currentUserId;
    return _combineLatest2(
      () => _firestore
          .collection('directPrivacyPreferences')
          .doc(uid)
          .snapshots(),
      () => _firestore.collection('entitlements').doc(uid).snapshots(),
      (preference, entitlement) {
        var premiumActive = false;
        try {
          premiumActive = SubscriptionEntitlements.fromFirestore(
            entitlement,
          ).isPremium;
        } catch (_) {
          // A malformed server projection cannot keep a local privacy control
          // active. The callable independently applies the same fail-closed
          // entitlement boundary.
        }
        if (!premiumActive) {
          return PremiumMessagingPrivacy.disabled;
        }
        try {
          return PremiumMessagingPrivacy.fromFirestore(preference);
        } on FormatException {
          return PremiumMessagingPrivacy.privacySafeHidden;
        }
      },
    );
  }

  /// The conversation's messages, minus anything this account deleted.
  ///
  /// The cut-off is resolved from the conversation root FIRST and the message
  /// query is opened only after it is known. That ordering is deliberate:
  /// starting an unconstrained query optimistically would both flash locally
  /// cached history that was supposed to be gone and be refused outright by
  /// Rules, which require the matching `sequence` bound (see
  /// `conversationDeletedThrough` in `firestore.rules`).
  ///
  /// A cut-off of 0 — nobody has deleted this thread, which is every
  /// conversation until someone does — keeps the exact `sentAt` query this
  /// method has always used, so the common path is unchanged and works
  /// against roots and messages that predate the feature.
  Stream<List<Message>> watchMessages(String conversationId) {
    return _watchWithDeletionCutoff<List<Message>>(
      conversationId,
      (cutoff) => _messagesQuery(conversationId, cutoff).snapshots().map(
        (snapshot) =>
            snapshot.docs.map(Message.fromFirestore).toList(growable: false),
      ),
    );
  }

  /// Re-opens [build] whenever this account's deletion cut-off for
  /// [conversationId] changes, and never before it is known.
  Stream<T> _watchWithDeletionCutoff<T>(
    String conversationId,
    Stream<T> Function(int cutoff) build,
  ) {
    final currentUserId = _currentUserId;
    return Stream<T>.multi((controller) {
      StreamSubscription<T>? inner;
      int? appliedCutoff;

      final root = _conversations.doc(conversationId).snapshots().listen(
        (snapshot) {
          final cutoff = snapshot.exists
              ? Conversation.fromFirestore(
                  snapshot,
                ).deletedThroughSequenceFor(currentUserId)
              : 0;
          // Only a delete moves this, so the inner listener is opened
          // once and rebuilt only when the account really did delete.
          if (cutoff == appliedCutoff) return;
          appliedCutoff = cutoff;
          unawaited(inner?.cancel());
          inner = build(
            cutoff,
          ).listen(controller.add, onError: controller.addError);
        },
        // A root that cannot be read cannot be filtered safely, and
        // falling back to the unfiltered query could surface deleted
        // history. Surface the failure instead.
        onError: controller.addError,
      );

      controller.onCancel = () {
        unawaited(inner?.cancel());
        unawaited(root.cancel());
      };
    });
  }

  /// This account's delete-for-me cut-off, read once.
  Future<int> _deletedThroughSequence(String conversationId) async {
    final currentUserId = _currentUserId;
    final snapshot = await _conversations.doc(conversationId).get();
    if (!snapshot.exists) return 0;
    return Conversation.fromFirestore(
      snapshot,
    ).deletedThroughSequenceFor(currentUserId);
  }

  Query<Map<String, dynamic>> _messagesQuery(
    String conversationId,
    int cutoff,
  ) {
    final messages = _conversations.doc(conversationId).collection('messages');
    if (cutoff <= 0) {
      return messages.orderBy('sentAt', descending: true).limit(250);
    }
    // `sequence` is assigned in send order, so ordering by it is the same
    // ordering as `sentAt` — and Firestore requires the inequality field to
    // lead the sort.
    return messages
        .where('sequence', isGreaterThan: cutoff)
        .orderBy('sequence', descending: true)
        .limit(250);
  }

  Query<Map<String, dynamic>> _sharedMediaQuery({
    required String conversationId,
    required MessageType type,
    required int pageSize,
    required int cutoff,
  }) {
    if (type == MessageType.text || type == MessageType.gif) {
      throw ArgumentError.value(type, 'type', 'Text is not shared media.');
    }
    if (pageSize < 1 || pageSize > 100) {
      throw RangeError.range(pageSize, 1, 100, 'pageSize');
    }
    final messages = _conversations
        .doc(conversationId)
        .collection('messages')
        .where('type', isEqualTo: type.name);
    if (cutoff <= 0) {
      return messages.orderBy('sentAt', descending: true).limit(pageSize);
    }
    return messages
        .where('sequence', isGreaterThan: cutoff)
        .orderBy('sequence', descending: true)
        .limit(pageSize);
  }

  SharedMediaPage _sharedMediaPage(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int pageSize,
  ) {
    final observed = snapshot.docs
        .map(Message.fromFirestore)
        .toList(growable: false);
    final messages = observed
        .where(
          (message) =>
              !message.isDeleted &&
              (message.mediaUrl?.trim().isNotEmpty ?? false),
        )
        .toList(growable: false);
    return SharedMediaPage(
      messages: messages,
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      // A full page may still be the final page. One harmless follow-up query
      // resolves that edge without ever hiding an older attachment.
      hasMore: snapshot.docs.length == pageSize,
      hiddenMessageIds: observed
          .where(
            (message) =>
                message.isDeleted ||
                !(message.mediaUrl?.trim().isNotEmpty ?? false),
          )
          .map((message) => message.id)
          .toSet(),
    );
  }

  /// Watches the newest page for one media type so newly sent attachments
  /// appear immediately while older pages remain explicitly pageable.
  Stream<SharedMediaPage> watchSharedMediaFirstPage({
    required String conversationId,
    required MessageType type,
    int pageSize = 48,
  }) {
    return _watchWithDeletionCutoff<SharedMediaPage>(
      conversationId,
      (cutoff) => _sharedMediaQuery(
        conversationId: conversationId,
        type: type,
        pageSize: pageSize,
        cutoff: cutoff,
      ).snapshots().map((snapshot) => _sharedMediaPage(snapshot, pageSize)),
    );
  }

  /// Loads the next older page for [type]. A cursor from another service or
  /// query is rejected locally instead of issuing an ambiguous request.
  Future<SharedMediaPage> loadSharedMediaPage({
    required String conversationId,
    required MessageType type,
    required Object cursor,
    int pageSize = 48,
  }) async {
    if (cursor is! DocumentSnapshot<Map<String, dynamic>> || !cursor.exists) {
      throw ArgumentError.value(cursor, 'cursor', 'Invalid media cursor.');
    }
    // The cursor came from a page built at the same cut-off, so the query
    // shape has to match it — re-resolve rather than assume zero.
    final query = _sharedMediaQuery(
      conversationId: conversationId,
      type: type,
      pageSize: pageSize,
      cutoff: await _deletedThroughSequence(conversationId),
    ).startAfterDocument(cursor);
    return _sharedMediaPage(await query.get(), pageSize);
  }

  Stream<ChatPresence> watchUserPresence(String userId) {
    // Presence is intentionally not part of the public profile. The
    // server-owned socialPresence projection is readable only for self and
    // canonical friends; a non-friend chat therefore fails closed to the
    // StreamBuilder's offline state instead of exposing a private user doc.
    return _socialPresence.doc(userId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final lastSeenValue = data['lastSeen'];

      final availability = data['availability'];
      return ChatPresence(
        isOnline: data['isOnline'] as bool? ?? false,
        lastSeen: lastSeenValue is Timestamp ? lastSeenValue.toDate() : null,
        availability: availability is String ? availability : null,
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

    // Conversation roots are server-owned. Current Firestore Rules reject a
    // client-side typing fallback, and attempting it only turns an optional
    // presence signal into a second permission error. An old backend that
    // does not expose the callable therefore degrades to no indicator while
    // text, media and calls keep their independent delivery paths.
  }

  /// Client-side deadline for `openDirectConversation` (see the call site).
  static const Duration openConversationTimeout = Duration(seconds: 15);

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
      // Bounded on purpose: the plugin default is 60 s, which left the
      // Friends chat bubble frozen for up to a minute when the callable
      // cold-started or stalled. 15 s covers a cold start plus the two
      // server transactions; a timeout surfaces as a real error the screen
      // can name, and a retry simply finds the root the server did create.
      final callable = functions.httpsCallable(
        'openDirectConversation',
        options: HttpsCallableOptions(timeout: openConversationTimeout),
      );
      // ONE intent per (account, target) until it succeeds. A fresh request
      // id per attempt leaked an `integrityPreflightLedgers` row on every
      // failure — the preflight transaction commits even when the main one
      // rolls back — and made a lost acknowledgement impossible to replay.
      // The same store also refuses to touch the network inside the backoff
      // window, which is the only thing that stops a dozen taps becoming a
      // dozen `direct.attempt.open` quota events and then a 429.
      final intents = openIntents;
      final intent = intents.beginAttempt(
        otherUserId,
        newRequestId: _newRequestId,
      );
      final Map<Object?, Object?> data;
      try {
        final response = await callable.call<Map<Object?, Object?>>({
          'targetUserId': otherUserId,
          'requestId': intent.requestId,
        });
        data = response.data;
      } catch (error, stackTrace) {
        intents.recordFailure(otherUserId, error, stackTrace);
        recordCallableRefusalIfTerminal(
          callable: 'openDirectConversation',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
      final conversationId = data['conversationId'];

      if (conversationId is String && conversationId.isNotEmpty) {
        intents.recordSuccess(otherUserId);
        // Whether the server created the root or found it, THIS account
        // asked for it: keep it visible in Chats while it is still empty.
        intents.markOpenedHere(conversationId);
        return conversationId;
      }

      // The server answered, but not with a usable root. Treat it as a
      // failed attempt so the retry keeps the same id rather than minting a
      // second ledger row for the same intent.
      final malformed = StateError(
        'Malformed server response for opening conversation.',
      );
      intents.recordFailure(otherUserId, malformed, StackTrace.current);
      throw malformed;
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
        'participantPhotoUrls': {currentUser.uid: '', otherUserId: ''},
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

    openIntents.markOpenedHere(conversationId);
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
    } catch (error, stackTrace) {
      if (_isRetryable(error)) {
        if (_isOfflineFailure(error)) {
          // No server saw this, so nothing was learned and nothing may be
          // charged against the retry budget. One to two minutes in a lift
          // used to be enough to park a message at "Not sent" for good.
          await queue.markDeferred(entry.id, _describeError(error));
        } else {
          await queue.markRetry(entry.id, _describeError(error));
        }
        _scheduleDrain(queue);
        return false;
      }
      await queue.markFailed(entry.id, _describeError(error));
      recordCallableRefusalIfTerminal(
        callable: 'sendDirectMessage',
        error: error,
        stackTrace: stackTrace,
      );
      if (rethrowRefusal) {
        rethrow;
      }
      return false;
    }
  }

  /// Whether a retryable failure happened because there was no network at
  /// all, as opposed to because the server was having a bad moment.
  ///
  /// Two independent signals, because neither is available everywhere: the
  /// connectivity stream's last verdict (absent in unit tests and previews,
  /// where it stays null — "unknown", never "offline"), and the shape of
  /// the failure itself. A transport-loss error is conclusive on its own.
  bool _isOfflineFailure(Object error) {
    if (_offlineObserved ?? false) return true;
    if (error is TimeoutException) return true;
    final raw = error is FirebaseFunctionsException
        ? '${error.code} ${error.message ?? ''}'.toLowerCase()
        : error.toString().toLowerCase();
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('network-request-failed') ||
        raw.contains('no internet');
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
      // Preserve the stable callable code for safe UI classification. The
      // backend message can contain useful diagnostics for a future support
      // export, but presentation code must never render it verbatim.
      return message == null || message.isEmpty
          ? error.code
          : '${error.code}:$message';
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
        final wasOffline = _offlineObserved ?? false;
        _offlineObserved = offline;
        if (offline) return;
        if (wasOffline) {
          // Crossing back online is the moment to undo what an outage did
          // to the budget, before anything is attempted again.
          unawaited(_reviveAndFlush());
          return;
        }
        unawaited(
          flushOutbox().catchError((Object error) {
            debugPrint('Outbox drain on connectivity change failed: $error');
          }),
        );
        unawaited(
          flushAttachmentOutbox().catchError((Object error) {
            debugPrint('Attachment drain on connectivity failed: $error');
          }),
        );
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

  /// Returns transport-exhausted entries to the queue and drains it.
  ///
  /// Defensive throughout: this runs from a connectivity callback with no
  /// caller to receive an error, and a device with an unusable media store
  /// must still get its text messages out.
  Future<void> _reviveAndFlush() async {
    try {
      final queue = outbox;
      await queue.reviveDeferredFailures();
      unawaited(
        _flushOutbox(queue).catchError((Object error) {
          debugPrint('Outbox drain after reconnect failed: $error');
        }),
      );
    } catch (error) {
      debugPrint('Outbox revival after reconnect failed: $error');
    }
    try {
      final mediaQueue = attachmentOutbox;
      await mediaQueue.reviveDeferredFailures();
      unawaited(
        _flushAttachmentOutbox(mediaQueue).catchError((Object error) {
          debugPrint('Attachment drain after reconnect failed: $error');
        }),
      );
    } catch (error) {
      debugPrint('Attachment revival after reconnect failed: $error');
    }
  }

  /// Restores and resumes persisted work when the authenticated shell starts.
  /// No new message is required to wake a queue left by an earlier process.
  Future<void> resumeOutbox() async {
    final queue = outbox;
    await queue.load();
    final mediaQueue = attachmentOutbox;
    await mediaQueue.load();
    _listenForConnectivity();
    // Repairs what earlier builds did to devices that spent a couple of
    // minutes without network: those entries are terminal only because the
    // transport budget ran out, never because the server refused. Their
    // request ids are preserved, so a send that secretly landed replays.
    await Future.wait<Object?>([
      queue.reviveDeferredFailures(),
      mediaQueue.reviveDeferredFailures(),
    ]);
    // These queues also drain independently when connectivity returns. A
    // slow text callable must not hold every persisted attachment on restart.
    // Each drain retains its own ordering, account and single-flight guards.
    await Future.wait<void>([
      _flushOutbox(queue),
      _flushAttachmentOutbox(mediaQueue),
    ]);
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
    attachmentDelivery.dispose();
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
    final (queue, entry) = await _queueImageMessage(
      conversationId: conversationId,
      image: image,
    );
    await _deliverAttachment(entry.id, queue: queue);
  }

  /// Persists a selected photo locally and returns as soon as it is safe.
  /// Reserve, upload and finalize continue through the visible outbox card.
  Future<String> enqueueImageMessage({
    required String conversationId,
    required XFile image,
  }) async {
    final (queue, entry) = await _queueImageMessage(
      conversationId: conversationId,
      image: image,
    );
    unawaited(
      _deliverAttachment(entry.id, queue: queue).catchError((Object _) {}),
    );
    return entry.id;
  }

  Future<(DirectAttachmentOutbox, DirectAttachmentOutboxEntry)>
  _queueImageMessage({
    required String conversationId,
    required XFile image,
  }) async {
    // Capture the account-scoped queue before the first platform/file await.
    // A picker read that finishes after sign-out must never select the next
    // account's queue simply because `attachmentOutbox` was resolved late.
    final capture = _captureAttachmentQueueOwner();
    await capture.queue.load();
    _requireAttachmentQueueOwner(capture);
    final declaredLength = await image.length();
    _requireAttachmentQueueOwner(capture);
    if (declaredLength < 128 || declaredLength > directImageMaxBytes) {
      throw StateError('Choose a photo smaller than 8 MB.');
    }
    final source = DirectAttachmentPayloadSource.pickedFile(
      image,
      length: declaredLength,
    );
    final digest = await source.digest();
    _requireAttachmentQueueOwner(capture);
    if (digest.length != declaredLength ||
        digest.length < 128 ||
        digest.length > directImageMaxBytes) {
      throw StateError('Choose a photo smaller than 8 MB.');
    }
    final contentType = _imageContentType(image);
    _requireAttachmentQueueOwner(capture);
    final queued = await capture.queue.enqueueSourceWithDisposition(
      fingerprint: digest.fingerprint,
      conversationId: conversationId,
      type: MessageType.image,
      contentType: contentType,
      durationSeconds: null,
      source: source.verifiedAgainst(digest.fingerprint),
      reserveRequestId: _newRequestId(),
      finalizeRequestId: _newRequestId(),
    );
    final entry = queued.entry;
    if (!_stillOwnsAttachmentQueue(capture)) {
      await _rejectAttachmentAfterOwnerChange(
        capture,
        entry,
        created: queued.created,
      );
    }
    _listenForConnectivity();
    return (capture.queue, entry);
  }

  /// Sends a short private video through the same server-reserved,
  /// participant-only attachment pipeline as photos and voice messages.
  Future<void> sendVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    final (queue, entry) = await _queueVideoMessage(
      conversationId: conversationId,
      video: video,
      durationSeconds: durationSeconds,
    );
    await _deliverAttachment(entry.id, queue: queue);
  }

  /// Persists a selected video locally and lets its visible outbox card own
  /// the network work, so the composer is not locked for the whole upload.
  Future<String> enqueueVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    final (queue, entry) = await _queueVideoMessage(
      conversationId: conversationId,
      video: video,
      durationSeconds: durationSeconds,
    );
    unawaited(
      _deliverAttachment(entry.id, queue: queue).catchError((Object _) {}),
    );
    return entry.id;
  }

  Future<(DirectAttachmentOutbox, DirectAttachmentOutboxEntry)>
  _queueVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    if (durationSeconds < 1 || durationSeconds > directVideoMaxSeconds) {
      throw StateError('Videos must be between 1 and 60 seconds.');
    }
    final capture = _captureAttachmentQueueOwner();
    await capture.queue.load();
    _requireAttachmentQueueOwner(capture);
    final declaredLength = await video.length();
    _requireAttachmentQueueOwner(capture);
    if (declaredLength < 1024 || declaredLength > directVideoMaxBytes) {
      throw StateError('Choose a video smaller than 64 MB.');
    }
    final source = DirectAttachmentPayloadSource.pickedFile(
      video,
      length: declaredLength,
    );
    final digest = await source.digest(prefixBytes: 4096);
    _requireAttachmentQueueOwner(capture);
    if (digest.length != declaredLength ||
        digest.length < 1024 ||
        digest.length > directVideoMaxBytes) {
      throw StateError('Choose a video smaller than 64 MB.');
    }
    _requireAttachmentQueueOwner(capture);
    final queued = await capture.queue.enqueueSourceWithDisposition(
      fingerprint: digest.fingerprint,
      conversationId: conversationId,
      type: MessageType.video,
      contentType: _videoContentType(video, digest.prefix),
      durationSeconds: durationSeconds,
      source: source.verifiedAgainst(digest.fingerprint),
      reserveRequestId: _newRequestId(),
      finalizeRequestId: _newRequestId(),
    );
    final entry = queued.entry;
    if (!_stillOwnsAttachmentQueue(capture)) {
      await _rejectAttachmentAfterOwnerChange(
        capture,
        entry,
        created: queued.created,
      );
    }
    _listenForConnectivity();
    return (capture.queue, entry);
  }

  /// Copies a finished recording into the durable outbox and returns the queue
  /// entry, without contacting the server.
  ///
  /// STREAMED, NOT BUFFERED. This used to start with `audio.readBytes()` —
  /// the whole recording resident, hashed as one buffer, then written to disk
  /// a second time while the first copy was still alive. A finished recording
  /// is already a file (or a browser Blob); it is read once, in chunks, to
  /// fingerprint it and once more to copy it, and it is never all in the heap.
  /// Nothing the backend sees changes: no device path is declared anywhere,
  /// and the reservation still carries only type, contentType and duration.
  Future<(DirectAttachmentOutbox, DirectAttachmentOutboxEntry)>
  _queueVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) async {
    final problem = validateRecordedAudio(audio);
    if (problem != null) throw problem;
    if (durationSeconds < 1 || durationSeconds > directVoiceMaxSeconds) {
      throw StateError('Voice messages must be between 1 and 60 seconds.');
    }
    final capture = _captureAttachmentQueueOwner();
    await capture.queue.load();
    _requireAttachmentQueueOwner(capture);
    final contentType = normalizeAudioContentType(audio.contentType);
    final source = DirectAttachmentPayloadSource.recording(audio);
    final digest = await source.digest();
    _requireAttachmentQueueOwner(capture);
    if (digest.length != audio.byteLength) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The recording changed before it could be saved safely.',
        action: 'Record it again.',
      );
    }
    _requireAttachmentQueueOwner(capture);
    final queued = await capture.queue.enqueueSourceWithDisposition(
      fingerprint: digest.fingerprint,
      conversationId: conversationId,
      type: MessageType.voice,
      contentType: contentType,
      durationSeconds: durationSeconds,
      source: source.verifiedAgainst(digest.fingerprint),
      reserveRequestId: _newRequestId(),
      finalizeRequestId: _newRequestId(),
    );
    final entry = queued.entry;
    if (!_stillOwnsAttachmentQueue(capture)) {
      await _rejectAttachmentAfterOwnerChange(
        capture,
        entry,
        created: queued.created,
      );
    }
    _listenForConnectivity();
    return (capture.queue, entry);
  }

  /// Publishes an already-finished AAC/MP4 recording as a private voice DM and
  /// waits for the server to accept it.
  ///
  /// The recording is retained by the durable outbox, not by the caller, so a
  /// failed finalize is retried from the queued copy rather than by asking
  /// somebody to record again.
  Future<void> sendVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) async {
    final (queue, entry) = await _queueVoiceMessage(
      conversationId: conversationId,
      audio: audio,
      durationSeconds: durationSeconds,
    );
    await _deliverAttachment(entry.id, queue: queue);
  }

  /// Queues a voice message durably and returns as soon as it cannot be lost,
  /// leaving delivery to run in the background.
  ///
  /// This is what the recorder sheet awaits. The point at which a voice
  /// message becomes safe is the enqueue — bytes copied into app-private
  /// storage, manifest persisted — not the finalize, so holding a modal open
  /// across two callables and an upload bought the person nothing but a
  /// spinner. Everything after the enqueue is reported on the queued card in
  /// the thread: progress while it uploads, "Waiting for connection" while it
  /// retries, "Not sent" with Retry and Discard when it gives up. Returns the
  /// outbox entry id so a caller can follow exactly that entry.
  Future<String> enqueueVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) async {
    final (queue, entry) = await _queueVoiceMessage(
      conversationId: conversationId,
      audio: audio,
      durationSeconds: durationSeconds,
    );
    // The delivery's own error handling is the outbox: it marks the entry
    // retrying or failed before it rethrows, and the queued card renders that.
    // Rethrowing into an unawaited future would only reach the zone handler.
    unawaited(
      _deliverAttachment(entry.id, queue: queue).catchError((Object _) {}),
    );
    return entry.id;
  }

  Future<void> flushAttachmentOutbox() =>
      _flushAttachmentOutbox(attachmentOutbox);

  Future<void> discardQueuedAttachment(String entryId) =>
      attachmentOutbox.discard(entryId);

  /// Removes durable media work only after the canonical conversation stream
  /// proves that this account published the same reserved media message.
  ///
  /// A finalize callable can commit and then lose its response. In that case
  /// the canonical snapshot is stronger evidence than the local retry state,
  /// including a max-attempt `failed` entry. Matching the sender, conversation,
  /// message id and media type prevents an unrelated or malformed document
  /// from deleting somebody's pending bytes.
  Future<void> reconcileCommittedAttachments(Iterable<Message> messages) async {
    final queue = attachmentOutbox;
    final ownerId = _auth.currentUser?.uid;
    if (ownerId == null || ownerId != queue.ownerId) return;
    await queue.load();
    if (_auth.currentUser?.uid != ownerId) return;

    final canonical = <String>{
      for (final message in messages)
        if (message.senderId == ownerId &&
            message.type != MessageType.text &&
            message.type != MessageType.gif)
          '${message.conversationId}\u0000${message.id}\u0000${message.type.name}',
    };
    if (canonical.isEmpty) return;

    final completed = queue.entries
        .where((entry) {
          final reservation = entry.reservation;
          if (reservation == null || reservation.messageId.isEmpty) {
            return false;
          }
          if (reservation.conversationId != entry.conversationId ||
              reservation.type != entry.type) {
            return false;
          }
          return canonical.contains(
            '${entry.conversationId}\u0000${reservation.messageId}\u0000${entry.type.name}',
          );
        })
        .toList(growable: false);

    for (final entry in completed) {
      if (_auth.currentUser?.uid != ownerId) return;
      await queue.complete(entry.id);
    }
  }

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
    final ownerId = queue.ownerId;
    bool stillOwnsQueue() =>
        queue.ownerId == ownerId && _auth.currentUser?.uid == ownerId;
    if (!stillOwnsQueue()) return;
    var entry = queue.entry(entryId);
    if (entry == null) return;
    attachmentDelivery.report(entryId, DirectAttachmentDeliveryStage.preparing);
    try {
      // A lease can expire while the process is offline or between upload and
      // finalize. Rotation is bounded and atomic in the manifest; the durable
      // bytes never move and every new server input gets fresh idempotency IDs.
      for (var rotations = 0; rotations < 3; rotations++) {
        entry = queue.entry(entryId);
        if (entry == null || !stillOwnsQueue()) return;

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
              attachmentDelivery.report(
                entryId,
                DirectAttachmentDeliveryStage.finalizing,
              );
              final finalized = await _finalizeDirectAttachment(
                reservation,
                entry.generation!,
                requestId: entry.finalizeRequestId,
                ownerId: ownerId,
              );
              if (!finalized || !stillOwnsQueue()) return;
              await queue.complete(entry.id);
              return;
            } on FirebaseFunctionsException catch (error) {
              if (_isAuthoritativeReservationInvalid(error)) {
                entry = (await queue.rotateRejectedReservation(
                  entry.id,
                  expectedReserveRequestId: entry.reserveRequestId,
                  reserveRequestId: _newRequestId(),
                  finalizeRequestId: _newRequestId(),
                ))!;
                continue;
              }
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
            attachmentDelivery.report(
              entryId,
              DirectAttachmentDeliveryStage.reserving,
            );
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
          if (!stillOwnsQueue()) return;
          entry = (await queue.setReservation(
            entry.id,
            _reservationRecord(reservation, queue: queue),
          ))!;
          if (!stillOwnsQueue()) return;
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
            attachmentDelivery.report(
              entryId,
              DirectAttachmentDeliveryStage.uploading,
              progress: 0,
            );
            generation = await _uploadDirectAttachment(
              reservation,
              contentType: entry.contentType,
              ownerId: ownerId,
              upload: (reference, metadata) => queue.payloadStore.upload(
                queue.accountNamespace,
                entry!.id,
                reference,
                metadata,
                onProgress: (value) => attachmentDelivery.report(
                  entryId,
                  DirectAttachmentDeliveryStage.uploading,
                  progress: value,
                ),
              ),
            );
            if (generation == null) return;
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
          if (!stillOwnsQueue()) return;
          entry = (await queue.setGeneration(entry.id, generation))!;
          if (!stillOwnsQueue()) return;
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
        if (!stillOwnsQueue()) return;
        try {
          attachmentDelivery.report(
            entryId,
            DirectAttachmentDeliveryStage.finalizing,
          );
          final finalized = await _finalizeDirectAttachment(
            reservation,
            generation,
            requestId: entry.finalizeRequestId,
            ownerId: ownerId,
          );
          if (!finalized) return;
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
        if (!stillOwnsQueue()) return;
        await queue.complete(entry.id);
        return;
      }
      throw StateError('The attachment reservation kept expiring. Try again.');
    } catch (error, stackTrace) {
      if (_isAmbiguousAttachmentFailure(error)) {
        if (_isOfflineFailure(error)) {
          await queue.markDeferred(entryId, error.runtimeType.toString());
        } else {
          await queue.markRetry(entryId, error);
        }
        _scheduleAttachmentDrain(queue);
      } else {
        await queue.markFailed(entryId, error);
        recordCallableRefusalIfTerminal(
          callable: 'finalizeDirectMessageAttachment',
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    } finally {
      // The queued card falls back to the durable status — "Waiting for
      // connection", "Not sent" — the moment there is no live delivery, which
      // is exactly true once this returns or throws.
      attachmentDelivery.clear(entryId);
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
      if (_isAuthoritativeReservationInvalid(error)) return false;
      // A callable can commit the canonical message and still lose its ACK.
      // Keep this exactly aligned with the text outbox so background
      // cancellation and protocol-level INTERNAL/UNKNOWN responses replay the
      // same idempotency request instead of becoming a false permanent
      // failure. This branch must precede FirebaseException because
      // FirebaseFunctionsException extends it.
      return _isAmbiguousTransportFailure(error);
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
    if (error is! FirebaseException) return false;
    final message = (error.message ?? '').trim().toLowerCase();
    // These are the production finalize responses. They are authoritative,
    // not ambiguous transport failures, even though their callable codes also
    // appear in the generic retry set. Exact text keeps an unrelated deadline
    // or transaction abort on the stable idempotency identity.
    if (error.code == 'deadline-exceeded' &&
        message == 'the attachment reservation expired.') {
      return true;
    }
    if (error.code == 'aborted' &&
        message == 'the attachment reservation changed. try again.') {
      return true;
    }
    if (error.code != 'failed-precondition') return false;
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

  String _videoContentType(XFile video, Uint8List bytes) {
    final sniffed = _sniffVideoContentType(bytes);
    if (sniffed != null) return sniffed;

    final declared = video.mimeType?.split(';').first.trim().toLowerCase();
    if (declared == 'video/mp4' ||
        declared == 'video/quicktime' ||
        declared == 'video/webm') {
      return declared!;
    }
    final lower = video.name.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    throw StateError('Choose an MP4, MOV, or WebM video.');
  }

  /// iOS can expose an ISO-BMFF recording as `.MOV`/`video/quicktime` even
  /// when its immutable bytes use an MP4 brand. Bind the reservation to the
  /// bytes when possible so Storage metadata and the trusted server probe
  /// agree. This is only an early client hint; the backend still inspects the
  /// complete generation and its audio/video tracks before publishing.
  String? _sniffVideoContentType(Uint8List bytes) {
    if (bytes.lengthInBytes >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return 'video/webm';
    }

    final limit = min(bytes.lengthInBytes, 4096);
    var offset = 0;
    while (offset + 12 <= limit) {
      final size =
          (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final isFileType =
          bytes[offset + 4] == 0x66 &&
          bytes[offset + 5] == 0x74 &&
          bytes[offset + 6] == 0x79 &&
          bytes[offset + 7] == 0x70;
      if (isFileType) {
        final majorBrand = String.fromCharCodes(
          bytes.sublist(offset + 8, offset + 12),
        );
        return majorBrand == 'qt  ' || majorBrand == 'M4V '
            ? 'video/quicktime'
            : 'video/mp4';
      }
      if (size < 8 || offset + size > limit) break;
      offset += size;
    }
    return null;
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
    required String ownerId,
  }) {
    return SettableMetadata(
      contentType: contentType,
      customMetadata: _attachmentCustomMetadata(reservation, ownerId: ownerId),
    );
  }

  /// Uploads to one immutable server reservation even when the Storage SDK
  /// loses the response after committing the object. A retry never reserves a
  /// second path: first it asks Storage whether the exact object/metadata is
  /// already present, then it retries the same upload target. This avoids both
  /// duplicate messages and abandoned objects on ambiguous network failures.
  Future<String?> _uploadDirectAttachment(
    _DirectAttachmentReservation reservation, {
    required String contentType,
    required String ownerId,
    required Future<String> Function(
      Reference reference,
      SettableMetadata metadata,
    )
    upload,
  }) async {
    final reference = _storage.ref(reservation.storagePath);
    final metadata = _attachmentMetadata(
      reservation,
      contentType: contentType,
      ownerId: ownerId,
    );
    Object? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (_auth.currentUser?.uid != ownerId) return null;
      try {
        final generation = await upload(reference, metadata);
        if (_auth.currentUser?.uid != ownerId) return null;
        if (generation.isEmpty) {
          throw StateError('The uploaded attachment could not be verified.');
        }
        return generation;
      } catch (error) {
        if (_auth.currentUser?.uid != ownerId) return null;
        lastError = error;
        try {
          final committedGeneration = await _committedAttachmentGeneration(
            reference,
            reservation,
            contentType: contentType,
            ownerId: ownerId,
          );
          if (committedGeneration == null) return null;
          return committedGeneration;
        } catch (_) {
          if (_auth.currentUser?.uid != ownerId) return null;
          if (attempt == 2) throw error;
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
          if (_auth.currentUser?.uid != ownerId) return null;
        }
      }
    }

    throw lastError ?? StateError('The attachment could not be uploaded.');
  }

  Future<String?> _committedAttachmentGeneration(
    Reference reference,
    _DirectAttachmentReservation reservation, {
    required String contentType,
    required String ownerId,
  }) async {
    if (_auth.currentUser?.uid != ownerId) return null;
    final stored = await reference.getMetadata();
    if (_auth.currentUser?.uid != ownerId) return null;
    final expected = _attachmentCustomMetadata(reservation, ownerId: ownerId);
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
    _DirectAttachmentReservation reservation, {
    required String ownerId,
  }) {
    return {
      'yovoiceConversationId': reservation.conversationId,
      'yovoiceMessageId': reservation.messageId,
      'yovoiceMessagePath':
          'conversations/${reservation.conversationId}/messages/${reservation.messageId}',
      'yovoiceMediaType': reservation.type.name,
      'yovoiceOwnerUid': ownerId,
    };
  }

  Future<bool> _finalizeDirectAttachment(
    _DirectAttachmentReservation reservation,
    String generation, {
    required String requestId,
    required String ownerId,
  }) async {
    final functions = _functions;
    if (functions == null) {
      throw StateError('Private media sharing needs a connection to YO Voice.');
    }
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_auth.currentUser?.uid != ownerId) return false;
      try {
        await functions.httpsCallable('finalizeDirectMessageAttachment').call({
          'conversationId': reservation.conversationId,
          'messageId': reservation.messageId,
          'objectGeneration': generation,
          'requestId': requestId,
        });
        return _auth.currentUser?.uid == ownerId;
      } catch (error) {
        if (_auth.currentUser?.uid != ownerId) return false;
        lastError = error;
        if (_isAuthoritativeReservationInvalid(error)) rethrow;
        final retryable = _isAmbiguousTransportFailure(error);
        if (!retryable || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        if (_auth.currentUser?.uid != ownerId) return false;
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
    final request = <String, Object?>{
      'conversationId': conversationId,
      'preference': 'archived',
      'enabled': true,
      'requestId': _newRequestId(),
    };
    final called = await _tryIdempotentCallableAfterAmbiguousTransport(
      'setDirectConversationPreference',
      request,
    );

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
    final request = <String, Object?>{
      'conversationId': conversationId,
      'preference': 'archived',
      'enabled': false,
      'requestId': _newRequestId(),
    };
    final called = await _tryIdempotentCallableAfterAmbiguousTransport(
      'setDirectConversationPreference',
      request,
    );

    if (called) {
      return;
    }

    final userId = _currentUserId;

    await _conversations.doc(conversationId).update({
      'archivedBy': FieldValue.arrayRemove([userId]),
    });
  }

  /// Deletes this conversation FOR THIS ACCOUNT ONLY.
  ///
  /// The other participant keeps their copy, is not told, and sees no change.
  /// If they write again the thread comes back holding only what arrives from
  /// that point on — the server records a cut-off, and Firestore Rules refuse
  /// to serve anything at or below it (see `firestore.rules`).
  ///
  /// There is no client fallback. Every other participant-owned preference on
  /// this service degrades to a direct write when the callable is missing, but
  /// a direct write here would be refused by Rules AND would leave the caller
  /// believing a deletion happened. A build that cannot reach the callable
  /// says so instead.
  Future<void> deleteConversationForMe(String conversationId) async {
    final functions = _functions;
    if (_preferLegacyBehaviour || functions == null) {
      throw StateError(
        'This build cannot delete conversations. Update YO Voice.',
      );
    }
    try {
      await functions.httpsCallable('deleteDirectConversationForMe').call({
        'conversationId': conversationId,
        'requestId': _newRequestId(),
      });
    } catch (error) {
      if (_isCallableUnavailable(error)) {
        throw StateError(
          'This build cannot delete conversations. Update YO Voice.',
        );
      }
      rethrow;
    }
    // Only after the server has accepted. Queued work for a thread the user
    // removed must not be delivered later and resurrect it with content they
    // believed was gone — the same boundary `clearLocalSensitiveStateForUser`
    // draws at sign-out, drawn here per conversation.
    await _purgeLocalConversationState(conversationId);
  }

  Future<void> _purgeLocalConversationState(String conversationId) async {
    await outbox.purgeConversation(conversationId);
    await attachmentOutbox.purgeConversation(conversationId);
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

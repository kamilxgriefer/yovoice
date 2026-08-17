import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
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
  });

  final String conversationId;
  final String messageId;
  final String storagePath;
  final MessageType type;

  factory _DirectAttachmentReservation.fromResponse(
    Map<Object?, Object?> data,
  ) {
    final conversationId = data['conversationId'];
    final messageId = data['messageId'];
    final storagePath = data['storagePath'];
    final typeValue = data['type'];
    final type = MessageType.values.where((item) => item.name == typeValue);
    if (conversationId is! String ||
        conversationId.isEmpty ||
        messageId is! String ||
        messageId.isEmpty ||
        storagePath is! String ||
        storagePath.isEmpty ||
        type.isEmpty ||
        type.first == MessageType.text) {
      throw StateError('Malformed attachment reservation from YO Voice.');
    }
    return _DirectAttachmentReservation(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
      type: type.first,
    );
  }
}

class _PendingDirectAttachment {
  _PendingDirectAttachment({
    required this.type,
    required this.contentType,
    required this.durationSeconds,
    required this.reserveRequestId,
    required this.finalizeRequestId,
  });

  final MessageType type;
  final String contentType;
  final int? durationSeconds;
  final String reserveRequestId;
  final String finalizeRequestId;
  _DirectAttachmentReservation? reservation;
  String? generation;
}

class MessageService {
  MessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    // Compatibility injection for existing previews/tests. Notification
    // delivery is now derived by the backend from the committed message.
    NotificationService? notificationService,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _legacyNotificationService = notificationService,
       _functionsOverride = functions,
       _storageOverride = storage;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService? _legacyNotificationService;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage? _storageOverride;
  final Map<String, _PendingDirectAttachment> _pendingImageAttachments = {};
  final Expando<Map<String, _PendingDirectAttachment>>
  _pendingVoiceAttachments = Expando('directVoiceAttachments');

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

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

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
    return _conversations.doc(conversationId).snapshots().map((snapshot) {
      final typing = snapshot.data()?['typing'] as Map?;
      final value = typing?[otherUserId] as Map?;
      final isTyping = value?['isTyping'] as bool? ?? false;
      final updatedAt = value?['updatedAt'];

      if (!isTyping || updatedAt is! Timestamp) {
        return false;
      }

      return DateTime.now().difference(updatedAt.toDate()).inSeconds < 8;
    });
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

    if (called) {
      return;
    }

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

  Future<void> sendTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {
    final currentUserId = _currentUserId;
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return;
    }

    final called = await _tryCallable('sendDirectMessage', {
      'conversationId': conversationId,
      'text': trimmed,
      'requestId': _newRequestId(),
      'replyToMessageId': replyTo?.id,
    });

    if (called) {
      // The callable is authoritative and has already performed the whole
      // send inside one server transaction: it created the canonical
      // message document and updated the conversation summary, the unread
      // counts and the typing state. Anything written from here would be a
      // SECOND message document under an auto-id and a SECOND
      // `unreadCounts.<recipient>` increment. The client write below is the
      // fallback for when the callable does not answer — never a follow-up
      // to when it does.
      return;
    }

    await _sendTextMessageDirectly(
      conversationId: conversationId,
      recipientId: recipientId,
      senderId: currentUserId,
      text: trimmed,
      replyTo: replyTo,
    );
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
    final operationKey =
        '$conversationId:$contentType:${sha256.convert(bytes)}';
    final pending = _pendingImageAttachments.putIfAbsent(
      operationKey,
      () => _newPendingAttachment(
        type: MessageType.image,
        contentType: contentType,
      ),
    );
    try {
      final reservation = pending.reservation ??=
          await _reserveDirectAttachment(
            conversationId: conversationId,
            type: pending.type,
            contentType: pending.contentType,
            durationSeconds: pending.durationSeconds,
            requestId: pending.reserveRequestId,
          );
      final generation = pending.generation ??= await _uploadDirectAttachment(
        reservation,
        contentType: contentType,
        upload: (reference, metadata) async {
          final snapshot = await reference.putData(bytes, metadata);
          final stored = await snapshot.ref.getMetadata();
          return stored.generation ?? '';
        },
      );
      await _finalizeDirectAttachment(
        reservation,
        generation,
        requestId: pending.finalizeRequestId,
      );
      _pendingImageAttachments.remove(operationKey);
    } catch (error) {
      if (!_isAmbiguousAttachmentFailure(error)) {
        _pendingImageAttachments.remove(operationKey);
      }
      rethrow;
    }
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
    final operations =
        _pendingVoiceAttachments[audio] ?? <String, _PendingDirectAttachment>{};
    _pendingVoiceAttachments[audio] = operations;
    final pending = operations.putIfAbsent(
      conversationId,
      () => _newPendingAttachment(
        type: MessageType.voice,
        contentType: contentType,
        durationSeconds: durationSeconds,
      ),
    );
    if (pending.contentType != contentType ||
        pending.durationSeconds != durationSeconds) {
      throw StateError(
        'This recording already has a different pending send contract.',
      );
    }
    try {
      final reservation = pending.reservation ??=
          await _reserveDirectAttachment(
            conversationId: conversationId,
            type: pending.type,
            contentType: pending.contentType,
            durationSeconds: pending.durationSeconds,
            requestId: pending.reserveRequestId,
          );
      final generation = pending.generation ??= await _uploadDirectAttachment(
        reservation,
        contentType: contentType,
        upload: audio.uploadTo,
      );
      await _finalizeDirectAttachment(
        reservation,
        generation,
        requestId: pending.finalizeRequestId,
      );
      operations.remove(conversationId);
    } catch (error) {
      if (!_isAmbiguousAttachmentFailure(error)) {
        operations.remove(conversationId);
      }
      rethrow;
    }
  }

  _PendingDirectAttachment _newPendingAttachment({
    required MessageType type,
    required String contentType,
    int? durationSeconds,
  }) {
    return _PendingDirectAttachment(
      type: type,
      contentType: contentType,
      durationSeconds: durationSeconds,
      reserveRequestId: _newRequestId(),
      finalizeRequestId: _newRequestId(),
    );
  }

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

  /// The client-side send, used when `sendDirectMessage` is unavailable
  /// (no Firebase app, or the callable is not deployed) and by the
  /// previews/tests that inject a [NotificationService].
  ///
  /// Deliberately mirrors what the callable leaves behind, key for key:
  /// `functions/messaging/direct_integrity.js`'s `validateMessage` demands
  /// an EXACT key set, so a message written without `schemaVersion` and
  /// `sequence` is one the server can never edit, delete, react to or be
  /// replied to again ("The direct message schema is not canonical").
  /// `sequence` has to be derived from the conversation, hence a
  /// transaction rather than a batch.
  Future<void> _sendTextMessageDirectly({
    required String conversationId,
    required String recipientId,
    required String senderId,
    required String text,
    required Message? replyTo,
  }) async {
    final legacyNotifications = _legacyNotificationService;
    bool suppressBell = false;
    if (legacyNotifications != null) {
      suppressBell =
          (await _users
                  .doc(recipientId)
                  .collection('friends')
                  .doc(senderId)
                  .get())
              .exists;
    }

    final conversation = _conversations.doc(conversationId);
    final message = conversation.collection('messages').doc();
    final now = Timestamp.now();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(conversation);
      final previous =
          (snapshot.data()?['lastMessageSequence'] as num?)?.toInt() ?? 0;
      final sequence = previous < 0 ? 1 : previous + 1;

      transaction.set(message, {
        'schemaVersion': 2,
        'sequence': sequence,
        'conversationId': conversationId,
        'senderId': senderId,
        'type': MessageType.text.name,
        'content': text,
        'mediaUrl': null,
        'durationSeconds': null,
        'sentAt': now,
        'readBy': [senderId],
        'reactions': <String, String>{},
        'isDeleted': false,
        'editedAt': null,
        'replyToMessageId': replyTo?.id,
        'replyToSenderId': replyTo?.senderId,
        'replyToContent': replyTo == null
            ? null
            : replyTo.isDeleted
            ? 'Message deleted'
            : _replyPreview(replyTo.previewText()),
      });

      transaction.update(conversation, {
        'lastMessage': text,
        'lastMessageId': message.id,
        'lastMessageSequence': sequence,
        'lastMessageType': MessageType.text.name,
        'lastMessageSenderId': senderId,
        'updatedAt': now,
        'archivedBy': <String>[],
        'unreadCounts.$senderId': 0,
        'unreadCounts.$recipientId': FieldValue.increment(1),
        'typing.$senderId.isTyping': false,
        'typing.$senderId.updatedAt': now,
      });
    });

    if (legacyNotifications == null) {
      return;
    }

    final type = replyTo?.senderId == recipientId
        ? NotificationType.reply
        : NotificationType.directMessage;

    try {
      await legacyNotifications.notify(
        recipientId: recipientId,
        type: type,
        targetId: conversationId,
        suppressBell: suppressBell,
      );
    } catch (error) {
      // Fail toward VISIBLE: a rejected bell suppression must not cost the
      // recipient the record that carries the push.
      if (!suppressBell) {
        debugPrint('MessageService legacy notification failed: $error');
        return;
      }
      await legacyNotifications.notify(
        recipientId: recipientId,
        type: type,
        targetId: conversationId,
      );
    }
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
    final called = await _tryCallable('markDirectConversationRead', {
      'conversationId': conversationId,
      'requestId': _newRequestId(),
    });

    if (called) {
      return;
    }

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

  /// The server caps `replyToContent` at 240 characters and rejects the
  /// whole message as non-canonical past it, so the fallback truncates the
  /// same way rather than writing a reply that can never be edited again.
  static String _replyPreview(String value) =>
      value.length <= 240 ? value : value.substring(0, 240);

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

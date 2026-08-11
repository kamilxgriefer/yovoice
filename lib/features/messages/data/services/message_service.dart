import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

class ChatPresence {
  const ChatPresence({required this.isOnline, required this.lastSeen});

  final bool isOnline;
  final DateTime? lastSeen;
}

class MessageService {
  MessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _notifications = notificationService ?? NotificationService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService _notifications;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

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
    return _users.doc(userId).snapshots().map((snapshot) {
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
              ? _displayNameFromEmail(otherEmail)
              : otherDisplayName.trim(),
        },
        'participantEmails': {
          currentUser.uid: currentUser.email ?? '',
          otherUserId: otherEmail,
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

    final conversation = _conversations.doc(conversationId);
    final message = conversation.collection('messages').doc();
    final now = Timestamp.now();
    final batch = _firestore.batch();

    batch.set(message, {
      'conversationId': conversationId,
      'senderId': currentUserId,
      'type': MessageType.text.name,
      'content': trimmed,
      'mediaUrl': null,
      'durationSeconds': null,
      'sentAt': now,
      'readBy': [currentUserId],
      'reactions': <String, String>{},
      'isDeleted': false,
      'editedAt': null,
      'replyToMessageId': replyTo?.id,
      'replyToSenderId': replyTo?.senderId,
      'replyToContent': replyTo == null
          ? null
          : replyTo.isDeleted
          ? 'Message deleted'
          : replyTo.previewText(),
    });

    batch.update(conversation, {
      'lastMessage': trimmed,
      'lastMessageType': MessageType.text.name,
      'lastMessageSenderId': currentUserId,
      'updatedAt': now,
      'archivedBy': <String>[],
      'unreadCounts.$currentUserId': 0,
      'unreadCounts.$recipientId': FieldValue.increment(1),
      'typing.$currentUserId.isTyping': false,
      'typing.$currentUserId.updatedAt': now,
    });

    await batch.commit();

    final isReplyToRecipient =
        replyTo != null && replyTo.senderId == recipientId;

    // Routing decision, made at the source: a DM to an EXISTING FRIEND
    // already surfaces through the conversation's unreadCounts (Chats
    // badge, unread cards), so its notification record is written
    // bell-suppressed — it still exists (that document is what fires the
    // push) but never duplicates into the global bell. A non-friend's
    // message keeps the bell entry: that IS the message-request moment.
    var suppressBell = false;
    try {
      final friendDoc = await _users
          .doc(currentUserId)
          .collection('friends')
          .doc(recipientId)
          .get();
      suppressBell = friendDoc.exists;
    } catch (_) {
      // Fail open: if friendship can't be read, keep the bell entry — a
      // redundant bell row for a friend beats silently hiding a
      // stranger's message request.
    }

    final type = isReplyToRecipient
        ? NotificationType.reply
        : NotificationType.directMessage;
    try {
      await _notifications.notify(
        recipientId: recipientId,
        type: type,
        targetId: conversationId,
        suppressBell: suppressBell,
      );
    } catch (_) {
      // The rules only accept a SUPPRESSED record when the recipient's
      // own friends list contains the sender. If our sender-side read
      // said "friend" but the write was rejected (asymmetric state, e.g.
      // mid-unfriend), fail toward VISIBLE so the recipient still gets
      // the record — and its push — rather than nothing.
      if (suppressBell) {
        try {
          await _notifications.notify(
            recipientId: recipientId,
            type: type,
            targetId: conversationId,
          );
        } catch (error) {
          // Best-effort — the message itself already sent above — but a
          // recipient silently losing both the bell row AND its push is
          // exactly the class of failure that hid the friend-request
          // outage, so it is named here.
          debugPrint(
            'MessageService: no notification could be written for this '
            'message (${error.runtimeType}). The message itself sent.',
          );
        }
      }
      // Best-effort — the message itself already sent above.
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

    if (reactions[userId] == emoji) {
      await reference.update({'reactions.$userId': FieldValue.delete()});
    } else {
      await reference.update({'reactions.$userId': emoji});
    }
  }

  Future<void> markConversationRead(String conversationId) async {
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
    final userId = _currentUserId;

    await _conversations.doc(conversationId).update({
      'mutedBy': muted
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> archiveConversation(String conversationId) async {
    final userId = _currentUserId;

    await _conversations.doc(conversationId).update({
      'archivedBy': FieldValue.arrayUnion([userId]),
      'unreadCounts.$userId': 0,
    });
  }

  Future<void> unarchiveConversation(String conversationId) async {
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';

class MessageService {
  MessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _conversations {
    return _firestore.collection('conversations');
  }

  String get _currentUserId {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in to use messages.');
    }

    return user.uid;
  }

  Stream<List<Conversation>> watchConversations() {
    final currentUserId = _currentUserId;

    return _conversations
        .where('participantIds', arrayContains: currentUserId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(Conversation.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<Message>> watchMessages(String conversationId) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(Message.fromFirestore)
              .toList(growable: false),
        );
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

    final conversationId = buildConversationId(
      currentUser.uid,
      otherUserId,
    );

    final conversationReference = _conversations.doc(conversationId);
    final now = Timestamp.now();

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(conversationReference);

      if (existing.exists) {
        return;
      }

      final currentDisplayName = _currentDisplayName(
        currentUser.displayName,
        currentUser.email,
      );

      transaction.set(conversationReference, <String, dynamic>{
        'participantIds': <String>[currentUser.uid, otherUserId],
        'participantNames': <String, String>{
          currentUser.uid: currentDisplayName,
          otherUserId: otherDisplayName.trim().isEmpty
              ? _displayNameFromEmail(otherEmail)
              : otherDisplayName.trim(),
        },
        'participantEmails': <String, String>{
          currentUser.uid: currentUser.email ?? '',
          otherUserId: otherEmail,
        },
        'participantPhotoUrls': <String, String>{
          currentUser.uid: currentUser.photoURL ?? '',
          otherUserId: otherPhotoUrl,
        },
        'unreadCounts': <String, int>{
          currentUser.uid: 0,
          otherUserId: 0,
        },
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
  }) async {
    final currentUserId = _currentUserId;
    final trimmedText = text.trim();

    if (trimmedText.isEmpty) {
      return;
    }

    final conversationReference = _conversations.doc(conversationId);
    final messageReference = conversationReference.collection('messages').doc();
    final now = Timestamp.now();

    final batch = _firestore.batch();

    batch.set(messageReference, <String, dynamic>{
      'conversationId': conversationId,
      'senderId': currentUserId,
      'type': MessageType.text.name,
      'content': trimmedText,
      'mediaUrl': null,
      'durationSeconds': null,
      'sentAt': now,
      'readBy': <String>[currentUserId],
      'isDeleted': false,
    });

    batch.update(conversationReference, <String, dynamic>{
      'lastMessage': trimmedText,
      'lastMessageType': MessageType.text.name,
      'lastMessageSenderId': currentUserId,
      'updatedAt': now,
      'unreadCounts.$currentUserId': 0,
      'unreadCounts.$recipientId': FieldValue.increment(1),
    });

    await batch.commit();
  }

  Future<void> markConversationRead(String conversationId) async {
    final currentUserId = _currentUserId;
    final conversationReference = _conversations.doc(conversationId);

    final latestMessages = await conversationReference
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(100)
        .get();

    final batch = _firestore.batch();

    batch.update(conversationReference, <String, dynamic>{
      'unreadCounts.$currentUserId': 0,
    });

    for (final document in latestMessages.docs) {
      final data = document.data();
      final senderId = data['senderId'] as String? ?? '';
      final readBy = List<String>.from(
        data['readBy'] as List<dynamic>? ?? const [],
      );

      if (senderId != currentUserId && !readBy.contains(currentUserId)) {
        batch.update(document.reference, <String, dynamic>{
          'readBy': FieldValue.arrayUnion(<String>[currentUserId]),
        });
      }
    }

    await batch.commit();
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final currentUserId = _currentUserId;
    final messageReference = _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    final message = await messageReference.get();
    final senderId = message.data()?['senderId'] as String? ?? '';

    if (senderId != currentUserId) {
      throw StateError('You can only delete your own messages.');
    }

    await messageReference.update(<String, dynamic>{
      'content': '',
      'mediaUrl': null,
      'isDeleted': true,
    });
  }

  static String buildConversationId(String firstUserId, String secondUserId) {
    final userIds = <String>[firstUserId, secondUserId]..sort();
    return '${userIds[0]}_${userIds[1]}';
  }

  static String _currentDisplayName(String? displayName, String? email) {
    final trimmedName = displayName?.trim() ?? '';

    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }

    return _displayNameFromEmail(email ?? '');
  }

  static String _displayNameFromEmail(String email) {
    final trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty) {
      return 'YoVoice user';
    }

    return trimmedEmail.split('@').first;
  }
}

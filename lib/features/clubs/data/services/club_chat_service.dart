import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';

class ClubChatService {
  ClubChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use club chat.');
    }
    return user;
  }

  CollectionReference<Map<String, dynamic>> _messages({
    required String clubId,
    required String channelId,
  }) {
    return _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('channels')
        .doc(channelId)
        .collection('messages');
  }

  Stream<List<ClubMessage>> watchMessages({
    required String clubId,
    required String channelId,
  }) {
    return _messages(clubId: clubId, channelId: channelId)
        .orderBy('sentAt', descending: true)
        .limit(250)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => ClubMessage.fromFirestore(
                  clubId: clubId,
                  channelId: channelId,
                  document: document,
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> sendTextMessage({
    required String clubId,
    required String channelId,
    required String text,
  }) async {
    final user = _user;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (normalized.length > 2000) {
      throw ArgumentError('A club message cannot exceed 2000 characters.');
    }

    final member = await _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('members')
        .doc(user.uid)
        .get();
    if (!member.exists) throw StateError('You are not a member of this club.');

    final memberData = member.data() ?? const <String, dynamic>{};
    final role = ClubRole.fromValue(memberData['role']);
    if (!role.canWriteChat) {
      throw StateError('Guests cannot send messages in club chat.');
    }
    final displayName = (memberData['displayName'] as String?)?.trim();
    final photoUrl = memberData['photoUrl'] as String?;
    final messageRef = _messages(clubId: clubId, channelId: channelId).doc();
    final now = Timestamp.now();

    await messageRef.set({
      'clubId': clubId,
      'channelId': channelId,
      'senderId': user.uid,
      'senderName': displayName?.isNotEmpty == true
          ? displayName
          : _resolveUserName(user),
      'senderPhotoUrl': photoUrl?.trim().isNotEmpty == true
          ? photoUrl!.trim()
          : user.photoURL,
      'content': normalized,
      'sentAt': now,
      'editedAt': null,
      'isDeleted': false,
    });
  }

  Future<void> deleteMessage({
    required String clubId,
    required String channelId,
    required ClubMessage message,
  }) async {
    final user = _user;
    final memberSnapshot = await _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('members')
        .doc(user.uid)
        .get();
    if (!memberSnapshot.exists) {
      throw StateError('You are not a member of this club.');
    }
    final role = ClubRole.fromValue(memberSnapshot.data()?['role']);
    final canModerate = role.power >= ClubRole.moderator.power;
    if (message.senderId != user.uid && !canModerate) {
      throw StateError('Your role cannot remove this message.');
    }

    await _messages(
      clubId: clubId,
      channelId: channelId,
    ).doc(message.id).update({
      'content': '',
      'isDeleted': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  static String _resolveUserName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'YO Voice user';
  }
}

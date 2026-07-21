import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

class RoomService {
  RoomService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _roomsCollection =>
      _firestore.collection('rooms');

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use voice rooms.');
    }
    return user;
  }

  Future<VoiceRoom> createRoom({
    required String name,
    required String description,
    required String category,
    required String visibility,
    required String language,
    required int? maxParticipants,
  }) async {
    final user = _currentUser;
    final normalizedName = name.trim();
    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }

    final room = _roomsCollection.doc();
    final participant = room.collection('participants').doc(user.uid);
    final hostName = _resolveUserName(user);
    final batch = _firestore.batch();

    batch.set(room, {
      'hostId': user.uid,
      'hostName': hostName,
      'hostPhotoUrl': user.photoURL,
      'name': normalizedName,
      'description': description.trim(),
      'category': category,
      'visibility': visibility,
      'language': language,
      'maxParticipants': maxParticipants,
      'participantCount': 1,
      'isLive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(participant, {
      'userId': user.uid,
      'displayName': hostName,
      'photoUrl': user.photoURL,
      'role': 'host',
      'isMuted': false,
      'isSpeaker': true,
      'isHandRaised': false,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return VoiceRoom.fromFirestore(await room.get());
  }

  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    return _roomsCollection
        .where('isLive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(VoiceRoom.fromFirestore).toList(growable: false));
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _roomsCollection.doc(roomId).snapshots().map((document) {
      if (!document.exists) throw StateError('The room no longer exists.');
      return VoiceRoom.fromFirestore(document);
    });
  }

  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    return _roomsCollection
        .doc(roomId)
        .collection('participants')
        .snapshots()
        .map((snapshot) {
      final participants =
          snapshot.docs.map(RoomParticipant.fromFirestore).toList();
      participants.sort((a, b) {
        final role = _priority(a).compareTo(_priority(b));
        if (role != 0) return role;
        final aTime = a.joinedAt ?? DateTime(2100);
        final bTime = b.joinedAt ?? DateTime(2100);
        return aTime.compareTo(bTime);
      });
      return participants;
    });
  }


  Future<VoiceRoom> joinRoom(String roomId) async {
    final user = _currentUser;
    final room = _roomsCollection.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(room);
      final data = roomSnapshot.data();
      if (!roomSnapshot.exists || data == null) {
        throw StateError('The requested room does not exist.');
      }
      if (data['isLive'] != true) {
        throw StateError('This room is no longer live.');
      }

      final existing = await transaction.get(participant);
      if (existing.exists) return;

      final count = (data['participantCount'] as num?)?.toInt() ?? 0;
      final max = (data['maxParticipants'] as num?)?.toInt();
      if (max != null && count >= max) throw StateError('This room is full.');

      transaction.set(participant, {
        'userId': user.uid,
        'displayName': _resolveUserName(user),
        'photoUrl': user.photoURL,
        'role': 'listener',
        'isMuted': true,
        'isSpeaker': false,
        'isHandRaised': false,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(room, {
        'participantCount': count + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    return VoiceRoom.fromFirestore(await room.get());
  }

  Future<void> setMuted({
    required String roomId,
    required bool isMuted,
  }) async {
    final user = _currentUser;
    final participant =
        _roomsCollection.doc(roomId).collection('participants').doc(user.uid);
    final snapshot = await participant.get();
    if (!snapshot.exists) throw StateError('You are not in this room.');
    if (snapshot.data()?['isSpeaker'] != true) {
      throw StateError('Only speakers can use the microphone.');
    }
    await participant.update({
      'isMuted': isMuted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setHandRaised({
    required String roomId,
    required bool isRaised,
  }) async {
    final user = _currentUser;
    await _roomsCollection
        .doc(roomId)
        .collection('participants')
        .doc(user.uid)
        .update({
      'isHandRaised': isRaised,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setSpeaker({
    required String roomId,
    required String participantId,
    required bool isSpeaker,
  }) async {
    await _requireHost(roomId);
    final participant =
        _roomsCollection.doc(roomId).collection('participants').doc(participantId);
    final snapshot = await participant.get();
    if (!snapshot.exists) throw StateError('Participant not found.');
    if (snapshot.data()?['role'] == 'host') return;

    await participant.update({
      'role': isSpeaker ? 'speaker' : 'listener',
      'isSpeaker': isSpeaker,
      'isMuted': true,
      'isHandRaised': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> hostSetMuted({
    required String roomId,
    required String participantId,
    required bool isMuted,
  }) async {
    await _requireHost(roomId);
    await _roomsCollection
        .doc(roomId)
        .collection('participants')
        .doc(participantId)
        .update({
      'isMuted': isMuted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeParticipant({
    required String roomId,
    required String participantId,
  }) async {
    await _requireHost(roomId);
    final room = _roomsCollection.doc(roomId);
    final participant = room.collection('participants').doc(participantId);

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(room);
      final participantSnapshot = await transaction.get(participant);
      if (!participantSnapshot.exists) return;
      if (participantSnapshot.data()?['role'] == 'host') {
        throw StateError('The host cannot be removed.');
      }
      final count =
          (roomSnapshot.data()?['participantCount'] as num?)?.toInt() ?? 0;
      transaction.delete(participant);
      transaction.update(room, {
        'participantCount': count > 0 ? count - 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> sendReaction({
    required String roomId,
    required String emoji,
  }) async {
    final user = _currentUser;
    const allowed = ['👏', '❤️', '😂', '🔥', '🎉', '💜'];
    if (!allowed.contains(emoji)) {
      throw ArgumentError('Unsupported reaction.');
    }

    await _roomsCollection.doc(roomId).collection('reactions').add({
      'userId': user.uid,
      'displayName': _resolveUserName(user),
      'emoji': emoji,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<RoomMessage>> watchRoomMessages(String roomId) {
    return _roomsCollection
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(RoomMessage.fromFirestore).toList(growable: false));
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String text,
  }) async {
    final user = _currentUser;
    final normalizedText = text.trim();

    if (normalizedText.isEmpty) return;
    if (normalizedText.length > 500) {
      throw ArgumentError('A room message can contain up to 500 characters.');
    }

    final participant = await _roomsCollection
        .doc(roomId)
        .collection('participants')
        .doc(user.uid)
        .get();

    if (!participant.exists) {
      throw StateError('You must join the room before sending a message.');
    }

    await _roomsCollection.doc(roomId).collection('messages').add({
      'senderId': user.uid,
      'senderName': _resolveUserName(user),
      'senderPhotoUrl': user.photoURL,
      'text': normalizedText,
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': <String, List<String>>{},
    });
  }

  Future<void> toggleMessageReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  }) async {
    const allowed = ['❤️', '🔥', '😂', '👏', '🎉', '💜'];
    if (!allowed.contains(emoji)) {
      throw ArgumentError('Unsupported reaction.');
    }

    final user = _currentUser;
    final message = _roomsCollection
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(message);
      if (!snapshot.exists) {
        throw StateError('This message no longer exists.');
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final rawReactions = data['reactions'];
      final reactions = <String, dynamic>{};

      if (rawReactions is Map) {
        for (final entry in rawReactions.entries) {
          reactions[entry.key.toString()] = entry.value;
        }
      }

      final users = (reactions[emoji] is List)
          ? List<String>.from(
              (reactions[emoji] as List).whereType<String>(),
            )
          : <String>[];

      if (users.contains(user.uid)) {
        users.remove(user.uid);
      } else {
        users.add(user.uid);
      }

      if (users.isEmpty) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = users;
      }

      transaction.update(message, {
        'reactions': reactions,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> leaveRoom(String roomId) async {
    final user = _currentUser;
    final room = _roomsCollection.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(room);
      final data = roomSnapshot.data();
      if (!roomSnapshot.exists || data == null) return;
      if (data['hostId'] == user.uid) {
        throw StateError('The host must close the room.');
      }
      final participantSnapshot = await transaction.get(participant);
      if (!participantSnapshot.exists) return;

      final count = (data['participantCount'] as num?)?.toInt() ?? 0;
      transaction.delete(participant);
      transaction.update(room, {
        'participantCount': count > 0 ? count - 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> closeRoom(String roomId) async {
    await _requireHost(roomId);
    await _roomsCollection.doc(roomId).update({
      'isLive': false,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _requireHost(String roomId) async {
    final user = _currentUser;
    final room = await _roomsCollection.doc(roomId).get();
    if (!room.exists || room.data()?['hostId'] != user.uid) {
      throw StateError('Only the room host can do this.');
    }
  }

  static int _priority(RoomParticipant participant) {
    if (participant.isHost) return 0;
    if (participant.isSpeaker) return 1;
    if (participant.isHandRaised) return 2;
    return 3;
  }

  static String _resolveUserName(User user) {
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'YoVoice user';
  }
}

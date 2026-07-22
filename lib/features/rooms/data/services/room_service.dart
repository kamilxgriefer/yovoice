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

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('rooms');

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use rooms.');
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
    required RoomType roomType,
    String? imageUrl,
  }) async {
    final user = _user;
    final normalizedName = name.trim();

    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }

    final room = _rooms.doc();
    final participant = room.collection('participants').doc(user.uid);
    final member = room.collection('members').doc(user.uid);
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
      'memberCount': roomType == RoomType.community ? 1 : 0,
      'isLive': true,
      'roomType': roomType.name,
      'imageUrl': imageUrl,
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

    if (roomType == RoomType.community) {
      batch.set(member, {
        'userId': user.uid,
        'displayName': hostName,
        'photoUrl': user.photoURL,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return VoiceRoom.fromFirestore(await room.get());
  }

  Future<void> updateImageUrl({
    required String roomId,
    required String imageUrl,
  }) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).update({
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    return _rooms
        .where('isLive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(VoiceRoom.fromFirestore).toList(growable: false));
  }

  Stream<List<VoiceRoom>> watchPublicRooms() {
    return _rooms
        .where('visibility', isEqualTo: 'public')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(VoiceRoom.fromFirestore).toList(growable: false));
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _rooms.doc(roomId).snapshots().map((document) {
      if (!document.exists) {
        throw StateError('The room no longer exists.');
      }
      return VoiceRoom.fromFirestore(document);
    });
  }

  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('participants')
        .snapshots()
        .map((snapshot) {
      final participants =
          snapshot.docs.map(RoomParticipant.fromFirestore).toList();
      participants.sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        if (a.isSpeaker != b.isSpeaker) return a.isSpeaker ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });
      return participants;
    });
  }

  Stream<List<RoomMessage>> watchRoomMessages(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(RoomMessage.fromFirestore).toList(growable: false));
  }

  Future<VoiceRoom> joinRoom(String roomId) async {
    final user = _user;
    final room = _rooms.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(room);
      final data = roomSnapshot.data();

      if (!roomSnapshot.exists || data == null) {
        throw StateError('The requested room does not exist.');
      }

      final type = RoomType.fromValue(data['roomType']);
      if (data['isLive'] != true && type == RoomType.temporary) {
        throw StateError('This temporary room is no longer live.');
      }

      final existing = await transaction.get(participant);
      if (existing.exists) return;

      final count = (data['participantCount'] as num?)?.toInt() ?? 0;
      final max = (data['maxParticipants'] as num?)?.toInt();

      if (max != null && count >= max && data['isLive'] == true) {
        throw StateError('This room is full.');
      }

      transaction.set(participant, {
        'userId': user.uid,
        'displayName': _resolveUserName(user),
        'photoUrl': user.photoURL,
        'role': data['isLive'] == true ? 'listener' : 'member',
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

  Future<void> joinCommunity(String roomId) async {
    final user = _user;
    final room = _rooms.doc(roomId);
    final member = room.collection('members').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(room);
      final data = roomSnapshot.data();

      if (!roomSnapshot.exists || data == null) {
        throw StateError('The room no longer exists.');
      }

      if (RoomType.fromValue(data['roomType']) != RoomType.community) {
        throw StateError('Only community rooms have members.');
      }

      final memberSnapshot = await transaction.get(member);
      if (memberSnapshot.exists) return;

      final count = (data['memberCount'] as num?)?.toInt() ?? 0;

      transaction.set(member, {
        'userId': user.uid,
        'displayName': _resolveUserName(user),
        'photoUrl': user.photoURL,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(room, {
        'memberCount': count + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> startCommunityVoice(String roomId) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).update({
      'isLive': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.delete(),
    });
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String text,
  }) async {
    final user = _user;
    final normalized = text.trim();

    if (normalized.isEmpty) return;
    if (normalized.length > 500) {
      throw ArgumentError('A room message can contain up to 500 characters.');
    }

    await _rooms.doc(roomId).collection('messages').add({
      'senderId': user.uid,
      'senderName': _resolveUserName(user),
      'senderPhotoUrl': user.photoURL,
      'text': normalized,
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': <String, List<String>>{},
    });

    await _rooms.doc(roomId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setMuted({
    required String roomId,
    required bool isMuted,
  }) async {
    final user = _user;
    await _rooms.doc(roomId).collection('participants').doc(user.uid).update({
      'isMuted': isMuted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setHandRaised({
    required String roomId,
    required bool isRaised,
  }) async {
    final user = _user;
    await _rooms.doc(roomId).collection('participants').doc(user.uid).update({
      'isHandRaised': isRaised,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> leaveRoom(String roomId) async {
    final user = _user;
    final room = _rooms.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(room);
      final data = roomSnapshot.data();

      if (!roomSnapshot.exists || data == null) return;

      final participantSnapshot = await transaction.get(participant);
      if (!participantSnapshot.exists) return;

      final count = (data['participantCount'] as num?)?.toInt() ?? 0;
      final isHost = data['hostId'] == user.uid;
      final type = RoomType.fromValue(data['roomType']);

      transaction.delete(participant);

      final update = <String, dynamic>{
        'participantCount': count > 0 ? count - 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isHost) {
        update['isLive'] = false;
        update['endedAt'] = FieldValue.serverTimestamp();
      }

      transaction.update(room, update);

      if (isHost && type == RoomType.temporary) {
        // Document stays as ended history. It can be explicitly deleted later.
      }
    });
  }

  Future<void> deleteRoom(String roomId) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).delete();
  }

  Future<void> _requireHost(String roomId) async {
    final user = _user;
    final room = await _rooms.doc(roomId).get();

    if (!room.exists || room.data()?['hostId'] != user.uid) {
      throw StateError('Only the room host can do this.');
    }
  }

  static String _resolveUserName(User user) {
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;

    return 'YoVoice user';
  }
}

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
    if (user == null) throw StateError('You must be signed in to use rooms.');
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
    final hostName = _resolveUserName(user);
    final batch = _firestore.batch();
    final isCommunity = roomType == RoomType.community;

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
      'participantCount': isCommunity ? 0 : 1,
      'memberCount': isCommunity ? 1 : 0,
      'isLive': !isCommunity,
      'roomType': roomType.name,
      'status': RoomStatus.active.name,
      'imageUrl': imageUrl,
      'approvalRequired': false,
      'slowModeSeconds': 0,
      'autoMuteNewUsers': true,
      'membersCanStartVoice': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (isCommunity) {
      batch.set(room.collection('members').doc(user.uid), {
        'userId': user.uid,
        'displayName': hostName,
        'photoUrl': user.photoURL,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.set(room.collection('participants').doc(user.uid), {
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
    }

    await batch.commit();
    return VoiceRoom.fromFirestore(await room.get());
  }

  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    return _rooms
        .where('isLive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(VoiceRoom.fromFirestore)
            .where((room) => room.isActive)
            .toList(growable: false));
  }

  Stream<List<VoiceRoom>> watchPublicRooms() {
    return _rooms
        .where('visibility', isEqualTo: 'public')
        .snapshots()
        .map((snapshot) {
      final rooms = snapshot.docs
          .map(VoiceRoom.fromFirestore)
          .where((room) => room.isActive)
          .toList();
      rooms.sort((a, b) =>
          (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
            a.updatedAt ?? a.createdAt ?? DateTime(1970),
          ));
      return rooms;
    });
  }

  Stream<List<VoiceRoom>> watchOwnedRooms() {
    return _rooms
        .where('hostId', isEqualTo: _user.uid)
        .snapshots()
        .map((snapshot) {
      final rooms = snapshot.docs.map(VoiceRoom.fromFirestore).toList();
      rooms.sort((a, b) =>
          (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
            a.updatedAt ?? a.createdAt ?? DateTime(1970),
          ));
      return rooms;
    });
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _rooms.doc(roomId).snapshots().map((document) {
      if (!document.exists) throw StateError('The room no longer exists.');
      return VoiceRoom.fromFirestore(document);
    });
  }

  Stream<bool> watchIsParticipant(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('participants')
        .doc(_user.uid)
        .snapshots()
        .map((document) => document.exists);
  }

  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    return _rooms.doc(roomId).collection('participants').snapshots().map(
      (snapshot) {
        final participants =
            snapshot.docs.map(RoomParticipant.fromFirestore).toList();
        participants.sort((a, b) {
          if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
          if (a.isSpeaker != b.isSpeaker) return a.isSpeaker ? -1 : 1;
          return a.displayName.compareTo(b.displayName);
        });
        return participants;
      },
    );
  }

  Stream<List<RoomMessage>> watchRoomMessages(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(RoomMessage.fromFirestore)
            .toList(growable: false));
  }

  Future<void> updateRoomSettings({
    required String roomId,
    required String name,
    required String description,
    required String category,
    required String visibility,
    required String language,
    required int? maxParticipants,
    required bool approvalRequired,
    required int slowModeSeconds,
    required bool autoMuteNewUsers,
    required bool membersCanStartVoice,
  }) async {
    await _requireHost(roomId);
    final normalizedName = name.trim();
    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }
    await _rooms.doc(roomId).update({
      'name': normalizedName,
      'description': description.trim(),
      'category': category,
      'visibility': visibility,
      'language': language,
      'maxParticipants': maxParticipants,
      'approvalRequired': approvalRequired,
      'slowModeSeconds': slowModeSeconds,
      'autoMuteNewUsers': autoMuteNewUsers,
      'membersCanStartVoice': membersCanStartVoice,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Future<void> setRoomStatus(String roomId, RoomStatus status) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).update({
      'status': status.name,
      if (status != RoomStatus.active) 'isLive': false,
      if (status != RoomStatus.active) 'participantCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (status != RoomStatus.active) {
      await _deleteCollection(_rooms.doc(roomId).collection('participants'));
    }
  }

  Future<VoiceRoom> joinRoom(String roomId) async {
    final user = _user;
    final room = _rooms.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(room);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('The requested room does not exist.');
      }
      if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
        throw StateError('This room is currently unavailable.');
      }
      if (data['isLive'] != true) {
        throw StateError('Voice is not live in this room.');
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
        'role': data['hostId'] == user.uid ? 'host' : 'listener',
        'isMuted': data['hostId'] == user.uid
            ? false
            : (data['autoMuteNewUsers'] as bool? ?? true),
        'isSpeaker': data['hostId'] == user.uid,
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
      final snapshot = await transaction.get(room);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) throw StateError('Room not found.');
      if (RoomType.fromValue(data['roomType']) != RoomType.community) {
        throw StateError('Only community rooms have members.');
      }
      if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
        throw StateError('This community is currently unavailable.');
      }
      final existing = await transaction.get(member);
      if (existing.exists) return;
      if (data['approvalRequired'] == true) {
        throw StateError('This community requires owner approval.');
      }
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
    final room = await _rooms.doc(roomId).get();
    final data = room.data();
    if (!room.exists || data == null) throw StateError('Room not found.');
    final canStart = data['hostId'] == _user.uid ||
        (data['membersCanStartVoice'] == true &&
            await _isMember(roomId, _user.uid));
    if (!canStart) throw StateError('You cannot start voice in this room.');
    if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
      throw StateError('Open the room before starting voice.');
    }
    await _rooms.doc(roomId).update({
      'isLive': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.delete(),
    });
    await joinRoom(roomId);
  }

  Future<void> endCommunityVoice(String roomId) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).update({
      'isLive': false,
      'participantCount': 0,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _deleteCollection(_rooms.doc(roomId).collection('participants'));
  }

  Future<void> sendRoomMessage({required String roomId, required String text}) async {
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
    await _rooms.doc(roomId).update({'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> setMuted({required String roomId, required bool isMuted}) async {
    await _rooms.doc(roomId).collection('participants').doc(_user.uid).update({
      'isMuted': isMuted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setHandRaised({required String roomId, required bool isRaised}) async {
    await _rooms.doc(roomId).collection('participants').doc(_user.uid).update({
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
      if (isHost && type == RoomType.temporary) {
        update['isLive'] = false;
        update['endedAt'] = FieldValue.serverTimestamp();
      }
      transaction.update(room, update);
    });
  }

  Future<void> deleteRoom(String roomId) async {
    await _requireHost(roomId);
    await _deleteCollection(_rooms.doc(roomId).collection('participants'));
    await _deleteCollection(_rooms.doc(roomId).collection('members'));
    await _deleteCollection(_rooms.doc(roomId).collection('messages'));
    await _rooms.doc(roomId).delete();
  }

  Future<bool> _isMember(String roomId, String userId) async {
    return (await _rooms.doc(roomId).collection('members').doc(userId).get()).exists;
  }

  Future<void> _requireHost(String roomId) async {
    final room = await _rooms.doc(roomId).get();
    if (!room.exists || room.data()?['hostId'] != _user.uid) {
      throw StateError('Only the room owner can do this.');
    }
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(100).get();
      if (snapshot.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
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

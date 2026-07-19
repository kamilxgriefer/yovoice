import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';

class RoomService {
  RoomService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _roomsCollection {
    return _firestore.collection('rooms');
  }

  Future<VoiceRoom> createRoom({
    required String name,
    required String description,
    required String category,
    required String visibility,
    required String language,
    required int? maxParticipants,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in before creating a room.');
    }

    final normalizedName = name.trim();
    final normalizedDescription = description.trim();

    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }

    final roomDocument = _roomsCollection.doc();

    final participantDocument = roomDocument
        .collection('participants')
        .doc(user.uid);

    final hostName = _resolveUserName(user);

    final batch = _firestore.batch();

    batch.set(roomDocument, {
      'hostId': user.uid,
      'hostName': hostName,
      'hostPhotoUrl': user.photoURL,
      'name': normalizedName,
      'description': normalizedDescription,
      'category': category,
      'visibility': visibility,
      'language': language,
      'maxParticipants': maxParticipants,
      'participantCount': 1,
      'isLive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(participantDocument, {
      'userId': user.uid,
      'displayName': hostName,
      'photoUrl': user.photoURL,
      'role': 'host',
      'isMuted': false,
      'isSpeaker': true,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    final createdDocument = await roomDocument.get();

    return VoiceRoom.fromFirestore(createdDocument);
  }

  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    return _roomsCollection
        .where('isLive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(VoiceRoom.fromFirestore).toList();
        });
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _roomsCollection.doc(roomId).snapshots().map((document) {
      if (!document.exists) {
        throw StateError('The requested room does not exist.');
      }

      return VoiceRoom.fromFirestore(document);
    });
  }

  Future<VoiceRoom> joinRoom(String roomId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in before joining a room.');
    }

    final normalizedRoomId = roomId.trim();

    if (normalizedRoomId.isEmpty) {
      throw ArgumentError('Room ID cannot be empty.');
    }

    final roomDocument = _roomsCollection.doc(normalizedRoomId);

    final participantDocument = roomDocument
        .collection('participants')
        .doc(user.uid);

    await _firestore.runTransaction<void>((transaction) async {
      final roomSnapshot = await transaction.get(roomDocument);

      if (!roomSnapshot.exists) {
        throw StateError('The requested room does not exist.');
      }

      final roomData = roomSnapshot.data();

      if (roomData == null) {
        throw StateError('The requested room does not contain any data.');
      }

      final isLive = roomData['isLive'] as bool? ?? false;
      final visibility = roomData['visibility'] as String? ?? 'private';
      final hostId = roomData['hostId'] as String? ?? '';

      if (!isLive) {
        throw StateError('This room is no longer live.');
      }

      if (visibility != 'public' && hostId != user.uid) {
        throw StateError('This room is private.');
      }

      final participantSnapshot = await transaction.get(participantDocument);

      if (participantSnapshot.exists) {
        return;
      }

      final participantCount =
          (roomData['participantCount'] as num?)?.toInt() ?? 0;

      final maxParticipants = (roomData['maxParticipants'] as num?)?.toInt();

      if (maxParticipants != null && participantCount >= maxParticipants) {
        throw StateError('This room is full.');
      }

      final userName = _resolveUserName(user);

      transaction.set(participantDocument, {
        'userId': user.uid,
        'displayName': userName,
        'photoUrl': user.photoURL,
        'role': 'listener',
        'isMuted': true,
        'isSpeaker': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(roomDocument, {
        'participantCount': participantCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final updatedRoomDocument = await roomDocument.get();

    if (!updatedRoomDocument.exists) {
      throw StateError('The requested room does not exist.');
    }

    return VoiceRoom.fromFirestore(updatedRoomDocument);
  }

  Future<void> leaveRoom(String roomId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in before leaving a room.');
    }

    final normalizedRoomId = roomId.trim();

    if (normalizedRoomId.isEmpty) {
      throw ArgumentError('Room ID cannot be empty.');
    }

    final roomDocument = _roomsCollection.doc(normalizedRoomId);

    final participantDocument = roomDocument
        .collection('participants')
        .doc(user.uid);

    await _firestore.runTransaction<void>((transaction) async {
      final roomSnapshot = await transaction.get(roomDocument);

      if (!roomSnapshot.exists) {
        return;
      }

      final roomData = roomSnapshot.data();

      if (roomData == null) {
        return;
      }

      final hostId = roomData['hostId'] as String? ?? '';

      if (hostId == user.uid) {
        throw StateError(
          'The room host must close the room instead of leaving it.',
        );
      }

      final participantSnapshot = await transaction.get(participantDocument);

      if (!participantSnapshot.exists) {
        return;
      }

      final participantCount =
          (roomData['participantCount'] as num?)?.toInt() ?? 0;

      transaction.delete(participantDocument);

      transaction.update(roomDocument, {
        'participantCount': participantCount > 0 ? participantCount - 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> closeRoom(String roomId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in before closing a room.');
    }

    final roomDocument = _roomsCollection.doc(roomId);
    final roomSnapshot = await roomDocument.get();
    final roomData = roomSnapshot.data();

    if (!roomSnapshot.exists || roomData == null) {
      throw StateError('The requested room does not exist.');
    }

    if (roomData['hostId'] != user.uid) {
      throw StateError('Only the room host can close this room.');
    }

    await roomDocument.update({
      'isLive': false,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _resolveUserName(User user) {
    final displayName = user.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'YoVoice user';
  }
}

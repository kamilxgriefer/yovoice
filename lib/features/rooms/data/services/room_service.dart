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

    final hostName = _resolveHostName(user);

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
        .map((snapshot) => snapshot.docs.map(VoiceRoom.fromFirestore).toList());
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _roomsCollection.doc(roomId).snapshots().map((document) {
      if (!document.exists) {
        throw StateError('The requested room does not exist.');
      }

      return VoiceRoom.fromFirestore(document);
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

  String _resolveHostName(User user) {
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

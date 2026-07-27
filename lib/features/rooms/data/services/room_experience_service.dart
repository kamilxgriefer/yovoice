import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';

class BroadcastHandRequest {
  const BroadcastHandRequest({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.createdAt,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final DateTime? createdAt;

  factory BroadcastHandRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final timestamp = data['createdAt'];
    return BroadcastHandRequest(
      userId: document.id,
      displayName: data['displayName'] as String? ?? 'YoVoice user',
      photoUrl: data['photoUrl'] as String?,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

class RoomExperienceService {
  RoomExperienceService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _room(String roomId) =>
      _firestore.collection('rooms').doc(roomId);

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in.');
    }
    return user;
  }

  String _name(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'YoVoice user';
  }

  Future<void> configureRoom({
    required String roomId,
    required RoomExperience experience,
    required String topic,
    required bool audienceCanSpeak,
    required bool handRaisingEnabled,
  }) async {
    await _room(roomId).update({
      'experience': experience.firestoreValue,
      'topic': topic.trim(),
      'audienceCanSpeak': audienceCanSpeak,
      'handRaisingEnabled': handRaisingEnabled,
      'stageLimit': experience == RoomExperience.broadcast ? 8 : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<RoomExperience> watchExperience(String roomId) {
    return _room(roomId).snapshots().map(
      (snapshot) => RoomExperience.fromValue(snapshot.data()?['experience']),
    );
  }

  Future<RoomExperience> getExperience(String roomId) async {
    final snapshot = await _room(roomId).get();
    return RoomExperience.fromValue(snapshot.data()?['experience']);
  }

  Stream<List<BroadcastHandRequest>> watchRaisedHands(String roomId) {
    return _room(roomId)
        .collection('handRequests')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(BroadcastHandRequest.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<bool> watchMyHandRaised(String roomId) {
    final uid = _user.uid;
    return _room(roomId)
        .collection('handRequests')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  Future<void> setHandRaised({
    required String roomId,
    required bool raised,
  }) async {
    final user = _user;
    final request = _room(roomId).collection('handRequests').doc(user.uid);

    if (!raised) {
      await request.delete();
      return;
    }

    final room = await _room(roomId).get();
    final data = room.data();
    if (data == null) throw StateError('Room not found.');
    if (!RoomExperience.fromValue(data['experience']).isBroadcast) {
      throw StateError('Raise hand is available only in Broadcast Rooms.');
    }
    if (data['handRaisingEnabled'] == false) {
      throw StateError('The host disabled hand raising.');
    }

    await request.set({
      'displayName': _name(user),
      'photoUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> inviteToStage({
    required String roomId,
    required BroadcastHandRequest request,
  }) async {
    final roomRef = _room(roomId);
    final room = await roomRef.get();
    final data = room.data();
    if (data == null) throw StateError('Room not found.');
    if (data['hostId'] != _user.uid) {
      throw StateError('Only the host can invite people to the stage.');
    }

    final participant = roomRef.collection('participants').doc(request.userId);
    final batch = _firestore.batch();
    batch.set(participant, {
      'userId': request.userId,
      'displayName': request.displayName,
      'photoUrl': request.photoUrl,
      'role': 'speaker',
      'isSpeaker': true,
      'isMuted': true,
      'isHandRaised': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.delete(roomRef.collection('handRequests').doc(request.userId));
    await batch.commit();
  }

  Future<void> moveToAudience({
    required String roomId,
    required String userId,
  }) async {
    final roomRef = _room(roomId);
    final room = await roomRef.get();
    final data = room.data();
    if (data == null || data['hostId'] != _user.uid) {
      throw StateError('Only the host can manage the stage.');
    }

    await roomRef.collection('participants').doc(userId).set({
      'role': 'listener',
      'isSpeaker': false,
      'isMuted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Compatibility alias for code created before Podcast Rooms were renamed.
@Deprecated('Use BroadcastHandRequest instead.')
typedef PodcastHandRequest = BroadcastHandRequest;

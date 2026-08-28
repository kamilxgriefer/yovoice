import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';

/// Compatibility view for code written before stage requests moved onto the
/// canonical participant row. New UI uses [RoomService] and `isHandRaised`.
@Deprecated('Use RoomParticipant.isHandRaised through RoomService instead.')
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

  factory BroadcastHandRequest.fromParticipant(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final timestamp = data['updatedAt'] ?? data['joinedAt'];
    return BroadcastHandRequest(
      userId: document.id,
      displayName: data['displayName'] as String? ?? 'YO Voice user',
      photoUrl: data['photoUrl'] as String?,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

class RoomExperienceService {
  RoomExperienceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    NotificationService? notificationService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  DocumentReference<Map<String, dynamic>> _room(String roomId) =>
      _firestore.collection('rooms').doc(roomId);

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in.');
    }
    return user;
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

  /// Compatibility adapter over the canonical participant roster. This no
  /// longer creates or watches a second `handRequests` collection.
  @Deprecated('Watch RoomService.watchParticipants and isHandRaised instead.')
  Stream<List<BroadcastHandRequest>> watchRaisedHands(String roomId) {
    return _room(roomId).collection('participants').snapshots().map((snapshot) {
      final requests = snapshot.docs
          .where((document) => document.data()['isHandRaised'] == true)
          .map(BroadcastHandRequest.fromParticipant)
          .toList(growable: false);
      requests.sort((a, b) {
        final left = a.createdAt;
        final right = b.createdAt;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });
      return requests;
    });
  }

  @Deprecated('Watch your RoomParticipant.isHandRaised instead.')
  Stream<bool> watchMyHandRaised(String roomId) {
    return _room(roomId)
        .collection('participants')
        .doc(_user.uid)
        .snapshots()
        .map((snapshot) => snapshot.data()?['isHandRaised'] == true);
  }

  @Deprecated('Use RoomService.setHandRaised instead.')
  Future<void> setHandRaised({
    required String roomId,
    required bool raised,
  }) async {
    await _room(roomId).collection('participants').doc(_user.uid).update({
      'isHandRaised': raised,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @Deprecated('Use RoomService.setParticipantSpeakerStatus instead.')
  Future<void> inviteToStage({
    required String roomId,
    required BroadcastHandRequest request,
  }) async {
    final callable = _functions.httpsCallable('moderateRoomParticipantSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'participantId': request.userId,
      'isSpeaker': true,
    });
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

    final callable = _functions.httpsCallable('moderateRoomParticipantSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'participantId': userId,
      'isSpeaker': false,
    });
  }
}

/// Compatibility alias for code created before Podcast Rooms were renamed.
@Deprecated('Use BroadcastHandRequest instead.')
typedef PodcastHandRequest = BroadcastHandRequest;

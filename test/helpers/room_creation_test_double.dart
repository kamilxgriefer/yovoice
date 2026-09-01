import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Minimal Admin-callable stand-in for RoomService widget/unit tests.
///
/// Production creation is server-only. Tests inject this boundary instead of
/// silently restoring the retired direct client batch whenever Firebase is
/// absent, which keeps the production authorization model visible in tests.
Future<Map<Object?, Object?>> createRoomForTest({
  required FirebaseFirestore firestore,
  required String userId,
  required Map<String, Object?> request,
  bool incrementRoomCount = false,
}) async {
  final requestId = request['requestId']! as String;
  final roomId = 'r_${sha256.convert(utf8.encode('$userId:$requestId'))}'
      .substring(0, 42);
  final reference = firestore.collection('rooms').doc(roomId);
  final existing = await reference.get();
  if (existing.exists) {
    return <Object?, Object?>{
      'schemaVersion': 1,
      'roomId': roomId,
      'created': true,
    };
  }
  final profile = await firestore.collection('users').doc(userId).get();
  final displayName = profile.data()?['displayName'];
  if (displayName is! String || displayName.trim().isEmpty) {
    throw StateError('Your profile does not have a display name.');
  }
  final roomType = request['roomType']! as String;
  final experience = request['experience']! as String;
  final community = roomType == 'community';
  final batch = firestore.batch();
  batch.set(reference, <String, Object?>{
    'hostId': userId,
    'hostName': displayName,
    'hostPhotoUrl': null,
    'name': request['name'],
    'description': request['description'],
    'category': request['category'],
    'visibility': request['visibility'],
    'language': request['language'],
    'maxParticipants': request['maxParticipants'],
    'participantCount': community ? 0 : 1,
    'memberCount': community ? 1 : 0,
    'isLive': !community,
    'roomType': roomType,
    'status': 'active',
    'imageUrl': null,
    'targetAudience': request['targetAudience'],
    'topicTags': request['topicTags'],
    'roomGuidelines': request['roomGuidelines'],
    if (request['conversationStyle'] != null)
      'conversationStyle': request['conversationStyle'],
    if (request['newcomerFriendly'] == true) 'newcomerFriendly': true,
    if (request['showFormat'] != null) 'showFormat': request['showFormat'],
    'experience': experience,
    'topic': request['topic'],
    'audienceCanSpeak': request['audienceCanSpeak'],
    'handRaisingEnabled': request['handRaisingEnabled'],
    'stageLimit': experience == 'broadcast' ? 8 : null,
    'approvalRequired': false,
    'slowModeSeconds': 0,
    'autoMuteNewUsers': experience == 'broadcast',
    'membersCanStartVoice': false,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  if (community) {
    batch.set(reference.collection('roomMembers').doc(userId), {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': null,
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });
  } else {
    batch.set(reference.collection('participants').doc(userId), {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': null,
      'role': 'host',
      'isMuted': false,
      'isSpeaker': true,
      'isHandRaised': false,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  if (incrementRoomCount) {
    batch.set(firestore.collection('users').doc(userId), {
      'roomCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }
  await batch.commit();
  return <Object?, Object?>{
    'schemaVersion': 1,
    'roomId': roomId,
    'created': true,
  };
}

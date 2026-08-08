import 'package:cloud_firestore/cloud_firestore.dart';

class RoomParticipant {
  const RoomParticipant({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.role,
    required this.isMuted,
    required this.isSpeaker,
    required this.isHandRaised,
    required this.joinedAt,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final String role;
  final bool isMuted;
  final bool isSpeaker;
  final bool isHandRaised;
  final DateTime? joinedAt;

  bool get isHost => role == 'host';
  bool get isListener => !isSpeaker;

  factory RoomParticipant.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    return RoomParticipant(
      userId: data['userId'] as String? ?? document.id,
      displayName: data['displayName'] as String? ?? 'YO Voice user',
      photoUrl: data['photoUrl'] as String?,
      role: data['role'] as String? ?? 'listener',
      isMuted: data['isMuted'] as bool? ?? true,
      isSpeaker: data['isSpeaker'] as bool? ?? false,
      isHandRaised: data['isHandRaised'] as bool? ?? false,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}

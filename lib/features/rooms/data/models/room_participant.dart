import 'package:cloud_firestore/cloud_firestore.dart';

class RoomParticipant {
  const RoomParticipant({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.role,
    required this.isMuted,
    required this.isSpeaker,
    required this.joinedAt,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final String role;
  final bool isMuted;
  final bool isSpeaker;
  final DateTime? joinedAt;

  bool get isHost => role == 'host';

  factory RoomParticipant.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;

    return RoomParticipant(
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Unknown',
      photoUrl: data['photoUrl'] as String?,
      role: data['role'] as String? ?? 'listener',
      isMuted: data['isMuted'] as bool? ?? true,
      isSpeaker: data['isSpeaker'] as bool? ?? false,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class RoomReaction {
  const RoomReaction({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.emoji,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String emoji;
  final DateTime? createdAt;

  factory RoomReaction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    return RoomReaction(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'YoVoice user',
      emoji: data['emoji'] as String? ?? '👏',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

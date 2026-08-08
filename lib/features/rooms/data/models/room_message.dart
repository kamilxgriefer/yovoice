import 'package:cloud_firestore/cloud_firestore.dart';

class RoomMessage {
  const RoomMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.text,
    required this.createdAt,
    required this.reactions,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String text;
  final DateTime? createdAt;

  /// Emoji -> list of user ids that reacted with this emoji.
  final Map<String, List<String>> reactions;

  int reactionCount(String emoji) => reactions[emoji]?.length ?? 0;

  bool reactedBy(String emoji, String userId) {
    return reactions[emoji]?.contains(userId) ?? false;
  }

  factory RoomMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawReactions = data['reactions'];

    final reactions = <String, List<String>>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        final value = entry.value;
        if (value is List) {
          reactions[entry.key.toString()] = value.whereType<String>().toList(
            growable: false,
          );
        }
      }
    }

    return RoomMessage(
      id: document.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'YO Voice user',
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      reactions: reactions,
    );
  }
}

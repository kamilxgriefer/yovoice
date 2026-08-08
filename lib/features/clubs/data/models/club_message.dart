import 'package:cloud_firestore/cloud_firestore.dart';

class ClubMessage {
  const ClubMessage({
    required this.id,
    required this.clubId,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.content,
    required this.sentAt,
    required this.editedAt,
    required this.isDeleted,
  });

  final String id;
  final String clubId;
  final String channelId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String content;
  final DateTime sentAt;
  final DateTime? editedAt;
  final bool isDeleted;

  factory ClubMessage.fromFirestore({
    required String clubId,
    required String channelId,
    required DocumentSnapshot<Map<String, dynamic>> document,
  }) {
    final data = document.data() ?? const <String, dynamic>{};
    return ClubMessage(
      id: document.id,
      clubId: clubId,
      channelId: channelId,
      senderId: data['senderId'] as String? ?? '',
      senderName: (data['senderName'] as String?)?.trim().isNotEmpty == true
          ? (data['senderName'] as String).trim()
          : 'YO Voice user',
      senderPhotoUrl: _nullableString(data['senderPhotoUrl']),
      content: data['content'] as String? ?? '',
      sentAt:
          _readDate(data['sentAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      editedAt: _readDate(data['editedAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  static String? _nullableString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

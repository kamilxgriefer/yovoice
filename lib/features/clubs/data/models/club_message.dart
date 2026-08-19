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
    this.deletedBy,
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

  /// Who performed the removal. Absent on live messages, and absent on
  /// removals written before the client started stamping it — so a null
  /// value means "unknown", never "the author did it".
  final String? deletedBy;

  /// True only when a removal is known to have been performed by someone
  /// other than the author, which is the one case worth telling the room
  /// about. An unattributed removal reads as an ordinary retraction,
  /// because that is all we can honestly claim about it.
  bool get wasRemovedByModerator =>
      isDeleted && deletedBy != null && deletedBy != senderId;

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
      deletedBy: _nullableString(data['deletedBy']),
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

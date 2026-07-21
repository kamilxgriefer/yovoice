import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, voice, image }

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.content,
    required this.sentAt,
    required this.readBy,
    required this.reactions,
    this.mediaUrl,
    this.durationSeconds,
    this.isDeleted = false,
    this.editedAt,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToContent,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String content;
  final DateTime sentAt;
  final List<String> readBy;
  final Map<String, String> reactions;
  final String? mediaUrl;
  final int? durationSeconds;
  final bool isDeleted;
  final DateTime? editedAt;
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToContent;

  bool isMine(String currentUserId) => senderId == currentUserId;
  bool isReadBy(String userId) => readBy.contains(userId);

  factory Message.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? <String, dynamic>{};

    return Message(
      id: document.id,
      conversationId: data['conversationId'] as String? ?? '',
      senderId: data['senderId'] as String? ?? '',
      type: _messageTypeFromString(data['type'] as String?),
      content: data['content'] as String? ?? '',
      sentAt: _dateTimeFromValue(data['sentAt']),
      readBy: List<String>.from(data['readBy'] as List<dynamic>? ?? const []),
      reactions: _stringMap(data['reactions']),
      mediaUrl: data['mediaUrl'] as String?,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt(),
      isDeleted: data['isDeleted'] as bool? ?? false,
      editedAt: _nullableDateTimeFromValue(data['editedAt']),
      replyToMessageId: data['replyToMessageId'] as String?,
      replyToSenderId: data['replyToSenderId'] as String?,
      replyToContent: data['replyToContent'] as String?,
    );
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    return value.map<String, String>(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    );
  }

  static MessageType _messageTypeFromString(String? value) {
    return MessageType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => MessageType.text,
    );
  }

  static DateTime _dateTimeFromValue(Object? value) {
    return _nullableDateTimeFromValue(value) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _nullableDateTimeFromValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

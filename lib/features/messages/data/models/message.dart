import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  voice,
  image,
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.content,
    required this.sentAt,
    required this.readBy,
    this.mediaUrl,
    this.durationSeconds,
    this.isDeleted = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String content;
  final DateTime sentAt;
  final List<String> readBy;
  final String? mediaUrl;
  final int? durationSeconds;
  final bool isDeleted;

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
      mediaUrl: data['mediaUrl'] as String?,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt(),
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'conversationId': conversationId,
      'senderId': senderId,
      'type': type.name,
      'content': content,
      'sentAt': Timestamp.fromDate(sentAt),
      'readBy': readBy,
      'mediaUrl': mediaUrl,
      'durationSeconds': durationSeconds,
      'isDeleted': isDeleted,
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    MessageType? type,
    String? content,
    DateTime? sentAt,
    List<String>? readBy,
    String? mediaUrl,
    int? durationSeconds,
    bool? isDeleted,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      content: content ?? this.content,
      sentAt: sentAt ?? this.sentAt,
      readBy: readBy ?? this.readBy,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  static MessageType _messageTypeFromString(String? value) {
    return MessageType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => MessageType.text,
    );
  }

  static DateTime _dateTimeFromValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

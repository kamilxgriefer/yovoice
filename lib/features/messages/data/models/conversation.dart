import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/features/messages/data/models/message.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.participantIds,
    required this.participantNames,
    required this.participantEmails,
    required this.participantPhotoUrls,
    required this.unreadCounts,
    required this.lastMessage,
    required this.lastMessageType,
    required this.lastMessageSenderId,
    required this.updatedAt,
    required this.createdAt,
    required this.archivedBy,
    required this.mutedBy,
  });

  final String id;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final Map<String, String> participantEmails;
  final Map<String, String> participantPhotoUrls;
  final Map<String, int> unreadCounts;
  final String lastMessage;
  final MessageType lastMessageType;
  final String lastMessageSenderId;
  final DateTime updatedAt;
  final DateTime createdAt;
  final List<String> archivedBy;
  final List<String> mutedBy;

  String otherUserId(String currentUserId) {
    return participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => currentUserId,
    );
  }

  String displayNameFor(String userId) {
    final name = participantNames[userId]?.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    final email = participantEmails[userId]?.trim();

    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'YO Voice user';
  }

  String emailFor(String userId) {
    return participantEmails[userId] ?? '';
  }

  String photoUrlFor(String userId) {
    return participantPhotoUrls[userId] ?? '';
  }

  int unreadCountFor(String userId) {
    return unreadCounts[userId] ?? 0;
  }

  bool isArchivedFor(String userId) => archivedBy.contains(userId);

  bool isMutedFor(String userId) => mutedBy.contains(userId);

  String previewFor(String currentUserId) {
    if (lastMessage.isEmpty) {
      return 'Start a conversation';
    }

    final prefix = lastMessageSenderId == currentUserId ? 'You: ' : '';

    switch (lastMessageType) {
      case MessageType.voice:
        return '${prefix}Voice message';
      case MessageType.image:
        return '${prefix}Photo';
      case MessageType.text:
        return '$prefix$lastMessage';
    }
  }

  factory Conversation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? <String, dynamic>{};

    return Conversation(
      id: document.id,
      participantIds: List<String>.from(
        data['participantIds'] as List<dynamic>? ?? const <dynamic>[],
      ),
      participantNames: _stringMap(data['participantNames']),
      participantEmails: _stringMap(data['participantEmails']),
      participantPhotoUrls: _stringMap(data['participantPhotoUrls']),
      unreadCounts: _intMap(data['unreadCounts']),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageType: _messageTypeFromString(
        data['lastMessageType'] as String?,
      ),
      lastMessageSenderId: data['lastMessageSenderId'] as String? ?? '',
      updatedAt: _dateTimeFromValue(data['updatedAt']),
      createdAt: _dateTimeFromValue(data['createdAt']),
      archivedBy: List<String>.from(
        data['archivedBy'] as List<dynamic>? ?? const <dynamic>[],
      ),
      mutedBy: List<String>.from(
        data['mutedBy'] as List<dynamic>? ?? const <dynamic>[],
      ),
    );
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return <String, String>{};
    }

    return value.map<String, String>(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    );
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) {
      return <String, int>{};
    }

    return value.map<String, int>(
      (key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0),
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

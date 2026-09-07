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
    this.deletedBy = const <String>[],
    this.deletedSequences = const <String, int>{},
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

  /// Participants who deleted this conversation for THEMSELVES. Server-owned,
  /// and cleared for both participants as soon as a new message arrives — a
  /// deleted thread revives, it does not stay gone.
  final List<String> deletedBy;

  /// Per-participant deletion cut-off: the `sequence` each one deleted
  /// through. Unlike [deletedBy] this is never cleared, which is what makes a
  /// revived thread start empty instead of handing back the deleted history.
  /// Firestore Rules enforce it on reads; see `conversationDeletedThrough` in
  /// `firestore.rules`.
  final Map<String, int> deletedSequences;

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

    return 'YO Voice user';
  }

  /// Legacy documents may still carry participantEmails until the bounded
  /// scrub runs. They are deliberately never surfaced as social identity.
  String emailFor(String userId) {
    return '';
  }

  String photoUrlFor(String userId) {
    return '';
  }

  int unreadCountFor(String userId) {
    return unreadCounts[userId] ?? 0;
  }

  bool isArchivedFor(String userId) => archivedBy.contains(userId);

  bool isMutedFor(String userId) => mutedBy.contains(userId);

  bool isDeletedFor(String userId) => deletedBy.contains(userId);

  /// The newest message [userId] deleted through, or 0 when they never
  /// deleted this conversation.
  int deletedThroughSequenceFor(String userId) => deletedSequences[userId] ?? 0;

  /// Returns an offline-capable conversation snapshot with one participant's
  /// live public identity overlaid. The source object remains immutable and
  /// every unrelated participant/metadata field is preserved.
  Conversation withParticipantIdentity({
    required String userId,
    required String displayName,
    required String photoUrl,
  }) {
    return Conversation(
      id: id,
      participantIds: participantIds,
      participantNames: {
        ...participantNames,
        userId: displayName.trim().isEmpty ? 'YO Voice user' : displayName,
      },
      participantEmails: participantEmails,
      participantPhotoUrls: participantPhotoUrls,
      unreadCounts: unreadCounts,
      lastMessage: lastMessage,
      lastMessageType: lastMessageType,
      lastMessageSenderId: lastMessageSenderId,
      updatedAt: updatedAt,
      createdAt: createdAt,
      archivedBy: archivedBy,
      mutedBy: mutedBy,
      deletedBy: deletedBy,
      deletedSequences: deletedSequences,
    );
  }

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
      case MessageType.video:
        return '${prefix}Video';
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
      participantPhotoUrls: const <String, String>{},
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
      deletedBy: List<String>.from(
        data['deletedBy'] as List<dynamic>? ?? const <dynamic>[],
      ),
      deletedSequences: _intMap(data['deletedSequences']),
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

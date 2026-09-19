import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/messages/data/models/message.dart';

/// The wire value a deleted message leaves behind on the conversation root.
///
/// `functions/messaging/direct_integrity.js` writes this English literal and
/// it stays the storage format — every client maps it to the reader's
/// language at render time via [conversationPreview].
const conversationDeletedTombstone = 'Message deleted';

/// The ONE way a conversation's last message is turned into list copy.
///
/// Chats, Home's recent chats and the shell's incoming-message overlay all
/// render the same preview for the same thread, so they all come through
/// here. An English-only duplicate used to live on [Conversation] and made
/// the Polish Chats list disagree with the Polish thread it opened.
String conversationPreview(
  Conversation conversation,
  String currentUserId,
  AppLocalizations copy,
) {
  if (conversation.lastMessage.isEmpty) {
    return copy.text('Start a conversation', 'Rozpocznij rozmowę');
  }

  final prefix = conversation.lastMessageSenderId == currentUserId
      ? copy.text('You: ', 'Ty: ')
      : '';
  final content = switch (conversation.lastMessageType) {
    MessageType.voice => copy.text('Voice message', 'Wiadomość głosowa'),
    MessageType.image => copy.text('Photo', 'Zdjęcie'),
    MessageType.video => copy.text('Video', 'Film'),
    MessageType.text || MessageType.gif => localizedMessageTombstone(
      conversation.lastMessage,
      copy,
    ),
  };

  return '$prefix$content';
}

/// Maps the server-written deletion tombstone onto the reader's language and
/// returns every other body verbatim. User content is never translated.
String localizedMessageTombstone(String lastMessage, AppLocalizations copy) {
  if (lastMessage.trim() != conversationDeletedTombstone) return lastMessage;
  return copy.text('Message deleted', 'Wiadomość usunięta');
}

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
    this.lastMessageSequence = 0,
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

  /// The server-assigned sequence of the newest committed message, 0 while
  /// the thread has none. Written by `sendDirectMessage`
  /// (`functions/messaging/direct_integrity.js`) and read here only as one
  /// more witness for [hasMessages] on roots whose preview fields are blank.
  final int lastMessageSequence;

  /// Whether at least one message was ever committed to this thread.
  ///
  /// `openDirectConversation` creates the root for BOTH participants the
  /// moment one of them opens the other's profile, with `lastMessage: ""`,
  /// `lastMessageSenderId: ""`, `lastMessageSequence: 0` and
  /// `updatedAt = createdAt = now`. Without this distinction the person who
  /// was merely looked at sees an empty "Start a conversation" row hoisted to
  /// the top of Chats and Home. Any of the three witnesses is enough — a
  /// legacy root can carry a message while one preview field is blank.
  bool get hasMessages =>
      lastMessage.isNotEmpty ||
      lastMessageSenderId.isNotEmpty ||
      lastMessageSequence > 0;

  /// The instant lists order by.
  ///
  /// For a thread with messages this is [updatedAt]: the server bumps it only
  /// on message events — send (`direct_integrity.js` text and media paths),
  /// editing or deleting the newest message, and an admin deletion — and
  /// never for typing heartbeats, read cursors, archive/mute preferences,
  /// delete-for-me or reactions. For a thread that has no message yet it is
  /// [createdAt], so a root touch after creation can never promote it.
  DateTime get lastActivityAt => hasMessages ? updatedAt : createdAt;

  /// Newest activity first; ties fall back to creation time, then to the id
  /// so the order is stable across snapshots.
  static int compareByRecentActivity(Conversation a, Conversation b) {
    final byActivity = b.lastActivityAt.compareTo(a.lastActivityAt);
    if (byActivity != 0) return byActivity;
    final byCreation = b.createdAt.compareTo(a.createdAt);
    if (byCreation != 0) return byCreation;
    return a.id.compareTo(b.id);
  }

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
      lastMessageSequence: lastMessageSequence,
    );
  }

  /// Applies the owner-only unread projection used after an incognito read.
  /// The participant-readable conversation root intentionally retains its
  /// previous counter so the peer cannot infer that the thread was opened.
  Conversation withUnreadCountFor(String userId, int unreadCount) {
    return Conversation(
      id: id,
      participantIds: participantIds,
      participantNames: participantNames,
      participantEmails: participantEmails,
      participantPhotoUrls: participantPhotoUrls,
      unreadCounts: {...unreadCounts, userId: unreadCount},
      lastMessage: lastMessage,
      lastMessageType: lastMessageType,
      lastMessageSenderId: lastMessageSenderId,
      updatedAt: updatedAt,
      createdAt: createdAt,
      archivedBy: archivedBy,
      mutedBy: mutedBy,
      deletedBy: deletedBy,
      deletedSequences: deletedSequences,
      lastMessageSequence: lastMessageSequence,
    );
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
      lastMessageSequence: _nonNegativeInt(data['lastMessageSequence']),
    );
  }

  static int _nonNegativeInt(Object? value) {
    if (value is! num) return 0;
    final parsed = value.toInt();
    return parsed < 0 ? 0 : parsed;
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

import 'package:cloud_firestore/cloud_firestore.dart';

/// One message in the community-wide Global Chat.
///
/// Deliberately its own model rather than a reuse of [Message]: a public
/// message and a private direct message must never be interchangeable in
/// the type system, so a Global message cannot be rendered by a private
/// conversation widget (or counted by one) by accident.
///
/// Every field here is written under firestore.rules validation —
/// `senderId` equals the authenticated uid, `sentAt` equals the server's
/// `request.time`, and the denormalised identity fields must match the
/// sender's real profile document, so none of them can be spoofed from a
/// modified client.
class GlobalMessage {
  const GlobalMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.senderIsCreator,
    required this.senderIsStaff,
    required this.content,
    required this.sentAt,
    required this.isDeleted,
    required this.deletedBy,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;

  /// Mirrors `users/{uid}.accountType == 'creator'` at send time,
  /// validated by rules against the profile document.
  final bool senderIsCreator;

  /// Mirrors the sender's platform `role` custom claim at send time.
  /// Rules compare it to the token, so it cannot be self-awarded.
  final bool senderIsStaff;

  final String content;
  final DateTime? sentAt;

  /// Soft-deleted by its author or by platform staff. The document
  /// survives with empty content so the feed can show that something was
  /// removed rather than silently reflowing.
  final bool isDeleted;
  final String? deletedBy;

  bool get removedByModerator => isDeleted && deletedBy != senderId;

  factory GlobalMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return GlobalMessage(
      id: document.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: (data['senderName'] as String?)?.trim().isNotEmpty == true
          ? (data['senderName'] as String).trim()
          : 'YO Voice user',
      senderPhotoUrl: null,
      senderIsCreator: data['senderIsCreator'] as bool? ?? false,
      senderIsStaff: data['senderIsStaff'] as bool? ?? false,
      content: data['content'] as String? ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedBy: data['deletedBy'] as String?,
    );
  }
}

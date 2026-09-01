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
    this.deletedByRole,
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

  /// The staff role recorded against a removal, written only by
  /// `adminDeleteMessage` through the Admin SDK. Clients cannot write it:
  /// it is absent from the update allowlist in `firestore.rules`, and the
  /// create allowlist's `hasOnly` keeps it from being forged at birth.
  final String? deletedByRole;

  /// A YO Voice staff redaction, which is NOT the same act as a club
  /// moderator's and must not be reported as one — moderators are told in
  /// product copy that the club owner's messages are staff-only, so
  /// labelling a staff removal "by a moderator" would describe something
  /// the app says is impossible and pin a platform decision on the club's
  /// volunteers.
  bool get wasRemovedByStaff =>
      isDeleted && (deletedByRole?.isNotEmpty ?? false);

  /// A club moderator reaching into somebody else's message. An
  /// unattributed removal is deliberately excluded: a null `deletedBy`
  /// means "unknown", never "the author did it".
  bool get wasRemovedByModerator =>
      isDeleted &&
      !wasRemovedByStaff &&
      deletedBy != null &&
      deletedBy != senderId;

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
      senderPhotoUrl: null,
      content: data['content'] as String? ?? '',
      sentAt:
          _readDate(data['sentAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      editedAt: _readDate(data['editedAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedBy: _nullableString(data['deletedBy']),
      deletedByRole: _nullableString(data['deletedByRole']),
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

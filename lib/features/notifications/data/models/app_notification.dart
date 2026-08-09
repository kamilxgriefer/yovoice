import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  friendRequest,
  friendAccepted,
  follow,
  clubInvite,
  clubInviteAccepted,
  roomInvite,
  broadcastInvite,
  directMessage,
  mention,
  reply,
  // Server-only: never in firestore.rules' client-creatable type list, so
  // only the Admin SDK (Cloud Functions) can ever produce one of these.
  achievementUnlocked,
  moderation,
  system;

  static NotificationType fromName(String? value) {
    return NotificationType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => NotificationType.system,
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorName,
    required this.actorPhotoUrl,
    required this.targetId,
    required this.targetLabel,
    required this.isRead,
    required this.createdAt,
    this.dedupeKey,
    this.bellSuppressed = false,
  });

  final String id;
  final NotificationType type;

  /// Who triggered this notification. Display text is always composed
  /// client-side from (type, actorName[, targetLabel]) rather than trusting
  /// a sender-supplied body string — firestore.rules only lets the actor
  /// write structured fields, never free text, so there's nothing here a
  /// malicious sender could use to phish the recipient with fake content.
  final String actorId;
  final String actorName;
  final String? actorPhotoUrl;

  /// What this notification is about — a clubId, roomId, conversationId,
  /// etc, depending on [type]. Used for deep-linking when tapped.
  final String? targetId;
  final String? targetLabel;

  final bool isRead;
  final DateTime? createdAt;

  /// Client-chosen key used to collapse repeat notifications of the same
  /// kind (e.g. re-inviting the same person to the same club) instead of
  /// piling up duplicates. Purely advisory — not enforced by rules.
  final String? dedupeKey;

  /// True for records that exist only to carry a push (friend DMs): the
  /// chat surfaces already show that unread state, so the global bell
  /// feed and its badge skip these instead of duplicating it. Routing is
  /// decided by the SENDER at write time (see MessageService), not
  /// filtered cosmetically per screen.
  final bool bellSuppressed;

  String get title {
    switch (type) {
      case NotificationType.friendRequest:
        return '$actorName sent you a friend request';
      case NotificationType.friendAccepted:
        return '$actorName accepted your friend request';
      case NotificationType.follow:
        return '$actorName started following you';
      case NotificationType.clubInvite:
        return targetLabel == null
            ? '$actorName invited you to a club'
            : '$actorName invited you to $targetLabel';
      case NotificationType.clubInviteAccepted:
        return targetLabel == null
            ? '$actorName accepted your club invitation'
            : '$actorName joined $targetLabel';
      case NotificationType.roomInvite:
        return targetLabel == null
            ? '$actorName invited you to a room'
            : '$actorName invited you to $targetLabel';
      case NotificationType.broadcastInvite:
        return targetLabel == null
            ? '$actorName invited you to a broadcast'
            : '$actorName invited you to $targetLabel';
      case NotificationType.directMessage:
        // Friend DMs never reach the bell (bellSuppressed), so a
        // directMessage row here is a non-friend reaching out — the
        // product's "message request" moment.
        return '$actorName sent you a message request';
      case NotificationType.mention:
        return targetLabel == null
            ? '$actorName mentioned you'
            : '$actorName mentioned you in $targetLabel';
      case NotificationType.reply:
        return targetLabel == null
            ? '$actorName replied to you'
            : '$actorName replied to you in $targetLabel';
      case NotificationType.achievementUnlocked:
        return targetLabel == null
            ? 'Achievement unlocked'
            : 'Achievement unlocked: $targetLabel';
      case NotificationType.moderation:
        return targetLabel ?? 'A moderator took action on your account';
      case NotificationType.system:
        return targetLabel ?? 'YO Voice';
    }
  }

  factory AppNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final createdAtValue = data['createdAt'];
    return AppNotification(
      id: document.id,
      type: NotificationType.fromName(data['type'] as String?),
      actorId: data['actorId'] as String? ?? '',
      actorName: (data['actorName'] as String?)?.trim().isNotEmpty == true
          ? (data['actorName'] as String).trim()
          : 'YO Voice user',
      actorPhotoUrl: data['actorPhotoUrl'] as String?,
      targetId: data['targetId'] as String?,
      targetLabel: data['targetLabel'] as String?,
      isRead: data['isRead'] as bool? ?? false,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
      dedupeKey: data['dedupeKey'] as String?,
      bellSuppressed: data['bellSuppressed'] as bool? ?? false,
    );
  }
}

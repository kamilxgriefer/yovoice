import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  friendRequest,
  friendAccepted,
  follow,
  clubInvite,
  clubInviteAccepted,
  roomInvite,
  broadcastInvite,
  liveStarted,
  directMessage,
  directCall,
  missedCall,
  mention,
  reply,
  // Engagement and Server activity (ADR-213). Server-written like every
  // other type: a comment trigger, the event reminder worker and the
  // membership callables produce these.
  momentComment,
  reelComment,
  commentMention,
  serverEventReminder,
  serverRole,
  // Premium Pages (ADR-233 §2.6, §2.8, §2.10), server-written: a comment on
  // the recipient's Page post; the statement of reasons for a staff action
  // on the recipient's Page, post or comment; the lapse notices (Day 0
  // read-only, Day 23 hidden in 7 days).
  pagePostComment,
  pageModeration,
  pageLapse,
  // A Page the recipient follows published a post (ADR-237). The actor is
  // the Page (its id is its owner's uid), the target is the post.
  pagePostPublished,
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
    this.targetSubId,
    this.sourcePath,
    this.moderationAction,
    this.moderationReason,
    this.lapsePhase,
    this.postPreview,
    this.pageKind,
  });

  final String id;
  final NotificationType type;

  /// Who triggered this notification. Display text is always composed
  /// client-side from (type, actorName[, targetLabel]) rather than trusting
  /// a free-form body string. Notification documents are written only by
  /// trusted server authorities; Firestore Rules deny every client create.
  final String actorId;
  final String actorName;
  final String? actorPhotoUrl;

  /// What this notification is about — a serverId, legacy roomId, conversationId,
  /// etc, depending on [type]. Used for deep-linking when tapped.
  final String? targetId;
  final String? targetLabel;

  final bool isRead;
  final DateTime? createdAt;

  /// Server-chosen key used to collapse repeat notifications of the same
  /// kind instead of piling up duplicates. The exact lifecycle and
  /// generation semantics are owned by the corresponding server writer.
  final String? dedupeKey;

  /// True for records that exist only to carry a push (friend DMs): the
  /// chat surfaces already show that unread state, so the global bell
  /// feed and its badge skip these instead of duplicating it. The trusted
  /// server-side activity writer decides this at write time; screens do not
  /// infer or override it cosmetically.
  final bool bellSuppressed;

  /// The secondary target inside [targetId] — the comment to scroll to, or
  /// the Server channel an event lives in. Additive and optional: rows
  /// written before it existed simply carry none.
  final String? targetSubId;

  /// The server document this row was derived from, when the writer recorded
  /// one. The router uses it to tell a Moment comment from a Yeel comment
  /// without trusting anything the push payload carries.
  final String? sourcePath;

  /// `pageModeration` rows: which action (`postRemoved`, `postHeld`,
  /// `postRestored`, `commentRemoved`, `pageSuspended`,
  /// `pageSuspensionLifted`) and the report reason key. Additive; the
  /// English [targetLabel] stays the fallback.
  final String? moderationAction;
  final String? moderationReason;

  /// `pageLapse` rows: `readOnly` (Day 0) or `hidingSoon` (Day 23).
  final String? lapsePhase;

  /// `pagePostPublished` rows: the post's first line (at most 120
  /// characters, absent for a photo or voice post without a caption) and the
  /// Page's kind (`business` or `community`) for its face. Additive; a row
  /// without them still shows its title.
  final String? postPreview;
  final String? pageKind;

  /// True when the actor is a Page rather than a person: the row draws the
  /// Page's face and no personal identity badges.
  bool get actorIsPage => type == NotificationType.pagePostPublished;

  /// Rows YO Voice itself sends (no person behind them).
  bool get isSystemNotice =>
      actorId.isEmpty ||
      actorId == systemActorId ||
      type == NotificationType.pageModeration ||
      type == NotificationType.pageLapse;

  /// The actor id server notices carry (`report_contract.js` SYSTEM_ACTOR).
  static const String systemActorId = 'yovoice-system';

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
            ? '$actorName invited you to a server'
            : '$actorName invited you to $targetLabel';
      case NotificationType.clubInviteAccepted:
        return targetLabel == null
            ? '$actorName accepted your server invitation'
            : '$actorName joined $targetLabel';
      case NotificationType.roomInvite:
        return targetLabel == null
            ? '$actorName invited you to a voice channel'
            : '$actorName invited you to $targetLabel';
      case NotificationType.broadcastInvite:
        return targetLabel == null
            ? '$actorName invited you to a broadcast'
            : '$actorName invited you to $targetLabel';
      case NotificationType.liveStarted:
        return targetLabel == null
            ? '$actorName is live now'
            : '$actorName is live: $targetLabel';
      case NotificationType.directMessage:
        // Friend DMs never reach the bell (bellSuppressed), so a
        // directMessage row here is a non-friend reaching out — the
        // product's "message request" moment.
        return '$actorName sent you a message request';
      case NotificationType.directCall:
        return '$actorName is calling you';
      case NotificationType.missedCall:
        return 'Missed call from $actorName';
      case NotificationType.mention:
        return targetLabel == null
            ? '$actorName mentioned you'
            : '$actorName mentioned you in $targetLabel';
      case NotificationType.reply:
        return targetLabel == null
            ? '$actorName replied to you'
            : '$actorName replied to you in $targetLabel';
      case NotificationType.momentComment:
        return '$actorName commented on your Moment';
      case NotificationType.reelComment:
        return '$actorName commented on your Yeel';
      case NotificationType.commentMention:
        return '$actorName mentioned you in a comment';
      case NotificationType.serverEventReminder:
        return targetLabel == null
            ? 'An event is starting soon'
            : 'Starting soon: $targetLabel';
      case NotificationType.serverRole:
        return targetLabel == null
            ? '$actorName promoted you in a server'
            : '$actorName promoted you in $targetLabel';
      case NotificationType.pagePostComment:
        return '$actorName commented on your Page post';
      case NotificationType.pageModeration:
        return targetLabel ?? 'A moderator took action on your Page';
      case NotificationType.pageLapse:
        return targetLabel ?? 'Your Page changed while YO Voice VIP is off';
      case NotificationType.pagePostPublished:
        // `targetLabel` is the sentence for builds that do not know this
        // type; the title here names the Page itself.
        return '$actorName published a post';
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
      targetSubId: data['targetSubId'] as String?,
      sourcePath: data['sourcePath'] as String?,
      moderationAction: _optionalString(data['moderationAction']),
      moderationReason: _optionalString(data['moderationReason']),
      lapsePhase: _optionalString(data['lapsePhase']),
      postPreview: _optionalString(data['postPreview']),
      pageKind: _optionalString(data['pageKind']),
    );
  }

  static String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

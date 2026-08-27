import 'package:cloud_firestore/cloud_firestore.dart';

class VoiceMoment {
  const VoiceMoment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.caption,
    required this.audioUrl,
    required this.durationSeconds,
    required this.likeCount,
    required this.commentCount,
    required this.isPublished,
    required this.createdAt,
    this.expiresAt,
    this.schemaVersion = 0,
    this.status = 'legacy',
    this.isDeleted = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String caption;
  final String? audioUrl;
  final int durationSeconds;
  final int likeCount;
  final int commentCount;
  final bool isPublished;
  final DateTime? createdAt;

  /// When this Moment stops being publicly alive. Written by
  /// `finalizeMomentDraft` as `createdAt + availabilityHours` (24 by
  /// default; any whole-hour value from 24 through 720 is accepted); enforced
  /// server-side by the expiry sweeper AND client-side by [isActiveAt] so
  /// the sweep gap (up to 10 minutes) never surfaces a dead Moment.
  ///
  /// `null` means PERMANENT — the author chose "Keep until deleted", so
  /// finalize wrote no deadline at all and the sweeper never touches it
  /// (its range filter cannot match an absent field). This AMENDS
  /// ADR-101, which read null as legacy-expired: the operator asked for a
  /// keep-until-deleted option, and the only null-expiry documents in
  /// production are legacy ones the operator owns, so null now means
  /// "never expires" on every surface. Deletion is the author's exit.
  final DateTime? expiresAt;
  final int schemaVersion;
  final String status;
  final bool isDeleted;

  bool get isCanonicalPublished =>
      schemaVersion == 2 && status == 'published' && isPublished && !isDeleted;

  /// True when this Moment never expires: the author chose
  /// "Keep until deleted", so `finalizeMomentDraft` wrote no `expiresAt`.
  bool get isPermanent => expiresAt == null;

  /// Whether this Moment may be surfaced in a feed, strip or chain at
  /// [now].
  ///
  /// The rules, in the order they can fail:
  ///
  ///  * never deleted, never a draft (`isPublished` is the server's word);
  ///  * never `status == 'expired'` — the sweeper's mark is final even if
  ///    the timestamps somehow disagree;
  ///  * a present `expiresAt` must still be in the future; a MISSING
  ///    `expiresAt` means PERMANENT and always passes. This deliberately
  ///    reverses ADR-101's null=legacy-hidden rule (see [expiresAt]):
  ///    "keep until deleted" is expressed as no deadline, and the sweeper
  ///    already skips documents without the field.
  bool isActiveAt(DateTime now) {
    if (!isPublished || isDeleted) return false;
    if (status == 'expired') return false;
    final expiry = expiresAt;
    return expiry == null || expiry.isAfter(now);
  }

  factory VoiceMoment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    return VoiceMoment(
      id: document.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'YO Voice user',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      caption: data['caption'] as String? ?? '',
      audioUrl: data['audioUrl'] as String?,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      isPublished: data['isPublished'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? 'legacy',
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  /// A field-for-field copy with selective overrides. `expiresAt` and the
  /// other nullable fields keep their current value when the parameter is
  /// omitted; passing them explicitly replaces them.
  VoiceMoment copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorPhotoUrl,
    String? caption,
    String? audioUrl,
    int? durationSeconds,
    int? likeCount,
    int? commentCount,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? schemaVersion,
    String? status,
    bool? isDeleted,
  }) {
    return VoiceMoment(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      caption: caption ?? this.caption,
      audioUrl: audioUrl ?? this.audioUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  /// Only the two live counters, and only those, can be replaced.
  ///
  /// Deliberately narrow: this exists so a surface holding a Moment
  /// fetched once can adopt fresher `likeCount`/`commentCount` from a
  /// document listener WITHOUT re-fetching, re-ranking or inventing
  /// anything else about the Moment. Everything else on the document is
  /// immutable for the life of a rendered stack.
  VoiceMoment withCounts({int? likeCount, int? commentCount}) {
    if (likeCount == null && commentCount == null) return this;
    if ((likeCount ?? this.likeCount) == this.likeCount &&
        (commentCount ?? this.commentCount) == this.commentCount) {
      return this;
    }
    return copyWith(likeCount: likeCount, commentCount: commentCount);
  }

  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

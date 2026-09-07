import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/features/moderation/data/services/report_service.dart';

/// Where a report sits in triage. Mirrors the STATUS constants in
/// `functions/moderation/reports.js`, which is the only writer.
enum ReportStatus { open, inReview, resolved, dismissed }

/// Why a report was closed. Mirrors the RESOLUTIONS set in the same
/// function; the server rejects anything outside it.
enum ReportResolution {
  contentRemoved,
  warningIssued,
  noActionNeeded,
  notAViolation,
  duplicate,
  insufficientEvidence,
}

/// A report as staff see it.
///
/// Reporter-created evidence (reason, note, target, timestamps) is
/// immutable: no client can write it after creation, and the moderation
/// Function never touches those fields. Everything else here is workflow
/// state written exclusively by that Function.
class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.schemaVersion,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.momentId,
    required this.reelId,
    required this.reelAuthorId,
    required this.commentId,
    required this.reportedUserId,
    required this.contextPath,
    required this.targetText,
    required this.reason,
    required this.note,
    required this.createdAt,
    required this.status,
    required this.assignedTo,
    required this.assignedAt,
    required this.resolution,
    required this.resolutionNote,
    required this.resolvedBy,
    required this.resolvedAt,
    required this.contentRemoved,
  });

  final String id;
  final int? schemaVersion;

  /// Kept for the audit trail, NOT surfaced to the reported account or
  /// any ordinary client — reports are unreadable outside staff.
  final String reporterId;

  final ReportTargetType? targetType;
  final String targetId;
  final String? momentId;

  /// The Reel a reported comment sits under. Present only on `reelComment`
  /// reports, which the server writes with the full target identity.
  final String? reelId;

  /// Who owns the Reel a reported comment sits under.
  ///
  /// Not the person reported — that is [reportedUserId], the comment's
  /// author. This is surfaced because it is the difference between "a
  /// stranger left this under someone's Reel" and "the Reel's own author
  /// wrote it", and because the Reel's author is the other party who can
  /// remove the comment, so a moderator needs to know who that is.
  final String? reelAuthorId;

  final String? commentId;
  final String reportedUserId;
  final String? contextPath;

  /// The reported words, snapshotted into the report at creation time.
  ///
  /// Present only where the reported document itself is unreadable by staff —
  /// today that is `reelComment` alone. `reels/{id}/comments/{id}` is
  /// `allow read, write: if false` for every client, so without this field a
  /// moderator would be deciding a harassment report having never seen the
  /// harassment. It is also the only evidence that outlives the removal, and
  /// therefore the only thing an appeal can be judged against.
  final String? targetText;

  final ReportReason? reason;
  final String note;
  final DateTime? createdAt;

  final ReportStatus status;
  final String? assignedTo;
  final DateTime? assignedAt;
  final ReportResolution? resolution;
  final String? resolutionNote;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final bool contentRemoved;

  bool get isClosed =>
      status == ReportStatus.resolved || status == ReportStatus.dismissed;

  factory ModerationReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final targetType = _enumByName(
      ReportTargetType.values,
      data['targetType'] as String?,
    );
    final schemaVersion = (data['schemaVersion'] as num?)?.toInt();
    final momentId = _nonEmptyString(data['momentId']);
    final reelId = _nonEmptyString(data['reelId']);
    final reelAuthorId = _nonEmptyString(data['reelAuthorId']);
    final commentId = _nonEmptyString(data['commentId']);
    final storedTargetId = _nonEmptyString(data['targetId']);
    final targetId =
        storedTargetId ??
        switch (targetType) {
          ReportTargetType.voiceMoment => momentId ?? '',
          ReportTargetType.voiceMomentComment => commentId ?? momentId ?? '',
          // A reelComment report is server-written and always self-contained,
          // so this fallback is defensive only — there is no legacy shape.
          ReportTargetType.reelComment => commentId ?? '',
          _ => '',
        };
    final storedContextPath = _nonEmptyString(data['contextPath']);
    final contextPath =
        storedContextPath ??
        switch (targetType) {
          ReportTargetType.voiceMoment when momentId != null =>
            'voiceMoments/$momentId',
          ReportTargetType.voiceMomentComment
              when momentId != null && commentId != null =>
            'voiceMoments/$momentId/comments/$commentId',
          ReportTargetType.reelComment
              when reelId != null && commentId != null =>
            'reels/$reelId/comments/$commentId',
          _ => null,
        };

    return ModerationReport(
      id: document.id,
      schemaVersion: schemaVersion,
      reporterId: data['reporterId'] as String? ?? '',
      targetType: targetType,
      targetId: targetId,
      momentId: momentId,
      reelId: reelId,
      reelAuthorId: reelAuthorId,
      commentId: commentId,
      reportedUserId: _nonEmptyString(data['reportedUserId']) ?? '',
      contextPath: contextPath,
      // Kept verbatim — NOT trimmed to non-empty and NOT defaulted. A report
      // whose snapshot is missing must render as missing rather than as an
      // empty comment, because the two mean different things to a reviewer.
      targetText: data['targetTextSnapshot'] is String
          ? data['targetTextSnapshot'] as String
          : null,
      reason: _enumByName(ReportReason.values, data['reason'] as String?),
      note: data['note'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      // A document written before the workflow fields existed is Open.
      // The absence of the field IS the open state — no migration, no
      // Console work, and nothing disappears from the queue.
      status:
          _enumByName(ReportStatus.values, data['status'] as String?) ??
          ReportStatus.open,
      assignedTo: data['assignedTo'] as String?,
      assignedAt: (data['assignedAt'] as Timestamp?)?.toDate(),
      resolution: _enumByName(
        ReportResolution.values,
        data['resolution'] as String?,
      ),
      resolutionNote: data['resolutionNote'] as String?,
      resolvedBy: data['resolvedBy'] as String?,
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      contentRemoved: data['contentRemoved'] as bool? ?? false,
    );
  }

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null || name.isEmpty) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

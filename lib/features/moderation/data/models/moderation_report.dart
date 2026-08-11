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
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.reportedUserId,
    required this.contextPath,
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

  /// Kept for the audit trail, NOT surfaced to the reported account or
  /// any ordinary client — reports are unreadable outside staff.
  final String reporterId;

  final ReportTargetType? targetType;
  final String targetId;
  final String reportedUserId;
  final String? contextPath;
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

    return ModerationReport(
      id: document.id,
      reporterId: data['reporterId'] as String? ?? '',
      targetType: _enumByName(
        ReportTargetType.values,
        data['targetType'] as String?,
      ),
      targetId: data['targetId'] as String? ?? '',
      reportedUserId: data['reportedUserId'] as String? ?? '',
      contextPath: (data['contextPath'] as String?)?.trim().isNotEmpty == true
          ? data['contextPath'] as String
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
}

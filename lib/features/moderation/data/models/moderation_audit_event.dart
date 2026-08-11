/// Which question an audit event answers.
///
/// These are deliberately NOT merged. "The report was resolved" and
/// "the message was removed" are different facts recorded by different
/// writers, and collapsing them into one row would imply that every
/// resolution removed content — or that a removal always closed a
/// report. A remove-and-resolve produces one of each.
enum ModerationAuditKind {
  /// `report_{reportId}_{requestId}`, written by the `moderateReport`
  /// callable: how the REPORT moved through triage.
  reportWorkflow,

  /// `globalMessage_{eventId}`, written by the `onGlobalMessageModerated`
  /// trigger: what happened to the MESSAGE, and what it said.
  contentModeration,

  /// A record whose shape this build does not recognise. Rendered as an
  /// honest "unrecognised entry" rather than silently dropped, so a
  /// reviewer is never shown a trail with an invisible gap in it.
  unknown,
}

/// One entry in a report's moderation history.
///
/// Every field here comes from `listReportAuditTrail`'s response
/// allowlist. There is no raw document behind it: emails, provider data
/// and unrelated details keys never leave the server.
class ModerationAuditEvent {
  const ModerationAuditEvent({
    required this.id,
    required this.kind,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.previousStatus,
    required this.newStatus,
    required this.resolution,
    required this.note,
    required this.contentRemoved,
    required this.removedContent,
    required this.createdAt,
  });

  final String id;
  final ModerationAuditKind kind;
  final String action;
  final String? actorId;

  /// Public display name of the acting moderator, resolved server-side.
  final String? actorName;
  final String? actorRole;

  final String? previousStatus;
  final String? newStatus;
  final String? resolution;

  /// The moderator note as recorded with THIS action, bounded server-side.
  final String? note;

  final bool contentRemoved;

  /// For a content-moderation event: the message text as it was before
  /// removal. Bounded server-side.
  final String? removedContent;

  final DateTime? createdAt;

  factory ModerationAuditEvent.fromMap(Map<String, dynamic> map) {
    return ModerationAuditEvent(
      id: map['id'] as String? ?? '',
      kind: switch (map['kind']) {
        'reportWorkflow' => ModerationAuditKind.reportWorkflow,
        'contentModeration' => ModerationAuditKind.contentModeration,
        _ => ModerationAuditKind.unknown,
      },
      action: map['action'] as String? ?? 'unknown',
      actorId: map['actorId'] as String?,
      actorName: (map['actorName'] as String?)?.trim().isNotEmpty == true
          ? (map['actorName'] as String).trim()
          : null,
      actorRole: map['actorRole'] as String?,
      previousStatus: map['previousStatus'] as String?,
      newStatus: map['newStatus'] as String?,
      resolution: map['resolution'] as String?,
      note: (map['note'] as String?)?.trim().isNotEmpty == true
          ? (map['note'] as String).trim()
          : null,
      contentRemoved: map['contentRemoved'] == true,
      removedContent:
          (map['removedContent'] as String?)?.trim().isNotEmpty == true
          ? (map['removedContent'] as String).trim()
          : null,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '')?.toLocal(),
    );
  }
}

/// One bounded page of a report's history.
class ModerationAuditPage {
  const ModerationAuditPage({
    required this.events,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<ModerationAuditEvent> events;
  final bool hasMore;

  /// Passed back to fetch the next page. The server treats it as a
  /// strict upper bound on `createdAt`, so pages cannot overlap.
  final String? nextCursor;

  static const empty = ModerationAuditPage(
    events: <ModerationAuditEvent>[],
    hasMore: false,
    nextCursor: null,
  );

  factory ModerationAuditPage.fromResponse(Map<String, dynamic> data) {
    final raw = data['events'];
    return ModerationAuditPage(
      events: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (event) => ModerationAuditEvent.fromMap(
                    Map<String, dynamic>.from(event),
                  ),
                )
                .toList(growable: false)
          : const <ModerationAuditEvent>[],
      hasMore: data['hasMore'] == true,
      nextCursor: data['nextCursor'] as String?,
    );
  }
}

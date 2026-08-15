import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// One audit row from the owner's full browser (listAdminAuditLogs).
/// Unlike the overview summaries this carries the actor/target labels
/// the audit record itself holds — it is the owner-gated deep view.
@immutable
class StaffAuditEntry {
  const StaffAuditEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.actorRole,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.details,
    required this.createdAt,
  });

  factory StaffAuditEntry.fromMap(Map<String, dynamic> data) {
    final actor = Map<String, dynamic>.from(data['actor'] as Map? ?? {});
    final target = Map<String, dynamic>.from(data['target'] as Map? ?? {});
    return StaffAuditEntry(
      id: data['id'] as String? ?? '',
      action: data['action'] as String? ?? 'unknown',
      actorUid: actor['uid'] as String?,
      actorRole: actor['role'] as String?,
      targetType: target['type'] as String?,
      targetId: target['id'] as String?,
      targetLabel: target['name'] as String?,
      details: Map<String, dynamic>.from(data['details'] as Map? ?? {}),
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
    );
  }

  final String id;
  final String action;
  final String? actorUid;
  final String? actorRole;
  final String? targetType;
  final String? targetId;
  final String? targetLabel;
  final Map<String, dynamic> details;
  final DateTime? createdAt;
}

@immutable
class StaffAuditPage {
  const StaffAuditPage({required this.entries, required this.cursorId});

  final List<StaffAuditEntry> entries;
  final String? cursorId;
}

class StaffAuditService {
  StaffAuditService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<StaffAuditPage> list({
    String? action,
    String? actorUid,
    String? targetId,
    String? cursorId,
    int limit = 50,
  }) async {
    final result = await _functions
        .httpsCallable('listAdminAuditLogs')
        .call<Map<String, dynamic>>(<String, dynamic>{
          'limit': limit,
          if (action != null && action.isNotEmpty) 'action': action,
          if (actorUid != null && actorUid.isNotEmpty) 'actorUid': actorUid,
          if (targetId != null && targetId.isNotEmpty) 'targetId': targetId,
          'cursorId': ?cursorId,
        });
    final data = Map<String, dynamic>.from(result.data);
    return StaffAuditPage(
      entries: (data['logs'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => StaffAuditEntry.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      cursorId: data['nextCursorId'] as String?,
    );
  }
}

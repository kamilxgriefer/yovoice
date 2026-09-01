import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Server-derived counts for the Staff Center overview. Every number is
/// a real aggregate; the client never invents one.
@immutable
class StaffOverviewCounts {
  const StaffOverviewCounts({
    required this.totalUsers,
    required this.activeRooms,
    required this.openReports,
    required this.restrictedAccounts,
    required this.staffMembers,
    required this.vipUsers,
    required this.securityAlerts,
  });

  factory StaffOverviewCounts.fromMap(Map<String, dynamic> data) =>
      StaffOverviewCounts(
        totalUsers: (data['totalUsers'] as num?)?.toInt() ?? 0,
        activeRooms: (data['activeRooms'] as num?)?.toInt() ?? 0,
        openReports: (data['openReports'] as num?)?.toInt() ?? 0,
        restrictedAccounts: (data['restrictedAccounts'] as num?)?.toInt() ?? 0,
        staffMembers: (data['staffMembers'] as num?)?.toInt() ?? 0,
        vipUsers: (data['vipUsers'] as num?)?.toInt() ?? 0,
        securityAlerts: (data['securityAlerts'] as num?)?.toInt() ?? 0,
      );

  final int totalUsers;
  final int activeRooms;
  final int openReports;
  final int restrictedAccounts;
  final int staffMembers;
  final int vipUsers;
  final int securityAlerts;
}

@immutable
class OverviewReport {
  const OverviewReport({
    required this.id,
    required this.targetType,
    required this.reason,
    required this.status,
    required this.reportedUserId,
    required this.createdAt,
  });

  factory OverviewReport.fromMap(Map<String, dynamic> data) => OverviewReport(
    id: data['id'] as String? ?? '',
    targetType: data['targetType'] as String?,
    reason: data['reason'] as String?,
    status: data['status'] as String? ?? 'open',
    reportedUserId: data['reportedUserId'] as String?,
    createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
  );

  final String id;
  final String? targetType;
  final String? reason;
  final String status;
  final String? reportedUserId;
  final DateTime? createdAt;
}

@immutable
class OverviewRoom {
  const OverviewRoom({
    required this.id,
    required this.name,
    required this.hostId,
    required this.hostName,
    required this.participantCount,
    required this.experience,
  });

  factory OverviewRoom.fromMap(Map<String, dynamic> data) => OverviewRoom(
    id: data['id'] as String? ?? '',
    name: data['name'] as String? ?? '',
    hostId: data['hostId'] as String?,
    hostName: data['hostName'] as String? ?? '',
    participantCount: (data['participantCount'] as num?)?.toInt() ?? 0,
    experience: data['experience'] as String?,
  );

  final String id;
  final String name;
  final String? hostId;
  final String hostName;
  final int participantCount;
  final String? experience;
}

/// A summarised audit row: ids and roles, never an email.
@immutable
class OverviewAuditEntry {
  const OverviewAuditEntry({
    required this.id,
    required this.action,
    required this.actorId,
    required this.actorRole,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.role,
    required this.previousRole,
    required this.createdAt,
  });

  factory OverviewAuditEntry.fromMap(Map<String, dynamic> data) {
    final details = Map<String, dynamic>.from(data['details'] as Map? ?? {});
    return OverviewAuditEntry(
      id: data['id'] as String? ?? '',
      action: data['action'] as String? ?? 'unknown',
      actorId: data['actorId'] as String?,
      actorRole: data['actorRole'] as String?,
      targetType: data['targetType'] as String?,
      targetId: data['targetId'] as String?,
      reason: details['reason'] as String?,
      role: details['role'] as String?,
      previousRole: details['previousRole'] as String?,
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
    );
  }

  final String id;
  final String action;
  final String? actorId;
  final String? actorRole;
  final String? targetType;
  final String? targetId;
  final String? reason;
  final String? role;
  final String? previousRole;
  final DateTime? createdAt;
}

@immutable
class StaffOverview {
  const StaffOverview({
    required this.counts,
    required this.latestOpenReports,
    required this.activeRooms,
    required this.recentSanctions,
    required this.recentRoleChanges,
    required this.securityAlerts,
  });

  factory StaffOverview.fromMap(Map<String, dynamic> data) {
    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (data[key] as List? ?? const [])
            .whereType<Map>()
            .map((row) => parse(Map<String, dynamic>.from(row)))
            .toList(growable: false);
    return StaffOverview(
      counts: StaffOverviewCounts.fromMap(
        Map<String, dynamic>.from(data['counts'] as Map? ?? {}),
      ),
      latestOpenReports: parseList('latestOpenReports', OverviewReport.fromMap),
      activeRooms: parseList('activeRooms', OverviewRoom.fromMap),
      recentSanctions: parseList('recentSanctions', OverviewAuditEntry.fromMap),
      recentRoleChanges: parseList(
        'recentRoleChanges',
        OverviewAuditEntry.fromMap,
      ),
      securityAlerts: parseList('securityAlerts', OverviewAuditEntry.fromMap),
    );
  }

  final StaffOverviewCounts counts;
  final List<OverviewReport> latestOpenReports;
  final List<OverviewRoom> activeRooms;
  final List<OverviewAuditEntry> recentSanctions;
  final List<OverviewAuditEntry> recentRoleChanges;
  final List<OverviewAuditEntry> securityAlerts;
}

class StaffOverviewService {
  StaffOverviewService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<StaffOverview> load() async {
    final result = await _functions
        .httpsCallable('getStaffOverview')
        .call<Map<String, dynamic>>(<String, dynamic>{});
    return StaffOverview.fromMap(Map<String, dynamic>.from(result.data));
  }
}

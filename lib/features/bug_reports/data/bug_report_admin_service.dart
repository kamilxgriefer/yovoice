import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/bug_reports/data/bug_report_service.dart';

/// Triage states, exactly the server's `STATUSES`.
const List<String> bugReportStatuses = <String>[
  'new',
  'triaged',
  'resolved',
  'dismissed',
];

@immutable
class BugReportSummary {
  const BugReportSummary({
    required this.reportId,
    required this.reporterId,
    required this.status,
    required this.createdAt,
    required this.descriptionPreview,
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.route,
    required this.screenshotStatus,
  });

  factory BugReportSummary.fromMap(Map<Object?, Object?> map) {
    String? text(Object? value) => value is String ? value : null;
    final created = map['createdAtMillis'];
    return BugReportSummary(
      reportId: text(map['reportId']) ?? '',
      reporterId: text(map['reporterId']),
      status: text(map['status']) ?? 'new',
      createdAt: created is int
          ? DateTime.fromMillisecondsSinceEpoch(created)
          : null,
      descriptionPreview: text(map['descriptionPreview']) ?? '',
      platform: text(map['platform']),
      appVersion: text(map['appVersion']),
      buildNumber: text(map['buildNumber']),
      route: text(map['route']),
      screenshotStatus: text(map['screenshotStatus']) ?? 'none',
    );
  }

  final String reportId;
  final String? reporterId;
  final String status;
  final DateTime? createdAt;
  final String descriptionPreview;
  final String? platform;
  final String? appVersion;
  final String? buildNumber;
  final String? route;
  final String screenshotStatus;
}

@immutable
class BugReportDetail {
  const BugReportDetail({
    required this.summary,
    required this.description,
    required this.context,
    required this.screenshotUrl,
    required this.delivery,
  });

  factory BugReportDetail.fromMap(Map<Object?, Object?> map) {
    final context = map['context'];
    final screenshot = map['screenshot'];
    final delivery = map['delivery'];
    return BugReportDetail(
      summary: BugReportSummary.fromMap(map),
      description: map['description'] is String
          ? map['description'] as String
          : '',
      context: <String, String>{
        if (context is Map)
          for (final entry in context.entries)
            if (entry.key is String && entry.value != null)
              entry.key as String: '${entry.value}',
      },
      screenshotUrl: screenshot is Map && screenshot['url'] is String
          ? screenshot['url'] as String
          : null,
      delivery: <String, String>{
        if (delivery is Map)
          for (final entry in delivery.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: '${(entry.value as Map)['status']}',
      },
    );
  }

  final BugReportSummary summary;
  final String description;
  final Map<String, String> context;
  final String? screenshotUrl;
  final Map<String, String> delivery;
}

@immutable
class BugReportPage {
  const BugReportPage({required this.reports, required this.nextCursor});

  final List<BugReportSummary> reports;
  final String? nextCursor;
}

/// The owner's read and triage path. Every call is refused server-side for
/// anyone but the protected owner (YOVOICE_PROTECTED_OWNER_UID); nothing here
/// is an authorization decision.
class BugReportAdminService {
  BugReportAdminService({
    FirebaseFunctions? functions,
    BugReportCallableInvoker? invoker,
  }) : _functions = functions,
       _invoker = invoker;

  final FirebaseFunctions? _functions;
  final BugReportCallableInvoker? _invoker;

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, payload);
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
    final response = await functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(payload);
    return response.data;
  }

  Future<BugReportPage> list({String? status, String? cursor}) async {
    final data = await _call('listBugReportsV1', <String, Object?>{
      'limit': 25,
      'status': status,
      'cursor': cursor,
    });
    final rows = data['reports'];
    final next = data['nextCursor'];
    return BugReportPage(
      reports: <BugReportSummary>[
        if (rows is List)
          for (final row in rows)
            if (row is Map) BugReportSummary.fromMap(row),
      ],
      nextCursor: next is String ? next : null,
    );
  }

  Future<BugReportDetail> get(String reportId) async {
    final data = await _call('getBugReportV1', <String, Object?>{
      'reportId': reportId,
    });
    return BugReportDetail.fromMap(data);
  }

  Future<void> updateStatus(String reportId, String status) async {
    await _call('updateBugReportStatusV1', <String, Object?>{
      'reportId': reportId,
      'status': status,
    });
  }
}

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/messages/data/models/global_message.dart';
import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';

/// Why a privileged moderation call failed, so the panel can say
/// something true instead of "error".
enum ModerationFailure {
  /// Another moderator holds this report, or it moved on since the queue
  /// was rendered.
  conflict,

  /// Already resolved or dismissed.
  alreadyHandled,

  /// The role was revoked, the account was restricted, or this action is
  /// above the caller's role.
  accessExpired,

  /// The report or its target is gone.
  missing,

  /// Network, offline, or anything else.
  unknown,
}

class ModerationException implements Exception {
  const ModerationException(this.failure, this.message);

  final ModerationFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// The result of a successful triage call, as the SERVER reported it.
/// The panel renders this rather than assuming its own optimistic
/// outcome.
class ModerationResult {
  const ModerationResult({
    required this.status,
    required this.contentRemoved,
    required this.replayed,
  });

  final ReportStatus status;
  final bool contentRemoved;

  /// True when the server recognised this as a retry of a call it had
  /// already applied, and changed nothing.
  final bool replayed;
}

/// Staff-side access to the report queue.
///
/// READS are direct Firestore queries, gated by `isActiveStaff()` in
/// firestore.rules — the signed `role` claim AND the server-written
/// `users/{uid}.role` mirror AND an unrestricted account. A revoked role
/// therefore stops working on the next request rather than when the
/// token expires.
///
/// WRITES are not client writes at all: every triage action goes through
/// the `moderateReport` callable, which re-checks the same authority
/// server-side, enforces the state machine, detects another moderator's
/// claim, and writes the audit record. firestore.rules denies client
/// updates to `reports` outright, so this is the only path.
class ModerationService {
  ModerationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // Resolved lazily for the same reason ClubService does it:
  // FirebaseFunctions.instance throws with no Firebase app, which would
  // make the service unconstructible in widget tests that only read.
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// One page of the queue. The collection is never downloaded whole.
  static const int pageSize = 20;

  /// Mirrors MAX_MODERATOR_NOTE in functions/moderation/reports.js.
  static const int maxModeratorNoteLength = 500;

  /// Mirrors DEFAULT_LIMIT in functions/moderation/report_audit.js. The
  /// callable caps it at MAX_LIMIT regardless of what is asked for.
  static const int auditPageSize = 10;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('reports');

  /// Whether this account is staff by BOTH measures the server requires.
  ///
  /// The claim alone would keep a demoted moderator inside the panel
  /// until their token expired; the document alone could not be trusted
  /// if it were client-writable (it is not). Requiring both here means
  /// the UI agrees with what rules and the Function will actually allow.
  Future<bool> isActiveStaff() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult();
      final claim = token.claims?['role'];
      const staff = ['moderator', 'admin', 'superAdmin'];
      if (claim is! String || !staff.contains(claim)) return false;

      final profile = await _firestore.collection('users').doc(user.uid).get();
      final data = profile.data() ?? const <String, dynamic>{};
      if (data['banned'] == true) return false;
      final documentRole = data['role'];
      return documentRole is String && staff.contains(documentRole);
    } catch (_) {
      return false;
    }
  }

  /// The caller's server-side role, for deciding which actions to OFFER.
  /// The Function re-checks; this only shapes the UI.
  Future<String> currentRole() async {
    final user = _auth.currentUser;
    if (user == null) return 'user';
    try {
      final profile = await _firestore.collection('users').doc(user.uid).get();
      final role = profile.data()?['role'];
      return role is String ? role : 'user';
    } catch (_) {
      return 'user';
    }
  }

  /// The queue, newest first.
  ///
  /// EVERY filter is a server-side equality clause — status, target type
  /// and reason alike. Narrowing a page in Dart would be a lie: one page
  /// of the broad query, filtered locally, looks like "all open spam
  /// reports" while actually being "the spam reports that happened to
  /// fall in the newest 20 open ones". The composite indexes for each
  /// combination the UI can produce are declared in
  /// firestore.indexes.json.
  ///
  /// Ordering is deterministic: Firestore appends `__name__` in the same
  /// direction as the final orderBy, so two reports filed in the same
  /// millisecond keep one stable order, and a growing window cannot
  /// reorder or duplicate them.
  Stream<List<ModerationReport>> watchQueue({
    required ReportStatus status,
    ReportTargetType? targetType,
    ReportReason? reason,
    int limit = pageSize,
  }) {
    Query<Map<String, dynamic>> query = _reports.where(
      'status',
      isEqualTo: status.name,
    );
    if (targetType != null) {
      query = query.where('targetType', isEqualTo: targetType.name);
    }
    if (reason != null) {
      query = query.where('reason', isEqualTo: reason.name);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ModerationReport.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<ModerationReport?> watchReport(String reportId) {
    return _reports
        .doc(reportId)
        .snapshots()
        .map((doc) => doc.exists ? ModerationReport.fromFirestore(doc) : null);
  }

  /// The reported account's PUBLIC profile fields only — the same
  /// document any signed-in member can already read. Nothing private
  /// (email, phone, provider data, internal flags) is returned, and the
  /// detail panel is given only these two values.
  Future<({String? displayName, String? photoUrl})?> publicProfile(
    String userId,
  ) async {
    if (userId.isEmpty) return null;
    final snapshot = await _firestore.collection('users').doc(userId).get();
    final data = snapshot.data();
    if (data == null) return null;
    return (
      displayName: (data['displayName'] as String?)?.trim(),
      photoUrl: (data['photoUrl'] as String?)?.trim(),
    );
  }

  /// The reported Global Chat message, or null if it no longer exists.
  Future<GlobalMessage?> targetMessage(String messageId) async {
    if (messageId.isEmpty) return null;
    final snapshot = await _firestore
        .collection('globalChat')
        .doc('main')
        .collection('messages')
        .doc(messageId)
        .get();
    if (!snapshot.exists) return null;
    return GlobalMessage.fromFirestore(snapshot);
  }

  /// The selected report's moderation history.
  ///
  /// Goes through `listReportAuditTrail`, NOT the broad
  /// `listAdminAuditLogs` browser: `adminAuditLogs` is unreadable by
  /// every client (rules deny it outright), and the scoped callable
  /// derives the target ids from the report document, so there is no
  /// parameter a caller could point at another report or an unrelated
  /// admin action.
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = auditPageSize,
    String? cursor,
  }) async {
    try {
      final callable = _functions.httpsCallable('listReportAuditTrail');
      final response = await callable.call<Map<String, dynamic>>({
        'reportId': reportId,
        'limit': limit,
        'cursor': ?cursor,
      });
      return ModerationAuditPage.fromResponse(response.data);
    } on FirebaseFunctionsException catch (error) {
      throw ModerationException(_failureFor(error), _messageFor(error));
    } catch (_) {
      throw const ModerationException(
        ModerationFailure.unknown,
        'The activity history could not be loaded.',
      );
    }
  }

  /// A fresh idempotency key. Held by the UI for the lifetime of one
  /// user action so a retry after a failure reuses it and cannot apply
  /// the action twice.
  static String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<ModerationResult> claim(String reportId, {required String requestId}) =>
      _call(reportId: reportId, action: 'claim', requestId: requestId);

  Future<ModerationResult> release(
    String reportId, {
    required String requestId,
  }) => _call(reportId: reportId, action: 'release', requestId: requestId);

  Future<ModerationResult> resolve(
    String reportId, {
    required ReportResolution resolution,
    required String requestId,
    String note = '',
  }) => _call(
    reportId: reportId,
    action: 'resolve',
    requestId: requestId,
    resolution: resolution,
    note: note,
  );

  Future<ModerationResult> removeContentAndResolve(
    String reportId, {
    required String requestId,
    String note = '',
  }) => _call(
    reportId: reportId,
    action: 'removeAndResolve',
    requestId: requestId,
    resolution: ReportResolution.contentRemoved,
    note: note,
  );

  Future<ModerationResult> dismiss(
    String reportId, {
    required ReportResolution resolution,
    required String requestId,
    String note = '',
  }) => _call(
    reportId: reportId,
    action: 'dismiss',
    requestId: requestId,
    resolution: resolution,
    note: note,
  );

  Future<ModerationResult> _call({
    required String reportId,
    required String action,
    required String requestId,
    ReportResolution? resolution,
    String note = '',
  }) async {
    try {
      final callable = _functions.httpsCallable('moderateReport');
      final response = await callable.call<Map<String, dynamic>>({
        'reportId': reportId,
        'action': action,
        'requestId': requestId,
        if (resolution != null) 'resolution': resolution.name,
        if (note.trim().isNotEmpty)
          'moderatorNote': note.trim().length > maxModeratorNoteLength
              ? note.trim().substring(0, maxModeratorNoteLength)
              : note.trim(),
      });

      final data = response.data;
      return ModerationResult(
        status:
            ReportStatus.values.firstWhere(
              (value) => value.name == data['status'],
              orElse: () => ReportStatus.open,
            ),
        contentRemoved: data['contentRemoved'] == true,
        replayed: data['replayed'] == true,
      );
    } on FirebaseFunctionsException catch (error) {
      throw ModerationException(_failureFor(error), _messageFor(error));
    } catch (error) {
      throw ModerationException(
        ModerationFailure.unknown,
        'That did not go through. Check your connection and try again.',
      );
    }
  }

  static ModerationFailure _failureFor(FirebaseFunctionsException error) {
    return switch (error.code) {
      'aborted' => ModerationFailure.conflict,
      'failed-precondition' => ModerationFailure.alreadyHandled,
      'permission-denied' || 'unauthenticated' =>
        ModerationFailure.accessExpired,
      'not-found' => ModerationFailure.missing,
      _ => ModerationFailure.unknown,
    };
  }

  static String _messageFor(FirebaseFunctionsException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return 'That action could not be completed.';
  }
}

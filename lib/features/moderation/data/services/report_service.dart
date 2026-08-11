import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What a report is about. The names are the values firestore.rules
/// accepts; adding one here without adding it there produces a denied
/// write, not a silently unvalidated field.
enum ReportTargetType {
  /// A single Global Chat message.
  globalMessage,

  /// An account, independent of any one message.
  user,
}

/// Why something was reported. A closed set rather than free text, so
/// triage can filter and a reporter cannot use the field as a message
/// channel. Free-form context goes in the bounded [ReportService.report]
/// `note`.
enum ReportReason {
  spam,
  harassment,
  hate,
  sexual,
  violence,
  selfHarm,
  impersonation,
  other,
}

/// Abuse reports.
///
/// NEW with Global Chat: before it there was no reporting anywhere in the
/// product (blocking existed, reporting did not). A public channel open
/// to the whole community cannot ship without one, so this is the secure
/// minimum built on patterns already here rather than a new moderation
/// stack.
///
/// WHAT firestore.rules ENFORCES — none of it is client-side courtesy:
///
///  - **Identity**: `reporterId` must equal the caller's uid and
///    `createdAt` must equal the server's `request.time`.
///  - **Uniqueness**: the document id must be
///    `{reporterId}_{targetType}_{targetId}` ([reportIdFor]). A second
///    report of the same thing by the same person is a create against an
///    existing document, which Firestore rejects by itself — no counter,
///    no query, nothing to race.
///  - **Real targets**: the reported message or user must exist, and
///    `reportedUserId` must be the account that actually owns it, so the
///    collection cannot be used to attach arbitrary uids to complaints.
///  - **Shape**: exact field allowlist, `reason` from the enum above, a
///    note of at most [maxNoteLength] characters.
///  - **Workflow**: the only workflow field a client may write is
///    `status`, pinned by rules to `'open'`. Assignment, resolution, the
///    acting moderator and every review timestamp are written by the
///    `moderateReport` Cloud Function through the Admin SDK, so nobody
///    can file a pre-closed or self-assigned report — and no client,
///    staff included, can move a report's status directly.
///  - **Rate limit**: [reportCooldown] between reports and
///    [dailyLimit] per FIXED 24-hour window, enforced atomically through
///    `reportLimits/{uid}` exactly like Global Chat's sender state.
///  - **Account status**: restricted accounts cannot file at all.
///  - **Visibility**: members can never read, edit or withdraw a report,
///    including their own. Reads and triage require the platform `role`
///    claim.
///
/// LIMITATION worth stating plainly: filing a report records it for
/// review. There is no automated action, no notification to the reporter,
/// and no Admin Center screen listing these yet — triage is a Firestore
/// Console job until one is built.
class ReportService {
  ReportService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Mirrors the `note.size() <= 300` bound in firestore.rules.
  static const int maxNoteLength = 300;

  /// Mirrors `duration.value(30, 's')` in firestore.rules.
  static const Duration reportCooldown = Duration(seconds: 30);

  /// Mirrors `duration.value(24, 'h')` and the `<= 20` cap. FIXED
  /// (tumbling) window, like Global Chat's send limit: the window opens
  /// at the first report and resets only once a full 24 hours have
  /// passed from that instant.
  static const Duration dailyWindow = Duration(hours: 24);
  static const int dailyLimit = 20;

  /// The deterministic document id rules require. Exposed because it is
  /// part of the contract, not an implementation detail: the same
  /// reporter reporting the same target always addresses the same
  /// document.
  static String reportIdFor({
    required String reporterId,
    required ReportTargetType targetType,
    required String targetId,
  }) => '${reporterId}_${targetType.name}_$targetId';

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to report content.');
    }
    return user;
  }

  /// The reporter's current rate-limit state.
  Future<ReportAllowance> allowance() async {
    final user = _auth.currentUser;
    if (user == null) return const ReportAllowance.allowed();

    final snapshot = await _firestore
        .collection('reportLimits')
        .doc(user.uid)
        .get();
    final data = snapshot.data();
    if (data == null) return const ReportAllowance.allowed();

    final now = DateTime.now().toUtc();
    final lastAt = (data['lastReportAt'] as Timestamp?)?.toDate().toUtc();
    final windowStartAt =
        (data['windowStartAt'] as Timestamp?)?.toDate().toUtc();
    final windowCount = (data['windowCount'] as num?)?.toInt() ?? 0;

    if (windowStartAt != null &&
        now.difference(windowStartAt) < dailyWindow &&
        windowCount >= dailyLimit) {
      return ReportAllowance.blocked(
        retryAfter: windowStartAt.add(dailyWindow).difference(now),
        atDailyLimit: true,
      );
    }
    if (lastAt != null && now.difference(lastAt) < reportCooldown) {
      return ReportAllowance.blocked(
        retryAfter: lastAt.add(reportCooldown).difference(now),
        atDailyLimit: false,
      );
    }
    return const ReportAllowance.allowed();
  }

  /// Files a report. [reportedUserId] is the account being reported —
  /// for a message that is its author, which rules verify against the
  /// message document itself.
  ///
  /// Throws [ReportAlreadyFiledException] when this reporter has already
  /// reported this exact target, so the UI can say so instead of
  /// surfacing a permission error.
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required String reportedUserId,
    required ReportReason reason,
    String note = '',
    String? contextPath,
  }) async {
    final user = _user;
    if (reportedUserId == user.uid) {
      throw StateError('You cannot report yourself.');
    }

    final reportId = reportIdFor(
      reporterId: user.uid,
      targetType: targetType,
      targetId: targetId,
    );
    final report = _firestore.collection('reports').doc(reportId);
    final limits = _firestore.collection('reportLimits').doc(user.uid);

    // Same pattern as Global Chat's sender state: read the current
    // window only to decide which shape to write. Rules re-derive the
    // decision from the stored document, so a client that lies here is
    // rejected rather than believed.
    final existing = await limits.get();
    final data = existing.data();
    final windowStartedAt = (data?['windowStartAt'] as Timestamp?)?.toDate();
    final windowLive =
        windowStartedAt != null &&
        DateTime.now().toUtc().difference(windowStartedAt.toUtc()) <
            dailyWindow;
    final windowCount = (data?['windowCount'] as num?)?.toInt() ?? 0;

    final trimmed = note.trim();
    final batch = _firestore.batch();

    batch.set(report, {
      'reporterId': user.uid,
      'targetType': targetType.name,
      'targetId': targetId,
      'reportedUserId': reportedUserId,
      'contextPath': contextPath,
      'reason': reason.name,
      'note': trimmed.length > maxNoteLength
          ? trimmed.substring(0, maxNoteLength)
          : trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      // The one workflow field a client may write, pinned by rules to
      // this exact value. Everything else about triage is set by the
      // moderateReport Function.
      'status': 'open',
    });
    batch.set(limits, {
      'lastReportAt': FieldValue.serverTimestamp(),
      'lastReportId': reportId,
      'windowStartAt': windowLive
          ? data!['windowStartAt']
          : FieldValue.serverTimestamp(),
      'windowCount': windowLive ? windowCount + 1 : 1,
    });

    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      // A duplicate is a create against an existing document, which the
      // staff-only update rule denies — indistinguishable from any other
      // refusal at the wire level, so it is disambiguated here.
      if (error.code == 'permission-denied' &&
          (await report.get().then((snapshot) => snapshot.exists).catchError(
            (_) => false,
          ))) {
        throw const ReportAlreadyFiledException();
      }
      rethrow;
    }
  }
}

/// Whether this account may file a report right now, and if not, which
/// limit is holding it and for how long. Rules remain the enforcement;
/// this exists so the UI can say "wait 12 seconds" instead of
/// "permission denied".
class ReportAllowance {
  const ReportAllowance.allowed()
    : canReport = true,
      retryAfter = Duration.zero,
      atDailyLimit = false;

  const ReportAllowance.blocked({
    required this.retryAfter,
    required this.atDailyLimit,
  }) : canReport = false;

  final bool canReport;
  final Duration retryAfter;
  final bool atDailyLimit;
}

/// This reporter has already reported this exact target.
class ReportAlreadyFiledException implements Exception {
  const ReportAlreadyFiledException();

  @override
  String toString() => 'You have already reported this.';
}

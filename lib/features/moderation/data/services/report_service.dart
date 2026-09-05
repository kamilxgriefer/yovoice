import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What a report is about. The names are the values firestore.rules
/// accepts; adding one here without adding it there produces a denied
/// write, not a silently unvalidated field.
enum ReportTargetType {
  /// A single Global Chat message.
  globalMessage,

  /// A published Reel created through the server-authoritative Reel flow.
  reel,

  /// A published Voice Moment reported through `createContentReport`.
  voiceMoment,

  /// One comment attached to a Voice Moment, reported through
  /// `createContentReport`.
  voiceMomentComment,

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

  /// Mirrors the `contextPath.size() <= 300` bound in firestore.rules.
  static const int maxContextPathLength = 300;

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
    final windowStartAt = (data['windowStartAt'] as Timestamp?)
        ?.toDate()
        .toUtc();
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
  /// FAILURE COPY IS PART OF THIS CONTRACT. Every throw below is a
  /// `StateError` carrying a finished sentence, so a caller running it
  /// through `intentionalOrFriendly` shows the reporter which of
  /// "already reported", "too fast", "daily limit reached" or
  /// "something went wrong" applies. That mattered because the previous
  /// version could not tell them apart: it tried to distinguish a
  /// duplicate by reading its own report back, `reports` is
  /// `allow read: if isActiveStaff()`, and so the read was denied every
  /// time, [ReportAlreadyFiledException] was unreachable in production,
  /// and all three states reached the user as
  /// `[cloud_firestore/permission-denied] The caller does not have
  /// permission…` on a safety path.
  ///
  /// Throws:
  ///  - [ReportRateLimitedException] when the cooldown or the daily cap
  ///    is holding, decided BEFORE the write from `reportLimits/{uid}`,
  ///    which the owner may read. This is the only place the two limits
  ///    can be told apart at all — rules answer both with the same
  ///    refusal.
  ///  - [ReportAlreadyFiledException] when the write is refused after
  ///    that pre-flight passed. See the note at the catch for exactly
  ///    how sound that inference is.
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
    // Bounded in rules at 300; a caller passing something longer would
    // otherwise produce a refusal indistinguishable from a duplicate.
    if (contextPath != null && contextPath.length > maxContextPathLength) {
      throw ArgumentError('The report context is too long to record.');
    }

    // Decided here rather than inferred from the refusal, because rules
    // cannot tell the reporter which limit stopped them and this
    // document can.
    final current = await allowance();
    if (!current.canReport) {
      throw ReportRateLimitedException(
        retryAfter: current.retryAfter,
        atDailyLimit: current.atDailyLimit,
      );
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
      if (error.code != 'permission-denied') rethrow;

      // A duplicate is a create against an existing document; the create
      // rule no longer applies and `allow update: if false` refuses it.
      // At the wire level that is the same `permission-denied` as every
      // other refusal, and the report itself CANNOT be read back to
      // check — `reports` is staff-read-only by design, and opening it
      // to reporters would expose the moderation workflow fields
      // (assignee, acting moderator, review timestamps) that
      // `moderateReport` adds later. So this is decided by elimination
      // instead of by a read.
      //
      // Every other create precondition is satisfied by construction
      // above: the document id, the field allowlist, `reporterId`, the
      // server timestamp, `status: 'open'`, an enum reason, the
      // truncated note, the bounded context path, and
      // `reportedUserId != uid`. The rate limit was just checked against
      // the document rules re-derive it from. What remains is a
      // duplicate, a restricted reporter, or a target that vanished
      // between the check and the write — and of those, only the
      // duplicate is a state the reporter can act on or would recognise.
      // Being told "you already reported this" in the rare other two is
      // a far smaller failure than today's raw permission error, and
      // neither of them loses a report that would otherwise have been
      // filed.
      throw ReportAlreadyFiledException();
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
///
/// A `StateError` so `intentionalOrFriendly` in
/// `lib/core/helpers/error_messages.dart` shows this sentence as written
/// instead of laundering it into "You don't have permission to do that."
class ReportAlreadyFiledException extends StateError {
  ReportAlreadyFiledException()
    : super('You already reported this. Our team still has it.');

  @override
  String toString() => message;
}

/// A report was refused by one of the two rate limits, and this says
/// which one.
///
/// The distinction is not cosmetic. "Wait 12 seconds" is a pause;
/// "you have used your 20 reports for today" means the person in front
/// of a sustained abuse campaign has to be told to use blocking instead,
/// and cannot be left tapping a button that will keep refusing for
/// hours.
class ReportRateLimitedException extends StateError {
  ReportRateLimitedException({
    required this.retryAfter,
    required this.atDailyLimit,
  }) : super(_message(retryAfter, atDailyLimit));

  /// How long until the holding limit lifts.
  final Duration retryAfter;

  /// True for the [ReportService.dailyLimit] cap, false for the
  /// [ReportService.reportCooldown] between reports.
  final bool atDailyLimit;

  static String _message(Duration retryAfter, bool atDailyLimit) {
    if (atDailyLimit) {
      return "You've reached the limit of ${ReportService.dailyLimit} "
          'reports in 24 hours. You can report again in '
          '${_humanize(retryAfter)}. If someone is still bothering you, '
          'block them in the meantime.';
    }
    return 'You just sent a report. Please wait '
        '${_humanize(retryAfter)} before sending another.';
  }

  static String _humanize(Duration remaining) {
    // Rounded up, never down: telling someone to wait 12 seconds when it
    // is really 12.6 produces one more refusal.
    if (remaining <= Duration.zero) return 'a moment';
    if (remaining.inMinutes < 1) {
      final seconds = (remaining.inMilliseconds / 1000).ceil();
      return '$seconds second${seconds == 1 ? '' : 's'}';
    }
    if (remaining.inHours < 1) {
      final minutes = (remaining.inSeconds / 60).ceil();
      return '$minutes minute${minutes == 1 ? '' : 's'}';
    }
    final hours = (remaining.inMinutes / 60).ceil();
    return 'about $hours hour${hours == 1 ? '' : 's'}';
  }

  @override
  String toString() => message;
}

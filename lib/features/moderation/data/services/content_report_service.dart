import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:yovoice/features/moderation/data/services/report_service.dart';

/// A single piece of content the deployed `createContentReport` callable
/// will accept.
///
/// THIS LIST IS THE SERVER'S, NOT OURS. `createContentReport`
/// (`functions/moments/integrity.js`) hard-rejects any `targetType`
/// outside `directMessage` / `voiceMoment` / `voiceMomentComment` with
/// `invalid-argument`. Room messages and club messages are NOT reportable
/// through it — adding cases here without the matching Functions change
/// produces a rejected call, not a quietly unvalidated report.
enum ReportedContentType {
  /// One message inside a two-person conversation. The server re-checks
  /// that the caller is one of the two participants.
  directMessage,

  /// A published Voice Moment.
  voiceMoment,

  /// One comment on a Voice Moment.
  voiceMomentComment,
}

/// Which document is being reported, in the exact shape the callable
/// validates. The server rejects any combination of ids other than the
/// one its `targetType` expects, so these constructors are the only
/// legal ways to build a call.
class ReportedContent {
  const ReportedContent._({
    required this.type,
    this.conversationId,
    this.messageId,
    this.momentId,
    this.commentId,
    this.reportReceipt,
  });

  /// A direct message. Reportable only by a participant of
  /// [conversationId] — the server reads the conversation and refuses
  /// anyone else with `permission-denied`.
  const ReportedContent.directMessage({
    required String conversationId,
    required String messageId,
  }) : this._(
         type: ReportedContentType.directMessage,
         conversationId: conversationId,
         messageId: messageId,
       );

  const ReportedContent.voiceMoment({
    required String momentId,
    String? reportReceipt,
  }) : this._(
         type: ReportedContentType.voiceMoment,
         momentId: momentId,
         reportReceipt: reportReceipt,
       );

  const ReportedContent.voiceMomentComment({
    required String momentId,
    required String commentId,
    String? reportReceipt,
  }) : this._(
         type: ReportedContentType.voiceMomentComment,
         momentId: momentId,
         commentId: commentId,
         reportReceipt: reportReceipt,
       );

  final ReportedContentType type;
  final String? conversationId;
  final String? messageId;
  final String? momentId;
  final String? commentId;
  final String? reportReceipt;

  /// The noun this content is called in user-facing copy. Kept next to
  /// the target so a new content type cannot ship with a sentence that
  /// says "message" about a Voice Moment.
  String get noun => switch (type) {
    ReportedContentType.directMessage => 'message',
    ReportedContentType.voiceMoment => 'Voice Moment',
    ReportedContentType.voiceMomentComment => 'comment',
  };

  /// The callable's payload minus `reason` and `requestId`.
  ///
  /// `requireExactInput` rejects unknown keys AND the server rejects a
  /// non-null id that does not belong to the target type, so only the
  /// ids this type actually uses are sent.
  Map<String, Object?> get callablePayload => <String, Object?>{
    'targetType': type.name,
    if (conversationId != null) 'conversationId': conversationId,
    if (messageId != null) 'messageId': messageId,
    if (momentId != null) 'momentId': momentId,
    if (commentId != null) 'commentId': commentId,
    if (reportReceipt != null) 'reportReceipt': reportReceipt,
  };

  /// Stable identity of the reported document, used to derive the
  /// idempotency key. Order and separators are fixed on purpose: change
  /// them and every previously reported target becomes reportable again.
  String get _fingerprint =>
      '${type.name}|${conversationId ?? ''}|${messageId ?? ''}'
      '|${momentId ?? ''}|${commentId ?? ''}';
}

/// Reporting a specific piece of content, through the callable that is
/// already deployed.
///
/// WHY A CALLABLE AND NOT A CLIENT WRITE. [ReportService] files reports
/// by writing `reports/{id}` directly, which works because firestore.rules
/// can verify a `globalMessage`/`user` target with `exists()`/`get()`.
/// It cannot do that for a direct message: proving the reporter is one of
/// the two participants, and that the message exists inside a
/// conversation the reporter can read, needs a server read of a document
/// the reporter may not read arbitrarily. `createContentReport` does
/// exactly that with the Admin SDK. So there are two report paths on
/// purpose, and this one owns everything message-shaped.
///
/// WHAT THE SERVER ENFORCES — none of it is client-side courtesy:
///  - **Identity**: `reporterId` is the callable's auth uid. A client
///    cannot name someone else as the reporter.
///  - **Target type**: an allowlist of exactly the three values in
///    [ReportedContentType]; anything else is `invalid-argument`.
///  - **Target shape**: the id fields must match the target type
///    exactly — a `voiceMoment` report carrying a `conversationId` is
///    refused as a conflict, so the collection cannot be used to attach
///    arbitrary paths to a complaint.
///  - **Target existence**: the reported document is read inside the
///    transaction and a missing one is `not-found`.
///  - **Participation**: for `directMessage`, the conversation must have
///    exactly two participants and include the reporter.
///  - **Rate limit**: 10 reports per rolling 10 minutes per account,
///    consumed transactionally.
///  - **Workflow**: the report is created with `status: 'open'` and
///    nothing else. Assignment, resolution and the acting moderator are
///    written later by `moderateReport`, so nobody can file a
///    pre-resolved report or attribute one to a moderator.
///  - **Visibility**: `reports` is `allow read: if isActiveStaff()`. The
///    reporter cannot read back what they filed — see
///    [ContentReportException] for why that matters here.
///
/// DEDUPLICATION. The callable has no notion of "this person already
/// reported this thing"; left alone it would happily create a second
/// report document for the same reporter and the same message, and a
/// moderator queue full of one person's repeat taps is a degraded queue.
/// So [requestIdFor] derives the idempotency key **from the target**
/// rather than from a random per-attempt value. The server's own
/// operation ledger then does the deduplication:
///
///  - same target, same reason -> the ledger replays and returns the
///    original `reportId`. No second document, no rate-limit spend.
///  - same target, different reason -> same ledger id, different input
///    hash, and the server answers `already-exists`, which is surfaced
///    as [ContentReportFailure.alreadyReported].
///
/// That is the same one-report-per-reporter-per-target policy
/// firestore.rules enforces for the other path through its deterministic
/// document id, reached by a different mechanism. Its cost is stated in
/// the report: a report cannot be re-filed after a moderator dismisses
/// it, because the ledger entry outlives the review.
class ContentReportService {
  ContentReportService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  /// Same region every other callable in this app uses. Resolved lazily
  /// and defensively: a widget test with no Firebase app must be able to
  /// build the surfaces that own a report action without exploding, the
  /// same way [MomentService] does it.
  FirebaseFunctions? get _functions =>
      _functionsOverride ??
      (() {
        try {
          return FirebaseFunctions.instanceFor(region: 'europe-west1');
        } on FirebaseException catch (error) {
          if (error.code == 'no-app') return null;
          rethrow;
        }
      })();

  /// The idempotency key for a target, matching the server's
  /// `^[A-Za-z0-9_-]{8,128}$`.
  ///
  /// Hashed rather than concatenated: a conversation id is
  /// `{uidA}_{uidB}`, and two long provider uids plus a message id would
  /// sit uncomfortably close to the 128-character ceiling. Exposed
  /// because it is part of the contract — the same reporter reporting the
  /// same target always sends the same key, and that is what makes the
  /// operation idempotent.
  static String requestIdFor(ReportedContent content) {
    final digest = sha256.convert(utf8.encode(content._fingerprint));
    return 'report-${digest.toString().substring(0, 40)}';
  }

  /// Files a report against [content].
  ///
  /// [reason] is sent as its enum `name`, not as a sentence. The callable
  /// takes `reason` as free text (1-500 characters) and validates only
  /// the length, so the client is the only thing standing between the
  /// moderator queue and 500 characters of unsortable prose. Sending the
  /// enum name keeps every report on both paths — this one and
  /// [ReportService]'s — in the same vocabulary, so
  /// `reportReasonLabel` renders them identically and a queue can be
  /// filtered by reason at all.
  ///
  /// Throws [ContentReportException] with a specific
  /// [ContentReportFailure] for every outcome a reporter can act on.
  Future<void> report({
    required ReportedContent content,
    required ReportReason reason,
  }) async {
    final functions = _functions;
    if (functions == null) {
      throw ContentReportException(
        ContentReportFailure.unavailable,
        noun: content.noun,
      );
    }

    try {
      await functions.httpsCallable('createContentReport').call<Object?>({
        ...content.callablePayload,
        'reason': reason.name,
        'requestId': requestIdFor(content),
      });
    } on FirebaseFunctionsException catch (error) {
      throw ContentReportException(
        _classify(error),
        noun: content.noun,
        cause: error,
      );
    } on FirebaseException catch (error) {
      throw ContentReportException(
        error.code == 'no-app'
            ? ContentReportFailure.unavailable
            : ContentReportFailure.unknown,
        noun: content.noun,
        cause: error,
      );
    }
  }

  /// Maps the callable's status codes onto outcomes a reporter can do
  /// something about.
  ///
  /// Every branch corresponds to a real `fail(...)` inside
  /// `createContentReport` or the guards it calls — this is a reading of
  /// the deployed function, not a guess at what a backend might return.
  static ContentReportFailure _classify(FirebaseFunctionsException error) {
    return switch (error.code) {
      // consumeRateLimit: 10 reports per 10 minutes.
      'resource-exhausted' => ContentReportFailure.tooManyReports,
      // assertLedgerReplay, when the same target is reported again under
      // a different reason. The request id is derived from the target,
      // so this code cannot mean anything else here.
      'already-exists' => ContentReportFailure.alreadyReported,
      // The reported document was read inside the transaction and was
      // gone, or the reporter has no profile document.
      'not-found' => ContentReportFailure.contentGone,
      // requireActor's email-verification gate, which this product's own
      // reporting policy says should not apply to a safety action. Until
      // that is changed server-side a reporter at least learns what to
      // do instead of seeing "something went wrong".
      'failed-precondition' => ContentReportFailure.emailUnverified,
      // Not a participant of the conversation, or a suspended/banned
      // account.
      'permission-denied' => ContentReportFailure.notAllowed,
      'unauthenticated' => ContentReportFailure.signedOut,
      // The callable is not deployed in this environment.
      'unimplemented' || 'not-implemented' => ContentReportFailure.unavailable,
      'unavailable' || 'deadline-exceeded' => ContentReportFailure.offline,
      _ => ContentReportFailure.unknown,
    };
  }
}

/// Why a report did not go through, in terms the reporter can act on.
///
/// A safety path that answers every failure with one sentence teaches
/// people that reporting does not work. Each of these has a different
/// next step, so each gets its own.
enum ContentReportFailure {
  /// This reporter has already reported this exact content.
  alreadyReported,

  /// The per-account report rate limit is spent.
  tooManyReports,

  /// The reported content no longer exists.
  contentGone,

  /// The reporter is not a participant, or the account is restricted.
  notAllowed,

  /// The server refuses unverified accounts. See the note in
  /// [ContentReportService._classify].
  emailUnverified,

  /// Not signed in.
  signedOut,

  /// Network or backend outage.
  offline,

  /// Reporting is not wired up in this environment.
  unavailable,

  /// Anything unclassified.
  unknown,
}

/// A failed report, carrying both the machine-readable [failure] and the
/// sentence a reporter should see.
///
/// EXTENDS [StateError] on purpose. `intentionalOrFriendly` in
/// `lib/core/helpers/error_messages.dart` is the app's one rule for error
/// copy: a `StateError` carries deliberate user-facing wording and is
/// shown as written, everything else is laundered through
/// `friendlyErrorMessage`. Fitting into that rule means every screen that
/// owns a report action already knows how to display this — no screen
/// re-invents the copy, and no screen can accidentally interpolate a
/// `[firebase_functions/...]` code into a snackbar.
///
/// The wording deliberately does NOT come from the server. The callable's
/// own strings are written for a developer ("A report exists without its
/// ledger", "Too many requests. Please try again later."), and `reports`
/// is staff-read-only so a client cannot inspect what happened either.
/// Both facts push the sentences here, next to the taxonomy they describe.
class ContentReportException extends StateError {
  ContentReportException(this.failure, {required String noun, this.cause})
    : super(_messageFor(failure, noun));

  final ContentReportFailure failure;

  /// The original exception, for logging. Never shown.
  final Object? cause;

  /// [noun] is the content's own word, so the same failure reads
  /// correctly whether it happened on a message, a Voice Moment or a
  /// comment.
  static String _messageFor(ContentReportFailure failure, String noun) =>
      switch (failure) {
        ContentReportFailure.alreadyReported =>
          'You already reported this $noun. Our team still has it.',
        ContentReportFailure.tooManyReports =>
          "You've sent a lot of reports just now. Please wait a few "
              'minutes and try again.',
        ContentReportFailure.contentGone =>
          'That $noun is no longer available, so there was nothing to '
              'report.',
        ContentReportFailure.notAllowed => "You can't report this $noun.",
        ContentReportFailure.emailUnverified =>
          'Verify your email address to report content.',
        ContentReportFailure.signedOut =>
          'Please sign in again to report this.',
        ContentReportFailure.offline => 'Check your connection and try again.',
        ContentReportFailure.unavailable =>
          'Reporting is unavailable right now. Please try again later.',
        ContentReportFailure.unknown =>
          'Your report could not be sent. Please try again.',
      };

  @override
  String toString() => message;
}

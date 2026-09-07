const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { createHash } = require("node:crypto");

const {
  requireAuthentication,
  requireVerifiedStaff,
} = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const { USER_ROLES } = require("../utils/roles");
const { isValidOpaqueUid } = require("../achievements/identity");
const { REEL_SCHEMA_VERSION } = require("../reels/contract");
const {
  MAX_REEL_AVAILABILITY_HOURS,
  MIN_REEL_AVAILABILITY_HOURS,
} = require("../reels/availability");
// Pure validators, no service closure: functions/reels/engagement.js requires
// only the shared guards and the Reel contract, so importing it here adds no
// cycle and no Firestore handle. It is the SAME validator the write path uses,
// which is the point — a moderator must never remove a document this file
// believes is a comment while the engagement contract does not.
const {
  MAX_REEL_COMMENT_LENGTH,
  storedEngagementCount,
  validateReelComment,
} = require("../reels/engagement");
const {
  digest,
  nonNegativeCount,
  timestampMillis,
} = require("../integrity/guards");
const {
  momentStoragePath,
  validateComment,
  validateLegacyMomentForPlayback,
  validateMoment,
  voiceReplyStoragePath,
} = require("../moments/integrity");
const {
  momentCapacityLedgerReference,
  touchMomentCapacityLedger,
} = require("../moments/capacity");

const REGION = "europe-west1";

// Report triage is the one place in Global Chat that is NOT a
// rules-gated client write, and deliberately so (ADR-013's second and
// fourth conditions both apply):
//
//  - it grants a capability rules cannot safely compute — enforcing a
//    state machine, detecting that ANOTHER moderator already claimed the
//    report, and making a retry idempotent all need to read-then-write
//    atomically against state the caller does not control;
//  - "remove the message AND resolve the report" is one decision that
//    must not half-apply, across two documents in different collections.
//
// It is also not latency-critical the way a chat send is: a moderator
// clicking Resolve can afford a round trip, and gets a real answer
// instead of a permission error.

const STATUS = Object.freeze({
  OPEN: "open",
  IN_REVIEW: "inReview",
  RESOLVED: "resolved",
  DISMISSED: "dismissed",
});

const ACTION = Object.freeze({
  CLAIM: "claim",
  RELEASE: "release",
  RESOLVE: "resolve",
  REMOVE_AND_RESOLVE: "removeAndResolve",
  DISMISS: "dismiss",
});

// Closed set, mirrored by ReportResolution in the Flutter client.
const RESOLUTIONS = new Set([
  "contentRemoved",
  "warningIssued",
  "noActionNeeded",
  "notAViolation",
  "duplicate",
  "insufficientEvidence",
]);

const TERMINAL = new Set([STATUS.RESOLVED, STATUS.DISMISSED]);

/// Legal transitions. A report with no `status` at all is treated as
/// open — see the note in the handler.
const TRANSITIONS = {
  [ACTION.CLAIM]: { from: [STATUS.OPEN], to: STATUS.IN_REVIEW },
  [ACTION.RELEASE]: { from: [STATUS.IN_REVIEW], to: STATUS.OPEN },
  [ACTION.RESOLVE]: {
    from: [STATUS.OPEN, STATUS.IN_REVIEW],
    to: STATUS.RESOLVED,
  },
  [ACTION.REMOVE_AND_RESOLVE]: {
    from: [STATUS.OPEN, STATUS.IN_REVIEW],
    to: STATUS.RESOLVED,
  },
  [ACTION.DISMISS]: {
    from: [STATUS.OPEN, STATUS.IN_REVIEW],
    to: STATUS.DISMISSED,
  },
};

const MAX_MODERATOR_NOTE = 500;
const SAFE_REPORT_ID = /^[A-Za-z0-9_-]{1,256}$/u;
const SAFE_REEL_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SAFE_REEL_COMMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SAFE_VOICE_CONTENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SAFE_REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/u;
const REPORT_STAFF_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.SUPER_MODERATOR,
  USER_ROLES.SUPER_ADMIN,
]);

/// Both halves of staff authority, checked server-side.
///
/// The custom claim is signed and cannot be forged; the `users/{uid}.role`
/// mirror is written by assignUserRole through the Admin SDK and is what
/// makes a REVOCATION effective immediately, rather than whenever the
/// removed moderator's ID token happens to expire. Exact equality plus the
/// full active-account check rejects crossed staff tiers, bans, disablement
/// and both soft-deletion representations.
async function requireActiveStaff(request, { privileged = false } = {}) {
  return requireVerifiedStaff(
    request,
    REPORT_STAFF_ROLES,
    "You do not have permission to moderate reports.",
    { privileged },
  );
}

function canonicalReelReference(report) {
  const reelId = report.targetId;
  if (
    typeof reelId !== "string" ||
    !SAFE_REEL_ID.test(reelId) ||
    !isValidOpaqueUid(report.reportedUserId) ||
    report.contextPath !== `reels/${reelId}`
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel reference is invalid.",
    );
  }
  return db.collection("reels").doc(reelId);
}

function hasExactKeys(value, expectedKeys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function canonicalPurgedReelEvidence(reel, report) {
  const evidence = reel?.moderationEvidence;
  const expiredAtMs = timestampMillis(reel?.expiredAt);
  const purgedAtMs = timestampMillis(reel?.purgedAt);
  const publishedAtMs = timestampMillis(evidence?.publishedAt);
  if (
    !hasExactKeys(reel, [
      "schemaVersion",
      "status",
      "authorId",
      "moderationStatusAtExpiry",
      "moderationEvidence",
      "expiredAt",
      "purgedAt",
      "updatedAt",
    ]) ||
    !hasExactKeys(evidence, [
      "evidenceVersion",
      "publishedAt",
      "expiredAt",
      "availabilityHours",
      "metadataFingerprint",
    ]) ||
    reel.schemaVersion !== REEL_SCHEMA_VERSION ||
    reel.status !== "expired" ||
    reel.authorId !== report.reportedUserId ||
    (reel.moderationStatusAtExpiry !== "visible" &&
      reel.moderationStatusAtExpiry !== "hidden") ||
    evidence.evidenceVersion !== 1 ||
    publishedAtMs === null ||
    expiredAtMs === null ||
    timestampMillis(evidence.expiredAt) !== expiredAtMs ||
    !Number.isSafeInteger(evidence.availabilityHours) ||
    evidence.availabilityHours < MIN_REEL_AVAILABILITY_HOURS ||
    evidence.availabilityHours > MAX_REEL_AVAILABILITY_HOURS ||
    typeof evidence.metadataFingerprint !== "string" ||
    !/^[a-f0-9]{64}$/u.test(evidence.metadataFingerprint) ||
    purgedAtMs === null ||
    publishedAtMs > expiredAtMs ||
    purgedAtMs < expiredAtMs ||
    timestampMillis(reel.updatedAt) !== purgedAtMs
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel evidence is invalid.",
    );
  }
  return { reel, isPurgedEvidence: true };
}

function canonicalModeratableReel(snapshot, report) {
  if (!snapshot.exists) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel no longer exists.",
    );
  }
  const reel = snapshot.data();
  if (
    reel?.status === "expired" &&
    Object.prototype.hasOwnProperty.call(reel, "purgedAt")
  ) {
    return canonicalPurgedReelEvidence(reel, report);
  }
  if (
    reel.schemaVersion !== REEL_SCHEMA_VERSION ||
    (reel.status !== "published" && reel.status !== "expired") ||
    reel.authorId !== report.reportedUserId ||
    (reel.moderationStatus !== "visible" &&
      reel.moderationStatus !== "hidden")
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel is not canonical moderatable evidence.",
    );
  }
  return { reel, isPurgedEvidence: false };
}

// A Reel comment report is SELF-CONTAINED, with no legacy shape to tolerate:
// `createReelCommentReport` is the only writer, the client create rule in
// firestore.rules cannot produce this targetType at all, and nothing existed
// before it. So every field is required, and a report that does not carry the
// full target identity is refused rather than partially trusted.
//
// The text snapshot is validated here for the same reason it is stored: a
// `reels/{id}/comments/{id}` document is `allow read, write: if false` for
// every client INCLUDING staff, so the snapshot is the moderator's only view
// of the reported words and the only evidence that survives the removal. A
// report missing it is not something a moderator can act on honestly.
function canonicalReelCommentReportTarget(report) {
  const reelId = report.reelId;
  const commentId = report.commentId;
  if (
    report.schemaVersion !== 2 ||
    !isValidOpaqueUid(report.reporterId) ||
    timestampMillis(report.createdAt) === null ||
    typeof report.reason !== "string" ||
    report.reason.length === 0 ||
    report.reason.length > 500 ||
    typeof report.note !== "string" ||
    report.note.length > 300 ||
    typeof reelId !== "string" ||
    !SAFE_REEL_ID.test(reelId) ||
    typeof commentId !== "string" ||
    !SAFE_REEL_COMMENT_ID.test(commentId) ||
    report.targetId !== commentId ||
    !isValidOpaqueUid(report.reportedUserId) ||
    !isValidOpaqueUid(report.reelAuthorId) ||
    report.contextPath !== `reels/${reelId}/comments/${commentId}` ||
    typeof report.targetTextSnapshot !== "string" ||
    report.targetTextSnapshot.length === 0 ||
    report.targetTextSnapshot.length > MAX_REEL_COMMENT_LENGTH
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel comment reference is invalid.",
    );
  }
  // `reelAuthorId` is deliberately shape-checked but NOT reconciled against
  // the live Reel root. It exists so a moderator can see whose Reel a
  // reported comment sat under; it carries no authority, and making it a
  // precondition would let an unrelated root inconsistency strand a report
  // that is otherwise fully actionable.
  return { reelId, commentId, reportedUserId: report.reportedUserId };
}

function canonicalVoiceReportTarget(report) {
  const isMoment = report.targetType === "voiceMoment";
  const isComment = report.targetType === "voiceMomentComment";
  const unusedPathIds = [
    "channelId",
    "clubId",
    "conversationId",
    "messageId",
    "roomId",
  ];
  const momentId = report.momentId;
  const commentId = isComment ? report.commentId : null;
  const expectedTargetId = isComment ? commentId : momentId;
  const expectedContextPath = isComment
    ? `voiceMoments/${momentId}/comments/${commentId}`
    : `voiceMoments/${momentId}`;
  const legacyTargetSnapshot =
    (report.targetId === undefined || report.targetId === null) &&
    (report.reportedUserId === undefined || report.reportedUserId === null) &&
    (report.contextPath === undefined || report.contextPath === null);
  const selfContainedTargetSnapshot =
    report.targetId === expectedTargetId &&
    isValidOpaqueUid(report.reportedUserId) &&
    report.contextPath === expectedContextPath;
  if (
    report.schemaVersion !== 2 ||
    !isValidOpaqueUid(report.reporterId) ||
    timestampMillis(report.createdAt) === null ||
    timestampMillis(report.updatedAt) === null ||
    typeof report.reason !== "string" ||
    report.reason.length === 0 ||
    report.reason.length > 500 ||
    typeof report.note !== "string" ||
    report.note.length > 300 ||
    (!isMoment && !isComment) ||
    typeof momentId !== "string" ||
    !SAFE_VOICE_CONTENT_ID.test(momentId) ||
    (isMoment && report.commentId !== null) ||
    (isComment &&
      (typeof commentId !== "string" ||
        !SAFE_VOICE_CONTENT_ID.test(commentId))) ||
    unusedPathIds.some((field) => report[field] !== null) ||
    (!legacyTargetSnapshot && !selfContainedTargetSnapshot)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Voice Moment reference is invalid.",
    );
  }
  return {
    momentId,
    commentId,
    reportedUserId: selfContainedTargetSnapshot
      ? report.reportedUserId
      : null,
  };
}

// A server-created report proves the target existed when the report was
// filed. If its root has since disappeared, or is in the canonical one-way
// deletion state, another report/author deletion already won the race. That
// is a successful moderation convergence, not a reason to strand the report
// open forever.
function voiceMomentAlreadyRemoved(snapshot, momentId) {
  if (!snapshot.exists) return true;
  const data = snapshot.data() ?? {};
  return (
    data.status === "deleting" &&
    data.isDeleted === true &&
    data.isPublished === false &&
    isValidOpaqueUid(data.authorId) &&
    data.storagePath === momentStoragePath(data.authorId, momentId)
  );
}

function canonicalModeratableVoiceMoment(snapshot, momentId) {
  if (snapshot.exists && snapshot.data()?.schemaVersion !== 2) {
    const legacy = snapshot.data() ?? {};
    if (legacy.status === "expired" && legacy.isPublished === false) {
      // The expiry sweep changes only lifecycle fields. Reconstruct the
      // preceding published state solely for the legacy integrity validator,
      // then return the untouched evidence. This keeps old Build 19 reports
      // removable after expiry without accepting drafts or arbitrary roots.
      validateLegacyMomentForPlayback(
        {
          exists: true,
          id: snapshot.id,
          data: () => ({
            ...legacy,
            isPublished: true,
            status: "published",
          }),
        },
        momentId,
        0,
      );
      return legacy;
    }
    // Existing reports remain actionable even if their deadline passed
    // between report creation and staff review. The validator still proves
    // the full legacy publication/media identity; zero only disables the
    // current-time availability decision for this evidence-preserving path.
    return validateLegacyMomentForPlayback(snapshot, momentId, 0);
  }
  const moment = validateMoment(snapshot, momentId, { allowExpired: true });
  const published =
    moment.status === "published" && moment.isPublished === true;
  const expired = moment.status === "expired" && moment.isPublished === false;
  if (!published && !expired) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Voice Moment is not moderatable content.",
    );
  }
  return moment;
}

function moderationAuditId(reportId, requestId) {
  const digest = createHash("sha256")
    .update(`${reportId}\0${requestId}`, "utf8")
    .digest("hex");
  return `report_${digest}`;
}

const moderateReport = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await requireActiveStaff(request, { privileged: true });

    // Document and idempotency identities are authority-bearing input. Never
    // trim or truncate them: doing so can alias two different caller values to
    // the same report/audit document before the closed grammar is checked.
    const reportId = request.data?.reportId;
    const requestId = request.data?.requestId;
    if (typeof reportId !== "string" || !SAFE_REPORT_ID.test(reportId)) {
      throw new HttpsError("invalid-argument", "A valid report id is required.");
    }
    if (typeof requestId !== "string" || !SAFE_REQUEST_ID.test(requestId)) {
      throw new HttpsError(
        "invalid-argument",
        "A valid requestId is required.",
      );
    }

    const action = normalizeText(request.data?.action, 32);
    // Client-generated per user action. A retry reuses it, which is what
    // makes this endpoint safely repeatable — see the short-circuit
    // inside the transaction.
    const resolution = normalizeText(request.data?.resolution, 64);
    const moderatorNote = normalizeText(
      request.data?.moderatorNote,
      MAX_MODERATOR_NOTE,
    );

    if (!TRANSITIONS[action]) {
      throw new HttpsError("invalid-argument", "Unknown moderation action.");
    }

    const needsResolution =
      action === ACTION.RESOLVE ||
      action === ACTION.REMOVE_AND_RESOLVE ||
      action === ACTION.DISMISS;

    if (needsResolution && !RESOLUTIONS.has(resolution)) {
      throw new HttpsError(
        "invalid-argument",
        "A valid resolution reason is required to close a report.",
      );
    }

    const reportReference = db.collection("reports").doc(reportId);
    const auditReference = db
      .collection("adminAuditLogs")
      .doc(moderationAuditId(reportId, requestId));

    const outcome = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reportReference);
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "That report no longer exists.");
      }
      const report = snapshot.data();

      // Idempotency: the same requestId replayed returns the result of
      // the original call without touching anything.
      if (report.lastRequestId === requestId) {
        return {
          status: report.status,
          replayed: true,
          contentRemoved: report.contentRemoved === true,
        };
      }

      // A report written before `status` existed is Open. No migration
      // and no Console work: the absence of the field IS the open state.
      const current = report.status ?? STATUS.OPEN;
      const transition = TRANSITIONS[action];

      if (TERMINAL.has(current)) {
        throw new HttpsError(
          "failed-precondition",
          `This report was already ${current}.`,
        );
      }
      if (!transition.from.includes(current)) {
        throw new HttpsError(
          "failed-precondition",
          `A report that is ${current} cannot be ${action}ed.`,
        );
      }

      // Somebody else is actively working this one. Claiming, releasing
      // or closing it out from under them is a conflict, not a race to
      // be won silently.
      const assignee = report.assignedTo ?? null;
      if (
        current === STATUS.IN_REVIEW &&
        assignee &&
        assignee !== caller.uid
      ) {
        throw new HttpsError(
          "aborted",
          "Another moderator is reviewing this report.",
        );
      }

      let contentRemoved = false;
      // "The content is gone" and "I am the one who removed it" are DIFFERENT
      // FACTS, and the audit entry has only ever recorded the first.
      //
      // That gap matters most on exactly this target type. A Reel's author
      // can now remove any comment on their own Reel, so "the author deleted
      // the reported comment before a moderator reached it" is a real and
      // repeatable event — and it is the pattern Trust and Safety most needs
      // to be able to count. With only `contentRemoved`, the trail reads
      // identically whether the moderator acted or was beaten to it.
      //
      // Null means "not applicable / not computed", which is every branch but
      // the Reel comment one today. Extending it to the Voice Moment branch,
      // which converges the same way, is a follow-up rather than a silent
      // change to a deployed audit shape.
      let contentAlreadyRemoved = null;
      if (action === ACTION.REMOVE_AND_RESOLVE) {
        if (report.targetType === "globalMessage") {
          const messageReference = db
            .collection("globalChat")
            .doc("main")
            .collection("messages")
            .doc(String(report.targetId));
          const message = await transaction.get(messageReference);

          if (!message.exists) {
            throw new HttpsError(
              "failed-precondition",
              "The reported message no longer exists.",
            );
          }
          // Already gone: resolving is still correct, removing again is
          // not, and re-writing it would fire a second moderation audit.
          if (message.data().isDeleted !== true) {
            transaction.update(messageReference, {
              isDeleted: true,
              deletedBy: caller.uid,
              deletedAt: FieldValue.serverTimestamp(),
              content: "",
            });
            contentRemoved = true;
          }
        } else if (report.targetType === "reel") {
          const reelReference = canonicalReelReference(report);
          const reelSnapshot = await transaction.get(reelReference);
          const target = canonicalModeratableReel(reelSnapshot, report);
          const reel = target.reel;

          // Media descriptors and bytes remain intact for evidence and a
          // future reviewed appeal. Reads fail closed because every Reel
          // playback/feed path requires moderationStatus == "visible".
          // A purged expiry tombstone contains no public content to hide and
          // remains byte-stable as immutable moderation evidence.
          if (
            !target.isPurgedEvidence &&
            reel.moderationStatus !== "hidden"
          ) {
            transaction.update(reelReference, {
              moderationStatus: "hidden",
              updatedAt: FieldValue.serverTimestamp(),
            });
            contentRemoved = true;
          }
        } else if (report.targetType === "reelComment") {
          const target = canonicalReelCommentReportTarget(report);
          const reelReference = db.collection("reels").doc(target.reelId);
          const commentReference = reelReference
            .collection("comments")
            .doc(target.commentId);
          // Both reads before any write: the counter decision depends on the
          // root, and the root is only written when the comment is really
          // there to be removed.
          const reelSnapshot = await transaction.get(reelReference);
          const commentSnapshot = await transaction.get(commentReference);
          const now = FieldValue.serverTimestamp();

          if (!commentSnapshot.exists) {
            // The report proves the comment existed when it was filed. Its
            // absence now means the Reel's author removed it, the comment's
            // own author deleted it, the deletion/expiry purge swept it, or
            // another report won the race. Every one of those is a successful
            // convergence on "the words are gone", not a reason to strand a
            // safety report open forever. The audit entry says which of the
            // two happened, so a moderator's record never claims a removal
            // somebody else performed.
            contentRemoved = true;
            contentAlreadyRemoved = true;
          } else {
            const comment = validateReelComment(
              commentSnapshot,
              target.reelId,
            );
            if (comment.authorId !== target.reportedUserId) {
              throw new HttpsError(
                "failed-precondition",
                "The reported Reel comment author is inconsistent.",
              );
            }
            const reel = reelSnapshot.exists
              ? (reelSnapshot.data() ?? {})
              : null;
            const rootIsTombstone =
              reel !== null &&
              (reel.status === "deleted" ||
                (reel.status === "expired" &&
                  Object.prototype.hasOwnProperty.call(reel, "purgedAt")));
            if (reel === null || rootIsTombstone) {
              // A deletion or purged-expiry tombstone carries an exact key
              // set with NO commentCount, and the engagement purge worker is
              // already draining this thread. Removing the document is still
              // right — the reported words should not wait on a worker — but
              // writing a counter onto a tombstone would corrupt it, so the
              // root is left untouched.
              transaction.delete(commentReference);
              contentRemoved = true;
              contentAlreadyRemoved = false;
            } else {
              // An absent counter is exactly zero (the additive engagement
              // schema), and a Reel that holds a comment while claiming zero
              // is corruption. Fail closed rather than write a negative
              // count: this is the same refusal the Voice Moment comment
              // path makes.
              const commentCount = storedEngagementCount(
                reel.commentCount,
                "Reel commentCount",
              );
              if (commentCount === 0) {
                throw new HttpsError(
                  "failed-precondition",
                  "The Reel comment count is inconsistent.",
                );
              }
              transaction.delete(commentReference);
              transaction.update(reelReference, {
                commentCount: commentCount - 1,
                updatedAt: now,
              });
              contentRemoved = true;
              contentAlreadyRemoved = false;
            }
          }
        } else if (
          report.targetType === "voiceMoment" ||
          report.targetType === "voiceMomentComment"
        ) {
          const target = canonicalVoiceReportTarget(report);
          const momentReference = db
            .collection("voiceMoments")
            .doc(target.momentId);
          const momentSnapshot = await transaction.get(momentReference);
          const now = FieldValue.serverTimestamp();

          if (voiceMomentAlreadyRemoved(momentSnapshot, target.momentId)) {
            if (
              momentSnapshot.exists &&
              target.commentId === null &&
              target.reportedUserId !== null &&
              target.reportedUserId !== momentSnapshot.data().authorId
            ) {
              throw new HttpsError(
                "failed-precondition",
                "The reported Voice Moment author is inconsistent.",
              );
            }
            contentRemoved = true;
          } else {
            const moment = canonicalModeratableVoiceMoment(
              momentSnapshot,
              target.momentId,
            );

            if (
              target.commentId === null &&
              target.reportedUserId !== null &&
              target.reportedUserId !== moment.authorId
            ) {
              throw new HttpsError(
                "failed-precondition",
                "The reported Voice Moment author is inconsistent.",
              );
            }

            if (target.commentId === null) {
              const capacityReference = momentCapacityLedgerReference(
                db,
                moment.authorId,
              );
              const capacity = await transaction.get(capacityReference);
              touchMomentCapacityLedger(
                transaction,
                capacityReference,
                capacity,
                moment.authorId,
                now,
              );
              transaction.update(momentReference, {
                isDeleted: true,
                isPublished: false,
                status: "deleting",
                updatedAt: now,
              });
              const outboxId = digest("moment-cleanup", target.momentId);
              transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
                schemaVersion: 1,
                kind: "voiceMoment",
                rootPath: `voiceMoments/${target.momentId}`,
                objectPaths: [
                  momentStoragePath(moment.authorId, target.momentId),
                ],
                status: "pending",
                attemptCount: 0,
                requestedBy: moment.authorId,
                requestedReason: "staffModeration",
                createdAt: now,
                updatedAt: now,
              });
              contentRemoved = true;
            } else {
              const commentReference = momentReference
                .collection("comments")
                .doc(target.commentId);
              const commentSnapshot = await transaction.get(commentReference);

              if (!commentSnapshot.exists) {
                contentRemoved = true;
              } else {
                const comment = validateComment(
                  commentSnapshot,
                  target.momentId,
                );
                if (
                  target.reportedUserId !== null &&
                  target.reportedUserId !== comment.authorId
                ) {
                  throw new HttpsError(
                    "failed-precondition",
                    "The reported Voice Moment comment author is inconsistent.",
                  );
                }
                const commentCount = nonNegativeCount(
                  moment.commentCount,
                  "Voice Moment commentCount",
                );
                if (commentCount === 0) {
                  throw new HttpsError(
                    "failed-precondition",
                    "The Voice Moment comment count is inconsistent.",
                  );
                }
                transaction.delete(commentReference);
                transaction.update(momentReference, {
                  commentCount: commentCount - 1,
                  updatedAt: now,
                });
                if (comment.type === "voice") {
                  const outboxId = digest(
                    "comment-cleanup",
                    target.momentId,
                    target.commentId,
                  );
                  transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
                    schemaVersion: 1,
                    kind: "voiceMomentComment",
                    rootPath:
                      `voiceMoments/${target.momentId}/comments/${target.commentId}`,
                    objectPaths: [
                      voiceReplyStoragePath(
                        comment.authorId,
                        target.momentId,
                        target.commentId,
                      ),
                    ],
                    status: "pending",
                    attemptCount: 0,
                    requestedBy: comment.authorId,
                    requestedReason: "staffModeration",
                    createdAt: now,
                    updatedAt: now,
                  });
                }
                contentRemoved = true;
              }
            }
          }
        } else {
          throw new HttpsError(
            "failed-precondition",
            "Only supported messages, Reels, Reel comments, or Voice Moments can be removed this way.",
          );
        }
      }

      // Reporter evidence — reporterId, targetType, targetId,
      // reportedUserId, contextPath, reason, note, createdAt — is never
      // in this update. Only workflow fields move.
      const workflow = {
        status: transition.to,
        lastRequestId: requestId,
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (action === ACTION.CLAIM) {
        workflow.assignedTo = caller.uid;
        workflow.assignedAt = FieldValue.serverTimestamp();
      } else if (action === ACTION.RELEASE) {
        workflow.assignedTo = null;
        workflow.assignedAt = null;
      } else {
        workflow.resolution = resolution;
        workflow.resolutionNote = moderatorNote || null;
        workflow.resolvedBy = caller.uid;
        workflow.resolvedAt = FieldValue.serverTimestamp();
        workflow.contentRemoved =
          contentRemoved || report.contentRemoved === true;
        // Closing a report you never claimed still attributes it to you.
        workflow.assignedTo = assignee ?? caller.uid;
      }

      transaction.set(reportReference, workflow, { merge: true });

      // The state transition and its immutable audit evidence are one
      // transaction. A lost response can therefore never leave a resolved
      // report without a trail, and replaying the same requestId observes the
      // already-committed pair instead of creating another entry.
      transaction.create(auditReference, {
        actorId: caller.uid,
        actorEmail: caller.token?.email ?? caller.email ?? null,
        actorRole: caller.role,
        action: `report_${action}`,
        targetType: "report",
        targetId: reportId,
        targetLabel: null,
        details: {
          previousStatus: current,
          newStatus: transition.to,
          resolution: needsResolution ? resolution : null,
          note: moderatorNote || null,
          contentRemoved,
          // True when this action resolved a report whose target somebody
          // else had already removed, false when this moderator's own
          // transaction removed it, null where the distinction was not
          // computed. See the declaration for why the two are separated.
          contentAlreadyRemoved,
          requestId,
        },
        createdAt: FieldValue.serverTimestamp(),
      });

      return {
        status: transition.to,
        previous: current,
        replayed: false,
        contentRemoved,
      };
    });

    return {
      success: true,
      reportId,
      status: outcome.status,
      contentRemoved: outcome.contentRemoved,
      replayed: outcome.replayed,
    };
  },
);

module.exports = {
  moderateReport,
  requireActiveStaff,
  STATUS,
  ACTION,
  RESOLUTIONS,
  MAX_MODERATOR_NOTE,
  SAFE_REPORT_ID,
  SAFE_REQUEST_ID,
  moderationAuditId,
};

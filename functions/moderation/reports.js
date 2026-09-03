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

function canonicalPublishedReel(snapshot, report) {
  if (!snapshot.exists) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel no longer exists.",
    );
  }
  const reel = snapshot.data();
  if (
    reel.schemaVersion !== REEL_SCHEMA_VERSION ||
    reel.status !== "published" ||
    reel.authorId !== report.reportedUserId ||
    (reel.moderationStatus !== "visible" &&
      reel.moderationStatus !== "hidden")
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The reported Reel is not a canonical published Reel.",
    );
  }
  return reel;
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
        return { status: report.status, replayed: true, contentRemoved: false };
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
          const reel = canonicalPublishedReel(reelSnapshot, report);

          // Media descriptors and bytes remain intact for evidence and a
          // future reviewed appeal. Reads fail closed because every Reel
          // playback/feed path requires moderationStatus == "visible".
          if (reel.moderationStatus !== "hidden") {
            transaction.update(reelReference, {
              moderationStatus: "hidden",
              updatedAt: FieldValue.serverTimestamp(),
            });
            contentRemoved = true;
          }
        } else {
          throw new HttpsError(
            "failed-precondition",
            "Only a Global Chat message or Reel can be removed this way.",
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

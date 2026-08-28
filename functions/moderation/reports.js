const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const {
  requireAuthentication,
  requireVerifiedStaff,
} = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const { writeAuditLog } = require("../utils/audit");
const { USER_ROLES } = require("../utils/roles");

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
async function requireActiveStaff(request) {
  return requireVerifiedStaff(
    request,
    REPORT_STAFF_ROLES,
    "You do not have permission to moderate reports.",
  );
}

const moderateReport = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await requireActiveStaff(request);

    const reportId = normalizeText(request.data?.reportId, 256);
    const action = normalizeText(request.data?.action, 32);
    // Client-generated per user action. A retry reuses it, which is what
    // makes this endpoint safely repeatable — see the short-circuit
    // inside the transaction.
    const requestId = normalizeText(request.data?.requestId, 64);
    const resolution = normalizeText(request.data?.resolution, 64);
    const moderatorNote = normalizeText(
      request.data?.moderatorNote,
      MAX_MODERATOR_NOTE,
    );

    if (!reportId || !/^[A-Za-z0-9_-]+$/.test(reportId)) {
      throw new HttpsError("invalid-argument", "A valid report id is required.");
    }
    if (!TRANSITIONS[action]) {
      throw new HttpsError("invalid-argument", "Unknown moderation action.");
    }
    if (!requestId || requestId.length < 8) {
      throw new HttpsError(
        "invalid-argument",
        "A requestId of at least 8 characters is required.",
      );
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
        if (report.targetType !== "globalMessage") {
          throw new HttpsError(
            "failed-precondition",
            "Only a Global Chat message can be removed this way.",
          );
        }
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

      return {
        status: transition.to,
        previous: current,
        replayed: false,
        contentRemoved,
      };
    });

    if (!outcome.replayed) {
      // Deterministic on the idempotency key, so a retry that reaches
      // this line after a network failure overwrites its own entry
      // rather than appending a second one.
      await writeAuditLog({
        entryId: `report_${reportId}_${requestId}`,
        caller: { uid: caller.uid, role: caller.role },
        action: `report_${action}`,
        targetType: "report",
        targetId: reportId,
        targetLabel: null,
        details: {
          previousStatus: outcome.previous,
          newStatus: outcome.status,
          resolution: needsResolution ? resolution : null,
          // The note as recorded at the time of the action. The report
          // document holds only the latest one; a trail needs the value
          // that went with this specific transition.
          note: moderatorNote || null,
          contentRemoved: outcome.contentRemoved,
          requestId,
        },
      });
    }

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
};

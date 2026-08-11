const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { db, normalizeText, positiveInteger } = require("../utils/firestore");
const { requireActiveStaff } = require("./reports");

const REGION = "europe-west1";

// WHY THIS EXISTS INSTEAD OF REUSING listAdminAuditLogs.
//
// functions/admin/audit.js's listAdminAuditLogs is a whole-collection
// browser: it is gated on requireAdminCenterAccess (which already
// includes moderators), lists `adminAuditLogs` unfiltered by default,
// supports free-text search across every field, and returns
// `actor.email` and `target.email`. Pointing the Moderation Center at
// it would let a moderator reviewing one report page through every ban,
// role assignment and club deletion in the product, with emails
// attached. Widening or re-gating it is out of scope and would change
// an existing admin surface.
//
// This callable answers exactly one question: "what has happened to
// THIS report, and to the message it is about?" The target ids are
// derived from the report document server-side — the client sends a
// report id and nothing else that selects data — so there is no
// parameter that can be pointed at another report or an unrelated
// admin action.

/// Fields returned to staff. Anything not listed here never leaves the
/// server: no actor email, no target email, no auth-provider data, no
/// raw document, no unrelated details keys.
const MAX_LIMIT = 25;
const DEFAULT_LIMIT = 10;

/// The report-workflow actions this trail recognises.
const REPORT_ACTIONS = new Set([
  "report_claim",
  "report_release",
  "report_resolve",
  "report_removeAndResolve",
  "report_dismiss",
]);

function isoOf(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

/// Bounded, so a long removed message or moderator note cannot turn the
/// audit response into a bulk content export.
function bounded(value, max = 500) {
  if (typeof value !== "string") return null;
  return value.length > max ? `${value.slice(0, max)}…` : value;
}

/// Report-workflow event: how the REPORT moved.
function mapReportEvent(document, displayNames) {
  const data = document.data() ?? {};
  const details = data.details ?? {};
  return {
    id: document.id,
    kind: "reportWorkflow",
    action: data.action ?? "unknown",
    actorId: data.actorId ?? null,
    actorName: displayNames.get(data.actorId) ?? null,
    actorRole: data.actorRole ?? null,
    previousStatus: details.previousStatus ?? null,
    newStatus: details.newStatus ?? null,
    resolution: details.resolution ?? null,
    note: bounded(details.note),
    contentRemoved: details.contentRemoved === true,
    removedContent: null,
    createdAt: isoOf(data.createdAt),
  };
}

/// Content-moderation event: what happened to the MESSAGE. Deliberately
/// a separate kind — "the report was resolved" and "the message was
/// removed" are different facts, and collapsing them into one row would
/// imply every resolution removed content.
function mapMessageEvent(document, displayNames) {
  const data = document.data() ?? {};
  const details = data.details ?? {};
  return {
    id: document.id,
    kind: "contentModeration",
    action: data.action ?? "unknown",
    actorId: data.actorId ?? null,
    actorName: displayNames.get(data.actorId) ?? null,
    actorRole: data.actorRole ?? null,
    previousStatus: null,
    newStatus: null,
    resolution: null,
    note: null,
    contentRemoved: true,
    // The text as it was before removal — the evidence a reviewer needs,
    // and the reason soft deletion keeps the document at all.
    removedContent: bounded(details.removedContent),
    createdAt: isoOf(data.createdAt),
  };
}

/// Public display names for the acting moderators only. Never emails,
/// never the full profile.
async function resolveDisplayNames(uids) {
  const unique = [...new Set(uids.filter(Boolean))].slice(0, 20);
  const names = new Map();
  if (unique.length === 0) return names;

  const snapshots = await db.getAll(
    ...unique.map((uid) => db.collection("users").doc(uid)),
  );
  for (const snapshot of snapshots) {
    const displayName = snapshot.data()?.displayName;
    if (typeof displayName === "string" && displayName.trim()) {
      names.set(snapshot.id, displayName.trim());
    }
  }
  return names;
}

const listReportAuditTrail = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    // Same three-part staff test the queue rules and moderateReport use:
    // signed claim, server-written users/{uid}.role, not banned.
    await requireActiveStaff(request);

    const reportId = normalizeText(request.data?.reportId, 256);
    if (!reportId || !/^[A-Za-z0-9_-]+$/.test(reportId)) {
      throw new HttpsError("invalid-argument", "A valid report id is required.");
    }

    const limit = positiveInteger(request.data?.limit, DEFAULT_LIMIT, MAX_LIMIT);

    // Cursor is the createdAt of the last event already shown. Strictly
    // BEFORE, so a page boundary can neither repeat nor skip on a
    // re-fetch, and both sub-queries advance together.
    const rawCursor = normalizeText(request.data?.cursor, 40);
    let cursor = null;
    if (rawCursor) {
      const parsed = new Date(rawCursor);
      if (Number.isNaN(parsed.getTime())) {
        throw new HttpsError("invalid-argument", "Malformed pagination cursor.");
      }
      cursor = parsed;
    }

    // The report is the ONLY thing the caller names, and the target is
    // read from it. A caller cannot ask for an arbitrary target id.
    const reportSnapshot = await db.collection("reports").doc(reportId).get();
    if (!reportSnapshot.exists) {
      throw new HttpsError("not-found", "That report no longer exists.");
    }
    const report = reportSnapshot.data() ?? {};

    const audits = db.collection("adminAuditLogs");

    function scopedQuery(targetType, targetId) {
      let query = audits
        .where("targetType", "==", targetType)
        .where("targetId", "==", targetId)
        .orderBy("createdAt", "desc");
      if (cursor) query = query.where("createdAt", "<", cursor);
      return query.limit(limit + 1).get();
    }

    const requests = [scopedQuery("report", reportId)];

    // The associated message's own moderation history, only when this
    // report is actually about that message.
    const targetsMessage =
      report.targetType === "globalMessage" &&
      typeof report.targetId === "string" &&
      report.targetId.length > 0;
    if (targetsMessage) {
      requests.push(scopedQuery("globalMessage", report.targetId));
    }

    const [reportAudits, messageAudits] = await Promise.all([
      requests[0],
      requests[1] ?? Promise.resolve({ docs: [] }),
    ]);

    const reportDocs = reportAudits.docs.filter((document) =>
      REPORT_ACTIONS.has(document.data()?.action),
    );
    const messageDocs = messageAudits.docs;

    const displayNames = await resolveDisplayNames([
      ...reportDocs.map((d) => d.data()?.actorId),
      ...messageDocs.map((d) => d.data()?.actorId),
    ]);

    const merged = [
      ...reportDocs.map((d) => mapReportEvent(d, displayNames)),
      ...messageDocs.map((d) => mapMessageEvent(d, displayNames)),
    ].sort((a, b) => {
      // Newest first, with the document id as a deterministic
      // tie-break so two events written in the same millisecond keep
      // one stable order across pages.
      const byTime = (b.createdAt ?? "").localeCompare(a.createdAt ?? "");
      return byTime !== 0 ? byTime : b.id.localeCompare(a.id);
    });

    const page = merged.slice(0, limit);
    const hasMore = merged.length > limit;

    return {
      reportId,
      events: page,
      hasMore,
      // What the client should send back to fetch the next page.
      nextCursor: hasMore ? page[page.length - 1].createdAt : null,
    };
  },
);

module.exports = { listReportAuditTrail, MAX_LIMIT, DEFAULT_LIMIT };

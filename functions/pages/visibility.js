// pageVisibility/v1: the ONE server-only document the feed and Find read to
// drop non-viewable Pages BEFORE querying (ADR-233 §1.6).
//
//   { schemaVersion: 1,
//     notViewable:   { <pageId>: "paused" | "suspended" | "hidden" },
//     readOnlySince: { <pageId>: <epoch ms> },
//     updatedAt }
//
// Every Page status transition (pause/resume, suspend/lift, lapse/restore,
// account deletion) writes it in the SAME transaction as pages/{pageId}, via
// applyPageVisibilityInTransaction. The entry is fully derived from the Page
// (pageVisibilityEntry), so a writer never "adds" or "removes" by hand and two
// writers cannot disagree. Only the one page's two map entries are touched
// (FieldPath updates), never the rest of the document.
//
// Size bound: 20 000 entries (about 800 KB). Past 15 000 the writer logs
// `pages visibility index near cap`, the ADR-233 trigger to move to a
// denormalised post flag. A readOnlySince older than 30 days counts as hidden
// at read time (lapse.js), so the sweep's lag never un-hides anything.

const { FieldPath, FieldValue } = require("firebase-admin/firestore");
const defaultLogger = require("firebase-functions/logger");

const { fail, timestampMillis } = require("../integrity/guards");

const PAGE_VISIBILITY_PATH = "pageVisibility/v1";
const PAGE_VISIBILITY_KEYS = Object.freeze([
  "notViewable",
  "readOnlySince",
  "schemaVersion",
  "updatedAt",
]);
const NOT_VIEWABLE_REASONS = Object.freeze(["paused", "suspended", "hidden"]);
const PAGE_VISIBILITY_WARN_ENTRIES = 15_000;
const PAGE_VISIBILITY_MAX_ENTRIES = 20_000;

function pageVisibilityReference(db) {
  return db.doc(PAGE_VISIBILITY_PATH);
}

/// The entry `page` must have. Precedence of the one notViewable reason:
/// suspended (a moderator's decision) > hidden (lapse) > paused (the owner).
/// A deleted Page (null) has no entry at all.
function pageVisibilityEntry(page) {
  if (!page) return { notViewable: null, readOnlySinceMs: null };
  const notViewable = page.suspended === true
    ? "suspended"
    : page.status === "hidden"
      ? "hidden"
      : page.ownerPaused === true
        ? "paused"
        : null;
  const readOnlySinceMs = page.status === "readOnly"
    ? timestampMillis(page.lapsedAt)
    : null;
  return { notViewable, readOnlySinceMs };
}

function plainMap(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value) &&
    typeof value.toMillis !== "function";
}

/**
 * The canonical visibility index. A missing document is empty. A document
 * with the wrong top-level shape is `data-loss` (readers must never treat a
 * broken index as "everything viewable"). Individual malformed entries are
 * read as `hidden` (fail closed) rather than dropped.
 */
function canonicalPageVisibility(snapshot) {
  if (!snapshot?.exists) {
    return Object.freeze({ notViewable: new Map(), readOnlySince: new Map(), exists: false });
  }
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  if (keys.length !== PAGE_VISIBILITY_KEYS.length ||
      keys.some((key, index) => key !== PAGE_VISIBILITY_KEYS[index]) ||
      data.schemaVersion !== 1 || !plainMap(data.notViewable) ||
      !plainMap(data.readOnlySince) || timestampMillis(data.updatedAt) === null) {
    fail("data-loss", "The Page visibility index is malformed.");
  }
  const notViewable = new Map();
  for (const [pageId, reason] of Object.entries(data.notViewable)) {
    notViewable.set(pageId, NOT_VIEWABLE_REASONS.includes(reason) ? reason : "hidden");
  }
  const readOnlySince = new Map();
  for (const [pageId, since] of Object.entries(data.readOnlySince)) {
    if (Number.isSafeInteger(since) && since >= 0) {
      readOnlySince.set(pageId, since);
    } else {
      notViewable.set(pageId, notViewable.get(pageId) ?? "hidden");
    }
  }
  return Object.freeze({ notViewable, readOnlySince, exists: true });
}

function entryCount(index) {
  return new Set([...index.notViewable.keys(), ...index.readOnlySince.keys()]).size;
}

/**
 * Writes pageId's derived entry into pageVisibility/v1 inside `transaction`.
 * `snapshot` is the transaction's read of the index (reads must precede all
 * writes). `page` is the Page AFTER this transaction's change, or null for a
 * deleted Page. Returns true when a write was queued.
 */
function applyPageVisibilityInTransaction(transaction, {
  db,
  snapshot,
  pageId,
  page,
  now,
  logger = defaultLogger,
  safetyAction = false,
}) {
  const reference = pageVisibilityReference(db);
  let index;
  try {
    index = canonicalPageVisibility(snapshot);
  } catch (error) {
    // A broken index must never block a SAFETY write (an owner pause, going
    // private): the Page document itself carries ownerPaused, and every
    // reader re-checks it per item. Everything else refuses (data-loss).
    if (!safetyAction) throw error;
    logger.error("pages visibility index malformed on a safety action", {});
    return false;
  }
  const desired = pageVisibilityEntry(page);
  const currentNotViewable = index.notViewable.get(pageId) ?? null;
  const currentReadOnly = index.readOnlySince.get(pageId) ?? null;
  const rawNotViewable = snapshot?.exists
    ? (snapshot.data()?.notViewable?.[pageId] ?? null)
    : null;
  if (currentNotViewable === desired.notViewable &&
      rawNotViewable === desired.notViewable &&
      currentReadOnly === desired.readOnlySinceMs) {
    return false;
  }

  const hadEntry = index.notViewable.has(pageId) || index.readOnlySince.has(pageId);
  const willHaveEntry = desired.notViewable !== null || desired.readOnlySinceMs !== null;
  const entries = entryCount(index) + (willHaveEntry && !hadEntry ? 1 : 0) -
    (!willHaveEntry && hadEntry ? 1 : 0);
  if (entries >= PAGE_VISIBILITY_MAX_ENTRIES) {
    // Never refused: an entry that HIDES a Page is a safety write. The alert
    // is the operator's signal that ADR-233's fallback is overdue.
    logger.error("pages visibility index at cap", { entries });
  } else if (entries > PAGE_VISIBILITY_WARN_ENTRIES) {
    logger.warn("pages visibility index near cap", { entries });
  }

  if (!snapshot?.exists) {
    transaction.set(reference, {
      schemaVersion: 1,
      notViewable: desired.notViewable === null ? {} : { [pageId]: desired.notViewable },
      readOnlySince: desired.readOnlySinceMs === null
        ? {}
        : { [pageId]: desired.readOnlySinceMs },
      updatedAt: now,
    });
    return true;
  }
  transaction.update(
    reference,
    new FieldPath("notViewable", pageId),
    desired.notViewable === null ? FieldValue.delete() : desired.notViewable,
    new FieldPath("readOnlySince", pageId),
    desired.readOnlySinceMs === null ? FieldValue.delete() : desired.readOnlySinceMs,
    "updatedAt",
    now,
  );
  return true;
}

module.exports = {
  NOT_VIEWABLE_REASONS,
  PAGE_VISIBILITY_KEYS,
  PAGE_VISIBILITY_MAX_ENTRIES,
  PAGE_VISIBILITY_PATH,
  PAGE_VISIBILITY_WARN_ENTRIES,
  applyPageVisibilityInTransaction,
  canonicalPageVisibility,
  pageVisibilityEntry,
  pageVisibilityReference,
};

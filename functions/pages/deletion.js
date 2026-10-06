// managePageDeletionV1 and the durable Page-deletion worker (ADR-236, which
// amends ADR-233: an owner can now delete a Page without deleting the
// account). One op callable, europe-west1, App Check in the project's rollout
// mode (enforceAppCheck:false, like every Pages callable).
//
//   op          kind     activation  rate                    gate  notes
//   status      read     NONE        pages.deletionStatus    no    the caller's own state only
//   request     safety   NONE        pages.deletionRequest   NO    pauses the Page in the same transaction,
//                                                                  writes the 30-day record; unverified,
//                                                                  muted and lapsed owners allowed
//   restore     safety   NONE        none for the cancel     NO    CANCELS a pending deletion, always: no
//                                                                  switch, no capability, no mute, no
//                                                                  verified e-mail, no budget. Then, as a
//                                                                  separate gated write (switch,
//                                                                  pages.deletionRestore, verified, active,
//                                                                  !muted, live Premium/VIP, the resume
//                                                                  rules), the Page is resumed when it was
//                                                                  running before; a refusal there leaves
//                                                                  an ordinary paused Page, never a record
//   purgeNow    safety   NONE        pages.deletionPurge     NO    only a PENDING deletion; irreversible:
//                                                                  needs a sign-in no older than 5 minutes
//                                                                  (utils/auth.js, as account deletion) and
//                                                                  the requestedAtMs of the request it
//                                                                  confirms
//   clearPosts  safety   NONE        pages.deletionClear     NO    deletes every post, keeps the Page
//                                                                  and its followers
//
// The undo is never harder than the deletion: every state in which the
// 30-day timer runs is a state in which `restore` (and managePageV1 resume,
// what builds 40/41 offer) removes the record. The gates only decide whether
// the Page also goes back on air.
//
// Every op answers the same exact shape, the caller's deletion state:
//
//   { schemaVersion: 1, pageId, pageExists,
//     deletion:      null | { state: "pending" | "purging", requestedAtMs, deleteAtMs },
//     postsClearing: null | { requestedAtMs },
//     recreateAllowedAtMs: null | <epoch ms>,
//     pagePaused: null | bool }          (null when there is no Page)
//
// Input is exactly {op}; purgeNow is exactly {op, requestedAtMs}.
//
// managePageV1 keeps its four ops and its exact 4-key result. Two of its
// paths read this module's records (lifecycle.js): `create` refuses during
// the 7-day cooldown and re-applies a remembered suspension, and `resume`
// cancels a PENDING deletion BEFORE any of its own gates, in its own
// transaction (an installed build 40/41 shows a Page that is pending deletion
// as "paused", and its "Resume" must mean "I want it back", whether or not
// the resume itself is then allowed); while a deletion is PURGING, update
// and resume answer `pageNotFound`.
//
// Server-only records (firestore.rules denies every client read and write):
//
//   pageDeletions/{pageId}      { schemaVersion, pageId, state, requestedAt,
//                                 deleteAt, pausedBefore, reminderAt|null,
//                                 dueAt, step, cursor|null, attempts,
//                                 updatedAt }
//     kept OUTSIDE the exact 26-key pages/{pageId} document, so builds 40/41
//     keep parsing their own Page. `pending` until deleteAt (request + 30
//     days) or purgeNow, then `purging`, which cannot be undone.
//   pagePostClearJobs/{pageId}  { schemaVersion, pageId, requestedAt,
//                                 cursor|null, attempts, nextAttemptAt,
//                                 updatedAt }
//     "delete all posts": only posts created at or before requestedAt.
//   pageMemory/{pageId}         { schemaVersion, pageId, deletedAt,
//                                 recreateAllowedAt, suspension|null,
//                                 expiresAt|null, updatedAt }
//     written in the SAME transaction that removes pages/{pageId}: the
//     7-day re-create cooldown and, when the Page was suspended, the
//     suspension (which otherwise lives only in the Page document, so delete
//     + re-create would erase it). Without a suspension the row expires with
//     the cooldown; with one it stays until the next create takes it over.
//     The staff arm (moderation.js) writes a suspension here too when its
//     decision finds the Page already deleted, and lifts a remembered one.
//
// The purge (pagesMaintenance slice `pageDeletion`, and one inline pass after
// purgeNow) reuses the account-deletion stages of account_deletion.js WITHOUT
// processComments (the owner's comments on other Pages belong to the
// account, which stays). Order is the safety argument:
//
//   0 posts      processPosts / retirePost {reason:"pageDeleted",
//                ownerDelete:true}: hard delete, or a <= 90-day tombstone
//                for reported, held and removed posts (the evidence pattern)
//   1 followers  removeFollowEdges(side:"followers", survivor:true), then
//                followerCount settled to 0. BEFORE the Page document goes:
//                every "is this account a Page?" check (the DM "People you
//                follow" exemption in messaging/direct_integrity.js, the
//                follower achievement, Creator audience, the LIVE fan-out)
//                reads pages/{uid} existence, so none of them can flip while
//                an edge remains
//   2 storage    sweepStorage: unheld media jobs and open uploads
//   3 records    removeRecords: the per-day posting budgets
//   4 page       removePage + pageMemory + this record, the carry-over job,
//                the upload lease and a leftover clear job, ONE transaction
//                that re-reads this record and writes only while it is
//                still `purging` (a duplicate run or a retry is a no-op)
//
// Every step is bounded, cursor-resumable and idempotent; a failure backs the
// record off (pageJobBackoffMs) and never stops the next record. Log lines
// carry counts and codes only, never a uid or pageId.

const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const defaultLogger = require("firebase-functions/logger");

const {
  assertNotRestricted,
  canonicalPublicProfile,
  consumeRateLimit,
  fail,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireObject,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const { requireRecentPrivilegedAuthentication } = require("../utils/auth");
const { likersAccountIsActive } = require("../utils/likers_access");
const { normalizeProfileVisibility } = require("../profile/profile_visibility");
const { pageNameViolation } = require("../profile/name_safety");
const {
  derivePagesCapability,
  pageAccessRequiredError,
  pagesCapabilityReferences,
} = require("./access");
const { pagesWriteAllowed, readPagesActivation } = require("./activation");
const {
  PAGE_ERRORS,
  canonicalPageOrNull,
  derivePageListed,
  pageDisplayNameMirror,
  pageMalformedReason,
} = require("./contract");
const { applyPagePauseInTransaction, pageForSafetyAction, pageReference } = require("./hooks");
const { restoredPageFields } = require("./lapse");
const { GENERATION_PATTERN, pageJobBackoffMs } = require("./media_contract");
const { isMissingObject } = require("./media_storage");
const { PAGE_LAPSE_NOTICE_TYPE, pageSystemNotice } = require("./report_contract");
const {
  applyPageVisibilityInTransaction,
  pageVisibilityReference,
} = require("./visibility");

const REGION = "europe-west1";
const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

const PAGE_DELETION_WINDOW_MS = 30 * DAY_MS;
const PAGE_DELETION_REMINDER_BEFORE_MS = 3 * DAY_MS;
const PAGE_RECREATE_COOLDOWN_MS = 7 * DAY_MS;
// How long a due deletion waits before it is looked at again while the
// deadline purge is held (the owner cannot use Pages: see deadlineHeld).
const PAGE_DELETION_HOLD_RETRY_MS = 6 * HOUR_MS;

const PAGE_DELETIONS = "pageDeletions";
const PAGE_POST_CLEAR_JOBS = "pagePostClearJobs";
const PAGE_MEMORY = "pageMemory";

const MANAGE_PAGE_DELETION_OPS = Object.freeze([
  "status", "request", "restore", "purgeNow", "clearPosts",
]);
const PAGE_DELETION_STATES = Object.freeze(["pending", "purging"]);
const PAGE_DELETION_STEPS = Object.freeze(["posts", "followers", "storage", "records", "page"]);
const PAGE_DELETION_REMINDER_PHASE = "deletionSoon";
// English and human-readable: builds 40/41 show an unknown lapse phase with
// this label (the pageLapse convention, report_contract.js).
const PAGE_DELETION_REMINDER_LABEL =
  "Your Page will be deleted in 3 days. Restore it in Page settings to keep it.";

// request, purgeNow and clearPosts are safety actions, so their budgets are
// generous: no owner reaches them by hand, a script does. Each is charged in
// its own transaction before the op, so a refused call still costs. The
// cancel half of `restore` charges nothing (it must never be refused); only
// the resume that may follow it is budgeted.
const PAGES_DELETION_RATE_LIMITS = Object.freeze({
  "pages.deletionStatus": Object.freeze({ maxEvents: 60, windowMs: MINUTE_MS }),
  "pages.deletionRestore": Object.freeze({ maxEvents: 10, windowMs: HOUR_MS }),
  "pages.deletionRequest": Object.freeze({ maxEvents: 20, windowMs: HOUR_MS }),
  "pages.deletionPurge": Object.freeze({ maxEvents: 10, windowMs: HOUR_MS }),
  "pages.deletionClear": Object.freeze({ maxEvents: 10, windowMs: HOUR_MS }),
});

const PAGES_DELETION_WORK_LIMITS = Object.freeze({
  // Records a maintenance run picks up, and bounded rounds on each.
  deletions: 5,
  deletionRounds: 6,
  // "Delete all posts": 10 posts a round (account_deletion.js limits.posts),
  // so one job clears up to 200 posts a run, stopping early when the part's
  // time budget is used.
  clearJobs: 5,
  clearRounds: 20,
  reminders: 20,
  memory: 50,
  // One follower page (account/stages.js DEFAULT_LIMITS.edgePage).
  edgePage: 25,
  // What a callable does itself right after its commit, so a small Page is
  // done before the owner looks again; the worker finishes larger ones.
  inlineClearRounds: 5,
  inlineDeletionRounds: 3,
  // The clear jobs and the purges each stop picking up further work once
  // THEIR part has run this long (the rest is due again in 10 minutes), so
  // a few very large Pages can never push pagesMaintenance (300 s) past the
  // slices that follow, and a purge can never starve a "delete all posts"
  // job, whose posts are still public while it waits.
  sweepBudgetMs: 45 * 1000,
});

const PAGE_DELETION_KEYS = Object.freeze([
  "attempts", "cursor", "deleteAt", "dueAt", "pageId", "pausedBefore",
  "reminderAt", "requestedAt", "schemaVersion", "state", "step", "updatedAt",
]);
const PAGE_POST_CLEAR_JOB_KEYS = Object.freeze([
  "attempts", "cursor", "nextAttemptAt", "pageId", "requestedAt",
  "schemaVersion", "updatedAt",
]);
const PAGE_MEMORY_KEYS = Object.freeze([
  "deletedAt", "expiresAt", "pageId", "recreateAllowedAt", "schemaVersion",
  "suspension", "updatedAt",
]);
const PAGE_MEMORY_SUSPENSION_KEYS = Object.freeze(["suspendedAt", "suspensionReason"]);
const PAGE_DELETION_STATE_KEYS = Object.freeze([
  "deletion", "pageExists", "pageId", "pagePaused", "postsClearing",
  "recreateAllowedAtMs", "schemaVersion",
]);
const SUSPENSION_REASON_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,63}$/u;

// The exact worker query shapes, each on a single-field (automatic) index.
// The emulator index test runs these same builders (ADR-007).
const PAGES_DELETION_WORK_QUERIES = Object.freeze({
  dueDeletions: (db, now) => db.collection(PAGE_DELETIONS)
    .where("dueAt", "<=", now)
    .orderBy("dueAt", "asc"),
  dueReminders: (db, now) => db.collection(PAGE_DELETIONS)
    .where("reminderAt", "<=", now)
    .orderBy("reminderAt", "asc"),
  dueClearJobs: (db, now) => db.collection(PAGE_POST_CLEAR_JOBS)
    .where("nextAttemptAt", "<=", now)
    .orderBy("nextAttemptAt", "asc"),
  expiredMemory: (db, now) => db.collection(PAGE_MEMORY)
    .where("expiresAt", "<=", now)
    .orderBy("expiresAt", "asc"),
});

// ------------------------------------------------------------------ errors

const PAGE_DELETION_ERRORS = Object.freeze({
  // A purge has started: nothing is left to restore.
  inProgress: () => new HttpsError("failed-precondition",
    "This Page is being deleted.", { reason: "pageDeletionInProgress" }),
  notRequested: () => new HttpsError("failed-precondition",
    "Page deletion was not requested.", { reason: "pageDeletionNotRequested" }),
  // "Delete now" confirms ONE request: the one the owner was looking at. A
  // delayed or repeated call that meets a newer request is refused.
  changed: () => new HttpsError("failed-precondition",
    "This deletion request has changed.", { reason: "pageDeletionChanged" }),
  recreateCooldown: (retryAtMs) => new HttpsError("failed-precondition",
    "A new Page can be created 7 days after the previous one was deleted.",
    { reason: "pageRecreateCooldown", retryAtMs }),
});

// ------------------------------------------------------------- references

function pageDeletionReference(db, pageId) {
  return db.doc(`${PAGE_DELETIONS}/${pageId}`);
}

function pagePostClearJobReference(db, pageId) {
  return db.doc(`${PAGE_POST_CLEAR_JOBS}/${pageId}`);
}

function pageMemoryReference(db, pageId) {
  return db.doc(`${PAGE_MEMORY}/${pageId}`);
}

// ------------------------------------------------------------- canonical

function exactKeys(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  return actual.length === keys.length && actual.every((key, index) => key === keys[index]);
}

// The keyset position processPosts returns: {t: createdAt ms, id: the post
// document's id}. The id is bounded but not pattern-checked: a malformed
// post document is consumed like any other, and its id must stay a valid
// cursor (a record nobody can read would park the purge).
function validCursor(value) {
  return value === null || (exactKeys(value, ["id", "t"]) &&
    Number.isSafeInteger(value.t) && value.t >= 0 &&
    typeof value.id === "string" && value.id.length > 0 && value.id.length <= 256);
}

/**
 * The deletion record in `snapshot` for `pageId`: null when missing, the
 * parsed record when exact, and {malformed: true} otherwise. A malformed
 * record is NEVER acted on by the worker (a purge is irreversible): the
 * owner's next request rewrites it and a restore removes it.
 */
function canonicalPageDeletion(snapshot, pageId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const requestedAtMs = timestampMillis(data.requestedAt);
  const deleteAtMs = timestampMillis(data.deleteAt);
  const dueAtMs = timestampMillis(data.dueAt);
  const reminderAtMs = timestampMillis(data.reminderAt);
  if (!exactKeys(data, PAGE_DELETION_KEYS) || data.schemaVersion !== 1 ||
      data.pageId !== pageId || snapshot.id !== pageId ||
      !PAGE_DELETION_STATES.includes(data.state) ||
      requestedAtMs === null || deleteAtMs === null || dueAtMs === null ||
      deleteAtMs < requestedAtMs ||
      (data.reminderAt !== null && reminderAtMs === null) ||
      typeof data.pausedBefore !== "boolean" ||
      !Number.isSafeInteger(data.step) || data.step < 0 ||
      data.step >= PAGE_DELETION_STEPS.length ||
      !validCursor(data.cursor) ||
      !Number.isSafeInteger(data.attempts) || data.attempts < 0 ||
      timestampMillis(data.updatedAt) === null) {
    return Object.freeze({ malformed: true });
  }
  return Object.freeze({
    malformed: false,
    pageId,
    state: data.state,
    requestedAtMs,
    deleteAtMs,
    dueAtMs,
    reminderAtMs,
    pausedBefore: data.pausedBefore,
    step: data.step,
    cursor: data.cursor,
    attempts: data.attempts,
  });
}

/// A usable deletion record, or null (missing or malformed).
function livePageDeletion(snapshot, pageId) {
  const deletion = canonicalPageDeletion(snapshot, pageId);
  return deletion === null || deletion.malformed ? null : deletion;
}

function canonicalPagePostClearJob(snapshot, pageId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const requestedAtMs = timestampMillis(data.requestedAt);
  if (!exactKeys(data, PAGE_POST_CLEAR_JOB_KEYS) || data.schemaVersion !== 1 ||
      data.pageId !== pageId || snapshot.id !== pageId || requestedAtMs === null ||
      !validCursor(data.cursor) ||
      !Number.isSafeInteger(data.attempts) || data.attempts < 0 ||
      timestampMillis(data.nextAttemptAt) === null ||
      timestampMillis(data.updatedAt) === null) {
    return Object.freeze({ malformed: true });
  }
  return Object.freeze({
    malformed: false,
    pageId,
    requestedAtMs,
    cursor: data.cursor,
    attempts: data.attempts,
  });
}

function validSuspension(value) {
  return value === null || (exactKeys(value, PAGE_MEMORY_SUSPENSION_KEYS) &&
    timestampMillis(value.suspendedAt) !== null &&
    typeof value.suspensionReason === "string" &&
    SUSPENSION_REASON_PATTERN.test(value.suspensionReason));
}

/**
 * The memory of a deleted Page: null when missing, the parsed row when
 * exact. A malformed row is `data-loss`: it may hide a suspension or a
 * cooldown, so nobody may create a Page over it until an operator repairs it.
 */
function canonicalPageMemory(snapshot, pageId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const deletedAtMs = timestampMillis(data.deletedAt);
  const recreateAllowedAtMs = timestampMillis(data.recreateAllowedAt);
  if (!exactKeys(data, PAGE_MEMORY_KEYS) || data.schemaVersion !== 1 ||
      data.pageId !== pageId || snapshot.id !== pageId ||
      deletedAtMs === null || recreateAllowedAtMs === null ||
      !validSuspension(data.suspension) ||
      (data.expiresAt !== null && timestampMillis(data.expiresAt) === null) ||
      // A remembered suspension never expires by time.
      (data.suspension !== null && data.expiresAt !== null) ||
      timestampMillis(data.updatedAt) === null) {
    fail("data-loss", "The Page memory record is malformed.");
  }
  return Object.freeze({
    pageId,
    deletedAtMs,
    recreateAllowedAtMs,
    suspension: data.suspension === null
      ? null
      : Object.freeze({
        suspendedAt: data.suspension.suspendedAt,
        suspensionReason: data.suspension.suspensionReason,
      }),
  });
}

// --------------------------------------------------------------- documents

function pageDeletionDocument({ pageId, pausedBefore, nowMs, now, TimestampImpl }) {
  const deleteAtMs = nowMs + PAGE_DELETION_WINDOW_MS;
  const deleteAt = TimestampImpl.fromMillis(deleteAtMs);
  return {
    schemaVersion: 1,
    pageId,
    state: "pending",
    requestedAt: now,
    deleteAt,
    pausedBefore,
    reminderAt: TimestampImpl.fromMillis(deleteAtMs - PAGE_DELETION_REMINDER_BEFORE_MS),
    dueAt: deleteAt,
    step: 0,
    cursor: null,
    attempts: 0,
    updatedAt: now,
  };
}

function pagePostClearJobDocument({ pageId, now }) {
  return {
    schemaVersion: 1,
    pageId,
    requestedAt: now,
    cursor: null,
    attempts: 0,
    nextAttemptAt: now,
    updatedAt: now,
  };
}

/// The memory a removed Page leaves. `pageData` is the raw pages/{pageId}
/// document (or null when it was already gone): a suspension is read from
/// it as it is, even when the rest of the document is malformed.
/// `remembered` is the suspension an EXISTING memory row already carries
/// (staff suspended the Page after an earlier deletion, see
/// rememberPageSuspensionInTransaction): the Page's own suspension wins,
/// and without one the remembered suspension is kept, never dropped.
function pageMemoryDocument({ pageId, pageData, nowMs, now, TimestampImpl, remembered = null }) {
  const recreateAllowedAt = TimestampImpl.fromMillis(nowMs + PAGE_RECREATE_COOLDOWN_MS);
  const suspended = pageData?.suspended === true;
  const suspension = suspended
    ? {
        suspendedAt: timestampMillis(pageData.suspendedAt) === null ? now : pageData.suspendedAt,
        suspensionReason: typeof pageData.suspensionReason === "string" &&
            SUSPENSION_REASON_PATTERN.test(pageData.suspensionReason)
          ? pageData.suspensionReason
          : "other",
      }
    : remembered !== null && validSuspension(remembered) ? { ...remembered } : null;
  return {
    schemaVersion: 1,
    pageId,
    deletedAt: now,
    recreateAllowedAt,
    suspension,
    expiresAt: suspension === null ? recreateAllowedAt : null,
    updatedAt: now,
  };
}

// ------------------------------------------- moderation after a deletion

/// canonicalPageMemory without the throw: {memory, malformed}.
function readPageMemory(snapshot, pageId) {
  try {
    return { memory: canonicalPageMemory(snapshot, pageId), malformed: false };
  } catch {
    return { memory: null, malformed: true };
  }
}

/**
 * Staff suspended a Page whose owner had ALREADY deleted it (moderation.js,
 * inside the moderator's transaction; `memorySnapshot` was read there before
 * any write). pages/{pageId} is gone, so the suspension is written into the
 * memory row instead: the next Page this account creates starts suspended,
 * exactly as if the suspension had landed before the deletion. Without this
 * an owner could delete a reported Page ("delete now"), wait out the report
 * and the 7 days, and start clean.
 *
 * An existing row keeps its dates (the cooldown is not restarted); with no
 * row left the suspension alone is remembered. A row that already remembers
 * a suspension is left as it is, and a malformed row is not touched (create
 * fails closed on it). Returns true when the suspension was written.
 */
function rememberPageSuspensionInTransaction(transaction, {
  db, pageId, memorySnapshot, reason, now, logger = defaultLogger,
}) {
  const { memory, malformed } = readPageMemory(memorySnapshot, pageId);
  if (malformed) {
    logger.error("pages memory record malformed", {});
    return false;
  }
  if (memory !== null && memory.suspension !== null) return false;
  const stored = memory === null ? null : memorySnapshot.data();
  transaction.set(pageMemoryReference(db, pageId), {
    schemaVersion: 1,
    pageId,
    deletedAt: stored === null ? now : stored.deletedAt,
    recreateAllowedAt: stored === null ? now : stored.recreateAllowedAt,
    suspension: {
      suspendedAt: now,
      suspensionReason: typeof reason === "string" && SUSPENSION_REASON_PATTERN.test(reason)
        ? reason
        : "other",
    },
    // A remembered suspension never expires by time.
    expiresAt: null,
    updatedAt: now,
  });
  return true;
}

/**
 * Staff lifted the suspension of a Page that no longer exists: the
 * remembered suspension goes, and the row is left to expire with its
 * cooldown. Returns true when a remembered suspension was lifted.
 */
function liftRememberedPageSuspensionInTransaction(transaction, {
  db, pageId, memorySnapshot, now, logger = defaultLogger,
}) {
  const { memory, malformed } = readPageMemory(memorySnapshot, pageId);
  if (malformed) {
    logger.error("pages memory record malformed", {});
    return false;
  }
  if (memory === null || memory.suspension === null) return false;
  const stored = memorySnapshot.data();
  transaction.set(pageMemoryReference(db, pageId), {
    schemaVersion: 1,
    pageId,
    deletedAt: stored.deletedAt,
    recreateAllowedAt: stored.recreateAllowedAt,
    suspension: null,
    expiresAt: stored.recreateAllowedAt,
    updatedAt: now,
  });
  return true;
}

// ------------------------------------------- create-side checks (lifecycle)

/// Throws `pageRecreateCooldown` while the 7-day cooldown of `memory` runs.
function assertPageRecreateAllowed(memory, nowMs) {
  if (memory !== null && nowMs < memory.recreateAllowedAtMs) {
    throw PAGE_DELETION_ERRORS.recreateCooldown(memory.recreateAllowedAtMs);
  }
}

/// The suspension fields a NEW Page takes over from `memory`, or null.
function rememberedPageSuspension(memory) {
  if (!memory || memory.suspension === null) return null;
  return {
    suspended: true,
    suspendedAt: memory.suspension.suspendedAt,
    suspensionReason: memory.suspension.suspensionReason,
  };
}

// ------------------------------------------------------------------ views

function pageDeletionState({
  pageId, pageExists, deletion, clearJob, memory, nowMs, pagePaused = null,
}) {
  return {
    schemaVersion: 1,
    pageId,
    pageExists,
    // Whether the caller's own Page is paused by its owner right now: after
    // a restore this says if the Page came back on air or stayed paused.
    pagePaused: pageExists ? pagePaused === true : null,
    deletion: deletion
      ? {
          state: deletion.state,
          requestedAtMs: deletion.requestedAtMs,
          deleteAtMs: deletion.deleteAtMs,
        }
      : null,
    postsClearing: clearJob && !clearJob.malformed
      ? { requestedAtMs: clearJob.requestedAtMs }
      : null,
    recreateAllowedAtMs: !pageExists && memory && memory.recreateAllowedAtMs > nowMs
      ? memory.recreateAllowedAtMs
      : null,
  };
}

/// The owner's "deleted in 3 days" bell row (the pageLapse notice shape).
function pageDeletionReminderNotice({ pageId, deleteAtMs, now }) {
  const id = `${PAGE_LAPSE_NOTICE_TYPE}_${PAGE_DELETION_REMINDER_PHASE}_${deleteAtMs}`;
  return {
    id,
    data: pageSystemNotice({
      type: PAGE_LAPSE_NOTICE_TYPE,
      targetId: pageId,
      targetLabel: PAGE_DELETION_REMINDER_LABEL,
      dedupeKey: id,
      now,
      extra: { lapsePhase: PAGE_DELETION_REMINDER_PHASE },
    }),
  };
}

function exactDeletionInput(data) {
  requireObject(data);
  if (typeof data.op !== "string" || !MANAGE_PAGE_DELETION_OPS.includes(data.op)) {
    fail("invalid-argument", "op is invalid.");
  }
  if (data.op !== "purgeNow") {
    requireExactInput(data, ["op"], ["op"]);
    return { op: data.op };
  }
  // "Delete now" names the request it confirms (the requestedAtMs the owner
  // was shown), so it can never act on a different, newer one.
  requireExactInput(data, ["op", "requestedAtMs"], ["op", "requestedAtMs"]);
  if (!Number.isSafeInteger(data.requestedAtMs) || data.requestedAtMs < 0) {
    fail("invalid-argument", "requestedAtMs is invalid.");
  }
  return { op: data.op, requestedAtMs: data.requestedAtMs };
}

function errorCode(error) {
  return typeof error?.code === "string" || Number.isSafeInteger(error?.code) ? error.code : null;
}

/// sweepStorage (account_deletion.js) speaks to a bucket; the Pages storage
/// adapter is generation-bound. An open upload has no recorded generation,
/// so the live one is resolved first (the reservation-expiry order).
function bucketOver(storage) {
  return {
    file(path, options = {}) {
      return {
        async delete() {
          let generation = options.generation;
          if (generation === undefined || generation === null) {
            try {
              const metadata = await storage.getMetadata(path);
              generation = String(metadata?.generation ?? "");
            } catch (error) {
              if (isMissingObject(error)) return;
              throw error;
            }
            if (!GENERATION_PATTERN.test(generation)) return;
          }
          await storage.deleteObject(path, { generation: String(generation) });
        },
      };
    },
  };
}

// ----------------------------------------------------------------- service

function createPagesDeletionService({
  firestore,
  storage = null,
  resolveStorage = null,
  stages = null,
  removeFollowEdges = null,
  settleFollowers = null,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimits = PAGES_DELETION_RATE_LIMITS,
  limits = PAGES_DELETION_WORK_LIMITS,
}) {
  if (!firestore?.doc || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, Timestamp and clock are required.");
  }

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  // Lazy collaborators: a status read loads none of them.
  let stagesService = stages;
  function pageStages() {
    if (stagesService === null) {
      const { createPagesAccountDeletion } = require("./account_deletion");
      stagesService = createPagesAccountDeletion({ db: firestore, TimestampImpl, clock, logger });
    }
    return stagesService;
  }
  let edgeRemover = removeFollowEdges;
  function followEdges() {
    if (edgeRemover === null) {
      const { createFollowEdgeRemover } = require("../account/follow_edges");
      edgeRemover = createFollowEdgeRemover({
        db: firestore, FieldValue, edgePage: limits.edgePage,
      });
    }
    return edgeRemover;
  }
  function settle(uid) {
    if (settleFollowers !== null) return settleFollowers(uid);
    return require("../account/follow_edges").settleFollowerCount(firestore, uid);
  }
  let storageAdapter = storage;
  function pageStorage() {
    if (storageAdapter === null) {
      storageAdapter = typeof resolveStorage === "function"
        ? resolveStorage()
        : require("./media_runtime").defaultPagesMediaDependencies().storage;
    }
    return storageAdapter;
  }

  async function chargeRate(scope, uid, { nowMs, now }) {
    const reference = rateLimitReference(firestore, scope, uid);
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      consumeRateLimit(transaction, snapshot, {
        reference, scope, uid, nowMs, now, ...rateLimits[scope],
      });
    });
  }

  function references(uid) {
    return {
      pageRef: pageReference(firestore, uid),
      deletionRef: pageDeletionReference(firestore, uid),
      clearRef: pagePostClearJobReference(firestore, uid),
      memoryRef: pageMemoryReference(firestore, uid),
    };
  }

  /// The caller's state from four plain reads.
  async function readState(uid) {
    const { nowMs } = timing();
    const { pageRef, deletionRef, clearRef, memoryRef } = references(uid);
    const [pageSnapshot, deletionSnapshot, clearSnapshot, memorySnapshot] =
      await firestore.getAll(pageRef, deletionRef, clearRef, memoryRef);
    let memory = null;
    try {
      memory = canonicalPageMemory(memorySnapshot, uid);
    } catch {
      // `create` is what fails closed on a malformed memory; the state view
      // only loses the cooldown date.
      logger.error("pages memory record malformed", {});
    }
    return pageDeletionState({
      pageId: uid,
      pageExists: pageSnapshot.exists,
      pagePaused: pageSnapshot.exists && pageSnapshot.data()?.ownerPaused === true,
      deletion: livePageDeletion(deletionSnapshot, uid),
      clearJob: canonicalPagePostClearJob(clearSnapshot, uid),
      memory,
      nowMs,
    });
  }

  // ----------------------------------------------------------------- ops

  async function status(auth) {
    await chargeRate("pages.deletionStatus", auth.uid, timing());
    return readState(auth.uid);
  }

  async function request(auth) {
    const uid = auth.uid;
    const timed = timing();
    const { nowMs, now } = timed;
    await chargeRate("pages.deletionRequest", uid, timed);
    const { pageRef, deletionRef, clearRef } = references(uid);
    return firestore.runTransaction(async (transaction) => {
      const [pageSnapshot, visibilitySnapshot, deletionSnapshot, clearSnapshot] =
        await transactionGetAll(
          transaction, pageRef, pageVisibilityReference(firestore), deletionRef, clearRef,
        );
      // A safety action: a malformed Page is still paused and still deleted.
      const page = pageForSafetyAction(pageSnapshot, uid, logger);
      if (page === null) throw PAGE_ERRORS.notFound();
      const clearJob = canonicalPagePostClearJob(clearSnapshot, uid);
      const existing = canonicalPageDeletion(deletionSnapshot, uid);
      if (existing !== null && !existing.malformed) {
        // Idempotent: the first request's date stands. A record means "this
        // Page is paused"; one found over a RUNNING Page (an operator's
        // repair, a record that outlived an earlier Page) pauses it again
        // rather than leaving a public Page on a deletion timer.
        applyPagePauseInTransaction(transaction, {
          db: firestore, uid, page, visibilitySnapshot, now, logger,
        });
        return pageDeletionState({
          pageId: uid, pageExists: true, pagePaused: true, deletion: existing, clearJob,
          memory: null, nowMs,
        });
      }
      if (existing?.malformed) logger.error("pages deletion record malformed on request", {});
      const pausedBefore = page.ownerPaused === true;
      applyPagePauseInTransaction(transaction, {
        db: firestore, uid, page, visibilitySnapshot, now, logger,
      });
      const record = pageDeletionDocument({ pageId: uid, pausedBefore, nowMs, now, TimestampImpl });
      transaction.set(deletionRef, record);
      return pageDeletionState({
        pageId: uid,
        pageExists: true,
        pagePaused: true,
        deletion: {
          state: "pending",
          requestedAtMs: nowMs,
          deleteAtMs: nowMs + PAGE_DELETION_WINDOW_MS,
        },
        clearJob,
        memory: null,
        nowMs,
      });
    });
  }

  /**
   * Takes a pending deletion back, in two separate steps.
   *
   * 1. CANCEL, a safety action. The record goes whenever it is still
   *    pending: no switch, no capability, no mute, no verified e-mail, no
   *    budget, and whatever state the Page document is in (it is not even
   *    read). The purge reads none of those gates, so the undo must not
   *    either: a gate that stayed closed for the rest of the 30 days would
   *    otherwise turn a deletion the owner tried to take back into a
   *    permanent one. Once the purge has started there is nothing to cancel
   *    (`pageDeletionInProgress`).
   * 2. RESUME, an ordinary gated write, only for a Page that was running
   *    before the request. Any refusal (switch off, unverified, muted, no
   *    live Premium or VIP, a private profile, a name no longer allowed, a
   *    suspension, a broken visibility index, the budget) leaves the Page
   *    exactly what a cancelled deletion leaves by itself: an ordinary paused
   *    Page that the owner resumes later with managePageV1. The answer's
   *    `pagePaused` says which of the two happened.
   */
  async function restore(auth) {
    const uid = auth.uid;
    const timed = timing();
    const { deletionRef } = references(uid);
    const cancelled = await firestore.runTransaction(async (transaction) => {
      const existing = canonicalPageDeletion(await transaction.get(deletionRef), uid);
      // Nothing pending: an idempotent answer.
      if (existing === null) return null;
      if (!existing.malformed && existing.state === "purging") {
        throw PAGE_DELETION_ERRORS.inProgress();
      }
      // A malformed record goes too: nothing may ever act on it, and what
      // it said about the Page before the request is not trusted.
      transaction.delete(deletionRef);
      return { resume: existing.malformed !== true && existing.pausedBefore === false };
    });
    if (cancelled !== null && cancelled.resume) {
      let outcome;
      try {
        outcome = await resumeAfterCancel(auth, timed);
      } catch (error) {
        outcome = `error:${errorCode(error) ?? "unknown"}`;
      }
      if (outcome !== "resumed") {
        logger.info("pages deletion cancelled, page left paused", { outcome });
      }
    }
    return readState(uid);
  }

  /// Step 2 of `restore`: the Page goes back on air when today's gates allow
  /// it. Returns a short outcome word; never the reason a Page is deleted.
  async function resumeAfterCancel(auth, timed) {
    const uid = auth.uid;
    const { nowMs, now } = timed;
    if (auth.token?.email_verified !== true) return "unverified";
    const activation = await readPagesActivation({ db: firestore, logger });
    if (!pagesWriteAllowed(activation, uid)) return "notEnabled";
    await chargeRate("pages.deletionRestore", uid, timed);
    const { pageRef, deletionRef } = references(uid);
    return firestore.runTransaction(async (transaction) => {
      const [userSnapshot, entitlementSnapshot, grantSnapshot, restrictionSnapshot, pageSnapshot,
        publicSnapshot, visibilitySnapshot, deletionSnapshot] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        pageRef,
        firestore.doc(`publicProfiles/${uid}`),
        pageVisibilityReference(firestore),
        deletionRef,
      );
      // A new request landed after the cancel: that Page stays paused (a
      // record always means "paused").
      if (deletionSnapshot.exists) return "requestedAgain";
      const user = userSnapshot.exists ? (userSnapshot.data() ?? null) : null;
      if (!likersAccountIsActive(user)) return "inactive";
      assertNotRestricted(restrictionSnapshot, "Your", nowMs);
      const capability = derivePagesCapability(
        { userSnapshot, entitlementSnapshot, grantSnapshot },
        { tokenRole: typeof auth.token?.role === "string" ? auth.token.role : null, now: nowMs },
      );
      if (!capability.allowed) return "accessRequired";
      const page = canonicalPageOrNull(pageSnapshot, uid);
      if (pageSnapshot.exists && page === null) {
        logger.error("pages malformed page on a deletion restore", {
          reason: pageMalformedReason(pageSnapshot.data(), uid),
        });
      }
      // No Page, a malformed one or a suspended one is left exactly as it
      // is (a suspended one as a moderator put it).
      if (page === null) return "noPage";
      if (page.suspended) return "suspended";
      if (page.ownerPaused !== true) return "resumed";
      // The resume rules of managePageV1: a public profile, an allowed name.
      if (!resumable(user, publicSnapshot, uid)) return "notResumable";
      // The capability is live (the gate passed): a lapsed Page is restored.
      const changes = { ...restoredPageFields(page), ownerPaused: false };
      const next = { ...page, ...changes, updatedAt: now };
      next.listed = derivePageListed(next);
      transaction.update(pageRef, { ...changes, listed: next.listed, updatedAt: now });
      applyPageVisibilityInTransaction(transaction, {
        db: firestore, snapshot: visibilitySnapshot, pageId: uid, page: next, now, logger,
      });
      return "resumed";
    });
  }

  /// managePageV1 resume's two content rules, as a boolean.
  function resumable(user, publicSnapshot, uid) {
    if (normalizeProfileVisibility(user.profileVisibility) !== "public") return false;
    try {
      canonicalPublicProfile(publicSnapshot, uid);
    } catch {
      return false;
    }
    const displayName = pageDisplayNameMirror(publicSnapshot.data().displayName);
    return displayName !== null && pageNameViolation(displayName) === null;
  }

  /**
   * "Delete now": the one irreversible op, so it is the one that asks for
   * more than a valid session.
   *   * A sign-in no older than 5 minutes (the account-deletion rule,
   *     utils/auth.js): a stolen or left-open session can start a deletion,
   *     which the owner can take back for 30 days, but cannot skip the wait.
   *   * The requestedAtMs of the request it confirms: a delayed or repeated
   *     call never purges a newer request.
   */
  async function purgeNow(auth, input) {
    const uid = auth.uid;
    const timed = timing();
    const { nowMs, now } = timed;
    requireRecentPrivilegedAuthentication(auth, { nowSeconds: Math.floor(nowMs / 1000) });
    await chargeRate("pages.deletionPurge", uid, timed);
    const { deletionRef } = references(uid);
    const started = await firestore.runTransaction(async (transaction) => {
      const deletion = canonicalPageDeletion(await transaction.get(deletionRef), uid);
      if (deletion === null || deletion.malformed) throw PAGE_DELETION_ERRORS.notRequested();
      if (deletion.requestedAtMs !== input.requestedAtMs) throw PAGE_DELETION_ERRORS.changed();
      // Already running: the worker has it. No second runner is started.
      if (deletion.state === "purging") return false;
      transaction.update(deletionRef, {
        state: "purging",
        step: 0,
        cursor: null,
        attempts: 0,
        reminderAt: null,
        dueAt: now,
        updatedAt: now,
      });
      return true;
    });
    if (started) {
      try {
        await advanceDeletion(uid, { rounds: limits.inlineDeletionRounds });
      } catch (error) {
        // The record stays; pagesMaintenance finishes the purge.
        logger.warn("pages deletion purge deferred", { code: errorCode(error) });
      }
    }
    return readState(uid);
  }

  async function clearPosts(auth) {
    const uid = auth.uid;
    const timed = timing();
    const { now } = timed;
    await chargeRate("pages.deletionClear", uid, timed);
    const { pageRef, deletionRef, clearRef } = references(uid);
    const queued = await firestore.runTransaction(async (transaction) => {
      const [pageSnapshot, deletionSnapshot] = await transactionGetAll(
        transaction, pageRef, deletionRef,
      );
      if (pageForSafetyAction(pageSnapshot, uid, logger) === null) throw PAGE_ERRORS.notFound();
      // A purge already removes every post.
      if (livePageDeletion(deletionSnapshot, uid)?.state === "purging") return false;
      // A repeated request moves the boundary to now: posts published since
      // the first one are included, and the walk starts over.
      transaction.set(clearRef, pagePostClearJobDocument({ pageId: uid, now }));
      return true;
    });
    if (queued) {
      try {
        await runClearJob(uid, { rounds: limits.inlineClearRounds });
      } catch (error) {
        logger.warn("pages post clearing deferred", { code: errorCode(error) });
      }
    }
    return readState(uid);
  }

  async function managePageDeletionV1(request_) {
    // No op needs a verified e-mail: status is a read, and request,
    // purgeNow, clearPosts and the CANCEL half of restore are safety actions
    // (an owner who could ask for the deletion unverified must be able to
    // take it back unverified). Only the resume that may follow a cancel
    // looks at the e-mail, and it leaves the Page paused instead of refusing.
    const auth = requireActor(request_, { verified: false });
    const input = exactDeletionInput(request_.data);
    switch (input.op) {
      case "status": return status(auth);
      case "request": return request(auth);
      case "restore": return restore(auth);
      case "purgeNow": return purgeNow(auth, input);
      case "clearPosts": return clearPosts(auth);
      default: return fail("invalid-argument", "op is invalid.");
    }
  }

  // -------------------------------------------------------------- worker

  /// Saves the purge position; a record that is no longer `purging` (it
  /// cannot be: purging is terminal) or is gone is left alone.
  async function saveProgress(uid, changes) {
    const { now } = timing();
    const { deletionRef } = references(uid);
    return firestore.runTransaction(async (transaction) => {
      const deletion = livePageDeletion(await transaction.get(deletionRef), uid);
      if (deletion === null || deletion.state !== "purging") return false;
      transaction.update(deletionRef, { ...changes, attempts: 0, dueAt: now, updatedAt: now });
      return true;
    });
  }

  /// The last step: the Page, its index entry, the memory and every
  /// Page-keyed job, in ONE transaction that also RE-READS this record.
  /// Only a record that is still `purging` authorises it: a second runner
  /// (purgeNow's inline pass beside the worker) or a retry after a lost
  /// response finds the record gone and writes nothing, so it can neither
  /// overwrite the memory the first one wrote (which would drop a
  /// remembered suspension) nor delete a Page it has no record for.
  function finishDeletion(uid) {
    const { deletionRef, clearRef, memoryRef } = references(uid);
    return pageStages().removePage(uid, {
      reads: [deletionRef, memoryRef],
      guard: ([deletionSnapshot]) =>
        livePageDeletion(deletionSnapshot, uid)?.state === "purging",
      also: (transaction, { pageSnapshot, snapshots, nowMs, now }) => {
        const existing = readPageMemory(snapshots[1], uid);
        if (existing.malformed) {
          // Never replaced: it may hide a suspension, and create fails
          // closed on it until an operator repairs it.
          logger.error("pages memory record malformed", {});
        } else {
          transaction.set(memoryRef, pageMemoryDocument({
            pageId: uid,
            pageData: pageSnapshot.exists ? (pageSnapshot.data() ?? null) : null,
            nowMs,
            now,
            TimestampImpl,
            remembered: existing.memory?.suspension ?? null,
          }));
        }
        transaction.delete(deletionRef);
        transaction.delete(clearRef);
        transaction.delete(firestore.doc(`pageFollowCarryJobs/${uid}`));
        transaction.delete(firestore.doc(`pagePostMediaLeases/${uid}`));
      },
    });
  }

  /// One bounded step of a purge. {finished, step, cursor}.
  async function purgeStep(uid, deletion) {
    const stagesNow = pageStages();
    switch (PAGE_DELETION_STEPS[deletion.step]) {
      case "posts": {
        const posts = await stagesNow.processPosts(uid, deletion.cursor, {
          reason: "pageDeleted", ownerDelete: true,
        });
        return posts.done
          ? { finished: false, step: deletion.step + 1, cursor: null }
          : { finished: false, step: deletion.step, cursor: posts.after };
      }
      case "followers": {
        const removed = await followEdges()(uid, { side: "followers", survivor: true });
        const empty = removed < limits.edgePage && await settle(uid);
        return { finished: false, step: empty ? deletion.step + 1 : deletion.step, cursor: null };
      }
      case "storage": {
        const swept = await stagesNow.sweepStorage(uid, bucketOver(pageStorage()));
        return { finished: false, step: swept.more ? deletion.step : deletion.step + 1, cursor: null };
      }
      case "records": {
        const records = await stagesNow.removeRecords(uid);
        return { finished: false, step: records.done ? deletion.step + 1 : deletion.step, cursor: null };
      }
      default:
        await finishDeletion(uid);
        return { finished: true, step: deletion.step, cursor: null };
    }
  }

  /**
   * Advances one deletion record by at most `rounds` bounded steps. A
   * pending record whose date passed is claimed (`purging`) first, in a
   * transaction that re-reads it, so a restore either wins outright or
   * finds the purge already started.
   *
   * `deadlineHeld(uid)` is the operator's brake on the ONE irreversible
   * transition nobody asked for today: while it answers true a pending
   * record whose date passed is NOT claimed; it is looked at again in
   * PAGE_DELETION_HOLD_RETRY_MS and stays restorable meanwhile. A purge that
   * already started, and "delete now", are never held.
   * "none" | "waiting" | "held" | "more" | "done".
   */
  async function advanceDeletion(uid, {
    rounds = limits.deletionRounds, deadlineHeld = null,
  } = {}) {
    const { nowMs, now } = timing();
    const { deletionRef } = references(uid);
    let deletion = await firestore.runTransaction(async (transaction) => {
      const current = canonicalPageDeletion(await transaction.get(deletionRef), uid);
      if (current === null) return null;
      if (current.malformed) return current;
      if (current.state === "pending") {
        if (current.deleteAtMs > nowMs) return { ...current, waiting: true };
        if (typeof deadlineHeld === "function" && deadlineHeld(uid) === true) {
          transaction.update(deletionRef, {
            dueAt: TimestampImpl.fromMillis(nowMs + PAGE_DELETION_HOLD_RETRY_MS),
            updatedAt: now,
          });
          return { ...current, held: true };
        }
        transaction.update(deletionRef, {
          state: "purging", step: 0, cursor: null, attempts: 0, reminderAt: null,
          dueAt: now, updatedAt: now,
        });
        return { ...current, state: "purging", step: 0, cursor: null, attempts: 0 };
      }
      return current;
    });
    if (deletion === null) return "none";
    if (deletion.malformed) {
      // Never purge on a record nobody can read: park it and alert.
      logger.error("pages deletion record malformed", {});
      await deletionRef.update({
        dueAt: TimestampImpl.fromMillis(nowMs + DAY_MS),
      }).catch(() => {});
      return "none";
    }
    if (deletion.waiting) return "waiting";
    if (deletion.held) return "held";
    try {
      for (let round = 0; round < rounds; round += 1) {
        const outcome = await purgeStep(uid, deletion);
        if (outcome.finished) return "done";
        if (!await saveProgress(uid, { step: outcome.step, cursor: outcome.cursor })) return "none";
        deletion = { ...deletion, step: outcome.step, cursor: outcome.cursor };
      }
      return "more";
    } catch (error) {
      const failedAtMs = timing().nowMs;
      await firestore.runTransaction(async (transaction) => {
        const current = livePageDeletion(await transaction.get(deletionRef), uid);
        if (current === null || current.state !== "purging") return;
        transaction.update(deletionRef, {
          attempts: current.attempts + 1,
          dueAt: TimestampImpl.fromMillis(failedAtMs + pageJobBackoffMs(current.attempts)),
          updatedAt: TimestampImpl.fromMillis(failedAtMs),
        });
      }).catch(() => {});
      throw error;
    }
  }

  /// True once a sweep that started at `startedMs` has used its budget.
  function overBudget(startedMs) {
    return Number.isSafeInteger(startedMs) && Number.isSafeInteger(limits.sweepBudgetMs) &&
      clock() - startedMs >= limits.sweepBudgetMs;
  }

  /**
   * The operator's brake on deadline purges (never on "delete now"): a
   * pending deletion is not turned into a purge while its owner could not
   * use Pages at all, i.e. while appConfig/pagesV1 has Pages writes switched
   * off for them (the kill switch, testers mode for a non-tester, or a
   * missing or malformed switch, which reads as disabled). With Pages
   * hidden an owner may not even reach "Przywróć stronę", and an incident
   * that outlasts the rest of a 30-day window must not make deletions
   * permanent by itself. Returns a predicate over the owner's uid; the
   * switch is read once per run, and only when something is due.
   */
  async function deadlineHold() {
    const activation = await readPagesActivation({ db: firestore, logger });
    return (uid) => !pagesWriteAllowed(activation, uid);
  }

  async function processDueDeletions({ limit = limits.deletions, startedMs = null } = {}) {
    const { now } = timing();
    const page = await PAGES_DELETION_WORK_QUERIES.dueDeletions(firestore, now).limit(limit).get();
    const line = {
      processed: page.size, done: 0, failed: 0, held: 0, hasMore: page.size === limit,
    };
    const deadlineHeld = page.empty ? null : await deadlineHold();
    for (const document of page.docs) {
      if (overBudget(startedMs)) {
        line.hasMore = true;
        break;
      }
      if (!isValidOpaqueUid(document.id)) {
        logger.error("pages deletion record malformed", {});
        continue;
      }
      try {
        const outcome = await advanceDeletion(document.id, { deadlineHeld });
        if (outcome === "done") line.done += 1;
        if (outcome === "held") line.held += 1;
        if (outcome === "more") line.hasMore = true;
      } catch (error) {
        line.failed += 1;
        const attempts = Number.isSafeInteger(document.data()?.attempts)
          ? document.data().attempts + 1
          : 1;
        const level = attempts >= 5 ? "error" : "warn";
        logger[level]("pages deletion retry", { attempts, code: errorCode(error) });
      }
    }
    // Somebody must notice: these Pages stay restorable until the switch is
    // back, and are purged within PAGE_DELETION_HOLD_RETRY_MS after it is.
    if (line.held > 0) logger.warn("pages deletion deadline held", { held: line.held });
    return line;
  }

  /**
   * Runs one "delete all posts" job for at most `rounds` pages of posts.
   * Every save re-reads the job: a job the owner re-requested meanwhile (a
   * new requestedAt) is left to its next run. "none" | "more" | "done".
   */
  async function runClearJob(uid, { rounds = limits.clearRounds, startedMs = null } = {}) {
    const { clearRef } = references(uid);
    let job = canonicalPagePostClearJob(await clearRef.get(), uid);
    if (job === null) return "none";
    if (job.malformed) {
      // A malformed job names nothing to delete: it is dropped, and the
      // owner's next request writes a fresh one.
      logger.error("pages post clear job malformed", {});
      await clearRef.delete();
      return "none";
    }
    const same = (snapshot) => {
      const current = canonicalPagePostClearJob(snapshot, uid);
      return current !== null && !current.malformed && current.requestedAtMs === job.requestedAtMs
        ? current
        : null;
    };
    try {
      for (let round = 0; round < rounds; round += 1) {
        // The part's time budget also bounds ONE large job (after its first
        // round, so every due job always moves).
        if (round > 0 && overBudget(startedMs)) return "more";
        const posts = await pageStages().processPosts(uid, job.cursor, {
          reason: "postsCleared", ownerDelete: true, before: job.requestedAtMs,
        });
        const { now } = timing();
        const saved = await firestore.runTransaction(async (transaction) => {
          if (same(await transaction.get(clearRef)) === null) return false;
          if (posts.done) {
            transaction.delete(clearRef);
          } else {
            transaction.update(clearRef, {
              cursor: posts.after, attempts: 0, nextAttemptAt: now, updatedAt: now,
            });
          }
          return true;
        });
        if (!saved) return "none";
        if (posts.done) return "done";
        job = { ...job, cursor: posts.after };
      }
      return "more";
    } catch (error) {
      const { nowMs, now } = timing();
      await firestore.runTransaction(async (transaction) => {
        const current = same(await transaction.get(clearRef));
        if (current === null) return;
        transaction.update(clearRef, {
          attempts: current.attempts + 1,
          nextAttemptAt: TimestampImpl.fromMillis(nowMs + pageJobBackoffMs(current.attempts)),
          updatedAt: now,
        });
      }).catch(() => {});
      throw error;
    }
  }

  async function processDueClearJobs({ limit = limits.clearJobs, startedMs = null } = {}) {
    const { now } = timing();
    const page = await PAGES_DELETION_WORK_QUERIES.dueClearJobs(firestore, now).limit(limit).get();
    const line = { processed: page.size, done: 0, failed: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      if (overBudget(startedMs)) {
        line.hasMore = true;
        break;
      }
      if (!isValidOpaqueUid(document.id)) {
        logger.error("pages post clear job malformed", {});
        await document.ref.delete();
        continue;
      }
      try {
        const outcome = await runClearJob(document.id, { startedMs });
        if (outcome === "done") line.done += 1;
        if (outcome === "more") line.hasMore = true;
      } catch (error) {
        line.failed += 1;
        logger.warn("pages post clearing retry", { code: errorCode(error) });
      }
    }
    return line;
  }

  /// The one bell row an owner gets 3 days before the purge.
  async function sendDueReminders({ limit = limits.reminders } = {}) {
    const { nowMs, now } = timing();
    const page = await PAGES_DELETION_WORK_QUERIES.dueReminders(firestore, now).limit(limit).get();
    const line = { processed: page.size, sent: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      const uid = document.id;
      if (!isValidOpaqueUid(uid)) continue;
      const sent = await firestore.runTransaction(async (transaction) => {
        const deletion = livePageDeletion(await transaction.get(document.ref), uid);
        if (deletion === null || deletion.reminderAtMs === null ||
            deletion.reminderAtMs > nowMs) {
          return false;
        }
        transaction.update(document.ref, { reminderAt: null, updatedAt: now });
        // A reminder that is already too late (the worker was down) is
        // dropped, never sent after the fact.
        if (deletion.state !== "pending" || deletion.deleteAtMs <= nowMs) return false;
        const notice = pageDeletionReminderNotice({
          pageId: uid, deleteAtMs: deletion.deleteAtMs, now,
        });
        transaction.set(firestore.doc(`users/${uid}/notifications/${notice.id}`), notice.data);
        return true;
      });
      if (sent) line.sent += 1;
    }
    return line;
  }

  /// Memory rows whose cooldown ended and that remember no suspension.
  async function expireMemory({ limit = limits.memory } = {}) {
    const { nowMs, now } = timing();
    const page = await PAGES_DELETION_WORK_QUERIES.expiredMemory(firestore, now).limit(limit).get();
    const line = { processed: page.size, removed: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      const removed = await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document.ref);
        if (!snapshot.exists) return false;
        const data = snapshot.data() ?? {};
        const expiresAtMs = timestampMillis(data.expiresAt);
        // Only a row that still says so itself: a suspension written since
        // the query (expiresAt null) keeps it.
        if (expiresAtMs === null || expiresAtMs > nowMs ||
            (data.suspension !== null && data.suspension !== undefined)) {
          return false;
        }
        transaction.delete(document.ref);
        return true;
      });
      if (removed) line.removed += 1;
    }
    return line;
  }

  /// The pagesMaintenance slice: each part isolated from the others. The
  /// clear jobs run BEFORE the purges and on their own time budget: the
  /// posts of a "delete all posts" are still public while they wait, a
  /// purged Page's are already hidden (it is paused).
  async function sweep() {
    const parts = [
      ["reminders", () => sendDueReminders()],
      ["clearJobs", () => processDueClearJobs({ startedMs: clock() })],
      ["deletions", () => processDueDeletions({ startedMs: clock() })],
      ["memory", () => expireMemory()],
    ];
    const results = {};
    for (const [name, part] of parts) {
      try {
        results[name] = await part();
      } catch (error) {
        logger.error("pages deletion slice failed", { part: name, code: errorCode(error) });
        results[name] = { failed: true };
      }
    }
    return results;
  }

  return Object.freeze({
    advanceDeletion,
    expireMemory,
    managePageDeletionV1,
    processDueClearJobs,
    processDueDeletions,
    readState,
    runClearJob,
    sendDueReminders,
    sweep,
  });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    defaultService = createPagesDeletionService({ firestore: db });
  }
  return defaultService;
}

const managePageDeletionV1 = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => service().managePageDeletionV1(request),
);

module.exports = {
  MANAGE_PAGE_DELETION_OPS,
  PAGES_DELETION_RATE_LIMITS,
  PAGES_DELETION_WORK_LIMITS,
  PAGES_DELETION_WORK_QUERIES,
  PAGE_DELETIONS,
  PAGE_DELETION_ERRORS,
  PAGE_DELETION_HOLD_RETRY_MS,
  PAGE_DELETION_KEYS,
  PAGE_DELETION_REMINDER_BEFORE_MS,
  PAGE_DELETION_REMINDER_LABEL,
  PAGE_DELETION_REMINDER_PHASE,
  PAGE_DELETION_STATE_KEYS,
  PAGE_DELETION_STEPS,
  PAGE_DELETION_WINDOW_MS,
  PAGE_MEMORY,
  PAGE_MEMORY_KEYS,
  PAGE_POST_CLEAR_JOBS,
  PAGE_POST_CLEAR_JOB_KEYS,
  PAGE_RECREATE_COOLDOWN_MS,
  assertPageRecreateAllowed,
  canonicalPageDeletion,
  canonicalPageMemory,
  canonicalPagePostClearJob,
  createPagesDeletionService,
  liftRememberedPageSuspensionInTransaction,
  livePageDeletion,
  managePageDeletionV1,
  pageDeletionDocument,
  pageDeletionReference,
  pageDeletionReminderNotice,
  pageDeletionState,
  pageMemoryDocument,
  pageMemoryReference,
  pagePostClearJobDocument,
  pagePostClearJobReference,
  rememberPageSuspensionInTransaction,
  rememberedPageSuspension,
};

// The account-deletion outbox contract, in one place.
//
// It lives apart from functions/account/deletion.js so the Auth `onDelete`
// trigger in functions/profile/public_profiles.js can read and enqueue a row
// without requiring the worker (and without a require cycle). Everything here
// is pure: identifiers, row shapes and predicates — no Firestore handle, no
// Cloud Functions registration, nothing that costs a cold start.

const crypto = require("node:crypto");

const { isValidOpaqueUid } = require("../achievements/identity");

const OUTBOX_COLLECTION = "accountDeletionOutbox";
const DIGEST_COLLECTION = "deletedAccountDigests";
const CONFIG_DOCUMENT = Object.freeze({
  collection: "appConfig",
  id: "accountDeletion",
});

const OUTBOX_SCHEMA_VERSION = 1;
const ACCOUNT_DELETION_SCHEMA_VERSION = 1;

// The stage sequence, in execution order. `auth` is second to last on purpose:
// the uid is the only reliable key to everything else, so destroying the Auth
// identity earlier turns a retryable failure into an unrecoverable one.
const STAGE_ORDER = Object.freeze([
  "revoke",
  "content",
  "social",
  "messaging",
  "storage",
  "records",
  "auth",
  "finalize",
]);

const OUTBOX_STATUSES = Object.freeze([
  "pending",
  "processing",
  "completed",
  "deadLetter",
]);

const REQUEST_SOURCES = Object.freeze(["app", "web", "authTrigger"]);

// Copied from reelCleanupOutbox (functions/reels/service.js): eight attempts,
// exponential backoff, then a terminal deadLetter that a human investigates.
const MAX_ATTEMPTS = 8;
// The budget for attempts that NEVER REPORTED ANYTHING. `MAX_ATTEMPTS` bounds
// raised errors, and a raised error requires a live process to raise it: an
// instance killed mid-attempt (OOM, eviction, the 540s timeout) increments
// neither counter, so its row simply sits in `processing` until the lease
// lapses and the sweep re-claims it — for ever, with no error, no dead letter
// and nothing for an operator to notice. This counter bounds exactly that: it
// rises only when a row is re-claimed while still `processing`, and any
// orderly outcome (progress, or an error the worker lived to record) clears
// it, so no legitimately long deletion can be dead-lettered by it.
const MAX_ABANDONED_ATTEMPTS = 8;
const LEASE_MS = 5 * 60 * 1000;
const BACKOFF_BASE_MS = 30 * 1000;
const BACKOFF_CEILING_MS = 30 * 60 * 1000;

/**
 * A hashed document id, following the precedent at
 * `privateRateLimits/searchPublicProfiles_${sha256(uid)}`: Firebase Auth
 * accepts a wider character vocabulary than a Firestore path segment, so a raw
 * uid never becomes a document id. The worker needs the uid, so the row's
 * PAYLOAD carries it — exactly as `contentCleanupOutbox.requestedBy` does.
 */
function outboxIdForUid(uid) {
  if (!isValidOpaqueUid(uid)) return null;
  return crypto
    .createHash("sha256")
    .update(`account-deletion\0${uid}`)
    .digest("hex");
}

function backoffMs(attemptCount) {
  const attempt = Number.isSafeInteger(attemptCount) && attemptCount > 0
    ? attemptCount
    : 1;
  return Math.min(
    BACKOFF_CEILING_MS,
    BACKOFF_BASE_MS * 2 ** Math.min(attempt - 1, 10),
  );
}

function stageIndex(stage) {
  return STAGE_ORDER.indexOf(stage);
}

function isTerminalStatus(status) {
  return status === "completed" || status === "deadLetter";
}

/**
 * True only for a row that has finished every stage before `auth`.
 *
 * The one ordering that matters, asserted rather than assumed: a dead-lettered
 * row must never reach `admin.auth().deleteUser`, because a disabled, flagged
 * account an operator can still recover is strictly better than an Auth
 * identity destroyed with its data still in place.
 */
function mayDeleteAuthUser(row) {
  return Boolean(row) &&
    row.status !== "deadLetter" &&
    row.status !== "completed" &&
    stageIndex(row.stage) === stageIndex("auth");
}

/** The row a fresh deletion request creates. Every field is server-owned. */
function initialOutboxRow({
  uid,
  source,
  reporterTombstone,
  now,
}) {
  if (!isValidOpaqueUid(uid)) {
    throw new TypeError("A canonical uid is required.");
  }
  return {
    schemaVersion: OUTBOX_SCHEMA_VERSION,
    uid,
    source: REQUEST_SOURCES.includes(source) ? source : "app",
    stage: STAGE_ORDER[0],
    cursor: null,
    status: "pending",
    // TWO COUNTERS, TWO MEANINGS. `attemptCount` counts LEASES and only ever
    // grows — it is what mints the lease token, so it must never be reset.
    // `failureCount` is the retry budget `MAX_ATTEMPTS` bounds: only a raised
    // error increments it, and an attempt that made progress clears it. With
    // one counter doing both jobs, any account large enough to need eight
    // leases dead-lettered on its first transient error with none of the eight
    // retries the design promises.
    attemptCount: 0,
    failureCount: 0,
    // A THIRD meaning, and the only one that survives a dead process: how many
    // consecutive leases ended without the worker saying anything at all.
    abandonedCount: 0,
    nextAttemptAt: now,
    leaseToken: null,
    leaseUntil: null,
    lastErrorCode: null,
    reporterTombstone,
    requestedAt: now,
    updatedAt: now,
  };
}

/** The `users/{uid}.accountDeletion` map. Absent from the rules allowlist. */
function accountDeletionMark({ source, now }) {
  return {
    schemaVersion: ACCOUNT_DELETION_SCHEMA_VERSION,
    state: "pending",
    requestedAt: now,
    source: REQUEST_SOURCES.includes(source) ? source : "app",
  };
}

module.exports = {
  ACCOUNT_DELETION_SCHEMA_VERSION,
  BACKOFF_BASE_MS,
  BACKOFF_CEILING_MS,
  CONFIG_DOCUMENT,
  DIGEST_COLLECTION,
  LEASE_MS,
  MAX_ABANDONED_ATTEMPTS,
  MAX_ATTEMPTS,
  OUTBOX_COLLECTION,
  OUTBOX_SCHEMA_VERSION,
  OUTBOX_STATUSES,
  REQUEST_SOURCES,
  STAGE_ORDER,
  accountDeletionMark,
  backoffMs,
  initialOutboxRow,
  isTerminalStatus,
  mayDeleteAuthUser,
  outboxIdForUid,
  stageIndex,
};

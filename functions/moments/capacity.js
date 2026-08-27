const {
  fail,
  isValidOpaqueUid,
  timestampMillis,
} = require("../integrity/guards");

const MAX_ACTIVE_MOMENTS = 10;
const MOMENT_CAPACITY_LEDGER_SCHEMA_VERSION = 1;

function momentCapacityLedgerReference(db, uid) {
  if (!db?.doc || !isValidOpaqueUid(uid)) {
    throw new TypeError("A Firestore instance and canonical uid are required.");
  }
  return db.doc(`momentCapacityLedgers/${uid}`);
}

/**
 * The source of truth for capacity is always the complete set of published
 * Moments, never the mutex document. Equality-filtering is deliberate: an
 * arbitrary number of newer unpublished drafts cannot push an old permanent
 * Moment outside this query.
 */
function exactPublishedMomentsQuery(db, uid) {
  if (!db?.collection || !isValidOpaqueUid(uid)) {
    throw new TypeError("A Firestore instance and canonical uid are required.");
  }
  return db.collection("voiceMoments")
    .where("authorId", "==", uid)
    .where("isPublished", "==", true);
}

function countActiveMoments(snapshot, nowMs, { excludeMomentId = null } = {}) {
  if (!snapshot?.docs || !Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("A query snapshot and epoch milliseconds are required.");
  }
  let activeCount = 0;
  for (const candidate of snapshot.docs) {
    if (candidate.id === excludeMomentId) continue;
    const data = candidate.data() ?? {};
    const expiresAtMs = timestampMillis(data.expiresAt);
    // Missing/null expiry is permanent. A malformed expiry is also counted
    // fail-closed because timestampMillis returns null for it; corrupt legacy
    // data must never grant an extra publishing slot.
    if (data.isPublished === true &&
        (expiresAtMs === null || expiresAtMs > nowMs)) {
      activeCount += 1;
    }
  }
  return activeCount;
}

function assertActiveMomentCapacity(
  snapshot,
  nowMs,
  { excludeMomentId = null } = {},
) {
  const activeCount = countActiveMoments(snapshot, nowMs, { excludeMomentId });
  if (activeCount >= MAX_ACTIVE_MOMENTS) {
    fail(
      "resource-exhausted",
      `You already have ${MAX_ACTIVE_MOMENTS} active Voice Moments. ` +
        "Wait for one to expire, or delete one to make room for a " +
        "new recording.",
    );
  }
  return activeCount;
}

function capacityLedgerRevision(snapshot, uid) {
  if (!snapshot?.exists) return 0;
  const data = snapshot.data() ?? {};
  if (data.schemaVersion !== MOMENT_CAPACITY_LEDGER_SCHEMA_VERSION ||
      data.ownerId !== uid || !Number.isSafeInteger(data.revision) ||
      data.revision < 1) {
    fail("data-loss", "The Voice Moment capacity ledger is invalid.");
  }
  return data.revision;
}

/**
 * Every capacity-changing transaction writes the same per-author document.
 * Firestore therefore retries two concurrent finalizations (or a finalize
 * racing delete/expiry) even when they modify different Moment documents.
 * The revision is a mutex/version only; exact capacity remains reconstructible
 * from the published query, so rollout needs no backfill and cannot drift.
 */
function touchMomentCapacityLedger(
  transaction,
  reference,
  snapshot,
  uid,
  now,
) {
  const revision = capacityLedgerRevision(snapshot, uid);
  if (revision === Number.MAX_SAFE_INTEGER) {
    fail("data-loss", "The Voice Moment capacity ledger cannot advance safely.");
  }
  transaction.set(reference, {
    schemaVersion: MOMENT_CAPACITY_LEDGER_SCHEMA_VERSION,
    ownerId: uid,
    revision: revision + 1,
    updatedAt: now,
  });
}

module.exports = {
  MAX_ACTIVE_MOMENTS,
  MOMENT_CAPACITY_LEDGER_SCHEMA_VERSION,
  assertActiveMomentCapacity,
  countActiveMoments,
  exactPublishedMomentsQuery,
  momentCapacityLedgerReference,
  touchMomentCapacityLedger,
};

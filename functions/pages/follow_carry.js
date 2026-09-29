// Carrying an account's EXISTING followers over to its new Page (ADR-234,
// owner decision 2026-09-29: every Premium account may create a Page,
// whether or not it has or had followers).
//
// Follow edges are shared between a person and their Page: the Page's
// followers ARE users/{P}/followers, and users/{P}.followerCount counts them
// exactly. Nothing is mirrored, so creating a Page never writes an edge or a
// counter. The one per-follower Page-side state is the Treści hint
// pageFollowIndex/{f} (follows.js); "carry-over" means putting P into each
// existing follower's hint, with the rule a live follow uses
// (pageIdsAfterFollow).
//
//   pageFollowCarryJobs/{pageId}   server-only, written by managePageV1
//                                  create in the SAME transaction as pages/{P}
//     { schemaVersion: 1, pageId, afterId: null | uid (the cursor),
//       scanned, carried, skipped, evicted, attempts, nextAttemptAt,
//       createdAt, updatedAt }
//
// Right after that commit managePageV1 runs ONE batch (<= 100 followers)
// itself, so a small account is fully carried over before create returns.
// pagesMaintenance's `followCarry` slice finishes larger accounts in bounded
// (<= 10 x 100 followers a run), cursor-resumable batches; the create writes
// nextAttemptAt = now + 5 min so the worker never races the create's own
// batch. A failure backs off (pageJobBackoffMs) and alerts from 5 attempts.
//
// Each follower is ONE small transaction that re-reads users/{f}, both edge
// mirrors, both block directions and pageFollowIndex/{f}, and writes the
// index only while both edges exist and there is no block (carryDecision).
// Blocks: setUserBlock deletes both edges in its own transaction, so a
// blocked pair can never end up with a hint; an old inconsistent pair (edge
// plus block) is skipped. A deleted follower (users/{f} missing or deleted,
// or Auth-deleted) gets NO index document, so account deletion's `records`
// stage leaves no residue. Banned and disabled followers are carried: their
// edges exist and every reader re-checks the viewer's account anyway.
// Communication mutes never removed edges and do not stop reading, so they
// are not checked; minors are carried (every account may follow, D11).
//
// It never writes edges, counters, notifications or rate-limit rows, and the
// Page's pause / readOnly / hidden / suspended state and the kill switch do
// not stop it: a hint never grants visibility (the feed re-checks every
// Page and its edge per read). Idempotent: a re-run writes nothing for a
// follower whose index already holds P.
//
// A deleted Page: a run re-checks pages/{P} before every further batch and
// stops (noPage) once it is gone, and account deletion's social stage drops
// the deleted uid from each remaining follower's hint in the transaction
// that removes the edge (account/stages.js), so no hint outlives the
// account. In processDueJobs a failure of one job, wherever it happens,
// backs that job off and never stops the next due job.
//
// Log lines carry counts and codes only, never a uid or pageId.

const { FieldPath, FieldValue, Timestamp } = require("firebase-admin/firestore");
const defaultLogger = require("firebase-functions/logger");

const { timestampMillis, transactionGetAll } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const { followingEdgeExists } = require("./audience");
const {
  PAGE_FOLLOW_INDEX_MAX,
  canonicalPageFollowIndex,
  pageFollowIndexDocument,
  pageFollowIndexReference,
  pageIdsAfterFollow,
} = require("./follows");
const { pageJobBackoffMs } = require("./media_contract");

const PAGE_FOLLOW_CARRY_COLLECTION = "pageFollowCarryJobs";
const PAGE_FOLLOW_CARRY_JOB_KEYS = Object.freeze([
  "afterId",
  "attempts",
  "carried",
  "createdAt",
  "evicted",
  "nextAttemptAt",
  "pageId",
  "scanned",
  "schemaVersion",
  "skipped",
  "updatedAt",
]);
const PAGE_FOLLOW_CARRY_COUNTERS = Object.freeze([
  "scanned",
  "carried",
  "skipped",
  "evicted",
  "attempts",
]);
const PAGE_FOLLOW_CARRY_LIMITS = Object.freeze({
  batchSize: 100,
  // Batches managePageV1 runs itself right after the create commit.
  createBatches: 1,
  // Batches one pagesMaintenance run spends, across every due job.
  runBatches: 10,
  jobsPerRun: 5,
  // Follower transactions in flight at once.
  concurrency: 10,
});
const PAGE_FOLLOW_CARRY_HANDOFF_MS = 5 * 60 * 1000;
const PAGE_FOLLOW_CARRY_STUCK_ATTEMPTS = 5;
const PAGE_FOLLOW_CARRY_OUTCOMES = Object.freeze([
  "invalid",
  "noEdge",
  "gone",
  "blocked",
  "already",
  "carry",
  "carryEvict",
]);

// The exact worker query shapes. The index smoke and the emulator index test
// run these same builders (ADR-007); both use automatic single-field
// indexes, so firestore.indexes.json does not change.
const PAGE_FOLLOW_CARRY_QUERIES = Object.freeze({
  // Single-field (automatic) index on nextAttemptAt.
  dueJobs: (db, now) => db.collection(PAGE_FOLLOW_CARRY_COLLECTION)
    .where("nextAttemptAt", "<=", now)
    .orderBy("nextAttemptAt", "asc"),
  // The Page's followers in document-id order (the cursor is the last id).
  followers: (db, pageId) => db.collection(`users/${pageId}/followers`)
    .orderBy(FieldPath.documentId(), "asc"),
});

function pageFollowCarryJobReference(db, pageId) {
  return db.doc(`${PAGE_FOLLOW_CARRY_COLLECTION}/${pageId}`);
}

/// A fresh job for `pageId`: cursor at the start, every counter zero.
function pageFollowCarryJobDocument({ pageId, now, nextAttemptAt }) {
  return {
    schemaVersion: 1,
    pageId,
    afterId: null,
    scanned: 0,
    carried: 0,
    skipped: 0,
    evicted: 0,
    attempts: 0,
    nextAttemptAt,
    createdAt: now,
    updatedAt: now,
  };
}

function nonNegativeSafeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

/**
 * The job in `snapshot` for `pageId`: {exists, malformed, job}. A malformed
 * job is reported with `job` null; the worker resets it to a fresh one,
 * which is safe because every step is idempotent. Never throws.
 */
function canonicalPageFollowCarryJob(snapshot, pageId) {
  if (!snapshot?.exists) return Object.freeze({ exists: false, malformed: false, job: null });
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const exact = keys.length === PAGE_FOLLOW_CARRY_JOB_KEYS.length &&
    keys.every((key, index) => key === PAGE_FOLLOW_CARRY_JOB_KEYS[index]) &&
    data.schemaVersion === 1 &&
    data.pageId === pageId &&
    (data.afterId === null || (isValidOpaqueUid(data.afterId) && data.afterId !== pageId)) &&
    PAGE_FOLLOW_CARRY_COUNTERS.every((key) => nonNegativeSafeInteger(data[key])) &&
    data.carried + data.skipped <= data.scanned &&
    data.evicted <= data.carried &&
    timestampMillis(data.nextAttemptAt) !== null &&
    timestampMillis(data.createdAt) !== null &&
    timestampMillis(data.updatedAt) !== null;
  if (!exact) return Object.freeze({ exists: true, malformed: true, job: null });
  return Object.freeze({ exists: true, malformed: false, job: Object.freeze({ ...data }) });
}

function snapshotData(snapshot) {
  return snapshot?.exists ? (snapshot.data() ?? null) : null;
}

/// users/{f} is gone for the carry-over: missing, deleted, or Auth-deleted.
/// Banned and disabled accounts are NOT gone (their edges still exist).
function followerAccountGone(user) {
  return !user || typeof user !== "object" ||
    user.status === "deleted" ||
    user.deleted === true ||
    (user.authDeletedAt !== null && user.authDeletedAt !== undefined);
}

/**
 * What carrying `followerId` over to `pageId` needs (pure). `index` is the
 * canonicalPageFollowIndex of pageFollowIndex/{followerId}. Returns
 * {outcome, pageIds} where `pageIds` is the index to write, or null for no
 * write. outcome is one of PAGE_FOLLOW_CARRY_OUTCOMES.
 */
function carryDecision({
  pageId,
  followerId,
  followerUser,
  followingEdge,
  followerEdge,
  followerBlocksPage,
  pageBlocksFollower,
  index,
}) {
  const none = (outcome) => Object.freeze({ outcome, pageIds: null });
  if (!isValidOpaqueUid(pageId) || !isValidOpaqueUid(followerId) || followerId === pageId) {
    return none("invalid");
  }
  if (!followingEdgeExists(followingEdge, pageId) || !followingEdgeExists(followerEdge, followerId)) {
    return none("noEdge");
  }
  if (followerAccountGone(followerUser)) return none("gone");
  if (followerBlocksPage === true || pageBlocksFollower === true) return none("blocked");
  const ids = index?.pageIds ?? [];
  if (ids.includes(pageId)) {
    // Already there: only a malformed document is rewritten (repaired).
    return Object.freeze({
      outcome: "already",
      pageIds: index?.malformed === true ? [...ids] : null,
    });
  }
  // A full index without P: the live-follow rule drops the oldest hint,
  // which lies outside the feed's newest-300 window.
  const outcome = ids.length >= PAGE_FOLLOW_INDEX_MAX ? "carryEvict" : "carry";
  return Object.freeze({ outcome, pageIds: pageIdsAfterFollow([...ids], pageId) });
}

function errorCode(error) {
  return typeof error?.code === "string" || Number.isSafeInteger(error?.code) ? error.code : null;
}

function isNotFound(error) {
  return error?.code === 5 || error?.code === "not-found" || error?.code === "NOT_FOUND";
}

/// Runs `task` over `items` with at most `concurrency` in flight. Every item
/// runs to completion; the first error (if any) is thrown afterwards.
async function mapBounded(items, concurrency, task) {
  const results = new Array(items.length);
  let next = 0;
  let firstError = null;
  async function worker() {
    while (next < items.length) {
      const slot = next;
      next += 1;
      try {
        results[slot] = await task(items[slot]);
      } catch (error) {
        if (firstError === null) firstError = error;
      }
    }
  }
  const lanes = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(Array.from({ length: lanes }, () => worker()));
  if (firstError !== null) throw firstError;
  return results;
}

function createPagesFollowCarryService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  limits = PAGE_FOLLOW_CARRY_LIMITS,
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

  /**
   * Carries one follower over in its own transaction. Returns the outcome.
   * Writes pageFollowIndex/{followerId} only for carry / carryEvict or to
   * repair a malformed index that already holds the Page.
   */
  async function carryFollower(pageId, followerId) {
    if (!isValidOpaqueUid(pageId) || !isValidOpaqueUid(followerId) || followerId === pageId) {
      return "invalid";
    }
    const indexRef = pageFollowIndexReference(firestore, followerId);
    return firestore.runTransaction(async (transaction) => {
      const [userSnapshot, followingEdge, followerEdge, followerBlock, pageBlock, indexSnapshot] =
        await transactionGetAll(
          transaction,
          firestore.doc(`users/${followerId}`),
          firestore.doc(`users/${followerId}/following/${pageId}`),
          firestore.doc(`users/${pageId}/followers/${followerId}`),
          firestore.doc(`users/${followerId}/blocked/${pageId}`),
          firestore.doc(`users/${pageId}/blocked/${followerId}`),
          indexRef,
        );
      const decision = carryDecision({
        pageId,
        followerId,
        followerUser: snapshotData(userSnapshot),
        followingEdge,
        followerEdge,
        followerBlocksPage: followerBlock.exists,
        pageBlocksFollower: pageBlock.exists,
        index: canonicalPageFollowIndex(indexSnapshot, followerId),
      });
      if (decision.pageIds !== null) {
        transaction.set(indexRef, pageFollowIndexDocument(
          decision.pageIds,
          FieldValue.serverTimestamp(),
        ));
      }
      return decision.outcome;
    });
  }

  function countsOf(job) {
    return {
      scanned: job.scanned,
      carried: job.carried,
      skipped: job.skipped,
      evicted: job.evicted,
    };
  }

  function completionLine(outcome, counts) {
    return {
      outcome,
      scanned: counts.scanned,
      carried: counts.carried,
      already: Math.max(counts.scanned - counts.carried - counts.skipped, 0),
      skipped: counts.skipped,
      evicted: counts.evicted,
    };
  }

  // Bookkeeping writes are plain updates: a job deleted meanwhile (another
  // runner completed it) is NOT_FOUND, and the work it covered is done.
  async function saveJob(jobRef, fields) {
    try {
      await jobRef.update(fields);
      return true;
    } catch (error) {
      if (isNotFound(error)) return false;
      throw error;
    }
  }

  async function recordFailure(jobRef, attempts, error) {
    const { nowMs, now } = timing();
    const next = attempts + 1;
    await saveJob(jobRef, {
      attempts: next,
      nextAttemptAt: TimestampImpl.fromMillis(nowMs + pageJobBackoffMs(attempts)),
      updatedAt: now,
    }).catch(() => false);
    logger.warn("pages follow carry-over retry", { attempts: next, code: errorCode(error) });
    if (next >= PAGE_FOLLOW_CARRY_STUCK_ATTEMPTS) {
      logger.error("pages follow carry-over stuck", { attempts: next, code: errorCode(error) });
    }
  }

  /**
   * Runs up to `maxBatches` batches of the Page's job. Returns
   * {outcome, batches}: outcome is noJob | noPage | completed | progress |
   * retry | vanished; `batches` counts follower pages read.
   */
  async function runJob(pageId, { maxBatches = limits.runBatches } = {}) {
    if (!isValidOpaqueUid(pageId)) return { outcome: "noJob", batches: 0 };
    const jobRef = pageFollowCarryJobReference(firestore, pageId);
    const [jobSnapshot, pageSnapshot] = await firestore.getAll(
      jobRef,
      firestore.doc(`pages/${pageId}`),
    );
    const state = canonicalPageFollowCarryJob(jobSnapshot, pageId);
    if (!state.exists) return { outcome: "noJob", batches: 0 };
    if (!pageSnapshot.exists) {
      // The Page is gone (account deletion): nothing is carried any more.
      await jobRef.delete();
      logger.info("pages follow carry-over completed", completionLine("noPage",
        state.job ?? { scanned: 0, carried: 0, skipped: 0, evicted: 0 }));
      return { outcome: "noPage", batches: 0 };
    }
    let job = state.job;
    if (state.malformed) {
      logger.error("pages follow carry-over job malformed", {});
      const { now } = timing();
      job = pageFollowCarryJobDocument({ pageId, now, nextAttemptAt: now });
      await jobRef.set(job);
    }
    let afterId = job.afterId;
    let attempts = job.attempts;
    const counts = countsOf(job);
    let batches = 0;
    try {
      while (batches < maxBatches) {
        // The Page can go (account deletion's content stage) while a run is
        // in flight: re-check it before every further batch (one read), so
        // no more hints naming a Page that no longer exists are written.
        if (batches > 0 && !(await firestore.doc(`pages/${pageId}`).get()).exists) {
          await jobRef.delete();
          logger.info("pages follow carry-over completed", completionLine("noPage", counts));
          return { outcome: "noPage", batches };
        }
        let query = PAGE_FOLLOW_CARRY_QUERIES.followers(firestore, pageId);
        if (afterId !== null) query = query.startAfter(afterId);
        const page = await query.limit(limits.batchSize).get();
        batches += 1;
        const followerIds = page.docs.map((document) => document.id);
        const outcomes = await mapBounded(followerIds, limits.concurrency,
          (followerId) => carryFollower(pageId, followerId));
        let evicted = 0;
        for (const outcome of outcomes) {
          counts.scanned += 1;
          if (outcome === "carry" || outcome === "carryEvict") counts.carried += 1;
          else if (outcome !== "already") counts.skipped += 1;
          if (outcome === "carryEvict") evicted += 1;
        }
        counts.evicted += evicted;
        if (evicted > 0) logger.warn("pages follow carry-over index full", { count: evicted });
        if (page.size < limits.batchSize) {
          await jobRef.delete();
          logger.info("pages follow carry-over completed", completionLine("completed", counts));
          return { outcome: "completed", batches };
        }
        afterId = followerIds[followerIds.length - 1];
        const { now } = timing();
        const saved = await saveJob(jobRef, {
          afterId,
          ...counts,
          attempts: 0,
          nextAttemptAt: now,
          updatedAt: now,
        });
        if (!saved) return { outcome: "vanished", batches };
        attempts = 0;
      }
      return { outcome: "progress", batches };
    } catch (error) {
      await recordFailure(jobRef, attempts, error);
      return { outcome: "retry", batches };
    }
  }

  /**
   * The pagesMaintenance slice: due jobs (nextAttemptAt <= now), at most
   * `jobsPerRun` of them and `runBatches` follower pages in total.
   */
  async function processDueJobs() {
    const { now } = timing();
    const due = await PAGE_FOLLOW_CARRY_QUERIES.dueJobs(firestore, now)
      .limit(limits.jobsPerRun).get();
    const line = {
      processed: 0,
      completed: 0,
      retried: 0,
      batches: 0,
      hasMore: due.size === limits.jobsPerRun,
    };
    let budget = limits.runBatches;
    for (const document of due.docs) {
      if (budget <= 0) {
        line.hasMore = true;
        break;
      }
      let result;
      try {
        result = await runJob(document.id, { maxBatches: budget });
      } catch (error) {
        // A failure before runJob's own retry handling (reading the job and
        // its Page, deleting a job whose Page is gone, resetting a malformed
        // one) is isolated to that job: it backs off and alerts like any
        // other, and the next due job still runs.
        const attempts = document.data()?.attempts;
        await recordFailure(
          pageFollowCarryJobReference(firestore, document.id),
          nonNegativeSafeInteger(attempts) ? attempts : 0,
          error,
        );
        result = { outcome: "retry", batches: 0 };
      }
      budget -= result.batches;
      line.batches += result.batches;
      line.processed += 1;
      if (result.outcome === "completed" || result.outcome === "noPage") line.completed += 1;
      if (result.outcome === "retry") line.retried += 1;
    }
    return line;
  }

  return Object.freeze({ carryFollower, processDueJobs, runJob });
}

module.exports = {
  PAGE_FOLLOW_CARRY_COLLECTION,
  PAGE_FOLLOW_CARRY_HANDOFF_MS,
  PAGE_FOLLOW_CARRY_JOB_KEYS,
  PAGE_FOLLOW_CARRY_LIMITS,
  PAGE_FOLLOW_CARRY_OUTCOMES,
  PAGE_FOLLOW_CARRY_QUERIES,
  PAGE_FOLLOW_CARRY_STUCK_ATTEMPTS,
  canonicalPageFollowCarryJob,
  carryDecision,
  createPagesFollowCarryService,
  followerAccountGone,
  pageFollowCarryJobDocument,
  pageFollowCarryJobReference,
};

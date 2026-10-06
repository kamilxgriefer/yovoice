// pagesMaintenance (ADR-233 §2.12): the one scheduled worker of Premium Pages,
// every 10 minutes, europe-west1, one instance. Each slice is bounded and
// resumable, and a failing slice never stops the next one:
//
//   1. reservations  expired pagePostMediaReservations: CLAIM (status
//                    "expiring", which also closes the Storage-rules upload
//                    window), delete the object generation-guarded, then
//                    delete the reservation and the owner's lease if it is
//                    the same expired set. The message-media order
//                    (servers/message_media.js).
//   2. deletionJobs  pagePostMediaDeletionJobs with heldBy == null that are
//                    due: delete the object generation-guarded, then the
//                    job; a failure backs off. A held job (report evidence)
//                    is never touched here.
//   3. cleanupJobs   pagePostCleanupJobs: the likes and comments of a
//                    HARD-deleted post, in batches of 400. Each comment's
//                    `pagePostComment` bell row on the Page owner is retired
//                    first (package B4), so no row outlives its comment.
//   4. evidenceRetention  (package B5) tombstones a DELETED account left
//                    because a report was open (§2.11), and every tombstone
//                    an owner's delete left (audit 2026-09-28): due when the
//                    last report resolved (moderation sets purgeAt to now) or
//                    90 days passed. The post, its likes and comments and its
//                    media (jobs released) go.
//   4b. pageDeletion (ADR-236, pages/deletion.js) an owner's Page deletion
//                    and "delete all posts": the 3-day reminder bell row, the
//                    purge of a deletion whose 30 days passed (or that the
//                    owner asked to run now): posts, follower edges, storage,
//                    records, then the Page with its memory row; due clear
//                    jobs; expired memory rows. BEFORE the job slices, so the
//                    media and cleanup jobs it queues go in the same run.
//                    Bounded per record and per run, cursor-resumable.
//   5. lapse         (package B5) hourly, cursor-resumable, <= 5 x 200 Pages:
//                    the §2.8 transitions (pages/lapse_service.js), each in
//                    its own re-deriving transaction.
//   6. followCarry   (ADR-234) pageFollowCarryJobs that are due: an
//                    account's EXISTING followers carried over to its new
//                    Page (pageFollowIndex hints only; pages/follow_carry.js),
//                    <= 10 x 100 followers a run across <= 5 jobs,
//                    cursor-resumable, backing off on failure. AFTER lapse:
//                    its follower transactions can take a while, and the
//                    lapse sweep is the backstop that must never wait on
//                    them. It does not read appConfig/pagesV1: it only
//                    writes hints, and every reader re-checks the Page, the
//                    edge and blocks.
//   7. orphans       once a day (cursor-resumable, <= 1000 objects a run):
//                    page_posts/ objects older than 1 h that no post
//                    references, no reservation covers and no job owns.
//
// Only the lapse slice reads appConfig/pagesV1, for `lapseEnabled` (missing
// or malformed = downgrades frozen, restores still run). Every other slice
// only removes what is already unreferenced, expired, released or queued,
// or (followCarry) writes follow hints that grant nothing by themselves, so
// the worker keeps running with the kill switch on (an owner's delete is a
// safety action, and so is deleting a whole Page). With nothing to do it
// costs one empty query per slice (four for pageDeletion).

const { Timestamp } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const defaultLogger = require("firebase-functions/logger");

const { timestampMillis, transactionGetAll } = require("../integrity/guards");
const {
  GENERATION_PATTERN,
  canonicalPageMediaDeletionJob,
  canonicalPageMediaReservation,
  canonicalPagePostCleanupJob,
  pageJobBackoffMs,
  parsePagePostObjectName,
} = require("./media_contract");
const { isMissingObject } = require("./media_storage");
const { PAGE_COMMENT_ID_PATTERN } = require("./contract");
const { pageCommentNotificationId } = require("./engagement_contract");
const { createPagesAccountDeletion } = require("./account_deletion");
const { createPagesLapseService } = require("./lapse_service");
const { createPagesFollowCarryService } = require("./follow_carry");
const { createPagesDeletionService } = require("./deletion");

const REGION = "europe-west1";
const RESERVATIONS = "pagePostMediaReservations";
const LEASES = "pagePostMediaLeases";
const DELETION_JOBS = "pagePostMediaDeletionJobs";
const CLEANUP_JOBS = "pagePostCleanupJobs";
const MAINTENANCE_STATE = "pageMaintenanceState";
const ORPHAN_STATE_ID = "orphanSweep";
const CLEANUP_BATCH = 400;
const CLEANUP_ROUNDS = 5;
const ORPHAN_MIN_AGE_MS = 60 * 60 * 1000;
const ORPHAN_SWEEP_EVERY_MS = 24 * 60 * 60 * 1000;
const ORPHAN_PAGE_SIZE = 1000;
const GET_ALL_CHUNK = 300;

const PAGES_MAINTENANCE_LIMITS = Object.freeze({
  reservations: 50,
  deletionJobs: 50,
  cleanupJobs: 20,
  evidenceRetention: 20,
  orphans: ORPHAN_PAGE_SIZE,
});

// The exact worker query shapes. The index smoke and the emulator index test
// run these same builders (ADR-007).
const PAGES_MAINTENANCE_QUERIES = Object.freeze({
  // Single-field (automatic) index on expiresAt.
  expiredReservations: (db, now) => db.collection(RESERVATIONS)
    .where("expiresAt", "<=", now)
    .orderBy("expiresAt", "asc"),
  // pagePostMediaDeletionJobs (heldBy ASC, nextAttemptAt ASC)
  dueDeletionJobs: (db, now) => db.collection(DELETION_JOBS)
    .where("heldBy", "==", null)
    .where("nextAttemptAt", "<=", now)
    .orderBy("nextAttemptAt", "asc"),
  // Single-field (automatic) index on nextAttemptAt.
  dueCleanupJobs: (db, now) => db.collection(CLEANUP_JOBS)
    .where("nextAttemptAt", "<=", now)
    .orderBy("nextAttemptAt", "asc"),
  // Single-field (automatic) index on postId; the post is already gone.
  postComments: (db, postId) => db.collection("pagePostComments")
    .where("postId", "==", postId),
  postLikes: (db, postId) => db.collection(`pagePosts/${postId}/likes`),
  // Single-field (automatic) index on purgeAt.
  dueEvidenceRetention: (db, now) => db.collection("pageEvidenceRetention")
    .where("purgeAt", "<=", now)
    .orderBy("purgeAt", "asc"),
});

function errorCode(error) {
  return typeof error?.code === "string" || Number.isSafeInteger(error?.code) ? error.code : null;
}

function isGenerationMismatch(error) {
  return error?.code === 412 || error?.code === "412";
}

function createPagesMaintenanceService({
  firestore,
  storage,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  limits = PAGES_MAINTENANCE_LIMITS,
  lapse = null,
  deletion = null,
  followCarry = null,
  pageDeletion = null,
}) {
  if (!firestore?.doc || !storage?.deleteObject || !storage?.getMetadata ||
      !storage?.listObjects || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, storage, Timestamp and clock are required.");
  }

  function timing() {
    const nowMs = clock();
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  const lapseService = lapse ?? createPagesLapseService({
    firestore, TimestampImpl, clock, logger,
  });
  const deletionService = deletion ?? createPagesAccountDeletion({
    db: firestore, TimestampImpl, clock, logger,
  });
  const followCarryService = followCarry ?? createPagesFollowCarryService({
    firestore, TimestampImpl, clock, logger,
  });
  // ADR-236: the same stages and the same Storage adapter this worker uses.
  const pageDeletionService = pageDeletion ?? createPagesDeletionService({
    firestore, storage, stages: deletionService, TimestampImpl, clock, logger,
  });

  // ------------------------------------------------ evidence retention

  async function purgeDueEvidence({ limit = limits.evidenceRetention } = {}) {
    const { now } = timing();
    const page = await PAGES_MAINTENANCE_QUERIES.dueEvidenceRetention(firestore, now)
      .limit(limit).get();
    const line = { processed: page.size, purged: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      if (await deletionService.purgeRetainedPost(document.id)) line.purged += 1;
    }
    return line;
  }

  async function getAllChunked(references) {
    const out = [];
    for (let start = 0; start < references.length; start += GET_ALL_CHUNK) {
      const slice = references.slice(start, start + GET_ALL_CHUNK);
      if (slice.length > 0) out.push(...await firestore.getAll(...slice));
    }
    return out;
  }

  // ----------------------------------------------------- deletion jobs

  /**
   * Deletes the object of one due, unheld job and then the job. Safe to run
   * concurrently with the worker (the delete is idempotent and
   * generation-guarded). {deleted, held, retry}.
   */
  async function processMediaDeletionJob(jobId) {
    const jobRef = firestore.doc(`${DELETION_JOBS}/${jobId}`);
    const job = canonicalPageMediaDeletionJob(await jobRef.get());
    if (job === null) return { deleted: true, held: false, retry: false };
    if (job.heldBy !== null) return { deleted: false, held: true, retry: false };
    try {
      await storage.deleteObject(job.storagePath, { generation: job.generation });
    } catch (error) {
      // 412: the live object at this path is a DIFFERENT generation, which
      // this job never owned. It is left alone and the job is finished.
      if (!isGenerationMismatch(error)) {
        const { nowMs } = timing();
        await firestore.runTransaction(async (transaction) => {
          const current = canonicalPageMediaDeletionJob(await transaction.get(jobRef));
          if (current === null || current.heldBy !== null) return;
          transaction.update(jobRef, {
            attempts: current.attempts + 1,
            nextAttemptAt: TimestampImpl.fromMillis(nowMs + pageJobBackoffMs(current.attempts)),
          });
        });
        logger.warn("pages media deletion retry", {
          attempts: job.attempts + 1,
          code: errorCode(error),
        });
        return { deleted: false, held: false, retry: true };
      }
      logger.warn("pages media deletion generation superseded", {});
    }
    await firestore.runTransaction(async (transaction) => {
      const current = canonicalPageMediaDeletionJob(await transaction.get(jobRef));
      if (current === null || current.heldBy !== null ||
          current.generation !== job.generation || current.storagePath !== job.storagePath) {
        return;
      }
      transaction.delete(jobRef);
    });
    return { deleted: true, held: false, retry: false };
  }

  async function processDeletionJobs({ limit = limits.deletionJobs } = {}) {
    const { now } = timing();
    const page = await PAGES_MAINTENANCE_QUERIES.dueDeletionJobs(firestore, now).limit(limit).get();
    const line = { processed: page.size, deleted: 0, retried: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      const outcome = await processMediaDeletionJob(document.id);
      if (outcome.deleted) line.deleted += 1;
      if (outcome.retry) line.retried += 1;
    }
    return line;
  }

  // ------------------------------------------------------ cleanup jobs

  async function deleteQueryBatch(query) {
    const snapshot = await query.limit(CLEANUP_BATCH).get();
    if (snapshot.empty) return 0;
    const batch = firestore.batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
    return snapshot.size;
  }

  // One batch of a hard-deleted post's comments. The owner's bell rows go
  // FIRST, in their own batch: if the comment batch then fails, the retry
  // finds the same comments and re-deletes the (already gone) rows, so no
  // row can outlive its comment. The row path is built from the job's
  // pageId, never from a comment's own field.
  async function deleteCommentBatch(postId, pageId) {
    const snapshot = await PAGES_MAINTENANCE_QUERIES.postComments(firestore, postId)
      .limit(CLEANUP_BATCH).get();
    if (snapshot.empty) return 0;
    const rows = firestore.batch();
    snapshot.docs.forEach((document) => {
      if (PAGE_COMMENT_ID_PATTERN.test(document.id)) {
        rows.delete(firestore.doc(`users/${pageId}/notifications/${pageCommentNotificationId(document.id)}`));
      }
    });
    await rows.commit();
    const comments = firestore.batch();
    snapshot.docs.forEach((document) => comments.delete(document.ref));
    await comments.commit();
    return snapshot.size;
  }

  /**
   * Deletes the likes and comments of a hard-deleted post, at most
   * CLEANUP_ROUNDS x 400 of each per call. {done}.
   */
  async function processPostCleanupJob(postId, { rounds = CLEANUP_ROUNDS } = {}) {
    const jobRef = firestore.doc(`${CLEANUP_JOBS}/${postId}`);
    const job = canonicalPagePostCleanupJob(await jobRef.get());
    if (job === null) return { done: true };
    const postSnapshot = await firestore.doc(`pagePosts/${postId}`).get();
    if (postSnapshot.exists) {
      // Never delete the comments of a post that exists (a tombstone keeps
      // them as evidence). A hard delete removed the post first.
      logger.error("pages post cleanup found a live post", {});
      await jobRef.delete();
      return { done: true };
    }
    try {
      for (let round = 0; round < rounds; round += 1) {
        const likes = await deleteQueryBatch(PAGES_MAINTENANCE_QUERIES.postLikes(firestore, postId));
        const comments = await deleteCommentBatch(postId, job.pageId);
        if (likes < CLEANUP_BATCH && comments < CLEANUP_BATCH) {
          const [finalLikes, finalComments] = await Promise.all([
            PAGES_MAINTENANCE_QUERIES.postLikes(firestore, postId).limit(1).get(),
            PAGES_MAINTENANCE_QUERIES.postComments(firestore, postId).limit(1).get(),
          ]);
          if (finalLikes.empty && finalComments.empty) {
            await jobRef.delete();
            return { done: true };
          }
        }
      }
      // More than one call's worth: due again on the next run.
      await jobRef.update({ nextAttemptAt: timing().now });
      return { done: false };
    } catch (error) {
      const { nowMs } = timing();
      await jobRef.update({
        attempts: job.attempts + 1,
        nextAttemptAt: TimestampImpl.fromMillis(nowMs + pageJobBackoffMs(job.attempts)),
      }).catch(() => {});
      logger.warn("pages post cleanup retry", { attempts: job.attempts + 1, code: errorCode(error) });
      return { done: false };
    }
  }

  async function processCleanupJobs({ limit = limits.cleanupJobs } = {}) {
    const { now } = timing();
    const page = await PAGES_MAINTENANCE_QUERIES.dueCleanupJobs(firestore, now).limit(limit).get();
    const line = { processed: page.size, done: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      const outcome = await processPostCleanupJob(document.id);
      if (outcome.done) line.done += 1;
    }
    return line;
  }

  // ------------------------------------------------------ reservations

  async function currentGeneration(storagePath) {
    try {
      const metadata = await storage.getMetadata(storagePath);
      const generation = String(metadata?.generation ?? "");
      return GENERATION_PATTERN.test(generation) ? generation : null;
    } catch (error) {
      if (isMissingObject(error)) return null;
      throw error;
    }
  }

  async function expireReservations({ limit = limits.reservations } = {}) {
    const { nowMs, now } = timing();
    const page = await PAGES_MAINTENANCE_QUERIES.expiredReservations(firestore, now)
      .limit(limit).get();
    const line = { processed: page.size, expired: 0, malformed: 0, hasMore: page.size === limit };
    for (const document of page.docs) {
      if (canonicalPageMediaReservation(document) === null) {
        line.malformed += 1;
        continue;
      }
      const claimed = await firestore.runTransaction(async (transaction) => {
        const value = canonicalPageMediaReservation(await transaction.get(document.ref));
        if (value === null || value.expiresAtMs > nowMs) return null;
        if (value.status === "uploading") transaction.update(document.ref, { status: "expiring" });
        return value;
      });
      if (claimed === null) continue;
      // After the claim no upload can land (storage.rules needs "uploading"
      // and a future expiresAt), so the generation read here is final.
      const generation = await currentGeneration(claimed.storagePath);
      if (generation !== null) {
        await storage.deleteObject(claimed.storagePath, { generation });
      }
      await firestore.runTransaction(async (transaction) => {
        const leaseRef = firestore.doc(`${LEASES}/${claimed.ownerId}`);
        const [current, lease] = await transactionGetAll(transaction, document.ref, leaseRef);
        const value = canonicalPageMediaReservation(current);
        if (value !== null && value.status === "expiring") transaction.delete(document.ref);
        const leaseData = lease.exists ? (lease.data() ?? {}) : null;
        const leaseExpiresAtMs = timestampMillis(leaseData?.expiresAt);
        if (leaseData !== null && leaseData.postId === claimed.postId &&
            leaseData.ownerId === claimed.ownerId &&
            (leaseExpiresAtMs === null || leaseExpiresAtMs <= nowMs)) {
          transaction.delete(leaseRef);
        }
      });
      line.expired += 1;
    }
    if (line.malformed > 0) logger.error("pages malformed reservation", { count: line.malformed });
    return line;
  }

  // ----------------------------------------------------------- orphans

  function referencedBy(postSnapshot, name, mediaId) {
    if (!postSnapshot?.exists) return false;
    const media = postSnapshot.data()?.media;
    return Array.isArray(media) &&
      media.some((entry) => entry?.mediaId === mediaId || entry?.storagePath === name);
  }

  /**
   * One page (<= 1000) of the daily page_posts/ sweep. Runs when a pass is
   * in progress (a stored page token) or the last pass finished >= 24 h ago.
   */
  async function sweepOrphans({ maxResults = limits.orphans, force = false } = {}) {
    const { nowMs, now } = timing();
    const stateRef = firestore.doc(`${MAINTENANCE_STATE}/${ORPHAN_STATE_ID}`);
    const stateSnapshot = await stateRef.get();
    const state = stateSnapshot.exists ? (stateSnapshot.data() ?? {}) : {};
    const pageToken = typeof state.pageToken === "string" && state.pageToken.length > 0
      ? state.pageToken
      : null;
    const lastCompletedMs = timestampMillis(state.lastCompletedAt);
    if (!force && pageToken === null && lastCompletedMs !== null &&
        nowMs - lastCompletedMs < ORPHAN_SWEEP_EVERY_MS) {
      return { ran: false };
    }
    const listing = await storage.listObjects({ maxResults, pageToken });
    const objects = Array.isArray(listing?.objects) ? listing.objects : [];
    const candidates = [];
    let young = 0;
    for (const object of objects) {
      if (typeof object?.name !== "string" || !object.name.startsWith("page_posts/") ||
          !GENERATION_PATTERN.test(object.generation ?? "")) {
        continue;
      }
      if (!Number.isFinite(object.timeCreatedMs) || nowMs - object.timeCreatedMs < ORPHAN_MIN_AGE_MS) {
        young += 1;
        continue;
      }
      candidates.push({ ...object, parsed: parsePagePostObjectName(object.name) });
    }
    const parsed = candidates.filter((candidate) => candidate.parsed !== null);
    const postIds = [...new Set(parsed.map((candidate) => candidate.parsed.postId))];
    const snapshots = await getAllChunked([
      ...postIds.map((postId) => firestore.doc(`pagePosts/${postId}`)),
      ...parsed.map((candidate) => firestore.doc(`${RESERVATIONS}/${candidate.parsed.mediaId}`)),
      ...parsed.map((candidate) => firestore.doc(`${DELETION_JOBS}/${candidate.parsed.mediaId}`)),
    ]);
    const posts = new Map(postIds.map((postId, index) => [postId, snapshots[index]]));
    const reservations = snapshots.slice(postIds.length, postIds.length + parsed.length);
    const jobs = snapshots.slice(postIds.length + parsed.length);
    let deleted = 0;
    let kept = 0;
    for (const candidate of candidates) {
      if (candidate.parsed !== null) {
        const index = parsed.indexOf(candidate);
        if (referencedBy(posts.get(candidate.parsed.postId), candidate.name,
          candidate.parsed.mediaId) || reservations[index].exists || jobs[index].exists) {
          kept += 1;
          continue;
        }
      }
      // Unparsable names cannot be referenced by any post (clients can only
      // create reserved names); unreferenced ones are orphans.
      await storage.deleteObject(candidate.name, { generation: candidate.generation });
      deleted += 1;
    }
    const nextPageToken = typeof listing?.nextPageToken === "string" &&
      listing.nextPageToken.length > 0 ? listing.nextPageToken : null;
    await stateRef.set({
      schemaVersion: 1,
      pageToken: nextPageToken,
      lastCompletedAt: nextPageToken === null ? now : (state.lastCompletedAt ?? null),
      updatedAt: now,
    });
    return { ran: true, listed: objects.length, deleted, kept, young, hasMore: nextPageToken !== null };
  }

  // --------------------------------------------------------------- run

  async function run() {
    const slices = [
      ["reservations", () => expireReservations()],
      // Before the job slices, so released media goes in the same run.
      ["evidenceRetention", () => purgeDueEvidence()],
      // Before the job slices too: a purged Page's media and post cleanup
      // jobs are worked off in this run (ADR-236).
      ["pageDeletion", () => pageDeletionService.sweep()],
      ["deletionJobs", () => processDeletionJobs()],
      ["cleanupJobs", () => processCleanupJobs()],
      ["lapse", () => lapseService.sweep()],
      // After the lapse backstop: bounded, but its follower transactions
      // must never delay a lapse transition (ADR-234).
      ["followCarry", () => followCarryService.processDueJobs()],
      ["orphans", () => sweepOrphans()],
    ];
    const results = {};
    for (const [name, slice] of slices) {
      try {
        results[name] = await slice();
      } catch (error) {
        logger.error("pages maintenance slice failed", { slice: name, code: errorCode(error) });
        results[name] = { failed: true };
      }
    }
    logger.info("pages maintenance", results);
    return results;
  }

  return Object.freeze({
    expireReservations,
    purgeDueEvidence,
    processCleanupJobs,
    processDeletionJobs,
    processMediaDeletionJob,
    processPostCleanupJob,
    run,
    sweepOrphans,
  });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    const { defaultPagesMediaDependencies } = require("./media_runtime");
    defaultService = createPagesMaintenanceService({
      firestore: db,
      storage: defaultPagesMediaDependencies().storage,
    });
  }
  return defaultService;
}

const pagesMaintenance = onSchedule(
  {
    region: REGION,
    schedule: "every 10 minutes",
    timeZone: "Etc/UTC",
    memory: "512MiB",
    timeoutSeconds: 300,
    maxInstances: 1,
  },
  async () => {
    await service().run();
  },
);

module.exports = {
  CLEANUP_BATCH,
  MAINTENANCE_STATE,
  ORPHAN_MIN_AGE_MS,
  ORPHAN_SWEEP_EVERY_MS,
  PAGES_MAINTENANCE_LIMITS,
  PAGES_MAINTENANCE_QUERIES,
  createPagesMaintenanceService,
  pagesMaintenance,
};

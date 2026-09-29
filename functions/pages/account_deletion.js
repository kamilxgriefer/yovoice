// Premium Pages in the ADR-206 account-deletion pipeline (ADR-233 §2.11).
// account/stages.js calls these from its stages; each call is bounded and
// idempotent, and advances only after its own work is empty.
//
//   content   1. pages/{uid} is deleted together with its pageVisibility/v1
//               entry (one transaction: every status transition writes both).
//             2. pagePosts where authorId == uid, a page at a time:
//                - no open report, no evidenceHold, not held: HARD delete, a
//                  cleanup job for its likes and comments, and an UNHELD
//                  deletion job per media object;
//                - under review (evidenceHold or an open report): kept
//                  as a TOMBSTONE (status "deleted", moderationEvidence) with
//                  HELD media jobs and a pageEvidenceRetention row, purged
//                  when the report resolves or after 90 days, whichever comes
//                  first (pagesMaintenance). Spec decision; counsel to confirm.
//             3. pagePostComments where authorId == uid: each deleted with its
//                post's commentCount and the Page owner's bell row.
//   storage   The account's page_posts/{uid}/ objects through the rows that
//             name them (unheld deletion jobs, open reservations), each by
//             exact path and generation; objects named by a HELD job are
//             skipped. Anything unnamed is an orphan the daily sweep removes.
//   records   pagePostBudgets rows (by pageId). pageFollowIndex/{uid},
//             pagePostMediaLeases/{uid}, pageAdultRefusals/{uid} and
//             pageFollowCarryJobs/{uid} (ADR-234) are in the stages'
//             uid-keyed document list. The carry-over worker also deletes a
//             job whose Page the `content` stage removed, and never writes
//             a follower's index once the `social` stage removed the edges.
//
// Likes the account gave stay (as in ADR-230); reports it filed are re-keyed
// by the existing records step; reports ABOUT its content keep their
// snapshots.

const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const defaultLogger = require("firebase-functions/logger");

const { timestampMillis, transactionGetAll } = require("../integrity/guards");
const { PAGE_COMMENT_ID_PATTERN } = require("./contract");
const { pageCommentNotificationId, pageCommentSourcePath } = require("./engagement_contract");
const {
  GENERATION_PATTERN,
  PAGE_MODERATION_HOLD,
  canonicalPageMediaDeletionJob,
  pageMediaDeletionJob,
  pagePostCleanupJob,
  pagePostEvidenceFingerprint,
  pagePostOpenReports,
  parsePagePostObjectName,
} = require("./media_contract");
const { canonicalPageCommentData, canonicalPagePostData } = require("./post_contract");
const {
  PAGE_EVIDENCE_RETENTION_MS,
  canonicalPageEvidenceRetention,
  pageEvidenceRetentionDocument,
} = require("./report_contract");
const { applyPageVisibilityInTransaction, pageVisibilityReference } = require("./visibility");

const PAGES_DELETION_LIMITS = Object.freeze({ posts: 10, comments: 25, storage: 25, records: 200 });

// The exact deletion query shapes (indexes: pagePosts authorId ASC,
// createdAt DESC, __name__ DESC; pagePostComments the same;
// pagePostMediaDeletionJobs heldBy ASC, storagePath ASC; single-field
// ownerId / pageId). The index smoke and the emulator index test run these
// same builders (ADR-007).
const PAGES_DELETION_QUERIES = Object.freeze({
  authorPosts: (db, uid) => db.collection("pagePosts")
    .where("authorId", "==", uid)
    .orderBy("createdAt", "desc")
    .orderBy(FieldPath.documentId(), "desc"),
  authorComments: (db, uid) => db.collection("pagePostComments")
    .where("authorId", "==", uid)
    .orderBy("createdAt", "desc")
    .orderBy(FieldPath.documentId(), "desc"),
  unheldJobsUnder: (db, uid) => db.collection("pagePostMediaDeletionJobs")
    .where("heldBy", "==", null)
    .where("storagePath", ">=", `page_posts/${uid}/`)
    .where("storagePath", "<", `page_posts/${uid}0`)
    .orderBy("storagePath", "asc"),
  ownerReservations: (db, uid) => db.collection("pagePostMediaReservations")
    .where("ownerId", "==", uid),
  pageBudgets: (db, uid) => db.collection("pagePostBudgets")
    .where("pageId", "==", uid),
});

function incompleteStorage(message) {
  const error = new Error(message);
  error.code = "storage-cleanup-incomplete";
  return error;
}

function isGenerationMismatch(error) {
  return error?.code === 412 || error?.code === "412";
}

function createPagesAccountDeletion({
  db,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  limits = PAGES_DELETION_LIMITS,
}) {
  if (!db?.doc) throw new TypeError("A Firestore database is required.");

  function timing() {
    const nowMs = clock();
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  // ---------------------------------------------------------- content

  async function removePage(uid) {
    const { now } = timing();
    const pageRef = db.doc(`pages/${uid}`);
    return db.runTransaction(async (transaction) => {
      const [pageSnapshot, visibilitySnapshot] = await transactionGetAll(
        transaction, pageRef, pageVisibilityReference(db),
      );
      applyPageVisibilityInTransaction(transaction, {
        db, snapshot: visibilitySnapshot, pageId: uid, page: null, now, logger, safetyAction: true,
      });
      if (!pageSnapshot.exists) return false;
      transaction.delete(pageRef);
      return true;
    });
  }

  /// One post of the account: hard delete, or a retained tombstone.
  async function retirePost(uid, postId) {
    const { nowMs, now } = timing();
    const postRef = db.doc(`pagePosts/${postId}`);
    return db.runTransaction(async (transaction) => {
      const [postSnapshot, reportsSnapshot, retentionSnapshot] = await transactionGetAll(
        transaction,
        postRef,
        db.doc(`pagePostOpenReports/${postId}`),
        db.doc(`pageEvidenceRetention/${postId}`),
      );
      if (!postSnapshot.exists) return "gone";
      const post = canonicalPagePostData(postSnapshot);
      if (post === null || post.authorId !== uid) {
        // Nothing here can be trusted to name media; the doc goes, and any
        // bytes it named are orphans for the daily sweep.
        logger.error("pages deletion removed a malformed post", {});
        transaction.delete(postRef);
        return "malformed";
      }
      const reports = pagePostOpenReports(reportsSnapshot, postId);
      // Only an OPEN report (or its evidence hold) keeps a post: a held
      // post whose reports all closed has nothing left to release its jobs.
      const underReview = post.evidenceHold === true || reports.count > 0;
      if (underReview) {
        if (post.status !== "deleted") {
          transaction.update(postRef, {
            status: "deleted",
            deletedAt: now,
            moderationEvidence: {
              evidenceVersion: 1,
              metadataFingerprint: pagePostEvidenceFingerprint(post),
            },
          });
        }
        const heldBy = reports.lastReportId ?? PAGE_MODERATION_HOLD;
        for (const entry of post.media) {
          transaction.set(db.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`), pageMediaDeletionJob({
            storagePath: entry.storagePath,
            generation: entry.generation,
            reason: "accountDeleted",
            heldBy,
            now,
          }));
        }
        if (canonicalPageEvidenceRetention(retentionSnapshot) === null) {
          transaction.set(db.doc(`pageEvidenceRetention/${postId}`), pageEvidenceRetentionDocument({
            postId,
            pageId: uid,
            now,
            purgeAt: TimestampImpl.fromMillis(nowMs + PAGE_EVIDENCE_RETENTION_MS),
          }));
        }
        return "retained";
      }
      transaction.delete(postRef);
      transaction.set(db.doc(`pagePostCleanupJobs/${postId}`), pagePostCleanupJob({
        postId, pageId: uid, reason: "accountDeleted", now,
      }));
      for (const entry of post.media) {
        transaction.set(db.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`), pageMediaDeletionJob({
          storagePath: entry.storagePath,
          generation: entry.generation,
          reason: "accountDeleted",
          heldBy: null,
          now,
        }));
      }
      if (reportsSnapshot.exists) transaction.delete(reportsSnapshot.ref);
      if (retentionSnapshot.exists) transaction.delete(retentionSnapshot.ref);
      return "deleted";
    });
  }

  async function processPosts(uid, after) {
    let query = PAGES_DELETION_QUERIES.authorPosts(db, uid).limit(limits.posts);
    if (after && Number.isSafeInteger(after.t) && typeof after.id === "string") {
      query = query.startAfter(TimestampImpl.fromMillis(after.t), after.id);
    }
    const snapshot = await query.get();
    const counts = { deleted: 0, retained: 0, malformed: 0 };
    let last = null;
    for (const document of snapshot.docs) {
      const outcome = await retirePost(uid, document.id);
      if (outcome in counts) counts[outcome] += 1;
      const createdAtMs = timestampMillis(document.data()?.createdAt);
      if (createdAtMs !== null) last = { t: createdAtMs, id: document.id };
    }
    return {
      done: snapshot.size < limits.posts,
      after: last ?? after ?? null,
      counts,
    };
  }

  /// One comment the account wrote: gone with its counter and bell row.
  async function removeComment(commentId) {
    const commentRef = db.doc(`pagePostComments/${commentId}`);
    return db.runTransaction(async (transaction) => {
      const [commentSnapshot] = await transactionGetAll(transaction, commentRef);
      if (!commentSnapshot.exists) return false;
      const comment = canonicalPageCommentData(commentSnapshot);
      if (comment === null) {
        logger.error("pages deletion removed a malformed comment", {});
        transaction.delete(commentRef);
        return true;
      }
      const postRef = db.doc(`pagePosts/${comment.postId}`);
      const bellRef = db.doc(
        `users/${comment.pageId}/notifications/${pageCommentNotificationId(comment.commentId)}`,
      );
      const [postSnapshot, bellSnapshot] = await transactionGetAll(transaction, postRef, bellRef);
      transaction.delete(commentRef);
      const post = canonicalPagePostData(postSnapshot);
      if (post !== null && post.pageId === comment.pageId) {
        if (Number.isSafeInteger(post.commentCount) && post.commentCount > 0) {
          transaction.update(postRef, { commentCount: post.commentCount - 1 });
        } else {
          logger.error("pages comment count underflow", {});
        }
      }
      const bell = bellSnapshot.exists ? (bellSnapshot.data() ?? {}) : null;
      if (bell !== null && bell.type === "pagePostComment" &&
          bell.sourcePath === pageCommentSourcePath(comment.commentId)) {
        transaction.delete(bellRef);
      }
      return true;
    });
  }

  async function processComments(uid) {
    const snapshot = await PAGES_DELETION_QUERIES.authorComments(db, uid)
      .limit(limits.comments).get();
    let removed = 0;
    for (const document of snapshot.docs) {
      if (!PAGE_COMMENT_ID_PATTERN.test(document.id)) {
        await document.ref.delete();
        removed += 1;
        continue;
      }
      if (await removeComment(document.id)) removed += 1;
    }
    return { done: snapshot.size < limits.comments, removed };
  }

  /**
   * The content stage's Pages part. `cursor` is {step, after?}: 0 the Page,
   * 1 the posts (keyset-paged by createdAt, id), 2 the comments. Returns
   * {done, cursor, details}.
   */
  async function runContent(uid, cursor = null) {
    let step = Number.isSafeInteger(cursor?.step) ? cursor.step : 0;
    const details = {};
    if (step === 0) {
      details.pageDeleted = await removePage(uid);
      step = 1;
    }
    if (step === 1) {
      const posts = await processPosts(uid, cursor?.step === 1 ? cursor.after : null);
      details.posts = posts.counts;
      if (!posts.done) return { done: false, cursor: { step: 1, after: posts.after }, details };
      step = 2;
    }
    const comments = await processComments(uid);
    details.comments = comments.removed;
    if (!comments.done) return { done: false, cursor: { step: 2 }, details };
    return { done: true, cursor: null, details };
  }

  // ---------------------------------------------------------- storage

  /**
   * One bounded page of the account's Page media: every object an UNHELD
   * deletion job or an open reservation names, by exact path (re-parsed and
   * checked against the uid) and, for a job, exact generation. A row goes
   * only after its object. Held jobs are never touched. {removed, more}.
   */
  async function sweepStorage(uid, bucket) {
    let removed = 0;
    const [jobs, reservations] = await Promise.all([
      PAGES_DELETION_QUERIES.unheldJobsUnder(db, uid).limit(limits.storage).get(),
      PAGES_DELETION_QUERIES.ownerReservations(db, uid).limit(limits.storage).get(),
    ]);
    for (const document of jobs.docs) {
      let job;
      try {
        job = canonicalPageMediaDeletionJob(document);
      } catch {
        throw incompleteStorage("A Page media deletion job is malformed.");
      }
      const parsed = parsePagePostObjectName(job.storagePath);
      if (parsed === null || parsed.pageId !== uid || job.heldBy !== null) continue;
      try {
        await bucket.file(job.storagePath, { generation: job.generation }).delete({
          ignoreNotFound: true,
          ifGenerationMatch: job.generation,
        });
      } catch (error) {
        // A different generation lives at the path: not this job's object.
        if (!isGenerationMismatch(error)) throw error;
      }
      await db.runTransaction(async (transaction) => {
        const current = canonicalPageMediaDeletionJob(await transaction.get(document.ref));
        if (current !== null && current.heldBy === null) transaction.delete(document.ref);
      });
      removed += 1;
    }
    for (const document of reservations.docs) {
      const value = document.data() ?? {};
      const parsed = parsePagePostObjectName(value.storagePath);
      if (parsed === null || parsed.pageId !== uid || parsed.mediaId !== document.id) {
        throw incompleteStorage("A Page media reservation is malformed.");
      }
      await bucket.file(value.storagePath).delete({ ignoreNotFound: true });
      await document.ref.delete();
      removed += 1;
    }
    return {
      removed,
      more: jobs.size >= limits.storage || reservations.size >= limits.storage,
    };
  }

  // ---------------------------------------------------------- records

  async function removeRecords(uid) {
    const snapshot = await PAGES_DELETION_QUERIES.pageBudgets(db, uid).limit(limits.records).get();
    if (!snapshot.empty) {
      const batch = db.batch();
      snapshot.docs.forEach((document) => batch.delete(document.ref));
      await batch.commit();
    }
    return { done: snapshot.size < limits.records, removed: snapshot.size };
  }

  // ------------------------------------------------ evidence retention

  /**
   * Purges one retained tombstone (a deleted account's, or an owner-deleted
   * post of a live account) once the report resolved or 90 days passed: the
   * post, its likes and comments (cleanup job), and its media (jobs
   * released). Returns true when it purged.
   */
  async function purgeRetainedPost(postId) {
    const { nowMs, now } = timing();
    const retentionRef = db.doc(`pageEvidenceRetention/${postId}`);
    const postRef = db.doc(`pagePosts/${postId}`);
    return db.runTransaction(async (transaction) => {
      const [retentionSnapshot, postSnapshot, reportsSnapshot] = await transactionGetAll(
        transaction, retentionRef, postRef, db.doc(`pagePostOpenReports/${postId}`),
      );
      const retention = canonicalPageEvidenceRetention(retentionSnapshot);
      if (retention === null || retention.purgeAtMs > nowMs) return false;
      if (retention.malformed) logger.error("pages evidence retention row malformed", {});
      const reason = retention.reason;
      if (postSnapshot.exists && postSnapshot.data()?.status !== "deleted") {
        // A retention row only ever names a tombstone: a live post is never
        // purged by a stray row.
        logger.error("pages evidence retention names a live post", {});
        transaction.delete(retentionRef);
        return false;
      }
      const post = canonicalPagePostData(postSnapshot);
      const jobSnapshots = post === null
        ? []
        : await transactionGetAll(
          transaction,
          ...post.media.map((entry) => db.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`)),
        );
      if (post !== null) {
        for (const [index, entry] of post.media.entries()) {
          const job = jobSnapshots[index];
          if (job.exists) {
            transaction.update(job.ref, { heldBy: null, nextAttemptAt: now });
          } else if (GENERATION_PATTERN.test(entry.generation)) {
            transaction.set(job.ref, pageMediaDeletionJob({
              storagePath: entry.storagePath,
              generation: entry.generation,
              reason,
              heldBy: null,
              now,
            }));
          }
        }
        transaction.set(db.doc(`pagePostCleanupJobs/${postId}`), pagePostCleanupJob({
          postId, pageId: post.pageId, reason, now,
        }));
      }
      if (postSnapshot.exists) transaction.delete(postRef);
      if (reportsSnapshot.exists) transaction.delete(reportsSnapshot.ref);
      transaction.delete(retentionRef);
      return true;
    });
  }

  return Object.freeze({
    processComments,
    processPosts,
    purgeRetainedPost,
    removePage,
    removeRecords,
    runContent,
    sweepStorage,
  });
}

module.exports = {
  PAGES_DELETION_LIMITS,
  PAGES_DELETION_QUERIES,
  createPagesAccountDeletion,
};

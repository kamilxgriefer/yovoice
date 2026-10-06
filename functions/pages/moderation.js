// Staff moderation of Premium Pages (ADR-233 §2.10): the Page arms of
// moderateReport (moderation/reports.js) and of the tester-phase operator
// script (scripts/pages_moderation.js), which call this SAME function.
//
//   action (moderateReport)       target               effect
//   removeAndResolve              pagePost             post -> "removed" (bytes kept as evidence)
//   removeAndResolve              pagePostComment      comment deleted, counter, bell row retired
//   removeAndResolve              page                 Page suspended
//   holdPagePost                  pagePost             published -> "held" (owner sees it with a notice)
//   restorePagePost               pagePost             held -> published
//   suspendPage                   any Page report      Page suspended (a Page its owner already
//                                                      deleted: remembered in pageMemory, ADR-236)
//   liftPageSuspension            any Page report      suspension lifted (also a remembered one)
//   resolve / dismiss             any Page report      resolution; a HELD post whose last
//                                                      open report closes is restored
//
// Every arm that ENDS a pagePost / pagePostComment report (removeAndResolve,
// resolve, dismiss) decrements pagePostOpenReports/{postId}.count in the same
// transaction. At zero it clears the post's evidenceHold, releases the
// post's held media deletion jobs (an owner's delete while under review),
// makes a retained tombstone (pageEvidenceRetention: a deleted account's, or
// an owner-deleted post's) due for purging now and, for resolve / dismiss,
// RESTORES a held post: a hold lasts only while a report on the post is open
// and never outlives the review that justified it (audit 2026-09-28; the
// report is terminal afterwards, so restorePagePost could no longer run).
//
// Every arm that HIDES content (removeAndResolve, holdPagePost, suspendPage)
// is a safety write: a malformed pageVisibility/v1 is logged and skipped,
// never a reason to leave reported content up. Restore and lift (and the
// restore on close) still fail closed on a malformed index.
//
// Each content action writes pageVisibility/v1 when the Page's viewability
// changes, recomputes `listed` and postCount, and sends the affected person a
// `pageModeration` statement of reasons (DSA Art. 17) with human-readable
// English text.
//
// Called INSIDE the caller's transaction after the report itself was read;
// every read here happens before any write, and the caller writes the
// report workflow and the audit row after this returns.

const defaultLogger = require("firebase-functions/logger");

const { fail, transactionGetAll } = require("../integrity/guards");
const {
  PAGE_ERRORS,
  canonicalPageOrNull,
  derivePageListed,
  pageMalformedReason,
} = require("./contract");
const { pagePostOpenReports, pagePostMediaJobReferences, releaseHeldPagePostMediaJobs } =
  require("./media_contract");
const { canonicalPagePostData, canonicalPageCommentData } = require("./post_contract");
const { pageCommentNotificationId, pageCommentSourcePath } = require("./engagement_contract");
const {
  PAGE_MODERATION_ACTIONS,
  canonicalPageEvidenceRetention,
  canonicalPageReportTarget,
  pageModerationNotice,
  pageModerationReason,
} = require("./report_contract");
const { applyPageVisibilityInTransaction, pageVisibilityReference } = require("./visibility");

const RESOLVING_ACTIONS = new Set(["resolve", "removeAndResolve", "dismiss"]);
const PAGE_ARM_ACTIONS = new Set([
  "resolve",
  "removeAndResolve",
  "dismiss",
  ...Object.values(PAGE_MODERATION_ACTIONS),
]);

function dataOf(snapshot) {
  return snapshot?.exists ? (snapshot.data() ?? null) : null;
}

/**
 * Applies `action` for the Page report `report` (id `reportId`) inside
 * `transaction`. `now` is a Firestore Timestamp. Returns
 * {contentRemoved, contentAlreadyRemoved, released}.
 */
async function applyPageReportModeration(transaction, {
  db,
  report,
  reportId,
  action,
  moderationReason = null,
  now,
  logger = defaultLogger,
}) {
  if (!PAGE_ARM_ACTIONS.has(action)) {
    fail("failed-precondition", "This action does not apply to a Page report.");
  }
  const target = canonicalPageReportTarget(report);
  const reason = pageModerationReason(moderationReason, report.reason);
  const resolving = RESOLVING_ACTIONS.has(action);
  const removing = action === "removeAndResolve";
  const suspending = action === PAGE_MODERATION_ACTIONS.SUSPEND_PAGE ||
    (removing && target.targetType === "page");
  const lifting = action === PAGE_MODERATION_ACTIONS.LIFT_SUSPENSION;
  const holding = action === PAGE_MODERATION_ACTIONS.HOLD_POST;
  const restoring = action === PAGE_MODERATION_ACTIONS.RESTORE_POST;
  const removingPost = removing && target.targetType === "pagePost";
  const removingComment = removing && target.targetType === "pagePostComment";
  if ((holding || restoring) && target.targetType !== "pagePost") {
    fail("failed-precondition", "Only a Page post report can hold or restore a post.");
  }
  const countsReport = resolving && target.postId !== null;

  // ------------------------------------------------------------- reads
  const pageRef = db.doc(`pages/${target.pageId}`);
  const postRef = target.postId ? db.doc(`pagePosts/${target.postId}`) : null;
  const commentRef = target.commentId ? db.doc(`pagePostComments/${target.commentId}`) : null;
  const references = [
    pageRef,
    pageVisibilityReference(db),
    db.doc(`users/${target.pageId}`),
    postRef ?? pageRef,
    commentRef ?? pageRef,
    countsReport ? db.doc(`pagePostOpenReports/${target.postId}`) : pageRef,
    countsReport ? db.doc(`pageEvidenceRetention/${target.postId}`) : pageRef,
    removingComment
      ? db.doc(`users/${target.pageId}/notifications/${pageCommentNotificationId(target.commentId)}`)
      : pageRef,
    removingComment ? db.doc(`users/${target.reportedUserId}`) : pageRef,
    // ADR-236: the memory of a Page its owner deleted. A suspension (or its
    // lift) that finds no Page lands there, so deleting a reported Page is
    // never a way around the decision.
    suspending || lifting ? db.doc(`pageMemory/${target.pageId}`) : pageRef,
  ];
  const [pageSnapshot, visibilitySnapshot, ownerSnapshot, rawPostSnapshot, rawCommentSnapshot,
    rawReportsSnapshot, rawRetentionSnapshot, rawBellSnapshot, rawAuthorSnapshot,
    rawMemorySnapshot] = await transactionGetAll(transaction, ...references);
  const postSnapshot = postRef ? rawPostSnapshot : null;
  const commentSnapshot = commentRef ? rawCommentSnapshot : null;
  const post = postSnapshot ? canonicalPagePostData(postSnapshot) : null;
  if (postSnapshot?.exists && post === null) {
    logger.error("pages moderation found a malformed post", {});
  }
  if (post !== null && post.pageId !== target.pageId) {
    fail("failed-precondition", "The reported Page post is inconsistent.");
  }
  const openReports = countsReport ? pagePostOpenReports(rawReportsSnapshot, target.postId) : null;
  const willRelease = countsReport && openReports.count <= 1;
  const jobSnapshots = willRelease && post !== null
    ? await transactionGetAll(transaction, ...pagePostMediaJobReferences(db, post))
    : [];
  const page = canonicalPageOrNull(pageSnapshot, target.pageId);
  if (pageSnapshot.exists && page === null) {
    logger.error("pages moderation found a malformed page", {
      reason: pageMalformedReason(pageSnapshot.data(), target.pageId),
    });
  }

  // ----------------------------------------------------------- writes
  const outcome = { contentRemoved: false, contentAlreadyRemoved: null, released: 0 };
  const postChanges = {};
  const pageChanges = {};
  const notices = [];
  const ownerNotice = (noticeAction, subjectId) => {
    if (!ownerSnapshot.exists) return;
    notices.push({
      recipient: target.pageId,
      ...pageModerationNotice({
        action: noticeAction, reason, reportId, pageId: target.pageId, subjectId, now,
      }),
    });
  };

  if (removingPost || holding || restoring) {
    if (post === null) {
      if (removingPost) {
        // The owner (or an earlier decision) already removed it: resolving
        // is still right, and the audit says who did.
        outcome.contentRemoved = true;
        outcome.contentAlreadyRemoved = true;
      } else {
        fail("failed-precondition", "The reported post no longer exists.");
      }
    } else if (removingPost) {
      if (post.status === "published" || post.status === "held") {
        postChanges.status = "removed";
        postChanges.removedAt = now;
        postChanges.removedReason = reason;
        if (post.status === "published") pageChanges.postCountDelta = -1;
        if (page?.pinnedPostId === post.postId) pageChanges.pinnedPostId = null;
        ownerNotice("postRemoved", post.postId);
        outcome.contentAlreadyRemoved = false;
      } else {
        outcome.contentAlreadyRemoved = true;
      }
      outcome.contentRemoved = true;
    } else if (holding) {
      if (post.status === "published") {
        postChanges.status = "held";
        postChanges.heldAt = now;
        pageChanges.postCountDelta = -1;
        ownerNotice("postHeld", post.postId);
      } else if (post.status !== "held") {
        fail("failed-precondition", "Only a published post can be held.");
      }
    } else if (post.status === "held") {
      postChanges.status = "published";
      postChanges.heldAt = null;
      pageChanges.postCountDelta = 1;
      ownerNotice("postRestored", post.postId);
    } else if (post.status !== "published") {
      fail("failed-precondition", "Only a held post can be restored.");
    }
  }

  if (removingComment) {
    const comment = commentSnapshot ? canonicalPageCommentData(commentSnapshot) : null;
    if (!commentSnapshot?.exists) {
      outcome.contentRemoved = true;
      outcome.contentAlreadyRemoved = true;
    } else {
      if (comment === null) fail("data-loss", "The Page comment record is malformed.");
      if (comment.postId !== target.postId || comment.pageId !== target.pageId ||
          comment.authorId !== target.reportedUserId) {
        fail("failed-precondition", "The reported Page comment is inconsistent.");
      }
      transaction.delete(commentRef);
      if (post !== null) {
        if (Number.isSafeInteger(post.commentCount) && post.commentCount > 0) {
          postChanges.commentCount = post.commentCount - 1;
        } else {
          logger.error("pages comment count underflow", {});
        }
      }
      const bell = dataOf(rawBellSnapshot);
      if (bell !== null && bell.type === "pagePostComment" &&
          bell.sourcePath === pageCommentSourcePath(comment.commentId)) {
        transaction.delete(rawBellSnapshot.ref);
      }
      if (rawAuthorSnapshot.exists) {
        notices.push({
          recipient: comment.authorId,
          ...pageModerationNotice({
            action: "commentRemoved", reason, reportId, pageId: target.pageId,
            subjectId: comment.postId, now,
          }),
        });
      }
      outcome.contentRemoved = true;
      outcome.contentAlreadyRemoved = false;
    }
  }

  if (suspending || lifting) {
    if (!pageSnapshot.exists) {
      // ADR-236: the owner deleted the Page but the ACCOUNT is still here.
      // The decision is kept in pageMemory/{pageId}: the next Page this
      // account creates starts suspended (managePageV1 create), and a lift
      // clears a remembered suspension. Loaded lazily, like the Page arm.
      //
      // "Still here" means a users/{uid} document that is NOT being deleted.
      // During account deletion that document outlives the Page and the
      // uid-keyed records step (it goes last, in `finalize`), so a decision
      // taken in that window would write a never-expiring uid-keyed row for
      // an account that is being erased. A banned account (disabled, no
      // accountDeletion mark) is still remembered: a ban can be lifted.
      const owner = dataOf(ownerSnapshot);
      const accountStays = owner !== null && (owner.accountDeletion ?? null) === null;
      const memory = accountStays ? require("./deletion") : null;
      if (lifting) {
        const lifted = memory !== null && memory.liftRememberedPageSuspensionInTransaction(
          transaction,
          { db, pageId: target.pageId, memorySnapshot: rawMemorySnapshot, now, logger },
        );
        if (!lifted) throw PAGE_ERRORS.notFound();
        ownerNotice("pageSuspensionLifted", null);
      } else {
        const remembered = memory !== null && memory.rememberPageSuspensionInTransaction(
          transaction,
          { db, pageId: target.pageId, memorySnapshot: rawMemorySnapshot, reason, now, logger },
        );
        if (remembered) ownerNotice("pageSuspended", null);
        // With no account left there is nothing to suspend; either way the
        // Page itself was already removed by its owner.
        outcome.contentRemoved = true;
        outcome.contentAlreadyRemoved = true;
      }
    } else {
      if (page === null && lifting) fail("data-loss", "The Page record is malformed.");
      const current = page ?? pageSnapshot.data();
      if (suspending) {
        if (current.suspended !== true) {
          pageChanges.suspended = true;
          pageChanges.suspendedAt = now;
          pageChanges.suspensionReason = reason;
          ownerNotice("pageSuspended", null);
          outcome.contentAlreadyRemoved = false;
        } else {
          outcome.contentAlreadyRemoved = true;
        }
        outcome.contentRemoved = removing ? true : outcome.contentRemoved;
      } else if (current.suspended === true) {
        pageChanges.suspended = false;
        pageChanges.suspendedAt = null;
        pageChanges.suspensionReason = null;
        ownerNotice("pageSuspensionLifted", null);
      }
    }
  }

  if (countsReport) {
    const count = Math.max(0, openReports.count - 1);
    if (openReports.malformed) logger.error("pages open-report record malformed on resolve", {});
    if (openReports.exists) {
      transaction.set(db.doc(`pagePostOpenReports/${target.postId}`), {
        schemaVersion: 1,
        postId: target.postId,
        pageId: target.pageId,
        count,
        lastReportId: openReports.lastReportId ?? reportId,
        updatedAt: now,
      });
    }
    if (count === 0) {
      if (post !== null && post.evidenceHold === true) postChanges.evidenceHold = false;
      if (!removing && post !== null && post.status === "held") {
        postChanges.status = "published";
        postChanges.heldAt = null;
        pageChanges.postCountDelta = (pageChanges.postCountDelta ?? 0) + 1;
        ownerNotice("postRestored", post.postId);
      }
      outcome.released = releaseHeldPagePostMediaJobs(transaction, jobSnapshots, now);
      const retention = canonicalPageEvidenceRetention(rawRetentionSnapshot);
      if (retention !== null) {
        transaction.update(rawRetentionSnapshot.ref, { purgeAt: now });
      }
    }
  }

  if (post !== null && Object.keys(postChanges).length > 0) {
    transaction.update(postRef, postChanges);
  }

  // The Page: counters, pin, suspension, `listed`, the visibility index.
  const { postCountDelta = 0, ...plainPageChanges } = pageChanges;
  if (page !== null && (postCountDelta !== 0 || Object.keys(plainPageChanges).length > 0)) {
    const postCount = Math.max(0, page.postCount + postCountDelta);
    if (page.postCount + postCountDelta < 0) logger.error("pages post count underflow", {});
    const next = { ...page, ...plainPageChanges, postCount, updatedAt: now };
    next.listed = derivePageListed(next);
    transaction.update(pageRef, {
      ...plainPageChanges,
      ...(postCountDelta !== 0 ? { postCount } : {}),
      listed: next.listed,
      updatedAt: now,
    });
    applyPageVisibilityInTransaction(transaction, {
      db,
      snapshot: visibilitySnapshot,
      pageId: target.pageId,
      page: next,
      now,
      logger,
      // Hiding content is a safety write (a broken index never keeps it up);
      // restoring and lifting fail closed.
      safetyAction: suspending || removing || holding,
    });
  } else if (page === null && pageSnapshot.exists && suspending) {
    // A malformed Page is still suspended (a safety action): only the
    // suspension fields and `listed` move; the index hides it.
    transaction.update(pageRef, {
      suspended: true,
      suspendedAt: now,
      suspensionReason: reason,
      listed: false,
      updatedAt: now,
    });
    applyPageVisibilityInTransaction(transaction, {
      db,
      snapshot: visibilitySnapshot,
      pageId: target.pageId,
      page: { ...pageSnapshot.data(), suspended: true },
      now,
      logger,
      safetyAction: true,
    });
  }

  for (const notice of notices) {
    transaction.set(db.doc(`users/${notice.recipient}/notifications/${notice.id}`), notice.data);
  }
  return outcome;
}

module.exports = {
  PAGE_ARM_ACTIONS,
  RESOLVING_ACTIONS,
  applyPageReportModeration,
};

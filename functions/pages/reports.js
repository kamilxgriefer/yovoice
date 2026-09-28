// createPageReportV1: report a Page, a Page post or a comment on one
// (ADR-233 §2.10, decision D7). A sibling of createContentReport and the
// Reels report callables, never a widening of them: their operation
// identities and report ids are deployed contracts.
//
// A SAFETY ACTION (§2.1): it never reads appConfig/pagesV1, never checks
// canViewPage and is allowed while muted and unverified. Only EXISTENCE is
// required, so a person a harassing Page has blocked can still report it
// (the reel-comment reasoning in reels/service.js: an audience check would
// let a harasser immunise their content by blocking the victim).
//
// Order: auth (verification not required) -> exact input (every id
// format-checked before any read) -> the `pages.report` budget (10 / 10 min),
// CHARGED BEFORE THE TARGET IS READ so a refused probe costs the same as a
// report (only an exact ledger replay is free) -> one transaction:
//
//   * the reporter's account is active;
//   * the target exists (one uniform not-found for every missing state) and
//     is not the reporter's own;
//   * reports/{id} is written with the snapshot the moderator needs (staff
//     cannot read any Pages collection); a `page` report also snapshots the
//     Page's newest published or held posts (recentPosts, at most 5);
//   * for a post or comment report: the post gets evidenceHold:true and
//     pagePostOpenReports/{postId}.count moves up by one, so an owner's
//     delete becomes a tombstone and the bytes stay until the report is
//     resolved (managePagePostV1, pages/moderation.js).
//
// One report per reporter per target: a second report of the same thing is
// {created:false} and moves nothing.

const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  assertLedgerReplay,
  consumeRateLimit,
  fail,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireRequestId,
  transactionGetAll,
} = require("../integrity/guards");
const { likersAccountIsActive } = require("../utils/likers_access");
const { canonicalPagePostData, canonicalPageCommentData } = require("./post_contract");
const { pagePostOpenReports } = require("./media_contract");
const {
  PAGE_REPORT_ERRORS,
  pageReportDocument,
  pageReportId,
  requirePageReportInput,
} = require("./report_contract");

const REGION = "europe-west1";
const LEDGER_KIND = "pages.report.v1";
const PAGES_REPORT_RATE_LIMIT = Object.freeze({ maxEvents: 10, windowMs: 10 * 60 * 1000 });
const PAGE_REPORT_RESPONSE_KEYS = Object.freeze(["created", "reportId", "schemaVersion"]);
// The newest posts of a reported Page. The same shape (and index: pagePosts
// authorId ASC, createdAt DESC, __name__ DESC) as account deletion's
// authorPosts, which the index smoke runs (ADR-007); a Page's posts are
// authored by the Page account.
const RECENT_POSTS_SCAN = 10;
const PAGES_REPORT_QUERIES = Object.freeze({
  recentPosts: (db, pageId) => db.collection("pagePosts")
    .where("authorId", "==", pageId)
    .orderBy("createdAt", "desc")
    .orderBy(FieldPath.documentId(), "desc")
    .limit(RECENT_POSTS_SCAN),
});

function createPagesReportService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimit = PAGES_REPORT_RATE_LIMIT,
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

  // Ledger replay first (free), else the budget, in one small transaction
  // committed BEFORE the target is read.
  async function beginAttempt(uid, identity, timed) {
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    const rateRef = rateLimitReference(firestore, "pages.report", uid);
    return firestore.runTransaction(async (transaction) => {
      const [ledger, rate] = await transactionGetAll(transaction, ledgerRef, rateRef);
      const replay = assertLedgerReplay(ledger, {
        kind: LEDGER_KIND, uid, inputHash: identity.inputHash,
      });
      if (replay) return replay;
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope: "pages.report",
        uid,
        nowMs: timed.nowMs,
        now: timed.now,
        ...rateLimit,
      });
      return null;
    });
  }

  async function createPageReportV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = requirePageReportInput(request.data);
    const requestId = requireRequestId(input.requestId);
    const uid = auth.uid;
    const identity = operationIdentity(LEDGER_KIND, uid, requestId, {
      targetType: input.targetType,
      pageId: input.pageId,
      postId: input.postId,
      commentId: input.commentId,
      reason: input.reason,
      note: input.note,
    });
    const timed = timing();
    const replay = await beginAttempt(uid, identity, timed);
    if (replay) return replay;

    const reportId = pageReportId(uid, input.targetType, input.targetId);
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    const reportRef = firestore.doc(`reports/${reportId}`);
    const pageRef = firestore.doc(`pages/${input.pageId}`);
    const postRef = input.postId ? firestore.doc(`pagePosts/${input.postId}`) : null;
    const commentRef = input.commentId
      ? firestore.doc(`pagePostComments/${input.commentId}`)
      : null;
    const openReportsRef = input.postId
      ? firestore.doc(`pagePostOpenReports/${input.postId}`)
      : null;
    return firestore.runTransaction(async (transaction) => {
      const [ledger, reportSnapshot, reporterSnapshot, pageSnapshot, postSnapshot,
        commentSnapshot, openReportsSnapshot] = await transactionGetAll(
        transaction,
        ledgerRef,
        reportRef,
        firestore.doc(`users/${uid}`),
        pageRef,
        postRef ?? pageRef,
        commentRef ?? pageRef,
        openReportsRef ?? pageRef,
      );
      const prior = assertLedgerReplay(ledger, {
        kind: LEDGER_KIND, uid, inputHash: identity.inputHash,
      });
      if (prior) return prior;
      const reporter = reporterSnapshot.exists ? reporterSnapshot.data() : null;
      if (!likersAccountIsActive(reporter)) fail("permission-denied", "Your account is not active.");

      // EXISTENCE only, one uniform refusal for every missing state.
      if (!pageSnapshot.exists) throw PAGE_REPORT_ERRORS.missing();
      const page = pageSnapshot.data() ?? {};
      let post = null;
      let comment = null;
      if (input.postId !== null) {
        post = canonicalPagePostData(postSnapshot);
        if (post === null) {
          if (postSnapshot.exists) logger.error("pages report found a malformed post", {});
          throw PAGE_REPORT_ERRORS.missing();
        }
        // A deleted tombstone or a removed post has nothing left to report.
        if (post.pageId !== input.pageId || !["published", "held"].includes(post.status)) {
          throw PAGE_REPORT_ERRORS.missing();
        }
      }
      if (input.commentId !== null) {
        comment = canonicalPageCommentData(commentSnapshot);
        if (comment === null || comment.postId !== input.postId ||
            comment.pageId !== input.pageId) {
          throw PAGE_REPORT_ERRORS.missing();
        }
      }
      const ownerOfTarget = input.targetType === "pagePostComment"
        ? comment.authorId
        : input.pageId;
      if (ownerOfTarget === uid) throw PAGE_REPORT_ERRORS.own();

      let recentPosts = [];
      if (!reportSnapshot.exists && input.targetType === "page") {
        const recent = await transaction.get(
          PAGES_REPORT_QUERIES.recentPosts(firestore, input.pageId));
        recentPosts = recent.docs
          .map((document) => canonicalPagePostData(document))
          .filter((candidate) => candidate !== null && candidate.pageId === input.pageId &&
            ["published", "held"].includes(candidate.status));
      }

      let created = false;
      if (!reportSnapshot.exists) {
        created = true;
        transaction.create(reportRef, pageReportDocument({
          reporterId: uid, input, page, post, comment, now: timed.now, recentPosts,
        }));
        if (post !== null) {
          if (post.evidenceHold !== true) {
            transaction.update(postRef, { evidenceHold: true });
          }
          const open = pagePostOpenReports(openReportsSnapshot, input.postId);
          if (open.malformed) logger.error("pages open-report record malformed on report", {});
          transaction.set(openReportsRef, {
            schemaVersion: 1,
            postId: input.postId,
            pageId: input.pageId,
            count: open.count + 1,
            lastReportId: reportId,
            updatedAt: timed.now,
          });
        }
      }
      const result = { schemaVersion: 1, reportId, created };
      transaction.create(ledgerRef, ledgerData({
        kind: LEDGER_KIND,
        uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timed.now,
      }));
      if (created) logger.info("pages report filed", { targetType: input.targetType });
      return result;
    });
  }

  return Object.freeze({ createPageReportV1 });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    defaultService = createPagesReportService({ firestore: db });
  }
  return defaultService;
}

const createPageReportV1 = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => service().createPageReportV1(request),
);

module.exports = {
  LEDGER_KIND,
  PAGES_REPORT_RATE_LIMIT,
  PAGE_REPORT_RESPONSE_KEYS,
  PAGES_REPORT_QUERIES,
  createPageReportV1,
  createPagesReportService,
};

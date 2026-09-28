// Page post engagement (ADR-233 §2.6, package B4): pagePostEngagementV1
// (like, unlike, comment, deleteComment) and listPagePostLikersV1 (the
// ADR-230 "See who liked" list on a Page post). europe-west1,
// enforceAppCheck:false, like every Pages callable. Neither is warm or a
// keep-warm target.
//
// Order in every call (§2.1): auth -> exact input -> activation (non-safety
// only) -> rate budget -> content. There is no Pages capability gate for the
// CALLER here: visitors engage; the Page OWNER's capability is what a comment
// re-derives (D14: a readOnly Page takes no comments).
//
//   like / unlike   readAccess; canViewPage (audience.js) and the post
//                   `published`. Likes and unlikes work while the Page is
//                   readOnly. An unlike of an edge the caller already holds
//                   skips the audience check and the mute check, so a like
//                   can never get stuck behind a later block or pause; its
//                   answer carries likeCount null when the post is no longer
//                   visible to the caller. 60/min.
//   comment         writeAccess; verified e-mail; active and not muted;
//                   canViewPage; post `published` with comments on; the Page
//                   LIVE-active (capability re-derived from the owner's
//                   users / entitlements / vipGrants, not paused, not
//                   suspended); the link filter. 20/min + 200/day, and 3/min
//                   for an account whose FIREBASE AUTH creation time is under
//                   7 days old (never users.createdAt, which the client
//                   writes). The comment, the post's commentCount and the
//                   owner's `pagePostComment` bell row move in ONE
//                   transaction; the owner is never notified of their own
//                   comment, nor while muted.
//   deleteComment   a SAFETY action: no activation read, allowed while muted
//                   and unverified. The comment's author or the Page owner;
//                   anyone else, and a missing comment, get the uniform
//                   pageUnavailable. The bell row it produced is retired in
//                   the same transaction. 30/min.
//
// listPagePostLikersV1 {postId, cursor|null}: pagesV1 readAccess, then the
// ADR-230 order (likersV1.enabled, the likers budgets, the likers gate), then
// the post authorized with canViewPage + `published` inside the ADR-230
// uniform refusal, candidates from pagePosts/{postId}/likes (createdAt desc,
// __name__ desc; the automatic single-field index), the one liker predicate
// (surface "content") and the ADR-230 page loop (20, scan cap 60).

const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  assertLedgerReplay,
  assertNotRestricted,
  canonicalPublicProfile,
  consumeRateLimit,
  fail,
  incrementCanonicalCount,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  restrictionIsActive,
  transactionGetAll,
} = require("../integrity/guards");
const { likersAccountIsActive } = require("../utils/likers_access");
const { LIKERS_SURFACES } = require("../engagement/likers_activation");
const { serveLikersList } = require("../engagement/likers_callable");
const {
  queryCandidateFetcher,
  requireLikersListInput,
} = require("../engagement/likers_paging");
const { assertPagesReadEnabled, assertPagesWriteEnabled } = require("./activation");
const {
  livePageStatus,
  pageUnavailableError,
  pageViewDecision,
} = require("./audience");
const { PAGE_ERRORS, canonicalPageOrNull } = require("./contract");
const {
  PAGE_COMMENT_NOTIFICATION_TYPE,
  PAGE_ENGAGEMENT_ERRORS,
  PAGE_NEW_ACCOUNT_MS,
  commentResponse,
  deleteCommentResponse,
  likeResponse,
  pageCommentIdFor,
  pageCommentNotificationId,
  pageCommentSourcePath,
  pageCommentTargetLabel,
  pageLikeDocument,
  requireEngagementInput,
  validPageLike,
} = require("./engagement_contract");
const { PAGE_POST_ERRORS } = require("./media_contract");
const {
  canonicalPageCommentData,
  canonicalPagePostData,
  pageCommentMalformedReason,
} = require("./post_contract");
const { commentView } = require("./views");

const REGION = "europe-west1";
const MINUTE_MS = 60_000;
const DAY_MS = 24 * 60 * MINUTE_MS;

const PAGES_ENGAGEMENT_RATE_LIMITS = Object.freeze({
  "pages.like": Object.freeze({ maxEvents: 60, windowMs: MINUTE_MS }),
  "pages.comment": Object.freeze({ maxEvents: 20, windowMs: MINUTE_MS }),
  "pages.commentDaily": Object.freeze({ maxEvents: 200, windowMs: DAY_MS }),
  "pages.commentNewAccount": Object.freeze({ maxEvents: 3, windowMs: MINUTE_MS }),
  "pages.commentDelete": Object.freeze({ maxEvents: 30, windowMs: MINUTE_MS }),
});
const LEDGER_KINDS = Object.freeze({
  like: "pages.engagement.like.v1",
  unlike: "pages.engagement.unlike.v1",
  comment: "pages.engagement.comment.v1",
  deleteComment: "pages.engagement.deleteComment.v1",
});
// Bound on the per-instance Auth creation-time memo (uid -> ms). Creation
// time never changes, so a cached value is never stale; the bound only caps
// memory.
const AUTH_AGE_MEMO_MAX = 5000;

// The likers candidate source. queryCandidateFetcher (ADR-230) orders it
// createdAt desc, __name__ desc; pages_index_emulator.test.js and the index
// smoke run the same fetcher over this same builder. No composite index: an
// orderBy on one field plus __name__ in the same direction is served by the
// automatic single-field index.
const PAGES_ENGAGEMENT_QUERIES = Object.freeze({
  postLikes: (db, postId) => db.collection(`pagePosts/${postId}/likes`),
});

/// The bell row reference of one comment (B5's comment removal and account
/// deletion retire it through this too).
function pageCommentNotificationReference(db, pageId, commentId) {
  return db.doc(`users/${pageId}/notifications/${pageCommentNotificationId(commentId)}`);
}

/// Queues the retirement of a comment's bell row when `snapshot` (read in
/// the same transaction) is the row that comment produced. A row the owner
/// already deleted, or one with another source, is left alone.
function retirePageCommentNotificationInTransaction(transaction, snapshot, commentId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  if (data.type !== PAGE_COMMENT_NOTIFICATION_TYPE ||
      data.sourcePath !== pageCommentSourcePath(commentId)) {
    return false;
  }
  transaction.delete(snapshot.ref);
  return true;
}

function defaultNotificationData() {
  return require("../notifications/canonical").canonicalNotificationData;
}

function defaultAuthAdmin() {
  const { getAuth } = require("firebase-admin/auth");
  return getAuth();
}

function createPagesEngagementService({
  firestore,
  TimestampImpl = Timestamp,
  documentIdField = FieldPath.documentId(),
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimits = PAGES_ENGAGEMENT_RATE_LIMITS,
  authAdmin = null,
  notificationData = null,
}) {
  if (!firestore?.doc || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, Timestamp and clock are required.");
  }
  const authCreationMemo = new Map();

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  function dataOf(snapshot) {
    return snapshot?.exists ? (snapshot.data() ?? null) : null;
  }

  async function chargeRates(scopes, uid, timed) {
    await firestore.runTransaction(async (transaction) => {
      const references = scopes.map((scope) => rateLimitReference(firestore, scope, uid));
      const snapshots = await transactionGetAll(transaction, ...references);
      scopes.forEach((scope, index) => {
        consumeRateLimit(transaction, snapshots[index], {
          reference: references[index],
          scope,
          uid,
          nowMs: timed.nowMs,
          now: timed.now,
          ...rateLimits[scope],
        });
      });
    });
  }

  function ledgerRefOf(identity) {
    return firestore.doc(`integrityOperationLedgers/${identity.id}`);
  }

  // A replay (same requestId, same input) is free: rates are for new work.
  async function priorResult(kind, uid, identity) {
    return assertLedgerReplay(await ledgerRefOf(identity).get(), {
      kind, uid, inputHash: identity.inputHash,
    });
  }

  // The caller's Firebase Auth creation time (never users.createdAt, which
  // the client writes). Memoised per instance. An unreadable or missing
  // record is treated as a NEW account: the stricter limit, never a refusal.
  async function authCreatedAtMs(uid) {
    if (authCreationMemo.has(uid)) return authCreationMemo.get(uid);
    let createdAtMs = null;
    try {
      const auth = authAdmin ?? defaultAuthAdmin();
      const record = await auth.getUser(uid);
      const parsed = Date.parse(record?.metadata?.creationTime ?? "");
      createdAtMs = Number.isFinite(parsed) ? parsed : null;
    } catch (error) {
      logger.warn("pages auth age unavailable", {
        code: typeof error?.code === "string" ? error.code : null,
      });
      return null;
    }
    if (createdAtMs !== null) {
      if (authCreationMemo.size >= AUTH_AGE_MEMO_MAX) authCreationMemo.clear();
      authCreationMemo.set(uid, createdAtMs);
    }
    return createdAtMs;
  }

  async function isNewAccount(uid, nowMs) {
    const createdAtMs = await authCreatedAtMs(uid);
    return createdAtMs === null || nowMs - createdAtMs < PAGE_NEW_ACCOUNT_MS;
  }

  // pages/{P}, users/{P} and the two blocks, in this order.
  function pageAudienceReferences(viewerId, pageId) {
    return [
      firestore.doc(`pages/${pageId}`),
      firestore.doc(`users/${pageId}`),
      firestore.doc(`users/${viewerId}/blocked/${pageId}`),
      firestore.doc(`users/${pageId}/blocked/${viewerId}`),
    ];
  }

  function pageOf(snapshot, pageId) {
    const page = canonicalPageOrNull(snapshot, pageId);
    if (snapshot?.exists && page === null) {
      logger.warn("pages malformed record skipped", { kind: "page", count: 1 });
    }
    return page;
  }

  function viewDecision({ viewerId, post, viewerUser, audience, activation, nowMs }) {
    const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock] = audience;
    const page = pageOf(pageSnapshot, post.pageId);
    const decision = pageViewDecision({
      viewerId,
      pageId: post.pageId,
      page,
      pageUser: dataOf(pageUserSnapshot),
      viewerUser,
      viewerBlocksPage: viewerBlock.exists,
      pageBlocksViewer: pageBlock.exists,
      nowMs,
      lapseEnabled: activation.lapseEnabled,
    });
    return { ...decision, page };
  }

  function assertViewerActive(viewerSnapshot) {
    const viewer = dataOf(viewerSnapshot);
    if (!likersAccountIsActive(viewer)) fail("permission-denied", "Your account is not active.");
    return viewer;
  }

  // ------------------------------------------------------- like / unlike

  async function setLike(auth, input, timed) {
    const uid = auth.uid;
    const liked = input.op === "like";
    const kind = LEDGER_KINDS[input.op];
    const identity = operationIdentity(kind, uid, input.requestId, { postId: input.postId });
    const activation = await assertPagesReadEnabled({ db: firestore, uid, logger });
    const replay = await priorResult(kind, uid, identity);
    if (replay) return replay;
    await chargeRates(["pages.like"], uid, timed);

    const postRef = firestore.doc(`pagePosts/${input.postId}`);
    const likeRef = firestore.doc(`pagePosts/${input.postId}/likes/${uid}`);
    const ledgerRef = ledgerRefOf(identity);
    return firestore.runTransaction(async (transaction) => {
      const [ledgerSnapshot, postSnapshot, likeSnapshot, viewerSnapshot, restriction] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          postRef,
          likeRef,
          firestore.doc(`users/${uid}`),
          firestore.doc(`restrictions/${uid}`),
        );
      const prior = assertLedgerReplay(ledgerSnapshot, { kind, uid, inputHash: identity.inputHash });
      if (prior) return prior;
      const viewerUser = assertViewerActive(viewerSnapshot);
      const post = canonicalPagePostData(postSnapshot);
      // An unlike removes the caller's edge even when it is malformed (a
      // like must never get stuck); a like over a malformed edge is
      // data-loss.
      const holds = likeSnapshot.exists;
      if (holds && !validPageLike(likeSnapshot, input.postId, uid)) {
        if (liked) fail("data-loss", "The Page post like edge is not canonical.");
        logger.error("pages malformed record skipped", { kind: "pagePostLike", count: 1 });
      }
      // The audience is read whenever the post exists; a held unlike only
      // uses it to decide whether the answer may carry the count.
      const audience = post === null
        ? null
        : await transactionGetAll(transaction, ...pageAudienceReferences(uid, post.pageId));
      const decision = post === null
        ? { viewable: false }
        : viewDecision({ viewerId: uid, post, viewerUser, audience, activation, nowMs: timed.nowMs });
      const visible = post !== null && decision.viewable && post.status === "published";
      const heldUnlike = !liked && holds;
      if (!heldUnlike) {
        if (liked) assertNotRestricted(restriction, "Your", timed.nowMs);
        if (!visible) throw pageUnavailableError();
      }

      let changed = false;
      let likeCount = post === null ? null : post.likeCount;
      if (liked && !holds) {
        likeCount = incrementCanonicalCount(post.likeCount, "Page post likeCount");
        transaction.create(likeRef, pageLikeDocument({ userId: uid, postId: input.postId, now: timed.now }));
        transaction.update(postRef, { likeCount });
        changed = true;
      } else if (!liked && holds) {
        transaction.delete(likeRef);
        changed = true;
        if (post !== null) {
          if (!Number.isSafeInteger(post.likeCount) || post.likeCount <= 0) {
            // The edge and the counter move together, so only out-of-band
            // corruption lands here. An unlike is never refused for it: the
            // edge goes, the broken counter is left for reconciliation.
            logger.error("pages like count underflow", {});
            likeCount = null;
          } else {
            likeCount = post.likeCount - 1;
            transaction.update(postRef, { likeCount });
          }
        } else if (postSnapshot.exists) {
          logger.error("pages malformed record skipped", { kind: "pagePost", count: 1 });
        }
      } else if (post !== null && (!Number.isSafeInteger(likeCount) || likeCount < 0)) {
        likeCount = null;
      }
      const result = likeResponse({
        op: input.op,
        postId: input.postId,
        liked,
        changed,
        likeCount: visible ? likeCount : null,
      });
      transaction.create(ledgerRef, ledgerData({
        kind, uid, requestId: input.requestId, inputHash: identity.inputHash, result, now: timed.now,
      }));
      return result;
    });
  }

  // ------------------------------------------------------------ comment

  async function comment(auth, input, timed) {
    const uid = auth.uid;
    const kind = LEDGER_KINDS.comment;
    const identity = operationIdentity(kind, uid, input.requestId, {
      postId: input.postId, text: input.text,
    });
    const activation = await assertPagesWriteEnabled({ db: firestore, uid, logger });
    const replay = await priorResult(kind, uid, identity);
    if (replay) return replay;
    const scopes = ["pages.comment", "pages.commentDaily"];
    if (await isNewAccount(uid, timed.nowMs)) scopes.push("pages.commentNewAccount");
    await chargeRates(scopes, uid, timed);

    const commentId = pageCommentIdFor(uid, input.requestId);
    const postRef = firestore.doc(`pagePosts/${input.postId}`);
    const commentRef = firestore.doc(`pagePostComments/${commentId}`);
    const ledgerRef = ledgerRefOf(identity);
    const buildNotification = notificationData ?? defaultNotificationData();
    return firestore.runTransaction(async (transaction) => {
      const [ledgerSnapshot, postSnapshot, commentSnapshot, viewerSnapshot, restriction,
        publicSnapshot] = await transactionGetAll(
        transaction,
        ledgerRef,
        postRef,
        commentRef,
        firestore.doc(`users/${uid}`),
        firestore.doc(`restrictions/${uid}`),
        firestore.doc(`publicProfiles/${uid}`),
      );
      const prior = assertLedgerReplay(ledgerSnapshot, { kind, uid, inputHash: identity.inputHash });
      if (prior) return prior;
      const viewerUser = assertViewerActive(viewerSnapshot);
      assertNotRestricted(restriction, "Your", timed.nowMs);
      const post = canonicalPagePostData(postSnapshot);
      if (post === null) throw pageUnavailableError();
      const pageId = post.pageId;
      const notifies = pageId !== uid;
      const notificationRef = pageCommentNotificationReference(firestore, pageId, commentId);
      const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock, entitlement, grant,
        ownerRestriction] = await transactionGetAll(
        transaction,
        ...pageAudienceReferences(uid, pageId),
        firestore.doc(`entitlements/${pageId}`),
        firestore.doc(`vipGrants/${pageId}`),
        firestore.doc(`restrictions/${pageId}`),
      );
      const decision = viewDecision({
        viewerId: uid,
        post,
        viewerUser,
        audience: [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock],
        activation,
        nowMs: timed.nowMs,
      });
      if (!decision.viewable || post.status !== "published") throw pageUnavailableError();
      const page = decision.page;
      if (page.suspended) throw PAGE_ERRORS.suspended();
      if (page.ownerPaused) throw PAGE_POST_ERRORS.paused();
      // D14: comments need the Page LIVE-active, capability re-derived now.
      const status = livePageStatus({
        page,
        pageUser: dataOf(pageUserSnapshot),
        pageEntitlement: dataOf(entitlement),
        pageGrant: dataOf(grant),
        nowMs: timed.nowMs,
        lapseEnabled: activation.lapseEnabled,
      });
      if (status !== "active") throw PAGE_ENGAGEMENT_ERRORS.readOnly();
      if (post.commentsEnabled !== true) throw PAGE_ENGAGEMENT_ERRORS.commentsOff();
      if (commentSnapshot.exists) {
        fail("data-loss", "A Page comment exists without its receipt.");
      }
      const authorName = canonicalPublicProfile(publicSnapshot, uid).displayName;
      const commentCount = incrementCanonicalCount(post.commentCount, "Page post commentCount");
      const stored = {
        schemaVersion: 1,
        commentId,
        postId: post.postId,
        pageId,
        authorId: uid,
        text: input.text,
        createdAt: timed.now,
      };
      if (pageCommentMalformedReason(stored, commentId) !== null) {
        fail("data-loss", "The Page comment could not be composed.");
      }
      transaction.create(commentRef, stored);
      transaction.update(postRef, { commentCount });
      if (notifies && !restrictionIsActive(dataOf(ownerRestriction), timed.nowMs)) {
        const row = buildNotification({
          actorId: uid,
          actorProfile: { displayName: authorName },
          type: PAGE_COMMENT_NOTIFICATION_TYPE,
          targetId: post.postId,
          targetLabel: pageCommentTargetLabel(authorName),
          dedupeKey: pageCommentNotificationId(commentId),
          targetSubId: commentId,
        });
        transaction.set(notificationRef, { ...row, sourcePath: pageCommentSourcePath(commentId) });
      }
      const result = commentResponse({
        postId: post.postId,
        comment: commentView(stored, { authorName, pageId }),
        commentCount,
      });
      transaction.create(ledgerRef, ledgerData({
        kind, uid, requestId: input.requestId, inputHash: identity.inputHash, result, now: timed.now,
      }));
      return result;
    });
  }

  // ------------------------------------------------------ deleteComment

  // A SAFETY action: no activation read, no gate, allowed while muted and
  // unverified (§2.1). A malformed Page post never blocks it.
  async function deleteComment(auth, input, timed) {
    const uid = auth.uid;
    const kind = LEDGER_KINDS.deleteComment;
    const identity = operationIdentity(kind, uid, input.requestId, { commentId: input.commentId });
    const replay = await priorResult(kind, uid, identity);
    if (replay) return replay;
    await chargeRates(["pages.commentDelete"], uid, timed);

    const commentRef = firestore.doc(`pagePostComments/${input.commentId}`);
    const ledgerRef = ledgerRefOf(identity);
    return firestore.runTransaction(async (transaction) => {
      const [ledgerSnapshot, commentSnapshot] =
        await transactionGetAll(transaction, ledgerRef, commentRef);
      const prior = assertLedgerReplay(ledgerSnapshot, { kind, uid, inputHash: identity.inputHash });
      if (prior) return prior;
      const raw = dataOf(commentSnapshot);
      // One uniform refusal for "no such comment" and "not yours to delete".
      if (raw === null || (raw.authorId !== uid && raw.pageId !== uid)) {
        throw pageUnavailableError();
      }
      const stored = canonicalPageCommentData(commentSnapshot);
      if (stored === null) fail("data-loss", "The Page comment record is malformed.");
      const postRef = firestore.doc(`pagePosts/${stored.postId}`);
      const [postSnapshot, notificationSnapshot] = await transactionGetAll(
        transaction,
        postRef,
        pageCommentNotificationReference(firestore, stored.pageId, stored.commentId),
      );
      transaction.delete(commentRef);
      const post = canonicalPagePostData(postSnapshot);
      if (post !== null && post.pageId === stored.pageId) {
        if (Number.isSafeInteger(post.commentCount) && post.commentCount > 0) {
          transaction.update(postRef, { commentCount: post.commentCount - 1 });
        } else {
          logger.error("pages comment count underflow", {});
        }
      } else if (postSnapshot.exists) {
        logger.error("pages malformed record skipped", { kind: "pagePost", count: 1 });
      }
      retirePageCommentNotificationInTransaction(transaction, notificationSnapshot, stored.commentId);
      const result = deleteCommentResponse({ postId: stored.postId, commentId: stored.commentId });
      transaction.create(ledgerRef, ledgerData({
        kind, uid, requestId: input.requestId, inputHash: identity.inputHash, result, now: timed.now,
      }));
      return result;
    });
  }

  async function pagePostEngagementV1(request) {
    // deleteComment is a safety action: it runs unverified. Every other op
    // needs a verified e-mail (the Reels like and comment precedent).
    const auth = requireActor(request, { verified: request?.data?.op !== "deleteComment" });
    const input = requireEngagementInput(request.data);
    const timed = timing();
    if (input.op === "deleteComment") return deleteComment(auth, input, timed);
    if (input.op === "comment") return comment(auth, input, timed);
    return setLike(auth, input, timed);
  }

  // --------------------------------------------------------- likers list

  async function listPagePostLikersV1(request) {
    // pagesV1 readAccess first (after auth and exact input), then the
    // ADR-230 order inside serveLikersList. Both activation refusals describe
    // only the caller, so they reach the client unchanged.
    const auth = requireActor(request, { verified: false });
    requireLikersListInput("pagePost", request.data);
    const activation = await assertPagesReadEnabled({ db: firestore, uid: auth.uid, logger });
    const getAllPlain = (...references) => (references.length === 0
      ? Promise.resolve([])
      : firestore.getAll(...references));
    return serveLikersList({
      db: firestore,
      Timestamp: TimestampImpl,
      request,
      family: "pagePost",
      surface: LIKERS_SURFACES.CONTENT,
      time: timing,
      logger,
      openTarget: async ({ input, admitted, timing: requestTime }) => {
        const postRef = firestore.doc(`pagePosts/${input.postId}`);
        const [postSnapshot] = await getAllPlain(postRef);
        const post = canonicalPagePostData(postSnapshot);
        if (post === null) throw pageUnavailableError();
        const audience = await getAllPlain(...pageAudienceReferences(auth.uid, post.pageId));
        const decision = viewDecision({
          viewerId: auth.uid,
          post,
          viewerUser: dataOf(admitted.callerProfile),
          audience,
          activation,
          nowMs: requestTime.nowMs,
        });
        if (!decision.viewable || post.status !== "published") throw pageUnavailableError();
        return {
          fetchCandidates: queryCandidateFetcher({
            query: PAGES_ENGAGEMENT_QUERIES.postLikes(firestore, input.postId),
            documentIdField,
            // A malformed edge is skipped (but consumed), never an oracle.
            toLikerId: (document) => (validPageLike(document, input.postId) ? document.id : null),
          }),
          // A fresh read at response time: a post held, removed or deleted
          // during the scan is not listed.
          recheck: async () => {
            const [fresh] = await getAllPlain(postRef);
            const freshPost = canonicalPagePostData(fresh);
            if (freshPost === null || freshPost.status !== "published" ||
                freshPost.pageId !== post.pageId) {
              throw pageUnavailableError();
            }
          },
        };
      },
    });
  }

  return Object.freeze({ listPagePostLikersV1, pagePostEngagementV1 });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    defaultService = createPagesEngagementService({ firestore: db });
  }
  return defaultService;
}

const callableOptions = { region: REGION, enforceAppCheck: false };
const pagePostEngagementV1 = onCall(
  callableOptions,
  (request) => service().pagePostEngagementV1(request),
);
const listPagePostLikersV1 = onCall(
  callableOptions,
  (request) => service().listPagePostLikersV1(request),
);

module.exports = {
  AUTH_AGE_MEMO_MAX,
  LEDGER_KINDS,
  PAGES_ENGAGEMENT_QUERIES,
  PAGES_ENGAGEMENT_RATE_LIMITS,
  createPagesEngagementService,
  listPagePostLikersV1,
  pageCommentNotificationReference,
  pagePostEngagementV1,
  retirePageCommentNotificationInTransaction,
};

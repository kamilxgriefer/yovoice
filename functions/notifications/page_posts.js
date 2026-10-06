/**
 * "A Page you follow published a post" (ADR-237).
 *
 * The producer is a Firestore trigger on `pagePosts/{postId}`, not a change to
 * `publishPagePostV1`: the publish callable is transactional, idempotency-
 * ledgered and heavily tested, and a notification is derived from the
 * COMMITTED post rather than from a second best-effort write.
 *
 * Fan-out is the room-live outbox pattern (activity.js), one page at a time:
 *
 *   onPagePostCreated               -> ensures pagePostFanoutOutbox/{id}
 *                                      (create-once, identity checked)
 *   onPagePostFanoutOutboxWritten   -> while the outbox is `pending`: reads
 *                                      ONE page of 200 followers after the
 *                                      durable cursor, writes one bell row per
 *                                      follower, then commits the cursor; that
 *                                      commit re-fires the trigger for the
 *                                      next page
 *
 * Idempotent: every row is created through `createNotificationForEvent`,
 * whose event ledger is keyed by (post, follower), so a redelivered page
 * writes nothing twice and never resurrects a row the follower deleted.
 * Resumable and crash-safe: the cursor moves only after a whole page was
 * attempted, in a transaction that refuses a cursor somebody else already
 * moved; a worker that dies mid-page is retried from the committed cursor.
 *
 * Every row is validated twice by `pagePostPublishedSourceIsCurrent` — in
 * the writer's transaction and again in the push claim — so a post that was
 * deleted or held, a paused or suspended Page, an unfollow or a block stops
 * the row and the push. The per-Page daily push cap lives at the push
 * boundary (push.js): later posts of the same day still land in the bell.
 */
const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore",
);
const { logger } = require("firebase-functions/v2");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { digest } = require("../integrity/guards");
const { fanOutRoomLiveFollowers } = require("./activity");
const { createNotificationForEvent } = require("./canonical");
const { pagePostPublishedSourceIsCurrent } = require("./engagement_source");
const { documentGeneration } = require("./social_source");

const REGION = "europe-west1";
const PAGE_POST_NOTIFICATION_TYPE = "pagePostPublished";
const PAGE_POST_FANOUT_COLLECTION = "pagePostFanoutOutbox";
const PAGE_POST_FOLLOWER_PAGE_SIZE = 200;
const PAGE_POST_FANOUT_CONCURRENCY = 16;
const PAGE_POST_PREVIEW_MAX = 120;
const PAGE_POST_LABEL_NAME_MAX = 40;
// A post announced more than six hours late is noise, not delivery. The
// platform retries a failing event for up to seven days; both handlers bound
// the chain themselves.
const PAGE_POST_RETRY_WINDOW_MS = 6 * 60 * 60_000;
// Outbox rows are operational state. Firestore TTL (firestore.indexes.json)
// removes them after the platform's own seven-day retry horizon; the words a
// row carries (the Page's name, the post's first line) are dropped earlier,
// the moment its fan-out completes.
const PAGE_POST_OUTBOX_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
const PAGE_POST_COMPLETED_LABEL = "New post from a Page you follow: a Page";
const PAGE_KINDS = Object.freeze(["business", "community"]);
const STOP_REASONS = Object.freeze(["source-gone", "pages-disabled", "expired"]);

function pagePostNotificationId(postId) {
  return `pagePost_${postId}`;
}

function pagePostSourcePath(postId) {
  return `pagePosts/${postId}`;
}

function pagePostEventId(postId, followerId) {
  return `page-post:${postId}:${followerId}`;
}

function cutToCodePoints(value, max) {
  const characters = Array.from(value);
  return characters.length > max
    ? `${characters.slice(0, max - 1).join("").trimEnd()}…`
    : value;
}

/**
 * The one-line preview a newer client shows under the title and the push
 * carries as its body: the post's own words, whitespace collapsed, at most
 * 120 characters. Empty for a photo or voice post without a caption.
 *
 * A Page post is public to every signed-in reader, so unlike a comment its
 * words may appear on a lock screen.
 */
function pagePostPreview(text) {
  if (typeof text !== "string") return "";
  const flat = text
    // Invisible and directional controls never reach a lock screen.
    .replace(/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁠-⁩﻿]/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
  return cutToCodePoints(flat, PAGE_POST_PREVIEW_MAX);
}

/**
 * The English sentence builds that do not know this type show as the row's
 * title (they render an unknown type as `system`). The server-authored words
 * come FIRST and the Page's free name is capped after them, so a name written
 * to read like a YO Voice notice cannot pose as one (the pagePostComment
 * rule, audit 2026-09-28).
 */
function pagePostTargetLabel(pageName) {
  const trimmed = typeof pageName === "string" ? pageName.replace(/\s+/gu, " ").trim() : "";
  const name = trimmed.length === 0
    ? "a Page"
    : cutToCodePoints(trimmed, PAGE_POST_LABEL_NAME_MAX);
  return `New post from a Page you follow: ${name}`;
}

function pagePostFanoutOutboxReference(postId, firestore = db) {
  const id = `page_post_${digest("page-post-fanout", postId).slice(0, 48)}`;
  return firestore.doc(`${PAGE_POST_FANOUT_COLLECTION}/${id}`);
}

function validOutbox(data) {
  return data?.schemaVersion === 1 &&
    typeof data.postId === "string" && data.postId.length > 0 &&
    typeof data.pageId === "string" && data.pageId.length > 0 &&
    data.sourcePath === pagePostSourcePath(data.postId) &&
    typeof data.sourceGeneration === "string" && data.sourceGeneration.length > 0 &&
    typeof data.targetLabel === "string" && data.targetLabel.length > 0 &&
    typeof data.postPreview === "string" &&
    data.postPreview.length <= PAGE_POST_PREVIEW_MAX * 2 &&
    PAGE_KINDS.includes(data.pageKind) &&
    (data.afterId === null || typeof data.afterId === "string") &&
    ["pending", "complete"].includes(data.status) &&
    (data.stoppedReason === null || STOP_REASONS.includes(data.stoppedReason)) &&
    Number.isSafeInteger(data.followers) && data.followers >= 0 &&
    Number.isSafeInteger(data.pages) && data.pages >= 0 &&
    Number.isSafeInteger(data.written) && data.written >= 0 &&
    typeof data.createdAt?.toMillis === "function" &&
    typeof data.expiresAt?.toMillis === "function";
}

const OUTBOX_IDENTITY_KEYS = Object.freeze([
  "postId",
  "pageId",
  "sourcePath",
  "sourceGeneration",
  "targetLabel",
  "postPreview",
  "pageKind",
]);
// What somebody wrote. Needed only while rows are still being written.
const OUTBOX_TEXT_KEYS = Object.freeze(["targetLabel", "postPreview"]);

/**
 * Creates the outbox once. A redelivered create event finds the same
 * identity and changes nothing; a DIFFERENT identity under the same post id
 * is a bug upstream and is refused rather than merged.
 */
async function ensurePagePostFanoutOutbox({
  postId,
  pageId,
  sourceGeneration,
  targetLabel,
  postPreview,
  pageKind,
  firestore = db,
  now = Timestamp.now(),
}) {
  const reference = pagePostFanoutOutboxReference(postId, firestore);
  const identity = {
    postId,
    pageId,
    sourcePath: pagePostSourcePath(postId),
    sourceGeneration,
    targetLabel,
    postPreview,
    pageKind,
  };
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (snapshot.exists) {
      const existing = snapshot.data();
      // A finished fan-out has dropped its words; only the ids still
      // identify it, and a redelivered create event must find it done.
      const keys = validOutbox(existing) && existing.status === "complete"
        ? OUTBOX_IDENTITY_KEYS.filter((key) => !OUTBOX_TEXT_KEYS.includes(key))
        : OUTBOX_IDENTITY_KEYS;
      if (!validOutbox(existing) ||
          keys.some((key) => existing[key] !== identity[key])) {
        throw new Error("page-post fanout outbox identity conflict");
      }
      return;
    }
    transaction.create(reference, {
      schemaVersion: 1,
      ...identity,
      afterId: null,
      status: "pending",
      stoppedReason: null,
      followers: 0,
      pages: 0,
      written: 0,
      createdAt: now,
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        now.toMillis() + PAGE_POST_OUTBOX_RETENTION_MS,
      ),
    });
  });
  return reference;
}

/**
 * Why a fan-out should stop before reading any follower, or null. One cheap
 * read pair per page instead of a refused transaction per follower: a post
 * that was deleted or held, or Pages switched off for everybody, ends the
 * fan-out. Everything recipient-specific stays in the per-row validator.
 */
async function fanoutStopReason(state, { firestore, nowMs }) {
  if (nowMs - state.createdAt.toMillis() > PAGE_POST_RETRY_WINDOW_MS) return "expired";
  // Lazy: the Pages graph stays out of this module's cold start.
  const { canonicalPagesActivation } = require("../pages/activation");
  const { canonicalPagePostData } = require("../pages/post_contract");
  const [post, activation] = await firestore.getAll(
    firestore.doc(state.sourcePath),
    firestore.doc("appConfig/pagesV1"),
  );
  const postData = canonicalPagePostData(post);
  if (!postData || postData.pageId !== state.pageId ||
      postData.status !== "published" ||
      documentGeneration(post, "createTime") !== state.sourceGeneration) {
    return "source-gone";
  }
  if (canonicalPagesActivation(activation).readAccess === "disabled") {
    return "pages-disabled";
  }
  return null;
}

function notifyFollowerOperation(state, firestore) {
  const notificationId = pagePostNotificationId(state.postId);
  const notificationShape = {
    type: PAGE_POST_NOTIFICATION_TYPE,
    actorId: state.pageId,
    targetId: state.postId,
    sourcePath: state.sourcePath,
    sourceGeneration: state.sourceGeneration,
  };
  return (followerId) => createNotificationForEvent({
    eventId: pagePostEventId(state.postId, followerId),
    recipientId: followerId,
    actorId: state.pageId,
    type: PAGE_POST_NOTIFICATION_TYPE,
    notificationId,
    targetId: state.postId,
    targetLabel: state.targetLabel,
    sourcePath: state.sourcePath,
    sourceGeneration: state.sourceGeneration,
    extraFields: {
      pageKind: state.pageKind,
      postPreview: state.postPreview.length > 0 ? state.postPreview : null,
    },
    validate: (transaction) => pagePostPublishedSourceIsCurrent({
      recipientId: followerId,
      notification: notificationShape,
      reader: transaction,
      firestore,
    }),
    firestore,
  });
}

/**
 * Processes ONE page of followers and commits the cursor. Safe to call any
 * number of times for the same outbox state: rows are idempotent, and a
 * cursor that somebody else already moved makes this call a no-op ("stale").
 */
async function processPagePostFanoutOutbox(reference, {
  firestore = db,
  pageLoader = undefined,
  notify = null,
  pageSize = PAGE_POST_FOLLOWER_PAGE_SIZE,
  nowMs = Date.now(),
} = {}) {
  const snapshot = await reference.get();
  if (!snapshot.exists) return { state: "missing" };
  const state = snapshot.data();
  // A malformed outbox cannot heal by being retried for seven days.
  if (!validOutbox(state)) return { state: "malformed" };
  if (state.status === "complete") return { state: "complete" };
  const cursor = state.afterId;

  const stoppedReason = await fanoutStopReason(state, { firestore, nowMs });
  const page = stoppedReason !== null
    ? { afterId: cursor, complete: true, followers: 0, pages: 0, written: 0 }
    : await fanOutRoomLiveFollowers({
      afterId: cursor,
      concurrency: PAGE_POST_FANOUT_CONCURRENCY,
      firestore,
      hostId: state.pageId,
      maxPages: 1,
      notify: notify ?? notifyFollowerOperation(state, firestore),
      pageSize,
      ...(pageLoader ? { pageLoader } : {}),
    });

  const commit = await firestore.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(reference);
    const current = currentSnapshot.data();
    if (!currentSnapshot.exists || !validOutbox(current) ||
        current.status !== "pending" || current.afterId !== cursor) {
      return "stale";
    }
    transaction.update(reference, {
      afterId: page.afterId,
      status: page.complete ? "complete" : "pending",
      stoppedReason,
      followers: current.followers + page.followers,
      pages: current.pages + page.pages,
      written: current.written + page.written,
      updatedAt: FieldValue.serverTimestamp(),
      // Done: the outbox keeps ids and counters, not the post's words or
      // the Page's name, for the days until TTL removes it.
      ...(page.complete
        ? { postPreview: "", targetLabel: PAGE_POST_COMPLETED_LABEL }
        : {}),
    });
    return page.complete ? "complete" : "pending";
  });
  return { ...page, state: commit, stoppedReason };
}

function eventIsTooOld(event, nowMs = Date.now()) {
  const raw = event?.time;
  if (typeof raw !== "string" || raw.length === 0) return false;
  const emittedMs = Date.parse(raw);
  if (!Number.isFinite(emittedMs)) return false;
  return nowMs - emittedMs > PAGE_POST_RETRY_WINDOW_MS;
}

async function handlePagePostCreated(event, { firestore = db } = {}) {
  const snapshot = event.data;
  if (!snapshot?.exists) return null;
  const postId = event.params?.postId;
  if (eventIsTooOld(event)) {
    logger.warn("Abandoning a stale Page post notification", { postId });
    return null;
  }
  const { canonicalPageOrNull } = require("../pages/contract");
  const { canonicalPagePostData } = require("../pages/post_contract");
  const post = canonicalPagePostData(snapshot);
  // Only a post that is born published announces itself. A held post that
  // moderation restores later is not "new", and a malformed one never is.
  if (!post || post.postId !== postId || post.status !== "published") return null;
  const sourceGeneration = documentGeneration(snapshot, "createTime");
  if (typeof sourceGeneration !== "string") return null;
  const page = canonicalPageOrNull(
    await firestore.doc(`pages/${post.pageId}`).get(),
    post.pageId,
  );
  if (!page) {
    logger.warn("Page post notification skipped: the Page is not canonical", {
      postId,
    });
    return null;
  }
  const reference = await ensurePagePostFanoutOutbox({
    postId,
    pageId: post.pageId,
    sourceGeneration,
    targetLabel: pagePostTargetLabel(page.displayName),
    postPreview: pagePostPreview(post.text),
    pageKind: page.kind,
    firestore,
  });
  // The outbox trigger owns every page, the first one included: one worker
  // per cursor instead of this handler racing it for page one.
  return reference.path;
}

async function handlePagePostFanoutOutboxWritten(event, options = {}) {
  const after = event.data?.after;
  if (!after?.exists || after.data()?.status !== "pending") return null;
  const fanout = await processPagePostFanoutOutbox(after.ref, options);
  if (fanout.state === "malformed") {
    logger.error("page post fanout outbox is malformed", {
      outboxId: event.params?.outboxId,
    });
    return fanout;
  }
  logger.info("page post notifications", {
    outboxId: event.params?.outboxId,
    state: fanout.state,
    stoppedReason: fanout.stoppedReason ?? null,
    followers: fanout.followers ?? 0,
    written: fanout.written ?? 0,
  });
  return fanout;
}

const onPagePostCreated = onDocumentCreated(
  {
    document: "pagePosts/{postId}",
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 25,
    retry: true,
  },
  (event) => handlePagePostCreated(event),
);

const onPagePostFanoutOutboxWritten = onDocumentWritten(
  {
    document: `${PAGE_POST_FANOUT_COLLECTION}/{outboxId}`,
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
    maxInstances: 25,
    retry: true,
  },
  (event) => handlePagePostFanoutOutboxWritten(event),
);

module.exports = {
  PAGE_POST_FANOUT_COLLECTION,
  PAGE_POST_FOLLOWER_PAGE_SIZE,
  PAGE_POST_NOTIFICATION_TYPE,
  PAGE_POST_OUTBOX_RETENTION_MS,
  PAGE_POST_PREVIEW_MAX,
  PAGE_POST_RETRY_WINDOW_MS,
  ensurePagePostFanoutOutbox,
  handlePagePostCreated,
  handlePagePostFanoutOutboxWritten,
  onPagePostCreated,
  onPagePostFanoutOutboxWritten,
  pagePostEventId,
  pagePostFanoutOutboxReference,
  pagePostNotificationId,
  pagePostPreview,
  pagePostSourcePath,
  pagePostTargetLabel,
  processPagePostFanoutOutbox,
};

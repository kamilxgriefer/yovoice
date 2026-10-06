/**
 * The bell rows of "a Page you follow published a post" (ADR-237): their
 * names, and the two ways they are RETIRED.
 *
 * A row carries the post's first line. It must not outlive the right to read
 * that post:
 *
 *   retirePagePostNotifications(postId)
 *       every follower's row of one post, when the post stops being
 *       published (deleted, tombstoned, held or removed by a moderator, or
 *       gone with its owner's account). Rows are found with ONE collection
 *       group query on the row's own `sourcePath`, so a follower who has
 *       unfollowed since, or whose follow edge the account-deletion pipeline
 *       already removed, is found too. That query needs the
 *       COLLECTION_GROUP single-field index on `notifications.sourcePath`
 *       declared in firestore.indexes.json (ADR-007: automatic single-field
 *       indexes are COLLECTION scope only and the emulator enforces neither).
 *
 *   retirePagePostNotificationsBetween(recipientId, pageId)
 *       one account's rows from one Page, when a block lands between them.
 *       Two equality filters on one inbox: served by merging the automatic
 *       single-field indexes, no composite needed.
 *
 * Both only DELETE rows the server itself wrote, are idempotent and are
 * bounded per call. No SDK trigger is imported here, so a callable may
 * require this module without pulling the fan-out's graph into its cold
 * start.
 */
const { isValidOpaqueUid } = require("../achievements/identity");
const { db } = require("../utils/firestore");

const PAGE_POST_NOTIFICATION_TYPE = "pagePostPublished";
const PAGE_POST_RETIRE_BATCH = 400;
// 400 x 250 = 100,000 rows per call; the caller retries when a call is cut
// short, and every finished batch is already gone.
const PAGE_POST_RETIRE_MAX_BATCHES = 250;
const PAGE_POST_RETIRE_BUDGET_MS = 240_000;
const PAGE_POST_BLOCK_RETIRE_BATCH = 200;
const PAGE_POST_BLOCK_RETIRE_MAX_BATCHES = 10;
// A post id is one path segment: no slash, bounded.
const SAFE_SEGMENT = /^[A-Za-z0-9_-]{1,128}$/u;

function pagePostNotificationId(postId) {
  return `pagePost_${postId}`;
}

function pagePostSourcePath(postId) {
  return `pagePosts/${postId}`;
}

/** The collection-group query behind `retirePagePostNotifications`. */
function pagePostNotificationsQuery(postId, firestore = db) {
  return firestore.collectionGroup("notifications")
    .where("sourcePath", "==", pagePostSourcePath(postId));
}

/** True for `users/{uid}/notifications/pagePost_{postId}` of this type. */
function isPagePostRow(document, postId) {
  const owner = document.ref.parent?.parent;
  return document.id === pagePostNotificationId(postId) &&
    document.get("type") === PAGE_POST_NOTIFICATION_TYPE &&
    owner?.parent?.id === "users" && owner.parent.parent === null;
}

/**
 * Deletes every follower's bell row of `postId`. Returns `{deleted, done}`;
 * `done` is false only when the batch or time budget ran out first, and the
 * caller then runs it again (rows already deleted stay deleted).
 */
async function retirePagePostNotifications(postId, {
  firestore = db,
  batchSize = PAGE_POST_RETIRE_BATCH,
  maxBatches = PAGE_POST_RETIRE_MAX_BATCHES,
  budgetMs = PAGE_POST_RETIRE_BUDGET_MS,
  clock = Date.now,
} = {}) {
  if (typeof postId !== "string" || !SAFE_SEGMENT.test(postId)) {
    throw new TypeError("A Page post id is required.");
  }
  if (!Number.isSafeInteger(batchSize) || batchSize < 1 || batchSize > 500) {
    throw new TypeError("retire batch size must be between 1 and 500.");
  }
  const startedAt = clock();
  let deleted = 0;
  let cursor = null;
  for (let round = 0; round < maxBatches; round += 1) {
    if (clock() - startedAt > budgetMs) return { deleted, done: false };
    let query = pagePostNotificationsQuery(postId, firestore).limit(batchSize);
    // A cursor rather than "query again until empty": a document this
    // function refuses to delete must not be read forever.
    if (cursor !== null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) return { deleted, done: true };
    const batch = firestore.batch();
    let writes = 0;
    for (const document of snapshot.docs) {
      // The query matches one field. Only the row this feature writes, at
      // the id it writes it under, in a user's own inbox, is ever deleted.
      if (!isPagePostRow(document, postId)) continue;
      batch.delete(document.ref);
      writes += 1;
    }
    if (writes > 0) await batch.commit();
    deleted += writes;
    if (snapshot.size < batchSize) return { deleted, done: true };
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
  return { deleted, done: false };
}

/**
 * Deletes `recipientId`'s rows about posts of the Page `pageId`. Bounded:
 * at most 2,000 rows a call, which is far more than one Page can have
 * written to one inbox.
 */
async function retirePagePostNotificationsBetween(recipientId, pageId, {
  firestore = db,
  batchSize = PAGE_POST_BLOCK_RETIRE_BATCH,
  maxBatches = PAGE_POST_BLOCK_RETIRE_MAX_BATCHES,
} = {}) {
  if (!isValidOpaqueUid(recipientId) || !isValidOpaqueUid(pageId) ||
      recipientId === pageId) {
    return { deleted: 0, done: true };
  }
  let deleted = 0;
  for (let round = 0; round < maxBatches; round += 1) {
    const snapshot = await firestore
      .collection(`users/${recipientId}/notifications`)
      .where("type", "==", PAGE_POST_NOTIFICATION_TYPE)
      .where("actorId", "==", pageId)
      .limit(batchSize)
      .get();
    if (snapshot.empty) return { deleted, done: true };
    const batch = firestore.batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
    deleted += snapshot.size;
    if (snapshot.size < batchSize) return { deleted, done: true };
  }
  return { deleted, done: false };
}

module.exports = {
  PAGE_POST_NOTIFICATION_TYPE,
  PAGE_POST_RETIRE_BATCH,
  pagePostNotificationId,
  pagePostNotificationsQuery,
  pagePostSourcePath,
  retirePagePostNotifications,
  retirePagePostNotificationsBetween,
};

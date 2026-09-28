// Comment likes (ADR-230): the flat, server-only edge store keyed by
// `commentKey`, shared by Voice Moment and Yeel comments.
//
//   commentLikes/{commentKey}:{uid}
//     { schemaVersion: 1, parentKind: "voiceMoment" | "reel", parentId,
//       commentId, commentKey, userId (== the id suffix), createdAt }
//
// Comment documents themselves stay byte-identical (their validators take an
// EXACT key set), which is why the edges live in their own collection with a
// distinct collection id instead of under `…/comments/{c}/likes`.
//
//   commentLikeCounters/{commentKey}
//     { schemaVersion: 1, parentKind, parentId, commentId, commentKey,
//       likeCount (safe integer >= 0), updatedAt }
//
// An absent counter IS zero (the storedEngagementCount rule). The edge and
// the counter only ever move together, inside one transaction of
// setMomentCommentLikeV1 / setReelCommentLikeV1, so an edge without a
// counter (or a counter at 0 beside an edge) is corruption: the toggle fails
// closed with data-loss, while every READ path (the V2 views'
// includeCommentLikes, the likers list) skips a malformed edge or counter as
// absent / 0 so a malformed document is never an identity oracle.
//
// The module needs no Firebase SDK: every function takes the database handle
// it works on, which keeps it free for the cold-start graph of every caller
// (moments/integrity.js, reels/service.js, notifications/engagement.js).

const {
  SAFE_ID,
  fail,
  incrementCanonicalCount,
  isValidOpaqueUid,
  timestampMillis,
} = require("../integrity/guards");

const COMMENT_LIKES_COLLECTION = "commentLikes";
const COMMENT_LIKE_COUNTERS_COLLECTION = "commentLikeCounters";
const COMMENT_LIKE_SCHEMA_VERSION = 1;
// Firestore's ceiling for an `in` filter. The views pass at most seven ids
// (MAX_THREAD_COMMENTS / MAX_REEL_THREAD_COMMENTS), so one query each.
const COMMENT_LIKE_IN_LIMIT = 30;
// What an includeCommentLikes view adds on top of its unflagged cost: one
// counters query and one caller-edges query. Each is billed at least one
// read even when it returns nothing.
const COMMENT_LIKE_VIEW_READS = 2;
// Edges deleted per batch when a comment's likes are purged.
const COMMENT_LIKE_PURGE_BATCH_SIZE = 400;
const COMMENT_LIKE_PARENT_PREFIX = Object.freeze({
  voiceMoment: "v",
  reel: "r",
});
const COMMENT_LIKE_EDGE_KEYS = Object.freeze([
  "commentId",
  "commentKey",
  "createdAt",
  "parentId",
  "parentKind",
  "schemaVersion",
  "userId",
]);
const COMMENT_LIKE_COUNTER_KEYS = Object.freeze([
  "commentId",
  "commentKey",
  "likeCount",
  "parentId",
  "parentKind",
  "schemaVersion",
  "updatedAt",
]);

function requireSafeComponent(value, label) {
  if (typeof value !== "string" || !SAFE_ID.test(value)) {
    throw new TypeError(`${label} must be a safe id.`);
  }
  return value;
}

// "v:" + momentId + ":" + commentId, or "r:" + reelId + ":" + commentId.
// Every component matches SAFE_ID, which excludes ":", so the key is
// unambiguous.
function commentLikeKey(parentKind, parentId, commentId) {
  const prefix = COMMENT_LIKE_PARENT_PREFIX[parentKind];
  if (prefix === undefined) {
    throw new TypeError(`Unknown comment like parent kind: ${parentKind}`);
  }
  return `${prefix}:${requireSafeComponent(parentId, "parentId")}:${
    requireSafeComponent(commentId, "commentId")}`;
}

function commentLikeEdgeId(commentKey, uid) {
  if (typeof commentKey !== "string" || commentKey.length === 0) {
    throw new TypeError("commentKey is required.");
  }
  if (!isValidOpaqueUid(uid)) throw new TypeError("uid is invalid.");
  return `${commentKey}:${uid}`;
}

// The uid an edge document id names for `commentKey`, or null when the id is
// not `${commentKey}:{uid}`.
function commentLikeUserIdOf(edgeId, commentKey) {
  const prefix = `${commentKey}:`;
  if (typeof edgeId !== "string" || !edgeId.startsWith(prefix)) return null;
  const uid = edgeId.slice(prefix.length);
  return isValidOpaqueUid(uid) ? uid : null;
}

// false when the edge does not exist; true when it is the exact canonical
// edge for (parent, comment, user); data-loss otherwise. The same contract as
// validateMomentLike / validateReelLike: a toggle fails closed on a malformed
// edge, and a read path catches the error and skips the edge, so a malformed
// edge is never used as an identity oracle.
function validateCommentLike(snapshot, { parentKind, parentId, commentId, userId }) {
  if (!snapshot?.exists) return false;
  const commentKey = commentLikeKey(parentKind, parentId, commentId);
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  if (
    keys.length !== COMMENT_LIKE_EDGE_KEYS.length ||
    keys.some((key, index) => key !== COMMENT_LIKE_EDGE_KEYS[index]) ||
    data.schemaVersion !== COMMENT_LIKE_SCHEMA_VERSION ||
    data.parentKind !== parentKind ||
    data.parentId !== parentId ||
    data.commentId !== commentId ||
    data.commentKey !== commentKey ||
    data.userId !== userId ||
    !isValidOpaqueUid(userId) ||
    snapshot.id !== commentLikeEdgeId(commentKey, userId) ||
    timestampMillis(data.createdAt) === null
  ) {
    fail("data-loss", "The comment like edge is not canonical.");
  }
  return true;
}

// The views' opt-in flag: absent, or the literal `true`. Anything else,
// `false` and `null` included, is invalid-argument, so a client can never
// believe it asked for comment-like state it did not get.
function requireIncludeCommentLikes(value) {
  if (value === undefined) return false;
  if (value !== true) {
    fail("invalid-argument", "includeCommentLikes must be true when present.");
  }
  return true;
}

const COMMENT_REFUSAL_CODES = Object.freeze(new Set([
  "not-found",
  "failed-precondition",
  "permission-denied",
  "data-loss",
]));

// One refusal for every parent or comment reason (missing, expired,
// malformed, hidden by its author's audience), so a comment-like toggle is
// not an oracle for comment ids or for other people's state. Any other
// error (a raw driver error included) is returned unchanged.
function commentUnavailable(error) {
  if (COMMENT_REFUSAL_CODES.has(error?.code)) {
    try {
      fail("permission-denied", "This comment is unavailable.");
    } catch (refusal) {
      return refusal;
    }
  }
  return error;
}

// Whether `error` is one of the reasons commentUnavailable collapses.
function isCommentRefusal(error) {
  return COMMENT_REFUSAL_CODES.has(error?.code);
}

// The likeCount answered to an unlike of a held like whose Moment/Yeel or
// comment the caller can no longer see (blocked, private, restricted). The
// unlike still runs (review S9), but the fresh count is not disclosed.
const HIDDEN_COMMENT_LIKE_COUNT = 0;

function exactKeys(data, expected) {
  const keys = Object.keys(data).sort();
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]);
}

// The stored count of a comment: 0 when the counter does not exist; the
// exact canonical likeCount otherwise; data-loss for anything else.
function validateCommentLikeCounter(snapshot, { parentKind, parentId, commentId }) {
  if (!snapshot?.exists) return 0;
  const commentKey = commentLikeKey(parentKind, parentId, commentId);
  const data = snapshot.data() ?? {};
  if (
    !exactKeys(data, COMMENT_LIKE_COUNTER_KEYS) ||
    data.schemaVersion !== COMMENT_LIKE_SCHEMA_VERSION ||
    data.parentKind !== parentKind ||
    data.parentId !== parentId ||
    data.commentId !== commentId ||
    data.commentKey !== commentKey ||
    snapshot.id !== commentKey ||
    !Number.isSafeInteger(data.likeCount) ||
    data.likeCount < 0 ||
    timestampMillis(data.updatedAt) === null
  ) {
    fail("data-loss", "The comment like counter is not canonical.");
  }
  return data.likeCount;
}

// Everything one (comment, user) toggle touches.
function commentLikeReferences(db, { parentKind, parentId, commentId, userId }) {
  const commentKey = commentLikeKey(parentKind, parentId, commentId);
  return {
    commentKey,
    edgeRef: db.doc(
      `${COMMENT_LIKES_COLLECTION}/${commentLikeEdgeId(commentKey, userId)}`,
    ),
    counterRef: db.doc(`${COMMENT_LIKE_COUNTERS_COLLECTION}/${commentKey}`),
  };
}

// The caller's current state and the stored count, validated for a WRITE:
// a malformed edge or counter, an edge with no counter, or a counter at 0
// beside an edge is data-loss. Nothing is written by this function.
function commentLikeWriteState(target, { edgeSnapshot, counterSnapshot }) {
  const liked = validateCommentLike(edgeSnapshot, target);
  const likeCount = validateCommentLikeCounter(counterSnapshot, target);
  if (liked && (!counterSnapshot?.exists || likeCount === 0)) {
    fail("data-loss", "The comment like counter is missing for an existing like.");
  }
  return { liked, likeCount };
}

// Applies one toggle inside the caller's transaction and returns the result
// fields. `state` is commentLikeWriteState's answer from the same
// transaction's reads; `now` is the transaction's server time.
function applyCommentLikeToggle(transaction, {
  references,
  target,
  state,
  liked,
  now,
}) {
  const changed = state.liked !== liked;
  let likeCount = state.likeCount;
  if (!changed) return { changed, likeCount };
  if (liked) {
    likeCount = incrementCanonicalCount(likeCount, "comment likeCount");
    transaction.create(references.edgeRef, {
      schemaVersion: COMMENT_LIKE_SCHEMA_VERSION,
      parentKind: target.parentKind,
      parentId: target.parentId,
      commentId: target.commentId,
      commentKey: references.commentKey,
      userId: target.userId,
      createdAt: now,
    });
  } else {
    // commentLikeWriteState already refused a counter at 0 beside an edge.
    likeCount -= 1;
    transaction.delete(references.edgeRef);
  }
  transaction.set(references.counterRef, {
    schemaVersion: COMMENT_LIKE_SCHEMA_VERSION,
    parentKind: target.parentKind,
    parentId: target.parentId,
    commentId: target.commentId,
    commentKey: references.commentKey,
    likeCount,
    updatedAt: now,
  });
  return { changed, likeCount };
}

function chunks(values, size) {
  const result = [];
  for (let start = 0; start < values.length; start += size) {
    result.push(values.slice(start, start + size));
  }
  return result;
}

// The V2 views' opt-in `commentLikes` map: exactly one entry per id in
// `commentIds` (the PROJECTED comments, nothing for withheld ones),
// `{ likeCount, callerLiked }`. Two plain queries outside any transaction:
// the counters `commentKey in keys`, and the caller's own edges
// `userId == viewer && commentKey in keys`. A malformed counter reads as 0
// and a malformed edge as "not liked": a read path never fails, and never
// reveals, because of one bad document.
async function loadCommentLikeStates({
  db,
  parentKind,
  parentId,
  commentIds,
  viewerId,
}) {
  if (!isValidOpaqueUid(viewerId)) throw new TypeError("viewerId is invalid.");
  const states = new Map();
  const keyToCommentId = new Map();
  for (const commentId of commentIds) {
    states.set(commentId, { likeCount: 0, callerLiked: false });
    // An id no toggle could ever have written (requireId refuses it) has no
    // likes; it is answered without being put into a query.
    if (typeof commentId !== "string" || !SAFE_ID.test(commentId)) continue;
    keyToCommentId.set(commentLikeKey(parentKind, parentId, commentId), commentId);
  }
  const keys = [...keyToCommentId.keys()];
  for (const group of chunks(keys, COMMENT_LIKE_IN_LIMIT)) {
    const [counters, edges] = await Promise.all([
      db.collection(COMMENT_LIKE_COUNTERS_COLLECTION)
        .where("commentKey", "in", group)
        .get(),
      db.collection(COMMENT_LIKES_COLLECTION)
        .where("userId", "==", viewerId)
        .where("commentKey", "in", group)
        .get(),
    ]);
    for (const document of counters.docs) {
      const commentId = keyToCommentId.get(document.id);
      if (commentId === undefined) continue;
      try {
        states.get(commentId).likeCount = validateCommentLikeCounter(document, {
          parentKind,
          parentId,
          commentId,
        });
      } catch (_) {
        // A malformed counter is treated as absent.
      }
    }
    for (const document of edges.docs) {
      const commentKey = document.data()?.commentKey;
      const commentId = keyToCommentId.get(commentKey);
      if (commentId === undefined) continue;
      try {
        if (validateCommentLike(document, {
          parentKind,
          parentId,
          commentId,
          userId: viewerId,
        })) {
          states.get(commentId).callerLiked = true;
        }
      } catch (_) {
        // A malformed edge is treated as absent.
      }
    }
  }
  return Object.fromEntries(
    [...states.entries()].map(([commentId, state]) => [commentId, { ...state }]),
  );
}

// Deletes every like edge of one comment, then its counter. Idempotent: a
// redelivered trigger finds nothing and deletes nothing. The edges are paged
// by the equality filter alone (served by the automatic single-field index),
// because each committed batch removes exactly the documents it read.
async function purgeCommentLikes(firestore, commentKey, {
  batchSize = COMMENT_LIKE_PURGE_BATCH_SIZE,
} = {}) {
  if (typeof commentKey !== "string" || commentKey.length === 0) {
    throw new TypeError("commentKey is required.");
  }
  if (!Number.isSafeInteger(batchSize) || batchSize < 1 || batchSize > 500) {
    throw new TypeError("batchSize must be 1-500.");
  }
  let deleted = 0;
  for (;;) {
    const snapshot = await firestore
      .collection(COMMENT_LIKES_COLLECTION)
      .where("commentKey", "==", commentKey)
      .limit(batchSize)
      .get();
    if (snapshot.docs.length === 0) break;
    const batch = firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    deleted += snapshot.docs.length;
    if (snapshot.docs.length < batchSize) break;
  }
  await firestore.doc(`${COMMENT_LIKE_COUNTERS_COLLECTION}/${commentKey}`).delete();
  return { deleted };
}

module.exports = {
  COMMENT_LIKES_COLLECTION,
  COMMENT_LIKE_COUNTERS_COLLECTION,
  COMMENT_LIKE_COUNTER_KEYS,
  COMMENT_LIKE_EDGE_KEYS,
  COMMENT_LIKE_IN_LIMIT,
  COMMENT_LIKE_PURGE_BATCH_SIZE,
  COMMENT_LIKE_SCHEMA_VERSION,
  COMMENT_LIKE_VIEW_READS,
  HIDDEN_COMMENT_LIKE_COUNT,
  applyCommentLikeToggle,
  commentLikeEdgeId,
  commentLikeKey,
  commentLikeReferences,
  commentLikeUserIdOf,
  commentLikeWriteState,
  commentUnavailable,
  isCommentRefusal,
  loadCommentLikeStates,
  purgeCommentLikes,
  requireIncludeCommentLikes,
  validateCommentLike,
  validateCommentLikeCounter,
};

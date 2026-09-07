const {
  fail,
  isValidOpaqueUid,
  nonNegativeCount,
  requireId,
  timestampMillis,
} = require("../integrity/guards");
const { exactStoredObject } = require("./contract");

// ---------------------------------------------------------------------------
// Reel engagement contract (likes and comments).
//
// This mirrors the Voice Moment engagement contract in
// functions/moments/integrity.js rather than inventing a second shape:
// a like is one server-written edge keyed by the liker's uid, a comment is
// one server-written child document, and both aggregate into counters on the
// Reel root that only an Admin SDK transaction ever advances.
//
// The counters are DELIBERATELY OPTIONAL on the root. Every Reel published
// before this contract carries neither key, and no backfill runs: an absent
// counter IS zero, everywhere, forever. The first like or comment
// materializes the field through a transactional update, so an old Reel and
// a new one converge on the same shape without a migration and without a
// window where a half-written counter could be read as authority.
// ---------------------------------------------------------------------------

const REEL_COMMENT_SCHEMA_VERSION = 1;
const REEL_LIKE_SCHEMA_VERSION = 1;
const REEL_VIEW_SCHEMA_VERSION = 2;
const MAX_REEL_COMMENT_LENGTH = 1000;
const MAX_REEL_THREAD_COMMENTS = 7;
const MAX_REEL_COMMENT_CURSOR_LENGTH = 256;
// Only text comments exist today. `type` and the always-null
// `durationSeconds` are the same two fields a Voice Moment comment carries,
// so a later voice reply is an additive branch here rather than a schema
// change that would strand already-written comments.
const REEL_COMMENT_TYPES = new Set(["text"]);

// An engagement counter that is absent means a Reel published before this
// contract existed. Absent is exactly zero; null, a float, a string or a
// negative number is corruption and must fail closed rather than default.
function storedEngagementCount(value, label) {
  if (value === undefined) return 0;
  return nonNegativeCount(value, label);
}

function validateReelLike(snapshot, reelId, userId) {
  if (!snapshot?.exists) return false;
  exactStoredObject(
    snapshot.data() ?? {},
    ["createdAt", "reelId", "schemaVersion", "userId"],
    "Reel like edge",
  );
  const value = snapshot.data() ?? {};
  if (
    value.schemaVersion !== REEL_LIKE_SCHEMA_VERSION ||
    value.userId !== userId ||
    value.reelId !== reelId ||
    timestampMillis(value.createdAt) === null
  ) {
    fail("data-loss", "The Reel like edge is not canonical.");
  }
  return true;
}

function validateReelComment(snapshot, reelId) {
  if (!snapshot?.exists) fail("not-found", "The comment does not exist.");
  const value = exactStoredObject(
    snapshot.data() ?? {},
    [
      "authorId",
      "authorName",
      "createdAt",
      "durationSeconds",
      "reelId",
      "schemaVersion",
      "text",
      "type",
    ],
    "Reel comment",
  );
  if (
    value.schemaVersion !== REEL_COMMENT_SCHEMA_VERSION ||
    !REEL_COMMENT_TYPES.has(value.type) ||
    value.reelId !== reelId ||
    !isValidOpaqueUid(value.authorId) ||
    typeof value.authorName !== "string" ||
    value.authorName !== value.authorName.trim() ||
    value.authorName.length < 1 ||
    value.authorName.length > 80 ||
    typeof value.text !== "string" ||
    value.text !== value.text.trim() ||
    value.text.length < 1 ||
    value.text.length > MAX_REEL_COMMENT_LENGTH ||
    // Reserved for a future voice reply; a text comment carries no duration.
    value.durationSeconds !== null ||
    timestampMillis(value.createdAt) === null
  ) {
    fail("data-loss", "The Reel comment is malformed.");
  }
  return { ...value, id: snapshot.id };
}

// The projected author name is the one the server captured from the canonical
// public profile at write time — the same choice the Reel root itself makes
// for `authorName`, and the reason the feed does not spend a profile read per
// item. Artwork is never copied into a content projection; a renderer
// resolves it through its own short-lived, viewer-authorized media grant.
function reelCommentProjection(commentId, data) {
  return {
    schemaVersion: REEL_COMMENT_SCHEMA_VERSION,
    commentId,
    type: data.type,
    authorId: data.authorId,
    authorName: data.authorName,
    authorPhotoUrl: null,
    text: data.text,
    durationSeconds: data.durationSeconds,
    createdAtMillis: timestampMillis(data.createdAt),
  };
}

function encodeReelCommentCursor({ reelId, id, createdAtMillis }) {
  if (!Number.isSafeInteger(createdAtMillis) || createdAtMillis < 0) {
    fail("data-loss", "The Reel comment page boundary is malformed.");
  }
  return Buffer.from(
    JSON.stringify({
      schemaVersion: 1,
      kind: "reelComment",
      reelId,
      id,
      createdAtMillis,
    }),
    "utf8",
  ).toString("base64url");
}

function decodeReelCommentCursor(value, { reelId }) {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > MAX_REEL_COMMENT_CURSOR_LENGTH ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    fail("invalid-argument", "commentCursor is invalid.");
  }
  try {
    const decoded = Buffer.from(value, "base64url");
    if (
      decoded.length > MAX_REEL_COMMENT_CURSOR_LENGTH ||
      decoded.toString("base64url") !== value
    ) {
      fail("invalid-argument", "commentCursor is invalid.");
    }
    const cursor = JSON.parse(decoded.toString("utf8"));
    const expectedKeys = [
      "createdAtMillis",
      "id",
      "kind",
      "reelId",
      "schemaVersion",
    ];
    const keys =
      cursor && typeof cursor === "object" && !Array.isArray(cursor)
        ? Object.keys(cursor).sort()
        : [];
    if (
      keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      cursor.schemaVersion !== 1 ||
      cursor.kind !== "reelComment" ||
      // A cursor is scoped to the Reel that issued it. Replaying one against
      // another Reel is refused rather than silently paging the wrong thread.
      cursor.reelId !== reelId ||
      !Number.isSafeInteger(cursor.createdAtMillis) ||
      cursor.createdAtMillis < 0
    ) {
      fail("invalid-argument", "commentCursor is invalid.");
    }
    requireId(cursor.id, "commentCursor id");
    return cursor;
  } catch (error) {
    if (error?.code === "invalid-argument") throw error;
    fail("invalid-argument", "commentCursor is invalid.");
  }
}

module.exports = {
  MAX_REEL_COMMENT_CURSOR_LENGTH,
  MAX_REEL_COMMENT_LENGTH,
  MAX_REEL_THREAD_COMMENTS,
  REEL_COMMENT_SCHEMA_VERSION,
  REEL_COMMENT_TYPES,
  REEL_LIKE_SCHEMA_VERSION,
  REEL_VIEW_SCHEMA_VERSION,
  decodeReelCommentCursor,
  encodeReelCommentCursor,
  reelCommentProjection,
  storedEngagementCount,
  validateReelComment,
  validateReelLike,
};

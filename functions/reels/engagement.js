const {
  digest,
  fail,
  isValidOpaqueUid,
  nonNegativeCount,
  requireId,
  timestampMillis,
} = require("../integrity/guards");
const { REEL_SCHEMA_VERSION, exactStoredObject } = require("./contract");
// THE VOICE MOMENT AUDIO GUARD IS IMPORTED, NOT COPIED. A Reel voice comment
// and a Voice Moment voice reply are the same bytes under the same limits
// (512 B - 12 MiB, audio/mp4 | audio/m4a | audio/x-m4a, generation must match
// the one the client finalized, custom metadata exactly the expected keys plus
// Firebase's own download-token key). Re-implementing it here would be a
// second copy of a security predicate that has to stay identical forever.
// functions/moments/integrity.js requires only node:crypto, ../utils/server_access
// and ../integrity/guards, so this adds no SDK and no cycle to the cold start.
const { validateStoredAudio } = require("../moments/integrity");

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
// `type` and `durationSeconds` were reserved from the first day of this
// contract precisely so a voice comment could be added as an ADDITIVE BRANCH
// rather than a schema change. That is what happened: a text comment is
// byte-for-byte the shape it always was (the exact eight keys, a null
// duration, `schemaVersion` still 1, no backfill), and a voice comment is the
// same eight keys plus the four media descriptors a private-media grant needs.
// Nothing already written changes meaning, and a reader that only knows text
// still validates every text comment it ever validated.
const REEL_COMMENT_TYPES = new Set(["text", "voice"]);

// The stored shape of a voice comment, enumerated once. Text keeps the exact
// eight-key object; voice adds exactly four, and NOTHING else is accepted in
// either direction — an extra key is corruption, not an upgrade.
const REEL_TEXT_COMMENT_KEYS = Object.freeze([
  "authorId",
  "authorName",
  "createdAt",
  "durationSeconds",
  "reelId",
  "schemaVersion",
  "text",
  "type",
]);
const REEL_VOICE_COMMENT_KEYS = Object.freeze([
  ...REEL_TEXT_COMMENT_KEYS,
  "mediaContentType",
  "mediaGeneration",
  "mediaSize",
  "storagePath",
]);

// The recording limits, identical to the Voice reply's and to the recorder the
// client already ships (1-60 s, caption <= 140 characters and MAY BE EMPTY —
// a voice comment whose whole content is the audio is the normal case).
const MIN_REEL_VOICE_COMMENT_SECONDS = 1;
const MAX_REEL_VOICE_COMMENT_SECONDS = 60;
const MAX_REEL_VOICE_COMMENT_TEXT_LENGTH = 140;
// Mirrors of the bounds validateStoredAudio enforces on the object itself
// (functions/moments/integrity.js MIN_AUDIO_BYTES / MAX_AUDIO_BYTES /
// AUDIO_TYPES). They are restated here because the STORED DOCUMENT carries a
// copy of size and content type, and a document whose copy disagrees with the
// object is corruption that must fail closed at read time, not only at write
// time. test/reel_voice_comments.test.js pins them against the real guard.
const MIN_REEL_VOICE_COMMENT_BYTES = 512;
const MAX_REEL_VOICE_COMMENT_BYTES = 12 * 1024 * 1024;
const REEL_VOICE_COMMENT_AUDIO_TYPES = Object.freeze([
  "audio/mp4",
  "audio/m4a",
  "audio/x-m4a",
]);
const REEL_VOICE_COMMENT_GENERATION_PATTERN = /^[0-9]{1,30}$/u;
// A canonical comment id is `reelCommentIdFor` (a 40-character hex digest of
// uid + reelId + requestId). The object name is bound to it, which is what
// makes one comment document unable to describe another comment's bytes.
const REEL_VOICE_COMMENT_ID_PATTERN = /^[a-f0-9]{40}$/u;

// The one place the object name is derived. Storage Rules spell the same
// string; the two are pinned against each other by the emulator suite.
function reelVoiceCommentStoragePath(ownerId, reelId, commentId) {
  return `reel_voice_comments/${ownerId}/${reelId}/${commentId}.m4a`;
}

// True only for the exact object one (owner, reel, comment) triple may hold.
// Deliberately NOT a widening of isCanonicalCleanupPath in service.js: that
// predicate guards the Reel's own media/backing-audio pair, and making it
// answer for a third shape would put voice-comment paths inside the same
// positional `index === 0 ? media : backingAudio` reasoning they have nothing
// to do with.
function isCanonicalReelVoiceCommentPath(path, ownerId, reelId, commentId) {
  return typeof path === "string" &&
    isValidOpaqueUid(ownerId) &&
    typeof reelId === "string" &&
    typeof commentId === "string" &&
    REEL_VOICE_COMMENT_ID_PATTERN.test(commentId) &&
    path === reelVoiceCommentStoragePath(ownerId, reelId, commentId);
}

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
  const raw = snapshot.data() ?? {};
  // THE TYPE PICKS THE KEY SET, AND AN UNKNOWN TYPE PICKS NOTHING. Reading
  // `type` before the exact-shape check is safe because it is compared against
  // a closed set first: a document claiming a type this server does not know
  // is malformed, full stop, and never reaches a branch that could interpret
  // its other fields.
  if (!REEL_COMMENT_TYPES.has(raw.type)) {
    fail("data-loss", "The Reel comment is malformed.");
  }
  const isVoice = raw.type === "voice";
  const value = exactStoredObject(
    raw,
    isVoice ? REEL_VOICE_COMMENT_KEYS : REEL_TEXT_COMMENT_KEYS,
    "Reel comment",
  );
  if (
    value.schemaVersion !== REEL_COMMENT_SCHEMA_VERSION ||
    value.reelId !== reelId ||
    !isValidOpaqueUid(value.authorId) ||
    typeof value.authorName !== "string" ||
    value.authorName !== value.authorName.trim() ||
    value.authorName.length < 1 ||
    value.authorName.length > 80 ||
    typeof value.text !== "string" ||
    value.text !== value.text.trim() ||
    timestampMillis(value.createdAt) === null
  ) {
    fail("data-loss", "The Reel comment is malformed.");
  }
  if (isVoice) {
    if (
      // A caption is optional on a voice comment and bounded much tighter
      // than a text comment's body — it is a label for a recording, not a
      // second comment.
      value.text.length > MAX_REEL_VOICE_COMMENT_TEXT_LENGTH ||
      !Number.isSafeInteger(value.durationSeconds) ||
      value.durationSeconds < MIN_REEL_VOICE_COMMENT_SECONDS ||
      value.durationSeconds > MAX_REEL_VOICE_COMMENT_SECONDS ||
      // The object name is DERIVED, never trusted: a comment document can only
      // ever describe the one object that belongs to its own author, its own
      // Reel and its own document id.
      !isCanonicalReelVoiceCommentPath(
        value.storagePath,
        value.authorId,
        reelId,
        snapshot.id,
      ) ||
      typeof value.mediaGeneration !== "string" ||
      !REEL_VOICE_COMMENT_GENERATION_PATTERN.test(value.mediaGeneration) ||
      !Number.isSafeInteger(value.mediaSize) ||
      value.mediaSize < MIN_REEL_VOICE_COMMENT_BYTES ||
      value.mediaSize > MAX_REEL_VOICE_COMMENT_BYTES ||
      !REEL_VOICE_COMMENT_AUDIO_TYPES.includes(value.mediaContentType)
    ) {
      fail("data-loss", "The Reel comment is malformed.");
    }
  } else if (
    value.text.length < 1 ||
    value.text.length > MAX_REEL_COMMENT_LENGTH ||
    // A text comment carries no duration. Unchanged from the original
    // contract, and still the assertion that keeps the two shapes apart.
    value.durationSeconds !== null
  ) {
    fail("data-loss", "The Reel comment is malformed.");
  }
  return { ...value, id: snapshot.id };
}

// ---------------------------------------------------------------------------
// The cleanup row for one voice comment's bytes.
//
// It lives HERE, next to the path derivation, because four call sites write
// it — the comment's own author deleting it, the Reel's author removing it, a
// moderator acting on a report, and the expiry/deletion purge enumerating a
// whole thread — and three of those are in different files. One shared builder
// is the only way the outbox id, the kind and the object identity cannot drift
// apart between them; a drifting id would silently write a SECOND row that the
// worker then refuses as malformed, and the audio would never be deleted.
// ---------------------------------------------------------------------------

function reelVoiceCommentCleanupOutboxId(reelId, commentId) {
  return digest("reel-voice-comment-cleanup", reelId, commentId).slice(0, 40);
}

// `generation` is a string when the comment document still carries a
// trustworthy one, and null when it does not (an abandoned reservation, or a
// recovered document). Null deletes the object unconditionally, which is the
// same allowance the abandoned-draft cleanup row already makes.
function reelVoiceCommentCleanupRow({
  ownerId,
  reelId,
  commentId,
  storagePath,
  generation,
  now,
}) {
  return {
    schemaVersion: REEL_SCHEMA_VERSION,
    kind: "reelVoiceComment",
    ownerId,
    reelId,
    commentId,
    storageObjects: [{ path: storagePath, generation }],
    status: "pending",
    attemptCount: 0,
    phase: "delete",
    nextAttemptAt: now,
    leaseToken: null,
    leaseUntil: null,
    lastErrorCode: null,
    createdAt: now,
    updatedAt: now,
  };
}

// The Voice reply object guard, under the name the Reels code calls it by.
// This is an ALIAS, not a wrapper: the two are the same function object, which
// test/reel_voice_comments.test.js asserts by reference so the guarantee
// cannot quietly become "two similar implementations". `expected` is the exact
// custom-metadata identity Storage Rules also pinned at upload time:
// authorId, reelId, commentId and nothing else.
const validateReelVoiceCommentAudio = validateStoredAudio;

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
  MAX_REEL_VOICE_COMMENT_BYTES,
  MAX_REEL_VOICE_COMMENT_SECONDS,
  MAX_REEL_VOICE_COMMENT_TEXT_LENGTH,
  MIN_REEL_VOICE_COMMENT_BYTES,
  MIN_REEL_VOICE_COMMENT_SECONDS,
  REEL_COMMENT_SCHEMA_VERSION,
  REEL_COMMENT_TYPES,
  REEL_LIKE_SCHEMA_VERSION,
  REEL_VIEW_SCHEMA_VERSION,
  REEL_VOICE_COMMENT_AUDIO_TYPES,
  REEL_VOICE_COMMENT_GENERATION_PATTERN,
  REEL_VOICE_COMMENT_ID_PATTERN,
  decodeReelCommentCursor,
  encodeReelCommentCursor,
  isCanonicalReelVoiceCommentPath,
  reelCommentProjection,
  reelVoiceCommentCleanupOutboxId,
  reelVoiceCommentCleanupRow,
  reelVoiceCommentStoragePath,
  storedEngagementCount,
  validateReelComment,
  validateReelLike,
  validateReelVoiceCommentAudio,
};

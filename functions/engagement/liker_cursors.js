// Opaque, server-stored pagination cursors for "See who liked" (ADR-230).
//
// A plain startAfter(createdAt, docId) cursor would base64 the last edge's
// doc id, which IS the liker's uid, and that edge may be a hidden liker. So a
// cursor is 32 random bytes (base64url, 43 characters) naming a server-only
// document `likerPageCursors/{token}` that holds the position of the last
// CONSUMED candidate. The token decodes to no uid and no time.
//
// Stored shape (exact keys):
//   schemaVersion   1
//   viewerId        uid; must equal the caller
//   targetKey       64-hex digest of target type, ids and emoji filter
//   afterCreatedAt  content likes: createdAt of the last consumed edge | null
//   afterId         content likes: doc id of the last consumed edge     | null
//   afterEmojiIndex server messages: emoji index of the last consumed   | null
//   afterUid        server messages: uid of the last consumed reactor   | null
//   expiresAt       createdAt + 15 min (TTL field override deletes it)
//   createdAt
//
// A cursor may be reused until it expires, so a retry after a lost response
// works; with a fixed server page size a replay returns the same page. The
// document is written with a plain create() AFTER the scan, never inside a
// read-write transaction. Any resolution failure is one invalid-argument.

const crypto = require("node:crypto");

const {
  digest,
  fail,
  isValidOpaqueUid,
  requireId,
  timestampMillis,
} = require("../integrity/guards");
const { ALLOWED_DIRECT_REACTIONS } = require("../messaging/direct_reactions");

const LIKERS_CURSOR_COLLECTION = "likerPageCursors";
const LIKERS_CURSOR_TTL_MS = 15 * 60_000;
const LIKERS_CURSOR_TOKEN = /^[A-Za-z0-9_-]{43}$/u;
const LIKERS_CURSOR_KEYS = Object.freeze([
  "afterCreatedAt",
  "afterEmojiIndex",
  "afterId",
  "afterUid",
  "createdAt",
  "expiresAt",
  "schemaVersion",
  "targetKey",
  "viewerId",
]);
const LIKERS_TARGET_TYPES = Object.freeze([
  "voiceMoment",
  "voiceMomentComment",
  "reel",
  "reelComment",
  "serverMessage",
  // ADR-233 §2.6: a Premium Page post (content likes, opaque cursor).
  "pagePost",
]);
const TARGET_KEY = /^[a-f0-9]{64}$/u;
const MAX_POSITION_ID_LENGTH = 1500;
const CURSOR_INVALID_MESSAGE = "cursor is invalid.";

function cursorKindOf(targetType) {
  if (!LIKERS_TARGET_TYPES.includes(targetType)) {
    throw new TypeError(`Unknown likers target type: ${targetType}`);
  }
  return targetType === "serverMessage" ? "server" : "content";
}

// Page size is a server constant, so it is not part of the key.
function likersTargetKey({ targetType, ids, emoji = null }) {
  cursorKindOf(targetType);
  if (!Array.isArray(ids) || ids.length === 0) {
    throw new TypeError("ids are required.");
  }
  ids.forEach((id) => requireId(id, "target id"));
  if (emoji !== null && targetType !== "serverMessage") {
    throw new TypeError("Only serverMessage targets take an emoji filter.");
  }
  return digest("likers-target", targetType, ...ids, emoji ?? "");
}

function cursorInvalid() {
  fail("invalid-argument", CURSOR_INVALID_MESSAGE);
}

// The raw createdAt of a content edge goes back into startAfter(), so it is
// stored as read. Canonical edges carry a Timestamp; any other Firestore
// scalar is kept too, so one malformed (skipped but consumed) edge can never
// strand pagination.
function storableCreatedAt(value) {
  if (value === null || value === undefined) return false;
  if (timestampMillis(value) !== null) return true;
  if (typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (typeof value === "string") return value.length <= MAX_POSITION_ID_LENGTH;
  return false;
}

function validContentPosition(position) {
  return Boolean(position) &&
    storableCreatedAt(position.createdAt) &&
    typeof position.id === "string" &&
    position.id.length >= 1 &&
    position.id.length <= MAX_POSITION_ID_LENGTH &&
    !position.id.includes("/");
}

function validServerPosition(position) {
  return Boolean(position) &&
    Number.isSafeInteger(position.emojiIndex) &&
    position.emojiIndex >= 0 &&
    position.emojiIndex < ALLOWED_DIRECT_REACTIONS.length &&
    isValidOpaqueUid(position.uid);
}

// Whether storeLikersCursor could store `position` for this target type.
function storableLikersPosition(targetType, position) {
  return cursorKindOf(targetType) === "content"
    ? validContentPosition(position)
    : validServerPosition(position);
}

function newCursorToken(randomBytes = crypto.randomBytes) {
  const token = randomBytes(32).toString("base64url");
  if (!LIKERS_CURSOR_TOKEN.test(token)) {
    throw new TypeError("randomBytes must return 32 bytes.");
  }
  return token;
}

// Input validation only (no read): absent or null = first page.
function requireLikersCursorToken(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !LIKERS_CURSOR_TOKEN.test(value)) {
    cursorInvalid();
  }
  return value;
}

// One plain read. Returns null for the first page, else the stored position
// of the last consumed candidate: content {createdAt, id}, server
// {emojiIndex, uid}.
async function resolveLikersCursor({
  db,
  token,
  viewerId,
  targetType,
  targetKey,
  nowMs,
}) {
  const kind = cursorKindOf(targetType);
  const checkedToken = requireLikersCursorToken(token);
  if (checkedToken === null) return null;
  if (!TARGET_KEY.test(targetKey ?? "")) throw new TypeError("targetKey is invalid.");
  const snapshot = await db
    .doc(`${LIKERS_CURSOR_COLLECTION}/${checkedToken}`)
    .get();
  if (!snapshot?.exists) cursorInvalid();
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const createdAtMs = timestampMillis(data.createdAt);
  const expiresAtMs = timestampMillis(data.expiresAt);
  if (
    keys.length !== LIKERS_CURSOR_KEYS.length ||
    keys.some((key, index) => key !== LIKERS_CURSOR_KEYS[index]) ||
    data.schemaVersion !== 1 ||
    data.viewerId !== viewerId ||
    data.targetKey !== targetKey ||
    createdAtMs === null ||
    expiresAtMs === null ||
    expiresAtMs - createdAtMs !== LIKERS_CURSOR_TTL_MS ||
    expiresAtMs <= nowMs
  ) {
    cursorInvalid();
  }
  if (kind === "content") {
    const position = { createdAt: data.afterCreatedAt, id: data.afterId };
    if (
      !validContentPosition(position) ||
      data.afterEmojiIndex !== null ||
      data.afterUid !== null
    ) {
      cursorInvalid();
    }
    return position;
  }
  const position = { emojiIndex: data.afterEmojiIndex, uid: data.afterUid };
  if (
    !validServerPosition(position) ||
    data.afterCreatedAt !== null ||
    data.afterId !== null
  ) {
    cursorInvalid();
  }
  return position;
}

// Plain create() after the scan (no transaction). Returns the new token.
async function storeLikersCursor({
  db,
  Timestamp,
  viewerId,
  targetType,
  targetKey,
  position,
  timing,
  randomBytes = crypto.randomBytes,
}) {
  const kind = cursorKindOf(targetType);
  if (!Timestamp?.fromMillis) throw new TypeError("Timestamp is required.");
  if (!isValidOpaqueUid(viewerId)) throw new TypeError("viewerId is invalid.");
  if (!TARGET_KEY.test(targetKey ?? "")) throw new TypeError("targetKey is invalid.");
  if (!timing || !Number.isSafeInteger(timing.nowMs) || timing.now == null) {
    throw new TypeError("timing {nowMs, now} is required.");
  }
  const content = kind === "content";
  if (content ? !validContentPosition(position) : !validServerPosition(position)) {
    fail("data-loss", "The likers page position is malformed.");
  }
  const token = newCursorToken(randomBytes);
  await db.doc(`${LIKERS_CURSOR_COLLECTION}/${token}`).create({
    schemaVersion: 1,
    viewerId,
    targetKey,
    afterCreatedAt: content ? position.createdAt : null,
    afterId: content ? position.id : null,
    afterEmojiIndex: content ? null : position.emojiIndex,
    afterUid: content ? null : position.uid,
    expiresAt: Timestamp.fromMillis(timing.nowMs + LIKERS_CURSOR_TTL_MS),
    createdAt: timing.now,
  });
  return token;
}

module.exports = {
  CURSOR_INVALID_MESSAGE,
  LIKERS_CURSOR_COLLECTION,
  LIKERS_CURSOR_KEYS,
  LIKERS_CURSOR_TOKEN,
  LIKERS_CURSOR_TTL_MS,
  LIKERS_TARGET_TYPES,
  cursorKindOf,
  likersTargetKey,
  newCursorToken,
  requireLikersCursorToken,
  resolveLikersCursor,
  storableLikersPosition,
  storeLikersCursor,
};

// The stored shape of Page posts and comments (ADR-233 §1.3-§1.5), for the
// READ side. Pure: no SDK import.
//
// pagePosts/{postId} and pagePostComments/{commentId} are server-only (rules
// deny every client) and written by the publish, engagement and moderation
// packages. The readers here never trust a half-understood document: a post
// or comment that fails its exact shape is SKIPPED per item (it is consumed by
// the scan and logged by the caller), never an error that would break a whole
// feed page. Counters are the one exception (§1.7): a negative or non-integer
// likeCount / commentCount is `data-loss` in the WRITER and reads as 0 here.
//
// Every writer (B2 publish, B4 engagement, B5 moderation) must produce exactly
// PAGE_POST_KEYS / PAGE_COMMENT_KEYS; canonicalPagePostData and
// canonicalPageCommentData are the one definition of "exact".

const { timestampMillis } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const { PAGE_KINDS } = require("./catalog");
const {
  PAGE_COMMENT_ID_PATTERN,
  PAGE_MEDIA_ID_PATTERN,
  PAGE_POST_ID_PATTERN,
} = require("./contract");

const PAGE_POST_KEYS = Object.freeze([
  "authorId",
  "commentCount",
  "commentsEnabled",
  "createdAt",
  "deletedAt",
  "evidenceHold",
  "heldAt",
  "kind",
  "likeCount",
  "media",
  "moderationEvidence",
  "pageId",
  "pageKind",
  "postId",
  "removedAt",
  "removedReason",
  "schemaVersion",
  "status",
  "text",
]);
const PAGE_POST_KINDS = Object.freeze(["text", "photo", "voice"]);
const PAGE_POST_STATUSES = Object.freeze(["published", "held", "removed", "deleted"]);
const PAGE_POST_TEXT_MAX = 5000;
const PAGE_POST_MAX_PHOTOS = 10;
const PAGE_POST_IMAGE_MAX_BYTES = 4 * 1024 * 1024;
const PAGE_POST_IMAGE_MIN_BYTES = 128;
const PAGE_POST_AUDIO_MAX_BYTES = 4 * 1024 * 1024;
const PAGE_POST_AUDIO_MIN_BYTES = 512;
const PAGE_POST_MAX_DIMENSION = 8192;
// The trusted probe's reading of a 60 s take may run slightly past 60 000 ms
// (native capture starts before the recorder's stopwatch): the same 2 s grace
// the direct-message probe allows. Declarations stay 1-60 s.
const PAGE_POST_VOICE_MAX_MS = 62_000;
const PAGE_IMAGE_MEDIA_KEYS = Object.freeze([
  "contentType",
  "generation",
  "height",
  "mediaId",
  "size",
  "storagePath",
  "type",
  "width",
]);
const PAGE_AUDIO_MEDIA_KEYS = Object.freeze([
  "contentType",
  "durationMs",
  "generation",
  "mediaId",
  "size",
  "storagePath",
  "type",
]);
const PAGE_MODERATION_EVIDENCE_KEYS = Object.freeze([
  "evidenceVersion",
  "metadataFingerprint",
]);
const PAGE_COMMENT_KEYS = Object.freeze([
  "authorId",
  "commentId",
  "createdAt",
  "pageId",
  "postId",
  "schemaVersion",
  "text",
]);
const PAGE_COMMENT_TEXT_MAX = 1000;
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const REASON_KEY_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,63}$/u;
const FINGERPRINT_PATTERN = /^[a-f0-9]{64}$/u;

function exactKeys(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  return actual.length === keys.length && actual.every((key, index) => key === keys[index]);
}

function nullableTimestamp(value) {
  return value === null || timestampMillis(value) !== null;
}

function positiveInt(value, max) {
  return Number.isSafeInteger(value) && value >= 1 && value <= max;
}

/// Views read a broken counter as 0 (§1.7); the writer refuses it.
function pageCount(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

/// `page_posts/{pageId}/{postId}/{mediaId}.{jpg|m4a}` (§1.3).
function pagePostStoragePath(pageId, postId, mediaId, type) {
  return `page_posts/${pageId}/${postId}/${mediaId}.${type === "image" ? "jpg" : "m4a"}`;
}

function validMediaEntry(entry, { type, pageId, postId }) {
  if (type === "image") {
    return exactKeys(entry, PAGE_IMAGE_MEDIA_KEYS) &&
      entry.type === "image" &&
      entry.contentType === "image/jpeg" &&
      Number.isSafeInteger(entry.size) &&
      entry.size >= PAGE_POST_IMAGE_MIN_BYTES && entry.size <= PAGE_POST_IMAGE_MAX_BYTES &&
      positiveInt(entry.width, PAGE_POST_MAX_DIMENSION) &&
      positiveInt(entry.height, PAGE_POST_MAX_DIMENSION) &&
      typeof entry.mediaId === "string" && PAGE_MEDIA_ID_PATTERN.test(entry.mediaId) &&
      entry.storagePath === pagePostStoragePath(pageId, postId, entry.mediaId, "image") &&
      typeof entry.generation === "string" && GENERATION_PATTERN.test(entry.generation);
  }
  return exactKeys(entry, PAGE_AUDIO_MEDIA_KEYS) &&
    entry.type === "audio" &&
    entry.contentType === "audio/mp4" &&
    Number.isSafeInteger(entry.size) &&
    entry.size >= PAGE_POST_AUDIO_MIN_BYTES && entry.size <= PAGE_POST_AUDIO_MAX_BYTES &&
    positiveInt(entry.durationMs, PAGE_POST_VOICE_MAX_MS) &&
    typeof entry.mediaId === "string" && PAGE_MEDIA_ID_PATTERN.test(entry.mediaId) &&
    entry.storagePath === pagePostStoragePath(pageId, postId, entry.mediaId, "audio") &&
    typeof entry.generation === "string" && GENERATION_PATTERN.test(entry.generation);
}

function validMedia(kind, media, pageId, postId) {
  if (!Array.isArray(media)) return false;
  if (kind === "text") return media.length === 0;
  const type = kind === "photo" ? "image" : "audio";
  const max = kind === "photo" ? PAGE_POST_MAX_PHOTOS : 1;
  if (media.length < 1 || media.length > max) return false;
  const seen = new Set();
  for (const entry of media) {
    if (!validMediaEntry(entry, { type, pageId, postId })) return false;
    if (seen.has(entry.mediaId)) return false;
    seen.add(entry.mediaId);
  }
  return true;
}

/// The reason `data` (document `postId`) is not an exact Page post, or null.
/// Counters are NOT part of exactness (they read as 0 when broken).
function pagePostMalformedReason(data, postId) {
  if (!exactKeys(data, PAGE_POST_KEYS)) return "keys";
  if (data.schemaVersion !== 1) return "schemaVersion";
  if (typeof postId !== "string" || !PAGE_POST_ID_PATTERN.test(postId) ||
      data.postId !== postId) {
    return "postId";
  }
  if (!isValidOpaqueUid(data.pageId) || data.authorId !== data.pageId) return "identity";
  if (!PAGE_KINDS.includes(data.pageKind)) return "pageKind";
  if (!PAGE_POST_KINDS.includes(data.kind)) return "kind";
  if (typeof data.text !== "string" || data.text.length > PAGE_POST_TEXT_MAX) return "text";
  if (data.kind === "text" && data.text.trim().length === 0) return "text";
  if (!validMedia(data.kind, data.media, data.pageId, postId)) return "media";
  if (!PAGE_POST_STATUSES.includes(data.status)) return "status";
  if (typeof data.evidenceHold !== "boolean") return "evidenceHold";
  if (typeof data.commentsEnabled !== "boolean") return "commentsEnabled";
  if (timestampMillis(data.createdAt) === null) return "createdAt";
  if (!nullableTimestamp(data.heldAt) || !nullableTimestamp(data.removedAt) ||
      !nullableTimestamp(data.deletedAt)) {
    return "moderationTimes";
  }
  if (data.removedReason !== null &&
      (typeof data.removedReason !== "string" || !REASON_KEY_PATTERN.test(data.removedReason))) {
    return "removedReason";
  }
  if (data.moderationEvidence !== null &&
      (!exactKeys(data.moderationEvidence, PAGE_MODERATION_EVIDENCE_KEYS) ||
        data.moderationEvidence.evidenceVersion !== 1 ||
        typeof data.moderationEvidence.metadataFingerprint !== "string" ||
        !FINGERPRINT_PATTERN.test(data.moderationEvidence.metadataFingerprint))) {
    return "moderationEvidence";
  }
  if (data.status === "held" && timestampMillis(data.heldAt) === null) return "heldAt";
  if (data.status === "removed" && timestampMillis(data.removedAt) === null) return "removedAt";
  if (data.status === "deleted" && timestampMillis(data.deletedAt) === null) return "deletedAt";
  return null;
}

/// The exact post in `snapshot`, or null (missing or malformed). Readers
/// skip a null per item.
function canonicalPagePostData(snapshot) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data();
  if (pagePostMalformedReason(data, snapshot.id) !== null) return null;
  return Object.freeze({ ...data });
}

/// The reason `data` (document `commentId`) is not an exact comment, or null.
function pageCommentMalformedReason(data, commentId) {
  if (!exactKeys(data, PAGE_COMMENT_KEYS)) return "keys";
  if (data.schemaVersion !== 1) return "schemaVersion";
  if (typeof commentId !== "string" || !PAGE_COMMENT_ID_PATTERN.test(commentId) ||
      data.commentId !== commentId) {
    return "commentId";
  }
  if (typeof data.postId !== "string" || !PAGE_POST_ID_PATTERN.test(data.postId)) return "postId";
  if (!isValidOpaqueUid(data.pageId) || !isValidOpaqueUid(data.authorId)) return "identity";
  if (typeof data.text !== "string" || data.text.trim().length === 0 ||
      data.text.length > PAGE_COMMENT_TEXT_MAX) {
    return "text";
  }
  if (timestampMillis(data.createdAt) === null) return "createdAt";
  return null;
}

function canonicalPageCommentData(snapshot) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data();
  if (pageCommentMalformedReason(data, snapshot.id) !== null) return null;
  return Object.freeze({ ...data });
}

module.exports = {
  PAGE_AUDIO_MEDIA_KEYS,
  PAGE_COMMENT_KEYS,
  PAGE_COMMENT_TEXT_MAX,
  PAGE_IMAGE_MEDIA_KEYS,
  PAGE_POST_AUDIO_MAX_BYTES,
  PAGE_POST_AUDIO_MIN_BYTES,
  PAGE_POST_IMAGE_MAX_BYTES,
  PAGE_POST_IMAGE_MIN_BYTES,
  PAGE_POST_KEYS,
  PAGE_POST_KINDS,
  PAGE_POST_MAX_DIMENSION,
  PAGE_POST_MAX_PHOTOS,
  PAGE_POST_STATUSES,
  PAGE_POST_TEXT_MAX,
  PAGE_POST_VOICE_MAX_MS,
  canonicalPageCommentData,
  canonicalPagePostData,
  pageCommentMalformedReason,
  pageCount,
  pagePostMalformedReason,
  pagePostStoragePath,
};

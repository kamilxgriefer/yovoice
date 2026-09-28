// The Premium Pages POST WRITE contract (ADR-233 §1.9, §2.4): media
// reservations, the per-owner upload lease, the per-Page daily budget, the
// durable media deletion jobs, the post cleanup jobs and the open-report
// record the evidence rules read. Pure: no SDK import beyond the error type.
//
// Every document here is server-only (firestore.rules denies every client).
// The one cross-service reader is storage.rules, which reads
// pagePostMediaReservations/{mediaId} with firestore.get() to admit exactly
// one upload; its key list below is the rules' key list.
//
// Identifiers are ALWAYS server-allocated and derived from the caller and the
// request id (digest), so a retry of the same request allocates the same ids
// and the operation ledger replays the same result:
//
//   postId   pp_ + 40 hex   reserve (media posts) or publish (text posts)
//   mediaId  pm_ + 40 hex   one per reserved item
//
//   pagePostMediaReservations/{mediaId}
//     {schemaVersion:1, kind:"pagePostMedia", pageId, ownerId, postId,
//      mediaId, index, type, contentType, size, durationMs|null,
//      width|null, height|null, storagePath, requestId,
//      status:"uploading"|"expiring", createdAt, expiresAt}      (15 min)
//   pagePostMediaLeases/{ownerId}
//     {schemaVersion:1, ownerId, postId, requestId, mediaIds, status:"uploading",
//      expiresAt}                              one open reservation set per owner
//   pagePostBudgets/{pageId}_{yyyymmdd}
//     {schemaVersion:1, pageId, day, posts, reservations, bytes, updatedAt}
//   pagePostMediaDeletionJobs/{mediaId}
//     {schemaVersion:1, storagePath, generation, reason, heldBy, attempts,
//      createdAt, nextAttemptAt}     heldBy != null: kept as evidence (§2.10)
//   pagePostCleanupJobs/{postId}
//     {schemaVersion:1, postId, pageId, reason, attempts, createdAt,
//      nextAttemptAt}          likes + comments of a HARD-deleted post (§2.4)
//   pagePostOpenReports/{postId}      (written by the reporting package)
//     {schemaVersion:1, postId, pageId, count, lastReportId, updatedAt}

const { digest, fail, timestampMillis } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const {
  PAGE_MEDIA_ID_PATTERN,
  PAGE_POST_ID_PATTERN,
  pagesError,
} = require("./contract");
const {
  PAGE_POST_AUDIO_MAX_BYTES,
  PAGE_POST_AUDIO_MIN_BYTES,
  PAGE_POST_IMAGE_MAX_BYTES,
  PAGE_POST_IMAGE_MIN_BYTES,
  PAGE_POST_MAX_DIMENSION,
  PAGE_POST_MAX_PHOTOS,
  PAGE_POST_TEXT_MAX,
  pagePostStoragePath,
} = require("./post_contract");

const PAGE_MEDIA_SCHEMA_VERSION = 1;
const PAGE_MEDIA_RESERVATION_KIND = "pagePostMedia";
const PAGE_MEDIA_RESERVATION_TTL_MS = 15 * 60 * 1000;
const PAGE_MEDIA_PREFIX = "page_posts";
// assertNoImageMetadata reads at most this much of a photo (§2.4 step 3).
const PAGE_MEDIA_HEAD_BYTES = 256 * 1024;
// Declared voice length (D8): the recorder clamps to 1-60 s.
const PAGE_VOICE_DECLARED_MIN_MS = 1;
const PAGE_VOICE_DECLARED_MAX_MS = 60_000;
// The probe's reading may differ from the declaration by this much (the
// direct-message tolerance).
const PAGE_VOICE_DURATION_TOLERANCE_MS = 2_000;

// §1.1 beta budgets, per Page per UTC day. Reservations count MEDIA ITEMS
// (one photo = one reservation); bytes are charged at reserve; posts at
// publish. Nothing is refunded.
const PAGE_DAILY_BUDGET = Object.freeze({
  posts: 10,
  reservations: 30,
  bytes: 200 * 1024 * 1024,
});

const PAGE_MEDIA_RESERVATION_KEYS = Object.freeze([
  "contentType",
  "createdAt",
  "durationMs",
  "expiresAt",
  "height",
  "index",
  "kind",
  "mediaId",
  "ownerId",
  "pageId",
  "postId",
  "requestId",
  "schemaVersion",
  "size",
  "status",
  "storagePath",
  "type",
  "width",
]);
const PAGE_MEDIA_LEASE_KEYS = Object.freeze([
  "expiresAt",
  "mediaIds",
  "ownerId",
  "postId",
  "requestId",
  "schemaVersion",
  "status",
]);
const PAGE_BUDGET_KEYS = Object.freeze([
  "bytes",
  "day",
  "pageId",
  "posts",
  "reservations",
  "schemaVersion",
  "updatedAt",
]);
const PAGE_MEDIA_DELETION_JOB_KEYS = Object.freeze([
  "attempts",
  "createdAt",
  "generation",
  "heldBy",
  "nextAttemptAt",
  "reason",
  "schemaVersion",
  "storagePath",
]);
const PAGE_POST_CLEANUP_JOB_KEYS = Object.freeze([
  "attempts",
  "createdAt",
  "nextAttemptAt",
  "pageId",
  "postId",
  "reason",
  "schemaVersion",
]);
const PAGE_OPEN_REPORTS_KEYS = Object.freeze([
  "count",
  "lastReportId",
  "pageId",
  "postId",
  "schemaVersion",
  "updatedAt",
]);
const PAGE_MEDIA_UPLOAD_METADATA_KEYS = Object.freeze([
  "yovoiceMediaId",
  "yovoiceMediaType",
  "yovoicePageId",
  "yovoicePostId",
]);
const PAGE_MEDIA_TYPES = Object.freeze({
  photo: Object.freeze({
    type: "image",
    contentType: "image/jpeg",
    extension: "jpg",
    minBytes: PAGE_POST_IMAGE_MIN_BYTES,
    maxBytes: PAGE_POST_IMAGE_MAX_BYTES,
    maxItems: PAGE_POST_MAX_PHOTOS,
  }),
  voice: Object.freeze({
    type: "audio",
    contentType: "audio/mp4",
    extension: "m4a",
    minBytes: PAGE_POST_AUDIO_MIN_BYTES,
    maxBytes: PAGE_POST_AUDIO_MAX_BYTES,
    maxItems: 1,
  }),
});
const PAGE_MEDIA_POST_KINDS = Object.freeze(Object.keys(PAGE_MEDIA_TYPES));
const PAGE_RESERVE_ITEM_KEYS = Object.freeze([
  "contentType",
  "durationMs",
  "height",
  "index",
  "size",
  "width",
]);
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
// A report id as moderation writes it (moderation/reports.js SAFE_REPORT_ID).
const HELD_BY_PATTERN = /^[A-Za-z0-9_-]{1,256}$/u;
const JOB_REASON_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,63}$/u;
const BUDGET_DAY_PATTERN = /^[0-9]{8}$/u;
const OBJECT_NAME_PATTERN =
  /^page_posts\/([A-Za-z0-9_-]{1,128})\/(pp_[a-f0-9]{40})\/(pm_[a-f0-9]{40})\.(jpg|m4a)$/u;
// The job id of a post whose deletion found no open report but a held or
// removed status: the evidence is kept until a moderator releases it.
const PAGE_MODERATION_HOLD = "moderationHold";

// ------------------------------------------------------------------ errors

const PAGE_POST_ERRORS = Object.freeze({
  budget: () => pagesError("resource-exhausted",
    "Your Page reached today's posting limit.", "pagePostBudget"),
  uploadInProgress: () => pagesError("resource-exhausted",
    "Finish the current upload first.", "pageUploadInProgress"),
  uploadExpired: () => pagesError("deadline-exceeded",
    "The upload expired. Start again.", "pageUploadExpired"),
  mediaMetadata: () => pagesError("failed-precondition",
    "This photo couldn't be prepared. Try again.", "pageMediaMetadata"),
  mediaInvalid: () => pagesError("failed-precondition",
    "The uploaded file couldn't be verified. Try again.", "pageMediaInvalid"),
  paused: () => pagesError("failed-precondition",
    "This Page is paused.", "pagePaused"),
});

// ------------------------------------------------------------- identifiers

function hex40(...parts) {
  return digest(...parts).slice(0, 40);
}

/// The post id a reserve (media) or a publish (text) request allocates.
function pagePostIdFor(uid, requestId, purpose) {
  if (purpose !== "media" && purpose !== "text") {
    throw new TypeError("purpose must be media or text.");
  }
  return `pp_${hex40("pages.post.id.v1", purpose, uid, requestId)}`;
}

function pageMediaIdFor(uid, requestId, index) {
  return `pm_${hex40("pages.media.id.v1", uid, requestId, String(index))}`;
}

/// yyyymmdd in UTC.
function pageBudgetDay(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 10).replace(/-/gu, "");
}

function pageBudgetId(pageId, nowMs) {
  return `${pageId}_${pageBudgetDay(nowMs)}`;
}

/// The exact custom metadata an upload must carry (storage.rules).
function pageMediaUploadMetadata({ pageId, postId, mediaId, type }) {
  return {
    yovoicePageId: pageId,
    yovoicePostId: postId,
    yovoiceMediaId: mediaId,
    yovoiceMediaType: type,
  };
}

/// {pageId, postId, mediaId, extension} for an object this feature could
/// have written, or null.
function parsePagePostObjectName(name) {
  if (typeof name !== "string") return null;
  const match = OBJECT_NAME_PATTERN.exec(name);
  if (!match) return null;
  return { pageId: match[1], postId: match[2], mediaId: match[3], extension: match[4] };
}

// ------------------------------------------------------------------ inputs

function exactKeys(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  return actual.length === keys.length && actual.every((key, index) => key === keys[index]);
}

function intIn(value, min, max) {
  return Number.isSafeInteger(value) && value >= min && value <= max;
}

/**
 * The reserve items (§2.4), validated exactly. Photos: 1-10 image/jpeg items
 * with layout-only width/height; voice: exactly one audio/mp4 item with a
 * declared 1-60 s length. `index` is 0..n-1 in order. There is no client
 * postId anywhere.
 */
function requireReserveItems(kind, items) {
  const shape = PAGE_MEDIA_TYPES[kind];
  if (!shape) fail("invalid-argument", "kind must be photo or voice.");
  if (!Array.isArray(items) || items.length < 1 || items.length > shape.maxItems) {
    fail("invalid-argument", kind === "photo"
      ? "A photo post has 1-10 photos."
      : "A voice post has exactly one clip.");
  }
  return items.map((item, position) => {
    if (!exactKeys(item, PAGE_RESERVE_ITEM_KEYS)) {
      fail("invalid-argument", "Each item must list exactly index, contentType, size, width, height and durationMs.");
    }
    if (item.index !== position) fail("invalid-argument", "items must be in index order from 0.");
    if (item.contentType !== shape.contentType) {
      fail("invalid-argument", `contentType must be ${shape.contentType}.`);
    }
    if (!intIn(item.size, shape.minBytes, shape.maxBytes)) {
      fail("invalid-argument", "size is outside the allowed range.");
    }
    if (shape.type === "image") {
      if (!intIn(item.width, 1, PAGE_POST_MAX_DIMENSION) ||
          !intIn(item.height, 1, PAGE_POST_MAX_DIMENSION) || item.durationMs !== null) {
        fail("invalid-argument", "A photo needs width and height (1-8192) and no duration.");
      }
    } else if (!intIn(item.durationMs, PAGE_VOICE_DECLARED_MIN_MS, PAGE_VOICE_DECLARED_MAX_MS) ||
        item.width !== null || item.height !== null) {
      fail("invalid-argument", "A voice clip needs a 1-60 s duration and no dimensions.");
    }
    return Object.freeze({
      index: item.index,
      contentType: item.contentType,
      size: item.size,
      width: shape.type === "image" ? item.width : null,
      height: shape.type === "image" ? item.height : null,
      durationMs: shape.type === "audio" ? item.durationMs : null,
    });
  });
}

// Control, format and separator characters are refused as in
// display_name.js, with two deliberate exceptions for post text: LF (CRLF
// and CR fold to it) and the zero-width (non-)joiner, without which emoji
// sequences (family, flags with ZWJ) and scripts such as Persian break.
const UNSAFE_POST_TEXT =
  /[\u0000-\u0009\u000b-\u001f\u007f-\u009f\p{Zl}\p{Zp}]|\p{Cf}(?<![\u200c\u200d])/u;
const INVISIBLE = /[\s\u200c\u200d\ufe0e\ufe0f]/gu;

/// Normalised post text (NFC, LF line breaks, trimmed). A text post needs at
/// least one visible character.
function normalizePostText(value, kind) {
  if (typeof value !== "string") fail("invalid-argument", "text must be a string.");
  if (!value.isWellFormed()) fail("invalid-argument", "text contains unsupported characters.");
  const text = value.normalize("NFC").replace(/\r\n?/gu, "\n").trim();
  if (UNSAFE_POST_TEXT.test(text)) {
    fail("invalid-argument", "text contains unsupported characters.");
  }
  if (text.length > PAGE_POST_TEXT_MAX) {
    fail("invalid-argument", `text must be at most ${PAGE_POST_TEXT_MAX} characters.`);
  }
  if (kind === "text" && text.replace(INVISIBLE, "").length === 0) {
    fail("invalid-argument", "A text post needs some text.");
  }
  return text;
}

// ------------------------------------------------------------- documents

function newReservation({ pageId, postId, mediaId, item, kind, requestId, now, expiresAt }) {
  const shape = PAGE_MEDIA_TYPES[kind];
  return {
    schemaVersion: PAGE_MEDIA_SCHEMA_VERSION,
    kind: PAGE_MEDIA_RESERVATION_KIND,
    pageId,
    ownerId: pageId,
    postId,
    mediaId,
    index: item.index,
    type: shape.type,
    contentType: shape.contentType,
    size: item.size,
    durationMs: item.durationMs,
    width: item.width,
    height: item.height,
    storagePath: pagePostStoragePath(pageId, postId, mediaId, shape.type),
    requestId,
    status: "uploading",
    createdAt: now,
    expiresAt,
  };
}

/**
 * The reservation in `snapshot`, exact, or null when it is not one. Readers
 * that need a LIVE reservation also check status and expiresAt.
 */
function canonicalPageMediaReservation(snapshot) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  if (!exactKeys(value, PAGE_MEDIA_RESERVATION_KEYS)) return null;
  const kind = value.type === "image" ? "photo" : value.type === "audio" ? "voice" : null;
  const shape = kind === null ? null : PAGE_MEDIA_TYPES[kind];
  const expiresAtMs = timestampMillis(value.expiresAt);
  if (value.schemaVersion !== PAGE_MEDIA_SCHEMA_VERSION ||
      value.kind !== PAGE_MEDIA_RESERVATION_KIND ||
      shape === null ||
      !isValidOpaqueUid(value.pageId) || value.ownerId !== value.pageId ||
      typeof value.postId !== "string" || !PAGE_POST_ID_PATTERN.test(value.postId) ||
      value.mediaId !== snapshot.id || !PAGE_MEDIA_ID_PATTERN.test(value.mediaId) ||
      !intIn(value.index, 0, PAGE_POST_MAX_PHOTOS - 1) ||
      value.contentType !== shape.contentType ||
      !intIn(value.size, shape.minBytes, shape.maxBytes) ||
      value.storagePath !== pagePostStoragePath(value.pageId, value.postId, value.mediaId, shape.type) ||
      typeof value.requestId !== "string" || value.requestId.length < 1 ||
      !["uploading", "expiring"].includes(value.status) ||
      timestampMillis(value.createdAt) === null || expiresAtMs === null) {
    return null;
  }
  if (shape.type === "image"
    ? !intIn(value.width, 1, PAGE_POST_MAX_DIMENSION) ||
      !intIn(value.height, 1, PAGE_POST_MAX_DIMENSION) || value.durationMs !== null
    : !intIn(value.durationMs, PAGE_VOICE_DECLARED_MIN_MS, PAGE_VOICE_DECLARED_MAX_MS) ||
      value.width !== null || value.height !== null) {
    return null;
  }
  return Object.freeze({ ...value, postKind: kind, expiresAtMs });
}

function canonicalPageMediaLease(snapshot, ownerId) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  const expiresAtMs = timestampMillis(value.expiresAt);
  if (!exactKeys(value, PAGE_MEDIA_LEASE_KEYS) ||
      value.schemaVersion !== PAGE_MEDIA_SCHEMA_VERSION ||
      value.ownerId !== ownerId || snapshot.id !== ownerId ||
      typeof value.postId !== "string" || !PAGE_POST_ID_PATTERN.test(value.postId) ||
      typeof value.requestId !== "string" || value.requestId.length < 1 ||
      !Array.isArray(value.mediaIds) || value.mediaIds.length < 1 ||
      value.mediaIds.length > PAGE_POST_MAX_PHOTOS ||
      new Set(value.mediaIds).size !== value.mediaIds.length ||
      value.mediaIds.some((id) => typeof id !== "string" || !PAGE_MEDIA_ID_PATTERN.test(id)) ||
      value.status !== "uploading" || expiresAtMs === null) {
    fail("data-loss", "The Page upload lease needs reconciliation.");
  }
  return Object.freeze({ ...value, mediaIds: Object.freeze([...value.mediaIds]), expiresAtMs });
}

/// The budget row for (pageId, day): zeros when missing, data-loss when it
/// is not exact (a broken counter is never read as "nothing used").
function canonicalPageBudget(snapshot, pageId, day) {
  if (!snapshot?.exists) return Object.freeze({ posts: 0, reservations: 0, bytes: 0, exists: false });
  const value = snapshot.data() ?? {};
  if (!exactKeys(value, PAGE_BUDGET_KEYS) || value.schemaVersion !== PAGE_MEDIA_SCHEMA_VERSION ||
      value.pageId !== pageId || value.day !== day || !BUDGET_DAY_PATTERN.test(value.day) ||
      !Number.isSafeInteger(value.posts) || value.posts < 0 ||
      !Number.isSafeInteger(value.reservations) || value.reservations < 0 ||
      !Number.isSafeInteger(value.bytes) || value.bytes < 0 ||
      timestampMillis(value.updatedAt) === null) {
    fail("data-loss", "The Page posting budget needs reconciliation.");
  }
  return Object.freeze({
    posts: value.posts,
    reservations: value.reservations,
    bytes: value.bytes,
    exists: true,
  });
}

function pageBudgetDocument({ pageId, day, posts, reservations, bytes, now }) {
  return { schemaVersion: PAGE_MEDIA_SCHEMA_VERSION, pageId, day, posts, reservations, bytes, updatedAt: now };
}

/// The deletion job for one media object (job id = mediaId).
function pageMediaDeletionJob({ storagePath, generation, reason, heldBy, now }) {
  if (typeof generation !== "string" || !GENERATION_PATTERN.test(generation)) {
    throw new TypeError("A generation is required for a Page media deletion job.");
  }
  if (heldBy !== null && (typeof heldBy !== "string" || !HELD_BY_PATTERN.test(heldBy))) {
    throw new TypeError("heldBy must be null or a report id.");
  }
  return {
    schemaVersion: PAGE_MEDIA_SCHEMA_VERSION,
    storagePath,
    generation,
    reason,
    heldBy,
    attempts: 0,
    createdAt: now,
    nextAttemptAt: now,
  };
}

function canonicalPageMediaDeletionJob(snapshot) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  const parsed = parsePagePostObjectName(value.storagePath);
  if (!exactKeys(value, PAGE_MEDIA_DELETION_JOB_KEYS) ||
      value.schemaVersion !== PAGE_MEDIA_SCHEMA_VERSION ||
      parsed === null || parsed.mediaId !== snapshot.id ||
      typeof value.generation !== "string" || !GENERATION_PATTERN.test(value.generation) ||
      typeof value.reason !== "string" || !JOB_REASON_PATTERN.test(value.reason) ||
      (value.heldBy !== null &&
        (typeof value.heldBy !== "string" || !HELD_BY_PATTERN.test(value.heldBy))) ||
      !Number.isSafeInteger(value.attempts) || value.attempts < 0 ||
      timestampMillis(value.createdAt) === null || timestampMillis(value.nextAttemptAt) === null) {
    fail("data-loss", "The Page media deletion job needs reconciliation.");
  }
  return Object.freeze({ ...value, mediaId: snapshot.id });
}

function pagePostCleanupJob({ postId, pageId, reason, now }) {
  return {
    schemaVersion: PAGE_MEDIA_SCHEMA_VERSION,
    postId,
    pageId,
    reason,
    attempts: 0,
    createdAt: now,
    nextAttemptAt: now,
  };
}

function canonicalPagePostCleanupJob(snapshot) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  if (!exactKeys(value, PAGE_POST_CLEANUP_JOB_KEYS) ||
      value.schemaVersion !== PAGE_MEDIA_SCHEMA_VERSION ||
      value.postId !== snapshot.id || !PAGE_POST_ID_PATTERN.test(value.postId) ||
      !isValidOpaqueUid(value.pageId) ||
      typeof value.reason !== "string" || !JOB_REASON_PATTERN.test(value.reason) ||
      !Number.isSafeInteger(value.attempts) || value.attempts < 0 ||
      timestampMillis(value.createdAt) === null || timestampMillis(value.nextAttemptAt) === null) {
    fail("data-loss", "The Page post cleanup job needs reconciliation.");
  }
  return Object.freeze({ ...value });
}

/**
 * The open-report record of a post (§2.10), written by the reporting
 * package in the same transaction as each report and each resolution:
 * `count` is the number of OPEN reports on the post or its comments;
 * `lastReportId` is the newest report ever filed and stays after
 * resolution. Missing means "never reported". A malformed record reads as
 * reported with an unknown report (fail closed: evidence is kept).
 */
function pagePostOpenReports(snapshot, postId) {
  if (!snapshot?.exists) return Object.freeze({ exists: false, count: 0, lastReportId: null });
  const value = snapshot.data() ?? {};
  if (!exactKeys(value, PAGE_OPEN_REPORTS_KEYS) || value.schemaVersion !== 1 ||
      value.postId !== postId || !isValidOpaqueUid(value.pageId) ||
      !Number.isSafeInteger(value.count) || value.count < 0 ||
      typeof value.lastReportId !== "string" || !HELD_BY_PATTERN.test(value.lastReportId) ||
      timestampMillis(value.updatedAt) === null) {
    return Object.freeze({ exists: true, count: 1, lastReportId: null, malformed: true });
  }
  return Object.freeze({ exists: true, count: value.count, lastReportId: value.lastReportId });
}

/// The deletion-job references of every media object of `post` (job id =
/// mediaId). Read them in the transaction before calling
/// releaseHeldPagePostMediaJobs.
function pagePostMediaJobReferences(db, post) {
  return post.media.map((entry) => db.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`));
}

/**
 * Releases the HELD media deletion jobs of a post (§2.10): the reporting
 * package calls this in the transaction that brings the post's open-report
 * count to zero, so the evidence kept by an owner's delete is removed by the
 * next pagesMaintenance run. Returns the number of jobs released.
 */
function releaseHeldPagePostMediaJobs(transaction, jobSnapshots, now) {
  let released = 0;
  for (const snapshot of jobSnapshots) {
    const job = canonicalPageMediaDeletionJob(snapshot);
    if (job !== null && job.heldBy !== null) {
      transaction.update(snapshot.ref, { heldBy: null, nextAttemptAt: now });
      released += 1;
    }
  }
  return released;
}

/// The moderationEvidence fingerprint of a tombstoned post (§2.4): the
/// owner's delete, and account deletion while a report is open.
function pagePostEvidenceFingerprint(post) {
  return digest("pages.post.evidence.v1", post.postId, post.authorId, post.status,
    post.text, post.media);
}

/// The media deletion backoff: 1 min, 2, 4 … capped at 6 h.
function pageJobBackoffMs(attempts) {
  const exponent = Math.min(Math.max(attempts, 0), 9);
  return Math.min(60_000 * (2 ** exponent), 6 * 60 * 60 * 1000);
}

module.exports = {
  GENERATION_PATTERN,
  PAGE_BUDGET_KEYS,
  PAGE_DAILY_BUDGET,
  PAGE_MEDIA_DELETION_JOB_KEYS,
  PAGE_MEDIA_HEAD_BYTES,
  PAGE_MEDIA_LEASE_KEYS,
  PAGE_MEDIA_POST_KINDS,
  PAGE_MEDIA_PREFIX,
  PAGE_MEDIA_RESERVATION_KEYS,
  PAGE_MEDIA_RESERVATION_KIND,
  PAGE_MEDIA_RESERVATION_TTL_MS,
  PAGE_MEDIA_TYPES,
  PAGE_MEDIA_UPLOAD_METADATA_KEYS,
  PAGE_MODERATION_HOLD,
  PAGE_OPEN_REPORTS_KEYS,
  PAGE_POST_CLEANUP_JOB_KEYS,
  PAGE_POST_ERRORS,
  PAGE_RESERVE_ITEM_KEYS,
  PAGE_VOICE_DECLARED_MAX_MS,
  PAGE_VOICE_DURATION_TOLERANCE_MS,
  canonicalPageBudget,
  canonicalPageMediaDeletionJob,
  canonicalPageMediaLease,
  canonicalPageMediaReservation,
  canonicalPagePostCleanupJob,
  newReservation,
  normalizePostText,
  PAGE_INVISIBLE_TEXT: INVISIBLE,
  PAGE_UNSAFE_TEXT: UNSAFE_POST_TEXT,
  pageBudgetDay,
  pageBudgetDocument,
  pageBudgetId,
  pageJobBackoffMs,
  pageMediaDeletionJob,
  pageMediaIdFor,
  pageMediaUploadMetadata,
  pagePostCleanupJob,
  pagePostEvidenceFingerprint,
  pagePostIdFor,
  pagePostMediaJobReferences,
  pagePostOpenReports,
  parsePagePostObjectName,
  releaseHeldPagePostMediaJobs,
  requireReserveItems,
};

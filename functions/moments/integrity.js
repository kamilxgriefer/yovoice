const crypto = require("node:crypto");

const {
  SAFE_ID,
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  canonicalPublicProfile,
  consumeRateLimit,
  digest,
  fail,
  incrementCanonicalCount,
  isValidOpaqueUid,
  ledgerData,
  nonNegativeCount,
  normalizeText,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const {
  MAX_ACTIVE_MOMENTS,
  assertActiveMomentCapacity,
  exactPublishedMomentsQuery,
  momentCapacityLedgerReference,
  touchMomentCapacityLedger,
} = require("./capacity");
const {
  exactFriendshipGuard,
  profileVisibilityOf,
} = require("../profile/media_contract");

const DEFAULT_LIMITS = Object.freeze({
  uploadReserve: { maxEvents: 5, windowMs: 10 * 60_000 },
  finalize: { maxEvents: 10, windowMs: 10 * 60_000 },
  mediaAccess: { maxEvents: 30, windowMs: 60_000 },
  mediaAccessHourly: { maxEvents: 300, windowMs: 60 * 60_000 },
  read: { maxEvents: 60, windowMs: 60_000 },
  readHourly: { maxEvents: 1_000, windowMs: 60 * 60_000 },
  like: { maxEvents: 60, windowMs: 60_000 },
  comment: { maxEvents: 20, windowMs: 60_000 },
  delete: { maxEvents: 10, windowMs: 60_000 },
  report: { maxEvents: 10, windowMs: 10 * 60_000 },
});

// ---------------------------------------------------------------------------
// Story expiry (2026-08) with operator-chosen availability (2026-08, later;
// amends ADR-101).
//
// A published Voice Moment carries `expiresAt = createdAt + availability`,
// stamped by finalizeMomentDraft inside the publish transaction. The
// availability is the caller's `availabilityHours` — any safe whole-hour
// value from MIN_MOMENT_AVAILABILITY_HOURS through
// MAX_MOMENT_AVAILABILITY_HOURS, defaulting to 24 when absent (the original
// contract, byte for byte) — or the literal string "permanent", which
// writes NO expiresAt field at all: null-or-missing expiresAt MEANS a
// Moment that stays published until its author deletes it, everywhere
// (client filters, the sweep, and the active cap alike). The deadline
// anchors on the STORED createdAt — the reserve transaction's request time
// — rather than on the finalize request's clock, because the client-side
// contract derives chain order and countdowns from the exact equality of
// the two fields; deriving each from its own request would let them drift
// by the upload duration. Enforcement is two-layer:
// expireVoiceMomentsSchedule (functions/moments/expiry.js) flips passed
// deadlines to `status: "expired"` every 10 minutes, and the client feed
// filters on the deadline so the sweep gap never shows a dead Moment.
//
// MAX_ACTIVE_MOMENTS caps how many simultaneously live (published, not yet
// expired — permanent counts, forever) Moments one author may hold — the
// story-shelf size the product is designed around. The cap is checked both
// when a draft is reserved (an advisory fast refusal when already full) and,
// critically, again in the publish transaction. Both checks query EVERY
// published Moment for the author, so no number of newer draft documents can
// hide an old permanent story. The authoritative finalization also reads and
// advances the author's server-only capacity ledger: one shared mutex makes
// competing finalizations, deletions and expirations serialize even though
// each writes a different Moment document. Expired deadlines are filtered in
// memory immediately, before the scheduled sweep catches up.
// ---------------------------------------------------------------------------
const HOUR_MS = 60 * 60_000;
const MOMENT_TTL_MS = 24 * HOUR_MS;
const MIN_MOMENT_AVAILABILITY_HOURS = 24;
const MAX_MOMENT_AVAILABILITY_HOURS = 720;
const PERMANENT_AVAILABILITY = "permanent";

/// The operator-chosen availability of a finalize request. Strict on
/// purpose: a safe whole-hour count in the supported range or the exact
/// string "permanent" — not null, not "24", and not a fractional value.
/// Absent defaults to 24, which is precisely the deployed behaviour, so
/// pre-availability clients keep publishing 24-hour stories without
/// changing a byte.
function momentAvailability(value) {
  if (value === undefined) return MIN_MOMENT_AVAILABILITY_HOURS;
  if (value === PERMANENT_AVAILABILITY) return PERMANENT_AVAILABILITY;
  return requireSafeInteger(value, "availabilityHours", {
    min: MIN_MOMENT_AVAILABILITY_HOURS,
    max: MAX_MOMENT_AVAILABILITY_HOURS,
  });
}

// ---------------------------------------------------------------------------
// Content reports
//
// Every surface a report can name, and the ids that surface requires. The
// table is the allowlist: a targetType that is not a key here is refused
// before a single read happens, and any id field a target does not name must
// arrive null, so one report can never carry a second, unrelated path
// alongside the one it is about.
//
// The names match functions/admin/messages.js's MESSAGE_TYPES on purpose.
// That callable is what a moderator uses to actually remove the reported
// message, and it derives its path from roomId / clubId + channelId +
// messageId — the same ids stored below. One vocabulary, so a report and the
// action taken on it describe the same thing.
// ---------------------------------------------------------------------------
const REPORT_TARGETS = Object.freeze({
  directMessage: Object.freeze(["conversationId", "messageId"]),
  voiceMoment: Object.freeze(["momentId"]),
  voiceMomentComment: Object.freeze(["momentId", "commentId"]),
  roomMessage: Object.freeze(["roomId", "messageId"]),
  clubMessage: Object.freeze(["clubId", "channelId", "messageId"]),
});

const REPORT_TARGET_IDS = Object.freeze([
  "channelId",
  "clubId",
  "commentId",
  "conversationId",
  "messageId",
  "momentId",
  "roomId",
]);

// The id fields the DEPLOYED function has always folded into the operation
// ledger's inputHash. Reports already exist in production keyed on exactly
// these; see reportIdentityInput() for why that list cannot simply grow.
const LEGACY_REPORT_INPUT_IDS = Object.freeze([
  "conversationId",
  "messageId",
  "momentId",
  "commentId",
]);

const MAX_REPORT_NOTE = 300;

const AUDIO_TYPES = new Set(["audio/mp4", "audio/m4a", "audio/x-m4a"]);
const MAX_AUDIO_BYTES = 12 * 1024 * 1024;
const MIN_AUDIO_BYTES = 512;
// A media grant is deliberately shorter than a Voice Moment. It is still a
// bearer URL while it exists, but a copied URL dies quickly and is bounded by
// the Moment's own expiry. Sixty seconds of audio plus network startup fits in
// ninety seconds without turning one playback into a durable capability.
const MEDIA_ACCESS_TTL_MS = 90_000;
// A report receipt is a server-issued capability proving that this viewer saw
// this exact Voice Moment target through the privacy-filtered v2 projection.
// It is deliberately short-lived: long enough to open the safety sheet and
// submit it after a block/mute race, but not a durable bypass of later privacy.
const VOICE_REPORT_RECEIPT_TTL_MS = 10 * 60_000;
const VOICE_REPORT_RECEIPT_TOKEN = /^[A-Za-z0-9_-]{43}$/u;
const MAX_FEED_LIMIT = 10;
const MAX_THREAD_COMMENTS = 7;
const MAX_THREAD_REACTIONS = 3;
const MAX_PAGE_CURSOR_LENGTH = 256;
const VOICE_MOMENT_V2_READ_BUDGETS = Object.freeze({
  // Two reads happen in the separate minute/hour limiter transaction.
  // A feed candidate costs one query read, one caller-like read and either
  // five (public) or seven (friends-only) author-context reads.
  // The feed query reads one look-ahead document so `hasMore` is exact.
  // The v2 response also reads one server-only report-receipt row per
  // candidate. `following` mode adds one canonical following edge per author.
  feedTypical: 2 + 3 + MAX_FEED_LIMIT * 8,
  feedFollowingTypical: 2 + 3 + MAX_FEED_LIMIT * 9,
  feedWorst: 2 + 3 + MAX_FEED_LIMIT * 11,
  viewTypical:
    2 +
    4 +
    (MAX_THREAD_COMMENTS + 1) +
    MAX_THREAD_REACTIONS * 2 +
    (1 + MAX_THREAD_COMMENTS + MAX_THREAD_REACTIONS * 2) * 5 +
    (1 + MAX_THREAD_COMMENTS),
  viewWorst:
    2 +
    4 +
    (MAX_THREAD_COMMENTS + 1) +
    MAX_THREAD_REACTIONS * 2 +
    (1 + MAX_THREAD_COMMENTS + MAX_THREAD_REACTIONS * 2) * 7 +
    (1 + MAX_THREAD_COMMENTS),
});

function exactFollowingEdge(snapshot, targetId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const allowed = new Set(["followedAt", "notificationId", "uid"]);
  return keys.length >= 2 &&
    keys.every((key) => allowed.has(key)) &&
    keys.includes("followedAt") &&
    keys.includes("uid") &&
    data.uid === targetId &&
    timestampMillis(data.followedAt) !== null &&
    (!("notificationId" in data) ||
      (typeof data.notificationId === "string" &&
        data.notificationId.length > 0 &&
        data.notificationId.length <= 320));
}

function canonicalMomentId(uid, requestId) {
  return digest("voice-moment", uid, requestId).slice(0, 20);
}

function canonicalCommentId(uid, momentId, requestId) {
  return digest("voice-moment-comment", uid, momentId, requestId).slice(0, 20);
}

function momentStoragePath(uid, momentId) {
  return `voice_moments/${uid}/${momentId}.m4a`;
}

function voiceReplyStoragePath(uid, momentId, commentId) {
  return `voice_replies/${uid}/${momentId}/${commentId}.m4a`;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/// Validates the caller's target and returns it in canonical form: the
/// targetType plus every id field, with the ones this target does not use
/// pinned to null.
function reportTarget(data) {
  if (
    typeof data.targetType !== "string" ||
    !Object.prototype.hasOwnProperty.call(REPORT_TARGETS, data.targetType)
  ) {
    fail("invalid-argument", "targetType is invalid.");
  }
  const required = REPORT_TARGETS[data.targetType];
  const target = { targetType: data.targetType };
  for (const field of REPORT_TARGET_IDS) {
    target[field] = data[field] ?? null;
  }
  for (const field of required) {
    requireId(target[field], field);
  }
  for (const field of REPORT_TARGET_IDS) {
    if (!required.includes(field) && target[field] !== null) {
      fail("invalid-argument", "The report target fields conflict.");
    }
  }
  return target;
}

/// The document being reported. Every id in `target` has already passed
/// SAFE_ID, so no segment here can contain a slash and walk out of the
/// collection it names.
function reportTargetReference(db, target) {
  switch (target.targetType) {
    case "directMessage":
      return db.doc(
        `conversations/${target.conversationId}/messages/${target.messageId}`,
      );
    case "voiceMoment":
      return db.doc(`voiceMoments/${target.momentId}`);
    case "voiceMomentComment":
      return db.doc(
        `voiceMoments/${target.momentId}/comments/${target.commentId}`,
      );
    case "roomMessage":
      return db.doc(`rooms/${target.roomId}/messages/${target.messageId}`);
    case "clubMessage":
      return db.doc(
        `clubs/${target.clubId}/channels/${target.channelId}/messages/${target.messageId}`,
      );
    default:
      return fail("invalid-argument", "targetType is invalid.");
  }
}

/// The value hashed into the operation ledger's inputHash.
///
/// WHY THIS IS NOT JUST `{ reason, ...target }`. createContentReport is
/// deployed and live, and the client derives its requestId from the TARGET
/// rather than from the attempt — so a reporter tapping report twice on the
/// same message replays an existing ledger entry and gets the original
/// reportId back. Those entries were written with an inputHash computed over
/// exactly `reason` plus the five legacy keys below. Folding roomId, clubId,
/// channelId or note into the hash unconditionally would change the hash for
/// targets that do not even use them, re-keying every report already filed:
/// the next replay would stop replaying and start answering `already-exists`.
/// So the new fields join the hash only when the target actually carries
/// them, which is never for a target type that predates them.
function reportIdentityInput(target, reason, note) {
  const input = { reason, targetType: target.targetType };
  for (const field of LEGACY_REPORT_INPUT_IDS) {
    input[field] = target[field];
  }
  for (const field of REPORT_TARGET_IDS) {
    if (!LEGACY_REPORT_INPUT_IDS.includes(field) && target[field] !== null) {
      input[field] = target[field];
    }
  }
  if (note !== null) input.note = note;
  return input;
}

function validateMoment(
  snapshot,
  momentId,
  { published = undefined, allowExpired = false, activeAtMs = null } = {},
) {
  if (!snapshot.exists) fail("not-found", "The Voice Moment does not exist.");
  const data = snapshot.data() ?? {};
  const expectedKeys = [
    "audioUrl",
    "authorId",
    "authorName",
    "authorPhotoUrl",
    "caption",
    "commentCount",
    "createdAt",
    "durationSeconds",
    "isDeleted",
    "isPublished",
    "likeCount",
    "mediaContentType",
    "mediaGeneration",
    "mediaSize",
    "publishedAt",
    "replyToMomentId",
    "schemaVersion",
    "status",
    "storagePath",
    "updatedAt",
  ];
  // `expiresAt` is additive (2026-08): finalizeMomentDraft stamps it on
  // every EXPIRING publish, while a "permanent" publish (operator-chosen
  // availability, amending ADR-101) deliberately writes none — and
  // production also still holds legacy pre-expiry documents without it.
  // Optional here so both no-deadline shapes stay canonical; when the key
  // is present it must be a real timestamp (checked below).
  const hasExpiresAt = Object.prototype.hasOwnProperty.call(data, "expiresAt");
  if (hasExpiresAt) {
    expectedKeys.push("expiresAt");
    expectedKeys.sort();
  }
  const keys = Object.keys(data).sort();
  if (
    keys.length !== expectedKeys.length ||
    keys.some((key, index) => key !== expectedKeys[index]) ||
    data.schemaVersion !== 2 ||
    typeof data.authorId !== "string" ||
    data.storagePath !== momentStoragePath(data.authorId, momentId) ||
    !Number.isSafeInteger(data.durationSeconds) ||
    data.durationSeconds < 1 ||
    data.durationSeconds > 60 ||
    typeof data.caption !== "string" ||
    data.caption.length > 280 ||
    typeof data.isPublished !== "boolean" ||
    typeof data.isDeleted !== "boolean"
  ) {
    fail("data-loss", "The Voice Moment schema is not canonical.");
  }
  if (
    typeof data.authorName !== "string" ||
    !data.authorName.trim() ||
    data.authorName.length > 80 ||
    (data.authorPhotoUrl !== null &&
      (typeof data.authorPhotoUrl !== "string" ||
        data.authorPhotoUrl.length > 2048)) ||
    data.replyToMomentId !== null ||
    timestampMillis(data.createdAt) === null ||
    timestampMillis(data.updatedAt) === null ||
    (hasExpiresAt && timestampMillis(data.expiresAt) === null)
  ) {
    fail("data-loss", "The Voice Moment identity or timestamps are malformed.");
  }
  if (data.isDeleted || data.status === "deleting") {
    if (
      data.isDeleted !== true ||
      data.status !== "deleting" ||
      data.isPublished !== false
    ) {
      fail("data-loss", "The Voice Moment deletion state is malformed.");
    }
    fail("failed-precondition", "The Voice Moment is being deleted.");
  }
  if (data.status === "expired") {
    // expireVoiceMomentsSchedule flips exactly
    // { isPublished, status, updatedAt } and nothing else, so an expired
    // Moment still carries the full published media shape plus the
    // expiresAt that retired it. Likes and comments refuse it below;
    // deletion passes { allowExpired: true } because the author keeps the
    // right to remove an expired story (and its audio) at any time.
    if (
      data.isPublished !== false ||
      !hasExpiresAt ||
      (data.audioUrl !== null &&
        (typeof data.audioUrl !== "string" ||
          !data.audioUrl ||
          data.audioUrl.length > 4096)) ||
      typeof data.mediaGeneration !== "string" ||
      !data.mediaGeneration ||
      !Number.isSafeInteger(data.mediaSize) ||
      data.mediaSize < MIN_AUDIO_BYTES ||
      data.mediaSize > MAX_AUDIO_BYTES ||
      !AUDIO_TYPES.has(data.mediaContentType) ||
      timestampMillis(data.publishedAt) === null
    ) {
      fail("data-loss", "The expired Voice Moment state is malformed.");
    }
    if (!allowExpired) {
      fail("failed-precondition", "This Voice Moment has expired.");
    }
  } else if (data.isPublished) {
    if (
      data.status !== "published" ||
      (data.audioUrl !== null &&
        (typeof data.audioUrl !== "string" ||
          !data.audioUrl ||
          data.audioUrl.length > 4096)) ||
      typeof data.mediaGeneration !== "string" ||
      !data.mediaGeneration ||
      !Number.isSafeInteger(data.mediaSize) ||
      data.mediaSize < MIN_AUDIO_BYTES ||
      data.mediaSize > MAX_AUDIO_BYTES ||
      !AUDIO_TYPES.has(data.mediaContentType) ||
      timestampMillis(data.publishedAt) === null
    ) {
      fail("data-loss", "The published Voice Moment media state is malformed.");
    }
    // The scheduled sweep is the durable state transition, not a grace
    // period. Engagement callables pass their server request time here so a
    // Moment stops accepting new likes/comments exactly at its deadline even
    // if the ten-minute sweeper has not flipped `status` yet. A missing
    // expiresAt remains the explicit permanent shape.
    if (activeAtMs !== null) {
      if (!Number.isSafeInteger(activeAtMs) || activeAtMs < 0) {
        throw new TypeError("activeAtMs must be epoch milliseconds.");
      }
      const expiresAtMs = hasExpiresAt ? timestampMillis(data.expiresAt) : null;
      if (expiresAtMs !== null && expiresAtMs <= activeAtMs) {
        fail("failed-precondition", "This Voice Moment has expired.");
      }
    }
  } else if (
    data.status !== "uploading" ||
    data.audioUrl !== null ||
    data.mediaGeneration !== null ||
    data.mediaSize !== null ||
    data.mediaContentType !== null ||
    data.publishedAt !== null
  ) {
    fail("data-loss", "The Voice Moment draft state is malformed.");
  }
  nonNegativeCount(data.likeCount, "Voice Moment likeCount");
  nonNegativeCount(data.commentCount, "Voice Moment commentCount");
  if (published !== undefined && data.isPublished !== published) {
    fail(
      "failed-precondition",
      published
        ? "The Voice Moment is not published."
        : "The Voice Moment is already published.",
    );
  }
  return data;
}

// Read-only compatibility for published records created before the canonical
// schema-v2 rollout. The durable `audioUrl` is never returned or trusted: the
// media identity is reconstructed from authorId + momentId and verified
// against Storage metadata before a short-lived grant is signed. Bulk
// migration remains the canonical write path; this bridge only keeps an old
// installed build's already-published audio playable during rollout.
function validateLegacyMomentForPlayback(snapshot, momentId, activeAtMs) {
  if (!snapshot.exists) fail("not-found", "The Voice Moment does not exist.");
  const data = snapshot.data() ?? {};
  if (
    data.schemaVersion === 2 ||
    (data.schemaVersion !== undefined &&
      data.schemaVersion !== 0 &&
      data.schemaVersion !== 1) ||
    !isValidOpaqueUid(data.authorId) ||
    data.storagePath !== momentStoragePath(data.authorId, momentId) ||
    !Number.isSafeInteger(data.durationSeconds) ||
    data.durationSeconds < 1 ||
    data.durationSeconds > 60 ||
    typeof data.caption !== "string" ||
    data.caption.length > 280 ||
    data.isPublished !== true ||
    data.isDeleted === true ||
    ![undefined, "legacy", "published"].includes(data.status) ||
    (data.replyToMomentId !== undefined && data.replyToMomentId !== null) ||
    timestampMillis(data.createdAt) === null ||
    (data.updatedAt !== undefined &&
      timestampMillis(data.updatedAt) === null) ||
    (data.publishedAt !== undefined &&
      timestampMillis(data.publishedAt) === null)
  ) {
    fail("data-loss", "The legacy Voice Moment record is malformed.");
  }
  // A partially upgraded record is corruption, not a legacy shape. Refuse it
  // rather than letting absent/forged media fields weaken the v2 validator.
  if (
    data.mediaGeneration !== undefined ||
    data.mediaSize !== undefined ||
    data.mediaContentType !== undefined
  ) {
    fail("data-loss", "The legacy Voice Moment media state is malformed.");
  }
  if (
    data.audioUrl !== undefined &&
    (typeof data.audioUrl !== "string" ||
      !data.audioUrl ||
      data.audioUrl.length > 4096)
  ) {
    fail("data-loss", "The legacy Voice Moment media URL is malformed.");
  }
  nonNegativeCount(data.likeCount ?? 0, "legacy Voice Moment likeCount");
  nonNegativeCount(
    data.commentCount ?? 0,
    "legacy Voice Moment commentCount",
  );
  const expiresAtMs = Object.prototype.hasOwnProperty.call(data, "expiresAt")
    ? timestampMillis(data.expiresAt)
    : null;
  if (
    (Object.prototype.hasOwnProperty.call(data, "expiresAt") &&
      expiresAtMs === null) ||
    (expiresAtMs !== null && expiresAtMs <= activeAtMs)
  ) {
    fail("failed-precondition", "This Voice Moment has expired.");
  }
  return data;
}

function validateComment(snapshot, momentId) {
  if (!snapshot.exists) fail("not-found", "The comment does not exist.");
  const data = snapshot.data() ?? {};
  const expectedKeys = [
    "audioUrl",
    "authorId",
    "authorName",
    "authorPhotoUrl",
    "createdAt",
    "durationSeconds",
    "mediaContentType",
    "mediaGeneration",
    "mediaSize",
    "schemaVersion",
    "storagePath",
    "text",
    "type",
  ];
  const keys = Object.keys(data).sort();
  if (
    keys.length !== expectedKeys.length ||
    keys.some((key, index) => key !== expectedKeys[index]) ||
    data.schemaVersion !== 2 ||
    !["text", "voice"].includes(data.type) ||
    !isValidOpaqueUid(data.authorId) ||
    typeof data.authorName !== "string" ||
    !data.authorName.trim() ||
    data.authorName.length > 80 ||
    (data.authorPhotoUrl !== null &&
      (typeof data.authorPhotoUrl !== "string" ||
        data.authorPhotoUrl.length > 2048)) ||
    typeof data.text !== "string" ||
    timestampMillis(data.createdAt) === null
  ) {
    fail("data-loss", "The comment schema is not canonical.");
  }
  if (data.type === "text") {
    if (
      !data.text ||
      data.text.length > 1000 ||
      data.audioUrl !== null ||
      data.storagePath !== null ||
      data.durationSeconds !== null ||
      data.mediaGeneration !== null ||
      data.mediaSize !== null ||
      data.mediaContentType !== null
    ) {
      fail("data-loss", "The text comment payload is malformed.");
    }
  } else if (
    data.storagePath !==
      voiceReplyStoragePath(data.authorId, momentId, snapshot.id) ||
    !Number.isSafeInteger(data.durationSeconds) ||
    data.durationSeconds < 1 ||
    data.durationSeconds > 60 ||
    (data.audioUrl !== null &&
      (typeof data.audioUrl !== "string" ||
        !data.audioUrl ||
        data.audioUrl.length > 4096)) ||
    data.text.length > 140 ||
    typeof data.mediaGeneration !== "string" ||
    !data.mediaGeneration ||
    !Number.isSafeInteger(data.mediaSize) ||
    data.mediaSize < MIN_AUDIO_BYTES ||
    data.mediaSize > MAX_AUDIO_BYTES ||
    !AUDIO_TYPES.has(data.mediaContentType)
  ) {
    fail("data-loss", "The voice comment payload is malformed.");
  }
  return data;
}

function validateMomentLike(snapshot, momentId, userId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = ["createdAt", "momentId", "schemaVersion", "userId"];
  if (
    keys.length !== expected.length ||
    keys.some((key, index) => key !== expected[index]) ||
    data.schemaVersion !== 1 ||
    data.userId !== userId ||
    data.momentId !== momentId ||
    timestampMillis(data.createdAt) === null
  ) {
    fail("data-loss", "The like edge is not canonical.");
  }
  return true;
}

function voiceMomentProjection(
  momentId,
  data,
  publicProfile,
  callerLiked,
  reportReceipt,
) {
  const identity = canonicalPublicProfile(publicProfile, data.authorId);
  const createdAtMillis = timestampMillis(data.createdAt);
  const publishedAtMillis = timestampMillis(data.publishedAt) ?? createdAtMillis;
  const expiresAtMillis = Object.prototype.hasOwnProperty.call(data, "expiresAt")
    ? timestampMillis(data.expiresAt)
    : null;
  return {
    schemaVersion: 2,
    momentId,
    authorId: data.authorId,
    authorName: identity.displayName,
    // Profile artwork is intentionally resolved through its own short-lived,
    // viewer-authorized grant. Never copy a durable profile URL into this
    // content projection.
    authorPhotoUrl: identity.photoUrl,
    caption: data.caption,
    durationSeconds: data.durationSeconds,
    likeCount: data.likeCount ?? 0,
    commentCount: data.commentCount ?? 0,
    callerLiked,
    reportReceipt,
    createdAtMillis,
    publishedAtMillis,
    expiresAtMillis,
  };
}

function voiceMomentCommentProjection(
  commentId,
  data,
  publicProfile,
  reportReceipt,
) {
  const identity = canonicalPublicProfile(publicProfile, data.authorId);
  return {
    schemaVersion: 2,
    commentId,
    type: data.type,
    authorId: data.authorId,
    authorName: identity.displayName,
    authorPhotoUrl: identity.photoUrl,
    text: data.text,
    durationSeconds: data.durationSeconds,
    createdAtMillis: timestampMillis(data.createdAt),
    reportReceipt,
  };
}

function encodeVoiceMomentPageCursor({
  kind,
  id,
  createdAtMillis,
  momentId = null,
  sortMode = null,
  feedMode = null,
  orderValue = null,
}) {
  if (
    !Number.isSafeInteger(createdAtMillis) ||
    createdAtMillis < 0 ||
    (sortMode !== null &&
      (!Number.isSafeInteger(orderValue) || orderValue < 0))
  ) {
    fail("data-loss", "The Voice Moment page boundary is malformed.");
  }
  return Buffer.from(JSON.stringify({
    schemaVersion: 1,
    kind,
    id,
    createdAtMillis,
    ...(momentId === null ? {} : { momentId }),
    ...(sortMode === null ? {} : { sortMode, feedMode, orderValue }),
  }), "utf8").toString("base64url");
}

function decodeVoiceMomentPageCursor(
  value,
  { kind, momentId = null, sortMode = null, feedMode = null },
) {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > MAX_PAGE_CURSOR_LENGTH ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    fail("invalid-argument", "The Voice Moment page cursor is invalid.");
  }
  try {
    const decoded = Buffer.from(value, "base64url");
    if (
      decoded.length > MAX_PAGE_CURSOR_LENGTH ||
      decoded.toString("base64url") !== value
    ) {
      fail("invalid-argument", "The Voice Moment page cursor is invalid.");
    }
    const cursor = JSON.parse(decoded.toString("utf8"));
    const expectedKeys = [
      "createdAtMillis",
      "id",
      "kind",
      ...(momentId === null ? [] : ["momentId"]),
      ...(sortMode === null ? [] : ["feedMode", "orderValue", "sortMode"]),
      "schemaVersion",
    ].sort();
    const keys = cursor && typeof cursor === "object" && !Array.isArray(cursor)
      ? Object.keys(cursor).sort()
      : [];
    if (
      keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      cursor.schemaVersion !== 1 ||
      cursor.kind !== kind ||
      !Number.isSafeInteger(cursor.createdAtMillis) ||
      cursor.createdAtMillis < 0 ||
      (momentId !== null && cursor.momentId !== momentId) ||
      (sortMode !== null &&
        (cursor.sortMode !== sortMode ||
          cursor.feedMode !== feedMode ||
          !Number.isSafeInteger(cursor.orderValue) ||
          cursor.orderValue < 0))
    ) {
      fail("invalid-argument", "The Voice Moment page cursor is invalid.");
    }
    requireId(cursor.id, "cursor id");
    return cursor;
  } catch (error) {
    if (error?.code === "invalid-argument") throw error;
    fail("invalid-argument", "The Voice Moment page cursor is invalid.");
  }
}

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return isPlainObject(custom) ? custom : {};
}

function validateStoredAudio(metadata, expected, requestedGeneration) {
  if (!metadata || typeof metadata !== "object") {
    fail("failed-precondition", "The uploaded audio object is missing.");
  }
  const size = Number(metadata.size);
  if (
    !Number.isSafeInteger(size) ||
    size < MIN_AUDIO_BYTES ||
    size > MAX_AUDIO_BYTES ||
    !AUDIO_TYPES.has(metadata.contentType)
  ) {
    fail("failed-precondition", "The uploaded audio payload is invalid.");
  }
  const generation = String(metadata.generation ?? "");
  if (!generation || String(requestedGeneration) !== generation) {
    fail(
      "failed-precondition",
      "The uploaded object generation does not match.",
    );
  }
  const custom = customMetadataOf(metadata);
  const keys = Object.keys(custom).sort();
  const expectedKeys = Object.keys(expected).sort();
  const allowedKeys = [...expectedKeys, "firebaseStorageDownloadTokens"].sort();
  if (
    keys.some((key) => !allowedKeys.includes(key)) ||
    expectedKeys.some((key) => custom[key] !== expected[key])
  ) {
    fail("failed-precondition", "The uploaded object identity is invalid.");
  }
  return {
    contentType: metadata.contentType,
    generation,
    size,
  };
}

function validateVoiceReservation(
  data,
  { ownerId, momentId, commentId, storagePath, nowMs },
) {
  const expectedKeys = [
    "authorName",
    "authorPhotoUrl",
    "commentId",
    "createdAt",
    "durationSeconds",
    "expiresAt",
    "kind",
    "momentId",
    "ownerId",
    "schemaVersion",
    "status",
    "storagePath",
    "text",
  ];
  const keys = Object.keys(data).sort();
  if (
    keys.length !== expectedKeys.length ||
    keys.some((key, index) => key !== expectedKeys[index]) ||
    data.schemaVersion !== 1 ||
    data.kind !== "voiceMomentComment" ||
    data.ownerId !== ownerId ||
    data.momentId !== momentId ||
    data.commentId !== commentId ||
    data.storagePath !== storagePath ||
    data.status !== "uploading" ||
    !Number.isSafeInteger(data.durationSeconds) ||
    data.durationSeconds < 1 ||
    data.durationSeconds > 60 ||
    typeof data.text !== "string" ||
    data.text.length > 140 ||
    typeof data.authorName !== "string" ||
    !data.authorName.trim() ||
    data.authorName.length > 80 ||
    (data.authorPhotoUrl !== null &&
      (typeof data.authorPhotoUrl !== "string" ||
        data.authorPhotoUrl.length > 2048)) ||
    timestampMillis(data.createdAt) === null ||
    timestampMillis(data.expiresAt) === null ||
    timestampMillis(data.expiresAt) <= nowMs
  ) {
    fail("failed-precondition", "The voice-comment reservation is invalid.");
  }
  return data;
}

function createMomentIntegrityService({
  db,
  FieldPath,
  Timestamp,
  storage,
  clock = () => Date.now(),
  cleanupPageSize = 100,
  limits = DEFAULT_LIMITS,
}) {
  if (
    !db ||
    !FieldPath?.documentId ||
    !Timestamp?.fromMillis ||
    !storage?.getMetadata ||
    !storage?.getSignedReadUrl ||
    !storage?.revokeDownloadTokens
  ) {
    throw new TypeError(
      "db, FieldPath, Timestamp and a private-media storage adapter are required.",
    );
  }
  requireSafeInteger(cleanupPageSize, "cleanupPageSize", { min: 1, max: 200 });

  function time() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  function ledgerReference(identity) {
    return db.doc(`integrityOperationLedgers/${identity.id}`);
  }

  function limitReference(scope, uid) {
    return rateLimitReference(db, `moment.${scope}`, uid);
  }

  function consume(transaction, snapshot, reference, scope, uid, timing) {
    const config = limits[scope];
    if (!config) throw new TypeError(`Missing moment.${scope} rate limit.`);
    consumeRateLimit(transaction, snapshot, {
      reference,
      scope: `moment.${scope}`,
      uid,
      ...timing,
      ...config,
    });
  }

  // A reserve can be rejected only after an exact published-set query. Keep
  // that query outside the rate-limit transaction so a refusal cannot roll
  // the quota write back with the rest of the operation. A completed
  // operation ledger is still a free idempotent replay: it returns before the
  // attempt budget is touched.
  async function beginOperationAttempt({ identity, kind, uid, scope, timing }) {
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference(scope, uid);
      const [ledger, rate] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      consume(transaction, rate, rateRef, scope, uid, timing);
      return { replay: null };
    });
  }

  async function beginMediaAccessAttempt(uid, timing) {
    return db.runTransaction(async (transaction) => {
      const minuteRef = limitReference("mediaAccess", uid);
      const hourRef = limitReference("mediaAccessHourly", uid);
      const [minute, hour] = await transactionGetAll(
        transaction,
        minuteRef,
        hourRef,
      );
      consume(transaction, minute, minuteRef, "mediaAccess", uid, timing);
      consume(transaction, hour, hourRef, "mediaAccessHourly", uid, timing);
    });
  }

  async function beginVoiceMomentReadAttempt(uid, timing) {
    return db.runTransaction(async (transaction) => {
      const minuteRef = limitReference("read", uid);
      const hourRef = limitReference("readHourly", uid);
      const [minute, hour] = await transactionGetAll(
        transaction,
        minuteRef,
        hourRef,
      );
      consume(transaction, minute, minuteRef, "read", uid, timing);
      consume(transaction, hour, hourRef, "readHourly", uid, timing);
    });
  }

  async function loadVoiceAudienceContexts(
    transaction,
    viewerId,
    authorIds,
    { includeSocialEdges = false } = {},
  ) {
    const descriptors = [];
    const baseReferences = [];
    for (const authorId of [...new Set(authorIds)]) {
      if (!isValidOpaqueUid(authorId)) {
        fail("data-loss", "The Voice Moment author is invalid.");
      }
      const descriptor = {
        authorId,
        baseStart: baseReferences.length,
        sharedIdentity: authorId === viewerId,
      };
      baseReferences.push(
        db.doc(`users/${authorId}`),
        db.doc(`restrictions/${authorId}`),
        db.doc(`publicProfiles/${authorId}`),
      );
      descriptors.push(descriptor);
    }
    const baseSnapshots = baseReferences.length === 0
      ? []
      : await transactionGetAll(transaction, ...baseReferences);
    const relationshipReferences = [];
    for (const descriptor of descriptors) {
      if (descriptor.sharedIdentity) continue;
      descriptor.blockStart = relationshipReferences.length;
      relationshipReferences.push(
        db.doc(`users/${viewerId}/blocked/${descriptor.authorId}`),
        db.doc(`users/${descriptor.authorId}/blocked/${viewerId}`),
      );
      if (includeSocialEdges) {
        descriptor.followingStart = relationshipReferences.length;
        relationshipReferences.push(
          db.doc(`users/${viewerId}/following/${descriptor.authorId}`),
        );
      }
      const authorProfile = baseSnapshots[descriptor.baseStart];
      if (
        includeSocialEdges ||
        profileVisibilityOf(authorProfile?.data()) === "friends"
      ) {
        descriptor.friendshipStart = relationshipReferences.length;
        relationshipReferences.push(
          db.doc(
            `friendshipGuards/${viewerId}/friends/${descriptor.authorId}`,
          ),
          db.doc(
            `friendshipGuards/${descriptor.authorId}/friends/${viewerId}`,
          ),
        );
      }
    }
    const relationshipSnapshots = relationshipReferences.length === 0
      ? []
      : await transactionGetAll(transaction, ...relationshipReferences);
    const contexts = new Map();
    for (const descriptor of descriptors) {
      const {
        authorId,
        baseStart,
        blockStart,
        friendshipStart,
        followingStart,
        sharedIdentity,
      } = descriptor;
      contexts.set(authorId, {
        authorProfile: baseSnapshots[baseStart],
        authorRestriction: baseSnapshots[baseStart + 1],
        publicProfile: baseSnapshots[baseStart + 2],
        viewerBlock: sharedIdentity
          ? null
          : relationshipSnapshots[blockStart],
        authorBlock: sharedIdentity
          ? null
          : relationshipSnapshots[blockStart + 1],
        following: followingStart === undefined
          ? null
          : relationshipSnapshots[followingStart],
        forwardFriendship: friendshipStart === undefined
          ? null
          : relationshipSnapshots[friendshipStart],
        reverseFriendship: friendshipStart === undefined
          ? null
          : relationshipSnapshots[friendshipStart + 1],
      });
    }
    return contexts;
  }

  function assertVoiceMomentSocialRelationship(viewerId, authorId, context) {
    if (viewerId === authorId) return;
    if (
      exactFollowingEdge(context?.following, authorId) ||
      (exactFriendshipGuard(context?.forwardFriendship, viewerId, authorId) &&
        exactFriendshipGuard(context?.reverseFriendship, authorId, viewerId))
    ) {
      return;
    }
    fail("permission-denied", "This Voice Moment is unavailable.");
  }

  function assertVoiceMomentAudienceFromContext({
    viewerId,
    viewerProfile,
    viewerRestriction,
    authorId,
    context,
    nowMs,
  }) {
    activeProfile(viewerProfile, "Your");
    assertNotRestricted(viewerRestriction, "Your", nowMs);
    if (!context) fail("data-loss", "The Voice Moment access context is missing.");
    const author = activeProfile(context.authorProfile, "The author");
    assertNotRestricted(context.authorRestriction, "The author", nowMs);
    if (viewerId === authorId) return context;
    assertNotBlocked(context.viewerBlock, context.authorBlock);
    const visibility = profileVisibilityOf(author);
    if (visibility === "public") return context;
    if (
      visibility === "friends" &&
      exactFriendshipGuard(context.forwardFriendship, viewerId, authorId) &&
      exactFriendshipGuard(context.reverseFriendship, authorId, viewerId)
    ) {
      return context;
    }
    fail("permission-denied", "This Voice Moment is unavailable.");
  }

  async function assertVoiceMomentAudience(transaction, {
    viewerId,
    authorId,
    nowMs,
    viewerProfile = undefined,
    viewerRestriction = undefined,
  }) {
    let resolvedProfile = viewerProfile;
    let resolvedRestriction = viewerRestriction;
    if (resolvedProfile === undefined || resolvedRestriction === undefined) {
      [resolvedProfile, resolvedRestriction] = await transactionGetAll(
        transaction,
        db.doc(`users/${viewerId}`),
        db.doc(`restrictions/${viewerId}`),
      );
    }
    const contexts = await loadVoiceAudienceContexts(
      transaction,
      viewerId,
      [authorId],
    );
    return assertVoiceMomentAudienceFromContext({
      viewerId,
      viewerProfile: resolvedProfile,
      viewerRestriction: resolvedRestriction,
      authorId,
      context: contexts.get(authorId),
      nowMs,
    });
  }

  function publishedMomentForRead(snapshot, momentId, nowMs) {
    const legacy = snapshot.data()?.schemaVersion !== 2;
    return legacy
      ? validateLegacyMomentForPlayback(snapshot, momentId, nowMs)
      : validateMoment(snapshot, momentId, {
          published: true,
          activeAtMs: nowMs,
        });
  }

  function voiceReportReceiptReference(viewerId, target) {
    const receiptId = digest(
      "voice-moment-report-receipt",
      viewerId,
      target.targetType,
      target.momentId,
      target.commentId ?? "",
    ).slice(0, 40);
    return db.doc(`voiceMomentReportReceipts/${receiptId}`);
  }

  function exactVoiceReportReceipt(snapshot, target, viewerId, nowMs) {
    if (!snapshot?.exists) return null;
    const data = snapshot.data() ?? {};
    const expected = [
      "commentId",
      "expiresAt",
      "issuedAt",
      "momentId",
      "ownerId",
      "schemaVersion",
      "targetAuthorId",
      "targetType",
      "token",
    ].sort();
    const keys = Object.keys(data).sort();
    const issuedAtMs = timestampMillis(data.issuedAt);
    const expiresAtMs = timestampMillis(data.expiresAt);
    if (
      keys.length !== expected.length ||
      keys.some((key, index) => key !== expected[index]) ||
      data.schemaVersion !== 1 ||
      data.ownerId !== viewerId ||
      data.targetType !== target.targetType ||
      data.momentId !== target.momentId ||
      data.commentId !== (target.commentId ?? null) ||
      !isValidOpaqueUid(data.targetAuthorId) ||
      typeof data.token !== "string" ||
      !VOICE_REPORT_RECEIPT_TOKEN.test(data.token) ||
      issuedAtMs === null ||
      expiresAtMs === null ||
      issuedAtMs > nowMs ||
      expiresAtMs - issuedAtMs !== VOICE_REPORT_RECEIPT_TTL_MS ||
      expiresAtMs <= nowMs
    ) {
      return null;
    }
    return data;
  }

  function receiptTokenMatches(expected, received) {
    if (
      typeof expected !== "string" ||
      typeof received !== "string" ||
      !VOICE_REPORT_RECEIPT_TOKEN.test(expected) ||
      !VOICE_REPORT_RECEIPT_TOKEN.test(received)
    ) {
      return false;
    }
    return crypto.timingSafeEqual(
      Buffer.from(expected, "ascii"),
      Buffer.from(received, "ascii"),
    );
  }

  function issueVoiceReportReceipt(
    transaction,
    snapshot,
    { reference, target, targetAuthorId, viewerId, timing },
  ) {
    const current = exactVoiceReportReceipt(
      snapshot,
      target,
      viewerId,
      timing.nowMs,
    );
    if (current !== null && current.targetAuthorId === targetAuthorId) {
      return current.token;
    }
    const token = crypto.randomBytes(32).toString("base64url");
    transaction.set(reference, {
      schemaVersion: 1,
      ownerId: viewerId,
      targetType: target.targetType,
      momentId: target.momentId,
      commentId: target.commentId ?? null,
      targetAuthorId,
      token,
      issuedAt: timing.now,
      expiresAt: Timestamp.fromMillis(
        timing.nowMs + VOICE_REPORT_RECEIPT_TTL_MS,
      ),
    });
    return token;
  }

  function voiceMomentReportTarget(momentId, commentId = null) {
    return {
      targetType: commentId === null ? "voiceMoment" : "voiceMomentComment",
      momentId,
      commentId,
    };
  }

  async function getVoiceMomentsFeedV2(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["cursor", "feedMode", "limit", "sortMode"],
      [],
    );
    const sortMode = data.sortMode ?? "recent";
    if (sortMode !== "recent" && sortMode !== "popular") {
      fail("invalid-argument", "sortMode must be recent or popular.");
    }
    const feedMode = data.feedMode ?? "discover";
    if (feedMode !== "discover" && feedMode !== "following") {
      fail("invalid-argument", "feedMode must be discover or following.");
    }
    if (feedMode === "following" && sortMode !== "recent") {
      fail("invalid-argument", "following feedMode only supports recent sortMode.");
    }
    const limit = data.limit === undefined
      ? MAX_FEED_LIMIT
      : requireSafeInteger(data.limit, "limit", { min: 1, max: MAX_FEED_LIMIT });
    const cursor = data.cursor === undefined
      ? null
      : decodeVoiceMomentPageCursor(data.cursor, {
          kind: "feed",
          sortMode,
          feedMode,
        });
    const timing = time();
    await beginVoiceMomentReadAttempt(auth.uid, timing);
    const scanLimit = limit;

    return db.runTransaction(async (transaction) => {
      const [viewerProfile, viewerRestriction] = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      activeProfile(viewerProfile, "Your");
      assertNotRestricted(viewerRestriction, "Your", timing.nowMs);
      let query = db.collection("voiceMoments").where("isPublished", "==", true);
      query = sortMode === "popular"
        ? query
            .orderBy("likeCount", "desc")
            .orderBy(FieldPath.documentId(), "desc")
        : query
            .orderBy("createdAt", "desc")
            .orderBy(FieldPath.documentId(), "desc");
      if (cursor !== null) {
        query = sortMode === "popular"
          ? query.startAfter(cursor.orderValue, cursor.id)
          : query.startAfter(
              Timestamp.fromMillis(cursor.createdAtMillis),
              cursor.id,
            );
      }
      query = query.limit(scanLimit + 1);
      const snapshot = await transaction.get(query);
      const pageDocuments = snapshot.docs.slice(0, scanLimit);
      const candidates = [];
      for (const document of pageDocuments) {
        try {
          candidates.push({
            document,
            data: publishedMomentForRead(document, document.id, timing.nowMs),
          });
        } catch (_) {
          // A corrupt, expired, deleting or otherwise non-canonical root is
          // omitted. The projection must fail closed per item rather than
          // widening access because a scheduled sweep is late.
        }
      }
      const contexts = await loadVoiceAudienceContexts(
        transaction,
        auth.uid,
        candidates.map((candidate) => candidate.data.authorId),
        { includeSocialEdges: feedMode === "following" },
      );
      const likeSnapshots = candidates.length === 0
        ? []
        : await transactionGetAll(
            transaction,
            ...candidates.map((candidate) =>
              candidate.document.ref.collection("likes").doc(auth.uid)),
          );
      const receiptReferences = candidates.map((candidate) =>
        voiceReportReceiptReference(
          auth.uid,
          voiceMomentReportTarget(candidate.document.id),
        ));
      const receiptSnapshots = receiptReferences.length === 0
        ? []
        : await transactionGetAll(transaction, ...receiptReferences);
      // Re-sample server time only after every transactional read. An item
      // expiring while the callable was resolving privacy must never escape in
      // the response merely because it was alive at request admission.
      const responseTiming = time();
      activeProfile(viewerProfile, "Your");
      assertNotRestricted(
        viewerRestriction,
        "Your",
        responseTiming.nowMs,
      );
      const moments = [];
      for (let index = 0; index < candidates.length; index += 1) {
        const candidate = candidates[index];
        try {
          const activeData = publishedMomentForRead(
            candidate.document,
            candidate.document.id,
            responseTiming.nowMs,
          );
          const context = assertVoiceMomentAudienceFromContext({
            viewerId: auth.uid,
            viewerProfile,
            viewerRestriction,
            authorId: activeData.authorId,
            context: contexts.get(activeData.authorId),
            nowMs: responseTiming.nowMs,
          });
          if (feedMode === "following") {
            assertVoiceMomentSocialRelationship(
              auth.uid,
              activeData.authorId,
              context,
            );
          }
          const callerLiked = validateMomentLike(
            likeSnapshots[index],
            candidate.document.id,
            auth.uid,
          );
          const target = voiceMomentReportTarget(candidate.document.id);
          const reportReceipt = issueVoiceReportReceipt(
            transaction,
            receiptSnapshots[index],
            {
              reference: receiptReferences[index],
              target,
              targetAuthorId: activeData.authorId,
              viewerId: auth.uid,
              timing: responseTiming,
            },
          );
          moments.push(
            voiceMomentProjection(
              candidate.document.id,
              activeData,
              context.publicProfile,
              callerLiked,
              reportReceipt,
            ),
          );
        } catch (_) {
          // Per-author privacy and integrity failures stay indistinguishable
          // from absence in a multi-item feed.
        }
        if (moments.length === limit) break;
      }
      const hasMore = snapshot.size > scanLimit;
      const lastDocument = pageDocuments.at(-1) ?? null;
      const nextCursor = hasMore && lastDocument !== null
        ? encodeVoiceMomentPageCursor({
            kind: "feed",
            id: lastDocument.id,
            createdAtMillis: timestampMillis(lastDocument.get("createdAt")),
            sortMode,
            feedMode,
            orderValue: sortMode === "popular"
              ? lastDocument.get("likeCount")
              : timestampMillis(lastDocument.get("createdAt")),
          })
        : null;
      return {
        schemaVersion: 2,
        moments,
        scannedCount: pageDocuments.length,
        hasMore,
        nextCursor,
      };
    });
  }

  async function getVoiceMomentViewV2(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentCursor", "commentLimit", "momentId", "reactionLimit"],
      ["momentId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const commentCursor = data.commentCursor === undefined
      ? null
      : decodeVoiceMomentPageCursor(data.commentCursor, {
          kind: "comment",
          momentId,
        });
    const commentLimit = data.commentLimit === undefined
      ? MAX_THREAD_COMMENTS
      : requireSafeInteger(data.commentLimit, "commentLimit", {
          min: 1,
          max: MAX_THREAD_COMMENTS,
        });
    const reactionLimit = data.reactionLimit === undefined
      ? MAX_THREAD_REACTIONS
      : requireSafeInteger(data.reactionLimit, "reactionLimit", {
          min: 1,
          max: MAX_THREAD_REACTIONS,
        });
    const timing = time();
    await beginVoiceMomentReadAttempt(auth.uid, timing);

    try {
      return await db.runTransaction(async (transaction) => {
        const momentRef = db.doc(`voiceMoments/${momentId}`);
        const [moment, viewerProfile, viewerRestriction, callerLike] =
          await transactionGetAll(
            transaction,
            momentRef,
            db.doc(`users/${auth.uid}`),
            db.doc(`restrictions/${auth.uid}`),
            momentRef.collection("likes").doc(auth.uid),
          );
        const momentData = publishedMomentForRead(moment, momentId, timing.nowMs);
        activeProfile(viewerProfile, "Your");
        assertNotRestricted(viewerRestriction, "Your", timing.nowMs);

        let commentQuery = momentRef
          .collection("comments")
          .orderBy("createdAt", "asc")
          .orderBy(FieldPath.documentId(), "asc");
        if (commentCursor !== null) {
          commentQuery = commentQuery.startAfter(
            Timestamp.fromMillis(commentCursor.createdAtMillis),
            commentCursor.id,
          );
        }
        commentQuery = commentQuery.limit(commentLimit + 1);
        const reactionQuery = momentRef
          .collection("likes")
          .orderBy("createdAt", "desc")
          .limit(reactionLimit * 2);
        const commentSnapshot = await transaction.get(commentQuery);
        const reactionSnapshot = await transaction.get(reactionQuery);
        const commentDocuments = commentSnapshot.docs.slice(0, commentLimit);
        const comments = [];
        for (const document of commentDocuments) {
          try {
            comments.push({
              document,
              data: validateComment(document, momentId),
            });
          } catch (_) {
            // A malformed child is never projected.
          }
        }
        const reactions = [];
        for (const document of reactionSnapshot.docs) {
          try {
            if (validateMomentLike(document, momentId, document.id)) {
              reactions.push({ document, userId: document.id });
            }
          } catch (_) {
            // A malformed like edge is never used as an identity oracle.
          }
        }
        const authorIds = [
          momentData.authorId,
          ...comments.map((comment) => comment.data.authorId),
          ...reactions.map((reaction) => reaction.userId),
        ];
        const contexts = await loadVoiceAudienceContexts(
          transaction,
          auth.uid,
          authorIds,
        );
        const receiptTargets = [
          voiceMomentReportTarget(momentId),
          ...comments.map((comment) =>
            voiceMomentReportTarget(momentId, comment.document.id)),
        ];
        const receiptReferences = receiptTargets.map((target) =>
          voiceReportReceiptReference(auth.uid, target));
        const receiptSnapshots = await transactionGetAll(
          transaction,
          ...receiptReferences,
        );
        const responseTiming = time();
        const responseMomentData = publishedMomentForRead(
          moment,
          momentId,
          responseTiming.nowMs,
        );
        activeProfile(viewerProfile, "Your");
        assertNotRestricted(
          viewerRestriction,
          "Your",
          responseTiming.nowMs,
        );
        const parentContext = assertVoiceMomentAudienceFromContext({
          viewerId: auth.uid,
          viewerProfile,
          viewerRestriction,
          authorId: responseMomentData.authorId,
          context: contexts.get(responseMomentData.authorId),
          nowMs: responseTiming.nowMs,
        });
        const momentReportReceipt = issueVoiceReportReceipt(
          transaction,
          receiptSnapshots[0],
          {
            reference: receiptReferences[0],
            target: receiptTargets[0],
            targetAuthorId: responseMomentData.authorId,
            viewerId: auth.uid,
            timing: responseTiming,
          },
        );
        const projectedComments = [];
        for (let index = 0; index < comments.length; index += 1) {
          const comment = comments[index];
          try {
            const context = assertVoiceMomentAudienceFromContext({
              viewerId: auth.uid,
              viewerProfile,
              viewerRestriction,
              authorId: comment.data.authorId,
              context: contexts.get(comment.data.authorId),
              nowMs: responseTiming.nowMs,
            });
            const reportReceipt = issueVoiceReportReceipt(
              transaction,
              receiptSnapshots[index + 1],
              {
                reference: receiptReferences[index + 1],
                target: receiptTargets[index + 1],
                targetAuthorId: comment.data.authorId,
                viewerId: auth.uid,
                timing: responseTiming,
              },
            );
            projectedComments.push(
              voiceMomentCommentProjection(
                comment.document.id,
                comment.data,
                context.publicProfile,
                reportReceipt,
              ),
            );
          } catch (_) {
            // A later block/privacy/restriction change hides that comment.
          }
        }
        const topReactions = [];
        for (const reaction of reactions) {
          if (topReactions.length === reactionLimit) break;
          try {
            const context = assertVoiceMomentAudienceFromContext({
              viewerId: auth.uid,
              viewerProfile,
              viewerRestriction,
              authorId: reaction.userId,
              context: contexts.get(reaction.userId),
              nowMs: responseTiming.nowMs,
            });
            const identity = canonicalPublicProfile(
              context.publicProfile,
              reaction.userId,
            );
            topReactions.push({
              userId: reaction.userId,
              displayName: identity.displayName,
              photoUrl: identity.photoUrl,
            });
          } catch (_) {
            // Hidden identities remain included only in the aggregate count.
          }
        }
        const commentsTruncated = commentSnapshot.size > commentLimit;
        const lastComment = commentDocuments.at(-1) ?? null;
        const nextCommentCursor = commentsTruncated && lastComment !== null
          ? encodeVoiceMomentPageCursor({
              kind: "comment",
              id: lastComment.id,
              createdAtMillis: timestampMillis(lastComment.get("createdAt")),
              momentId,
            })
          : null;
        return {
          schemaVersion: 2,
          moment: voiceMomentProjection(
            momentId,
            responseMomentData,
            parentContext.publicProfile,
            validateMomentLike(callerLike, momentId, auth.uid),
            momentReportReceipt,
          ),
          comments: projectedComments,
          commentsTruncated,
          nextCommentCursor,
          topReactions,
        };
      });
    } catch (error) {
      if (
        ["not-found", "failed-precondition", "permission-denied", "data-loss"]
          .includes(error?.code)
      ) {
        fail("permission-denied", "This Voice Moment is unavailable.");
      }
      throw error;
    }
  }

  async function beginStoragePreflight({
    identity,
    kind,
    uid,
    requestId,
    scope,
    timing,
  }) {
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const rateRef = limitReference(scope, uid);
      const [ledger, preflight, rate] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        rateRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      if (preflight.exists) {
        const existing = preflight.data() ?? {};
        if (
          existing.kind !== kind ||
          existing.ownerId !== uid ||
          existing.inputHash !== identity.inputHash
        ) {
          fail("already-exists", "requestId was reused for another upload.");
        }
      } else {
        transaction.create(preflightRef, {
          schemaVersion: 1,
          kind,
          ownerId: uid,
          requestId,
          inputHash: identity.inputHash,
          createdAt: timing.now,
        });
      }
      // An existing preflight is not a completed operation. Every retry that
      // may proceed to Storage therefore consumes another attempt; only the
      // operation-ledger replay above is free. This prevents one permanently
      // invalid upload and requestId from becoming an unbounded Storage-read
      // oracle.
      consume(transaction, rate, rateRef, scope, uid, timing);
      return { replay: null };
    });
  }

  async function reserveMomentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["caption", "durationSeconds", "requestId"],
      ["caption", "durationSeconds", "requestId"],
    );
    const requestId = requireRequestId(data.requestId);
    const caption =
      normalizeText(data.caption, 280, "caption", { allowEmpty: true }) ||
      "Voice Moment";
    const durationSeconds = requireSafeInteger(
      data.durationSeconds,
      "durationSeconds",
      { min: 1, max: 60 },
    );
    const momentId = canonicalMomentId(auth.uid, requestId);
    const storagePath = momentStoragePath(auth.uid, momentId);
    const input = { caption, durationSeconds };
    const identity = operationIdentity(
      "moment.reserve",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();

    const attempt = await beginOperationAttempt({
      identity,
      kind: "moment.reserve",
      uid: auth.uid,
      scope: "uploadReserve",
      timing,
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const [ledger, existing, profileSnapshot, publicProfile, restriction] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          momentRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`publicProfiles/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.reserve",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profileSnapshot, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      // Advisory active-story cap. The query contains published documents
      // only and has no limit, so unpublished filler drafts cannot hide an
      // older permanent Moment. Finalize repeats this under the capacity
      // mutex and remains the authoritative enforcement point.
      const authoredMoments = await transaction.get(
        exactPublishedMomentsQuery(db, auth.uid),
      );
      assertActiveMomentCapacity(authoredMoments, timing.nowMs);
      if (existing.exists) {
        fail(
          "data-loss",
          "A Voice Moment exists without its reservation ledger.",
        );
      }
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(momentRef, {
        schemaVersion: 2,
        authorId: auth.uid,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        caption,
        audioUrl: null,
        storagePath,
        durationSeconds,
        likeCount: 0,
        commentCount: 0,
        replyToMomentId: null,
        isPublished: false,
        isDeleted: false,
        status: "uploading",
        mediaGeneration: null,
        mediaSize: null,
        mediaContentType: null,
        createdAt: timing.now,
        updatedAt: timing.now,
        publishedAt: null,
      });
      const result = { momentId, storagePath, created: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.reserve",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function finalizeMomentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["availabilityHours", "momentId", "objectGeneration", "requestId"],
      ["momentId", "objectGeneration", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    if (!/^[a-f0-9]{20}$/u.test(momentId)) {
      fail("invalid-argument", "momentId is not a canonical reservation id.");
    }
    const requestId = requireRequestId(data.requestId);
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const availability = momentAvailability(data.availabilityHours);
    // WHY THE DEFAULT STAYS OUT OF THE HASH (the reportIdentityInput
    // reasoning, applied here). finalizeMomentDraft is deployed and live:
    // every publish already ledgered hashed exactly
    // `{ momentId, objectGeneration }`, and clients retry a finalize with
    // the same requestId expecting a replay. Folding a default
    // `availabilityHours: 24` in unconditionally would re-key all of those
    // ledgers — the next retry would stop replaying and start answering
    // already-exists. So the default (absent OR an explicit 24 — they are
    // the same request) keeps the deployed hash, while a non-default
    // availability joins it precisely so the same requestId carrying a
    // DIFFERENT duration is a different request: it is refused with
    // already-exists rather than silently replaying the original deadline
    // as if the new one had taken effect.
    const input = { momentId, objectGeneration };
    if (availability !== MIN_MOMENT_AVAILABILITY_HOURS) {
      input.availabilityHours = availability;
    }
    const identity = operationIdentity(
      "moment.finalize",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginStoragePreflight({
      identity,
      kind: "moment.finalize",
      uid: auth.uid,
      requestId,
      scope: "finalize",
      timing,
    });
    if (preflight.replay) return preflight.replay;
    const path = momentStoragePath(auth.uid, momentId);
    const metadata = await storage.getMetadata(path);
    const media = validateStoredAudio(
      metadata,
      { authorId: auth.uid, momentId },
      objectGeneration,
    );
    // Firebase client uploads carry a long-lived download token. Revoke it
    // before making the document public and never persist a bearer URL in
    // Firestore. Playback goes through getVoiceMomentMediaAccess, which
    // re-checks publication, expiry, restrictions and both block directions
    // before minting a generation-bound 90-second signed URL.
    await storage.revokeDownloadTokens(path, metadata);

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const capacityRef = momentCapacityLedgerReference(db, auth.uid);
      const [ledger, preflightLedger, moment, profile, restriction, capacity] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          preflightRef,
          momentRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          capacityRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightData = preflightLedger.exists
        ? (preflightLedger.data() ?? {})
        : {};
      if (
        preflightData.ownerId !== auth.uid ||
        preflightData.kind !== "moment.finalize" ||
        preflightData.inputHash !== identity.inputHash
      ) {
        fail("failed-precondition", "The upload preflight is not canonical.");
      }
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const momentData = validateMoment(moment, momentId, { published: false });
      if (
        momentData.authorId !== auth.uid ||
        momentData.status !== "uploading" ||
        momentData.audioUrl !== null ||
        momentData.mediaGeneration !== null
      ) {
        fail(
          "permission-denied",
          "Only the canonical draft author can publish it.",
        );
      }
      // AUTHORITATIVE ACTIVE-STORY CAP. Reservation intentionally ignores
      // unpublished drafts, so an author may prepare several recordings.
      // This exact published-only query cannot be starved by draft filler.
      // Advancing the shared ledger below serializes two finalizations at the
      // tenth slot and finalization races with delete/expiry.
      const authoredMoments = await transaction.get(
        exactPublishedMomentsQuery(db, auth.uid),
      );
      assertActiveMomentCapacity(authoredMoments, timing.nowMs, {
        excludeMomentId: momentId,
      });
      // The deadline anchors on the STORED createdAt (the reserve
      // transaction's request time), not on this request's clock: the
      // contract the client builds chains and countdowns on is the exact
      // equality `expiresAt == createdAt + availability`, and
      // validateMoment above has already proven createdAt is a real
      // timestamp. On replay the ledger short-circuits before this write,
      // so the deadline never moves after first publish. A "permanent"
      // publish writes NO expiresAt field at all — absence, not null, not
      // a far-future date, is what the sweep's range filter and every
      // client surface read as "stays until the author deletes it".
      const publishUpdate = {
        audioUrl: null,
        isPublished: true,
        status: "published",
        mediaGeneration: media.generation,
        mediaSize: media.size,
        mediaContentType: media.contentType,
        publishedAt: timing.now,
        updatedAt: timing.now,
      };
      if (availability !== PERMANENT_AVAILABILITY) {
        publishUpdate.expiresAt = Timestamp.fromMillis(
          timestampMillis(momentData.createdAt) + availability * HOUR_MS,
        );
      }
      touchMomentCapacityLedger(
        transaction,
        capacityRef,
        capacity,
        auth.uid,
        timing.now,
      );
      transaction.update(momentRef, publishUpdate);
      const result = { momentId, published: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.finalize",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function authorizeVoiceMomentMediaAccess({
    auth,
    momentId,
    commentId,
  }) {
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const [moment, caller, callerRestriction] = await transactionGetAll(
        transaction,
        momentRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const legacyMoment = moment.data()?.schemaVersion !== 2;
      const momentData = legacyMoment
        ? validateLegacyMomentForPlayback(moment, momentId, timing.nowMs)
        : validateMoment(moment, momentId, {
            published: true,
            activeAtMs: timing.nowMs,
          });
      // The compatibility exception applies only to the legacy root audio.
      // A voice reply still carries canonical generation/MIME/size fields and
      // must keep the full v2 media binding even when its parent is legacy.
      const legacyMedia = legacyMoment && commentId === null;

      let mediaAuthorId = momentData.authorId;
      let storagePath = momentData.storagePath;
      let mediaGeneration = momentData.mediaGeneration;
      let mediaContentType = momentData.mediaContentType;
      let mediaSize = momentData.mediaSize;
      if (commentId !== null) {
        const comment = await transaction.get(
          momentRef.collection("comments").doc(commentId),
        );
        const commentData = validateComment(comment, momentId);
        if (commentData.type !== "voice") {
          fail("failed-precondition", "This comment has no voice media.");
        }
        mediaAuthorId = commentData.authorId;
        storagePath = commentData.storagePath;
        mediaGeneration = commentData.mediaGeneration;
        mediaContentType = commentData.mediaContentType;
        mediaSize = commentData.mediaSize;
      }

      // A reply remains part of the parent Moment, but its own author is an
      // independent privacy principal. Re-check account state, profile
      // audience, exact mutual friendship (when needed), and both block
      // directions for every relevant author before issuing a bearer grant.
      const relevantAuthors = [...new Set([momentData.authorId, mediaAuthorId])];
      const contexts = await loadVoiceAudienceContexts(
        transaction,
        auth.uid,
        relevantAuthors,
      );
      for (const authorId of relevantAuthors) {
        assertVoiceMomentAudienceFromContext({
          viewerId: auth.uid,
          viewerProfile: caller,
          viewerRestriction: callerRestriction,
          authorId,
          context: contexts.get(authorId),
          nowMs: timing.nowMs,
        });
      }

      const momentExpiryMs = Object.prototype.hasOwnProperty.call(
        momentData,
        "expiresAt",
      )
        ? timestampMillis(momentData.expiresAt)
        : null;
      return {
        legacyMedia,
        legacyMoment,
        mediaAuthorId,
        commentId,
        mediaContentType,
        mediaGeneration,
        mediaSize,
        storagePath,
        checkedAtMs: timing.nowMs,
        expiresAtMs: Math.min(
          timing.nowMs + MEDIA_ACCESS_TTL_MS,
          momentExpiryMs ?? Number.MAX_SAFE_INTEGER,
        ),
      };
    });
  }

  /**
   * Returns one short-lived, generation-bound read grant for a published
   * Voice Moment or one of its voice replies.
   *
   * Firestore intentionally stores only the canonical object path and media
   * generation. The callable is therefore the sole public read boundary: it
   * re-evaluates account state, exact publication/expiry and both block
   * directions on every grant. A URL copied after that check remains useful
   * for at most MEDIA_ACCESS_TTL_MS and never past the Moment deadline.
   */
  async function getVoiceMomentMediaAccess(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentId", "momentId"],
      ["momentId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const commentId =
      data.commentId === undefined
        ? null
        : requireId(data.commentId, "commentId");

    await beginMediaAccessAttempt(auth.uid, time());

    const access = await authorizeVoiceMomentMediaAccess({
      auth,
      momentId,
      commentId,
    });

    const metadata = await storage.getMetadata(access.storagePath);
    const expected =
      access.commentId === null
        ? { authorId: access.mediaAuthorId, momentId }
        : {
            authorId: access.mediaAuthorId,
            commentId: access.commentId,
            momentId,
          };
    const media = validateStoredAudio(
      metadata,
      expected,
      access.legacyMedia
        ? String(metadata?.generation ?? "")
        : access.mediaGeneration,
    );
    if (
      !access.legacyMedia &&
      (media.contentType !== access.mediaContentType ||
        media.size !== access.mediaSize)
    ) {
      fail("data-loss", "The Voice Moment media no longer matches its record.");
    }
    // Lazy revocation closes legacy v2 documents the first time a modern
    // client reads them. The privileged migration closes the rest in bulk.
    await storage.revokeDownloadTokens(access.storagePath, metadata);
    const url = await storage.getSignedReadUrl(access.storagePath, {
      expiresAtMs: access.expiresAtMs,
      generation: media.generation,
    });
    if (typeof url !== "string" || !url || url.length > 4096) {
      fail("failed-precondition", "A private media grant is unavailable.");
    }
    // Storage I/O and IAM signing happen outside Firestore's transaction.
    // Re-authorize after signing and before returning the bearer capability;
    // a concurrent block, expiry, deletion, comment removal or media swap
    // therefore fails closed instead of leaking the freshly minted URL.
    const finalAccess = await authorizeVoiceMomentMediaAccess({
      auth,
      momentId,
      commentId,
    });
    if (
      finalAccess.checkedAtMs >= access.expiresAtMs ||
      finalAccess.legacyMedia !== access.legacyMedia ||
      finalAccess.legacyMoment !== access.legacyMoment ||
      finalAccess.mediaAuthorId !== access.mediaAuthorId ||
      finalAccess.mediaContentType !== access.mediaContentType ||
      finalAccess.mediaGeneration !== access.mediaGeneration ||
      finalAccess.mediaSize !== access.mediaSize ||
      finalAccess.storagePath !== access.storagePath
    ) {
      fail("aborted", "Voice Moment media authorization changed. Try again.");
    }
    return {
      schemaVersion: 1,
      url,
      expiresAtMillis: access.expiresAtMs,
      mediaGeneration: media.generation,
      mediaContentType: media.contentType,
      mediaSize: media.size,
    };
  }

  async function setMomentLike(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["liked", "momentId", "requestId"],
      ["liked", "momentId", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const liked = requireBoolean(data.liked, "liked");
    const input = { liked, momentId };
    const identity = operationIdentity(
      "moment.like",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const attempt = await beginOperationAttempt({
      identity,
      kind: "moment.like",
      uid: auth.uid,
      scope: "like",
      timing,
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const likeRef = momentRef.collection("likes").doc(auth.uid);
      const [ledger, moment, like] = await transactionGetAll(
        transaction,
        ledgerRef,
        momentRef,
        likeRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.like",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const momentData = validateMoment(moment, momentId, {
        published: true,
        activeAtMs: timing.nowMs,
      });
      const authorId = momentData.authorId;
      await assertVoiceMomentAudience(transaction, {
        viewerId: auth.uid,
        authorId,
        nowMs: timing.nowMs,
      });
      const currentCount = nonNegativeCount(momentData.likeCount, "likeCount");
      const currentlyLiked = validateMomentLike(like, momentId, auth.uid);
      const changed = currentlyLiked !== liked;
      let likeCount = currentCount;
      if (changed && liked) {
        transaction.create(likeRef, {
          schemaVersion: 1,
          userId: auth.uid,
          momentId,
          createdAt: timing.now,
        });
        likeCount = incrementCanonicalCount(likeCount, "likeCount");
      } else if (changed) {
        if (currentCount === 0) {
          fail("data-loss", "likeCount would become negative.");
        }
        transaction.delete(likeRef);
        likeCount -= 1;
      }
      if (changed) {
        transaction.update(momentRef, { likeCount, updatedAt: timing.now });
      }
      const result = { momentId, liked, changed, likeCount };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.like",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function reserveVoiceCommentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["durationSeconds", "momentId", "requestId", "text"],
      ["durationSeconds", "momentId", "requestId", "text"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const durationSeconds = requireSafeInteger(
      data.durationSeconds,
      "durationSeconds",
      { min: 1, max: 60 },
    );
    const text = normalizeText(data.text, 140, "text", { allowEmpty: true });
    const commentId = canonicalCommentId(auth.uid, momentId, requestId);
    const storagePath = voiceReplyStoragePath(auth.uid, momentId, commentId);
    const input = { durationSeconds, momentId, text };
    const identity = operationIdentity(
      "moment.voiceComment.reserve",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const attempt = await beginOperationAttempt({
      identity,
      kind: "moment.voiceComment.reserve",
      uid: auth.uid,
      scope: "uploadReserve",
      timing,
    });
    if (attempt.replay) return attempt.replay;
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const reservationRef = db.doc(
        `voiceMomentUploadReservations/${commentId}`,
      );
      const [
        ledger,
        moment,
        reservation,
        actorProfile,
        publicProfile,
        actorRestriction,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        momentRef,
        reservationRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.voiceComment.reserve",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const momentData = validateMoment(moment, momentId, {
        published: true,
        activeAtMs: timing.nowMs,
      });
      const authorId = momentData.authorId;
      await assertVoiceMomentAudience(transaction, {
        viewerId: auth.uid,
        authorId,
        nowMs: timing.nowMs,
        viewerProfile: actorProfile,
        viewerRestriction: actorRestriction,
      });
      if (reservation.exists) {
        fail(
          "data-loss",
          "A voice-comment reservation exists without its ledger.",
        );
      }
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(reservationRef, {
        schemaVersion: 1,
        kind: "voiceMomentComment",
        ownerId: auth.uid,
        momentId,
        commentId,
        storagePath,
        durationSeconds,
        text,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        status: "uploading",
        createdAt: timing.now,
        expiresAt: Timestamp.fromMillis(timing.nowMs + 30 * 60_000),
      });
      const result = { momentId, commentId, storagePath, created: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.voiceComment.reserve",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function finalizeVoiceCommentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["commentId", "momentId", "objectGeneration", "requestId"],
      ["commentId", "momentId", "objectGeneration", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const commentId = requireId(data.commentId, "commentId");
    if (!/^[a-f0-9]{20}$/u.test(commentId)) {
      fail("invalid-argument", "commentId is not a canonical reservation id.");
    }
    const requestId = requireRequestId(data.requestId);
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const input = { commentId, momentId, objectGeneration };
    const identity = operationIdentity(
      "moment.voiceComment.finalize",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginStoragePreflight({
      identity,
      kind: "moment.voiceComment.finalize",
      uid: auth.uid,
      requestId,
      scope: "finalize",
      timing,
    });
    if (preflight.replay) return preflight.replay;

    const reservationRef = db.doc(`voiceMomentUploadReservations/${commentId}`);
    const reservationSnapshot = await reservationRef.get();
    const reservation = reservationSnapshot.exists
      ? (reservationSnapshot.data() ?? {})
      : {};
    const storagePath = voiceReplyStoragePath(auth.uid, momentId, commentId);
    validateVoiceReservation(reservation, {
      ownerId: auth.uid,
      momentId,
      commentId,
      storagePath,
      nowMs: timing.nowMs,
    });
    const metadata = await storage.getMetadata(storagePath);
    const media = validateStoredAudio(
      metadata,
      { authorId: auth.uid, commentId, momentId },
      objectGeneration,
    );
    await storage.revokeDownloadTokens(storagePath, metadata);

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const commentRef = momentRef.collection("comments").doc(commentId);
      const [
        ledger,
        preflightLedger,
        moment,
        currentReservation,
        comment,
        actorProfile,
        publicProfile,
        actorRestriction,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        momentRef,
        reservationRef,
        commentRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.voiceComment.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightData = preflightLedger.exists
        ? (preflightLedger.data() ?? {})
        : {};
      if (
        preflightData.ownerId !== auth.uid ||
        preflightData.kind !== "moment.voiceComment.finalize" ||
        preflightData.inputHash !== identity.inputHash
      ) {
        fail("failed-precondition", "The upload preflight is not canonical.");
      }
      const momentData = validateMoment(moment, momentId, {
        published: true,
        activeAtMs: timing.nowMs,
      });
      const reservationData = currentReservation.exists
        ? (currentReservation.data() ?? {})
        : {};
      validateVoiceReservation(reservationData, {
        ownerId: auth.uid,
        momentId,
        commentId,
        storagePath,
        nowMs: timing.nowMs,
      });
      if (comment.exists) {
        fail(
          "data-loss",
          "A voice comment exists without its finalize ledger.",
        );
      }
      const authorId = momentData.authorId;
      await assertVoiceMomentAudience(transaction, {
        viewerId: auth.uid,
        authorId,
        nowMs: timing.nowMs,
        viewerProfile: actorProfile,
        viewerRestriction: actorRestriction,
      });
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(commentRef, {
        schemaVersion: 2,
        type: "voice",
        authorId: auth.uid,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        text: reservationData.text,
        audioUrl: null,
        storagePath,
        durationSeconds: reservationData.durationSeconds,
        mediaGeneration: media.generation,
        mediaSize: media.size,
        mediaContentType: media.contentType,
        createdAt: timing.now,
      });
      const commentCount = incrementCanonicalCount(
        momentData.commentCount,
        "commentCount",
      );
      transaction.update(momentRef, { commentCount, updatedAt: timing.now });
      transaction.delete(reservationRef);
      const result = { momentId, commentId, created: true, commentCount };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.voiceComment.finalize",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function createMomentComment(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["momentId", "requestId", "text"],
      ["momentId", "requestId", "text"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const text = normalizeText(data.text, 1000, "text");
    const commentId = canonicalCommentId(auth.uid, momentId, requestId);
    const input = { momentId, text };
    const identity = operationIdentity(
      "moment.comment",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const attempt = await beginOperationAttempt({
      identity,
      kind: "moment.comment",
      uid: auth.uid,
      scope: "comment",
      timing,
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const commentRef = momentRef.collection("comments").doc(commentId);
      const [
        ledger,
        moment,
        existingComment,
        actorProfile,
        publicProfile,
        actorRestriction,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        momentRef,
        commentRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.comment",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const momentData = validateMoment(moment, momentId, {
        published: true,
        activeAtMs: timing.nowMs,
      });
      const authorId = momentData.authorId;
      await assertVoiceMomentAudience(transaction, {
        viewerId: auth.uid,
        authorId,
        nowMs: timing.nowMs,
        viewerProfile: actorProfile,
        viewerRestriction: actorRestriction,
      });
      if (existingComment.exists) {
        fail("data-loss", "A comment exists without its idempotency ledger.");
      }
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(commentRef, {
        schemaVersion: 2,
        type: "text",
        authorId: auth.uid,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        text,
        audioUrl: null,
        storagePath: null,
        durationSeconds: null,
        mediaGeneration: null,
        mediaSize: null,
        mediaContentType: null,
        createdAt: timing.now,
      });
      const commentCount = incrementCanonicalCount(
        momentData.commentCount,
        "commentCount",
      );
      transaction.update(momentRef, { commentCount, updatedAt: timing.now });
      const result = { momentId, commentId, created: true, commentCount };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.comment",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function deleteMomentComment(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentId", "momentId", "requestId"],
      ["commentId", "momentId", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const commentId = requireId(data.commentId, "commentId");
    const requestId = requireRequestId(data.requestId);
    const input = { commentId, momentId };
    const identity = operationIdentity(
      "moment.comment.delete",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const attempt = await beginOperationAttempt({
      identity,
      kind: "moment.comment.delete",
      uid: auth.uid,
      scope: "delete",
      timing,
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const commentRef = momentRef.collection("comments").doc(commentId);
      const [ledger, moment, comment, profile] = await transactionGetAll(
        transaction,
        ledgerRef,
        momentRef,
        commentRef,
        db.doc(`users/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.comment.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      // allowExpired: your own comment stays deletable after the Moment's
      // chosen availability passes — expiry retires a story from feeds; it
      // does not freeze other people's words in place.
      const momentData = validateMoment(moment, momentId, {
        allowExpired: true,
      });
      const commentData = validateComment(comment, momentId);
      if (commentData.authorId !== auth.uid) {
        fail("permission-denied", "You can only delete your own comment.");
      }
      const currentCount = nonNegativeCount(
        momentData.commentCount,
        "commentCount",
      );
      if (currentCount === 0)
        fail("data-loss", "commentCount would become negative.");
      transaction.delete(commentRef);
      transaction.update(momentRef, {
        commentCount: currentCount - 1,
        updatedAt: timing.now,
      });
      if (commentData.type === "voice") {
        const outboxId = digest("comment-cleanup", momentId, commentId);
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "voiceMomentComment",
          rootPath: `voiceMoments/${momentId}/comments/${commentId}`,
          objectPaths: [voiceReplyStoragePath(auth.uid, momentId, commentId)],
          status: "pending",
          attemptCount: 0,
          requestedBy: auth.uid,
          createdAt: timing.now,
          updatedAt: timing.now,
        });
      }
      const result = {
        momentId,
        commentId,
        deleted: true,
        commentCount: currentCount - 1,
      };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.comment.delete",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function deleteMoment(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["momentId", "requestId"],
      ["momentId", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const input = { momentId };
    const identity = operationIdentity(
      "moment.delete",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const attempt = await beginOperationAttempt({
      identity,
      kind: "moment.delete",
      uid: auth.uid,
      scope: "delete",
      timing,
    });
    if (attempt.replay) return attempt.replay;
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const capacityRef = momentCapacityLedgerReference(db, auth.uid);
      const [ledger, moment, profile, capacity] = await transactionGetAll(
        transaction,
        ledgerRef,
        momentRef,
        db.doc(`users/${auth.uid}`),
        capacityRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      // allowExpired: the author keeps the right to delete an expired
      // story — expiry hides it from feeds, deletion is what actually
      // removes the document, its comments and the audio object.
      const momentData = validateMoment(moment, momentId, {
        allowExpired: true,
      });
      if (momentData.authorId !== auth.uid) {
        fail("permission-denied", "You can only delete your own Voice Moment.");
      }
      touchMomentCapacityLedger(
        transaction,
        capacityRef,
        capacity,
        auth.uid,
        timing.now,
      );
      transaction.update(momentRef, {
        isDeleted: true,
        isPublished: false,
        status: "deleting",
        updatedAt: timing.now,
      });
      const outboxId = digest("moment-cleanup", momentId);
      transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
        schemaVersion: 1,
        kind: "voiceMoment",
        rootPath: `voiceMoments/${momentId}`,
        objectPaths: [momentStoragePath(auth.uid, momentId)],
        status: "pending",
        attemptCount: 0,
        requestedBy: auth.uid,
        createdAt: timing.now,
        updatedAt: timing.now,
      });
      const result = { momentId, outboxId, deletionQueued: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "moment.delete",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }),
      );
      return result;
    });
  }

  async function createContentReport(request) {
    // REPORTING IS DELIBERATELY NOT EMAIL-VERIFICATION GATED, and this is
    // the one call in this file that passes { verified: false } for a
    // reason other than "it only touches the caller's own state".
    //
    // requireActor()'s default is { verified: true }, which is right for
    // every OUTBOUND action — publishing a Moment, commenting, sending a
    // DM — because verification is this product's anti-spam gate on
    // things other people have to read. A report is not outbound: it is a
    // safety action, read only by staff, and firestore.rules says so in
    // writing on the sibling reports/{reportId} create rule ("reporting
    // is a SAFETY action and sits with blocking, which that policy
    // explicitly leaves available to a freshly-registered account.
    // Someone being harassed on their first day must be able to say
    // so."). setUserBlock in functions/friends/social_graph.js is
    // consistent with that; this callable was not, so an unverified
    // account could be harassed and could block, but could not report.
    //
    // The volume argument for verification does not apply either: this
    // path is bounded by a transactional 10-per-10-minutes budget and by
    // an operation ledger that makes a repeat report of the same target
    // a replay rather than a second document. Do not "restore" the
    // default here.
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      [
        "channelId",
        "clubId",
        "commentId",
        "conversationId",
        "messageId",
        "momentId",
        "note",
        "reason",
        "reportReceipt",
        "requestId",
        "roomId",
        "targetType",
      ],
      ["reason", "requestId", "targetType"],
    );
    // Checked here rather than inside reportTarget() only to keep the
    // deployed order of refusals: an unknown targetType has always been
    // reported before a malformed requestId or reason.
    if (
      typeof data.targetType !== "string" ||
      !Object.prototype.hasOwnProperty.call(REPORT_TARGETS, data.targetType)
    ) {
      fail("invalid-argument", "targetType is invalid.");
    }
    const requestId = requireRequestId(data.requestId);
    const reason = normalizeText(data.reason, 500, "reason");
    // Optional reporter context, the same bounded field and 300-character
    // cap the client-written v1 report path already uses, so one
    // Moderation Center field renders both. An empty note normalizes to
    // absent rather than to "", so sending `note: ""` cannot produce a
    // different operation identity than sending no note at all.
    const note =
      data.note === undefined || data.note === null
        ? null
        : normalizeText(data.note, MAX_REPORT_NOTE, "note", {
            allowEmpty: true,
          }) || null;
    const target = reportTarget(data);
    const isVoiceTarget =
      target.targetType === "voiceMoment" ||
      target.targetType === "voiceMomentComment";
    const reportReceipt = data.reportReceipt ?? null;
    if (
      (reportReceipt !== null &&
        (typeof reportReceipt !== "string" ||
          !VOICE_REPORT_RECEIPT_TOKEN.test(reportReceipt))) ||
      (!isVoiceTarget && reportReceipt !== null)
    ) {
      fail("invalid-argument", "reportReceipt is invalid for this target.");
    }
    // reportReceipt is intentionally NOT part of reportIdentityInput. It is
    // short-lived authorization for the same stable target, not part of the
    // idempotent operation identity. A lost acknowledgement must still replay
    // after the receipt has been atomically consumed.
    const input = reportIdentityInput(target, reason, note);
    const identity = operationIdentity(
      "content.report",
      auth.uid,
      requestId,
      input,
    );
    const reportId = digest("content-report", auth.uid, requestId).slice(0, 40);
    const timing = time();
    const attempt = await beginOperationAttempt({
      identity,
      kind: "content.report",
      uid: auth.uid,
      scope: "report",
      timing,
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const reportRef = db.doc(`reports/${reportId}`);
      const targetRef = reportTargetReference(db, target);
      const receiptRef = isVoiceTarget
        ? voiceReportReceiptReference(auth.uid, target)
        : null;
      const snapshots = await transactionGetAll(
        transaction,
        ledgerRef,
        reportRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
        targetRef,
        ...(receiptRef === null ? [] : [receiptRef]),
      );
      const [
        ledger,
        existing,
        profile,
        reporterRestriction,
        targetSnapshot,
        receiptSnapshot,
      ] = snapshots;
      const replay = assertLedgerReplay(ledger, {
        kind: "content.report",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const reportTiming = time();
      activeProfile(profile, "Your");
      const receiptData = reportReceipt === null || receiptRef === null
        ? null
        : exactVoiceReportReceipt(
            receiptSnapshot,
            target,
            auth.uid,
            reportTiming.nowMs,
          );
      const authorizedByReceipt = receiptData !== null && receiptTokenMatches(
        receiptData.token,
        reportReceipt,
      );
      if (reportReceipt !== null && !authorizedByReceipt) {
        // One normalized refusal for a guessed, expired, consumed, malformed or
        // target-mismatched capability. Never disclose receipt/target state.
        fail("permission-denied", "You cannot report this Voice Moment.");
      }
      if (!authorizedByReceipt) {
        assertNotRestricted(
          reporterRestriction,
          "Your",
          reportTiming.nowMs,
        );
      }
      // ACCESS BEFORE EXISTENCE, deliberately.
      //
      // The target is the one input a caller fully controls, so the order
      // of these two checks decides whether the endpoint doubles as an
      // existence oracle for private spaces. Answering "not-found" first
      // would let anyone probe whether a given room, Club, channel or
      // message id exists simply by watching which refusal comes back.
      // A caller who cannot read the container is told exactly one thing
      // — permission-denied — whether or not the thing they named is
      // real. Existence is only reported to somebody already entitled to
      // see it.
      if (!authorizedByReceipt) {
        await assertReportTargetVisible(transaction, target, auth.uid, {
          targetSnapshot,
          viewerProfile: profile,
          viewerRestriction: reporterRestriction,
          nowMs: reportTiming.nowMs,
        });
      }
      if (!targetSnapshot.exists)
        fail("not-found", "The reported content is missing.");
      let voiceTargetMetadata = null;
      if (target.targetType === "voiceMoment") {
        const moment = publishedMomentForRead(
          targetSnapshot,
          target.momentId,
          reportTiming.nowMs,
        );
        voiceTargetMetadata = {
          targetId: target.momentId,
          reportedUserId: moment.authorId,
          contextPath: `voiceMoments/${target.momentId}`,
        };
      } else if (target.targetType === "voiceMomentComment") {
        const comment = validateComment(targetSnapshot, target.momentId);
        voiceTargetMetadata = {
          targetId: target.commentId,
          reportedUserId: comment.authorId,
          contextPath:
            `voiceMoments/${target.momentId}/comments/${target.commentId}`,
        };
      }
      if (
        authorizedByReceipt &&
        voiceTargetMetadata.reportedUserId !== receiptData.targetAuthorId
      ) {
        fail("permission-denied", "You cannot report this Voice Moment.");
      }
      if (existing.exists)
        fail("data-loss", "A report exists without its ledger.");
      transaction.create(reportRef, {
        schemaVersion: 2,
        reporterId: auth.uid,
        targetType: target.targetType,
        conversationId: target.conversationId,
        messageId: target.messageId,
        momentId: target.momentId,
        commentId: target.commentId,
        roomId: target.roomId,
        clubId: target.clubId,
        channelId: target.channelId,
        ...(voiceTargetMetadata ?? {}),
        note: note ?? "",
        reason,
        status: "open",
        createdAt: reportTiming.now,
        updatedAt: reportTiming.now,
      });
      if (authorizedByReceipt) transaction.delete(receiptRef);
      const result = { reportId, created: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "content.report",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: reportTiming.now,
        }),
      );
      return result;
    });
  }

  function validateConversationForReport(snapshot, uid) {
    const participants = snapshot.exists
      ? snapshot.data()?.participantIds
      : null;
    if (
      !Array.isArray(participants) ||
      participants.length !== 2 ||
      !participants.includes(uid)
    ) {
      fail(
        "permission-denied",
        "Only a conversation participant may report it.",
      );
    }
  }

  /// The reporter must be somebody who can actually see the reported
  /// content. Without this a report is a read primitive: a caller could
  /// name any room or Club id and learn from the answer whether it exists
  /// and whether a given message is in it.
  ///
  /// Each branch re-reads the container server-side and mirrors the
  /// Firestore rule that governs reading that container's messages. It
  /// deliberately does not consult a client-supplied membership claim of
  /// any kind. Voice Moments additionally re-use the same account,
  /// restriction, bilateral-block, audience and expiry boundary as the v2
  /// feed. Other message surfaces keep their own container semantics.
  async function assertReportTargetVisible(
    transaction,
    target,
    uid,
    { targetSnapshot, viewerProfile, viewerRestriction, nowMs },
  ) {
    switch (target.targetType) {
      case "directMessage":
        validateConversationForReport(
          await transaction.get(
            db.doc(`conversations/${target.conversationId}`),
          ),
          uid,
        );
        return;
      case "roomMessage":
        await assertRoomMessageVisible(transaction, target.roomId, uid);
        return;
      case "clubMessage":
        await assertClubMembership(
          transaction,
          target.clubId,
          uid,
          "You cannot report this Club message.",
        );
        return;
      case "voiceMoment":
      case "voiceMomentComment": {
        const message = "You cannot report this Voice Moment.";
        try {
          const momentSnapshot = target.targetType === "voiceMoment"
            ? targetSnapshot
            : await transaction.get(db.doc(`voiceMoments/${target.momentId}`));
          const moment = publishedMomentForRead(
            momentSnapshot,
            target.momentId,
            nowMs,
          );
          await assertVoiceMomentAudience(transaction, {
            viewerId: uid,
            authorId: moment.authorId,
            nowMs,
            viewerProfile,
            viewerRestriction,
          });
          if (target.targetType === "voiceMomentComment") {
            // Detail v2 applies privacy independently to each comment author.
            // Keep guessed/missing ids inside the same normalized refusal so
            // reporting cannot become an oracle for a now-hidden reply.
            const comment = validateComment(targetSnapshot, target.momentId);
            await assertVoiceMomentAudience(transaction, {
              viewerId: uid,
              authorId: comment.authorId,
              nowMs,
              viewerProfile,
              viewerRestriction,
            });
          }
          return;
        } catch (error) {
          if (
            [
              "not-found",
              "failed-precondition",
              "permission-denied",
              "data-loss",
            ].includes(error?.code)
          ) {
            fail("permission-denied", message);
          }
          throw error;
        }
      }
      default:
        fail("invalid-argument", "targetType is invalid.");
    }
  }

  /// Mirrors the read rule on rooms/{roomId}/messages/{messageId}: a
  /// public room's chat is previewable without joining, and a private
  /// room's needs a host, roomMembers, canonical Club, or host-admitted
  /// participant relationship. Read that rule and this together — if one
  /// moves, the other has to.
  async function assertRoomMessageVisible(transaction, roomId, uid) {
    const message = "You cannot report this room message.";
    const [room, member, participant] = await transactionGetAll(
      transaction,
      db.doc(`rooms/${roomId}`),
      db.doc(`rooms/${roomId}/roomMembers/${uid}`),
      db.doc(`rooms/${roomId}/participants/${uid}`),
    );
    if (!room.exists) fail("permission-denied", message);
    const data = room.data() ?? {};
    // A roomMembers row is authority on its own, matching the rules'
    // separate `|| isRoomMember(roomId)` branch: membership is joined
    // while a room is public and survives the host flipping it private.
    if (data.visibility === "public" || data.hostId === uid || member.exists) {
      return;
    }
    const clubId = typeof data.clubId === "string" ? data.clubId : "";
    if (clubId) {
      // A Club lounge derives admission from canonical Club membership
      // and from nothing else. The id comes out of a document rather than
      // out of the request, so it still has to prove it is a single safe
      // path segment before it is used to build one.
      if (!SAFE_ID.test(clubId)) fail("permission-denied", message);
      await assertClubMembership(transaction, clubId, uid, message);
      return;
    }
    // A participant row only counts when the CURRENT host admitted it,
    // which is what refuses legacy and self-forged rows.
    if (
      participant.exists &&
      typeof data.hostId === "string" &&
      data.hostId &&
      (participant.data() ?? {}).admittedBy === data.hostId
    ) {
      return;
    }
    fail("permission-denied", message);
  }

  /// Mirrors isClubMember(): an existing, active, non-deleting Club, plus
  /// a membership row that names this caller and is not Club-banned.
  async function assertClubMembership(transaction, clubId, uid, message) {
    const [club, member] = await transactionGetAll(
      transaction,
      db.doc(`clubs/${clubId}`),
      db.doc(`clubs/${clubId}/members/${uid}`),
    );
    const clubData = club.exists ? (club.data() ?? {}) : null;
    const memberData = member.exists ? (member.data() ?? {}) : null;
    if (
      !clubData ||
      !memberData ||
      clubData.status !== "active" ||
      clubData.deletionInProgress === true ||
      memberData.userId !== uid ||
      memberData.banned === true
    ) {
      fail("permission-denied", message);
    }
  }

  async function processCleanupOutbox(outboxId) {
    requireId(outboxId, "outboxId");
    const outboxRef = db.doc(`contentCleanupOutbox/${outboxId}`);
    const outbox = await outboxRef.get();
    if (!outbox.exists) return { outboxId, skipped: true };
    const data = outbox.data() ?? {};
    if (
      ![
        "voiceMoment",
        "voiceMomentComment",
        "voiceMomentCommentReservation",
        "directMessageAttachment",
        "directMessageAttachmentReservation",
      ].includes(data.kind) ||
      !Array.isArray(data.objectPaths) ||
      data.objectPaths.some((path) => typeof path !== "string")
    ) {
      fail("data-loss", "The cleanup outbox entry is malformed.");
    }
    const rootParts =
      typeof data.rootPath === "string" ? data.rootPath.split("/") : [];
    if (!isValidOpaqueUid(data.requestedBy)) {
      fail("data-loss", "The cleanup owner is malformed.");
    }
    let expectedObjectPath;
    if (data.kind === "voiceMoment") {
      if (
        rootParts.length !== 2 ||
        rootParts[0] !== "voiceMoments" ||
        !SAFE_ID.test(rootParts[1])
      ) {
        fail("data-loss", "The Moment cleanup root is malformed.");
      }
      expectedObjectPath = momentStoragePath(data.requestedBy, rootParts[1]);
    } else if (data.kind === "voiceMomentComment") {
      if (
        rootParts.length !== 4 ||
        rootParts[0] !== "voiceMoments" ||
        rootParts[2] !== "comments" ||
        !SAFE_ID.test(rootParts[1]) ||
        !/^[A-Za-z0-9]{20}$/u.test(rootParts[3])
      ) {
        fail("data-loss", "The comment cleanup root is malformed.");
      }
      expectedObjectPath = voiceReplyStoragePath(
        data.requestedBy,
        rootParts[1],
        rootParts[3],
      );
    } else if (data.kind === "voiceMomentCommentReservation") {
      if (
        rootParts.length !== 2 ||
        rootParts[0] !== "voiceMomentUploadReservations" ||
        !/^[A-Za-z0-9]{20}$/u.test(rootParts[1])
      ) {
        fail("data-loss", "The reservation cleanup root is malformed.");
      }
      const reservationMomentId = data.objectPaths[0]?.split("/")[2];
      if (!reservationMomentId || !SAFE_ID.test(reservationMomentId)) {
        fail("data-loss", "The reservation cleanup path is malformed.");
      }
      expectedObjectPath = voiceReplyStoragePath(
        data.requestedBy,
        reservationMomentId,
        rootParts[1],
      );
    } else {
      const isReservation = data.kind === "directMessageAttachmentReservation";
      if (isReservation) {
        if (
          rootParts.length !== 2 ||
          rootParts[0] !== "directMessageUploadReservations" ||
          !/^m_[a-f0-9]{40}$/u.test(rootParts[1])
        ) {
          fail(
            "data-loss",
            "The direct reservation cleanup root is malformed.",
          );
        }
      } else if (
        rootParts.length !== 4 ||
        rootParts[0] !== "conversations" ||
        rootParts[2] !== "messages" ||
        !SAFE_ID.test(rootParts[1]) ||
        !/^m_[a-f0-9]{40}$/u.test(rootParts[3])
      ) {
        fail("data-loss", "The direct attachment cleanup root is malformed.");
      }
      const path = data.objectPaths[0];
      const segments = typeof path === "string" ? path.split("/") : [];
      const messageId = isReservation ? rootParts[1] : rootParts[3];
      const conversationId = isReservation ? segments[2] : rootParts[1];
      if (
        segments.length !== 4 ||
        segments[0] !== "message_attachments" ||
        segments[1] !== data.requestedBy ||
        segments[2] !== conversationId ||
        !SAFE_ID.test(conversationId) ||
        !new RegExp(`^${messageId}[.](jpg|png|webp|m4a)$`, "u").test(
          segments[3],
        )
      ) {
        fail("data-loss", "The direct attachment cleanup path is malformed.");
      }
      expectedObjectPath = path;
    }
    if (
      data.objectPaths.length !== 1 ||
      data.objectPaths[0] !== expectedObjectPath
    ) {
      fail("data-loss", "The cleanup object path is not canonical.");
    }
    if (data.status === "completed") return { outboxId, completed: true };
    const timing = time();
    const objectPaths = [...data.objectPaths];
    let commentPage = null;
    let nextCursor = null;
    const quarantined = [];
    if (data.kind === "voiceMoment") {
      const momentId = String(data.rootPath ?? "").split("/")[1] ?? "";
      requireId(momentId, "cleanup momentId");
      let query = db
        .collection(`voiceMoments/${momentId}/comments`)
        .orderBy(FieldPath.documentId())
        .limit(cleanupPageSize);
      if (typeof data.commentCursor === "string" && data.commentCursor) {
        query = query.startAfter(data.commentCursor);
      }
      commentPage = await query.get();
      for (const comment of commentPage.docs) {
        const commentData = comment.data() ?? {};
        if (commentData.type === "voice") {
          if (
            isValidOpaqueUid(commentData.authorId) &&
            /^[A-Za-z0-9]{20}$/u.test(comment.id)
          ) {
            objectPaths.push(
              voiceReplyStoragePath(commentData.authorId, momentId, comment.id),
            );
          } else {
            quarantined.push({
              commentId: comment.id.slice(0, 128),
              reason: "nonCanonicalVoiceReplyIdentity",
            });
          }
        }
      }
      nextCursor = commentPage.docs.at(-1)?.id ?? data.commentCursor ?? null;
    }
    for (const path of [...new Set(objectPaths)]) {
      await storage.deleteObject(path, { ignoreNotFound: true });
    }
    await Promise.all(
      quarantined.map((entry) =>
        db
          .doc(
            `contentCleanupQuarantine/${digest(
              "cleanup-quarantine",
              outboxId,
              entry.commentId,
            )}`,
          )
          .set({
            schemaVersion: 1,
            outboxId,
            rootPath: data.rootPath,
            ...entry,
            createdAt: timing.now,
          }),
      ),
    );
    const needsAnotherPage =
      data.kind === "voiceMoment" && commentPage.size === cleanupPageSize;
    if (
      !needsAnotherPage &&
      data.kind === "voiceMoment" &&
      typeof db.recursiveDelete === "function"
    ) {
      await db.recursiveDelete(db.doc(data.rootPath));
    }
    const attemptCount = incrementCanonicalCount(
      data.attemptCount ?? 0,
      "attemptCount",
    );
    if (needsAnotherPage) {
      const priorProcessed = nonNegativeCount(
        data.processedCommentCount ?? 0,
        "processedCommentCount",
      );
      if (priorProcessed > Number.MAX_SAFE_INTEGER - commentPage.size) {
        fail(
          "data-loss",
          "processedCommentCount cannot be incremented safely.",
        );
      }
      await outboxRef.update({
        status: "pending",
        commentCursor: nextCursor,
        processedCommentCount: priorProcessed + commentPage.size,
        attemptCount,
        updatedAt: timing.now,
      });
      return { outboxId, completed: false, nextCursor, quarantined };
    }
    await outboxRef.update({
      status: "completed",
      attemptCount,
      updatedAt: timing.now,
      completedAt: timing.now,
    });
    return { outboxId, completed: true, quarantined };
  }

  async function expireAbandonedMomentDrafts({
    olderThanMs = 24 * 60 * 60_000,
    limit = 100,
    cursor = null,
  } = {}) {
    requireSafeInteger(olderThanMs, "olderThanMs", { min: 60_000 });
    requireSafeInteger(limit, "limit", { min: 1, max: 200 });
    if (
      cursor !== null &&
      (!isPlainObject(cursor) ||
        !Number.isSafeInteger(cursor.createdAtMs) ||
        cursor.createdAtMs < 0 ||
        typeof cursor.id !== "string")
    ) {
      fail("invalid-argument", "cursor is invalid.");
    }
    if (cursor !== null) requireId(cursor.id, "cursor.id");
    const timing = time();
    const cutoffMs = timing.nowMs - olderThanMs;
    let query = db
      .collection("voiceMoments")
      .where("status", "==", "uploading")
      .where("createdAt", "<=", Timestamp.fromMillis(cutoffMs))
      .orderBy("createdAt")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor) {
      query = query.startAfter(
        Timestamp.fromMillis(cursor.createdAtMs),
        cursor.id,
      );
    }
    const snapshot = await query.get();
    const expired = [];
    const malformed = [];
    for (const document of snapshot.docs) {
      const createdAtMs = timestampMillis(document.data()?.createdAt);
      if (createdAtMs === null) {
        malformed.push(document.id);
        continue;
      }
      const changed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return false;
        const currentData = current.data() ?? {};
        const currentCreatedAt = timestampMillis(currentData.createdAt);
        if (
          currentData.status !== "uploading" ||
          currentData.isPublished !== false ||
          currentData.isDeleted === true ||
          currentCreatedAt === null ||
          currentCreatedAt > cutoffMs ||
          typeof currentData.authorId !== "string" ||
          currentData.storagePath !==
            momentStoragePath(currentData.authorId, current.id)
        ) {
          return false;
        }
        transaction.update(current.ref, {
          isDeleted: true,
          status: "deleting",
          updatedAt: timing.now,
        });
        const outboxId = digest("moment-cleanup", current.id);
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "voiceMoment",
          rootPath: current.ref.path,
          objectPaths: [currentData.storagePath],
          status: "pending",
          attemptCount: 0,
          requestedBy: currentData.authorId,
          requestedReason: "abandonedUpload",
          createdAt: timing.now,
          updatedAt: timing.now,
        });
        return true;
      });
      if (changed) expired.push(document.id);
    }
    return {
      expired,
      malformed,
      nextCursor:
        snapshot.docs.length === 0
          ? null
          : {
              createdAtMs: timestampMillis(
                snapshot.docs.at(-1).data().createdAt,
              ),
              id: snapshot.docs.at(-1).id,
            },
      hasMore: snapshot.size === limit,
    };
  }

  async function expireAbandonedVoiceCommentDrafts({
    limit = 100,
    cursor = null,
  } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 200 });
    if (
      cursor !== null &&
      (!isPlainObject(cursor) ||
        !Number.isSafeInteger(cursor.expiresAtMs) ||
        cursor.expiresAtMs < 0 ||
        typeof cursor.id !== "string")
    ) {
      fail("invalid-argument", "cursor is invalid.");
    }
    if (cursor !== null) requireId(cursor.id, "cursor.id");
    const timing = time();
    let query = db
      .collection("voiceMomentUploadReservations")
      .where("status", "==", "uploading")
      .where("expiresAt", "<=", timing.now)
      .orderBy("expiresAt")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor) {
      query = query.startAfter(
        Timestamp.fromMillis(cursor.expiresAtMs),
        cursor.id,
      );
    }
    const snapshot = await query.get();
    const expired = [];
    const malformed = [];
    for (const document of snapshot.docs) {
      const changed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return false;
        const reservation = current.data() ?? {};
        const expiresAtMs = timestampMillis(reservation.expiresAt);
        if (
          reservation.status !== "uploading" ||
          expiresAtMs === null ||
          expiresAtMs > timing.nowMs
        ) {
          return false;
        }
        const quarantine = () => {
          transaction.set(
            db.doc(
              `contentCleanupQuarantine/${digest(
                "expired-reservation-quarantine",
                current.id,
              )}`,
            ),
            {
              schemaVersion: 1,
              rootPath: current.ref.path,
              reason: "nonCanonicalExpiredVoiceCommentReservation",
              createdAt: timing.now,
            },
          );
          transaction.delete(current.ref);
          return "malformed";
        };
        if (
          !isValidOpaqueUid(reservation.ownerId) ||
          typeof reservation.momentId !== "string" ||
          !SAFE_ID.test(reservation.momentId) ||
          !/^[A-Za-z0-9]{20}$/u.test(current.id)
        ) {
          return quarantine();
        }
        const canonicalPath = voiceReplyStoragePath(
          reservation.ownerId,
          reservation.momentId,
          current.id,
        );
        if (
          reservation.commentId !== current.id ||
          reservation.storagePath !== canonicalPath
        ) {
          return quarantine();
        }
        transaction.delete(current.ref);
        const outboxId = digest(
          "voice-comment-reservation-cleanup",
          current.id,
        );
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "voiceMomentCommentReservation",
          rootPath: current.ref.path,
          objectPaths: [canonicalPath],
          status: "pending",
          attemptCount: 0,
          requestedBy: reservation.ownerId,
          requestedReason: "expiredUploadReservation",
          createdAt: timing.now,
          updatedAt: timing.now,
        });
        return true;
      });
      if (changed === true) expired.push(document.id);
      else if (changed === "malformed") malformed.push(document.id);
    }
    return {
      expired,
      malformed,
      nextCursor:
        snapshot.docs.length === 0
          ? null
          : {
              expiresAtMs: timestampMillis(
                snapshot.docs.at(-1).data().expiresAt,
              ),
              id: snapshot.docs.at(-1).id,
            },
      hasMore: snapshot.size === limit,
    };
  }

  return {
    createContentReport,
    createMomentComment,
    deleteMoment,
    deleteMomentComment,
    expireAbandonedMomentDrafts,
    expireAbandonedVoiceCommentDrafts,
    finalizeVoiceCommentDraft,
    finalizeMomentDraft,
    getVoiceMomentViewV2,
    getVoiceMomentMediaAccess,
    getVoiceMomentsFeedV2,
    processCleanupOutbox,
    reserveMomentDraft,
    reserveVoiceCommentDraft,
    setMomentLike,
  };
}

function createBucketStorageAdapter(bucket) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  async function hardenManagedImageMetadata(
    path,
    metadata,
    requiredMetadata,
  ) {
    const generation = String(metadata?.generation ?? "");
    if (!/^[0-9]{1,30}$/u.test(generation)) {
      fail("data-loss", "The managed image generation is malformed.");
    }
    if (
      !requiredMetadata ||
      typeof requiredMetadata !== "object" ||
      Array.isArray(requiredMetadata) ||
      Object.entries(requiredMetadata).some(
        ([key, value]) =>
          !/^[A-Za-z][A-Za-z0-9]{0,63}$/u.test(key) ||
          typeof value !== "string" ||
          value.length === 0 ||
          value.length > 256,
      )
    ) {
      fail("failed-precondition", "The managed image identity is invalid.");
    }
    const custom = customMetadataOf(metadata);
    const [updated] = await bucket.file(path).setMetadata(
      {
        metadata: {
          ...custom,
          ...requiredMetadata,
          firebaseStorageDownloadTokens: null,
        },
      },
      { ifGenerationMatch: generation },
    );
    return updated;
  }
  return {
    bucketName: bucket.name,
    getObjectReference(path) {
      if (typeof bucket.name !== "string" || !bucket.name) {
        fail("failed-precondition", "The Storage bucket name is unavailable.");
      }
      return `gs://${bucket.name}/${path}`;
    },
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },
    async getDownloadUrl(path, metadata) {
      const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
      if (!token || typeof bucket.name !== "string") {
        fail(
          "failed-precondition",
          "The object has no canonical download token.",
        );
      }
      return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(
        bucket.name,
      )}/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`;
    },
    async revokeDownloadTokens(path, metadata, { requiredMetadata = null } = {}) {
      const custom = customMetadataOf(metadata);
      const additions = requiredMetadata ?? {};
      if (
        !additions ||
        typeof additions !== "object" ||
        Array.isArray(additions) ||
        Object.entries(additions).some(
          ([key, value]) =>
            !/^[A-Za-z][A-Za-z0-9]{0,63}$/u.test(key) ||
            typeof value !== "string" ||
            value.length === 0 ||
            value.length > 256,
        )
      ) {
        fail("failed-precondition", "The private media identity is invalid.");
      }
      const hasToken =
        typeof custom.firebaseStorageDownloadTokens === "string" &&
        custom.firebaseStorageDownloadTokens.length > 0;
      const hasRequiredMetadata = Object.entries(additions).every(
        ([key, value]) => custom[key] === value,
      );
      if (!hasToken && hasRequiredMetadata) {
        return metadata;
      }
      const generation = String(metadata?.generation ?? "");
      if (!/^[0-9]{1,30}$/u.test(generation)) {
        fail("data-loss", "The private media generation is malformed.");
      }
      const [updated] = await bucket.file(path).setMetadata(
        {
          metadata: {
            ...custom,
            ...additions,
            // google-cloud/storage serializes null as metadata deletion. Keep
            // every canonical identity field and remove only Firebase's
            // permanent bearer capability.
            firebaseStorageDownloadTokens: null,
          },
        },
        // Never strip a token from a different object recreated at the same
        // path after the metadata read.
        { ifGenerationMatch: generation },
      );
      return updated;
    },
    hardenManagedImageMetadata,
    async hardenRoomCoverMetadata(path, metadata, { ownerId, roomId }) {
      return hardenManagedImageMetadata(path, metadata, {
        ownerId,
        roomId,
      });
    },
    async listObjects(prefixOrOptions, maybeOptions = {}) {
      const options = typeof prefixOrOptions === "string"
        ? { ...maybeOptions, prefix: prefixOrOptions }
        : prefixOrOptions;
      const {
        prefix,
        pageToken = null,
        maxResults = 200,
      } = options ?? {};
      if (
        typeof prefix !== "string" ||
        prefix.length === 0 ||
        prefix.length > 1024 ||
        (pageToken !== null &&
          (typeof pageToken !== "string" || pageToken.length > 4096)) ||
        !Number.isSafeInteger(maxResults) ||
        maxResults < 1 ||
        maxResults > 1000
      ) {
        fail("invalid-argument", "The Storage inventory request is invalid.");
      }
      const [files, nextQuery] = await bucket.getFiles({
        prefix,
        maxResults,
        autoPaginate: false,
        ...(pageToken === null ? {} : { pageToken }),
      });
      return {
        names: files.map((file) => file.name),
        nextPageToken:
          typeof nextQuery?.pageToken === "string" && nextQuery.pageToken
            ? nextQuery.pageToken
            : null,
      };
    },
    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      if (
        !Number.isSafeInteger(expiresAtMs) ||
        expiresAtMs <= 0 ||
        typeof generation !== "string" ||
        !/^[0-9]{1,30}$/u.test(generation)
      ) {
        fail("failed-precondition", "The private media grant is malformed.");
      }
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4",
        action: "read",
        expires: expiresAtMs,
        queryParams: { generation },
      });
      return url;
    },
    async deleteObject(path, { ignoreNotFound = false } = {}) {
      await bucket.file(path).delete({ ignoreNotFound });
    },
  };
}

module.exports = {
  DEFAULT_LIMITS,
  MAX_MOMENT_AVAILABILITY_HOURS,
  MAX_ACTIVE_MOMENTS,
  MIN_MOMENT_AVAILABILITY_HOURS,
  MOMENT_TTL_MS,
  PERMANENT_AVAILABILITY,
  VOICE_MOMENT_V2_READ_BUDGETS,
  canonicalCommentId,
  canonicalMomentId,
  createBucketStorageAdapter,
  createMomentIntegrityService,
  momentStoragePath,
  validateComment,
  validateLegacyMomentForPlayback,
  validateMoment,
  validateMomentLike,
  validateStoredAudio,
  voiceReplyStoragePath,
};

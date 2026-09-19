// The pure contract of photo and video messages in Servers V1 text channels:
// ids, the private Storage layout, the exact upload metadata, the stored media
// descriptor and the durable deletion jobs. No I/O and no SDK here, so the
// callable service, the club-message moderation callable, the server content
// cleanup and account deletion all derive the SAME paths from the same inputs
// instead of trusting a stored string.
//
// Storage layout (storage.rules `match /server_message_media/...`):
//   server_message_media/{serverId}/{channelId}/{ownerUid}/{messageId}.{ext}
// messageId = "cm_" + digest("club-message-media", serverId, channelId, uid,
// requestId).slice(0, 40), so a retried reservation lands on the same object.

const { digest, fail, requireId, requireRequestId, requireUid } = require("../integrity/guards");
const { DIRECT_MEDIA_TYPES } = require("../messaging/direct_integrity");

const SERVER_MESSAGE_MEDIA_SCHEMA_VERSION = 1;
const SERVER_MESSAGE_MEDIA_PREFIX = "server_message_media";
const SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS = 15 * 60_000;
const SERVER_MESSAGE_MEDIA_ACCESS_TTL_MS = 90_000;
const SERVER_MESSAGE_MEDIA_DAILY_BYTES = 512 * 1024 * 1024;
const SERVER_MESSAGE_MEDIA_MAX_ACCESS_IDS = 20;
const SERVER_MESSAGE_MEDIA_MAX_DURATION_SECONDS = 60;
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const MESSAGE_ID_PATTERN = /^cm_[a-f0-9]{40}$/u;

// Collections, every one Admin-SDK-only (firestore.rules denies all client
// reads and writes explicitly).
const RESERVATIONS = "serverMessageMediaUploadReservations";
const LEASES = "serverMessageMediaUploadLeases";
const BUDGETS = "serverMessageMediaUploadBudgets";
const DELETION_JOBS = "serverMessageMediaDeletionJobs";
// One row per published object, keyed by messageId and carrying the owner, so
// account deletion can reach an author's objects across every server — the
// uid is the fourth path segment, never a prefix.
const OBJECTS = "serverMessageMediaObjects";

// The direct-message image and video bounds, reused rather than copied.
const SERVER_MESSAGE_MEDIA_TYPES = Object.freeze({
  image: DIRECT_MEDIA_TYPES.image,
  video: DIRECT_MEDIA_TYPES.video,
});
const EXTENSIONS = Object.freeze({
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "video/mp4": "mp4",
  "video/quicktime": "mov",
  "video/webm": "webm",
});
// The content fallback every installed client renders when it does not know
// the media fields (builds up to 3.0.0+34 draw `content` whenever gif is null).
const CONTENT_FALLBACK = Object.freeze({ image: "Photo", video: "Video" });

function mediaTypeOf(type) {
  const value = SERVER_MESSAGE_MEDIA_TYPES[type];
  if (!value || !Object.hasOwn(SERVER_MESSAGE_MEDIA_TYPES, type)) {
    fail("invalid-argument", "type is invalid.");
  }
  return value;
}

/** The media contract a reservation or descriptor must satisfy exactly. */
function requireMediaShape({ type, contentType, size, durationSeconds }, code = "invalid-argument") {
  let bounds;
  try {
    bounds = mediaTypeOf(type);
  } catch (_) {
    fail(code, "type is invalid.");
  }
  if (typeof contentType !== "string" || !bounds.contentTypes.includes(contentType)) {
    fail(code, "contentType is invalid.");
  }
  if (!Number.isSafeInteger(size) || size < bounds.minBytes || size > bounds.maxBytes) {
    fail(code, "size is invalid.");
  }
  if (type === "image" ? durationSeconds !== null
    : !Number.isSafeInteger(durationSeconds) || durationSeconds < 1 ||
      durationSeconds > SERVER_MESSAGE_MEDIA_MAX_DURATION_SECONDS) {
    fail(code, "durationSeconds is invalid.");
  }
  return { type, contentType, size, durationSeconds };
}

function serverMessageMediaMessageId(serverId, channelId, uid, requestId) {
  requireId(serverId, "serverId");
  requireId(channelId, "channelId");
  requireUid(uid);
  requireRequestId(requestId);
  return `cm_${digest("club-message-media", serverId, channelId, uid, requestId).slice(0, 40)}`;
}

function serverMessagePath(serverId, channelId, messageId) {
  requireId(serverId, "serverId");
  requireId(channelId, "channelId");
  requireId(messageId, "messageId");
  return `clubs/${serverId}/channels/${channelId}/messages/${messageId}`;
}

function serverMessageMediaStoragePath({ serverId, channelId, ownerId, messageId, contentType }) {
  requireId(serverId, "serverId");
  requireId(channelId, "channelId");
  requireUid(ownerId, "ownerId");
  if (typeof messageId !== "string" || !MESSAGE_ID_PATTERN.test(messageId)) {
    fail("invalid-argument", "messageId is invalid.");
  }
  if (typeof contentType !== "string" || !Object.hasOwn(EXTENSIONS, contentType)) {
    fail("invalid-argument", "contentType is invalid.");
  }
  return `${SERVER_MESSAGE_MEDIA_PREFIX}/${serverId}/${channelId}/${ownerId}/${messageId}.${EXTENSIONS[contentType]}`;
}

/** The exact custom metadata an upload must carry (and keeps after finalize). */
function serverMessageMediaUploadMetadata({ serverId, channelId, ownerId, messageId, type }) {
  return Object.freeze({
    yovoiceServerId: serverId,
    yovoiceChannelId: channelId,
    yovoiceOwnerUid: ownerId,
    yovoiceMessageId: messageId,
    // The binding admin/messages.js `deleteAttachments` requires before it
    // deletes a message's object: exact message path AND author uid.
    yovoiceMessagePath: serverMessagePath(serverId, channelId, messageId),
    yovoiceMediaType: type,
  });
}

function requireGeneration(value, label = "objectGeneration") {
  if (typeof value !== "string" || !GENERATION_PATTERN.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

/**
 * The stored `media` descriptor of a published message, validated exactly
 * and bound to the message's own identity. Null when absent; data-loss when
 * present but wrong, so no caller ever signs or deletes a path it derived
 * from a forged descriptor.
 */
function canonicalServerMessageMedia(message, { serverId, channelId, messageId }) {
  const media = message?.media;
  if (media === undefined || media === null) return null;
  const keys = media && typeof media === "object" && !Array.isArray(media)
    ? Object.keys(media).sort() : [];
  const expected = ["contentType", "durationSeconds", "generation", "schemaVersion", "size", "storagePath"];
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index]) ||
      media.schemaVersion !== SERVER_MESSAGE_MEDIA_SCHEMA_VERSION ||
      typeof media.generation !== "string" || !GENERATION_PATTERN.test(media.generation) ||
      !["image", "video"].includes(message.type)) {
    fail("data-loss", "The server message media is malformed.");
  }
  requireMediaShape({
    type: message.type,
    contentType: media.contentType,
    size: media.size,
    durationSeconds: media.durationSeconds,
  }, "data-loss");
  let canonicalPath;
  try {
    canonicalPath = serverMessageMediaStoragePath({
      serverId, channelId, ownerId: message.senderId, messageId, contentType: media.contentType,
    });
  } catch (_) {
    fail("data-loss", "The server message media is malformed.");
  }
  if (media.storagePath !== canonicalPath) {
    fail("data-loss", "The server message media is malformed.");
  }
  return Object.freeze({ ...media, type: message.type, ownerId: message.senderId });
}

function objectDeletionJobId(serverId, channelId, messageId) {
  return `smd_${digest("server.message.media.delete.v1", serverId, channelId, messageId).slice(0, 40)}`;
}

function prefixDeletionJobId(prefix) {
  return `smp_${digest("server.message.media.prefix.v1", prefix).slice(0, 40)}`;
}

/** A durable job that deletes exactly one published object by generation. */
function objectDeletionJob({ serverId, channelId, messageId, media, reason, now }) {
  const jobId = objectDeletionJobId(serverId, channelId, messageId);
  return {
    jobId,
    document: {
      schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
      kind: "serverChannelMessageMediaDelete",
      target: "object",
      jobId,
      serverId,
      channelId,
      messageId,
      ownerId: media.ownerId,
      storagePath: media.storagePath,
      generation: media.generation,
      reason,
      status: "pending",
      createdAt: now,
      updatedAt: now,
    },
  };
}

function channelMediaPrefix(serverId, channelId) {
  requireId(serverId, "serverId");
  if (channelId === null) return `${SERVER_MESSAGE_MEDIA_PREFIX}/${serverId}/`;
  requireId(channelId, "channelId");
  return `${SERVER_MESSAGE_MEDIA_PREFIX}/${serverId}/${channelId}/`;
}

/**
 * A durable job that sweeps every object under one channel's (or, with a
 * null channelId, one server's) prefix, page by page, generation-guarded.
 * Written by the server content cleanup when a channel or server is deleted.
 */
function prefixDeletionJob({ serverId, channelId = null, reason, now }) {
  const prefix = channelMediaPrefix(serverId, channelId);
  const jobId = prefixDeletionJobId(prefix);
  return {
    jobId,
    document: {
      schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
      kind: "serverChannelMessageMediaDelete",
      target: "prefix",
      jobId,
      serverId,
      channelId,
      prefix,
      reason,
      status: "pending",
      createdAt: now,
      updatedAt: now,
    },
  };
}

/** Parses one object name under the server media prefix, or null. */
function parseServerMessageMediaObjectName(name) {
  if (typeof name !== "string") return null;
  const segments = name.split("/");
  if (segments.length !== 5 || segments[0] !== SERVER_MESSAGE_MEDIA_PREFIX) return null;
  const [, serverId, channelId, ownerId, fileName] = segments;
  const dot = fileName.lastIndexOf(".");
  const messageId = dot > 0 ? fileName.slice(0, dot) : "";
  const extension = dot > 0 ? fileName.slice(dot + 1) : "";
  if (!/^[A-Za-z0-9_-]{1,128}$/u.test(serverId) || !/^[A-Za-z0-9_-]{1,128}$/u.test(channelId) ||
      !ownerId || !MESSAGE_ID_PATTERN.test(messageId) ||
      !Object.values(EXTENSIONS).includes(extension)) {
    return null;
  }
  return { serverId, channelId, ownerId, messageId };
}

module.exports = {
  BUDGETS,
  CONTENT_FALLBACK,
  DELETION_JOBS,
  EXTENSIONS,
  GENERATION_PATTERN,
  LEASES,
  MESSAGE_ID_PATTERN,
  OBJECTS,
  RESERVATIONS,
  SERVER_MESSAGE_MEDIA_ACCESS_TTL_MS,
  SERVER_MESSAGE_MEDIA_DAILY_BYTES,
  SERVER_MESSAGE_MEDIA_MAX_ACCESS_IDS,
  SERVER_MESSAGE_MEDIA_MAX_DURATION_SECONDS,
  SERVER_MESSAGE_MEDIA_PREFIX,
  SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS,
  SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
  SERVER_MESSAGE_MEDIA_TYPES,
  canonicalServerMessageMedia,
  channelMediaPrefix,
  objectDeletionJob,
  objectDeletionJobId,
  parseServerMessageMediaObjectName,
  prefixDeletionJob,
  prefixDeletionJobId,
  requireGeneration,
  requireMediaShape,
  serverMessageMediaMessageId,
  serverMessageMediaStoragePath,
  serverMessageMediaUploadMetadata,
  serverMessagePath,
};

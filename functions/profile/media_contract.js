const { fail, isValidOpaqueUid, timestampMillis } = require("../integrity/guards");

const PROFILE_MEDIA_SCHEMA_VERSION = 1;
const PROFILE_MEDIA_KINDS = Object.freeze(["avatar", "banner"]);
const PROFILE_MEDIA_TYPES = Object.freeze([
  "image/jpeg",
  "image/png",
  "image/webp",
]);
const MIN_PROFILE_MEDIA_BYTES = 128;
const MAX_PROFILE_MEDIA_BYTES = 2 * 1024 * 1024;
const PROFILE_MEDIA_ACCESS_TTL_MS = 90_000;
const PROFILE_MEDIA_NEGATIVE_TTL_MS = 30_000;
const PROFILE_MEDIA_UPLOAD_TTL_MS = 10 * 60_000;
const PROFILE_MEDIA_UPLOAD_ID = /^[a-f0-9]{32}$/u;
const PROFILE_MEDIA_GENERATION = /^[0-9]{1,30}$/u;

const EXTENSION_BY_CONTENT_TYPE = Object.freeze({
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
});

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value, expected) {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value).sort();
  const canonical = [...expected].sort();
  return keys.length === canonical.length &&
    keys.every((key, index) => key === canonical[index]);
}

function requireProfileMediaKind(value) {
  if (!PROFILE_MEDIA_KINDS.includes(value)) {
    fail("invalid-argument", "kind must be avatar or banner.");
  }
  return value;
}

function requireProfileMediaContentType(value) {
  if (!PROFILE_MEDIA_TYPES.includes(value)) {
    fail("invalid-argument", "The profile image type is unsupported.");
  }
  return value;
}

function requireProfileMediaSize(value) {
  if (!Number.isSafeInteger(value) ||
      value < MIN_PROFILE_MEDIA_BYTES ||
      value > MAX_PROFILE_MEDIA_BYTES) {
    fail("invalid-argument", "The profile image size is invalid.");
  }
  return value;
}

function requireProfileMediaUploadId(value) {
  if (typeof value !== "string" || !PROFILE_MEDIA_UPLOAD_ID.test(value)) {
    fail("invalid-argument", "uploadId is invalid.");
  }
  return value;
}

function profileMediaStoragePath(ownerId, kind, uploadId, contentType) {
  if (!isValidOpaqueUid(ownerId)) {
    fail("invalid-argument", "The profile owner is invalid.");
  }
  requireProfileMediaKind(kind);
  requireProfileMediaUploadId(uploadId);
  requireProfileMediaContentType(contentType);
  return `users/${ownerId}/profile/${kind}_${uploadId}.` +
    EXTENSION_BY_CONTENT_TYPE[contentType];
}

function parseProfileMediaStoragePath(value) {
  if (typeof value !== "string" || value.length > 1024) return null;
  const segments = value.split("/");
  if (segments.length !== 4 ||
      segments[0] !== "users" ||
      segments[2] !== "profile" ||
      !isValidOpaqueUid(segments[1])) {
    return null;
  }
  // Timestamp suffixes are the historical client contract. The 32-hex
  // suffix is the reservation-bound contract used for every new upload.
  const match = /^(avatar|banner)_([a-f0-9]{32}|[0-9]{1,20})[.](jpg|jpeg|png|webp)$/u
    .exec(segments[3]);
  if (!match) return null;
  const extension = match[3] === "jpeg" ? "jpg" : match[3];
  const contentType = extension === "jpg"
    ? "image/jpeg"
    : `image/${extension}`;
  return {
    ownerId: segments[1],
    kind: match[1],
    uploadId: match[2],
    contentType,
    path: value,
  };
}

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return isPlainObject(custom) ? custom : {};
}

function canonicalProfileMediaDescriptor(value, {
  ownerId,
  kind,
  allowNull = true,
} = {}) {
  if (value === null || value === undefined) {
    if (allowNull) return null;
    fail("data-loss", `The canonical ${kind} media record is missing.`);
  }
  if (!hasExactKeys(value, [
    "contentType",
    "generation",
    "size",
    "storagePath",
  ])) {
    fail("data-loss", `The canonical ${kind} media record is malformed.`);
  }
  const parsed = parseProfileMediaStoragePath(value.storagePath);
  if (!parsed || parsed.ownerId !== ownerId || parsed.kind !== kind ||
      !PROFILE_MEDIA_GENERATION.test(value.generation) ||
      parsed.contentType !== value.contentType ||
      !PROFILE_MEDIA_TYPES.includes(value.contentType) ||
      !Number.isSafeInteger(value.size) ||
      value.size < MIN_PROFILE_MEDIA_BYTES ||
      value.size > MAX_PROFILE_MEDIA_BYTES) {
    fail("data-loss", `The canonical ${kind} media record is malformed.`);
  }
  return {
    storagePath: value.storagePath,
    generation: value.generation,
    contentType: value.contentType,
    size: value.size,
  };
}

function canonicalProfileMediaDocument(snapshot, ownerId) {
  if (!snapshot?.exists) {
    return {
      uid: ownerId,
      schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
      revision: 0,
      avatar: null,
      banner: null,
      updatedAt: null,
    };
  }
  const data = snapshot.data() ?? {};
  if (!hasExactKeys(data, [
    "avatar",
    "banner",
    "revision",
    "schemaVersion",
    "uid",
    "updatedAt",
  ]) ||
      data.uid !== ownerId ||
      data.schemaVersion !== PROFILE_MEDIA_SCHEMA_VERSION ||
      !Number.isSafeInteger(data.revision) ||
      data.revision < 1 ||
      timestampMillis(data.updatedAt) === null) {
    fail("data-loss", "The canonical profile-media record is malformed.");
  }
  return {
    uid: ownerId,
    schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
    revision: data.revision,
    avatar: canonicalProfileMediaDescriptor(data.avatar, {
      ownerId,
      kind: "avatar",
    }),
    banner: canonicalProfileMediaDescriptor(data.banner, {
      ownerId,
      kind: "banner",
    }),
    updatedAt: data.updatedAt,
  };
}

function validateStoredProfileMedia(metadata, {
  ownerId,
  kind,
  storagePath,
  requestedGeneration = null,
  allowLegacyMetadata = false,
} = {}) {
  const parsed = parseProfileMediaStoragePath(storagePath);
  const generation = String(metadata?.generation ?? "");
  const size = Number(metadata?.size);
  if (!parsed || parsed.ownerId !== ownerId || parsed.kind !== kind ||
      !PROFILE_MEDIA_GENERATION.test(generation) ||
      (requestedGeneration !== null &&
        String(requestedGeneration) !== generation) ||
      metadata?.contentType !== parsed.contentType ||
      !PROFILE_MEDIA_TYPES.includes(metadata?.contentType) ||
      !Number.isSafeInteger(size) ||
      size < MIN_PROFILE_MEDIA_BYTES ||
      size > MAX_PROFILE_MEDIA_BYTES) {
    fail("failed-precondition", "The uploaded profile image is invalid.");
  }
  const custom = customMetadataOf(metadata);
  const allowed = new Set([
    "firebaseStorageDownloadTokens",
    "ownerId",
    "profileKind",
    "uploadId",
  ]);
  if (Object.keys(custom).some((key) => !allowed.has(key))) {
    fail("failed-precondition", "The profile image metadata is not canonical.");
  }
  if (!allowLegacyMetadata &&
      (custom.ownerId !== ownerId ||
        custom.profileKind !== kind ||
        custom.uploadId !== parsed.uploadId)) {
    fail("failed-precondition", "The profile image identity is invalid.");
  }
  if (allowLegacyMetadata &&
      ((custom.ownerId !== undefined && custom.ownerId !== ownerId) ||
        (custom.profileKind !== undefined && custom.profileKind !== kind) ||
        (custom.uploadId !== undefined && custom.uploadId !== parsed.uploadId))) {
    fail("failed-precondition", "The legacy profile image identity conflicts.");
  }
  return {
    storagePath,
    generation,
    contentType: metadata.contentType,
    size,
    uploadId: parsed.uploadId,
  };
}

function parseManagedProfileDownloadUrl(value, {
  bucketName = null,
  ownerId = null,
  kind = null,
} = {}) {
  if (typeof value !== "string" || value.length > 4096) return null;
  let uri;
  try {
    uri = new URL(value);
  } catch (_) {
    return null;
  }
  if (uri.protocol !== "https:" ||
      uri.hostname !== "firebasestorage.googleapis.com" ||
      uri.port !== "" ||
      uri.username !== "" ||
      uri.password !== "") {
    return null;
  }
  const segments = uri.pathname.split("/").filter(Boolean);
  if (segments.length !== 5 || segments[0] !== "v0" ||
      segments[1] !== "b" || segments[3] !== "o" ||
      (bucketName !== null && segments[2] !== bucketName)) {
    return null;
  }
  let path;
  try {
    path = decodeURIComponent(segments[4]);
  } catch (_) {
    return null;
  }
  const parsed = parseProfileMediaStoragePath(path);
  if (!parsed ||
      (ownerId !== null && parsed.ownerId !== ownerId) ||
      (kind !== null && parsed.kind !== kind)) {
    return null;
  }
  return { bucket: segments[2], ...parsed };
}

function exactFriendshipGuard(snapshot, ownerId, friendId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  return hasExactKeys(data, [
    "establishedAt",
    "friendId",
    "ownerId",
    "schemaVersion",
  ]) &&
    data.ownerId === ownerId &&
    data.friendId === friendId &&
    data.schemaVersion === 1 &&
    timestampMillis(data.establishedAt) !== null;
}

function activeProfileData(snapshot, label = "The") {
  if (!snapshot?.exists) fail("not-found", `${label} profile does not exist.`);
  const data = snapshot.data() ?? {};
  if (data.banned === true || data.disabled === true || data.deleted === true ||
      data.status === "deleted" || data.authDeletedAt != null) {
    fail("permission-denied", `${label} account is not active.`);
  }
  return data;
}

function profileVisibilityOf(data) {
  const value = data?.profileVisibility;
  if (value === undefined || value === null || value === "") return "public";
  return ["public", "friends", "private"].includes(value)
    ? value
    : "private";
}

module.exports = {
  MAX_PROFILE_MEDIA_BYTES,
  MIN_PROFILE_MEDIA_BYTES,
  PROFILE_MEDIA_ACCESS_TTL_MS,
  PROFILE_MEDIA_KINDS,
  PROFILE_MEDIA_NEGATIVE_TTL_MS,
  PROFILE_MEDIA_SCHEMA_VERSION,
  PROFILE_MEDIA_TYPES,
  PROFILE_MEDIA_UPLOAD_TTL_MS,
  activeProfileData,
  canonicalProfileMediaDescriptor,
  canonicalProfileMediaDocument,
  customMetadataOf,
  exactFriendshipGuard,
  hasExactKeys,
  parseManagedProfileDownloadUrl,
  parseProfileMediaStoragePath,
  profileMediaStoragePath,
  profileVisibilityOf,
  requireProfileMediaContentType,
  requireProfileMediaKind,
  requireProfileMediaSize,
  requireProfileMediaUploadId,
  validateStoredProfileMedia,
};

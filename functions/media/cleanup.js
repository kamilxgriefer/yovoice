// Server-side lifecycle cleanup for media whose client delete is deliberately
// denied or ownership-scoped by storage.rules.
//
// This module intentionally registers no Cloud Function. Call it from the
// authoritative Room/Club/Voice Moment deletion workflow *before* deleting
// the Firestore documents that carry the binding data. functions/index.js is
// left untouched so the release owner can wire each hook atomically.

const FIREBASE_STORAGE_DOWNLOAD_HOST = "firebasestorage.googleapis.com";
const MAX_REFERENCE_LENGTH = 4096;
const MAX_EXACT_DELETES = 1000;

function safeSegment(value) {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= 1500 &&
    value !== "." &&
    value !== ".." &&
    !value.includes("/") &&
    !/[\\\u0000-\u001f\u007f]/u.test(value);
}

function canonicalObjectPath(encodedPath) {
  let objectPath;
  try {
    objectPath = decodeURIComponent(encodedPath);
  } catch (_) {
    return null;
  }
  if (
    !objectPath ||
    objectPath.startsWith("/") ||
    objectPath.endsWith("/") ||
    Buffer.byteLength(objectPath, "utf8") > 2048 ||
    /[\\\u0000-\u001f\u007f]/u.test(objectPath) ||
    /%[0-9a-f]{2}/iu.test(objectPath)
  ) {
    return null;
  }
  const segments = objectPath.split("/");
  return segments.some((segment) => !safeSegment(segment)) ? null : objectPath;
}

// Accept only canonical references to the configured bucket. Firestore media
// URLs are client-writable on some legacy rows, so a URL is never itself
// authority for an Admin SDK delete.
function parseStorageObjectReference(value, expectedBucketName) {
  const reference = typeof value === "string" ? value.trim() : "";
  if (
    !reference ||
    reference.length > MAX_REFERENCE_LENGTH ||
    !safeSegment(expectedBucketName) ||
    /%2e/iu.test(reference) ||
    /(?:^|\/)\.\.?(?:\/|$)/u.test(reference)
  ) {
    return null;
  }

  let parsed;
  try {
    parsed = new URL(reference);
  } catch (_) {
    return null;
  }
  if (parsed.username || parsed.password || parsed.hash) return null;

  if (parsed.protocol === "gs:") {
    if (parsed.hostname !== expectedBucketName || parsed.search) return null;
    return canonicalObjectPath(parsed.pathname.slice(1));
  }

  if (
    parsed.protocol !== "https:" ||
    parsed.hostname !== FIREBASE_STORAGE_DOWNLOAD_HOST
  ) {
    return null;
  }
  const segments = parsed.pathname.split("/");
  if (
    segments.length !== 6 ||
    segments[1] !== "v0" ||
    segments[2] !== "b" ||
    segments[3] !== expectedBucketName ||
    segments[4] !== "o"
  ) {
    return null;
  }
  return canonicalObjectPath(segments[5]);
}

function clubMediaPaths({ clubId, club, bucketName }) {
  if (!safeSegment(clubId) || !club || typeof club !== "object") return [];
  const paths = [];
  // `imageUrl` is the legacy avatar field still present on older Club rows;
  // `avatarUrl` is canonical for new Clubs. The validated object path below,
  // never the URL field name, remains the deletion authority.
  for (const reference of [club.avatarUrl, club.imageUrl, club.bannerUrl]) {
    const objectPath = parseStorageObjectReference(reference, bucketName);
    if (!objectPath) continue;
    const segments = objectPath.split("/");
    if (
      segments.length === 4 &&
      segments[0] === "clubs" &&
      safeSegment(segments[1]) &&
      segments[2] === clubId &&
      ["avatar", "banner"].includes(segments[3])
    ) {
      paths.push(objectPath);
    }
  }
  return [...new Set(paths)];
}

function voiceMomentMediaPaths({ momentId, moment, comments = [] }) {
  if (!safeSegment(momentId) || !moment || typeof moment !== "object") return [];
  const paths = [];
  const authorId = moment.authorId;
  const expectedMain = safeSegment(authorId)
    ? `voice_moments/${authorId}/${momentId}.m4a`
    : null;
  if (expectedMain && moment.storagePath === expectedMain) paths.push(expectedMain);

  for (const entry of comments.slice(0, MAX_EXACT_DELETES)) {
    const data = entry?.data && typeof entry.data === "object"
      ? entry.data
      : entry;
    const commentId = entry?.id ?? data?.id;
    const replyAuthorId = data?.authorId;
    if (!safeSegment(commentId) || !safeSegment(replyAuthorId)) continue;
    const expectedReply =
      `voice_replies/${replyAuthorId}/${momentId}/${commentId}.m4a`;
    if (data?.storagePath === expectedReply) paths.push(expectedReply);
  }
  return [...new Set(paths)].slice(0, MAX_EXACT_DELETES);
}

async function deleteExactPaths(paths, bucket) {
  if (!bucket || typeof bucket.file !== "function") {
    throw new TypeError("A Storage bucket is required.");
  }
  const uniquePaths = [...new Set(paths)]
    .filter((objectPath) => canonicalObjectPath(objectPath) === objectPath)
    .slice(0, MAX_EXACT_DELETES);
  const results = [];
  for (const objectPath of uniquePaths) {
    try {
      await bucket.file(objectPath).delete({ ignoreNotFound: true });
      results.push({ objectPath, deleted: true });
    } catch (error) {
      results.push({
        objectPath,
        deleted: false,
        reason: typeof error?.code === "string" ? error.code : "error",
      });
    }
  }
  return results;
}

async function deleteTrustedPrefix(prefix, bucket) {
  if (
    !bucket ||
    typeof bucket.deleteFiles !== "function" ||
    canonicalObjectPath(`${prefix}placeholder`) !== `${prefix}placeholder`
  ) {
    throw new TypeError("A canonical prefix and Storage bucket are required.");
  }
  try {
    await bucket.deleteFiles({ prefix, force: true });
    return { prefix, deleted: true };
  } catch (error) {
    return {
      prefix,
      deleted: false,
      reason: typeof error?.code === "string" ? error.code : "error",
    };
  }
}

async function cleanupRoomMedia({ roomId, bucket }) {
  if (!safeSegment(roomId)) throw new TypeError("Invalid roomId.");
  return deleteTrustedPrefix(`room_images/${roomId}/`, bucket);
}

async function cleanupFamilyMedia({ clubId, bucket }) {
  if (!safeSegment(clubId)) throw new TypeError("Invalid clubId.");
  return deleteTrustedPrefix(`family_moments/${clubId}/`, bucket);
}

async function cleanupClubMedia({ clubId, club, bucket }) {
  const paths = clubMediaPaths({
    clubId,
    club,
    bucketName: bucket?.name,
  });
  return deleteExactPaths(paths, bucket);
}

async function cleanupVoiceMomentMedia({ momentId, moment, comments, bucket }) {
  const paths = voiceMomentMediaPaths({ momentId, moment, comments });
  return deleteExactPaths(paths, bucket);
}

module.exports = {
  canonicalObjectPath,
  parseStorageObjectReference,
  clubMediaPaths,
  voiceMomentMediaPaths,
  deleteExactPaths,
  cleanupRoomMedia,
  cleanupFamilyMedia,
  cleanupClubMedia,
  cleanupVoiceMomentMedia,
};

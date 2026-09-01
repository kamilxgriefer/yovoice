const {
  fail,
  isValidOpaqueUid,
  requireId,
  requireSafeInteger,
} = require("../integrity/guards");
const {
  canonicalRoomCoverPath,
  customMetadataOf,
  parseManagedRoomCoverUrl,
  validateStoredRoomCover,
} = require("./covers");

const DEFAULT_PAGE_SIZE = 200;
const MAX_OBJECTS_PER_ROOM = 10_000;

function tokenPresent(metadata) {
  const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
  return typeof token === "string" && token.length > 0;
}

function isMissingObject(error) {
  return (
    error?.code === 404 ||
    error?.code === "404" ||
    error?.code === "storage/object-not-found" ||
    /(?:no such object|not found|missing fake object)/iu.test(
      String(error?.message ?? ""),
    )
  );
}

function roomState(snapshot) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  return {
    hostId: data.hostId,
    imageUrl: data.imageUrl ?? null,
    coverStoragePath: data.coverStoragePath ?? null,
    coverGeneration: data.coverGeneration ?? null,
    coverContentType: data.coverContentType ?? null,
    coverSize: data.coverSize ?? null,
    visibility: data.visibility,
  };
}

function sameRoomState(left, right) {
  return (
    left !== null &&
    right !== null &&
    left.hostId === right.hostId &&
    left.imageUrl === right.imageUrl &&
    left.coverStoragePath === right.coverStoragePath &&
    left.coverGeneration === right.coverGeneration &&
    left.coverContentType === right.coverContentType &&
    left.coverSize === right.coverSize &&
    left.visibility === right.visibility
  );
}

function roomIdFromObjectPath(path) {
  if (typeof path !== "string") return null;
  const segments = path.split("/");
  if (
    segments.length !== 3 ||
    segments[0] !== "room_images" ||
    !isValidOpaqueUid(segments[1]) ||
    segments[2].length === 0
  ) {
    return null;
  }
  return segments[1];
}

function createRoomCoverMigrationService({
  db,
  FieldPath,
  Timestamp,
  storage,
  clock = () => Date.now(),
}) {
  if (
    !db ||
    !FieldPath?.documentId ||
    !Timestamp?.fromMillis ||
    !storage?.getMetadata ||
    !storage?.listObjects ||
    !storage?.revokeDownloadTokens ||
    !storage?.hardenRoomCoverMetadata
  ) {
    throw new TypeError(
      "db, FieldPath, Timestamp and room-cover storage are required.",
    );
  }

  function now() {
    const value = clock();
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return Timestamp.fromMillis(value);
  }

  async function listAll(prefix, { maxObjects = MAX_OBJECTS_PER_ROOM } = {}) {
    const names = [];
    let pageToken = null;
    do {
      const page = await storage.listObjects({
        prefix,
        pageToken,
        maxResults: Math.min(DEFAULT_PAGE_SIZE, maxObjects - names.length),
      });
      if (
        !page ||
        !Array.isArray(page.names) ||
        page.names.some((name) => typeof name !== "string") ||
        (page.nextPageToken !== null &&
          typeof page.nextPageToken !== "string")
      ) {
        fail("data-loss", "The room-cover inventory response is malformed.");
      }
      names.push(...page.names);
      if (names.length > maxObjects) {
        fail("resource-exhausted", "The room cover inventory is too large.");
      }
      pageToken = page.nextPageToken;
      if (pageToken !== null && names.length === maxObjects) {
        fail("resource-exhausted", "The room cover inventory is too large.");
      }
    } while (pageToken !== null);
    return names;
  }

  // Token revocation deliberately precedes every shape/conflict decision.
  // A corrupt or conflicting room pointer must never be the reason a durable
  // bearer capability survives the migration.
  async function sweepTokens(names, { dryRun }) {
    const rows = [];
    for (const path of names) {
      let metadata;
      try {
        metadata = await storage.getMetadata(path);
      } catch (error) {
        if (!isMissingObject(error)) throw error;
        rows.push({ path, missing: true, tokenPresent: false });
        continue;
      }
      const hadToken = tokenPresent(metadata);
      if (!dryRun && hadToken) {
        await storage.revokeDownloadTokens(path, metadata);
      }
      rows.push({ path, metadata, missing: false, tokenPresent: hadToken });
    }
    return rows;
  }

  function referencedPath(state, roomId) {
    if (typeof state?.coverStoragePath === "string") {
      return state.coverStoragePath;
    }
    return parseManagedRoomCoverUrl(state?.imageUrl, {
      roomId,
      bucketName: storage.bucketName ?? null,
    })?.path ?? null;
  }

  async function migrateRoomCover({
    roomId,
    dryRun,
    maxObjects = MAX_OBJECTS_PER_ROOM,
  }) {
    requireId(roomId, "roomId");
    if (typeof dryRun !== "boolean") {
      fail("invalid-argument", "dryRun must be a boolean.");
    }
    requireSafeInteger(maxObjects, "maxObjects", {
      min: 1,
      max: MAX_OBJECTS_PER_ROOM,
    });
    const roomRef = db.doc(`rooms/${roomId}`);
    const initialSnapshot = await roomRef.get();
    const initial = roomState(initialSnapshot);
    const names = await listAll(`room_images/${roomId}/`, { maxObjects });
    const swept = await sweepTokens(names, { dryRun });
    const revokedTokens = swept.filter((row) => row.tokenPresent).length;

    if (initial === null) {
      return {
        roomId,
        dryRun,
        status: "orphan-room",
        objectsScanned: swept.length,
        tokensRevoked: dryRun ? 0 : revokedTokens,
        tokensFound: revokedTokens,
      };
    }

    const path = referencedPath(initial, roomId);
    let status = "no-cover";
    let canonical = null;
    if (
      path !== null &&
      isValidOpaqueUid(initial.hostId) &&
      canonicalRoomCoverPath(path, { roomId, hostId: initial.hostId })
    ) {
      const row = swept.find((candidate) => candidate.path === path);
      if (row && !row.missing) {
        try {
          const media = validateStoredRoomCover(row.metadata, {
            roomId,
            hostId: initial.hostId,
            requestedGeneration: initial.coverGeneration,
            allowLegacyMetadata: true,
          });
          canonical = {
            path,
            generation: media.generation,
            contentType: media.contentType,
            size: media.size,
          };
          status = "canonicalizable";
        } catch (_) {
          status = "invalid-referenced-object";
        }
      } else {
        status = "missing-referenced-object";
      }
    } else if (path !== null) {
      status = "conflicting-pointer";
    }

    if (!dryRun) {
      if (canonical !== null) {
        const row = swept.find((candidate) => candidate.path === canonical.path);
        await storage.hardenRoomCoverMetadata(canonical.path, row.metadata, {
          ownerId: initial.hostId,
          roomId,
        });
      }
      await db.runTransaction(async (transaction) => {
        const currentSnapshot = await transaction.get(roomRef);
        const current = roomState(currentSnapshot);
        if (!sameRoomState(current, initial)) {
          fail("aborted", "The room changed during cover migration.");
        }
        const update = {
          // Removing this URL is the fail-closed boundary. It happens even
          // for a malformed/conflicting private pointer because the complete
          // prefix token sweep above has already run independently.
          ...(initial.visibility === "private" || path !== null
            ? { imageUrl: null }
            : {}),
          updatedAt: now(),
        };
        if (canonical !== null) {
          update.coverStoragePath = canonical.path;
          update.coverGeneration = canonical.generation;
          update.coverContentType = canonical.contentType;
          update.coverSize = canonical.size;
        }
        transaction.update(roomRef, update);
      });
    }

    return {
      roomId,
      dryRun,
      status,
      canonicalized: canonical !== null,
      objectsScanned: swept.length,
      tokensFound: revokedTokens,
      tokensRevoked: dryRun ? 0 : revokedTokens,
    };
  }

  async function scanRoomCoverMigration({ cursor = null, limit = 25 }) {
    requireSafeInteger(limit, "limit", { min: 1, max: 100 });
    if (cursor !== null) requireId(cursor, "cursor");
    let query = db
      .collection("rooms")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor !== null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    const rooms = snapshot.docs.map((document) => {
      const state = roomState(document);
      const path = referencedPath(state, document.id);
      const canonical =
        path !== null &&
        isValidOpaqueUid(state?.hostId) &&
        canonicalRoomCoverPath(path, {
          roomId: document.id,
          hostId: state.hostId,
        });
      return {
        roomId: document.id,
        visibility: state?.visibility ?? null,
        hasCoverPointer: path !== null,
        canonicalPointer: canonical,
        needsMigration:
          path !== null &&
          (state.imageUrl !== null || !canonical),
      };
    });
    return {
      rooms,
      hasMore: snapshot.size === limit,
      nextCursor: snapshot.size === 0 ? null : snapshot.docs.at(-1).id,
    };
  }

  async function scanRoomCoverObjectInventory({
    pageToken = null,
    maxResults = DEFAULT_PAGE_SIZE,
    dryRun = true,
  }) {
    requireSafeInteger(maxResults, "maxResults", { min: 1, max: 1000 });
    if (
      pageToken !== null &&
      (typeof pageToken !== "string" || pageToken.length > 4096)
    ) {
      fail("invalid-argument", "pageToken is invalid.");
    }
    if (typeof dryRun !== "boolean") {
      fail("invalid-argument", "dryRun must be a boolean.");
    }
    const page = await storage.listObjects({
      prefix: "room_images/",
      pageToken,
      maxResults,
    });
    const entries = [];
    for (const path of page.names) {
      let metadata = null;
      try {
        metadata = await storage.getMetadata(path);
      } catch (error) {
        if (!isMissingObject(error)) throw error;
        // An object deleted during inventory is reported as missing; a later
        // page/run converges without treating deletion as an orphan write.
      }
      const roomId = roomIdFromObjectPath(path);
      const room = roomId === null
        ? null
        : roomState(await db.doc(`rooms/${roomId}`).get());
      const referenced =
        roomId !== null && referencedPath(room, roomId) === path;
      const hadToken = metadata !== null && tokenPresent(metadata);
      if (!dryRun && hadToken) {
        await storage.revokeDownloadTokens(path, metadata);
      }
      entries.push({
        path,
        roomId,
        roomExists: room !== null,
        referenced,
        orphan: room === null || !referenced,
        missing: metadata === null,
        tokenPresent: hadToken,
      });
    }
    return {
      dryRun,
      entries,
      nextPageToken: page.nextPageToken,
      hasMore: page.nextPageToken !== null,
      tokensFound: entries.filter((entry) => entry.tokenPresent).length,
      tokensRevoked: dryRun
        ? 0
        : entries.filter((entry) => entry.tokenPresent).length,
    };
  }

  return Object.freeze({
    migrateRoomCover,
    scanRoomCoverMigration,
    scanRoomCoverObjectInventory,
  });
}

module.exports = {
  DEFAULT_PAGE_SIZE,
  MAX_OBJECTS_PER_ROOM,
  createRoomCoverMigrationService,
  roomIdFromObjectPath,
  tokenPresent,
};

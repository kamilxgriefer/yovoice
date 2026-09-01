const { fail } = require("../integrity/guards");
const {
  canonicalProfileMediaDocument,
  parseProfileMediaStoragePath,
} = require("./media_contract");
const { canonicalLease } = require("./media");

const ORPHAN_SWEEP_STATE_PATH = "profileMediaMaintenance/orphanSweep";

function validPageToken(value) {
  return (
    value === null ||
    (typeof value === "string" && value.length > 0 && value.length <= 4096)
  );
}

function invalidPageTokenError(error) {
  const code = String(error?.code ?? "").toLowerCase();
  const message = String(error?.message ?? "").toLowerCase();
  return (
    code.includes("invalid") ||
    (message.includes("page") && message.includes("token"))
  );
}

function createProfileMediaCleanupService({
  db,
  storage,
  migration,
  clock = () => Date.now(),
}) {
  if (
    !db ||
    !storage?.deleteObject ||
    !migration?.inventoryProfileMediaObjects ||
    !migration?.isProfileMediaObjectReferenced
  ) {
    throw new TypeError(
      "db, storage and profile-media migration services are required.",
    );
  }

  function nowMs() {
    const value = clock();
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return value;
  }

  async function cleanupExpiredLease(snapshot, timing) {
    return db.runTransaction(async (transaction) => {
      const live = await transaction.get(snapshot.ref);
      if (!live.exists) return null;
      const data = live.data() ?? {};
      const ownerId = data.ownerId;
      const kind = data.kind;
      if (typeof ownerId !== "string" || !["avatar", "banner"].includes(kind)) {
        fail("data-loss", "A profile upload lease is malformed.");
      }
      const lease = canonicalLease(live, { ownerId, kind });
      if (lease.expiresAt.toMillis() > timing) return null;
      const mediaRef = db.doc(`profileMedia/${ownerId}`);
      const media = await transaction.get(mediaRef);
      const canonical = canonicalProfileMediaDocument(media, ownerId);
      const isPublished = canonical[kind]?.storagePath === lease.storagePath;
      transaction.delete(db.doc(lease.reservationPath));
      transaction.delete(live.ref);
      return isPublished ? null : lease.storagePath;
    });
  }

  async function sweep({ cursor = null, limit = 100 } = {}) {
    if (
      (cursor !== null &&
        (typeof cursor !== "string" || cursor.length > 4096)) ||
      !Number.isSafeInteger(limit) ||
      limit < 1 ||
      limit > 200
    ) {
      fail("invalid-argument", "The profile-media sweep input is invalid.");
    }
    const timing = nowMs();
    const expired = await db
      .collection("profileMediaUploadLeases")
      .where("expiresAt", "<=", new Date(timing))
      .limit(limit)
      .get();
    let expiredObjectsDeleted = 0;
    for (const lease of expired.docs) {
      const path = await cleanupExpiredLease(lease, timing);
      if (path !== null) {
        await storage.deleteObject(path, { ignoreNotFound: true });
        expiredObjectsDeleted += 1;
      }
    }

    const inventory = await migration.inventoryProfileMediaObjects({
      cursor,
      limit,
      revokeTokens: true,
    });
    let orphanObjectsDeleted = 0;
    for (const object of inventory.objects) {
      if (
        !object.orphan ||
        object.missing ||
        parseProfileMediaStoragePath(object.path) === null
      ) {
        continue;
      }
      // Recheck immediately before deletion; inventory may have taken long
      // enough for a reservation or migration to publish this exact object.
      if (await migration.isProfileMediaObjectReferenced(object.path)) {
        continue;
      }
      await storage.deleteObject(object.path, { ignoreNotFound: true });
      orphanObjectsDeleted += 1;
    }
    return {
      expiredLeasesDeleted: expired.size,
      expiredObjectsDeleted,
      orphanObjectsDeleted,
      nextCursor: inventory.nextCursor,
      hasMore: inventory.hasMore,
    };
  }

  async function scheduledSweep({ limit = 200 } = {}) {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 200) {
      fail("invalid-argument", "The profile-media sweep limit is invalid.");
    }
    const stateRef = db.doc(ORPHAN_SWEEP_STATE_PATH);
    const state = await stateRef.get();
    const storedCursor = state.exists ? (state.data()?.cursor ?? null) : null;
    if (!validPageToken(storedCursor)) {
      await stateRef.set({
        schemaVersion: 1,
        cursor: null,
        resetReason: "invalid-state",
        updatedAt: new Date(nowMs()),
      });
      return { outcome: "cursor-reset", reason: "invalid-state" };
    }

    let result;
    try {
      result = await sweep({ cursor: storedCursor, limit });
    } catch (error) {
      if (!invalidPageTokenError(error)) throw error;
      await stateRef.set({
        schemaVersion: 1,
        cursor: null,
        resetReason: "provider-rejected-token",
        updatedAt: new Date(nowMs()),
      });
      return { outcome: "cursor-reset", reason: "provider-rejected-token" };
    }

    const nextCursor = result.hasMore ? result.nextCursor : null;
    if (
      !validPageToken(nextCursor) ||
      (result.hasMore && nextCursor === null)
    ) {
      fail(
        "data-loss",
        "Storage returned an invalid profile-media page token.",
      );
    }
    await stateRef.set({
      schemaVersion: 1,
      cursor: nextCursor,
      resetReason: null,
      updatedAt: new Date(nowMs()),
    });
    return {
      ...result,
      outcome: result.hasMore ? "advanced" : "wrapped",
    };
  }

  return Object.freeze({ scheduledSweep, sweep });
}

module.exports = {
  ORPHAN_SWEEP_STATE_PATH,
  createProfileMediaCleanupService,
  invalidPageTokenError,
  validPageToken,
};

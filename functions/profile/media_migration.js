const { fail, isValidOpaqueUid } = require("../integrity/guards");
const {
  PROFILE_MEDIA_SCHEMA_VERSION,
  canonicalProfileMediaDocument,
  customMetadataOf,
  parseManagedProfileDownloadUrl,
  parseProfileMediaStoragePath,
  validateStoredProfileMedia,
} = require("./media_contract");
const { canonicalLease, leaseReference } = require("./media");

function missingObject(error) {
  return error?.code === 404 || error?.code === "404" ||
    error?.code === "storage/object-not-found" ||
    /(?:no such object|not found|missing fake object)/iu.test(
      String(error?.message ?? ""),
    );
}

function managedSourcePath(value, {
  bucketName,
  ownerId,
  kind,
}) {
  return parseManagedProfileDownloadUrl(value, {
    bucketName,
    ownerId,
    kind,
  })?.path ?? null;
}

function referencedPaths({ user, publicProfile, media, bucketName, ownerId }) {
  const paths = new Set();
  for (const [kind, field] of [
    ["avatar", "photoUrl"],
    ["banner", "bannerUrl"],
  ]) {
    for (const source of [user, publicProfile]) {
      const path = managedSourcePath(source?.[field], {
        bucketName,
        ownerId,
        kind,
      });
      if (path) paths.add(path);
    }
    const descriptor = media?.[kind];
    if (descriptor?.storagePath) paths.add(descriptor.storagePath);
  }
  return paths;
}

function valueSignature(value) {
  return typeof value === "string" ? value : null;
}

function sourceSignature(user, publicProfile, media) {
  return JSON.stringify({
    userPhoto: valueSignature(user?.photoUrl),
    userBanner: valueSignature(user?.bannerUrl),
    publicPhoto: valueSignature(publicProfile?.photoUrl),
    publicBanner: valueSignature(publicProfile?.bannerUrl),
    mediaRevision: media?.revision ?? 0,
    mediaAvatar: media?.avatar?.storagePath ?? null,
    mediaAvatarGeneration: media?.avatar?.generation ?? null,
    mediaBanner: media?.banner?.storagePath ?? null,
    mediaBannerGeneration: media?.banner?.generation ?? null,
  });
}

function createProfileMediaMigrationService({
  db,
  Timestamp,
  FieldPath,
  storage,
  clock = () => Date.now(),
}) {
  if (!db || !Timestamp?.fromMillis || !FieldPath?.documentId ||
      !storage?.getMetadata || !storage?.listObjects ||
      !storage?.hardenManagedImageMetadata ||
      !storage?.revokeDownloadTokens ||
      typeof storage.bucketName !== "string" || !storage.bucketName) {
    throw new TypeError(
      "db, Timestamp, FieldPath and profile-media storage are required.",
    );
  }

  function time() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  async function profileState(ownerId) {
    const [user, publicProfile, media] = await db.getAll(
      db.doc(`users/${ownerId}`),
      db.doc(`publicProfiles/${ownerId}`),
      db.doc(`profileMedia/${ownerId}`),
    );
    const userData = user.exists ? user.data() ?? {} : {};
    const publicData = publicProfile.exists ? publicProfile.data() ?? {} : {};
    const canonical = canonicalProfileMediaDocument(media, ownerId);
    return {
      user,
      publicProfile,
      media,
      userData,
      publicData,
      canonical,
      signature: sourceSignature(userData, publicData, canonical),
    };
  }

  async function inspectPath(path, { allowLegacyMetadata = true } = {}) {
    const parsed = parseProfileMediaStoragePath(path);
    if (!parsed) return { path, valid: false, missing: false, parsed: null };
    let metadata;
    try {
      metadata = await storage.getMetadata(path);
    } catch (error) {
      if (missingObject(error)) {
        return { path, valid: false, missing: true, parsed, metadata: null };
      }
      throw error;
    }
    try {
      const descriptor = validateStoredProfileMedia(metadata, {
        ownerId: parsed.ownerId,
        kind: parsed.kind,
        storagePath: path,
        allowLegacyMetadata,
      });
      return {
        path,
        valid: true,
        missing: false,
        parsed,
        metadata,
        descriptor,
      };
    } catch (error) {
      return {
        path,
        valid: false,
        missing: false,
        parsed,
        metadata,
        validationError: error,
      };
    }
  }

  async function isProfileMediaObjectReferenced(path) {
    const parsed = parseProfileMediaStoragePath(path);
    if (!parsed) return false;
    const state = await profileState(parsed.ownerId);
    const references = referencedPaths({
      user: state.userData,
      publicProfile: state.publicData,
      media: state.canonical,
      bucketName: storage.bucketName,
      ownerId: parsed.ownerId,
    });
    if (references.has(path)) return true;
    const leaseSnapshot = await leaseReference(
      db,
      parsed.ownerId,
      parsed.kind,
    ).get();
    const lease = canonicalLease(leaseSnapshot, {
      ownerId: parsed.ownerId,
      kind: parsed.kind,
    });
    return lease !== null &&
      lease.storagePath === path &&
      lease.expiresAt.toMillis() > time().nowMs;
  }

  async function revokeAndCanonicalize(item) {
    if (item.missing || item.metadata === null) return false;
    if (item.valid) {
      await storage.hardenManagedImageMetadata(item.path, item.metadata, {
        ownerId: item.parsed.ownerId,
        profileKind: item.parsed.kind,
        uploadId: item.parsed.uploadId,
      });
      return true;
    }
    // Corrupt content metadata must never block revocation of a bearer token.
    // It is intentionally NOT blessed into a canonical profileMedia record.
    await storage.revokeDownloadTokens(item.path, item.metadata);
    return true;
  }

  async function scanProfileMediaMigration({ cursor = null, limit = 25 } = {}) {
    if (cursor !== null && !isValidOpaqueUid(cursor)) {
      fail("invalid-argument", "cursor is invalid.");
    }
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      fail("invalid-argument", "limit must be between 1 and 100.");
    }
    let query = db.collection("users")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor !== null) query = query.startAfter(cursor);
    const users = await query.get();
    const rows = [];
    for (const document of users.docs) {
      const state = await profileState(document.id);
      const paths = referencedPaths({
        user: state.userData,
        publicProfile: state.publicData,
        media: state.canonical,
        bucketName: storage.bucketName,
        ownerId: document.id,
      });
      rows.push({
        userId: document.id,
        referencedObjectCount: paths.size,
        hasCanonicalAvatar: state.canonical.avatar !== null,
        hasCanonicalBanner: state.canonical.banner !== null,
        hasManagedLegacyAvatar:
          managedSourcePath(state.userData.photoUrl, {
            bucketName: storage.bucketName,
            ownerId: document.id,
            kind: "avatar",
          }) !== null ||
          managedSourcePath(state.publicData.photoUrl, {
            bucketName: storage.bucketName,
            ownerId: document.id,
            kind: "avatar",
          }) !== null,
        hasManagedLegacyBanner:
          managedSourcePath(state.userData.bannerUrl, {
            bucketName: storage.bucketName,
            ownerId: document.id,
            kind: "banner",
          }) !== null ||
          managedSourcePath(state.publicData.bannerUrl, {
            bucketName: storage.bucketName,
            ownerId: document.id,
            kind: "banner",
          }) !== null,
      });
    }
    return {
      rows,
      nextCursor: users.empty ? null : users.docs.at(-1).id,
      hasMore: users.size === limit,
    };
  }

  async function migrateProfileMedia({ userId, dryRun }) {
    if (!isValidOpaqueUid(userId) || typeof dryRun !== "boolean") {
      fail("invalid-argument", "A valid userId and dryRun are required.");
    }
    const state = await profileState(userId);
    if (!state.user.exists && !state.publicProfile.exists &&
        !state.media.exists) {
      return { userId, outcome: "absent", dryRun, inspected: 0 };
    }
    const candidates = {
      avatar: [
        state.canonical.avatar?.storagePath ?? null,
        managedSourcePath(state.userData.photoUrl, {
          bucketName: storage.bucketName,
          ownerId: userId,
          kind: "avatar",
        }),
        managedSourcePath(state.publicData.photoUrl, {
          bucketName: storage.bucketName,
          ownerId: userId,
          kind: "avatar",
        }),
      ].filter(Boolean),
      banner: [
        state.canonical.banner?.storagePath ?? null,
        managedSourcePath(state.userData.bannerUrl, {
          bucketName: storage.bucketName,
          ownerId: userId,
          kind: "banner",
        }),
        managedSourcePath(state.publicData.bannerUrl, {
          bucketName: storage.bucketName,
          ownerId: userId,
          kind: "banner",
        }),
      ].filter(Boolean),
    };
    const allPaths = [...new Set([...candidates.avatar, ...candidates.banner])];
    const inspected = [];
    for (const path of allPaths) inspected.push(await inspectPath(path));
    const byPath = new Map(inspected.map((item) => [item.path, item]));
    const selected = {};
    for (const kind of ["avatar", "banner"]) {
      selected[kind] = null;
      for (const path of [...new Set(candidates[kind])]) {
        const item = byPath.get(path);
        if (item?.valid) {
          selected[kind] = {
            storagePath: path,
            generation: item.descriptor.generation,
            contentType: item.descriptor.contentType,
            size: item.descriptor.size,
          };
          break;
        }
      }
    }
    const result = {
      userId,
      dryRun,
      inspected: inspected.length,
      valid: inspected.filter((item) => item.valid).length,
      missing: inspected.filter((item) => item.missing).length,
      malformed: inspected.filter((item) =>
        !item.valid && !item.missing).length,
      conflicts:
        Number(new Set(candidates.avatar).size > 1) +
        Number(new Set(candidates.banner).size > 1),
      canonicalAvatar: selected.avatar !== null,
      canonicalBanner: selected.banner !== null,
      outcome: dryRun ? "planned" : "migrated",
    };
    if (dryRun) return result;

    // Revoke EVERY referenced token before committing a chosen descriptor.
    // A conflicting stale public projection therefore cannot retain a bearer
    // URL merely because the private source won canonical selection.
    for (const item of inspected) await revokeAndCanonicalize(item);

    const timing = time();
    await db.runTransaction(async (transaction) => {
      const userRef = db.doc(`users/${userId}`);
      const publicRef = db.doc(`publicProfiles/${userId}`);
      const mediaRef = db.doc(`profileMedia/${userId}`);
      const [user, publicProfile, media] = await transactionGetAllCompat(
        transaction,
        userRef,
        publicRef,
        mediaRef,
      );
      const userData = user.exists ? user.data() ?? {} : {};
      const publicData = publicProfile.exists ? publicProfile.data() ?? {} : {};
      const current = canonicalProfileMediaDocument(media, userId);
      if (sourceSignature(userData, publicData, current) !== state.signature) {
        fail("aborted", "The profile changed during media migration.");
      }
      const mediaChanged =
        current.avatar?.storagePath !== selected.avatar?.storagePath ||
        current.avatar?.generation !== selected.avatar?.generation ||
        current.banner?.storagePath !== selected.banner?.storagePath ||
        current.banner?.generation !== selected.banner?.generation;
      if (mediaChanged &&
          (selected.avatar !== null || selected.banner !== null || media.exists)) {
        if (current.revision === Number.MAX_SAFE_INTEGER) {
          fail("data-loss", "The profile-media revision cannot advance.");
        }
        transaction.set(mediaRef, {
          schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
          uid: userId,
          revision: current.revision + 1,
          avatar: selected.avatar,
          banner: selected.banner,
          updatedAt: timing.now,
        });
      }
      const userUpdate = {};
      if (managedSourcePath(userData.photoUrl, {
        bucketName: storage.bucketName,
        ownerId: userId,
        kind: "avatar",
      })) userUpdate.photoUrl = null;
      if (managedSourcePath(userData.bannerUrl, {
        bucketName: storage.bucketName,
        ownerId: userId,
        kind: "banner",
      })) userUpdate.bannerUrl = null;
      if (user.exists && Object.keys(userUpdate).length > 0) {
        userUpdate.profileUpdatedAt = timing.now;
        transaction.update(userRef, userUpdate);
      }
      const publicUpdate = {};
      if (managedSourcePath(publicData.photoUrl, {
        bucketName: storage.bucketName,
        ownerId: userId,
        kind: "avatar",
      })) publicUpdate.photoUrl = null;
      if (managedSourcePath(publicData.bannerUrl, {
        bucketName: storage.bucketName,
        ownerId: userId,
        kind: "banner",
      })) publicUpdate.bannerUrl = null;
      if (publicProfile.exists && Object.keys(publicUpdate).length > 0) {
        publicUpdate.updatedAt = timing.now;
        transaction.update(publicRef, publicUpdate);
      }
    });
    return result;
  }

  async function inventoryProfileMediaObjects({
    cursor = null,
    limit = 100,
    revokeTokens = false,
  } = {}) {
    if ((cursor !== null &&
          (typeof cursor !== "string" || cursor.length > 4096)) ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 200 ||
        typeof revokeTokens !== "boolean") {
      fail("invalid-argument", "The profile-media inventory input is invalid.");
    }
    const page = await storage.listObjects("users/", {
      pageToken: cursor,
      maxResults: limit,
    });
    const parsedObjects = page.names
      .map((path) => parseProfileMediaStoragePath(path))
      .filter(Boolean);
    const objects = [];
    for (const parsed of parsedObjects) {
      const item = await inspectPath(parsed.path);
      const referenced = await isProfileMediaObjectReferenced(parsed.path);
      const token = item.metadata === null
        ? null
        : customMetadataOf(item.metadata).firebaseStorageDownloadTokens;
      const hadDurableToken = typeof token === "string" && token.length > 0;
      let tokenRevoked = false;
      if (revokeTokens && item.metadata !== null && hadDurableToken) {
        await revokeAndCanonicalize(item);
        tokenRevoked = true;
      }
      objects.push({
        path: parsed.path,
        ownerId: parsed.ownerId,
        kind: parsed.kind,
        referenced,
        orphan: !referenced,
        valid: item.valid,
        missing: item.missing,
        generation: item.metadata === null
          ? null
          : String(item.metadata.generation ?? ""),
        contentType: item.metadata?.contentType ?? null,
        size: item.metadata === null ? null : Number(item.metadata.size),
        hadDurableToken,
        tokenRevoked,
      });
    }
    return {
      objects,
      nextCursor: page.nextPageToken,
      hasMore: page.nextPageToken !== null,
      inspectedStorageEntries: page.names.length,
      ignoredNonProfileEntries: page.names.length - parsedObjects.length,
      revokeTokens,
    };
  }

  return Object.freeze({
    inventoryProfileMediaObjects,
    isProfileMediaObjectReferenced,
    migrateProfileMedia,
    scanProfileMediaMigration,
  });
}

async function transactionGetAllCompat(transaction, ...references) {
  if (typeof transaction.getAll === "function") {
    return transaction.getAll(...references);
  }
  const snapshots = [];
  for (const reference of references) {
    snapshots.push(await transaction.get(reference));
  }
  return snapshots;
}

module.exports = {
  createProfileMediaMigrationService,
  managedSourcePath,
  missingObject,
  referencedPaths,
  sourceSignature,
};

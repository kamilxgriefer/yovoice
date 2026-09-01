const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  PROFILE_MEDIA_DAILY_BYTE_LIMIT,
  createProfileMediaService,
} = require("../profile/media");
const {
  createProfileMediaMigrationService,
} = require("../profile/media_migration");
const {
  createProfileMediaCleanupService,
} = require("../profile/media_cleanup");
const { rateLimitReference } = require("../integrity/guards");

const db = getFirestore();
const A = "profile-media-alice";
const B = "profile-media-bob";
const C = "profile-media-charlie";
const USERS = [A, B, C];
let nowMs = 1_820_000_000_000;
let storage;

class FakeStorage {
  constructor() {
    this.bucketName = "test-bucket.appspot.com";
    this.objects = new Map();
    this.hardened = [];
    this.revoked = [];
    this.signed = [];
    this.metadataReads = [];
    this.beforeSignedRead = null;
  }

  put(
    path,
    {
      generation = "1001",
      contentType = "image/jpeg",
      size = 4096,
      metadata = {},
      durableToken = "durable-token",
    } = {},
  ) {
    this.objects.set(path, {
      generation,
      contentType,
      size: String(size),
      metadata: {
        ...metadata,
        ...(durableToken
          ? { firebaseStorageDownloadTokens: durableToken }
          : {}),
      },
    });
  }

  async getMetadata(path) {
    this.metadataReads.push(path);
    const metadata = this.objects.get(path);
    if (!metadata) throw new Error(`Missing fake object: ${path}`);
    return metadata;
  }

  async hardenManagedImageMetadata(path, metadata, required) {
    const current = this.objects.get(path);
    if (!current || current.generation !== metadata.generation) {
      throw new Error("generation conflict");
    }
    current.metadata = { ...current.metadata, ...required };
    delete current.metadata.firebaseStorageDownloadTokens;
    this.hardened.push(path);
    return current;
  }

  async revokeDownloadTokens(path) {
    const current = this.objects.get(path);
    if (!current) throw new Error(`Missing fake object: ${path}`);
    delete current.metadata.firebaseStorageDownloadTokens;
    this.revoked.push(path);
    return current;
  }

  async getSignedReadUrl(path, { expiresAtMs, generation }) {
    this.signed.push({ path, expiresAtMs, generation });
    if (this.beforeSignedRead) await this.beforeSignedRead();
    return (
      `https://storage.googleapis.com/${this.bucketName}/` +
      `${encodeURIComponent(path)}?generation=${generation}&sig=test`
    );
  }

  async listObjects(prefix, { pageToken = null, maxResults = 100 } = {}) {
    const names = [...this.objects.keys()]
      .filter((name) => name.startsWith(prefix))
      .sort();
    const start = pageToken === null ? 0 : Number(pageToken);
    const selected = names.slice(start, start + maxResults);
    const next =
      start + selected.length < names.length
        ? String(start + selected.length)
        : null;
    return { names: selected, nextPageToken: next };
  }

  async deleteObject(path, { ignoreNotFound = false } = {}) {
    if (!this.objects.has(path) && !ignoreNotFound) {
      throw new Error(`Missing fake object: ${path}`);
    }
    this.objects.delete(path);
  }
}

function request(uid, data, verified = true) {
  return {
    auth: {
      uid,
      token: { email_verified: verified, email: `${uid}@example.invalid` },
    },
    data,
  };
}

function service() {
  return createProfileMediaService({
    db,
    Timestamp,
    storage,
    clock: () => nowMs,
  });
}

function migration() {
  return createProfileMediaMigrationService({
    db,
    Timestamp,
    FieldPath,
    storage,
    clock: () => nowMs,
  });
}

function cleanup() {
  const migrationService = migration();
  return createProfileMediaCleanupService({
    db,
    storage,
    migration: migrationService,
    clock: () => nowMs,
  });
}

async function deleteTree(path) {
  const ref = db.doc(path);
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(ref);
  } else {
    await ref.delete();
  }
}

async function reset() {
  await deleteTree("profileMediaMaintenance/orphanSweep");
  for (const uid of USERS) {
    await Promise.all([
      deleteTree(`users/${uid}`),
      deleteTree(`publicProfiles/${uid}`),
      deleteTree(`profileMedia/${uid}`),
      deleteTree(`profileMediaUploadReservations/${uid}`),
      deleteTree(`profileMediaFinalizations/${uid}`),
      deleteTree(`profileMediaUploadBudgets/${uid}`),
      deleteTree(`friendshipGuards/${uid}`),
    ]);
  }
  const rates = await db.collection("privateRateLimits").get();
  const leases = await db.collection("profileMediaUploadLeases").get();
  const operationLedgers = await db.collection("integrityOperationLedgers").get();
  const preflightLedgers = await db.collection("integrityPreflightLedgers").get();
  await Promise.all(
    rates.docs
      .filter((doc) => doc.data()?.ownerId?.startsWith("profile-media-"))
      .map((doc) => doc.ref.delete()),
  );
  await Promise.all(
    leases.docs
      .filter((doc) => doc.data()?.ownerId?.startsWith("profile-media-"))
      .map((doc) => doc.ref.delete()),
  );
  await Promise.all(
    [...operationLedgers.docs, ...preflightLedgers.docs]
      .filter((doc) => doc.data()?.ownerId?.startsWith("profile-media-"))
      .map((doc) => doc.ref.delete()),
  );
  await Promise.all(
    USERS.map((uid) =>
      db.doc(`users/${uid}`).set({
        uid,
        displayName: uid,
        profileVisibility: "public",
        banned: false,
        disabled: false,
      }),
    ),
  );
  storage = new FakeStorage();
  nowMs += 100_000;
}

beforeEach(reset);
after(async () => reset());

async function reserveAndPut({
  uid = A,
  kind = "avatar",
  uploadId = "a".repeat(32),
  contentType = "image/jpeg",
  size = 4096,
  generation = "1001",
  verified = true,
} = {}) {
  const reserved = await service().reserveProfileMediaUpload(
    request(uid, { kind, uploadId, contentType, size }, verified),
  );
  storage.put(reserved.storagePath, {
    generation,
    contentType,
    size,
    metadata: { ownerId: uid, profileKind: kind, uploadId },
  });
  return reserved;
}

async function rateCount(scope, uid = A) {
  const snapshot = await rateLimitReference(db, scope, uid).get();
  return snapshot.exists ? snapshot.data().count : 0;
}

test("reserve and finalize require a verified email", async () => {
  await assert.rejects(
    service().reserveProfileMediaUpload(
      request(
        A,
        {
          kind: "avatar",
          uploadId: "a".repeat(32),
          contentType: "image/jpeg",
          size: 4096,
        },
        false,
      ),
    ),
    (error) => error.code === "failed-precondition",
  );
  await reserveAndPut();
  await assert.rejects(
    service().finalizeProfileMediaUpload(
      request(
        A,
        {
          uploadId: "a".repeat(32),
          objectGeneration: "1001",
        },
        false,
      ),
    ),
    (error) => error.code === "failed-precondition",
  );
});

test("only one live upload per owner and kind is admitted", async () => {
  await reserveAndPut({ uploadId: "a".repeat(32) });
  await assert.rejects(
    reserveAndPut({ uploadId: "b".repeat(32) }),
    (error) => error.code === "already-exists",
  );
});

test("an expired lease is atomically replaced and its object is removed", async () => {
  const first = await reserveAndPut({ uploadId: "a".repeat(32) });
  nowMs += 10 * 60_000 + 1;
  const second = await reserveAndPut({
    uploadId: "b".repeat(32),
    generation: "1002",
  });
  assert.notEqual(first.storagePath, second.storagePath);
  assert.equal(storage.objects.has(first.storagePath), false);
  assert.equal(storage.objects.has(second.storagePath), true);
  assert.equal(
    (
      await db
        .doc(`profileMediaUploadReservations/${A}/uploads/${"a".repeat(32)}`)
        .get()
    ).exists,
    false,
  );
});

test("daily byte budget permits N and rejects N plus one", async () => {
  const day = new Date(nowMs).toISOString().slice(0, 10);
  await db.doc(`profileMediaUploadBudgets/${A}/days/${day}`).set({
    schemaVersion: 1,
    ownerId: A,
    day,
    bytesReserved: PROFILE_MEDIA_DAILY_BYTE_LIMIT - 128,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  await reserveAndPut({ size: 128 });
  await assert.rejects(
    reserveAndPut({
      kind: "banner",
      uploadId: "b".repeat(32),
      size: 128,
    }),
    (error) => error.code === "resource-exhausted",
  );
});

test("finalize rejects missing, expired, reused and mismatched objects", async () => {
  await service().reserveProfileMediaUpload(
    request(A, {
      kind: "avatar",
      uploadId: "a".repeat(32),
      contentType: "image/jpeg",
      size: 4096,
    }),
  );
  await assert.rejects(
    service().finalizeProfileMediaUpload(
      request(A, {
        uploadId: "a".repeat(32),
        objectGeneration: "1001",
      }),
    ),
    /Missing fake object/u,
  );
  const reservedPath = `users/${A}/profile/avatar_${"a".repeat(32)}.jpg`;
  storage.put(reservedPath, {
    generation: "1001",
    size: 4097,
    metadata: {
      ownerId: A,
      profileKind: "avatar",
      uploadId: "a".repeat(32),
    },
  });
  await assert.rejects(
    service().finalizeProfileMediaUpload(
      request(A, {
        uploadId: "a".repeat(32),
        objectGeneration: "1001",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  storage.objects.get(reservedPath).size = "4096";
  nowMs += 10 * 60_000 + 1;
  await assert.rejects(
    service().finalizeProfileMediaUpload(
      request(A, {
        uploadId: "a".repeat(32),
        objectGeneration: "1001",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
});

test("reservation-bound upload finalization removes durable URLs and replays", async () => {
  const legacy =
    `https://firebasestorage.googleapis.com/v0/b/` +
    `${storage.bucketName}/o/${encodeURIComponent(
      `users/${A}/profile/avatar_1.jpg`,
    )}?alt=media&token=legacy`;
  await db.doc(`users/${A}`).set({ photoUrl: legacy }, { merge: true });
  await db.doc(`publicProfiles/${A}`).set({
    photoUrl: legacy,
    bannerUrl: null,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  const reserved = await reserveAndPut();
  const handler = service();
  const input = request(A, {
    uploadId: "a".repeat(32),
    objectGeneration: "1001",
  });
  const result = await handler.finalizeProfileMediaUpload(input);
  assert.equal(result.kind, "avatar");
  assert.equal(result.generation, "1001");
  assert.equal(
    storage.objects.get(reserved.storagePath).metadata
      .firebaseStorageDownloadTokens,
    undefined,
  );
  assert.deepEqual(storage.objects.get(reserved.storagePath).metadata, {
    ownerId: A,
    profileKind: "avatar",
    uploadId: "a".repeat(32),
  });
  const media = (await db.doc(`profileMedia/${A}`).get()).data();
  assert.equal(media.avatar.storagePath, reserved.storagePath);
  assert.equal(media.revision, 1);
  assert.equal((await db.doc(`users/${A}`).get()).data().photoUrl, null);
  assert.equal(
    (await db.doc(`publicProfiles/${A}`).get()).data().photoUrl,
    null,
  );
  assert.deepEqual(await handler.finalizeProfileMediaUpload(input), result);
});

test("committed preflights charge denied profile-media work and stop Storage at the cap", async () => {
  await db.doc(`users/${A}`).update({ banned: true });
  await assert.rejects(
    service().reserveProfileMediaUpload(request(A, {
      kind: "avatar",
      uploadId: "c".repeat(32),
      contentType: "image/jpeg",
      size: 4096,
    })),
    (error) => error.code === "permission-denied",
  );
  assert.equal(await rateCount("profileMedia.reserve"), 1);
  await db.doc(`users/${A}`).update({ banned: false });

  await service().reserveProfileMediaUpload(request(A, {
    kind: "avatar",
    uploadId: "d".repeat(32),
    contentType: "image/jpeg",
    size: 4096,
  }));
  const reserveCount = await rateCount("profileMedia.reserve");
  await assert.rejects(
    service().reserveProfileMediaUpload(request(A, {
      kind: "avatar",
      uploadId: "d".repeat(32),
      contentType: "image/jpeg",
      size: 4097,
    })),
    (error) => error.code === "already-exists",
  );
  assert.equal(await rateCount("profileMedia.reserve"), reserveCount + 1);
  const finalizeInput = request(A, {
    uploadId: "d".repeat(32),
    objectGeneration: "404",
  });
  await assert.rejects(
    service().finalizeProfileMediaUpload(finalizeInput),
    /Missing fake object/u,
  );
  await assert.rejects(
    service().finalizeProfileMediaUpload(finalizeInput),
    /Missing fake object/u,
  );
  assert.equal(await rateCount("profileMedia.finalize"), 2);
  assert.equal(storage.metadataReads.length, 2);

  const finalizeRate = rateLimitReference(db, "profileMedia.finalize", A);
  await finalizeRate.set({
    schemaVersion: 1,
    ownerId: A,
    scope: "profileMedia.finalize",
    windowStartedAt: Timestamp.fromMillis(nowMs),
    count: 20,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service().finalizeProfileMediaUpload(finalizeInput),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(storage.metadataReads.length, 2);

  await db.doc(`users/${A}`).update({ profileVisibility: "private" });
  await assert.rejects(
    service().getProfileMediaAccess(
      request(B, { userId: A, kind: "avatar" }),
    ),
    (error) => error.code === "permission-denied",
  );
  assert.equal(await rateCount("profileMedia.access", B), 1);
});

test("a completed profile finalization is a free idempotent replay", async () => {
  await reserveAndPut({ uploadId: "e".repeat(32), generation: "505" });
  const instance = service();
  const input = request(A, {
    uploadId: "e".repeat(32),
    objectGeneration: "505",
  });
  const first = await instance.finalizeProfileMediaUpload(input);
  assert.equal(await rateCount("profileMedia.finalize"), 1);
  const reads = storage.metadataReads.length;
  const replay = await instance.finalizeProfileMediaUpload(input);
  assert.deepEqual(replay, first);
  assert.equal(await rateCount("profileMedia.finalize"), 1);
  assert.equal(storage.metadataReads.length, reads);
});

test("profile visibility, exact bilateral friendship and both blocks gate grants", async () => {
  const reserved = await reserveAndPut({ verified: true });
  await service().finalizeProfileMediaUpload(
    request(A, {
      uploadId: "a".repeat(32),
      objectGeneration: "1001",
    }),
  );
  let result = await service().getProfileMediaAccess(
    request(B, {
      userId: A,
      kind: "avatar",
    }),
  );
  assert.equal(result.available, true);
  assert.equal(storage.signed.at(-1).expiresAtMs - nowMs, 90_000);

  await db
    .doc(`users/${A}`)
    .set({ profileVisibility: "friends" }, { merge: true });
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "permission-denied",
  );
  const establishedAt = Timestamp.fromMillis(nowMs);
  await db.doc(`friendshipGuards/${B}/friends/${A}`).set({
    ownerId: B,
    friendId: A,
    schemaVersion: 1,
    establishedAt,
  });
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`friendshipGuards/${A}/friends/${B}`).set({
    ownerId: A,
    friendId: B,
    schemaVersion: 1,
    establishedAt,
  });
  result = await service().getProfileMediaAccess(
    request(B, {
      userId: A,
      kind: "avatar",
    }),
  );
  assert.equal(result.available, true);

  await db.doc(`users/${B}/blocked/${A}`).set({ blocked: true });
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${B}/blocked/${A}`).delete();
  await db.doc(`users/${A}/blocked/${B}`).set({ blocked: true });
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "failed-precondition",
  );
});

test("private media is self-only and inactive callers or targets fail closed", async () => {
  await reserveAndPut();
  await service().finalizeProfileMediaUpload(
    request(A, {
      uploadId: "a".repeat(32),
      objectGeneration: "1001",
    }),
  );
  await db
    .doc(`users/${A}`)
    .set({ profileVisibility: "private" }, { merge: true });
  assert.equal(
    (
      await service().getProfileMediaAccess(
        request(
          A,
          {
            userId: A,
            kind: "avatar",
          },
          false,
        ),
      )
    ).available,
    true,
  );
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${A}`).set({ disabled: true }, { merge: true });
  await assert.rejects(
    service().getProfileMediaAccess(
      request(A, { userId: A, kind: "avatar" }, false),
    ),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${A}`).set({ disabled: false }, { merge: true });
  await db
    .doc(`users/${B}`)
    .set({ authDeletedAt: Timestamp.fromMillis(nowMs) }, { merge: true });
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "permission-denied",
  );
});

test("authorization is rechecked after URL signing", async () => {
  await reserveAndPut();
  await service().finalizeProfileMediaUpload(
    request(A, {
      uploadId: "a".repeat(32),
      objectGeneration: "1001",
    }),
  );
  storage.beforeSignedRead = async () => {
    await db
      .doc(`users/${A}`)
      .set({ profileVisibility: "private" }, { merge: true });
    storage.beforeSignedRead = null;
  };
  await assert.rejects(
    service().getProfileMediaAccess(request(B, { userId: A, kind: "avatar" })),
    (error) => error.code === "permission-denied",
  );
});

test("concurrent reservations cannot overwrite a newer finalized revision", async () => {
  await reserveAndPut({ uploadId: "a".repeat(32), generation: "1001" });
  await reserveAndPut({
    kind: "banner",
    uploadId: "b".repeat(32),
    generation: "1002",
  });
  await service().finalizeProfileMediaUpload(
    request(A, {
      uploadId: "a".repeat(32),
      objectGeneration: "1001",
    }),
  );
  await assert.rejects(
    service().finalizeProfileMediaUpload(
      request(A, {
        uploadId: "b".repeat(32),
        objectGeneration: "1002",
      }),
    ),
    (error) => error.code === "aborted",
  );
});

test("cleanup removes expired leases and unreferenced upload objects", async () => {
  const expired = await reserveAndPut({ uploadId: "a".repeat(32) });
  const orphan = `users/${A}/profile/banner_${"c".repeat(32)}.png`;
  storage.put(orphan, {
    generation: "1003",
    contentType: "image/png",
    metadata: {
      ownerId: A,
      profileKind: "banner",
      uploadId: "c".repeat(32),
    },
  });
  nowMs += 10 * 60_000 + 1;
  const result = await cleanup().sweep({ limit: 100 });
  assert.equal(result.expiredObjectsDeleted, 1);
  assert.equal(result.orphanObjectsDeleted, 1);
  assert.equal(storage.objects.has(expired.storagePath), false);
  assert.equal(storage.objects.has(orphan), false);
  assert.equal(
    (
      await db
        .doc(`profileMediaUploadReservations/${A}/uploads/${"a".repeat(32)}`)
        .get()
    ).exists,
    false,
  );
});

test("scheduled cleanup persists its cursor and reaches an orphan on page two", async () => {
  const canonical = await reserveAndPut({
    uploadId: "a".repeat(32),
    generation: "1001",
  });
  await service().finalizeProfileMediaUpload(
    request(A, {
      uploadId: "a".repeat(32),
      objectGeneration: "1001",
    }),
  );
  const orphan = `users/${A}/profile/banner_${"b".repeat(32)}.png`;
  storage.put(orphan, {
    generation: "1002",
    contentType: "image/png",
    metadata: {
      ownerId: A,
      profileKind: "banner",
      uploadId: "b".repeat(32),
    },
  });

  const cleaner = cleanup();
  const first = await cleaner.scheduledSweep({ limit: 1 });
  assert.equal(first.outcome, "advanced");
  assert.equal(storage.objects.has(canonical.storagePath), true);
  assert.equal(storage.objects.has(orphan), true);
  assert.equal(
    (await db.doc("profileMediaMaintenance/orphanSweep").get()).data().cursor,
    "1",
  );

  const second = await cleaner.scheduledSweep({ limit: 1 });
  assert.equal(second.outcome, "wrapped");
  assert.equal(second.orphanObjectsDeleted, 1);
  assert.equal(storage.objects.has(canonical.storagePath), true);
  assert.equal(storage.objects.has(orphan), false);
  assert.equal(
    (await db.doc("profileMediaMaintenance/orphanSweep").get()).data().cursor,
    null,
  );
});

test("scheduled cleanup resets malformed cursor state without touching storage", async () => {
  const orphan = `users/${A}/profile/banner_${"c".repeat(32)}.png`;
  storage.put(orphan, {
    contentType: "image/png",
    metadata: {
      ownerId: A,
      profileKind: "banner",
      uploadId: "c".repeat(32),
    },
  });
  await db.doc("profileMediaMaintenance/orphanSweep").set({
    schemaVersion: 1,
    cursor: { attacker: true },
  });
  const result = await cleanup().scheduledSweep({ limit: 1 });
  assert.deepEqual(result, {
    outcome: "cursor-reset",
    reason: "invalid-state",
  });
  assert.equal(storage.objects.has(orphan), true);
  assert.equal(
    (await db.doc("profileMediaMaintenance/orphanSweep").get()).data().cursor,
    null,
  );
});

test("migration revokes every conflicting reference and inventory marks orphans", async () => {
  const avatarA = `users/${A}/profile/avatar_1.jpg`;
  const avatarB = `users/${A}/profile/avatar_2.jpg`;
  const orphan = `users/${A}/profile/banner_3.png`;
  storage.put(avatarA);
  storage.put(avatarB, { generation: "1002" });
  storage.put(orphan, { generation: "1003", contentType: "image/png" });
  const url = (path) =>
    `https://firebasestorage.googleapis.com/v0/b/` +
    `${storage.bucketName}/o/${encodeURIComponent(path)}?alt=media&token=x`;
  await db.doc(`users/${A}`).set({ photoUrl: url(avatarA) }, { merge: true });
  await db.doc(`publicProfiles/${A}`).set({
    photoUrl: url(avatarB),
    bannerUrl: null,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  const migrated = await migration().migrateProfileMedia({
    userId: A,
    dryRun: false,
  });
  assert.equal(migrated.conflicts, 1);
  assert.equal(
    storage.objects.get(avatarA).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
  assert.equal(
    storage.objects.get(avatarB).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
  assert.equal(
    (await db.doc(`profileMedia/${A}`).get()).data().avatar.storagePath,
    avatarA,
  );

  const inventory = await migration().inventoryProfileMediaObjects({
    limit: 100,
    revokeTokens: true,
  });
  const orphanRow = inventory.objects.find((row) => row.path === orphan);
  assert.equal(orphanRow.orphan, true);
  assert.equal(orphanRow.hadDurableToken, true);
  assert.equal(orphanRow.tokenRevoked, true);
  assert.equal(
    storage.objects.get(orphan).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
});

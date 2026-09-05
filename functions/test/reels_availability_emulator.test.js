// Firestore integration coverage for the Reel v2 availability query and
// transaction boundary. Run with:
//   firebase emulators:exec --only firestore --project reel-availability-test \
//     "cd functions && node --test test/reels_availability_emulator.test.js"
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "reel-availability-test";

const assert = require("node:assert/strict");
const { after, test } = require("node:test");
const { deleteApp, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");

const { HOUR_MS } = require("../reels/availability");
const {
  REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH,
  createReelService,
} = require("../reels/service");

const app = initializeApp(
  { projectId: "reel-availability-test" },
  `reel-availability-${process.pid}`,
);
const db = getFirestore(app);
const NOW_MS = 1_778_500_000_000;

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

function composition() {
  return {
    caption: "emulator boundary",
    crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
    filter: "original",
    trimStartMs: 0,
    trimEndMs: 0,
    textOverlays: [],
    linkOverlays: [],
    originalAudioVolume: 0,
    backingAudioVolume: 0,
    audioTrimStartMs: 0,
    audioRightsAttested: false,
    audioAttribution: "",
  };
}

function root(reelId, publishedAt) {
  const authorId = `emulator-author-${process.pid}`;
  return {
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId,
    authorName: "Emulator Author",
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "777",
      durationMs: 0,
      storagePath: `reels/${authorId}/${reelId}/media.jpg`,
    },
    backingAudio: null,
    composition: composition(),
    sortKey: `${String(publishedAt.toMillis()).padStart(13, "0")}_${reelId}`,
    publishedAt,
    updatedAt: publishedAt,
  };
}

function sidecar(reelId, rootValue, createdAtMs, availabilityHours = 24) {
  return {
    schemaVersion: 2,
    status: "published",
    ownerId: rootValue.authorId,
    reelId,
    availabilityHours,
    createdAt: Timestamp.fromMillis(createdAtMs),
    publishedAt: rootValue.publishedAt,
    expiresAt: Timestamp.fromMillis(createdAtMs + availabilityHours * HOUR_MS),
    updatedAt: rootValue.publishedAt,
  };
}

test("emulator expires <= now atomically and leaves future sidecars visible", async () => {
  const exactId = `emulator-exact-${process.pid}`;
  const futureId = `emulator-future-${process.pid}`;
  const publishedAt = Timestamp.fromMillis(NOW_MS - 1000);
  const exactRoot = root(exactId, publishedAt);
  const futureRoot = root(futureId, publishedAt);
  const batch = db.batch();
  batch.set(db.doc(`reels/${exactId}`), exactRoot);
  batch.set(
    db.doc(`reelAvailability/${exactId}`),
    sidecar(exactId, exactRoot, NOW_MS - 24 * HOUR_MS),
  );
  batch.set(db.doc(`reels/${futureId}`), futureRoot);
  batch.set(
    db.doc(`reelAvailability/${futureId}`),
    sidecar(futureId, futureRoot, NOW_MS - 24 * HOUR_MS + 1),
  );
  await batch.commit();

  const service = createReelService({
    db,
    FieldPath,
    Timestamp,
    clock: () => NOW_MS,
    storage: {
      async getMetadata() { return {}; },
      async readHeader() { return Buffer.alloc(0); },
      async revokeDownloadTokens() {},
      async getSignedReadUrl() {
        return "https://storage.googleapis.com/private/reel";
      },
      async deleteObject() {},
    },
  });
  const outcome = await service.expirePublishedReels({ limit: 20 });
  assert.deepEqual(outcome.failed, []);
  assert.deepEqual(outcome.expired, [exactId]);

  const exact = (await db.doc(`reelAvailability/${exactId}`).get()).data();
  const future = (await db.doc(`reelAvailability/${futureId}`).get()).data();
  const expiredRoot = (await db.doc(`reels/${exactId}`).get()).data();
  assert.equal(exact.status, "expired");
  assert.equal(expiredRoot.status, "expired");
  assert.equal(Object.hasOwn(exact, "expiresAt"), false);
  assert.equal(future.status, "published");
  assert.equal(future.expiresAt.toMillis(), NOW_MS + 1);
  const outbox = (await db
    .collection("reelCleanupOutbox")
    .where("reelId", "==", exactId)
    .limit(1)
    .get()).docs[0].data();
  assert.equal(outbox.phase, "retain");
  assert.equal(outbox.status, "pending");
  assert.equal(outbox.nextAttemptAt.toMillis(), NOW_MS);
  assert.ok(outbox.purgeAt.toMillis() > NOW_MS);

  assert.deepEqual(
    (await service.expirePublishedReels({ limit: 20 })).expired,
    [],
    "the exact-deadline transition must be idempotent",
  );
});

test("emulator legacy sweep advances past future pending rows", async () => {
  const existingOutboxes = await db.collection("reelCleanupOutbox").get();
  const cleanup = db.batch();
  for (const document of existingOutboxes.docs) cleanup.delete(document.ref);
  cleanup.delete(db.doc(REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH));
  await cleanup.commit();

  const authorId = `emulator-author-${process.pid}`;
  await db.doc(`users/${authorId}`).set({ uid: authorId });
  const service = createReelService({
    db,
    FieldPath,
    Timestamp,
    clock: () => NOW_MS,
    storage: {
      async getMetadata() { return {}; },
      async readHeader() { return Buffer.alloc(0); },
      async revokeDownloadTokens() {},
      async getSignedReadUrl() {
        return "https://storage.googleapis.com/private/reel";
      },
      async deleteObject() {},
    },
  });
  const outboxes = [];
  for (const suffix of ["a", "b", "z"]) {
    const reelId = `emulator-legacy-${suffix}-${process.pid}`;
    const publishedAt = Timestamp.fromMillis(NOW_MS - 1000);
    await db.doc(`reels/${reelId}`).set(root(reelId, publishedAt));
    await service.deleteReel({
      auth: { uid: authorId, token: { email_verified: true } },
      data: {
        reelId,
        requestId: `emulator-delete-${suffix}-${process.pid}`,
      },
    });
    const snapshot = await db.collection("reelCleanupOutbox")
      .where("reelId", "==", reelId)
      .limit(1)
      .get();
    assert.equal(snapshot.size, 1);
    outboxes.push(snapshot.docs[0]);
  }
  outboxes.sort((left, right) => left.id.localeCompare(right.id));
  await Promise.all(outboxes.slice(0, 2).map((document) =>
    document.ref.update({
      nextAttemptAt: Timestamp.fromMillis(NOW_MS + HOUR_MS),
    })));
  await outboxes.at(-1).ref.update({ nextAttemptAt: FieldValue.delete() });

  const first = await service.processReadyCleanupOutbox({ limit: 2 });
  assert.equal(first.processed, 0);
  assert.equal(first.hasMore, true);
  assert.equal(
    (await db.doc(REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH).get()).data().cursor,
    outboxes[1].id,
  );

  const second = await service.processReadyCleanupOutbox({ limit: 2 });
  assert.equal(second.processed, 1);
  assert.equal(second.completed, 1);
  assert.equal(second.hasMore, false);
  assert.equal((await outboxes.at(-1).ref.get()).data().status, "completed");
  assert.equal(
    (await db.doc(REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH).get()).data().cursor,
    null,
  );
});

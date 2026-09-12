// Run only against the coordinated local Firestore emulator. Signing is a
// controlled adapter; this proves real Admin queries and post-signing reads,
// not production IAM or delivery of video bytes.
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
const assert = require("node:assert/strict");
const { after, test } = require("node:test");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { FieldPath, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { createReelService } = require("../reels/service");

assert.match(process.env.FIRESTORE_EMULATOR_HOST, /^(127\.0\.0\.1|localhost):[0-9]+$/u,
  "Inline grant integration tests require the local Firestore emulator.");
const app = initializeApp({ projectId: "demo-reel-inline-grants" }, `inline-${process.pid}`);
const db = getFirestore(app);
const NOW_MS = 1_778_000_000_000;
const DAY_MS = 24 * 60 * 60 * 1000;
let nextFixture = 0;

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

async function fixture(t) {
  const suffix = `${process.pid}-${nextFixture++}`;
  const viewer = `viewer-${suffix}`;
  const author = `author-${suffix}`;
  const id = `reel-${suffix}`;
  const publishedAt = Timestamp.fromMillis(NOW_MS - 1000);
  const objectPath = `reels/${author}/${id}/media.jpg`;
  const root = {
    schemaVersion: 1, status: "published", moderationStatus: "visible",
    authorId: author, authorName: "Public Creator",
    media: {
      kind: "image", contentType: "image/jpeg", size: 1024,
      generation: "777", durationMs: 0, storagePath: objectPath,
    },
    backingAudio: null,
    composition: {
      caption: "Emulator Reel",
      crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
      filter: "original", trimStartMs: 0, trimEndMs: 0,
      textOverlays: [], linkOverlays: [], originalAudioVolume: 0,
      backingAudioVolume: 0, audioTrimStartMs: 0,
      audioRightsAttested: false, audioAttribution: "",
    },
    sortKey: `${String(NOW_MS - 1000)}_${id}`,
    publishedAt, updatedAt: publishedAt,
  };
  const refs = [
    db.doc(`users/${viewer}`), db.doc(`users/${author}`), db.doc(`reels/${id}`),
    db.doc(`reelAvailability/${id}`), db.doc(`restrictions/${viewer}`),
    db.doc(`users/${author}/blocked/${viewer}`),
    db.doc(`users/${viewer}/blocked/${author}`),
    db.doc(`users/${viewer}/reelViews/${id}`),
  ];
  t.after(async () => {
    const cleanup = db.batch();
    refs.forEach((ref) => cleanup.delete(ref));
    await cleanup.commit();
  });
  const seed = db.batch();
  seed.set(refs[0], { uid: viewer, email: "private-viewer@example.invalid" });
  seed.set(refs[1], { uid: author, email: "private-author@example.invalid" });
  seed.set(refs[2], root);
  seed.set(refs[3], {
    schemaVersion: 2, status: "published", ownerId: author, reelId: id,
    availabilityHours: 24, createdAt: publishedAt, publishedAt,
    expiresAt: Timestamp.fromMillis(NOW_MS - 1000 + DAY_MS), updatedAt: publishedAt,
  });
  await seed.commit();
  const calls = [];
  const storage = {
    async getMetadata(path) {
      assert.equal(path, objectPath);
      return {
        generation: "777", size: "1024", contentType: "image/jpeg",
        metadata: { ownerId: author, reelId: id, assetKind: "media" },
      };
    },
    async readHeader() { return Buffer.from([0xff, 0xd8, 0xff]); },
    async revokeDownloadTokens() {},
    async getSignedReadUrl(path, options) {
      calls.push({ path, ...options });
      return `https://storage.googleapis.com/test-bucket/${path}?generation=${options.generation}`;
    },
    async deleteObject() {},
  };
  const service = createReelService({
    db, FieldPath, Timestamp, storage, clock: () => NOW_MS,
    randomSeed: () => "0123456789abcdef",
  });
  const request = (data = {}, uid = viewer) => ({
    auth: { uid, token: { email_verified: false } },
    data: { limit: 3, mediaGrants: true, ...data },
  });
  return { viewer, author, id, root, refs, service, calls, storage, request };
}

test("emulator real query returns opt-in grants and legacy/own/cursor shapes remain usable", async (t) => {
  const f = await fixture(t);
  const flagged = await f.service.listReelsV2(f.request());
  assert.equal(flagged.items.length, 1);
  assert.equal(flagged.items[0].id, f.id);
  assert.deepEqual(Object.keys(flagged.items[0].mediaGrant).sort(),
    ["expiresAtMillis", "generation", "url"]);
  assert.equal(flagged.items[0].mediaGrant.generation, "777");
  const old = await f.service.listReelsV2(f.request({ mediaGrants: false }));
  assert.equal(old.items[0].mediaGrant, undefined);
  // A cursor is only meaningful when another owned item exists. Seed it
  // after the one-item assertions; use the legacy no-sidecar path and no
  // inline grant on resume so the signer fixture remains single-object.
  const secondId = `${f.id}-older`;
  const secondRef = db.doc(`reels/${secondId}`);
  f.refs.push(secondRef);
  await secondRef.set({
    ...f.root,
    media: { ...f.root.media, storagePath: `reels/${f.author}/${secondId}/media.jpg` },
    sortKey: `${String(NOW_MS - 2000)}_${secondId}`,
    publishedAt: Timestamp.fromMillis(NOW_MS - 2000),
    updatedAt: Timestamp.fromMillis(NOW_MS - 2000),
  });
  const own = await f.service.listReelsV2(f.request({ scope: "own", limit: 1 }, f.author));
  assert.equal(own.items[0].id, f.id);
  assert.ok(own.items[0].mediaGrant);
  assert.match(own.nextCursor, /^f1\.o\.[0-9a-f]{16}\./u);
  const resumed = await f.service.listReelsV2(f.request({
    scope: "own", mediaGrants: false, cursor: own.nextCursor.split(".")[3],
  }, f.author));
  assert.deepEqual(resumed.items.map((item) => item.id), [secondId]);
  assert.equal(resumed.nextCursor, null);
  await assert.rejects(f.service.listReelsV2(f.request({ cursor: own.nextCursor })),
    (error) => error.code === "invalid-argument");
  assert.doesNotMatch(JSON.stringify(flagged), /private-|email|storagePath/u);
});

test("emulator canonical seen row suppresses only discover and never signs a suppressed item", async (t) => {
  const f = await fixture(t);
  await db.doc(`users/${f.viewer}/reelViews/${f.id}`).set({
    viewedAt: Timestamp.fromMillis(NOW_MS - 1000),
    expiresAt: Timestamp.fromMillis(NOW_MS - 1000 + 90 * DAY_MS),
  });
  assert.deepEqual((await f.service.listReelsV2(f.request())).items, []);
  assert.equal(f.calls.length, 0);
  const included = await f.service.listReelsV2(f.request({ includeSeen: true }));
  assert.equal(included.items[0].id, f.id);
  assert.ok(included.items[0].mediaGrant);
});

test("emulator both block directions and a restricted viewer deny before Storage signing", async (t) => {
  const f = await fixture(t);
  for (const blockPath of [
    `users/${f.viewer}/blocked/${f.author}`, `users/${f.author}/blocked/${f.viewer}`,
  ]) {
    await db.doc(blockPath).set({ createdAt: Timestamp.fromMillis(NOW_MS) });
    assert.deepEqual((await f.service.listReelsV2(f.request())).items, []);
    await db.doc(blockPath).delete();
  }
  await db.doc(`restrictions/${f.viewer}`).set({ type: "communicationMute", expiresAt: null });
  await assert.rejects(f.service.listReelsV2(f.request()),
    (error) => error.code === "permission-denied");
  assert.equal(f.calls.length, 0);
});

test("emulator final batch observes a block committed during signing", async (t) => {
  const f = await fixture(t);
  const sign = f.storage.getSignedReadUrl;
  f.storage.getSignedReadUrl = async (...args) => {
    const url = await sign(...args);
    await db.doc(`users/${f.author}/blocked/${f.viewer}`).set({ createdAt: Timestamp.fromMillis(NOW_MS) });
    return url;
  };
  const page = await f.service.listReelsV2(f.request());
  assert.equal(f.calls.length, 1);
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0].mediaGrant, undefined);
  await assert.rejects(f.service.getReelMediaAccessV2({
    auth: f.request().auth, data: { reelId: f.id, asset: "media" },
  }), (error) => error.code === "failed-precondition");
});

test("emulator signing failure leaves a renderable page and the direct callable can recover", async (t) => {
  const f = await fixture(t);
  const sign = f.storage.getSignedReadUrl;
  f.storage.getSignedReadUrl = async () => { throw new Error("private-provider-failure"); };
  const page = await f.service.listReelsV2(f.request());
  assert.equal(page.items[0].id, f.id);
  assert.equal(page.items[0].mediaGrant, undefined);
  f.storage.getSignedReadUrl = sign;
  assert.ok((await f.service.getReelMediaAccessV2({
    auth: f.request().auth, data: { reelId: f.id, asset: "media" },
  })).url);
});

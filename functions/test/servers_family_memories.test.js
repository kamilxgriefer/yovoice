// Family Memories V1: Firestore authorization and idempotency are exercised
// against the emulator while a deterministic private-media adapter supplies
// object metadata, trusted probe results, signed grants and deletion faults.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp(
    { projectId: "demo-yovoice-servers-family-memories" },
    `server-family-memories-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const {
  FAMILY_MEMORY_ACCESS_TTL_MS,
  FAMILY_MEMORY_RESERVATION_TTL_MS,
  MAX_VOICE_DURATION_MS,
  VOICE_DURATION_GRACE_MS,
  canonicalFamilyMemoryId,
  createServerFamilyMemoryService,
  deletionJobId,
  validateTrustedProbe,
} = require("../servers/family_memories");

const START_MS = 1_900_000_000_000;
const request = (uid, data, verified = true) => ({
  auth: { uid, token: { email_verified: verified } },
  data,
});
const rejection = (promise, code) => assert.rejects(
  promise,
  (error) => error.code === code,
);
const emulatorTest = (name, fn) => test(
  `Server Family Memories: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);

after(async () => {
  if (app) await require("firebase-admin/app").deleteApp(app);
});

class FakePrivateStorage {
  constructor() {
    this.objects = new Map();
    this.deleted = [];
    this.hardened = [];
    this.signed = [];
    this.failDelete = new Set();
    this.onSign = null;
    this.onProbe = null;
  }

  upload(asset, generation, probe = {}) {
    this.objects.set(asset.storagePath, {
      generation: String(generation),
      size: asset.size,
      contentType: asset.contentType,
      metadata: {
        ...asset.uploadMetadata,
        firebaseStorageDownloadTokens: `token-${generation}`,
      },
      probe: {
        detectedContentType: asset.contentType,
        durationMs: Object.hasOwn(asset, "durationMs") ? asset.durationMs : null,
        generation: String(generation),
        hasAudio: Object.hasOwn(asset, "durationMs"),
        hasVideo: false,
        size: asset.size,
        ...probe,
      },
    });
  }

  async getMetadata(path) {
    const object = this.objects.get(path);
    if (!object) {
      const error = new Error("missing fake object");
      error.code = 404;
      throw error;
    }
    return {
      generation: object.generation,
      size: String(object.size),
      contentType: object.contentType,
      metadata: { ...object.metadata },
    };
  }

  async hardenObject(path, metadata, required) {
    const object = this.objects.get(path);
    assert.ok(object);
    assert.equal(String(metadata.generation), object.generation);
    object.metadata = { ...object.metadata, ...required };
    delete object.metadata.firebaseStorageDownloadTokens;
    this.hardened.push(path);
    return this.getMetadata(path);
  }

  async getSignedReadUrl(path, options) {
    this.signed.push([path, options]);
    if (this.onSign) await this.onSign(path, options);
    return `https://storage.googleapis.com/test-private/${encodeURIComponent(path)}?generation=${options.generation}`;
  }

  async deleteObject(path, { generation = null } = {}) {
    if (this.failDelete.has(path)) throw new Error("injected storage delete failure");
    const object = this.objects.get(path);
    if (object && generation !== null && object.generation !== generation) {
      throw new Error("generation mismatch");
    }
    this.objects.delete(path);
    this.deleted.push([path, generation]);
  }

  async probeMedia(input) {
    if (this.onProbe) await this.onProbe(input);
    const object = this.objects.get(input.storagePath);
    if (!object) throw new Error("missing fake object");
    return { ...object.probe };
  }
}

async function createUser(prefix) {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${prefix}`,
    status: "active",
  });
  return uid;
}

async function fixture({ serverType = "family" } = {}) {
  const ownerId = await createUser(`memory-${serverType}-owner`);
  const clock = { nowMs: START_MS };
  const storage = new FakePrivateStorage();
  const dependencies = {
    db,
    Timestamp,
    clock: () => clock.nowMs,
    storage,
    probeMedia: (input) => storage.probeMedia(input),
  };
  const creation = createServerCreationService(dependencies);
  const memories = createServerFamilyMemoryService(dependencies);
  const created = await creation.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType,
    templateVersion: 1,
    name: `${serverType} memories`,
    description: "",
    privacy: serverType === "family" ? "inviteOnly" : "public",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const channels = await db.doc(`clubs/${created.serverId}`).collection("channels").get();
  const memoryChannel = channels.docs.find((document) => document.data().kind === "memories");
  const textChannel = channels.docs.find((document) => document.data().kind === "text");

  async function addMember(role = "member") {
    const uid = await createUser(`memory-${role}`);
    await db.doc(`clubs/${created.serverId}/members/${uid}`).set({
      userId: uid,
      displayName: `Canonical ${role}`,
      photoUrl: null,
      role,
      isOnline: false,
      joinedAt: Timestamp.fromMillis(clock.nowMs),
      invitedBy: ownerId,
      authorizationRevision: 1,
    });
    return uid;
  }

  const reserveData = (overrides = {}) => ({
    serverId: created.serverId,
    channelId: memoryChannel?.id ?? textChannel.id,
    requestId: randomUUID(),
    caption: "Sunday together",
    photoContentType: "image/jpeg",
    photoSize: 4096,
    voiceContentType: "audio/mp4",
    voiceSize: 8192,
    voiceDurationMs: 12_000,
    ...overrides,
  });

  async function reserveAndUpload(uid = ownerId, overrides = {}) {
    const data = reserveData(overrides);
    const reserved = await memories.reserveServerFamilyMemoryV1(request(uid, data));
    storage.upload(reserved.photo, "101");
    storage.upload(reserved.voice, "102");
    return { data, reserved };
  }

  const finalizeData = (reserved, overrides = {}) => ({
    serverId: created.serverId,
    channelId: reserved.channelId,
    memoryId: reserved.memoryId,
    requestId: randomUUID(),
    photoGeneration: "101",
    voiceGeneration: "102",
    ...overrides,
  });

  return {
    ...created,
    ...memories,
    ownerId,
    clock,
    storage,
    memoryChannelId: memoryChannel?.id ?? null,
    textChannelId: textChannel.id,
    addMember,
    reserveData,
    reserveAndUpload,
    finalizeData,
    memoryRef: (memoryId) => db.doc(`clubs/${created.serverId}/moments/${memoryId}`),
  };
}

emulatorTest("reservation is canonical, bounded, exact and replay-safe", async () => {
  const value = await fixture();
  const data = value.reserveData();
  const reserved = await value.reserveServerFamilyMemoryV1(request(value.ownerId, data));
  assert.equal(
    reserved.memoryId,
    canonicalFamilyMemoryId(value.ownerId, value.serverId, data.requestId),
  );
  assert.equal(reserved.expiresAtMillis, START_MS + FAMILY_MEMORY_RESERVATION_TTL_MS);
  assert.match(
    reserved.photo.storagePath,
    new RegExp(`^family_moments/${value.serverId}/${value.ownerId}/fm_[a-f0-9]{40}_photo[.]jpg$`, "u"),
  );
  assert.match(reserved.voice.storagePath, /_voice[.]m4a$/u);
  assert.deepEqual(Object.keys(reserved.photo.uploadMetadata).sort(), [
    "yovoiceAssetKind", "yovoiceChannelId", "yovoiceMemoryId",
    "yovoiceOwnerUid", "yovoiceServerId",
  ]);
  assert.deepEqual(
    await value.reserveServerFamilyMemoryV1(request(value.ownerId, data)),
    reserved,
  );
  await rejection(value.reserveServerFamilyMemoryV1(request(value.ownerId, {
    ...value.reserveData(),
    unsupported: true,
  })), "invalid-argument");
  await rejection(value.reserveServerFamilyMemoryV1(request(value.ownerId, value.reserveData({
    photoContentType: "image/gif",
  }))), "invalid-argument");
  await rejection(value.reserveServerFamilyMemoryV1(request(value.ownerId, value.reserveData({
    voiceDurationMs: 30_001,
  }))), "invalid-argument");
  await rejection(value.reserveServerFamilyMemoryV1(request(value.ownerId, value.reserveData())),
    "resource-exhausted");
});

emulatorTest("only a current Family memories-channel member may reserve", async () => {
  const family = await fixture();
  const memberId = await family.addMember();
  const outsiderId = await createUser("memory-outsider");
  const member = await family.reserveServerFamilyMemoryV1(request(
    memberId,
    family.reserveData(),
  ));
  assert.equal(member.photo.uploadMetadata.yovoiceOwnerUid, memberId);
  await rejection(family.reserveServerFamilyMemoryV1(request(
    outsiderId,
    family.reserveData(),
  )), "permission-denied");
  await rejection(family.reserveServerFamilyMemoryV1(request(
    family.ownerId,
    family.reserveData({ channelId: family.textChannelId }),
  )), "permission-denied");

  const community = await fixture({ serverType: "community" });
  await rejection(community.reserveServerFamilyMemoryV1(request(
    community.ownerId,
    community.reserveData({ channelId: community.textChannelId }),
  )), "permission-denied");
});

emulatorTest("finalize probes both generations and writes no durable URL", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  const data = value.finalizeData(reserved);
  const result = await value.finalizeServerFamilyMemoryV1(request(value.ownerId, data));
  assert.deepEqual(result, {
    schemaVersion: 1,
    serverId: value.serverId,
    channelId: value.memoryChannelId,
    memoryId: reserved.memoryId,
    revision: 1,
    status: "published",
  });
  assert.deepEqual(
    await value.finalizeServerFamilyMemoryV1(request(value.ownerId, data)),
    result,
  );
  const stored = (await value.memoryRef(reserved.memoryId).get()).data();
  assert.equal(stored.memoryKind, "familyMemory");
  assert.equal(stored.authorId, value.ownerId);
  assert.equal(stored.authorDisplayName, "Canonical memory-family-owner");
  assert.equal(stored.authorPhotoUrl, null);
  assert.equal(stored.status, "published");
  assert.equal(stored.photo.generation, "101");
  assert.equal(stored.voice.generation, "102");
  assert.equal(stored.voice.durationMs, 12_000);
  assert.equal(JSON.stringify(stored).includes("https://"), false);
  assert.deepEqual(value.storage.hardened.sort(), [
    reserved.photo.storagePath,
    reserved.voice.storagePath,
  ].sort());
  assert.equal(
    (await db.doc(`serverFamilyMemoryUploadReservations/${reserved.memoryId}`).get()).exists,
    false,
  );
  assert.equal(
    (await db.doc(`serverFamilyMemoryUploadLeases/${value.ownerId}`).get()).exists,
    false,
  );
});

emulatorTest("finalize rejects generation, signature and duration mismatches", async () => {
  for (const scenario of ["generation", "photo-type", "voice-duration", "voice-video"]) {
    const value = await fixture();
    const { reserved } = await value.reserveAndUpload();
    const data = value.finalizeData(reserved);
    if (scenario === "generation") data.photoGeneration = "999";
    if (scenario === "photo-type") {
      value.storage.objects.get(reserved.photo.storagePath).probe.detectedContentType = "image/png";
    }
    if (scenario === "voice-duration") {
      value.storage.objects.get(reserved.voice.storagePath).probe.durationMs = 29_000;
    }
    if (scenario === "voice-video") {
      value.storage.objects.get(reserved.voice.storagePath).probe.hasVideo = true;
    }
    await rejection(value.finalizeServerFamilyMemoryV1(request(value.ownerId, data)),
      "failed-precondition");
    assert.equal((await value.memoryRef(reserved.memoryId).get()).exists, false);
    assert.equal(
      (await db.doc(`serverFamilyMemoryUploadReservations/${reserved.memoryId}`).get()).exists,
      true,
    );
  }
});

test("Server Family Memories: a voice note capped at 30 s may measure up to 2 s over and is stored as 30 s", () => {
  assert.equal(MAX_VOICE_DURATION_MS, 30_000);
  assert.equal(VOICE_DURATION_GRACE_MS, 2000);
  const descriptor = { generation: "102", size: 8192, contentType: "audio/mp4", durationMs: 30_000 };
  const probe = (durationMs) => ({
    generation: "102",
    size: 8192,
    detectedContentType: "audio/mp4",
    durationMs,
    hasAudio: true,
    hasVideo: false,
  });
  for (const [measured, stored] of [
    [30_000, 30_000], [30_400, 30_000], [31_900, 30_000], [32_000, 30_000],
  ]) {
    assert.equal(validateTrustedProbe(probe(measured), descriptor, "voice"), stored,
      `measured ${measured} ms`);
  }
  for (const measured of [32_001, 32_100, 45_000]) {
    assert.throws(() => validateTrustedProbe(probe(measured), descriptor, "voice"),
      (error) => error.code === "failed-precondition" &&
        error.message === "The Family Memory voice note is invalid.",
      `measured ${measured} ms`);
  }
  // Below the cap the real measurement is kept, not rounded or clamped.
  assert.equal(validateTrustedProbe(probe(12_400), { ...descriptor, durationMs: 12_000 }, "voice"),
    12_400);
  // The grace never widens the declared-vs-measured tolerance.
  assert.throws(() => validateTrustedProbe(probe(31_900), { ...descriptor, durationMs: 29_000 }, "voice"),
    (error) => error.code === "failed-precondition");
});

emulatorTest("a voice note that hits the 30 s cap and measures 31.9 s is published as 30 s", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload(value.ownerId, { voiceDurationMs: 30_000 });
  value.storage.objects.get(reserved.voice.storagePath).probe.durationMs = 31_900;
  await value.finalizeServerFamilyMemoryV1(request(value.ownerId, value.finalizeData(reserved)));
  const stored = (await value.memoryRef(reserved.memoryId).get()).data();
  assert.equal(stored.status, "published");
  assert.equal(stored.voice.durationMs, 30_000);
  // The canonical memory read accepts the clamped value.
  const memberId = await value.addMember();
  const access = await value.getServerFamilyMemoryMediaAccessV1(request(memberId, {
    serverId: value.serverId,
    channelId: value.memoryChannelId,
    memoryId: reserved.memoryId,
  }));
  assert.equal(access.voice.durationMs, 30_000);
});

emulatorTest("a voice note measured past the 30 s grace is refused and never published", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload(value.ownerId, { voiceDurationMs: 30_000 });
  value.storage.objects.get(reserved.voice.storagePath).probe.durationMs = 32_100;
  await rejection(value.finalizeServerFamilyMemoryV1(request(
    value.ownerId,
    value.finalizeData(reserved),
  )), "failed-precondition");
  assert.equal((await value.memoryRef(reserved.memoryId).get()).exists, false);
});

emulatorTest("finalize reauthorizes after the external probe", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  let removed = false;
  value.storage.onProbe = async () => {
    if (removed) return;
    removed = true;
    await db.doc(`clubs/${value.serverId}/members/${value.ownerId}`).delete();
  };
  await rejection(value.finalizeServerFamilyMemoryV1(request(
    value.ownerId,
    value.finalizeData(reserved),
  )), "permission-denied");
  assert.equal((await value.memoryRef(reserved.memoryId).get()).exists, false);
  assert.equal(
    (await db.doc(`serverFamilyMemoryUploadReservations/${reserved.memoryId}`).get()).exists,
    true,
  );
});

emulatorTest("media access returns short grants and closes a signing TOCTOU", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  await value.finalizeServerFamilyMemoryV1(request(
    value.ownerId,
    value.finalizeData(reserved),
  ));
  const memberId = await value.addMember();
  const input = {
    serverId: value.serverId,
    channelId: value.memoryChannelId,
    memoryId: reserved.memoryId,
  };
  const access = await value.getServerFamilyMemoryMediaAccessV1(request(memberId, input));
  assert.equal(access.expiresAtMillis, START_MS + FAMILY_MEMORY_ACCESS_TTL_MS);
  assert.match(access.photo.url, /^https:\/\/storage[.]googleapis[.]com\//u);
  assert.match(access.voice.url, /^https:\/\/storage[.]googleapis[.]com\//u);
  assert.equal(access.voice.durationMs, 12_000);

  let removed = false;
  value.storage.onSign = async () => {
    if (removed) return;
    removed = true;
    await db.doc(`clubs/${value.serverId}/members/${memberId}`).delete();
  };
  await rejection(value.getServerFamilyMemoryMediaAccessV1(request(memberId, input)),
    "permission-denied");
});

emulatorTest("author or moderator deletion is fenced and storage-resumable", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  await value.finalizeServerFamilyMemoryV1(request(
    value.ownerId,
    value.finalizeData(reserved),
  ));
  const peerId = await value.addMember();
  const moderatorId = await value.addMember("moderator");
  const base = {
    serverId: value.serverId,
    channelId: value.memoryChannelId,
    memoryId: reserved.memoryId,
    expectedRevision: 1,
    requestId: randomUUID(),
  };
  await rejection(value.deleteServerFamilyMemoryV1(request(peerId, base)),
    "permission-denied");
  await rejection(value.deleteServerFamilyMemoryV1(request(moderatorId, {
    ...base,
    requestId: randomUUID(),
    expectedRevision: 2,
  })), "aborted");

  value.storage.failDelete.add(reserved.voice.storagePath);
  await assert.rejects(value.deleteServerFamilyMemoryV1(request(moderatorId, base)),
    /injected storage delete failure/u);
  const tombstone = (await value.memoryRef(reserved.memoryId).get()).data();
  assert.equal(tombstone.status, "deleting");
  assert.equal(tombstone.revision, 2);
  const job = deletionJobId(value.serverId, reserved.memoryId);
  assert.equal((await db.doc(`serverFamilyMemoryDeletionJobs/${job}`).get()).exists, true);
  assert.equal(value.storage.objects.has(reserved.photo.storagePath), false);
  assert.equal(value.storage.objects.has(reserved.voice.storagePath), true);

  value.storage.failDelete.clear();
  const sweep = await value.processPendingFamilyMemoryDeletionJobs({ limit: 20 });
  assert.deepEqual(sweep.completed, [job]);
  assert.equal((await value.memoryRef(reserved.memoryId).get()).exists, false);
  assert.equal((await db.doc(`serverFamilyMemoryDeletionJobs/${job}`).get()).exists, false);
  const replay = await value.deleteServerFamilyMemoryV1(request(moderatorId, base));
  assert.equal(replay.deleted, true);
  assert.equal(replay.cleanupPending, false);
});

emulatorTest("expired upload cleanup retires reservation, lease and both objects", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  value.clock.nowMs += FAMILY_MEMORY_RESERVATION_TTL_MS + 1;
  const cleanup = await value.expireServerFamilyMemoryUploadReservations({ limit: 20 });
  assert.ok(cleanup.expired.includes(reserved.memoryId));
  assert.equal(value.storage.objects.has(reserved.photo.storagePath), false);
  assert.equal(value.storage.objects.has(reserved.voice.storagePath), false);
  assert.equal(
    (await db.doc(`serverFamilyMemoryUploadReservations/${reserved.memoryId}`).get()).exists,
    false,
  );
  assert.equal(
    (await db.doc(`serverFamilyMemoryUploadLeases/${value.ownerId}`).get()).exists,
    false,
  );
  const next = await value.reserveServerFamilyMemoryV1(request(
    value.ownerId,
    value.reserveData(),
  ));
  assert.notEqual(next.memoryId, reserved.memoryId);
});

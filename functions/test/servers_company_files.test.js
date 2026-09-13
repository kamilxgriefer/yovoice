// Company Files V1 exercises authorization and replay against Firestore while
// a deterministic private-object adapter models generation, byte probing,
// signed access and cleanup faults without contacting Cloud Storage.
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
    { projectId: "demo-yovoice-servers-company-files" },
    `server-company-files-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerManagementService } = require("../servers/management");
const {
  createServerConvergenceRuntimeService,
} = require("../servers/convergence_runtime");
const {
  COMPANY_FILE_ACCESS_TTL_MS,
  COMPANY_FILE_RESERVATION_TTL_MS,
  companyFileId,
  createServerCompanyFileService,
  deletionJobId,
  detectCompanyFileType,
} = require("../servers/company_files");

const START_MS = 1_900_000_000_000;
const request = (uid, data, verified = true) => ({
  auth: { uid, token: { email_verified: verified } },
  data,
});
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const emulatorTest = (name, fn) => test(`Server Company Files: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.",
  timeout: 60_000,
}, fn);

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
    this.onProbe = null;
    this.onSign = null;
  }

  upload(asset, generation, { detectedContentType = asset.contentType } = {}) {
    this.objects.set(asset.storagePath, {
      generation: String(generation),
      size: asset.size,
      contentType: asset.contentType,
      metadata: {
        ...asset.uploadMetadata,
        firebaseStorageDownloadTokens: `token-${generation}`,
      },
      detectedContentType,
    });
  }

  async getMetadata(path) {
    const value = this.objects.get(path);
    if (!value) throw new Error("missing fake object");
    return {
      generation: value.generation,
      size: String(value.size),
      contentType: value.contentType,
      metadata: { ...value.metadata },
    };
  }

  async probeFile(path, options) {
    if (this.onProbe) await this.onProbe(path, options);
    const value = this.objects.get(path);
    if (!value) throw new Error("missing fake object");
    return {
      generation: value.generation,
      size: value.size,
      detectedContentType: value.detectedContentType,
    };
  }

  async hardenObject(path, metadata, required) {
    const value = this.objects.get(path);
    assert.ok(value);
    assert.equal(String(metadata.generation), value.generation);
    value.metadata = { ...value.metadata, ...required };
    delete value.metadata.firebaseStorageDownloadTokens;
    this.hardened.push(path);
    return this.getMetadata(path);
  }

  async getSignedReadUrl(path, options) {
    this.signed.push([path, options]);
    if (this.onSign) await this.onSign(path, options);
    return `https://storage.googleapis.com/company-private/${encodeURIComponent(path)}?generation=${options.generation}`;
  }

  async deleteObject(path, { generation = null } = {}) {
    if (this.failDelete.has(path)) throw new Error("injected storage delete failure");
    const value = this.objects.get(path);
    if (value && generation !== null && value.generation !== generation) {
      throw new Error("generation mismatch");
    }
    this.objects.delete(path);
    this.deleted.push([path, generation]);
  }
}

async function createUser(prefix) {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: `Canonical ${prefix}`, status: "active" });
  return uid;
}

async function fixture({ serverType = "company" } = {}) {
  const ownerId = await createUser(`file-${serverType}-owner`);
  const clock = { nowMs: START_MS };
  const storage = new FakePrivateStorage();
  const dependencies = { db, Timestamp, clock: () => clock.nowMs, storage };
  const companyFiles = createServerCompanyFileService(dependencies);
  const livekit = {
    assertSupported() {},
    async revokeParticipant() {
      throw new Error("Idle Company File cleanup must not contact LiveKit.");
    },
    async endRoom() {
      throw new Error("Idle Company File cleanup must not contact LiveKit.");
    },
  };
  const familyMemoryStorage = {
    async listObjects() { return []; },
    async deleteObject() {
      throw new Error("Company File cleanup must not delete Family media.");
    },
  };
  const service = {
    ...companyFiles,
    ...createServerChannelService(dependencies),
    ...createServerManagementService(dependencies),
    ...createServerConvergenceRuntimeService({
      ...dependencies,
      livekit,
      familyMemoryStorage,
      companyFileStorage: storage,
    }),
  };
  const created = await createServerCreationService(dependencies).createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType,
    templateVersion: 1,
    name: `${serverType} files`,
    description: "",
    privacy: serverType === "community" ? "public" : "inviteOnly",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const anchors = await db.collection("rooms")
    .where("serverId", "==", created.serverId)
    .get();
  for (const anchor of anchors.docs) {
    await anchor.ref.update({
      status: "active",
      serverActivationState: "active",
      hostId: ownerId,
    });
  }
  const channels = await db.doc(`clubs/${created.serverId}`).collection("channels").get();
  const fileChannel = channels.docs.find((document) => document.data().kind === "files");
  const textChannel = channels.docs.find((document) => document.data().kind === "text");

  async function addMember(role = "member") {
    const uid = await createUser(`file-${role}`);
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
    channelId: fileChannel?.id ?? textChannel.id,
    requestId: randomUUID(),
    displayName: "Quarterly plan.pdf",
    contentType: "application/pdf",
    size: 4096,
    ...overrides,
  });

  async function reserveAndUpload(uid = ownerId, overrides = {}, upload = {}) {
    const data = reserveData(overrides);
    const reserved = await service.reserveServerCompanyFileV1(request(uid, data));
    storage.upload(reserved.file, "301", upload);
    return { data, reserved };
  }

  const finalizeData = (reserved, overrides = {}) => ({
    serverId: created.serverId,
    channelId: reserved.channelId,
    fileId: reserved.fileId,
    generation: "301",
    requestId: randomUUID(),
    ...overrides,
  });

  return {
    ...created,
    ...service,
    ownerId,
    clock,
    storage,
    fileChannelId: fileChannel?.id ?? null,
    textChannelId: textChannel.id,
    addMember,
    reserveData,
    reserveAndUpload,
    finalizeData,
    fileRef: (fileId) => db.doc(
      `clubs/${created.serverId}/channels/${fileChannel?.id ?? textChannel.id}/files/${fileId}`,
    ),
  };
}

async function outboxFor(serverId, kind) {
  const snapshot = await db.collection("serverControlOutbox")
    .where("serverId", "==", serverId)
    .get();
  return snapshot.docs
    .map((document) => ({ id: document.id, data: document.data() }))
    .filter((entry) => entry.data.kind === kind);
}

async function drainDeletion(value, operationId, { limit = 240 } = {}) {
  let result = null;
  for (let pass = 0; pass < limit; pass += 1) {
    result = await value.processServerConvergencePage({
      operationId,
      pageSize: 2,
    });
    if (result.cleanupPending === false) return result;
  }
  assert.fail(`Deletion ${operationId} did not converge within ${limit} pages.`);
}

test("Company File probe recognizes only the bounded V1 type set", () => {
  assert.equal(detectCompanyFileType(Buffer.from("%PDF-1.7\nbody\n%%EOF")), "application/pdf");
  assert.equal(detectCompanyFileType(
    Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x01, 0xff, 0xd9]),
  ), "image/jpeg");
  assert.equal(detectCompanyFileType(Buffer.from("plain utf8 text")), "text/plain");
  assert.equal(detectCompanyFileType(Buffer.from([0x00, 0x01, 0x02])), null);
});

emulatorTest("reservation is canonical, exact, bounded and replay safe", async () => {
  const value = await fixture();
  const data = value.reserveData();
  const reserved = await value.reserveServerCompanyFileV1(request(value.ownerId, data));
  assert.equal(reserved.fileId,
    companyFileId(value.ownerId, value.serverId, value.fileChannelId, data.requestId));
  assert.equal(reserved.expiresAtMillis, START_MS + COMPANY_FILE_RESERVATION_TTL_MS);
  assert.match(reserved.file.storagePath,
    new RegExp(`^server_company_files/${value.serverId}/${value.fileChannelId}/${value.ownerId}/cf_[a-f0-9]{40}[.]pdf$`, "u"));
  assert.deepEqual(Object.keys(reserved.file.uploadMetadata).sort(), [
    "yovoiceAssetKind", "yovoiceChannelId", "yovoiceFileId",
    "yovoiceOwnerUid", "yovoiceServerId",
  ]);
  assert.deepEqual(await value.reserveServerCompanyFileV1(request(value.ownerId, data)), reserved);
  await rejection(value.reserveServerCompanyFileV1(request(value.ownerId, {
    ...value.reserveData(), unsupported: true,
  })), "invalid-argument");
  await rejection(value.reserveServerCompanyFileV1(request(value.ownerId,
    value.reserveData({ contentType: "application/zip" }))), "invalid-argument");
  await rejection(value.reserveServerCompanyFileV1(request(value.ownerId,
    value.reserveData({ displayName: "../private.pdf" }))), "invalid-argument");
  await rejection(value.reserveServerCompanyFileV1(request(value.ownerId, value.reserveData())),
    "resource-exhausted");
});

emulatorTest("only a current Company files-channel member may reserve", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const outsider = await createUser("file-outsider");
  const member = await value.reserveServerCompanyFileV1(request(memberId, value.reserveData()));
  assert.equal(member.file.uploadMetadata.yovoiceOwnerUid, memberId);
  await rejection(value.reserveServerCompanyFileV1(request(outsider, value.reserveData())),
    "permission-denied");
  await rejection(value.reserveServerCompanyFileV1(request(value.ownerId,
    value.reserveData({ channelId: value.textChannelId }))), "permission-denied");
  const community = await fixture({ serverType: "community" });
  await rejection(community.reserveServerCompanyFileV1(request(community.ownerId,
    community.reserveData({ channelId: community.textChannelId }))), "permission-denied");
});

emulatorTest("finalize probes generation and bytes, reauthorizes, and stores no URL", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  const data = value.finalizeData(reserved);
  const result = await value.finalizeServerCompanyFileV1(request(value.ownerId, data));
  assert.deepEqual(result, {
    schemaVersion: 1,
    serverId: value.serverId,
    channelId: value.fileChannelId,
    fileId: reserved.fileId,
    revision: 1,
    status: "published",
  });
  assert.deepEqual(await value.finalizeServerCompanyFileV1(request(value.ownerId, data)), result);
  const stored = (await value.fileRef(reserved.fileId).get()).data();
  assert.equal(stored.fileKind, "companyFile");
  assert.equal(stored.ownerDisplayName, "Canonical file-company-owner");
  assert.equal(stored.ownerPhotoUrl, null);
  assert.equal(stored.file.generation, "301");
  assert.equal(JSON.stringify(stored).includes("https://"), false);
  assert.deepEqual(value.storage.hardened, [reserved.file.storagePath]);
  assert.equal((await db.doc(`serverCompanyFileUploadReservations/${reserved.fileId}`).get()).exists, false);
  assert.equal((await db.doc(`serverCompanyFileUploadLeases/${value.ownerId}`).get()).exists, false);

  const mismatch = await fixture();
  const bad = await mismatch.reserveAndUpload(undefined, {}, { detectedContentType: "image/png" });
  await rejection(mismatch.finalizeServerCompanyFileV1(request(
    mismatch.ownerId, mismatch.finalizeData(bad.reserved),
  )), "failed-precondition");
  assert.equal((await mismatch.fileRef(bad.reserved.fileId).get()).exists, false);

  const revoked = await fixture();
  const pending = await revoked.reserveAndUpload();
  revoked.storage.onProbe = async () => {
    await db.doc(`clubs/${revoked.serverId}/members/${revoked.ownerId}`).delete();
  };
  await rejection(revoked.finalizeServerCompanyFileV1(request(
    revoked.ownerId, revoked.finalizeData(pending.reserved),
  )), "permission-denied");
  assert.equal((await revoked.fileRef(pending.reserved.fileId).get()).exists, false);
});

emulatorTest("private signed read is short lived and closes signing TOCTOU", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  await value.finalizeServerCompanyFileV1(request(value.ownerId, value.finalizeData(reserved)));
  const memberId = await value.addMember();
  const input = {
    serverId: value.serverId,
    channelId: value.fileChannelId,
    fileId: reserved.fileId,
  };
  const access = await value.getServerCompanyFileAccessV1(request(memberId, input));
  assert.equal(access.expiresAtMillis, START_MS + COMPANY_FILE_ACCESS_TTL_MS);
  assert.match(access.file.url, /^https:\/\/storage[.]googleapis[.]com\//u);
  assert.equal(access.file.generation, "301");
  let removed = false;
  value.storage.onSign = async () => {
    if (removed) return;
    removed = true;
    await db.doc(`clubs/${value.serverId}/members/${memberId}`).delete();
  };
  await rejection(value.getServerCompanyFileAccessV1(request(memberId, input)),
    "permission-denied");
});

emulatorTest("author or moderator delete is revision fenced, durable and resumable", async () => {
  const value = await fixture();
  const { reserved } = await value.reserveAndUpload();
  const finalization = value.finalizeData(reserved);
  await value.finalizeServerCompanyFileV1(request(value.ownerId, finalization));
  const peerId = await value.addMember();
  const moderatorId = await value.addMember("moderator");
  const input = {
    serverId: value.serverId,
    channelId: value.fileChannelId,
    fileId: reserved.fileId,
    expectedRevision: 1,
    requestId: randomUUID(),
  };
  await rejection(value.deleteServerCompanyFileV1(request(peerId, input)), "permission-denied");
  await rejection(value.deleteServerCompanyFileV1(request(moderatorId, {
    ...input, requestId: randomUUID(), expectedRevision: 2,
  })), "aborted");
  value.storage.failDelete.add(reserved.file.storagePath);
  await assert.rejects(value.deleteServerCompanyFileV1(request(moderatorId, input)),
    /injected storage delete failure/u);
  const tombstone = (await value.fileRef(reserved.fileId).get()).data();
  assert.equal(tombstone.status, "deleting");
  assert.equal(tombstone.revision, 2);
  const jobId = deletionJobId(value.serverId, value.fileChannelId, reserved.fileId);
  assert.equal((await db.doc(`serverCompanyFileDeletionJobs/${jobId}`).get()).exists, true);
  value.storage.failDelete.clear();
  assert.deepEqual(
    (await value.processPendingCompanyFileDeletionJobs({ limit: 20 })).completed,
    [jobId],
  );
  assert.equal((await value.fileRef(reserved.fileId).get()).exists, false);
  assert.equal((await db.doc(`serverCompanyFileDeletionJobs/${jobId}`).get()).exists, false);
  const replay = await value.deleteServerCompanyFileV1(request(moderatorId, input));
  assert.equal(replay.deleted, true);
  assert.equal(replay.cleanupPending, false);
  await rejection(
    value.finalizeServerCompanyFileV1(request(value.ownerId, finalization)),
    "not-found",
  );
  await rejection(value.getServerCompanyFileAccessV1(request(value.ownerId, {
    serverId: value.serverId,
    channelId: value.fileChannelId,
    fileId: reserved.fileId,
  })), "not-found");
});

emulatorTest("expired upload cleanup removes object, reservation and lease", async () => {
  const value = await fixture();
  const { data, reserved } = await value.reserveAndUpload();
  value.clock.nowMs += COMPANY_FILE_RESERVATION_TTL_MS + 1;
  const cleanup = await value.expireServerCompanyFileUploadReservations({ limit: 20 });
  assert.ok(cleanup.expired.includes(reserved.fileId));
  assert.equal(value.storage.objects.has(reserved.file.storagePath), false);
  assert.equal((await db.doc(`serverCompanyFileUploadReservations/${reserved.fileId}`).get()).exists, false);
  assert.equal((await db.doc(`serverCompanyFileUploadLeases/${value.ownerId}`).get()).exists, false);
  await rejection(
    value.reserveServerCompanyFileV1(request(value.ownerId, data)),
    "failed-precondition",
  );
});

emulatorTest("channel deletion drains published and reserved Company File bytes and resumes after failure", async () => {
  const value = await fixture();
  const published = await value.reserveAndUpload();
  await value.finalizeServerCompanyFileV1(request(
    value.ownerId,
    value.finalizeData(published.reserved),
  ));
  const pending = await value.reserveAndUpload();
  const deletion = await value.deleteServerChannelV1(request(value.ownerId, {
    serverId: value.serverId,
    channelId: value.fileChannelId,
    requestId: randomUUID(),
  }));
  assert.equal(deletion.cleanupPending, true);
  const jobs = await outboxFor(value.serverId, "channelDelete");
  assert.equal(jobs.length, 1);

  value.storage.failDelete.add(published.reserved.file.storagePath);
  let failed = false;
  for (let pass = 0; pass < 160 && !failed; pass += 1) {
    try {
      await value.processServerConvergencePage({
        operationId: jobs[0].id,
        pageSize: 2,
      });
    } catch (error) {
      assert.match(error.message, /injected storage delete failure/u);
      failed = true;
    }
  }
  assert.equal(failed, true, "the injected object deletion must be reached");
  const held = (await db.doc(`serverControlOutbox/${jobs[0].id}`).get()).data();
  assert.equal(held.bridgeLeaseId, null);
  assert.equal(held.lastErrorCode, "unavailable");
  assert.equal(held.retryAfterMillis, value.clock.nowMs + 30_000);
  assert.equal(value.storage.objects.has(pending.reserved.file.storagePath), false,
    "the earlier reservation page was durably drained");

  value.storage.failDelete.clear();
  value.clock.nowMs += 30_001;
  const settled = await drainDeletion(value, jobs[0].id);
  assert.equal(settled.cleanupPending, false);
  assert.equal((await db.doc(
    `clubs/${value.serverId}/channels/${value.fileChannelId}`,
  ).get()).exists, false);
  assert.equal(value.storage.objects.has(published.reserved.file.storagePath), false);
  assert.equal((await db.collection("serverCompanyFileUploadReservations")
    .where("serverId", "==", value.serverId).get()).empty, true);
  assert.equal((await db.collection("serverCompanyFileDeletionJobs")
    .where("serverId", "==", value.serverId).get()).empty, true);
  assert.equal((await db.doc(`serverCompanyFileUploadLeases/${value.ownerId}`).get()).exists, false);
});

emulatorTest("server deletion drains Company Files before removing their root", async () => {
  const value = await fixture();
  const published = await value.reserveAndUpload();
  await value.finalizeServerCompanyFileV1(request(
    value.ownerId,
    value.finalizeData(published.reserved),
  ));
  const deletion = await value.deleteServerV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
  }));
  assert.equal(deletion.cleanupPending, true);
  const jobs = await outboxFor(value.serverId, "serverDelete");
  assert.equal(jobs.length, 1);
  const settled = await drainDeletion(value, jobs[0].id);
  assert.equal(settled.cleanupPending, false);
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).exists, false);
  assert.equal(value.storage.objects.has(published.reserved.file.storagePath), false);
  assert.equal((await db.collection("serverCompanyFileUploadReservations")
    .where("serverId", "==", value.serverId).get()).empty, true);
  assert.equal((await db.collection("serverCompanyFileDeletionJobs")
    .where("serverId", "==", value.serverId).get()).empty, true);
});

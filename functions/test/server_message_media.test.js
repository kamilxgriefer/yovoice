// Photo and video messages in Servers V1 text channels: reserve, finalize,
// batched access grants, author retraction, the two workers, the content
// cleanup hand-off and the account-deletion sweep. Authorization refusals come
// first in every group. Firestore is the explicitly selected localhost
// emulator; a deterministic private-object adapter models generations, the
// trusted probe, token hardening, signing and deletion without Cloud Storage.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let app;
let db;
let Timestamp;
let FieldValue;
let FieldPath;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  FieldValue = firestore.FieldValue;
  FieldPath = firestore.FieldPath;
  app = adminApp.initializeApp({ projectId: "demo-yovoice-server-message-media" },
    `server-message-media-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

const { rateLimitReference } = require("../integrity/guards");
const {
  DELETION_JOBS,
  OBJECTS,
  RESERVATIONS,
  LEASES,
  SERVER_MESSAGE_MEDIA_ACCESS_TTL_MS,
  SERVER_MESSAGE_MEDIA_DAILY_BYTES,
  SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS,
  canonicalServerMessageMedia,
  objectDeletionJobId,
  prefixDeletionJob,
  prefixDeletionJobId,
  serverMessageMediaStoragePath,
  serverMessageMediaUploadMetadata,
} = require("../servers/message_media_contract");
const { createServerMessageMediaService } = require("../servers/message_media");
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerManagementService } = require("../servers/management");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const { createAccountDeletionStages } = require("../account/stages");
const { seedServerMessaging } = require("./helpers/server_message_fixture");

const NOW = 1_900_000_000_000;
const BUCKET = "demo-bucket";
const emulatorTest = (name, fn) => test(`Server message media: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.",
  timeout: 90_000,
}, fn);
const request = (uid, data, verified = true) => ({ auth: { uid, token: { email_verified: verified } }, data });
const rejects = (promise, code, reason = null) => assert.rejects(promise, (error) => {
  assert.equal(error.code, code, `${error.code}: ${error.message}`);
  if (reason !== null) assert.equal(error.message, reason);
  return true;
});

class FakeStorage {
  constructor() {
    this.objects = new Map();
    this.deleted = [];
    this.signed = [];
    this.failDelete = new Set();
    this.onProbe = null;
    this.onSign = null;
    this.keepToken = false;
  }

  upload(reserved, generation, { metadata = {}, probe = {}, size, contentType } = {}) {
    const media = reserved.media;
    this.objects.set(media.storagePath, {
      generation: String(generation),
      size: size ?? media.size,
      contentType: contentType ?? media.contentType,
      metadata: { ...media.uploadMetadata, firebaseStorageDownloadTokens: `token-${generation}`, ...metadata },
      probe: {
        detectedContentType: media.contentType,
        hasAudio: media.type === "video",
        hasVideo: media.type === "video",
        durationMs: media.type === "video" ? media.durationSeconds * 1000 : null,
        ...probe,
      },
    });
  }

  objectReference(path) {
    return `gs://${BUCKET}/${path}`;
  }

  async getMetadata(path) {
    const value = this.objects.get(path);
    if (!value) throw Object.assign(new Error("No such object"), { code: 404 });
    return {
      generation: value.generation,
      size: String(value.size),
      contentType: value.contentType,
      metadata: { ...value.metadata },
    };
  }

  async hardenObject(path, metadata, required) {
    const value = this.objects.get(path);
    assert.ok(value, "hardening a missing object");
    assert.equal(String(metadata.generation), value.generation);
    value.metadata = { ...value.metadata, ...required };
    if (!this.keepToken) delete value.metadata.firebaseStorageDownloadTokens;
    return this.getMetadata(path);
  }

  async getSignedReadUrl(path, options) {
    this.signed.push([path, options]);
    if (this.onSign) await this.onSign(path, options);
    return `https://storage.googleapis.com/${BUCKET}/${encodeURIComponent(path)}?generation=${options.generation}`;
  }

  async deleteObject(path, { generation = null } = {}) {
    if (this.failDelete.has(path)) throw new Error("injected storage delete failure");
    const value = this.objects.get(path);
    if (value && generation !== null && value.generation !== generation) throw new Error("generation mismatch");
    this.objects.delete(path);
    this.deleted.push([path, generation]);
  }

  async listObjects(prefix, { maxResults = 20 } = {}) {
    return [...this.objects.entries()]
      .filter(([name]) => name.startsWith(prefix))
      .slice(0, maxResults)
      .map(([name, value]) => ({ name, generation: value.generation }));
  }

  probe() {
    return async ({ storagePath, generation, size }) => {
      if (this.onProbe) await this.onProbe(storagePath);
      const value = this.objects.get(storagePath);
      assert.ok(value, "probing a missing object");
      return { generation, size, ...value.probe };
    };
  }
}

async function fixture() {
  const clock = { nowMs: NOW };
  const seeded = await seedServerMessaging(db, Timestamp, { label: "media", nowMs: NOW });
  const storage = new FakeStorage();
  const service = createServerMessageMediaService({
    db, Timestamp, clock: () => clock.nowMs, storage, probeMedia: storage.probe(),
  });
  const shape = {
    image: { type: "image", contentType: "image/jpeg", size: 4096, durationSeconds: null },
    video: { type: "video", contentType: "video/mp4", size: 65536, durationSeconds: 12 },
  };
  const reserveData = (channelKey = "text", kind = "image", overrides = {}) => ({
    serverId: seeded.serverId,
    channelId: seeded.channels[channelKey],
    ...shape[kind],
    requestId: randomUUID(),
    ...overrides,
  });
  const reserve = (userKey, channelKey, kind, overrides) =>
    service.reserveServerChannelMessageMediaV1(request(seeded.users[userKey], reserveData(channelKey, kind, overrides)));
  const finalizeData = (reserved, overrides = {}) => ({
    serverId: reserved.serverId,
    channelId: reserved.channelId,
    messageId: reserved.messageId,
    objectGeneration: "301",
    requestId: randomUUID(),
    ...overrides,
  });
  async function publish(userKey = "member", channelKey = "text", kind = "image") {
    const reserved = await reserve(userKey, channelKey, kind);
    storage.upload(reserved, "301");
    const finalized = await service.finalizeServerChannelMessageMediaV1(
      request(seeded.users[userKey], finalizeData(reserved)),
    );
    return { reserved, finalized, path: reserved.media.storagePath };
  }
  const access = (userKey, channelKey, messageIds) => service.getServerChannelMessageMediaAccessV1(
    request(seeded.users[userKey], { serverId: seeded.serverId, channelId: seeded.channels[channelKey], messageIds }),
  );
  const retract = (userKey, target, overrides = {}, verified = true) => service.deleteServerChannelMessageV1(
    request(seeded.users[userKey], {
      serverId: seeded.serverId,
      channelId: target.channelId,
      messageId: target.messageId ?? target.id,
      requestId: randomUUID(),
      ...overrides,
    }, verified),
  );
  const messageDoc = (channelId, messageId) =>
    db.doc(`clubs/${seeded.serverId}/channels/${channelId}/messages/${messageId}`);
  return { ...seeded, clock, storage, service, reserveData, reserve, finalizeData, publish, access, retract, messageDoc };
}

// ------------------------------------------------------------------ contract

test("Server message media: the contract derives one canonical path and binding", () => {
  const path = serverMessageMediaStoragePath({
    serverId: "s1", channelId: "c1", ownerId: "u1",
    messageId: `cm_${"a".repeat(40)}`, contentType: "video/quicktime",
  });
  assert.equal(path, `server_message_media/s1/c1/u1/cm_${"a".repeat(40)}.mov`);
  assert.deepEqual(serverMessageMediaUploadMetadata({
    serverId: "s1", channelId: "c1", ownerId: "u1", messageId: `cm_${"a".repeat(40)}`, type: "video",
  }), {
    yovoiceServerId: "s1",
    yovoiceChannelId: "c1",
    yovoiceOwnerUid: "u1",
    yovoiceMessageId: `cm_${"a".repeat(40)}`,
    yovoiceMessagePath: `clubs/s1/channels/c1/messages/cm_${"a".repeat(40)}`,
    yovoiceMediaType: "video",
  });
  const messageId = `cm_${"b".repeat(40)}`;
  const media = {
    schemaVersion: 1,
    storagePath: `server_message_media/s1/c1/u1/${messageId}.jpg`,
    generation: "7",
    contentType: "image/jpeg",
    size: 500,
    durationSeconds: null,
  };
  const message = { senderId: "u1", type: "image", media };
  assert.equal(canonicalServerMessageMedia(message, { serverId: "s1", channelId: "c1", messageId }).generation, "7");
  for (const forged of [
    { ...message, senderId: "u2" },
    { ...message, type: "video" },
    { ...message, media: { ...media, storagePath: "users/victim/profile/avatar.jpg" } },
    { ...message, media: { ...media, extra: true } },
    { ...message, media: { ...media, size: 100 } },
  ]) {
    assert.throws(() => canonicalServerMessageMedia(forged, { serverId: "s1", channelId: "c1", messageId }),
      (error) => error.code === "data-loss");
  }
  assert.equal(canonicalServerMessageMedia({ senderId: "u1" }, { serverId: "s1", channelId: "c1", messageId }), null);
  assert.equal(SERVER_MESSAGE_MEDIA_ACCESS_TTL_MS <= 90_000, true);
  assert.equal(SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS, 15 * 60_000);
});

// ------------------------------------------------------------------- reserve

emulatorTest("reserve refuses unauthenticated, unverified and malformed requests", async () => {
  const f = await fixture();
  await rejects(f.service.reserveServerChannelMessageMediaV1({ data: f.reserveData() }), "unauthenticated");
  await rejects(f.service.reserveServerChannelMessageMediaV1(request(f.users.member, f.reserveData(), false)),
    "failed-precondition");
  for (const overrides of [
    { contentType: "video/mp4" },
    { contentType: "image/gif" },
    { size: 127 },
    { size: 8 * 1024 * 1024 + 1 },
    { durationSeconds: 3 },
    { type: "voice" },
    { extra: true },
  ]) {
    await rejects(f.reserve("member", "text", "image", overrides), "invalid-argument");
  }
  for (const overrides of [
    { durationSeconds: 0 }, { durationSeconds: 61 }, { durationSeconds: null }, { durationSeconds: 1.5 },
    { size: 1023 }, { size: 64 * 1024 * 1024 + 1 }, { contentType: "image/jpeg" },
  ]) {
    await rejects(f.reserve("member", "text", "video", overrides), "invalid-argument");
  }
  assert.equal((await db.collection(RESERVATIONS).where("serverId", "==", f.serverId).get()).size, 0);
});

emulatorTest("reserve requires the channel write capability: outsiders, banned, departed, guests, muted and announcement members are refused", async () => {
  const f = await fixture();
  for (const userKey of ["outsider", "banned", "guest", "muted"]) {
    await rejects(f.reserve(userKey, "text", "image"), "permission-denied");
  }
  await db.doc(`clubs/${f.serverId}/members/${f.users.second}`).delete();
  await rejects(f.reserve("second", "text", "image"), "permission-denied");
  // Members read announcements and rules but cannot post there.
  await rejects(f.reserve("member", "announcements", "image"), "permission-denied");
  await rejects(f.reserve("member", "rules", "video"), "permission-denied");
  assert.match((await f.reserve("moderator", "announcements", "image")).messageId, /^cm_[a-f0-9]{40}$/u);
  // A voice channel has no thread; a restricted channel needs a current grant.
  await rejects(f.reserve("owner", "voice", "image"), "permission-denied");
  await rejects(f.reserve("stranger", "restricted", "image"), "permission-denied");
  assert.ok((await f.reserve("member", "restricted", "image")).messageId);
});

emulatorTest("reserve issues one exact reservation, lease and budget, and replays idempotently", async () => {
  const f = await fixture();
  const data = f.reserveData("text", "video");
  const reserved = await f.service.reserveServerChannelMessageMediaV1(request(f.users.member, data));
  const path = `server_message_media/${f.serverId}/${f.channels.text}/${f.users.member}/${reserved.messageId}.mp4`;
  assert.deepEqual(reserved, {
    schemaVersion: 1,
    serverId: f.serverId,
    channelId: f.channels.text,
    messageId: reserved.messageId,
    expiresAtMillis: NOW + SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS,
    media: {
      storagePath: path,
      type: "video",
      contentType: "video/mp4",
      size: 65536,
      durationSeconds: 12,
      uploadMetadata: serverMessageMediaUploadMetadata({
        serverId: f.serverId, channelId: f.channels.text, ownerId: f.users.member,
        messageId: reserved.messageId, type: "video",
      }),
    },
  });
  const stored = (await db.doc(`${RESERVATIONS}/${reserved.messageId}`).get()).data();
  assert.deepEqual(Object.keys(stored).sort(), [
    "channelId", "contentType", "createdAt", "durationSeconds", "expiresAt", "kind", "messageId",
    "ownerId", "requestId", "schemaVersion", "serverId", "size", "status", "storagePath", "type",
  ]);
  assert.equal(stored.kind, "serverChannelMessageMedia");
  assert.equal(stored.status, "uploading");
  assert.equal(stored.storagePath, path);
  assert.equal((await db.doc(`${LEASES}/${f.users.member}`).get()).data().messageId, reserved.messageId);
  // Same requestId, same input: the same receipt.
  assert.deepEqual(await f.service.reserveServerChannelMessageMediaV1(request(f.users.member, data)), reserved);
  await rejects(f.service.reserveServerChannelMessageMediaV1(request(f.users.member, { ...data, size: 65537 })),
    "already-exists");
  // One live upload per person at a time.
  await rejects(f.reserve("member", "text", "image"), "resource-exhausted");
  // The lease frees itself at expiry; the daily byte budget does not.
  f.clock.nowMs += SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS + 1;
  const budgetDocs = await db.collection("serverMessageMediaUploadBudgets")
    .where("ownerId", "==", f.users.member).get();
  assert.equal(budgetDocs.size, 1);
  await budgetDocs.docs[0].ref.update({ bytes: SERVER_MESSAGE_MEDIA_DAILY_BYTES - 1000 });
  await rejects(f.reserve("member", "text", "image"), "resource-exhausted");
  // A receipt never outlives access.
  await db.doc(`clubs/${f.serverId}/members/${f.users.member}`).update({ role: "guest" });
  await rejects(f.service.reserveServerChannelMessageMediaV1(request(f.users.member, data)), "permission-denied");
});

emulatorTest("legacy clubs and held servers are refused like a missing server", async () => {
  const f = await fixture();
  const legacyId = `legacy-${randomUUID().slice(0, 8)}`;
  await db.doc(`clubs/${legacyId}`).set({ ownerId: f.users.owner, status: "active" });
  await db.doc(`clubs/${legacyId}/members/${f.users.member}`).set({ userId: f.users.member, role: "member" });
  await db.doc(`clubs/${legacyId}/channels/general`).set({ type: "chat" });
  for (const serverId of [legacyId, "missing-server"]) {
    await rejects(f.service.reserveServerChannelMessageMediaV1(request(f.users.member, {
      ...f.reserveData(), serverId, channelId: "general",
    })), "permission-denied");
  }
  await db.doc(`clubs/${f.serverId}`).update({ serverActivationState: "held", status: "preparing" });
  await rejects(f.reserve("member", "text", "image"), "permission-denied");
});

// ------------------------------------------------------------------ finalize

emulatorTest("finalize publishes the exact message, secures the object, indexes it and replays", async () => {
  const f = await fixture();
  const reserved = await f.reserve("member", "text", "image");
  f.storage.upload(reserved, "301");
  const data = f.finalizeData(reserved);
  const result = await f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, data));
  assert.deepEqual(result, {
    schemaVersion: 1, serverId: f.serverId, channelId: f.channels.text, messageId: reserved.messageId, type: "image",
  });
  const message = (await f.messageDoc(f.channels.text, reserved.messageId).get()).data();
  assert.deepEqual(Object.keys(message).sort(), [
    "channelId", "clubId", "content", "editedAt", "isDeleted", "media", "mediaUrl", "senderId",
    "senderName", "senderPhotoUrl", "sentAt", "type",
  ]);
  assert.equal(message.content, "Photo");
  assert.equal(message.type, "image");
  assert.equal(message.senderName, "Canonical member");
  assert.equal(message.mediaUrl, `gs://${BUCKET}/${reserved.media.storagePath}`);
  assert.deepEqual(message.media, {
    schemaVersion: 1, storagePath: reserved.media.storagePath, generation: "301",
    contentType: "image/jpeg", size: 4096, durationSeconds: null,
  });
  const object = f.storage.objects.get(reserved.media.storagePath);
  assert.equal(object.metadata.firebaseStorageDownloadTokens, undefined, "the download token is revoked");
  assert.equal(object.metadata.yovoiceMessagePath,
    `clubs/${f.serverId}/channels/${f.channels.text}/messages/${reserved.messageId}`);
  assert.equal(object.metadata.yovoiceOwnerUid, f.users.member);
  assert.equal((await db.doc(`${RESERVATIONS}/${reserved.messageId}`).get()).exists, false);
  assert.equal((await db.doc(`${LEASES}/${f.users.member}`).get()).exists, false);
  const index = (await db.doc(`${OBJECTS}/${reserved.messageId}`).get()).data();
  assert.equal(index.ownerId, f.users.member);
  assert.equal(index.generation, "301");
  assert.deepEqual(await f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, data)), result);
});

emulatorTest("finalize trusts the probed video duration and publishes Video", async () => {
  const f = await fixture();
  const reserved = await f.reserve("member", "text", "video");
  f.storage.upload(reserved, "301", { probe: { durationMs: 13_200 } });
  await f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(reserved)));
  const message = (await f.messageDoc(f.channels.text, reserved.messageId).get()).data();
  assert.equal(message.content, "Video");
  assert.equal(message.media.durationSeconds, 14);
});

emulatorTest("a camera clip capped at 60 s that measures just past it publishes as 60 s", async () => {
  const f = await fixture();
  for (const durationMs of [60_000, 60_400, 61_900]) {
    const reserved = await f.reserve("member", "text", "video", { durationSeconds: 60 });
    f.storage.upload(reserved, "301", { probe: { durationMs } });
    await f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(reserved)));
    const message = (await f.messageDoc(f.channels.text, reserved.messageId).get()).data();
    assert.equal(message.media.durationSeconds, 60, `measured ${durationMs} ms`);
    // The canonical read path accepts the clamped value.
    const access = await f.access("member", "text", [reserved.messageId]);
    assert.deepEqual(access.grants.map((grant) => grant.messageId), [reserved.messageId]);
    assert.deepEqual(access.unavailable, []);
  }
  const over = await f.reserve("member", "text", "video", { durationSeconds: 60 });
  f.storage.upload(over, "301", { probe: { durationMs: 62_100 } });
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(over))),
    "failed-precondition", "The uploaded attachment tracks are invalid.");
  assert.equal((await f.messageDoc(f.channels.text, over.messageId).get()).exists, false);
});

emulatorTest("finalize refuses a wrong generation, drifted metadata, mismatched bytes and an unsecured object", async () => {
  const f = await fixture();
  const cases = [
    [{}, { objectGeneration: "302" }, "failed-precondition"],
    [{ metadata: { yovoiceOwnerUid: f.users.second } }, {}, "failed-precondition"],
    [{ metadata: { extra: "x" } }, {}, "failed-precondition"],
    [{ size: 4097 }, {}, "failed-precondition"],
    [{ contentType: "image/png" }, {}, "failed-precondition"],
    [{ probe: { detectedContentType: "image/png" } }, {}, "failed-precondition"],
    [{ probe: { hasVideo: true, hasAudio: false, durationMs: 1000 } }, {}, "failed-precondition"],
  ];
  for (const [upload, finalize, code] of cases) {
    const reserved = await f.reserve("member", "text", "image");
    f.storage.upload(reserved, "301", upload);
    await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member,
      f.finalizeData(reserved, finalize))), code);
    assert.equal((await f.messageDoc(f.channels.text, reserved.messageId).get()).exists, false);
    f.clock.nowMs += SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS + 1;
  }
  // Every clip here is declared 12 s. 61 s is inside the 60 s + 2 s measured
  // grace, so it must be refused by the declared-vs-measured tolerance, and
  // the reason is pinned so a relaxed length cap cannot hide behind it.
  for (const [probe, reason] of [
    [{ hasVideo: false }, "The uploaded attachment tracks are invalid."],
    [{ durationMs: 20_000 }, "The uploaded attachment duration does not match."],
    [{ durationMs: 61_000 }, "The uploaded attachment duration does not match."],
  ]) {
    const reserved = await f.reserve("member", "text", "video");
    f.storage.upload(reserved, "301", { probe });
    await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(reserved))),
      "failed-precondition", reason);
    f.clock.nowMs += SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS + 1;
  }
  // The object is replaced while the probe runs.
  const replaced = await f.reserve("member", "text", "image");
  f.storage.upload(replaced, "301");
  f.storage.onProbe = async (path) => { f.storage.objects.get(path).generation = "999"; };
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(replaced))),
    "failed-precondition");
  f.storage.onProbe = null;
  f.clock.nowMs += SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS + 1;
  // Hardening that fails to revoke the durable token never publishes.
  const unsecured = await f.reserve("member", "text", "image");
  f.storage.upload(unsecured, "301");
  f.storage.keepToken = true;
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(unsecured))),
    "aborted");
  assert.equal((await f.messageDoc(f.channels.text, unsecured.messageId).get()).exists, false);
});

emulatorTest("finalize is the reserver's alone, needs write, a live reservation and an uploaded object", async () => {
  const f = await fixture();
  const reserved = await f.reserve("member", "text", "image");
  f.storage.upload(reserved, "301");
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.second, f.finalizeData(reserved))),
    "failed-precondition");
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, {
    ...f.finalizeData(reserved), messageId: "not-a-message-id",
  })), "invalid-argument");
  // Losing write between reserve and finalize.
  await db.doc(`clubs/${f.serverId}/members/${f.users.member}`).update({ role: "guest" });
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(reserved))),
    "permission-denied");
  await db.doc(`clubs/${f.serverId}/members/${f.users.member}`).update({ role: "member" });
  // Nothing uploaded yet.
  const empty = await f.reserve("second", "text", "image");
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.second, f.finalizeData(empty))),
    "failed-precondition");
  // Expired.
  f.clock.nowMs += SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS + 1;
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(reserved))),
    "deadline-exceeded");
});

// -------------------------------------------------------------------- access

emulatorTest("access grants are batched, generation-bound, at most 90 s, and only for live media", async () => {
  const f = await fixture();
  const first = await f.publish("member", "text", "image");
  f.clock.nowMs += 1;
  const second = await f.publish("second", "text", "video");
  const text = await f.message("text");
  const removed = await f.message("text", { isDeleted: true, content: "", type: "image" });
  const granted = await f.access("guest", "text",
    [first.reserved.messageId, second.reserved.messageId, text.id, removed.id, "cm_missing"]);
  assert.equal(granted.expiresAtMillis - f.clock.nowMs <= 90_000, true);
  assert.deepEqual(granted.grants.map((grant) => grant.messageId).sort(),
    [first.reserved.messageId, second.reserved.messageId].sort());
  assert.deepEqual(granted.unavailable.sort(), [text.id, removed.id, "cm_missing"].sort());
  for (const grant of granted.grants) {
    assert.match(grant.url, /^https:\/\/storage\.googleapis\.com\//u);
    assert.match(grant.url, /generation=301/u);
  }
  const video = granted.grants.find((grant) => grant.type === "video");
  assert.equal(video.durationSeconds, 12);
  for (const messageIds of [[], Array.from({ length: 21 }, (_, index) => `cm_${index}`),
    [first.reserved.messageId, first.reserved.messageId]]) {
    await rejects(f.access("member", "text", messageIds), "invalid-argument");
  }
});

emulatorTest("access re-runs the channel ACL and refuses outsiders, banned, muted and ungranted viewers", async () => {
  const f = await fixture();
  const published = await f.publish("member", "restricted", "image");
  const ids = [published.reserved.messageId];
  for (const userKey of ["outsider", "banned", "stranger", "second"]) {
    await rejects(f.access(userKey, "restricted", ids), "permission-denied");
  }
  assert.equal((await f.access("member", "restricted", ids)).grants.length, 1);
  await db.doc(`restrictions/${f.users.member}`).set({ type: "communicationMute", expiresAt: null });
  await rejects(f.access("member", "restricted", ids), "permission-denied");
  await db.doc(`restrictions/${f.users.member}`).delete();
  // A stale grant after an ACL change.
  await db.doc(`clubs/${f.serverId}/channels/${f.channels.restricted}`).update({ aclRevision: 2 });
  await rejects(f.access("member", "restricted", ids), "permission-denied");
});

emulatorTest("access re-authorizes after signing and applies its own rate limit", async () => {
  const f = await fixture();
  const published = await f.publish("member", "text", "image");
  const ids = [published.reserved.messageId];
  f.storage.onSign = async () => {
    await db.doc(`clubs/${f.serverId}/members/${f.users.second}`).update({ authorizationRevision: 2 });
  };
  await rejects(f.access("second", "text", ids), "aborted");
  f.storage.onSign = null;
  // An object gone from Storage is reported unavailable, never signed.
  f.storage.objects.delete(published.path);
  assert.deepEqual((await f.access("owner", "text", ids)).unavailable, ids);
  const now = Timestamp.fromMillis(f.clock.nowMs);
  await rateLimitReference(db, "server.channel.message.media.access", f.users.moderator).set({
    schemaVersion: 1, ownerId: f.users.moderator, scope: "server.channel.message.media.access",
    windowStartedAt: now, count: 120, updatedAt: now,
  });
  await rejects(f.access("moderator", "text", ids), "resource-exhausted");
});

// -------------------------------------------------------------------- delete

emulatorTest("only the author retracts: moderators, owners and outsiders are refused", async () => {
  const f = await fixture();
  const published = await f.publish("member", "text", "image");
  for (const userKey of ["moderator", "owner", "second", "outsider"]) {
    await rejects(f.retract(userKey, published.reserved), "permission-denied");
  }
  await rejects(f.retract("member", { channelId: f.channels.text, messageId: "cm_missing" }), "not-found");
  const legacyId = `legacy-${randomUUID().slice(0, 8)}`;
  await db.doc(`clubs/${legacyId}`).set({ ownerId: f.users.member, status: "active" });
  await rejects(f.service.deleteServerChannelMessageV1(request(f.users.member, {
    serverId: legacyId, channelId: "general", messageId: "m1", requestId: randomUUID(),
  })), "permission-denied");
  assert.equal((await f.messageDoc(f.channels.text, published.reserved.messageId).get()).data().isDeleted, false);
});

emulatorTest("the author's retraction tombstones the message and removes the object, index and job", async () => {
  const f = await fixture();
  const published = await f.publish("member", "text", "image");
  await f.messageDoc(f.channels.text, published.reserved.messageId).update({
    reactions: { [f.users.second]: "❤️" },
  });
  const requestId = randomUUID();
  const result = await f.retract("member", published.reserved, { requestId });
  assert.deepEqual(result, {
    serverId: f.serverId, channelId: f.channels.text, messageId: published.reserved.messageId,
    deleted: true, alreadyRemoved: false, cleanupPending: false,
  });
  const message = (await f.messageDoc(f.channels.text, published.reserved.messageId).get()).data();
  assert.equal(message.content, "");
  assert.equal(message.isDeleted, true);
  assert.equal(message.deletedBy, f.users.member);
  assert.ok(message.deletedAt);
  assert.ok(message.editedAt);
  for (const field of ["media", "mediaUrl", "reactions", "gif"]) assert.equal(field in message, false, field);
  assert.equal(f.storage.objects.has(published.path), false);
  assert.deepEqual(f.storage.deleted.at(-1), [published.path, "301"]);
  assert.equal((await db.doc(`${DELETION_JOBS}/${objectDeletionJobId(
    f.serverId, f.channels.text, published.reserved.messageId)}`).get()).exists, false);
  assert.equal((await db.doc(`${OBJECTS}/${published.reserved.messageId}`).get()).exists, false);
  // Replay and a second retraction are both harmless.
  assert.equal((await f.retract("member", published.reserved, { requestId })).deleted, true);
  assert.equal((await f.retract("member", published.reserved)).alreadyRemoved, true);
  // Removed media never receives a grant.
  assert.deepEqual((await f.access("member", "text", [published.reserved.messageId])).grants, []);
});

emulatorTest("a Storage failure leaves a durable job that the worker completes", async () => {
  const f = await fixture();
  const published = await f.publish("member", "text", "video");
  f.storage.failDelete.add(published.path);
  const result = await f.retract("member", published.reserved);
  assert.equal(result.cleanupPending, true);
  const jobId = objectDeletionJobId(f.serverId, f.channels.text, published.reserved.messageId);
  const job = (await db.doc(`${DELETION_JOBS}/${jobId}`).get()).data();
  assert.equal(job.target, "object");
  assert.equal(job.generation, "301");
  assert.equal(job.reason, "author");
  f.storage.failDelete.clear();
  const swept = await f.service.processServerChannelMessageMediaDeletionJobs({ limit: 20 });
  assert.ok(swept.completed.includes(jobId));
  assert.equal(f.storage.objects.has(published.path), false);
  assert.equal((await db.doc(`${DELETION_JOBS}/${jobId}`).get()).exists, false);
});

emulatorTest("a muted, unverified or demoted author may still take their own words back", async () => {
  const f = await fixture();
  const muted = await f.message("text", { senderKey: "muted" });
  assert.equal((await f.retract("muted", muted, {}, false)).deleted, true);
  const guest = await f.message("text", { senderKey: "guest", gif: { provider: "yovoice", id: "x" }, type: "gif" });
  assert.equal((await f.retract("guest", guest)).deleted, true);
  const after = (await f.messageDoc(f.channels.text, guest.id).get()).data();
  assert.equal("gif" in after, false);
});

// ------------------------------------------------------------------- workers

emulatorTest("the reservation sweep removes only expired orphans with their lease", async () => {
  const f = await fixture();
  const reserved = await f.reserve("member", "text", "image");
  f.storage.upload(reserved, "301");
  assert.deepEqual((await f.service.expireServerChannelMessageMediaReservations({ limit: 20 })).expired, []);
  assert.equal(f.storage.objects.has(reserved.media.storagePath), true);
  f.clock.nowMs += SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS + 1;
  const swept = await f.service.expireServerChannelMessageMediaReservations({ limit: 20 });
  assert.ok(swept.expired.includes(reserved.messageId));
  assert.equal(f.storage.objects.has(reserved.media.storagePath), false);
  assert.equal((await db.doc(`${RESERVATIONS}/${reserved.messageId}`).get()).exists, false);
  assert.equal((await db.doc(`${LEASES}/${f.users.member}`).get()).exists, false);
  // The expired reservation cannot be finalized afterwards.
  await rejects(f.service.finalizeServerChannelMessageMediaV1(request(f.users.member, f.finalizeData(reserved))),
    "failed-precondition");
});

emulatorTest("a prefix job sweeps page by page, generation-guarded, and ends when the prefix is empty", async () => {
  const f = await fixture();
  const published = await f.publish("member", "text", "image");
  const other = await f.publish("second", "text", "image");
  const outside = `server_message_media/${f.serverId}/${f.channels.rules}/${f.users.owner}/cm_${"c".repeat(40)}.jpg`;
  f.storage.objects.set(outside, { generation: "5", size: 200, contentType: "image/jpeg", metadata: {}, probe: {} });
  const job = prefixDeletionJob({
    serverId: f.serverId, channelId: f.channels.text, reason: "channelDelete", now: Timestamp.fromMillis(NOW),
  });
  await db.doc(`${DELETION_JOBS}/${job.jobId}`).set(job.document);
  assert.equal(job.jobId, prefixDeletionJobId(`server_message_media/${f.serverId}/${f.channels.text}/`));
  const first = await f.service.processObjectDeletionJob(job.jobId);
  assert.equal(first.deleted, false);
  assert.equal(f.storage.objects.has(published.path), false);
  assert.equal(f.storage.objects.has(other.path), false);
  assert.equal(f.storage.objects.has(outside), true, "another channel's object is untouched");
  assert.equal((await db.doc(`${OBJECTS}/${published.reserved.messageId}`).get()).exists, false);
  assert.equal((await db.doc(`${DELETION_JOBS}/${job.jobId}`).get()).exists, true);
  const second = await f.service.processServerChannelMessageMediaDeletionJobs({ limit: 20 });
  assert.ok(second.completed.includes(job.jobId));
  assert.equal((await db.doc(`${DELETION_JOBS}/${job.jobId}`).get()).exists, false);
  // A forged job naming a path outside its own prefix is refused, not run.
  await db.doc(`${DELETION_JOBS}/forged`).set({ ...job.document, jobId: "forged" });
  await rejects(f.service.processObjectDeletionJob("forged"), "data-loss");
  await db.doc(`${DELETION_JOBS}/forged`).delete();
});

// ------------------------------------------------- content cleanup hand-off

async function realServer() {
  const clock = { nowMs: NOW };
  const ownerId = `cleanup-owner-${randomUUID()}`;
  await db.doc(`users/${ownerId}`).set({ displayName: "Cleanup owner", status: "active" });
  const storage = new FakeStorage();
  const dependencies = { db, Timestamp, clock: () => clock.nowMs };
  const livekit = {
    assertSupported() {},
    async revokeParticipant() { return { alreadyAbsent: true, revokedBeforeMillis: clock.nowMs }; },
    async endRoom() { return {}; },
    async roomOccupancy() { return { present: false, participantCount: 0 }; },
  };
  const service = {
    ...createServerChannelService(dependencies),
    ...createServerManagementService(dependencies),
    ...createServerConvergenceRuntimeService({
      ...dependencies,
      livekit,
      familyMemoryStorage: { async listObjects() { return []; }, async deleteObject() {} },
      companyFileStorage: storage,
    }),
    ...createServerMessageMediaService({ ...dependencies, storage, probeMedia: storage.probe() }),
  };
  const created = await createServerCreationService(dependencies).createServerV1(request(ownerId, {
    requestId: randomUUID(), serverType: "community", templateVersion: 1, name: "Cleanup",
    description: "", privacy: "public", defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({ status: "active", serverActivationState: "active" });
  const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
  for (const anchor of anchors.docs) {
    await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: ownerId });
  }
  const channel = await service.createServerChannelV1(request(ownerId, {
    serverId: created.serverId, requestId: randomUUID(), kind: "text", name: "photos",
    categoryId: null, accessMode: "members",
  }));
  async function post() {
    const reserved = await service.reserveServerChannelMessageMediaV1(request(ownerId, {
      serverId: created.serverId, channelId: channel.channelId, type: "image",
      contentType: "image/jpeg", size: 4096, durationSeconds: null, requestId: randomUUID(),
    }));
    storage.upload(reserved, "301");
    await service.finalizeServerChannelMessageMediaV1(request(ownerId, {
      serverId: created.serverId, channelId: channel.channelId, messageId: reserved.messageId,
      objectGeneration: "301", requestId: randomUUID(),
    }));
    clock.nowMs += 20_000;
    return reserved;
  }
  async function drain(kind) {
    const jobs = (await db.collection("serverControlOutbox").where("serverId", "==", created.serverId).get())
      .docs.filter((document) => document.data().kind === kind);
    assert.equal(jobs.length, 1);
    for (let pass = 0; pass < 240; pass += 1) {
      const result = await service.processServerConvergencePage({ operationId: jobs[0].id, pageSize: 2 });
      if (result.cleanupPending === false) return result;
    }
    assert.fail(`${kind} did not settle`);
  }
  return { ...created, ownerId, clock, storage, service, channelId: channel.channelId, post, drain };
}

emulatorTest("channel deletion hands its media prefix to a durable sweep that empties it", async () => {
  const f = await realServer();
  const reserved = await f.post();
  await f.service.deleteServerChannelV1(request(f.ownerId, {
    serverId: f.serverId, channelId: f.channelId, requestId: randomUUID(),
  }));
  await f.drain("channelDelete");
  const jobId = prefixDeletionJobId(`server_message_media/${f.serverId}/${f.channelId}/`);
  const job = (await db.doc(`${DELETION_JOBS}/${jobId}`).get()).data();
  assert.equal(job.target, "prefix");
  assert.equal(job.reason, "channelDelete");
  assert.equal(f.storage.objects.has(reserved.media.storagePath), true, "bytes wait for the worker");
  for (let pass = 0; pass < 3; pass += 1) {
    await f.service.processServerChannelMessageMediaDeletionJobs({ limit: 20 });
  }
  assert.equal(f.storage.objects.has(reserved.media.storagePath), false);
  assert.equal((await db.doc(`${DELETION_JOBS}/${jobId}`).get()).exists, false);
  assert.equal((await db.doc(`${OBJECTS}/${reserved.messageId}`).get()).exists, false);
});

emulatorTest("server deletion enqueues a sweep of the whole server prefix", async () => {
  const f = await realServer();
  const reserved = await f.post();
  await f.service.deleteServerV1(request(f.ownerId, { serverId: f.serverId, requestId: randomUUID() }));
  await f.drain("serverDelete");
  assert.equal((await db.doc(`clubs/${f.serverId}`).get()).exists, false);
  const serverJob = (await db.doc(`${DELETION_JOBS}/${prefixDeletionJobId(
    `server_message_media/${f.serverId}/`)}`).get()).data();
  assert.equal(serverJob.reason, "serverDelete");
  assert.equal(serverJob.channelId, null);
  for (let pass = 0; pass < 4; pass += 1) {
    await f.service.processServerChannelMessageMediaDeletionJobs({ limit: 20 });
  }
  assert.equal(f.storage.objects.has(reserved.media.storagePath), false);
  assert.equal((await db.collection(DELETION_JOBS).where("serverId", "==", f.serverId).get()).size, 0);
});

// ----------------------------------------------------------- account deletion

emulatorTest("account deletion sweeps the author's channel media through the owner index", async () => {
  const f = await fixture();
  const published = await f.publish("member", "text", "image");
  f.clock.nowMs += 20_000;
  const video = await f.publish("member", "restricted", "video");
  const pending = await f.reserve("member", "text", "image");
  f.storage.upload(pending, "44");
  const survivor = await f.publish("second", "text", "image");
  const deletes = [];
  const bucket = {
    name: BUCKET,
    file(path, options) {
      return {
        async delete(settings) {
          deletes.push({ path, generation: options?.generation ?? null, settings });
        },
      };
    },
  };
  const stages = createAccountDeletionStages({
    db, FieldValue, FieldPath,
    authAdmin: { async revokeRefreshTokens() {}, async deleteUser() {} },
    resolveBucket: () => bucket,
    deleteTrustedPrefix: async () => ({ deleted: true }),
    logger: { info() {}, warn() {}, error() {} },
  });
  let cursor = null;
  for (let pass = 0; pass < 10; pass += 1) {
    const outcome = await stages.runStage("storage", { uid: f.users.member, cursor });
    cursor = outcome.cursor;
    if (outcome.done) break;
  }
  assert.equal(cursor, null);
  const byPath = new Map(deletes.map((entry) => [entry.path, entry]));
  assert.equal(byPath.get(published.path).generation, "301");
  assert.equal(byPath.get(published.path).settings.ifGenerationMatch, "301");
  assert.equal(byPath.get(video.path).generation, "301");
  assert.ok(byPath.has(pending.media.storagePath), "an open upload is removed too");
  assert.equal(byPath.has(survivor.path), false, "another author's object is untouched");
  for (const messageId of [published.reserved.messageId, video.reserved.messageId]) {
    assert.equal((await db.doc(`${OBJECTS}/${messageId}`).get()).exists, false);
  }
  assert.equal((await db.doc(`${RESERVATIONS}/${pending.messageId}`).get()).exists, false);
  assert.equal((await db.doc(`${LEASES}/${f.users.member}`).get()).exists, false);
  assert.equal((await db.doc(`${OBJECTS}/${survivor.reserved.messageId}`).get()).exists, true);
  // A malformed index row stops the stage for a retry instead of skipping it.
  await db.doc(`${OBJECTS}/cm_${"d".repeat(40)}`).set({
    ownerId: f.users.member, storagePath: "users/victim/profile/avatar.jpg", generation: "1",
  });
  await assert.rejects(stages.runStage("storage", { uid: f.users.member, cursor: { step: 99 } }),
    (error) => error.code === "storage-cleanup-incomplete");
  await db.doc(`${OBJECTS}/cm_${"d".repeat(40)}`).delete();
});

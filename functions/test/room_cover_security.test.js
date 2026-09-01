const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const {
  createRoomCoverService,
} = require("../rooms/covers");
const { rateLimitReference } = require("../integrity/guards");

const db = getFirestore();
const HOST = "rc-host";
const VIEWER = "rc-viewer";
const OUTSIDER = "rc-outsider";
const ROOM = "rc-room";
let nowMs = 1_900_000_000_000;
let storage;

class FakeStorage {
  constructor() {
    this.bucketName = "test-bucket.firebasestorage.app";
    this.objects = new Map();
    this.revoked = [];
    this.signed = [];
    this.deleted = [];
    this.beforeSignedRead = null;
    this.beforeHarden = null;
    this.beforeMetadata = null;
    this.metadataReads = [];
  }

  put(path, {
    ownerId = HOST,
    roomId = ROOM,
    reservationId,
    generation = "101",
    contentType = "image/jpeg",
    size = 4096,
    token = "durable-token",
  } = {}) {
    this.objects.set(path, {
      generation,
      contentType,
      size: String(size),
      metadata: {
        ownerId,
        roomId,
        ...(reservationId ? { reservationId } : {}),
        ...(token ? { firebaseStorageDownloadTokens: token } : {}),
      },
    });
  }

  async getMetadata(path) {
    this.metadataReads.push(path);
    if (this.beforeMetadata) await this.beforeMetadata();
    const value = this.objects.get(path);
    if (!value) throw new Error(`Missing fake object: ${path}`);
    return value;
  }

  async hardenRoomCoverMetadata(path, metadata, { ownerId, roomId }) {
    if (this.beforeHarden) await this.beforeHarden();
    const current = this.objects.get(path);
    assert.equal(current, metadata);
    current.metadata = { ...current.metadata, ownerId, roomId };
    delete current.metadata.firebaseStorageDownloadTokens;
    this.revoked.push(path);
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
    return `https://storage.googleapis.com/test-bucket/${path}` +
      `?generation=${generation}&sig=short`;
  }

  async deleteObject(path) {
    this.deleted.push(path);
    this.objects.delete(path);
  }
}

function request(uid, data, verified = true) {
  return {
    auth: {
      uid,
      token: { email_verified: verified },
    },
    data,
  };
}

function path(revision = 1) {
  return `room_images/${ROOM}/${HOST}_${revision}.jpg`;
}

function service() {
  return createRoomCoverService({
    db,
    Timestamp,
    storage,
    clock: () => nowMs,
  });
}

async function reserveUpload(instance, requestId = "room-cover-reserve-1") {
  const reserved = await instance.reserveRoomCoverUpload(request(HOST, {
    roomId: ROOM,
    requestId,
    contentType: "image/jpeg",
    size: 4096,
  }));
  storage.put(reserved.storagePath, {
    generation: "202",
    reservationId: reserved.reservationId,
  });
  return reserved;
}

async function clearCollection(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function reset() {
  const reservations = await db
    .collection("roomCoverUploadReservations")
    .where("ownerId", "==", HOST)
    .get();
  const budgets = await db
    .collection("roomCoverUploadBudgets")
    .where("ownerId", "==", HOST)
    .get();
  await Promise.all([
    clearCollection(db.doc(`rooms/${ROOM}`)),
    clearCollection(db.doc("clubs/rc-club")),
    ...[HOST, VIEWER, OUTSIDER].flatMap((uid) => [
      clearCollection(db.doc(`users/${uid}`)),
      db.doc(`restrictions/${uid}`).delete(),
    ]),
    db.doc(`roomCoverUploadLeases/${HOST}`).delete(),
    ...reservations.docs.map((document) => document.ref.delete()),
    ...budgets.docs.map((document) => document.ref.delete()),
  ]);
  for (const first of [HOST, VIEWER, OUTSIDER]) {
    for (const second of [HOST, VIEWER, OUTSIDER]) {
      if (first !== second) {
        await db.doc(`users/${first}/blocked/${second}`).delete();
      }
    }
  }
  const rateLimits = await db
    .collection("privateRateLimits")
    .where("ownerId", "in", [HOST, VIEWER, OUTSIDER])
    .get();
  const operationLedgers = await db.collection("integrityOperationLedgers").get();
  const preflightLedgers = await db.collection("integrityPreflightLedgers").get();
  await Promise.all([
    ...rateLimits.docs.map((doc) => doc.ref.delete()),
    ...[...operationLedgers.docs, ...preflightLedgers.docs]
      .filter((doc) => [HOST, VIEWER, OUTSIDER].includes(doc.data()?.ownerId))
      .map((doc) => doc.ref.delete()),
  ]);
}

async function seedUser(uid, overrides = {}) {
  await db.doc(`users/${uid}`).set({ uid, displayName: uid, ...overrides });
}

async function seedRoom(overrides = {}) {
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "public",
    status: "active",
    deletionInProgress: false,
    imageUrl: null,
    coverStoragePath: path(),
    coverGeneration: "101",
    coverContentType: "image/jpeg",
    coverSize: 4096,
    ...overrides,
  });
}

async function rateCount(scope, uid = HOST) {
  const snapshot = await rateLimitReference(db, scope, uid).get();
  return snapshot.exists ? snapshot.data().count : 0;
}

beforeEach(async () => {
  nowMs = 1_900_000_000_000;
  storage = new FakeStorage();
  await reset();
  await Promise.all([seedUser(HOST), seedUser(VIEWER), seedUser(OUTSIDER)]);
  await seedRoom();
  storage.put(path());
});

after(reset);

test("public cover returns only a short generation-bound grant and revokes token", async () => {
  const result = await service().getRoomCoverMediaAccess(
    request(VIEWER, { roomId: ROOM }),
  );
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.coverGeneration, "101");
  assert.equal(result.expiresAtMillis, nowMs + 90_000);
  assert.deepEqual(storage.revoked, [path()]);
  assert.deepEqual(storage.signed, [{
    path: path(),
    expiresAtMs: nowMs + 90_000,
    generation: "101",
  }]);
});

test("upload reservation is verified, idempotent and limited to one active lease", async () => {
  const instance = service();
  await assert.rejects(
    instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: "reserve-unverified",
      contentType: "image/jpeg",
      size: 4096,
    }, false)),
    (error) => error.code === "failed-precondition",
  );
  const input = request(HOST, {
    roomId: ROOM,
    requestId: "reserve-idempotent",
    contentType: "image/jpeg",
    size: 4096,
  });
  const first = await instance.reserveRoomCoverUpload(input);
  const replay = await instance.reserveRoomCoverUpload(input);
  assert.equal(replay.reservationId, first.reservationId);
  assert.equal(replay.storagePath, first.storagePath);
  assert.equal(replay.replayed, true);
  await assert.rejects(
    instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: "reserve-second-active",
      contentType: "image/jpeg",
      size: 4096,
    })),
    (error) => error.code === "resource-exhausted",
  );

  nowMs += 10 * 60_000 + 1;
  const replacement = await instance.reserveRoomCoverUpload(request(HOST, {
    roomId: ROOM,
    requestId: "reserve-after-expiry",
    contentType: "image/jpeg",
    size: 4096,
  }));
  assert.notEqual(replacement.reservationId, first.reservationId);
});

test("expired upload reservations delete the orphan object and release the lease", async () => {
  const instance = service();
  const reserved = await reserveUpload(instance, "reserve-expiry-cleanup");
  nowMs = reserved.expiresAtMillis + 1;
  const result = await instance.expireRoomCoverUploadReservations({ limit: 10 });
  assert.deepEqual(result.expired, [reserved.reservationId]);
  assert.equal(storage.objects.has(reserved.storagePath), false);
  assert.equal(
    (await db.doc(`roomCoverUploadReservations/${reserved.reservationId}`).get()).exists,
    false,
  );
  assert.equal((await db.doc(`roomCoverUploadLeases/${HOST}`).get()).exists, false);
});

test("reservation quota stops N+1 abandoned allocations", async () => {
  const instance = service();
  for (let index = 0; index < 12; index += 1) {
    const reserved = await instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: `reserve-quota-${index}`,
      contentType: "image/jpeg",
      size: 4096,
    }));
    await Promise.all([
      db.doc(`roomCoverUploadReservations/${reserved.reservationId}`).delete(),
      db.doc(`roomCoverUploadLeases/${HOST}`).delete(),
    ]);
  }
  await assert.rejects(
    instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: "reserve-quota-overflow",
      contentType: "image/jpeg",
      size: 4096,
    })),
    (error) => error.code === "resource-exhausted",
  );
});

test("daily byte budget stops repeated abandoned maximum-size uploads", async () => {
  const instance = service();
  const maximumSize = 8 * 1024 * 1024;
  for (let index = 0; index < 8; index += 1) {
    const reserved = await instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: `reserve-byte-budget-${index}`,
      contentType: "image/jpeg",
      size: maximumSize,
    }));
    await Promise.all([
      db.doc(`roomCoverUploadReservations/${reserved.reservationId}`).delete(),
      db.doc(`roomCoverUploadLeases/${HOST}`).delete(),
    ]);
  }
  await assert.rejects(
    instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: "reserve-byte-budget-overflow",
      contentType: "image/jpeg",
      size: 128,
    })),
    (error) => error.code === "resource-exhausted",
  );
});

test("private access accepts host, roomMember and host-admitted participant but removal denies", async () => {
  await db.doc(`rooms/${ROOM}`).update({ visibility: "private" });
  await service().getRoomCoverMediaAccess(request(HOST, { roomId: ROOM }));

  await db.doc(`rooms/${ROOM}/roomMembers/${VIEWER}`).set({ userId: VIEWER });
  await service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM }));
  await db.doc(`rooms/${ROOM}/roomMembers/${VIEWER}`).delete();
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );

  await db.doc(`rooms/${ROOM}/participants/${VIEWER}`).set({
    userId: VIEWER,
    admittedBy: HOST,
  });
  await service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM }));
  await db.doc(`rooms/${ROOM}/participants/${VIEWER}`).update({
    admittedBy: OUTSIDER,
  });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
});

test("private Club room requires a live canonical unbanned membership", async () => {
  await db.doc(`rooms/${ROOM}`).update({
    visibility: "private",
    clubId: "rc-club",
  });
  await db.doc("clubs/rc-club").set({
    status: "active",
    deletionInProgress: false,
  });
  await db.doc(`clubs/rc-club/members/${VIEWER}`).set({
    userId: VIEWER,
    role: "member",
    banned: false,
  });
  await service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM }));
  await db.doc(`clubs/rc-club/members/${VIEWER}`).update({ role: "guest" });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`clubs/rc-club/members/${VIEWER}`).update({ role: "member" });
  await db.doc(`clubs/rc-club/members/${VIEWER}`).update({ banned: true });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
});

test("inactive, restricted and either block direction fail closed", async () => {
  await db.doc(`users/${VIEWER}`).update({ banned: true });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${VIEWER}`).update({ banned: false });
  await db.doc(`restrictions/${VIEWER}`).set({
    type: "communicationMute",
    expiresAt: Timestamp.fromMillis(nowMs + 60_000),
  });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`restrictions/${VIEWER}`).delete();

  await db.doc(`users/${VIEWER}/blocked/${HOST}`).set({ active: true });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${VIEWER}/blocked/${HOST}`).delete();
  await db.doc(`users/${HOST}/blocked/${VIEWER}`).set({ active: true });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "failed-precondition",
  );
});

test("wrong path, room and generation cannot be used as a confused deputy", async () => {
  await db.doc(`rooms/${ROOM}`).update({
    coverStoragePath: `room_images/other/${HOST}_1.jpg`,
  });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "data-loss",
  );
  await db.doc(`rooms/${ROOM}`).update({
    coverStoragePath: path(),
    coverGeneration: "999",
  });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "failed-precondition",
  );
});

test("public to private during signing aborts the outsider grant and denies the next one", async () => {
  storage.beforeSignedRead = async () => {
    storage.beforeSignedRead = null;
    await db.doc(`rooms/${ROOM}`).update({ visibility: "private" });
  };
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied" || error.code === "aborted",
  );
  assert.equal(storage.signed.length, 1);
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(VIEWER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
});

test("finalize atomically rechecks host account and expected cover tuple", async () => {
  const instance = service();
  const reserved = await reserveUpload(instance);
  const newPath = reserved.storagePath;
  storage.beforeHarden = async () => {
    storage.beforeHarden = null;
    await db.doc(`users/${HOST}`).update({ banned: true });
  };
  await assert.rejects(
    instance.finalizeRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      reservationId: reserved.reservationId,
      objectGeneration: "202",
    })),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).data().coverStoragePath, path());

  await db.doc(`users/${HOST}`).update({ banned: false });
  storage.beforeHarden = async () => {
    storage.beforeHarden = null;
    await db.doc(`rooms/${ROOM}`).update({
      coverStoragePath: path(3),
      coverGeneration: "303",
    });
  };
  await assert.rejects(
    instance.finalizeRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      reservationId: reserved.reservationId,
      objectGeneration: "202",
    })),
    (error) => error.code === "aborted",
  );
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).data().coverStoragePath, path(3));
});

test("finalize cannot resurrect a room deleted at the storage barrier", async () => {
  const instance = service();
  const reserved = await reserveUpload(instance, "room-cover-reserve-delete");
  storage.beforeHarden = async () => {
    storage.beforeHarden = null;
    await clearCollection(db.doc(`rooms/${ROOM}`));
  };
  await assert.rejects(
    instance.finalizeRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      reservationId: reserved.reservationId,
      objectGeneration: "202",
    })),
    (error) => error.code === "not-found",
  );
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).exists, false);
});

test("visibility change atomically refuses a concurrent cover A to B swap", async () => {
  const legacyUrl =
    `https://firebasestorage.googleapis.com/v0/b/${storage.bucketName}` +
    `/o/${encodeURIComponent(path())}?alt=media&token=legacy`;
  await db.doc(`rooms/${ROOM}`).update({
    imageUrl: legacyUrl,
    coverStoragePath: null,
    coverGeneration: null,
    coverContentType: null,
    coverSize: null,
  });
  storage.beforeMetadata = async () => {
    storage.beforeMetadata = null;
    await db.doc(`rooms/${ROOM}`).update({ imageUrl: null });
  };
  await assert.rejects(
    service().setRoomVisibilitySelf(request(HOST, {
      roomId: ROOM,
      visibility: "private",
    })),
    (error) => error.code === "aborted",
  );
  const state = (await db.doc(`rooms/${ROOM}`).get()).data();
  assert.equal(state.visibility, "public");
  assert.equal(state.imageUrl, null);
});

test("room-cover preflights commit denied attempts before target or Storage work", async () => {
  await db.doc(`rooms/${ROOM}`).update({ visibility: "private" });
  await assert.rejects(
    service().getRoomCoverMediaAccess(request(OUTSIDER, { roomId: ROOM })),
    (error) => error.code === "permission-denied",
  );
  assert.equal(await rateCount("roomCover.access", OUTSIDER), 1);
  assert.equal(storage.metadataReads.length, 0);

  await assert.rejects(
    service().reserveRoomCoverUpload(request(HOST, {
      roomId: "missing-room",
      requestId: "denied-room-cover-reserve",
      contentType: "image/jpeg",
      size: 4096,
    })),
    (error) => error.code === "not-found",
  );
  assert.equal(await rateCount("roomCover.reserve"), 1);
  await assert.rejects(
    service().reserveRoomCoverUpload(request(HOST, {
      roomId: "missing-room",
      requestId: "denied-room-cover-reserve",
      contentType: "image/jpeg",
      size: 4097,
    })),
    (error) => error.code === "already-exists",
  );
  assert.equal(await rateCount("roomCover.reserve"), 2);

  const finalizeInput = request(HOST, {
    roomId: ROOM,
    reservationId: "missing-room-cover-reservation",
    objectGeneration: "909",
  });
  await assert.rejects(
    service().finalizeRoomCoverUpload(finalizeInput),
    (error) => error.code === "failed-precondition",
  );
  await assert.rejects(
    service().finalizeRoomCoverUpload(finalizeInput),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(await rateCount("roomCover.update"), 2);
  assert.equal(storage.metadataReads.length, 0);

  const updateRate = rateLimitReference(db, "roomCover.update", HOST);
  await updateRate.set({
    schemaVersion: 1,
    ownerId: HOST,
    scope: "roomCover.update",
    windowStartedAt: Timestamp.fromMillis(nowMs),
    count: 12,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service().setRoomVisibilitySelf(request(HOST, {
      roomId: "another-missing-room",
      visibility: "private",
    })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(storage.metadataReads.length, 0);
});

test("a completed room-cover finalization replays without target or Storage work", async () => {
  const instance = service();
  const reserved = await reserveUpload(instance, "finalize-idempotent-cover");
  const reserveCount = await rateCount("roomCover.reserve");
  await assert.rejects(
    instance.reserveRoomCoverUpload(request(HOST, {
      roomId: ROOM,
      requestId: "finalize-idempotent-cover",
      contentType: "image/jpeg",
      size: 4097,
    })),
    (error) => error.code === "already-exists",
  );
  assert.equal(await rateCount("roomCover.reserve"), reserveCount + 1);
  const input = request(HOST, {
    roomId: ROOM,
    reservationId: reserved.reservationId,
    objectGeneration: "202",
  });
  const first = await instance.finalizeRoomCoverUpload(input);
  assert.equal(await rateCount("roomCover.update"), 1);
  const reads = storage.metadataReads.length;
  await clearCollection(db.doc(`rooms/${ROOM}`));
  const replay = await instance.finalizeRoomCoverUpload(input);
  assert.deepEqual(replay, first);
  assert.equal(await rateCount("roomCover.update"), 1);
  assert.equal(storage.metadataReads.length, reads);
});

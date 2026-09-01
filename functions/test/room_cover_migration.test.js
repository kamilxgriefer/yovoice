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
  createRoomCoverMigrationService,
} = require("../rooms/cover_migration");

const db = getFirestore();
const ROOM = "rcm-room";
const ORPHAN = "rcm-orphan";
const HOST = "rcm-host";
let storage;

class FakeStorage {
  constructor() {
    this.bucketName = "test-bucket.firebasestorage.app";
    this.objects = new Map();
    this.revoked = [];
    this.hardened = [];
    this.pages = [];
  }

  put(path, {
    generation = "100",
    ownerId,
    roomId,
    token = "legacy-token",
    extra = {},
  } = {}) {
    this.objects.set(path, {
      generation,
      contentType: "image/jpeg",
      size: "4096",
      metadata: {
        ...(ownerId ? { ownerId } : {}),
        ...(roomId ? { roomId } : {}),
        ...(token ? { firebaseStorageDownloadTokens: token } : {}),
        ...extra,
      },
    });
  }

  async getMetadata(path) {
    const metadata = this.objects.get(path);
    if (!metadata) throw new Error(`Missing fake object: ${path}`);
    return metadata;
  }

  async revokeDownloadTokens(path) {
    const metadata = this.objects.get(path);
    if (!metadata) throw new Error(`Missing fake object: ${path}`);
    delete metadata.metadata.firebaseStorageDownloadTokens;
    this.revoked.push(path);
    return metadata;
  }

  async hardenRoomCoverMetadata(path, metadata, { ownerId, roomId }) {
    assert.equal(this.objects.get(path), metadata);
    metadata.metadata = { ownerId, roomId };
    this.hardened.push(path);
    return metadata;
  }

  async listObjects({ prefix, pageToken = null, maxResults }) {
    const names = [...this.objects.keys()]
      .filter((name) => name.startsWith(prefix))
      .sort();
    const offset = pageToken === null ? 0 : Number(pageToken);
    const page = names.slice(offset, offset + maxResults);
    const next = offset + page.length < names.length
      ? String(offset + page.length)
      : null;
    this.pages.push({ prefix, pageToken, maxResults, count: page.length });
    return { names: page, nextPageToken: next };
  }
}

function migration() {
  return createRoomCoverMigrationService({
    db,
    FieldPath,
    Timestamp,
    storage,
    clock: () => 1_900_000_000_000,
  });
}

function objectPath(index) {
  return `room_images/${ROOM}/${HOST}_${index}.jpg`;
}

function firebaseUrl(path) {
  return `https://firebasestorage.googleapis.com/v0/b/${storage.bucketName}` +
    `/o/${encodeURIComponent(path)}?alt=media&token=legacy`;
}

async function reset() {
  await Promise.all([
    db.doc(`rooms/${ROOM}`).delete(),
    db.doc(`rooms/${ORPHAN}`).delete(),
  ]);
}

async function scanRoomById(roomId) {
  let cursor = null;
  do {
    const page = await migration().scanRoomCoverMigration({
      cursor,
      limit: 100,
    });
    const room = page.rooms.find((candidate) => candidate.roomId === roomId);
    if (room !== undefined) return room;
    if (!page.hasMore || page.nextCursor === null) return null;
    cursor = page.nextCursor;
  } while (true);
}

beforeEach(async () => {
  storage = new FakeStorage();
  await reset();
});

after(reset);

test("apply sweeps every page before canonicalizing one legacy pointer", async () => {
  const referenced = objectPath(7);
  for (let index = 0; index < 451; index += 1) {
    storage.put(objectPath(index), { generation: String(1000 + index) });
  }
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "private",
    imageUrl: firebaseUrl(referenced),
  });

  const result = await migration().migrateRoomCover({
    roomId: ROOM,
    dryRun: false,
    maxObjects: 1000,
  });
  assert.equal(result.objectsScanned, 451);
  assert.equal(result.tokensFound, 451);
  assert.equal(result.tokensRevoked, 451);
  assert.equal(result.canonicalized, true);
  assert.equal(new Set(storage.revoked).size, 451);
  assert.equal(storage.pages.length, 3);
  assert.deepEqual(storage.hardened, [referenced]);
  const room = (await db.doc(`rooms/${ROOM}`).get()).data();
  assert.equal(room.imageUrl, null);
  assert.equal(room.coverStoragePath, referenced);
  assert.equal(room.coverGeneration, "1007");
});

test("conflicting private pointer still revokes every token and is scrubbed", async () => {
  for (let index = 0; index < 225; index += 1) {
    storage.put(objectPath(index), {
      extra: index === 4 ? { attacker: "metadata-conflict" } : {},
    });
  }
  const wrong = `room_images/${ROOM}/other-host_1.jpg`;
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "private",
    imageUrl: firebaseUrl(wrong),
  });
  const result = await migration().migrateRoomCover({
    roomId: ROOM,
    dryRun: false,
    maxObjects: 1000,
  });
  assert.equal(result.status, "conflicting-pointer");
  assert.equal(result.canonicalized, false);
  assert.equal(result.tokensRevoked, 225);
  assert.equal(new Set(storage.revoked).size, 225);
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).data().imageUrl, null);
});

test("public legacy cover is canonicalized before its durable token is revoked", async () => {
  const referenced = objectPath(9);
  storage.put(referenced, { generation: "909" });
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "public",
    imageUrl: firebaseUrl(referenced),
  });

  const scannedRoom = await scanRoomById(ROOM);
  assert.notEqual(scannedRoom, null);
  assert.equal(scannedRoom.needsMigration, true);
  const result = await migration().migrateRoomCover({
    roomId: ROOM,
    dryRun: false,
  });
  assert.equal(result.canonicalized, true);
  assert.equal(result.tokensRevoked, 1);
  const room = (await db.doc(`rooms/${ROOM}`).get()).data();
  assert.equal(room.imageUrl, null);
  assert.equal(room.coverStoragePath, referenced);
  assert.equal(room.coverGeneration, "909");
});

test("dry run is read-only across Firestore and every object token", async () => {
  const referenced = objectPath(1);
  storage.put(referenced);
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "private",
    imageUrl: firebaseUrl(referenced),
  });
  const result = await migration().migrateRoomCover({
    roomId: ROOM,
    dryRun: true,
  });
  assert.equal(result.tokensFound, 1);
  assert.equal(result.tokensRevoked, 0);
  assert.equal(storage.revoked.length, 0);
  assert.equal(storage.hardened.length, 0);
  assert.equal(
    (await db.doc(`rooms/${ROOM}`).get()).data().imageUrl,
    firebaseUrl(referenced),
  );
  assert.equal(
    storage.objects.get(referenced).metadata.firebaseStorageDownloadTokens,
    "legacy-token",
  );
});

test("global inventory identifies orphan and superseded objects and revokes without delete", async () => {
  const referenced = objectPath(1);
  const superseded = objectPath(2);
  const orphan = `room_images/${ORPHAN}/${HOST}_3.jpg`;
  storage.put(referenced);
  storage.put(superseded);
  storage.put(orphan);
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "public",
    imageUrl: null,
    coverStoragePath: referenced,
    coverGeneration: "100",
    coverContentType: "image/jpeg",
    coverSize: 4096,
  });
  const result = await migration().scanRoomCoverObjectInventory({
    dryRun: false,
    maxResults: 10,
  });
  assert.equal(result.tokensRevoked, 3);
  assert.equal(result.entries.find((entry) => entry.path === referenced).orphan, false);
  assert.equal(result.entries.find((entry) => entry.path === superseded).orphan, true);
  assert.equal(result.entries.find((entry) => entry.path === orphan).orphan, true);
  assert.equal(storage.objects.size, 3);
});

test("migration is fail-closed if room changes after object hardening", async () => {
  const referenced = objectPath(1);
  storage.put(referenced);
  await db.doc(`rooms/${ROOM}`).set({
    hostId: HOST,
    visibility: "private",
    imageUrl: firebaseUrl(referenced),
  });
  const originalHarden = storage.hardenRoomCoverMetadata.bind(storage);
  storage.hardenRoomCoverMetadata = async (...args) => {
    const result = await originalHarden(...args);
    await db.doc(`rooms/${ROOM}`).update({ imageUrl: null });
    return result;
  };
  await assert.rejects(
    migration().migrateRoomCover({ roomId: ROOM, dryRun: false }),
    (error) => error.code === "aborted",
  );
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).data().imageUrl, null);
  assert.equal(storage.revoked.includes(referenced), true);
});

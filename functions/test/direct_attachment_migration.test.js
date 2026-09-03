const assert = require("node:assert/strict");
const { beforeEach, test } = require("node:test");

const {
  canonicalPairKey,
  directMediaMessageId,
} = require("../messaging/direct_integrity");
const { operationIdentity } = require("../integrity/guards");
const {
  createDirectAttachmentMigrationService,
  parseDirectAttachmentPath,
} = require("../messaging/direct_attachment_migration");
const {
  EXPECTED_STORAGE_BUCKET,
  assertProject,
  parseArgs,
  runMigration,
} = require("../scripts/migrate_direct_attachment_markers");

const A = "legacy-dm-alice";
const B = "legacy-dm-bob";
const CONVERSATION = "dm_legacy_marker_test";
const RESERVE_REQUEST_ID = "legacy-reserve-request-0001";
const FINALIZE_REQUEST_ID = "legacy-finalize-request-0001";
const MESSAGE = directMediaMessageId(A, CONVERSATION, RESERVE_REQUEST_ID);
const PATH = `message_attachments/${A}/${CONVERSATION}/${MESSAGE}.jpg`;
const BUCKET = "legacy-test.firebasestorage.app";
const NOW = new Date("2026-09-02T10:00:00.000Z");

function clone(value) {
  return structuredClone(value);
}

class FakeSnapshot {
  constructor(path, data) {
    this.id = path.split("/").at(-1);
    this.exists = data !== undefined;
    this._data = data;
  }

  data() {
    return this.exists ? clone(this._data) : undefined;
  }
}

class FakeDocumentReference {
  constructor(database, path) {
    this.database = database;
    this.path = path;
    this.id = path.split("/").at(-1);
  }

  async get() {
    return new FakeSnapshot(this.path, this.database.documents.get(this.path));
  }

  async set(value) {
    this.database.documents.set(this.path, clone(value));
  }

  async delete() {
    this.database.documents.delete(this.path);
  }

  collection(name) {
    return {
      doc: (id) => new FakeDocumentReference(
        this.database,
        `${this.path}/${name}/${id}`,
      ),
    };
  }
}

class FakeDb {
  constructor() {
    this.documents = new Map();
  }

  doc(path) {
    return new FakeDocumentReference(this, path);
  }

  collection(name) {
    const conditions = [];
    const query = {
      where: (field, operator, expected) => {
        assert.equal(operator, "==");
        assert.ok(["kind", "result.messageId"].includes(field));
        conditions.push({ field, expected });
        return query;
      },
      limit: (limit) => ({
        get: async () => {
          const prefix = `${name}/`;
          const read = (value, field) => field.split(".").reduce(
            (current, segment) => current?.[segment],
            value,
          );
          const docs = [...this.documents.entries()]
            .filter(([path, value]) =>
              path.startsWith(prefix) &&
              !path.slice(prefix.length).includes("/") &&
              conditions.every(({ field, expected }) =>
                read(value, field) === expected))
            .slice(0, limit)
            .map(([path, value]) => new FakeSnapshot(path, value));
          return { docs, size: docs.length };
        },
      }),
    };
    return query;
  }
}

class FakeStorage {
  constructor() {
    this.objects = new Map();
    this.metadataWrites = [];
  }

  put(path, value) {
    this.objects.set(path, clone(value));
  }

  async getMetadata(path) {
    const value = this.objects.get(path);
    if (value === undefined) {
      throw Object.assign(new Error("Missing fake object"), {
        code: "storage/object-not-found",
      });
    }
    return clone(value);
  }

  getObjectReference(path) {
    return `gs://${BUCKET}/${path}`;
  }

  async listObjects({ prefix, pageToken = null, maxResults }) {
    const names = [...this.objects.keys()]
      .filter((path) => path.startsWith(prefix))
      .sort();
    const offset = pageToken === null ? 0 : Number(pageToken);
    const page = names.slice(offset, offset + maxResults);
    return {
      names: page,
      nextPageToken: offset + page.length < names.length
        ? String(offset + page.length)
        : null,
    };
  }

  async revokeDownloadTokens(path, observed, { requiredMetadata = {} } = {}) {
    const current = this.objects.get(path);
    if (current === undefined) throw new Error("Missing fake object");
    assert.equal(String(current.generation), String(observed.generation));
    const updated = clone(current);
    updated.metadata = {
      ...updated.metadata,
      ...requiredMetadata,
    };
    delete updated.metadata.firebaseStorageDownloadTokens;
    this.objects.set(path, updated);
    this.metadataWrites.push({
      path,
      generation: String(observed.generation),
      requiredMetadata: clone(requiredMetadata),
    });
    return clone(updated);
  }
}

function conversationRoot() {
  const participants = [A, B].sort();
  return {
    archivedBy: [],
    createdAt: NOW,
    lastMessage: "Photo",
    lastMessageId: MESSAGE,
    lastMessageSenderId: A,
    lastMessageSequence: 1,
    lastMessageType: "image",
    mutedBy: [],
    pairKey: canonicalPairKey(...participants),
    participantEmails: { [participants[0]]: "", [participants[1]]: "" },
    participantIds: participants,
    participantNames: { [participants[0]]: "A", [participants[1]]: "B" },
    participantPhotoUrls: {
      [participants[0]]: `https://profiles.invalid/${participants[0]}.jpg`,
      [participants[1]]: `https://profiles.invalid/${participants[1]}.jpg`,
    },
    readSequences: { [participants[0]]: 1, [participants[1]]: 0 },
    schemaVersion: 2,
    typing: {
      [participants[0]]: { isTyping: false, updatedAt: NOW },
      [participants[1]]: { isTyping: false, updatedAt: NOW },
    },
    unreadCounts: { [participants[0]]: 0, [participants[1]]: 1 },
    updatedAt: NOW,
  };
}

function pairGuard() {
  const participants = [A, B].sort();
  return {
    conversationId: CONVERSATION,
    createdAt: NOW,
    pairKey: canonicalPairKey(...participants),
    participantIds: participants,
    schemaVersion: 1,
  };
}

function message() {
  return {
    schemaVersion: 2,
    sequence: 1,
    conversationId: CONVERSATION,
    senderId: A,
    type: "image",
    content: "",
    mediaUrl: `gs://${BUCKET}/${PATH}`,
    durationSeconds: null,
    sentAt: NOW,
    readBy: [A],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  };
}

function legacyMetadata({ generation = "101", token = "legacy-token" } = {}) {
  return {
    generation,
    size: "2048",
    contentType: "image/jpeg",
    metadata: {
      yovoiceConversationId: CONVERSATION,
      yovoiceMessageId: MESSAGE,
      yovoiceMessagePath:
        `conversations/${CONVERSATION}/messages/${MESSAGE}`,
      yovoiceMediaType: "image",
      yovoiceOwnerUid: A,
      ...(token === null ? {} : { firebaseStorageDownloadTokens: token }),
    },
  };
}

function matchingProbe(overrides = {}) {
  return async ({ generation, size }) => ({
    detectedContentType: "image/jpeg",
    durationMs: null,
    generation,
    hasAudio: false,
    hasVideo: false,
    size,
    ...overrides,
  });
}

let db;
let storage;

function seedCanonicalMessage() {
  const participants = [A, B].sort();
  db.documents.set(`conversations/${CONVERSATION}`, conversationRoot());
  db.documents.set(
    `directConversationPairs/${canonicalPairKey(...participants)}`,
    pairGuard(),
  );
  db.documents.set(
    `conversations/${CONVERSATION}/messages/${MESSAGE}`,
    message(),
  );
  const reserveInput = {
    contentType: "image/jpeg",
    conversationId: CONVERSATION,
    durationSeconds: null,
    recipientId: B,
    type: "image",
  };
  const reserveIdentity = operationIdentity(
    "direct.attachment.reserve",
    A,
    RESERVE_REQUEST_ID,
    reserveInput,
  );
  db.documents.set(`integrityOperationLedgers/${reserveIdentity.id}`, {
    schemaVersion: 1,
    kind: "direct.attachment.reserve",
    ownerId: A,
    requestId: RESERVE_REQUEST_ID,
    inputHash: reserveIdentity.inputHash,
    result: {
      conversationId: CONVERSATION,
      messageId: MESSAGE,
      storagePath: PATH,
      type: "image",
      expiresAtMillis: NOW.getTime() + 5 * 60 * 1000,
      maxBytes: 12 * 1024 * 1024,
      created: true,
    },
    createdAt: NOW,
  });
  const finalizeInput = {
    conversationId: CONVERSATION,
    messageId: MESSAGE,
    objectGeneration: "101",
  };
  const finalizeIdentity = operationIdentity(
    "direct.attachment.finalize",
    A,
    FINALIZE_REQUEST_ID,
    finalizeInput,
  );
  db.documents.set(`integrityOperationLedgers/${finalizeIdentity.id}`, {
    schemaVersion: 1,
    kind: "direct.attachment.finalize",
    ownerId: A,
    requestId: FINALIZE_REQUEST_ID,
    inputHash: finalizeIdentity.inputHash,
    result: {
      conversationId: CONVERSATION,
      messageId: MESSAGE,
      recipientId: B,
      type: "image",
      mediaSize: 2048,
      created: true,
    },
    createdAt: NOW,
  });
  return finalizeIdentity.id;
}

function migration(options = {}) {
  return createDirectAttachmentMigrationService({
    db,
    storage,
    mediaProbe: matchingProbe(),
    ...options,
  });
}

beforeEach(() => {
  db = new FakeDb();
  storage = new FakeStorage();
});

test("legacy path grammar is closed before any object is trusted", () => {
  assert.deepEqual(parseDirectAttachmentPath(PATH), {
    ownerId: A,
    conversationId: CONVERSATION,
    messageId: MESSAGE,
  });
  for (const path of [
    `${PATH}/extra`,
    PATH.replace(".jpg", ".exe"),
    PATH.replace(MESSAGE, `${MESSAGE}suffix`),
    PATH.replace("message_attachments", "voice_moments"),
    `message_attachments/${A}//${MESSAGE}.jpg`,
  ]) {
    assert.equal(parseDirectAttachmentPath(path), null, path);
  }
});

test("dry-run is read-only, apply hardens one Build 18 object, replay is a no-op", async () => {
  assert.notEqual(RESERVE_REQUEST_ID, FINALIZE_REQUEST_ID);
  seedCanonicalMessage();
  storage.put(PATH, legacyMetadata());

  const dry = await migration().migrateDirectAttachmentPage({ dryRun: true });
  assert.deepEqual(
    {
      scanned: dry.objectsScanned,
      eligible: dry.eligible,
      found: dry.tokensFound,
      revoked: dry.tokensRevoked,
    },
    { scanned: 1, eligible: 1, found: 1, revoked: 0 },
  );
  assert.equal(storage.metadataWrites.length, 0);
  assert.equal(
    storage.objects.get(PATH).metadata.firebaseStorageDownloadTokens,
    "legacy-token",
  );

  const applied = await migration().migrateDirectAttachmentPage({
    dryRun: false,
  });
  assert.equal(applied.finalized, 1);
  assert.equal(applied.tokensFound, 1);
  assert.equal(applied.tokensRevoked, 1);
  assert.equal(
    storage.objects.get(PATH).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
  assert.equal(storage.objects.get(PATH).metadata.yovoiceFinalized, "true");
  assert.deepEqual(storage.metadataWrites.map((write) => write.generation), [
    "101",
    "101",
  ]);
  assert.deepEqual(storage.metadataWrites[1].requiredMetadata, {
    yovoiceFinalized: "true",
  });

  const replay = await migration().migrateDirectAttachmentPage({ dryRun: false });
  assert.equal(replay.alreadyFinalized, 1);
  assert.equal(storage.metadataWrites.length, 2);
});

test("legacy finalize ledger must bind the exact generation input hash", async () => {
  const ledgerId = seedCanonicalMessage();
  const ledgerPath = `integrityOperationLedgers/${ledgerId}`;
  const ledger = db.documents.get(ledgerPath);
  ledger.inputHash = operationIdentity(
    "direct.attachment.finalize",
    A,
    FINALIZE_REQUEST_ID,
    {},
  ).inputHash;
  db.documents.set(ledgerPath, ledger);
  storage.put(PATH, legacyMetadata());

  const result = await migration().migrateDirectAttachmentPage({
    dryRun: false,
  });
  assert.equal(result.invalid, 1);
  assert.equal(result.tokensRevoked, 1);
  assert.equal(storage.objects.get(PATH).metadata.yovoiceFinalized, undefined);
});

test("orphan and forged legacy objects lose bearer tokens but never gain trust", async () => {
  storage.put(PATH, legacyMetadata());
  const forgedPath = `message_attachments/${A}/${CONVERSATION}/m_${"b".repeat(40)}.jpg`;
  const forged = legacyMetadata();
  forged.metadata.yovoiceMessageId = `m_${"b".repeat(40)}`;
  forged.metadata.yovoiceMessagePath =
    `conversations/${CONVERSATION}/messages/${forged.metadata.yovoiceMessageId}`;
  storage.put(forgedPath, forged);

  const result = await migration().migrateDirectAttachmentPage({ dryRun: false });
  assert.equal(result.invalid, 2);
  assert.equal(result.tokensFound, 2);
  assert.equal(result.tokensRevoked, 2);
  for (const value of storage.objects.values()) {
    assert.equal(value.metadata.firebaseStorageDownloadTokens, undefined);
    assert.equal(value.metadata.yovoiceFinalized, undefined);
  }
});

test("trusted probe rejection revokes the token and leaves playback denied", async () => {
  seedCanonicalMessage();
  storage.put(PATH, legacyMetadata());
  const result = await migration({
    mediaProbe: matchingProbe({ detectedContentType: "image/png" }),
  }).migrateDirectAttachmentPage({ dryRun: false });
  assert.equal(result.invalid, 1);
  assert.equal(result.tokensRevoked, 1);
  assert.equal(storage.objects.get(PATH).metadata.yovoiceFinalized, undefined);
});

test("a canonical message without its atomic Build 18 finalize ledger is not trusted", async () => {
  seedCanonicalMessage();
  for (const key of [...db.documents.keys()]) {
    if (key.startsWith("integrityOperationLedgers/")) db.documents.delete(key);
  }
  storage.put(PATH, legacyMetadata());
  const result = await migration().migrateDirectAttachmentPage({ dryRun: false });
  assert.equal(result.invalid, 1);
  assert.equal(result.tokensRevoked, 1);
  assert.equal(storage.objects.get(PATH).metadata.yovoiceFinalized, undefined);
});

test("message deletion between probe and marker fails closed", async () => {
  seedCanonicalMessage();
  storage.put(PATH, legacyMetadata());
  const result = await migration({
    beforeFinalize: async () => {
      db.documents.delete(
        `conversations/${CONVERSATION}/messages/${MESSAGE}`,
      );
    },
  }).migrateDirectAttachmentPage({ dryRun: false });
  assert.equal(result.raced, 1);
  assert.equal(result.tokensRevoked, 1);
  assert.equal(storage.objects.get(PATH).metadata.yovoiceFinalized, undefined);
});

test("a replacement generation is never blessed by the prior probe", async () => {
  seedCanonicalMessage();
  storage.put(PATH, legacyMetadata());
  const result = await migration({
    beforeFinalize: async () => {
      storage.put(PATH, legacyMetadata({
        generation: "202",
        token: "replacement-token",
      }));
    },
  }).migrateDirectAttachmentPage({ dryRun: false });
  assert.equal(result.raced, 1);
  assert.equal(storage.objects.get(PATH).generation, "202");
  assert.equal(
    storage.objects.get(PATH).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
  assert.equal(storage.objects.get(PATH).metadata.yovoiceFinalized, undefined);
  assert.deepEqual(storage.metadataWrites.map((write) => write.generation), [
    "101",
    "202",
  ]);
});

test("operator wrapper is bounded, resumable and aggregate-only", async () => {
  const stateDb = new FakeDb();
  const calls = [];
  const pages = [
    {
      dryRun: false,
      objectsScanned: 2,
      eligible: 0,
      finalized: 1,
      alreadyFinalized: 0,
      invalid: 1,
      missing: 0,
      raced: 0,
      tokensFound: 2,
      tokensRevoked: 2,
      hasMore: true,
      nextPageToken: "opaque-next",
    },
    {
      dryRun: false,
      objectsScanned: 1,
      eligible: 0,
      finalized: 1,
      alreadyFinalized: 0,
      invalid: 0,
      missing: 0,
      raced: 0,
      tokensFound: 0,
      tokensRevoked: 0,
      hasMore: false,
      nextPageToken: null,
    },
  ];
  const result = await runMigration({
    db: stateDb,
    migration: {
      async migrateDirectAttachmentPage(input) {
        calls.push(input);
        return pages.shift();
      },
    },
    FieldValue: { serverTimestamp: () => "server-time" },
    args: {
      apply: true,
      restart: false,
      maxObjects: 3,
      pageSize: 2,
    },
  });
  assert.equal(result.objectsScanned, 3);
  assert.equal(result.finalized, 2);
  assert.equal(result.invalid, 1);
  assert.equal(result.tokensRevoked, 2);
  assert.equal(result.reachedEnd, true);
  assert.equal(result.continuationStored, false);
  assert.deepEqual(calls, [
    { pageToken: null, maxResults: 2, dryRun: false },
    { pageToken: "opaque-next", maxResults: 1, dryRun: false },
  ]);
  assert.equal(
    stateDb.documents.has(
      "privateMigrationState/directAttachmentMarkerBackfill",
    ),
    false,
  );
  assert.equal(JSON.stringify(result).includes("opaque-next"), false);
  assert.equal(JSON.stringify(result).includes(A), false);
});

test("a changing inventory with missing objects cannot open the release gate", async () => {
  const result = await runMigration({
    db: new FakeDb(),
    migration: {
      async migrateDirectAttachmentPage() {
        return {
          dryRun: true,
          objectsScanned: 1,
          eligible: 0,
          finalized: 0,
          alreadyFinalized: 0,
          invalid: 0,
          missing: 1,
          raced: 0,
          tokensFound: 0,
          tokensRevoked: 0,
          hasMore: false,
          nextPageToken: null,
        };
      },
    },
    FieldValue: { serverTimestamp: () => "server-time" },
    args: {
      apply: false,
      restart: false,
      maxObjects: 1,
      pageSize: 1,
      startPageToken: null,
    },
  });
  assert.equal(result.reachedEnd, true);
  assert.equal(result.missing, 1);
  assert.equal(result.releaseReady, false);
});

test("tail-only or invalid inventories cannot open the release gate", async () => {
  for (const scenario of [
    { invalid: 0, startPageToken: "opaque-tail" },
    { invalid: 1, startPageToken: null },
  ]) {
    const result = await runMigration({
      db: new FakeDb(),
      migration: {
        async migrateDirectAttachmentPage() {
          return {
            dryRun: true,
            objectsScanned: 1,
            eligible: 0,
            finalized: 0,
            alreadyFinalized: 0,
            invalid: scenario.invalid,
            missing: 0,
            raced: 0,
            tokensFound: 0,
            tokensRevoked: 0,
            hasMore: false,
            nextPageToken: null,
          };
        },
      },
      FieldValue: { serverTimestamp: () => "server-time" },
      args: {
        apply: false,
        restart: false,
        maxObjects: 1,
        pageSize: 1,
        startPageToken: scenario.startPageToken,
      },
    });
    assert.equal(result.reachedEnd, true);
    assert.equal(result.releaseReady, false);
  }
});

test("operator arguments pin project and refuse ambiguous restart", () => {
  assert.equal(EXPECTED_STORAGE_BUCKET, "yovoice-ec54a.firebasestorage.app");
  assert.deepEqual(
    parseArgs(["--project", "yovoice-ec54a", "--max-objects", "7"]),
    {
      apply: false,
      restart: false,
      maintenanceWindowConfirmed: false,
      project: "yovoice-ec54a",
      maxObjects: 7,
      pageSize: 25,
      startPageToken: null,
    },
  );
  assert.throws(() => parseArgs(["--restart"]), /only with --apply/u);
  assert.throws(
    () => parseArgs(["--project", "yovoice-ec54a", "--apply"]),
    /maintenance-window-confirmed/u,
  );
  assert.throws(
    () => assertProject({ project: "other" }, null),
    /must be exactly/u,
  );
  assert.throws(
    () => assertProject({ project: "yovoice-ec54a" }, "other"),
    /does not match/u,
  );
});

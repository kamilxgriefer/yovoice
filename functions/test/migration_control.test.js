const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  createMigrationControl,
} = require("../integrity/migration_control");

const db = getFirestore();
const OWNER = "migration owner-Ż";
let nowMs = 1_920_000_000_000;

function request(data, uid = OWNER) {
  return { auth: { uid, token: { role: "superAdmin" } }, data };
}

async function deleteQuery(query) {
  const snapshot = await query.get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}

async function reset() {
  await Promise.all([
    deleteQuery(
      db.collection("integrityMigrationOperations").where("ownerId", "==", OWNER),
    ),
    deleteQuery(
      db.collection("privateRateLimits").where("ownerId", "==", OWNER),
    ),
  ]);
}

function control({ direct = {}, moments = {}, authorize, limits } = {}) {
  return createMigrationControl({
    db,
    Timestamp,
    clock: () => nowMs,
    authorize: authorize ?? (async (input) => ({ uid: input.auth?.uid })),
    limits,
    directMigration: {
      migrateDirectConversation: async (input) => ({ ...input, status: "migrated" }),
      scanDirectConversationMigration: async (input) => ({ ...input, results: [] }),
      ...direct,
    },
    momentMigration: {
      migrateMoment: async (input) => ({ ...input, status: "migrated" }),
      scanMomentMigration: async (input) => ({ ...input, results: [] }),
      ...moments,
    },
  });
}

beforeEach(async () => {
  nowMs = 1_920_000_000_000;
  await reset();
});
after(reset);

test("migration requestId is Auth-bound, replay-safe and payload-bound", async () => {
  let calls = 0;
  const handlers = control({
    direct: {
      async migrateDirectConversation(input) {
        calls += 1;
        return { ...input, status: "migrated" };
      },
    },
  });
  const input = request({
    conversationId: "dm_migration",
    dryRun: false,
    requestId: "migration-0001",
  });
  const first = await handlers.migrateDirectConversation(input);
  const replay = await handlers.migrateDirectConversation(input);
  assert.deepEqual(replay, first);
  assert.equal(calls, 1);

  await assert.rejects(
    handlers.migrateDirectConversation(request({
      ...input.data,
      maxMessages: 10,
    })),
    (error) => error.code === "already-exists",
  );
  assert.equal(calls, 1);

  const mismatched = control({
    authorize: async () => ({ uid: "different owner" }),
  });
  await assert.rejects(
    mismatched.scanDirectMigration(request({ requestId: "migration-auth1" })),
    (error) => error.code === "permission-denied",
  );
});

test("a concurrent duplicate cannot run while the first lease is active", async () => {
  let release;
  let started;
  const startedPromise = new Promise((resolve) => {
    started = resolve;
  });
  const workPromise = new Promise((resolve) => {
    release = resolve;
  });
  let calls = 0;
  const handlers = control({
    direct: {
      async migrateDirectConversation(input) {
        calls += 1;
        started();
        await workPromise;
        return { ...input, status: "migrated" };
      },
    },
  });
  const input = request({
    conversationId: "dm_concurrent",
    dryRun: false,
    requestId: "migration-race1",
  });
  const first = handlers.migrateDirectConversation(input);
  await startedPromise;
  await assert.rejects(
    handlers.migrateDirectConversation(input),
    (error) => error.code === "aborted",
  );
  release();
  const result = await first;
  assert.equal(result.status, "migrated");
  assert.deepEqual(await handlers.migrateDirectConversation(input), result);
  assert.equal(calls, 1);
});

test("failed work can retry safely under a new ledger attempt", async () => {
  let calls = 0;
  const handlers = control({
    moments: {
      async migrateMoment(input) {
        calls += 1;
        if (calls === 1) {
          const error = new Error("simulated transient failure");
          error.code = "aborted";
          throw error;
        }
        return { ...input, status: "migrated" };
      },
    },
  });
  const input = request({
    momentId: "0123456789abcdefghij",
    dryRun: false,
    requestId: "migration-retry",
  });
  await assert.rejects(
    handlers.migrateMoment(input),
    (error) => error.code === "aborted",
  );
  assert.equal((await handlers.migrateMoment(input)).status, "migrated");
  assert.equal(calls, 2);
});

test("server-time migration quota stops distinct requestId scan bursts", async () => {
  let calls = 0;
  const handlers = control({
    direct: {
      async scanDirectConversationMigration(input) {
        calls += 1;
        return { ...input, results: [] };
      },
    },
    limits: {
      scan: { maxEvents: 2, windowMs: 1_000 },
      apply: { maxEvents: 2, windowMs: 1_000 },
    },
  });
  await handlers.scanDirectMigration(request({ requestId: "migration-scan1" }));
  await handlers.scanDirectMigration(request({ requestId: "migration-scan2" }));
  await assert.rejects(
    handlers.scanDirectMigration(request({ requestId: "migration-scan3" })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(calls, 2);
  nowMs += 1_001;
  await handlers.scanDirectMigration(request({ requestId: "migration-scan4" }));
  assert.equal(calls, 3);
});

test("migration endpoints authenticate before exposing input validation", async () => {
  const handlers = control();
  await assert.rejects(
    handlers.migrateMoment({ auth: null, data: { unexpected: true } }),
    (error) => error.code === "permission-denied",
  );
});

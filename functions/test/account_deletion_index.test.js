/**
 * ADR-198 shape, applied to the account-deletion retry sweep.
 *
 * `processReadyAccountDeletionOutbox` runs two composite queries every two
 * minutes:
 *
 *   accountDeletionOutbox where status == "pending"    && nextAttemptAt <= now
 *   accountDeletionOutbox where status == "processing" && leaseUntil    <= now
 *
 * Both are equality + inequality on DIFFERENT fields, which Firestore serves
 * only from a hand-declared composite index. The emulator does NOT enforce
 * index requirements (docs/TESTING.md), so an emulator run alone can never
 * reproduce the production FAILED_PRECONDITION that RC-13 taught this project
 * to test for. Both halves below are required and neither is sufficient alone:
 *
 *   1. the declaration test asserts firestore.indexes.json carries the two
 *      composites the deployed queries need — what the emulator cannot check;
 *   2. the emulator tests run the REAL queries, and the real sweep, against the
 *      emulator with that same index file loaded — what a declaration test
 *      cannot check.
 *
 * A deleted account's sweep row failing to be picked up is not a cosmetic
 * defect: it is a user who asked to be erased and was not.
 */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
process.env.GCLOUD_PROJECT ||= "demo-yovoice-account-deletion-index";

const { getApps, initializeApp, deleteApp } = require("firebase-admin/app");
if (getApps().length === 0) {
  initializeApp({ projectId: process.env.GCLOUD_PROJECT });
}
const { Timestamp } = require("firebase-admin/firestore");
const { db } = require("../utils/firestore");
const {
  processReadyAccountDeletionOutbox,
} = require("../account/deletion");
const { OUTBOX_COLLECTION } = require("../account/outbox");

// The exact production queries, kept in one place so the declaration test and
// the emulator tests cannot drift apart.
const COMPOSITES = Object.freeze([
  { status: "pending", field: "nextAttemptAt" },
  { status: "processing", field: "leaseUntil" },
]);

const readyQuery = (status, field, now, limit = 20) => db
  .collection(OUTBOX_COLLECTION)
  .where("status", "==", status)
  .where(field, "<=", now)
  .orderBy(field)
  .limit(limit);

// Deliberately ancient (2001-09-09) so this fixture cannot overlap the
// 2030-era timestamps other suites seed into the shared emulator database.
const SWEEP_NOW_MS = 1_000_000_000_000;

const emulatorTest = (name, fn) => test(
  `Account deletion sweep index: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);

after(async () => {
  if (getApps().length > 0) await deleteApp(getApps()[0]);
});

test("firestore.indexes.json declares both sweep composites", () => {
  const indexesPath = path.resolve(__dirname, "../../firestore.indexes.json");
  const config = JSON.parse(readFileSync(indexesPath, "utf8"));
  const declared = config.indexes.filter(
    (index) => index.collectionGroup === OUTBOX_COLLECTION,
  );

  for (const { field } of COMPOSITES) {
    const match = declared.filter((index) =>
      index.queryScope === "COLLECTION" &&
      Array.isArray(index.fields) &&
      index.fields.length === 2 &&
      index.fields[0].fieldPath === "status" &&
      index.fields[0].order === "ASCENDING" &&
      index.fields[1].fieldPath === field &&
      index.fields[1].order === "ASCENDING");
    assert.equal(
      match.length,
      1,
      `exactly one status+${field} composite must be declared for the sweep`,
    );
  }

  // The outbox is a server-only collection with no field override today.
  // Declaring one here would REPLACE automatic single-field indexing for that
  // field rather than add to it (docs/Firebase.md), which would silently break
  // the point reads the worker does on every claim.
  const overrides = (config.fieldOverrides ?? []).filter(
    (override) => override.collectionGroup === OUTBOX_COLLECTION,
  );
  assert.deepEqual(overrides, []);
});

async function fixture() {
  const token = randomUUID().replaceAll("-", "");
  const ready = db.collection(OUTBOX_COLLECTION).doc(`adi_ready_${token}`);
  const deferred = db.collection(OUTBOX_COLLECTION).doc(`adi_later_${token}`);
  const expired = db.collection(OUTBOX_COLLECTION).doc(`adi_expired_${token}`);
  const leased = db.collection(OUTBOX_COLLECTION).doc(`adi_leased_${token}`);

  await Promise.all([
    ready.set({
      schemaVersion: 1,
      uid: `adi_uid_ready_${token}`,
      stage: "revoke",
      cursor: null,
      status: "pending",
      attemptCount: 0,
      nextAttemptAt: Timestamp.fromMillis(SWEEP_NOW_MS - 60_000),
      leaseToken: null,
      leaseUntil: null,
    }),
    deferred.set({
      schemaVersion: 1,
      uid: `adi_uid_later_${token}`,
      stage: "revoke",
      cursor: null,
      status: "pending",
      attemptCount: 1,
      nextAttemptAt: Timestamp.fromMillis(SWEEP_NOW_MS + 600_000),
      leaseToken: null,
      leaseUntil: null,
    }),
    expired.set({
      schemaVersion: 1,
      uid: `adi_uid_expired_${token}`,
      stage: "revoke",
      cursor: null,
      status: "processing",
      attemptCount: 1,
      nextAttemptAt: Timestamp.fromMillis(SWEEP_NOW_MS - 60_000),
      leaseToken: "a".repeat(32),
      leaseUntil: Timestamp.fromMillis(SWEEP_NOW_MS - 30_000),
    }),
    leased.set({
      schemaVersion: 1,
      uid: `adi_uid_leased_${token}`,
      stage: "revoke",
      cursor: null,
      status: "processing",
      attemptCount: 1,
      nextAttemptAt: Timestamp.fromMillis(SWEEP_NOW_MS - 60_000),
      leaseToken: "b".repeat(32),
      leaseUntil: Timestamp.fromMillis(SWEEP_NOW_MS + 600_000),
    }),
  ]);

  return {
    ready,
    deferred,
    expired,
    leased,
    async cleanup() {
      await Promise.all([
        ready.delete(), deferred.delete(), expired.delete(), leased.delete(),
      ]);
    },
  };
}

emulatorTest("the real pending query returns only rows whose backoff elapsed", async () => {
  const value = await fixture();
  try {
    const now = Timestamp.fromMillis(SWEEP_NOW_MS);
    const snapshot = await readyQuery("pending", "nextAttemptAt", now).get();
    const ids = new Set(snapshot.docs.map((document) => document.id));
    assert.ok(ids.has(value.ready.id), "an elapsed backoff must be scanned");
    assert.ok(
      !ids.has(value.deferred.id),
      "a row still inside its backoff must NOT be scanned",
    );
  } finally {
    await value.cleanup();
  }
});

emulatorTest("the real processing query reclaims only expired leases", async () => {
  const value = await fixture();
  try {
    const now = Timestamp.fromMillis(SWEEP_NOW_MS);
    const snapshot = await readyQuery("processing", "leaseUntil", now).get();
    const ids = new Set(snapshot.docs.map((document) => document.id));
    assert.ok(ids.has(value.expired.id), "an expired lease must be reclaimable");
    assert.ok(
      !ids.has(value.leased.id),
      "a live lease must NOT be stolen from the instance holding it",
    );
  } finally {
    await value.cleanup();
  }
});

emulatorTest("the real sweep scans both queries in one pass", async () => {
  const value = await fixture();
  try {
    const seen = [];
    // A stage runner that immediately completes every row, so this exercises
    // the sweep's query + claim path rather than the teardown itself.
    const stages = {
      runStage: async (stage, context) => {
        seen.push([stage, context.uid]);
        return { done: true, cursor: null };
      },
    };
    const outcome = await processReadyAccountDeletionOutbox({
      database: db,
      stages,
      nowMs: () => SWEEP_NOW_MS,
      log: { info() {}, error() {} },
    });
    assert.ok(outcome.scanned >= 2, "both the ready and the expired row");
    const uids = new Set(seen.map((entry) => entry[1]));
    assert.ok(uids.has((await value.ready.get()).data()?.uid ?? "ready-gone") ||
      (await value.ready.get()).data()?.status === "completed");
    assert.equal(
      (await value.deferred.get()).data()?.status,
      "pending",
      "a deferred row must be left alone",
    );
    assert.equal(
      (await value.leased.get()).data()?.leaseToken,
      "b".repeat(32),
      "a live lease must be left alone",
    );
  } finally {
    await value.cleanup();
  }
});

const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  FirestoreAchievementMigrationStore,
  GLOBAL_STATE_PATH,
  MAX_BOOTSTRAP_ATTEMPTS,
  MIGRATION_SCHEMA_VERSION,
  createAchievementMigrationService,
} = require("../achievements/migration");
const { legacyProgressFromUser } = require("../achievements/model");

const db = getFirestore();
const NOW = new Date("2026-08-19T09:00:00.000Z");
// Unique per-file uid prefix: test files share one emulator instance.
const uidFor = (name) => `achv-migration-${name}`;

async function seedState(currentUid) {
  await db.doc(GLOBAL_STATE_PATH).set({
    schemaVersion: MIGRATION_SCHEMA_VERSION,
    afterUid: null,
    currentUid,
    complete: false,
    updatedAt: NOW,
  });
}

function serviceFor(errors) {
  return createAchievementMigrationService({
    store: new FirestoreAchievementMigrationStore({ db }),
    clock: () => NOW,
    logger: { error: (...args) => errors.push(args) },
    // One user per page: the run finishes on the pre-seeded currentUid and
    // never scans the shared users collection of the emulator.
    usersPerRun: 1,
  });
}

describe("achievement migration recovery", () => {
  test("legacy bootstrap never contains undefined values", () => {
    const progress = legacyProgressFromUser({ uid: "u" });
    assert.equal(progress.selectedTitleId, null);
    assert.equal(progress.legacyUnlockedTitleTimestamps, null);
    assert.ok(Object.values(progress).every((value) => value !== undefined));
  });

  test("a legacy skeleton profile bootstraps instead of crashing the run", async () => {
    // Production repro (2026-08-16..19): a presence-only legacy user document
    // made the bootstrap write undefined values, which Firestore rejects; the
    // failure record then wedged the whole pipeline on this first user.
    const uid = uidFor("skeleton");
    await db.doc(`users/${uid}`).set({
      uid,
      displayName: "Legacy",
      email: "legacy@example.com",
      photoUrl: null,
      bannerUrl: null,
      isOnline: false,
      lastSeen: NOW,
      presenceUpdatedAt: NOW,
    });
    await seedState(uid);
    const errors = [];

    const result = await serviceFor(errors).runPage();

    assert.equal(result.usersCompleted, 1);
    assert.equal(result.usersUnrecoverable, 0);
    assert.equal(errors.length, 0);
    const migration = (await db.doc(`achievementMigrations/${uid}`).get()).data();
    assert.equal(migration.schemaVersion, MIGRATION_SCHEMA_VERSION);
    assert.equal(migration.uid, uid);
    assert.equal(migration.bootstrapCompleted, true);
    assert.equal(migration.status, "verified");
    const progress = (await db.doc(`achievementProgress/${uid}`).get()).data();
    assert.equal(progress.selectedTitleId, null);
    assert.equal(progress.legacyUnlockedTitleTimestamps, null);
    const user = (await db.doc(`users/${uid}`).get()).data();
    assert.equal(user.achievementVerificationStatus, "verified");
    const state = (await db.doc(GLOBAL_STATE_PATH).get()).data();
    assert.equal(state.afterUid, uid);
    assert.equal(state.currentUid, null);
  });

  test("the historical partial failure record re-initializes instead of wedging", async () => {
    // Exact shape the old failUser left behind for a user whose bootstrap
    // never committed: no schemaVersion, no uid, no bootstrapCompleted.
    const uid = uidFor("poisoned");
    await db.doc(`users/${uid}`).set({ uid, displayName: "Poisoned" });
    await db.doc(`achievementMigrations/${uid}`).set({
      status: "failed",
      failureCode: "canonical-reconciliation-failed",
      updatedAt: NOW,
    });
    await seedState(uid);
    const errors = [];

    const result = await serviceFor(errors).runPage();

    assert.equal(result.usersCompleted, 1);
    assert.equal(result.usersUnrecoverable, 0);
    assert.equal(errors.length, 0);
    const migration = (await db.doc(`achievementMigrations/${uid}`).get()).data();
    assert.equal(migration.bootstrapCompleted, true);
    assert.equal(migration.status, "verified");
    assert.equal(migration.failureCode, undefined);
    const state = (await db.doc(GLOBAL_STATE_PATH).get()).data();
    assert.equal(state.afterUid, uid);
    assert.equal(state.currentUid, null);
  });

  test("a contradictory migration record is terminal for one user and the run advances", async () => {
    const uid = uidFor("contradictory");
    await db.doc(`users/${uid}`).set({ uid, displayName: "Broken" });
    await db.doc(`achievementMigrations/${uid}`).set({
      schemaVersion: 999,
      uid: "someone-else",
      bootstrapCompleted: true,
      status: "reconciling",
      updatedAt: NOW,
    });
    await seedState(uid);
    const errors = [];

    const result = await serviceFor(errors).runPage();

    assert.equal(result.usersCompleted, 1);
    assert.equal(result.usersUnrecoverable, 1);
    assert.equal(errors.length, 1);
    assert.equal(errors[0][1].failureCode, "malformed-user-migration-state");
    const reference = db.doc(`achievementMigrations/${uid}`);
    const rewritten = await reference.get();
    assert.deepEqual(
      { ...rewritten.data(), updatedAt: null },
      {
        schemaVersion: MIGRATION_SCHEMA_VERSION,
        uid,
        status: "failed",
        failureCode: "malformed-user-migration-state",
        attemptCount: 0,
        updatedAt: null,
      },
    );
    const state = (await db.doc(GLOBAL_STATE_PATH).get()).data();
    assert.equal(state.afterUid, uid);
    assert.equal(state.currentUid, null);

    // Terminal stays terminal, without rewriting the record again.
    await seedState(uid);
    const again = await serviceFor(errors).runPage();
    assert.equal(again.usersUnrecoverable, 1);
    const untouched = await reference.get();
    assert.equal(
      untouched.updateTime.toMillis(),
      rewritten.updateTime.toMillis(),
    );
  });

  test("pre-bootstrap failures terminalize at the attempt cap and retry below it", async () => {
    const exhaustedUid = uidFor("exhausted");
    await db.doc(`users/${exhaustedUid}`).set({ uid: exhaustedUid });
    await db.doc(`achievementMigrations/${exhaustedUid}`).set({
      schemaVersion: MIGRATION_SCHEMA_VERSION,
      uid: exhaustedUid,
      status: "failed",
      failureCode: "canonical-reconciliation-failed",
      attemptCount: MAX_BOOTSTRAP_ATTEMPTS,
      updatedAt: NOW,
    });
    await seedState(exhaustedUid);
    const errors = [];
    const result = await serviceFor(errors).runPage();
    assert.equal(result.usersUnrecoverable, 1);
    const exhausted = (await db.doc(`achievementMigrations/${exhaustedUid}`).get()).data();
    assert.equal(exhausted.failureCode, "bootstrap-attempts-exhausted");
    assert.equal(exhausted.status, "failed");

    const retryingUid = uidFor("retrying");
    await db.doc(`users/${retryingUid}`).set({ uid: retryingUid });
    await db.doc(`achievementMigrations/${retryingUid}`).set({
      schemaVersion: MIGRATION_SCHEMA_VERSION,
      uid: retryingUid,
      status: "failed",
      failureCode: "canonical-reconciliation-failed",
      attemptCount: MAX_BOOTSTRAP_ATTEMPTS - 1,
      updatedAt: NOW,
    });
    await seedState(retryingUid);
    const retried = await serviceFor(errors).runPage();
    assert.equal(retried.usersUnrecoverable, 0);
    const recovered = (await db.doc(`achievementMigrations/${retryingUid}`).get()).data();
    assert.equal(recovered.bootstrapCompleted, true);
    assert.equal(recovered.status, "verified");
  });

  test("failUser always writes a self-describing record and counts attempts", async () => {
    const uid = uidFor("fail-user");
    const store = new FirestoreAchievementMigrationStore({ db });
    await store.failUser({ uid, now: NOW });
    const first = (await db.doc(`achievementMigrations/${uid}`).get()).data();
    assert.equal(first.schemaVersion, MIGRATION_SCHEMA_VERSION);
    assert.equal(first.uid, uid);
    assert.equal(first.status, "failed");
    assert.equal(first.failureCode, "canonical-reconciliation-failed");
    assert.equal(first.attemptCount, 1);
    await store.failUser({ uid, now: NOW });
    const second = (await db.doc(`achievementMigrations/${uid}`).get()).data();
    assert.equal(second.attemptCount, 2);
  });

  test("bootstrap adopts live verified progress instead of overwriting it", async () => {
    // Live triggers can reach a user before the reconciler does. Their
    // verified progress is unreplayable (the dedup ledger absorbs replays),
    // so the bootstrap must never reset it — and must not re-derive legacy
    // floors from the user document, whose counters the projection has
    // already replaced with verified values.
    const uid = uidFor("live-progress");
    await db.doc(`users/${uid}`).set({ uid, messageCount: 3 });
    const seededProgress = {
      schemaVersion: 1,
      verifiedMetrics: { messages: 7 },
      legacyMetricFloors: { messages: 250 },
      verifiedUnlockedTitleIds: ["messages_1"],
      updatedAt: NOW,
    };
    await db.doc(`achievementProgress/${uid}`).set(seededProgress);
    await seedState(uid);
    const errors = [];

    const result = await serviceFor(errors).runPage();

    assert.equal(result.usersCompleted, 1);
    assert.equal(result.usersUnrecoverable, 0);
    const progress = (await db.doc(`achievementProgress/${uid}`).get()).data();
    assert.equal(progress.verifiedMetrics.messages, 7);
    assert.equal(progress.legacyMetricFloors.messages, 250);
    const migration = (await db.doc(`achievementMigrations/${uid}`).get()).data();
    assert.equal(migration.bootstrapCompleted, true);
    assert.equal(migration.legacyMetricFloors.messages, 250);
    const user = (await db.doc(`users/${uid}`).get()).data();
    assert.equal(user.achievementVerificationStatus, "verified");
    assert.equal(user.messageCount, 3);
  });
});

// Coverage for the publicBadges mirror: derivation, sync, the batch
// reader, and the backfill.
//
// The properties that matter:
//
//  1. The mirror never carries more than its four fields — not the VIP
//     source, not an email, not a reason. Ever.
//  2. An ordinary account has NO document; revocation converges to that.
//  3. Sync derives from CURRENT state, so repeats and out-of-order
//     deliveries are harmless.
//  4. The batch reader is bounded, authenticated, and returns only the
//     public schema whatever is stored.
//
// Every fixture is prefixed `pb-` and scans are bounded to that prefix —
// node --test runs suites in parallel over one emulator database.
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  deriveBadge,
  syncPublicBadgeForUser,
  getPublicBadges,
  MAX_BATCH_UIDS,
} = require("../badges/public_badges");

const { backfill, emptyReport, EXPECTED_PROJECT } = require("../scripts/backfill_badges");

const db = getFirestore();
const runBatch = getPublicBadges.run ?? getPublicBadges;

const P = "pb-";
const STAFF_VOCAB = [
  "guideMaster",
  "support",
  "auditor",
  "moderator",
  "superModerator",
  "superAdmin",
];

const FIXTURES = [
  `${P}plain`,
  `${P}vip-sub`,
  `${P}vip-grant`,
  `${P}staff-vip`,
  `${P}invalid`,
  `${P}orphan`,
  ...STAFF_VOCAB.map((role) => `${P}${role}`),
];

async function wipeOwn() {
  await Promise.all(
    FIXTURES.flatMap((uid) => [
      db.collection("users").doc(uid).delete(),
      db.collection("vipGrants").doc(uid).delete(),
      db.collection("publicBadges").doc(uid).delete(),
    ]),
  );
}

function caller(uid = `${P}reader`) {
  return { auth: { uid, token: {} } };
}

beforeEach(wipeOwn);

describe("derivation", () => {
  test("every staff role derives a badge with exactly the four-field shape", () => {
    for (const role of STAFF_VOCAB) {
      const badge = deriveBadge({ user: { role } });
      assert.deepEqual(Object.keys(badge).sort(), [
        "isVip",
        "schemaVersion",
        "staffRole",
      ]);
      assert.equal(badge.staffRole, role);
      assert.equal(badge.isVip, false);
    }
  });

  test("an ordinary account derives NO badge", () => {
    assert.equal(deriveBadge({ user: { role: "user" } }), null);
    assert.equal(deriveBadge({ user: {} }), null);
  });

  test("VIP-only and staff+VIP both derive, and stay distinguishable", () => {
    const vipOnly = deriveBadge({ user: { role: "user", premiumIdentity: true } });
    assert.equal(vipOnly.staffRole, "user");
    assert.equal(vipOnly.isVip, true);

    const both = deriveBadge({
      user: { role: "moderator", premiumIdentity: true },
    });
    assert.equal(both.staffRole, "moderator");
    assert.equal(both.isVip, true);
  });

  test("a complimentary grant confers the badge VIP without exposing why", () => {
    const badge = deriveBadge({
      user: { role: "user" },
      grant: { source: "adminGrant", expiresAt: null },
    });
    assert.equal(badge.isVip, true);
    // The SOURCE never reaches the mirror.
    assert.equal("source" in badge, false);
  });

  test("an unknown role is published as user, never repeated verbatim", () => {
    assert.equal(deriveBadge({ user: { role: "wizard" } }), null);
    const withVip = deriveBadge({
      user: { role: "wizard", premiumIdentity: true },
    });
    assert.equal(withVip.staffRole, "user");
  });

  test("a deleted user derives nothing even with a lingering grant", () => {
    assert.equal(deriveBadge({ user: null, grant: { expiresAt: null } }), null);
  });
});

describe("sync", () => {
  test("writes, revokes, and repeated out-of-order syncs converge", async () => {
    const uid = `${P}moderator`;
    await db.collection("users").doc(uid).set({ role: "moderator" });

    let result = await syncPublicBadgeForUser(uid);
    assert.equal(result.outcome, "written");

    let doc = await db.collection("publicBadges").doc(uid).get();
    assert.equal(doc.data().staffRole, "moderator");
    assert.deepEqual(Object.keys(doc.data()).sort(), [
      "isVip",
      "schemaVersion",
      "staffRole",
      "updatedAt",
    ]);

    // Repeat: harmless, same converged state.
    await syncPublicBadgeForUser(uid);
    await syncPublicBadgeForUser(uid);
    doc = await db.collection("publicBadges").doc(uid).get();
    assert.equal(doc.data().staffRole, "moderator");

    // Revocation: the role returns to user, the badge disappears —
    // however many stale trigger deliveries replay afterwards.
    await db.collection("users").doc(uid).set({ role: "user" });
    result = await syncPublicBadgeForUser(uid);
    assert.equal(result.outcome, "removed");
    await syncPublicBadgeForUser(uid); // replayed event
    doc = await db.collection("publicBadges").doc(uid).get();
    assert.equal(doc.exists, false);
  });

  test("user deletion removes the badge", async () => {
    const uid = `${P}support`;
    await db.collection("users").doc(uid).set({ role: "support" });
    await syncPublicBadgeForUser(uid);
    assert.equal((await db.collection("publicBadges").doc(uid).get()).exists, true);

    await db.collection("users").doc(uid).delete();
    await syncPublicBadgeForUser(uid);
    assert.equal(
      (await db.collection("publicBadges").doc(uid).get()).exists,
      false,
    );
  });

  test("sync heals a document that acquired foreign fields", async () => {
    const uid = `${P}auditor`;
    await db.collection("users").doc(uid).set({ role: "auditor" });
    await db.collection("publicBadges").doc(uid).set({
      staffRole: "auditor",
      isVip: false,
      schemaVersion: 1,
      email: "leak@example.invalid",
      grantSource: "adminGrant",
    });

    await syncPublicBadgeForUser(uid);
    const data = (await db.collection("publicBadges").doc(uid).get()).data();
    assert.equal("email" in data, false, "foreign field survived a sync");
    assert.equal("grantSource" in data, false);
  });

  test("a malformed uid is refused without touching anything", async () => {
    assert.deepEqual(await syncPublicBadgeForUser("a/b"), {
      outcome: "invalidUid",
    });
    assert.deepEqual(await syncPublicBadgeForUser(""), {
      outcome: "invalidUid",
    });
  });
});

describe("getPublicBadges", () => {
  test("an authenticated caller batch-reads only the public schema", async () => {
    const staffUid = `${P}superModerator`;
    const vipUid = `${P}vip-sub`;
    await db.collection("users").doc(staffUid).set({ role: "superModerator" });
    await db
      .collection("users")
      .doc(vipUid)
      .set({ role: "user", premiumIdentity: true });
    await syncPublicBadgeForUser(staffUid);
    await syncPublicBadgeForUser(vipUid);

    const result = await runBatch({
      ...caller(),
      data: { uids: [staffUid, vipUid, `${P}plain`, staffUid] }, // dupe + miss
    });

    assert.deepEqual(Object.keys(result.badges).sort(), [staffUid, vipUid].sort());
    for (const badge of Object.values(result.badges)) {
      assert.deepEqual(Object.keys(badge).sort(), [
        "isVip",
        "schemaVersion",
        "staffRole",
        "updatedAt",
      ]);
    }
    assert.equal(result.badges[staffUid].staffRole, "superModerator");
    assert.equal(result.badges[vipUid].isVip, true);
  });

  test("unauthenticated, oversized and malformed requests are refused", async () => {
    await assert.rejects(
      () => runBatch({ auth: null, data: { uids: ["x"] } }),
      /signed in/i,
    );
    await assert.rejects(
      () => runBatch({ ...caller(), data: { uids: "not-an-array" } }),
      /must be an array/,
    );
    await assert.rejects(
      () =>
        runBatch({
          ...caller(),
          data: { uids: Array.from({ length: MAX_BATCH_UIDS + 1 }, (_, i) => `u${i}`) },
        }),
      /At most/,
    );
    for (const bad of ["a/b", "", "..", 42]) {
      await assert.rejects(
        () => runBatch({ ...caller(), data: { uids: [bad] } }),
        /uid/i,
      );
    }
    // Empty list is a benign no-op, not an error.
    assert.deepEqual(
      (await runBatch({ ...caller(), data: { uids: [] } })).badges,
      {},
    );
  });

  test("stored private fields never reach the response", async () => {
    const uid = `${P}guideMaster`;
    await db.collection("publicBadges").doc(uid).set({
      staffRole: "guideMaster",
      isVip: true,
      schemaVersion: 1,
      email: "leak@example.invalid",
      reason: "warned twice",
    });

    const result = await runBatch({ ...caller(), data: { uids: [uid] } });
    const serialised = JSON.stringify(result);
    assert.equal(serialised.includes("leak@example.invalid"), false);
    assert.equal(serialised.includes("warned twice"), false);
  });
});

describe("backfill", () => {
  const args = { apply: false, project: EXPECTED_PROJECT, batchSize: 50 };

  async function seedWorld() {
    await Promise.all([
      db.collection("users").doc(`${P}plain`).set({ role: "user" }),
      db.collection("users").doc(`${P}moderator`).set({ role: "moderator" }),
      db
        .collection("users")
        .doc(`${P}vip-sub`)
        .set({ role: "user", premiumIdentity: true }),
      db
        .collection("users")
        .doc(`${P}staff-vip`)
        .set({ role: "superAdmin", premiumIdentity: true }),
      db.collection("vipGrants").doc(`${P}vip-grant`).set({ expiresAt: null }),
      db.collection("users").doc(`${P}vip-grant`).set({ role: "user" }),
      // A badge whose user is gone: must be swept.
      db
        .collection("publicBadges")
        .doc(`${P}orphan`)
        .set({ staffRole: "moderator", isVip: false, schemaVersion: 1 }),
    ]);
  }

  test("dry run writes nothing and counts the work", async () => {
    await seedWorld();
    const report = await backfill({ db, args, uidPrefix: P });

    assert.equal(report.appliedWrites, 0);
    assert.equal(report.appliedDeletes, 0);
    assert.ok(report.staffBadges >= 1);
    assert.ok(report.vipOnlyBadges >= 2);
    assert.ok(report.staffVipBadges >= 1);
    assert.ok(report.toCreate >= 4);
    assert.ok(report.toDelete >= 1, "the orphan must be planned away");

    // Nothing was actually created.
    assert.equal(
      (await db.collection("publicBadges").doc(`${P}moderator`).get()).exists,
      false,
    );
    // The report leaks nothing personal.
    const serialised = JSON.stringify(report);
    for (const uid of FIXTURES) {
      assert.equal(serialised.includes(uid), false, `${uid} leaked`);
    }
  });

  test("apply creates, sweeps orphans, and a second run is a no-op", async () => {
    await seedWorld();
    const first = await backfill({
      db,
      args: { ...args, apply: true },
      uidPrefix: P,
    });
    assert.ok(first.appliedWrites >= 4);
    assert.ok(first.appliedDeletes >= 1);

    assert.equal(
      (await db.collection("publicBadges").doc(`${P}moderator`).get()).data()
        .staffRole,
      "moderator",
    );
    assert.equal(
      (await db.collection("publicBadges").doc(`${P}plain`).get()).exists,
      false,
    );
    assert.equal(
      (await db.collection("publicBadges").doc(`${P}orphan`).get()).exists,
      false,
    );

    const second = await backfill({
      db,
      args: { ...args, apply: true },
      uidPrefix: P,
    });
    assert.equal(second.appliedWrites, 0);
    assert.equal(second.appliedDeletes, 0);
    assert.ok(second.upToDate >= 4);
  });

  test("apply refuses when the scan finds an invalid role", async () => {
    await seedWorld();
    await db.collection("users").doc(`${P}invalid`).set({ role: "wizard" });

    await assert.rejects(
      () => backfill({ db, args: { ...args, apply: true }, uidPrefix: P }),
      /Refusing --apply/,
    );
    // And nothing was written before the refusal.
    assert.equal(
      (await db.collection("publicBadges").doc(`${P}moderator`).get()).exists,
      false,
    );

    // The dry run still reports the anomaly rather than refusing.
    const report = await backfill({ db, args, uidPrefix: P });
    assert.ok(report.invalidRoles >= 1);
  });
});

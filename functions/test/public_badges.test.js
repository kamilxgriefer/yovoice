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
  derivePublicRole,
  syncPublicBadgeForUser: syncPublicBadgeForUserRaw,
  getPublicBadges,
  MAX_BATCH_UIDS,
} = require("../badges/public_badges");

const {
  backfill: backfillRaw,
  assertOwnerGuard,
  emptyReport,
  EXPECTED_PROJECT,
} = require("../scripts/backfill_badges");

const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const runBatch = getPublicBadges.run ?? getPublicBadges;

const P = "pb-";
// The one uid the owner badge may attach to, injected as the protected
// owner for every test below. superAdmin is exercised separately from
// this list because its published value depends on the uid.
const OWNER_UID = `${P}owner`;
const NON_OWNER_VOCAB = [
  "guideMaster",
  "support",
  "auditor",
  "moderator",
  "superModerator",
];

const FIXTURES = [
  `${P}plain`,
  `${P}vip-sub`,
  `${P}vip-grant`,
  `${P}staff-vip`,
  `${P}invalid`,
  `${P}orphan`,
  `${P}auth-orphan`,
  `${P}auth-disabled`,
  `${P}forged`,
  OWNER_UID,
  ...NON_OWNER_VOCAB.map((role) => `${P}${role}`),
];

const activeAuthUser = (uid) => ({ uid, disabled: false });
const fetchActiveAuthUser = async (uid) => activeAuthUser(uid);

function syncPublicBadgeForUser(
  uid,
  { authUser = activeAuthUser(uid), fetchAuthUser = null } = {},
) {
  return syncPublicBadgeForUserRaw(uid, {
    database: db,
    fetchAuthUser: fetchAuthUser ?? (async () => authUser),
  });
}

function backfill(options) {
  return backfillRaw({
    ...options,
    fetchAuthUser: options.fetchAuthUser ?? fetchActiveAuthUser,
  });
}

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

beforeEach(() => {
  setProtectedOwnerUidForTests(OWNER_UID);
  return wipeOwn();
});

describe("derivation", () => {
  test("every staff role derives a badge with exactly the four-field shape", () => {
    for (const role of NON_OWNER_VOCAB) {
      const badge = deriveBadge({ uid: `${P}${role}`, user: { role } });
      assert.deepEqual(Object.keys(badge).sort(), [
        "isVip",
        "schemaVersion",
        "staffRole",
      ]);
      assert.equal(badge.staffRole, role);
      assert.equal(
        badge.isVip,
        role === "moderator" || role === "superModerator",
      );
    }
  });

  test("the confirmed owner — and only the owner — derives superAdmin", () => {
    const owner = deriveBadge({
      uid: OWNER_UID,
      user: { role: "superAdmin" },
    });
    assert.equal(owner.staffRole, "superAdmin");

    // A forged or stale superAdmin on any other uid fails safe to the
    // tier the capability matrix actually grants it.
    const forged = deriveBadge({
      uid: `${P}forged`,
      user: { role: "superAdmin" },
    });
    assert.equal(forged.staffRole, "superModerator");
    assert.equal(
      derivePublicRole(`${P}forged`, { role: "superAdmin" })
        .unconfirmedSuperAdmin,
      true,
    );

    // With the secret unavailable nobody can be confirmed, so nobody is
    // published as the owner — the real owner included.
    setProtectedOwnerUidForTests(null);
    const previousEnv = process.env.YOVOICE_PROTECTED_OWNER_UID;
    delete process.env.YOVOICE_PROTECTED_OWNER_UID;
    try {
      const unguarded = deriveBadge({
        uid: OWNER_UID,
        user: { role: "superAdmin" },
      });
      assert.equal(unguarded.staffRole, "superModerator");
    } finally {
      if (previousEnv !== undefined) {
        process.env.YOVOICE_PROTECTED_OWNER_UID = previousEnv;
      }
      setProtectedOwnerUidForTests(OWNER_UID);
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

  test("role publication is byte-exact and never trims into staff", () => {
    assert.equal(deriveBadge({ user: { role: " moderator " } }), null);
    const paid = deriveBadge({
      user: { role: " moderator ", premiumIdentity: true },
    });
    assert.equal(paid.staffRole, "user");
    assert.equal(paid.isVip, true, "independent paid identity stays truthful");
    assert.equal(
      derivePublicRole(`${P}spaced`, { role: " superAdmin " })
        .unconfirmedSuperAdmin,
      false,
    );
  });

  test("a deleted user derives nothing even with a lingering grant", () => {
    assert.equal(deriveBadge({ user: null, grant: { expiresAt: null } }), null);
  });

  test("an inactive moderator derives no public badge or VIP identity", () => {
    for (const state of [
      { banned: true },
      { disabled: true },
      { deleted: true },
      { status: "deleted" },
    ]) {
      assert.equal(
        deriveBadge({ user: { role: "moderator", ...state } }),
        null,
      );
    }
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
    assert.equal(doc.data().isVip, true);

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

  test("suspending a moderator removes the public badge", async () => {
    const uid = `${P}moderator`;
    await db.collection("users").doc(uid).set({
      role: "moderator",
      banned: false,
    });
    await syncPublicBadgeForUser(uid);
    assert.equal(
      (await db.collection("publicBadges").doc(uid).get()).data().isVip,
      true,
    );

    await db.collection("users").doc(uid).update({ banned: true });
    await syncPublicBadgeForUser(uid);
    assert.equal(
      (await db.collection("publicBadges").doc(uid).get()).exists,
      false,
    );
  });

  test("an Auth-orphan profile cannot retain or recreate a public badge", async () => {
    const uid = `${P}auth-orphan`;
    await db.collection("users").doc(uid).set({ role: "moderator" });
    await db.collection("publicBadges").doc(uid).set({
      staffRole: "moderator",
      isVip: true,
      schemaVersion: 1,
    });

    const result = await syncPublicBadgeForUser(uid, { authUser: null });
    assert.equal(result.outcome, "removed");
    assert.equal(
      (await db.collection("publicBadges").doc(uid).get()).exists,
      false,
    );

    // A later user/grant trigger replay still cannot recreate the identity.
    await syncPublicBadgeForUser(uid, { authUser: null });
    assert.equal(
      (await db.collection("publicBadges").doc(uid).get()).exists,
      false,
    );
  });

  test("a disabled Auth identity cannot retain or recreate a public badge", async () => {
    const uid = `${P}auth-disabled`;
    await db.collection("users").doc(uid).set({ role: "superModerator" });
    await db.collection("publicBadges").doc(uid).set({
      staffRole: "superModerator",
      isVip: true,
      schemaVersion: 1,
    });

    await syncPublicBadgeForUser(uid, {
      authUser: { uid, disabled: true },
    });
    assert.equal(
      (await db.collection("publicBadges").doc(uid).get()).exists,
      false,
    );

    await syncPublicBadgeForUser(uid, {
      authUser: { uid, disabled: true },
    });
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

  test("a forged superAdmin syncs as superModerator and raises the alert", async () => {
    const uid = `${P}forged`;
    await db.collection("users").doc(uid).set({ role: "superAdmin" });

    await syncPublicBadgeForUser(uid);

    const badge = (await db.collection("publicBadges").doc(uid).get()).data();
    assert.equal(badge.staffRole, "superModerator");

    const alerts = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", uid)
      .where("action", "==", "security_alert_non_owner_super_admin")
      .get();
    assert.ok(alerts.size >= 1, "the invalid state must be audited");
  });

  test("the confirmed owner syncs as superAdmin, without an alert", async () => {
    await db.collection("users").doc(OWNER_UID).set({ role: "superAdmin" });

    await syncPublicBadgeForUser(OWNER_UID);

    const badge = (
      await db.collection("publicBadges").doc(OWNER_UID).get()
    ).data();
    assert.equal(badge.staffRole, "superAdmin");

    const alerts = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", OWNER_UID)
      .where("action", "==", "security_alert_non_owner_super_admin")
      .get();
    assert.equal(alerts.size, 0, "the owner is not an anomaly");
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
    assert.equal(result.badges[staffUid].isVip, true);
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

  test("a STALE stored superAdmin row is demoted in the response", async () => {
    // Planted directly, as if it predated the owner guard: the stored
    // document says superAdmin for a uid that is not the owner.
    await db.collection("publicBadges").doc(`${P}forged`).set({
      staffRole: "superAdmin",
      isVip: false,
      schemaVersion: 1,
    });
    await db.collection("publicBadges").doc(OWNER_UID).set({
      staffRole: "superAdmin",
      isVip: true,
      schemaVersion: 1,
    });

    const result = await runBatch({
      ...caller(),
      data: { uids: [`${P}forged`, OWNER_UID] },
    });

    assert.equal(result.badges[`${P}forged`].staffRole, "superModerator");
    assert.equal(result.badges[OWNER_UID].staffRole, "superAdmin");
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
      db.collection("users").doc(`${P}support`).set({ role: "support" }),
      db
        .collection("users")
        .doc(`${P}vip-sub`)
        .set({ role: "user", premiumIdentity: true }),
      // A forged superAdmin (not the injected owner uid) …
      db
        .collection("users")
        .doc(`${P}staff-vip`)
        .set({ role: "superAdmin", premiumIdentity: true }),
      // … and the real owner.
      db
        .collection("users")
        .doc(OWNER_UID)
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
    assert.ok(
      report.unconfirmedSuperAdmins >= 1,
      "the forged superAdmin must be counted",
    );

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

    const moderatorBadge = (
      await db.collection("publicBadges").doc(`${P}moderator`).get()
    ).data();
    assert.equal(moderatorBadge.staffRole, "moderator");
    assert.equal(moderatorBadge.isVip, true);
    // The owner's badge survives as superAdmin; the forged one is
    // written as the tier it actually holds.
    assert.equal(
      (await db.collection("publicBadges").doc(OWNER_UID).get()).data()
        .staffRole,
      "superAdmin",
    );
    assert.equal(
      (await db.collection("publicBadges").doc(`${P}staff-vip`).get()).data()
        .staffRole,
      "superModerator",
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

  test("backfill removes Auth-orphan/disabled badges and never republishes them", async () => {
    const orphanUid = `${P}auth-orphan`;
    const disabledUid = `${P}auth-disabled`;
    await Promise.all([
      db.collection("users").doc(orphanUid).set({ role: "moderator" }),
      db.collection("users").doc(disabledUid).set({
        role: "superModerator",
      }),
      db.collection("publicBadges").doc(orphanUid).set({
        staffRole: "moderator",
        isVip: true,
        schemaVersion: 1,
      }),
      db.collection("publicBadges").doc(disabledUid).set({
        staffRole: "superModerator",
        isVip: true,
        schemaVersion: 1,
      }),
    ]);
    const fetchAuthUser = async (uid) => {
      if (uid === orphanUid) return null;
      if (uid === disabledUid) return { uid, disabled: true };
      return activeAuthUser(uid);
    };

    const dryRun = await backfill({
      db,
      args,
      uidPrefix: P,
      fetchAuthUser,
    });
    assert.equal(dryRun.authOrphans, 1);
    assert.equal(dryRun.disabledAuthAccounts, 1);
    assert.equal(dryRun.toDelete, 2);
    assert.equal(dryRun.appliedDeletes, 0);
    assert.equal(JSON.stringify(dryRun).includes(orphanUid), false);
    assert.equal(JSON.stringify(dryRun).includes(disabledUid), false);

    const applied = await backfill({
      db,
      args: { ...args, apply: true },
      uidPrefix: P,
      fetchAuthUser,
    });
    assert.equal(applied.appliedDeletes, 2);
    assert.equal(
      (await db.collection("publicBadges").doc(orphanUid).get()).exists,
      false,
    );
    assert.equal(
      (await db.collection("publicBadges").doc(disabledUid).get()).exists,
      false,
    );

    const converged = await backfill({
      db,
      args: { ...args, apply: true },
      uidPrefix: P,
      fetchAuthUser,
    });
    assert.equal(converged.appliedWrites, 0);
    assert.equal(converged.appliedDeletes, 0);
  });

  test("apply refuses when the scan finds an invalid role", async () => {
    await seedWorld();
    await db.collection("users").doc(`${P}invalid`).set({ role: "wizard" });
    await db.collection("users").doc(`${P}spaced`).set({
      role: " moderator ",
    });

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
    assert.ok(report.invalidRoles >= 2);
  });

  test("the backfill refuses to run without the owner guard", async () => {
    setProtectedOwnerUidForTests(null);
    const previousEnv = process.env.YOVOICE_PROTECTED_OWNER_UID;
    delete process.env.YOVOICE_PROTECTED_OWNER_UID;
    try {
      assert.throws(() => assertOwnerGuard(), /YOVOICE_PROTECTED_OWNER_UID/);
      await assert.rejects(
        () => backfill({ db, args, uidPrefix: P }),
        /YOVOICE_PROTECTED_OWNER_UID/,
      );
    } finally {
      if (previousEnv !== undefined) {
        process.env.YOVOICE_PROTECTED_OWNER_UID = previousEnv;
      }
      setProtectedOwnerUidForTests(OWNER_UID);
    }
  });
});

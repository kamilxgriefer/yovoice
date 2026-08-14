// Coverage for assignUserRole as an OWNERSHIP capability.
//
// Runs against BOTH emulators: Firestore for the authoritative records
// and audit log, Auth for the real claim writes the callable performs.
// The auth-emulator env var is set before any require so the module-level
// getAuth() binds to the emulator, never to production.
//
//   firebase emulators:start --only firestore,auth --project rules-test-yovoice
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (getApps().length === 0) initializeApp();

const { assignUserRole } = require("../admin/users");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const adminAuth = getAuth();
const run = assignUserRole.run ?? assignUserRole;

const P = "asr-";
const OWNER = `${P}owner`;
const FAKE_SUPER = `${P}fake-super`;
const MOD = `${P}mod`;
const PLAIN = `${P}plain`;
const TARGET = `${P}target`;

function request(uid, role, data) {
  return { auth: { uid, token: { role } }, data };
}

async function wipeOwn() {
  await Promise.all(
    [OWNER, FAKE_SUPER, MOD, PLAIN, TARGET].map((uid) =>
      db.collection("users").doc(uid).delete(),
    ),
  );
  for (const action of ["assign_user_role", "security_alert_non_owner_super_admin"]) {
    const entries = await db
      .collection("adminAuditLogs")
      .where("action", "==", action)
      .get();
    await Promise.all(
      entries.docs
        .filter((doc) =>
          String(doc.data().targetId ?? doc.data().userId ?? "").startsWith(P),
        )
        .map((doc) => doc.ref.delete()),
    );
  }
  // Reset the target's Auth record for a clean previousRole.
  for (const uid of [TARGET, OWNER]) {
    try {
      await adminAuth.deleteUser(uid);
    } catch {
      /* not present */
    }
    await adminAuth.createUser({ uid, email: `${uid}@test.invalid` });
  }
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  await wipeOwn();
  await db.collection("users").doc(OWNER).set({ role: "superAdmin" });
  await db.collection("users").doc(FAKE_SUPER).set({ role: "superAdmin" });
  await db.collection("users").doc(MOD).set({ role: "moderator" });
  await db.collection("users").doc(PLAIN).set({ role: "user" });
  // The target has VIP that must SURVIVE every role change.
  await db
    .collection("users")
    .doc(TARGET)
    .set({ role: "user", premiumIdentity: true, displayName: "Target" });
});

afterEach(() => setProtectedOwnerUidForTests(null));

const assignArgs = (role, extra = {}) => ({
  uid: TARGET,
  role,
  reason: "verified staff application",
  ...extra,
});

describe("allowed: the confirmed owner", () => {
  for (const role of [
    "guideMaster",
    "support",
    "auditor",
    "moderator",
    "superModerator",
  ]) {
    test(`assigns ${role}, audited with reason, and VIP survives`, async () => {
      const result = await run(
        request(OWNER, "superAdmin", assignArgs(role)),
      );
      assert.equal(result.success, true);
      assert.equal(result.role, role);

      // The claim was really written.
      const record = await adminAuth.getUser(TARGET);
      assert.equal(record.customClaims.role, role);

      // The authoritative mirror followed, and VIP was untouched.
      const profile = (await db.collection("users").doc(TARGET).get()).data();
      assert.equal(profile.role, role);
      assert.equal(profile.premiumIdentity, true, "VIP must never be removed");

      // Audit: actor, target, previous, new, reason.
      const audit = await db
        .collection("adminAuditLogs")
        .where("action", "==", "assign_user_role")
        .get();
      const mine = audit.docs
        .map((doc) => doc.data())
        .filter((entry) => (entry.targetId ?? entry.userId) === TARGET);
      assert.equal(mine.length, 1);
      assert.equal(mine[0].details.previousRole, "user");
      assert.equal(mine[0].details.newRole, role);
      assert.equal(mine[0].details.reason, "verified staff application");
    });
  }

  test("revokes a staff role by assigning user back", async () => {
    await run(request(OWNER, "superAdmin", assignArgs("moderator")));
    const result = await run(
      request(
        OWNER,
        "superAdmin",
        assignArgs("user", { expectedRole: "moderator" }),
      ),
    );
    assert.equal(result.success, true);
    const record = await adminAuth.getUser(TARGET);
    assert.equal(record.customClaims.role, "user");
  });

  test("the stale-result guard refuses an outdated expectedRole", async () => {
    await run(request(OWNER, "superAdmin", assignArgs("moderator")));
    // A second admin session still believes the target is `user`.
    await assert.rejects(
      () =>
        run(
          request(
            OWNER,
            "superAdmin",
            assignArgs("support", { expectedRole: "user" }),
          ),
        ),
      /changed since you looked/,
    );
    // With the CURRENT role declared, the same change is accepted.
    const result = await run(
      request(
        OWNER,
        "superAdmin",
        assignArgs("support", { expectedRole: "moderator" }),
      ),
    );
    assert.equal(result.success, true);
  });
});

describe("denied", () => {
  test("superAdmin can never be assigned, even by the owner", async () => {
    await assert.rejects(
      () => run(request(OWNER, "superAdmin", assignArgs("superAdmin"))),
      /cannot be assigned from the app/,
    );
  });

  test("a missing or trivial reason is refused", async () => {
    await assert.rejects(
      () =>
        run(
          request(OWNER, "superAdmin", {
            uid: TARGET,
            role: "moderator",
            reason: "",
          }),
        ),
      /reason .* required/i,
    );
  });

  test("the retired legacy values are not assignable", async () => {
    for (const role of ["vip", "admin"]) {
      await assert.rejects(
        () => run(request(OWNER, "superAdmin", assignArgs(role))),
        /Role must be/,
      );
    }
  });

  test("the protected owner cannot be modified", async () => {
    await assert.rejects(
      () =>
        run(
          request(OWNER, "superAdmin", {
            uid: OWNER,
            role: "user",
            reason: "should never work",
          }),
        ),
      /owner's role cannot be changed/,
    );
  });

  test("a FORGED superAdmin is refused and recorded; moderators and "
      + "ordinary users are refused flat", async () => {
    await assert.rejects(
      () => run(request(FAKE_SUPER, "superAdmin", assignArgs("moderator"))),
      /reserved for the application owner/,
    );
    const alerts = await db
      .collection("adminAuditLogs")
      .where("action", "==", "security_alert_non_owner_super_admin")
      .where("targetId", "==", FAKE_SUPER)
      .get();
    assert.equal(alerts.size, 1);

    for (const [uid, role] of [
      [MOD, "moderator"],
      [PLAIN, "user"],
    ]) {
      await assert.rejects(
        () => run(request(uid, role, assignArgs("support"))),
        /super administrator|permission/i,
      );
    }
    await assert.rejects(
      () => run({ auth: null, data: assignArgs("support") }),
      /signed in/i,
    );

    // Nothing moved.
    const record = await adminAuth.getUser(TARGET);
    assert.equal(record.customClaims?.role, undefined);
  });
});

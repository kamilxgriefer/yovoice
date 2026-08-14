// Coverage for the capability matrix and getMyStaffCapabilities.
//
// The single most important property: OWNERSHIP requires the secret to be
// present AND matched. A superAdmin role alone — forged, stale, or
// wrongly assigned — must never confer a destructive capability, and must
// be recorded when observed. The guard's fail-closed direction (secret
// missing ⇒ everyone reads as protected) must never become a GRANT.
//
// Matrix tests are pure. Callable and setUserBan-tier tests use the
// Firestore emulator; nothing here touches Firebase Auth.
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  deriveCapabilities,
  SUSPENSION_LIMIT_HOURS,
} = require("../utils/capabilities");
const { setProtectedOwnerUidForTests } = require("../utils/roles");
const { getMyStaffCapabilities } = require("../staff/capabilities");
const { setUserBan } = require("../admin/users");

const db = getFirestore();
const runCaps = getMyStaffCapabilities.run ?? getMyStaffCapabilities;
const runBan = setUserBan.run ?? setUserBan;

const P = "cap-";
const OWNER = `${P}owner`;
const FAKE_SUPER = `${P}fake-super`;
const FIXTURES = [
  OWNER,
  FAKE_SUPER,
  `${P}mod`,
  `${P}supermod`,
  `${P}auditor`,
  `${P}support`,
  `${P}guide`,
  `${P}plain`,
  `${P}vip`,
];

const OWNER_CAPS = [
  "permanentDeleteSpaces",
  "deleteAnyMessage",
  "permanentBan",
  "manageRoles",
  "fullAuditAccess",
  "sanctionStaff",
];

async function wipeOwn() {
  await Promise.all([
    ...FIXTURES.map((uid) => db.collection("users").doc(uid).delete()),
  ]);
  const alerts = await db
    .collection("adminAuditLogs")
    .where("action", "==", "security_alert_non_owner_super_admin")
    .get();
  await Promise.all(
    alerts.docs
      .filter((doc) => String(doc.data().targetId ?? "").startsWith(P))
      .map((doc) => doc.ref.delete()),
  );
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  await wipeOwn();
});

afterEach(() => setProtectedOwnerUidForTests(null));

describe("matrix", () => {
  test("the confirmed owner holds every destructive capability", () => {
    const caps = deriveCapabilities({
      uid: OWNER,
      user: { role: "superAdmin" },
    });
    assert.equal(caps.isOwner, true);
    for (const cap of OWNER_CAPS) assert.equal(caps[cap], true, cap);
    assert.equal(caps.suspensionLimitHours, null);
    assert.equal(caps.viewAllQueues, true);
  });

  test("a superAdmin that is NOT the owner gets moderation, never "
      + "ownership, and is marked", () => {
    const caps = deriveCapabilities({
      uid: FAKE_SUPER,
      user: { role: "superAdmin" },
    });
    assert.equal(caps.isOwner, false);
    assert.equal(caps.unconfirmedSuperAdmin, true);
    for (const cap of OWNER_CAPS) assert.equal(caps[cap], false, cap);
    // Fails SAFELY into the super-moderation tier.
    assert.equal(caps.viewAllQueues, true);
    assert.equal(caps.suspensionLimitHours, SUSPENSION_LIMIT_HOURS.superModerator);
  });

  test("with the secret MISSING, even the owner uid grants nothing "
      + "destructive — fail closed in the granting direction too", () => {
    setProtectedOwnerUidForTests(null);
    const caps = deriveCapabilities({
      uid: OWNER,
      user: { role: "superAdmin" },
    });
    assert.equal(caps.isOwner, false);
    for (const cap of OWNER_CAPS) assert.equal(caps[cap], false, cap);
  });

  test("superModerator: full moderation, 30-day ceiling, no destruction", () => {
    const caps = deriveCapabilities({
      uid: `${P}supermod`,
      user: { role: "superModerator" },
    });
    assert.equal(caps.viewAllQueues, true);
    assert.equal(caps.quarantineSpaces, true);
    assert.equal(caps.endAnyRoom, true);
    assert.equal(caps.liftSuspensions, true);
    assert.equal(caps.suspensionLimitHours, 720);
    for (const cap of OWNER_CAPS) assert.equal(caps[cap], false, cap);
  });

  test("moderator: assigned-report moderation, 24-hour ceiling, no "
      + "quarantine and no destruction", () => {
    const caps = deriveCapabilities({
      uid: `${P}mod`,
      user: { role: "moderator" },
    });
    assert.equal(caps.handleAssignedReports, true);
    assert.equal(caps.removeReportedContent, true);
    assert.equal(caps.warnUsers, true);
    assert.equal(caps.endPublicRoomWithReason, true);
    assert.equal(caps.suspensionLimitHours, 24);
    assert.equal(caps.quarantineSpaces, false);
    assert.equal(caps.endAnyRoom, false);
    assert.equal(caps.liftSuspensions, false);
    assert.equal(caps.viewAllQueues, false);
    for (const cap of OWNER_CAPS) assert.equal(caps[cap], false, cap);
  });

  test("auditor, support and guideMaster get exactly their one flag", () => {
    const table = [
      ["auditor", "readAuditLogs"],
      ["support", "supportLookup"],
      ["guideMaster", "guideMode"],
    ];
    for (const [role, flag] of table) {
      const caps = deriveCapabilities({ uid: `${P}${role}`, user: { role } });
      assert.equal(caps[flag], true, `${role} missing ${flag}`);
      // ...and no moderation or destruction leaks in.
      assert.equal(caps.handleAssignedReports, false, role);
      assert.equal(caps.suspendUsers, false, role);
      assert.equal(caps.quarantineSpaces, false, role);
      for (const cap of OWNER_CAPS) assert.equal(caps[cap], false, `${role} ${cap}`);
    }
  });

  test("VIP coexists with every staff role and grants no moderation", () => {
    for (const role of ["user", "moderator", "superModerator", "auditor"]) {
      const caps = deriveCapabilities({
        uid: `${P}vip`,
        user: { role, premiumIdentity: true },
      });
      assert.equal(caps.isVip, true, role);
    }
    const vipOnly = deriveCapabilities({
      uid: `${P}vip`,
      user: { role: "user", premiumIdentity: true },
    });
    assert.equal(vipOnly.suspendUsers, false);
    assert.equal(vipOnly.handleAssignedReports, false);
    for (const cap of OWNER_CAPS) assert.equal(vipOnly[cap], false, cap);
  });

  test("an ordinary user holds nothing", () => {
    const caps = deriveCapabilities({ uid: `${P}plain`, user: { role: "user" } });
    const granted = Object.entries(caps).filter(
      ([key, value]) =>
        value === true && key !== "isVip" && key !== "isOwner",
    );
    assert.deepEqual(granted, []);
  });

  test("a banned staff account loses everything", () => {
    for (const role of ["moderator", "superModerator", "superAdmin"]) {
      const caps = deriveCapabilities({
        uid: role === "superAdmin" ? OWNER : `${P}x`,
        user: { role, banned: true },
      });
      assert.equal(caps.suspendUsers, false, role);
      assert.equal(caps.viewAllQueues, false, role);
      for (const cap of OWNER_CAPS) assert.equal(caps[cap], false, `${role} ${cap}`);
    }
  });
});

describe("getMyStaffCapabilities", () => {
  test("the owner sees ownership; the response hides the internal marker", async () => {
    await db.collection("users").doc(OWNER).set({ role: "superAdmin" });
    const result = await runCaps({ auth: { uid: OWNER, token: {} }, data: {} });
    assert.equal(result.capabilities.isOwner, true);
    assert.equal(result.capabilities.permanentDeleteSpaces, true);
    assert.equal("unconfirmedSuperAdmin" in result.capabilities, false);
  });

  test("a NON-owner superAdmin gets no ownership and a security audit "
      + "event is recorded", async () => {
    await db.collection("users").doc(FAKE_SUPER).set({ role: "superAdmin" });
    const result = await runCaps({
      auth: { uid: FAKE_SUPER, token: {} },
      data: {},
    });
    assert.equal(result.capabilities.isOwner, false);
    assert.equal(result.capabilities.permanentDeleteSpaces, false);

    const alerts = await db
      .collection("adminAuditLogs")
      .where("action", "==", "security_alert_non_owner_super_admin")
      .where("targetId", "==", FAKE_SUPER)
      .get();
    assert.equal(alerts.size, 1, "the forged superAdmin must be recorded");
  });

  test("an ordinary user gets an all-false answer, not an error", async () => {
    await db.collection("users").doc(`${P}plain`).set({ role: "user" });
    const result = await runCaps({
      auth: { uid: `${P}plain`, token: {} },
      data: {},
    });
    assert.equal(result.capabilities.staffRole, "user");
    assert.equal(result.capabilities.isOwner, false);
    assert.equal(result.capabilities.suspendUsers, false);
  });

  test("unauthenticated callers are refused", async () => {
    await assert.rejects(() => runCaps({ auth: null, data: {} }), /signed in/i);
  });
});

describe("setUserBan tiers (caller-side boundaries)", () => {
  function banRequest(uid, role, data) {
    return { auth: { uid, token: { role } }, data };
  }

  test("a moderator may not exceed 24 hours, ban permanently, or unban", async () => {
    await db.collection("users").doc(`${P}mod`).set({ role: "moderator" });
    await assert.rejects(
      () =>
        runBan(
          banRequest(`${P}mod`, "moderator", {
            uid: `${P}target`,
            banned: true,
            durationHours: 25,
            reason: "x",
          }),
        ),
      /at most 24 hours/,
    );
    await assert.rejects(
      () =>
        runBan(
          banRequest(`${P}mod`, "moderator", {
            uid: `${P}target`,
            banned: true,
            durationHours: 0,
            reason: "x",
          }),
        ),
      /owner can ban permanently/,
    );
    await assert.rejects(
      () =>
        runBan(
          banRequest(`${P}mod`, "moderator", {
            uid: `${P}target`,
            banned: false,
            reason: "x",
          }),
        ),
      /lift a suspension/,
    );
  });

  test("a super moderator is capped at 30 days and may not ban "
      + "permanently", async () => {
    await db
      .collection("users")
      .doc(`${P}supermod`)
      .set({ role: "superModerator" });
    await assert.rejects(
      () =>
        runBan(
          banRequest(`${P}supermod`, "superModerator", {
            uid: `${P}target`,
            banned: true,
            durationHours: 721,
            reason: "x",
          }),
        ),
      /at most 720 hours/,
    );
    await assert.rejects(
      () =>
        runBan(
          banRequest(`${P}supermod`, "superModerator", {
            uid: `${P}target`,
            banned: true,
            durationHours: 0,
            reason: "x",
          }),
        ),
      /owner can ban permanently/,
    );
  });

  test("a NON-owner superAdmin attempting a permanent ban is refused and "
      + "recorded", async () => {
    await db.collection("users").doc(FAKE_SUPER).set({ role: "superAdmin" });
    await assert.rejects(
      () =>
        runBan(
          banRequest(FAKE_SUPER, "superAdmin", {
            uid: `${P}target`,
            banned: true,
            durationHours: 0,
            reason: "x",
          }),
        ),
      /owner can ban permanently/,
    );
    const alerts = await db
      .collection("adminAuditLogs")
      .where("action", "==", "security_alert_non_owner_super_admin")
      .where("targetId", "==", FAKE_SUPER)
      .get();
    assert.ok(alerts.size >= 1, "the attempt must be recorded");
  });

  test("a stale claim — role revoked in the record — is refused", async () => {
    await db.collection("users").doc(`${P}mod`).set({ role: "user" });
    await assert.rejects(
      () =>
        runBan(
          banRequest(`${P}mod`, "moderator", {
            uid: `${P}target`,
            banned: true,
            durationHours: 2,
            reason: "x",
          }),
        ),
      /permission/i,
    );
  });

  test("an auditor or ordinary user cannot sanction at all", async () => {
    await db.collection("users").doc(`${P}auditor`).set({ role: "auditor" });
    for (const role of ["auditor", "user"]) {
      await assert.rejects(
        () =>
          runBan(
            banRequest(`${P}auditor`, role, {
              uid: `${P}target`,
              banned: true,
              durationHours: 1,
              reason: "x",
            }),
          ),
        /permission/i,
      );
    }
  });
});

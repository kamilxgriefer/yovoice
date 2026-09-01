// Coverage for applySanction — warnings, communication mutes and lifts.
//
// The boundaries that matter, exactly as with setUserBan:
//
//  1. Tier ceilings: 24h for a moderator, 720h for a super moderator,
//     indefinite for the owner alone — enforced at and just past each
//     boundary.
//  2. Targets: staff accounts are the owner's alone; the protected owner
//     is nobody's, and both denials are AUDITED, not just refused.
//  3. Personal block/mute and staff mute are different mechanisms; the
//     restriction document belongs to the staff path only.
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

const { applySanction } = require("../staff/sanctions");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const adminAuth = getAuth();
const run = applySanction.run ?? applySanction;

const P = "sanc-";
const OWNER = `${P}owner`;
const FAKE_SUPER = `${P}fake-super`;
const SUPERMOD = `${P}supermod`;
const MOD = `${P}mod`;
const AUDITOR = `${P}auditor`;
const TARGET = `${P}target`;
const STAFF_TARGET = `${P}staff-target`;
const CLAIM_STAFF_TARGET = `${P}claim-staff-target`;

function request(uid, role, data, token = {}) {
  return {
    auth: {
      uid,
      token: {
        role,
        auth_time: Math.floor(Date.now() / 1000),
        ...token,
      },
    },
    data,
  };
}

const args = (action, extra = {}) => ({
  action,
  uid: TARGET,
  reason: "repeated harassment",
  ...extra,
});

async function deleteAuthUser(uid) {
  try {
    await adminAuth.deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
  }
}

async function wipeOwn() {
  const uids = [
    OWNER,
    FAKE_SUPER,
    SUPERMOD,
    MOD,
    AUDITOR,
    TARGET,
    STAFF_TARGET,
    CLAIM_STAFF_TARGET,
  ];
  await Promise.all([
    ...uids.map((uid) => db.collection("users").doc(uid).delete()),
    ...uids.map((uid) => db.collection("restrictions").doc(uid).delete()),
    deleteAuthUser(CLAIM_STAFF_TARGET),
  ]);
  for (const action of [
    "warn_user",
    "communication_mute",
    "lift_communication_mute",
    "denied_sanction_attempt",
  ]) {
    const entries = await db
      .collection("adminAuditLogs")
      .where("action", "==", action)
      .get();
    await Promise.all(
      entries.docs
        .filter((doc) => String(doc.data().targetId ?? "").startsWith(P))
        .map((doc) => doc.ref.delete()),
    );
  }
  const warnings = await db
    .collection("userWarnings")
    .doc(TARGET)
    .collection("entries")
    .get();
  await Promise.all(warnings.docs.map((doc) => doc.ref.delete()));
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  await wipeOwn();
  await db.collection("users").doc(OWNER).set({ role: "superAdmin" });
  await db.collection("users").doc(FAKE_SUPER).set({ role: "superAdmin" });
  await db.collection("users").doc(SUPERMOD).set({ role: "superModerator" });
  await db.collection("users").doc(MOD).set({ role: "moderator" });
  await db.collection("users").doc(AUDITOR).set({ role: "auditor" });
  // The target is an ordinary user with VIP — both sanctionable tiers may
  // act on VIP users, and VIP must make no difference.
  await db
    .collection("users")
    .doc(TARGET)
    .set({ role: "user", premiumIdentity: true });
  await db.collection("users").doc(STAFF_TARGET).set({ role: "moderator" });
});

afterEach(() => setProtectedOwnerUidForTests(null));

async function deniedAttempts(detail) {
  const entries = await db
    .collection("adminAuditLogs")
    .where("action", "==", "denied_sanction_attempt")
    .get();
  return entries.docs
    .map((doc) => doc.data())
    .filter(
      (entry) =>
        String(entry.targetId ?? "").startsWith(P) &&
        (!detail || entry.details?.reason === detail),
    );
}

describe("warnings", () => {
  test("a moderator can warn an ordinary/VIP user, recorded twice over", async () => {
    const result = await run(request(MOD, "moderator", args("warn")));
    assert.equal(result.outcome, "warned");

    const warnings = await db
      .collection("userWarnings")
      .doc(TARGET)
      .collection("entries")
      .get();
    assert.equal(warnings.size, 1);
    assert.equal(warnings.docs[0].data().reason, "repeated harassment");

    const audit = await db
      .collection("adminAuditLogs")
      .where("action", "==", "warn_user")
      .get();
    assert.ok(
      audit.docs.some((doc) => doc.data().targetId === TARGET),
      "the warning must be audited",
    );
  });

  test("an auditor cannot warn; an unauthenticated caller cannot call", async () => {
    await assert.rejects(
      () => run(request(AUDITOR, "auditor", args("warn"))),
      /permission/i,
    );
    await assert.rejects(() => run({ auth: null, data: args("warn") }), /signed in/i);
  });
});

describe("communication mute tiers", () => {
  test("a moderator mutes up to 24h; 25h and indefinite are refused, and "
      + "the indefinite probe is audited", async () => {
    const ok = await run(
      request(MOD, "moderator", args("communicationMute", { durationHours: 24 })),
    );
    assert.equal(ok.outcome, "muted");
    const restriction = await db.collection("restrictions").doc(TARGET).get();
    assert.equal(restriction.data().type, "communicationMute");
    assert.equal(restriction.data().appliedByRole, "moderator");

    await assert.rejects(
      () =>
        run(
          request(
            MOD,
            "moderator",
            args("communicationMute", { durationHours: 25 }),
          ),
        ),
      /at most 24 hours/,
    );
    await assert.rejects(
      () =>
        run(
          request(
            MOD,
            "moderator",
            args("communicationMute", { durationHours: 0 }),
          ),
        ),
      /owner can mute indefinitely/,
    );
    const probes = await deniedAttempts("indefiniteMuteBelowOwner");
    assert.equal(probes.length, 1);
  });

  test("a super moderator mutes up to 720h; 721h and indefinite are "
      + "refused", async () => {
    const ok = await run(
      request(
        SUPERMOD,
        "superModerator",
        args("communicationMute", { durationHours: 720 }),
      ),
    );
    assert.equal(ok.outcome, "muted");
    await assert.rejects(
      () =>
        run(
          request(
            SUPERMOD,
            "superModerator",
            args("communicationMute", { durationHours: 721 }),
          ),
        ),
      /at most 720 hours/,
    );
    await assert.rejects(
      () =>
        run(
          request(
            SUPERMOD,
            "superModerator",
            args("communicationMute", { durationHours: 0 }),
          ),
        ),
      /owner can mute indefinitely/,
    );
  });

  test("the owner may mute indefinitely; the record carries no expiry", async () => {
    const result = await run(
      request(
        OWNER,
        "superAdmin",
        args("communicationMute", { durationHours: 0 }),
      ),
    );
    assert.equal(result.outcome, "muted");
    assert.equal(result.expiresAt, null);
    const restriction = await db.collection("restrictions").doc(TARGET).get();
    assert.equal(restriction.data().expiresAt, null);
  });

  test("a FORGED superAdmin gets the super-moderation ceiling, not the "
      + "owner's", async () => {
    await assert.rejects(
      () =>
        run(
          request(
            FAKE_SUPER,
            "superAdmin",
            args("communicationMute", { durationHours: 0 }),
          ),
        ),
      /owner can mute indefinitely/,
    );
    // ...but a bounded mute within 720h is the safe-fallback tier.
    const ok = await run(
      request(
        FAKE_SUPER,
        "superAdmin",
        args("communicationMute", { durationHours: 100 }),
      ),
    );
    assert.equal(ok.outcome, "muted");
  });
});

describe("protected targets", () => {
  test("staff accounts are sanctionable by the owner alone, and the "
      + "attempt below is audited", async () => {
    for (const [uid, role] of [
      [MOD, "moderator"],
      [SUPERMOD, "superModerator"],
      [FAKE_SUPER, "superAdmin"],
    ]) {
      await assert.rejects(
        () =>
          run(request(uid, role, args("warn", { uid: STAFF_TARGET }))),
        /owner can sanction staff/,
        `${role} must not sanction staff`,
      );
    }
    const probes = await deniedAttempts("staffTarget");
    assert.equal(probes.length, 3);

    // The owner CAN warn a staff account.
    const result = await run(
      request(OWNER, "superAdmin", args("warn", { uid: STAFF_TARGET })),
    );
    assert.equal(result.outcome, "warned");
  });

  test("a stale staff claim protects a target whose profile says user",
    async () => {
      await Promise.all([
        db.collection("users").doc(CLAIM_STAFF_TARGET).set({ role: "user" }),
        adminAuth.createUser({
          uid: CLAIM_STAFF_TARGET,
          email: `${CLAIM_STAFF_TARGET}@test.invalid`,
        }),
      ]);
      await adminAuth.setCustomUserClaims(CLAIM_STAFF_TARGET, {
        role: "support",
      });

      await assert.rejects(
        () => run(request(MOD, "moderator", args("warn", {
          uid: CLAIM_STAFF_TARGET,
        }))),
        /owner can sanction staff/,
      );
      const ownerResult = await run(request(OWNER, "superAdmin", args("warn", {
        uid: CLAIM_STAFF_TARGET,
      })));
      assert.equal(ownerResult.outcome, "warned");
    });

  test("NOBODY sanctions the protected owner, and every attempt is "
      + "audited", async () => {
    for (const [uid, role] of [
      [MOD, "moderator"],
      [SUPERMOD, "superModerator"],
      [FAKE_SUPER, "superAdmin"],
    ]) {
      await assert.rejects(
        () => run(request(uid, role, args("warn", { uid: OWNER }))),
        /owner cannot be sanctioned/,
        role,
      );
    }
    const probes = await deniedAttempts("protectedOwnerTarget");
    assert.equal(probes.length, 3);
  });

  test("self-sanction is refused for everyone, the owner included", async () => {
    await assert.rejects(
      () => run(request(OWNER, "superAdmin", args("warn", { uid: OWNER }))),
      /own account/,
    );
    await assert.rejects(
      () => run(request(MOD, "moderator", args("warn", { uid: MOD }))),
      /own account/,
    );
  });

  test("a stale claim — record no longer staff — is refused flat", async () => {
    await db.collection("users").doc(MOD).set({ role: "user" });
    await assert.rejects(
      () => run(request(MOD, "moderator", args("warn"))),
      /permission/i,
    );
  });
});

describe("lifting", () => {
  test("a super moderator lifts a mute; a moderator's attempt is refused "
      + "and audited", async () => {
    await run(
      request(
        SUPERMOD,
        "superModerator",
        args("communicationMute", { durationHours: 48 }),
      ),
    );
    await assert.rejects(
      () => run(request(MOD, "moderator", args("liftMute"))),
      /super moderation can lift/,
    );
    const probes = await deniedAttempts("liftBelowTier");
    assert.equal(probes.length, 1);

    const result = await run(
      request(SUPERMOD, "superModerator", args("liftMute")),
    );
    assert.equal(result.outcome, "lifted");
    const restriction = await db.collection("restrictions").doc(TARGET).get();
    assert.equal(restriction.exists, false);
  });

  test("a reason is required for every action", async () => {
    for (const action of ["warn", "communicationMute", "liftMute"]) {
      await assert.rejects(
        () =>
          run(
            request(OWNER, "superAdmin", {
              action,
              uid: TARGET,
              reason: "",
            }),
          ),
        /reason is required/,
      );
    }
  });

  test("an unsupported action and a malformed uid are refused", async () => {
    await assert.rejects(
      () => run(request(OWNER, "superAdmin", args("deleteAccount"))),
      /Unsupported sanction/,
    );
    await assert.rejects(
      () => run(request(OWNER, "superAdmin", args("warn", { uid: "a/b" }))),
      /uid is required/,
    );
  });
});

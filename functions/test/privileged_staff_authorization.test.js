// Regression coverage for privileged callable authorization outside Clubs.
//
// The threat is a still-valid Firebase ID token after a role was revoked or
// the account was banned. Every callable in this suite must compare that
// claim with the server-written users/{uid}.role mirror before returning
// data or mutating another user's state. Full audit/user/Premium surfaces
// additionally require the secret-confirmed protected owner.
//
//   firebase emulators:start --only firestore,auth --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (getApps().length === 0) initializeApp();

const {
  listAdminAuditLogs,
  getAdminAuditLog,
  getAuditLogFilters,
} = require("../admin/audit");
const { getAdminDashboard } = require("../admin/dashboard");
const {
  getUserRole,
  listAdminUsers,
  setUserBan,
  bootstrapSuperAdmin,
} = require("../admin/users");
const {
  listAdminRooms,
  getAdminRoom,
  setRoomModerationStatus,
  forceEndRoom,
  removeRoomParticipant,
  setParticipantMute,
  setRoomLiveKitControlForTests,
} = require("../admin/rooms");
const {
  adminSetPremiumEntitlements,
} = require("../premium/entitlements");
const { listAdminClubs, getAdminClub } = require("../admin/clubs");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const adminAuth = getAuth();

const run = (callable) => callable.run ?? callable;
const P = "priv-auth-";
const OWNER = `${P}owner`;
const STALE = `${P}stale`;
const MISMATCH = `${P}mismatch`;
const BANNED_MOD = `${P}banned-mod`;
const BANNED_SUPER = `${P}banned-super`;
const DISABLED_MOD = `${P}disabled-mod`;
const DISABLED_SUPER = `${P}disabled-super`;
const FAKE_SUPER = `${P}fake-super`;
const MOD = `${P}moderator`;
const SUPERMOD = `${P}supermod`;
const AUDITOR = `${P}auditor`;
const PLAIN = `${P}plain`;
const TARGET = `${P}target`;
const TARGET_MIRROR_STAFF = `${P}target-mirror-staff`;
const TARGET_CLAIM_STAFF = `${P}target-claim-staff`;
const PUBLIC_ROOM = `${P}public-room`;
const PRIVATE_ROOM = `${P}private-room`;

const ALL_UIDS = [
  OWNER,
  STALE,
  MISMATCH,
  BANNED_MOD,
  BANNED_SUPER,
  DISABLED_MOD,
  DISABLED_SUPER,
  FAKE_SUPER,
  MOD,
  SUPERMOD,
  AUDITOR,
  PLAIN,
  TARGET,
  TARGET_MIRROR_STAFF,
  TARGET_CLAIM_STAFF,
];

function request(uid, role, data = {}, token = {}) {
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

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

async function deleteAuthUser(uid) {
  try {
    await adminAuth.deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
  }
}

async function clearOwnedAuditRows() {
  const snapshot = await db.collection("adminAuditLogs").get();
  await Promise.all(
    snapshot.docs
      .filter((document) => {
        const data = document.data() ?? {};
        return [data.actorId, data.targetId].some((value) =>
          String(value ?? "").startsWith(P),
        );
      })
      .map((document) => document.ref.delete()),
  );
}

async function resetFixtures() {
  await Promise.all([
    ...ALL_UIDS.map((uid) => db.collection("users").doc(uid).delete()),
    db.collection("entitlements").doc(TARGET).delete(),
    db.collection("rooms").doc(PUBLIC_ROOM).delete(),
    db.collection("rooms").doc(PRIVATE_ROOM).delete(),
    clearOwnedAuditRows(),
  ]);

  await Promise.all([
    db.collection("users").doc(OWNER).set({ role: "superAdmin" }),
    db.collection("users").doc(STALE).set({ role: "user" }),
    db.collection("users").doc(MISMATCH).set({ role: "moderator" }),
    db.collection("users").doc(BANNED_MOD).set({
      role: "moderator",
      banned: true,
    }),
    db.collection("users").doc(BANNED_SUPER).set({
      role: "superAdmin",
      banned: true,
    }),
    db.collection("users").doc(DISABLED_MOD).set({
      role: "moderator",
      disabled: true,
    }),
    db.collection("users").doc(DISABLED_SUPER).set({
      role: "superAdmin",
      disabled: true,
    }),
    db.collection("users").doc(FAKE_SUPER).set({ role: "superAdmin" }),
    db.collection("users").doc(MOD).set({ role: "moderator" }),
    db.collection("users").doc(SUPERMOD).set({ role: "superModerator" }),
    db.collection("users").doc(AUDITOR).set({ role: "auditor" }),
    db.collection("users").doc(PLAIN).set({ role: "user" }),
    db.collection("users").doc(TARGET).set({ role: "user" }),
    db.collection("users").doc(TARGET_MIRROR_STAFF).set({ role: "support" }),
    db.collection("users").doc(TARGET_CLAIM_STAFF).set({ role: "user" }),
    db.collection("rooms").doc(PUBLIC_ROOM).set({
      name: "Public test room",
      visibility: "public",
      status: "active",
      isLive: true,
      participantCount: 0,
      updatedAt: Timestamp.now(),
    }),
    db.collection("rooms").doc(PRIVATE_ROOM).set({
      name: "Private test room",
      visibility: "private",
      status: "active",
      isLive: true,
      participantCount: 0,
      updatedAt: Timestamp.now(),
    }),
  ]);
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  setRoomLiveKitControlForTests({
    endRoom: async () => ({ alreadyAbsent: false }),
    revokeParticipant: async () => ({ alreadyAbsent: false }),
    setPublishingAllowed: async () => ({ alreadyAbsent: false }),
  });
  await resetFixtures();
});

afterEach(() => {
  setProtectedOwnerUidForTests(null);
  setRoomLiveKitControlForTests(null);
});

const ownerOnly = [
  ["listAdminAuditLogs", listAdminAuditLogs],
  ["getAdminAuditLog", getAdminAuditLog],
  ["getAuditLogFilters", getAuditLogFilters],
  ["getAdminDashboard", getAdminDashboard],
  ["getUserRole", getUserRole],
  ["listAdminUsers", listAdminUsers],
  ["adminSetPremiumEntitlements", adminSetPremiumEntitlements],
];

const roomStaff = [
  ["listAdminRooms", listAdminRooms],
  ["getAdminRoom", getAdminRoom],
  ["setRoomModerationStatus", setRoomModerationStatus],
  ["forceEndRoom", forceEndRoom],
  ["removeRoomParticipant", removeRoomParticipant],
  ["setParticipantMute", setParticipantMute],
  ["listAdminClubs", listAdminClubs],
  ["getAdminClub", getAdminClub],
];

describe("protected-owner callables", () => {
  for (const [name, callable] of ownerOnly) {
    test(`${name} rejects a revoked claim, mismatched mirror, ban and forged owner`,
      async () => {
        const handler = run(callable);
        for (const [uid, role] of [
          [STALE, "superAdmin"],
          [MISMATCH, "superAdmin"],
          [BANNED_SUPER, "superAdmin"],
          [DISABLED_SUPER, "superAdmin"],
          [FAKE_SUPER, "superAdmin"],
          [AUDITOR, "auditor"],
        ]) {
          await expectCode(handler(request(uid, role)), "permission-denied");
        }
      });
  }

  test("the confirmed owner reaches the full audit browser", async () => {
    await db.collection("adminAuditLogs").doc(`${P}entry`).set({
      action: "test_action",
      actorId: OWNER,
      actorEmail: "owner@test.invalid",
      targetId: TARGET,
      details: { privateReason: "owner-only" },
      createdAt: Timestamp.now(),
    });

    const result = await run(listAdminAuditLogs)(
      request(OWNER, "superAdmin", { limit: 10 }),
    );
    const entry = result.logs.find((log) => log.id === `${P}entry`);
    assert.equal(entry.actor.email, "owner@test.invalid");
    assert.equal(entry.details.privateReason, "owner-only");
  });

  test("a stale owner sign-in cannot grant Premium", async () => {
    await assert.rejects(
      run(adminSetPremiumEntitlements)(request(
        OWNER,
        "superAdmin",
        { uid: TARGET, plan: "monthly", days: 30 },
        {
          auth_time: Math.floor(Date.now() / 1000) - (5 * 60) - 1,
        },
      )),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        assert.equal(
          error.details?.reason,
          "recent-authentication-required",
        );
        return true;
      },
    );

    assert.equal(
      (await db.collection("entitlements").doc(TARGET).get()).exists,
      false,
    );
    assert.notEqual(
      (await db.collection("users").doc(TARGET).get()).data()
        .premiumIdentity,
      true,
    );
  });

  test("a matching auditor still cannot read the unscoped full audit", async () => {
    await expectCode(
      run(listAdminAuditLogs)(request(AUDITOR, "auditor", { limit: 10 })),
      "permission-denied",
    );
  });
});

describe("room staff callables", () => {
  for (const [name, callable] of roomStaff) {
    test(`${name} rejects stale, mismatched and banned staff authority`,
      async () => {
        const handler = run(callable);
        for (const [uid, role] of [
          [STALE, "moderator"],
          [MISMATCH, "superModerator"],
          [BANNED_MOD, "moderator"],
          [DISABLED_MOD, "moderator"],
          [PLAIN, "user"],
        ]) {
          await expectCode(handler(request(uid, role)), "permission-denied");
        }
      });
  }

  test("a moderator cannot quarantine a room", async () => {
    await expectCode(
      run(setRoomModerationStatus)(request(MOD, "moderator", {
        roomId: PUBLIC_ROOM,
        suspended: true,
        reason: "security review",
      })),
      "permission-denied",
    );
  });

  test("a moderator ends only a public room and only with a reason", async () => {
    await expectCode(
      run(forceEndRoom)(request(MOD, "moderator", {
        roomId: PRIVATE_ROOM,
        reason: "security review",
      })),
      "permission-denied",
    );
    await expectCode(
      run(forceEndRoom)(request(MOD, "moderator", {
        roomId: PUBLIC_ROOM,
      })),
      "invalid-argument",
    );

    const result = await run(forceEndRoom)(request(MOD, "moderator", {
      roomId: PUBLIC_ROOM,
      reason: "security review",
    }));
    assert.equal(result.success, true);
    assert.equal(result.isLive, false);
  });

  test("a matching moderator can list rooms", async () => {
    const result = await run(listAdminRooms)(
      request(MOD, "moderator", { limit: 10 }),
    );
    assert.ok(result.rooms.some((room) => room.id === PUBLIC_ROOM));
  });
});

describe("staff-target and bootstrap fail-closed behavior", () => {
  test("either side of a target role mismatch protects it from moderators",
    async () => {
      for (const [uid, claimRole] of [
        [TARGET_MIRROR_STAFF, "user"],
        [TARGET_CLAIM_STAFF, "support"],
      ]) {
        await deleteAuthUser(uid);
        await adminAuth.createUser({ uid, email: `${uid}@test.invalid` });
        await adminAuth.setCustomUserClaims(uid, { role: claimRole });

        await expectCode(
          run(setUserBan)(request(MOD, "moderator", {
            uid,
            banned: true,
            durationHours: 1,
            reason: "must be owner-only",
          })),
          "permission-denied",
        );
      }
    });

  test("a server-banned protected uid cannot bootstrap ownership", async () => {
    await deleteAuthUser(OWNER);
    await adminAuth.createUser({
      uid: OWNER,
      email: `${OWNER}@test.invalid`,
      emailVerified: true,
    });
    await db.collection("users").doc(OWNER).set({
      role: "user",
      banned: true,
    });

    await expectCode(
      run(bootstrapSuperAdmin)({
        auth: {
          uid: OWNER,
          token: {
            role: "user",
            email_verified: true,
            auth_time: Math.floor(Date.now() / 1000),
          },
        },
        data: {},
      }),
      "permission-denied",
    );
  });
});

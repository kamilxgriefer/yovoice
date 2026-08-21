// getStaffOverview: every count is a real aggregate and every list a
// real query — and the whole thing is owner-only.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { getStaffOverview } = require("../staff/overview");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const run = getStaffOverview.run ?? getStaffOverview;

const P = "so-";
const OWNER_UID = `${P}owner`;

const DOCS = [
  ["users", OWNER_UID, { role: "superAdmin" }],
  ["users", `${P}mod`, { role: "moderator" }],
  [
    "userDirectory",
    `${P}mod`,
    { isStaff: true, isVip: false, banned: false, restricted: false },
  ],
  [
    "userDirectory",
    `${P}vip`,
    { isStaff: false, isVip: true, banned: false, restricted: false },
  ],
  [
    "rooms",
    `${P}room`,
    {
      name: "Overview Room",
      status: "active",
      isLive: true,
      hostId: `${P}mod`,
      hostName: "Mod",
      participantCount: 3,
    },
  ],
  // THE MAJORITY PRODUCTION SHAPE: no `status` key at all — 25 of the 45
  // rooms. `where("status", "==", "active")` matches only documents where
  // the field is present and equal, so the two-equality form this overview
  // used dropped every one of them from both the count and the list.
  // Deliberately named to sort AFTER `${P}room` so it takes the next slot
  // of the `limit(5)` listing rather than that room's.
  [
    "rooms",
    `${P}room-legacy`,
    {
      name: "Legacy Overview Room",
      isLive: true,
      hostId: `${P}mod`,
      hostName: "Mod",
      participantCount: 2,
    },
  ],
  // The control: absent status reads as active, an EXPLICIT one still
  // decides. Moderation always writes the field, which is why defaulting
  // the absent case to active loosens nothing moderation relies on.
  [
    "rooms",
    `${P}room-suspended`,
    {
      name: "Suspended Overview Room",
      status: "suspended",
      isLive: true,
      hostId: `${P}mod`,
      hostName: "Mod",
      participantCount: 1,
    },
  ],
  [
    "reports",
    `${P}report`,
    {
      status: "open",
      targetType: "globalMessage",
      reason: "spam",
      reporterId: `${P}vip`,
      reportedUserId: `${P}mod`,
      createdAt: Timestamp.now(),
    },
  ],
  [
    "restrictions",
    `${P}muted`,
    {
      type: "communicationMute",
      expiresAt: null,
      reason: "test",
    },
  ],
  [
    "adminAuditLogs",
    `${P}sanction`,
    {
      action: "communication_mute",
      actorId: OWNER_UID,
      actorRole: "superAdmin",
      actorEmail: "owner@example.invalid",
      targetType: "account",
      targetId: `${P}muted`,
      details: { reason: "test", durationHours: 0 },
      createdAt: Timestamp.now(),
    },
  ],
  [
    "adminAuditLogs",
    `${P}rolechange`,
    {
      action: "assign_user_role",
      actorId: OWNER_UID,
      actorRole: "superAdmin",
      targetType: "user",
      targetId: `${P}mod`,
      details: { role: "moderator", previousRole: "user", reason: "test" },
      createdAt: Timestamp.now(),
    },
  ],
];

async function wipe() {
  await Promise.all(
    DOCS.map(([collection, id]) => db.collection(collection).doc(id).delete()),
  );
}

async function seed() {
  await Promise.all(
    DOCS.map(([collection, id, data]) =>
      db.collection(collection).doc(id).set(data),
    ),
  );
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER_UID);
  await wipe();
});

describe("getStaffOverview", () => {
  test("counts and lists reflect the seeded world, without emails", async () => {
    await seed();

    const result = await run({
      auth: { uid: OWNER_UID, token: { role: "superAdmin" } },
      data: {},
    });

    assert.ok(result.counts.totalUsers >= 2);
    assert.ok(result.counts.activeRooms >= 1);
    assert.ok(result.counts.openReports >= 1);
    assert.ok(result.counts.restrictedAccounts >= 1);
    assert.ok(result.counts.staffMembers >= 1);
    assert.ok(result.counts.vipUsers >= 1);

    assert.ok(
      result.latestOpenReports.some((row) => row.id === `${P}report`),
    );
    assert.ok(result.activeRooms.some((row) => row.id === `${P}room`));
    assert.ok(
      result.recentSanctions.some((row) => row.action === "communication_mute"),
    );
    assert.ok(
      result.recentRoleChanges.some((row) => row.action === "assign_user_role"),
    );

    // Summaries carry ids and roles, never an email.
    const serialised = JSON.stringify(result);
    assert.ok(!serialised.includes("owner@example.invalid"));
  });

  // THE ONE THAT MATTERS. Both the count and the list ran
  // `where("status", "==", "active").where("isLive", "==", true)`, which is
  // invisible to a room that carries no `status` field — the shape 25 of the
  // 45 production rooms have. The overview under-reported live rooms to the
  // only people who can act on them.
  test("a live room with no status field is counted and listed", async () => {
    await seed();

    const result = await run({
      auth: { uid: OWNER_UID, token: { role: "superAdmin" } },
      data: {},
    });

    const listed = result.activeRooms.map((row) => row.id);

    assert.ok(
      listed.includes(`${P}room-legacy`),
      "an absent `status` reads as active, exactly as firestore.rules' own " +
        ".get('status', 'active') reads it",
    );
    assert.ok(listed.includes(`${P}room`), "an explicit active room too");
    assert.ok(
      !listed.includes(`${P}room-suspended`),
      "an EXPLICIT inactive status still decides",
    );

    // The count is over the whole shared collection, so only a floor is
    // this file's to claim: two of the rooms it seeded are live and active.
    assert.ok(result.counts.activeRooms >= 2);
    assert.ok(result.counts.activeRooms >= result.activeRooms.length);

    // The summary of a legacy room is complete, not a degraded row.
    const legacy = result.activeRooms.find(
      (row) => row.id === `${P}room-legacy`,
    );
    assert.equal(legacy.name, "Legacy Overview Room");
    assert.equal(legacy.hostId, `${P}mod`);
    assert.equal(legacy.participantCount, 2);
  });

  test("everyone below the confirmed owner is refused", async () => {
    await seed();

    await assert.rejects(
      () =>
        run({
          auth: { uid: `${P}mod`, token: { role: "moderator" } },
          data: {},
        }),
      /permission|super administrator/i,
    );

    // A forged superAdmin (claim + record, wrong uid) is refused too.
    await db.collection("users").doc(`${P}forged`).set({ role: "superAdmin" });
    await assert.rejects(
      () =>
        run({
          auth: { uid: `${P}forged`, token: { role: "superAdmin" } },
          data: {},
        }),
      /reserved for the application owner/i,
    );
    await db.collection("users").doc(`${P}forged`).delete();
  });
});

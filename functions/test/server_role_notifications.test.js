/**
 * "You were promoted" / "you were made owner" (ADR-212).
 *
 * The three properties this suite exists for:
 *   - a PROMOTION notifies the member, with the server's name and the exact
 *     membership revision it produced;
 *   - a DEMOTION, and any other role change that does not raise the member's
 *     power, notifies nobody — a role an admin can cycle must not be a way
 *     to push repeated notifications at somebody;
 *   - the notice never turns a committed membership change into an error,
 *     and a row whose promotion was undone fails the push boundary.
 */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice-server-roles";

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp(
    { projectId: "demo-yovoice-server-roles" },
    `server-roles-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const { createServerMembershipService } = require("../servers/memberships");
const {
  PROMOTION_BUDGET,
  chargePromotionBudget,
  createServerRolePromotionNotifier,
  isPromotion,
  promotionBudgetKey,
  serverRoleNotificationId,
} = require("../notifications/server_roles");
const {
  serverRoleSourceIsCurrent,
} = require("../notifications/engagement_source");

const NOW_MS = 1_930_000_000_000;
const request = (uid, data) => ({
  auth: { uid, token: { email_verified: true } },
  data,
});
const emulatorTest = (name, fn) => test(
  `Server role notifications: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);

after(async () => {
  if (app) await require("firebase-admin/app").deleteApp(app);
});

test("only a rise in role power is a promotion", () => {
  assert.equal(isPromotion("member", "moderator"), true);
  assert.equal(isPromotion("moderator", "admin"), true);
  assert.equal(isPromotion("coOwner", "owner"), true);
  assert.equal(isPromotion("admin", "member"), false);
  assert.equal(isPromotion("member", "member"), false);
  assert.equal(isPromotion("member", "guest"), false);
  assert.equal(isPromotion("member", "nonsense"), false);
});

async function user(prefix = "role-user") {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${uid}`,
    status: "active",
  });
  return uid;
}

async function fixture({ notifier = null } = {}) {
  const ownerId = await user("role-owner");
  const dependencies = { db, Timestamp, clock: () => NOW_MS };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerMembershipService({
      ...dependencies,
      notifyServerRolePromotion: notifier ??
        createServerRolePromotionNotifier({ firestore: db }),
    }),
  };
  const created = await service.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType: "community",
    templateVersion: 1,
    name: "Role server",
    description: "",
    privacy: "public",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const anchors = await db.collection("rooms")
    .where("serverId", "==", created.serverId).get();
  for (const anchor of anchors.docs) {
    await anchor.ref.update({
      status: "active",
      serverActivationState: "active",
      hostId: ownerId,
    });
  }
  async function join() {
    const uid = await user("role-member");
    await service.joinServerV1(request(uid, {
      serverId: created.serverId,
      requestId: randomUUID(),
    }));
    return uid;
  }
  return { ...created, ...service, ownerId, join };
}

const inbox = async (uid) =>
  (await db.collection(`users/${uid}/notifications`).get()).docs;

emulatorTest("a promotion notifies the member, a demotion notifies nobody",
  async () => {
    const value = await fixture();
    const member = await value.join();
    const promoted = await value.setServerMemberRoleV1(
      request(value.ownerId, {
        serverId: value.serverId,
        requestId: randomUUID(),
        memberId: member,
        role: "moderator",
      }),
    );
    assert.equal(promoted.role, "moderator");
    const rows = await inbox(member);
    assert.equal(rows.length, 1);
    const row = rows[0].data();
    assert.equal(
      rows[0].id,
      serverRoleNotificationId(
        value.serverId,
        member,
        promoted.membershipRevision,
      ),
    );
    assert.equal(row.type, "serverRole");
    assert.equal(row.actorId, value.ownerId);
    assert.equal(row.targetId, value.serverId);
    assert.equal(row.targetLabel, "Role server");
    assert.equal(row.sourcePath, `clubs/${value.serverId}/members/${member}`);
    assert.equal(row.sourceGeneration, String(promoted.membershipRevision));
    assert.equal(row.actorPhotoUrl, null);

    // Demotion: the server state changes, the inbox does not.
    const demoted = await value.setServerMemberRoleV1(
      request(value.ownerId, {
        serverId: value.serverId,
        requestId: randomUUID(),
        memberId: member,
        role: "member",
      }),
    );
    assert.equal(demoted.role, "member");
    assert.equal((await inbox(member)).length, 1);

    // The push boundary refuses the earlier row now that the membership
    // revision moved on.
    assert.equal(
      await serverRoleSourceIsCurrent({
        recipientId: member,
        notification: {
          type: "serverRole",
          actorId: value.ownerId,
          targetId: value.serverId,
          sourcePath: `clubs/${value.serverId}/members/${member}`,
          sourceGeneration: String(promoted.membershipRevision),
        },
        reader: db,
        firestore: db,
      }),
      false,
    );
  });

emulatorTest("a blocked promoter writes no row but still changes the role",
  async () => {
    const value = await fixture();
    const member = await value.join();
    await db.doc(`users/${member}/blocked/${value.ownerId}`)
      .set({ blocked: true });
    const promoted = await value.setServerMemberRoleV1(
      request(value.ownerId, {
        serverId: value.serverId,
        requestId: randomUUID(),
        memberId: member,
        role: "admin",
      }),
    );
    assert.equal(promoted.role, "admin");
    assert.equal((await inbox(member)).length, 0);
    const stored = await db
      .doc(`clubs/${value.serverId}/members/${member}`).get();
    assert.equal(stored.data().role, "admin");
  });

emulatorTest("ownership transfer notifies the new owner exactly once", async () => {
  const value = await fixture();
  const member = await value.join();
  await value.transferServerOwnershipV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    newOwnerId: member,
  }));
  const rows = await inbox(member);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].data().type, "serverRole");
  assert.equal(rows[0].data().actorId, value.ownerId);
  // The former owner becomes coOwner: a demotion, and silent.
  assert.equal((await inbox(value.ownerId)).length, 0);
  const current = await db
    .doc(`clubs/${value.serverId}/members/${member}`).get();
  assert.equal(current.data().role, "owner");
  assert.equal(
    await serverRoleSourceIsCurrent({
      recipientId: member,
      notification: {
        type: "serverRole",
        actorId: value.ownerId,
        targetId: value.serverId,
        sourcePath: `clubs/${value.serverId}/members/${member}`,
        sourceGeneration: rows[0].data().sourceGeneration,
      },
      reader: db,
      firestore: db,
    }),
    true,
  );
});

emulatorTest("a failing notifier never fails the role change", async () => {
  const value = await fixture({
    notifier: async () => {
      throw new Error("simulated notification outage");
    },
  });
  const member = await value.join();
  const promoted = await value.setServerMemberRoleV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    memberId: member,
    role: "moderator",
  }));
  assert.equal(promoted.role, "moderator");
  assert.equal((await inbox(member)).length, 0);
  const stored = await db
    .doc(`clubs/${value.serverId}/members/${member}`).get();
  assert.equal(stored.data().role, "moderator");
});

// ---------------------------------------------------------------------
// Review round, 2026-09-20. Silence on demotion was not enough on its own:
// `authorizationRevision` moves on EVERY role change, so the notification
// id, the bell row and the push were all fresh again each time an owner
// demoted and re-promoted the same member. The notice is now charged
// against a per-actor-per-recipient-per-role budget.
// ---------------------------------------------------------------------

emulatorTest("cycling a role announces it once, not once per revision",
  async () => {
    const value = await fixture();
    const member = await value.join();
    const setRole = (role) => value.setServerMemberRoleV1(request(value.ownerId, {
      serverId: value.serverId,
      requestId: randomUUID(),
      memberId: member,
      role,
    }));

    const first = await setRole("moderator");
    for (let round = 0; round < 3; round += 1) {
      await setRole("member");
      await setRole("moderator");
    }
    const rows = await inbox(member);
    assert.equal(
      rows.length,
      1,
      "a cycled role must not be a repeatable push channel",
    );
    assert.equal(
      rows[0].id,
      serverRoleNotificationId(value.serverId, member, first.membershipRevision),
    );
    // The role itself still changed every time; only the notice is bounded.
    const stored = await db
      .doc(`clubs/${value.serverId}/members/${member}`).get();
    assert.equal(stored.data().role, "moderator");
    assert.ok(
      stored.data().authorizationRevision > first.membershipRevision,
      "the membership revision kept moving",
    );

    // A role the member has NOT been given today is still real news.
    const admin = await setRole("admin");
    const after = await inbox(member);
    assert.equal(after.length, 2);
    assert.ok(after.some((row) => row.id === serverRoleNotificationId(
      value.serverId,
      member,
      admin.membershipRevision,
    )));
  });

emulatorTest("the budget key separates actors, recipients and roles",
  async () => {
    const actor = `role-actor-${randomUUID()}`;
    const member = `role-recipient-${randomUUID()}`;
    const charge = (uid, target, role) =>
      chargePromotionBudget(db, uid, target, role, NOW_MS);
    assert.equal(await charge(actor, member, "moderator"), true);
    assert.equal(await charge(actor, member, "moderator"), false);
    // A different role, a different recipient and a different actor each
    // have their own budget.
    assert.equal(await charge(actor, member, "admin"), true);
    assert.equal(await charge(actor, `${member}-other`, "moderator"), true);
    assert.equal(await charge(`${actor}-other`, member, "moderator"), true);
    // The window is a day, so the exhausted key stays exhausted.
    assert.equal(
      await chargePromotionBudget(db, actor, member, "moderator",
        NOW_MS + 23 * 60 * 60_000),
      false,
    );
    assert.equal(
      await chargePromotionBudget(db, actor, member, "moderator",
        NOW_MS + 25 * 60 * 60_000),
      true,
    );
    assert.equal(PROMOTION_BUDGET.maxEvents, 1);
    assert.equal(PROMOTION_BUDGET.windowMs, 24 * 60 * 60_000);
    assert.equal(
      promotionBudgetKey("a", "b", "moderator"),
      "a:b:moderator",
    );
  });

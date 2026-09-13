const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp(
    { projectId: "demo-yovoice-servers-family-checkins" },
    `server-family-checkins-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const {
  canonicalFamilyCheckInId,
  createServerFamilyCheckInService,
} = require("../servers/family_checkins");

const NOW_MS = 1_900_000_000_000;
const request = (uid, data) => ({
  auth: { uid, token: { email_verified: true } },
  data,
});
const rejection = (promise, code) => assert.rejects(
  promise,
  (error) => error.code === code,
);
const emulatorTest = (name, fn) => test(
  `Family check-ins: ${name}`,
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

async function user(prefix) {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${prefix}`,
    photoUrl: null,
    status: "active",
  });
  return uid;
}

async function fixture() {
  const ownerId = await user("owner");
  const dependencies = { db, Timestamp, clock: () => NOW_MS };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerFamilyCheckInService(dependencies),
  };
  const created = await service.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType: "family",
    templateVersion: 1,
    name: "Our family",
    description: "",
    privacy: "inviteOnly",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });

  async function addMember(role = "member") {
    const uid = await user(role);
    await db.doc(`clubs/${created.serverId}/members/${uid}`).set({
      userId: uid,
      displayName: `Canonical ${role}`,
      photoUrl: null,
      role,
      isOnline: false,
      joinedAt: Timestamp.fromMillis(NOW_MS),
      invitedBy: ownerId,
      authorizationRevision: 1,
    });
    return uid;
  }

  return {
    ...created,
    ...service,
    ownerId,
    addMember,
    reference: (checkInId) => db.doc(
      `clubs/${created.serverId}/checkIns/${checkInId}`,
    ),
  };
}

emulatorTest("a member posts one canonical location-free status", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const data = {
    serverId: value.serverId,
    requestId: randomUUID(),
    status: "onMyWay",
  };
  const created = await value.createServerFamilyCheckInV1(request(memberId, data));
  assert.equal(
    created.checkInId,
    canonicalFamilyCheckInId(memberId, data.requestId),
  );
  assert.deepEqual(
    await value.createServerFamilyCheckInV1(request(memberId, data)),
    created,
  );
  const stored = (await value.reference(created.checkInId).get()).data();
  assert.equal(stored.userId, memberId);
  assert.equal(stored.status, "onMyWay");
  assert.equal(Object.hasOwn(stored, "location"), false);
  assert.equal(Object.hasOwn(stored, "latitude"), false);
  assert.equal(Object.hasOwn(stored, "longitude"), false);
});

emulatorTest("foreign servers and unsupported payloads fail closed", async () => {
  const value = await fixture();
  const outsiderId = await user("outsider");
  await rejection(value.createServerFamilyCheckInV1(request(outsiderId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    status: "home",
  })), "permission-denied");
  await rejection(value.createServerFamilyCheckInV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    status: "emergency",
  })), "invalid-argument");
  await rejection(value.createServerFamilyCheckInV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    status: "home",
    location: "somewhere",
  })), "invalid-argument");
});

emulatorTest("only the author or a manager may remove a check-in", async () => {
  const value = await fixture();
  const authorId = await value.addMember();
  const peerId = await value.addMember();
  const managerId = await value.addMember("admin");
  async function create() {
    return value.createServerFamilyCheckInV1(request(authorId, {
      serverId: value.serverId,
      requestId: randomUUID(),
      status: "allGood",
    }));
  }
  const first = await create();
  const deletion = (uid, checkInId, requestId = randomUUID()) =>
    value.deleteServerFamilyCheckInV1(request(uid, {
      serverId: value.serverId,
      checkInId,
      requestId,
    }));
  await rejection(deletion(peerId, first.checkInId), "permission-denied");
  const authorRequestId = randomUUID();
  const deleted = await deletion(authorId, first.checkInId, authorRequestId);
  assert.equal(deleted.deleted, true);
  assert.deepEqual(
    await deletion(authorId, first.checkInId, authorRequestId),
    deleted,
  );

  const second = await create();
  assert.equal((await deletion(managerId, second.checkInId)).deleted, true);
});

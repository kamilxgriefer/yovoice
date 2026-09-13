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
    { projectId: "demo-yovoice-servers-follows" },
    `server-follows-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const { createServerFollowService } = require("../servers/follows");

const NOW_MS = 1_900_000_000_000;
const request = (uid, data) => ({
  auth: { uid, token: { email_verified: true } },
  data,
});
const emulatorTest = (name, fn) => test(
  `Community server follows: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);
const rejection = (promise, code) => assert.rejects(
  promise,
  (error) => error.code === code,
);

after(async () => {
  if (app) await require("firebase-admin/app").deleteApp(app);
});

async function user(prefix) {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${prefix}`,
    status: "active",
  });
  return uid;
}

async function fixture(type = "community") {
  const ownerId = await user("follow-owner");
  const dependencies = { db, Timestamp, clock: () => NOW_MS };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerFollowService(dependencies),
  };
  const created = await service.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType: type,
    templateVersion: 1,
    name: "Tech after hours",
    description: "",
    privacy: type === "community" ? "public" : "inviteOnly",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  return { ownerId, ...created, ...service };
}

emulatorTest("follow and unfollow write both private projections", async () => {
  const value = await fixture();
  const follow = {
    serverId: value.serverId,
    requestId: randomUUID(),
    following: true,
  };
  const result = await value.setCommunityServerFollowV1(
    request(value.ownerId, follow),
  );
  assert.deepEqual(result, {
    serverId: value.serverId,
    following: true,
    changed: true,
  });
  assert.deepEqual(
    await value.setCommunityServerFollowV1(request(value.ownerId, follow)),
    result,
  );
  assert.equal((await db.doc(
    `clubs/${value.serverId}/followers/${value.ownerId}`,
  ).get()).data().following, true);
  assert.equal((await db.doc(
    `users/${value.ownerId}/serverFollows/${value.serverId}`,
  ).get()).data().following, true);

  const unfollowed = await value.setCommunityServerFollowV1(
    request(value.ownerId, {
      serverId: value.serverId,
      requestId: randomUUID(),
      following: false,
    }),
  );
  assert.equal(unfollowed.following, false);
  assert.equal(unfollowed.changed, true);
  assert.equal((await db.doc(
    `clubs/${value.serverId}/followers/${value.ownerId}`,
  ).get()).exists, false);
  assert.equal((await db.doc(
    `users/${value.ownerId}/serverFollows/${value.serverId}`,
  ).get()).exists, false);
});

emulatorTest("only a member of a community server can set the preference", async () => {
  const community = await fixture();
  const outsiderId = await user("follow-outsider");
  await rejection(community.setCommunityServerFollowV1(request(outsiderId, {
    serverId: community.serverId,
    requestId: randomUUID(),
    following: true,
  })), "permission-denied");

  const friends = await fixture("friends");
  await rejection(friends.setCommunityServerFollowV1(request(friends.ownerId, {
    serverId: friends.serverId,
    requestId: randomUUID(),
    following: true,
  })), "permission-denied");
});

emulatorTest("unexpected input is rejected without changing state", async () => {
  const value = await fixture();
  await rejection(value.setCommunityServerFollowV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    following: true,
    userId: value.ownerId,
  })), "invalid-argument");
  assert.equal((await db.doc(
    `clubs/${value.serverId}/followers/${value.ownerId}`,
  ).get()).exists, false);
});

emulatorTest("a missing or divergent private mirror fails closed", async () => {
  const value = await fixture();
  const first = {
    serverId: value.serverId,
    requestId: randomUUID(),
    following: true,
  };
  await value.setCommunityServerFollowV1(request(value.ownerId, first));
  await db.doc(`users/${value.ownerId}/serverFollows/${value.serverId}`).delete();

  await rejection(value.setCommunityServerFollowV1(request(value.ownerId, first)),
    "data-loss");
  await rejection(value.setCommunityServerFollowV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
    following: false,
  })), "data-loss");
  assert.equal((await db.doc(
    `clubs/${value.serverId}/followers/${value.ownerId}`,
  ).get()).exists, true);
});

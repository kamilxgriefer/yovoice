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
    { projectId: "demo-yovoice-servers-shared-list" },
    `server-shared-list-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const {
  canonicalListItemId,
  createServerSharedListService,
} = require("../servers/shared_list");

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
  `Family shared list: ${name}`,
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
    displayName: `Canonical ${uid}`,
    status: "active",
  });
  return uid;
}

async function fixture() {
  const ownerId = await user("list-owner");
  const dependencies = { db, Timestamp, clock: () => NOW_MS };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerSharedListService(dependencies),
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
  const channelRows = await db.doc(`clubs/${created.serverId}`)
    .collection("channels").get();
  const listChannel = channelRows.docs.find((doc) => doc.data().kind === "list");
  const textChannel = channelRows.docs.find((doc) => doc.data().kind === "text");
  assert.ok(listChannel);
  assert.ok(textChannel);

  async function addMember(role = "member") {
    const uid = await user(`list-${role}`);
    await db.doc(`clubs/${created.serverId}/members/${uid}`).set({
      userId: uid,
      displayName: `Canonical ${uid}`,
      photoUrl: null,
      role,
      isOnline: false,
      joinedAt: Timestamp.fromMillis(NOW_MS),
      invitedBy: ownerId,
      authorizationRevision: 1,
    });
    return uid;
  }

  const itemReference = (itemId) => db.doc(
    `clubs/${created.serverId}/channels/${listChannel.id}/listItems/${itemId}`,
  );
  const createData = (overrides = {}) => ({
    serverId: created.serverId,
    channelId: listChannel.id,
    requestId: randomUUID(),
    text: "Milk",
    ...overrides,
  });
  return {
    ...created,
    ...service,
    ownerId,
    listChannelId: listChannel.id,
    textChannelId: textChannel.id,
    addMember,
    itemReference,
    createData,
  };
}

emulatorTest("create and toggle are canonical and replay-safe", async () => {
  const value = await fixture();
  const data = value.createData();
  const created = await value.createServerListItemV1(request(value.ownerId, data));
  assert.equal(created.itemId, canonicalListItemId(value.ownerId, data.requestId));
  assert.equal(created.revision, 1);
  assert.deepEqual(
    await value.createServerListItemV1(request(value.ownerId, data)),
    created,
  );

  const memberId = await value.addMember();
  const update = {
    serverId: value.serverId,
    channelId: value.listChannelId,
    itemId: created.itemId,
    requestId: randomUUID(),
    expectedRevision: 1,
    patch: { checked: true },
  };
  const changed = await value.updateServerListItemV1(request(memberId, update));
  assert.equal(changed.revision, 2);
  assert.deepEqual(
    await value.updateServerListItemV1(request(memberId, update)),
    changed,
  );
  const stored = (await value.itemReference(created.itemId).get()).data();
  assert.equal(stored.checked, true);
  assert.equal(stored.checkedById, memberId);
});

emulatorTest("only the family list channel and authorized members are accepted", async () => {
  const value = await fixture();
  const outsiderId = await user("list-outsider");
  await rejection(value.createServerListItemV1(request(outsiderId, value.createData())),
    "permission-denied");
  await rejection(value.createServerListItemV1(request(value.ownerId, value.createData({
    channelId: value.textChannelId,
  }))), "permission-denied");
  await rejection(value.createServerListItemV1(request(value.ownerId, {
    ...value.createData(),
    unsupported: true,
  })), "invalid-argument");
});

emulatorTest("concurrent updates use the item revision", async () => {
  const value = await fixture();
  const created = await value.createServerListItemV1(request(
    value.ownerId,
    value.createData(),
  ));
  await value.updateServerListItemV1(request(value.ownerId, {
    serverId: value.serverId,
    channelId: value.listChannelId,
    itemId: created.itemId,
    requestId: randomUUID(),
    expectedRevision: 1,
    patch: { text: "Oat milk" },
  }));
  await rejection(value.updateServerListItemV1(request(value.ownerId, {
    serverId: value.serverId,
    channelId: value.listChannelId,
    itemId: created.itemId,
    requestId: randomUUID(),
    expectedRevision: 1,
    patch: { checked: true },
  })), "aborted");
});

emulatorTest("the author or a moderator may delete an item", async () => {
  const value = await fixture();
  const authorId = await value.addMember();
  const peerId = await value.addMember();
  const moderatorId = await value.addMember("moderator");
  const first = await value.createServerListItemV1(request(authorId, value.createData()));
  const deletion = (actorId, itemId) => value.deleteServerListItemV1(request(actorId, {
    serverId: value.serverId,
    channelId: value.listChannelId,
    itemId,
    requestId: randomUUID(),
    expectedRevision: 1,
  }));
  await rejection(deletion(peerId, first.itemId), "permission-denied");
  const deleted = await deletion(authorId, first.itemId);
  assert.equal(deleted.deleted, true);
  assert.equal((await value.itemReference(first.itemId).get()).exists, false);

  const second = await value.createServerListItemV1(request(authorId, value.createData()));
  assert.equal((await deletion(moderatorId, second.itemId)).deleted, true);
});

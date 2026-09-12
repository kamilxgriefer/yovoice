const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

// No default cloud endpoint or ambient credential access. These tests only
// create fixtures in an explicitly selected localhost demo emulator project.
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const projectId = "demo-yovoice-servers-backend";
let db;
let app;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp({ projectId }, `servers-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { canonicalLiveKitRoomName, canonicalServerId, serverChannelRefId } = require("../servers/contract");
const { readChannelAccess, readBoundSessionAccess } = require("../servers/authority");
const { rateLimitReference } = require("../integrity/guards");

const fixture = async () => {
  const uid = `sv-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: "Canonical owner", status: "active" });
  const deps = { db, Timestamp, clock: () => 1_900_000_000_000 };
  return { uid, ...createServerCreationService(deps), ...createServerChannelService(deps) };
};
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const input = (overrides = {}) => ({ requestId: randomUUID(), serverType: "friends", templateVersion: 1,
  name: "Trusted server", description: "", privacy: "inviteOnly", defaultLanguage: "English", ...overrides });
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const access = (uid, serverId, channelId, extra = {}) => db.runTransaction((transaction) =>
  readChannelAccess({ db, transaction, uid, serverId, channelId, allowHeld: true, ...extra }));

after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

emulatorTest("atomic company creation seeds only canonical owner, private HR grants and idle room bindings", async () => {
  const service = await fixture();
  const result = await service.createServerV1(request(service.uid, input({ serverType: "company", defaultLanguage: "Polish" })));
  const root = (await db.doc(`clubs/${result.serverId}`).get()).data();
  assert.equal(root.status, "preparing");
  assert.equal(root.serverActivationState, "held");
  assert.equal(root.onlineCount, 0);
  assert.equal(root.memberCount, 1);
  assert.equal(root.ownerName, "Canonical owner");
  assert.equal(root.entitlementPolicyId, "freeServersV1");
  const members = await db.collection(`clubs/${result.serverId}/members`).get();
  assert.equal(members.size, 1);
  assert.equal(members.docs[0].data().isOnline, false);
  assert.equal(members.docs[0].data().authorizationRevision, 1);
  const channels = await db.collection(`clubs/${result.serverId}/channels`).get();
  assert.equal(channels.size, 9);
  for (const channelSnapshot of channels.docs) {
    const channel = channelSnapshot.data();
    assert.equal((await channelSnapshot.ref.collection("messages").get()).size, 0);
    if (channel.roomId) {
      const room = (await db.doc(`rooms/${channel.roomId}`).get()).data();
      assert.equal(room.channelId, channelSnapshot.id);
      assert.equal(room.serverId, result.serverId);
      assert.equal(room.isLive, false);
      assert.equal(room.participantCount, 0);
      assert.equal(room.status, "preparing");
      assert.equal(room.hostId, null);
      assert.equal(room.serverOwnerId, service.uid);
    }
    if (channel.accessMode === "restricted") {
      const actual = await access(service.uid, result.serverId, channelSnapshot.id);
      assert.equal(actual.capabilities.manage, true);
      const pointer = (await db.doc(`users/${service.uid}/serverChannelRefs/${serverChannelRefId(result.serverId, channelSnapshot.id)}`).get()).data();
      assert.deepEqual(pointer, { serverId: result.serverId, channelId: channelSnapshot.id });
    }
  }
  await rejection(access(service.uid, result.serverId, result.defaultChannelId, { allowHeld: false }), "permission-denied");
});

emulatorTest("parallel duplicate requests commit one graph; changed payload reuse is rejected", async () => {
  const service = await fixture();
  const data = input();
  const results = await Promise.all(Array.from({ length: 5 }, () => service.createServerV1(request(service.uid, data))));
  assert.equal(new Set(results.map((result) => result.serverId)).size, 1);
  assert.equal(results.filter((result) => result.alreadyExisted === false).length, 1);
  const owned = await db.collection("clubs").where("ownerId", "==", service.uid).get();
  assert.equal(owned.size, 1);
  assert.equal((await db.collection(`clubs/${results[0].serverId}/channels`).get()).size, 6);
  await rejection(service.createServerV1(request(service.uid, { ...data, name: "Changed payload" })), "already-exists");
});

emulatorTest("twentieth free allocation is atomic under parallel creation and seed rooms cost no extra slots", async () => {
  const service = await fixture();
  for (let index = 0; index < 19; index += 1) await db.doc(`clubs/quota-${service.uid}-${index}`).set({
    ownerId: service.uid, serverSchemaVersion: 1, entitlementPolicyId: "freeServersV1", status: "preparing",
  });
  const outcomes = await Promise.allSettled([1, 2].map(() => service.createServerV1(request(service.uid, input()))));
  assert.equal(outcomes.filter((outcome) => outcome.status === "fulfilled").length, 1);
  assert.equal(outcomes.find((outcome) => outcome.status === "rejected").reason.code, "resource-exhausted");
  const owned = await db.collection("clubs").where("ownerId", "==", service.uid).get();
  assert.equal(owned.size, 20);
});

emulatorTest("existing ordinary rooms share free capacity; legacy paid clubs do not become free-server paywalls", async () => {
  const service = await fixture();
  const roomIds = Array.from({ length: 19 }, (_, index) => `ordinary-${service.uid}-${index}`);
  await Promise.all(roomIds.map((id) => db.doc(`rooms/${id}`).set({ hostId: service.uid, status: "active", roomType: "community" })));
  await db.doc(`privateRoomHostGuards/${service.uid}`).set({ schemaVersion: 2, ownerId: service.uid, activeRoomIds: roomIds, capacityLocked: false });
  await db.doc(`clubs/paid-${service.uid}`).set({ ownerId: service.uid, type: "community", status: "active", entitlementPolicyId: "legacyCommunityPremiumV1" });
  await service.createServerV1(request(service.uid, input()));
  await rejection(service.createServerV1(request(service.uid, input())), "resource-exhausted");
});

emulatorTest("family duplicate requests reserve one identity, preserve privacy and reject transferred-away recovery", async () => {
  const service = await fixture();
  const result = await service.createServerV1(request(service.uid, input({ serverType: "family" })));
  assert.equal(result.serverId, `family_${service.uid}`);
  const replay = await service.createServerV1(request(service.uid, input({ serverType: "family", name: "No rename" })));
  assert.equal(replay.serverId, result.serverId);
  assert.equal(replay.alreadyExisted, true);
  assert.equal((await db.doc(`clubs/${result.serverId}`).get()).data().name, "Trusted server");
  await db.doc(`clubs/${result.serverId}`).update({ ownerId: "other-owner" });
  await rejection(service.createServerV1(request(service.uid, input({ serverType: "family" }))), "permission-denied");
});

emulatorTest("foreign child collision rolls creation back and still consumes attempt budget", async () => {
  const service = await fixture();
  const data = input();
  const serverId = canonicalServerId(service.uid, data.requestId, data.serverType);
  await db.doc(`rooms/club_lounge_${serverId}`).set({ hostId: "other" });
  await rejection(service.createServerV1(request(service.uid, data)), "data-loss");
  assert.equal((await db.doc(`clubs/${serverId}`).get()).exists, false);
  assert.equal((await db.doc(`clubs/${serverId}/members/${service.uid}`).get()).exists, false);
  assert.equal((await db.collection(`clubs/${serverId}/channels`).get()).size, 0);
  assert.equal((await rateLimitReference(db, "server.v1.attempt", service.uid).get()).data().count, 1);
});

emulatorTest("channel create/update/reorder are hashed, scoped and revision guarded", async () => {
  const service = await fixture();
  const root = await service.createServerV1(request(service.uid, input()));
  const createData = { serverId: root.serverId, requestId: randomUUID(), kind: "text", name: "Project", categoryId: null, accessMode: "members" };
  const created = await service.createServerChannelV1(request(service.uid, createData));
  assert.deepEqual(await service.createServerChannelV1(request(service.uid, createData)), created);
  const mutation = { serverId: root.serverId, channelId: created.channelId, requestId: randomUUID(), expectedRevision: 1, patch: { name: "Updated" } };
  const update = await service.updateServerChannelV1(request(service.uid, mutation));
  assert.equal(update.revision, 2);
  await rejection(service.updateServerChannelV1(request(service.uid, { ...mutation, requestId: randomUUID() })), "aborted");
  await rejection(service.updateServerChannelV1(request(service.uid, { ...mutation, requestId: randomUUID(), patch: { roomId: "foreign" } })), "invalid-argument");
  const current = (await db.doc(`clubs/${root.serverId}`).get()).data();
  const reorder = { serverId: root.serverId, requestId: randomUUID(), expectedRevision: current.revision, channelIds: [...root.channelIds, created.channelId].reverse() };
  await service.reorderServerChannelsV1(request(service.uid, reorder));
  const channels = await db.collection(`clubs/${root.serverId}/channels`).orderBy("position").get();
  assert.deepEqual(channels.docs.map((doc) => doc.id), reorder.channelIds);
});

emulatorTest("channel ACL invalidates stale grants immediately and writes IDs-only mirrors", async () => {
  const service = await fixture();
  const root = await service.createServerV1(request(service.uid, input({ serverType: "company" })));
  const hr = (await db.collection(`clubs/${root.serverId}/channels`).where("seedKey", "==", "hr").get()).docs[0];
  const user = `member-${randomUUID()}`;
  await db.doc(`users/${user}`).set({ displayName: "A member", status: "active" });
  await db.doc(`clubs/${root.serverId}/members/${user}`).set({ userId: user, role: "member", authorizationRevision: 1 });
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  await rejection(access(user, root.serverId, hr.id), "permission-denied");
  const policyData = { serverId: root.serverId, channelId: hr.id, requestId: randomUUID(), expectedAclRevision: 1,
    policy: { accessMode: "restricted", roleIds: ["owner"], userIds: [user] } };
  const granted = await service.setServerChannelAccessV1(request(service.uid, policyData));
  assert.equal(granted.aclRevision, 2);
  await access(user, root.serverId, hr.id);
  await service.setServerChannelAccessV1(request(service.uid, { ...policyData, requestId: randomUUID(), expectedAclRevision: 2,
    policy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] } }));
  await rejection(access(user, root.serverId, hr.id), "permission-denied");
  assert.equal((await db.doc(`clubs/${root.serverId}/channels/${hr.id}/accessGrants/${user}`).get()).data().aclRevision, 2);
  await rejection(service.updateServerChannelV1(request(user, { serverId: root.serverId, channelId: hr.id,
    requestId: randomUUID(), expectedRevision: 3, patch: { name: "Forged" } })), "permission-denied");
});

emulatorTest("archive invalidates runtime, retains authorized owner history, and queues durable scoped cleanup", async () => {
  const service = await fixture();
  const root = await service.createServerV1(request(service.uid, input({ serverType: "company" })));
  const hr = (await db.collection(`clubs/${root.serverId}/channels`).where("seedKey", "==", "hr").get()).docs[0];
  const data = { serverId: root.serverId, channelId: hr.id, requestId: randomUUID() };
  const result = await service.archiveServerChannelV1(request(service.uid, data));
  assert.equal(result.status, "archived");
  await rejection(access(service.uid, root.serverId, hr.id), "permission-denied");
  await access(service.uid, root.serverId, hr.id, { allowArchived: true });
  assert.deepEqual(await service.archiveServerChannelV1(request(service.uid, data)), result);
  const jobs = await db.collection("serverControlOutbox").where("serverId", "==", root.serverId).get();
  assert.equal(jobs.size, 1);
  assert.equal(jobs.docs[0].data().kind, "channelArchive");
  assert.equal(jobs.docs[0].data().status, "pending");
});

emulatorTest("creation replay rechecks canonical owner membership rather than trusting a receipt", async () => {
  const service = await fixture();
  const data = input();
  const root = await service.createServerV1(request(service.uid, data));
  await db.doc(`clubs/${root.serverId}/members/${service.uid}`).update({ banned: true });
  await rejection(service.createServerV1(request(service.uid, data)), "permission-denied");
});

emulatorTest("delete keeps a scoped tombstone and reauthorizes idempotent receipts", async () => {
  const service = await fixture();
  const root = await service.createServerV1(request(service.uid, input({ serverType: "company" })));
  const hr = (await db.collection(`clubs/${root.serverId}/channels`).where("seedKey", "==", "hr").get()).docs[0];
  const data = { serverId: root.serverId, channelId: hr.id, requestId: randomUUID() };
  const deleted = await service.deleteServerChannelV1(request(service.uid, data));
  assert.equal(deleted.status, "deleting");
  assert.equal(deleted.cleanupPending, true);
  assert.equal((await hr.ref.get()).exists, true);
  assert.deepEqual(await service.deleteServerChannelV1(request(service.uid, data)), deleted);
  await db.doc(`clubs/${root.serverId}/members/${service.uid}`).update({ banned: true });
  await rejection(service.deleteServerChannelV1(request(service.uid, data)), "permission-denied");
});

emulatorTest("rate limits are distinct from capacity and forged counts never reach the graph", async () => {
  const service = await fixture();
  const actor = service.uid;
  const rate = rateLimitReference(db, "server.v1.attempt", actor);
  await rate.set({ schemaVersion: 1, ownerId: actor, scope: "server.v1.attempt",
    count: 120, windowStartedAt: Timestamp.fromMillis(1_900_000_000_000) });
  await assert.rejects(service.createServerV1(request(actor, input())), (error) =>
    error.code === "resource-exhausted" && error.details?.reason !== "server-capacity-reached");
  const forged = input({ memberCount: 44 });
  await rejection(service.createServerV1(request(actor, forged)), "invalid-argument");
  assert.equal((await db.collection("clubs").where("ownerId", "==", actor).get()).size, 0);
});

emulatorTest("session authorization denies reciprocal binding substitution and old generation", async () => {
  const service = await fixture();
  const root = await service.createServerV1(request(service.uid, input()));
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  const authorize = (sessionId) => db.runTransaction((transaction) => readBoundSessionAccess({
    db, transaction, uid: service.uid, serverId: root.serverId, channelId: root.defaultChannelId, sessionId,
  }));
  await rejection(authorize("session-one"), "permission-denied");
  const channelReference = db.doc(`clubs/${root.serverId}/channels/${root.defaultChannelId}`);
  const channel = (await channelReference.get()).data();
  await channelReference.update({ activeSessionId: "session-one" });
  await db.doc(`rooms/${channel.roomId}`).update({ status: "active", isLive: true, voiceSessionId: "session-one", channelId: "foreign" });
  await channelReference.collection("channelSessions").doc("session-one").set({ sessionId: "session-one" });
  await rejection(authorize("session-one"), "permission-denied");
  await rejection(authorize("session-two"), "permission-denied");
  const livekitRoomName = canonicalLiveKitRoomName(root.serverId, root.defaultChannelId, "session-one");
  await db.doc(`rooms/${channel.roomId}`).update({ channelId: root.defaultChannelId,
    hostId: service.uid, serverActivationState: "active", livekitRoomName });
  await channelReference.collection("channelSessions").doc("session-one").set({
    serverSchemaVersion: 1, serverId: root.serverId, channelId: root.defaultChannelId,
    roomId: channel.roomId, sessionId: "session-one", livekitRoomName, status: "live",
    experience: channel.experience, mediaMode: channel.mediaMode,
  });
  assert.equal((await authorize("session-one")).livekitRoomName, livekitRoomName);
});

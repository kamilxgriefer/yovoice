const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let db;
let app;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp({ projectId: "demo-yovoice-servers-backend" }, `server-members-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerMembershipService } = require("../servers/memberships");
const { createServerConvergenceService } = require("../servers/convergence");
const { readChannelAccess } = require("../servers/authority");
const { serverChannelRefId } = require("../servers/contract");
const nowMs = 1_900_000_000_000;
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const input = (serverType = "community") => ({ requestId: randomUUID(), serverType, templateVersion: 1,
  name: "Membership server", description: "", privacy: serverType === "community" ? "public" : "inviteOnly", defaultLanguage: "English" });
const operation = (serverId, extra = {}) => ({ serverId, requestId: randomUUID(), ...extra });
async function user() {
  const uid = `sm-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: `Canonical ${uid}`, status: "active" });
  return uid;
}
async function fixture(serverType = "community") {
  const uid = await user();
  const deps = { db, Timestamp, clock: () => nowMs };
  const service = { ...createServerCreationService(deps), ...createServerChannelService(deps),
    ...createServerMembershipService(deps), ...createServerConvergenceService(deps) };
  const created = await service.createServerV1(request(uid, input(serverType)));
  // Explicit emulator fixture activation, never a shipped activation path.
  await db.doc(`clubs/${created.serverId}`).update({ status: "active", serverActivationState: "active" });
  const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
  for (const anchor of anchors.docs) await anchor.ref.update({
    status: "active", serverActivationState: "active", hostId: uid,
  });
  return { uid, ...created, ...service };
}
async function invite(fixture, inviteeId, changes = {}) {
  const owner = (await db.doc(`clubs/${fixture.serverId}/members/${fixture.uid}`).get()).data();
  await db.doc(`clubs/${fixture.serverId}/invites/${inviteeId}`).set({
    serverSchemaVersion: 1, serverId: fixture.serverId, inviteeId, inviterId: fixture.uid,
    inviterAuthorizationRevision: owner.authorizationRevision, generation: 1, status: "pending",
    expiresAt: Timestamp.fromMillis(nowMs + 60_000), ...changes,
  });
}
const getAccess = (uid, serverId, channelId) => db.runTransaction((transaction) =>
  readChannelAccess({ db, transaction, uid, serverId, channelId }));
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

emulatorTest("concurrent public joins create one canonical member and no fake online count", async () => {
  const fixtureValue = await fixture();
  const uid = await user();
  const results = await Promise.all(Array.from({ length: 4 }, () => fixtureValue.joinServerV1(request(uid, operation(fixtureValue.serverId)))));
  assert.equal(results.filter((result) => result.alreadyMember === false).length, 1);
  const root = (await db.doc(`clubs/${fixtureValue.serverId}`).get()).data();
  assert.equal(root.memberCount, 2);
  assert.equal(root.onlineCount, 0);
  const member = (await db.doc(`clubs/${fixtureValue.serverId}/members/${uid}`).get()).data();
  assert.equal(member.role, "member");
  assert.equal(member.photoUrl, null);
  assert.equal(member.isOnline, false);
  assert.equal((await db.doc(`users/${uid}/clubs/${fixtureValue.serverId}`).get()).data().role, "member");
});

emulatorTest("private admission needs current targeted generation and rejects expired, forwarded and demoted inviter", async () => {
  const value = await fixture("friends");
  const uid = await user();
  await rejection(value.joinServerV1(request(uid, operation(value.serverId))), "permission-denied");
  await invite(value, uid, { expiresAt: Timestamp.fromMillis(nowMs - 1) });
  await rejection(value.respondToServerInviteV1(request(uid, operation(value.serverId, { response: "accept" }))), "permission-denied");
  await invite(value, uid, { inviteeId: "other-user" });
  await rejection(value.respondToServerInviteV1(request(uid, operation(value.serverId, { response: "accept" }))), "permission-denied");
  await invite(value, uid, { inviterAuthorizationRevision: 999 });
  await rejection(value.respondToServerInviteV1(request(uid, operation(value.serverId, { response: "accept" }))), "permission-denied");
  await invite(value, uid);
  const data = operation(value.serverId, { response: "accept" });
  const joined = await value.respondToServerInviteV1(request(uid, data));
  assert.equal(joined.inviteGeneration, 1);
  assert.deepEqual(await value.respondToServerInviteV1(request(uid, data)), joined);
  assert.equal((await db.doc(`clubs/${value.serverId}/invites/${uid}`).get()).data().status, "accepted");
});

emulatorTest("decline receipt cannot consume a newer invitation generation", async () => {
  const value = await fixture("friends");
  const uid = await user();
  await invite(value, uid);
  const data = operation(value.serverId, { response: "decline" });
  const declined = await value.respondToServerInviteV1(request(uid, data));
  assert.deepEqual(await value.respondToServerInviteV1(request(uid, data)), declined);
  await invite(value, uid, { generation: 2 });
  await rejection(value.respondToServerInviteV1(request(uid, data)), "permission-denied");
  assert.equal((await db.doc(`clubs/${value.serverId}/invites/${uid}`).get()).data().status, "pending");
});

emulatorTest("leave is available under a social restriction and rejoin cannot reactivate stale grants", async () => {
  const value = await fixture();
  const uid = await user();
  const joinData = operation(value.serverId);
  const joined = await value.joinServerV1(request(uid, joinData));
  await db.doc(`restrictions/${uid}`).set({ expiresAt: Timestamp.fromMillis(nowMs + 60_000) });
  const leaveData = operation(value.serverId);
  const left = await value.leaveServerV1(request(uid, leaveData));
  assert.equal(left.membershipRevision, joined.membershipRevision + 1);
  assert.equal((await db.doc(`clubs/${value.serverId}/members/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`users/${uid}/clubs/${value.serverId}`).get()).exists, false);
  assert.deepEqual(await value.leaveServerV1(request(uid, leaveData)), left);
  await db.doc(`restrictions/${uid}`).delete();
  await rejection(value.joinServerV1(request(uid, joinData)), "permission-denied");
  const rejoined = await value.joinServerV1(request(uid, operation(value.serverId)));
  assert.equal(rejoined.membershipRevision, left.membershipRevision + 1);
  await rejection(value.leaveServerV1(request(uid, leaveData)), "aborted");
  await rejection(value.leaveServerV1(request(value.uid, operation(value.serverId))), "failed-precondition");
});

emulatorTest("only owner/co-owner manage roles and role changes immediately invalidate restricted access", async () => {
  const value = await fixture();
  const admin = await user();
  const member = await user();
  await value.joinServerV1(request(admin, operation(value.serverId)));
  await value.joinServerV1(request(member, operation(value.serverId)));
  await value.setServerMemberRoleV1(request(value.uid, operation(value.serverId, { memberId: admin, role: "admin" })));
  await rejection(value.setServerMemberRoleV1(request(admin, operation(value.serverId, { memberId: member, role: "guest" }))), "permission-denied");
  const channel = await value.createServerChannelV1(request(value.uid, operation(value.serverId, {
    kind: "text", name: "Private admin", categoryId: null, accessMode: "restricted",
  })));
  await value.setServerChannelAccessV1(request(value.uid, operation(value.serverId, {
    channelId: channel.channelId, expectedAclRevision: 1, policy: { accessMode: "restricted", roleIds: ["owner", "admin"], userIds: [admin] },
  })));
  await getAccess(admin, value.serverId, channel.channelId);
  // Remove the explicit user rule, then materialize the current admin grant.
  await value.setServerChannelAccessV1(request(value.uid, operation(value.serverId, {
    channelId: channel.channelId, expectedAclRevision: 2, policy: { accessMode: "restricted", roleIds: ["owner", "admin"], userIds: [] },
  })));
  const jobs = await db.collection("serverControlOutbox").where("serverId", "==", value.serverId).where("kind", "==", "channelAccess").get();
  for (const job of jobs.docs) await value.processServerControlOutboxPage({ operationId: job.id, pageSize: 50 });
  await getAccess(admin, value.serverId, channel.channelId);
  await value.setServerMemberRoleV1(request(value.uid, operation(value.serverId, { memberId: admin, role: "member" })));
  await rejection(getAccess(admin, value.serverId, channel.channelId), "permission-denied");
  assert.equal((await db.doc(`users/${admin}/serverChannelRefs/${serverChannelRefId(value.serverId, channel.channelId)}`).get()).exists, false);
});

emulatorTest("ownership transfer preserves IDs, changes every room owner and does not grant former owner HR", async () => {
  const value = await fixture("company");
  const target = await user();
  await invite(value, target);
  await value.respondToServerInviteV1(request(target, operation(value.serverId, { response: "accept" })));
  const hr = (await db.collection(`clubs/${value.serverId}/channels`).where("seedKey", "==", "hr").get()).docs[0];
  const data = operation(value.serverId, { newOwnerId: target });
  const result = await value.transferServerOwnershipV1(request(value.uid, data));
  assert.equal(result.serverId, value.serverId);
  assert.deepEqual(await value.transferServerOwnershipV1(request(value.uid, data)), result);
  const root = (await db.doc(`clubs/${value.serverId}`).get()).data();
  assert.equal(root.ownerId, target);
  assert.equal((await db.doc(`clubs/${value.serverId}/members/${target}`).get()).data().role, "owner");
  assert.equal((await db.doc(`clubs/${value.serverId}/members/${value.uid}`).get()).data().role, "coOwner");
  await rejection(getAccess(target, value.serverId, hr.id), "permission-denied");
  await rejection(getAccess(value.uid, value.serverId, hr.id), "permission-denied");
  const jobs = await db.collection("serverControlOutbox").where("serverId", "==", value.serverId)
    .where("kind", "==", "ownershipTransferred").get();
  await value.processServerControlOutboxPage({ operationId: jobs.docs[0].id });
  await getAccess(target, value.serverId, hr.id);
  await rejection(getAccess(value.uid, value.serverId, hr.id), "permission-denied");
  const rooms = await db.collection("rooms").where("serverId", "==", value.serverId).get();
  assert.ok(rooms.docs.every((room) => room.data().serverOwnerId === target && room.data().isLive === false));
});

emulatorTest("family transfer atomically moves owner reservation and rejects a recipient with another family", async () => {
  const value = await fixture("family");
  const target = await user();
  await invite(value, target);
  await value.respondToServerInviteV1(request(target, operation(value.serverId, { response: "accept" })));
  await db.doc(`serverFamilyOwnerReservations/${target}`).set({ schemaVersion: 1, ownerId: target, serverId: "other", status: "active" });
  await rejection(value.transferServerOwnershipV1(request(value.uid, operation(value.serverId, { newOwnerId: target }))), "resource-exhausted");
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).data().ownerId, value.uid);
  await db.doc(`serverFamilyOwnerReservations/${target}`).delete();
  await value.transferServerOwnershipV1(request(value.uid, operation(value.serverId, { newOwnerId: target })));
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${value.uid}`).get()).exists, false);
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${target}`).get()).data().serverId, value.serverId);
  const recovered = await value.createServerV1(request(target, input("family")));
  assert.equal(recovered.serverId, value.serverId);
  await rejection(value.createServerV1(request(value.uid, input("family"))), "permission-denied");
});

emulatorTest("existing over-limit owner can transfer out while full recipient cannot gain an allocation", async () => {
  const value = await fixture();
  const target = await user();
  await value.joinServerV1(request(target, operation(value.serverId)));
  for (let index = 0; index < 21; index += 1) await db.doc(`clubs/over-${value.uid}-${index}`).set({
    ownerId: value.uid, serverSchemaVersion: 1, entitlementPolicyId: "freeServersV1", status: "active",
  });
  for (let index = 0; index < 20; index += 1) await db.doc(`clubs/full-${target}-${index}`).set({
    ownerId: target, serverSchemaVersion: 1, entitlementPolicyId: "freeServersV1", status: "active",
  });
  await rejection(value.transferServerOwnershipV1(request(value.uid, operation(value.serverId, { newOwnerId: target }))), "resource-exhausted");
  await db.doc(`clubs/full-${target}-19`).delete();
  await value.transferServerOwnershipV1(request(value.uid, operation(value.serverId, { newOwnerId: target })));
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).data().ownerId, target);
});

emulatorTest("bounded grant convergence paginates canonical role membership and retains pending RTC cleanup", async () => {
  const value = await fixture();
  const members = await Promise.all(Array.from({ length: 5 }, () => user()));
  for (const uid of members) await value.joinServerV1(request(uid, operation(value.serverId)));
  const channel = await value.createServerChannelV1(request(value.uid, operation(value.serverId, {
    kind: "text", name: "Project", categoryId: null, accessMode: "restricted",
  })));
  await value.setServerChannelAccessV1(request(value.uid, operation(value.serverId, {
    channelId: channel.channelId, expectedAclRevision: 1, policy: { accessMode: "restricted", roleIds: ["owner", "member"], userIds: [] },
  })));
  const jobs = await db.collection("serverControlOutbox").where("serverId", "==", value.serverId).where("kind", "==", "channelAccess").get();
  const job = jobs.docs[0];
  let pages = 0;
  let result;
  do {
    result = await value.processServerControlOutboxPage({ operationId: job.id, pageSize: 2 });
    pages += 1;
    assert.ok(result.processed <= 2);
  } while (!result.propagationComplete && pages < 10);
  assert.equal(pages, 3);
  assert.equal(result.cleanupPending, true);
  assert.equal((await job.ref.get()).data().status, "pending");
  for (const uid of members) await getAccess(uid, value.serverId, channel.channelId);
});

emulatorTest("an admin reorders only permitted channels without moving or submitting hidden HR slots", async () => {
  const value = await fixture("company");
  const admin = await user();
  await invite(value, admin);
  await value.respondToServerInviteV1(request(admin, operation(value.serverId, { response: "accept" })));
  await value.setServerMemberRoleV1(request(value.uid, operation(value.serverId, { memberId: admin, role: "admin" })));
  const before = await db.collection(`clubs/${value.serverId}/channels`).orderBy("position").get();
  const hidden = before.docs.filter((doc) => doc.data().accessMode === "restricted");
  const visible = before.docs.filter((doc) => doc.data().accessMode === "members");
  const root = (await db.doc(`clubs/${value.serverId}`).get()).data();
  await value.reorderServerChannelsV1(request(admin, operation(value.serverId, {
    expectedRevision: root.revision, channelIds: visible.map((doc) => doc.id).reverse(),
  })));
  for (const item of hidden) assert.equal((await item.ref.get()).data().position, item.data().position);
  const after = await db.collection(`clubs/${value.serverId}/channels`).where("accessMode", "==", "members").orderBy("position").get();
  assert.deepEqual(after.docs.map((doc) => doc.id), visible.map((doc) => doc.id).reverse());
  const next = (await db.doc(`clubs/${value.serverId}`).get()).data();
  await rejection(value.reorderServerChannelsV1(request(admin, operation(value.serverId, {
    expectedRevision: next.revision, channelIds: before.docs.map((doc) => doc.id),
  }))), "invalid-argument");
});

emulatorTest("metadata projections converge in bounded pages to current canonical name", async () => {
  const value = await fixture();
  const uid = await user();
  await value.joinServerV1(request(uid, operation(value.serverId)));
  const root = (await db.doc(`clubs/${value.serverId}`).get()).data();
  await value.updateServerV1(request(value.uid, operation(value.serverId, { expectedRevision: root.revision,
    patch: { name: "Canonical renamed" } })));
  const jobs = await db.collection("serverControlOutbox").where("serverId", "==", value.serverId).where("kind", "==", "serverMetadata").get();
  let result;
  do { result = await value.processServerControlOutboxPage({ operationId: jobs.docs[0].id, pageSize: 1 }); } while (!result.propagationComplete);
  assert.equal((await db.doc(`users/${uid}/clubs/${value.serverId}`).get()).data().name, "Canonical renamed");
  assert.equal((await jobs.docs[0].ref.get()).data().status, "completed");
});

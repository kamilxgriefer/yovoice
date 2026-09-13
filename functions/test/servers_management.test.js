// Servers V1 management parity (ADR-F): manager removal, member ban and its
// lift, server deletion, and the four staff adapters the legacy admin
// callables delegate to on a versioned root.
//
// Real local Firestore transactions against the production factories. No
// LiveKit, no network, no cloud project: a live generation is constructed as
// the documents the reviewed writers themselves produce, so the convergence
// staging these operations perform is observed rather than mocked.
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
  app = adminApp.initializeApp({ projectId: "demo-yovoice-servers-management" }, `server-management-${randomUUID()}`);
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerMembershipService } = require("../servers/memberships");
const { createServerManagementService } = require("../servers/management");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const { readServerAccess } = require("../servers/authority");
const { canonicalLiveKitRoomName, serverChannelRefId, serverInviteRefPath } = require("../servers/contract");
const { validateConvergenceJob } = require("../servers/convergence_runtime");

const nowMs = 1_900_000_000_000;
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const emulatorTest = (name, fn) => test(`Management parity: ${name}`,
  { skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.", timeout: 60_000 }, fn);
const operation = (serverId, extra = {}) => ({ serverId, requestId: randomUUID(), ...extra });
const input = (serverType = "community") => ({
  requestId: randomUUID(), serverType, templateVersion: 1, name: "Management server",
  description: "", privacy: serverType === "community" ? "public" : "inviteOnly",
  defaultLanguage: "English",
});

after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

async function user(prefix = "mgmt") {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: `Canonical ${uid}`, status: "active" });
  return uid;
}

async function fixture(serverType = "community") {
  const uid = await user("owner");
  const deps = { db, Timestamp, clock: () => nowMs };
  const livekit = {
    assertSupported() {},
    async revokeParticipant() { throw new Error("Idle cleanup must not contact LiveKit."); },
    async endRoom() { throw new Error("Idle cleanup must not contact LiveKit."); },
  };
  const memoryObjects = new Map();
  const memoryDeletes = [];
  const familyMemoryStorage = {
    async listObjects(prefix, { maxResults }) {
      return [...memoryObjects.entries()]
        .filter(([name]) => name.startsWith(prefix))
        .slice(0, maxResults)
        .map(([name, generation]) => ({ name, generation }));
    },
    async deleteObject(path, { generation }) {
      if (memoryObjects.has(path) && memoryObjects.get(path) !== generation) {
        throw new Error("generation mismatch");
      }
      memoryDeletes.push({ path, generation });
      memoryObjects.delete(path);
    },
  };
  const service = {
    ...createServerCreationService(deps), ...createServerChannelService(deps),
    ...createServerMembershipService(deps), ...createServerManagementService(deps),
    ...createServerConvergenceRuntimeService({ ...deps, livekit, familyMemoryStorage }),
  };
  const created = await service.createServerV1(request(uid, input(serverType)));
  // This fixture uses the raw factory, which deliberately remains held. The
  // exact registered creation runtime seeds new active graphs atomically but
  // exposes no transition that could activate this existing held root.
  await db.doc(`clubs/${created.serverId}`).update({ status: "active", serverActivationState: "active" });
  const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
  for (const anchor of anchors.docs) {
    await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: uid });
  }
  return { uid, ...created, ...service, memoryObjects, memoryDeletes };
}

/** Joins a public server and optionally promotes the new member. */
async function member(value, role = "member") {
  const uid = await user("member");
  await value.joinServerV1(request(uid, operation(value.serverId)));
  if (role !== "member") {
    await value.setServerMemberRoleV1(request(value.uid, operation(value.serverId, { memberId: uid, role })));
  }
  return uid;
}

/**
 * The document set a started session really leaves behind (sessions.js):
 * the channelSession, the channel's activeSessionId and live projection, and
 * the room's live binding. Written directly so this file needs no LiveKit.
 */
async function startLiveGeneration(value, startedById) {
  const channelId = value.defaultChannelId;
  const channel = (await db.doc(`clubs/${value.serverId}/channels/${channelId}`).get()).data();
  const roomId = channel.roomId;
  const sessionId = `ss_${randomUUID().replace(/-/gu, "")}`.slice(0, 43);
  const livekitRoomName = canonicalLiveKitRoomName(value.serverId, channelId, sessionId);
  await db.doc(`clubs/${value.serverId}/channels/${channelId}/channelSessions/${sessionId}`).set({
    serverSchemaVersion: 1, serverId: value.serverId, channelId, roomId, sessionId,
    livekitRoomName, status: "live", authorizationRevision: 1, sourcePolicyVersion: 1,
    maxTokenExpiresAtMillis: nowMs + 300_000, startedById,
    experience: channel.experience, mediaMode: channel.mediaMode,
    startedAt: Timestamp.fromMillis(nowMs), updatedAt: Timestamp.fromMillis(nowMs),
  });
  await db.doc(`clubs/${value.serverId}/channels/${channelId}`).update({
    activeSessionId: sessionId,
    liveness: { schemaVersion: 1, isLive: true, startedAt: Timestamp.fromMillis(nowMs) },
  });
  await db.doc(`rooms/${roomId}`).update({
    isLive: true, voiceSessionId: sessionId, livekitRoomName,
  });
  return { channelId, roomId, sessionId, livekitRoomName };
}

const root = (serverId) => db.doc(`clubs/${serverId}`).get().then((s) => s.data());
const membership = (serverId, uid) => db.doc(`clubs/${serverId}/members/${uid}`).get();
const authorization = (serverId, uid) => db.doc(`clubs/${serverId}/memberAuthorizations/${uid}`).get();
const mirror = (serverId, uid) => db.doc(`users/${uid}/clubs/${serverId}`).get();
const job = (operationId) => db.doc(`serverControlOutbox/${operationId}`).get().then((s) => s.data());
const access = (uid, serverId) => db.runTransaction((transaction) =>
  readServerAccess({ db, transaction, uid, serverId }));

// Every test in this file shares one emulator project, so an outbox query is
// scoped to THIS fixture's server and filtered in memory — a `kind` equality
// across the whole collection would read other tests' jobs.
async function jobsFor(serverId, kind = null) {
  const page = await db.collection("serverControlOutbox").where("serverId", "==", serverId).get();
  return page.docs
    .map((document) => ({ id: document.id, data: document.data() }))
    .filter((entry) => kind === null || entry.data.kind === kind);
}

// ---------------------------------------------------------------------------
// R1 — removal
// ---------------------------------------------------------------------------

emulatorTest("a manager's removal revokes authorization, sweeps grants, decrements the count and replays as itself", async () => {
  const value = await fixture();
  const target = await member(value);
  const inviteReference = db.doc(`clubs/${value.serverId}/invites/${target}`);
  await inviteReference.set({
    serverSchemaVersion: 1, serverId: value.serverId, inviteeId: target,
    inviterId: value.uid, inviterAuthorizationRevision: 1, status: "pending", generation: 1,
    expiresAt: Timestamp.fromMillis(nowMs + 60_000), createdAt: Timestamp.fromMillis(nowMs),
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  await db.doc(serverInviteRefPath(target, value.serverId)).set({
    serverId: value.serverId, generation: 1, expiresAt: Timestamp.fromMillis(nowMs + 60_000),
  });
  const before = await root(value.serverId);
  assert.equal(before.memberCount, 2);
  const targetMember = (await membership(value.serverId, target)).data();

  const data = operation(value.serverId, { memberId: target });
  const removed = await value.removeServerMemberV1(request(value.uid, data));
  assert.equal(removed.removed, true);
  assert.equal(removed.cleanupPending, true);
  assert.equal(removed.membershipRevision, targetMember.authorizationRevision + 1);

  assert.equal((await membership(value.serverId, target)).exists, false);
  assert.equal((await mirror(value.serverId, target)).exists, false);
  const ledger = (await authorization(value.serverId, target)).data();
  assert.equal(ledger.status, "left");
  assert.equal(ledger.revision, removed.membershipRevision);
  const retiredInvite = (await inviteReference.get()).data();
  assert.equal(retiredInvite.status, "revoked");
  assert.equal(retiredInvite.revokedById, value.uid);
  assert.equal((await db.doc(serverInviteRefPath(target, value.serverId)).get()).exists, false);
  const after = await root(value.serverId);
  assert.equal(after.memberCount, 1);
  assert.equal(after.revision, before.revision + 1);
  const ref = serverChannelRefId(value.serverId, value.defaultChannelId);
  assert.equal((await db.doc(`users/${target}/serverChannelRefs/${ref}`).get()).exists, false);

  // The idempotent receipt is the SAME removal, never a second one.
  assert.deepEqual(await value.removeServerMemberV1(request(value.uid, data)), removed);
  assert.equal((await root(value.serverId)).memberCount, 1);
});

emulatorTest("a removal stages a convergence job that names the removed member, and the job is canonical", async () => {
  const value = await fixture();
  const target = await member(value);
  await startLiveGeneration(value, value.uid);
  const removed = await value.removeServerMemberV1(request(value.uid, operation(value.serverId, { memberId: target })));
  const jobs = await jobsFor(value.serverId, "memberRemoved");
  assert.equal(jobs.length, 1);
  const document = jobs[0].data;
  assert.equal(document.userId, target);
  assert.equal(document.membershipRevision, removed.membershipRevision);
  // The reviewed worker must accept it, and it must carry a recipient target
  // for the live generation — a removal that only deleted a document would
  // leave the removed member connected to the room.
  validateConvergenceJob(document, jobs[0].id);
  assert.equal(document.rtcTargets.length, 1);
  assert.equal(document.rtcTargets[0].mode, "recipient");
  assert.equal(document.rtcTargets[0].userId, target);
  assert.equal(document.rtcStatus, "pending");
});

emulatorTest("removal refuses self, the owner, an equal rank, a non-manager and an outsider — all with the same denial", async () => {
  const value = await fixture();
  const admin = await member(value, "admin");
  const peer = await member(value, "admin");
  const plain = await member(value);
  const outsider = await user("outsider");

  // Self-removal belongs to leaveServerV1 and is refused here.
  await rejection(value.removeServerMemberV1(request(admin, operation(value.serverId, { memberId: admin }))), "permission-denied");
  // The owner is unremovable.
  await rejection(value.removeServerMemberV1(request(admin, operation(value.serverId, { memberId: value.uid }))), "permission-denied");
  // Equal rank cannot remove equal rank.
  await rejection(value.removeServerMemberV1(request(admin, operation(value.serverId, { memberId: peer }))), "permission-denied");
  // An ordinary member has no removal capability at all.
  await rejection(value.removeServerMemberV1(request(plain, operation(value.serverId, { memberId: peer }))), "permission-denied");
  // A non-member, and an unknown server, answer identically — no oracle.
  await rejection(value.removeServerMemberV1(request(outsider, operation(value.serverId, { memberId: plain }))), "permission-denied");
  await rejection(value.removeServerMemberV1(request(value.uid, operation(`srv_${"0".repeat(40)}`, { memberId: plain }))), "permission-denied");
  // A moderator CAN remove an ordinary member, which is exactly Club's rule.
  const moderator = await member(value, "moderator");
  const removed = await value.removeServerMemberV1(request(moderator, operation(value.serverId, { memberId: plain })));
  assert.equal(removed.removed, true);
});

// ---------------------------------------------------------------------------
// R2 — ban, and its lift
// ---------------------------------------------------------------------------

emulatorTest("a ban is honoured immediately, strips grants, and the banned member can neither act nor leave nor rejoin", async () => {
  const value = await fixture();
  const target = await member(value);
  await access(target, value.serverId);

  const banned = await value.setServerMemberBanV1(request(value.uid,
    operation(value.serverId, { memberId: target, banned: true, reason: "Harassment" })));
  assert.equal(banned.banned, true);
  assert.equal(banned.changed, true);

  const record = (await membership(value.serverId, target)).data();
  assert.equal(record.banned, true);
  assert.equal(record.banReason, "Harassment");
  assert.equal(record.bannedBy, value.uid);
  assert.equal(record.authorizationRevision, banned.membershipRevision);
  // The membership survives, so the count is unchanged and the ban is durable.
  assert.equal((await root(value.serverId)).memberCount, 2);

  await rejection(access(target, value.serverId), "permission-denied");
  await rejection(value.leaveServerV1(request(target, operation(value.serverId))), "permission-denied");
  await rejection(value.joinServerV1(request(target, operation(value.serverId))), "permission-denied");
  const ref = serverChannelRefId(value.serverId, value.defaultChannelId);
  assert.equal((await db.doc(`users/${target}/serverChannelRefs/${ref}`).get()).exists, false);
});

emulatorTest("a ban can be LIFTED, and the lift restores access through the current roles, not a pre-ban snapshot", async () => {
  const value = await fixture();
  const target = await member(value);
  const set = await value.setServerMemberBanV1(request(value.uid,
    operation(value.serverId, { memberId: target, banned: true, reason: "Spam" })));
  await rejection(access(target, value.serverId), "permission-denied");

  const lifted = await value.setServerMemberBanV1(request(value.uid,
    operation(value.serverId, { memberId: target, banned: false, reason: "" })));
  assert.equal(lifted.banned, false);
  assert.equal(lifted.changed, true);
  assert.equal(lifted.membershipRevision, set.membershipRevision + 1);

  const record = (await membership(value.serverId, target)).data();
  assert.equal(record.banned, false);
  assert.equal(record.banReason, null);
  assert.equal(record.bannedBy, null);
  assert.equal((await authorization(value.serverId, target)).data().status, "member");
  assert.equal((await mirror(value.serverId, target)).exists, true);
  const restored = await access(target, value.serverId);
  assert.equal(restored.member.authorizationRevision, lifted.membershipRevision);
});

emulatorTest("a ban needs a reason, a lift refuses one, and an unchanged ban state writes nothing", async () => {
  const value = await fixture();
  const target = await member(value);
  await rejection(value.setServerMemberBanV1(request(value.uid,
    operation(value.serverId, { memberId: target, banned: true, reason: "" }))), "invalid-argument");
  await rejection(value.setServerMemberBanV1(request(value.uid,
    operation(value.serverId, { memberId: target, banned: false, reason: "why" }))), "invalid-argument");

  const noop = await value.setServerMemberBanV1(request(value.uid,
    operation(value.serverId, { memberId: target, banned: false, reason: "" })));
  assert.equal(noop.changed, false);
  assert.equal(noop.cleanupPending, false);
  // The join created a `memberJoined` job; an unchanged ban must add none.
  assert.equal((await jobsFor(value.serverId, "memberBanned")).length, 0);
  assert.equal((await jobsFor(value.serverId, "memberBanLifted")).length, 0);
  assert.equal((await membership(value.serverId, target)).data().authorizationRevision,
    noop.membershipRevision);
});

emulatorTest("ban authority is removal authority: self, owner, equal rank, plain member and outsider are all refused", async () => {
  const value = await fixture();
  const admin = await member(value, "admin");
  const peer = await member(value, "admin");
  const plain = await member(value);
  const outsider = await user("outsider");
  const ban = (actor, memberId) => value.setServerMemberBanV1(request(actor,
    operation(value.serverId, { memberId, banned: true, reason: "x" })));
  await rejection(ban(admin, admin), "permission-denied");
  await rejection(ban(admin, value.uid), "permission-denied");
  await rejection(ban(admin, peer), "permission-denied");
  await rejection(ban(plain, peer), "permission-denied");
  await rejection(ban(outsider, plain), "permission-denied");
});

// ---------------------------------------------------------------------------
// R3 — deletion
// ---------------------------------------------------------------------------

emulatorTest("deletion is owner-only, refuses a live generation, and marks a root that then denies every read", async () => {
  const value = await fixture();
  const admin = await member(value, "admin");
  await rejection(value.deleteServerV1(request(admin, operation(value.serverId))), "permission-denied");

  const live = await startLiveGeneration(value, value.uid);
  await rejection(value.deleteServerV1(request(value.uid, operation(value.serverId))), "failed-precondition");
  // Nothing was written by the refusal.
  assert.equal((await root(value.serverId)).deletionInProgress, undefined);
  assert.equal((await db.doc(
    `clubs/${value.serverId}/channels/${live.channelId}/channelSessions/${live.sessionId}`,
  ).get()).data().status, "live");

  // End the generation the way the owner would, then delete.
  await db.doc(`clubs/${value.serverId}/channels/${live.channelId}/channelSessions/${live.sessionId}`)
    .update({ status: "ended", endedAt: Timestamp.fromMillis(nowMs) });
  await db.doc(`clubs/${value.serverId}/channels/${live.channelId}`)
    .update({ activeSessionId: null, liveness: { schemaVersion: 1, isLive: false, startedAt: null } });
  await db.doc(`rooms/${live.roomId}`).update({ isLive: false, voiceSessionId: null, livekitRoomName: null });

  const data = operation(value.serverId);
  const deleted = await value.deleteServerV1(request(value.uid, data));
  assert.equal(deleted.deleted, true);
  assert.equal(deleted.contentCleanupPending, true);
  const after = await root(value.serverId);
  assert.equal(after.deletionInProgress, true);
  assert.equal(after.deletionRequestedBy, value.uid);
  await rejection(access(value.uid, value.serverId), "permission-denied");
  await rejection(access(admin, value.serverId), "permission-denied");
  // The receipt is re-served against the same marked root.
  assert.deepEqual(await value.deleteServerV1(request(value.uid, data)), deleted);
});

emulatorTest("deletion drains all bounded V1 content, completes, and remains replay-idempotent", async () => {
  const value = await fixture();
  const other = await member(value);
  const invitee = await user("invitee");
  const invite = db.doc(`clubs/${value.serverId}/invites/${invitee}`);
  const inviteMirror = db.doc(`users/${invitee}/serverInviteRefs/${value.serverId}`);
  await invite.set({ serverSchemaVersion: 1, serverId: value.serverId, inviteeId: invitee });
  await inviteMirror.set({ serverId: value.serverId, generation: 1 });
  const channel = db.doc(`clubs/${value.serverId}/channels/${value.defaultChannelId}`);
  const history = channel.collection("messages").doc("delete-history");
  await history.set({ content: "Bounded deletion fixture" });
  const followed = {
    schemaVersion: 1, serverId: value.serverId, userId: other, following: true,
    createdAt: Timestamp.fromMillis(nowMs), updatedAt: Timestamp.fromMillis(nowMs),
  };
  const orphanUid = await user("orphan-follow");
  const orphanFollow = { ...followed, userId: orphanUid };
  const follow = db.doc(`clubs/${value.serverId}/followers/${other}`);
  const followMirror = db.doc(`users/${other}/serverFollows/${value.serverId}`);
  const orphanMirror = db.doc(`users/${orphanUid}/serverFollows/${value.serverId}`);
  await follow.set(followed);
  await followMirror.set(followed);
  await orphanMirror.set(orphanFollow);
  const data = operation(value.serverId);
  const deleted = await value.deleteServerV1(request(value.uid, data));
  const jobs = await jobsFor(value.serverId, "serverDelete");
  assert.equal(jobs.length, 1);
  const document = jobs[0].data;
  assert.equal(document.serverId, value.serverId);
  assert.equal(document.contentCleanupPending, true);
  assert.equal(document.status, "pending");
  assert.equal(document.rtcStatus, "completed");
  assert.equal(document.grantStatus, "completed");
  assert.deepEqual(document.rtcTargets, []);
  validateConvergenceJob(document, jobs[0].id);
  assert.equal(deleted.cleanupPending, true);
  let result;
  for (let page = 0; page < 200; page += 1) {
    result = await value.processServerConvergencePage({ operationId: jobs[0].id, pageSize: 2 });
    if (!result.cleanupPending) break;
  }
  assert.equal(result.cleanupPending, false);
  assert.equal(result.contentCleanupPending, false);
  assert.equal((await db.doc(`serverControlOutbox/${jobs[0].id}`).get()).data().status, "completed");
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).exists, false);
  assert.equal((await db.collection("rooms").where("serverId", "==", value.serverId).get()).size, 0);
  for (const reference of [history, invite, inviteMirror, follow, followMirror, orphanMirror,
    db.doc(`users/${value.uid}/clubs/${value.serverId}`),
    db.doc(`users/${other}/clubs/${value.serverId}`)]) {
    assert.equal((await reference.get()).exists, false, reference.path);
  }
  assert.deepEqual(await value.deleteServerV1(request(value.uid, data)), deleted);
});

emulatorTest("family deletion retires upload capabilities before draining every private media object", async () => {
  const value = await fixture("family");
  const memoryId = `fm_${"a".repeat(40)}`;
  const prefix = `family_moments/${value.serverId}/${value.uid}/`;
  const photoPath = `${prefix}${memoryId}_photo.jpg`;
  const voicePath = `${prefix}${memoryId}_voice.m4a`;
  const orphanPath = `${prefix}orphan.bin`;
  const reservation = {
    schemaVersion: 1, kind: "serverFamilyMemory", serverId: value.serverId,
    channelId: "memories", memoryId, ownerId: value.uid,
    requestId: "family-delete-reservation", caption: "",
    photoStoragePath: photoPath, photoContentType: "image/jpeg", photoSize: 128,
    voiceStoragePath: voicePath, voiceContentType: "audio/mp4", voiceSize: 1024,
    voiceDurationMs: 1000, status: "uploading",
    createdAt: Timestamp.fromMillis(nowMs), expiresAt: Timestamp.fromMillis(nowMs + 60_000),
  };
  const reservationRef = db.doc(`serverFamilyMemoryUploadReservations/${memoryId}`);
  const leaseRef = db.doc(`serverFamilyMemoryUploadLeases/${value.uid}`);
  const deletionJobRef = db.doc("serverFamilyMemoryDeletionJobs/family-delete-job");
  await reservationRef.set(reservation);
  await leaseRef.set(reservation);
  await deletionJobRef.set({
    schemaVersion: 1, kind: "serverFamilyMemoryDelete", jobId: deletionJobRef.id,
    serverId: value.serverId, channelId: "memories", memoryId,
    authorId: value.uid, requestedBy: value.uid,
    deletionOperationId: "family-delete-operation", deletionRevision: 2,
    photo: { storagePath: photoPath, generation: "11", contentType: "image/jpeg", size: 128 },
    voice: { storagePath: voicePath, generation: "12", contentType: "audio/mp4", size: 1024, durationMs: 1000 },
    status: "pending", createdAt: Timestamp.fromMillis(nowMs), updatedAt: Timestamp.fromMillis(nowMs),
  });
  value.memoryObjects.set(photoPath, "11");
  value.memoryObjects.set(voicePath, "12");
  value.memoryObjects.set(orphanPath, "13");

  const requestData = operation(value.serverId);
  const deleted = await value.deleteServerV1(request(value.uid, requestData));
  const [jobRow] = await jobsFor(value.serverId, "serverDelete");
  let result;
  for (let page = 0; page < 250; page += 1) {
    result = await value.processServerConvergencePage({ operationId: jobRow.id, pageSize: 2 });
    if (!result.cleanupPending) break;
  }
  assert.equal(result.cleanupPending, false);
  assert.equal(value.memoryObjects.size, 0);
  assert.deepEqual(value.memoryDeletes.map((entry) => entry.generation).sort(), ["11", "12", "13"]);
  for (const reference of [reservationRef, leaseRef, deletionJobRef]) {
    assert.equal((await reference.get()).exists, false, reference.path);
  }
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).exists, false);
  assert.deepEqual(await value.deleteServerV1(request(value.uid, requestData)), deleted);
});

emulatorTest("deleting a family server releases its one-per-owner reservation in the same transaction", async () => {
  const value = await fixture("family");
  const reservation = db.doc(`serverFamilyOwnerReservations/${value.uid}`);
  assert.equal((await reservation.get()).data().serverId, value.serverId);
  await value.deleteServerV1(request(value.uid, operation(value.serverId)));
  assert.equal((await reservation.get()).exists, false);
});

// ---------------------------------------------------------------------------
// R4 — the staff adapters
// ---------------------------------------------------------------------------

emulatorTest("a staff suspension freezes the root and ends every live generation; restore puts it back", async () => {
  const value = await fixture();
  const staff = await user("staff");
  const target = await member(value);
  const live = await startLiveGeneration(value, value.uid);

  const suspended = await value.staffSetServerModerationStatus({
    serverId: value.serverId, suspended: true, reason: "Abuse report", actorUid: staff,
  });
  assert.equal(suspended.changed, true);
  assert.equal(suspended.status, "suspended");
  assert.equal(suspended.cleanupPending, true);

  const after = await root(value.serverId);
  assert.equal(after.status, "suspended");
  assert.equal(after.moderationReason, "Abuse report");
  assert.equal(after.moderatedBy, staff);
  // Frozen for everyone, owner included.
  await rejection(access(value.uid, value.serverId), "permission-denied");
  await rejection(access(target, value.serverId), "permission-denied");
  // The generation is ending, not still live.
  const session = (await db.doc(
    `clubs/${value.serverId}/channels/${live.channelId}/channelSessions/${live.sessionId}`,
  ).get()).data();
  assert.equal(session.status, "ending");
  assert.equal((await db.doc(`rooms/${live.roomId}`).get()).data().isLive, false);
  const endJob = await job(session.endOperationId);
  assert.equal(endJob.kind, "sessionEnd");

  const restored = await value.staffSetServerModerationStatus({
    serverId: value.serverId, suspended: false, reason: null, actorUid: staff,
  });
  assert.equal(restored.status, "active");
  assert.equal((await root(value.serverId)).moderationReason, null);
  assert.equal((await access(target, value.serverId)).member.userId, target);
  // Re-running either direction is a no-op, not a second write.
  assert.equal((await value.staffSetServerModerationStatus({
    serverId: value.serverId, suspended: false, reason: null, actorUid: staff,
  })).changed, false);
});

emulatorTest("staff removal and staff ban carry the same V1 invariants a raw admin write would skip", async () => {
  const value = await fixture();
  const staff = await user("staff");
  const removed = await member(value);
  const banned = await member(value);

  const removal = await value.staffRemoveServerMember({
    serverId: value.serverId, memberId: removed, actorUid: staff,
  });
  assert.equal(removal.changed, true);
  assert.equal((await membership(value.serverId, removed)).exists, false);
  assert.equal((await authorization(value.serverId, removed)).data().status, "left");
  assert.equal((await mirror(value.serverId, removed)).exists, false);
  // An already-absent member is reported, never an error — legacy parity.
  assert.equal((await value.staffRemoveServerMember({
    serverId: value.serverId, memberId: removed, actorUid: staff,
  })).alreadyRemoved, true);

  const ban = await value.staffSetServerMemberBan({
    serverId: value.serverId, memberId: banned, banned: true, reason: "Ban evasion", actorUid: staff,
  });
  assert.equal(ban.changed, true);
  const record = (await membership(value.serverId, banned)).data();
  assert.equal(record.banned, true);
  assert.equal(record.bannedBy, staff);
  assert.equal(record.authorizationRevision, ban.membershipRevision);
  await rejection(access(banned, value.serverId), "permission-denied");
  assert.equal((await value.staffSetServerMemberBan({
    serverId: value.serverId, memberId: banned, banned: false, reason: null, actorUid: staff,
  })).changed, true);
  assert.equal((await access(banned, value.serverId)).member.banned, false);

  // Staff may not remove or ban the owner, exactly as legacy refuses.
  await rejection(value.staffRemoveServerMember({
    serverId: value.serverId, memberId: value.uid, actorUid: staff,
  }), "failed-precondition");
  await rejection(value.staffSetServerMemberBan({
    serverId: value.serverId, memberId: value.uid, banned: true, reason: "x", actorUid: staff,
  }), "failed-precondition");
});

emulatorTest("staff deletion is NOT blocked by a live generation: it ends it and stages bounded content cleanup", async () => {
  const value = await fixture();
  const staff = await user("staff");
  const live = await startLiveGeneration(value, value.uid);
  const outcome = await value.staffDeleteServer({ serverId: value.serverId, actorUid: staff });
  assert.equal(outcome.changed, true);
  assert.equal(outcome.endedSessions, 1);
  assert.equal(outcome.contentCleanupPending, true);
  assert.equal((await root(value.serverId)).deletionInProgress, true);
  const session = (await db.doc(
    `clubs/${value.serverId}/channels/${live.channelId}/channelSessions/${live.sessionId}`,
  ).get()).data();
  assert.equal(session.status, "ending");
  const document = await job(outcome.operationId);
  assert.equal(document.kind, "serverDelete");
  assert.equal(document.contentCleanupPending, true);
  assert.equal(document.rtcTargets.length, 1);
  assert.equal(document.rtcTargets[0].mode, "sessionEnd");
  validateConvergenceJob(document, outcome.operationId);
  // A second staff deletion reports the mark, it does not delete twice.
  assert.equal((await value.staffDeleteServer({ serverId: value.serverId, actorUid: staff })).alreadyMarked, true);
});

emulatorTest("a staff adapter refuses a legacy Club and an unknown root rather than acting on either", async () => {
  const value = await fixture();
  const staff = await user("staff");
  const legacyId = `legacy-${randomUUID()}`;
  await db.doc(`clubs/${legacyId}`).set({
    name: "Ordinary Club", ownerId: staff, type: "community", status: "active", memberCount: 1,
  });
  await rejection(value.staffSetServerModerationStatus({
    serverId: legacyId, suspended: true, reason: "x", actorUid: staff,
  }), "failed-precondition");
  await rejection(value.staffDeleteServer({ serverId: legacyId, actorUid: staff }), "failed-precondition");
  await rejection(value.staffRemoveServerMember({
    serverId: `srv_${"0".repeat(40)}`, memberId: value.uid, actorUid: staff,
  }), "not-found");
});

emulatorTest("a staff adapter refuses a HELD root, so the legacy staff path can never become an activation writer", async () => {
  const value = await fixture();
  const staff = await user("staff");
  const target = await member(value);
  await db.doc(`clubs/${value.serverId}`).update({ status: "preparing", serverActivationState: "held" });
  for (const action of [
    () => value.staffSetServerModerationStatus({ serverId: value.serverId, suspended: false, reason: null, actorUid: staff }),
    () => value.staffSetServerModerationStatus({ serverId: value.serverId, suspended: true, reason: "x", actorUid: staff }),
    () => value.staffRemoveServerMember({ serverId: value.serverId, memberId: target, actorUid: staff }),
    () => value.staffSetServerMemberBan({ serverId: value.serverId, memberId: target, banned: true, reason: "x", actorUid: staff }),
    () => value.staffDeleteServer({ serverId: value.serverId, actorUid: staff }),
  ]) {
    await rejection(action(), "permission-denied");
  }
  const after = await root(value.serverId);
  assert.equal(after.status, "preparing");
  assert.equal(after.serverActivationState, "held");
  assert.equal(after.deletionInProgress, undefined);
  assert.equal((await membership(value.serverId, target)).exists, true);
});

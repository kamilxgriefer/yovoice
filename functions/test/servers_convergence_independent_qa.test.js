const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

// Independent integration QA. Only this explicit localhost, demo-only graph
// is writable. The provider is a deterministic acknowledgement seam, NOT a
// LiveKit connection, offline-token provider proof, microphone or device test.
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let app; let db; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-convergence-independent" }, `independent-bridge-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

const { createServerCreationService } = require("../servers/creation");
const { createServerMembershipService } = require("../servers/memberships");
const { createServerChannelService } = require("../servers/channels");
const { createServerSessionService } = require("../servers/sessions");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const { accessPolicy, serverChannelRefId } = require("../servers/contract");
const { tokenRecipientId } = require("../servers/session_contract");
const { readChannelAccess } = require("../servers/authority");
const { operationIdentity } = require("../integrity/guards");

const qa = (name, fn) => test(`Independent bridge QA: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.", timeout: 60_000,
}, fn);
const req = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const rejected = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { resolve, promise };
};
const operationKinds = {
  joinServerV1: "server.join.v1", respondToServerInviteV1: "server.invite.respond.v1",
  leaveServerV1: "server.leave.v1", setServerMemberRoleV1: "server.member.role.v1",
  setServerChannelAccessV1: "server.channel.access.v1", archiveServerChannelV1: "server.channel.archive.v1",
  deleteServerChannelV1: "server.channel.delete.v1", transferServerOwnershipV1: "server.ownership.transfer.v1",
};

async function fixture({ type = "community", activate = true } = {}) {
  let nowMs = Date.now();
  const clock = () => nowMs;
  const owner = `qa-bridge-owner:${randomUUID()}`;
  await db.doc(`users/${owner}`).set({ displayName: "Independent owner", status: "active" });
  const deps = { db, Timestamp, clock };
  const created = await createServerCreationService(deps).createServerV1(req(owner, {
    requestId: randomUUID(), serverType: type, templateVersion: 1,
    name: "Independent bridge fixture", description: "", privacy: type === "community" ? "public" : "inviteOnly",
    defaultLanguage: "English",
  }));
  const root = db.doc(`clubs/${created.serverId}`);
  const sourceChannels = await root.collection("channels").get();
  const channel = sourceChannels.docs.find((doc) => doc.data().kind === "voice") ?? sourceChannels.docs.find((doc) => doc.data().roomId);
  const room = db.doc(`rooms/${channel.data().roomId}`);
  if (activate) {
    // No production activation exists; this direct write is a test fixture.
    await root.update({ status: "active", serverActivationState: "active" });
    for (const value of sourceChannels.docs.filter((doc) => doc.data().roomId)) {
      await db.doc(`rooms/${value.data().roomId}`).update({ status: "active", serverActivationState: "active", hostId: owner });
    }
  }
  const effects = { mint: [], remove: [], end: [] };
  const hooks = { remove: null, end: null };
  const provider = {
    assertSupported() {},
    async mintToken(input) {
      effects.mint.push(input);
      const token = `independent-bridge-test-only-${randomUUID()}`;
      return { serverUrl: "wss://independent-bridge.livekit.cloud", token, participantToken: token,
        roomName: input.binding.livekitRoomName, participantIdentity: input.uid,
        participantName: input.participantName, expiresAtMillis: clock() + 300_000,
        permissions: { canPublish: input.grant.canPublish, canSubscribe: input.grant.canSubscribe,
          canPublishData: input.grant.canPublishData }, permittedTrackSources: input.grant.permittedTrackSources,
        serverId: input.binding.serverId, channelId: input.binding.channelId, roomId: input.binding.roomId,
        sessionId: input.binding.sessionId, sessionRole: input.sessionRole };
    },
    async revokeParticipant(roomName, userId) {
      const effect = { roomName, userId }; effects.remove.push(effect);
      const receipt = { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(clock() / 1000) + 1) * 1000 };
      return hooks.remove ? hooks.remove(effect, receipt) : receipt;
    },
    async endRoom(roomName) {
      effects.end.push(roomName);
      return hooks.end ? hooks.end(roomName) : {};
    },
  };
  const dependencies = { ...deps, livekit: provider };
  const service = { ...createServerMembershipService(dependencies), ...createServerChannelService(dependencies),
    ...createServerSessionService(dependencies), ...createServerConvergenceRuntimeService(dependencies) };
  const target = { serverId: root.id, channelId: channel.id };
  async function mutate(method, patch = {}, uid = owner) {
    const data = { serverId: root.id, requestId: randomUUID(), ...patch };
    const result = await service[method](req(uid, data));
    const { requestId, ...input } = data;
    if (input.policy) input.policy = accessPolicy(input.policy);
    const identity = operationIdentity(operationKinds[method], uid, requestId, input);
    return { result, data, ref: db.doc(`serverControlOutbox/${identity.id}`) };
  }
  async function join(uid = `qa:member+żółć-${randomUUID()}`) {
    await db.doc(`users/${uid}`).set({ displayName: "Independent member", status: "active" });
    if (type === "community") await mutate("joinServerV1", {}, uid);
    else {
      const currentOwner = (await root.get()).data().ownerId;
      const currentMember = (await root.collection("members").doc(currentOwner).get()).data();
      await root.collection("invites").doc(uid).set({ serverSchemaVersion: 1, serverId: root.id, inviteeId: uid,
        inviterId: currentOwner, inviterAuthorizationRevision: currentMember.authorizationRevision,
        generation: 1, status: "pending", expiresAt: Timestamp.fromMillis(clock() + 60_000) });
      await mutate("respondToServerInviteV1", { response: "accept" }, uid);
    }
    return uid;
  }
  const start = (uid = owner, channelId = channel.id) => service.startServerChannelSessionV1(req(uid,
    { serverId: root.id, channelId, requestId: randomUUID() }));
  const token = (sessionId, uid = owner, requestId = randomUUID()) => service.createServerChannelTokenV1(req(uid,
    { ...target, sessionId, requestId }));
  const end = (sessionId, uid = owner) => service.endServerChannelSessionV1(req(uid,
    { ...target, sessionId, requestId: randomUUID() }));
  const process = (ref, pageSize = 20) => service.processServerConvergencePage({ operationId: ref.id, pageSize });
  async function drain(ref, pageSize = 20) {
    for (let page = 0; page < 120; page += 1) {
      const result = await process(ref, pageSize);
      if (!result.cleanupPending || result.recoveryRequired || result.contentCleanupPending) return result;
    }
    assert.fail("Independent convergence fixture did not settle in bounded pages.");
  }
  const session = (id) => channel.ref.collection("channelSessions").doc(id);
  return { owner, root, channel: channel.ref, room, target, effects, hooks, service,
    clock, advance: (ms) => { nowMs += ms; }, mutate, join, start, token, end, process, drain, session,
    recipient: (id, uid) => session(id).collection("tokenRecipients").doc(tokenRecipientId(uid)),
    participant: (uid) => room.collection("participants").doc(uid),
    mirror: (uid) => db.doc(`activeVoiceSessions/${uid}/rooms/${room.id}`),
    access: (uid, channelId = channel.id) => db.runTransaction((transaction) =>
      readChannelAccess({ db, transaction, uid, serverId: root.id, channelId })),
  };
}

qa("held configuration can converge empty projections but never activate voice", async () => {
  const f = await fixture({ activate: false });
  const job = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 1,
    policy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] } });
  assert.deepEqual((await job.ref.get()).data().rtcTargets, []);
  assert.equal((await f.drain(job.ref, 1)).cleanupPending, false);
  await rejected(f.start(), "permission-denied");
  assert.equal((await f.root.get()).data().serverActivationState, "held");
  assert.equal((await f.room.get()).data().hostId, null);
  assert.deepEqual(f.effects, { mint: [], remove: [], end: [] });
});

qa("unknown bridge metadata fails before lease writes or provider calls", async () => {
  const f = await fixture(); const member = await f.join(); const { sessionId } = await f.start();
  await f.token(sessionId, member);
  const job = await f.mutate("leaveServerV1", {}, member);
  const original = (await job.ref.get()).data();
  for (const patch of [{ convergenceVersion: 999 }, { rtcTargets: null }, { rtcStatus: "successful" },
    { bridgeLeaseExpiresAtMillis: -1 }, { rtcRecipientCursor: "../foreign" }]) {
    await job.ref.set({ ...original, ...patch });
    const before = (await job.ref.get()).data();
    await assert.rejects(f.process(job.ref));
    assert.deepEqual((await job.ref.get()).data(), before);
  }
  assert.equal(f.effects.remove.length, 0); assert.equal(f.effects.end.length, 0);
});

qa("one uncertain recipient pins a partial page without retrying settled siblings", async () => {
  const f = await fixture(); const users = [];
  for (let index = 0; index < 6; index += 1) users.push(await f.join());
  const { sessionId } = await f.start();
  for (const uid of users) await f.token(sessionId, uid);
  const sorted = [...users].sort((a, b) => tokenRecipientId(a).localeCompare(tokenRecipientId(b)));
  const uncertain = sorted[1];
  const job = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 1,
    policy: { accessMode: "members", roleIds: [], userIds: [] } });
  f.hooks.remove = ({ userId }, receipt) => userId === uncertain ? {} : receipt;
  const first = await f.process(job.ref, 4);
  assert.equal(first.recoveryRequired, true); assert.equal(first.rtcCleanupPending, true);
  assert.equal((await job.ref.get()).data().rtcRecipientCursor, null);
  assert.deepEqual(new Set(f.effects.remove.map((v) => v.userId)), new Set(sorted.slice(0, 4)));
  const attempts = f.effects.remove.length;
  f.advance(120_001); f.hooks.remove = null;
  await rejected(f.token(sessionId, uncertain), "failed-precondition");
  await f.token(sessionId, sorted[0]);
  assert.equal((await f.process(job.ref, 4)).recoveryRequired, true);
  assert.equal(f.effects.remove.length, attempts);
  assert.equal(f.effects.end.length, 0);
  await rejected(f.end(sessionId, uncertain), "permission-denied");
  assert.equal((await f.end(sessionId)).cleanupPending, false);
  const next = await f.start(); await f.token(next.sessionId, uncertain);
  const mirror = (await f.mirror(uncertain).get()).data();
  const effectsBefore = f.effects.remove.length + f.effects.end.length;
  assert.equal((await f.drain(job.ref, 4)).cleanupPending, false);
  assert.equal(f.effects.remove.length + f.effects.end.length, effectsBefore);
  assert.deepEqual((await f.mirror(uncertain).get()).data(), mirror);
  assert.equal((await f.recipient(sessionId, uncertain).get()).data().revocationAttempt.state, "uncertain");
});

qa("different role and ACL jobs share one durable recipient attempt", async () => {
  const f = await fixture(); const member = await f.join(); const { sessionId } = await f.start();
  await f.token(sessionId, member);
  const role = await f.mutate("setServerMemberRoleV1", { memberId: member, role: "coOwner" });
  const acl = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 1,
    policy: { accessMode: "members", roleIds: [], userIds: [] } });
  const entered = deferred(); const release = deferred();
  f.hooks.remove = async (_, receipt) => { entered.resolve(); await release.promise; return receipt; };
  const pending = f.process(role.ref); await entered.promise;
  try {
    assert.equal((await f.process(acl.ref)).rtcCleanupPending, true);
    assert.equal(f.effects.remove.length, 1);
    f.advance(120_001);
    assert.equal((await f.process(acl.ref)).recoveryRequired, true);
    assert.equal(f.effects.remove.length, 1);
    await rejected(f.token(sessionId, member), "failed-precondition");
    release.resolve(); await pending; f.advance(2_001);
    await f.token(sessionId, member);
    assert.equal((await f.drain(acl.ref)).cleanupPending, false);
    assert.equal((await f.drain(role.ref)).cleanupPending, false);
    assert.equal(f.effects.remove.length, 1); assert.equal(f.effects.end.length, 0);
  } finally { release.resolve(); await Promise.allSettled([pending]); }
});

qa("late recipient-page acknowledgement cannot overwrite a changed cursor", async () => {
  const f = await fixture(); const members = [await f.join(), await f.join()]; const { sessionId } = await f.start();
  for (const member of members) await f.token(sessionId, member);
  const job = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 1,
    policy: { accessMode: "members", roleIds: [], userIds: [] } });
  const entered = deferred(); const release = deferred();
  f.hooks.remove = async (_, receipt) => { entered.resolve(); await release.promise; return receipt; };
  const pending = f.process(job.ref, 1); await entered.promise;
  try {
    const cursor = tokenRecipientId(f.effects.remove[0].userId);
    await job.ref.update({ rtcRecipientCursor: cursor });
    const changed = (await job.ref.get()).data();
    release.resolve(); await pending;
    assert.deepEqual((await job.ref.get()).data(), changed);
    assert.equal(f.effects.remove.length, 1);
  } finally { release.resolve(); await Promise.allSettled([pending]); }
});

qa("two ownership transfers with overlapping terminal cleanup preserve the new generation", async () => {
  const f = await fixture({ type: "company" });
  const middle = await f.join(); const last = await f.join(); const { sessionId } = await f.start();
  const oldToken = await f.token(sessionId);
  const first = await f.mutate("transferServerOwnershipV1", { newOwnerId: middle });
  const second = await f.mutate("transferServerOwnershipV1", { newOwnerId: last }, middle);
  const firstTarget = (await first.ref.get()).data().rtcTargets[0];
  assert.deepEqual((await second.ref.get()).data().rtcTargets[0], firstTarget);
  const entered = deferred(); const release = deferred(); let endCount = 0;
  f.hooks.end = async () => { if (++endCount === 1) { entered.resolve(); await release.promise; } return {}; };
  const pending = f.process(first.ref); await entered.promise;
  try {
    assert.equal((await f.process(second.ref)).cleanupPending, true);
    await rejected(f.start(last), "failed-precondition");
    f.advance(120_001);
    assert.equal((await f.drain(second.ref)).cleanupPending, false);
    const next = await f.start(last); const fresh = await f.token(next.sessionId, last);
    assert.notEqual(fresh.roomName, oldToken.roomName);
    const mirror = (await f.mirror(last).get()).data();
    release.resolve(); await pending;
    assert.equal((await f.drain(first.ref)).cleanupPending, false);
    assert.deepEqual((await f.mirror(last).get()).data(), mirror);
    assert.equal((await f.channel.get()).data().activeSessionId, next.sessionId);
    assert.ok(f.effects.end.every((name) => name === oldToken.roomName));
    assert.equal((await f.root.get()).data().ownerId, last);
  } finally { release.resolve(); await Promise.allSettled([pending]); }
});

qa("ownership projection reads current membership and never resurrects a departed former owner", async () => {
  const f = await fixture({ type: "company" }); const next = await f.join();
  const hr = (await f.root.collection("channels").where("seedKey", "==", "hr").get()).docs[0];
  const transferred = await f.mutate("transferServerOwnershipV1", { newOwnerId: next });
  const left = await f.mutate("leaveServerV1", {}, f.owner);
  assert.equal((await f.drain(transferred.ref, 1)).cleanupPending, false);
  assert.equal((await f.drain(left.ref)).cleanupPending, false);
  await rejected(f.access(f.owner, hr.id), "permission-denied"); await f.access(next, hr.id);
  assert.equal((await db.doc(`users/${f.owner}/clubs/${f.root.id}`).get()).exists, false);
  assert.equal((await hr.ref.collection("accessGrants").doc(f.owner).get()).exists, false);
  assert.equal((await db.doc(`users/${f.owner}/serverChannelRefs/${serverChannelRefId(f.root.id, hr.id)}`).get()).exists, false);
});

qa("a mismatched terminal receipt refuses a membership mutation atomically", async () => {
  const f = await fixture(); const member = await f.join(); const { sessionId } = await f.start();
  await f.token(sessionId);
  const archive = await f.mutate("archiveServerChannelV1", { channelId: f.channel.id });
  const target = (await archive.ref.get()).data().rtcTargets[0];
  await db.doc(`serverControlOutbox/${target.endOperationId}`).update({ roomId: "independent-foreign-room" });
  const rootBefore = (await f.root.get()).data();
  const memberBefore = (await f.root.collection("members").doc(member).get()).data();
  const jobsBefore = await db.collection("serverControlOutbox").where("serverId", "==", f.root.id).get();
  await rejected(f.mutate("leaveServerV1", {}, member), "failed-precondition");
  assert.deepEqual((await f.root.get()).data(), rootBefore);
  assert.deepEqual((await f.root.collection("members").doc(member).get()).data(), memberBefore);
  assert.equal((await db.collection("serverControlOutbox").where("serverId", "==", f.root.id).get()).size, jobsBefore.size);
  assert.equal(f.effects.remove.length, 0); assert.equal(f.effects.end.length, 0);
});

qa("20-recipient archive reserves room teardown within the adapter-effect page bound", async () => {
  const f = await fixture(); const members = [];
  for (let index = 0; index < 20; index += 1) members.push(await f.join());
  const { sessionId } = await f.start();
  for (const member of members) await f.token(sessionId, member);
  const archived = await f.mutate("archiveServerChannelV1", { channelId: f.channel.id });
  const first = await f.process(archived.ref, 20);
  assert.equal(first.rtcCleanupPending, true); assert.equal(f.effects.remove.length, 19);
  assert.equal(f.effects.end.length, 0);
  const before = f.effects.remove.length + f.effects.end.length;
  assert.equal((await f.drain(archived.ref, 20)).cleanupPending, false);
  assert.equal(f.effects.remove.length, 20); assert.equal(f.effects.end.length, 1);
  assert.ok(f.effects.remove.length + f.effects.end.length - before <= 20);
  // The actual endRoom adapter may perform many HTTP requests. This test
  // deliberately makes no HTTP, latency or provider-cost boundedness claim.
});

qa("idle text deletion is idempotent but stays pending with content untouched", async () => {
  const f = await fixture();
  const textChannel = (await f.root.collection("channels").where("kind", "==", "text").get()).docs[0];
  const history = textChannel.ref.collection("messages").doc("independent-history");
  const body = { content: "Independent retained private fixture", attachment: { generation: "123456789012345678" } };
  await history.set(body);
  const deleted = await f.mutate("deleteServerChannelV1", { channelId: textChannel.id });
  assert.deepEqual(await f.service.deleteServerChannelV1(req(f.owner, deleted.data)), deleted.result);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const result = await f.process(deleted.ref);
    assert.equal(result.rtcCleanupPending, false); assert.equal(result.contentCleanupPending, true);
    assert.equal(result.cleanupPending, true); assert.equal(result.processed, 0);
  }
  assert.deepEqual((await history.get()).data(), body);
  assert.equal((await deleted.ref.get()).data().status, "pending");
  assert.deepEqual(f.effects, { mint: [], remove: [], end: [] });
});

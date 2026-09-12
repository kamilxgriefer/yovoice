const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let db; let app; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app"); const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-server-convergence" }, `server-bridge-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerMembershipService } = require("../servers/memberships");
const { createServerSessionService } = require("../servers/sessions");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const { createServerConvergenceService } = require("../servers/convergence");
const { accessPolicy, canonicalLiveKitRoomName, serverChannelRefId } = require("../servers/contract");
const { tokenRecipientId } = require("../servers/session_contract");
const { readChannelAccess, grantDocument } = require("../servers/authority");
const { channelDocument, channelRoomDocument } = require("../servers/documents");
const { operationIdentity } = require("../integrity/guards");
const emulatorTest = (name, fn) => test(`Convergence: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const denied = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const gate = () => { let resolve; const promise = new Promise((done) => { resolve = done; }); return { resolve, promise }; };
const methods = { joinServerV1: "server.join.v1", respondToServerInviteV1: "server.invite.respond.v1",
  leaveServerV1: "server.leave.v1", setServerMemberRoleV1: "server.member.role.v1",
  setServerChannelAccessV1: "server.channel.access.v1", transferServerOwnershipV1: "server.ownership.transfer.v1",
  archiveServerChannelV1: "server.channel.archive.v1", deleteServerChannelV1: "server.channel.delete.v1" };
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

async function fixture(serverType = "community") {
  const owner = `bridge-owner${serverType === "family" ? "-" : ":"}${randomUUID()}`; let nowMs = Date.now();
  await db.doc(`users/${owner}`).set({ displayName: "Bridge test owner", status: "active" });
  const clock = () => nowMs; const deps = { db, Timestamp, clock };
  const created = await createServerCreationService(deps).createServerV1(request(owner, {
    requestId: randomUUID(), serverType, templateVersion: 1, name: "Bridge emulator fixture",
    description: "", privacy: serverType === "community" ? "public" : "inviteOnly", defaultLanguage: "English",
  }));
  const root = db.doc(`clubs/${created.serverId}`);
  // Isolated emulator activation only. There is no shipped activation path.
  await root.update({ status: "active", serverActivationState: "active" });
  const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
  for (const anchor of anchors.docs) await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: owner });
  const channels = await root.collection("channels").get();
  const channel = channels.docs.find((doc) => doc.data().kind === "voice") ?? channels.docs.find((doc) => doc.data().roomId);
  const roomId = channel.data().roomId;
  const calls = { removed: [], ended: [], minted: [], maxConcurrency: 0 }; let concurrency = 0;
  const hooks = { remove: null, end: null, sign: null };
  // Deterministic provider-control seam. These tests prove requested effects
  // and acknowledgement handling, not Cloud connectivity or physical capture.
  const livekit = {
    assertSupported() {},
    async mintToken(value) {
      calls.minted.push(value); if (hooks.sign) await hooks.sign(value);
      const token = `test-only-${randomUUID()}`;
      return { serverUrl: "wss://test-fixture.livekit.cloud", token, participantToken: token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid, participantName: value.participantName,
        expiresAtMillis: nowMs + 300_000, permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources, sessionRole: value.sessionRole,
        serverId: value.binding.serverId, channelId: value.binding.channelId, roomId: value.binding.roomId, sessionId: value.binding.sessionId };
    },
    async revokeParticipant(roomName, userId) {
      calls.removed.push({ roomName, userId }); concurrency += 1; calls.maxConcurrency = Math.max(calls.maxConcurrency, concurrency);
      try {
        const receipt = { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 };
        return hooks.remove ? await hooks.remove(roomName, userId, receipt) : receipt;
      } finally { concurrency -= 1; }
    },
    async endRoom(roomName) { calls.ended.push(roomName); return hooks.end ? hooks.end(roomName) : {}; },
  };
  const dependencies = { ...deps, livekit };
  const service = { ...createServerChannelService(dependencies), ...createServerMembershipService(dependencies),
    ...createServerSessionService(dependencies), ...createServerConvergenceRuntimeService(dependencies),
    ...createServerConvergenceService(dependencies) };
  const target = { serverId: root.id, channelId: channel.id };
  async function mutate(method, extra = {}, uid = owner) {
    const data = { serverId: root.id, requestId: randomUUID(), ...extra };
    const result = await service[method](request(uid, data));
    const { requestId, ...input } = data;
    if (input.policy) input.policy = accessPolicy(input.policy);
    const id = operationIdentity(methods[method], uid, requestId, input).id;
    return { result, reference: db.doc(`serverControlOutbox/${id}`), data };
  }
  async function member() {
    const uid = `bridge-member:${randomUUID()}`;
    await db.doc(`users/${uid}`).set({ displayName: "Bridge test member", status: "active" });
    if (serverType === "community") await mutate("joinServerV1", {}, uid);
    else {
      const current = (await root.get()).data(); const inviter = (await root.collection("members").doc(current.ownerId).get()).data();
      await root.collection("invites").doc(uid).set({ serverSchemaVersion: 1, serverId: root.id, inviteeId: uid,
        inviterId: current.ownerId, inviterAuthorizationRevision: inviter.authorizationRevision,
        generation: 1, status: "pending", expiresAt: Timestamp.fromMillis(nowMs + 60_000) });
      await mutate("respondToServerInviteV1", { response: "accept" }, uid);
    }
    return uid;
  }
  const startAt = (channelId, uid = owner) => service.startServerChannelSessionV1(request(uid,
    { serverId: root.id, channelId, requestId: randomUUID() }));
  const start = (uid = owner) => startAt(channel.id, uid);
  const token = (sessionId, uid = owner, requestId = randomUUID()) => service.createServerChannelTokenV1(request(uid,
    { ...target, sessionId, requestId }));
  const end = (sessionId, uid = owner) => service.endServerChannelSessionV1(request(uid,
    { ...target, sessionId, requestId: randomUUID() }));
  const process = (reference, pageSize = 20) => service.processServerConvergencePage({ operationId: reference.id, pageSize });
  async function drain(reference) {
    let result;
    for (let page = 0; page < 150; page += 1) {
      result = await process(reference);
      if (!result.cleanupPending || result.recoveryRequired || result.contentCleanupPending) return result;
    }
    assert.fail("The bounded bridge fixture did not settle.");
  }
  return { ...service, owner, root, target, channel, roomId, dependencies, calls, hooks, clock,
    advance: (ms) => { nowMs += ms; }, mutate, member, start, startAt, token, end, process, drain,
    recipient: (sessionId, uid = owner) => channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).doc(tokenRecipientId(uid)),
    access: (uid, channelId = channel.id) => db.runTransaction((transaction) => readChannelAccess({ db, transaction, uid, serverId: root.id, channelId })) };
}

emulatorTest("leave captures offline-issued credentials and immediately denies replay before provider work", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start();
  const requestId = randomUUID(); const connection = await f.token(sessionId, member, requestId);
  const job = await f.mutate("leaveServerV1", {}, member);
  assert.equal(f.calls.removed.length, 0);
  assert.equal((await job.reference.get()).data().rtcTargets[0].sessionId, sessionId);
  await denied(f.token(sessionId, member, requestId), "permission-denied");
  assert.equal((await f.drain(job.reference)).cleanupPending, false);
  assert.deepEqual(f.calls.removed, [{ roomName: connection.roomName, userId: member }]);
  assert.equal((await db.doc(`activeVoiceSessions/${member}/rooms/${f.roomId}`).get()).exists, false);
  assert.equal((await db.doc(`rooms/${f.roomId}/participants/${member}`).get()).data().isMuted, true);
  assert.equal((await f.root.get()).data().onlineCount, 0);
});

emulatorTest("role projection never promotes session role or clears moderator mute", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start(); await f.token(sessionId, member);
  const participant = db.doc(`rooms/${f.roomId}/participants/${member}`);
  await participant.update({ serverMuted: true, authorizationRevision: 2 });
  const roleBefore = (await participant.get()).data().role;
  const job = await f.mutate("setServerMemberRoleV1", { memberId: member, role: "coOwner" });
  await denied(f.token(sessionId, member), "failed-precondition");
  await f.drain(job.reference); f.advance(2_001);
  const next = await f.token(sessionId, member);
  assert.equal(next.sessionRole, roleBefore); assert.equal(next.permissions.canPublish, false);
  assert.deepEqual(next.permittedTrackSources, []);
  assert.equal((await participant.get()).data().serverMuted, true); assert.equal((await participant.get()).data().isMuted, true);
});

emulatorTest("uncertain leave cannot retry, rejoin or end another person's session; authorized end recovers", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start(); await f.token(sessionId, member);
  const job = await f.mutate("leaveServerV1", {}, member);
  f.hooks.remove = () => { throw new Error("test-only uncertain transport"); };
  assert.equal((await f.process(job.reference)).recoveryRequired, true);
  assert.equal((await job.reference.get()).data().rtcTargetIndex, 0);
  await f.mutate("joinServerV1", {}, member); f.advance(120_001); f.hooks.remove = null;
  assert.equal((await f.process(job.reference)).recoveryRequired, true);
  assert.equal(f.calls.removed.length, 1); assert.equal(f.calls.ended.length, 0);
  await denied(f.token(sessionId, member), "failed-precondition");
  await denied(f.end(sessionId, member), "permission-denied");
  assert.equal((await f.end(sessionId)).cleanupPending, false);
  const next = await f.start(); await f.token(next.sessionId, member);
  const calls = f.calls.removed.length;
  assert.equal((await f.drain(job.reference)).cleanupPending, false); assert.equal(f.calls.removed.length, calls);
});

emulatorTest("ACL scans token recipients including removed members in globally bounded pages", async () => {
  const f = await fixture(); const members = [];
  for (let index = 0; index < 25; index += 1) members.push(await f.member());
  const { sessionId } = await f.start();
  for (const member of members) await f.token(sessionId, member);
  await f.mutate("leaveServerV1", {}, members[0]);
  const job = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 1,
    policy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] } });
  const first = await f.process(job.reference);
  assert.equal(first.rtcCleanupPending, true); assert.equal(f.calls.removed.length, 20);
  assert.equal((await job.reference.get()).data().rtcTargetIndex, 0);
  assert.ok((await job.reference.get()).data().rtcRecipientCursor);
  assert.equal((await f.drain(job.reference)).cleanupPending, false);
  assert.equal(f.calls.removed.length, 25); assert.ok(f.calls.maxConcurrency <= 4);
  assert.ok(f.calls.removed.some((call) => call.userId === members[0]));
  assert.equal(f.calls.ended.length, 0);
});

emulatorTest("superseded ACL still revokes old credentials, but stale jobs preserve fresh authorized admission", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start(); await f.token(sessionId, member);
  const old = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 1,
    policy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] } });
  const newer = await f.mutate("setServerChannelAccessV1", { channelId: f.channel.id, expectedAclRevision: 2,
    policy: { accessMode: "members", roleIds: [], userIds: [] } });
  await f.drain(old.reference); assert.equal((await old.reference.get()).data().grantStatus, "superseded");
  assert.equal(f.calls.removed.length, 1); f.advance(2_001); await f.token(sessionId, member);
  const before = (await f.recipient(sessionId, member).get()).data();
  await f.drain(newer.reference); assert.equal(f.calls.removed.length, 1);
  assert.deepEqual((await f.recipient(sessionId, member).get()).data(), before);
});

emulatorTest("archive atomically stages teardown and keeps its barrier during provider failure", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const token = await f.token(sessionId);
  await f.channel.ref.collection("messages").doc("test-history").set({ content: "Emulator-only retained history" });
  const job = await f.mutate("archiveServerChannelV1", { channelId: f.channel.id });
  const session = (await f.channel.ref.collection("channelSessions").doc(sessionId).get()).data();
  const captured = (await job.reference.get()).data().rtcTargets[0];
  assert.equal(session.status, "ending"); assert.equal(session.endOperationId, captured.endOperationId);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, sessionId);
  assert.equal((await f.channel.ref.get()).data().activeSessionId, null);
  f.hooks.remove = () => ({ alreadyAbsent: true });
  assert.equal((await f.process(job.reference)).cleanupPending, true);
  assert.equal((await job.reference.get()).data().rtcTargetIndex, 0);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, sessionId);
  f.hooks.remove = null;
  assert.equal((await f.drain(job.reference)).cleanupPending, false);
  assert.deepEqual(f.calls.ended, [token.roomName]);
  assert.equal((await f.channel.ref.collection("channelSessions").doc(sessionId).get()).data().status, "ended");
  assert.equal((await f.channel.ref.collection("messages").doc("test-history").get()).exists, true);
});

emulatorTest("delete completes RTC only and never claims missing content cleanup is done", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  const job = await f.mutate("deleteServerChannelV1", { channelId: f.channel.id });
  const result = await f.drain(job.reference);
  assert.equal(result.rtcCleanupPending, false); assert.equal(result.contentCleanupPending, true); assert.equal(result.cleanupPending, true);
  assert.equal((await job.reference.get()).data().status, "pending");
  const calls = f.calls.removed.length; await f.process(job.reference); assert.equal(f.calls.removed.length, calls);
});

emulatorTest("expired bridge progress lease never reclaims provider work and late completion cannot advance progress", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start(); await f.token(sessionId, member);
  const job = await f.mutate("setServerMemberRoleV1", { memberId: member, role: "coOwner" });
  const entered = gate(); const release = gate();
  f.hooks.remove = async (_, __, receipt) => { entered.resolve(); await release.promise; return receipt; };
  const first = f.process(job.reference); await entered.promise;
  try {
    assert.equal((await f.process(job.reference)).cleanupPending, true); assert.equal(f.calls.removed.length, 1);
    f.advance(120_001); assert.equal((await f.process(job.reference)).recoveryRequired, true);
    assert.equal(f.calls.removed.length, 1); await denied(f.token(sessionId, member), "failed-precondition");
    release.resolve(); await first;
    assert.equal((await job.reference.get()).data().rtcTargetIndex, 0);
    f.advance(2_001); await f.token(sessionId, member);
    assert.equal((await f.drain(job.reference)).cleanupPending, false); assert.equal(f.calls.removed.length, 1);
  } finally { release.resolve(); await Promise.allSettled([first]); }
});

emulatorTest("membership change overtakes signing without disclosing or forgetting an offline credential", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start();
  const entered = gate(); const release = gate();
  f.hooks.sign = async () => { entered.resolve(); await release.promise; };
  const pending = f.token(sessionId, member); const rejected = denied(pending, "permission-denied"); await entered.promise;
  try {
    const job = await f.mutate("leaveServerV1", {}, member); release.resolve(); await rejected;
    assert.equal((await f.recipient(sessionId, member).get()).exists, false);
    assert.equal((await f.drain(job.reference)).cleanupPending, false); assert.equal(f.calls.removed.length, 0);
  } finally { release.resolve(); await Promise.allSettled([pending]); }
});

emulatorTest("transfer reuses already-ending archived/deleting generations and defers private grants", async () => {
  const f = await fixture("company"); const nextOwner = await f.member();
  const hr = (await f.root.collection("channels").where("seedKey", "==", "hr").get()).docs[0];
  const current = await f.start(); await f.token(current.sessionId);
  const priorEnds = [];
  for (const method of ["archiveServerChannelV1", "deleteServerChannelV1"]) {
    const added = await f.createServerChannelV1(request(f.owner, { serverId: f.root.id, requestId: randomUUID(),
      kind: "voice", name: "Ending fixture", categoryId: null, accessMode: "members", experience: "community", mediaMode: "audio" }));
    const started = await f.startAt(added.channelId);
    await f.createServerChannelTokenV1(request(f.owner, { serverId: f.root.id, channelId: added.channelId,
      sessionId: started.sessionId, requestId: randomUUID() }));
    const job = await f.mutate(method, { channelId: added.channelId });
    priorEnds.push({ reference: job.reference, target: (await job.reference.get()).data().rtcTargets[0] });
  }
  const transfer = await f.mutate("transferServerOwnershipV1", { newOwnerId: nextOwner });
  const targets = (await transfer.reference.get()).data().rtcTargets;
  assert.equal(targets.length, 3);
  for (const old of priorEnds) assert.equal(targets.find((target) => target.channelId === old.target.channelId).endOperationId, old.target.endOperationId);
  await denied(f.access(nextOwner, hr.id), "permission-denied"); await denied(f.access(f.owner, hr.id), "permission-denied");
  await denied(f.start(nextOwner), "failed-precondition");
  assert.equal((await f.drain(transfer.reference)).cleanupPending, false);
  await f.access(nextOwner, hr.id); await denied(f.access(f.owner, hr.id), "permission-denied");
  const next = await f.start(nextOwner); await f.token(next.sessionId, nextOwner);
  const mirror = db.doc(`activeVoiceSessions/${nextOwner}/rooms/${f.roomId}`); const before = (await mirror.get()).data();
  const effects = f.calls.removed.length + f.calls.ended.length;
  for (const old of priorEnds) await f.process(old.reference);
  assert.equal(f.calls.removed.length + f.calls.ended.length, effects);
  assert.deepEqual((await mirror.get()).data(), before);
});

emulatorTest("orphan, mismatched and multiple nonterminal generations refuse the mutation atomically", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start();
  const room = db.doc(`rooms/${f.roomId}`); const sessionReference = f.channel.ref.collection("channelSessions").doc(sessionId);
  const originalRoom = (await room.get()).data(); const originalChannel = (await f.channel.ref.get()).data();
  const role = () => f.mutate("setServerMemberRoleV1", { memberId: member, role: "coOwner" });
  await room.update({ serverOwnerId: "foreign-owner" }); await denied(role(), "failed-precondition");
  await room.set(originalRoom); await f.channel.ref.update({ activeSessionId: null });
  await room.update({ isLive: false, voiceSessionId: null, livekitRoomName: null });
  await denied(role(), "failed-precondition");
  await room.set(originalRoom); await f.channel.ref.set(originalChannel);
  const duplicate = f.channel.ref.collection("channelSessions").doc("test-second-generation");
  await duplicate.set({ ...(await sessionReference.get()).data(), sessionId: duplicate.id,
    livekitRoomName: canonicalLiveKitRoomName(f.root.id, f.channel.id, duplicate.id) });
  await denied(f.mutate("archiveServerChannelV1", { channelId: f.channel.id }), "failed-precondition");
  assert.equal((await f.root.collection("members").doc(member).get()).data().role, "member");
  assert.equal((await f.channel.ref.get()).data().status, "active");
  assert.equal(f.calls.removed.length, 0);
});

emulatorTest("late bridge acknowledgement fences a changed immutable target without overwriting it", async () => {
  const f = await fixture(); const member = await f.member(); const { sessionId } = await f.start(); await f.token(sessionId, member);
  const job = await f.mutate("setServerMemberRoleV1", { memberId: member, role: "coOwner" });
  const entered = gate(); const release = gate();
  f.hooks.remove = async (_, __, receipt) => { entered.resolve(); await release.promise; return receipt; };
  const first = f.process(job.reference); await entered.promise;
  try {
    const original = (await job.reference.get()).data().rtcTargets;
    const changed = original.map((target) => ({ ...target, roomId: "test-foreign-anchor" }));
    await job.reference.update({ rtcTargets: changed });
    release.resolve(); await first;
    const after = (await job.reference.get()).data();
    assert.deepEqual(after.rtcTargets, changed); assert.equal(after.rtcTargetIndex, 0); assert.equal(after.status, "pending");
    f.advance(120_001); await denied(f.process(job.reference), "permission-denied");
    assert.equal(f.calls.removed.length, 1);
  } finally { release.resolve(); await Promise.allSettled([first]); }
});

emulatorTest("100 live family media channels transfer in exactly 416 unique mutation writes", async () => {
  const f = await fixture("family"); const nextOwner = await f.member();
  const root = (await f.root.get()).data(); const ownerMember = (await f.root.collection("members").doc(f.owner).get()).data();
  const originals = await f.root.collection("channels").get(); const batch = db.batch();
  for (const original of originals.docs) {
    batch.delete(original.ref);
    if (original.data().roomId) batch.delete(db.doc(`rooms/${original.data().roomId}`));
  }
  const channels = [];
  for (let index = 0; index < 100; index += 1) {
    const id = `maximum-channel-${index}`; const now = Timestamp.fromMillis(f.clock());
    const channel = channelDocument({ serverId: f.root.id, channelId: id, uid: f.owner, position: index, now,
      input: { kind: "voice", name: `Test channel ${index}`, categoryId: null, accessMode: "restricted", experience: "community", mediaMode: "audio" } });
    batch.set(f.root.collection("channels").doc(id), channel);
    batch.set(db.doc(`rooms/${channel.roomId}`), channelRoomDocument({ serverId: f.root.id, channelId: id, server: root, channel, now }));
    batch.set(f.root.collection("channels").doc(id).collection("accessGrants").doc(f.owner),
      grantDocument({ uid: f.owner, serverId: f.root.id, channelId: id, member: ownerMember, channel, now }));
    batch.set(db.doc(`users/${f.owner}/serverChannelRefs/${serverChannelRefId(f.root.id, id)}`), { serverId: f.root.id, channelId: id });
    channels.push({ id, channel });
  }
  batch.update(f.root, { defaultChatChannelId: null, announcementChannelId: null,
    defaultVoiceChannelId: channels[0].id, loungeRoomId: channels[0].channel.roomId });
  await batch.commit();
  for (const channel of channels) await f.startAt(channel.id);
  const attempts = [];
  const countedDb = new Proxy(db, { get(target, key) {
    if (key === "runTransaction") return (work, options) => target.runTransaction(async (transaction) => {
      const writes = []; attempts.push(writes);
      const counted = new Proxy(transaction, { get(tx, operation) {
        const value = tx[operation];
        if (["create", "set", "update", "delete"].includes(operation)) return (...args) => {
          writes.push({ operation, path: args[0].path }); return value.apply(tx, args);
        };
        return typeof value === "function" ? value.bind(tx) : value;
      } });
      return work(counted);
    }, options);
    const value = target[key]; return typeof value === "function" ? value.bind(target) : value;
  } });
  const service = createServerMembershipService({ ...f.dependencies, db: countedDb });
  const result = await service.transferServerOwnershipV1(request(f.owner,
    { serverId: f.root.id, newOwnerId: nextOwner, requestId: randomUUID() }));
  assert.equal(result.propagationPending, true);
  const mutation = attempts.find((writes) => writes.length > 100);
  assert.equal(mutation.length, 416); assert.equal(new Set(mutation.map((write) => write.path)).size, 416);
  assert.ok(attempts.some((writes) => writes.length === 1), "The actor-only attempt budget remains a separate transaction.");
  const sessions = await Promise.all(channels.map((channel) => f.root.collection("channels").doc(channel.id).collection("channelSessions").get()));
  assert.ok(sessions.every((page) => page.size === 1 && page.docs[0].data().status === "ending"));
  const jobs = await db.collection("serverControlOutbox").where("serverId", "==", f.root.id).where("kind", "==", "sessionEnd").get();
  assert.equal(jobs.size, 100); assert.equal(f.calls.removed.length, 0); assert.equal(f.calls.ended.length, 0);
  await denied(f.access(nextOwner, channels[0].id), "permission-denied");
});

emulatorTest("a stale ownership projection cannot restore private access after another transfer", async () => {
  const f = await fixture("company"); const middle = await f.member(); const finalOwner = await f.member();
  const hr = (await f.root.collection("channels").where("seedKey", "==", "hr").get()).docs[0];
  const first = await f.mutate("transferServerOwnershipV1", { newOwnerId: middle });
  const second = await f.mutate("transferServerOwnershipV1", { newOwnerId: finalOwner }, middle);
  await f.drain(first.reference);
  await denied(f.access(middle, hr.id), "permission-denied");
  await denied(f.access(finalOwner, hr.id), "permission-denied");
  assert.equal((await db.doc(`users/${middle}/clubs/${f.root.id}`).get()).data().role, "coOwner");
  await f.drain(second.reference); await f.access(finalOwner, hr.id);
  await denied(f.access(middle, hr.id), "permission-denied"); await denied(f.access(f.owner, hr.id), "permission-denied");
});

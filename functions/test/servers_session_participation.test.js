// Session participation (gap G5, ADR-181): promotion, demotion, hand raise and
// host/moderator mutes on a live V1 generation, and the revocation of an
// already-issued bearer token through the existing convergence worker. Every
// case runs against the Firestore emulator with the deterministic provider
// seam the sessions and convergence suites use: requested provider effects
// are asserted, never Cloud connectivity.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let db; let app; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-server-participation" }, `server-participation-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerMembershipService } = require("../servers/memberships");
const { createServerSessionService } = require("../servers/sessions");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const { PARTICIPATION_KIND, createServerSessionParticipationService } = require("../servers/session_participation");
const { tokenRecipientId } = require("../servers/session_contract");
const { canonicalLiveKitRoomName } = require("../servers/contract");
const { operationIdentity } = require("../integrity/guards");

const emulatorTest = (name, fn) => test(`Participation: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data, token = {}) => ({ auth: { uid, token: { email_verified: true, ...token } }, data });
const reject = (promise, code) => assert.rejects(promise, (error) => error.code === code, `expected ${code}`);
const KINDS = { setServerSessionParticipantRoleV1: "server.session.participant.role.v1",
  setServerSessionHandV1: "server.session.hand.v1", setServerSessionMuteV1: "server.session.mute.v1" };
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

async function fixture() {
  const owner = `part-owner:${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${owner}`).set({ displayName: "Participation owner", status: "active" });
  const deps = { db, Timestamp, clock };
  const created = await createServerCreationService(deps).createServerV1(request(owner, {
    requestId: randomUUID(), serverType: "community", templateVersion: 1, name: "Participation fixture",
    description: "", privacy: "public", defaultLanguage: "English",
  }));
  const root = db.doc(`clubs/${created.serverId}`);
  // Isolated emulator activation only; there is no shipped activation path.
  await root.update({ status: "active", serverActivationState: "active" });
  const channels = createServerChannelService(deps);
  const stageResult = await channels.createServerChannelV1(request(owner, {
    serverId: root.id, requestId: randomUUID(), kind: "stage", name: "Studio", categoryId: null,
    accessMode: "members", experience: "broadcast", mediaMode: "audio",
  }));
  const anchors = await db.collection("rooms").where("serverId", "==", root.id).get();
  for (const anchor of anchors.docs) await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: owner });
  const stage = await root.collection("channels").doc(stageResult.channelId).get();
  const voice = (await root.collection("channels").where("kind", "==", "voice").get()).docs[0];
  const calls = { minted: [], removed: [], ended: [] };
  const livekit = {
    assertSupported() {},
    async mintToken(value) {
      calls.minted.push(value);
      const token = `test-only-${randomUUID()}`;
      return { serverUrl: "wss://test-fixture.livekit.cloud", token, participantToken: token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid, participantName: value.participantName,
        expiresAtMillis: nowMs + 300_000, permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources, sessionRole: value.sessionRole,
        serverId: value.binding.serverId, channelId: value.binding.channelId, roomId: value.binding.roomId, sessionId: value.binding.sessionId };
    },
    async revokeParticipant(roomName, userId) {
      calls.removed.push({ roomName, userId });
      return { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 };
    },
    async endRoom(roomName) { calls.ended.push(roomName); return {}; },
  };
  const dependencies = { ...deps, livekit };
  const service = { ...createServerMembershipService(dependencies), ...createServerSessionService(dependencies),
    ...createServerConvergenceRuntimeService(dependencies), ...createServerSessionParticipationService(dependencies) };
  async function member(role = "member") {
    const uid = `part-member:${randomUUID()}`;
    await db.doc(`users/${uid}`).set({ displayName: `Participant ${uid.slice(-4)}`, status: "active" });
    await service.joinServerV1(request(uid, { serverId: root.id, requestId: randomUUID() }));
    if (role !== "member") await service.setServerMemberRoleV1(request(owner, { serverId: root.id, requestId: randomUUID(), memberId: uid, role }));
    return uid;
  }
  const target = (channel) => ({ serverId: root.id, channelId: channel.id });
  const start = (channel = stage, uid = owner) => service.startServerChannelSessionV1(request(uid, { ...target(channel), requestId: randomUUID() }));
  const token = (channel, sessionId, uid, requestId = randomUUID()) =>
    service.createServerChannelTokenV1(request(uid, { ...target(channel), sessionId, requestId }));
  async function call(method, uid, data, token = {}) {
    const payload = { serverId: root.id, requestId: randomUUID(), ...data };
    const result = await service[method](request(uid, payload, token));
    const { requestId, ...input } = payload;
    return { result, payload, job: db.doc(`serverControlOutbox/${operationIdentity(KINDS[method], uid, requestId, input).id}`) };
  }
  const process = (reference) => service.processServerConvergencePage({ operationId: reference.id, pageSize: 20 });
  async function drain(reference) {
    for (let page = 0; page < 50; page += 1) {
      const result = await process(reference);
      if (!result.cleanupPending || result.recoveryRequired) return result;
    }
    assert.fail("The participation job did not settle.");
  }
  const jobs = () => db.collection("serverControlOutbox").where("serverId", "==", root.id).where("kind", "==", PARTICIPATION_KIND).get();
  const participant = (channel, uid) => db.doc(`rooms/${channel.data().roomId}/participants/${uid}`).get().then((snap) => snap.data());
  return { owner, root, stage, voice, service, calls, member, start, token, call, process, drain, jobs, participant,
    advance: (ms) => { nowMs += ms; }, clock,
    recipient: (channel, sessionId, uid) => channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).doc(tokenRecipientId(uid)),
    mirror: (channel, uid) => db.doc(`activeVoiceSessions/${uid}/rooms/${channel.data().roomId}`) };
}

emulatorTest("input, standing and binding are refused before any write: unknown keys, the host role, self-mute, strangers, guests, plain members, staff claims, a held root and another channel's generation", async () => {
  const f = await fixture();
  const listener = await f.member();
  const plain = await f.member();
  const guest = await f.member("guest");
  const { sessionId } = await f.start();
  await f.token(f.stage, sessionId, listener);
  await f.token(f.stage, sessionId, f.owner);
  const stageBinding = { channelId: f.stage.id, sessionId };
  const before = await f.participant(f.stage, listener);
  const roleOf = (uid, data, token) => f.call("setServerSessionParticipantRoleV1", uid, { ...stageBinding, participantId: listener, role: "guest", ...data }, token);
  const muteOf = (uid, data, token) => f.call("setServerSessionMuteV1", uid, { ...stageBinding, participantId: listener, muted: true, ...data }, token);
  // Exact input: every unknown key, wrong type or unassignable role is refused
  // as invalid-argument, and the hand callable has no participantId at all.
  await reject(roleOf(f.owner, { extra: true }), "invalid-argument");
  await reject(roleOf(f.owner, { role: "host" }), "invalid-argument");
  await reject(roleOf(f.owner, { role: "moderator" }), "invalid-argument");
  await reject(muteOf(f.owner, { muted: "true" }), "invalid-argument");
  await reject(f.call("setServerSessionHandV1", listener, { ...stageBinding, raised: true, participantId: plain }), "invalid-argument");
  await reject(f.call("setServerSessionHandV1", listener, { ...stageBinding, raised: "yes" }), "invalid-argument");
  await reject(f.call("setServerSessionMuteV1", f.owner, { ...stageBinding, participantId: f.owner, muted: true }), "invalid-argument");
  // Standing: a plain member, a guest-role member, a stranger, and a caller
  // carrying platform staff claims with no standing on this channel.
  const stranger = `part-stranger:${randomUUID()}`;
  await db.doc(`users/${stranger}`).set({ displayName: "Stranger", status: "active" });
  await db.doc(`staffRoles/${stranger}`).set({ role: "admin", grantedAt: Timestamp.fromMillis(f.clock()) });
  await db.doc(`staffRoles/${plain}`).set({ role: "admin", grantedAt: Timestamp.fromMillis(f.clock()) });
  for (const [uid, token] of [[plain, {}], [guest, {}], [stranger, {}], [stranger, { admin: true, staff: true }], [plain, { admin: true, staff: true }]]) {
    await reject(roleOf(uid, {}, token), "permission-denied");
    await reject(muteOf(uid, {}, token), "permission-denied");
  }
  // Binding: a call naming the stage's generation under the voice channel, or
  // the voice channel's generation under the stage, fails closed; a channel
  // token never grants another channel and neither does a moderation call.
  const voiceSession = await f.start(f.voice);
  await reject(roleOf(f.owner, { channelId: f.voice.id }), "permission-denied");
  await reject(roleOf(f.owner, { sessionId: voiceSession.sessionId }), "permission-denied");
  await reject(muteOf(f.owner, { channelId: f.voice.id }), "permission-denied");
  await reject(f.call("setServerSessionHandV1", listener, { channelId: f.voice.id, sessionId, raised: true }), "permission-denied");
  // A target who never received a token has no participant document.
  await reject(f.call("setServerSessionParticipantRoleV1", f.owner, { ...stageBinding, participantId: plain, role: "guest" }), "failed-precondition");
  await reject(f.call("setServerSessionMuteV1", f.owner, { ...stageBinding, participantId: plain, muted: true }), "failed-precondition");
  await reject(f.call("setServerSessionHandV1", plain, { ...stageBinding, raised: true }), "failed-precondition");
  // The host keeps the host role, and the host does not queue.
  await reject(f.call("setServerSessionParticipantRoleV1", f.owner, { ...stageBinding, participantId: f.owner, role: "listener" }), "failed-precondition");
  await reject(f.call("setServerSessionHandV1", f.owner, { ...stageBinding, raised: true }), "failed-precondition");
  // A held root closes every participation write, owner included.
  await f.root.update({ status: "preparing", serverActivationState: "held" });
  await reject(roleOf(f.owner), "permission-denied");
  await reject(muteOf(f.owner), "permission-denied");
  await reject(f.call("setServerSessionHandV1", listener, { ...stageBinding, raised: true }), "permission-denied");
  await f.root.update({ status: "active", serverActivationState: "active" });
  // Nothing above wrote anything.
  assert.deepEqual(await f.participant(f.stage, listener), before);
  assert.equal((await f.jobs()).size, 0);
  assert.equal(f.calls.removed.length, 0);
});

emulatorTest("a hand is the participant's own write: no revision moves, no token is revoked, the receipt replays, and a promotion lowers it", async () => {
  const f = await fixture();
  const listener = await f.member();
  const { sessionId } = await f.start();
  const binding = { channelId: f.stage.id, sessionId };
  const requestId = randomUUID();
  const issued = await f.token(f.stage, sessionId, listener, requestId);
  const raise = await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  assert.equal(raise.result.raised, true);
  assert.equal(raise.result.changed, true);
  assert.equal(raise.result.role, "listener");
  let doc = await f.participant(f.stage, listener);
  assert.equal(doc.isHandRaised, true);
  assert.ok(doc.handRaisedAt instanceof Timestamp);
  assert.equal(doc.authorizationRevision, 1);
  assert.equal((await f.jobs()).size, 0);
  // The token authority fingerprint does not include the hand, so the
  // original receipt still replays and no revocation is staged.
  assert.deepEqual(await f.token(f.stage, sessionId, listener, requestId), issued);
  assert.equal(f.calls.removed.length, 0);
  // Same request replays; a repeated raise is a no-op receipt.
  assert.deepEqual(await f.service.setServerSessionHandV1(request(listener, raise.payload)), raise.result);
  assert.equal((await f.call("setServerSessionHandV1", listener, { ...binding, raised: true })).result.changed, false);
  const lower = await f.call("setServerSessionHandV1", listener, { ...binding, raised: false });
  assert.equal(lower.result.changed, true);
  doc = await f.participant(f.stage, listener);
  assert.equal(doc.isHandRaised, false);
  assert.equal(doc.handRaisedAt, null);
  // A promotion answers the raised hand.
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "guest" });
  doc = await f.participant(f.stage, listener);
  assert.equal(doc.role, "guest");
  assert.equal(doc.isHandRaised, false);
  assert.equal(doc.handRaisedAt, null);
  // A guest may still ask; a demotion leaves the hand as it is.
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "listener" });
  assert.equal((await f.participant(f.stage, listener)).isHandRaised, true);
});

emulatorTest("promotion grants permission only: the old receipt stops replaying, the worker revokes the bearer, the re-minted token may publish and nothing unmutes the microphone", async () => {
  const f = await fixture();
  const listener = await f.member();
  const { sessionId } = await f.start();
  const binding = { channelId: f.stage.id, sessionId };
  const oldRequest = randomUUID();
  const old = await f.token(f.stage, sessionId, listener, oldRequest);
  assert.equal(old.sessionRole, "listener");
  assert.equal(old.permissions.canPublish, false);
  const promotion = await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "guest" });
  assert.deepEqual(promotion.result, { serverId: f.root.id, channelId: f.stage.id, sessionId, participantId: listener,
    role: "guest", hostMuted: false, serverMuted: false, participantRevision: 2, changed: true, cleanupPending: true });
  const doc = await f.participant(f.stage, listener);
  assert.equal(doc.role, "guest");
  assert.equal(doc.authorizationRevision, 2);
  assert.equal(doc.lastModeratedById, f.owner);
  const job = (await promotion.job.get()).data();
  assert.equal(job.kind, PARTICIPATION_KIND);
  assert.equal(job.userId, listener);
  assert.equal(job.participantRevision, 2);
  assert.equal(job.grantStatus, "completed");
  assert.equal(job.rtcStatus, "pending");
  assert.deepEqual(job.rtcTargets, [{ serverId: f.root.id, channelId: f.stage.id, roomId: f.stage.data().roomId, sessionId,
    livekitRoomName: canonicalLiveKitRoomName(f.root.id, f.stage.id, sessionId), mode: "recipient", userId: listener }]);
  // The same request replays its receipt and stages no second job.
  assert.deepEqual(await f.service.setServerSessionParticipantRoleV1(request(f.owner, promotion.payload)), promotion.result);
  assert.equal((await f.jobs()).size, 1);
  // The bearer's authority changed: the old receipt is refused at once and a
  // fresh token waits for the revocation the worker owns.
  await reject(f.token(f.stage, sessionId, listener, oldRequest), "permission-denied");
  await reject(f.token(f.stage, sessionId, listener), "failed-precondition");
  assert.equal(f.calls.removed.length, 0);
  assert.equal((await f.drain(promotion.job)).cleanupPending, false);
  assert.deepEqual(f.calls.removed, [{ roomName: old.roomName, userId: listener }]);
  const recipient = (await f.recipient(f.stage, sessionId, listener).get()).data();
  assert.equal(recipient.revocationState, "revoked");
  assert.ok(recipient.revokedBeforeMillis > 0);
  assert.equal((await f.mirror(f.stage, listener).get()).exists, false);
  // The worker preserved the promotion and kept the person's capture consent
  // where it was: promotion never turns a microphone on.
  const afterWorker = await f.participant(f.stage, listener);
  assert.equal(afterWorker.role, "guest");
  assert.equal(afterWorker.isMuted, true);
  await reject(f.token(f.stage, sessionId, listener), "failed-precondition");
  f.advance(2_001);
  const fresh = await f.token(f.stage, sessionId, listener);
  assert.equal(fresh.sessionRole, "guest");
  assert.equal(fresh.permissions.canPublish, true);
  assert.deepEqual(fresh.permittedTrackSources, ["microphone"]);
  assert.equal(fresh.roomName, old.roomName);
  assert.equal((await f.participant(f.stage, listener)).isMuted, true);
  // The same role again is a receipt without a write or a job.
  const again = await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "guest" });
  assert.equal(again.result.changed, false);
  assert.equal(again.result.participantRevision, 2);
  assert.equal((await again.job.get()).exists, false);
  // A moderator not in the session may promote themselves onto the stage;
  // a plain member may not.
  const moderator = await f.member("moderator");
  const plain = await f.member();
  await f.token(f.stage, sessionId, moderator);
  await f.token(f.stage, sessionId, plain);
  await reject(f.call("setServerSessionParticipantRoleV1", plain, { ...binding, participantId: plain, role: "guest" }), "permission-denied");
  const self = await f.call("setServerSessionParticipantRoleV1", moderator, { ...binding, participantId: moderator, role: "guest" });
  assert.equal(self.result.role, "guest");
  assert.equal(self.result.changed, true);
});

emulatorTest("demotion revokes the bearer through the convergence worker: the kept token stops replaying, the provider cutoff is positive, and the re-minted token cannot publish", async () => {
  const f = await fixture();
  const listener = await f.member();
  const { sessionId } = await f.start();
  const binding = { channelId: f.stage.id, sessionId };
  await f.token(f.stage, sessionId, listener);
  const promotion = await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "guest" });
  await f.drain(promotion.job);
  f.advance(2_001);
  const keptRequest = randomUUID();
  const kept = await f.token(f.stage, sessionId, listener, keptRequest);
  assert.equal(kept.permissions.canPublish, true);
  f.calls.removed.length = 0;
  const demotion = await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "listener" });
  assert.equal(demotion.result.role, "listener");
  assert.equal(demotion.result.participantRevision, 3);
  assert.equal(demotion.result.cleanupPending, true);
  // The kept token is a bearer. Its receipt no longer replays, no new token
  // is issued while the revocation is pending, and nothing else was touched.
  await reject(f.token(f.stage, sessionId, listener, keptRequest), "permission-denied");
  await reject(f.token(f.stage, sessionId, listener), "failed-precondition");
  const recipientBefore = (await f.recipient(f.stage, sessionId, listener).get()).data();
  assert.equal(recipientBefore.revocationState, "active");
  assert.equal(f.calls.removed.length, 0);
  // The worker: exactly one provider removal for exactly this identity in
  // exactly this generation's room, a positive cutoff on the ledger, the
  // private mirror gone, the demoted role kept.
  assert.equal((await f.drain(demotion.job)).cleanupPending, false);
  assert.deepEqual(f.calls.removed, [{ roomName: kept.roomName, userId: listener }]);
  const recipient = (await f.recipient(f.stage, sessionId, listener).get()).data();
  assert.equal(recipient.revocationState, "revoked");
  assert.ok(recipient.revokedBeforeMillis > 0);
  assert.equal(recipient.tokenEpoch, recipientBefore.tokenEpoch + 1);
  assert.equal((await f.mirror(f.stage, listener).get()).exists, false);
  const doc = await f.participant(f.stage, listener);
  assert.equal(doc.role, "listener");
  assert.equal(doc.authorizationRevision, 3);
  assert.equal(doc.isMuted, true);
  // After the skew barrier the person can rejoin — as a listener only.
  await reject(f.token(f.stage, sessionId, listener), "failed-precondition");
  f.advance(2_001);
  const fresh = await f.token(f.stage, sessionId, listener);
  assert.equal(fresh.sessionRole, "listener");
  assert.equal(fresh.permissions.canPublish, false);
  assert.deepEqual(fresh.permittedTrackSources, []);
  await reject(f.token(f.stage, sessionId, listener, keptRequest), "permission-denied");
  // The whole-generation authority is untouched: the host's token still
  // replays, the session revision did not move, and the channel projection
  // stays live.
  const session = (await f.stage.ref.collection("channelSessions").doc(sessionId).get()).data();
  assert.equal(session.authorizationRevision, 1);
  assert.equal(session.status, "live");
  assert.equal((await f.stage.ref.get()).data().liveness.isLive, true);
  const hostRequest = randomUUID();
  const host = await f.token(f.stage, sessionId, f.owner, hostRequest);
  assert.deepEqual(await f.token(f.stage, sessionId, f.owner, hostRequest), host);
});

emulatorTest("host and moderator mutes each clear only their own flag, both revoke through the worker, and the server hierarchy outranks the session host", async () => {
  const f = await fixture();
  const admin = await f.member("admin");
  const host = await f.member();
  const speaker = await f.member();
  // A plain member starts the community voice session and is its host.
  const { sessionId } = await f.start(f.voice, host);
  const binding = { channelId: f.voice.id, sessionId };
  for (const uid of [f.owner, admin, host, speaker]) await f.token(f.voice, sessionId, uid);
  assert.equal((await f.participant(f.voice, speaker)).role, "guest");
  const mute = (uid, participantId, muted) => f.call("setServerSessionMuteV1", uid, { ...binding, participantId, muted });
  async function converge(step, expected) {
    f.calls.removed.length = 0;
    assert.equal(step.result.changed, true);
    await reject(f.token(f.voice, sessionId, step.payload.participantId), "failed-precondition");
    assert.equal((await f.drain(step.job)).cleanupPending, false);
    assert.deepEqual(f.calls.removed.map((item) => item.userId), [step.payload.participantId]);
    f.advance(2_001);
    const fresh = await f.token(f.voice, sessionId, step.payload.participantId);
    assert.equal(fresh.permissions.canPublish, expected.canPublish);
    assert.equal(fresh.sessionRole, expected.role);
    return fresh;
  }
  // The host mutes: hostMuted only.
  const hostMute = await mute(host, speaker, true);
  assert.equal(hostMute.result.hostMuted, true);
  assert.equal(hostMute.result.serverMuted, false);
  assert.equal(hostMute.result.participantRevision, 2);
  await converge(hostMute, { canPublish: false, role: "guest" });
  // A moderator mutes: serverMuted only, on top.
  const adminMute = await mute(admin, speaker, true);
  assert.equal(adminMute.result.hostMuted, true);
  assert.equal(adminMute.result.serverMuted, true);
  assert.equal(adminMute.result.participantRevision, 3);
  await converge(adminMute, { canPublish: false, role: "guest" });
  // The host lifts only the host's mute: the person stays muted by the server.
  const hostUnmute = await mute(host, speaker, false);
  assert.equal(hostUnmute.result.hostMuted, false);
  assert.equal(hostUnmute.result.serverMuted, true);
  await converge(hostUnmute, { canPublish: false, role: "guest" });
  // A second host unmute is a receipt without a write: nothing left to clear.
  const noop = await mute(host, speaker, false);
  assert.equal(noop.result.changed, false);
  assert.equal(noop.result.serverMuted, true);
  assert.equal((await noop.job.get()).exists, false);
  // The moderator lifts the server mute: publishing returns, consent stays local.
  const adminUnmute = await mute(admin, speaker, false);
  assert.equal(adminUnmute.result.serverMuted, false);
  await converge(adminUnmute, { canPublish: true, role: "guest" });
  assert.equal((await f.participant(f.voice, speaker)).isMuted, true);
  // Hierarchy: the plain-member host governs peers, never the admin or the
  // owner; the admin governs the host but not the owner; the owner governs all.
  await reject(mute(host, admin, true), "permission-denied");
  await reject(mute(host, f.owner, true), "permission-denied");
  await reject(f.call("setServerSessionParticipantRoleV1", host, { ...binding, participantId: admin, role: "listener" }), "permission-denied");
  await reject(mute(admin, f.owner, true), "permission-denied");
  const adminMutesHost = await mute(admin, host, true);
  assert.equal(adminMutesHost.result.role, "host");
  assert.equal(adminMutesHost.result.serverMuted, true);
  await converge(adminMutesHost, { canPublish: false, role: "host" });
  const ownerMutesAdmin = await mute(f.owner, admin, true);
  assert.equal(ownerMutesAdmin.result.serverMuted, true);
  await converge(ownerMutesAdmin, { canPublish: false, role: "guest" });
  // A muted participant can still raise a hand — that is how they ask.
  const ask = await f.call("setServerSessionHandV1", speaker, { ...binding, raised: true });
  assert.equal(ask.result.changed, true);
  assert.equal((await f.participant(f.voice, speaker)).isHandRaised, true);
  // The host's own mute on the voice channel is a demotion of a peer only:
  // the host cannot demote or promote themselves, and the owner's stage host
  // role never changes hands here.
  await reject(f.call("setServerSessionParticipantRoleV1", host, { ...binding, participantId: host, role: "listener" }), "permission-denied");
  assert.equal((await f.jobs()).size, 6);
});

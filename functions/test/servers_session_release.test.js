// `releaseServerChannelSessionIfEmptyV1`: the last-leave signal of the
// empty-generation grace (session_staleness.js, ADR-180 amendment). A client
// that has just left a live generation asks the backend to look; the backend
// reads the provider itself, never trusts a client clock, and ends the
// generation only once its room has been empty for EMPTY_GENERATION_GRACE_MS
// with nobody admitted since. Every test uses a fresh emulator project.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const apps = [];
const { HttpsError } = require("firebase-functions/v2/https");
const { operationIdentity } = require("../integrity/guards");
const { createServerCreationService } = require("../servers/creation");
const { RELEASE_KIND, createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const {
  ADMISSION_WINDOW_MS, EMPTY_GENERATION_GRACE_MS, createServerSessionStalenessService,
} = require("../servers/session_staleness");
const { canonicalLiveKitRoomName, channelLiveness } = require("../servers/contract");
const { SESSION_TOKEN_TTL_SECONDS } = require("../servers/session_contract");

const TOKEN_TTL_MS = SESSION_TOKEN_TTL_SECONDS * 1000;
const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const withCode = (code) => (error) => error instanceof HttpsError && error.code === code;
after(async () => { for (const app of apps) await require("firebase-admin/app").deleteApp(app); });

function freshDb() {
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, Timestamp } = require("firebase-admin/firestore");
  const app = initializeApp({ projectId: `demo-yovoice-release-${randomUUID().slice(0, 8)}` }, `release-${randomUUID()}`);
  apps.push(app);
  return { db: getFirestore(app), Timestamp };
}

const nobody = () => ({ present: false, participantCount: 0, participantIdentities: [] });
const only = (...identities) => ({ present: true, participantCount: identities.length, participantIdentities: identities });

async function fixture() {
  const { db, Timestamp } = freshDb();
  const uid = `release-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Release owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Release fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const voices = (await db.collection(`clubs/${root.serverId}/channels`).where("kind", "==", "voice").get()).docs;
  const channel = voices[0];
  const roomId = channel.data().roomId;
  // Isolated emulator fixture activation, not a shipped activation path.
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  for (const voice of voices) {
    await db.doc(`rooms/${voice.data().roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  }
  const calls = { occupancy: [], revoked: [], ended: [] };
  let occupancyHook = async () => nobody();
  let endHook = null;
  const livekit = {
    assertSupported() { return "wss://test-fixture.livekit.cloud"; },
    async mintToken(value) {
      const token = `test-only-token-${randomUUID()}`;
      return { serverUrl: "wss://test-fixture.livekit.cloud", participantToken: token, token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid,
        participantName: value.participantName, expiresAtMillis: nowMs + TOKEN_TTL_MS,
        permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources,
        serverId: value.binding.serverId, channelId: value.binding.channelId,
        roomId: value.binding.roomId, sessionId: value.binding.sessionId, sessionRole: value.sessionRole };
    },
    async revokeParticipant(roomName, userId) {
      calls.revoked.push({ roomName, userId });
      return { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 };
    },
    async endRoom(roomName, context) {
      calls.ended.push({ roomName, context });
      if (endHook) await endHook(roomName);
      return {};
    },
    async roomOccupancy(binding) { calls.occupancy.push(binding); return occupancyHook(binding); },
  };
  const service = createServerSessionService({ ...dependencies, livekit });
  const control = createServerSessionControlService({ ...dependencies, livekit });
  const staleness = createServerSessionStalenessService({ ...dependencies, livekit });
  const target = { serverId: root.serverId, channelId: channel.id };
  const f = {
    db, Timestamp, uid, serverId: root.serverId, channelId: channel.id, otherChannelId: voices[1].id, roomId,
    calls, control, staleness, clock,
    channelRef: channel.ref, roomRef: db.doc(`rooms/${roomId}`),
    sessionRef: (sessionId) => channel.ref.collection("channelSessions").doc(sessionId),
    rtcName: (sessionId) => canonicalLiveKitRoomName(root.serverId, channel.id, sessionId),
    advance: (ms) => { nowMs += ms; },
    onOccupancy: (hook) => { occupancyHook = hook; },
    onEnd: (hook) => { endHook = hook; },
    start: () => service.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() })),
    token: (sessionId, actor = uid) =>
      service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    end: (sessionId, actor = uid) =>
      service.endServerChannelSessionV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    release: (sessionId, actor = uid, requestId = randomUUID(), data = {}) =>
      service.releaseServerChannelSessionIfEmptyV1(request(actor, { ...target, sessionId, requestId, ...data })),
    member: async () => {
      const userId = `release-member-${randomUUID()}`;
      await db.doc(`users/${userId}`).set({ displayName: "Release member", status: "active" });
      await db.doc(`clubs/${root.serverId}/members/${userId}`).set({ userId, role: "member", authorizationRevision: 1 });
      return userId;
    },
    outbox: async () => (await db.collection("serverControlOutbox").get()).docs.map((document) => document.data()),
    session: async (sessionId) => (await channel.ref.collection("channelSessions").doc(sessionId).get()).data(),
    drain: async (operationId) => {
      for (let attempt = 0; attempt < 4; attempt += 1) {
        const outcome = await control.processServerSessionEndPage({ operationId });
        if (!outcome.cleanupPending) return outcome;
      }
      throw new Error("The end generation did not drain within four passes.");
    },
  };
  return f;
}

emulatorTest("an unauthenticated caller, a non-member, a wrong channel, a member this generation never admitted and a restricted account are refused before the provider is read, and nothing is written", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const joined = await f.member();
  await f.token(sessionId, joined);
  const neverJoined = await f.member();
  const stranger = `release-stranger-${randomUUID()}`;
  await f.db.doc(`users/${stranger}`).set({ displayName: "Stranger", status: "active" });
  const before = { channel: (await f.channelRef.get()).data(), session: await f.session(sessionId) };
  const data = { serverId: f.serverId, channelId: f.channelId, sessionId, requestId: randomUUID() };
  const handler = (value) => createServerSessionService({ db: f.db, Timestamp: f.Timestamp, clock: f.clock,
    livekit: { assertSupported() {}, async mintToken() {}, async revokeParticipant() {}, async endRoom() {},
      async roomOccupancy() { throw new Error("must not be reached"); } } }).releaseServerChannelSessionIfEmptyV1(value);
  await assert.rejects(handler({ data }), withCode("unauthenticated"));
  await assert.rejects(handler({ auth: { uid: "bad/uid" }, data }), withCode("unauthenticated"));
  await assert.rejects(f.release(sessionId, stranger), withCode("permission-denied"));
  await assert.rejects(f.release(sessionId, neverJoined), withCode("permission-denied"));
  await assert.rejects(f.release(sessionId, f.uid, randomUUID(), { channelId: f.otherChannelId }),
    withCode("permission-denied"));
  await assert.rejects(f.release(`ss_${"0".repeat(40)}`), withCode("permission-denied"));
  await assert.rejects(f.release(sessionId, f.uid, randomUUID(), { extra: true }), withCode("invalid-argument"));
  await assert.rejects(handler({ auth: { uid: f.uid, token: { email_verified: false } }, data }),
    withCode("failed-precondition"));
  await f.db.doc(`restrictions/${joined}`).set({ type: "communicationMute", expiresAt: null });
  await assert.rejects(f.release(sessionId, joined), withCode("permission-denied"));
  assert.equal(f.calls.occupancy.length, 0, "no refused caller reached the provider");
  const after = { channel: (await f.channelRef.get()).data(), session: await f.session(sessionId) };
  assert.deepEqual(after.channel, before.channel);
  assert.equal(after.session.status, "live");
  assert.deepEqual(await f.outbox(), []);
});

emulatorTest("a room somebody else is still in answers occupied and keeps LIVE; an answer that cannot prove who is there is occupied too", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const member = await f.member();
  await f.token(sessionId, member);
  f.advance(ADMISSION_WINDOW_MS + 1);
  const before = (await f.channelRef.get()).data();
  for (const answer of [only(f.uid, member), only(member),
    { present: true, participantCount: 1 },
    { present: true, participantCount: 0, participantIdentities: null }, {}]) {
    f.onOccupancy(async () => answer);
    const receipt = await f.release(sessionId);
    assert.deepEqual(receipt, { sessionId, outcome: "occupied", recheckAfterMillis: 0 }, JSON.stringify(answer));
  }
  assert.deepEqual((await f.channelRef.get()).data(), before);
  assert.equal((await f.session(sessionId)).emptyObservation ?? null, null);
  assert.deepEqual(await f.outbox(), []);
});

emulatorTest("the last leaver starts the grace, a replay returns the same receipt, the grace is never extended, and a room still empty after it is ended through the sessionEnd worker", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const beforeChannel = (await f.channelRef.get()).data();
  // The provider may still list the leaver for a moment after a clean
  // disconnect: the caller is excluded, nobody else is there.
  f.onOccupancy(async () => only(f.uid));
  const requestId = randomUUID();
  const first = await f.release(sessionId, f.uid, requestId);
  assert.deepEqual(first, { sessionId, outcome: "pending", recheckAfterMillis: EMPTY_GENERATION_GRACE_MS });
  const observed = (await f.session(sessionId)).emptyObservation;
  assert.deepEqual(observed, { schemaVersion: 1, source: "release", observedAtMillis: f.clock(),
    maxTokenExpiresAtMillis: (await f.session(sessionId)).maxTokenExpiresAtMillis });
  assert.equal((await f.channelRef.get()).data().liveness.isLive, true, "the grace keeps the generation LIVE");
  // Inside the grace a later release keeps the running observation.
  f.onOccupancy(async () => nobody());
  f.advance(EMPTY_GENERATION_GRACE_MS - 1_000);
  assert.deepEqual(await f.release(sessionId), { sessionId, outcome: "pending", recheckAfterMillis: 1_000 });
  assert.deepEqual((await f.session(sessionId)).emptyObservation, observed, "never extended");
  assert.deepEqual(await f.outbox(), []);
  f.advance(1_000);
  const ended = await f.release(sessionId);
  assert.deepEqual(ended, { sessionId, outcome: "ended", recheckAfterMillis: 0 });
  const session = await f.session(sessionId);
  assert.equal(session.status, "ending");
  assert.equal(session.authorizationRevision, 2);
  const jobs = await f.outbox();
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].kind, "sessionEnd");
  assert.equal(jobs[0].operationId, session.endOperationId);
  assert.equal(jobs[0].sessionId, sessionId);
  assert.equal(jobs[0].hostId, f.uid);
  assert.equal(jobs[0].reconcileObsIngress, false);
  const channel = (await f.channelRef.get()).data();
  assert.equal(channel.activeSessionId, null);
  assert.deepEqual(channel.liveness, channelLiveness());
  assert.equal(channel.revision, beforeChannel.revision + 1);
  const room = (await f.roomRef.get()).data();
  assert.equal(room.isLive, false);
  assert.equal(room.voiceSessionId, null);
  assert.equal(room.serverSessionCleanupId, sessionId);
  // The existing worker drains it exactly like any authorized end.
  const drained = await f.drain(jobs[0].operationId);
  assert.equal(drained.cleanupPending, false);
  assert.equal((await f.session(sessionId)).status, "ended");
  assert.deepEqual(f.calls.revoked.map((call) => call.userId), [f.uid]);
  assert.deepEqual(f.calls.ended.map((call) => call.roomName), [f.rtcName(sessionId)]);
  // A release after the end is `changed`, idempotently: no second job.
  assert.deepEqual(await f.release(sessionId), { sessionId, outcome: "changed", recheckAfterMillis: 0 });
  assert.equal((await f.outbox()).length, 1);
  // Replaying the first requestId returns its stored receipt without a
  // provider read, even after the generation ended.
  const readsBefore = f.calls.occupancy.length;
  assert.deepEqual(await f.release(sessionId, f.uid, requestId), first);
  assert.equal(f.calls.occupancy.length, readsBefore);
  const ledger = await f.db.doc(`integrityOperationLedgers/${operationIdentity(RELEASE_KIND, f.uid, requestId,
    { serverId: f.serverId, channelId: f.channelId, sessionId }).id}`).get();
  assert.equal(ledger.data().kind, RELEASE_KIND);
  assert.deepEqual(ledger.data().result, first);
  assert.equal((await f.outbox()).length, 1);
});

emulatorTest("a rejoin inside the grace keeps the session: the observation no longer describes the generation, and a rejoin that leaves again restarts the grace", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const member = await f.member();
  await f.token(sessionId, member);
  f.advance(ADMISSION_WINDOW_MS + 1);
  // The member leaves first; the owner is still there.
  f.onOccupancy(async () => only(f.uid));
  assert.equal((await f.release(sessionId, member)).outcome, "occupied");
  // The owner leaves: the grace starts.
  f.onOccupancy(async () => nobody());
  assert.equal((await f.release(sessionId)).outcome, "pending");
  // The member rejoins 30 s later (a fresh token) and is in the room.
  f.advance(30_000);
  await f.token(sessionId, member);
  f.onOccupancy(async () => only(member));
  f.advance(EMPTY_GENERATION_GRACE_MS);
  // The owner's delayed re-check and the sweep both see the rejoin.
  assert.equal((await f.release(sessionId)).outcome, "occupied");
  assert.equal((await f.session(sessionId)).emptyObservation, null, "somebody is here: the observation is cleared");
  const swept = await f.staleness.stageStaleServerChannelSessions();
  assert.deepEqual(swept.staged, []);
  assert.equal((await f.session(sessionId)).status, "live");
  assert.equal((await f.channelRef.get()).data().liveness.isLive, true);
  // The member leaves again: a fresh grace, measured from this departure.
  f.onOccupancy(async () => only(member));
  const restarted = await f.release(sessionId, member);
  assert.deepEqual(restarted, { sessionId, outcome: "pending", recheckAfterMillis: EMPTY_GENERATION_GRACE_MS });
  f.onOccupancy(async () => nobody());
  f.advance(EMPTY_GENERATION_GRACE_MS - 1);
  assert.equal((await f.release(sessionId, member)).outcome, "pending");
  assert.equal((await f.session(sessionId)).status, "live");
  f.advance(1);
  assert.equal((await f.release(sessionId, member)).outcome, "ended");
  assert.equal((await f.session(sessionId)).status, "ending");
  assert.equal((await f.outbox()).length, 1);
});

emulatorTest("a token issued to somebody else inside the admission window refuses the observation; the caller's own recent token does not", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const member = await f.member();
  f.advance(ADMISSION_WINDOW_MS + 1);
  // The caller's own token, minted just before leaving, is excluded.
  await f.token(sessionId);
  // Somebody else was handed a token 10 s ago and may still be connecting.
  await f.token(sessionId, member);
  f.advance(10_000);
  f.onOccupancy(async () => nobody());
  assert.deepEqual(await f.release(sessionId), { sessionId, outcome: "occupied", recheckAfterMillis: 0 });
  assert.equal((await f.session(sessionId)).emptyObservation ?? null, null);
  f.advance(ADMISSION_WINDOW_MS);
  assert.equal((await f.release(sessionId)).outcome, "pending");
});

emulatorTest("a token minted between the provider reading and the commit refuses the decision as changed", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const member = await f.member();
  f.advance(ADMISSION_WINDOW_MS + 1);
  const before = (await f.channelRef.get()).data();
  f.onOccupancy(async () => {
    await f.token(sessionId, member);
    return nobody();
  });
  assert.deepEqual(await f.release(sessionId), { sessionId, outcome: "changed", recheckAfterMillis: 0 });
  assert.equal((await f.session(sessionId)).emptyObservation ?? null, null);
  assert.deepEqual((await f.channelRef.get()).data(), before);
  assert.deepEqual(await f.outbox(), []);
});

emulatorTest("a provider error is unknown: nothing is written, no receipt is kept, and the same requestId decides once the provider answers", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  f.advance(ADMISSION_WINDOW_MS + 1);
  f.onOccupancy(async () => { throw Object.assign(new Error("controlled outage"), { code: "unavailable" }); });
  const requestId = randomUUID();
  assert.deepEqual(await f.release(sessionId, f.uid, requestId), { sessionId, outcome: "unknown", recheckAfterMillis: 0 });
  const ledgerId = operationIdentity(RELEASE_KIND, f.uid, requestId,
    { serverId: f.serverId, channelId: f.channelId, sessionId }).id;
  assert.equal((await f.db.doc(`integrityOperationLedgers/${ledgerId}`).get()).exists, false);
  assert.equal((await f.session(sessionId)).emptyObservation ?? null, null);
  f.onOccupancy(async () => nobody());
  assert.equal((await f.release(sessionId, f.uid, requestId)).outcome, "pending");
  assert.equal((await f.db.doc(`integrityOperationLedgers/${ledgerId}`).get()).exists, true);
});

emulatorTest("a release naming an older generation never touches the newer live one, and an ending generation never gets a second job", async () => {
  const f = await fixture();
  const old = await f.start();
  await f.token(old.sessionId);
  // An end whose provider delete fails stays `ending` under one job.
  f.onEnd(() => { throw Object.assign(new Error("controlled outage"), { code: "unavailable" }); });
  const receipt = await f.end(old.sessionId);
  assert.equal(receipt.status, "ending");
  f.onOccupancy(async () => nobody());
  assert.deepEqual(await f.release(old.sessionId), { sessionId: old.sessionId, outcome: "changed", recheckAfterMillis: 0 });
  assert.equal((await f.outbox()).length, 1, "no second end job for an ending generation");
  f.onEnd(null);
  await f.drain(receipt.operationId);
  const newer = await f.start();
  assert.notEqual(newer.sessionId, old.sessionId);
  await f.token(newer.sessionId);
  f.advance(EMPTY_GENERATION_GRACE_MS * 2);
  const before = { channel: (await f.channelRef.get()).data(), session: await f.session(newer.sessionId) };
  assert.equal((await f.release(old.sessionId)).outcome, "changed");
  assert.deepEqual((await f.channelRef.get()).data(), before.channel);
  assert.deepEqual(await f.session(newer.sessionId), before.session);
  assert.equal(before.channel.activeSessionId, newer.sessionId);
  assert.equal(before.channel.liveness.isLive, true);
});

emulatorTest("an OBS provisioning lease never defers the release end; the worker waits for it before the provider delete", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  f.advance(ADMISSION_WINDOW_MS + 1);
  f.onOccupancy(async () => nobody());
  assert.equal((await f.release(sessionId)).outcome, "pending");
  f.advance(EMPTY_GENERATION_GRACE_MS);
  const leaseExpiresAtMillis = f.clock() + 180_000;
  await f.sessionRef(sessionId).update({ obsIngressProvisioning: {
    schemaVersion: 2, operationId: "b".repeat(64), leaseId: "lease-release-race",
    startedAtMillis: f.clock(), leaseExpiresAtMillis,
  } });
  assert.equal((await f.release(sessionId)).outcome, "ended");
  const [job] = await f.outbox();
  assert.equal(job.reconcileObsIngress, true);
  const deferred = await f.control.processServerSessionEndPage({ operationId: job.operationId });
  assert.equal(deferred.cleanupPending, true);
  assert.deepEqual(f.calls.ended, []);
  f.advance(leaseExpiresAtMillis - f.clock() + 1);
  const drained = await f.drain(job.operationId);
  assert.equal(drained.cleanupPending, false);
  assert.equal(f.calls.ended.length, 1);
  assert.equal((await f.session(sessionId)).status, "ended");
});

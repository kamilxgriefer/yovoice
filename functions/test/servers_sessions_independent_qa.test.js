const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

// Independent QA: real Firestore transactions, isolated demo-only fixtures,
// deliberately simulated provider transport. This never activates live data
// or proves a real LiveKit connection, webhook, microphone or device flow.
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let app; let db; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-server-runtime-independent" }, `independent-runtime-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const { tokenRecipientId } = require("../servers/session_contract");

const qa = (name, fn) => test(`Independent runtime QA: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.", timeout: 45_000,
}, fn);
const req = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const rejected = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const gate = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};

async function fixture() {
  const uid = `qa-runtime-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Independent QA owner", status: "active" });
  const deps = { db, Timestamp, clock };
  const created = await createServerCreationService(deps).createServerV1(req(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Independent runtime fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const server = db.doc(`clubs/${created.serverId}`);
  const channels = await server.collection("channels").where("kind", "==", "voice").get();
  const channel = channels.docs[0].ref;
  const roomId = channels.docs[0].data().roomId;
  const room = db.doc(`rooms/${roomId}`);
  // Activation is confined to this hard-coded demo project and fresh fixture.
  await server.update({ status: "active", serverActivationState: "active" });
  await room.update({ status: "active", serverActivationState: "active", hostId: uid });
  const calls = { mint: [], revoke: [], end: [] };
  const hooks = { mint: null, revoke: null, end: null };
  const provider = {
    assertSupported: () => "wss://independent-fixture.livekit.cloud",
    async mintToken(input) {
      calls.mint.push(input);
      const token = `independent-test-only-${randomUUID()}`;
      const connection = {
        serverUrl: "wss://independent-fixture.livekit.cloud", token, participantToken: token,
        roomName: input.binding.livekitRoomName, participantIdentity: input.uid,
        participantName: input.participantName, expiresAtMillis: clock() + 300_000,
        permissions: { canPublish: input.grant.canPublish, canSubscribe: input.grant.canSubscribe,
          canPublishData: input.grant.canPublishData },
        permittedTrackSources: input.grant.permittedTrackSources,
        serverId: input.binding.serverId, channelId: input.binding.channelId,
        roomId: input.binding.roomId, sessionId: input.binding.sessionId, sessionRole: input.sessionRole,
      };
      return hooks.mint ? hooks.mint(input, connection) : connection;
    },
    async revokeParticipant(roomName, userId) {
      calls.revoke.push({ roomName, userId });
      const receipt = { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(clock() / 1000) + 1) * 1000 };
      return hooks.revoke ? hooks.revoke({ roomName, userId }, receipt) : receipt;
    },
    async endRoom(roomName) {
      calls.end.push(roomName);
      return hooks.end ? hooks.end(roomName) : {};
    },
  };
  const service = createServerSessionService({ ...deps, livekit: provider });
  const control = createServerSessionControlService({ ...deps, livekit: provider });
  const configuration = createServerChannelService(deps);
  const target = { serverId: server.id, channelId: channel.id };
  const session = (id) => channel.collection("channelSessions").doc(id);
  const memberRef = (actor) => server.collection("members").doc(actor);
  return { uid, server, channel, room, roomId, service, control, configuration,
    calls, hooks, target, session, memberRef, clock, advance: (ms) => { nowMs += ms; },
    recipient: (id, actor = uid) => session(id).collection("tokenRecipients").doc(tokenRecipientId(actor)),
    participant: (actor = uid) => room.collection("participants").doc(actor),
    mirror: (actor = uid) => db.doc(`activeVoiceSessions/${actor}/rooms/${roomId}`),
    reconcile: (sessionId, userId = uid) => control.reconcileServerSessionParticipant({ ...target, roomId, sessionId, userId }),
    start: (requestId = randomUUID(), actor = uid) => service.startServerChannelSessionV1(req(actor, { ...target, requestId })),
    token: (sessionId, requestId = randomUUID(), actor = uid) => service.createServerChannelTokenV1(req(actor, { ...target, sessionId, requestId })),
    end: (sessionId, requestId = randomUUID(), actor = uid) => service.endServerChannelSessionV1(req(actor, { ...target, sessionId, requestId })),
    member: async () => {
      const actor = `qa-member-${randomUUID()}`;
      await db.doc(`users/${actor}`).set({ displayName: "Independent QA member", status: "active" });
      await memberRef(actor).set({ userId: actor, role: "member", authorizationRevision: 1, isOnline: false });
      return actor;
    },
  };
}

async function noAdmission(f, sessionId, actor = f.uid) {
  assert.equal((await f.participant(actor).get()).exists, false);
  assert.equal((await f.mirror(actor).get()).exists, false);
  assert.equal((await f.recipient(sessionId, actor).get()).exists, false);
}

qa("unauthenticated calls never reach provider or create a runtime graph", async () => {
  const f = await fixture();
  const data = { ...f.target, requestId: randomUUID() };
  await rejected(f.service.startServerChannelSessionV1({ data }), "unauthenticated");
  for (const method of ["createServerChannelTokenV1", "endServerChannelSessionV1"]) {
    await rejected(f.service[method]({ data: { ...data, sessionId: "unknown-session" } }), "unauthenticated");
  }
  assert.equal((await f.channel.collection("channelSessions").get()).size, 0);
  assert.deepEqual(f.calls, { mint: [], revoke: [], end: [] });
});

qa("held and unknown root/channel/anchor/session values deny cached start, token and end", async () => {
  const variants = [
    ["server", { status: "preparing", serverActivationState: "held" }],
    ["server", { serverSchemaVersion: 7 }],
    ["server", { serverType: "future-template" }],
    ["channel", { serverSchemaVersion: 7 }],
    ["channel", { kind: "future-media" }],
    ["room", { serverActivationState: "held" }],
    ["room", { serverSchemaVersion: 7 }],
    ["session", { sourcePolicyVersion: 7 }],
  ];
  for (const [document, patch] of variants) {
    const f = await fixture(); const startId = randomUUID(); const tokenId = randomUUID();
    const { sessionId } = await f.start(startId);
    await f.token(sessionId, tokenId);
    await (document === "session" ? f.session(sessionId) : f[document]).update(patch);
    await rejected(f.start(startId), "permission-denied");
    await rejected(f.token(sessionId, tokenId), "permission-denied");
    await rejected(f.end(sessionId), "permission-denied");
    assert.equal(f.calls.mint.length, 1);
    assert.equal(f.calls.revoke.length, 0);
  }
});

qa("issued/replayed tokens do not mark any member, roster, root or anchor online", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  const connection = await f.token(sessionId, id);
  assert.deepEqual(await f.token(sessionId, id), connection);
  const participant = (await f.participant().get()).data();
  assert.equal(participant.isMuted, true);
  assert.notEqual(participant.isOnline, true);
  assert.equal((await f.memberRef(f.uid).get()).data().isOnline, false);
  assert.equal((await f.server.get()).data().onlineCount, 0);
  assert.equal((await f.room.get()).data().participantCount, 0);
  assert.equal((await f.recipient(sessionId).get()).data().revocationState, "active");
  assert.equal(f.calls.mint.length, 1);
});

qa("provider signing failure leaves no admission or receipt and the same request can retry", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  f.hooks.mint = () => { throw new Error("test-only signing failure"); };
  await rejected(f.token(sessionId, id), "unavailable");
  await noAdmission(f, sessionId);
  assert.equal((await f.session(sessionId).get()).data().maxTokenExpiresAtMillis, 0);
  f.hooks.mint = null;
  const retry = await f.token(sessionId, id);
  assert.deepEqual(await f.token(sessionId, id), retry);
  assert.equal(f.calls.mint.length, 2);
});

qa("malformed provider scope, permission and expiry responses fail before persistence", async () => {
  const corruptions = [
    (value) => ({ ...value, roomName: "foreign-room" }),
    (value) => ({ ...value, sessionId: "foreign-generation" }),
    (value) => ({ ...value, permissions: { ...value.permissions, canPublishData: false } }),
    (value) => ({ ...value, permittedTrackSources: ["camera"] }),
    (value, f) => ({ ...value, expiresAtMillis: f.clock() }),
    (value, f) => ({ ...value, expiresAtMillis: f.clock() + 300_001 }),
  ];
  for (const corrupt of corruptions) {
    const f = await fixture(); const { sessionId } = await f.start();
    f.hooks.mint = (_, value) => corrupt(value, f);
    await rejected(f.token(sessionId), "unavailable");
    await noAdmission(f, sessionId);
  }
});

qa("account suspension, member deletion and held root during signing prevent disclosure", async () => {
  for (const mutate of [
    (f) => db.doc(`users/${f.uid}`).update({ disabled: true }),
    (f) => db.doc(`users/${f.uid}`).update({ banned: true }),
    (f) => db.doc(`users/${f.uid}`).update({ status: "deleted" }),
    (f) => db.doc(`restrictions/${f.uid}`).set({ type: "communicationMute", expiresAt: null }),
    (f) => f.memberRef(f.uid).delete(),
    (f) => f.server.update({ status: "preparing", serverActivationState: "held" }),
  ]) {
    const f = await fixture(); const { sessionId } = await f.start();
    f.hooks.mint = async (_, value) => { await mutate(f); return value; };
    await rejected(f.token(sessionId), "permission-denied");
    await noAdmission(f, sessionId);
  }
});

qa("end and a new start overtake a delayed signature without admitting the old generation", async () => {
  const f = await fixture(); const old = await f.start(); const entered = gate(); const release = gate();
  f.hooks.mint = async (_, value) => { entered.resolve(); await release.promise; return value; };
  const pending = f.token(old.sessionId);
  const deniedPending = rejected(pending, "permission-denied");
  await entered.promise;
  try {
    assert.equal((await f.end(old.sessionId)).cleanupPending, false);
    const next = await f.start();
    f.hooks.mint = null;
    await f.token(next.sessionId);
    release.resolve(); await deniedPending;
    assert.equal((await f.recipient(old.sessionId).get()).exists, false);
    assert.equal((await f.participant().get()).data().sessionId, next.sessionId);
    assert.equal((await f.mirror().get()).data().sessionId, next.sessionId);
  } finally { release.resolve(); }
});

qa("real rename/reorder callables during signing retain conversation authority and replay", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  f.hooks.mint = async (_, value) => {
    const channel = (await f.channel.get()).data();
    await f.configuration.updateServerChannelV1(req(f.uid, { ...f.target, requestId: randomUUID(),
      expectedRevision: channel.revision, patch: { name: "Renamed during token signing" } }));
    const [server, channels] = await Promise.all([f.server.get(), f.server.collection("channels").get()]);
    await f.configuration.reorderServerChannelsV1(req(f.uid, { serverId: f.server.id,
      requestId: randomUUID(), expectedRevision: server.data().revision,
      channelIds: channels.docs.map((doc) => doc.id).reverse() }));
    return value;
  };
  const token = await f.token(sessionId, id);
  assert.deepEqual(await f.token(sessionId, id), token);
  assert.equal((await f.reconcile(sessionId)).revoked, false);
  assert.equal((await f.channel.get()).data().activeSessionId, sessionId);
  assert.equal((await f.room.get()).data().voiceSessionId, sessionId);
  assert.equal((await f.channel.get()).data().name, "Renamed during token signing");
  assert.equal(f.calls.revoke.length, 0);
});

qa("removal and restored membership cannot replay a revoked bearer or bypass reconnect skew", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const member = await f.member();
  const memberBefore = (await f.memberRef(member).get()).data(); const tokenId = randomUUID();
  await f.token(sessionId, tokenId, member);
  await f.memberRef(member).delete();
  await rejected(f.token(sessionId, tokenId, member), "permission-denied");
  assert.equal((await f.reconcile(sessionId, member)).revoked, true);
  // An ABA restoration intentionally uses the exact old fields, so the
  // monotonic recipient epoch, not changed profile text, must defeat replay.
  await f.memberRef(member).set(memberBefore);
  await rejected(f.token(sessionId, tokenId, member), "permission-denied");
  await rejected(f.token(sessionId, randomUUID(), member), "failed-precondition");
  f.advance(2_001);
  const next = await f.token(sessionId, randomUUID(), member);
  assert.equal(next.participantIdentity, member);
  assert.equal((await f.recipient(sessionId, member).get()).data().tokenEpoch, 2);
  await rejected(f.token(sessionId, tokenId, member), "permission-denied");
});

qa("uncertain revocation never retries or reopens the generation; authorized end provides recovery", async () => {
  const outcomes = [
    { response: () => null, code: "unavailable" },
    { response: () => ({}), code: "unavailable" },
    { response: (f) => ({ alreadyAbsent: true, revokedBeforeMillis: f.clock() }), code: "unavailable" },
    { response: () => ({ alreadyAbsent: false, revokedBeforeMillis: -1 }), code: "unavailable" },
    { response: () => { throw Object.assign(new Error("test-only transport timeout"), { code: "deadline_exceeded" }); }, code: "deadline_exceeded" },
  ];
  for (const outcome of outcomes) {
    // A failed/ambiguous RPC must not be retried on this RTC identity. Each
    // failure gets a fresh fixture rather than fabricating a successful retry.
    const f = await fixture(); const { sessionId } = await f.start(); const tokenId = randomUUID();
    const oldToken = await f.token(sessionId, tokenId);
    await f.participant().update({ serverMuted: true, authorizationRevision: 2 });
    f.hooks.revoke = () => outcome.response(f);
    await rejected(f.reconcile(sessionId), outcome.code);
    const unresolved = (await f.recipient(sessionId).get()).data();
    assert.equal(unresolved.revocationState, "revoking");
    assert.equal(unresolved.revocationAttempt.state, "uncertain");
    assert.equal(unresolved.tokenEpoch, 2);
    assert.equal((await f.mirror().get()).exists, true);
    assert.deepEqual(await f.reconcile(sessionId), { revocationPending: true, revoked: false, recoveryRequired: true });
    assert.equal(f.calls.revoke.length, 1);
    await rejected(f.token(sessionId), "failed-precondition");
    await rejected(f.token(sessionId, tokenId), "permission-denied");
    f.advance(1_000_000); // Both lease and original JWT have long expired.
    f.hooks.revoke = null;
    assert.deepEqual(await f.reconcile(sessionId), { revocationPending: true, revoked: false, recoveryRequired: true });
    assert.equal(f.calls.revoke.length, 1);
    assert.deepEqual((await f.recipient(sessionId).get()).data().revocationAttempt, unresolved.revocationAttempt);
    await rejected(f.token(sessionId), "failed-precondition");
    await rejected(f.token(sessionId, tokenId), "permission-denied");
    assert.equal(f.calls.mint.length, 1);
    assert.equal((await f.end(sessionId)).cleanupPending, false);
    const next = await f.start(); const nextToken = await f.token(next.sessionId);
    assert.notEqual(next.sessionId, sessionId);
    assert.notEqual(nextToken.roomName, oldToken.roomName);
    assert.equal((await f.session(sessionId).get()).data().status, "ended");
    const nextRecipient = (await f.recipient(next.sessionId).get()).data();
    const callsBeforeStaleConvergence = f.calls.revoke.length;
    assert.deepEqual(await f.reconcile(sessionId), { revocationPending: false, revoked: false });
    assert.equal(f.calls.revoke.length, callsBeforeStaleConvergence);
    assert.deepEqual((await f.recipient(next.sessionId).get()).data(), nextRecipient);
    await rejected(f.token(sessionId, tokenId), "permission-denied");
  }
});

qa("duplicate ends share one durable operation while the worker lease is busy", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  const entered = gate(); const release = gate(); const id = randomUUID();
  f.hooks.revoke = async (_, receipt) => { entered.resolve(); await release.promise; return receipt; };
  const first = f.end(sessionId, id); await entered.promise;
  try {
    const second = await f.end(sessionId, id);
    const third = await f.end(sessionId);
    assert.equal(second.operationId, third.operationId);
    assert.equal(second.cleanupPending, true);
    assert.equal(f.calls.revoke.length, 1);
    await rejected(f.start(), "failed-precondition");
    release.resolve(); const completed = await first;
    assert.equal(completed.operationId, second.operationId);
    assert.equal(completed.cleanupPending, false);
    assert.equal((await f.end(sessionId, id)).cleanupPending, false);
    assert.equal(f.calls.end.length, 1);
  } finally { release.resolve(); }
});

qa("partial recipient failure does not advance the page or clear any cleanup barrier", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  const actors = [f.uid, await f.member(), await f.member()];
  for (const actor of actors) await f.token(sessionId, randomUUID(), actor);
  f.hooks.revoke = ({ userId }, receipt) => {
    if (userId === actors[1]) throw new Error("test-only partial provider failure");
    return receipt;
  };
  const requestId = randomUUID(); const pending = await f.end(sessionId, requestId);
  assert.equal(pending.cleanupPending, true);
  const job = (await db.doc(`serverControlOutbox/${pending.operationId}`).get()).data();
  assert.equal(job.cursor, null); assert.equal(job.status, "pending"); assert.equal(job.leaseId, null);
  assert.equal(f.calls.end.length, 0);
  for (const actor of actors) {
    assert.equal((await f.recipient(sessionId, actor).get()).data().revocationState, "revoking");
    assert.equal((await f.mirror(actor).get()).exists, true);
  }
  f.hooks.revoke = null;
  assert.equal((await f.end(sessionId, requestId)).cleanupPending, false);
  for (const actor of actors) assert.equal((await f.mirror(actor).get()).exists, false);
  assert.equal((await f.session(sessionId).get()).data().status, "ended");
});

qa("stale leased worker completion cannot remove a genuinely started newer generation", async () => {
  const f = await fixture(); const old = await f.start(); await f.token(old.sessionId);
  f.hooks.end = () => { throw new Error("test-only first deletion outage"); };
  const pending = await f.end(old.sessionId);
  const entered = gate(); const release = gate();
  f.hooks.end = async () => { entered.resolve(); await release.promise; return {}; };
  const stale = f.control.processServerSessionEndPage({ operationId: pending.operationId });
  await entered.promise;
  try {
    f.advance(120_001);
    f.hooks.end = null;
    const replacementWorker = await f.control.processServerSessionEndPage({ operationId: pending.operationId });
    assert.equal(replacementWorker.cleanupPending, false);
    const next = await f.start(); await f.token(next.sessionId);
    const roomBefore = (await f.room.get()).data();
    const participantBefore = (await f.participant().get()).data();
    const mirrorBefore = (await f.mirror().get()).data();
    release.resolve(); await stale;
    assert.deepEqual((await f.room.get()).data(), roomBefore);
    assert.deepEqual((await f.participant().get()).data(), participantBefore);
    assert.deepEqual((await f.mirror().get()).data(), mirrorBefore);
    assert.equal((await f.channel.get()).data().activeSessionId, next.sessionId);
    assert.ok(f.calls.end.every((roomName) => roomName !== roomBefore.livekitRoomName));
    assert.equal((await db.doc(`serverControlOutbox/${pending.operationId}`).get()).data().status, "completed");
  } finally { release.resolve(); }
});

qa("stale participant reconciliation does not mutate a newer generation after canonical teardown", async () => {
  const f = await fixture(); const old = await f.start(); await f.token(old.sessionId);
  await f.participant().update({ hostMuted: true, authorizationRevision: 2 });
  const entered = gate(); const release = gate();
  f.hooks.revoke = async (_, receipt) => { entered.resolve(); await release.promise; return receipt; };
  const stale = f.reconcile(old.sessionId); await entered.promise;
  try {
    f.advance(120_001);
    assert.deepEqual(await f.reconcile(old.sessionId), { revocationPending: true, revoked: false, recoveryRequired: true });
    assert.equal(f.calls.revoke.length, 1);
    await rejected(f.token(old.sessionId), "failed-precondition");
    f.hooks.revoke = null;
    assert.equal((await f.end(old.sessionId)).cleanupPending, false);
    const next = await f.start(); await f.token(next.sessionId);
    const nextRoom = (await f.room.get()).data();
    const nextRecipient = (await f.recipient(next.sessionId).get()).data();
    const nextParticipant = (await f.participant().get()).data();
    const nextMirror = (await f.mirror().get()).data();
    release.resolve(); assert.equal((await stale).revoked, false);
    assert.deepEqual((await f.room.get()).data(), nextRoom);
    assert.deepEqual((await f.recipient(next.sessionId).get()).data(), nextRecipient);
    assert.deepEqual((await f.participant().get()).data(), nextParticipant);
    assert.deepEqual((await f.mirror().get()).data(), nextMirror);
    assert.equal((await f.channel.get()).data().activeSessionId, next.sessionId);
  } finally { release.resolve(); await Promise.allSettled([stale]); }
});

qa("concurrent participant revocations stay single-flight after expiry and require exact reconnect time", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const tokenId = randomUUID();
  await f.token(sessionId, tokenId);
  await f.participant().update({ hostMuted: true, authorizationRevision: 2 });
  const firstEntered = gate(); const firstRelease = gate();
  const secondEntered = gate(); const secondRelease = gate();
  let removalsInFlight = 0;
  f.hooks.revoke = async (_, receipt) => {
    const firstCall = f.calls.revoke.length === 1;
    removalsInFlight += 1;
    (firstCall ? firstEntered : secondEntered).resolve();
    await (firstCall ? firstRelease : secondRelease).promise;
    removalsInFlight -= 1;
    return receipt;
  };
  const first = f.reconcile(sessionId); await firstEntered.promise;
  const second = f.reconcile(sessionId);
  // Race against a forbidden second dispatch so a regression fails promptly
  // instead of waiting for this test's timeout. The strict contract permits
  // only one provider call; duplicate workers report the existing operation.
  await Promise.race([secondEntered.promise, second]);
  try {
    assert.equal(f.calls.revoke.length, 1);
    assert.deepEqual(await second, { revocationPending: true, revoked: false, recoveryRequired: false });
    const attempt = (await f.recipient(sessionId).get()).data().revocationAttempt;
    f.advance(120_001);
    assert.deepEqual(await f.reconcile(sessionId), { revocationPending: true, revoked: false, recoveryRequired: true });
    assert.equal(f.calls.revoke.length, 1);
    assert.equal(removalsInFlight, 1);
    assert.deepEqual((await f.recipient(sessionId).get()).data().revocationAttempt, attempt);
    await rejected(f.token(sessionId), "failed-precondition");
    await rejected(f.token(sessionId, tokenId), "permission-denied");
    firstRelease.resolve(); assert.equal((await first).revoked, true);
    const acknowledged = (await f.recipient(sessionId).get()).data();
    assert.equal(acknowledged.revocationAttempt.id, attempt.id);
    assert.equal(acknowledged.revocationAttempt.state, "acknowledged");
    f.advance(acknowledged.reconnectAfterMillis - f.clock() - 1);
    await rejected(f.token(sessionId), "failed-precondition");
    f.advance(1);
    const token = await f.token(sessionId);
    assert.equal(token.permissions.canPublish, false);
    assert.equal(removalsInFlight, 0);
    assert.equal(f.calls.revoke.length, 1);
  } finally {
    firstRelease.resolve(); secondRelease.resolve();
    await Promise.allSettled([first, second]);
  }
});

// The sweep half of the empty-generation grace and the projection-drift
// repair (session_staleness.js, ADR-180 amendment). The sweep completes a
// grace the release callable or the provider recorded, never cuts a running
// one short, keeps the original ADR-180 rule for generations nobody observed
// emptying, and repairs only provably dead public projections. Each emulator
// test uses a fresh project so the scans see exactly the fixtures seeded.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const apps = [];
const { createServerCreationService } = require("../servers/creation");
const { createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const {
  ADMISSION_WINDOW_MS, EMPTY_GENERATION_GRACE_MS, MAX_UNPROVEN_LIVE_AGE_MS, STALE_GENERATION_GRACE_MS,
  classifyChannelProjection, createServerSessionStalenessService, emptyObservation, occupancyVerdict,
} = require("../servers/session_staleness");
const { canonicalLiveKitRoomName, channelLiveness } = require("../servers/contract");
const { SESSION_TOKEN_TTL_SECONDS } = require("../servers/session_contract");

const TOKEN_TTL_MS = SESSION_TOKEN_TTL_SECONDS * 1000;
const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
after(async () => { for (const app of apps) await require("firebase-admin/app").deleteApp(app); });

function freshDb() {
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, Timestamp } = require("firebase-admin/firestore");
  const app = initializeApp({ projectId: `demo-yovoice-leave-${randomUUID().slice(0, 8)}` }, `leave-${randomUUID()}`);
  apps.push(app);
  return { db: getFirestore(app), Timestamp };
}

const nobody = () => ({ present: false, participantCount: 0, participantIdentities: [] });
const only = (...identities) => ({ present: true, participantCount: identities.length, participantIdentities: identities });

async function fixture() {
  const { db, Timestamp } = freshDb();
  const uid = `leave-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Last-leave owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Last-leave fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const voices = (await db.collection(`clubs/${root.serverId}/channels`).where("kind", "==", "voice").get()).docs;
  // Isolated emulator fixture activation, not a shipped activation path.
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  for (const voice of voices) {
    await db.doc(`rooms/${voice.data().roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  }
  const calls = { occupancy: [], revoked: [], ended: [] };
  let occupancyHook = async () => nobody();
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
    async endRoom(roomName, context) { calls.ended.push({ roomName, context }); return {}; },
    async roomOccupancy(binding) { calls.occupancy.push(binding); return occupancyHook(binding); },
  };
  const service = createServerSessionService({ ...dependencies, livekit });
  const control = createServerSessionControlService({ ...dependencies, livekit });
  const staleness = createServerSessionStalenessService({ ...dependencies, livekit });
  const [channel, other] = voices;
  const target = { serverId: root.serverId, channelId: channel.id };
  return {
    db, Timestamp, uid, serverId: root.serverId, channelId: channel.id, roomId: channel.data().roomId,
    other: { id: other.id, ref: other.ref, roomId: other.data().roomId, roomRef: db.doc(`rooms/${other.data().roomId}`) },
    calls, control, staleness, clock,
    channelRef: channel.ref, roomRef: db.doc(`rooms/${channel.data().roomId}`),
    sessionRef: (sessionId, reference = channel.ref) => reference.collection("channelSessions").doc(sessionId),
    rtcName: (sessionId) => canonicalLiveKitRoomName(root.serverId, channel.id, sessionId),
    advance: (ms) => { nowMs += ms; },
    onOccupancy: (hook) => { occupancyHook = hook; },
    sweep: (options) => staleness.stageStaleServerChannelSessions(options),
    start: () => service.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() })),
    token: (sessionId, actor = uid) =>
      service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    end: (sessionId) => service.endServerChannelSessionV1(request(uid, { ...target, sessionId, requestId: randomUUID() })),
    release: (sessionId, actor = uid) =>
      service.releaseServerChannelSessionIfEmptyV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    session: async (sessionId) => (await channel.ref.collection("channelSessions").doc(sessionId).get()).data(),
    outbox: async () => (await db.collection("serverControlOutbox").get()).docs.map((document) => document.data()),
    drain: async (operationId) => {
      for (let attempt = 0; attempt < 4; attempt += 1) {
        const outcome = await control.processServerSessionEndPage({ operationId });
        if (!outcome.cleanupPending) return outcome;
      }
      throw new Error("The end generation did not drain within four passes.");
    },
  };
}

const drift = (outcome) => ({ driftRepaired: outcome.driftRepaired, driftUnresolved: outcome.driftUnresolved,
  driftTruncated: outcome.driftTruncated });

emulatorTest("the sweep never cuts a running grace short and never asks the provider during it; once the grace has elapsed on an empty room it stages the end through the sessionEnd outbox", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  f.advance(ADMISSION_WINDOW_MS + 1);
  assert.equal((await f.release(sessionId)).outcome, "pending");
  const reads = f.calls.occupancy.length;
  f.advance(EMPTY_GENERATION_GRACE_MS - 1);
  let outcome = await f.sweep();
  assert.equal(outcome.graceRunning, 1);
  assert.deepEqual(outcome.staged, []);
  assert.equal(f.calls.occupancy.length, reads, "a running grace costs no provider read");
  assert.equal((await f.session(sessionId)).status, "live");
  f.advance(1);
  outcome = await f.sweep();
  assert.equal(outcome.stagedEmpty, 1);
  assert.equal(outcome.staged.length, 1);
  const [staged] = outcome.staged;
  assert.deepEqual({ ...staged, endOperationId: undefined }, {
    outcome: "staged", serverId: f.serverId, channelId: f.channelId, roomId: f.roomId, sessionId,
    livekitRoomName: f.rtcName(sessionId), endOperationId: undefined,
  });
  assert.deepEqual(drift(outcome), { driftRepaired: 0, driftUnresolved: 0, driftTruncated: false });
  const session = await f.session(sessionId);
  assert.equal(session.status, "ending");
  assert.equal(session.endOperationId, staged.endOperationId);
  const jobs = await f.outbox();
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].kind, "sessionEnd");
  assert.deepEqual((await f.channelRef.get()).data().liveness, channelLiveness());
  assert.equal((await f.roomRef.get()).data().isLive, false);
  assert.equal((await f.drain(staged.endOperationId)).cleanupPending, false);
  assert.equal((await f.session(sessionId)).status, "ended");
  const again = await f.sweep();
  assert.equal(again.scanned, 0);
  assert.equal((await f.outbox()).length, 1);
});

emulatorTest("an elapsed observation whose room is occupied again is cleared and the generation stays live; a malformed answer changes nothing", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  f.advance(ADMISSION_WINDOW_MS + 1);
  assert.equal((await f.release(sessionId)).outcome, "pending");
  f.advance(EMPTY_GENERATION_GRACE_MS);
  f.onOccupancy(async () => ({}));
  let outcome = await f.sweep();
  assert.equal(outcome.skippedOccupied, 1);
  assert.notEqual(emptyObservation(await f.session(sessionId)), null, "an unknown never writes");
  f.onOccupancy(async () => { throw Object.assign(new Error("controlled outage"), { code: "unavailable" }); });
  outcome = await f.sweep();
  assert.equal(outcome.providerUnavailable, 1);
  f.onOccupancy(async () => only("somebody-reconnected"));
  outcome = await f.sweep();
  assert.equal(outcome.skippedOccupied, 1);
  assert.deepEqual(outcome.staged, []);
  assert.equal((await f.session(sessionId)).emptyObservation, null);
  assert.equal((await f.session(sessionId)).status, "live");
  assert.equal((await f.channelRef.get()).data().liveness.isLive, true);
  assert.deepEqual(await f.outbox(), []);
});

emulatorTest("a running grace also wins over the ADR-180 token rule, which still ends an unobserved generation on its own", async () => {
  const f = await fixture();
  const observed = await f.start();
  await f.token(observed.sessionId);
  // Old enough for the ADR-180 rule on its own.
  f.advance(TOKEN_TTL_MS + STALE_GENERATION_GRACE_MS + 1);
  assert.equal((await f.release(observed.sessionId)).outcome, "pending");
  let outcome = await f.sweep();
  assert.equal(outcome.graceRunning, 1);
  assert.deepEqual(outcome.staged, []);
  assert.equal((await f.session(observed.sessionId)).status, "live");
  f.advance(EMPTY_GENERATION_GRACE_MS);
  outcome = await f.sweep();
  assert.equal(outcome.stagedEmpty, 1);
  assert.equal((await f.session(observed.sessionId)).status, "ending");
  // A generation nobody observed emptying keeps the original bound.
  await f.drain(outcome.staged[0].endOperationId);
  const unobserved = await f.start();
  await f.token(unobserved.sessionId);
  f.advance(TOKEN_TTL_MS + STALE_GENERATION_GRACE_MS - 1);
  outcome = await f.sweep();
  assert.equal(outcome.skippedYoung, 1);
  f.advance(2);
  outcome = await f.sweep();
  assert.equal(outcome.staged.length, 1);
  assert.equal(outcome.stagedEmpty, 0);
  assert.equal((await f.session(unobserved.sessionId)).status, "ending");
});

emulatorTest("drift: a live projection that no generation claims is reset once with the terminal fence, and a projection naming an ended or missing session is reset with its pointer", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const { operationId } = await f.end(sessionId);
  await f.drain(operationId);
  const idle = (await f.channelRef.get()).data();
  assert.equal(idle.activeSessionId, null);
  // Stranded by an interrupted writer: the pointer is gone, the badge is not.
  const startedAt = f.Timestamp.fromMillis(f.clock() - 60 * 60_000);
  await f.channelRef.update({ liveness: { schemaVersion: 1, isLive: true, startedAt } });
  let outcome = await f.sweep();
  assert.deepEqual(drift(outcome), { driftRepaired: 1, driftUnresolved: 0, driftTruncated: false });
  let channel = (await f.channelRef.get()).data();
  assert.deepEqual(channel.liveness, channelLiveness());
  assert.equal(channel.activeSessionId, null);
  assert.equal(channel.revision, idle.revision, "the projection-only fence does not move the revision");
  outcome = await f.sweep();
  assert.deepEqual(drift(outcome), { driftRepaired: 0, driftUnresolved: 0, driftTruncated: false });
  // The pointer names the ended generation while its anchor is idle.
  await f.channelRef.update({ activeSessionId: sessionId, liveness: { schemaVersion: 1, isLive: true, startedAt } });
  const named = (await f.channelRef.get()).data();
  outcome = await f.sweep();
  assert.equal(outcome.driftRepaired, 1);
  channel = (await f.channelRef.get()).data();
  assert.equal(channel.activeSessionId, null);
  assert.deepEqual(channel.liveness, channelLiveness());
  assert.equal(channel.revision, named.revision + 1, "retiring the pointer moves the revision like every end writer");
  // A pointer at a session document that does not exist.
  await f.channelRef.update({ activeSessionId: `ss_${"1".repeat(40)}`, liveness: { schemaVersion: 1, isLive: true, startedAt } });
  outcome = await f.sweep();
  assert.equal(outcome.driftRepaired, 1);
  assert.equal((await f.channelRef.get()).data().activeSessionId, null);
  assert.deepEqual(await f.sweep().then(drift), { driftRepaired: 0, driftUnresolved: 0, driftTruncated: false });
  // After the repair a fresh generation starts and projects normally.
  const next = await f.start();
  assert.equal((await f.channelRef.get()).data().activeSessionId, next.sessionId);
  assert.equal(f.calls.occupancy.length, 0, "drift repair of dead shapes never reads the provider");
});

emulatorTest("drift: a projection naming a live generation is never touched, an unprovable shape is counted and left alone, and only after a day with an empty provider room is its badge reset", async () => {
  const f = await fixture();
  const live = await f.start();
  await f.token(live.sessionId);
  const liveBefore = (await f.channelRef.get()).data();
  // The second voice channel claims a generation whose anchor is idle.
  const ghostId = `ss_${"2".repeat(40)}`;
  const ghostStarted = f.Timestamp.fromMillis(f.clock() - 60 * 60_000);
  await f.sessionRef(ghostId, f.other.ref).set({ serverSchemaVersion: 1, serverId: f.serverId, channelId: f.other.id,
    roomId: f.other.roomId, sessionId: ghostId, status: "live", startedAt: ghostStarted,
    livekitRoomName: canonicalLiveKitRoomName(f.serverId, f.other.id, ghostId), maxTokenExpiresAtMillis: 0 });
  await f.other.ref.update({ activeSessionId: ghostId, liveness: { schemaVersion: 1, isLive: true, startedAt: ghostStarted } });
  const ghostBefore = (await f.other.ref.get()).data();
  let outcome = await f.sweep();
  assert.equal(outcome.skippedYoung, 1, "the live generation belongs to the anchor scan");
  assert.deepEqual(drift(outcome), { driftRepaired: 0, driftUnresolved: 1, driftTruncated: false });
  assert.deepEqual((await f.channelRef.get()).data(), liveBefore);
  assert.deepEqual((await f.other.ref.get()).data(), ghostBefore);
  assert.equal(f.calls.occupancy.length, 0);
  // Older than the ceiling, but the provider still reports somebody. The
  // first channel's live generation is occupied throughout, so the anchor
  // scan leaves it alone as well.
  f.advance(MAX_UNPROVEN_LIVE_AGE_MS);
  f.onOccupancy(async (binding) => (binding.channelId === f.other.id ? only("still-here") : only(f.uid)));
  outcome = await f.sweep();
  assert.equal(outcome.skippedOccupied, 1);
  assert.equal(outcome.driftUnresolved, 1);
  assert.deepEqual((await f.other.ref.get()).data(), ghostBefore);
  assert.deepEqual(f.calls.occupancy.at(-1), { serverId: f.serverId, channelId: f.other.id, roomId: f.other.roomId,
    sessionId: ghostId, livekitRoomName: canonicalLiveKitRoomName(f.serverId, f.other.id, ghostId) });
  // Empty: the badge alone is reset; the pointer and the private graph are
  // left for an operator.
  f.onOccupancy(async (binding) => (binding.channelId === f.other.id ? nobody() : only(f.uid)));
  outcome = await f.sweep();
  assert.equal(outcome.driftRepaired, 1);
  assert.equal(outcome.driftUnresolved, 0);
  const ghost = (await f.other.ref.get()).data();
  assert.deepEqual(ghost.liveness, channelLiveness());
  assert.equal(ghost.activeSessionId, ghostId);
  assert.equal(ghost.revision, ghostBefore.revision);
  assert.equal((await f.sessionRef(ghostId, f.other.ref).get()).data().status, "live");
  // The live generation of the first channel was never drift-repaired.
  const liveAfter = (await f.channelRef.get()).data();
  assert.equal(liveAfter.activeSessionId, live.sessionId);
});

test("classification is pure and writes only the provably dead shapes", () => {
  const serverId = "srv_a";
  const channelId = "ch_a";
  const nowMs = 2_000_000_000_000;
  const liveness = { schemaVersion: 1, isLive: true, startedAt: { toMillis: () => nowMs - 1_000 } };
  const channel = (overrides = {}) => ({ serverSchemaVersion: 1, serverId, roomId: "sr_a", activeSessionId: "ss_a",
    liveness, ...overrides });
  const room = (overrides = {}) => ({ serverSchemaVersion: 1, serverId, clubId: serverId, channelId, isLive: false,
    voiceSessionId: null, livekitRoomName: null, ...overrides });
  const session = (overrides = {}) => ({ serverSchemaVersion: 1, serverId, channelId, sessionId: "ss_a", status: "ended",
    ...overrides });
  const classify = (value) => classifyChannelProjection({ serverId, channelId, nowMs, ...value });
  assert.equal(classify({ channel: null }), "ok-idle");
  assert.equal(classify({ channel: channel({ liveness: channelLiveness() }) }), "ok-idle");
  assert.equal(classify({ channel: channel({ activeSessionId: null }), room: room() }), "reset-null-session");
  assert.equal(classify({ channel: channel({ activeSessionId: null }), room: null }), "reset-null-session");
  for (const status of ["ending", "ended", "failed"]) {
    assert.equal(classify({ channel: channel(), room: room(), session: session({ status }) }), "reset-terminal-session");
  }
  assert.equal(classify({ channel: channel(), room: room(), session: null }), "reset-terminal-session");
  assert.equal(classify({ channel: channel(), room: room({ isLive: true, voiceSessionId: "ss_a" }),
    session: session({ status: "live" }) }), "ok-live");
  // A newer generation on the anchor, a live anchor on an ended session and
  // any foreign or malformed binding are never written.
  assert.equal(classify({ channel: channel(), room: room({ isLive: true, voiceSessionId: "ss_b" }),
    session: session({ status: "ended" }) }), "unresolved");
  assert.equal(classify({ channel: channel(), room: room({ isLive: true, voiceSessionId: "ss_a" }),
    session: session({ status: "ended" }) }), "unresolved");
  assert.equal(classify({ channel: channel(), room: room({ voiceSessionId: "ss_a" }), session: session() }), "unresolved");
  assert.equal(classify({ channel: channel(), room: room({ serverId: "srv_b", clubId: "srv_b" }), session: session() }),
    "unresolved");
  assert.equal(classify({ channel: channel(), room: room(), session: session({ channelId: "ch_b" }) }), "unresolved");
  assert.equal(classify({ channel: channel({ serverSchemaVersion: undefined }), room: room(), session: session() }), "unresolved");
  assert.equal(classify({ channel: channel({ activeSessionId: "bad/id" }), room: room(), session: null }), "unresolved");
  assert.equal(classify({ channel: channel(), room: room(), session: session({ status: "live" }) }), "unresolved");
  assert.equal(classify({ channel: channel({ liveness: { ...liveness,
    startedAt: { toMillis: () => nowMs - MAX_UNPROVEN_LIVE_AGE_MS } } }), room: room(), session: session({ status: "live" }) }),
  "max-age-candidate");
});

test("occupancy verdicts fail closed and exclude only an identity the provider really listed", () => {
  assert.deepEqual({ ...occupancyVerdict(null) }, { known: false, empty: false, othersEmpty: false, callerPresent: false });
  assert.equal(occupancyVerdict({}).known, false);
  assert.equal(occupancyVerdict({ participantCount: -1 }).known, false);
  assert.equal(occupancyVerdict({ participantCount: 0, participantIdentities: null }).known, false);
  assert.equal(occupancyVerdict({ present: false, participantCount: 0 }).empty, true);
  assert.equal(occupancyVerdict({ present: true, participantCount: 1 }, "me").othersEmpty, false);
  assert.equal(occupancyVerdict(only("me"), "me").othersEmpty, true);
  assert.equal(occupancyVerdict(only("me"), "me").callerPresent, true);
  assert.equal(occupancyVerdict(only("me"), "me").empty, false);
  assert.equal(occupancyVerdict(only("me", "you"), "me").othersEmpty, false);
  assert.equal(occupancyVerdict(only("me")).othersEmpty, false, "nobody is excluded without a caller");
  assert.equal(occupancyVerdict({ present: true, participantCount: 2, participantIdentities: ["me"] }, "me").othersEmpty, false);
  assert.equal(occupancyVerdict({ present: true, participantCount: 1, participantIdentities: [7] }, "me").othersEmpty, false);
  assert.equal(emptyObservation({ maxTokenExpiresAtMillis: 5, emptyObservation: { schemaVersion: 1, source: "release",
    observedAtMillis: 1, maxTokenExpiresAtMillis: 4 } }), null, "a token minted since supersedes the observation");
  assert.equal(emptyObservation({ maxTokenExpiresAtMillis: 5, emptyObservation: { schemaVersion: 1, source: "client",
    observedAtMillis: 1, maxTokenExpiresAtMillis: 5 } }), null);
  assert.notEqual(emptyObservation({ maxTokenExpiresAtMillis: 5, emptyObservation: { schemaVersion: 1, source: "sweep",
    observedAtMillis: 1, maxTokenExpiresAtMillis: 5 } }), null);
});

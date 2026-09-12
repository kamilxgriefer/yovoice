// The bound on a V1 generation whose host vanished (ADR-180). A stale
// generation is staged for end through the SAME writer and worker every
// authorized end uses, and only when both facts hold: every token it ever
// issued expired a full grace period ago, and the provider reports its room
// empty or gone. Each test uses a fresh emulator project so the bare
// `rooms.isLive == true` scan sees exactly the fixtures it seeded.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const apps = [];
const { createServerCreationService } = require("../servers/creation");
const { createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const { MAX_LIVE_ANCHOR_SCAN, STALE_GENERATION_GRACE_MS, createServerSessionStalenessService } = require("../servers/session_staleness");
const { canonicalLiveKitRoomName, channelLiveness } = require("../servers/contract");
const { SESSION_TOKEN_TTL_SECONDS } = require("../servers/session_contract");

const TOKEN_TTL_MS = SESSION_TOKEN_TTL_SECONDS * 1000;
const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 45_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
after(async () => { for (const app of apps) await require("firebase-admin/app").deleteApp(app); });

function freshDb() {
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, Timestamp } = require("firebase-admin/firestore");
  const app = initializeApp({ projectId: `demo-yovoice-stale-${randomUUID().slice(0, 8)}` }, `stale-${randomUUID()}`);
  apps.push(app);
  return { db: getFirestore(app), Timestamp };
}

async function fixture() {
  const { db, Timestamp } = freshDb();
  const uid = `stale-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Staleness owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Staleness fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const channel = (await db.collection(`clubs/${root.serverId}/channels`).where("kind", "==", "voice").get()).docs[0];
  const roomId = channel.data().roomId;
  // Isolated emulator fixture activation, not a shipped activation path.
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  await db.doc(`rooms/${roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  const calls = { occupancy: [], revoked: [], ended: [] };
  let occupancyHook = async () => ({ present: false, participantCount: 0 });
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
    async endRoom(roomName) { calls.ended.push(roomName); return {}; },
    async roomOccupancy(binding) { calls.occupancy.push(binding); return occupancyHook(binding); },
  };
  const service = createServerSessionService({ ...dependencies, livekit });
  const control = createServerSessionControlService({ ...dependencies, livekit });
  const staleness = createServerSessionStalenessService({ ...dependencies, livekit });
  const target = { serverId: root.serverId, channelId: channel.id };
  return {
    db, Timestamp, uid, serverId: root.serverId, channelId: channel.id, roomId, calls, control, staleness,
    channelRef: channel.ref, roomRef: db.doc(`rooms/${roomId}`),
    sessionRef: (sessionId) => channel.ref.collection("channelSessions").doc(sessionId),
    rtcName: (sessionId) => canonicalLiveKitRoomName(root.serverId, channel.id, sessionId),
    advance: (ms) => { nowMs += ms; }, clock,
    onOccupancy: (hook) => { occupancyHook = hook; },
    sweep: (options) => staleness.stageStaleServerChannelSessions(options),
    start: () => service.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() })),
    token: (sessionId, actor = uid) =>
      service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    member: async () => {
      const userId = `stale-member-${randomUUID()}`;
      await db.doc(`users/${userId}`).set({ displayName: "Staleness member", status: "active" });
      await db.doc(`clubs/${root.serverId}/members/${userId}`).set({ userId, role: "member", authorizationRevision: 1 });
      return userId;
    },
    drain: async (operationId) => {
      for (let attempt = 0; attempt < 4; attempt += 1) {
        const outcome = await control.processServerSessionEndPage({ operationId });
        if (!outcome.cleanupPending) return outcome;
      }
      throw new Error("The end generation did not drain within four passes.");
    },
  };
}

const untouched = (outcome) => ({ ...outcome, staged: [] });

emulatorTest("a generation whose every token expired a grace ago and whose provider room is gone is staged through the sessionEnd outbox, then drained by the existing worker", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  const member = await f.member();
  await f.token(sessionId, member);
  const beforeChannel = (await f.channelRef.get()).data();
  assert.equal(beforeChannel.liveness.isLive, true);
  f.advance(TOKEN_TTL_MS + STALE_GENERATION_GRACE_MS + 1);
  const outcome = await f.sweep();
  assert.equal(outcome.scanned, 1);
  assert.equal(outcome.staged.length, 1);
  const [staged] = outcome.staged;
  assert.deepEqual({ ...staged, endOperationId: undefined }, {
    outcome: "staged", serverId: f.serverId, channelId: f.channelId, roomId: f.roomId, sessionId,
    livekitRoomName: f.rtcName(sessionId), endOperationId: undefined,
  });
  assert.match(staged.endOperationId, /^[a-f0-9]{64}$/u);
  assert.deepEqual(f.calls.occupancy, [{ serverId: f.serverId, channelId: f.channelId, roomId: f.roomId, sessionId, livekitRoomName: f.rtcName(sessionId) }]);
  // Exactly the staged-end shape every authorized end writes: the session is
  // ending under a durable end job, the projection is idle in the same
  // transaction, and the anchor carries the cleanup pointer.
  const session = (await f.sessionRef(sessionId).get()).data();
  assert.equal(session.status, "ending");
  assert.equal(session.endOperationId, staged.endOperationId);
  assert.equal(session.authorizationRevision, 2);
  const job = (await f.db.doc(`serverControlOutbox/${staged.endOperationId}`).get()).data();
  assert.equal(job.kind, "sessionEnd");
  assert.equal(job.status, "pending");
  assert.equal(job.sessionId, sessionId);
  assert.equal(job.maxTokenExpiresAtMillis, session.maxTokenExpiresAtMillis);
  assert.match(job.parentOperationId, /^[a-f0-9]{64}$/u);
  const channel = (await f.channelRef.get()).data();
  assert.equal(channel.activeSessionId, null);
  assert.deepEqual(channel.liveness, channelLiveness());
  assert.equal(channel.revision, beforeChannel.revision + 1);
  const room = (await f.roomRef.get()).data();
  assert.equal(room.isLive, false);
  assert.equal(room.voiceSessionId, null);
  assert.equal(room.livekitRoomName, null);
  assert.equal(room.serverSessionCleanupId, sessionId);
  // The existing end worker drains it: recipients revoked, the immutable
  // old generation deleted at the provider, the session ended.
  const drained = await f.drain(staged.endOperationId);
  assert.equal(drained.cleanupPending, false);
  assert.equal((await f.sessionRef(sessionId).get()).data().status, "ended");
  assert.deepEqual(f.calls.revoked.map((call) => call.userId), [member]);
  assert.deepEqual(f.calls.ended, [f.rtcName(sessionId)]);
  assert.equal((await f.roomRef.get()).data().serverSessionCleanupId, null);
  // Nothing is live any more, so the next sweep scans nothing.
  const again = await f.sweep();
  assert.equal(again.scanned, 0);
  assert.deepEqual(again.staged, []);
});

emulatorTest("a young generation, a renewed token, an occupied room, a provider error and a malformed occupancy are never staged, and a young one never reaches the provider", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const snapshot = async () => ({ channel: (await f.channelRef.get()).data(), room: (await f.roomRef.get()).data(),
    session: (await f.sessionRef(sessionId).get()).data() });
  const before = await snapshot();
  // Inside the token's own lifetime: young, and the provider is not asked.
  f.advance(TOKEN_TTL_MS - 1);
  let outcome = await f.sweep();
  assert.equal(outcome.skippedYoung, 1);
  assert.deepEqual(outcome.staged, []);
  assert.equal(f.calls.occupancy.length, 0);
  // Inside the grace after expiry: still young.
  f.advance(STALE_GENERATION_GRACE_MS);
  outcome = await f.sweep();
  assert.equal(outcome.skippedYoung, 1);
  assert.equal(f.calls.occupancy.length, 0);
  // A renewal moves the bound forward by a full token lifetime.
  await f.token(sessionId);
  f.advance(STALE_GENERATION_GRACE_MS + 2);
  outcome = await f.sweep();
  assert.equal(outcome.skippedYoung, 1);
  assert.equal(f.calls.occupancy.length, 0);
  f.advance(TOKEN_TTL_MS);
  // Past every token plus the grace: the provider decides, and an occupied
  // room is somebody whose connection outlived their token.
  f.onOccupancy(async () => ({ present: true, participantCount: 1 }));
  outcome = await f.sweep();
  assert.equal(outcome.skippedOccupied, 1);
  assert.equal(f.calls.occupancy.length, 1);
  // An unknown never ends a generation.
  f.onOccupancy(async () => { throw Object.assign(new Error("controlled outage"), { code: "unavailable" }); });
  outcome = await f.sweep();
  assert.equal(outcome.providerUnavailable, 1);
  f.onOccupancy(async () => ({}));
  outcome = await f.sweep();
  assert.equal(outcome.skippedOccupied, 1);
  assert.deepEqual(untouched(outcome).staged, []);
  const after = await snapshot();
  assert.deepEqual(after.channel, before.channel);
  assert.deepEqual(after.room, before.room);
  assert.equal(after.session.status, "live");
  assert.equal((await f.db.collection("serverControlOutbox").get()).size, 0);
});

emulatorTest("a generation that never issued a token is measured from its own start and drains with no recipients", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  f.advance(STALE_GENERATION_GRACE_MS - 1);
  assert.equal((await f.sweep()).skippedYoung, 1);
  f.advance(2);
  const outcome = await f.sweep();
  assert.equal(outcome.staged.length, 1);
  assert.equal((await f.sessionRef(sessionId).get()).data().status, "ending");
  const drained = await f.drain(outcome.staged[0].endOperationId);
  assert.equal(drained.cleanupPending, false);
  assert.equal((await f.sessionRef(sessionId).get()).data().status, "ended");
  assert.deepEqual(f.calls.revoked, []);
  assert.deepEqual(f.calls.ended, [f.rtcName(sessionId)]);
  assert.deepEqual((await f.channelRef.get()).data().liveness, channelLiveness());
});

emulatorTest("legacy live rooms are never candidates, a held anchor is never live, the scan bound reports truncation, and the option envelope fails closed", async () => {
  const f = await fixture();
  for (const index of [0, 1]) {
    await f.db.doc(`rooms/legacy-live-${index}`).set({
      status: "active", isLive: true, roomType: "community", visibility: "public", hostId: `legacy-host-${index}`,
      participantCount: 0, updatedAt: f.Timestamp.fromMillis(f.clock() - 10 * 60_000),
    });
  }
  // A held server's anchor: never live, so never scanned (start refuses held).
  const heldOwner = `held-owner-${randomUUID()}`;
  await f.db.doc(`users/${heldOwner}`).set({ displayName: "Held owner", status: "active" });
  const held = await createServerCreationService({ db: f.db, Timestamp: f.Timestamp, clock: f.clock }).createServerV1(request(heldOwner, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Held fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const heldAnchors = await f.db.collection("rooms").where("serverId", "==", held.serverId).get();
  assert.ok(heldAnchors.docs.every((anchor) => anchor.data().isLive === false && anchor.data().serverActivationState === "held"));
  const outcome = await f.sweep();
  assert.equal(outcome.scanned, 0);
  assert.equal(outcome.skippedLegacy, 2);
  assert.equal(outcome.truncated, false);
  assert.deepEqual(outcome.staged, []);
  assert.equal(f.calls.occupancy.length, 0);
  for (const index of [0, 1]) assert.equal((await f.db.doc(`rooms/legacy-live-${index}`).get()).data().isLive, true);
  const bounded = await f.sweep({ maxRooms: 1 });
  assert.equal(bounded.truncated, true);
  assert.equal(bounded.skippedLegacy, 1);
  for (const options of [{ graceMs: STALE_GENERATION_GRACE_MS - 1 }, { maxRooms: 0 }, { maxRooms: MAX_LIVE_ANCHOR_SCAN + 1 }]) {
    await assert.rejects(f.sweep(options), (error) => error.code === "invalid-argument", JSON.stringify(options));
  }
  assert.equal(STALE_GENERATION_GRACE_MS, TOKEN_TTL_MS);
  // An unsupported provider configuration surfaces on the run, before any scan.
  const unsupported = createServerSessionStalenessService({ db: f.db, Timestamp: f.Timestamp, clock: f.clock, livekit: {
    assertSupported() { throw Object.assign(new Error("not configured"), { code: "failed-precondition" }); },
    async roomOccupancy() { throw new Error("must not be reached"); },
  } });
  await assert.rejects(unsupported.stageStaleServerChannelSessions(), (error) => error.code === "failed-precondition");
  assert.throws(() => createServerSessionStalenessService({ db: f.db, Timestamp: f.Timestamp, clock: f.clock,
    livekit: { assertSupported() {} } }), TypeError);
});

emulatorTest("a token minted between the provider reading and the commit refuses the staging as changed, and the generation is staged only once its new bound has passed", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const member = await f.member();
  f.advance(TOKEN_TTL_MS + STALE_GENERATION_GRACE_MS + 1);
  const before = (await f.channelRef.get()).data();
  f.onOccupancy(async () => {
    // A reconnecting member mints a fresh token while the sweep is asking the
    // provider: the bound moves, and this occupancy reading is now stale.
    await f.token(sessionId, member);
    return { present: false, participantCount: 0 };
  });
  const raced = await f.sweep();
  assert.equal(raced.changed, 1);
  assert.deepEqual(raced.staged, []);
  assert.equal((await f.sessionRef(sessionId).get()).data().status, "live");
  assert.deepEqual((await f.channelRef.get()).data(), before);
  assert.equal((await f.db.collection("serverControlOutbox").get()).size, 0);
  f.onOccupancy(async () => ({ present: false, participantCount: 0 }));
  // The new token keeps the generation young until its own expiry plus grace.
  f.advance(TOKEN_TTL_MS + STALE_GENERATION_GRACE_MS - 1);
  assert.equal((await f.sweep()).skippedYoung, 1);
  f.advance(2);
  const staged = await f.sweep();
  assert.equal(staged.staged.length, 1);
  assert.equal((await f.sessionRef(sessionId).get()).data().status, "ending");
});

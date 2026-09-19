// The provider half of the empty-generation grace: a signed LiveKit
// `room_finished` for a `srv_` generation, received by
// receiveLiveKitAchievementWebhook, records (or completes) the same grace the
// release callable does, through the reviewed staleness service and behind
// `workersEnabled`. It is isolated from voice-time accounting in both
// directions. Real emulator, real achievement store, fresh project per test.
const assert = require("node:assert/strict");
const { createHash, randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const { AccessToken } = require("livekit-server-sdk");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const apps = [];
const {
  FirestoreVoiceAchievementStore, createLiveKitAchievementWebhookHandler, createServerChannelLifecycle, sessionDocumentId,
} = require("../achievements/livekit_http");
const { createServerCreationService } = require("../servers/creation");
const { createServerSessionService } = require("../servers/sessions");
const { ADMISSION_WINDOW_MS, EMPTY_GENERATION_GRACE_MS } = require("../servers/session_staleness");
const { canonicalLiveKitRoomName, channelLiveness } = require("../servers/contract");
const { SESSION_TOKEN_TTL_SECONDS } = require("../servers/session_contract");

const API_KEY = "livekit-room-finished-key";
const API_SECRET = "livekit-room-finished-secret-at-least-32-chars";
const TOKEN_TTL_MS = SESSION_TOKEN_TTL_SECONDS * 1000;
const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
after(async () => { for (const app of apps) await require("firebase-admin/app").deleteApp(app); });

function freshDb() {
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, Timestamp } = require("firebase-admin/firestore");
  const app = initializeApp({ projectId: `demo-yovoice-finish-${randomUUID().slice(0, 8)}` }, `finish-${randomUUID()}`);
  apps.push(app);
  return { db: getFirestore(app), Timestamp };
}

const nobody = () => ({ present: false, participantCount: 0, participantIdentities: [] });
const only = (...identities) => ({ present: true, participantCount: identities.length, participantIdentities: identities });

async function signedAuthorization(body) {
  const token = new AccessToken(API_KEY, API_SECRET, { ttl: 300 });
  token.sha256 = createHash("sha256").update(body).digest("base64");
  return token.toJwt();
}

async function fixture() {
  const { db, Timestamp } = freshDb();
  const uid = `finish-owner-${randomUUID()}`;
  // Whole seconds: LiveKit's `created_at` is in seconds.
  let nowMs = Math.floor(Date.now() / 1000) * 1000;
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Room finished owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Room finished fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const channel = (await db.collection(`clubs/${root.serverId}/channels`).where("kind", "==", "voice").get()).docs[0];
  const roomId = channel.data().roomId;
  // Isolated emulator fixture activation, not a shipped activation path.
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  await db.doc(`rooms/${roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  const calls = { occupancy: [], lifecycle: [] };
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
    async revokeParticipant() { return { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 }; },
    async endRoom() { return {}; },
    async roomOccupancy(binding) { calls.occupancy.push(binding); return occupancyHook(binding); },
  };
  let workersEnabled = true;
  let lifecycleFailure = null;
  let storeFailure = null;
  const lifecycle = createServerChannelLifecycle({ db, Timestamp, livekit, clock,
    activationGate: { requireCallable: async () => ({}), workersEnabled: async () => workersEnabled } });
  const serverLifecycle = {
    async onRoomFinished(input) {
      if (lifecycleFailure) throw lifecycleFailure;
      const result = await lifecycle.onRoomFinished(input);
      calls.lifecycle.push({ input, outcome: result.outcome });
      return result;
    },
  };
  const store = new FirestoreVoiceAchievementStore({ db });
  const failingStore = {
    async handle(webhook) {
      if (storeFailure) throw storeFailure;
      return store.handle(webhook);
    },
  };
  const handler = createLiveKitAchievementWebhookHandler({
    apiKeyProvider: () => API_KEY, apiSecretProvider: () => API_SECRET, store: failingStore, now: clock, serverLifecycle,
  });
  const service = createServerSessionService({ ...dependencies, livekit });
  const target = { serverId: root.serverId, channelId: channel.id };
  return {
    db, uid, serverId: root.serverId, channelId: channel.id, roomId, calls, clock,
    channelRef: channel.ref, roomRef: db.doc(`rooms/${roomId}`),
    rtcName: (sessionId) => canonicalLiveKitRoomName(root.serverId, channel.id, sessionId),
    advance: (ms) => { nowMs += ms; },
    onOccupancy: (hook) => { occupancyHook = hook; },
    pauseWorkers: (value) => { workersEnabled = !value; },
    failLifecycle: (error) => { lifecycleFailure = error; },
    failStore: (error) => { storeFailure = error; },
    start: () => service.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() })),
    token: (sessionId, actor = uid) =>
      service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    member: async () => {
      const userId = `finish-member-${randomUUID()}`;
      await db.doc(`users/${userId}`).set({ displayName: "Room finished member", status: "active" });
      await db.doc(`clubs/${root.serverId}/members/${userId}`).set({ userId, role: "member", authorizationRevision: 1 });
      return userId;
    },
    session: async (sessionId) => (await channel.ref.collection("channelSessions").doc(sessionId).get()).data(),
    outbox: async () => (await db.collection("serverControlOutbox").get()).docs.map((document) => document.data()),
    async deliver(body) {
      const recorded = { statusCode: null, body: null };
      const response = {
        set() { return response; },
        status(code) { recorded.statusCode = code; return response; },
        json(payload) { recorded.body = payload; return response; },
        send(payload) { recorded.body = payload; return response; },
      };
      await handler({ method: "POST", rawBody: Buffer.from(body, "utf8"),
        headers: { authorization: await signedAuthorization(body) } }, response);
      return recorded;
    },
  };
}

function participantBody(type, atSeconds, { roomName, roomSid, participantSid, identity, joinedAtSeconds }) {
  return JSON.stringify({
    event: type, id: `EV_${type}_${atSeconds}_${participantSid}`, created_at: atSeconds,
    room: { sid: roomSid, name: roomName },
    participant: { sid: participantSid, identity, joined_at: joinedAtSeconds, joined_at_ms: joinedAtSeconds * 1000 },
  });
}

function roomFinishedBody(atSeconds, { roomName, roomSid }) {
  return JSON.stringify({
    event: "room_finished", id: `EV_room_finished_${atSeconds}_${roomSid}`, created_at: atSeconds,
    room: { sid: roomSid, name: roomName },
  });
}

const seconds = (f) => Math.floor(f.clock() / 1000);

emulatorTest("room_finished records the grace, voice time is still credited, a replay after the grace ends the generation exactly once, and a further replay is a no-op", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const roomName = f.rtcName(sessionId);
  const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
  const joinedAt = seconds(f);
  const join = await f.deliver(participantBody("participant_joined", joinedAt,
    { roomName, roomSid, participantSid: "PA_owner", identity: f.uid, joinedAtSeconds: joinedAt }));
  assert.deepEqual([join.statusCode, join.body.outcome], [202, "opened"]);
  assert.deepEqual(f.calls.lifecycle, [], "only room_finished reaches the lifecycle");
  f.advance(ADMISSION_WINDOW_MS + 90_000);
  const finished = roomFinishedBody(seconds(f), { roomName, roomSid });
  const first = await f.deliver(finished);
  assert.deepEqual([first.statusCode, first.body.outcome], [202, "room-closed"]);
  const credited = (await f.db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_owner")}`).get()).data();
  assert.equal(credited.status, "closed");
  assert.equal(credited.creditedVoiceSeconds, (ADMISSION_WINDOW_MS + 90_000) / 1000);
  assert.deepEqual(f.calls.lifecycle, [{ input: { livekitRoomName: roomName, finishedAtMs: f.clock() }, outcome: "pending" }]);
  assert.equal((await f.session(sessionId)).emptyObservation.source, "providerFinished");
  assert.equal((await f.channelRef.get()).data().liveness.isLive, true, "the grace keeps LIVE");
  assert.deepEqual(await f.outbox(), []);
  // LiveKit retries a delivery it did not see acknowledged. After the grace,
  // the same signed event completes it.
  f.advance(EMPTY_GENERATION_GRACE_MS);
  const replay = await f.deliver(finished);
  assert.deepEqual([replay.statusCode, replay.body.outcome], [202, "room-closed"]);
  assert.equal(f.calls.lifecycle.at(-1).outcome, "ended");
  const session = await f.session(sessionId);
  assert.equal(session.status, "ending");
  const jobs = await f.outbox();
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].kind, "sessionEnd");
  assert.equal(jobs[0].operationId, session.endOperationId);
  const channel = (await f.channelRef.get()).data();
  assert.equal(channel.activeSessionId, null);
  assert.deepEqual(channel.liveness, channelLiveness());
  assert.equal((await f.roomRef.get()).data().isLive, false);
  const again = await f.deliver(finished);
  assert.equal(again.statusCode, 202);
  assert.equal(f.calls.lifecycle.at(-1).outcome, "not-live");
  assert.equal((await f.outbox()).length, 1, "a replayed delivery is a no-op");
  assert.equal((await f.db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_owner")}`).get()).data()
    .creditedVoiceSeconds, credited.creditedVoiceSeconds, "voice time is credited once");
});

emulatorTest("a lifecycle failure never changes the achievement answer, and an achievement failure never stops the lifecycle", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const roomName = f.rtcName(sessionId);
  const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
  f.advance(ADMISSION_WINDOW_MS + 1_000);
  f.failLifecycle(Object.assign(new Error("controlled lifecycle outage"), { code: 14 }));
  const withBrokenLifecycle = await f.deliver(roomFinishedBody(seconds(f), { roomName, roomSid }));
  assert.deepEqual([withBrokenLifecycle.statusCode, withBrokenLifecycle.body],
    [202, { accepted: true, outcome: "room-closed" }]);
  assert.equal((await f.session(sessionId)).emptyObservation ?? null, null);
  f.failLifecycle(null);
  // A transient achievement fault is still a 503 for LiveKit to retry, and
  // the finished room is still observed.
  f.advance(1_000);
  f.failStore(Object.assign(new Error("controlled store outage"), { code: 14 }));
  const withBrokenStore = await f.deliver(roomFinishedBody(seconds(f), { roomName, roomSid }));
  assert.deepEqual([withBrokenStore.statusCode, withBrokenStore.body],
    [503, { accepted: false, error: "temporarily-unavailable" }]);
  assert.equal(f.calls.lifecycle.at(-1).outcome, "pending");
  assert.equal((await f.session(sessionId)).emptyObservation.source, "providerFinished");
  // A permanent achievement refusal is still a 400.
  f.failStore(new TypeError("controlled permanent fault"));
  const permanent = await f.deliver(roomFinishedBody(seconds(f) + 1, { roomName, roomSid }));
  assert.deepEqual([permanent.statusCode, permanent.body], [400, { accepted: false, error: "invalid-source" }]);
  assert.equal(f.calls.lifecycle.at(-1).outcome, "pending");
});

emulatorTest("an unbound srv_ name, a legacy room, paused workers, a recent admission and an occupied room never record the grace", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  const roomName = f.rtcName(sessionId);
  const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
  f.advance(ADMISSION_WINDOW_MS + 1_000);
  const unbound = await f.deliver(roomFinishedBody(seconds(f), { roomName: `srv_${"0".repeat(40)}`, roomSid }));
  assert.equal(unbound.statusCode, 202);
  assert.equal(f.calls.lifecycle.at(-1).outcome, "unbound");
  const lifecycleCalls = f.calls.lifecycle.length;
  const legacy = await f.deliver(roomFinishedBody(seconds(f), { roomName: f.roomId, roomSid }));
  assert.equal(legacy.statusCode, 202);
  assert.equal(f.calls.lifecycle.length, lifecycleCalls, "a legacy room name never reaches the server path");
  f.pauseWorkers(true);
  const paused = await f.deliver(roomFinishedBody(seconds(f), { roomName, roomSid }));
  assert.deepEqual([paused.statusCode, paused.body.outcome], [202, "room-closed"], "accounting still answers");
  assert.equal(f.calls.lifecycle.at(-1).outcome, "workers-paused");
  assert.equal(f.calls.occupancy.length, 0);
  f.pauseWorkers(false);
  // Somebody was handed a token after finishedAt - 30 s: still arriving.
  const member = await f.member();
  await f.token(sessionId, member);
  f.advance(10_000);
  await f.deliver(roomFinishedBody(seconds(f), { roomName, roomSid }));
  assert.equal(f.calls.lifecycle.at(-1).outcome, "occupied");
  f.advance(ADMISSION_WINDOW_MS);
  f.onOccupancy(async () => only(member));
  await f.deliver(roomFinishedBody(seconds(f), { roomName, roomSid }));
  assert.equal(f.calls.lifecycle.at(-1).outcome, "occupied");
  f.onOccupancy(async () => { throw Object.assign(new Error("controlled outage"), { code: "unavailable" }); });
  await f.deliver(roomFinishedBody(seconds(f) + 1, { roomName, roomSid }));
  assert.equal(f.calls.lifecycle.at(-1).outcome, "unknown");
  assert.equal((await f.session(sessionId)).emptyObservation ?? null, null);
  assert.equal((await f.session(sessionId)).status, "live");
  assert.deepEqual(await f.outbox(), []);
});

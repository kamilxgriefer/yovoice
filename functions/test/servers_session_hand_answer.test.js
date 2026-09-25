// Request to speak end to end: the host's or a moderator's answer to a raised
// hand (answerServerSessionHandV1), the decision a promotion records, the
// reset a new raise performs, a hand on a finished generation, and the
// provider path that lowers a hand its owner left behind
// (session_staleness.js lowerDepartedHand). Real Firestore emulator, the
// deterministic provider seam the participation suite uses; nothing here
// proves a real LiveKit connection.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");
const { HttpsError } = require("firebase-functions/v2/https");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let db; let app; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-server-hand-answer" }, `server-hand-answer-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerMembershipService } = require("../servers/memberships");
const { createServerSessionService } = require("../servers/sessions");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const {
  ANSWERABLE_HAND_DECISIONS, HAND_DECISIONS, PARTICIPATION_KIND, createServerSessionParticipationService,
} = require("../servers/session_participation");
const { createServerSessionStalenessService } = require("../servers/session_staleness");
const { canonicalLiveKitRoomName } = require("../servers/contract");
const {
  SESSION_HAND_CALLABLE_METHODS, SESSION_HAND_EXPORT_NAMES, SERVERS_V1_EXPORT_NAMES,
  createServerSessionHandFunctions,
} = require("../servers/registration");

const emulatorTest = (name, fn) => test(`Hand answer: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data, token = {}) => ({ auth: { uid, token: { email_verified: true, ...token } }, data });
const reject = (promise, code) => assert.rejects(promise, (error) => error.code === code, `expected ${code}`);
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

async function fixture() {
  const owner = `hand-owner:${randomUUID()}`;
  let nowMs = Math.floor(Date.now() / 1000) * 1000;
  const clock = () => nowMs;
  await db.doc(`users/${owner}`).set({ displayName: "Hand owner", status: "active" });
  const deps = { db, Timestamp, clock };
  const created = await createServerCreationService(deps).createServerV1(request(owner, {
    requestId: randomUUID(), serverType: "community", templateVersion: 1, name: "Hand fixture",
    description: "", privacy: "public", defaultLanguage: "English",
  }));
  const root = db.doc(`clubs/${created.serverId}`);
  await root.update({ status: "active", serverActivationState: "active" });
  const stageResult = await createServerChannelService(deps).createServerChannelV1(request(owner, {
    serverId: root.id, requestId: randomUUID(), kind: "stage", name: "Studio B", categoryId: null,
    accessMode: "members", experience: "broadcast", mediaMode: "audio",
  }));
  const anchors = await db.collection("rooms").where("serverId", "==", root.id).get();
  for (const anchor of anchors.docs) await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: owner });
  const stage = await root.collection("channels").doc(stageResult.channelId).get();
  const calls = { removed: [], ended: [], occupancy: [] };
  let occupancy = async () => ({ present: false, participantCount: 0, participantIdentities: [] });
  const livekit = {
    assertSupported() {},
    async mintToken(value) {
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
    async roomOccupancy(binding) { calls.occupancy.push(binding); return occupancy(binding); },
  };
  const dependencies = { ...deps, livekit };
  const service = { ...createServerMembershipService(dependencies), ...createServerSessionService(dependencies),
    ...createServerConvergenceRuntimeService(dependencies), ...createServerSessionParticipationService(dependencies) };
  const staleness = createServerSessionStalenessService(dependencies);
  async function member(role = "member") {
    const uid = `hand-member:${randomUUID()}`;
    await db.doc(`users/${uid}`).set({ displayName: `Listener ${uid.slice(-4)}`, status: "active" });
    await service.joinServerV1(request(uid, { serverId: root.id, requestId: randomUUID() }));
    if (role !== "member") await service.setServerMemberRoleV1(request(owner, { serverId: root.id, requestId: randomUUID(), memberId: uid, role }));
    return uid;
  }
  const target = { serverId: root.id, channelId: stage.id };
  const start = () => service.startServerChannelSessionV1(request(owner, { ...target, requestId: randomUUID() }));
  const token = (sessionId, uid) => service.createServerChannelTokenV1(request(uid, { ...target, sessionId, requestId: randomUUID() }));
  async function call(method, uid, data, token = {}) {
    const payload = { serverId: root.id, requestId: randomUUID(), ...data };
    return { result: await service[method](request(uid, payload, token)), payload };
  }
  const participant = (uid) => db.doc(`rooms/${stage.data().roomId}/participants/${uid}`).get().then((snap) => snap.data());
  const jobs = () => db.collection("serverControlOutbox").where("serverId", "==", root.id).where("kind", "==", PARTICIPATION_KIND).get();
  return { owner, root, stage, service, staleness, calls, member, start, token, call, participant, jobs,
    advance: (ms) => { nowMs += ms; }, clock,
    onOccupancy: (hook) => { occupancy = hook; },
    rtcName: (sessionId) => canonicalLiveKitRoomName(root.id, stage.id, sessionId) };
}

test("Hand answer: the extension registers one secret-free callable outside the frozen manifest", async () => {
  assert.deepEqual(SESSION_HAND_EXPORT_NAMES, ["answerServerSessionHandV1"]);
  assert.equal(SESSION_HAND_CALLABLE_METHODS.answerServerSessionHandV1, "participation");
  assert.equal(SERVERS_V1_EXPORT_NAMES.includes("answerServerSessionHandV1"), false);
  assert.deepEqual(ANSWERABLE_HAND_DECISIONS, ["declined"]);
  assert.deepEqual(HAND_DECISIONS, ["approved", "declined", "lowered"]);
  const registrations = [];
  const calls = [];
  let admitted = false;
  const functions = createServerSessionHandFunctions({
    runtime: { db: {}, participation: { answerServerSessionHandV1: async (bound) => { calls.push(bound); return { ok: true }; } } },
    registrars: { onCall: (options, handler) => { const entry = { options, handler }; registrations.push(entry); return entry; } },
    activationGate: {
      requireCallable: async () => {
        if (!admitted) throw new HttpsError("failed-precondition", "Servers are not enabled for this account.");
        return {};
      },
      workersEnabled: async () => true,
    },
    log: { info() {}, warn() {}, error() {} },
  });
  assert.deepEqual(Object.keys(functions), ["answerServerSessionHandV1"]);
  const entry = functions.answerServerSessionHandV1;
  assert.equal(entry.options.region, "europe-west1");
  assert.equal(entry.options.minInstances, 0);
  assert.equal(entry.options.enforceAppCheck, false);
  assert.equal("secrets" in entry.options, false);
  await assert.rejects(entry.handler({ data: {} }), (error) => error.code === "unauthenticated");
  const bound = { auth: { uid: "u1", token: { email_verified: true } }, data: { a: 1 } };
  await assert.rejects(entry.handler(bound), (error) => error.code === "failed-precondition");
  admitted = true;
  assert.deepEqual(await entry.handler(bound), { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(registrations.length, 1);
});

emulatorTest("only the session host or an outranking moderator may decline, and the decline lowers the hand with a recorded decision and no authority change", async () => {
  const f = await fixture();
  const listener = await f.member();
  const plain = await f.member();
  const guest = await f.member("guest");
  const moderator = await f.member("moderator");
  const admin = await f.member("admin");
  const { sessionId } = await f.start();
  // A server `guest` holds no joinVoice capability on a members channel, so
  // it never receives a token; it is refused standing all the same.
  for (const uid of [f.owner, listener, plain, moderator, admin]) await f.token(sessionId, uid);
  const binding = { channelId: f.stage.id, sessionId };
  const answer = (uid, participantId, data = {}) =>
    f.call("answerServerSessionHandV1", uid, { ...binding, participantId, decision: "declined", ...data });
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  await f.call("setServerSessionHandV1", admin, { ...binding, raised: true });
  const before = await f.participant(listener);
  assert.equal(before.isHandRaised, true);
  // Exact input: an unknown decision, an approval (the role callable's job),
  // extra keys and a self-answer are all refused before any read.
  await reject(answer(f.owner, listener, { decision: "approved" }), "invalid-argument");
  await reject(answer(f.owner, listener, { decision: "lowered" }), "invalid-argument");
  await reject(answer(f.owner, listener, { extra: true }), "invalid-argument");
  await reject(answer(listener, listener), "invalid-argument");
  // Standing: a plain member, a guest and a platform-staff claim have none.
  for (const [uid, token] of [[plain, {}], [guest, {}], [plain, { admin: true, staff: true }]]) {
    await reject(f.call("answerServerSessionHandV1", uid, { ...binding, participantId: listener, decision: "declined" }, token),
      "permission-denied");
  }
  // A moderator does not outrank an admin; the session host (the owner) does.
  await reject(answer(moderator, admin), "permission-denied");
  // Nobody here outranks the generation's host (the owner), and the host
  // never queues anyway.
  await reject(answer(moderator, f.owner), "permission-denied");
  await reject(answer(admin, f.owner), "permission-denied");
  // Somebody who never received a token has no document to answer.
  const absent = await f.member();
  await reject(answer(f.owner, absent), "failed-precondition");
  assert.deepEqual(await f.participant(listener), before);

  const declined = await answer(moderator, listener);
  assert.deepEqual(declined.result, { serverId: f.root.id, channelId: f.stage.id, sessionId, participantId: listener,
    role: "listener", hostMuted: false, serverMuted: false, participantRevision: 1, decision: "declined", changed: true });
  const doc = await f.participant(listener);
  assert.equal(doc.isHandRaised, false);
  assert.equal(doc.handRaisedAt, null);
  assert.equal(doc.handDecision, "declined");
  assert.equal(doc.handDecidedById, moderator);
  assert.equal(doc.handDecidedAt.toMillis(), f.clock());
  // A hand is not authority: nothing that reaches the provider moved.
  assert.equal(doc.authorizationRevision, before.authorizationRevision);
  assert.equal(doc.role, "listener");
  assert.equal((await f.jobs()).size, 0);
  assert.equal(f.calls.removed.length, 0);
  // The host answers the admin they outrank.
  assert.equal((await answer(f.owner, admin)).result.changed, true);
  assert.equal((await f.participant(admin)).handDecision, "declined");
});

emulatorTest("answers are idempotent: a replay returns its receipt, a second answer is a no-op, and a new raise clears the old decision", async () => {
  const f = await fixture();
  const listener = await f.member();
  const moderator = await f.member("moderator");
  const { sessionId } = await f.start();
  await f.token(sessionId, listener);
  await f.token(sessionId, moderator);
  const binding = { channelId: f.stage.id, sessionId };
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  const first = await f.call("answerServerSessionHandV1", f.owner,
    { ...binding, participantId: listener, decision: "declined" });
  const afterFirst = await f.participant(listener);
  f.advance(5_000);
  // The same request replays its receipt and writes nothing new.
  assert.deepEqual(await f.service.answerServerSessionHandV1(request(f.owner, first.payload)), first.result);
  assert.deepEqual(await f.participant(listener), afterFirst);
  // A second moderator answering the same, already-answered hand changes
  // nothing and cannot overwrite the first answer.
  const second = await f.call("answerServerSessionHandV1", moderator,
    { ...binding, participantId: listener, decision: "declined" });
  assert.equal(second.result.changed, false);
  assert.deepEqual(await f.participant(listener), afterFirst);
  // The person asks again: the old decision belonged to the old request.
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  let doc = await f.participant(listener);
  assert.equal(doc.isHandRaised, true);
  assert.equal(doc.handDecision, null);
  assert.equal(doc.handDecidedAt, null);
  assert.equal(doc.handDecidedById, null);
  // Withdrawing it themselves also leaves no decision behind, and a decline
  // of a withdrawn hand is a no-op.
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: false });
  doc = await f.participant(listener);
  assert.equal(doc.isHandRaised, false);
  assert.equal(doc.handDecision, null);
  const late = await f.call("answerServerSessionHandV1", moderator,
    { ...binding, participantId: listener, decision: "declined" });
  assert.equal(late.result.changed, false);
  assert.equal((await f.participant(listener)).handDecision, null);
});

emulatorTest("a promotion that answers a raised hand records the approval; a promotion nobody asked for records none", async () => {
  const f = await fixture();
  const asking = await f.member();
  const quiet = await f.member();
  const { sessionId } = await f.start();
  await f.token(sessionId, asking);
  await f.token(sessionId, quiet);
  const binding = { channelId: f.stage.id, sessionId };
  await f.call("setServerSessionHandV1", asking, { ...binding, raised: true });
  const promotion = await f.call("setServerSessionParticipantRoleV1", f.owner,
    { ...binding, participantId: asking, role: "guest" });
  // The role receipt keeps its exact reviewed shape.
  assert.deepEqual(Object.keys(promotion.result).sort(), ["changed", "channelId", "cleanupPending", "hostMuted",
    "participantId", "participantRevision", "role", "serverId", "serverMuted", "sessionId"]);
  const approved = await f.participant(asking);
  assert.equal(approved.role, "guest");
  assert.equal(approved.isHandRaised, false);
  assert.equal(approved.handDecision, "approved");
  assert.equal(approved.handDecidedById, f.owner);
  assert.equal(approved.handDecidedAt.toMillis(), f.clock());
  await f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: quiet, role: "guest" });
  const unasked = await f.participant(quiet);
  assert.equal(unasked.role, "guest");
  assert.equal(unasked.handDecision, undefined);
  assert.equal(unasked.handDecidedById, undefined);
});

emulatorTest("a hand on a finished generation can be neither raised nor answered", async () => {
  const f = await fixture();
  const listener = await f.member();
  const { sessionId } = await f.start();
  await f.token(sessionId, listener);
  const binding = { channelId: f.stage.id, sessionId };
  await f.call("setServerSessionHandV1", listener, { ...binding, raised: true });
  await f.service.endServerChannelSessionV1(request(f.owner, { serverId: f.root.id, ...binding, requestId: randomUUID() }));
  // The end's cleanup may already have removed the generation's documents;
  // whatever it left is what must stay.
  const standing = await f.participant(listener);
  await reject(f.call("answerServerSessionHandV1", f.owner, { ...binding, participantId: listener, decision: "declined" }),
    "permission-denied");
  await reject(f.call("setServerSessionHandV1", listener, { ...binding, raised: false }), "permission-denied");
  await reject(f.call("setServerSessionParticipantRoleV1", f.owner, { ...binding, participantId: listener, role: "guest" }),
    "permission-denied");
  // Nothing wrote to the finished generation's document (if any is left);
  // the host's queue query cannot name it either, because it filters on the
  // live sessionId.
  assert.deepEqual(await f.participant(listener), standing);
  assert.notEqual(standing?.handDecision, "declined");
  // The provider path refuses it too.
  const lowered = await f.staleness.lowerDepartedHand({ livekitRoomName: f.rtcName(sessionId),
    participantIdentity: listener, leftAtMs: f.clock() });
  assert.notEqual(lowered.outcome, "lowered");
  assert.deepEqual(await f.participant(listener), standing);
});

emulatorTest("the provider lowers a hand its owner left behind, and only that one", async () => {
  const f = await fixture();
  const leaver = await f.member();
  const returning = await f.member();
  const { sessionId } = await f.start();
  await f.token(sessionId, leaver);
  await f.token(sessionId, returning);
  const binding = { channelId: f.stage.id, sessionId };
  await f.call("setServerSessionHandV1", leaver, { ...binding, raised: true });
  await f.call("setServerSessionHandV1", returning, { ...binding, raised: true });
  const livekitRoomName = f.rtcName(sessionId);
  f.advance(3_000);
  const leftAtMs = f.clock();
  // Malformed input and a room outside the Servers namespace do nothing.
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName: "legacy-room", participantIdentity: leaver, leftAtMs })).outcome, "skipped");
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: "", leftAtMs })).outcome, "skipped");
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: leaver, leftAtMs: 0 })).outcome, "skipped");
  // A provider that cannot answer lowers nothing.
  f.onOccupancy(async () => { throw new Error("provider down"); });
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: leaver, leftAtMs })).outcome, "unknown");
  f.onOccupancy(async () => ({ present: true, participantCount: 2, participantIdentities: [null, f.owner] }));
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: leaver, leftAtMs })).outcome, "unknown");
  assert.equal((await f.participant(leaver)).isHandRaised, true);
  // Still listed (a reconnect under a new participant SID): kept.
  f.onOccupancy(async () => ({ present: true, participantCount: 2, participantIdentities: [f.owner, returning] }));
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: returning, leftAtMs })).outcome, "present");
  assert.equal((await f.participant(returning)).isHandRaised, true);
  // Gone: lowered, with the reason the person can read.
  const lowered = await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: leaver, leftAtMs });
  assert.equal(lowered.outcome, "lowered");
  const doc = await f.participant(leaver);
  assert.equal(doc.isHandRaised, false);
  assert.equal(doc.handRaisedAt, null);
  assert.equal(doc.handDecision, "lowered");
  assert.equal(doc.handDecidedById, null);
  assert.equal(doc.authorizationRevision, 1);
  assert.equal((await f.jobs()).size, 0);
  // A replay converges without a second write.
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: leaver, leftAtMs })).outcome, "unchanged");
  assert.deepEqual(await f.participant(leaver), doc);
  // A hand raised after the departure instant belongs to a later request.
  f.onOccupancy(async () => ({ present: true, participantCount: 1, participantIdentities: [f.owner] }));
  f.advance(1_000);
  await f.call("setServerSessionHandV1", leaver, { ...binding, raised: true });
  assert.equal((await f.staleness.lowerDepartedHand({ livekitRoomName, participantIdentity: leaver, leftAtMs })).outcome, "unchanged");
  assert.equal((await f.participant(leaver)).isHandRaised, true);
});

emulatorTest("a signed participant_left for a srv_ generation reaches the lifecycle hook and lowers the hand; a paused worker or a hook without the departure half does nothing", async () => {
  const { createHash } = require("node:crypto");
  const { AccessToken } = require("livekit-server-sdk");
  const { createLiveKitAchievementWebhookHandler, createServerChannelLifecycle } = require("../achievements/livekit_http");
  const API_KEY = "livekit-hand-departure-key";
  const API_SECRET = "livekit-hand-departure-secret-at-least-32-chars";
  const f = await fixture();
  const leaver = await f.member();
  const { sessionId } = await f.start();
  await f.token(sessionId, leaver);
  await f.call("setServerSessionHandV1", leaver, { channelId: f.stage.id, sessionId, raised: true });
  f.onOccupancy(async () => ({ present: true, participantCount: 1, participantIdentities: [f.owner] }));
  let workersEnabled = false;
  const livekit = {
    assertSupported() {},
    roomOccupancy: async () => ({ present: true, participantCount: 1, participantIdentities: [f.owner] }),
  };
  const lifecycle = createServerChannelLifecycle({ db, Timestamp, livekit, clock: f.clock,
    activationGate: { requireCallable: async () => ({}), workersEnabled: async () => workersEnabled } });
  const outcomes = [];
  const store = { async handle() { return { outcome: "skipped:test" }; } };
  const handlerWith = (serverLifecycle) => createLiveKitAchievementWebhookHandler({
    apiKeyProvider: () => API_KEY, apiSecretProvider: () => API_SECRET, store, now: f.clock, serverLifecycle,
  });
  const recording = {
    onRoomFinished: async () => ({ outcome: "not-used" }),
    async onParticipantLeft(input) {
      const result = await lifecycle.onParticipantLeft(input);
      outcomes.push({ input, outcome: result.outcome });
      return result;
    },
  };
  async function deliver(handler, type) {
    const at = Math.floor(f.clock() / 1000);
    const body = JSON.stringify({
      event: type, id: `EV_${type}_${at}_${randomUUID()}`, created_at: at,
      room: { sid: "RM_hand_departure", name: f.rtcName(sessionId) },
      participant: { sid: "PA_leaver", identity: leaver, joined_at: at - 60, joined_at_ms: (at - 60) * 1000 },
    });
    const token = new AccessToken(API_KEY, API_SECRET, { ttl: 300 });
    token.sha256 = createHash("sha256").update(body).digest("base64");
    const recorded = { statusCode: null };
    const response = {
      set() { return response; },
      status(code) { recorded.statusCode = code; return response; },
      json() { return response; },
      send() { return response; },
    };
    await handler({ method: "POST", rawBody: Buffer.from(body, "utf8"),
      headers: { authorization: await token.toJwt() } }, response);
    return recorded;
  }
  // A hook that only knows room_finished is exactly as before.
  assert.equal((await deliver(handlerWith({ onRoomFinished: async () => ({}) }), "participant_left")).statusCode, 202);
  assert.equal((await f.participant(leaver)).isHandRaised, true);
  // Workers paused: nothing is lowered, the delivery is still accepted.
  f.advance(1_000);
  assert.equal((await deliver(handlerWith(recording), "participant_left")).statusCode, 202);
  assert.equal(outcomes.at(-1).outcome, "workers-paused");
  assert.equal((await f.participant(leaver)).isHandRaised, true);
  // Workers running: the departure lowers the hand.
  workersEnabled = true;
  f.advance(1_000);
  assert.equal((await deliver(handlerWith(recording), "participant_connection_aborted")).statusCode, 202);
  assert.deepEqual(outcomes.at(-1), { input: { livekitRoomName: f.rtcName(sessionId), participantIdentity: leaver,
    leftAtMs: f.clock() }, outcome: "lowered" });
  const doc = await f.participant(leaver);
  assert.equal(doc.isHandRaised, false);
  assert.equal(doc.handDecision, "lowered");
});

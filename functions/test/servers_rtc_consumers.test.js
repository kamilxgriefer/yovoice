// V1-aware global RTC consumers (slice S3).
//
// A V1 channel session lives under an immutable `srv_` LiveKit name, not the
// anchor room id. These tests prove, on a real Firestore emulator, that the
// three consumers outside the session runtime — staff voice enforcement, the
// legacy active-session mirror cleanup and the achievement webhook — resolve
// the reciprocal room -> channel -> channelSession binding instead of trusting
// a name, fail closed when nothing is bound, and leave legacy rooms untouched.
// The V1 graph is seeded through the reviewed factories; the provider is a
// stub in exactly the shape the existing consumer suites use.

const assert = require("node:assert/strict");
const { createHash, randomUUID } = require("node:crypto");
const { after, describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { AccessToken } = require("livekit-server-sdk");

if (getApps().length === 0) initializeApp();

const { createServerCreationService } = require("../servers/creation");
const { createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const { canonicalLiveKitRoomName } = require("../servers/contract");
const {
  RTC_BINDING_KINDS,
  RTC_BINDING_REASONS,
  resolveRtcBindingForLiveKitRoom,
  resolveRtcBindingForRoom,
} = require("../servers/rtc_binding");
const {
  EVENT_COLLECTION,
  EVENT_TYPES,
  MAX_UNBOUND_GENERATION_ATTEMPTS,
  NEEDS_RECONCILIATION,
  UNBOUND_LIVE_GENERATION,
  enqueueVoiceEnforcement,
  executeVoiceEnforcementEvent,
} = require("../staff/voice_enforcement");
const { deleteActiveVoiceSessionsForRoom } = require("../livekit/sessions");
const {
  FirestoreVoiceAchievementStore,
  SKIPPED_UNBOUND_RTC_NAME,
  createLiveKitAchievementWebhookHandler,
  sessionDocumentId,
} = require("../achievements/livekit_http");

const db = getFirestore();
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
// Every room this suite creates is removed afterwards: other suites on the
// same emulator project list live rooms globally, and a leftover live room
// here would crowd their bounded listings.
const createdRooms = new Set();
after(async () => {
  for (const roomId of createdRooms) {
    const participants = await db.collection(`rooms/${roomId}/participants`).listDocuments();
    await Promise.all(participants.map((reference) => reference.delete()));
    await db.doc(`rooms/${roomId}`).delete();
  }
});
const API_KEY = "livekit-rtc-consumers-key";
const API_SECRET = "livekit-rtc-consumers-secret-at-least-32-chars";
const BASE_MS = Date.parse("2026-09-11T09:00:00.000Z");
const BASE_SECONDS = BASE_MS / 1000;
const UNKNOWN_SRV_NAME = `srv_${"0".repeat(40)}`;

/* -------------------------------------------------------------------------
 * V1 graph through the reviewed factories, on the consumers' own database
 * ---------------------------------------------------------------------- */

async function fixture() {
  const uid = `rtc-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "RTC owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "RTC consumers fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const channel = (await db.collection(`clubs/${root.serverId}/channels`)
    .where("kind", "==", "voice").get()).docs[0];
  const roomId = channel.data().roomId;
  createdRooms.add(roomId);
  // Isolated emulator fixture, not an activation function: created graphs
  // stay held by default, exactly as in the reviewed session suite.
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  await db.doc(`rooms/${roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  const calls = { revoked: [], ended: [] };
  let endHook = null;
  const livekit = {
    assertSupported() { return "wss://test-fixture.livekit.cloud"; },
    async mintToken(value) {
      const token = `test-only-token-${randomUUID()}`;
      return { serverUrl: "wss://test-fixture.livekit.cloud", participantToken: token, token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid,
        participantName: value.participantName, expiresAtMillis: nowMs + 300_000,
        permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources,
        serverId: value.binding.serverId, channelId: value.binding.channelId,
        roomId: value.binding.roomId, sessionId: value.binding.sessionId, sessionRole: value.sessionRole };
    },
    async revokeParticipant(roomName, userId) {
      calls.revoked.push({ roomName, userId });
      return { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 };
    },
    async endRoom(roomName) {
      calls.ended.push(roomName);
      if (endHook) await endHook(roomName);
      return {};
    },
  };
  const service = createServerSessionService({ ...dependencies, livekit });
  const control = createServerSessionControlService({ ...dependencies, livekit });
  const target = { serverId: root.serverId, channelId: channel.id };
  return {
    uid, serverId: root.serverId, channelId: channel.id, roomId, calls, control,
    advance: (ms) => { nowMs += ms; },
    onEnd: (hook) => { endHook = hook; },
    rtcName: (sessionId) => canonicalLiveKitRoomName(root.serverId, channel.id, sessionId),
    start: () => service.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() })),
    token: (sessionId, actor = uid) =>
      service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    end: (sessionId, actor = uid) =>
      service.endServerChannelSessionV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    member: async (role = "member") => {
      const userId = `rtc-member-${randomUUID()}`;
      await db.doc(`users/${userId}`).set({ displayName: "RTC member", status: "active" });
      await db.doc(`clubs/${root.serverId}/members/${userId}`).set({ userId, role, authorizationRevision: 1 });
      return userId;
    },
    // Drains a generation whose eager end page was interrupted, the way the
    // held worker would on its next invocations.
    drain: async (operationId) => {
      for (let attempt = 0; attempt < 4; attempt += 1) {
        const outcome = await control.processServerSessionEndPage({ operationId });
        if (!outcome.cleanupPending) return outcome;
      }
      throw new Error("The end generation did not drain within four passes.");
    },
  };
}

async function seedLegacyRoom(uid, { hostId = `rtc-legacy-host-${randomUUID()}` } = {}) {
  const roomId = `rtc-legacy-room-${randomUUID()}`;
  createdRooms.add(roomId);
  await Promise.all([
    db.doc(`rooms/${roomId}`).set({
      status: "active", isLive: true, roomType: "community", visibility: "public", hostId, clubId: null,
    }),
    db.doc(`rooms/${roomId}/participants/${uid}`).set({ userId: uid, role: "speaker" }),
    db.doc(`users/${uid}`).set({ displayName: "Legacy voice user", status: "active" }, { merge: true }),
  ]);
  return roomId;
}

async function queueEnforcement(targetUid) {
  const batch = db.batch();
  const reference = enqueueVoiceEnforcement(batch, {
    targetUid, type: EVENT_TYPES.COMMUNICATION_MUTE,
    requestedBy: "rtc-consumers-moderator", source: "servers_rtc_consumers.test",
  });
  batch.set(db.doc(`restrictions/${targetUid}`), {
    type: "communicationMute", expiresAt: null, voiceEnforcementEventId: reference.id,
  });
  await batch.commit();
  return db.collection(EVENT_COLLECTION).doc(reference.id).get();
}

const mirrorRef = (uid, roomId) => db.doc(`activeVoiceSessions/${uid}/rooms/${roomId}`);

/* -------------------------------------------------------------------------
 * Signed webhook deliveries, exactly as the existing achievement suites sign
 * ---------------------------------------------------------------------- */

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

async function signedAuthorization(body) {
  const token = new AccessToken(API_KEY, API_SECRET, { ttl: 300 });
  token.sha256 = createHash("sha256").update(body).digest("base64");
  return token.toJwt();
}

function webhookHarness() {
  let currentNowMs = BASE_MS;
  const store = new FirestoreVoiceAchievementStore({ db });
  const handler = createLiveKitAchievementWebhookHandler({
    apiKeyProvider: () => API_KEY, apiSecretProvider: () => API_SECRET, store, now: () => currentNowMs,
  });
  return {
    store,
    async deliver(body) {
      const createdAt = JSON.parse(body)?.created_at;
      if (Number.isFinite(createdAt)) currentNowMs = createdAt * 1000;
      const recorded = { statusCode: null, body: null, headers: {} };
      const response = {
        set(name, value) { recorded.headers[name] = value; return response; },
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

/* ---------------------------------------------------------------------- */

describe("rtc binding resolver", { timeout: 60_000 }, () => {
  test("a legacy room, including an unknown id, keeps its id as the namespace", async () => {
    const uid = `rtc-legacy-user-${randomUUID()}`;
    const roomId = await seedLegacyRoom(uid);
    const binding = await resolveRtcBindingForRoom({ db, roomId });
    assert.equal(binding.kind, RTC_BINDING_KINDS.LEGACY);
    assert.equal(binding.bound, true);
    assert.equal(binding.livekitRoomName, roomId);
    const ghost = await resolveRtcBindingForRoom({ db, roomId: `rtc-ghost-${randomUUID()}` });
    assert.equal(ghost.kind, RTC_BINDING_KINDS.LEGACY);
    assert.equal(ghost.bound, true);
    const byName = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: roomId });
    assert.equal(byName.kind, RTC_BINDING_KINDS.LEGACY);
    assert.equal(byName.livekitRoomName, roomId);
  });

  test("a V1 anchor binds only its live or ending generation, never the anchor id", async () => {
    const f = await fixture();
    const idle = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(idle.kind, RTC_BINDING_KINDS.V1);
    assert.equal(idle.bound, false);
    assert.equal(idle.reason, RTC_BINDING_REASONS.NO_ACTIVE_SESSION);

    const { sessionId } = await f.start();
    const live = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(live.bound, true);
    assert.equal(live.kind, RTC_BINDING_KINDS.V1);
    assert.equal(live.status, "live");
    assert.equal(live.sessionId, sessionId);
    assert.equal(live.livekitRoomName, f.rtcName(sessionId));
    assert.notEqual(live.livekitRoomName, f.roomId);
    assert.equal(live.startedById, f.uid);
    assert.deepEqual(live.anchor, { roomId: f.roomId, serverId: f.serverId, channelId: f.channelId });

    f.onEnd(() => { throw Object.assign(new Error("controlled provider outage"), { code: "unavailable" }); });
    const receipt = await f.end(sessionId);
    assert.equal(receipt.status, "ending");
    const ending = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(ending.bound, true);
    assert.equal(ending.status, "ending");
    assert.equal(ending.livekitRoomName, f.rtcName(sessionId));

    f.onEnd(null);
    await f.drain(receipt.operationId);
    const ended = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(ended.bound, false);
    assert.equal(ended.reason, RTC_BINDING_REASONS.NO_ACTIVE_SESSION);
    const byName = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: f.rtcName(sessionId) });
    assert.equal(byName.bound, false);
    assert.equal(byName.reason, RTC_BINDING_REASONS.SESSION_NOT_LIVE);
    assert.equal(byName.retained.roomId, f.roomId, "an ended generation stays attributable to its anchor");
    assert.equal(byName.retained.sessionId, sessionId);
  });

  test("a malformed versioned anchor is never treated as a legacy room", async () => {
    const roomId = `rtc-malformed-${randomUUID()}`;
    createdRooms.add(roomId);
    await db.doc(`rooms/${roomId}`).set({ serverSchemaVersion: 2, serverId: "srv", clubId: "srv", channelId: "ch" });
    const binding = await resolveRtcBindingForRoom({ db, roomId });
    assert.equal(binding.kind, RTC_BINDING_KINDS.V1);
    assert.equal(binding.bound, false);
    assert.equal(binding.reason, RTC_BINDING_REASONS.MALFORMED_ANCHOR);
  });

  test("a srv_ name resolves through a real collectionGroup query with reciprocal proof", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const name = f.rtcName(sessionId);

    // ADR-007: the query itself, not a point read, is the evidence.
    const proof = await db.collectionGroup("channelSessions").where("livekitRoomName", "==", name).limit(2).get();
    assert.equal(proof.size, 1);
    assert.equal(proof.docs[0].ref.path, `clubs/${f.serverId}/channels/${f.channelId}/channelSessions/${sessionId}`);

    const bound = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name });
    assert.equal(bound.bound, true);
    assert.deepEqual(
      { roomId: bound.roomId, serverId: bound.serverId, channelId: bound.channelId, sessionId: bound.sessionId },
      { roomId: f.roomId, serverId: f.serverId, channelId: f.channelId, sessionId },
    );

    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: UNKNOWN_SRV_NAME })).reason,
      RTC_BINDING_REASONS.UNKNOWN_NAME);
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: "srv_not-a-digest" })).reason,
      RTC_BINDING_REASONS.MALFORMED_NAME);

    // A forged session document under another path that claims this name
    // makes the name ambiguous; a lone forgery fails its own derivation.
    const forgedPath = `clubs/rtc-forged-${randomUUID()}/channels/forged/channelSessions/forged`;
    await db.doc(forgedPath).set({ ...proof.docs[0].data() });
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name })).reason,
      RTC_BINDING_REASONS.AMBIGUOUS_NAME);
    await db.doc(forgedPath).delete();
    const loneName = canonicalLiveKitRoomName("rtc-other-server", "rtc-other-channel", "rtc-other-session");
    const lonePath = `clubs/rtc-lone-${randomUUID()}/channels/lone/channelSessions/lone`;
    await db.doc(lonePath).set({ ...proof.docs[0].data(), livekitRoomName: loneName });
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: loneName })).reason,
      RTC_BINDING_REASONS.SESSION_MISMATCH);
    await db.doc(lonePath).delete();
  });
});

describe("staff voice enforcement", { timeout: 60_000 }, () => {
  test("a V1 anchor is revoked through its live srv_ name; legacy rooms are unchanged", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const target = await f.member();
    await f.token(sessionId, target);
    const legacyRoomId = await seedLegacyRoom(target);
    const ghostRoomId = `rtc-ghost-livekit-${randomUUID()}`;
    const srvName = f.rtcName(sessionId);
    assert.equal((await mirrorRef(target, f.roomId).get()).data().livekitRoomName, srvName);

    const event = await queueEnforcement(target);
    const revoked = [];
    const result = await executeVoiceEnforcementEvent(event, {
      async findParticipantRooms(identity) {
        assert.equal(identity, target);
        return [legacyRoomId, srvName, ghostRoomId];
      },
      async revokeParticipant(roomName, identity) {
        assert.equal(identity, target);
        revoked.push(roomName);
      },
    });
    assert.equal(result.completed, true);
    assert.deepEqual(new Set(revoked), new Set([legacyRoomId, srvName, ghostRoomId]));
    assert.equal(revoked.length, 3, "one provider call per resolved target, srv_ deduplicated across sources");
    assert.ok(!revoked.includes(f.roomId), "the anchor room id is never sent to the provider");
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, false, "the bound generation's mirror is cleared");
    assert.equal((await mirrorRef(target, legacyRoomId).get()).exists, false);
    const stored = (await event.ref.get()).data();
    assert.equal(stored.status, "completed");
    assert.equal(stored.roomsRevoked, 3);
    assert.equal(stored.roomsDiscovered, 4);
    assert.equal(stored.roomsSkipped, 0);
    assert.deepEqual(stored.skippedBindings, []);
  });

  // Review finding P1-1 changed this contract: the author's original version
  // pinned that an unbound provider-reported srv_ name is skipped. LiveKit's
  // own report is the pre-V1 safety net, so it is now always revoked; only
  // the Firestore-derived anchor candidate keeps the fail-closed skip.
  test("an anchor without a live generation is skipped; a provider-reported name is still revoked", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const target = await f.member();
    await f.token(sessionId, target);
    const staleMirror = (await mirrorRef(target, f.roomId).get()).data();
    const receipt = await f.end(sessionId);
    assert.equal(receipt.status, "ended");
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, false);
    // A mirror the end worker lost the ACK for: same generation, now ended.
    await mirrorRef(target, f.roomId).set(staleMirror);
    const endedName = f.rtcName(sessionId);

    const event = await queueEnforcement(target);
    const revoked = [];
    const result = await executeVoiceEnforcementEvent(event, {
      async findParticipantRooms() { return [UNKNOWN_SRV_NAME, endedName]; },
      async revokeParticipant(roomName) { revoked.push(roomName); },
    });
    assert.equal(result.completed, true);
    assert.deepEqual(new Set(revoked), new Set([UNKNOWN_SRV_NAME, endedName]),
      "every provider-reported room is revoked, bound or not");
    assert.ok(!revoked.includes(f.roomId), "the anchor id is never sent to the provider");
    assert.equal(result.roomsSkipped, 1);
    assert.equal(result.providerRoomsUnbound, 2);
    const stored = (await event.ref.get()).data();
    assert.equal(stored.status, "completed");
    assert.equal(stored.roomsRevoked, 2);
    assert.deepEqual(stored.skippedBindings, [
      { target: f.roomId, reason: RTC_BINDING_REASONS.NO_ACTIVE_SESSION },
    ]);
    assert.deepEqual(new Set(stored.unboundProviderRooms.map((entry) => JSON.stringify(entry))), new Set([
      JSON.stringify({ target: UNKNOWN_SRV_NAME, reason: RTC_BINDING_REASONS.UNKNOWN_NAME }),
      JSON.stringify({ target: endedName, reason: RTC_BINDING_REASONS.SESSION_NOT_LIVE }),
    ]));
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, true,
      "no mirror is cleared on the strength of a binding that did not prove out");
  });

  test("an unbound live generation keeps the event retrying until it is revoked", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const target = await f.member();
    await f.token(sessionId, target);
    const srvName = f.rtcName(sessionId);
    const anchorRef = db.doc(`rooms/${f.roomId}`);
    const intact = (await anchorRef.get()).data();
    // A legacy-shaped liveness write onto the anchor: the channelSession is
    // still live, but the graph no longer proves it.
    await anchorRef.update({ isLive: false });
    const unbound = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(unbound.reason, RTC_BINDING_REASONS.LIVENESS_MISMATCH);
    assert.equal(unbound.retained.status, "live");

    const event = await queueEnforcement(target);
    const revoked = [];
    const control = (rooms) => ({
      async findParticipantRooms() { return rooms; },
      async revokeParticipant(roomName) { revoked.push(roomName); },
    });
    await assert.rejects(() => executeVoiceEnforcementEvent(event, control([])),
      (error) => error.code === "unbound-live-generation");
    assert.deepEqual(revoked, [], "a Firestore-derived name is never guessed");
    const retrying = (await event.ref.get()).data();
    assert.equal(retrying.status, "retrying");
    assert.equal(retrying.lastErrorCode, "unbound-live-generation");
    assert.deepEqual(retrying.skippedBindings, [{ target: f.roomId, reason: RTC_BINDING_REASONS.LIVENESS_MISMATCH }]);
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, true);

    // The provider reports the identity in that generation: it is revoked by
    // its provider name, the owed generation is covered and the event ends.
    const covered = await executeVoiceEnforcementEvent(event, control([srvName]));
    assert.equal(covered.completed, true);
    assert.deepEqual(revoked, [srvName]);
    const stored = (await event.ref.get()).data();
    assert.equal(stored.status, "completed");
    assert.equal(stored.roomsRevoked, 1);
    assert.deepEqual(stored.unboundProviderRooms, [{ target: srvName, reason: RTC_BINDING_REASONS.LIVENESS_MISMATCH }]);
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, true,
      "an unbound revocation never clears the generation's mirror");

    // Repaired liveness: a fresh sanction binds again and clears the mirror.
    await anchorRef.update({ isLive: intact.isLive });
    const again = await queueEnforcement(target);
    const repaired = await executeVoiceEnforcementEvent(again, control([]));
    assert.equal(repaired.completed, true);
    assert.deepEqual(revoked, [srvName, srvName]);
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, false);
  });

  test("the unbound-live-generation retry has a ceiling: the last budgeted attempt writes needsReconciliation instead of rethrowing", async () => {
    // F4 (ADR-179). The stalled state below is a property of the Firestore
    // graph, not of the provider, so no redelivery can change it; without a
    // ceiling the retry: true trigger would re-run findParticipantRooms (one
    // listRooms plus one getParticipant per room) until Eventarc gave up.
    const f = await fixture();
    const { sessionId } = await f.start();
    const target = await f.member();
    await f.token(sessionId, target);
    await db.doc(`rooms/${f.roomId}`).update({ isLive: false });
    const event = await queueEnforcement(target);
    const revoked = [];
    const control = {
      async findParticipantRooms() { return []; },
      async revokeParticipant(roomName) { revoked.push(roomName); },
    };
    // One attempt below the ceiling is still an ordinary retry.
    await event.ref.update({ attemptCount: MAX_UNBOUND_GENERATION_ATTEMPTS - 2 });
    await assert.rejects(() => executeVoiceEnforcementEvent(event, control),
      (error) => error.code === UNBOUND_LIVE_GENERATION);
    let stored = (await event.ref.get()).data();
    assert.equal(stored.status, "retrying");
    assert.equal(stored.attemptCount, MAX_UNBOUND_GENERATION_ATTEMPTS - 1);
    // The ceiling attempt is terminal: it resolves, it does not throw.
    const terminal = await executeVoiceEnforcementEvent(event, control);
    assert.equal(terminal.completed, false);
    assert.equal(terminal.needsReconciliation, true);
    assert.equal(terminal.attemptCount, MAX_UNBOUND_GENERATION_ATTEMPTS);
    assert.equal(terminal.roomsSkipped, 1);
    stored = (await event.ref.get()).data();
    assert.equal(stored.status, NEEDS_RECONCILIATION);
    assert.equal(stored.lastErrorCode, UNBOUND_LIVE_GENERATION);
    assert.equal(stored.attemptCount, MAX_UNBOUND_GENERATION_ATTEMPTS);
    assert.ok(stored.processedAt, "a terminal event is stamped like every other terminal state");
    assert.deepEqual(stored.skippedBindings, [{ target: f.roomId, reason: RTC_BINDING_REASONS.LIVENESS_MISMATCH }]);
    assert.deepEqual(revoked, [], "a Firestore-derived name is never guessed, not even on the terminal attempt");
    // The sanction itself is untouched and still names this event.
    assert.equal((await db.doc(`restrictions/${target}`).get()).data().voiceEnforcementEventId, event.id);
    assert.equal((await mirrorRef(target, f.roomId).get()).exists, true);
    // A redelivery of the terminal event is a read-only no-op.
    let calls = 0;
    const replay = await executeVoiceEnforcementEvent(event, {
      async findParticipantRooms() { calls += 1; return []; },
      async revokeParticipant() { calls += 1; },
    });
    assert.deepEqual(replay, { skipped: true, reason: NEEDS_RECONCILIATION });
    assert.equal(calls, 0);

    // Only that one code is ceilinged. A provider outage on the last budgeted
    // attempt of a bound generation still rethrows, because an outage is
    // transient and the sanctioned identity may still be connected.
    const g = await fixture();
    const live = await g.start();
    const other = await g.member();
    await g.token(live.sessionId, other);
    const outage = await queueEnforcement(other);
    await outage.ref.update({ attemptCount: MAX_UNBOUND_GENERATION_ATTEMPTS - 1 });
    await assert.rejects(() => executeVoiceEnforcementEvent(outage, {
      async findParticipantRooms() { return [g.rtcName(live.sessionId)]; },
      async revokeParticipant() { throw Object.assign(new Error("controlled outage"), { code: "unavailable" }); },
    }), /controlled outage/u);
    const retrying = (await outage.ref.get()).data();
    assert.equal(retrying.status, "retrying");
    assert.equal(retrying.lastErrorCode, "unavailable");
    assert.equal(retrying.attemptCount, MAX_UNBOUND_GENERATION_ATTEMPTS);
  });

  test("a resolver without a caller transaction reads through a read-only one", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const options = [];
    const spy = {
      doc: (path) => db.doc(path),
      collectionGroup: (name) => db.collectionGroup(name),
      runTransaction: (work, transactionOptions) => {
        options.push(transactionOptions);
        return db.runTransaction(work, transactionOptions);
      },
    };
    const byRoom = await resolveRtcBindingForRoom({ db: spy, roomId: f.roomId });
    const byName = await resolveRtcBindingForLiveKitRoom({ db: spy, livekitRoomName: f.rtcName(sessionId) });
    assert.equal(byRoom.bound, true);
    assert.equal(byName.bound, true);
    assert.deepEqual(byRoom.pointers, [sessionId]);
    assert.deepEqual(options, [{ readOnly: true }, { readOnly: true }]);
    // Names that need no read never open a transaction.
    await resolveRtcBindingForLiveKitRoom({ db: spy, livekitRoomName: "legacy-room-name" });
    await resolveRtcBindingForLiveKitRoom({ db: spy, livekitRoomName: "srv_not-a-digest" });
    assert.equal(options.length, 2);
  });
});

describe("legacy active-session mirror cleanup", { timeout: 60_000 }, () => {
  test("a legacy room is cleared blindly by id, explicit and swept mirrors alike", async () => {
    const withRow = `rtc-cleanup-a-${randomUUID()}`;
    const sweptOnly = `rtc-cleanup-b-${randomUUID()}`;
    const roomId = await seedLegacyRoom(withRow);
    for (const uid of [withRow, sweptOnly]) {
      await mirrorRef(uid, roomId).set({ userId: uid, roomId, participantIdentity: uid,
        expiresAt: Timestamp.fromMillis(Date.now() + 300_000) });
    }
    await deleteActiveVoiceSessionsForRoom(roomId, [withRow]);
    assert.equal((await mirrorRef(withRow, roomId).get()).exists, false);
    assert.equal((await mirrorRef(sweptOnly, roomId).get()).exists, false);
  });

  test("a V1 anchor cleanup is generation-fenced", async () => {
    const f = await fixture();
    const first = (await f.start()).sessionId;
    const older = await f.member();
    await f.token(first, older);
    const staleMirror = (await mirrorRef(older, f.roomId).get()).data();
    assert.equal((await f.end(first)).status, "ended");
    await mirrorRef(older, f.roomId).set(staleMirror);

    const second = (await f.start()).sessionId;
    assert.notEqual(second, first);
    const newer = await f.member();
    await f.token(second, newer);
    const liveMirror = (await mirrorRef(newer, f.roomId).get()).data();
    assert.equal(liveMirror.sessionId, second);

    // A cleanup for the newer generation never clears it (its own end worker
    // does) and never clears a different generation than it names.
    await deleteActiveVoiceSessionsForRoom(f.roomId, [older, newer], { sessionId: second });
    assert.equal((await mirrorRef(older, f.roomId).get()).exists, true);
    assert.equal((await mirrorRef(newer, f.roomId).get()).exists, true);

    // A cleanup carrying the older generation clears only that generation.
    await deleteActiveVoiceSessionsForRoom(f.roomId, [older, newer], { sessionId: first });
    assert.equal((await mirrorRef(older, f.roomId).get()).exists, false);
    assert.equal((await mirrorRef(newer, f.roomId).get()).exists, true);

    // A cleanup keyed on the room id alone clears stale generations only.
    await mirrorRef(older, f.roomId).set(staleMirror);
    await deleteActiveVoiceSessionsForRoom(f.roomId, [older, newer]);
    assert.equal((await mirrorRef(older, f.roomId).get()).exists, false);
    assert.equal((await mirrorRef(newer, f.roomId).get()).exists, true);

    const anchor = (await db.doc(`rooms/${f.roomId}`).get()).data();
    assert.equal(anchor.isLive, true);
    assert.equal(anchor.voiceSessionId, second);
    assert.equal(anchor.livekitRoomName, f.rtcName(second));
    assert.equal((await db.doc(`clubs/${f.serverId}/channels/${f.channelId}`).get()).data().activeSessionId, second);
  });

  test("an unbound anchor with a live generation is a no-op; a retained pointer needs its generation named", async () => {
    const f = await fixture();
    const sessionId = (await f.start()).sessionId;
    const member = await f.member();
    await f.token(sessionId, member);
    const legacyShaped = `rtc-cleanup-legacy-${randomUUID()}`;
    await mirrorRef(legacyShaped, f.roomId).set({ userId: legacyShaped, roomId: f.roomId,
      participantIdentity: legacyShaped, expiresAt: Timestamp.fromMillis(Date.now() + 300_000) });
    const everyone = [member, legacyShaped];
    const anchorRef = db.doc(`rooms/${f.roomId}`);

    // A legacy liveness write lands on the anchor while its generation is
    // live: the graph stops proving liveness, the generation is retained.
    await anchorRef.update({ isLive: false });
    const unboundLive = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(unboundLive.reason, RTC_BINDING_REASONS.LIVENESS_MISMATCH);
    assert.equal(unboundLive.retained.status, "live");
    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone);
    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone, { sessionId });
    assert.equal((await mirrorRef(member, f.roomId).get()).exists, true, "the live generation's mirror is kept");
    assert.equal((await mirrorRef(legacyShaped, f.roomId).get()).exists, true, "a no-op deletes nothing at all");
    await anchorRef.update({ isLive: true });

    // A pointer naming a generation that does not prove out (a tampered host
    // makes it a session mismatch with nothing retained): a room-id cleanup
    // keeps its mirror, only a cleanup naming that generation clears it.
    const sessionRef = db.doc(`clubs/${f.serverId}/channels/${f.channelId}/channelSessions/${sessionId}`);
    const { startedById } = (await sessionRef.get()).data();
    await sessionRef.update({ startedById: null });
    const mismatch = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(mismatch.reason, RTC_BINDING_REASONS.SESSION_MISMATCH);
    assert.equal(mismatch.retained, null);
    assert.deepEqual(mismatch.pointers, [sessionId]);
    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone);
    assert.equal((await mirrorRef(member, f.roomId).get()).exists, true,
      "a room-id cleanup never clears the generation the anchor still names");
    assert.equal((await mirrorRef(legacyShaped, f.roomId).get()).exists, false,
      "legacy-shaped mirrors still follow the legacy rule");
    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone, { sessionId });
    assert.equal((await mirrorRef(member, f.roomId).get()).exists, false, "the named generation is cleared");
    await sessionRef.update({ startedById });
  });
});

describe("achievement webhook", { timeout: 60_000 }, () => {
  test("srv_ events are attributed to the anchor like legacy events; unbound names are acknowledged", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const srvName = f.rtcName(sessionId);
    const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
    const guest = await f.member();
    await f.token(sessionId, guest);
    await f.token(sessionId);
    const { deliver } = webhookHarness();

    const guestJoin = await deliver(participantBody("participant_joined", BASE_SECONDS,
      { roomName: srvName, roomSid, participantSid: "PA_guest", identity: guest, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(guestJoin.statusCode, 202);
    assert.equal(guestJoin.body.outcome, "opened");
    const guestDoc = (await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_guest")}`).get()).data();
    assert.equal(guestDoc.roomId, f.roomId, "attributed to the anchor room, not the provider name");
    assert.equal(guestDoc.livekitRoomName, srvName);
    assert.deepEqual(guestDoc.rtcBinding, { kind: "v1", serverId: f.serverId, channelId: f.channelId, sessionId });
    assert.equal(guestDoc.isHost, false);

    const hostJoin = await deliver(participantBody("participant_joined", BASE_SECONDS,
      { roomName: srvName, roomSid, participantSid: "PA_host", identity: f.uid, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(hostJoin.body.outcome, "opened");
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_host")}`).get()).data().isHost,
      true, "the generation's starter is its host");

    const guestLeft = await deliver(participantBody("participant_left", BASE_SECONDS + 600,
      { roomName: srvName, roomSid, participantSid: "PA_guest", identity: guest, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(guestLeft.statusCode, 202);
    assert.equal(guestLeft.body.outcome, "closed");
    const closedGuest = (await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_guest")}`).get()).data();
    assert.equal(closedGuest.status, "closed");
    assert.equal(closedGuest.creditedVoiceSeconds, 600);
    assert.equal(closedGuest.outboxIds.length, 1);
    const outbox = (await db.doc(`achievementOutbox/${closedGuest.outboxIds[0]}`).get()).data();
    assert.equal(outbox.event.beneficiaryId, guest);
    assert.equal(outbox.event.metric, "voiceSeconds");
    assert.equal(outbox.event.delta, 600);

    const finished = await deliver(roomFinishedBody(BASE_SECONDS + 900, { roomName: srvName, roomSid }));
    assert.equal(finished.statusCode, 202);
    assert.equal(finished.body.outcome, "room-closed");
    const closedHost = (await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_host")}`).get()).data();
    assert.equal(closedHost.status, "closed");
    assert.equal(closedHost.creditedVoiceSeconds, 900);
    assert.equal(closedHost.creditedHostSeconds, 900);

    // An unbound srv_ name: acknowledged, logged, no document, no attribution.
    const unknownSid = `RM_${randomUUID().replaceAll("-", "")}`;
    const unknownJoin = await deliver(participantBody("participant_joined", BASE_SECONDS + 1000,
      { roomName: UNKNOWN_SRV_NAME, roomSid: unknownSid, participantSid: "PA_x", identity: guest, joinedAtSeconds: BASE_SECONDS + 1000 }));
    assert.equal(unknownJoin.statusCode, 202);
    assert.equal(unknownJoin.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(unknownSid, "PA_x")}`).get()).exists, false);
    const unknownClose = await deliver(participantBody("participant_left", BASE_SECONDS + 1100,
      { roomName: UNKNOWN_SRV_NAME, roomSid: unknownSid, participantSid: "PA_x", identity: guest, joinedAtSeconds: BASE_SECONDS + 1000 }));
    assert.equal(unknownClose.statusCode, 202);
    assert.equal(unknownClose.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(unknownSid, "PA_x")}`).get()).exists, false);

    // A close that outruns its join after the generation ended still binds
    // to the anchor by structural proof, the way a legacy close only needs
    // the room to exist.
    assert.equal((await f.end(sessionId)).status, "ended");
    const lateClose = await deliver(participantBody("participant_left", BASE_SECONDS + 1200,
      { roomName: srvName, roomSid, participantSid: "PA_late", identity: guest, joinedAtSeconds: BASE_SECONDS + 1100 }));
    assert.equal(lateClose.statusCode, 202);
    assert.equal(lateClose.body.outcome, "awaiting-join");
    const awaiting = (await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_late")}`).get()).data();
    assert.equal(awaiting.roomId, f.roomId);
    assert.equal(awaiting.livekitRoomName, srvName);
    assert.deepEqual(awaiting.rtcBinding, { kind: "v1", serverId: f.serverId, channelId: f.channelId, sessionId });
    // A join for the ended generation is acknowledged without side effects.
    const lateJoin = await deliver(participantBody("participant_joined", BASE_SECONDS + 1300,
      { roomName: srvName, roomSid, participantSid: "PA_late", identity: guest, joinedAtSeconds: BASE_SECONDS + 1100 }));
    assert.equal(lateJoin.statusCode, 202);
    assert.equal(lateJoin.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_late")}`).get()).data().status,
      "awaitingJoin");
  });

  test("a participant row bound to another generation is not credited", async () => {
    const f = await fixture();
    const first = (await f.start()).sessionId;
    const guest = await f.member();
    await f.token(first, guest);
    const staleParticipant = (await db.doc(`rooms/${f.roomId}/participants/${guest}`).get()).data();
    assert.equal((await f.end(first)).status, "ended");
    const second = (await f.start()).sessionId;
    // The old row survives (a lost cleanup ACK) while the new generation is live.
    await db.doc(`rooms/${f.roomId}/participants/${guest}`).set(staleParticipant);
    const { deliver } = webhookHarness();
    const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
    const join = await deliver(participantBody("participant_joined", BASE_SECONDS,
      { roomName: f.rtcName(second), roomSid, participantSid: "PA_stale", identity: guest, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(join.statusCode, 400);
    assert.equal(join.body.error, "invalid-source");
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_stale")}`).get()).exists, false);
  });

  test("a legacy-namespace event naming a V1 anchor id is rejected, never attributed", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    // The owner's V1 participant row carries the role `host`, which the
    // legacy vocabulary also accepts: only the versioned anchor itself
    // distinguishes this event from a genuine legacy join.
    await f.token(sessionId);
    const { deliver } = webhookHarness();
    const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
    const join = await deliver(participantBody("participant_joined", BASE_SECONDS,
      { roomName: f.roomId, roomSid, participantSid: "PA_anchor", identity: f.uid, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(join.statusCode, 400);
    assert.equal(join.body.error, "invalid-source");
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_anchor")}`).get()).exists,
      false);

    const close = await deliver(participantBody("participant_left", BASE_SECONDS + 60,
      { roomName: f.roomId, roomSid, participantSid: "PA_anchor", identity: f.uid, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(close.statusCode, 202);
    assert.equal(close.body.outcome, "skipped:unknown-session");
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_anchor")}`).get()).exists,
      false, "no awaiting-join row is minted under a versioned anchor");

    // The same generation, through its own srv_ name, is credited as ever.
    const boundSid = `RM_${randomUUID().replaceAll("-", "")}`;
    const bound = await deliver(participantBody("participant_joined", BASE_SECONDS + 120,
      { roomName: f.rtcName(sessionId), roomSid: boundSid, participantSid: "PA_srv", identity: f.uid,
        joinedAtSeconds: BASE_SECONDS + 120 }));
    assert.equal(bound.statusCode, 202);
    assert.equal(bound.body.outcome, "opened");
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(boundSid, "PA_srv")}`).get()).data().roomId,
      f.roomId);
  });

  test("legacy room events are stored exactly as before", async () => {
    const uid = `rtc-legacy-voice-${randomUUID()}`;
    const roomId = await seedLegacyRoom(uid);
    const roomSid = `RM_${randomUUID().replaceAll("-", "")}`;
    const { deliver } = webhookHarness();
    const join = await deliver(participantBody("participant_joined", BASE_SECONDS,
      { roomName: roomId, roomSid, participantSid: "PA_legacy", identity: uid, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(join.statusCode, 202);
    assert.equal(join.body.outcome, "opened");
    const stored = (await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_legacy")}`).get()).data();
    assert.equal(stored.roomId, roomId);
    assert.equal(Object.hasOwn(stored, "livekitRoomName"), false);
    assert.equal(Object.hasOwn(stored, "rtcBinding"), false);
    const left = await deliver(participantBody("participant_left", BASE_SECONDS + 300,
      { roomName: roomId, roomSid, participantSid: "PA_legacy", identity: uid, joinedAtSeconds: BASE_SECONDS }));
    assert.equal(left.body.outcome, "closed");
    assert.equal((await db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, "PA_legacy")}`).get()).data()
      .creditedVoiceSeconds, 300);
  });
});

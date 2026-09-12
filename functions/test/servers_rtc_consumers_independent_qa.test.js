// Independent QA regressions for slice S3 (V1-aware global RTC consumers).
//
// Adversarial, deterministic cases the author's suite does not cover: multi-
// anchor identities, tampered liveness, three-generation cleanup fences,
// forged participant rows and session names, duplicate provider events, late
// room finishes, legacy ids inside the `srv_` namespace, the resolver under a
// Firestore transaction, forged collectionGroup matches and the audit caps.
// Fixture helpers are copied (not imported) from servers_rtc_consumers.test.js
// so this file never depends on the author's test internals.

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
// Every live room this suite creates is removed afterwards: other suites on
// the same emulator project list live rooms globally (staff_overview), and a
// leftover live room here would crowd their bounded listings.
const createdRooms = new Set();
after(async () => {
  for (const roomId of createdRooms) {
    const participants = await db.collection(`rooms/${roomId}/participants`).listDocuments();
    await Promise.all(participants.map((reference) => reference.delete()));
    await db.doc(`rooms/${roomId}`).delete();
  }
});
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const API_KEY = "livekit-rtc-qa-key";
const API_SECRET = "livekit-rtc-qa-secret-at-least-32-chars-long";
const BASE_MS = Date.parse("2026-09-11T12:00:00.000Z");
const BASE_SECONDS = BASE_MS / 1000;
const CLOSED_REASONS = new Set(Object.values(RTC_BINDING_REASONS));
const hex40 = (pair) => pair.repeat(20);
const newRoomSid = () => `RM_${randomUUID().replaceAll("-", "")}`;

/* ---------------------------------------------------------------- fixture */

async function fixture() {
  const uid = `qa-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "QA owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "QA fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const channel = (await db.collection(`clubs/${root.serverId}/channels`)
    .where("kind", "==", "voice").get()).docs[0];
  const roomId = channel.data().roomId;
  createdRooms.add(roomId);
  await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
  await db.doc(`rooms/${roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  const calls = { revoked: [], ended: [] };
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
    async endRoom(roomName) { calls.ended.push(roomName); return {}; },
  };
  const service = createServerSessionService({ ...dependencies, livekit });
  createServerSessionControlService({ ...dependencies, livekit });
  const target = { serverId: root.serverId, channelId: channel.id };
  const serverId = root.serverId;
  const channelId = channel.id;
  return {
    uid, serverId, channelId, roomId, calls,
    sessionPath: (sessionId) => `clubs/${serverId}/channels/${channelId}/channelSessions/${sessionId}`,
    rtcName: (sessionId) => canonicalLiveKitRoomName(serverId, channelId, sessionId),
    start: () => service.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() })),
    token: (sessionId, actor = uid) =>
      service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    end: (sessionId, actor = uid) =>
      service.endServerChannelSessionV1(request(actor, { ...target, sessionId, requestId: randomUUID() })),
    member: async (role = "member", userId = `qa-member-${randomUUID()}`) => {
      await db.doc(`users/${userId}`).set({ displayName: "QA member", status: "active" }, { merge: true });
      await db.doc(`clubs/${serverId}/members/${userId}`).set({ userId, role, authorizationRevision: 1 });
      return userId;
    },
  };
}

async function seedLegacyRoom(uid, { roomId = `qa-legacy-room-${randomUUID()}` } = {}) {
  const hostId = `qa-legacy-host-${randomUUID()}`;
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
    requestedBy: "qa-moderator", source: "servers_rtc_consumers_independent_qa.test",
  });
  batch.set(db.doc(`restrictions/${targetUid}`), {
    type: "communicationMute", expiresAt: null, voiceEnforcementEventId: reference.id,
  });
  await batch.commit();
  return db.collection(EVENT_COLLECTION).doc(reference.id).get();
}

async function enforce(targetUid, providerRooms) {
  const event = await queueEnforcement(targetUid);
  const revoked = [];
  const result = await executeVoiceEnforcementEvent(event, {
    async findParticipantRooms(identity) { assert.equal(identity, targetUid); return providerRooms; },
    async revokeParticipant(roomName, identity) { assert.equal(identity, targetUid); revoked.push(roomName); },
  });
  const stored = (await event.ref.get()).data();
  return { result, revoked, stored };
}

const mirrorRef = (uid, roomId) => db.doc(`activeVoiceSessions/${uid}/rooms/${roomId}`);
const exists = async (reference) => (await reference.get()).exists;
const achievementDoc = (roomSid, participantSid) =>
  db.doc(`achievementVoiceSessions/${sessionDocumentId(roomSid, participantSid)}`);

/* ---------------------------------------------------------------- webhook */

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
    async deliver(body) {
      const createdAt = JSON.parse(body)?.created_at;
      if (Number.isFinite(createdAt)) currentNowMs = createdAt * 1000;
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
    join: (f, { roomSid, participantSid, identity, name, at = BASE_SECONDS, joinedAt = BASE_SECONDS }) =>
      participantBody("participant_joined", at,
        { roomName: name, roomSid, participantSid, identity, joinedAtSeconds: joinedAt }),
    left: (f, { roomSid, participantSid, identity, name, at, joinedAt = BASE_SECONDS }) =>
      participantBody("participant_left", at,
        { roomName: name, roomSid, participantSid, identity, joinedAtSeconds: joinedAt }),
  };
}

/* ======================================================================== */

describe("independent QA: staff voice enforcement", { timeout: 120_000 }, () => {
  test("(a) one identity across a legacy room, a live generation and an ended generation with a re-created mirror",
    async () => {
      const live = await fixture();
      const ended = await fixture();
      const identity = `qa-multi-${randomUUID()}`;
      await live.member("member", identity);
      await ended.member("member", identity);
      const liveSession = (await live.start()).sessionId;
      const endedSession = (await ended.start()).sessionId;
      await live.token(liveSession, identity);
      await ended.token(endedSession, identity);
      const staleMirror = (await mirrorRef(identity, ended.roomId).get()).data();
      assert.equal(staleMirror.sessionId, endedSession);
      assert.equal((await ended.end(endedSession)).status, "ended");
      assert.equal(await exists(mirrorRef(identity, ended.roomId)), false, "the end worker clears its own mirror");
      await mirrorRef(identity, ended.roomId).set(staleMirror);
      const legacyRoomId = await seedLegacyRoom(identity);
      const srvLive = live.rtcName(liveSession);

      const { result, revoked, stored } = await enforce(identity, [legacyRoomId, srvLive]);
      assert.equal(result.completed, true);
      assert.deepEqual(revoked.slice().sort(), [legacyRoomId, srvLive].sort(),
        "exactly one legacy revoke and one srv_ revoke");
      assert.ok(!revoked.includes(live.roomId) && !revoked.includes(ended.roomId), "anchor ids never reach the provider");
      assert.ok(!revoked.includes(ended.rtcName(endedSession)), "the ended generation's name is never revoked");
      assert.equal(stored.status, "completed");
      assert.equal(stored.roomsRevoked, 2);
      assert.equal(stored.roomsDiscovered, 4, "live anchor, ended anchor, legacy room and the provider srv_ name");
      assert.equal(stored.roomsSkipped, 1);
      assert.deepEqual(stored.skippedBindings, [{ target: ended.roomId, reason: RTC_BINDING_REASONS.NO_ACTIVE_SESSION }]);
      assert.equal(await exists(mirrorRef(identity, live.roomId)), false, "the revoked live generation's mirror is cleared");
      assert.equal(await exists(mirrorRef(identity, ended.roomId)), true, "a skipped generation's mirror is left");
    });

  // Restated for the approved remedy (review-ledger "S3 RTC consumers", P1-1):
  // a room name the provider reports is ALWAYS revoked, bound or not, because
  // LiveKit reporting the identity inside a room is authority to disconnect
  // it; the binding only decides mirror cleanup. The fail-closed skip survives
  // for the ANCHOR-derived candidate, which is what this case pins now. Both
  // discovery sources still see the same tampered generation and neither may
  // clear anything on the strength of it.
  test("(b) a live channelSession whose anchor disagrees on liveness keeps the anchor candidate fail-closed while the provider-reported name is revoked",
    async () => {
      const f = await fixture();
      const { sessionId } = await f.start();
      const identity = await f.member();
      await f.token(sessionId, identity);
      const srvName = f.rtcName(sessionId);
      await db.doc(`rooms/${f.roomId}`).update({ voiceSessionId: `tampered-${randomUUID()}` });
      assert.equal((await db.doc(f.sessionPath(sessionId)).get()).data().status, "live");
      // Neither discovery source proves the generation out: the resolver's
      // verdict is identical by anchor id and by provider name.
      assert.equal((await resolveRtcBindingForRoom({ db, roomId: f.roomId })).reason,
        RTC_BINDING_REASONS.LIVENESS_MISMATCH);
      assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: srvName })).reason,
        RTC_BINDING_REASONS.LIVENESS_MISMATCH);

      // Anchor-derived candidate alone: still no provider call derived from
      // Firestore, and the skip is never a silent success.
      const anchorOnly = await queueEnforcement(identity);
      const anchorOnlyRevoked = [];
      await assert.rejects(
        () => executeVoiceEnforcementEvent(anchorOnly, {
          async findParticipantRooms() { return []; },
          async revokeParticipant(roomName) { anchorOnlyRevoked.push(roomName); },
        }),
        (error) => error.code === "unbound-live-generation",
      );
      assert.deepEqual(anchorOnlyRevoked, [], "no provider call on a liveness mismatch");
      const retrying = (await anchorOnly.ref.get()).data();
      assert.equal(retrying.status, "retrying");
      assert.equal(retrying.roomsRevoked, 0);
      assert.equal(retrying.roomsSkipped, 1);
      assert.deepEqual(retrying.skippedBindings,
        [{ target: f.roomId, reason: RTC_BINDING_REASONS.LIVENESS_MISMATCH }]);
      assert.equal(retrying.providerRoomsUnbound, 0);
      assert.deepEqual(retrying.unboundProviderRooms, []);
      assert.equal(await exists(mirrorRef(identity, f.roomId)), true, "nothing is cleared on a skip");

      // The provider reports the identity inside that very generation.
      const { result, revoked, stored } = await enforce(identity, [srvName]);
      assert.equal(result.completed, true, "the provider revocation covers the owed generation");
      assert.deepEqual(revoked, [srvName],
        "the provider-reported name is revoked despite the mismatch, and nothing else is called");
      assert.ok(!revoked.includes(f.roomId), "an anchor id is never sent to the provider");
      assert.equal(stored.roomsDiscovered, 2, "the anchor id and the provider name are separate candidates");
      assert.equal(stored.roomsRevoked, 1);
      assert.equal(stored.roomsSkipped, 1, "exactly the anchor-derived candidate is skipped");
      assert.deepEqual(stored.skippedBindings,
        [{ target: f.roomId, reason: RTC_BINDING_REASONS.LIVENESS_MISMATCH }]);
      assert.equal(stored.providerRoomsUnbound, 1);
      assert.deepEqual(stored.unboundProviderRooms,
        [{ target: srvName, reason: RTC_BINDING_REASONS.LIVENESS_MISMATCH }],
        "revoked, and audited as an unbound provider room rather than as a skip");
      assert.equal(stored.status, "completed");
      assert.equal(stored.lastErrorCode, null);
      assert.equal(await exists(mirrorRef(identity, f.roomId)), true,
        "a binding that did not prove out never clears a mirror, from either discovery source");
    });

  test("DEFECT D1: a provider room named after a V1 anchor id is deduplicated away by the anchor candidate",
    async () => {
      // Design (voice_enforcement.js, resolveRevocationTarget): a non-srv_ name
      // reported by LiveKit is a legacy-namespace room "regardless of any
      // anchor that shares the id". The candidate dedupe is keyed by value
      // only, so once the anchor id was resolved from the mirror, the same
      // string from the provider is never resolved as a provider room.
      const f = await fixture();
      const { sessionId } = await f.start();
      const identity = await f.member();
      await f.token(sessionId, identity);
      const srvName = f.rtcName(sessionId);
      const { result, revoked, stored } = await enforce(identity, [f.roomId]);
      assert.equal(result.completed, true);
      assert.ok(revoked.includes(srvName), "the live generation is revoked through its srv_ name");
      assert.ok(revoked.includes(f.roomId),
        "a legacy-namespace provider room that shares the anchor id must still be revoked by the LiveKit safety net");
      assert.equal(stored.roomsRevoked, 2);
    });

  // Restated for P1-1: 25 unknown provider-reported `srv_` names are all
  // revoked now, so the audit cap this case exists to pin moved from
  // `skippedBindings` to `unboundProviderRooms`. The cap itself is unchanged
  // (20 audited entries) and the exact total must still survive it.
  test("(g) audited unbound provider rooms are capped at 20 while the event revokes every one and keeps the exact count",
    async () => {
      const identity = `qa-capped-${randomUUID()}`;
      await db.doc(`users/${identity}`).set({ displayName: "Capped", status: "active" });
      const names = Array.from({ length: 25 }, (_, index) => `srv_${hex40(String(index).padStart(2, "0"))}`);
      assert.equal(new Set(names).size, 25);
      const { result, revoked, stored } = await enforce(identity, names);
      assert.equal(result.completed, true);
      assert.deepEqual(revoked.slice().sort(), names.slice().sort(),
        "every provider-reported name is revoked, none bound");
      assert.equal(revoked.length, 25, "exactly one provider call per name");
      assert.equal(stored.status, "completed");
      assert.equal(stored.roomsRevoked, 25);
      assert.equal(stored.roomsDiscovered, 25);
      // No anchor-derived candidate exists at all, so the skip audit stays
      // empty: a provider room is never recorded as an anchor skip.
      assert.equal(stored.roomsSkipped, 0);
      assert.deepEqual(stored.skippedBindings, []);
      assert.equal(result.providerRoomsUnbound, 25);
      assert.equal(stored.providerRoomsUnbound, 25, "the exact total is preserved past the cap");
      assert.equal(stored.unboundProviderRooms.length, 20, "the audited list stays bounded");
      assert.equal(new Set(stored.unboundProviderRooms.map((entry) => entry.target)).size, 20);
      for (const entry of stored.unboundProviderRooms) {
        assert.ok(names.includes(entry.target));
        assert.equal(entry.reason, RTC_BINDING_REASONS.UNKNOWN_NAME);
        assert.ok(CLOSED_REASONS.has(entry.reason), "audit reasons stay a closed set");
      }
      assert.equal(stored.lastErrorCode, null);
    });

  test("(d5) a legacy rooms/{srv_…} document resolves deterministically per discovery source", async () => {
    const identity = `qa-srv-legacy-${randomUUID()}`;
    const legacyId = `srv_${randomUUID().replaceAll("-", "")}00000000`;
    assert.match(legacyId, /^srv_[a-f0-9]{40}$/u);
    await seedLegacyRoom(identity, { roomId: legacyId });
    assert.equal((await resolveRtcBindingForRoom({ db, roomId: legacyId })).kind, RTC_BINDING_KINDS.LEGACY);
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: legacyId })).reason,
      RTC_BINDING_REASONS.UNKNOWN_NAME);
    // Firestore-discovered (participant row): legacy by id, revoked by id, and
    // BOUND — this is the only source that carries mirror-cleanup authority.
    const first = await enforce(identity, []);
    assert.deepEqual(first.revoked, [legacyId]);
    assert.equal(first.stored.roomsSkipped, 0);
    assert.deepEqual(first.stored.skippedBindings, []);
    assert.equal(first.stored.providerRoomsUnbound, 0);
    assert.deepEqual(first.stored.unboundProviderRooms, []);
    // Provider-only: the srv_ namespace is still fail-closed for attribution
    // and for mirror cleanup — it never falls back to a legacy binding — but
    // per P1-1 the name is revoked anyway, because LiveKit reporting the
    // identity in that room is authority to disconnect it.
    await db.doc(`rooms/${legacyId}/participants/${identity}`).delete();
    const second = await enforce(identity, [legacyId]);
    assert.deepEqual(second.revoked, [legacyId]);
    assert.equal(second.result.completed, true);
    assert.equal(second.stored.roomsDiscovered, 1);
    assert.equal(second.stored.roomsRevoked, 1);
    assert.equal(second.stored.roomsSkipped, 0, "a provider room is never an anchor skip");
    assert.deepEqual(second.stored.skippedBindings, []);
    assert.equal(second.stored.providerRoomsUnbound, 1);
    assert.deepEqual(second.stored.unboundProviderRooms,
      [{ target: legacyId, reason: RTC_BINDING_REASONS.UNKNOWN_NAME }],
      "revoked, and audited as an unbound provider room; the name never resolves as legacy");
    assert.equal(second.stored.status, "completed");
    assert.equal(second.stored.lastErrorCode, null);
  });
});

describe("independent QA: mirror cleanup fence", { timeout: 120_000 }, () => {
  test("(c) three generations: explicit ended, implicit ended, live, then the ordinary sweep after a proper end",
    async () => {
      const f = await fixture();
      const gen1 = (await f.start()).sessionId;
      const userA = await f.member();
      await f.token(gen1, userA);
      const mirrorA = (await mirrorRef(userA, f.roomId).get()).data();
      assert.equal((await f.end(gen1)).status, "ended");
      const gen2 = (await f.start()).sessionId;
      const userB = await f.member();
      await f.token(gen2, userB);
      const mirrorB = (await mirrorRef(userB, f.roomId).get()).data();
      assert.equal((await f.end(gen2)).status, "ended");
      const gen3 = (await f.start()).sessionId;
      const userC = await f.member();
      await f.token(gen3, userC);
      assert.equal(new Set([gen1, gen2, gen3]).size, 3);
      await mirrorRef(userA, f.roomId).set(mirrorA);
      await mirrorRef(userB, f.roomId).set(mirrorB);
      // A foreign V1 mirror re-pathed under this anchor (another server's ids).
      const foreign = await fixture();
      const foreignSession = (await foreign.start()).sessionId;
      const userD = await foreign.member();
      await foreign.token(foreignSession, userD);
      await mirrorRef(userD, f.roomId).set((await mirrorRef(userD, foreign.roomId).get()).data());
      const state = async () => ({
        A: await exists(mirrorRef(userA, f.roomId)), B: await exists(mirrorRef(userB, f.roomId)),
        C: await exists(mirrorRef(userC, f.roomId)), D: await exists(mirrorRef(userD, f.roomId)),
      });
      const everyone = [userA, userB, userC, userD];

      await deleteActiveVoiceSessionsForRoom(f.roomId, everyone, { sessionId: gen1 });
      assert.deepEqual(await state(), { A: false, B: true, C: true, D: true }, "{sessionId: ended-1} clears only ended-1");
      await mirrorRef(userA, f.roomId).set(mirrorA);
      await deleteActiveVoiceSessionsForRoom(f.roomId, everyone);
      assert.deepEqual(await state(), { A: false, B: false, C: true, D: true }, "no sessionId clears both ended generations");
      await mirrorRef(userA, f.roomId).set(mirrorA);
      await mirrorRef(userB, f.roomId).set(mirrorB);
      await deleteActiveVoiceSessionsForRoom(f.roomId, everyone, { sessionId: gen3 });
      assert.deepEqual(await state(), { A: true, B: true, C: true, D: true }, "{sessionId: live} clears nothing");
      const anchor = (await db.doc(`rooms/${f.roomId}`).get()).data();
      assert.equal(anchor.voiceSessionId, gen3);
      assert.equal(anchor.livekitRoomName, f.rtcName(gen3));

      const mirrorC = (await mirrorRef(userC, f.roomId).get()).data();
      assert.equal((await f.end(gen3)).status, "ended");
      assert.equal(await exists(mirrorRef(userC, f.roomId)), false, "endServerChannelSessionV1 clears its own mirror");
      await mirrorRef(userC, f.roomId).set(mirrorC);
      await deleteActiveVoiceSessionsForRoom(f.roomId, everyone);
      assert.deepEqual(await state(), { A: false, B: false, C: false, D: true },
        "after a proper end the ordinary sweep clears every stale generation; the foreign mirror is left");
      const after = (await db.doc(`rooms/${f.roomId}`).get()).data();
      assert.equal(after.isLive, false);
      assert.equal(after.voiceSessionId, null);
      assert.equal((await db.doc(`clubs/${f.serverId}/channels/${f.channelId}`).get()).data().activeSessionId, null);
    });

  test("legacy cleanup stays blind when the room document is gone or carries a null version marker", async () => {
    const uid = `qa-legacy-clean-${randomUUID()}`;
    const ghostRoomId = `qa-ghost-room-${randomUUID()}`;
    await mirrorRef(uid, ghostRoomId).set({ userId: uid, roomId: ghostRoomId, participantIdentity: uid,
      expiresAt: Timestamp.fromMillis(Date.now() + 300_000) });
    await deleteActiveVoiceSessionsForRoom(ghostRoomId, [uid]);
    assert.equal(await exists(mirrorRef(uid, ghostRoomId)), false, "a deleted legacy room still clears its mirrors");

    const markedRoomId = `qa-marked-room-${randomUUID()}`;
    createdRooms.add(markedRoomId);
    await db.doc(`rooms/${markedRoomId}`).set({ status: "active", isLive: true, serverId: null });
    const other = `qa-legacy-clean-b-${randomUUID()}`;
    await mirrorRef(uid, markedRoomId).set({ userId: uid, roomId: markedRoomId, participantIdentity: uid,
      expiresAt: Timestamp.fromMillis(Date.now() + 300_000) });
    await mirrorRef(other, markedRoomId).set({ serverSchemaVersion: 1, userId: other, roomId: markedRoomId,
      participantIdentity: other, serverId: "x", channelId: "y", sessionId: "z", livekitRoomName: `srv_${hex40("cd")}` });
    assert.equal((await resolveRtcBindingForRoom({ db, roomId: markedRoomId })).reason, RTC_BINDING_REASONS.MALFORMED_ANCHOR);
    await deleteActiveVoiceSessionsForRoom(markedRoomId, [uid, other]);
    assert.equal(await exists(mirrorRef(uid, markedRoomId)), false, "legacy-shaped mirrors are cleared under a malformed marker");
    assert.equal(await exists(mirrorRef(other, markedRoomId)), true, "a V1-shaped mirror is never cleared on the strength of a room id");
  });
});

describe("independent QA: achievement webhook", { timeout: 120_000 }, () => {
  test("(d1) a participant row of another server, or with a legacy role, is never credited", async () => {
    const f = await fixture();
    const other = await fixture();
    const { sessionId } = await f.start();
    const guest = await f.member();
    await f.token(sessionId, guest);
    const rowRef = db.doc(`rooms/${f.roomId}/participants/${guest}`);
    const row = (await rowRef.get()).data();
    const h = webhookHarness();
    const roomSid = newRoomSid();
    const name = f.rtcName(sessionId);

    await rowRef.set({ ...row, serverId: other.serverId });
    const foreign = await h.deliver(h.join(f, { roomSid, participantSid: "PA_foreign", identity: guest, name }));
    assert.equal(foreign.statusCode, 400);
    assert.equal(foreign.body.error, "invalid-source");
    assert.equal(await exists(achievementDoc(roomSid, "PA_foreign")), false);

    await rowRef.set({ ...row, role: "speaker" });
    const legacyRole = await h.deliver(h.join(f, { roomSid, participantSid: "PA_role", identity: guest, name }));
    assert.equal(legacyRole.statusCode, 400);
    assert.equal(await exists(achievementDoc(roomSid, "PA_role")), false);

    await rowRef.set(row);
    const genuine = await h.deliver(h.join(f, { roomSid, participantSid: "PA_ok", identity: guest, name }));
    assert.equal(genuine.body.outcome, "opened");
  });

  test("(d2) a channelSession whose stored name was tampered to another session's canonical name is never attributed",
    async () => {
      const f = await fixture();
      const other = await fixture();
      const mine = (await f.start()).sessionId;
      const theirs = (await other.start()).sessionId;
      const guest = await f.member();
      await f.token(mine, guest);
      const otherGuest = await other.member();
      await other.token(theirs, otherGuest);
      const h = webhookHarness();
      const roomSid = newRoomSid();
      await db.doc(f.sessionPath(mine)).update({ livekitRoomName: other.rtcName(theirs) });

      const ambiguous = await h.deliver(h.join(other, { roomSid, participantSid: "PA_amb", identity: otherGuest, name: other.rtcName(theirs) }));
      assert.equal(ambiguous.statusCode, 202);
      assert.equal(ambiguous.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
      assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: other.rtcName(theirs) })).reason,
        RTC_BINDING_REASONS.AMBIGUOUS_NAME);
      const orphaned = await h.deliver(h.join(f, { roomSid, participantSid: "PA_orphan", identity: guest, name: f.rtcName(mine) }));
      assert.equal(orphaned.statusCode, 202);
      assert.equal(orphaned.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
      assert.equal(await exists(achievementDoc(roomSid, "PA_amb")), false);
      assert.equal(await exists(achievementDoc(roomSid, "PA_orphan")), false);
      const closeUnderTamper = await h.deliver(h.left(f, { roomSid, participantSid: "PA_orphan", identity: guest,
        name: f.rtcName(mine), at: BASE_SECONDS + 60 }));
      assert.equal(closeUnderTamper.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
      assert.equal(await exists(achievementDoc(roomSid, "PA_orphan")), false, "no awaiting-join row for an unproven name");

      await db.doc(f.sessionPath(mine)).update({ livekitRoomName: f.rtcName(mine) });
      const recovered = await h.deliver(h.join(f, { roomSid, participantSid: "PA_recovered", identity: guest, name: f.rtcName(mine) }));
      assert.equal(recovered.body.outcome, "opened");
      assert.equal((await achievementDoc(roomSid, "PA_recovered").get()).data().roomId, f.roomId);
    });

  test("(d3) duplicate joins and duplicate closes are idempotent for a srv_ session", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const guest = await f.member();
    await f.token(sessionId, guest);
    const h = webhookHarness();
    const roomSid = newRoomSid();
    const name = f.rtcName(sessionId);
    const joinBody = h.join(f, { roomSid, participantSid: "PA_dup", identity: guest, name });
    assert.equal((await h.deliver(joinBody)).body.outcome, "opened");
    const opened = (await achievementDoc(roomSid, "PA_dup").get()).data();
    assert.equal((await h.deliver(joinBody)).body.outcome, "replayed");
    assert.deepEqual((await achievementDoc(roomSid, "PA_dup").get()).data(), opened, "a replayed join changes nothing");
    const leftBody = h.left(f, { roomSid, participantSid: "PA_dup", identity: guest, name, at: BASE_SECONDS + 120 });
    assert.equal((await h.deliver(leftBody)).body.outcome, "closed");
    const closed = (await achievementDoc(roomSid, "PA_dup").get()).data();
    assert.equal(closed.creditedVoiceSeconds, 120);
    assert.equal(closed.outboxIds.length, 1);
    assert.equal((await h.deliver(leftBody)).body.outcome, "replayed");
    assert.equal((await h.deliver(joinBody)).body.outcome, "replayed");
    assert.deepEqual((await achievementDoc(roomSid, "PA_dup").get()).data(), closed, "replays never re-credit");
    assert.equal((await db.collection("achievementOutbox").where("event.beneficiaryId", "==", guest).get()).size, 1);
  });

  test("(d4) room_finished after the generation ended credits the retained generation exactly once", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const guest = await f.member();
    await f.token(sessionId, guest);
    await f.token(sessionId);
    const h = webhookHarness();
    const roomSid = newRoomSid();
    const name = f.rtcName(sessionId);
    assert.equal((await h.deliver(h.join(f, { roomSid, participantSid: "PA_g", identity: guest, name }))).body.outcome, "opened");
    assert.equal((await h.deliver(h.join(f, { roomSid, participantSid: "PA_h", identity: f.uid, name }))).body.outcome, "opened");
    assert.equal((await f.end(sessionId)).status, "ended");
    assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().isLive, false);
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name })).bound, false);

    const finished = await h.deliver(roomFinishedBody(BASE_SECONDS + 300, { roomName: name, roomSid }));
    assert.equal(finished.statusCode, 202);
    assert.equal(finished.body.outcome, "room-closed");
    const guestDoc = (await achievementDoc(roomSid, "PA_g").get()).data();
    const hostDoc = (await achievementDoc(roomSid, "PA_h").get()).data();
    assert.equal(guestDoc.status, "closed");
    assert.equal(guestDoc.creditedVoiceSeconds, 300);
    assert.equal(guestDoc.creditedHostSeconds, 0);
    assert.equal(hostDoc.status, "closed");
    assert.equal(hostDoc.creditedHostSeconds, 300);
    assert.equal(guestDoc.roomId, f.roomId);

    const again = await h.deliver(roomFinishedBody(BASE_SECONDS + 400, { roomName: name, roomSid }));
    assert.equal(again.body.outcome, "room-closed");
    assert.deepEqual((await achievementDoc(roomSid, "PA_g").get()).data(), guestDoc, "a second finish re-credits nothing");
    assert.deepEqual((await achievementDoc(roomSid, "PA_h").get()).data(), hostDoc);
    const lateLeft = await h.deliver(h.left(f, { roomSid, participantSid: "PA_g", identity: guest, name, at: BASE_SECONDS + 500 }));
    assert.equal(lateLeft.body.outcome, "replayed");
    assert.equal((await db.collection("achievementOutbox").where("event.beneficiaryId", "==", guest).get()).size, 1);
    assert.equal((await db.collection("achievementOutbox").where("event.beneficiaryId", "==", f.uid).get()).size, 2,
      "host: one voiceSeconds and one hostSeconds record");
  });

  test("(d5) legacy room ids inside the srv_ namespace are skipped deterministically and never attributed", async () => {
    const identity = `qa-srv-shaped-${randomUUID()}`;
    const wellFormed = `srv_${hex40("ef")}`;
    const malformed = `srv_legacy-${randomUUID()}`;
    await seedLegacyRoom(identity, { roomId: wellFormed });
    await seedLegacyRoom(identity, { roomId: malformed });
    const h = webhookHarness();
    for (const [name, reason] of [[wellFormed, RTC_BINDING_REASONS.UNKNOWN_NAME], [malformed, RTC_BINDING_REASONS.MALFORMED_NAME]]) {
      const roomSid = newRoomSid();
      assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name })).reason, reason);
      const join = await h.deliver(h.join(null, { roomSid, participantSid: "PA_l", identity, name }));
      assert.equal(join.statusCode, 202);
      assert.equal(join.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
      const left = await h.deliver(h.left(null, { roomSid, participantSid: "PA_l", identity, name, at: BASE_SECONDS + 30 }));
      assert.equal(left.statusCode, 202);
      assert.equal(left.body.outcome, SKIPPED_UNBOUND_RTC_NAME);
      assert.equal(await exists(achievementDoc(roomSid, "PA_l")), false);
      assert.equal((await db.collection("achievementVoiceSessions").where("roomSid", "==", roomSid).get()).size, 0);
    }
  });
});

describe("independent QA: resolver", { timeout: 120_000 }, () => {
  test("(e) under a Firestore transaction every read goes through the transaction and nothing is written", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const name = f.rtcName(sessionId);
    const before = (await db.doc(f.sessionPath(sessionId)).get()).data();
    const audit = { reads: 0, writes: 0 };
    let byRoom;
    let byName;
    await db.runTransaction(async (transaction) => {
      const forbid = () => { audit.writes += 1; throw new Error("the resolver must not write"); };
      const wrapped = {
        get: (target) => { audit.reads += 1; return transaction.get(target); },
        getAll: () => { throw new Error("unexpected getAll"); },
        set: forbid, update: forbid, delete: forbid, create: forbid,
      };
      byRoom = await resolveRtcBindingForRoom({ db, transaction: wrapped, roomId: f.roomId });
      byName = await resolveRtcBindingForLiveKitRoom({ db, transaction: wrapped, livekitRoomName: name });
    });
    assert.equal(audit.reads, 6, "room, channel, session by id; query, room, channel by name");
    assert.equal(audit.writes, 0);
    assert.equal(byRoom.bound, true);
    assert.equal(byName.bound, true);
    assert.equal(byRoom.livekitRoomName, name);
    assert.equal(byName.sessionId, sessionId);
    assert.deepEqual((await db.doc(f.sessionPath(sessionId)).get()).data(), before, "no write reached the session");
  });

  test("(f) forged collectionGroup matches and a tampered session yield closed-set reasons and never throw", async () => {
    const f = await fixture();
    const { sessionId } = await f.start();
    const name = f.rtcName(sessionId);
    const real = (await db.doc(f.sessionPath(sessionId)).get()).data();
    const forged = Array.from({ length: 3 }, () => db.doc(`clubs/qa-forge-${randomUUID()}/channels/c/channelSessions/s`));
    await Promise.all(forged.map((reference) => reference.set({ ...real })));
    const ambiguous = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name });
    assert.equal(ambiguous.reason, RTC_BINDING_REASONS.AMBIGUOUS_NAME);
    assert.equal(ambiguous.bound, false);
    await Promise.all(forged.map((reference) => reference.delete()));

    const typed = [
      db.doc(`clubs/qa-typed-${randomUUID()}/channels/c/channelSessions/s`),
      db.doc(`clubs/qa-typed-${randomUUID()}/channels/c/channelSessions/s`),
    ];
    await typed[0].set({ ...real, livekitRoomName: 42 });
    await typed[1].set({ ...real, livekitRoomName: null });
    const unaffected = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name });
    assert.equal(unaffected.bound, true, "non-string name fields never match the real generation");
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: `srv_${hex40("42")}` })).reason,
      RTC_BINDING_REASONS.UNKNOWN_NAME);
    await Promise.all(typed.map((reference) => reference.delete()));

    // A tampered host on the real generation: assertSessionBinding's
    // HttpsError is mapped to session-mismatch (unbound), never to bound.
    await db.doc(f.sessionPath(sessionId)).update({ startedById: null });
    const tampered = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name });
    assert.equal(tampered.reason, RTC_BINDING_REASONS.SESSION_MISMATCH);
    assert.equal(tampered.bound, false);
    assert.equal(tampered.retained, null, "a forged document is never retained for attribution");
    const byRoom = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(byRoom.reason, RTC_BINDING_REASONS.SESSION_MISMATCH);
    for (const binding of [ambiguous, unaffected, tampered, byRoom]) {
      assert.ok(binding.reason === null || CLOSED_REASONS.has(binding.reason));
    }
    await db.doc(f.sessionPath(sessionId)).update({ startedById: real.startedById });
    assert.equal((await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: name })).bound, true);
  });
});

/* =========================================================== re-verification
 * Independent regressions added by the QA owner AFTER the S3 P1 fixes landed,
 * against behaviour the fixer's own suite does not pin adversarially:
 * P1-1 an identity the provider reports inside an ENDED generation is revoked
 *      while the anchor's current live generation is left completely alone;
 * P1-2 the stranded-room sweep never dates, closes or cleans a versioned
 *      anchor, including a MALFORMED one (the marker alone is the boundary);
 * P1-2 a room-id cleanup is a total no-op while an ENDING generation is
 *      retained but unproven, and stays fenced once the graph proves out.
 * ======================================================================== */

describe("independent QA: re-verification of the S3 P1 fixes", { timeout: 120_000 }, () => {
  const { sweepStrandedLiveRooms } = require("../rooms/liveness_sweeper");

  test("(qa-1) a banned identity the provider reports in an ended generation is revoked; the anchor's live generation is untouched",
    async () => {
      const f = await fixture();
      const banned = await f.member();
      const other = await f.member();
      const ended = (await f.start()).sessionId;
      await f.token(ended, banned);
      const endedName = f.rtcName(ended);
      assert.equal((await f.end(ended)).status, "ended");
      assert.equal(await exists(mirrorRef(banned, f.roomId)), false, "the end worker cleared the banned identity's mirror");
      // A NEW generation of the SAME anchor is live and belongs to somebody
      // else: nothing about revoking the old name may reach it.
      const live = (await f.start()).sessionId;
      await f.token(live, other);
      const liveName = f.rtcName(live);
      assert.notEqual(ended, live);
      // The banned identity leaves no Firestore trace at all, so LiveKit
      // reporting it inside the ended generation is the only discovery source.
      await db.doc(`rooms/${f.roomId}/participants/${banned}`).delete();
      assert.equal((await db.collection(`activeVoiceSessions/${banned}/rooms`).get()).empty, true);

      const { result, revoked, stored } = await enforce(banned, [endedName]);
      assert.equal(result.completed, true);
      assert.deepEqual(revoked, [endedName],
        "LiveKit reporting the identity in a room is authority to disconnect it, bound or not");
      assert.ok(!revoked.includes(liveName), "the live generation's name is never revoked for this event");
      assert.ok(!revoked.includes(f.roomId), "an anchor id is never sent to the provider");
      assert.equal(stored.status, "completed");
      assert.equal(stored.roomsDiscovered, 1);
      assert.equal(stored.roomsRevoked, 1);
      assert.equal(stored.roomsSkipped, 0);
      assert.deepEqual(stored.skippedBindings, []);
      assert.deepEqual(stored.unboundProviderRooms,
        [{ target: endedName, reason: RTC_BINDING_REASONS.SESSION_NOT_LIVE }],
        "revoked, and audited as an unbound provider room rather than as a skip");
      assert.equal(stored.lastErrorCode, null);
      assert.equal(await exists(mirrorRef(other, f.roomId)), true,
        "an unbound revocation never clears any mirror, least of all a newer generation's");
      const anchor = (await db.doc(`rooms/${f.roomId}`).get()).data();
      assert.equal(anchor.isLive, true);
      assert.equal(anchor.voiceSessionId, live);
      assert.equal((await resolveRtcBindingForRoom({ db, roomId: f.roomId })).sessionId, live);
    });

  test("(qa-2) the stranded-room sweep never dates, closes or cleans a versioned anchor, canonical or malformed", async () => {
    const f = await fixture();
    const member = await f.member();
    const { sessionId } = await f.start();
    await f.token(sessionId, member);
    // The roster row is the ONLY thing the legacy sweep keys on, and a crashed
    // or hostile client can delete it while the generation is still live.
    await db.doc(`rooms/${f.roomId}/participants/${member}`).delete();
    // A malformed versioned anchor: `serverId` alone makes it a versioned
    // boundary, the same test assertLegacyRoomAccess applies.
    const malformedId = `qa-sweep-versioned-${randomUUID()}`;
    createdRooms.add(malformedId);
    // An ancient age anchor plus a clock just past it: these two rooms are the
    // only ones old enough to be swept, so every other live room in this shared
    // emulator project is younger than the cutoff and is provably left alone.
    const ancientMillis = Date.parse("2020-01-01T00:00:00.000Z");
    const ancient = Timestamp.fromMillis(ancientMillis);
    await db.doc(`rooms/${malformedId}`).set({ status: "active", isLive: true, roomType: "community",
      visibility: "public", hostId: `qa-sweep-host-${randomUUID()}`, participantCount: 0,
      serverId: null, updatedAt: ancient, createdAt: ancient });
    await db.doc(`rooms/${f.roomId}`).update({ updatedAt: ancient });
    const anchorBefore = (await db.doc(`rooms/${f.roomId}`).get()).data();
    const malformedBefore = (await db.doc(`rooms/${malformedId}`).get()).data();
    const mirrorBefore = (await mirrorRef(member, f.roomId).get()).data();
    assert.equal(anchorBefore.isLive, true);
    assert.equal(mirrorBefore.serverSchemaVersion, 1);
    assert.equal((await db.collection(`rooms/${f.roomId}/participants`).limit(1).get()).empty, true,
      "an empty roster is exactly what would make a legacy room a candidate");

    const ended = [];
    const outcome = await sweepStrandedLiveRooms({
      roomControl: { async endRoom(name) { ended.push(name); return {}; } },
      gracePeriodSeconds: 60,
      now: () => Timestamp.fromMillis(ancientMillis + 120_000),
    });

    assert.equal(outcome.truncated, false, "a truncated scan would make the assertions below vacuous");
    assert.equal(outcome.failed, 0);
    assert.ok(outcome.skippedVersioned >= 2, `both anchors must be skipped as versioned (${outcome.skippedVersioned})`);
    assert.ok(!outcome.closedRoomIds.includes(f.roomId) && !outcome.closedRoomIds.includes(malformedId),
      "a versioned anchor is never closed");
    assert.ok(!ended.includes(f.roomId) && !ended.includes(malformedId),
      "endRoom(anchorId) would target the wrong namespace and is never called");
    assert.deepEqual((await db.doc(`rooms/${f.roomId}`).get()).data(), anchorBefore, "no liveness write on the anchor");
    assert.deepEqual((await db.doc(`rooms/${malformedId}`).get()).data(), malformedBefore,
      "a malformed marker is still versioned; it is refused, not swept");
    assert.deepEqual((await mirrorRef(member, f.roomId).get()).data(), mirrorBefore, "no mirror is cleared");
    const stillBound = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(stillBound.bound, true, "the generation is still endable and still enforceable after the sweep");
    assert.equal(stillBound.sessionId, sessionId);
  });

  test("(qa-3) a room-id cleanup is a total no-op while an ENDING generation is retained but unproven", async () => {
    const f = await fixture();
    const member = await f.member();
    const sessionId = (await f.start()).sessionId;
    await f.token(sessionId, member);
    const legacyShaped = `qa-ending-legacy-${randomUUID()}`;
    await mirrorRef(legacyShaped, f.roomId).set({ userId: legacyShaped, roomId: f.roomId,
      participantIdentity: legacyShaped, expiresAt: Timestamp.fromMillis(Date.now() + 300_000) });
    const everyone = [member, legacyShaped];
    const anchorRef = db.doc(`rooms/${f.roomId}`);

    // The canonical ENDING state the end transaction writes (servers/sessions.js:
    // status ending + endOperationId, channel.activeSessionId null, the anchor
    // holding only serverSessionCleanupId). Media may still be connected.
    await db.doc(f.sessionPath(sessionId)).update({ status: "ending", endOperationId: `qa-end-${randomUUID()}` });
    await db.doc(`clubs/${f.serverId}/channels/${f.channelId}`).update({ activeSessionId: null });
    await anchorRef.update({ isLive: false, voiceSessionId: null, livekitRoomName: null,
      serverSessionCleanupId: sessionId });
    const ending = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(ending.bound, true);
    assert.equal(ending.status, "ending");

    // A stale liveness field breaks the proof while that ending generation is
    // retained: `ending` is a bound status, so this is the second half of the
    // fence and nothing may be cleared on the strength of the room id.
    await anchorRef.update({ livekitRoomName: f.rtcName(sessionId) });
    const mismatch = await resolveRtcBindingForRoom({ db, roomId: f.roomId });
    assert.equal(mismatch.reason, RTC_BINDING_REASONS.LIVENESS_MISMATCH);
    assert.equal(mismatch.bound, false);
    assert.equal(mismatch.retained.status, "ending");

    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone);
    assert.equal(await exists(mirrorRef(member, f.roomId)), true,
      "a cleanup with no sessionId never clears the retained generation's mirror");
    assert.equal(await exists(mirrorRef(legacyShaped, f.roomId)), true,
      "the deferral is total: not even a legacy-shaped mirror is cleared");
    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone, { sessionId });
    assert.equal(await exists(mirrorRef(member, f.roomId)), true, "naming the generation does not lift the deferral");

    // Repaired: the generation proves out again, and its own mirror is still
    // only its end worker's to clear.
    await anchorRef.update({ livekitRoomName: null });
    assert.equal((await resolveRtcBindingForRoom({ db, roomId: f.roomId })).bound, true);
    await deleteActiveVoiceSessionsForRoom(f.roomId, everyone);
    assert.equal(await exists(mirrorRef(member, f.roomId)), true,
      "a bound ending generation's mirror belongs to its end worker, never to a room-id cleanup");
    assert.equal(await exists(mirrorRef(legacyShaped, f.roomId)), false,
      "legacy-shaped mirrors follow the legacy rule once the graph proves out");
  });
});

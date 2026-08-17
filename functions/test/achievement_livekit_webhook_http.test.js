// The HTTP edge of the voice-achievement chain, exercised end to end.
//
// `receiveLiveKitAchievementWebhook` is the project's only unauthenticated,
// internet-reachable endpoint and the only writer of connected voice time.
// These tests cover the two things that follow from that: nothing unsigned may
// reach Firestore, and a signed minute of talking must actually land in
// `users/{uid}.voiceMinutes` — the exact field the Creator Studio tile and the
// AchievementCategory.voice group read.

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { describe, test } = require("node:test");

const { AccessToken } = require("livekit-server-sdk");

const {
  FirestoreVoiceAchievementStore,
  MAX_WEBHOOK_BODY_BYTES,
  createLiveKitAchievementWebhookHandler,
} = require("../achievements/livekit_http");
const {
  FirestoreAchievementRepository,
} = require("../achievements/firestore_repository");
const { createAchievementRuntime } = require("../achievements/runtime");
const {
  createAchievementSourceHandlers,
} = require("../achievements/triggers");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const API_KEY = "livekit-achievement-key";
const API_SECRET = "livekit-achievement-secret-at-least-32-characters";
const ROOM_ID = "room-voice-1";
const ROOM_SID = "RM_voice_1";
const UID = "voice-user-1";
const HOST_UID = "voice-host-1";

const BASE_MS = Date.parse("2026-08-16T09:00:00.000Z");
const BASE_SECONDS = BASE_MS / 1000;
const PROCESSED_AT = new Date("2026-08-16T12:00:00.000Z");

/* -------------------------------------------------------------------------
 * Signed-delivery fixtures
 * ---------------------------------------------------------------------- */

function participantBody(type, atSeconds, {
  participantSid = "PA_voice_1",
  identity = UID,
  joinedAtSeconds = BASE_SECONDS,
  eventId = `EV_${type}_${atSeconds}_${participantSid}`,
  roomSid = ROOM_SID,
  roomName = ROOM_ID,
} = {}) {
  return JSON.stringify({
    event: type,
    id: eventId,
    created_at: atSeconds,
    room: { sid: roomSid, name: roomName },
    participant: {
      sid: participantSid,
      identity,
      joined_at: joinedAtSeconds,
      joined_at_ms: joinedAtSeconds * 1000,
    },
  });
}

function roomFinishedBody(atSeconds, { roomSid = ROOM_SID, roomName = ROOM_ID } = {}) {
  return JSON.stringify({
    event: "room_finished",
    id: `EV_room_finished_${atSeconds}`,
    created_at: atSeconds,
    room: { sid: roomSid, name: roomName },
  });
}

/**
 * Signs exactly the way LiveKit's SFU does: an HS256 JWT issued by the API key
 * whose `sha256` claim is the base64 digest of the precise bytes posted.
 */
async function signedAuthorization(body, {
  apiKey = API_KEY,
  apiSecret = API_SECRET,
  ttl = 300,
} = {}) {
  const token = new AccessToken(apiKey, apiSecret, { ttl });
  token.sha256 = createHash("sha256").update(body).digest("base64");
  return token.toJwt();
}

function recordingResponse() {
  const recorded = { statusCode: null, body: null, headers: {} };
  const response = {
    set(name, value) {
      recorded.headers[name] = value;
      return response;
    },
    status(code) {
      recorded.statusCode = code;
      return response;
    },
    json(payload) {
      recorded.body = payload;
      return response;
    },
    send(payload) {
      recorded.body = payload;
      return response;
    },
  };
  return { recorded, response };
}

// LiveKit delivers an event within seconds of emitting it, so the receiving
// clock tracks the event's own `created_at`. Each signed delivery below
// advances this to the instant it claims to describe. The freshness window
// itself — stale, future-dated and in-window — is exercised directly in
// achievement_livekit_webhook_hardening.test.js.
let currentNowMs = BASE_MS;

function postRequest(body, authorization) {
  return {
    method: "POST",
    rawBody: Buffer.from(body, "utf8"),
    headers: { authorization },
  };
}

/* -------------------------------------------------------------------------
 * A canonical, live room the webhook is allowed to credit against
 * ---------------------------------------------------------------------- */

function seedCanonicalRoom(memory, { hostId = HOST_UID, uid = UID } = {}) {
  memory.seed(`rooms/${ROOM_ID}`, {
    status: "active",
    isLive: true,
    roomType: "community",
    visibility: "public",
    hostId,
    clubId: null,
  });
  memory.seed(`rooms/${ROOM_ID}/participants/${uid}`, {
    userId: uid,
    role: uid === hostId ? "host" : "speaker",
  });
  memory.seed(`users/${uid}`, {
    displayName: "Voice User",
    voiceMinutes: 0,
    hostMinutes: 0,
    activeDays: 0,
  });
  if (hostId !== uid) {
    memory.seed(`users/${hostId}`, { displayName: "Voice Host", voiceMinutes: 0 });
  }
  return memory;
}

function buildHarness({ hostId = HOST_UID, uid = UID } = {}) {
  const memory = seedCanonicalRoom(new InMemoryFirestore(), { hostId, uid });
  const store = new FirestoreVoiceAchievementStore({ db: memory });
  const handler = createLiveKitAchievementWebhookHandler({
    apiKeyProvider: () => API_KEY,
    apiSecretProvider: () => API_SECRET,
    store,
    now: () => currentNowMs,
  });
  return { memory, store, handler };
}

async function deliver(handler, body, authorization) {
  const { recorded, response } = recordingResponse();
  await handler(postRequest(body, authorization), response);
  return recorded;
}

async function deliverSigned(handler, body, options = {}) {
  const createdAt = JSON.parse(body)?.created_at;
  if (Number.isFinite(createdAt)) currentNowMs = createdAt * 1000;
  return deliver(handler, body, await signedAuthorization(body, options));
}

/**
 * Runs every pending outbox record through the REAL achievement runtime, the
 * same way `onAchievementOutboxCreated` does in production. Without this the
 * webhook only proves it wrote an outbox row; with it, the test proves the
 * whole chain terminates in `users/{uid}.voiceMinutes`.
 */
async function drainAchievementOutbox(memory) {
  const runtime = createAchievementRuntime({
    repository: new FirestoreAchievementRepository({ db: memory }),
    clock: () => PROCESSED_AT,
  });
  const marked = [];
  const handlers = createAchievementSourceHandlers({
    reader: {
      async markOutboxProcessed(reference, result) {
        marked.push(result.outcome);
        await reference.set({ status: "processed" }, { merge: true });
      },
      async markOutboxInvalid(reference) {
        marked.push("invalid");
        await reference.set({ status: "invalid" }, { merge: true });
      },
    },
    runtimeProvider: () => runtime,
  });
  const snapshot = await memory.collection("achievementOutbox").get();
  for (const document of snapshot.docs) {
    if (document.data()?.status !== "pending") continue;
    await handlers.onOutboxCreated({
      params: { outboxId: document.id },
      data: document,
    });
  }
  return marked;
}

function outboxIds(memory) {
  return memory.paths("achievementOutbox/");
}

/* -------------------------------------------------------------------------
 * 1. Unsigned and wrongly-signed requests never reach Firestore
 * ---------------------------------------------------------------------- */

describe("LiveKit achievement webhook — rejection before any Firestore work", () => {
  function countingStore() {
    const calls = [];
    return {
      calls,
      store: {
        async handle(webhook) {
          calls.push(webhook.type);
          return { outcome: "opened" };
        },
      },
    };
  }

  function guardedHandler() {
    const counting = countingStore();
    return {
      calls: counting.calls,
      handler: createLiveKitAchievementWebhookHandler({
        apiKeyProvider: () => API_KEY,
        apiSecretProvider: () => API_SECRET,
        store: counting.store,
        now: () => currentNowMs,
      }),
    };
  }

  test("a GET is refused with Allow: POST and never touches the store", async () => {
    const { calls, handler } = guardedHandler();
    const { recorded, response } = recordingResponse();
    await handler({ method: "GET", headers: {} }, response);
    assert.equal(recorded.statusCode, 405);
    assert.equal(recorded.headers.Allow, "POST");
    assert.deepEqual(calls, []);
  });

  test("a missing Authorization header is refused without a signature check", async () => {
    const { calls, handler } = guardedHandler();
    const body = participantBody("participant_joined", BASE_SECONDS);
    const recorded = await deliver(handler, body, undefined);
    assert.equal(recorded.statusCode, 400);
    assert.deepEqual(recorded.body, { accepted: false, error: "invalid-webhook" });
    assert.deepEqual(calls, []);
  });

  test("a body signed with an attacker's own secret is refused", async () => {
    const { calls, handler } = guardedHandler();
    const body = participantBody("participant_joined", BASE_SECONDS);
    const forged = await signedAuthorization(body, {
      apiSecret: "attacker-secret-that-is-also-at-least-32-chars",
    });
    const recorded = await deliver(handler, body, forged);
    assert.equal(recorded.statusCode, 401);
    assert.deepEqual(recorded.body, { accepted: false, error: "invalid-signature" });
    assert.deepEqual(calls, []);
  });

  test("a valid signature from a different API key is refused — iss is pinned", async () => {
    const { calls, handler } = guardedHandler();
    const body = participantBody("participant_joined", BASE_SECONDS);
    const wrongIssuer = await signedAuthorization(body, { apiKey: "someone-elses-key" });
    const recorded = await deliver(handler, body, wrongIssuer);
    assert.equal(recorded.statusCode, 401);
    assert.deepEqual(calls, []);
  });

  test("a body altered after signing is refused — the sha256 claim binds it", async () => {
    const { calls, handler } = guardedHandler();
    const body = participantBody("participant_joined", BASE_SECONDS);
    const authorization = await signedAuthorization(body);
    const tampered = participantBody("participant_joined", BASE_SECONDS, {
      identity: "victim-account",
    });
    assert.notEqual(tampered, body);
    const recorded = await deliver(handler, tampered, authorization);
    assert.equal(recorded.statusCode, 401);
    assert.deepEqual(calls, []);
  });

  test("an expired signature is refused past the clock tolerance", async () => {
    const { calls, handler } = guardedHandler();
    const body = participantBody("participant_joined", BASE_SECONDS);
    const expired = await signedAuthorization(body, { ttl: -300 });
    const recorded = await deliver(handler, body, expired);
    assert.equal(recorded.statusCode, 401);
    assert.deepEqual(calls, []);
  });

  test("an oversized body is refused before it is hashed or verified", async () => {
    const { calls, handler } = guardedHandler();
    const padded = JSON.stringify({
      event: "participant_joined",
      id: "EV_flood",
      created_at: BASE_SECONDS,
      room: { sid: ROOM_SID, name: ROOM_ID },
      participant: { sid: "PA_flood", identity: UID, joined_at: BASE_SECONDS },
      padding: "A".repeat(MAX_WEBHOOK_BODY_BYTES),
    });
    assert.ok(Buffer.byteLength(padded, "utf8") > MAX_WEBHOOK_BODY_BYTES);
    // Correctly signed: the size bound must hold even for an authentic sender.
    const recorded = await deliverSigned(handler, padded);
    assert.equal(recorded.statusCode, 413);
    assert.deepEqual(recorded.body, { accepted: false, error: "payload-too-large" });
    assert.deepEqual(calls, []);
  });

  test("an unsigned request leaves the database completely untouched", async () => {
    const { memory, handler } = buildHarness();
    const before = memory.paths().sort();
    const body = participantBody("participant_joined", BASE_SECONDS);
    await deliver(handler, body, "Bearer not-a-livekit-token");
    await deliver(handler, body, undefined);
    assert.deepEqual(memory.paths().sort(), before);
    assert.deepEqual(outboxIds(memory), []);
  });

  test("an unsupported but authentically signed event writes nothing", async () => {
    const { memory, handler } = buildHarness();
    const before = memory.paths().sort();
    const body = JSON.stringify({
      event: "track_published",
      id: "EV_track",
      created_at: BASE_SECONDS,
      room: { sid: ROOM_SID, name: ROOM_ID },
      participant: { sid: "PA_voice_1", identity: UID },
    });
    const recorded = await deliverSigned(handler, body);
    assert.equal(recorded.statusCode, 204);
    assert.deepEqual(memory.paths().sort(), before);
  });
});

/* -------------------------------------------------------------------------
 * 2. Responses disclose nothing about who was in which room
 * ---------------------------------------------------------------------- */

describe("LiveKit achievement webhook — response disclosure", () => {
  test("no response body carries a uid, room id, sid or session id", async () => {
    const { memory, handler } = buildHarness();
    const bodies = [];

    bodies.push(await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
    ));
    bodies.push(await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS + 65),
    ));
    // A signed event for a room this project does not own: the most tempting
    // place for an implementation to explain itself in the error body.
    bodies.push(await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS, {
        roomName: "room-does-not-exist",
        roomSid: "RM_unknown",
        participantSid: "PA_unknown",
      }),
    ));
    bodies.push(await deliver(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
      "Bearer forged",
    ));

    const sessionIds = memory
      .paths("achievementVoiceSessions/")
      .map((path) => path.split("/").at(-1));
    assert.ok(sessionIds.length > 0);

    for (const recorded of bodies) {
      const serialized = JSON.stringify(recorded.body);
      for (const secret of [UID, HOST_UID, ROOM_ID, ROOM_SID, "PA_voice_1",
        "room-does-not-exist", "RM_unknown", ...sessionIds]) {
        assert.ok(
          !serialized.includes(secret),
          `response body leaked ${secret}: ${serialized}`,
        );
      }
    }

    assert.deepEqual(bodies[2].body, { accepted: false, error: "invalid-source" });
  });
});

/* -------------------------------------------------------------------------
 * 3. Replay cannot inflate voiceMinutes
 * ---------------------------------------------------------------------- */

describe("LiveKit achievement webhook — replay", () => {
  test("re-delivering the same join and leave credits exactly one minute once", async () => {
    const { memory, handler } = buildHarness();
    const join = participantBody("participant_joined", BASE_SECONDS);
    const leave = participantBody("participant_left", BASE_SECONDS + 65);

    assert.equal((await deliverSigned(handler, join)).body.outcome, "opened");
    assert.equal((await deliverSigned(handler, leave)).body.outcome, "closed");

    // Every ordering an attacker (or a retrying SFU) can produce.
    assert.equal((await deliverSigned(handler, join)).body.outcome, "replayed");
    assert.equal((await deliverSigned(handler, leave)).body.outcome, "replayed");
    assert.equal((await deliverSigned(handler, leave)).body.outcome, "replayed");
    assert.equal((await deliverSigned(handler, join)).body.outcome, "replayed");

    assert.equal(outboxIds(memory).length, 1);
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 1);

    // Replaying again after the credit has already been projected.
    await deliverSigned(handler, leave);
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 1);
  });

  test("a captured leave replayed with a fresh signature adds no time", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 600));
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 10);

    // Same canonical (roomSid, participantSid) pair, re-signed now, and a
    // second copy claiming a much later close time. The session document is
    // already closed, so neither is re-credited.
    for (const seconds of [BASE_SECONDS + 600, BASE_SECONDS + 40_000]) {
      const recorded = await deliverSigned(
        handler,
        participantBody("participant_left", seconds),
      );
      assert.equal(recorded.body.outcome, "replayed");
    }
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 10);
    assert.equal(outboxIds(memory).length, 1);
  });

  test("a replayed room_finished re-closes nothing", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    assert.equal(
      (await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 120))).body.outcome,
      "room-closed",
    );
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 2);

    await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 9_000));
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 2);
  });

  test("the outbox record is created once even across repeated closes", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    for (let attempt = 0; attempt < 5; attempt += 1) {
      await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 65));
    }
    assert.equal(outboxIds(memory).length, 1);
    const record = memory.data(outboxIds(memory)[0]);
    assert.equal(record.event.metric, "voiceSeconds");
    assert.equal(record.event.delta, 65);
    assert.equal(record.event.beneficiaryId, UID);
  });
});

/* -------------------------------------------------------------------------
 * 4. The minute arithmetic, all the way to users/{uid}.voiceMinutes
 * ---------------------------------------------------------------------- */

describe("LiveKit achievement webhook — minute accrual", () => {
  test("a 65 second session becomes exactly one voiceMinute for the speaker", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 65));

    const outboxes = outboxIds(memory);
    assert.equal(outboxes.length, 1, "a non-host session emits voiceSeconds only");

    await drainAchievementOutbox(memory);
    const user = memory.data(`users/${UID}`);
    assert.equal(user.voiceMinutes, 1);
    assert.equal(user.hostMinutes, 0);

    // The private ledger keeps the sub-minute remainder so it is not lost.
    const progress = memory.data(`achievementProgress/${UID}`);
    assert.equal(progress.verifiedMetrics.voiceSeconds, 65);
    assert.equal(progress.verifiedMetrics.voiceMinutes, 1);
  });

  test("59 seconds is honestly zero minutes but is not thrown away", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 59));
    await drainAchievementOutbox(memory);

    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 0);
    assert.equal(memory.data(`achievementProgress/${UID}`).verifiedMetrics.voiceSeconds, 59);
  });

  test("a second, later session in the same day accumulates rather than replaces", async () => {
    const { memory, handler } = buildHarness();

    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 65));

    // A reconnect: LiveKit issues a new participant SID for the same account.
    const second = { participantSid: "PA_voice_2", joinedAtSeconds: BASE_SECONDS + 3600 };
    await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS + 3600, second),
    );
    await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS + 7200, second),
    );

    await drainAchievementOutbox(memory);
    // 65s + 3600s = 3665s -> 61 minutes.
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 61);
    assert.equal(memory.data(`achievementProgress/${UID}`).verifiedMetrics.voiceSeconds, 3665);
  });

  test("two overlapping sessions credit wall-clock time, not doubled tab time", async () => {
    const { memory, handler } = buildHarness();

    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    // A second device for the same account, joining 60s in and leaving later.
    const overlapping = { participantSid: "PA_voice_2", joinedAtSeconds: BASE_SECONDS + 60 };
    await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS + 60, overlapping),
    );
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 120));
    await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS + 180, overlapping),
    );

    await drainAchievementOutbox(memory);
    // Union of [0,120] and [60,180] is 180 seconds, not 120 + 120 = 240.
    assert.equal(memory.data(`achievementProgress/${UID}`).verifiedMetrics.voiceSeconds, 180);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 3);
  });

  test("the host earns hostMinutes alongside voiceMinutes from one session", async () => {
    const { memory, handler } = buildHarness({ hostId: UID, uid: UID });
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 125));

    assert.equal(outboxIds(memory).length, 2, "a host session emits voice and host seconds");
    await drainAchievementOutbox(memory);

    const user = memory.data(`users/${UID}`);
    assert.equal(user.voiceMinutes, 2);
    assert.equal(user.hostMinutes, 2);
  });

  test("a crash close (participant_connection_aborted) credits the same as a clean leave", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_connection_aborted", BASE_SECONDS + 300),
    );
    assert.equal(recorded.body.outcome, "closed");

    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 5);
  });

  test("room_finished closes a session the SFU never reported leaving", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 600));

    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 10);
    const session = memory.data(memory.paths("achievementVoiceSessions/")[0]);
    assert.equal(session.status, "closed");
  });

  test("crossing the first voice threshold unlocks the voice achievement", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 90));
    await drainAchievementOutbox(memory);

    const user = memory.data(`users/${UID}`);
    assert.equal(user.voiceMinutes, 1);
    assert.ok(
      user.unlockedTitleIds.includes("voiceMinutes_1"),
      `expected voiceMinutes_1 in ${JSON.stringify(user.unlockedTitleIds)}`,
    );
  });
});

/* -------------------------------------------------------------------------
 * 5. Bounds on what a signed sender can create
 * ---------------------------------------------------------------------- */

describe("LiveKit achievement webhook — bounds", () => {
  test("an implausibly long session is capped rather than credited in full", async () => {
    const memory = seedCanonicalRoom(new InMemoryFirestore());
    const handler = createLiveKitAchievementWebhookHandler({
      apiKeyProvider: () => API_KEY,
      apiSecretProvider: () => API_SECRET,
      store: new FirestoreVoiceAchievementStore({
        db: memory,
        maximumSessionSeconds: 120,
      }),
      now: () => currentNowMs,
    });

    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 86_400));

    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 2);
    const session = memory.data(memory.paths("achievementVoiceSessions/")[0]);
    assert.equal(session.capped, true);
    assert.equal(session.creditedVoiceSeconds, 120);
  });

  test("a leave that predates its own join credits nothing", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS + 600));
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS, {
        joinedAtSeconds: BASE_SECONDS + 600,
      }),
    );
    assert.equal(recorded.statusCode, 400);
    assert.deepEqual(outboxIds(memory), []);
  });

  test("a signed event for a room this project does not own is refused", async () => {
    const { memory, handler } = buildHarness();
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS, {
        roomName: "not-a-yovoice-room",
        roomSid: "RM_foreign",
      }),
    );
    assert.equal(recorded.statusCode, 400);
    assert.deepEqual(memory.paths("achievementVoiceSessions/"), []);
    assert.deepEqual(outboxIds(memory), []);
  });

  test("a signed event for an account that is not in the room is refused", async () => {
    const { memory, handler } = buildHarness();
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS, {
        identity: "never-joined-this-room",
        participantSid: "PA_intruder",
      }),
    );
    assert.equal(recorded.statusCode, 400);
    assert.deepEqual(outboxIds(memory), []);
  });

  test("a banned account earns nothing even from an authentic session", async () => {
    const { memory, handler } = buildHarness();
    await deliverSigned(handler, participantBody("participant_joined", BASE_SECONDS));
    memory.seed(`users/${UID}`, { displayName: "Voice User", voiceMinutes: 0, banned: true });

    const recorded = await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS + 600),
    );
    assert.equal(recorded.body.outcome, "rejected:authority");
    assert.deepEqual(outboxIds(memory), []);

    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 0);
  });

  test("a close arriving before its join is parked, not credited blind", async () => {
    const { memory, handler } = buildHarness();
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS + 65),
    );
    assert.equal(recorded.body.outcome, "awaiting-join");
    assert.deepEqual(outboxIds(memory), []);

    const parked = memory.data(memory.paths("achievementVoiceSessions/")[0]);
    assert.equal(parked.status, "awaitingJoin");

    // Repeated deliveries of the same early close create no further documents.
    await deliverSigned(handler, participantBody("participant_left", BASE_SECONDS + 65));
    assert.equal(memory.paths("achievementVoiceSessions/").length, 1);

    // The join then settles it in one transaction, crediting once.
    const settled = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
    );
    assert.equal(settled.body.outcome, "closed");
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 1);
  });
});

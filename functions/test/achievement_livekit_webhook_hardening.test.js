// Regression coverage for the adversarial-audit findings on the LiveKit voice
// webhook. Each block names the defect it pins down; every one of these tests
// fails against the code as it stood at commit fe82755.
//
//   F1 — a close for an unknown room/account minted a permanent orphan row.
//   F2 — one poisoned session denied credit to every co-participant after it.
//   F3 — the 256-interval/day cap refused ordinary users' closes forever.
//   plus: max event age, and fatal errors misreported as retryable.

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { describe, test } = require("node:test");

const { AccessToken } = require("livekit-server-sdk");

const {
  FirestoreVoiceAchievementStore,
  createLiveKitAchievementWebhookHandler,
} = require("../achievements/livekit_http");
const {
  MAX_VOICE_INTERVALS_PER_DAY,
  MAX_WEBHOOK_EVENT_AGE_MS,
  mergeBillableInterval,
} = require("../achievements/voice_webhook");
const {
  AchievementOutboxValidationError,
} = require("../achievements/runtime");
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
const DAY = "2026-08-16";
const PROCESSED_AT = new Date("2026-08-16T12:00:00.000Z");

/* ---------------------------------------------------------------- fixtures */

function participantBody(type, atSeconds, {
  participantSid = "PA_voice_1",
  identity = UID,
  joinedAtSeconds = BASE_SECONDS,
  roomSid = ROOM_SID,
  roomName = ROOM_ID,
} = {}) {
  return JSON.stringify({
    event: type,
    id: `EV_${type}_${atSeconds}_${participantSid}`,
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

async function signedAuthorization(body) {
  const token = new AccessToken(API_KEY, API_SECRET, { ttl: 300 });
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

function seedRoom(memory, { hostId = HOST_UID, participants = [UID] } = {}) {
  memory.seed(`rooms/${ROOM_ID}`, {
    status: "active",
    isLive: true,
    roomType: "community",
    visibility: "public",
    hostId,
    clubId: null,
  });
  memory.seed(`users/${hostId}`, { displayName: "Host", voiceMinutes: 0 });
  for (const uid of participants) {
    memory.seed(`rooms/${ROOM_ID}/participants/${uid}`, {
      userId: uid,
      role: uid === hostId ? "host" : "speaker",
    });
    memory.seed(`users/${uid}`, { displayName: uid, voiceMinutes: 0 });
  }
  return memory;
}

/**
 * `now` is pinned to the fixture instant so the freshness window is evaluated
 * against the scenario's own clock rather than wall-clock test-run time.
 */
function buildHarness({
  memory = seedRoom(new InMemoryFirestore()),
  store = new FirestoreVoiceAchievementStore({ db: memory }),
  now = () => BASE_MS,
} = {}) {
  return {
    memory,
    store,
    handler: createLiveKitAchievementWebhookHandler({
      apiKeyProvider: () => API_KEY,
      apiSecretProvider: () => API_SECRET,
      store,
      now,
    }),
  };
}

async function deliverSigned(handler, body) {
  const { recorded, response } = recordingResponse();
  await handler({
    method: "POST",
    rawBody: Buffer.from(body, "utf8"),
    headers: { authorization: await signedAuthorization(body) },
  }, response);
  return recorded;
}

async function drainAchievementOutbox(memory) {
  const runtime = createAchievementRuntime({
    repository: new FirestoreAchievementRepository({ db: memory }),
    clock: () => PROCESSED_AT,
  });
  const handlers = createAchievementSourceHandlers({
    reader: {
      async markOutboxProcessed(reference) {
        await reference.set({ status: "processed" }, { merge: true });
      },
      async markOutboxInvalid(reference) {
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
}

function sessionPaths(memory) {
  return memory.paths("achievementVoiceSessions/");
}

/* ------------------------------------------------------------------ FIX 3 */

describe("F1 — a close must not mint a document for an unknown session", () => {
  test("participant_left for a room this project does not own writes nothing", async () => {
    const { memory, handler } = buildHarness();
    const recorded = await deliverSigned(handler, participantBody(
      "participant_left",
      BASE_SECONDS + 60,
      { roomName: "no-such-room", roomSid: "RM_ghost", participantSid: "PA_ghost" },
    ));
    assert.equal(recorded.statusCode, 202);
    assert.equal(recorded.body.outcome, "skipped:unknown-session");
    assert.deepEqual(sessionPaths(memory), []);
  });

  test("participant_left for an account that does not exist writes nothing", async () => {
    const { memory, handler } = buildHarness();
    const recorded = await deliverSigned(handler, participantBody(
      "participant_left",
      BASE_SECONDS + 60,
      { identity: "no-such-account", participantSid: "PA_ghost" },
    ));
    assert.equal(recorded.statusCode, 202);
    assert.equal(recorded.body.outcome, "skipped:unknown-session");
    assert.deepEqual(sessionPaths(memory), []);
  });

  test("fifty ghost closes mint zero documents", async () => {
    const { memory, handler } = buildHarness();
    for (let index = 0; index < 50; index += 1) {
      await deliverSigned(handler, participantBody(
        "participant_left",
        BASE_SECONDS + index,
        {
          roomName: "no-such-room",
          roomSid: `RM_ghost_${index}`,
          participantSid: `PA_ghost_${index}`,
          identity: `ghost-account-${index}`,
        },
      ));
    }
    assert.deepEqual(sessionPaths(memory), []);
    assert.deepEqual(memory.paths("achievementOutbox/"), []);
  });

  test("a room name containing a path separator cannot escape the collection", async () => {
    const { memory, handler } = buildHarness();
    const recorded = await deliverSigned(handler, participantBody(
      "participant_left",
      BASE_SECONDS + 60,
      { roomName: "rooms/../users/victim", participantSid: "PA_traverse" },
    ));
    assert.equal(recorded.statusCode, 202);
    assert.equal(recorded.body.outcome, "skipped:unknown-session");
    assert.deepEqual(sessionPaths(memory), []);
  });

  // The legitimate reason awaitingJoin exists at all. This must keep working:
  // the fix bounds WHICH closes may park, not whether parking happens.
  test("an out-of-order close for a real room and account still parks and settles", async () => {
    const { memory, handler } = buildHarness();
    const early = await deliverSigned(
      handler,
      participantBody("participant_left", BASE_SECONDS + 65),
    );
    assert.equal(early.body.outcome, "awaiting-join");
    assert.equal(sessionPaths(memory).length, 1);

    const settled = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
    );
    assert.equal(settled.body.outcome, "closed");
    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 1);
  });
});

/* ------------------------------------------------------------------ FIX 1 */

describe("F2 — one poisoned session must not deny credit to the room", () => {
  const CO_PARTICIPANTS = ["voice-user-a", "voice-user-b", "voice-user-c", "voice-user-d"];

  async function openAllSessions(handler) {
    for (const uid of CO_PARTICIPANTS) {
      const recorded = await deliverSigned(handler, participantBody(
        "participant_joined",
        BASE_SECONDS,
        { identity: uid, participantSid: `PA_${uid}` },
      ));
      assert.equal(recorded.body.outcome, "opened");
    }
  }

  test("room_finished credits every other participant and reports the failure", async () => {
    const memory = seedRoom(new InMemoryFirestore(), { participants: CO_PARTICIPANTS });
    const { handler } = buildHarness({ memory });
    await openAllSessions(handler);

    // Poison exactly one account's private day ledger. This throws
    // deterministically inside _closeInTransaction, so it fails identically on
    // every retry — the case that used to strand everyone ordered after it.
    const poisoned = CO_PARTICIPANTS[1];
    memory.seed(`achievementVoiceDays/${poisoned}/days/${DAY}`, {
      schemaVersion: 999,
      userId: poisoned,
      day: DAY,
      voiceIntervals: [],
      hostIntervals: [],
    });

    const recorded = await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 120));
    assert.equal(recorded.statusCode, 202, "a partial room close must not be a 400");
    assert.equal(recorded.body.outcome, "room-closed:partial");

    await drainAchievementOutbox(memory);
    for (const uid of CO_PARTICIPANTS) {
      const expected = uid === poisoned ? 0 : 2;
      assert.equal(
        memory.data(`users/${uid}`).voiceMinutes,
        expected,
        `${uid} should have ${expected} voiceMinutes`,
      );
    }

    // Every healthy session is closed; only the poisoned one remains open.
    const open = sessionPaths(memory)
      .map((path) => memory.data(path))
      .filter((session) => session.status === "open");
    assert.equal(open.length, 1);
    assert.equal(open[0].userId, poisoned);
  });

  test("the poisoned account is recovered once its ledger is repaired", async () => {
    const memory = seedRoom(new InMemoryFirestore(), { participants: CO_PARTICIPANTS });
    const { handler } = buildHarness({ memory });
    await openAllSessions(handler);
    const poisoned = CO_PARTICIPANTS[1];
    memory.seed(`achievementVoiceDays/${poisoned}/days/${DAY}`, {
      schemaVersion: 999, userId: poisoned, day: DAY,
      voiceIntervals: [], hostIntervals: [],
    });

    await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 120));
    memory.seed(`achievementVoiceDays/${poisoned}/days/${DAY}`, {
      schemaVersion: 1, userId: poisoned, day: DAY,
      voiceIntervals: [], hostIntervals: [],
      voiceSeconds: 0, hostSeconds: 0,
    });

    // Replaying room_finished now recovers the one session left behind, and
    // does not re-credit the sessions that already closed.
    const replay = await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 180));
    assert.equal(replay.body.outcome, "room-closed");
    await drainAchievementOutbox(memory);

    assert.equal(memory.data(`users/${poisoned}`).voiceMinutes, 3);
    for (const uid of CO_PARTICIPANTS.filter((value) => value !== poisoned)) {
      assert.equal(memory.data(`users/${uid}`).voiceMinutes, 2, "no double credit");
    }
  });

  test("a transient failure still aborts the whole delivery so LiveKit retries", async () => {
    const memory = seedRoom(new InMemoryFirestore(), { participants: CO_PARTICIPANTS });
    const store = new FirestoreVoiceAchievementStore({ db: memory });
    const { handler } = buildHarness({ memory, store });
    await openAllSessions(handler);

    const transient = Object.assign(new Error("firestore unavailable"), {
      code: "unavailable",
    });
    const original = store._closeKnownSession.bind(store);
    let calls = 0;
    store._closeKnownSession = async (reference, webhook) => {
      calls += 1;
      if (calls === 2) throw transient;
      return original(reference, webhook);
    };

    const recorded = await deliverSigned(handler, roomFinishedBody(BASE_SECONDS + 120));
    assert.equal(recorded.statusCode, 503);
    assert.deepEqual(recorded.body, {
      accepted: false,
      error: "temporarily-unavailable",
    });
  });
});

/* ------------------------------------------------------------------ FIX 2 */

describe("F3 — a full day ledger must saturate, never refuse the close", () => {
  test("mergeBillableInterval saturates instead of throwing", () => {
    const full = Array.from({ length: MAX_VOICE_INTERVALS_PER_DAY }, (_, index) => ({
      startMs: index * 2000,
      endMs: index * 2000 + 1000,
    }));
    const result = mergeBillableInterval(full, {
      startMs: MAX_VOICE_INTERVALS_PER_DAY * 2000,
      endMs: MAX_VOICE_INTERVALS_PER_DAY * 2000 + 1000,
    });
    assert.equal(result.saturated, true);
    assert.equal(result.addedSeconds, 0);
    assert.equal(result.intervals.length, MAX_VOICE_INTERVALS_PER_DAY);
  });

  test("the 257th session of a day closes with zero credit rather than failing", async () => {
    const memory = seedRoom(new InMemoryFirestore());
    // A day already at the interval bound — reachable by an ordinary phone
    // reconnecting roughly every five minutes for a day.
    const fullLedger = Array.from(
      { length: MAX_VOICE_INTERVALS_PER_DAY },
      (_, index) => ({
        startMs: BASE_MS + index * 4000,
        endMs: BASE_MS + index * 4000 + 1000,
      }),
    );
    memory.seed(`achievementVoiceDays/${UID}/days/${DAY}`, {
      schemaVersion: 1,
      userId: UID,
      day: DAY,
      voiceIntervals: fullLedger,
      hostIntervals: [],
      voiceSeconds: MAX_VOICE_INTERVALS_PER_DAY,
      hostSeconds: 0,
    });
    const joinedAtSeconds = BASE_SECONDS + 7200;
    // The overflow session happens two hours into the day, so the freshness
    // window is evaluated against that instant, not the start of the day.
    const { handler } = buildHarness({ memory, now: () => joinedAtSeconds * 1000 });
    await deliverSigned(handler, participantBody("participant_joined", joinedAtSeconds, {
      participantSid: "PA_overflow",
      joinedAtSeconds,
    }));
    const recorded = await deliverSigned(handler, participantBody(
      "participant_left",
      joinedAtSeconds + 300,
      { participantSid: "PA_overflow", joinedAtSeconds },
    ));

    assert.equal(recorded.statusCode, 202, "a saturated ledger must not be a 400");
    assert.equal(recorded.body.outcome, "closed:ledger-saturated");

    // The session is closed, not abandoned open forever.
    const sessions = sessionPaths(memory).map((path) => memory.data(path));
    assert.deepEqual(sessions.map((session) => session.status), ["closed"]);
    assert.equal(sessions[0].saturated, true);
    assert.equal(sessions[0].creditedVoiceSeconds, 0);

    // The stored ledger stays canonical and bounded.
    const day = memory.data(`achievementVoiceDays/${UID}/days/${DAY}`);
    assert.equal(day.voiceIntervals.length, MAX_VOICE_INTERVALS_PER_DAY);
    assert.deepEqual(memory.paths("achievementOutbox/"), []);
  });

  test("a saturated day does not corrupt the next day's accrual", async () => {
    const memory = seedRoom(new InMemoryFirestore());
    memory.seed(`achievementVoiceDays/${UID}/days/${DAY}`, {
      schemaVersion: 1,
      userId: UID,
      day: DAY,
      voiceIntervals: Array.from(
        { length: MAX_VOICE_INTERVALS_PER_DAY },
        (_, index) => ({
          startMs: BASE_MS + index * 4000,
          endMs: BASE_MS + index * 4000 + 1000,
        }),
      ),
      hostIntervals: [],
      voiceSeconds: MAX_VOICE_INTERVALS_PER_DAY,
      hostSeconds: 0,
    });

    const nextDayMs = Date.parse("2026-08-17T09:00:00.000Z");
    const nextDaySeconds = nextDayMs / 1000;
    const { handler } = buildHarness({ memory, now: () => nextDayMs });

    await deliverSigned(handler, participantBody("participant_joined", nextDaySeconds, {
      participantSid: "PA_nextday",
      joinedAtSeconds: nextDaySeconds,
    }));
    const recorded = await deliverSigned(handler, participantBody(
      "participant_left",
      nextDaySeconds + 120,
      { participantSid: "PA_nextday", joinedAtSeconds: nextDaySeconds },
    ));
    assert.equal(recorded.body.outcome, "closed");

    await drainAchievementOutbox(memory);
    assert.equal(memory.data(`users/${UID}`).voiceMinutes, 2);
  });
});

/* ------------------------------------------------------- max event age */

describe("a signed event outside its freshness window is refused", () => {
  test("an event older than the window is refused and writes nothing", async () => {
    const { memory, handler } = buildHarness({
      now: () => BASE_MS + MAX_WEBHOOK_EVENT_AGE_MS + 1000,
    });
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
    );
    assert.equal(recorded.statusCode, 400);
    assert.deepEqual(recorded.body, { accepted: false, error: "invalid-webhook" });
    assert.deepEqual(sessionPaths(memory), []);
  });

  test("a future-dated event beyond the window is refused too", async () => {
    const { memory, handler } = buildHarness({
      now: () => BASE_MS - MAX_WEBHOOK_EVENT_AGE_MS - 1000,
    });
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
    );
    assert.equal(recorded.statusCode, 400);
    assert.deepEqual(sessionPaths(memory), []);
  });

  test("an event inside the window is still accepted", async () => {
    const { handler } = buildHarness({
      now: () => BASE_MS + MAX_WEBHOOK_EVENT_AGE_MS - 1000,
    });
    const recorded = await deliverSigned(
      handler,
      participantBody("participant_joined", BASE_SECONDS),
    );
    assert.equal(recorded.statusCode, 202);
    assert.equal(recorded.body.outcome, "opened");
  });
});

/* ------------------------------------------ fatal vs retryable classification */

describe("fatal failures are not reported as retryable", () => {
  function throwingHandler(error) {
    return createLiveKitAchievementWebhookHandler({
      apiKeyProvider: () => API_KEY,
      apiSecretProvider: () => API_SECRET,
      store: { async handle() { throw error; } },
      now: () => BASE_MS,
    });
  }

  const permanent = [
    ["RangeError", new RangeError("Achievement counter exceeds the safe integer range.")],
    ["TypeError", new TypeError("A known achievement metric is required.")],
    ["AchievementOutboxValidationError",
      new AchievementOutboxValidationError("tampered outbox record")],
  ];

  for (const [name, error] of permanent) {
    test(`${name} is answered 400 so LiveKit stops retrying`, async () => {
      const recorded = await deliverSigned(
        throwingHandler(error),
        participantBody("participant_joined", BASE_SECONDS),
      );
      assert.equal(recorded.statusCode, 400);
      assert.deepEqual(recorded.body, { accepted: false, error: "invalid-source" });
    });
  }

  test("a genuinely transient failure is still answered 503", async () => {
    const recorded = await deliverSigned(
      throwingHandler(Object.assign(new Error("deadline exceeded"), {
        code: "deadline-exceeded",
      })),
      participantBody("participant_joined", BASE_SECONDS),
    );
    assert.equal(recorded.statusCode, 503);
    assert.deepEqual(recorded.body, {
      accepted: false,
      error: "temporarily-unavailable",
    });
  });

  test("no rejection body names the account or room it failed for", async () => {
    for (const [, error] of permanent) {
      const recorded = await deliverSigned(
        throwingHandler(error),
        participantBody("participant_joined", BASE_SECONDS),
      );
      const serialized = JSON.stringify(recorded.body);
      for (const secret of [UID, ROOM_ID, ROOM_SID, "PA_voice_1"]) {
        assert.ok(!serialized.includes(secret), `leaked ${secret}`);
      }
    }
  });
});

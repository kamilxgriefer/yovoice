const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { describe, test } = require("node:test");

const { AccessToken } = require("livekit-server-sdk");

const {
  MAX_VOICE_DAY_BUCKETS,
  MAX_VOICE_INTERVALS_PER_DAY,
  VoiceWebhookValidationError,
  closeVoiceSession,
  mergeBillableInterval,
  normalizeLiveKitWebhookEvent,
  planVoiceSessionCredit,
  receiveSignedLiveKitWebhook,
  splitIntervalByUtcDay,
  voiceAchievementEvents,
  voiceSessionFromJoin,
} = require("../achievements/voice_webhook");

const API_KEY = "achievement-webhook-key";
const API_SECRET = "achievement-webhook-secret-at-least-32-characters";
const JOINED_SECONDS = 1786881600;
const JOINED_MS = JOINED_SECONDS * 1000;

function webhookBody(overrides = {}) {
  return JSON.stringify({
    event: "participant_joined",
    id: "EV_achievement_join",
    created_at: JOINED_SECONDS,
    room: { sid: "RM_achievement", name: "room-1" },
    participant: {
      sid: "PA_achievement",
      identity: "voice-user",
      joined_at: JOINED_SECONDS,
      joined_at_ms: JOINED_MS,
    },
    ...overrides,
  });
}

async function authorizationFor(body) {
  const token = new AccessToken(API_KEY, API_SECRET, { ttl: "5m" });
  token.sha256 = createHash("sha256").update(body).digest("base64");
  return token.toJwt();
}

function normalized(type, createdAtMs, overrides = {}) {
  return {
    type,
    eventId: `EV_${type}_${createdAtMs}`,
    roomSid: "RM_achievement",
    roomName: "room-1",
    createdAtMs,
    participantSid: "PA_achievement",
    participantIdentity: "voice-user",
    joinedAtMs: JOINED_MS,
    ...overrides,
  };
}

describe("signed LiveKit achievement adapter", () => {
  test("accepts an authentic raw webhook and normalizes canonical identities", async () => {
    const body = webhookBody();
    const event = await receiveSignedLiveKitWebhook({
      apiKey: API_KEY,
      apiSecret: API_SECRET,
      rawBody: Buffer.from(body),
      authorization: await authorizationFor(body),
      // The fixture is a fixed instant, so the freshness window is evaluated
      // against that instant rather than against wall-clock test-run time.
      now: () => JOINED_MS,
    });
    assert.deepEqual(event, {
      type: "participant_joined",
      eventId: "EV_achievement_join",
      roomSid: "RM_achievement",
      roomName: "room-1",
      createdAtMs: JOINED_MS,
      participantSid: "PA_achievement",
      participantIdentity: "voice-user",
      joinedAtMs: JOINED_MS,
    });
  });

  test("missing signature, tampered body and pre-parsed JSON fail closed", async () => {
    const body = webhookBody();
    const authorization = await authorizationFor(body);
    await assert.rejects(
      receiveSignedLiveKitWebhook({
        apiKey: API_KEY,
        apiSecret: API_SECRET,
        rawBody: body,
        authorization: "",
      }),
      VoiceWebhookValidationError,
    );
    await assert.rejects(
      receiveSignedLiveKitWebhook({
        apiKey: API_KEY,
        apiSecret: API_SECRET,
        rawBody: `${body} `,
        authorization,
      }),
      /checksum/u,
    );
    await assert.rejects(
      receiveSignedLiveKitWebhook({
        apiKey: API_KEY,
        apiSecret: API_SECRET,
        rawBody: JSON.parse(body),
        authorization,
      }),
      VoiceWebhookValidationError,
    );
  });

  test("token issuance and unrelated webhook types can never represent voice time", () => {
    assert.equal(normalizeLiveKitWebhookEvent({ event: "token_issued" }), null);
    assert.equal(normalizeLiveKitWebhookEvent({ event: "track_published" }), null);
  });

  test("join binds host status exclusively to the canonical Room root", () => {
    const join = normalized("participant_joined", JOINED_MS);
    const session = voiceSessionFromJoin(join, {
      id: "room-1",
      hostId: "voice-user",
    });
    assert.equal(session.isHost, true);
    assert.equal(session.userId, "voice-user");
    assert.throws(
      () => voiceSessionFromJoin(join, { id: "forged-room", hostId: "voice-user" }),
      VoiceWebhookValidationError,
    );

    const opaqueUid = " voice-user ";
    const opaqueJoin = normalizeLiveKitWebhookEvent({
      event: "participant_joined",
      id: "EV_opaque_uid",
      createdAt: BigInt(JOINED_SECONDS),
      room: { sid: "RM_achievement", name: "room-1" },
      participant: {
        sid: "PA_opaque_uid",
        identity: opaqueUid,
        joinedAtMs: BigInt(JOINED_MS),
      },
    });
    const opaqueSession = voiceSessionFromJoin(opaqueJoin, {
      id: "room-1",
      hostId: opaqueUid,
    });
    assert.equal(opaqueSession.userId, opaqueUid);
    assert.equal(opaqueSession.isHost, true);
  });

  test("leave closes a matching session once and caps implausible duration", () => {
    const session = voiceSessionFromJoin(
      normalized("participant_joined", JOINED_MS),
      { id: "room-1", hostId: "voice-user" },
    );
    const normal = closeVoiceSession(
      session,
      normalized("participant_left", JOINED_MS + 90_000),
    );
    assert.equal(normal.endMs - normal.startMs, 90_000);
    assert.equal(normal.capped, false);

    const capped = closeVoiceSession(
      session,
      normalized("participant_left", JOINED_MS + 10_000_000),
      { maximumSessionSeconds: 60 },
    );
    assert.equal(capped.endMs - capped.startMs, 60_000);
    assert.equal(capped.capped, true);

    assert.equal(closeVoiceSession(
      session,
      normalized("participant_left", JOINED_MS - 1),
    ), null);
    assert.equal(closeVoiceSession(
      session,
      normalized("participant_left", JOINED_MS + 1000, {
        participantSid: "other-participant",
      }),
    ), null);
  });

  test("room_finished safely closes a known session without client participant data", () => {
    const session = voiceSessionFromJoin(
      normalized("participant_joined", JOINED_MS),
      { id: "room-1", hostId: "someone-else" },
    );
    const closed = closeVoiceSession(session, {
      type: "room_finished",
      eventId: "EV_room_finished",
      roomSid: "RM_achievement",
      roomName: "room-1",
      createdAtMs: JOINED_MS + 10_000,
    });
    assert.equal(closed.endMs - closed.startMs, 10_000);
  });

  test("overlapping sessions credit wall-clock union, not multiplied tab time", () => {
    const firstSession = {
      userId: "voice-user",
      roomId: "room-1",
      roomSid: "RM_achievement",
      participantSid: "PA_first",
      joinedAtMs: JOINED_MS,
      isHost: true,
    };
    const first = planVoiceSessionCredit({
      session: firstSession,
      closeWebhook: normalized("participant_left", JOINED_MS + 90_000, {
        participantSid: "PA_first",
      }),
    });
    assert.equal(first.voiceSecondsAdded, 90);
    assert.equal(first.hostSecondsAdded, 90);

    const secondSession = {
      ...firstSession,
      participantSid: "PA_second",
      joinedAtMs: JOINED_MS + 30_000,
      isHost: false,
    };
    const second = planVoiceSessionCredit({
      session: secondSession,
      closeWebhook: normalized("participant_left", JOINED_MS + 120_000, {
        participantSid: "PA_second",
        joinedAtMs: JOINED_MS + 30_000,
      }),
      voiceIntervalsByDay: first.voiceIntervalsByDay,
      hostIntervalsByDay: first.hostIntervalsByDay,
    });
    assert.equal(second.voiceSecondsAdded, 30);
    assert.equal(second.hostSecondsAdded, 0);
    assert.equal(
      second.voiceIntervalsByDay["2026-08-16"][0].endMs -
        second.voiceIntervalsByDay["2026-08-16"][0].startMs,
      120_000,
    );
  });

  test("UTC midnight splitting preserves every billable second", () => {
    const start = Date.parse("2026-08-16T23:59:30.000Z");
    const end = Date.parse("2026-08-17T00:00:30.000Z");
    assert.deepEqual(splitIntervalByUtcDay({ startMs: start, endMs: end }), [
      { day: "2026-08-16", startMs: start, endMs: Date.parse("2026-08-17T00:00:00Z") },
      { day: "2026-08-17", startMs: Date.parse("2026-08-17T00:00:00Z"), endMs: end },
    ]);
  });

  test("sub-second fragments accumulate without being rounded into free time", () => {
    const first = mergeBillableInterval([], { startMs: 0, endMs: 500 });
    assert.equal(first.addedSeconds, 0);
    const second = mergeBillableInterval(first.intervals, {
      startMs: 500,
      endMs: 1000,
    });
    assert.equal(second.addedSeconds, 1);
    assert.throws(
      () => mergeBillableInterval([{ startMs: 10, endMs: 5 }], {
        startMs: 1000,
        endMs: 2000,
      }),
      VoiceWebhookValidationError,
    );
  });

  test("reconnect spam cannot grow a daily interval ledger without bound", () => {
    const fullLedger = Array.from(
      { length: MAX_VOICE_INTERVALS_PER_DAY },
      (_, index) => ({
        startMs: index * 2000,
        endMs: index * 2000 + 1000,
      }),
    );
    // Growth past the bound SATURATES rather than throwing: the ledger stops
    // accepting new intervals, but the session must still be closeable. When
    // this threw, every close past the 256th disjoint interval in a UTC day
    // was refused with a non-retryable 400 and left its session open forever.
    const saturated = mergeBillableInterval(fullLedger, {
      startMs: MAX_VOICE_INTERVALS_PER_DAY * 2000,
      endMs: MAX_VOICE_INTERVALS_PER_DAY * 2000 + 1000,
    });
    assert.equal(saturated.saturated, true);
    assert.equal(saturated.addedSeconds, 0);
    assert.equal(saturated.intervals.length, MAX_VOICE_INTERVALS_PER_DAY);

    // Already-corrupt storage past the bound is still a loud failure: that is
    // stored-state corruption, not ordinary growth, and it is unreachable now
    // that growth saturates at the bound.
    assert.throws(
      () => mergeBillableInterval([...fullLedger, {
        startMs: MAX_VOICE_INTERVALS_PER_DAY * 2000,
        endMs: MAX_VOICE_INTERVALS_PER_DAY * 2000 + 1000,
      }], {
        startMs: 0,
        endMs: 1000,
      }),
      /safe bound/u,
    );

    const session = {
      userId: "voice-user",
      roomId: "room-1",
      roomSid: "RM_achievement",
      participantSid: "PA_achievement",
      joinedAtMs: JOINED_MS,
      isHost: false,
    };
    const unrelatedDays = Object.fromEntries(Array.from(
      { length: MAX_VOICE_DAY_BUCKETS + 1 },
      (_, index) => [`2026-08-${String(index + 1).padStart(2, "0")}`, []],
    ));
    assert.throws(
      () => planVoiceSessionCredit({
        session,
        closeWebhook: normalized("participant_left", JOINED_MS + 1000),
        voiceIntervalsByDay: unrelatedDays,
      }),
      /safe day bound/u,
    );
  });

  test("credit plan emits seconds events only after a signed, closed session", () => {
    const session = {
      userId: "voice-user",
      roomId: "room-1",
      roomSid: "RM_achievement",
      participantSid: "PA_achievement",
      joinedAtMs: JOINED_MS,
      isHost: true,
    };
    const plan = planVoiceSessionCredit({
      session,
      closeWebhook: normalized("participant_left", JOINED_MS + 65_000),
    });
    const events = voiceAchievementEvents(session, plan);
    assert.deepEqual(events.map((event) => [event.metric, event.delta]), [
      ["voiceSeconds", 65],
      ["hostSeconds", 65],
    ]);
    assert.deepEqual(voiceAchievementEvents(session, null), []);
  });
});

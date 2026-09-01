const assert = require("node:assert/strict");
const { beforeEach, describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
process.env.LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY ?? "devkey123";
process.env.LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET ??
  "devsecret123devsecret123devsecret123";
process.env.LIVEKIT_URL = process.env.LIVEKIT_URL ??
  "wss://yovoice-3f7j9fb7.livekit.cloud";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DIRECT_CALL_ATTEMPT_LIMITS,
  DIRECT_VIDEO_PROTOCOL_VERSION,
  DIRECT_CALL_START_LIMITS,
  DIRECT_CALL_TOKEN_RATE_LIMIT,
  DIRECT_CALL_TOKEN_RATE_WINDOW_MS,
  authorizeDirectCallVoice,
  directCallStartLimitReference,
  directCallAttemptRateReference,
  directCallRoomName,
  createDirectCallTokenHandler,
  expireDirectCall,
  expireDirectCallBatch,
  startDirectCall,
  acceptDirectCall,
  cancelDirectCall,
  declineDirectCall,
  endDirectCall,
  requireDirectCallMediaType,
  recordAuthorizedDirectCallSession,
} = require("../calls/direct_calls");

const db = getFirestore();
const P = "dct-";
const CALLER = `${P}caller`;
const CALLEE = `${P}callee`;

function request(uid, data, verified = true) {
  return { auth: { uid, token: { email_verified: verified } }, data };
}

function tokenHarness() {
  const state = { constructed: 0, signed: 0, grants: [] };
  class FakeAccessToken {
    constructor() {
      state.constructed += 1;
    }

    addGrant(grant) {
      state.grants.push(grant);
    }

    async toJwt() {
      state.signed += 1;
      return `direct-test-jwt-${state.signed}`;
    }
  }
  return { state, AccessTokenClass: FakeAccessToken };
}

function tokenOptions(harness, nowMs = Date.UTC(2026, 8, 1, 9, 0, 0)) {
  return {
    AccessTokenClass: harness.AccessTokenClass,
    apiKey: () => "test-key",
    apiSecret: () => "test-secret-long-enough",
    serverUrl: () => "wss://rtc.example.test",
    clock: () => nowMs,
  };
}

async function wipe() {
  const [calls, controlJobs, operationLedgers, rateLimits] = await Promise.all([
    db.collection("directCalls").get(),
    db.collection("directCallControlOutbox").get(),
    db.collection("integrityOperationLedgers")
      .where("ownerId", "in", [CALLER, CALLEE]).get(),
    db.collection("privateRateLimits")
      .where("ownerId", "in", [CALLER, CALLEE]).get(),
  ]);
  await Promise.all([
    ...calls.docs
      .filter((document) => {
        const data = document.data() ?? {};
        return [data.callerId, data.calleeId].some((uid) =>
          String(uid ?? "").startsWith(P),
        );
      })
      .map((document) => db.recursiveDelete(document.ref)),
    db.recursiveDelete(db.doc(`users/${CALLER}`)),
    db.recursiveDelete(db.doc(`users/${CALLEE}`)),
    db.recursiveDelete(db.doc(`users/${P}random-target`)),
    db.doc(`restrictions/${CALLER}`).delete(),
    db.doc(`restrictions/${CALLEE}`).delete(),
    db.recursiveDelete(db.doc(`friendshipGuards/${CALLER}`)),
    db.recursiveDelete(db.doc(`friendshipGuards/${CALLEE}`)),
    db.recursiveDelete(db.doc(`friendshipGuards/${P}random-target`)),
    db.recursiveDelete(db.doc(`activeVoiceSessions/${CALLER}`)),
    db.recursiveDelete(db.doc(`activeVoiceSessions/${CALLEE}`)),
    db.doc(`conversations/${P}conversation`).delete(),
    db.doc(`conversations/${P}random-conversation`).delete(),
    db.doc(`directCallLocks/${CALLER}`).delete(),
    db.doc(`directCallLocks/${CALLEE}`).delete(),
    directCallStartLimitReference("caller", CALLER).delete(),
    directCallStartLimitReference("callee", CALLEE).delete(),
    directCallStartLimitReference("pair", CALLER, CALLEE).delete(),
    ...operationLedgers.docs.map((document) => document.ref.delete()),
    ...rateLimits.docs.map((document) => document.ref.delete()),
    ...controlJobs.docs
      .filter((document) => {
        const ids = document.data()?.participantIds;
        return Array.isArray(ids) && ids.some((uid) =>
          String(uid ?? "").startsWith(P),
        );
      })
      .map((document) => document.ref.delete()),
  ]);
}

async function seedProfiles() {
  await Promise.all([
    db.doc(`users/${CALLER}`).set({
      uid: CALLER,
      displayName: "Caller",
      photoUrl: "https://example.com/caller.jpg",
      banned: false,
      disabled: false,
    }),
    db.doc(`users/${CALLEE}`).set({
      uid: CALLEE,
      displayName: "Callee",
      photoUrl: "https://example.com/callee.jpg",
      banned: false,
      disabled: false,
    }),
  ]);
}

async function seedFriendship() {
  const establishedAt = Timestamp.now();
  await Promise.all([
    db.doc(`friendshipGuards/${CALLER}/friends/${CALLEE}`).set({
      ownerId: CALLER,
      friendId: CALLEE,
      schemaVersion: 1,
      establishedAt,
    }),
    db.doc(`friendshipGuards/${CALLEE}/friends/${CALLER}`).set({
      ownerId: CALLEE,
      friendId: CALLER,
      schemaVersion: 1,
      establishedAt,
    }),
  ]);
}

async function seedConversation() {
  await db.doc(`conversations/${P}conversation`).set({
    participantIds: [CALLER, CALLEE].sort(),
  });
}

async function seedVideoCapableDevice({
  userId = CALLEE,
  token = "video-capable-device",
  protocol = DIRECT_VIDEO_PROTOCOL_VERSION,
} = {}) {
  await db.doc(`users/${userId}/fcmTokens/${token}`).set({
    platform: "ios",
    directVideoProtocol: protocol,
    updatedAt: Timestamp.now(),
  });
}

async function start(requestId = null, mediaType = undefined) {
  return startDirectCall.run(request(CALLER, {
    calleeId: CALLEE,
    conversationId: `${P}conversation`,
    ...(requestId === null ? {} : { requestId }),
    ...(mediaType === undefined ? {} : { mediaType }),
  }));
}

async function installReplacementCall(callId) {
  const expiresAt = Timestamp.fromMillis(Date.now() + 60_000);
  await Promise.all([
    db.doc(`directCalls/${callId}`).set({
      callerId: CALLER,
      calleeId: CALLEE,
      participantIds: [CALLER, CALLEE].sort(),
      status: "ringing",
      expiresAt,
    }),
    db.doc(`directCallLocks/${CALLER}`).set({
      userId: CALLER,
      callId,
      status: "ringing",
      expiresAt,
    }),
    db.doc(`directCallLocks/${CALLEE}`).set({
      userId: CALLEE,
      callId,
      status: "ringing",
      expiresAt,
    }),
  ]);
}

beforeEach(async () => {
  await wipe();
  await seedProfiles();
  await seedFriendship();
  await seedConversation();
  await seedVideoCapableDevice();
});

describe("direct call signaling", () => {
  test("creates one canonical ringing call, inbox signal, push carrier and locks", async () => {
    const result = await start();
    const [
      call,
      signal,
      notification,
      callerLock,
      calleeLock,
      callerLimit,
      calleeLimit,
      pairLimit,
    ] =
      await db.getAll(
        db.doc(`directCalls/${result.callId}`),
        db.doc(`users/${CALLEE}/incomingCalls/${result.callId}`),
        db.doc(`users/${CALLEE}/notifications/directCall_${result.callId}`),
        db.doc(`directCallLocks/${CALLER}`),
        db.doc(`directCallLocks/${CALLEE}`),
        directCallStartLimitReference("caller", CALLER),
        directCallStartLimitReference("callee", CALLEE),
        directCallStartLimitReference("pair", CALLER, CALLEE),
      );

    assert.equal(call.data().status, "ringing");
    assert.equal(call.data().mediaType, "audio");
    assert.deepEqual(call.data().participantIds, [CALLEE, CALLER].sort());
    assert.equal(call.data().caller.displayName, "Caller");
    assert.equal(call.data().callee.displayName, "Callee");
    assert.equal(call.data().caller.photoUrl, null);
    assert.equal(call.data().callee.photoUrl, null);
    assert.equal(signal.data().callerPhotoUrl, null);
    assert.equal(signal.data().callerId, CALLER);
    assert.equal(signal.data().mediaType, "audio");
    assert.equal(notification.data().type, "directCall");
    assert.equal(notification.data().bellSuppressed, true);
    assert.equal(callerLock.data().callId, result.callId);
    assert.equal(calleeLock.data().callId, result.callId);
    assert.equal(callerLimit.data().scope, "caller");
    assert.equal(calleeLimit.data().scope, "callee");
    assert.equal(pairLimit.data().scope, "pair");
    assert.equal(callerLimit.data().startedAt.length, 1);
    assert.equal(calleeLimit.data().startedAt.length, 1);
    assert.equal(pairLimit.data().startedAt.length, 1);
  });

  test("video is explicit, immutable and propagated to the private signal", async () => {
    const requestId = "video-call-start-1";
    const result = await start(requestId, "video");
    const [call, signal, notification] = await db.getAll(
      db.doc(`directCalls/${result.callId}`),
      db.doc(`users/${CALLEE}/incomingCalls/${result.callId}`),
      db.doc(`users/${CALLEE}/notifications/directCall_${result.callId}`),
    );
    assert.equal(call.data().mediaType, "video");
    assert.equal(signal.data().mediaType, "video");
    assert.equal(notification.data().targetLabel, "Incoming video call");

    await assert.rejects(
      () => start(requestId, "audio"),
      (error) => error?.code === "already-exists",
    );
  });

  test("video fails closed when no recipient device advertises support", async () => {
    await db.recursiveDelete(db.doc(`users/${CALLEE}/fcmTokens/video-capable-device`));

    await assert.rejects(
      () => start("video-without-capability", "video"),
      (error) => error?.code === "failed-precondition" &&
        /updates YO Voice on every active device/u.test(error.message),
    );
    assert.equal((await db.collection("directCalls")
      .where("callerId", "==", CALLER).get()).empty, true);
  });

  test("video fails closed when any registered recipient device is legacy", async () => {
    await db.doc(`users/${CALLEE}/fcmTokens/legacy-device`).set({
      platform: "android",
      updatedAt: Timestamp.now(),
    });

    await assert.rejects(
      () => start("video-with-mixed-devices", "video"),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("audio stays compatible with recipients that use a legacy client", async () => {
    await db.recursiveDelete(db.doc(`users/${CALLEE}/fcmTokens/video-capable-device`));
    await db.doc(`users/${CALLEE}/fcmTokens/legacy-device`).set({
      platform: "android",
      updatedAt: Timestamp.now(),
    });

    const result = await start("audio-with-legacy-device", "audio");
    assert.equal(
      (await db.doc(`directCalls/${result.callId}`).get()).data().mediaType,
      "audio",
    );
  });

  test("unsupported media types fail closed before signaling", async () => {
    await assert.rejects(
      () => start(null, "screen"),
      (error) => error?.code === "invalid-argument",
    );
    assert.throws(
      () => requireDirectCallMediaType("screen"),
      (error) => error?.code === "invalid-argument",
    );
  });

  test("new audio clients replay legacy idempotency hashes", async () => {
    const requestId = "legacy-audio-replay-1";
    const legacy = await start(requestId);
    const replay = await start(requestId, "audio");
    assert.deepEqual(replay, legacy);
  });

  test("legacy audio clients replay canonical audio idempotency hashes", async () => {
    const requestId = "canonical-audio-replay-1";
    const canonical = await start(requestId, "audio");
    const replay = await start(requestId);
    assert.deepEqual(replay, canonical);
  });

  test("only bilateral canonical friends may call", async () => {
    await db.doc(`friendshipGuards/${CALLEE}/friends/${CALLER}`).delete();
    await assert.rejects(
      start,
      (error) => error?.code === "failed-precondition",
    );
  });

  test("the conversation must belong to the exact caller and callee", async () => {
    await db.doc(`conversations/${P}conversation`).set({
      participantIds: [CALLEE, `${P}third`],
    });
    await assert.rejects(
      start,
      (error) => error?.code === "failed-precondition",
    );
  });

  test("blocks, restrictions and inactive accounts fail before signaling", async () => {
    await db.doc(`users/${CALLEE}/blocked/${CALLER}`).set({ createdAt: Timestamp.now() });
    await assert.rejects(start, (error) => error?.code === "failed-precondition");
    await db.doc(`users/${CALLEE}/blocked/${CALLER}`).delete();

    await db.doc(`restrictions/${CALLER}`).set({
      type: "communicationMute",
      expiresAt: null,
    });
    await assert.rejects(start, (error) => error?.code === "permission-denied");
    await db.doc(`restrictions/${CALLER}`).delete();

    await db.doc(`users/${CALLEE}`).update({ disabled: true });
    await assert.rejects(start, (error) => error?.code === "permission-denied");
  });

  test("one active lock prevents call spam and double ringing", async () => {
    await start();
    await assert.rejects(start, (error) => error?.code === "already-exists");
  });

  test("start then cancel cannot bypass the rolling pair cooldown", async () => {
    const first = await start();
    assert.deepEqual(
      await cancelDirectCall.run(request(CALLER, { callId: first.callId })),
      { callId: first.callId, status: "cancelled" },
    );
    assert.deepEqual(
      await cancelDirectCall.run(request(CALLER, { callId: first.callId })),
      { callId: first.callId, status: "cancelled" },
    );

    await assert.rejects(
      start,
      (error) => error?.code === "resource-exhausted",
    );
    const calls = await db.collection("directCalls")
      .where("callerId", "==", CALLER)
      .get();
    assert.equal(calls.size, 1);
  });

  test("rolling pair limit prunes expired starts but rejects a full live window", async () => {
    const config = DIRECT_CALL_START_LIMITS.pair;
    const limit = directCallStartLimitReference("pair", CALLER, CALLEE);
    const now = Date.now();
    await limit.set({
      schemaVersion: 1,
      scope: "pair",
      startedAt: Array.from(
        { length: config.maxEvents },
        (_, index) => Timestamp.fromMillis(
          now - config.cooldownMs - 1000 - index,
        ),
      ),
      updatedAt: Timestamp.fromMillis(now - config.cooldownMs - 1000),
    });
    await assert.rejects(
      start,
      (error) => error?.code === "resource-exhausted",
    );

    await limit.set({
      schemaVersion: 1,
      scope: "pair",
      startedAt: [Timestamp.fromMillis(now - config.windowMs - 1000)],
      updatedAt: Timestamp.fromMillis(now - config.windowMs - 1000),
    });
    const result = await start();
    assert.equal(result.status, "ringing");
    const refreshed = (await limit.get()).data();
    assert.equal(refreshed.startedAt.length, 1);
  });

  test("a lost start response replays the same canonical ringing call", async () => {
    const requestId = "call-start-lost-response-1";
    const first = await start(requestId);
    const replay = await start(requestId);

    assert.deepEqual(replay, first);
    const calls = await db.collection("directCalls")
      .where("callerId", "==", CALLER)
      .get();
    assert.equal(calls.size, 1);
    assert.equal(calls.docs[0].id, first.callId);
    assert.equal(calls.docs[0].data().startRequestId, requestId);
    assert.equal(
      (await directCallAttemptRateReference("start", CALLER).get()).data().count,
      1,
    );

    const conflictingStart = () => startDirectCall.run(request(CALLER, {
        calleeId: CALLEE,
        conversationId: `${P}other-conversation`,
        requestId,
      }));
    await assert.rejects(
      conflictingStart,
      (error) => error?.code === "already-exists",
    );
    const limit = DIRECT_CALL_ATTEMPT_LIMITS.start.maxEvents;
    assert.equal(
      (await directCallAttemptRateReference("start", CALLER).get()).data().count,
      2,
    );
    for (let charged = 2; charged < limit; charged += 1) {
      await assert.rejects(
        conflictingStart,
        (error) => error?.code === "already-exists",
      );
      assert.equal(
        (await directCallAttemptRateReference("start", CALLER).get())
          .data().count,
        charged + 1,
      );
    }
    await assert.rejects(
      conflictingStart,
      (error) => error?.code === "resource-exhausted",
    );
    assert.equal(
      (await directCallAttemptRateReference("start", CALLER).get()).data().count,
      limit,
    );
  });

  test("concurrent retries with one requestId create one call", async () => {
    const results = await Promise.all([
      start("call-start-concurrent-1"),
      start("call-start-concurrent-1"),
    ]);
    assert.equal(results[0].callId, results[1].callId);
    const calls = await db.collection("directCalls")
      .where("callerId", "==", CALLER)
      .get();
    assert.equal(calls.size, 1);
    const charged = (await directCallAttemptRateReference("start", CALLER).get())
      .data().count;
    assert.ok(charged >= 1 && charged <= 2);
    assert.deepEqual(
      await start("call-start-concurrent-1"),
      results[0],
    );
    assert.equal(
      (await directCallAttemptRateReference("start", CALLER).get()).data().count,
      charged,
    );
  });

  test("100 random denied starts stop at the committed actor-wide cap", async () => {
    const targetId = `${P}random-target`;
    const conversationId = `${P}random-conversation`;
    const limit = DIRECT_CALL_ATTEMPT_LIMITS.start.maxEvents;
    for (let index = 0; index < 100; index += 1) {
      await assert.rejects(
        startDirectCall.run(request(CALLER, {
          calleeId: targetId,
          conversationId,
          mediaType: "audio",
          requestId: `missing-target-${String(index).padStart(4, "0")}`,
        })),
        (error) => index < limit
          ? error?.code === "not-found"
          : error?.code === "resource-exhausted",
      );
    }
    const attempt = await directCallAttemptRateReference("start", CALLER).get();
    assert.equal(attempt.data().count, limit);
    assert.equal(
      (await directCallStartLimitReference("caller", CALLER).get()).exists,
      false,
    );

    // Make the formerly missing target fully valid. N+1 still stops in the
    // preflight transaction, before this graph can be consulted.
    const establishedAt = Timestamp.now();
    await Promise.all([
      db.doc(`users/${targetId}`).set({
        uid: targetId,
        displayName: "Now valid",
        banned: false,
        disabled: false,
      }),
      db.doc(`friendshipGuards/${CALLER}/friends/${targetId}`).set({
        ownerId: CALLER,
        friendId: targetId,
        schemaVersion: 1,
        establishedAt,
      }),
      db.doc(`friendshipGuards/${targetId}/friends/${CALLER}`).set({
        ownerId: targetId,
        friendId: CALLER,
        schemaVersion: 1,
        establishedAt,
      }),
      db.doc(`conversations/${conversationId}`).set({
        participantIds: [CALLER, targetId].sort(),
      }),
    ]);
    await assert.rejects(
      startDirectCall.run(request(CALLER, {
        calleeId: targetId,
        conversationId,
        mediaType: "audio",
        requestId: "valid-after-attempt-cap",
      })),
      (error) => error?.code === "resource-exhausted",
    );
  });

  test("callee accepts, both token authorities become active, and either side ends", async () => {
    const result = await start();
    assert.deepEqual(
      await acceptDirectCall.run(request(CALLEE, { callId: result.callId })),
      { callId: result.callId, status: "active" },
    );
    assert.deepEqual(
      await acceptDirectCall.run(request(CALLEE, { callId: result.callId })),
      { callId: result.callId, status: "active" },
    );
    const active = await db.doc(`directCalls/${result.callId}`).get();
    assert.equal(active.data().status, "active");
    assert.equal(
      (await db.doc(`users/${CALLEE}/notifications/directCall_${result.callId}`).get())
        .exists,
      false,
    );

    const callerAccess = await db.runTransaction((transaction) =>
      authorizeDirectCallVoice(result.callId, request(CALLER, {}).auth, transaction),
    );
    const calleeAccess = await db.runTransaction((transaction) =>
      authorizeDirectCallVoice(result.callId, request(CALLEE, {}).auth, transaction),
    );
    assert.deepEqual(callerAccess.participants, calleeAccess.participants);

    await endDirectCall.run(request(CALLER, { callId: result.callId }));
    const ended = await db.doc(`directCalls/${result.callId}`).get();
    assert.equal(ended.data().status, "ended");
    assert.equal((await db.doc(`directCallLocks/${CALLER}`).get()).exists, false);
    const outbox = await db.doc(`directCallControlOutbox/${result.callId}`).get();
    assert.equal(outbox.data().roomName, directCallRoomName(result.callId));
  });

  test("end commits and queues teardown when the inbox mirror is absent", async () => {
    const result = await start(null, "video");
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    await db.doc(`users/${CALLEE}/incomingCalls/${result.callId}`).delete();

    assert.deepEqual(
      await endDirectCall.run(request(CALLER, { callId: result.callId })),
      { callId: result.callId, status: "ended" },
    );
    assert.equal(
      (await db.doc(`directCalls/${result.callId}`).get()).data().status,
      "ended",
    );
    assert.equal((await db.doc(`directCallLocks/${CALLER}`).get()).exists, false);
    assert.equal((await db.doc(`directCallLocks/${CALLEE}`).get()).exists, false);
    assert.equal(
      (await db.doc(`directCallControlOutbox/${result.callId}`).get()).exists,
      true,
    );
  });

  for (const [mediaType, expectedSources] of [
    ["audio", ["microphone"]],
    ["video", ["microphone", "camera"]],
  ]) {
    test(`${mediaType} token exposes only its server-authorized sources`, async () => {
      const result = await start(null, mediaType);
      await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
      const response = await createDirectCallTokenHandler(
        request(CALLER, { callId: result.callId }),
      );
      assert.deepEqual(response.permissions.canPublishSources, expectedSources);
      assert.equal(response.permissions.canPublishSources.includes("screen_share"), false);
      assert.equal(response.permissions.canPublishSources.includes("screen_share_audio"), false);
    });
  }

  test("100 blocked token retries stop before graph and JWT after N", async () => {
    const result = await start("blocked-token-call-0001");
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    const block = db.doc(`users/${CALLEE}/blocked/${CALLER}`);
    await block.set({ createdAt: Timestamp.now() });
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const limit = DIRECT_CALL_ATTEMPT_LIMITS.token.maxEvents;

    for (let index = 0; index < limit; index += 1) {
      await assert.rejects(
        createDirectCallTokenHandler(
          request(CALLER, { callId: result.callId }),
          options,
        ),
        (error) => error?.code === "failed-precondition",
      );
    }
    await block.delete();
    for (let index = limit; index < 100; index += 1) {
      await assert.rejects(
        createDirectCallTokenHandler(
          request(CALLER, { callId: result.callId }),
          options,
        ),
        (error) => error?.code === "resource-exhausted",
      );
    }
    assert.equal(harness.state.constructed, 0);
    assert.equal(harness.state.signed, 0);
    assert.equal(
      (await directCallAttemptRateReference("token", CALLER).get()).data().count,
      limit,
    );
    assert.equal(
      (await db.doc(
        `activeVoiceSessions/${CALLER}/rooms/${directCallRoomName(result.callId)}`,
      ).get()).exists,
      false,
    );
  });

  test("completed direct-token requestId replay is free and signs once", async () => {
    const result = await start("token-replay-call-0001");
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const tokenRequest = request(CALLER, {
      callId: result.callId,
      requestId: "direct-token-replay-0001",
    });

    const first = await createDirectCallTokenHandler(tokenRequest, options);
    const replay = await createDirectCallTokenHandler(tokenRequest, options);
    assert.deepEqual(replay, first);
    assert.equal(harness.state.constructed, 1);
    assert.equal(harness.state.signed, 1);
    assert.equal(
      (await directCallAttemptRateReference("token", CALLER).get()).data().count,
      1,
    );
    const conflictingToken = () => createDirectCallTokenHandler(
      request(CALLER, {
        callId: `${P}different-call`,
        requestId: "direct-token-replay-0001",
      }),
      options,
    );
    await assert.rejects(
      conflictingToken,
      (error) => error?.code === "already-exists",
    );
    const limit = DIRECT_CALL_ATTEMPT_LIMITS.token.maxEvents;
    assert.equal(
      (await directCallAttemptRateReference("token", CALLER).get()).data().count,
      2,
    );
    for (let charged = 2; charged < limit; charged += 1) {
      await assert.rejects(
        conflictingToken,
        (error) => error?.code === "already-exists",
      );
      assert.equal(
        (await directCallAttemptRateReference("token", CALLER).get())
          .data().count,
        charged + 1,
      );
    }
    await assert.rejects(
      conflictingToken,
      (error) => error?.code === "resource-exhausted",
    );
    assert.equal(
      (await directCallAttemptRateReference("token", CALLER).get()).data().count,
      limit,
    );
    assert.equal(harness.state.signed, 1);
    const session = await db.doc(
      `activeVoiceSessions/${CALLER}/rooms/${directCallRoomName(result.callId)}`,
    ).get();
    assert.equal(session.data().tokenIssueCount, 1);
  });

  test("concurrent direct-token retries converge on one ledger result", async () => {
    const result = await start("token-race-call-0001");
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const tokenRequest = request(CALLER, {
      callId: result.callId,
      requestId: "direct-token-race-0001",
    });
    const responses = await Promise.all([
      createDirectCallTokenHandler(tokenRequest, options),
      createDirectCallTokenHandler(tokenRequest, options),
    ]);
    assert.deepEqual(responses[1], responses[0]);
    assert.ok(harness.state.signed >= 1 && harness.state.signed <= 2);
    const charged = (await directCallAttemptRateReference("token", CALLER).get())
      .data().count;
    assert.ok(charged >= 1 && charged <= 2);
    const session = await db.doc(
      `activeVoiceSessions/${CALLER}/rooms/${directCallRoomName(result.callId)}`,
    ).get();
    assert.equal(session.data().tokenIssueCount, 1);
  });

  test("direct-call token sessions are transactionally rate-limited per user and call", async () => {
    const result = await start();
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    const nowMs = Date.now();
    const expiresAt = Timestamp.fromMillis(nowMs + 5 * 60 * 1000);

    for (let index = 0; index < DIRECT_CALL_TOKEN_RATE_LIMIT; index += 1) {
      await recordAuthorizedDirectCallSession({
        callId: result.callId,
        authenticatedUser: request(CALLER, {}).auth,
        expiresAt,
        nowMs,
      });
    }

    const callerSessionRef = db.doc(
      `activeVoiceSessions/${CALLER}/rooms/${directCallRoomName(result.callId)}`,
    );
    const saturated = await callerSessionRef.get();
    assert.equal(saturated.data().tokenIssueCount, DIRECT_CALL_TOKEN_RATE_LIMIT);
    await assert.rejects(
      recordAuthorizedDirectCallSession({
        callId: result.callId,
        authenticatedUser: request(CALLER, {}).auth,
        expiresAt,
        nowMs,
      }),
      (error) => error?.code === "resource-exhausted",
    );
    const unchanged = await callerSessionRef.get();
    assert.equal(unchanged.data().tokenIssueCount, DIRECT_CALL_TOKEN_RATE_LIMIT);
    assert.equal(
      unchanged.data().tokenWindowStartedAt.toMillis(),
      saturated.data().tokenWindowStartedAt.toMillis(),
    );

    await recordAuthorizedDirectCallSession({
      callId: result.callId,
      authenticatedUser: request(CALLEE, {}).auth,
      expiresAt,
      nowMs,
    });
    const calleeSession = await db.doc(
      `activeVoiceSessions/${CALLEE}/rooms/${directCallRoomName(result.callId)}`,
    ).get();
    assert.equal(calleeSession.data().tokenIssueCount, 1);

    const secondCallId = `${P}parallel-active`;
    await db.doc(`directCalls/${secondCallId}`).set({
      callerId: CALLER,
      calleeId: CALLEE,
      participantIds: [CALLER, CALLEE].sort(),
      status: "active",
      expiresAt: Timestamp.fromMillis(nowMs + 60 * 60 * 1000),
    });
    await recordAuthorizedDirectCallSession({
      callId: secondCallId,
      authenticatedUser: request(CALLER, {}).auth,
      expiresAt,
      nowMs,
    });
    const secondSession = await db.doc(
      `activeVoiceSessions/${CALLER}/rooms/${directCallRoomName(secondCallId)}`,
    ).get();
    assert.equal(secondSession.data().tokenIssueCount, 1);

    const nextWindowMs = nowMs + DIRECT_CALL_TOKEN_RATE_WINDOW_MS;
    await recordAuthorizedDirectCallSession({
      callId: result.callId,
      authenticatedUser: request(CALLER, {}).auth,
      expiresAt: Timestamp.fromMillis(nextWindowMs + 5 * 60 * 1000),
      nowMs: nextWindowMs,
    });
    const reset = await callerSessionRef.get();
    assert.equal(reset.data().tokenIssueCount, 1);
    assert.equal(reset.data().tokenWindowStartedAt.toMillis(), nextWindowMs);
  });

  test("caller cannot accept and callee cannot cancel", async () => {
    const result = await start();
    await assert.rejects(
      () => acceptDirectCall.run(request(CALLER, { callId: result.callId })),
      (error) => error?.code === "failed-precondition",
    );
    await assert.rejects(
      () => cancelDirectCall.run(request(CALLEE, { callId: result.callId })),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("decline is terminal and frees both users immediately", async () => {
    const result = await start();
    assert.deepEqual(
      await declineDirectCall.run(request(CALLEE, { callId: result.callId })),
      { callId: result.callId, status: "declined" },
    );
    assert.deepEqual(
      await declineDirectCall.run(request(CALLEE, { callId: result.callId })),
      { callId: result.callId, status: "declined" },
    );
    assert.equal(
      (await db.doc(`directCalls/${result.callId}`).get()).data().status,
      "declined",
    );
    assert.equal((await db.doc(`directCallLocks/${CALLER}`).get()).exists, false);
    assert.equal((await db.doc(`directCallLocks/${CALLEE}`).get()).exists, false);
  });

  for (const [action, actorId, callable, expectedStatus] of [
    ["cancel", CALLER, cancelDirectCall, "cancelled"],
    ["decline", CALLEE, declineDirectCall, "declined"],
    ["end", CALLER, endDirectCall, "ended"],
  ]) {
    test(`late ${action} of an older call preserves replacement locks`, async () => {
      const older = await start();
      if (action === "end") {
        await acceptDirectCall.run(
          request(CALLEE, { callId: older.callId }),
        );
      }
      const replacementId = `${P}replacement-${action}`;
      await installReplacementCall(replacementId);

      assert.deepEqual(
        await callable.run(request(actorId, { callId: older.callId })),
        { callId: older.callId, status: expectedStatus },
      );
      const [callerLock, calleeLock] = await db.getAll(
        db.doc(`directCallLocks/${CALLER}`),
        db.doc(`directCallLocks/${CALLEE}`),
      );
      assert.equal(callerLock.data().callId, replacementId);
      assert.equal(calleeLock.data().callId, replacementId);
    });
  }

  test("expiry of an older ringing call preserves replacement locks", async () => {
    const older = await start();
    const olderRef = db.doc(`directCalls/${older.callId}`);
    await olderRef.update({
      expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    });
    const replacementId = `${P}replacement-expiry`;
    await installReplacementCall(replacementId);

    assert.equal(await expireDirectCall(await olderRef.get()), true);
    const [callerLock, calleeLock] = await db.getAll(
      db.doc(`directCallLocks/${CALLER}`),
      db.doc(`directCallLocks/${CALLEE}`),
    );
    assert.equal(callerLock.data().callId, replacementId);
    assert.equal(calleeLock.data().callId, replacementId);
  });

  test("expiry produces a missed-call notification and invalidates token access", async () => {
    const result = await start();
    const callRef = db.doc(`directCalls/${result.callId}`);
    await callRef.update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    assert.equal(await expireDirectCall(await callRef.get()), true);
    assert.equal((await callRef.get()).data().status, "missed");
    const missed = await db.doc(
      `users/${CALLEE}/notifications/missedCall_${result.callId}`,
    ).get();
    assert.equal(missed.data().type, "missedCall");
    assert.equal(missed.data().bellSuppressed, false);
    await assert.rejects(
      () => db.runTransaction((transaction) =>
        authorizeDirectCallVoice(result.callId, request(CALLER, {}).auth, transaction),
      ),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("active-call expiry ends media, frees locks and queues room teardown", async () => {
    const result = await start(null, "video");
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    const callRef = db.doc(`directCalls/${result.callId}`);
    await callRef.update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });

    assert.equal(await expireDirectCall(await callRef.get()), true);
    assert.equal((await callRef.get()).data().status, "ended");
    assert.equal((await db.doc(`directCallLocks/${CALLER}`).get()).exists, false);
    assert.equal((await db.doc(`directCallLocks/${CALLEE}`).get()).exists, false);
    const teardown = await db.doc(
      `directCallControlOutbox/${result.callId}`,
    ).get();
    assert.equal(teardown.data().roomName, directCallRoomName(result.callId));
    assert.deepEqual(teardown.data().participantIds, [CALLEE, CALLER].sort());
  });

  test("active-call expiry survives a missing inbox mirror", async () => {
    const result = await start(null, "video");
    await acceptDirectCall.run(request(CALLEE, { callId: result.callId }));
    const callRef = db.doc(`directCalls/${result.callId}`);
    await Promise.all([
      callRef.update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }),
      db.doc(`users/${CALLEE}/incomingCalls/${result.callId}`).delete(),
    ]);

    assert.equal(await expireDirectCall(await callRef.get()), true);
    assert.equal((await callRef.get()).data().status, "ended");
    assert.equal((await db.doc(`directCallLocks/${CALLER}`).get()).exists, false);
    assert.equal((await db.doc(`directCallLocks/${CALLEE}`).get()).exists, false);
    assert.equal(
      (await db.doc(`directCallControlOutbox/${result.callId}`).get()).exists,
      true,
    );
  });

  test("expiry batch isolates one broken call and continues", async () => {
    const seen = [];
    const now = Timestamp.now();
    const documents = [{ id: "broken" }, { id: "expired" }, { id: "fresh" }];
    const result = await expireDirectCallBatch(
      documents,
      now,
      async (document, receivedNow) => {
        assert.equal(receivedNow, now);
        seen.push(document.id);
        if (document.id === "broken") {
          const error = new Error("projection missing");
          error.code = "not-found";
          throw error;
        }
        return document.id === "expired";
      },
    );

    assert.deepEqual(seen, ["broken", "expired", "fresh"]);
    assert.deepEqual(result, {
      scanned: 3,
      expired: 1,
      failures: [{ callId: "broken", code: "not-found" }],
    });
  });
});

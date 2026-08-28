const assert = require("node:assert/strict");
const { beforeEach, describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DIRECT_CALL_START_LIMITS,
  authorizeDirectCallVoice,
  directCallStartLimitReference,
  directCallRoomName,
  expireDirectCall,
  startDirectCall,
  acceptDirectCall,
  cancelDirectCall,
  declineDirectCall,
  endDirectCall,
} = require("../calls/direct_calls");

const db = getFirestore();
const P = "dct-";
const CALLER = `${P}caller`;
const CALLEE = `${P}callee`;

function request(uid, data, verified = true) {
  return { auth: { uid, token: { email_verified: verified } }, data };
}

async function wipe() {
  const [calls, controlJobs] = await Promise.all([
    db.collection("directCalls").get(),
    db.collection("directCallControlOutbox").get(),
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
    db.doc(`restrictions/${CALLER}`).delete(),
    db.doc(`restrictions/${CALLEE}`).delete(),
    db.recursiveDelete(db.doc(`friendshipGuards/${CALLER}`)),
    db.recursiveDelete(db.doc(`friendshipGuards/${CALLEE}`)),
    db.doc(`conversations/${P}conversation`).delete(),
    db.doc(`directCallLocks/${CALLER}`).delete(),
    db.doc(`directCallLocks/${CALLEE}`).delete(),
    directCallStartLimitReference("caller", CALLER).delete(),
    directCallStartLimitReference("callee", CALLEE).delete(),
    directCallStartLimitReference("pair", CALLER, CALLEE).delete(),
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

async function start(requestId = null) {
  return startDirectCall.run(request(CALLER, {
    calleeId: CALLEE,
    conversationId: `${P}conversation`,
    ...(requestId === null ? {} : { requestId }),
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
    assert.deepEqual(call.data().participantIds, [CALLEE, CALLER].sort());
    assert.equal(call.data().caller.displayName, "Caller");
    assert.equal(call.data().callee.displayName, "Callee");
    assert.equal(signal.data().callerId, CALLER);
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

    await assert.rejects(
      () => startDirectCall.run(request(CALLER, {
        calleeId: CALLEE,
        conversationId: `${P}other-conversation`,
        requestId,
      })),
      (error) => error?.code === "already-exists",
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
});

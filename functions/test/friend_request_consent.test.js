// Friend requests are a consent decision (ADR "friend requests are an
// explicit consent decision"). These tests pin the server half:
//
// - sendFriendRequest's optional `acceptIncoming` flag. Absent or true keeps
//   the reciprocal accept every installed client relies on; false never
//   creates a friendship and answers `incomingPending` with no writes.
// - the stale answers an explicit Accept / Decline can meet.
// - the push decision for a friend request is observable and survives the
//   request being resolved (the actionable inbox row does not).
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { test, beforeEach, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  setUserBlock,
} = require("../friends/social_graph");
const {
  handleNotificationCreated,
  pushDecisionLedgerReference,
  PUSH_DECISION_RETENTION_MS,
} = require("../notifications/push");

const runSend = sendFriendRequest.run ?? sendFriendRequest;
const runRespond = respondToFriendRequest.run ?? respondToFriendRequest;
const runCancel = cancelFriendRequest.run ?? cancelFriendRequest;
const runBlock = setUserBlock.run ?? setUserBlock;

const A = "frc-alice";
const B = "frc-bob";

function request(uid, data) {
  return {
    auth: {
      uid,
      token: { email_verified: true, email: `${uid}@example.invalid` },
    },
    data,
  };
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function remove(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function reset() {
  const ledgers = await db.collection("notificationDeliveryEvents")
    .where("recipientId", "in", [A, B])
    .get();
  await Promise.all([
    ...ledgers.docs.map((document) => document.ref.delete()),
    ...[A, B].map((uid) => remove(db.doc(`users/${uid}`))),
    ...[A, B].map((uid) => remove(db.doc(`friendshipGuards/${uid}`))),
    ...[A, B].map((uid) => db.doc(`publicProfiles/${uid}`).delete()),
    ...[A, B].map((uid) => db.doc(`restrictions/${uid}`).delete()),
    ...[A, B].flatMap((uid) =>
      ["read", "mutation"].map((kind) =>
        db.doc(`privateRateLimits/socialGraph_${kind}_${digest(uid)}`)
          .delete(),
      ),
    ),
    ...[A, B].map((uid) =>
      db.doc(`privateSocialGraphCapacities/${digest(uid)}`).delete(),
    ),
  ]);
}

async function seed(uid) {
  const displayName = uid === A ? "Alice Consent" : "Bob Consent";
  await Promise.all([
    db.doc(`users/${uid}`).set({
      uid,
      displayName,
      username: uid,
      friendCount: 0,
      followerCount: 0,
      followingCount: 0,
    }),
    db.doc(`publicProfiles/${uid}`).set({ uid, displayName, username: uid }),
  ]);
}

async function exists(path) {
  return (await db.doc(path).get()).exists;
}

async function notificationsOf(uid, type) {
  const snapshot = await db.collection(`users/${uid}/notifications`).get();
  return snapshot.docs.filter((document) => document.data().type === type);
}

async function friendshipPaths() {
  const paths = [
    `users/${A}/friends/${B}`,
    `users/${B}/friends/${A}`,
    `friendshipGuards/${A}/friends/${B}`,
    `friendshipGuards/${B}/friends/${A}`,
  ];
  return Object.fromEntries(
    await Promise.all(paths.map(async (path) => [path, await exists(path)])),
  );
}

beforeEach(async () => {
  await reset();
  await seed(A);
  await seed(B);
});

after(reset);

// ---------------------------------------------------------------- the flag

test("acceptIncoming absent keeps the reciprocal accept (installed clients)", async () => {
  await runSend(request(B, { targetUserId: A }));
  const result = await runSend(request(A, { targetUserId: B }));
  assert.equal(result.outcome, "accepted");
  assert.deepEqual(Object.values(await friendshipPaths()), [
    true, true, true, true,
  ]);
  assert.equal(await exists(`users/${A}/friendRequests/${B}`), false);
  assert.equal((await notificationsOf(B, "friendAccepted")).length, 1);
});

test("acceptIncoming true behaves exactly like the absent flag", async () => {
  await runSend(request(B, { targetUserId: A }));
  const result = await runSend(
    request(A, { targetUserId: B, acceptIncoming: true }),
  );
  assert.equal(result.outcome, "accepted");
  assert.equal(await exists(`users/${A}/friends/${B}`), true);
});

test("acceptIncoming false never answers the other person's request", async () => {
  await runSend(request(B, { targetUserId: A }));
  const pendingBefore = (await db.doc(`users/${A}/friendRequests/${B}`).get())
    .data();
  const requestRows = await notificationsOf(A, "friendRequest");
  assert.equal(requestRows.length, 1);

  const result = await runSend(
    request(A, { targetUserId: B, acceptIncoming: false }),
  );

  assert.deepEqual(result, { outcome: "incomingPending", changed: false });
  // Nothing moved: no friendship, the request and its row are untouched, no
  // acceptance notification, no reverse request, counters unchanged.
  assert.deepEqual(Object.values(await friendshipPaths()), [
    false, false, false, false,
  ]);
  assert.deepEqual(
    (await db.doc(`users/${A}/friendRequests/${B}`).get()).data(),
    pendingBefore,
  );
  assert.equal(await exists(`users/${B}/sentFriendRequests/${A}`), true);
  assert.equal(await exists(`users/${B}/friendRequests/${A}`), false);
  assert.equal(await exists(`users/${A}/sentFriendRequests/${B}`), false);
  assert.equal(
    await exists(`users/${A}/notifications/${requestRows[0].id}`),
    true,
  );
  assert.equal((await notificationsOf(B, "friendAccepted")).length, 0);
  assert.equal((await db.doc(`users/${A}`).get()).data().friendCount, 0);
  assert.equal((await db.doc(`users/${B}`).get()).data().friendCount, 0);

  // The explicit Accept that follows is what makes the friendship.
  const accepted = await runRespond(
    request(A, { senderId: B, accept: true }),
  );
  assert.equal(accepted.outcome, "accepted");
  assert.equal(await exists(`users/${A}/friends/${B}`), true);
});

test("acceptIncoming false with nothing pending sends a normal request", async () => {
  const result = await runSend(
    request(A, { targetUserId: B, acceptIncoming: false }),
  );
  assert.equal(result.outcome, "requested");
  assert.equal(await exists(`users/${B}/friendRequests/${A}`), true);
  assert.equal((await notificationsOf(B, "friendRequest")).length, 1);
});

test("acceptIncoming must be a boolean when present", async () => {
  await assert.rejects(
    runSend(request(A, { targetUserId: B, acceptIncoming: "no" })),
    (error) => error.code === "invalid-argument",
  );
  assert.equal(await exists(`users/${B}/friendRequests/${A}`), false);
});

test("simultaneous consent-aware requests leave one request and one prompt", async () => {
  // The contract beside "simultaneous reciprocal requests converge on one
  // friendship" (installed clients): with the flag, two people tapping Add
  // at the same moment do NOT become friends. One request stands, the other
  // caller is told to answer it.
  const results = await Promise.all([
    runSend(request(A, { targetUserId: B, acceptIncoming: false })),
    runSend(request(B, { targetUserId: A, acceptIncoming: false })),
  ]);
  assert.deepEqual(
    new Set(results.map((result) => result.outcome)),
    new Set(["requested", "incomingPending"]),
  );
  assert.deepEqual(Object.values(await friendshipPaths()), [
    false, false, false, false,
  ]);
  const pending = [
    await exists(`users/${A}/friendRequests/${B}`),
    await exists(`users/${B}/friendRequests/${A}`),
  ];
  assert.equal(pending.filter(Boolean).length, 1);
});

// ---------------------------------------------------------- stale answers

test("accepting twice is idempotent: alreadyAccepted", async () => {
  await runSend(request(B, { targetUserId: A }));
  assert.equal(
    (await runRespond(request(A, { senderId: B, accept: true }))).outcome,
    "accepted",
  );
  assert.equal(
    (await runRespond(request(A, { senderId: B, accept: true }))).outcome,
    "alreadyAccepted",
  );
});

test("declining an accepted request is alreadyResolved and keeps the friendship", async () => {
  await runSend(request(B, { targetUserId: A }));
  await runRespond(request(A, { senderId: B, accept: true }));
  const declined = await runRespond(
    request(A, { senderId: B, accept: false }),
  );
  assert.equal(declined.outcome, "alreadyResolved");
  assert.equal(await exists(`users/${A}/friends/${B}`), true);
  assert.equal(await exists(`users/${B}/friends/${A}`), true);
});

test("accepting a cancelled request is not-found and creates nothing", async () => {
  await runSend(request(B, { targetUserId: A }));
  await runCancel(request(B, { targetUserId: A }));
  await assert.rejects(
    runRespond(request(A, { senderId: B, accept: true })),
    (error) => error.code === "not-found",
  );
  assert.equal(await exists(`users/${A}/friends/${B}`), false);
});

test("a block removes the request: Accept is not-found, Decline alreadyResolved", async () => {
  await runSend(request(B, { targetUserId: A }));
  await runBlock(request(A, { targetUserId: B, blocked: true }));
  await assert.rejects(
    runRespond(request(A, { senderId: B, accept: true })),
    (error) => error.code === "not-found",
  );
  assert.equal(
    (await runRespond(request(A, { senderId: B, accept: false }))).outcome,
    "alreadyResolved",
  );
  assert.equal(await exists(`users/${A}/friends/${B}`), false);
  assert.equal((await notificationsOf(A, "friendRequest")).length, 0);
});

// ------------------------------------------------------- push observability

function eventFor(uid, snapshot) {
  return {
    id: `frc-event-${snapshot.id}`,
    params: { userId: uid, notificationId: snapshot.id },
    data: snapshot,
  };
}

function fakeMessaging(sent) {
  return {
    sendEachForMulticast: async (message) => {
      sent.push(message);
      return { responses: message.tokens.map(() => ({ success: true })) };
    },
  };
}

test("a real friend request pushes once and its decision outlives the row", async () => {
  await db.doc(`users/${A}/fcmTokens/frc-token`).set({
    token: "frc-token",
    updatedAt: Timestamp.now(),
  });
  await runSend(request(B, { targetUserId: A }));
  const [row] = await notificationsOf(A, "friendRequest");
  const sent = [];

  await handleNotificationCreated(eventFor(A, await row.ref.get()), {
    messaging: fakeMessaging(sent),
  });

  assert.equal(sent.length, 1);
  assert.equal(sent[0].data.type, "friendRequest");
  assert.equal(sent[0].data.actorId, B);
  assert.equal(sent[0].android.notification.channelId, "yovoice_social_v1");
  assert.match(sent[0].notification.title, /sent you a friend request$/u);
  assert.equal((await row.ref.get()).data().pushDeliveryStatus, "sent");

  const ledger = pushDecisionLedgerReference(A, row.id);
  const receipt = (await ledger.get()).data();
  assert.equal(receipt.kind, "pushDecision");
  assert.equal(receipt.type, "friendRequest");
  assert.equal(receipt.notificationId, row.id);
  assert.equal(receipt.pushDeliveryStatus, "sent");
  assert.equal(receipt.pushSkipReason, null);
  assert.equal(
    receipt.expiresAt.toMillis() - receipt.decidedAt.toMillis(),
    PUSH_DECISION_RETENTION_MS,
  );
  // Only the decision: no token, title or body is kept.
  assert.equal(JSON.stringify(receipt).includes("frc-token"), false);

  // Accepting deletes the actionable row. The receipt stays.
  await runRespond(request(A, { senderId: B, accept: true }));
  assert.equal((await row.ref.get()).exists, false);
  assert.equal((await ledger.get()).data().pushDeliveryStatus, "sent");
});

test("a skipped friend-request push records why, and it survives a decline", async () => {
  await runSend(request(B, { targetUserId: A }));
  const [row] = await notificationsOf(A, "friendRequest");
  const sent = [];

  await handleNotificationCreated(eventFor(A, await row.ref.get()), {
    messaging: fakeMessaging(sent),
  });

  assert.equal(sent.length, 0);
  const current = (await row.ref.get()).data();
  assert.equal(current.pushDeliveryStatus, "skipped");
  assert.equal(current.pushSkipReason, "no-token");
  await runRespond(request(A, { senderId: B, accept: false }));
  assert.equal((await row.ref.get()).exists, false);
  const receipt = (await pushDecisionLedgerReference(A, row.id).get()).data();
  assert.equal(receipt.pushDeliveryStatus, "skipped");
  assert.equal(receipt.pushSkipReason, "no-token");
});

test("a disabled friend-request preference is recorded as preference-disabled", async () => {
  await db.doc(`users/${A}`).set(
    { notificationPreferences: { friendRequest: false } },
    { merge: true },
  );
  await db.doc(`users/${A}/fcmTokens/frc-token`).set({
    token: "frc-token",
    updatedAt: Timestamp.now(),
  });
  await runSend(request(B, { targetUserId: A }));
  const [row] = await notificationsOf(A, "friendRequest");
  const sent = [];

  await handleNotificationCreated(eventFor(A, await row.ref.get()), {
    messaging: fakeMessaging(sent),
  });

  assert.equal(sent.length, 0);
  const receipt = (await pushDecisionLedgerReference(A, row.id).get()).data();
  assert.equal(receipt.pushDeliveryStatus, "skipped");
  assert.equal(receipt.pushSkipReason, "preference-disabled");
});

test("other types keep no push-decision receipt", async () => {
  await db.doc(`users/${B}/fcmTokens/frc-token`).set({
    token: "frc-token",
    updatedAt: Timestamp.now(),
  });
  await runSend(request(B, { targetUserId: A }));
  await runRespond(request(A, { senderId: B, accept: true }));
  const [row] = await notificationsOf(B, "friendAccepted");
  const sent = [];

  await handleNotificationCreated(eventFor(B, await row.ref.get()), {
    messaging: fakeMessaging(sent),
  });

  assert.equal(sent.length, 1);
  assert.equal(
    (await pushDecisionLedgerReference(B, row.id).get()).exists,
    false,
  );
});

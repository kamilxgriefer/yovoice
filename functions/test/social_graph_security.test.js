const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { test, beforeEach, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const {
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  removeFriend,
  setFollow,
  setUserBlock,
  getMutualFriends,
  getFriendSuggestions,
  consumeSocialRateLimit,
  MAX_FRIENDS,
  MAX_FOLLOWING,
  QUOTA_MINUTE_MS,
} = require("../friends/social_graph");

const runSend = sendFriendRequest.run ?? sendFriendRequest;
const runRespond = respondToFriendRequest.run ?? respondToFriendRequest;
const runCancel = cancelFriendRequest.run ?? cancelFriendRequest;
const runRemove = removeFriend.run ?? removeFriend;
const runFollow = setFollow.run ?? setFollow;
const runBlock = setUserBlock.run ?? setUserBlock;
const runMutual = getMutualFriends.run ?? getMutualFriends;
const runSuggestions = getFriendSuggestions.run ?? getFriendSuggestions;

const A = "sgs-alice";
const B = "sgs-bob";
const C = "sgs-charlie";

function quotaId(uid, kind) {
  const digest = createHash("sha256").update(uid).digest("hex");
  return `socialGraph_${kind}_${digest}`;
}

function request(uid, data, verified = true) {
  return {
    auth: {
      uid,
      token: {
        email_verified: verified,
        email: `${uid}@example.invalid`,
      },
    },
    data,
  };
}

async function remove(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function reset() {
  await Promise.all([
    ...[A, B, C].map((uid) => remove(db.doc(`users/${uid}`))),
    ...[A, B, C].map((uid) =>
      remove(db.doc(`friendshipGuards/${uid}`)),
    ),
    ...[A, B, C].map((uid) => db.doc(`publicProfiles/${uid}`).delete()),
    ...[A, B, C].map((uid) => db.doc(`restrictions/${uid}`).delete()),
    ...[A, B, C].flatMap((uid) =>
      ["read", "mutation"].map((kind) =>
        db.doc(`privateRateLimits/${quotaId(uid, kind)}`).delete(),
      ),
    ),
  ]);
}

async function seed(uid, overrides = {}) {
  const displayName = uid === A ? "Alice Canonical" : "Bob Canonical";
  await Promise.all([
    db.doc(`users/${uid}`).set({
      uid,
      displayName,
      username: uid,
      photoUrl: `https://example.invalid/${uid}.jpg`,
      email: `${uid}@canonical.invalid`,
      friendCount: 0,
      followerCount: 0,
      followingCount: 0,
      ...overrides,
    }),
    db.doc(`publicProfiles/${uid}`).set({
      uid,
      displayName,
      username: uid,
      photoUrl: `https://example.invalid/${uid}.jpg`,
    }),
  ]);
}

async function socialNotifications(uid, type, actorId) {
  const snapshot = await db.doc(`users/${uid}`).collection("notifications").get();
  return snapshot.docs.filter((doc) => {
    const data = doc.data();
    return data.type === type && data.actorId === actorId;
  });
}

async function onlySocialNotification(uid, type, actorId) {
  const matches = await socialNotifications(uid, type, actorId);
  assert.equal(matches.length, 1, `${type} notification count`);
  return matches[0];
}

beforeEach(async () => {
  await reset();
  await Promise.all([seed(A), seed(B), seed(C)]);
});
after(reset);

test("friend request is canonical, atomic and replay-safe", async () => {
  const input = request(A, {
    targetUserId: B,
    senderName: "FORGED",
    actorPhotoUrl: "https://evil.invalid/avatar",
  });
  const first = await runSend(input);
  const replay = await runSend(input);
  assert.equal(first.outcome, "requested");
  assert.equal(replay.outcome, "alreadyPending");

  const [incoming, sent, notification] = await Promise.all([
    db.doc(`users/${B}/friendRequests/${A}`).get(),
    db.doc(`users/${A}/sentFriendRequests/${B}`).get(),
    onlySocialNotification(B, "friendRequest", A),
  ]);
  assert.equal(incoming.data().senderId, A);
  assert.equal(incoming.data().senderName, "Alice Canonical");
  assert.equal("senderEmail" in incoming.data(), false);
  assert.ok(incoming.data().createdAt);
  assert.equal(sent.data().receiverId, B);
  assert.equal(notification.data().actorName, "Alice Canonical");
  assert.equal(notification.data().type, "friendRequest");
  assert.equal(notification.data().isRead, false);
  assert.ok(notification.data().createdAt);
});

test("first post-upgrade social lifecycle replaces legacy deterministic ids", async () => {
  const legacyRequest = db.doc(
    `users/${B}/notifications/friendRequest_${A}`,
  );
  await legacyRequest.set({
    type: "friendRequest",
    actorId: A,
    isRead: true,
  });
  await runSend(request(A, { targetUserId: B }));
  assert.equal((await legacyRequest.get()).exists, false);
  const freshRequest = await onlySocialNotification(B, "friendRequest", A);
  assert.notEqual(freshRequest.id, `friendRequest_${A}`);

  const legacyAccepted = db.doc(
    `users/${A}/notifications/friendAccepted_${B}`,
  );
  await legacyAccepted.set({
    type: "friendAccepted",
    actorId: B,
    isRead: true,
  });
  await runRespond(request(B, { senderId: A, accept: true }));
  assert.equal((await legacyAccepted.get()).exists, false);
  const freshAccepted = await onlySocialNotification(A, "friendAccepted", B);
  assert.notEqual(freshAccepted.id, `friendAccepted_${B}`);

  const legacyFollow = db.doc(`users/${B}/notifications/follow_${A}`);
  await legacyFollow.set({ type: "follow", actorId: A, isRead: true });
  await runFollow(request(A, { targetUserId: B, following: true }));
  assert.equal((await legacyFollow.get()).exists, false);
  const freshFollow = await onlySocialNotification(B, "follow", A);
  assert.notEqual(freshFollow.id, `follow_${A}`);
});

test("simultaneous reciprocal requests converge on one friendship", async () => {
  const results = await Promise.all([
    runSend(request(A, { targetUserId: B })),
    runSend(request(B, { targetUserId: A })),
  ]);
  assert.deepEqual(
    new Set(results.map((result) => result.outcome)),
    new Set(["requested", "accepted"]),
  );
  for (const path of [
    `users/${A}/friends/${B}`,
    `users/${B}/friends/${A}`,
    `friendshipGuards/${A}/friends/${B}`,
    `friendshipGuards/${B}/friends/${A}`,
  ]) {
    assert.equal((await db.doc(path).get()).exists, true, path);
  }
  for (const path of [
    `users/${A}/friendRequests/${B}`,
    `users/${B}/friendRequests/${A}`,
    `users/${A}/sentFriendRequests/${B}`,
    `users/${B}/sentFriendRequests/${A}`,
  ]) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal((await db.doc(`users/${A}`).get()).data().friendCount, 1);
  assert.equal((await db.doc(`users/${B}`).get()).data().friendCount, 1);
});

test("only the concrete recipient can accept and the acceptance consumes once", async () => {
  await runSend(request(A, { targetUserId: B }));
  await assert.rejects(
    runRespond(request(A, { senderId: B, accept: true })),
    (error) => error.code === "not-found",
  );

  const first = await runRespond(request(B, { senderId: A, accept: true }));
  const replay = await runRespond(request(B, { senderId: A, accept: true }));
  assert.equal(first.outcome, "accepted");
  assert.equal(replay.outcome, "alreadyAccepted");

  const [
    aFriend,
    bFriend,
    aGuard,
    bGuard,
    requestDoc,
    sentDoc,
    a,
    b,
    accepted,
  ] =
    await Promise.all([
      db.doc(`users/${A}/friends/${B}`).get(),
      db.doc(`users/${B}/friends/${A}`).get(),
      db.doc(`friendshipGuards/${A}/friends/${B}`).get(),
      db.doc(`friendshipGuards/${B}/friends/${A}`).get(),
      db.doc(`users/${B}/friendRequests/${A}`).get(),
      db.doc(`users/${A}/sentFriendRequests/${B}`).get(),
      db.doc(`users/${A}`).get(),
      db.doc(`users/${B}`).get(),
      onlySocialNotification(A, "friendAccepted", B),
    ]);
  assert.equal(aFriend.data().userId, B);
  assert.equal(bFriend.data().userId, A);
  assert.deepEqual(
    {
      ownerId: aGuard.data().ownerId,
      friendId: aGuard.data().friendId,
      schemaVersion: aGuard.data().schemaVersion,
    },
    { ownerId: A, friendId: B, schemaVersion: 1 },
  );
  assert.equal(bGuard.data().ownerId, B);
  assert.equal(bGuard.data().friendId, A);
  assert.equal(requestDoc.exists, false);
  assert.equal(sentDoc.exists, false);
  assert.equal(a.data().friendCount, 1);
  assert.equal(b.data().friendCount, 1);
  assert.equal(accepted.data().actorName, "Bob Canonical");
  assert.equal(accepted.data().type, "friendAccepted");
});

test("decline consumes the request without inventing a friendship", async () => {
  await runSend(request(A, { targetUserId: B }));
  const result = await runRespond(request(B, { senderId: A, accept: false }));
  assert.equal(result.outcome, "declined");
  assert.equal(
    (await db.doc(`users/${B}/friendRequests/${A}`).get()).exists,
    false,
  );
  assert.equal((await db.doc(`users/${A}/friends/${B}`).get()).exists, false);
  assert.equal((await socialNotifications(A, "friendAccepted", B)).length, 0);
  assert.equal((await socialNotifications(B, "friendRequest", A)).length, 0);
});

test("cancel retires the recipient alert and a later request is fresh", async () => {
  await runSend(request(A, { targetUserId: B }));
  const first = await runCancel(request(A, { targetUserId: B }));
  const replay = await runCancel(request(A, { targetUserId: B }));
  assert.equal(first.changed, true);
  assert.equal(replay.changed, false);

  for (const path of [
    `users/${B}/friendRequests/${A}`,
    `users/${A}/sentFriendRequests/${B}`,
  ]) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal((await socialNotifications(B, "friendRequest", A)).length, 0);

  await runSend(request(A, { targetUserId: B }));
  const fresh = await onlySocialNotification(B, "friendRequest", A);
  assert.equal(fresh.data().isRead, false);
});

test("accept retires the actionable request alert", async () => {
  await runSend(request(A, { targetUserId: B }));
  await runRespond(request(B, { senderId: A, accept: true }));
  assert.equal((await socialNotifications(B, "friendRequest", A)).length, 0);
});

test("resolved request replays repair a stale actionable alert", async () => {
  await runSend(request(A, { targetUserId: B }));
  await runRespond(request(B, { senderId: A, accept: true }));
  const staleRef = db.doc(`users/${B}/notifications/friendRequest_${A}`);
  await staleRef.set({ type: "friendRequest", actorId: A, isRead: false });

  const acceptedReplay = await runRespond(
    request(B, { senderId: A, accept: true }),
  );
  assert.equal(acceptedReplay.outcome, "alreadyAccepted");
  assert.equal((await staleRef.get()).exists, false);

  await runRemove(request(A, { targetUserId: B }));
  await staleRef.set({ type: "friendRequest", actorId: A, isRead: false });
  const declinedReplay = await runRespond(
    request(B, { senderId: A, accept: false }),
  );
  assert.equal(declinedReplay.outcome, "alreadyResolved");
  assert.equal((await staleRef.get()).exists, false);
});

test("a later acceptance uses a fresh notification generation", async () => {
  await runSend(request(A, { targetUserId: B }));
  await runRespond(request(B, { senderId: A, accept: true }));
  const first = await onlySocialNotification(A, "friendAccepted", B);

  await runRemove(request(A, { targetUserId: B }));
  assert.equal(
    (await db.doc(`users/${A}/notifications/${first.id}`).get()).exists,
    false,
  );

  await runSend(request(A, { targetUserId: B }));
  await runRespond(request(B, { senderId: A, accept: true }));
  const generations = await socialNotifications(A, "friendAccepted", B);
  assert.equal(generations.length, 1);
  assert.notEqual(generations[0].id, first.id);
});

test("follow and unfollow maintain paired mirrors and counters under replay", async () => {
  const attempts = await Promise.all(
    Array.from({ length: 4 }, () =>
      runFollow(request(A, { targetUserId: B, following: true })),
    ),
  );
  assert.equal(attempts.filter((item) => item.changed).length, 1);
  let [a, b, following, follower, notification] = await Promise.all([
    db.doc(`users/${A}`).get(),
    db.doc(`users/${B}`).get(),
    db.doc(`users/${A}/following/${B}`).get(),
    db.doc(`users/${B}/followers/${A}`).get(),
    onlySocialNotification(B, "follow", A),
  ]);
  assert.equal(a.data().followingCount, 1);
  assert.equal(b.data().followerCount, 1);
  assert.deepEqual(Object.keys(following.data()).sort(), [
    "followedAt",
    "notificationId",
    "uid",
  ]);
  assert.deepEqual(Object.keys(follower.data()).sort(), [
    "followedAt",
    "notificationId",
    "uid",
  ]);
  assert.equal(following.data().uid, B);
  assert.equal(follower.data().uid, A);
  assert.equal(following.data().notificationId, notification.id);
  assert.equal(follower.data().notificationId, notification.id);
  assert.equal(notification.data().actorName, "Alice Canonical");
  const firstNotificationId = notification.id;

  await runFollow(request(A, { targetUserId: B, following: false }));
  await runFollow(request(A, { targetUserId: B, following: false }));
  [a, b, following, follower] = await Promise.all([
    db.doc(`users/${A}`).get(),
    db.doc(`users/${B}`).get(),
    db.doc(`users/${A}/following/${B}`).get(),
    db.doc(`users/${B}/followers/${A}`).get(),
  ]);
  assert.equal(a.data().followingCount, 0);
  assert.equal(b.data().followerCount, 0);
  assert.equal(following.exists, false);
  assert.equal(follower.exists, false);
  assert.equal(
    (await socialNotifications(B, "follow", A)).length,
    0,
    "unfollow retires the current activity generation atomically",
  );

  await runFollow(request(A, { targetUserId: B, following: true }));
  const secondGeneration = await socialNotifications(B, "follow", A);
  assert.equal(secondGeneration.length, 1);
  assert.notEqual(secondGeneration[0].id, firstNotificationId);
  const secondEdge = await db.doc(`users/${A}/following/${B}`).get();
  assert.equal(secondEdge.data().notificationId, secondGeneration[0].id);
});

test("unfollow replay removes a stale activity row without a graph edge", async () => {
  const notificationRef = db.doc(
    `users/${B}/notifications/follow_${A}`,
  );
  await notificationRef.set({
    type: "follow",
    actorId: A,
    isRead: false,
  });

  const replay = await runFollow(
    request(A, { targetUserId: B, following: false }),
  );

  assert.deepEqual(replay, { changed: false, following: false });
  assert.equal((await notificationRef.get()).exists, false);

  await runFollow(request(A, { targetUserId: B, following: true }));
  const fresh = await onlySocialNotification(B, "follow", A);
  assert.notEqual(fresh.id, `follow_${A}`);
});

test("blocks and active sanctions fail closed for connection creation", async () => {
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(
    runSend(request(A, { targetUserId: B })),
    (error) => error.code === "failed-precondition",
  );
  await assert.rejects(
    runFollow(request(A, { targetUserId: B, following: true })),
    (error) => error.code === "failed-precondition",
  );

  await db.doc(`users/${B}/blocked/${A}`).delete();
  await db.doc(`restrictions/${A}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    runSend(request(A, { targetUserId: B })),
    (error) => error.code === "permission-denied",
  );
  await assert.rejects(
    runFollow(request(A, { targetUserId: B, following: true })),
    (error) => error.code === "permission-denied",
  );
});

test("unverified and inactive accounts cannot create graph edges", async () => {
  await assert.rejects(
    runSend(request(A, { targetUserId: B }, false)),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${A}`).update({ banned: true });
  await assert.rejects(
    runFollow(request(A, { targetUserId: B, following: true })),
    (error) => error.code === "permission-denied",
  );
});

test("self-removal is rejected and blocking cannot create orphan targets", async () => {
  await assert.rejects(
    runRemove(request(A, { targetUserId: A })),
    (error) => error.code === "invalid-argument",
  );
  await db.recursiveDelete(db.doc(`users/${C}`));
  await assert.rejects(
    runBlock(request(A, { targetUserId: C, blocked: true })),
    (error) => error.code === "not-found",
  );
  assert.equal((await db.doc(`users/${A}/blocked/${C}`).get()).exists, false);

  await seed(C, { disabled: true });
  await assert.rejects(
    runBlock(request(A, { targetUserId: C, blocked: true })),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await db.doc(`users/${A}/blocked/${C}`).get()).exists, false);
});

test("invalid canonical counters fail closed without partial graph writes", async () => {
  await db.doc(`users/${A}`).update({ followingCount: -1 });
  await assert.rejects(
    runFollow(request(A, { targetUserId: B, following: true })),
    (error) => error.code === "data-loss",
  );
  assert.equal((await db.doc(`users/${A}/following/${B}`).get()).exists, false);
  assert.equal((await db.doc(`users/${B}/followers/${A}`).get()).exists, false);

  await db.doc(`users/${A}`).update({ followingCount: 1.5 });
  await assert.rejects(
    runFollow(request(A, { targetUserId: B, following: true })),
    (error) => error.code === "data-loss",
  );
});

test("mutuals and suggestions do not disclose inactive or blocking accounts", async () => {
  await Promise.all([
    db.doc(`users/${A}/friends/${C}`).set({ userId: C }),
    db.doc(`users/${C}/friends/${A}`).set({ userId: A }),
    db.doc(`users/${B}/friends/${C}`).set({ userId: C }),
    db.doc(`users/${C}/friends/${B}`).set({ userId: B }),
    db.doc(`friendshipGuards/${A}/friends/${C}`).set({
      ownerId: A,
      friendId: C,
      schemaVersion: 1,
    }),
    db.doc(`friendshipGuards/${C}/friends/${A}`).set({
      ownerId: C,
      friendId: A,
      schemaVersion: 1,
    }),
    db.doc(`friendshipGuards/${B}/friends/${C}`).set({
      ownerId: B,
      friendId: C,
      schemaVersion: 1,
    }),
    db.doc(`friendshipGuards/${C}/friends/${B}`).set({
      ownerId: C,
      friendId: B,
      schemaVersion: 1,
    }),
  ]);
  let mutual = await runMutual(request(A, { targetUserId: B }));
  assert.equal(mutual.count, 1);
  assert.equal(mutual.sample[0].uid, C);

  // Keep the stale public projection in place while the private authority is
  // banned, disabled and then deleted. Neither the aggregate nor the sample
  // may disclose that account.
  await db.doc(`users/${C}`).update({ banned: true });
  mutual = await runMutual(request(A, { targetUserId: B }));
  assert.deepEqual(mutual, { count: 0, sample: [] });
  await db.doc(`users/${C}`).update({ banned: false, disabled: true });
  mutual = await runMutual(request(A, { targetUserId: B }));
  assert.deepEqual(mutual, { count: 0, sample: [] });
  await db.doc(`users/${C}`).delete();
  mutual = await runMutual(request(A, { targetUserId: B }));
  assert.deepEqual(mutual, { count: 0, sample: [] });
  await seed(C);

  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(
    runMutual(request(A, { targetUserId: B })),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${B}/blocked/${A}`).delete();

  // B is a friend-of-friend candidate for A, but B blocked A. The reverse
  // private block must be enforced server-side and B must not be returned.
  await db.doc(`users/${A}/friends/${B}`).delete();
  await db.doc(`users/${B}/friends/${A}`).delete();
  await db.doc(`friendshipGuards/${A}/friends/${B}`).delete();
  await db.doc(`friendshipGuards/${B}/friends/${A}`).delete();
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  const suggestions = await runSuggestions(request(A, { limit: 10 }));
  assert.equal(
    suggestions.suggestions.some((item) => item.uid === B),
    false,
  );

  await db.doc(`users/${A}`).update({ disabled: true });
  await assert.rejects(
    runSuggestions(request(A, { limit: 10 })),
    (error) => error.code === "permission-denied",
  );
});

test("suggestions skip stale public projections for inactive candidates", async () => {
  await Promise.all([
    db.doc(`users/${A}/friends/${B}`).set({ userId: B }),
    db.doc(`users/${B}/friends/${A}`).set({ userId: A }),
    db.doc(`users/${B}/friends/${C}`).set({ userId: C }),
    db.doc(`users/${C}/friends/${B}`).set({ userId: B }),
    db.doc(`friendshipGuards/${A}/friends/${B}`).set({
      ownerId: A,
      friendId: B,
      schemaVersion: 1,
    }),
    db.doc(`friendshipGuards/${B}/friends/${A}`).set({
      ownerId: B,
      friendId: A,
      schemaVersion: 1,
    }),
    db.doc(`friendshipGuards/${B}/friends/${C}`).set({
      ownerId: B,
      friendId: C,
      schemaVersion: 1,
    }),
    db.doc(`friendshipGuards/${C}/friends/${B}`).set({
      ownerId: C,
      friendId: B,
      schemaVersion: 1,
    }),
  ]);

  await db.doc(`users/${C}`).update({ banned: true });
  let suggestions = await runSuggestions(request(A, { limit: 10 }));
  assert.equal(
    suggestions.suggestions.some((item) => item.uid === C),
    false,
  );

  await db.doc(`users/${C}`).update({ banned: false, disabled: true });
  suggestions = await runSuggestions(request(A, { limit: 10 }));
  assert.equal(
    suggestions.suggestions.some((item) => item.uid === C),
    false,
  );

  await db.doc(`users/${C}`).delete();
  suggestions = await runSuggestions(request(A, { limit: 10 }));
  assert.equal(
    suggestions.suggestions.some((item) => item.uid === C),
    false,
  );
});

test("blocking atomically severs friendship, follows and pending requests", async () => {
  await runSend(request(A, { targetUserId: B }));
  await runRespond(request(B, { senderId: A, accept: true }));
  await runFollow(request(A, { targetUserId: B, following: true }));
  await runFollow(request(B, { targetUserId: A, following: true }));
  const first = await runBlock(request(A, { targetUserId: B, blocked: true }));
  const replay = await runBlock(request(A, { targetUserId: B, blocked: true }));
  assert.equal(first.blocked, true);
  assert.equal(replay.changed, false);

  const [a, b, block] = await Promise.all([
    db.doc(`users/${A}`).get(),
    db.doc(`users/${B}`).get(),
    db.doc(`users/${A}/blocked/${B}`).get(),
  ]);
  assert.equal(a.data().friendCount, 0);
  assert.equal(b.data().friendCount, 0);
  assert.equal(a.data().followerCount, 0);
  assert.equal(a.data().followingCount, 0);
  assert.equal(b.data().followerCount, 0);
  assert.equal(b.data().followingCount, 0);
  assert.equal(block.data().userId, B);
  for (const path of [
    `users/${A}/friends/${B}`,
    `users/${B}/friends/${A}`,
    `users/${A}/following/${B}`,
    `users/${B}/followers/${A}`,
    `users/${B}/following/${A}`,
    `users/${A}/followers/${B}`,
    `friendshipGuards/${A}/friends/${B}`,
    `friendshipGuards/${B}/friends/${A}`,
  ]) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  for (const [recipientId, actorId] of [
    [A, B],
    [B, A],
  ]) {
    for (const type of ["friendRequest", "friendAccepted"]) {
      assert.equal(
        (await socialNotifications(recipientId, type, actorId)).length,
        0,
        `${recipientId} must not retain ${type} from ${actorId}`,
      );
    }
    assert.equal(
      (await socialNotifications(recipientId, "follow", actorId)).length,
      0,
      "block retires the active follow notification with the edge",
    );
  }

  await runBlock(request(A, { targetUserId: B, blocked: false }));
  assert.equal((await db.doc(`users/${A}/blocked/${B}`).get()).exists, false);
});

test("legacy symmetric friend mirrors never mint trusted friendship guards", async () => {
  await Promise.all([
    db.doc(`users/${A}/friends/${B}`).set({ userId: B }),
    db.doc(`users/${B}/friends/${A}`).set({ userId: A }),
    db.doc(`socialPresence/${B}`).set({ uid: B, isOnline: true }),
  ]);

  const mutual = await runMutual(request(A, { targetUserId: B }));
  assert.deepEqual(mutual, { count: 0, sample: [] });
  await assert.rejects(
    runSend(request(A, { targetUserId: B })),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.doc(`friendshipGuards/${A}/friends/${B}`).get()).exists,
    false,
  );
});

test("graph caps fail closed before creating new friend or follow edges", async () => {
  await db.doc(`users/${A}`).update({ friendCount: MAX_FRIENDS });
  await runSend(request(B, { targetUserId: A }));
  await assert.rejects(
    runRespond(request(A, { senderId: B, accept: true })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await db.doc(`users/${A}/friends/${B}`).get()).exists, false);

  await db.doc(`users/${A}`).update({ followingCount: MAX_FOLLOWING });
  await assert.rejects(
    runFollow(request(A, { targetUserId: B, following: true })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await db.doc(`users/${A}/following/${B}`).get()).exists, false);
});

test("private transactional social quota rejects bursts and resets", async () => {
  const now = require("firebase-admin/firestore").Timestamp.fromMillis(
    1_770_000_000_000,
  );
  const attempts = await Promise.allSettled([
    consumeSocialRateLimit(A, "read", {
      now,
      minuteLimit: 1,
      hourLimit: 3,
    }),
    consumeSocialRateLimit(A, "read", {
      now,
      minuteLimit: 1,
      hourLimit: 3,
    }),
  ]);
  assert.equal(
    attempts.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    attempts.find((result) => result.status === "rejected").reason.code,
    "resource-exhausted",
  );
  const reset = await consumeSocialRateLimit(A, "read", {
    now: require("firebase-admin/firestore").Timestamp.fromMillis(
      now.toMillis() + QUOTA_MINUTE_MS,
    ),
    minuteLimit: 1,
    hourLimit: 3,
  });
  assert.deepEqual(reset, { minuteCount: 1, hourCount: 2 });
});

test("the complete callable surface is exported for deployment", () => {
  const exports = require("../index");
  for (const name of [
    "sendFriendRequest",
    "respondToFriendRequest",
    "cancelFriendRequest",
    "removeFriend",
    "setFollow",
    "setUserBlock",
    "sendClubInvite",
    "onClubInviteCreated",
    "onClubMemberCreated",
  ]) {
    assert.equal(typeof exports[name], "function", name);
  }
  for (const retired of [
    "onFriendRequestCreated",
    "onFriendRequestResolved",
    "onFollowerCreated",
  ]) {
    assert.equal(exports[retired], undefined, `${retired} must stay retired`);
  }
});

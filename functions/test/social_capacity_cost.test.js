const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { test, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const {
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  setUserBlock,
  socialCapacityReference,
  MAX_BLOCKED_USERS,
  MAX_PENDING_REQUESTS,
} = require("../friends/social_graph");

const runSend = sendFriendRequest.run ?? sendFriendRequest;
const runRespond = respondToFriendRequest.run ?? respondToFriendRequest;
const runCancel = cancelFriendRequest.run ?? cancelFriendRequest;
const runBlock = setUserBlock.run ?? setUserBlock;

const cleanupRoots = new Set();
const cleanupDocs = new Set();

function request(uid, data) {
  return {
    auth: {
      uid,
      token: {
        email_verified: true,
        email: `${uid}@example.invalid`,
      },
    },
    data,
  };
}

function trackUser(uid) {
  cleanupRoots.add(`users/${uid}`);
  cleanupRoots.add(`friendshipGuards/${uid}`);
  cleanupDocs.add(`publicProfiles/${uid}`);
  cleanupDocs.add(socialCapacityReference(uid).path);
  const digest = createHash("sha256").update(uid).digest("hex");
  cleanupDocs.add(`privateRateLimits/socialGraph_mutation_${digest}`);
}

async function remove(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function cleanup() {
  await Promise.all(
    [...cleanupRoots].map((path) => remove(db.doc(path)).catch(() => undefined)),
  );
  const paths = [...cleanupDocs];
  for (let offset = 0; offset < paths.length; offset += 400) {
    const batch = db.batch();
    for (const path of paths.slice(offset, offset + 400)) {
      batch.delete(db.doc(path));
    }
    await batch.commit();
  }
  cleanupRoots.clear();
  cleanupDocs.clear();
}

after(cleanup);

async function writeDocuments(entries) {
  for (let offset = 0; offset < entries.length; offset += 400) {
    const batch = db.batch();
    for (const [path, value] of entries.slice(offset, offset + 400)) {
      batch.set(db.doc(path), value);
    }
    await batch.commit();
  }
}

async function seedProfiles(uids) {
  const writes = [];
  for (const uid of uids) {
    trackUser(uid);
    writes.push(
      [
        `users/${uid}`,
        {
          uid,
          displayName: uid,
          username: uid,
          friendCount: 0,
          followerCount: 0,
          followingCount: 0,
        },
      ],
      [
        `publicProfiles/${uid}`,
        { uid, displayName: uid, username: uid, photoUrl: null },
      ],
    );
  }
  await writeDocuments(writes);
}

test("a full legacy block list migrates once and concurrent blocks stay capped", async () => {
  const actor = "sc-block-actor";
  const targets = ["sc-block-first", "sc-block-second", "sc-block-third"];
  await seedProfiles([actor, ...targets]);
  await writeDocuments(
    Array.from({ length: MAX_BLOCKED_USERS }, (_, index) => {
      const targetId = `sc-block-legacy-${String(index).padStart(4, "0")}`;
      return [`users/${actor}/blocked/${targetId}`, { userId: targetId }];
    }),
  );

  await assert.rejects(
    runBlock(request(actor, { targetUserId: targets[0], blocked: true })),
    (error) => error.code === "resource-exhausted",
  );
  const capacityRef = socialCapacityReference(actor);
  const migrated = await capacityRef.get();
  assert.equal(migrated.data().blockedCount, MAX_BLOCKED_USERS);
  assert.equal(migrated.data().blockedOverflowed, false);
  const migratedAt = migrated.data().blockedMigratedAt.toMillis();

  await assert.rejects(
    runBlock(request(actor, { targetUserId: targets[1], blocked: true })),
    (error) => error.code === "resource-exhausted",
  );
  const replayedDenial = await capacityRef.get();
  assert.equal(replayedDenial.data().blockedMigratedAt.toMillis(), migratedAt);
  assert.equal(
    (await db.doc(`users/${actor}/blocked/${targets[1]}`).get()).exists,
    false,
  );

  await runBlock(
    request(actor, { targetUserId: "sc-block-legacy-0000", blocked: false }),
  );
  const attempts = await Promise.allSettled([
    runBlock(request(actor, { targetUserId: targets[0], blocked: true })),
    runBlock(request(actor, { targetUserId: targets[1], blocked: true })),
  ]);
  assert.equal(
    attempts.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    attempts.find((result) => result.status === "rejected").reason.code,
    "resource-exhausted",
  );
  const winnerIndex = attempts.findIndex(
    (result) => result.status === "fulfilled",
  );
  const winner = targets[winnerIndex];
  const replay = await runBlock(
    request(actor, { targetUserId: winner, blocked: true }),
  );
  assert.equal(replay.changed, false);
  assert.equal((await capacityRef.get()).data().blockedCount, MAX_BLOCKED_USERS);
  await cleanup();
});

test("outgoing request capacity is O(1) after migration and serializes races", async () => {
  const actor = "sc-outgoing-actor";
  const legacyTarget = "sc-outgoing-legacy-target";
  const targets = ["sc-outgoing-first", "sc-outgoing-second"];
  await seedProfiles([actor, legacyTarget, ...targets]);
  const writes = Array.from({ length: MAX_PENDING_REQUESTS }, (_, index) => {
    const targetId =
      index === 0
        ? legacyTarget
        : `sc-outgoing-legacy-${String(index).padStart(3, "0")}`;
    return [
      `users/${actor}/sentFriendRequests/${targetId}`,
      { receiverId: targetId },
    ];
  });
  writes.push([
    `users/${legacyTarget}/friendRequests/${actor}`,
    { senderId: actor },
  ]);
  await writeDocuments(writes);

  await assert.rejects(
    runSend(request(actor, { targetUserId: targets[0] })),
    (error) => error.code === "resource-exhausted",
  );
  const capacityRef = socialCapacityReference(actor);
  const migrated = await capacityRef.get();
  assert.equal(migrated.data().pendingOutgoingCount, MAX_PENDING_REQUESTS);
  const migratedAt = migrated.data().pendingOutgoingMigratedAt.toMillis();
  await assert.rejects(
    runSend(request(actor, { targetUserId: targets[1] })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(
    (await capacityRef.get()).data().pendingOutgoingMigratedAt.toMillis(),
    migratedAt,
  );

  await runCancel(request(actor, { targetUserId: legacyTarget }));
  const attempts = await Promise.allSettled(
    targets.map((targetUserId) => runSend(request(actor, { targetUserId }))),
  );
  assert.equal(
    attempts.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    attempts.find((result) => result.status === "rejected").reason.code,
    "resource-exhausted",
  );
  const winnerIndex = attempts.findIndex(
    (result) => result.status === "fulfilled",
  );
  const winner = targets[winnerIndex];
  const replay = await runSend(request(actor, { targetUserId: winner }));
  assert.equal(replay.outcome, "alreadyPending");
  assert.equal(
    (await capacityRef.get()).data().pendingOutgoingCount,
    MAX_PENDING_REQUESTS,
  );

  await runRespond(request(winner, { senderId: actor, accept: false }));
  assert.equal(
    (await capacityRef.get()).data().pendingOutgoingCount,
    MAX_PENDING_REQUESTS - 1,
  );
  assert.equal(
    (await socialCapacityReference(winner).get()).data().pendingIncomingCount,
    0,
  );
  await cleanup();
});

test("a full incoming queue migrates once across unrelated senders", async () => {
  const target = "sc-incoming-target";
  const actors = ["sc-incoming-first", "sc-incoming-second"];
  await seedProfiles([target, ...actors]);
  await writeDocuments(
    Array.from({ length: MAX_PENDING_REQUESTS }, (_, index) => {
      const senderId = `sc-incoming-legacy-${String(index).padStart(3, "0")}`;
      return [
        `users/${target}/friendRequests/${senderId}`,
        { senderId },
      ];
    }),
  );

  await assert.rejects(
    runSend(request(actors[0], { targetUserId: target })),
    (error) => error.code === "resource-exhausted",
  );
  const capacityRef = socialCapacityReference(target);
  const migrated = await capacityRef.get();
  assert.equal(migrated.data().pendingIncomingCount, MAX_PENDING_REQUESTS);
  const migratedAt = migrated.data().pendingIncomingMigratedAt.toMillis();
  await assert.rejects(
    runSend(request(actors[1], { targetUserId: target })),
    (error) => error.code === "resource-exhausted",
  );
  const second = await capacityRef.get();
  assert.equal(second.data().pendingIncomingMigratedAt.toMillis(), migratedAt);
  assert.equal(second.data().pendingIncomingCount, MAX_PENDING_REQUESTS);
  await cleanup();
});

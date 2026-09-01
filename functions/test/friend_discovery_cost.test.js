const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { test, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  consumeFriendDiscoveryRateLimit,
  friendDiscoveryCacheReference,
  getFriendSuggestions,
  getMutualFriends,
  MAX_FRIENDS_EXPANDED,
  MAX_EXPANDED_FRIENDS_PER_SOURCE,
  MAX_SUGGESTION_CANDIDATES,
  MAX_MUTUAL_FRIENDS_SCANNED,
  FRIEND_DISCOVERY_MINUTE_LIMIT,
  SUGGESTION_GRAPH_READ_BUDGET,
  MUTUAL_GRAPH_READ_BUDGET,
  QUOTA_MINUTE_MS,
  QUOTA_HOUR_MS,
} = require("../friends/social_graph");

const runSuggestions = getFriendSuggestions.run ?? getFriendSuggestions;
const runMutuals = getMutualFriends.run ?? getMutualFriends;

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

function discoveryQuotaPath(uid, kind) {
  const digest = createHash("sha256").update(uid).digest("hex");
  return `privateRateLimits/friendDiscovery_${kind}_${digest}`;
}

function trackUser(uid) {
  cleanupRoots.add(`users/${uid}`);
  cleanupRoots.add(`friendshipGuards/${uid}`);
  cleanupDocs.add(`publicProfiles/${uid}`);
  for (const kind of ["suggestions", "mutuals"]) {
    cleanupDocs.add(discoveryQuotaPath(uid, kind));
  }
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
          profileVisibility: "public",
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

function guardWrite(ownerId, friendId) {
  cleanupRoots.add(`friendshipGuards/${ownerId}`);
  return [
    `friendshipGuards/${ownerId}/friends/${friendId}`,
    { ownerId, friendId, schemaVersion: 1 },
  ];
}

test("friend-discovery quotas are atomic, isolated and reset both windows", async () => {
  const base = Timestamp.fromMillis(1_780_000_000_000);
  for (const kind of ["suggestions", "mutuals"]) {
    const uid = `fd-quota-${kind}`;
    const otherUid = `fd-quota-${kind}-other`;
    trackUser(uid);
    trackUser(otherUid);
    const attempts = await Promise.allSettled(
      Array.from({ length: FRIEND_DISCOVERY_MINUTE_LIMIT + 1 }, () =>
        consumeFriendDiscoveryRateLimit(uid, kind, {
          now: base,
          minuteLimit: FRIEND_DISCOVERY_MINUTE_LIMIT,
          hourLimit: FRIEND_DISCOVERY_MINUTE_LIMIT + 1,
        }),
      ),
    );
    assert.equal(
      attempts.filter((result) => result.status === "fulfilled").length,
      FRIEND_DISCOVERY_MINUTE_LIMIT,
    );
    assert.equal(
      attempts.find((result) => result.status === "rejected").reason.code,
      "resource-exhausted",
    );

    const independent = await consumeFriendDiscoveryRateLimit(otherUid, kind, {
      now: base,
      minuteLimit: 1,
      hourLimit: 1,
    });
    assert.deepEqual(independent, { minuteCount: 1, hourCount: 1 });

    const minuteReset = await consumeFriendDiscoveryRateLimit(uid, kind, {
      now: Timestamp.fromMillis(base.toMillis() + QUOTA_MINUTE_MS),
      minuteLimit: FRIEND_DISCOVERY_MINUTE_LIMIT,
      hourLimit: FRIEND_DISCOVERY_MINUTE_LIMIT + 1,
    });
    assert.deepEqual(minuteReset, {
      minuteCount: 1,
      hourCount: FRIEND_DISCOVERY_MINUTE_LIMIT + 1,
    });
    await assert.rejects(
      consumeFriendDiscoveryRateLimit(uid, kind, {
        now: Timestamp.fromMillis(base.toMillis() + 2 * QUOTA_MINUTE_MS),
        minuteLimit: FRIEND_DISCOVERY_MINUTE_LIMIT,
        hourLimit: FRIEND_DISCOVERY_MINUTE_LIMIT + 1,
      }),
      (error) => error.code === "resource-exhausted",
    );
    const hourReset = await consumeFriendDiscoveryRateLimit(uid, kind, {
      now: Timestamp.fromMillis(base.toMillis() + QUOTA_HOUR_MS),
      minuteLimit: FRIEND_DISCOVERY_MINUTE_LIMIT,
      hourLimit: FRIEND_DISCOVERY_MINUTE_LIMIT + 1,
    });
    assert.deepEqual(hourReset, { minuteCount: 1, hourCount: 1 });
  }
  await cleanup();
});

test("N+1 is denied before either endpoint can read a deleted profile graph", async () => {
  const suggestionCaller = "fd-nplus-suggestions";
  const mutualCaller = "fd-nplus-mutuals";
  const mutualTarget = "fd-nplus-target";
  await seedProfiles([suggestionCaller, mutualCaller, mutualTarget]);

  await runSuggestions(request(suggestionCaller, { limit: 10 }));
  await runSuggestions(request(suggestionCaller, { limit: 10 }));
  const suggestionCacheRef = friendDiscoveryCacheReference(
    suggestionCaller,
    "suggestions",
  );
  cleanupDocs.add(suggestionCacheRef.path);
  const suggestionCacheBefore = await suggestionCacheRef.get();
  await db.doc(`users/${suggestionCaller}`).delete();
  await assert.rejects(
    runSuggestions(request(suggestionCaller, { limit: 10 })),
    (error) => error.code === "resource-exhausted",
  );
  const suggestionCacheAfter = await suggestionCacheRef.get();
  assert.equal(
    suggestionCacheAfter.data().computedAt.toMillis(),
    suggestionCacheBefore.data().computedAt.toMillis(),
  );

  await runMutuals(request(mutualCaller, { targetUserId: mutualTarget }));
  await runMutuals(request(mutualCaller, { targetUserId: mutualTarget }));
  const mutualCacheRef = friendDiscoveryCacheReference(
    mutualCaller,
    "mutuals",
    mutualTarget,
  );
  cleanupDocs.add(mutualCacheRef.path);
  const mutualCacheBefore = await mutualCacheRef.get();
  await db.doc(`users/${mutualCaller}`).delete();
  await assert.rejects(
    runMutuals(request(mutualCaller, { targetUserId: mutualTarget })),
    (error) => error.code === "resource-exhausted",
  );
  const mutualCacheAfter = await mutualCacheRef.get();
  assert.equal(
    mutualCacheAfter.data().computedAt.toMillis(),
    mutualCacheBefore.data().computedAt.toMillis(),
  );
  await cleanup();
});

test("suggestions have bounded full-fanout reads and reuse a safe cache", async () => {
  const caller = "fd-full-suggestions";
  const sources = Array.from(
    { length: MAX_FRIENDS_EXPANDED + 1 },
    (_, index) => `fd-s-source-${String(index).padStart(2, "0")}`,
  );
  const candidates = Array.from(
    { length: MAX_EXPANDED_FRIENDS_PER_SOURCE },
    (_, index) => `fd-s-candidate-${String(index).padStart(2, "0")}`,
  );
  const outsideCandidate = "fd-s-outside-candidate";
  await seedProfiles([caller, ...candidates, outsideCandidate]);

  const graphWrites = sources.map((sourceId) => guardWrite(caller, sourceId));
  for (const sourceId of sources.slice(0, MAX_FRIENDS_EXPANDED)) {
    for (const candidateId of candidates) {
      graphWrites.push(guardWrite(sourceId, candidateId));
    }
  }
  graphWrites.push(
    guardWrite(sources[MAX_FRIENDS_EXPANDED], outsideCandidate),
  );
  await writeDocuments(graphWrites);

  const first = await runSuggestions(request(caller, { limit: 25 }));
  assert.equal(first.suggestions.length, 25);
  assert.equal(
    first.suggestions.some((entry) => entry.uid === outsideCandidate),
    false,
  );
  assert.ok(
    first.suggestions.every(
      (entry) => entry.mutualCount === MAX_FRIENDS_EXPANDED,
    ),
  );

  const cacheRef = friendDiscoveryCacheReference(caller, "suggestions");
  cleanupDocs.add(cacheRef.path);
  const firstCache = await cacheRef.get();
  assert.equal(firstCache.data().entries.length, MAX_SUGGESTION_CANDIDATES);
  assert.ok(
    firstCache.data().graphReadUpperBound <= SUGGESTION_GRAPH_READ_BUDGET,
  );
  const blockedId = first.suggestions[0].uid;
  await db.doc(`users/${caller}/blocked/${blockedId}`).set({ userId: blockedId });

  const second = await runSuggestions(request(caller, { limit: 25 }));
  assert.equal(second.suggestions.length, 25);
  assert.equal(second.suggestions.some((entry) => entry.uid === blockedId), false);
  const secondCache = await cacheRef.get();
  assert.equal(
    secondCache.data().computedAt.toMillis(),
    firstCache.data().computedAt.toMillis(),
  );
  await cleanup();
});

test("mutuals cap both source scans and revalidate cached privacy state", async () => {
  const caller = "fd-full-mutual-caller";
  const target = "fd-full-mutual-target";
  const candidates = Array.from(
    { length: MAX_MUTUAL_FRIENDS_SCANNED },
    (_, index) => `fd-m-candidate-${String(index).padStart(2, "0")}`,
  );
  await seedProfiles([caller, target, ...candidates]);
  await writeDocuments(
    candidates.flatMap((candidateId) => [
      guardWrite(caller, candidateId),
      guardWrite(target, candidateId),
    ]),
  );

  const first = await runMutuals(request(caller, { targetUserId: target }));
  assert.equal(first.count, MAX_MUTUAL_FRIENDS_SCANNED);
  assert.equal(first.sample.length, 6);
  const cacheRef = friendDiscoveryCacheReference(caller, "mutuals", target);
  cleanupDocs.add(cacheRef.path);
  const firstCache = await cacheRef.get();
  assert.equal(firstCache.data().ids.length, MAX_MUTUAL_FRIENDS_SCANNED);
  assert.ok(firstCache.data().graphReadUpperBound <= MUTUAL_GRAPH_READ_BUDGET);

  const blockedId = first.sample[0].uid;
  await db.doc(`users/${blockedId}/blocked/${caller}`).set({ userId: caller });
  const second = await runMutuals(request(caller, { targetUserId: target }));
  assert.equal(second.count, MAX_MUTUAL_FRIENDS_SCANNED - 1);
  assert.equal(second.sample.some((entry) => entry.uid === blockedId), false);
  const secondCache = await cacheRef.get();
  assert.equal(
    secondCache.data().computedAt.toMillis(),
    firstCache.data().computedAt.toMillis(),
  );
  await cleanup();
});

test("both discovery bindings cap autoscaling blast radius", () => {
  assert.equal(getFriendSuggestions.__endpoint.maxInstances, 20);
  assert.equal(getMutualFriends.__endpoint.maxInstances, 20);
});

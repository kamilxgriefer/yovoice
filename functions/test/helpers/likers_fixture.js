// Shared fixtures for the three "See who liked" list callables (ADR-230):
// the activation document, a canonical VIP grant, canonical public profiles,
// likers who pass (or fail) the one liker predicate, and read accounting over
// InMemoryFirestore that counts EVERY document a call reads (point reads,
// getAll, transaction reads and query results) and every path a read-write
// transaction touched.
const assert = require("node:assert/strict");
const { HttpsError } = require("firebase-functions/v2/https");

const { LIKERS_ACTIVATION_PATH } = require("../../engagement/likers_activation");

function activation(nowMs, overrides = {}) {
  return {
    schemaVersion: 1,
    enabled: true,
    serverMessagesEnabled: true,
    updatedAt: new Date(nowMs - 1_000),
    ...overrides,
  };
}

function testerGrant() {
  return {
    source: "testerProgram",
    expiresAt: null,
    revoked: false,
    grantedBy: "owner-console",
  };
}

function publicProfile(uid, nowMs, overrides = {}) {
  return {
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: null,
    creatorAudienceVisible: false,
    displayName: `Name ${uid}`,
    displayNameSearch: `name ${uid}`,
    followerCount: 0,
    followingCount: 0,
    friendCount: 0,
    learningLanguages: [],
    nativeLanguage: null,
    photoUrl: `https://public.invalid/${uid}.png`,
    premiumIdentity: null,
    schemaVersion: 1,
    spokenLanguages: [],
    statusMessage: "",
    uid,
    updatedAt: new Date(nowMs - 60_000),
    username: null,
    usernameSearch: null,
    website: null,
    ...overrides,
  };
}

function friendshipGuard(ownerId, friendId, nowMs) {
  return {
    schemaVersion: 1,
    ownerId,
    friendId,
    establishedAt: new Date(nowMs - 3_600_000),
  };
}

// A person who passes every predicate unless `options` says otherwise.
function seedPerson(db, uid, {
  nowMs,
  viewerId,
  user = {},
  omitUser = false,
  publicDoc = undefined,
  mute = null,
  viewerBlocks = false,
  personBlocks = false,
  friends = null, // null | "both" | "forward"
} = {}) {
  if (!omitUser) db.seed(`users/${uid}`, { role: "user", ...user });
  const profile = publicDoc === undefined ? publicProfile(uid, nowMs) : publicDoc;
  if (profile !== null) db.seed(`publicProfiles/${uid}`, profile);
  if (mute !== null) db.seed(`restrictions/${uid}`, mute);
  if (viewerBlocks) {
    db.seed(`users/${viewerId}/blocked/${uid}`, { blockedAt: new Date(nowMs) });
  }
  if (personBlocks) {
    db.seed(`users/${uid}/blocked/${viewerId}`, { blockedAt: new Date(nowMs) });
  }
  if (friends === "both" || friends === "forward") {
    db.seed(`friendshipGuards/${viewerId}/friends/${uid}`,
      friendshipGuard(viewerId, uid, nowMs));
  }
  if (friends === "both") {
    db.seed(`friendshipGuards/${uid}/friends/${viewerId}`,
      friendshipGuard(uid, viewerId, nowMs));
  }
}

// Hidden-liker variants every callable suite checks end to end.
function hiddenVariants(nowMs) {
  return {
    likesHidden: { user: { likesHidden: true } },
    privateProfile: { user: { profileVisibility: "private" } },
    friendsOnlyStranger: { user: { profileVisibility: "friends" }, friends: "forward" },
    muted: { mute: { type: "communicationMute", expiresAt: new Date(nowMs + 60_000) } },
    viewerBlocked: { viewerBlocks: true },
    blockedViewer: { personBlocks: true },
    banned: { user: { banned: true } },
    deletedAccount: { omitUser: true },
    authDeleted: { user: { authDeletedAt: new Date(nowMs - 1) } },
    noPublicProfile: { publicDoc: null },
  };
}

function seedViewer(db, viewerId, nowMs, { grant = testerGrant(), config = activation(nowMs) } = {}) {
  if (config !== null) db.seed(LIKERS_ACTIVATION_PATH, config);
  db.seed(`users/${viewerId}`, { role: "user" });
  db.seed(`publicProfiles/${viewerId}`, publicProfile(viewerId, nowMs));
  if (grant !== null) db.seed(`vipGrants/${viewerId}`, grant);
}

// Counts every document the in-memory database hands out (each one is a
// billed read), and records the paths every read-write transaction read.
function instrument(db) {
  let documentReads = 0;
  const snapshot = db._snapshot.bind(db);
  db._snapshot = (reference, documents) => {
    documentReads += 1;
    return snapshot(reference, documents);
  };
  const transactionReads = [];
  let transactions = 0;
  const runTransaction = db.runTransaction.bind(db);
  db.runTransaction = async (callback) => {
    transactions += 1;
    return runTransaction(async (transaction) => callback({
      ...transaction,
      get: async (reference) => {
        transactionReads.push(reference.path ?? `query:${reference.collectionPath}`);
        return transaction.get(reference);
      },
      getAll: async (...references) => {
        transactionReads.push(...references.map((reference) => reference.path));
        return transaction.getAll(...references);
      },
    }));
  };
  return {
    reads: () => documentReads,
    reset: () => {
      documentReads = 0;
      transactionReads.length = 0;
      transactions = 0;
    },
    transactionReads,
    transactionCount: () => transactions,
  };
}

function rateState(db, scope, uid) {
  return db.paths("privateRateLimits/")
    .map((path) => db.data(path))
    .find((value) => value.scope === scope && (uid === undefined || value.ownerId === uid));
}

async function rejectsWith(promise, code, { reason, message } = {}) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof HttpsError, String(error));
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    if (reason !== undefined) assert.deepEqual(error.details, { reason });
    if (message !== undefined) assert.equal(error.message, message);
    return true;
  });
}

function assertExactPage(page) {
  assert.deepEqual(Object.keys(page).sort(), ["hasMore", "likers", "nextCursor", "schemaVersion"]);
  assert.equal(page.schemaVersion, 1);
  assert.ok(page.likers.length <= 20);
  assert.equal(page.hasMore, page.nextCursor !== null);
  if (page.nextCursor !== null) assert.match(page.nextCursor, /^[A-Za-z0-9_-]{43}$/u);
  for (const row of page.likers) {
    assert.deepEqual(Object.keys(row).sort(), ["displayName", "photoUrl", "reaction", "userId"]);
    assert.equal(row.photoUrl, null);
  }
}

module.exports = {
  activation,
  assertExactPage,
  friendshipGuard,
  hiddenVariants,
  instrument,
  publicProfile,
  rateState,
  rejectsWith,
  seedPerson,
  seedViewer,
  testerGrant,
};

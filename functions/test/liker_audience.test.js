// ADR-230: the one liker predicate (engagement/liker_audience.js) and its
// phased loader, for content likes and Server message reactors.
const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  LIKER_CONTEXT_MAX_READS,
  likerIsVisible,
  likerResolver,
  likesHiddenOf,
  loadLikerContexts,
  projectLiker,
} = require("../engagement/liker_audience");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");
const { tracked } = require("./helpers/read_tracker");

const NOW_MS = 1_820_000_000_000;
const VIEWER = "viewer-uid";
const SERVER_ID = "server-1";
const SERVER = Object.freeze({ ownerId: "server-owner-uid" });

function publicProfile(uid, overrides = {}) {
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
    photoUrl: null,
    premiumIdentity: null,
    schemaVersion: 1,
    spokenLanguages: [],
    statusMessage: "",
    uid,
    updatedAt: new Date(NOW_MS - 60_000),
    username: null,
    usernameSearch: null,
    website: null,
    ...overrides,
  };
}

function guard(ownerId, friendId) {
  return {
    schemaVersion: 1,
    ownerId,
    friendId,
    establishedAt: new Date(NOW_MS - 3_600_000),
  };
}

// A liker who passes every predicate unless `options` says otherwise.
function seedLiker(db, uid, options = {}) {
  const {
    user = {},
    omitUser = false,
    publicDoc = publicProfile(uid),
    mute = null,
    viewerBlocks = false,
    likerBlocks = false,
    friends = null, // null | "both" | "forward" | "reverse"
    member = { userId: uid, role: "member", authorizationRevision: 1 },
  } = options;
  if (!omitUser) db.seed(`users/${uid}`, { role: "user", ...user });
  if (publicDoc !== null) db.seed(`publicProfiles/${uid}`, publicDoc);
  if (mute !== null) db.seed(`restrictions/${uid}`, mute);
  if (viewerBlocks) db.seed(`users/${VIEWER}/blocked/${uid}`, { blockedAt: new Date(NOW_MS) });
  if (likerBlocks) db.seed(`users/${uid}/blocked/${VIEWER}`, { blockedAt: new Date(NOW_MS) });
  if (friends === "both" || friends === "forward") {
    db.seed(`friendshipGuards/${VIEWER}/friends/${uid}`, guard(VIEWER, uid));
  }
  if (friends === "both" || friends === "reverse") {
    db.seed(`friendshipGuards/${uid}/friends/${VIEWER}`, guard(uid, VIEWER));
  }
  if (member !== null) db.seed(`clubs/${SERVER_ID}/members/${uid}`, member);
}

async function visibility(db, likerIds, { surface = "content" } = {}) {
  const contexts = await loadLikerContexts({
    getAll: (...references) => db.getAll(...references),
    db,
    viewerId: VIEWER,
    likerIds,
    nowMs: NOW_MS,
    surface,
    serverId: surface === "serverMessage" ? SERVER_ID : null,
    server: surface === "serverMessage" ? SERVER : null,
  });
  return Object.fromEntries(likerIds.map((likerId) => [
    likerId,
    likerIsVisible(contexts.get(likerId), { viewerId: VIEWER, nowMs: NOW_MS }),
  ]));
}

function viewerWorld() {
  const db = new InMemoryFirestore();
  db.seed(`users/${VIEWER}`, { role: "user" });
  db.seed(`publicProfiles/${VIEWER}`, publicProfile(VIEWER));
  return db;
}

const MATRIX = Object.freeze({
  shown: {},
  banned: { user: { banned: true } },
  disabled: { user: { disabled: true } },
  deleted: { user: { deleted: true } },
  statusDeleted: { user: { status: "deleted" } },
  authDeleted: { user: { authDeletedAt: new Date(NOW_MS - 1) } },
  missingUser: { omitUser: true },
  muted: { mute: { type: "communicationMute", expiresAt: new Date(NOW_MS + 60_000) } },
  mutedForever: { mute: { type: "communicationMute", expiresAt: null } },
  muteExpired: { mute: { type: "communicationMute", expiresAt: new Date(NOW_MS - 1) } },
  viewerBlocked: { viewerBlocks: true },
  likerBlocked: { likerBlocks: true },
  private: { user: { profileVisibility: "private" } },
  malformedVisibility: { user: { profileVisibility: "everyone" } },
  friendsBoth: { user: { profileVisibility: "friends" }, friends: "both" },
  friendsForwardOnly: { user: { profileVisibility: "friends" }, friends: "forward" },
  friendsReverseOnly: { user: { profileVisibility: "friends" }, friends: "reverse" },
  friendsNone: { user: { profileVisibility: "friends" } },
  likesHiddenTrue: { user: { likesHidden: true } },
  likesHiddenFalse: { user: { likesHidden: false } },
  likesHiddenNull: { user: { likesHidden: null } },
  likesHiddenString: { user: { likesHidden: "false" } },
  missingPublicProfile: { publicDoc: null },
  malformedPublicProfile: { publicDoc: { ...publicProfile("x"), uid: "someone-else" } },
});

const EXPECTED_CONTENT = Object.freeze({
  shown: true,
  banned: false,
  disabled: false,
  deleted: false,
  statusDeleted: false,
  authDeleted: false,
  missingUser: false,
  muted: false,
  mutedForever: false,
  muteExpired: true,
  viewerBlocked: false,
  likerBlocked: false,
  private: false,
  malformedVisibility: false,
  friendsBoth: true,
  friendsForwardOnly: false,
  friendsReverseOnly: false,
  friendsNone: false,
  likesHiddenTrue: false,
  likesHiddenFalse: true,
  likesHiddenNull: false,
  likesHiddenString: false,
  missingPublicProfile: false,
  malformedPublicProfile: false,
});

describe("likesHiddenOf", () => {
  test("missing or false is visible; anything else hides (fail closed)", () => {
    assert.equal(likesHiddenOf({}), false);
    assert.equal(likesHiddenOf({ likesHidden: false }), false);
    for (const value of [true, null, "false", 0, 1, {}, []]) {
      assert.equal(likesHiddenOf({ likesHidden: value }), true, JSON.stringify(value));
    }
    assert.equal(likesHiddenOf(null), true);
    assert.equal(likesHiddenOf(undefined), true);
  });

  test("accepts the users snapshot as well as its data", () => {
    const snapshot = (data) => ({ exists: data !== undefined, data: () => data });
    assert.equal(likesHiddenOf(snapshot({ role: "user" })), false);
    assert.equal(likesHiddenOf(snapshot({ likesHidden: true })), true);
    assert.equal(likesHiddenOf(snapshot(undefined)), true);
  });
});

describe("liker predicate matrix", () => {
  for (const surface of ["content", "serverMessage"]) {
    test(`every case on the ${surface} surface`, async () => {
      const db = viewerWorld();
      const ids = Object.keys(MATRIX).map((label) => `liker-${label}`);
      Object.entries(MATRIX).forEach(([label, options]) =>
        seedLiker(db, `liker-${label}`, options));
      const result = await visibility(db, ids, { surface });
      for (const label of Object.keys(MATRIX)) {
        assert.equal(result[`liker-${label}`], EXPECTED_CONTENT[label], `${surface}: ${label}`);
      }
    });
  }

  test("the viewer always sees themself, even hidden, private or muted", async () => {
    const db = new InMemoryFirestore();
    seedLiker(db, VIEWER, {
      user: { likesHidden: true, profileVisibility: "private" },
      mute: { type: "communicationMute", expiresAt: null },
    });
    for (const surface of ["content", "serverMessage"]) {
      const result = await visibility(db, [VIEWER], { surface });
      assert.equal(result[VIEWER], true, surface);
    }
  });

  test("server reactors must be canonical members", async () => {
    const db = viewerWorld();
    seedLiker(db, "departed", { member: null });
    seedLiker(db, "banned-member", {
      member: { userId: "banned-member", role: "member", authorizationRevision: 1, banned: true },
    });
    seedLiker(db, "wrong-user", {
      member: { userId: "someone", role: "member", authorizationRevision: 1 },
    });
    seedLiker(db, "bad-revision", {
      member: { userId: "bad-revision", role: "member", authorizationRevision: 0 },
    });
    seedLiker(db, "fake-owner", {
      member: { userId: "fake-owner", role: "owner", authorizationRevision: 1 },
    });
    seedLiker(db, "guest", {
      member: { userId: "guest", role: "guest", authorizationRevision: 2 },
    });
    const ids = ["departed", "banned-member", "wrong-user", "bad-revision", "fake-owner", "guest"];
    assert.deepEqual(await visibility(db, ids, { surface: "serverMessage" }), {
      departed: false,
      "banned-member": false,
      "wrong-user": false,
      "bad-revision": false,
      "fake-owner": false,
      guest: true,
    });
    // Membership is not part of the content predicate.
    assert.equal((await visibility(db, ["departed"]))["departed"], true);
  });

  test("invalid ids are hidden and cost no read", async () => {
    const db = viewerWorld();
    const probe = tracked(db);
    const contexts = await loadLikerContexts({
      getAll: (...references) => probe.db.getAll(...references),
      db: probe.db,
      viewerId: VIEWER,
      likerIds: ["", "a/b", "x".repeat(129)],
      nowMs: NOW_MS,
    });
    assert.deepEqual(probe.reads, []);
    for (const context of contexts.values()) {
      assert.equal(likerIsVisible(context, { viewerId: VIEWER, nowMs: NOW_MS }), false);
    }
  });
});

describe("phased loader", () => {
  test("phase 2 and 3 are never read for a candidate hidden in phase 1", async () => {
    const db = viewerWorld();
    seedLiker(db, "hides", { user: { likesHidden: true } });
    seedLiker(db, "private", { user: { profileVisibility: "private" } });
    seedLiker(db, "banned", { user: { banned: true } });
    seedLiker(db, "public-one");
    const probe = tracked(db);
    await loadLikerContexts({
      getAll: (...references) => probe.db.getAll(...references),
      db: probe.db,
      viewerId: VIEWER,
      likerIds: ["hides", "private", "banned", "public-one"],
      nowMs: NOW_MS,
    });
    for (const hidden of ["hides", "private", "banned"]) {
      assert.deepEqual(
        probe.reads.filter((path) => path.includes(hidden)),
        [`users/${hidden}`],
        hidden,
      );
    }
    assert.deepEqual(probe.reads.filter((path) => path.includes("public-one")), [
      "users/public-one",
      "publicProfiles/public-one",
      "restrictions/public-one",
      `users/${VIEWER}/blocked/public-one`,
      "users/public-one/blocked/viewer-uid",
    ]);
    assert.equal(probe.reads.some((path) => path.startsWith("friendshipGuards/")), false);
  });

  test("friendship guards are read only for friends-only phase-2 survivors", async () => {
    const db = viewerWorld();
    seedLiker(db, "friend", { user: { profileVisibility: "friends" }, friends: "both" });
    seedLiker(db, "friend-muted", {
      user: { profileVisibility: "friends" },
      friends: "both",
      mute: { type: "communicationMute", expiresAt: null },
    });
    const probe = tracked(db);
    await loadLikerContexts({
      getAll: (...references) => probe.db.getAll(...references),
      db: probe.db,
      viewerId: VIEWER,
      likerIds: ["friend", "friend-muted"],
      nowMs: NOW_MS,
    });
    const guardReads = probe.reads.filter((path) => path.startsWith("friendshipGuards/"));
    assert.deepEqual(guardReads, [
      `friendshipGuards/${VIEWER}/friends/friend`,
      `friendshipGuards/friend/friends/${VIEWER}`,
    ]);
  });

  test("the per-candidate read bound holds on each surface", async () => {
    for (const surface of ["content", "serverMessage"]) {
      const db = viewerWorld();
      seedLiker(db, "friend", { user: { profileVisibility: "friends" }, friends: "both" });
      const probe = tracked(db);
      const contexts = await loadLikerContexts({
        getAll: (...references) => probe.db.getAll(...references),
        db: probe.db,
        viewerId: VIEWER,
        likerIds: ["friend", "friend"],
        nowMs: NOW_MS,
        surface,
        serverId: surface === "serverMessage" ? SERVER_ID : null,
        server: surface === "serverMessage" ? SERVER : null,
      });
      assert.equal(probe.reads.length, LIKER_CONTEXT_MAX_READS[surface], surface);
      assert.equal(
        likerIsVisible(contexts.get("friend"), { viewerId: VIEWER, nowMs: NOW_MS }),
        true,
        surface,
      );
    }
  });

  test("the loader never opens a transaction", async () => {
    const db = viewerWorld();
    seedLiker(db, "someone");
    const probe = tracked(db);
    await likerResolver({
      getAll: (...references) => probe.db.getAll(...references),
      db: probe.db,
      viewerId: VIEWER,
      nowMs: NOW_MS,
    })([{ position: 1, likerId: "someone" }]);
    assert.equal(probe.transactionCount(), 0);
  });

  test("server contexts need the server and its id", async () => {
    await assert.rejects(loadLikerContexts({
      getAll: async () => [],
      db: new InMemoryFirestore(),
      viewerId: VIEWER,
      likerIds: [],
      nowMs: NOW_MS,
      surface: "serverMessage",
    }), TypeError);
  });
});

describe("projection", () => {
  test("rows carry the canonical name, a null photo and the reaction", async () => {
    const db = viewerWorld();
    seedLiker(db, "named", {
      publicDoc: publicProfile("named", {
        displayName: `  ${"N".repeat(90)}  `,
        photoUrl: "https://example.com/avatar.png",
      }),
    });
    seedLiker(db, "hidden", { user: { likesHidden: true } });
    const rows = await likerResolver({
      getAll: (...references) => db.getAll(...references),
      db,
      viewerId: VIEWER,
      nowMs: NOW_MS,
      surface: "serverMessage",
      serverId: SERVER_ID,
      server: SERVER,
    })([
      { position: { emojiIndex: 0, uid: "named" }, likerId: "named", reaction: "❤️" },
      { position: { emojiIndex: 0, uid: "hidden" }, likerId: "hidden", reaction: "❤️" },
      { position: { emojiIndex: 1, uid: "malformed" }, likerId: null, reaction: null },
    ]);
    assert.deepEqual(rows, [
      { userId: "named", displayName: "N".repeat(80), photoUrl: null, reaction: "❤️" },
      null,
      null,
    ]);
  });

  test("projecting a hidden context is refused", () => {
    assert.throws(() => projectLiker({ likerId: "x", publicProfile: null }), TypeError);
  });
});

// listServerChannelMessageReactorsV1 (ADR-230): "See who reacted" on a
// Servers V1 channel message, through the real reaction service over
// InMemoryFirestore seeded with the canonical Servers fixture. Channel ACL
// via readChannelAccess, the reactable-message rule, emoji-then-uid order,
// resuming against the CURRENT map, the member-row predicate, both switches
// of appConfig/likersV1, the gate and the budgets.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const { ALLOWED_DIRECT_REACTIONS } = require("../messaging/direct_integrity");
const {
  SERVER_MESSAGE_REACTORS_READ_BUDGETS,
  createServerMessageReactionService,
} = require("../servers/message_reactions");
const {
  SERVER_MESSAGE_CALLABLE_METHODS,
  SERVER_MESSAGE_EXPORT_NAMES,
  SERVERS_V1_EXPORT_NAMES,
} = require("../servers/registration");
const { seedServerMessaging } = require("./helpers/server_message_fixture");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");
const {
  activation,
  assertExactPage,
  hiddenVariants,
  instrument,
  rateState,
  rejectsWith,
  seedPerson,
  seedViewer,
} = require("./helpers/likers_fixture");

const NOW_MS = 1_900_000_000_000;
const Timestamp = Object.freeze({ fromMillis: (value) => new Date(value) });
const UNAVAILABLE = "This content is unavailable.";
const [HEART, LAUGH, FIRE, WOW, SAD, THUMBS] = ALLOWED_DIRECT_REACTIONS;

function member(uid, role = "member", extra = {}) {
  return {
    userId: uid,
    displayName: `Canonical ${uid}`,
    photoUrl: null,
    role,
    isOnline: false,
    joinedAt: new Date(NOW_MS - 86_400_000),
    invitedBy: null,
    authorizationRevision: 1,
    ...extra,
  };
}

async function world({ config, grant, viewerKey = "member" } = {}) {
  const db = new InMemoryFirestore();
  const seeded = await seedServerMessaging(db, Timestamp, { label: "lr", nowMs: NOW_MS });
  const viewer = seeded.users[viewerKey];
  seedViewer(db, viewer, NOW_MS, {
    ...(config === undefined ? {} : { config }),
    ...(grant === undefined ? {} : { grant }),
  });
  // Every fixture account gets a canonical public profile.
  for (const uid of Object.values(seeded.users)) {
    if (uid !== viewer) seedPerson(db, uid, { nowMs: NOW_MS, viewerId: viewer });
  }
  const service = createServerMessageReactionService({
    db,
    Timestamp,
    clock: () => NOW_MS,
  });
  const list = (target, extra = {}, uid = viewer) => service.listServerChannelMessageReactorsV1({
    auth: { uid, token: { email_verified: false } },
    data: {
      serverId: seeded.serverId,
      channelId: target.channelId,
      messageId: target.id,
      ...extra,
    },
  });
  // A reactor who is a canonical member with a public profile.
  const addReactor = (uid, options = {}) => {
    seedPerson(db, uid, { nowMs: NOW_MS, viewerId: viewer, ...options });
    if (options.member !== null) {
      db.seed(`clubs/${seeded.serverId}/members/${uid}`, member(uid, "member", options.member));
    }
  };
  return {
    db,
    ...seeded,
    viewer,
    service,
    list,
    addReactor,
  };
}

test("registered in the Server message extension, outside the frozen manifest", () => {
  assert.equal(SERVER_MESSAGE_CALLABLE_METHODS.listServerChannelMessageReactorsV1, "messageReactions");
  assert.ok(SERVER_MESSAGE_EXPORT_NAMES.includes("listServerChannelMessageReactorsV1"));
  assert.equal(SERVERS_V1_EXPORT_NAMES.includes("listServerChannelMessageReactorsV1"), false);
  assert.equal(SERVERS_V1_EXPORT_NAMES.length, 62);
});

test("read budgets are pinned from the final code", () => {
  assert.deepEqual(SERVER_MESSAGE_REACTORS_READ_BUDGETS, { typical: 134, worst: 496 });
});

test("both switches: serverMessagesEnabled:false refuses only the server list", async () => {
  const f = await world({ config: activation(NOW_MS, { serverMessagesEnabled: false }) });
  const target = await f.message("text", { reactions: { [f.users.owner]: HEART } });
  const meter = instrument(f.db);
  await rejectsWith(f.list(target), "failed-precondition", { reason: "likersNotEnabled" });
  assert.equal(meter.reads(), 1);
  assert.equal(rateState(f.db, "likers.list"), undefined);
  const off = await world({ config: activation(NOW_MS, { enabled: false }) });
  const offTarget = await off.message("text");
  await rejectsWith(off.list(offTarget), "failed-precondition", { reason: "likersNotEnabled" });
  const missing = await world({ config: null });
  await rejectsWith(missing.list(await missing.message("text")), "failed-precondition", {
    reason: "likersNotEnabled",
  });
});

test("input and gate: exact keys, the six emoji, and Premium / VIP / staff only", async () => {
  const f = await world({ grant: null });
  const target = await f.message("text", { reactions: { [f.users.owner]: HEART } });
  const meter = instrument(f.db);
  await rejectsWith(f.list(target, { limit: 20 }), "invalid-argument");
  await rejectsWith(f.list(target, { emoji: "🙂" }), "invalid-argument");
  await rejectsWith(f.list(target, { requestId: "abcdefgh" }), "invalid-argument");
  await rejectsWith(f.service.listServerChannelMessageReactorsV1({ data: {} }), "unauthenticated");
  assert.equal(meter.reads(), 0);
  await rejectsWith(f.list(target), "failed-precondition", { reason: "likersAccessRequired" });
  assert.equal(meter.reads(), 8, "no server, channel, message or reactor read");
});

test("orders by emoji picker index, then uid, and filters by emoji", async () => {
  const f = await world();
  const ids = ["lr-b", "lr-a", "lr-d", "lr-c", "lr-e"];
  ids.forEach((uid) => f.addReactor(uid));
  const target = await f.message("text", {
    reactions: {
      "lr-b": THUMBS,
      "lr-a": FIRE,
      "lr-d": HEART,
      "lr-c": HEART,
      "lr-e": FIRE,
      [f.viewer]: LAUGH,
    },
  });
  const page = await f.list(target);
  assertExactPage(page);
  assert.deepEqual(
    page.likers.map((row) => [row.userId, row.reaction]),
    [["lr-c", HEART], ["lr-d", HEART], [f.viewer, LAUGH], ["lr-a", FIRE], ["lr-e", FIRE],
      ["lr-b", THUMBS]],
  );
  const fires = await f.list(target, { emoji: FIRE });
  assert.deepEqual(fires.likers.map((row) => row.userId), ["lr-a", "lr-e"]);
  assert.ok(fires.likers.every((row) => row.reaction === FIRE));
  const none = await f.list(target, { emoji: SAD });
  assert.deepEqual(none, { schemaVersion: 1, likers: [], nextCursor: null, hasMore: false });
});

test("departed, banned, deleted, blocked, private, muted and hidden reactors are omitted", async () => {
  const f = await world();
  f.addReactor("lr-visible");
  const reactions = { "lr-visible": HEART };
  for (const [label, options] of Object.entries(hiddenVariants(NOW_MS))) {
    const uid = `lr-hidden-${label}`;
    f.addReactor(uid, options);
    reactions[uid] = HEART;
  }
  // Departed: the uid stays in the map, the member row is gone.
  f.addReactor("lr-departed", { member: null });
  reactions["lr-departed"] = HEART;
  // Banned member row, and a member row bound to another uid.
  f.addReactor("lr-banned-member", { member: { banned: true } });
  reactions["lr-banned-member"] = WOW;
  f.addReactor("lr-foreign-row", { member: { userId: "someone-else" } });
  reactions["lr-foreign-row"] = WOW;
  // The fixture's muted member and banned member row.
  reactions[f.users.muted] = THUMBS;
  reactions[f.users.banned] = THUMBS;
  // Somebody who never was a member at all.
  reactions[f.users.outsider] = THUMBS;
  const target = await f.message("text", { reactions });
  const page = await f.list(target);
  assert.deepEqual(page.likers.map((row) => row.userId), ["lr-visible"]);
  assert.equal(page.hasMore, false);
});

test("channel ACL and the reactable-message rule collapse to one refusal", async () => {
  const f = await world();
  const text = await f.message("text", { reactions: { [f.users.owner]: HEART } });
  // A non-member cannot ask, even with VIP.
  f.db.seed(`vipGrants/${f.users.outsider}`, {
    source: "testerProgram", expiresAt: null, revoked: false,
  });
  await rejectsWith(f.list(text, {}, f.users.outsider), "permission-denied", {
    message: UNAVAILABLE,
  });
  // A restricted channel without a current grant.
  const restricted = await f.message("restricted", {
    senderKey: "owner",
    reactions: { [f.users.owner]: HEART },
  });
  f.db.seed(`vipGrants/${f.users.stranger}`, {
    source: "testerProgram", expiresAt: null, revoked: false,
  });
  await rejectsWith(f.list(restricted, {}, f.users.stranger), "permission-denied", {
    message: UNAVAILABLE,
  });
  // ...while the member with a current grant may list it.
  assert.equal((await f.list(restricted)).likers.length, 1);
  for (const [label, target] of Object.entries({
    voice: await f.message("voice"),
    deleted: await f.message("text", { isDeleted: true, content: "" }),
    missing: { channelId: f.channels.text, id: "cm_missing" },
    misbound: await f.message("text", { channelId: f.channels.announcements }),
    poll: await f.message("text", { type: "poll" }),
    malformedMap: await f.message("text", { reactions: { [f.users.owner]: "🙂" } }),
    missingChannel: { channelId: "no-such-channel", id: "cm_x" },
  })) {
    await rejectsWith(f.list(target), "permission-denied", { message: UNAVAILABLE })
      .catch((error) => {
        throw new Error(`${label}: ${error.message}`);
      });
  }
});

test("guests keep `read` and may list; announcements and rules threads are listable", async () => {
  const f = await world({ viewerKey: "guest" });
  f.addReactor("lr-one");
  const announcement = await f.message("announcements", {
    senderKey: "owner",
    reactions: { "lr-one": HEART },
  });
  assert.deepEqual((await f.list(announcement)).likers.map((row) => row.userId), ["lr-one"]);
  const rules = await f.message("rules", { senderKey: "moderator", reactions: { "lr-one": WOW } });
  assert.equal((await f.list(rules)).likers[0].reaction, WOW);
});

test("a message deleted during the scan is refused by the response-time re-check", async () => {
  const f = await world();
  f.addReactor("lr-one");
  const target = await f.message("text", { reactions: { "lr-one": HEART } });
  const getAll = f.db.getAll.bind(f.db);
  f.db.getAll = async (...references) => {
    const result = await getAll(...references);
    // The liker contexts are the last plain batch before the re-check.
    if (references.some((reference) => reference.path.startsWith("publicProfiles/"))) {
      await f.db.doc(target.path).set({ isDeleted: true }, { merge: true });
    }
    return result;
  };
  await rejectsWith(f.list(target), "permission-denied", { message: UNAVAILABLE });
  assert.equal(f.db.paths("likerPageCursors/").length, 0);
});

test("paging resumes strictly after (emoji, uid) in the CURRENT map", async () => {
  const f = await world();
  const reactions = {};
  // 25 hearts: lr-h-00 .. lr-h-24.
  for (let index = 0; index < 25; index += 1) {
    const uid = `lr-h-${String(index).padStart(2, "0")}`;
    f.addReactor(uid);
    reactions[uid] = HEART;
  }
  const target = await f.message("text", { reactions });
  const first = await f.list(target);
  assert.deepEqual(first.likers.map((row) => row.userId),
    Array.from({ length: 20 }, (_, index) => `lr-h-${String(index).padStart(2, "0")}`));
  assert.equal(first.hasMore, true);
  const stored = f.db.data(`likerPageCursors/${first.nextCursor}`);
  assert.deepEqual([stored.afterEmojiIndex, stored.afterUid, stored.afterId], [0, "lr-h-19", null]);
  assert.equal(JSON.stringify(stored).includes(f.users.owner), false);

  // Between pages: an earlier reactor leaves, a new one sorts before the
  // cursor, lr-h-21 switches to 🔥 and a newcomer reacts with 👍.
  f.addReactor("lr-h-000");
  f.addReactor("lr-late");
  const next = { ...reactions, "lr-h-000": HEART, "lr-h-21": FIRE, "lr-late": THUMBS };
  delete next["lr-h-03"];
  await f.db.doc(target.path).set({ reactions: next }, { merge: true });
  const second = await f.list(target, { cursor: first.nextCursor });
  assert.deepEqual(second.likers.map((row) => row.userId),
    ["lr-h-20", "lr-h-22", "lr-h-23", "lr-h-24", "lr-h-21", "lr-late"]);
  assert.equal(second.hasMore, false);

  // A cursor is bound to the emoji filter.
  await rejectsWith(f.list(target, { emoji: HEART, cursor: first.nextCursor }),
    "invalid-argument", { message: "cursor is invalid." });
});

test("no write lock: only the rate-limit transaction, and only the likers budgets", async () => {
  const f = await world();
  f.addReactor("lr-one");
  const target = await f.message("text", { reactions: { "lr-one": HEART } });
  const meter = instrument(f.db);
  await f.list(target);
  assert.equal(meter.transactionCount(), 1);
  for (const path of meter.transactionReads) assert.match(path, /^privateRateLimits\//u);
  assert.equal(rateState(f.db, "likers.list").count, 1);
  assert.equal(rateState(f.db, "server.channel.message.reaction"), undefined);
});

test("a typical page costs exactly `typical`; a worst page stays within `worst`", async () => {
  const f = await world();
  const reactions = {};
  for (let index = 0; index < 25; index += 1) {
    const uid = `lr-t-${String(index).padStart(2, "0")}`;
    f.addReactor(uid);
    reactions[uid] = HEART;
  }
  const target = await f.message("text", { reactions });
  const meter = instrument(f.db);
  assert.equal((await f.list(target)).likers.length, 20);
  assert.equal(meter.reads(), SERVER_MESSAGE_REACTORS_READ_BUDGETS.typical);

  const heavy = await world();
  const many = {};
  for (let index = 0; index < 70; index += 1) {
    const uid = `lr-w-${String(index).padStart(2, "0")}`;
    heavy.addReactor(uid, { user: { profileVisibility: "friends" }, friends: "forward" });
    many[uid] = FIRE;
  }
  const restricted = await heavy.message("restricted", { senderKey: "owner", reactions: many });
  const heavyMeter = instrument(heavy.db);
  const page = await heavy.list(restricted);
  assert.deepEqual(page.likers, []);
  assert.equal(page.hasMore, true);
  // First page on a restricted channel: everything but the cursor read.
  assert.equal(heavyMeter.reads(), SERVER_MESSAGE_REACTORS_READ_BUDGETS.worst - 1);
});

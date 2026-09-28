// listReelLikersV1 (ADR-230): "See who liked" for a Yeel and for one of its
// comments, through the real Reel service over InMemoryFirestore. The parent
// follows the Yeel CONTENT rule (no profile-visibility check: a
// private-profile author's Yeel is listable), while the likers follow the one
// liker predicate (a private-profile liker is hidden).
const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  DEFAULT_LIMITS,
  REEL_LIKERS_READ_BUDGETS,
  createReelService,
} = require("../reels/service");
const { REEL_CALLABLE_METHODS, REEL_WARM_CALLABLES } = require("../reels/index");
const { REEL_COMMENT_SCHEMA_VERSION } = require("../reels/engagement");
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

const NOW_MS = 1_830_000_000_000;
const VIEWER = "rl-viewer";
const AUTHOR = "rl-author";
const COMMENTER = "rl-commenter";
const REEL_ID = "rl_reel_1";
const COMMENT = "rl-comment-1";
const UNAVAILABLE = "This content is unavailable.";

function reelDocument(overrides = {}) {
  return {
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId: AUTHOR,
    authorName: `Creator ${AUTHOR}`,
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "123",
      durationMs: 0,
      storagePath: `reels/${AUTHOR}/${REEL_ID}/media.jpg`,
    },
    backingAudio: null,
    composition: {
      caption: "A real Reel",
      crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
      filter: "original",
      trimStartMs: 0,
      trimEndMs: 0,
      textOverlays: [],
      linkOverlays: [],
      originalAudioVolume: 0,
      backingAudioVolume: 0,
      audioTrimStartMs: 0,
      audioRightsAttested: false,
      audioAttribution: "",
    },
    sortKey: `${String(NOW_MS).padStart(13, "0")}_${REEL_ID}`,
    publishedAt: new Date(NOW_MS - 3_600_000),
    updatedAt: new Date(NOW_MS - 3_600_000),
    ...overrides,
  };
}

const HOUR_MS = 3_600_000;

// `ageMs`: how long before NOW the Yeel was created and published. A timed
// Yeel is valid only for 24..720 hours (MIN_REEL_AVAILABILITY_HOURS); the
// Reel document must carry the same publishedAt (reelAt()).
function availabilityDocument(hours = "permanent", ageMs = HOUR_MS) {
  const at = new Date(NOW_MS - ageMs);
  return {
    schemaVersion: 2,
    status: "published",
    ownerId: AUTHOR,
    reelId: REEL_ID,
    availabilityHours: hours,
    createdAt: at,
    publishedAt: at,
    ...(hours === "permanent"
      ? {}
      : { expiresAt: new Date(NOW_MS - ageMs + hours * HOUR_MS) }),
    updatedAt: at,
  };
}

function reelAt(ageMs) {
  return { publishedAt: new Date(NOW_MS - ageMs), updatedAt: new Date(NOW_MS - ageMs) };
}

function textComment(overrides = {}) {
  return {
    schemaVersion: REEL_COMMENT_SCHEMA_VERSION,
    reelId: REEL_ID,
    authorId: COMMENTER,
    authorName: "Commenter",
    durationSeconds: null,
    text: "Great Yeel",
    type: "text",
    createdAt: new Date(NOW_MS - 1_800_000),
    ...overrides,
  };
}

function reelLike(db, uid, createdAtMs) {
  db.seed(`reels/${REEL_ID}/likes/${uid}`, {
    schemaVersion: 1,
    userId: uid,
    reelId: REEL_ID,
    createdAt: new Date(createdAtMs),
  });
}

function commentLike(db, uid, createdAtMs, commentId = COMMENT) {
  const commentKey = `r:${REEL_ID}:${commentId}`;
  db.seed(`commentLikes/${commentKey}:${uid}`, {
    schemaVersion: 1,
    parentKind: "reel",
    parentId: REEL_ID,
    commentId,
    commentKey,
    userId: uid,
    createdAt: new Date(createdAtMs),
  });
}

function world({
  grant,
  config,
  reel = {},
  availability = "permanent",
  availabilityAgeMs = HOUR_MS,
  comment = {},
} = {}) {
  const db = new InMemoryFirestore();
  seedViewer(db, VIEWER, NOW_MS, {
    ...(grant === undefined ? {} : { grant }),
    ...(config === undefined ? {} : { config }),
  });
  seedPerson(db, AUTHOR, { nowMs: NOW_MS, viewerId: VIEWER });
  seedPerson(db, COMMENTER, { nowMs: NOW_MS, viewerId: VIEWER });
  if (reel !== null) db.seed(`reels/${REEL_ID}`, reelDocument(reel));
  if (availability !== null) {
    db.seed(
      `reelAvailability/${REEL_ID}`,
      availabilityDocument(availability, availabilityAgeMs),
    );
  }
  if (comment !== null) db.seed(`reels/${REEL_ID}/comments/${COMMENT}`, textComment(comment));
  return db;
}

function service(db, { clock = () => NOW_MS, warnings = [] } = {}) {
  return createReelService({
    db,
    FieldPath: { documentId: () => "__name__" },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage: {
      getMetadata: async () => ({}),
      readHeader: async () => Buffer.alloc(0),
      revokeDownloadTokens: async () => {},
      getSignedReadUrl: async () => "",
      deleteObject: async () => {},
    },
    clock,
    limits: DEFAULT_LIMITS,
    log: {
      warn: (message, data) => warnings.push([message, data]),
      info() {},
      error() {},
      debug() {},
    },
  });
}

function call(reels, data, uid = VIEWER) {
  return reels.listReelLikersV1({ auth: { uid, token: { email_verified: false } }, data });
}

function seedPublicLikers(db, count, { prefix = "rl-liker", comment = false } = {}) {
  const ids = [];
  for (let index = 0; index < count; index += 1) {
    const uid = `${prefix}-${String(index).padStart(2, "0")}`;
    seedPerson(db, uid, { nowMs: NOW_MS, viewerId: VIEWER });
    const at = NOW_MS - 60_000 - index * 1_000;
    if (comment) commentLike(db, uid, at);
    else reelLike(db, uid, at);
    ids.push(uid);
  }
  return ids;
}

test("registered as a Reel callable and kept out of the warm set", () => {
  assert.equal(REEL_CALLABLE_METHODS.listReelLikersV1, "listReelLikersV1");
  assert.equal(REEL_WARM_CALLABLES.has("listReelLikersV1"), false);
  assert.equal(REEL_WARM_CALLABLES.size, 0);
});

test("read budgets are pinned from the final code", () => {
  assert.deepEqual(REEL_LIKERS_READ_BUDGETS, {
    reelTypical: 135,
    reelWorst: 498,
    commentTypical: 140,
    commentWorst: 503,
  });
});

test("order: auth, exact input, activation, budgets, gate", async () => {
  const db = world();
  const meter = instrument(db);
  await rejectsWith(service(db).listReelLikersV1({ data: { reelId: REEL_ID } }), "unauthenticated");
  await rejectsWith(call(service(db), { reelId: REEL_ID, limit: 50 }), "invalid-argument");
  await rejectsWith(call(service(db), { reelId: REEL_ID, emoji: "❤️" }), "invalid-argument");
  assert.equal(meter.reads(), 0);

  const off = world({ config: activation(NOW_MS, { enabled: false }) });
  const offMeter = instrument(off);
  await rejectsWith(call(service(off), { reelId: REEL_ID }), "failed-precondition", {
    reason: "likersNotEnabled",
    message: "See who liked is not available yet.",
  });
  assert.equal(offMeter.reads(), 1);
  assert.equal(rateState(off, "likers.list"), undefined);

  const locked = world({ grant: null });
  const lockedMeter = instrument(locked);
  await rejectsWith(call(service(locked), { reelId: REEL_ID }), "failed-precondition", {
    reason: "likersAccessRequired",
  });
  assert.equal(lockedMeter.reads(), 8, "no Reel, like or liker document was read");
});

test("private-profile author is listable; private-profile liker is hidden", async () => {
  const db = world();
  seedPerson(db, AUTHOR, {
    nowMs: NOW_MS,
    viewerId: VIEWER,
    user: { profileVisibility: "private" },
  });
  const visible = seedPublicLikers(db, 3);
  let offset = 0;
  for (const [label, options] of Object.entries(hiddenVariants(NOW_MS))) {
    const uid = `rl-hidden-${label}`;
    seedPerson(db, uid, { nowMs: NOW_MS, viewerId: VIEWER, ...options });
    reelLike(db, uid, NOW_MS - 60_500 - offset * 100);
    offset += 1;
  }
  // Malformed edge: extra key.
  seedPerson(db, "rl-malformed", { nowMs: NOW_MS, viewerId: VIEWER });
  db.seed(`reels/${REEL_ID}/likes/rl-malformed`, {
    schemaVersion: 1,
    userId: "rl-malformed",
    reelId: REEL_ID,
    createdAt: new Date(NOW_MS - 1_000),
    extra: true,
  });
  const meter = instrument(db);
  const page = await call(service(db), { reelId: REEL_ID });
  assertExactPage(page);
  assert.deepEqual(page.likers.map((row) => row.userId), visible);
  assert.equal(page.likers[0].displayName, `Name ${visible[0]}`);
  assert.equal(page.likers[0].reaction, null);
  assert.equal(page.hasMore, false);
  // Only the likers budgets; the Yeel `view` budget is untouched.
  assert.equal(rateState(db, "likers.list").count, 1);
  assert.equal(rateState(db, "reel.view"), undefined);
  assert.equal(meter.transactionCount(), 1);
  for (const path of meter.transactionReads) assert.match(path, /^privateRateLimits\//u);
});

test("the Yeel content rule guards the parent with one uniform refusal", async () => {
  const cases = {
    missingReel: { reel: null },
    // A valid 24-hour Yeel published 25 hours ago: expired at request time.
    expired: {
      availability: 24,
      availabilityAgeMs: 25 * HOUR_MS,
      reel: reelAt(25 * HOUR_MS),
    },
    // A timed Yeel below the 24-hour minimum is malformed, not expired.
    malformedAvailability: { availability: 1 },
    hidden: { reel: { moderationStatus: "hidden" } },
    deleted: { reel: { status: "deleted" } },
    malformed: { reel: { extra: 1 } },
    authorBlockedViewer: { author: { personBlocks: true } },
    viewerBlockedAuthor: { author: { viewerBlocks: true } },
    authorMuted: { author: { mute: { type: "communicationMute", expiresAt: null } } },
    authorSuspended: { author: { user: { banned: true } } },
  };
  for (const [label, {
    reel = {},
    availability = "permanent",
    availabilityAgeMs = HOUR_MS,
    author = null,
  }] of Object.entries(cases)) {
    const db = world({ reel, availability, availabilityAgeMs });
    if (author !== null) seedPerson(db, AUTHOR, { nowMs: NOW_MS, viewerId: VIEWER, ...author });
    seedPublicLikers(db, 2);
    await rejectsWith(call(service(db), { reelId: REEL_ID }), "permission-denied", {
      message: UNAVAILABLE,
    }).catch((error) => {
      throw new Error(`${label}: ${error.message}`);
    });
  }
  // A legacy Reel without an availability document is permanent and listable,
  // exactly as getReelViewV2 shows it.
  const legacy = world({ availability: null });
  seedPublicLikers(legacy, 2);
  assert.equal((await call(service(legacy), { reelId: REEL_ID })).likers.length, 2);
});

test("a Yeel that expires during the scan is refused at response time", async () => {
  // A valid 24-hour Yeel published 23 hours ago: the deadline is NOW + 1h.
  // The request clock reads NOW (listable); every later read is NOW + 2h, so
  // only the response-time re-check can refuse it.
  const age = 23 * HOUR_MS;
  const fixture = () => {
    const db = world({ availability: 24, availabilityAgeMs: age, reel: reelAt(age) });
    seedPublicLikers(db, 3);
    return db;
  };
  // Control: with a clock that stays at NOW the same Yeel is listed, so the
  // fixture is a valid, unexpired Yeel.
  assert.equal((await call(service(fixture()), { reelId: REEL_ID })).likers.length, 3);
  let calls = 0;
  const reels = service(fixture(), {
    clock: () => (calls++ === 0 ? NOW_MS : NOW_MS + 2 * HOUR_MS),
  });
  await rejectsWith(call(reels, { reelId: REEL_ID }), "permission-denied", {
    message: UNAVAILABLE,
  });
  assert.ok(calls >= 2, `the response-time clock was read (clock reads: ${calls})`);
});

test("paging: 25 visible among 30, cursor after the last consumed, replay stable", async () => {
  const db = world();
  const hiddenAt = new Set([0, 5, 11, 12, 29]);
  const visible = [];
  for (let index = 0; index < 30; index += 1) {
    const uid = `rl-p-${String(index).padStart(2, "0")}`;
    seedPerson(db, uid, {
      nowMs: NOW_MS,
      viewerId: VIEWER,
      ...(hiddenAt.has(index) ? { user: { profileVisibility: "private" } } : {}),
    });
    reelLike(db, uid, NOW_MS - 60_000 - index * 1_000);
    if (!hiddenAt.has(index)) visible.push(uid);
  }
  const reels = service(db);
  const first = await call(reels, { reelId: REEL_ID });
  assert.deepEqual(first.likers.map((row) => row.userId), visible.slice(0, 20));
  assert.equal(db.data(`likerPageCursors/${first.nextCursor}`).afterId, visible[19]);
  const second = await call(reels, { reelId: REEL_ID, cursor: first.nextCursor });
  assert.deepEqual(second.likers.map((row) => row.userId), visible.slice(20));
  assert.equal(second.hasMore, false);
  assert.deepEqual(await call(reels, { reelId: REEL_ID, cursor: first.nextCursor }), second);
  await rejectsWith(
    call(reels, { reelId: REEL_ID, commentId: COMMENT, cursor: first.nextCursor }),
    "invalid-argument",
    { message: "cursor is invalid." },
  );
});

test("a typical page costs exactly reelTypical; a worst page stays within reelWorst", async () => {
  const db = world();
  seedPublicLikers(db, 25);
  const meter = instrument(db);
  assert.equal((await call(service(db), { reelId: REEL_ID })).likers.length, 20);
  assert.equal(meter.reads(), REEL_LIKERS_READ_BUDGETS.reelTypical);

  const heavy = world();
  for (let index = 0; index < 70; index += 1) {
    const uid = `rl-w-${String(index).padStart(2, "0")}`;
    seedPerson(heavy, uid, {
      nowMs: NOW_MS,
      viewerId: VIEWER,
      user: { profileVisibility: "friends" },
      friends: "forward",
    });
    reelLike(heavy, uid, NOW_MS - 60_000 - index * 1_000);
  }
  const heavyMeter = instrument(heavy);
  const page = await call(service(heavy), { reelId: REEL_ID });
  assert.deepEqual(page.likers, []);
  assert.equal(page.hasMore, true);
  // First page: everything but the cursor read.
  assert.equal(heavyMeter.reads(), REEL_LIKERS_READ_BUDGETS.reelWorst - 1);
});

test("comment target: a comment lists its flat-store likes, the commenter included", async () => {
  const db = world();
  const visible = seedPublicLikers(db, 2, { prefix: "rl-c", comment: true });
  seedPerson(db, "rl-else", { nowMs: NOW_MS, viewerId: VIEWER });
  commentLike(db, "rl-else", NOW_MS - 1_000, "rl-comment-2");
  reelLike(db, "rl-else", NOW_MS - 1_000);
  const page = await call(service(db), { reelId: REEL_ID, commentId: COMMENT });
  assert.deepEqual(page.likers.map((row) => row.userId), visible);
  // The commenter may like their own comment and see themself.
  commentLike(db, VIEWER, NOW_MS - 500);
  const withSelf = await call(service(db), { reelId: REEL_ID, commentId: COMMENT });
  assert.deepEqual(withSelf.likers.map((row) => row.userId), [VIEWER, ...visible]);
});

test("comment target: missing, malformed or hidden commenter is the uniform refusal", async () => {
  const cases = {
    missing: { comment: null },
    malformed: { comment: { extra: 1 } },
    wrongReel: { comment: { reelId: "rl_other" } },
    commenterBlocked: { commenter: { viewerBlocks: true } },
    commenterMuted: { commenter: { mute: { type: "communicationMute", expiresAt: null } } },
  };
  for (const [label, { comment = {}, commenter = null }] of Object.entries(cases)) {
    const db = world({ comment });
    if (commenter !== null) {
      seedPerson(db, COMMENTER, { nowMs: NOW_MS, viewerId: VIEWER, ...commenter });
    }
    await rejectsWith(call(service(db), { reelId: REEL_ID, commentId: COMMENT }),
      "permission-denied", { message: UNAVAILABLE }).catch((error) => {
      throw new Error(`${label}: ${error.message}`);
    });
  }
  // The Yeel rule: a private-profile commenter's comment is still listable.
  const db = world();
  seedPerson(db, COMMENTER, {
    nowMs: NOW_MS,
    viewerId: VIEWER,
    user: { profileVisibility: "private" },
  });
  seedPublicLikers(db, 1, { comment: true });
  assert.equal((await call(service(db), { reelId: REEL_ID, commentId: COMMENT })).likers.length, 1);
});

test("the likers budgets are shared across families and exhaust per minute", async () => {
  const db = world();
  seedPublicLikers(db, 1);
  const warnings = [];
  const reels = service(db, { warnings });
  for (let index = 0; index < 10; index += 1) await call(reels, { reelId: REEL_ID });
  await rejectsWith(call(reels, { reelId: REEL_ID }), "resource-exhausted");
  assert.deepEqual(
    warnings.filter(([message]) => message === "likers budget exhausted"),
    [["likers budget exhausted", { scope: "likers.list" }]],
  );
});

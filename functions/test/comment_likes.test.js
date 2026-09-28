// Comment likes (ADR-230): the flat commentLikes / commentLikeCounters store,
// the two idempotent toggles (setMomentCommentLikeV1, setReelCommentLikeV1)
// through the real services over InMemoryFirestore, and the view loader the
// includeCommentLikes flag uses. The production-shaped queries (the `in`
// filters, the purge) also run on the emulator in
// comment_likes_emulator.test.js.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  COMMENT_LIKE_VIEW_READS,
  HIDDEN_COMMENT_LIKE_COUNT,
  commentLikeEdgeId,
  commentLikeKey,
  commentUnavailable,
  loadCommentLikeStates,
  purgeCommentLikes,
  requireIncludeCommentLikes,
  validateCommentLike,
  validateCommentLikeCounter,
} = require("../engagement/comment_likes");
const {
  DEFAULT_LIMITS: MOMENT_LIMITS,
  createMomentIntegrityService,
  momentStoragePath,
} = require("../moments/integrity");
const {
  DEFAULT_LIMITS: REEL_LIMITS,
  createReelService,
} = require("../reels/service");
const { REEL_CALLABLE_METHODS, REEL_WARM_CALLABLES } = require("../reels/index");
const { USER_CALLABLE_METHODS } = require("../integrity/stage_b_handlers");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");
const {
  instrument,
  rateState,
  rejectsWith,
  seedPerson,
} = require("./helpers/likers_fixture");

const NOW_MS = 1_830_000_000_000;
const VIEWER = "clk-viewer";
const AUTHOR = "clk-author";
const COMMENTER = "clk-commenter";
const MOMENT = "clk-moment-1";
const COMMENT = "clk-comment-1";
const REEL = "clk_reel_1";
const REEL_COMMENT = "b".repeat(40);
const OTHER = "clk-someone-else";
const UNAVAILABLE = "This comment is unavailable.";
const MUTE = { type: "communicationMute", expiresAt: new Date(NOW_MS + 60_000) };

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function momentDocument(overrides = {}) {
  return {
    audioUrl: null,
    authorId: AUTHOR,
    authorName: "Author",
    authorPhotoUrl: null,
    caption: "A Moment",
    commentCount: 1,
    createdAt: new Date(NOW_MS - 3_600_000),
    durationSeconds: 12,
    isDeleted: false,
    isPublished: true,
    likeCount: 0,
    mediaContentType: "audio/mp4",
    mediaGeneration: "1001",
    mediaSize: 4096,
    publishedAt: new Date(NOW_MS - 3_600_000),
    replyToMomentId: null,
    schemaVersion: 2,
    status: "published",
    storagePath: momentStoragePath(AUTHOR, MOMENT),
    updatedAt: new Date(NOW_MS - 3_600_000),
    ...overrides,
  };
}

function momentCommentDocument(overrides = {}) {
  return {
    audioUrl: null,
    authorId: COMMENTER,
    authorName: "Commenter",
    authorPhotoUrl: null,
    createdAt: new Date(NOW_MS - 1_800_000),
    durationSeconds: null,
    mediaContentType: null,
    mediaGeneration: null,
    mediaSize: null,
    schemaVersion: 2,
    storagePath: null,
    text: "Nice one",
    type: "text",
    ...overrides,
  };
}

function reelDocument(overrides = {}) {
  return {
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId: AUTHOR,
    authorName: "Creator",
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "123",
      durationMs: 0,
      storagePath: `reels/${AUTHOR}/${REEL}/media.jpg`,
    },
    backingAudio: null,
    composition: {
      caption: "",
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
    sortKey: `${String(NOW_MS).padStart(13, "0")}_${REEL}`,
    publishedAt: new Date(NOW_MS - 3_600_000),
    updatedAt: new Date(NOW_MS - 3_600_000),
    ...overrides,
  };
}

function reelAvailability(hours = "permanent") {
  return {
    schemaVersion: 2,
    status: "published",
    ownerId: AUTHOR,
    reelId: REEL,
    availabilityHours: hours,
    createdAt: new Date(NOW_MS - 3_600_000),
    publishedAt: new Date(NOW_MS - 3_600_000),
    ...(hours === "permanent"
      ? {}
      : { expiresAt: new Date(NOW_MS - 3_600_000 + hours * 3_600_000) }),
    updatedAt: new Date(NOW_MS - 3_600_000),
  };
}

function reelCommentDocument(overrides = {}) {
  return {
    authorId: COMMENTER,
    authorName: "Commenter",
    createdAt: new Date(NOW_MS - 1_800_000),
    durationSeconds: null,
    reelId: REEL,
    schemaVersion: 1,
    text: "Nice one",
    type: "text",
    ...overrides,
  };
}

// Viewer, Moment/Reel author and commenter are all public and active unless
// a test says otherwise.
function world({
  viewer = {},
  author = {},
  commenter = {},
  moment = {},
  momentComment = {},
  reel = {},
  reelComment = {},
  availability = "permanent",
} = {}) {
  const db = new InMemoryFirestore();
  seedPerson(db, VIEWER, { nowMs: NOW_MS, viewerId: VIEWER, ...viewer });
  seedPerson(db, AUTHOR, { nowMs: NOW_MS, viewerId: VIEWER, ...author });
  seedPerson(db, COMMENTER, { nowMs: NOW_MS, viewerId: VIEWER, ...commenter });
  if (moment !== null) db.seed(`voiceMoments/${MOMENT}`, momentDocument(moment));
  if (momentComment !== null) {
    db.seed(
      `voiceMoments/${MOMENT}/comments/${COMMENT}`,
      momentCommentDocument(momentComment),
    );
  }
  if (reel !== null) db.seed(`reels/${REEL}`, reelDocument(reel));
  if (availability !== null) {
    db.seed(`reelAvailability/${REEL}`, reelAvailability(availability));
  }
  if (reelComment !== null) {
    db.seed(`reels/${REEL}/comments/${REEL_COMMENT}`, reelCommentDocument(reelComment));
  }
  return db;
}

function moments(db, { limits = MOMENT_LIMITS, clock = () => NOW_MS } = {}) {
  return createMomentIntegrityService({
    db,
    FieldPath: { documentId: () => "__name__" },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage: {
      getMetadata: async () => ({}),
      getSignedReadUrl: async () => "",
      revokeDownloadTokens: async () => {},
    },
    clock,
    limits,
    logger: { warn() {}, debug() {}, info() {}, error() {} },
  });
}

function reels(db, { limits = REEL_LIMITS, clock = () => NOW_MS } = {}) {
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
    limits,
  });
}

let sequence = 0;
function requestId() {
  sequence += 1;
  return `clk-request-${String(sequence).padStart(6, "0")}`;
}

function voiceToggle(service, liked, {
  uid = VIEWER,
  id = requestId(),
  commentId = COMMENT,
  momentId = MOMENT,
  verified = true,
} = {}) {
  return service.setMomentCommentLikeV1({
    auth: { uid, token: { email_verified: verified } },
    data: { commentId, liked, momentId, requestId: id },
  });
}

function reelToggle(service, liked, {
  uid = VIEWER,
  id = requestId(),
  commentId = REEL_COMMENT,
  reelId = REEL,
} = {}) {
  return service.setReelCommentLikeV1({
    auth: { uid, token: { email_verified: true } },
    data: { commentId, liked, reelId, requestId: id },
  });
}

const VOICE_KEY = `v:${MOMENT}:${COMMENT}`;
const REEL_KEY = `r:${REEL}:${REEL_COMMENT}`;

function seedEdge(db, commentKey, parentKind, parentId, commentId, uid, overrides = {}) {
  db.seed(`commentLikes/${commentKey}:${uid}`, {
    schemaVersion: 1,
    parentKind,
    parentId,
    commentId,
    commentKey,
    userId: uid,
    createdAt: new Date(NOW_MS - 60_000),
    ...overrides,
  });
}

function seedCounter(db, commentKey, parentKind, parentId, commentId, likeCount, overrides = {}) {
  db.seed(`commentLikeCounters/${commentKey}`, {
    schemaVersion: 1,
    parentKind,
    parentId,
    commentId,
    commentKey,
    likeCount,
    updatedAt: new Date(NOW_MS - 60_000),
    ...overrides,
  });
}

function seedVoiceLike(db, uid = VIEWER, count = 1) {
  seedEdge(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, uid);
  seedCounter(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, count);
}

function seedReelLike(db, uid = VIEWER, count = 1) {
  seedEdge(db, REEL_KEY, "reel", REEL, REEL_COMMENT, uid);
  seedCounter(db, REEL_KEY, "reel", REEL, REEL_COMMENT, count);
}

function snapshot(id, data) {
  return {
    id,
    exists: data !== undefined,
    data: () => (data === undefined ? undefined : structuredClone(data)),
  };
}

// ---------------------------------------------------------------------------
// The store: keys, validators, the shared helpers
// ---------------------------------------------------------------------------

test("commentKey and edge ids are unambiguous and SAFE_ID-bound", () => {
  assert.equal(commentLikeKey("voiceMoment", "m1", "c1"), "v:m1:c1");
  assert.equal(commentLikeKey("reel", "r_1", "c-1"), "r:r_1:c-1");
  assert.equal(commentLikeEdgeId("v:m1:c1", "uid-1"), "v:m1:c1:uid-1");
  assert.throws(() => commentLikeKey("voiceMoment", "m:1", "c1"), TypeError);
  assert.throws(() => commentLikeKey("voiceMoment", "m1", "c/1"), TypeError);
  assert.throws(() => commentLikeKey("room", "m1", "c1"), TypeError);
  assert.throws(() => commentLikeEdgeId("v:m1:c1", "bad/uid"), TypeError);
});

test("the counter validator: absent is 0, exact shape only, data-loss otherwise", () => {
  const target = { parentKind: "voiceMoment", parentId: MOMENT, commentId: COMMENT };
  const canonical = {
    schemaVersion: 1,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentId: COMMENT,
    commentKey: VOICE_KEY,
    likeCount: 3,
    updatedAt: new Date(NOW_MS),
  };
  assert.equal(validateCommentLikeCounter(snapshot(VOICE_KEY, undefined), target), 0);
  assert.equal(validateCommentLikeCounter(snapshot(VOICE_KEY, canonical), target), 3);
  const broken = [
    { ...canonical, extra: true },
    { ...canonical, likeCount: -1 },
    { ...canonical, likeCount: 1.5 },
    { ...canonical, likeCount: "3" },
    { ...canonical, schemaVersion: 2 },
    { ...canonical, parentKind: "reel" },
    { ...canonical, parentId: "other" },
    { ...canonical, commentId: "other" },
    { ...canonical, commentKey: "v:other:x" },
    { ...canonical, updatedAt: "yesterday" },
    Object.fromEntries(Object.entries(canonical).filter(([key]) => key !== "updatedAt")),
  ];
  for (const data of broken) {
    assert.throws(
      () => validateCommentLikeCounter(snapshot(VOICE_KEY, data), target),
      (error) => error.code === "data-loss",
      JSON.stringify(data),
    );
  }
  // The document id must be the key itself.
  assert.throws(
    () => validateCommentLikeCounter(snapshot("v:other:c", canonical), target),
    (error) => error.code === "data-loss",
  );
});

test("the edge validator binds parent, comment, user and document id", () => {
  const target = {
    parentKind: "reel",
    parentId: REEL,
    commentId: REEL_COMMENT,
    userId: VIEWER,
  };
  const canonical = {
    schemaVersion: 1,
    parentKind: "reel",
    parentId: REEL,
    commentId: REEL_COMMENT,
    commentKey: REEL_KEY,
    userId: VIEWER,
    createdAt: new Date(NOW_MS),
  };
  const id = `${REEL_KEY}:${VIEWER}`;
  assert.equal(validateCommentLike(snapshot(id, undefined), target), false);
  assert.equal(validateCommentLike(snapshot(id, canonical), target), true);
  for (const data of [
    { ...canonical, extra: 1 },
    { ...canonical, userId: OTHER },
    { ...canonical, parentKind: "voiceMoment" },
    { ...canonical, createdAt: 5 },
  ]) {
    assert.throws(
      () => validateCommentLike(snapshot(id, data), target),
      (error) => error.code === "data-loss",
    );
  }
  assert.throws(
    () => validateCommentLike(snapshot(`${REEL_KEY}:${OTHER}`, canonical), target),
    (error) => error.code === "data-loss",
  );
});

test("the view flag is absent or the literal true, nothing else", () => {
  assert.equal(requireIncludeCommentLikes(undefined), false);
  assert.equal(requireIncludeCommentLikes(true), true);
  for (const value of [false, null, "true", 1, {}, []]) {
    assert.throws(
      () => requireIncludeCommentLikes(value),
      (error) => error.code === "invalid-argument",
    );
  }
});

test("the uniform comment refusal collapses content codes only", () => {
  for (const code of ["not-found", "failed-precondition", "permission-denied", "data-loss"]) {
    const refusal = commentUnavailable({ code });
    assert.equal(refusal.code, "permission-denied");
    assert.equal(refusal.message, UNAVAILABLE);
  }
  for (const code of ["resource-exhausted", "invalid-argument", "internal"]) {
    const error = { code };
    assert.equal(commentUnavailable(error), error);
  }
  const raw = new Error("driver");
  assert.equal(commentUnavailable(raw), raw);
});

// ---------------------------------------------------------------------------
// loadCommentLikeStates (the views' opt-in map)
// ---------------------------------------------------------------------------

test("loadCommentLikeStates answers every projected id with two queries", async () => {
  const db = new InMemoryFirestore();
  const ids = ["c1", "c2", "c3"];
  const key = (commentId) => `v:${MOMENT}:${commentId}`;
  seedCounter(db, key("c1"), "voiceMoment", MOMENT, "c1", 4);
  seedEdge(db, key("c1"), "voiceMoment", MOMENT, "c1", VIEWER);
  seedEdge(db, key("c1"), "voiceMoment", MOMENT, "c1", OTHER);
  seedCounter(db, key("c2"), "voiceMoment", MOMENT, "c2", 2);
  seedEdge(db, key("c2"), "voiceMoment", MOMENT, "c2", OTHER);
  // A comment that is not projected (withheld) has likes too: never listed.
  seedCounter(db, key("hidden"), "voiceMoment", MOMENT, "hidden", 9);
  seedEdge(db, key("hidden"), "voiceMoment", MOMENT, "hidden", VIEWER);
  // Another parent's comment with the same comment id is a different key.
  seedCounter(db, `r:${MOMENT}:c3`, "reel", MOMENT, "c3", 7);
  seedEdge(db, `r:${MOMENT}:c3`, "reel", MOMENT, "c3", VIEWER);

  const before = { ...db.metrics };
  const states = await loadCommentLikeStates({
    db,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentIds: ids,
    viewerId: VIEWER,
  });
  assert.deepEqual(states, {
    c1: { likeCount: 4, callerLiked: true },
    c2: { likeCount: 2, callerLiked: false },
    c3: { likeCount: 0, callerLiked: false },
  });
  assert.deepEqual(Object.keys(states), ids);
  assert.equal(db.metrics.queryCalls - before.queryCalls, COMMENT_LIKE_VIEW_READS);
  assert.equal(COMMENT_LIKE_VIEW_READS, 2);
});

test("loadCommentLikeStates skips malformed counters and edges, never fails", async () => {
  const db = new InMemoryFirestore();
  const key = `v:${MOMENT}:c1`;
  seedCounter(db, key, "voiceMoment", MOMENT, "c1", -3);
  seedEdge(db, key, "voiceMoment", MOMENT, "c1", VIEWER, { extra: true });
  const states = await loadCommentLikeStates({
    db,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentIds: ["c1"],
    viewerId: VIEWER,
  });
  assert.deepEqual(states, { c1: { likeCount: 0, callerLiked: false } });
});

test("loadCommentLikeStates with no projected comments reads nothing", async () => {
  const db = new InMemoryFirestore();
  const states = await loadCommentLikeStates({
    db,
    parentKind: "reel",
    parentId: REEL,
    commentIds: [],
    viewerId: VIEWER,
  });
  assert.deepEqual(states, {});
  assert.equal(db.metrics.queryCalls, 0);
  // An id no toggle accepts is answered as zero without a query.
  const legacy = await loadCommentLikeStates({
    db,
    parentKind: "reel",
    parentId: REEL,
    commentIds: ["legacy id with spaces"],
    viewerId: VIEWER,
  });
  assert.deepEqual(legacy, {
    "legacy id with spaces": { likeCount: 0, callerLiked: false },
  });
  assert.equal(db.metrics.queryCalls, 0);
});

test("purgeCommentLikes deletes every edge in batches, then the counter, idempotently", async () => {
  const db = new InMemoryFirestore();
  for (let index = 0; index < 850; index += 1) {
    seedEdge(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, `clk-u-${index}`);
  }
  seedCounter(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, 850);
  const otherKey = `v:${MOMENT}:other`;
  seedEdge(db, otherKey, "voiceMoment", MOMENT, "other", VIEWER);
  seedCounter(db, otherKey, "voiceMoment", MOMENT, "other", 1);
  let batches = 0;
  const batch = db.batch.bind(db);
  db.batch = () => {
    batches += 1;
    return batch();
  };
  assert.deepEqual(await purgeCommentLikes(db, VOICE_KEY), { deleted: 850 });
  assert.equal(batches, 3);
  assert.deepEqual(db.paths(`commentLikes/${VOICE_KEY}:`), []);
  assert.equal(db.data(`commentLikeCounters/${VOICE_KEY}`), undefined);
  // Another comment's likes are untouched.
  assert.equal(db.paths(`commentLikes/${otherKey}:`).length, 1);
  assert.equal(db.data(`commentLikeCounters/${otherKey}`).likeCount, 1);
  // A redelivery finds nothing.
  assert.deepEqual(await purgeCommentLikes(db, VOICE_KEY), { deleted: 0 });
  assert.equal(batches, 3);
});

// ---------------------------------------------------------------------------
// setMomentCommentLikeV1
// ---------------------------------------------------------------------------

test("setMomentCommentLikeV1 is a Stage B callable on the moments service", () => {
  assert.deepEqual(USER_CALLABLE_METHODS.setMomentCommentLikeV1, [
    "moments",
    "setMomentCommentLikeV1",
  ]);
  assert.equal(typeof moments(new InMemoryFirestore()).setMomentCommentLikeV1, "function");
});

test("Voice: like and unlike move the edge and counter together", async () => {
  const db = world();
  const service = moments(db);
  const commentPath = `voiceMoments/${MOMENT}/comments/${COMMENT}`;
  const commentBefore = db.data(commentPath);
  const momentBefore = db.data(`voiceMoments/${MOMENT}`);

  const liked = await voiceToggle(service, true);
  assert.deepEqual(liked, {
    momentId: MOMENT,
    commentId: COMMENT,
    liked: true,
    changed: true,
    likeCount: 1,
  });
  assert.deepEqual(Object.keys(liked).sort(), ["changed", "commentId", "likeCount", "liked", "momentId"]);
  assert.deepEqual(db.data(`commentLikes/${VOICE_KEY}:${VIEWER}`), {
    schemaVersion: 1,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentId: COMMENT,
    commentKey: VOICE_KEY,
    userId: VIEWER,
    createdAt: new Date(NOW_MS),
  });
  assert.deepEqual(db.data(`commentLikeCounters/${VOICE_KEY}`), {
    schemaVersion: 1,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentId: COMMENT,
    commentKey: VOICE_KEY,
    likeCount: 1,
    updatedAt: new Date(NOW_MS),
  });

  // A second person, and liking your own comment, both count.
  assert.equal((await voiceToggle(service, true, { uid: COMMENTER })).likeCount, 2);
  // Same state again: no change, count unchanged.
  const again = await voiceToggle(service, true);
  assert.equal(again.changed, false);
  assert.equal(again.likeCount, 2);

  const unliked = await voiceToggle(service, false);
  assert.deepEqual(unliked, {
    momentId: MOMENT,
    commentId: COMMENT,
    liked: false,
    changed: true,
    likeCount: 1,
  });
  assert.equal(db.data(`commentLikes/${VOICE_KEY}:${VIEWER}`), undefined);
  assert.equal(db.data(`commentLikeCounters/${VOICE_KEY}`).likeCount, 1);

  // Comment and Moment documents are byte-identical: no likeCount on them.
  assert.deepEqual(db.data(commentPath), commentBefore);
  assert.deepEqual(db.data(`voiceMoments/${MOMENT}`), momentBefore);
});

test("Voice: an absent counter is 0 and an unlike with no edge changes nothing", async () => {
  const db = world();
  const result = await voiceToggle(moments(db), false);
  assert.deepEqual(result, {
    momentId: MOMENT,
    commentId: COMMENT,
    liked: false,
    changed: false,
    likeCount: 0,
  });
  assert.equal(db.data(`commentLikeCounters/${VOICE_KEY}`), undefined);
});

test("Voice: a ledger replay returns the first result without a second write", async () => {
  const db = world();
  const service = moments(db);
  const id = requestId();
  const first = await voiceToggle(service, true, { id });
  await voiceToggle(service, true, { uid: COMMENTER });
  const replay = await voiceToggle(service, true, { id });
  assert.deepEqual(replay, first);
  assert.equal(db.data(`commentLikeCounters/${VOICE_KEY}`).likeCount, 2);
  // The same requestId for the opposite intent is refused.
  await rejectsWith(voiceToggle(service, false, { id }), "already-exists");
});

test("Voice: store corruption fails closed with data-loss", async () => {
  const cases = {
    edgeWithoutCounter: (db) => seedEdge(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, VIEWER),
    counterZeroBesideEdge: (db) => seedVoiceLike(db, VIEWER, 0),
    malformedEdge: (db) => {
      seedEdge(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, VIEWER, { extra: 1 });
      seedCounter(db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, 1);
    },
    malformedCounter: (db) => seedCounter(
      db, VOICE_KEY, "voiceMoment", MOMENT, COMMENT, 1, { likeCount: "1" },
    ),
  };
  for (const [name, corrupt] of Object.entries(cases)) {
    for (const liked of [true, false]) {
      const db = world();
      corrupt(db);
      await assert.rejects(
        voiceToggle(moments(db), liked),
        (error) => error.code === "data-loss",
        `${name} liked=${liked}`,
      );
    }
  }
});

test("Voice: a hidden comment or an unviewable parent cannot be liked (one refusal)", async () => {
  const hidden = {
    missingMoment: { moment: null },
    missingComment: { momentComment: null },
    expiredMoment: { moment: { expiresAt: new Date(NOW_MS - 1) } },
    malformedComment: { momentComment: { extra: true } },
    authorBlocksViewer: { author: { personBlocks: true } },
    viewerBlocksAuthor: { author: { viewerBlocks: true } },
    privateAuthor: { author: { user: { profileVisibility: "private" } } },
    commenterBlocksViewer: { commenter: { personBlocks: true } },
    privateCommenter: { commenter: { user: { profileVisibility: "private" } } },
    friendsOnlyStrangerCommenter: {
      commenter: { user: { profileVisibility: "friends" }, friends: "forward" },
    },
    mutedCommenter: { commenter: { mute: MUTE } },
    bannedCommenter: { commenter: { user: { banned: true } } },
  };
  for (const [name, options] of Object.entries(hidden)) {
    for (const liked of [true, false]) {
      const db = world(options);
      await rejectsWith(voiceToggle(moments(db), liked), "permission-denied", {
        message: UNAVAILABLE,
      }).catch((error) => {
        throw new Error(`${name} liked=${liked}: ${error.message}`);
      });
      assert.deepEqual(db.paths("commentLikes/"), [], name);
      assert.deepEqual(db.paths("commentLikeCounters/"), [], name);
    }
  }
  // A friends-only commenter with both guards is visible, so likeable.
  const friends = world({
    commenter: { user: { profileVisibility: "friends" }, friends: "both" },
  });
  assert.equal((await voiceToggle(moments(friends), true)).likeCount, 1);
});

test("Voice: an existing like can always be removed after a block, privacy change or mute", async () => {
  // Every row but viewerMuted is an audience refusal: the unlike still runs
  // (the stored counter drops to 2) but the answer carries the stable hidden
  // count, not the fresh one. The caller's own mute is not an audience
  // refusal, so that row answers the real count.
  assert.equal(HIDDEN_COMMENT_LIKE_COUNT, 0);
  const later = {
    commenterBlocksViewer: { commenter: { personBlocks: true } },
    viewerBlocksCommenter: { commenter: { viewerBlocks: true } },
    commenterFriendsOnly: { commenter: { user: { profileVisibility: "friends" } } },
    commenterPrivate: { commenter: { user: { profileVisibility: "private" } } },
    commenterMuted: { commenter: { mute: MUTE } },
    authorBlocksViewer: { author: { personBlocks: true } },
    authorPrivate: { author: { user: { profileVisibility: "private" } } },
    viewerMuted: { viewer: { mute: MUTE } },
  };
  for (const [name, options] of Object.entries(later)) {
    const db = world(options);
    seedVoiceLike(db, VIEWER, 3);
    const result = await voiceToggle(moments(db), false);
    assert.deepEqual(result, {
      momentId: MOMENT,
      commentId: COMMENT,
      liked: false,
      changed: true,
      likeCount: name === "viewerMuted" ? 2 : HIDDEN_COMMENT_LIKE_COUNT,
    }, name);
    assert.equal(db.data(`commentLikes/${VOICE_KEY}:${VIEWER}`), undefined, name);
    assert.equal(db.data(`commentLikeCounters/${VOICE_KEY}`).likeCount, 2, name);
    // Re-liking is an ordinary like again, so the audience applies.
    if (name !== "viewerMuted") {
      await rejectsWith(voiceToggle(moments(db), true), "permission-denied", {
        message: UNAVAILABLE,
      });
    }
  }
});

test("Voice: the caller's own account state keeps its own errors", async () => {
  const muted = world({ viewer: { mute: MUTE } });
  await rejectsWith(voiceToggle(moments(muted), true), "permission-denied", {
    message: "Your account cannot communicate right now.",
  });
  const banned = world({ viewer: { user: { banned: true } } });
  seedVoiceLike(banned);
  await rejectsWith(voiceToggle(moments(banned), false), "permission-denied", {
    message: "Your account is not active.",
  });
  await rejectsWith(
    voiceToggle(moments(world()), true, { verified: false }),
    "failed-precondition",
  );
  await rejectsWith(
    moments(world()).setMomentCommentLikeV1({ data: {} }),
    "unauthenticated",
  );
});

test("Voice: exact input", async () => {
  const service = moments(world());
  const auth = { uid: VIEWER, token: { email_verified: true } };
  const valid = { commentId: COMMENT, liked: true, momentId: MOMENT, requestId: requestId() };
  for (const data of [
    { ...valid, extra: 1 },
    { commentId: COMMENT, liked: true, momentId: MOMENT },
    { ...valid, liked: "true" },
    { ...valid, commentId: "bad/id" },
    { ...valid, momentId: "" },
    { ...valid, requestId: "x" },
  ]) {
    await rejectsWith(service.setMomentCommentLikeV1({ auth, data }), "invalid-argument");
  }
});

test("Voice: comment likes share the Moment `like` budget", async () => {
  const db = world();
  const service = moments(db, {
    limits: { ...MOMENT_LIMITS, like: { maxEvents: 2, windowMs: 60_000 } },
  });
  await service.setMomentLike({
    auth: { uid: VIEWER, token: { email_verified: true } },
    data: { liked: true, momentId: MOMENT, requestId: requestId() },
  });
  await voiceToggle(service, true);
  assert.ok(rateState(db, "moment.like", VIEWER));
  await rejectsWith(voiceToggle(service, false), "resource-exhausted");
  // A refused attempt still consumed nothing else and wrote no edge change.
  assert.ok(db.data(`commentLikes/${VOICE_KEY}:${VIEWER}`));
});

test("Voice: an unlike with an existing edge evaluates the audience only to mask the count", async () => {
  const db = world();
  seedVoiceLike(db, VIEWER, 4);
  const meter = instrument(db);
  const audience = () => meter.transactionReads.filter((path) =>
    path.startsWith(`users/${AUTHOR}`) ||
    path.startsWith(`users/${COMMENTER}`) ||
    path.startsWith("publicProfiles/") ||
    path.startsWith("friendshipGuards/"));
  // A visible comment: the unlike reads both authors' audience context and
  // answers the fresh count.
  assert.equal((await voiceToggle(moments(db), false)).likeCount, 3);
  assert.ok(audience().includes(`users/${AUTHOR}`));
  assert.ok(audience().includes(`users/${COMMENTER}`));
  // A hidden comment: the same unlike still succeeds and decrements, but the
  // answer is the stable hidden count, so a refused viewer does not learn
  // the fresh count (ADR-230).
  const hidden = world({ commenter: { personBlocks: true } });
  seedVoiceLike(hidden, VIEWER, 4);
  const id = requestId();
  const result = await voiceToggle(moments(hidden), false, { id });
  assert.equal(result.likeCount, HIDDEN_COMMENT_LIKE_COUNT);
  assert.equal(hidden.data(`commentLikeCounters/${VOICE_KEY}`).likeCount, 3);
  // The ledger replays the masked answer, never the fresh count.
  assert.deepEqual(await voiceToggle(moments(hidden), false, { id }), result);
});

// ---------------------------------------------------------------------------
// setReelCommentLikeV1
// ---------------------------------------------------------------------------

test("setReelCommentLikeV1 is a cold Reel callable implemented by the service", () => {
  assert.equal(REEL_CALLABLE_METHODS.setReelCommentLikeV1, "setReelCommentLikeV1");
  assert.equal(REEL_WARM_CALLABLES.has("setReelCommentLikeV1"), false);
  assert.equal(typeof reels(new InMemoryFirestore()).setReelCommentLikeV1, "function");
});

test("Yeel: like and unlike move the edge and counter together", async () => {
  const db = world();
  const service = reels(db);
  const commentPath = `reels/${REEL}/comments/${REEL_COMMENT}`;
  const commentBefore = db.data(commentPath);
  const reelBefore = db.data(`reels/${REEL}`);
  const liked = await reelToggle(service, true);
  assert.deepEqual(liked, {
    reelId: REEL,
    commentId: REEL_COMMENT,
    liked: true,
    changed: true,
    likeCount: 1,
  });
  assert.deepEqual(db.data(`commentLikes/${REEL_KEY}:${VIEWER}`), {
    schemaVersion: 1,
    parentKind: "reel",
    parentId: REEL,
    commentId: REEL_COMMENT,
    commentKey: REEL_KEY,
    userId: VIEWER,
    createdAt: new Date(NOW_MS),
  });
  assert.equal(db.data(`commentLikeCounters/${REEL_KEY}`).likeCount, 1);
  assert.equal((await reelToggle(service, true, { uid: AUTHOR })).likeCount, 2);
  assert.equal((await reelToggle(service, true)).changed, false);
  assert.deepEqual(await reelToggle(service, false), {
    reelId: REEL,
    commentId: REEL_COMMENT,
    liked: false,
    changed: true,
    likeCount: 1,
  });
  assert.equal(db.data(`commentLikes/${REEL_KEY}:${VIEWER}`), undefined);
  assert.deepEqual(db.data(commentPath), commentBefore);
  assert.deepEqual(db.data(`reels/${REEL}`), reelBefore);
});

test("Yeel: replay, absent counter and corruption", async () => {
  const db = world();
  const service = reels(db);
  assert.equal((await reelToggle(service, false)).likeCount, 0);
  const id = requestId();
  const first = await reelToggle(service, true, { id });
  assert.deepEqual(await reelToggle(service, true, { id }), first);
  assert.equal(db.data(`commentLikeCounters/${REEL_KEY}`).likeCount, 1);

  const orphan = world();
  seedEdge(orphan, REEL_KEY, "reel", REEL, REEL_COMMENT, VIEWER);
  await rejectsWith(reelToggle(reels(orphan), false), "data-loss");
  const zero = world();
  seedReelLike(zero, VIEWER, 0);
  await rejectsWith(reelToggle(reels(zero), true), "data-loss");
});

test("Yeel: the content rule decides who may like (a private commenter is likeable)", async () => {
  // The Yeel content rule has no profile-visibility check: a comment the view
  // shows is likeable.
  const privateCommenter = world({ commenter: { user: { profileVisibility: "private" } } });
  assert.equal((await reelToggle(reels(privateCommenter), true)).likeCount, 1);

  const hidden = {
    missingReel: { reel: null },
    missingComment: { reelComment: null },
    expiredReel: { availability: 1 },
    hiddenReel: { reel: { moderationStatus: "hidden" } },
    malformedComment: { reelComment: { extra: true } },
    authorBlocksViewer: { author: { personBlocks: true } },
    commenterBlocksViewer: { commenter: { personBlocks: true } },
    viewerBlocksCommenter: { commenter: { viewerBlocks: true } },
    mutedCommenter: { commenter: { mute: MUTE } },
    bannedCommenter: { commenter: { user: { banned: true } } },
  };
  for (const [name, options] of Object.entries(hidden)) {
    for (const liked of [true, false]) {
      const db = world(options);
      await rejectsWith(reelToggle(reels(db), liked), "permission-denied", {
        message: UNAVAILABLE,
      }).catch((error) => {
        throw new Error(`${name} liked=${liked}: ${error.message}`);
      });
      assert.deepEqual(db.paths("commentLikes/"), [], name);
    }
  }
});

test("Yeel: an existing like can always be removed after a block or mute", async () => {
  for (const [name, options] of Object.entries({
    commenterBlocksViewer: { commenter: { personBlocks: true } },
    commenterMuted: { commenter: { mute: MUTE } },
    authorBlocksViewer: { author: { personBlocks: true } },
    viewerMuted: { viewer: { mute: MUTE } },
  })) {
    const db = world(options);
    seedReelLike(db, VIEWER, 2);
    const result = await reelToggle(reels(db), false);
    assert.equal(result.changed, true, name);
    // The audience rows answer the stable hidden count; the caller's own
    // mute answers the real one. The stored counter is always decremented.
    assert.equal(
      result.likeCount,
      name === "viewerMuted" ? 1 : HIDDEN_COMMENT_LIKE_COUNT,
      name,
    );
    assert.equal(db.data(`commentLikes/${REEL_KEY}:${VIEWER}`), undefined, name);
    assert.equal(db.data(`commentLikeCounters/${REEL_KEY}`).likeCount, 1, name);
  }
  const muted = world({ viewer: { mute: MUTE } });
  await rejectsWith(reelToggle(reels(muted), true), "permission-denied", {
    message: "Your account cannot communicate right now.",
  });
});

test("Yeel: voice comments are likeable and the `like` budget is shared", async () => {
  const voiceId = "c".repeat(40);
  const db = world();
  db.seed(`reels/${REEL}/comments/${voiceId}`, reelCommentDocument({
    type: "voice",
    text: "",
    durationSeconds: 5,
    storagePath: `reel_voice_comments/${COMMENTER}/${REEL}/${voiceId}.m4a`,
    mediaGeneration: "77",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
  }));
  const service = reels(db, {
    limits: { ...REEL_LIMITS, like: { maxEvents: 2, windowMs: 60_000 } },
  });
  assert.equal((await reelToggle(service, true, { commentId: voiceId })).likeCount, 1);
  await service.setReelLike({
    auth: { uid: VIEWER, token: { email_verified: true } },
    data: { liked: true, reelId: REEL, requestId: requestId() },
  });
  assert.ok(rateState(db, "reel.like", VIEWER));
  await rejectsWith(reelToggle(service, true), "resource-exhausted");
});

test("Yeel: exact input", async () => {
  const service = reels(world());
  const auth = { uid: VIEWER, token: { email_verified: true } };
  const valid = { commentId: REEL_COMMENT, liked: true, reelId: REEL, requestId: requestId() };
  for (const data of [
    { ...valid, momentId: MOMENT },
    { commentId: REEL_COMMENT, liked: true, reelId: REEL },
    { ...valid, liked: 1 },
    { ...valid, reelId: "a/b" },
  ]) {
    await rejectsWith(service.setReelCommentLikeV1({ auth, data }), "invalid-argument");
  }
  await rejectsWith(
    service.setReelCommentLikeV1({ auth: { uid: VIEWER, token: {} }, data: valid }),
    "failed-precondition",
  );
});

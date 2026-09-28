// listVoiceMomentLikersV1 (ADR-230): "See who liked" for a Voice Moment and
// for one of its comments, through the real integrity service over
// InMemoryFirestore. Order (auth, exact input, activation, budgets, gate,
// content), the uniform content refusal, the one liker predicate, paging,
// read cost and the no-write-lock rule.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  DEFAULT_LIMITS,
  VOICE_MOMENT_LIKERS_READ_BUDGETS,
  createMomentIntegrityService,
  momentStoragePath,
} = require("../moments/integrity");
const { USER_CALLABLE_METHODS } = require("../integrity/stage_b_handlers");
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
const VIEWER = "vml-viewer";
const AUTHOR = "vml-author";
const COMMENTER = "vml-commenter";
const MOMENT = "vml-moment-1";
const COMMENT = "vml-comment-1";
const UNAVAILABLE = "This content is unavailable.";

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

function commentDocument(overrides = {}) {
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

function momentLike(db, uid, createdAtMs, momentId = MOMENT) {
  db.seed(`voiceMoments/${momentId}/likes/${uid}`, {
    schemaVersion: 1,
    userId: uid,
    momentId,
    createdAt: new Date(createdAtMs),
  });
}

function commentLike(db, uid, createdAtMs, commentId = COMMENT) {
  const commentKey = `v:${MOMENT}:${commentId}`;
  db.seed(`commentLikes/${commentKey}:${uid}`, {
    schemaVersion: 1,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentId,
    commentKey,
    userId: uid,
    createdAt: new Date(createdAtMs),
  });
}

function world({ grant, config, moment = {}, comment = {} } = {}) {
  const db = new InMemoryFirestore();
  seedViewer(db, VIEWER, NOW_MS, {
    ...(grant === undefined ? {} : { grant }),
    ...(config === undefined ? {} : { config }),
  });
  seedPerson(db, AUTHOR, { nowMs: NOW_MS, viewerId: VIEWER });
  seedPerson(db, COMMENTER, { nowMs: NOW_MS, viewerId: VIEWER });
  if (moment !== null) db.seed(`voiceMoments/${MOMENT}`, momentDocument(moment));
  if (comment !== null) {
    db.seed(`voiceMoments/${MOMENT}/comments/${COMMENT}`, commentDocument(comment));
  }
  return db;
}

function service(db, { clock = () => NOW_MS, warnings = [] } = {}) {
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
    limits: DEFAULT_LIMITS,
    logger: {
      warn: (message, data) => warnings.push([message, data]),
      debug() {},
      info() {},
      error() {},
    },
  });
}

function call(moments, data, uid = VIEWER) {
  return moments.listVoiceMomentLikersV1({
    auth: { uid, token: { email_verified: false } },
    data,
  });
}

// `count` public likers, newest first: liker-00 is the newest.
function seedPublicLikers(db, count, { prefix = "vml-liker", comment = false } = {}) {
  const ids = [];
  for (let index = 0; index < count; index += 1) {
    const uid = `${prefix}-${String(index).padStart(2, "0")}`;
    seedPerson(db, uid, { nowMs: NOW_MS, viewerId: VIEWER });
    const at = NOW_MS - 60_000 - index * 1_000;
    if (comment) commentLike(db, uid, at);
    else momentLike(db, uid, at);
    ids.push(uid);
  }
  return ids;
}

test("registered as a Stage B user callable on the moments service", () => {
  assert.deepEqual(USER_CALLABLE_METHODS.listVoiceMomentLikersV1, [
    "moments",
    "listVoiceMomentLikersV1",
  ]);
  assert.equal(typeof service(new InMemoryFirestore()).listVoiceMomentLikersV1, "function");
});

test("read budgets are pinned from the final code", () => {
  assert.deepEqual(VOICE_MOMENT_LIKERS_READ_BUDGETS, {
    momentTypical: 136,
    momentWorst: 501,
    commentTypical: 143,
    commentWorst: 510,
  });
});

test("auth and exact input come first: no read at all", async () => {
  const db = world();
  const meter = instrument(db);
  const moments = service(db);
  await rejectsWith(moments.listVoiceMomentLikersV1({ data: { momentId: MOMENT } }),
    "unauthenticated");
  for (const data of [
    { momentId: MOMENT, limit: 20 },
    { momentId: MOMENT, pageSize: 5 },
    {},
    { momentId: "bad/id" },
    { momentId: MOMENT, commentId: "" },
    { momentId: MOMENT, cursor: "short" },
    { momentId: MOMENT, cursor: 42 },
  ]) {
    await rejectsWith(call(moments, data), "invalid-argument");
  }
  assert.equal(meter.reads(), 0);
});

test("activation off answers likersNotEnabled before any budget, gate or content read", async () => {
  for (const config of [
    null,
    activation(NOW_MS, { enabled: false }),
    { ...activation(NOW_MS), listedSince: null },
    { ...activation(NOW_MS), schemaVersion: 2 },
  ]) {
    const db = world({ config });
    const meter = instrument(db);
    await rejectsWith(call(service(db), { momentId: MOMENT }), "failed-precondition", {
      reason: "likersNotEnabled",
    });
    assert.equal(meter.reads(), 1, "only appConfig/likersV1 is read");
    assert.equal(meter.transactionCount(), 0, "no budget is consumed");
    assert.equal(rateState(db, "likers.list"), undefined);
  }
  // serverMessagesEnabled:false does not switch Voice Moment lists off.
  const db = world({ config: activation(NOW_MS, { serverMessagesEnabled: false }) });
  seedPublicLikers(db, 1);
  assert.equal((await call(service(db), { momentId: MOMENT })).likers.length, 1);
});

test("the gate refuses a caller without Premium, VIP or staff preview before any content read", async () => {
  for (const grant of [
    null,
    {},
    { source: "testerProgram", expiresAt: null, revoked: "false" },
    { source: "testerProgram", expiresAt: null, revoked: false, revokedAt: new Date(NOW_MS) },
    { source: "somebody", expiresAt: null, revoked: false },
    { source: "admin", expiresAt: new Date(NOW_MS - 1), revoked: false },
  ]) {
    const db = world({ grant });
    seedPublicLikers(db, 3);
    const meter = instrument(db);
    await rejectsWith(call(service(db), { momentId: MOMENT }), "failed-precondition", {
      reason: "likersAccessRequired",
      message: "YO Voice Premium or VIP is required to see who liked.",
    });
    assert.equal(meter.reads(), 8, "activation 1 + budgets 3 + the caller's own 4");
    assert.equal(db.paths("likerPageCursors/").length, 0);
    // Budgets run before the gate, so a refused caller still spends them.
    assert.equal(rateState(db, "likers.list").count, 1);
  }
  // A forged request field is not authority.
  const db = world({ grant: null });
  await rejectsWith(
    call(service(db), { momentId: MOMENT, vip: true }),
    "invalid-argument",
  );
});

test("the caller's own suspension or mute propagates as-is, outside the uniform refusal", async () => {
  const banned = world();
  banned.seed(`users/${VIEWER}`, { role: "user", banned: true });
  await rejectsWith(call(service(banned), { momentId: MOMENT }), "permission-denied", {
    message: "Your account is not active.",
  });
  const muted = world();
  muted.seed(`restrictions/${VIEWER}`, { type: "communicationMute", expiresAt: null });
  await rejectsWith(call(service(muted), { momentId: MOMENT }), "permission-denied", {
    message: "Your account cannot communicate right now.",
  });
});

test("lists visible likers newest first with the exact shape and no write lock", async () => {
  const db = world();
  const visible = seedPublicLikers(db, 4);
  const hidden = hiddenVariants(NOW_MS);
  let offset = 0;
  for (const [label, options] of Object.entries(hidden)) {
    const uid = `vml-hidden-${label}`;
    seedPerson(db, uid, { nowMs: NOW_MS, viewerId: VIEWER, ...options });
    // Interleave hidden likers among the visible ones.
    momentLike(db, uid, NOW_MS - 60_500 - offset * 100);
    offset += 1;
  }
  // A friends-only liker with both guards is shown.
  seedPerson(db, "vml-friend", {
    nowMs: NOW_MS,
    viewerId: VIEWER,
    user: { profileVisibility: "friends" },
    friends: "both",
  });
  momentLike(db, "vml-friend", NOW_MS - 10_000);
  // The viewer always sees themself, even with Hide my likes on.
  db.seed(`users/${VIEWER}`, { role: "user", likesHidden: true });
  momentLike(db, VIEWER, NOW_MS - 5_000);
  // A malformed edge is skipped and never an identity oracle.
  db.seed(`voiceMoments/${MOMENT}/likes/vml-malformed`, {
    userId: "vml-malformed",
    momentId: MOMENT,
    createdAt: new Date(NOW_MS - 1_000),
  });
  seedPerson(db, "vml-malformed", { nowMs: NOW_MS, viewerId: VIEWER });

  const meter = instrument(db);
  const page = await call(service(db), { momentId: MOMENT });
  assertExactPage(page);
  assert.deepEqual(page.likers.map((row) => row.userId), [VIEWER, "vml-friend", ...visible]);
  assert.deepEqual(page.likers[0], {
    userId: VIEWER,
    displayName: `Name ${VIEWER}`,
    photoUrl: null,
    reaction: null,
  });
  assert.equal(page.hasMore, false);
  assert.equal(page.nextCursor, null);
  assert.equal(db.paths("likerPageCursors/").length, 0);

  // The likers budgets are the only budgets, in the one small transaction.
  assert.equal(rateState(db, "likers.list").count, 1);
  assert.equal(rateState(db, "likers.listHourly").count, 1);
  assert.equal(rateState(db, "likers.listDaily").count, 1);
  assert.equal(rateState(db, "moment.read"), undefined);
  assert.equal(rateState(db, "moment.readHourly"), undefined);
  assert.equal(meter.transactionCount(), 1);
  assert.ok(meter.transactionReads.length > 0);
  for (const path of meter.transactionReads) {
    assert.match(path, /^privateRateLimits\//u, `transaction read ${path}`);
  }
});

test("the Voice audience rule guards the parent with one uniform refusal", async () => {
  const cases = {
    missingMoment: { moment: null },
    expiredMoment: { moment: { expiresAt: new Date(NOW_MS - 1) } },
    expiredStatus: {
      moment: { status: "expired", isPublished: false, expiresAt: new Date(NOW_MS - 1) },
    },
    deletingMoment: { moment: { status: "deleting", isDeleted: true, isPublished: false } },
    draftMoment: {
      moment: {
        status: "uploading",
        isPublished: false,
        mediaContentType: null,
        mediaGeneration: null,
        mediaSize: null,
        publishedAt: null,
      },
    },
    malformedMoment: { moment: { extra: true } },
    authorBlockedViewer: { author: { personBlocks: true } },
    viewerBlockedAuthor: { author: { viewerBlocks: true } },
    privateAuthor: { author: { user: { profileVisibility: "private" } } },
    friendsOnlyAuthor: { author: { user: { profileVisibility: "friends" } } },
    mutedAuthor: { author: { mute: { type: "communicationMute", expiresAt: null } } },
    suspendedAuthor: { author: { user: { disabled: true } } },
    deletedAuthor: { author: { omitUser: true } },
  };
  for (const [label, { moment = {}, author = null }] of Object.entries(cases)) {
    const db = world({ moment });
    if (author !== null) {
      seedPerson(db, AUTHOR, { nowMs: NOW_MS, viewerId: VIEWER, ...author });
      if (author.omitUser) db._documents.delete(`users/${AUTHOR}`);
    }
    seedPublicLikers(db, 2);
    await rejectsWith(call(service(db), { momentId: MOMENT }), "permission-denied", {
      message: UNAVAILABLE,
    }).catch((error) => {
      throw new Error(`${label}: ${error.message}`);
    });
    assert.equal(db.paths("likerPageCursors/").length, 0, label);
  }
  // A friends-only author with both guards is listable (the Voice rule).
  const db = world();
  seedPerson(db, AUTHOR, {
    nowMs: NOW_MS,
    viewerId: VIEWER,
    user: { profileVisibility: "friends" },
    friends: "both",
  });
  seedPublicLikers(db, 2);
  assert.equal((await call(service(db), { momentId: MOMENT })).likers.length, 2);
});

test("the author sees the likers of their own Moment", async () => {
  const db = world();
  db.seed(`vipGrants/${AUTHOR}`, {
    source: "admin",
    expiresAt: null,
    revoked: false,
    active: true,
  });
  seedPublicLikers(db, 3);
  const page = await call(service(db), { momentId: MOMENT }, AUTHOR);
  assert.equal(page.likers.length, 3);
});

test("25 visible among 30 edges: page 2 starts at the 21st visible liker", async () => {
  const db = world();
  const hiddenAt = new Set([3, 9, 14, 20, 27]);
  const visible = [];
  for (let index = 0; index < 30; index += 1) {
    const uid = `vml-p-${String(index).padStart(2, "0")}`;
    seedPerson(db, uid, {
      nowMs: NOW_MS,
      viewerId: VIEWER,
      ...(hiddenAt.has(index) ? { user: { likesHidden: true } } : {}),
    });
    momentLike(db, uid, NOW_MS - 60_000 - index * 1_000);
    if (!hiddenAt.has(index)) visible.push(uid);
  }
  const moments = service(db);
  const first = await call(moments, { momentId: MOMENT });
  assertExactPage(first);
  assert.deepEqual(first.likers.map((row) => row.userId), visible.slice(0, 20));
  assert.equal(first.hasMore, true);
  const stored = db.data(`likerPageCursors/${first.nextCursor}`);
  assert.equal(stored.viewerId, VIEWER);
  assert.equal(stored.afterEmojiIndex, null);
  // The cursor sits after the last CONSUMED edge (the 20th visible), not
  // after the whole fetched chunk.
  assert.equal(stored.afterId, visible[19]);

  const second = await call(moments, { momentId: MOMENT, cursor: first.nextCursor });
  assert.deepEqual(second.likers.map((row) => row.userId), visible.slice(20));
  assert.equal(second.hasMore, false);
  assert.equal(second.nextCursor, null);

  // A retry after a lost response replays the identical page.
  const replay = await call(moments, { momentId: MOMENT, cursor: first.nextCursor });
  assert.deepEqual(replay, second);

  // A cursor is bound to its viewer and its target.
  db.seed(`vipGrants/${AUTHOR}`, {
    source: "testerProgram",
    expiresAt: null,
    revoked: false,
  });
  await rejectsWith(call(moments, { momentId: MOMENT, cursor: first.nextCursor }, AUTHOR),
    "invalid-argument", { message: "cursor is invalid." });
  await rejectsWith(
    call(moments, { momentId: MOMENT, commentId: COMMENT, cursor: first.nextCursor }),
    "invalid-argument",
    { message: "cursor is invalid." },
  );
  await rejectsWith(
    call(moments, { momentId: MOMENT, cursor: "A".repeat(43) }),
    "invalid-argument",
    { message: "cursor is invalid." },
  );
});

test("an expired cursor is invalid-argument", async () => {
  const db = world();
  seedPublicLikers(db, 22);
  let nowMs = NOW_MS;
  const moments = service(db, { clock: () => nowMs });
  const first = await call(moments, { momentId: MOMENT });
  assert.equal(first.hasMore, true);
  nowMs += 15 * 60_000;
  await rejectsWith(call(moments, { momentId: MOMENT, cursor: first.nextCursor }),
    "invalid-argument", { message: "cursor is invalid." });
});

test("a Moment that expires during the scan is refused by the response-time re-check", async () => {
  const db = world({ moment: { expiresAt: new Date(NOW_MS + 5) } });
  seedPublicLikers(db, 22);
  let calls = 0;
  // The request clock is inside the window; every later clock read is past it.
  const moments = service(db, { clock: () => (calls++ === 0 ? NOW_MS : NOW_MS + 10) });
  await rejectsWith(call(moments, { momentId: MOMENT }), "permission-denied", {
    message: UNAVAILABLE,
  });
  assert.equal(db.paths("likerPageCursors/").length, 0, "no cursor for a refused page");
});

test("worst case: 60 consumed hidden friends-only likers stay within momentWorst", async () => {
  const db = world();
  // Friends-only likers with ONE guard pass phases 1 and 2, then fail phase 3:
  // the most expensive hidden candidate.
  for (let index = 0; index < 70; index += 1) {
    const uid = `vml-w-${String(index).padStart(2, "0")}`;
    seedPerson(db, uid, {
      nowMs: NOW_MS,
      viewerId: VIEWER,
      user: { profileVisibility: "friends" },
      friends: "forward",
    });
    momentLike(db, uid, NOW_MS - 60_000 - index * 1_000);
  }
  const moments = service(db);
  const first = await call(moments, { momentId: MOMENT });
  assert.deepEqual(first.likers, []);
  assert.equal(first.hasMore, true, "the scan cap advanced the cursor");
  assert.equal(db.data(`likerPageCursors/${first.nextCursor}`).afterId, "vml-w-59");

  const meter = instrument(db);
  const second = await call(moments, { momentId: MOMENT, cursor: first.nextCursor });
  assert.deepEqual(second.likers, []);
  assert.equal(second.hasMore, false);
  assert.ok(meter.reads() <= VOICE_MOMENT_LIKERS_READ_BUDGETS.momentWorst);

  // A full worst first page measured exactly: a friends-only parent author
  // (7 context reads), 63 fetched edges and 60 consumed x 7; only the cursor
  // read of a later page is missing.
  const heavy = world();
  seedPerson(heavy, AUTHOR, {
    nowMs: NOW_MS,
    viewerId: VIEWER,
    user: { profileVisibility: "friends" },
    friends: "both",
  });
  for (let index = 0; index < 70; index += 1) {
    const uid = `vml-h-${String(index).padStart(2, "0")}`;
    seedPerson(heavy, uid, {
      nowMs: NOW_MS,
      viewerId: VIEWER,
      user: { profileVisibility: "friends" },
      friends: "forward",
    });
    momentLike(heavy, uid, NOW_MS - 60_000 - index * 1_000);
  }
  const heavyMeter = instrument(heavy);
  await call(service(heavy), { momentId: MOMENT });
  // First page: no cursor read.
  assert.equal(heavyMeter.reads(), VOICE_MOMENT_LIKERS_READ_BUDGETS.momentWorst - 1);
});

test("a typical page costs exactly momentTypical", async () => {
  const db = world();
  seedPublicLikers(db, 25);
  const meter = instrument(db);
  const page = await call(service(db), { momentId: MOMENT });
  assert.equal(page.likers.length, 20);
  assert.equal(meter.reads(), VOICE_MOMENT_LIKERS_READ_BUDGETS.momentTypical);
});

test("comment target: lists the comment's own likes through the flat store", async () => {
  const db = world();
  const visible = seedPublicLikers(db, 3, { prefix: "vml-c", comment: true });
  // Another comment's like and a Moment like are not this list.
  seedPerson(db, "vml-other", { nowMs: NOW_MS, viewerId: VIEWER });
  commentLike(db, "vml-other", NOW_MS - 1_000, "vml-comment-2");
  momentLike(db, "vml-other", NOW_MS - 1_000);
  // Malformed edges: wrong id suffix, extra key, wrong parent.
  const key = `v:${MOMENT}:${COMMENT}`;
  seedPerson(db, "vml-bad", { nowMs: NOW_MS, viewerId: VIEWER });
  db.seed(`commentLikes/${key}:vml-not-bad`, {
    schemaVersion: 1,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentId: COMMENT,
    commentKey: key,
    userId: "vml-bad",
    createdAt: new Date(NOW_MS - 2_000),
  });
  db.seed(`commentLikes/${key}:vml-bad`, {
    schemaVersion: 1,
    parentKind: "reel",
    parentId: MOMENT,
    commentId: COMMENT,
    commentKey: key,
    userId: "vml-bad",
    createdAt: new Date(NOW_MS - 3_000),
  });
  const meter = instrument(db);
  const page = await call(service(db), { momentId: MOMENT, commentId: COMMENT });
  assertExactPage(page);
  assert.deepEqual(page.likers.map((row) => row.userId), visible);
  assert.equal(page.hasMore, false);
  assert.ok(meter.reads() <= VOICE_MOMENT_LIKERS_READ_BUDGETS.commentTypical);
  for (const path of meter.transactionReads) assert.match(path, /^privateRateLimits\//u);
});

test("comment target: a missing, malformed or hidden comment is the uniform refusal", async () => {
  const cases = {
    missing: { comment: null },
    malformed: { comment: { extra: 1 } },
    commenterBlocked: { commenter: { personBlocks: true } },
    commenterMuted: { commenter: { mute: { type: "communicationMute", expiresAt: null } } },
    commenterPrivate: { commenter: { user: { profileVisibility: "private" } } },
  };
  for (const [label, { comment = {}, commenter = null }] of Object.entries(cases)) {
    const db = world({ comment });
    if (commenter !== null) {
      seedPerson(db, COMMENTER, { nowMs: NOW_MS, viewerId: VIEWER, ...commenter });
    }
    seedPublicLikers(db, 2, { comment: true });
    await rejectsWith(
      call(service(db), { momentId: MOMENT, commentId: COMMENT }),
      "permission-denied",
      { message: UNAVAILABLE },
    ).catch((error) => {
      throw new Error(`${label}: ${error.message}`);
    });
  }
  // The comment target inherits the parent refusal too.
  const db = world({ moment: { expiresAt: new Date(NOW_MS - 1) } });
  await rejectsWith(
    call(service(db), { momentId: MOMENT, commentId: COMMENT }),
    "permission-denied",
    { message: UNAVAILABLE },
  );
});

test("likers.list is 10 per minute, shared, and logs exhaustion without a uid", async () => {
  const db = world();
  seedPublicLikers(db, 1);
  const warnings = [];
  const moments = service(db, { warnings });
  for (let index = 0; index < 10; index += 1) {
    await call(moments, { momentId: MOMENT });
  }
  await rejectsWith(call(moments, { momentId: MOMENT }), "resource-exhausted");
  const exhausted = warnings.filter(([message]) => message === "likers budget exhausted");
  assert.deepEqual(exhausted, [["likers budget exhausted", { scope: "likers.list" }]]);
  assert.equal(JSON.stringify(exhausted).includes(VIEWER), false);
});

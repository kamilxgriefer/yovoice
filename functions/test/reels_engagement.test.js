const assert = require("node:assert/strict");
const { test } = require("node:test");

const { DEFAULT_LIMITS, createReelService } = require("../reels/service");
const { digest } = require("../integrity/guards");
const {
  MAX_REEL_COMMENT_LENGTH,
  MAX_REEL_THREAD_COMMENTS,
  decodeReelCommentCursor,
  encodeReelCommentCursor,
  storedEngagementCount,
  validateReelComment,
  validateReelLike,
} = require("../reels/engagement");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const AUTHOR = "creator-1";
const VIEWER = "viewer-1";
const OTHER = "viewer-2";
const REEL_ID = "reel_1";

function composition() {
  return {
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
  };
}

// Deliberately the pre-engagement shape: NO likeCount and NO commentCount.
// Every assertion in this file therefore starts from a Reel published before
// this contract existed, which is the only shape production currently holds.
function publishedReel({
  id = REEL_ID,
  authorId = AUTHOR,
  moderationStatus = "visible",
  status = "published",
} = {}) {
  return {
    schemaVersion: 1,
    status,
    moderationStatus,
    authorId,
    authorName: `Creator ${authorId}`,
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "123",
      durationMs: 0,
      storagePath: `reels/${authorId}/${id}/media.jpg`,
    },
    backingAudio: null,
    composition: composition(),
    sortKey: `${String(NOW_MS).padStart(13, "0")}_${id}`,
    publishedAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  };
}

function publicProfile(uid, displayName) {
  return {
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: null,
    displayName,
    displayNameSearch: displayName.toLowerCase(),
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
    updatedAt: new Date(NOW_MS),
    username: uid,
    usernameSearch: uid,
    website: null,
  };
}

function engagementFixture({
  limits = DEFAULT_LIMITS,
  clock = () => NOW_MS,
  reel = {},
  availability = { hours: "permanent" },
} = {}) {
  const db = new InMemoryFirestore();
  for (const uid of [AUTHOR, VIEWER, OTHER]) {
    db.seed(`users/${uid}`, { uid, displayName: `Name ${uid}` });
    db.seed(`publicProfiles/${uid}`, publicProfile(uid, `Name ${uid}`));
  }
  const reelId = reel.id ?? REEL_ID;
  db.seed(`reels/${reelId}`, publishedReel(reel));
  if (availability !== null) {
    db.seed(`reelAvailability/${reelId}`, {
      schemaVersion: 2,
      status: "published",
      ownerId: reel.authorId ?? AUTHOR,
      reelId,
      availabilityHours: availability.hours,
      createdAt: new Date(NOW_MS),
      publishedAt: new Date(NOW_MS),
      ...(availability.hours === "permanent"
        ? {}
        : { expiresAt: new Date(NOW_MS + availability.hours * 60 * 60 * 1000) }),
      updatedAt: new Date(NOW_MS),
    });
  }
  const deletions = [];
  const storage = {
    // The retention phase re-reads and revokes the real object, so the
    // metadata must match what finalize wrote or that phase fails closed.
    getMetadata: async (path) => ({
      generation: "123",
      contentType: "image/jpeg",
      size: 1024,
      metadata: {
        ownerId: reel.authorId ?? AUTHOR,
        reelId,
        assetKind: path.includes("backing-audio") ? "backingAudio" : "media",
      },
    }),
    readHeader: async () => Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
    revokeDownloadTokens: async () => {},
    getSignedReadUrl: async () => "https://storage.googleapis.com/bucket/file",
    deleteObject: async (path, options) => {
      deletions.push({ path, options });
    },
  };
  return {
    db,
    deletions,
    service: createReelService({
      db,
      FieldPath: { documentId: () => "__name__" },
      Timestamp: { fromMillis: (value) => new Date(value) },
      storage,
      clock,
      limits,
    }),
  };
}

function likeRequest(overrides = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: true } },
    data: {
      reelId: REEL_ID,
      liked: true,
      requestId: "like-request-0001",
      ...overrides,
    },
  };
}

function commentRequest(overrides = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: true } },
    data: {
      reelId: REEL_ID,
      text: "Real words from a real person",
      requestId: "comment-request-0001",
      ...overrides,
    },
  };
}

function viewRequest(overrides = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: { reelId: REEL_ID, ...overrides },
  };
}

async function rejects(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

function rateState(db, scope) {
  return db.paths("privateRateLimits/")
    .map((path) => db.data(path))
    .find((value) => value.scope === scope);
}

// ---------------------------------------------------------------------------
// Additive schema
// ---------------------------------------------------------------------------

test("a Reel published before the engagement contract still likes and comments", async () => {
  const { db, service } = engagementFixture();
  assert.equal(db.data(`reels/${REEL_ID}`).likeCount, undefined);
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, undefined);

  const liked = await service.setReelLike(likeRequest());
  assert.deepEqual(liked, {
    reelId: REEL_ID,
    liked: true,
    changed: true,
    likeCount: 1,
  });
  const commented = await service.createReelComment(commentRequest());
  assert.equal(commented.created, true);
  assert.equal(commented.commentCount, 1);

  const stored = db.data(`reels/${REEL_ID}`);
  assert.equal(stored.likeCount, 1);
  assert.equal(stored.commentCount, 1);
  // The counters were materialized without disturbing any other field.
  assert.equal(stored.sortKey, publishedReel().sortKey);
  assert.equal(stored.authorName, publishedReel().authorName);
  assert.equal(stored.status, "published");
});

test("absent counters read as zero and a corrupt counter fails closed", () => {
  assert.equal(storedEngagementCount(undefined, "likeCount"), 0);
  assert.equal(storedEngagementCount(0, "likeCount"), 0);
  assert.equal(storedEngagementCount(7, "likeCount"), 7);
  for (const bad of [null, -1, 1.5, "3", true]) {
    assert.throws(() => storedEngagementCount(bad, "likeCount"), {
      code: "data-loss",
    });
  }
});

test("an unknown field on a Reel root is still rejected by the exact guard", async () => {
  const { db, service } = engagementFixture();
  db.seed(`reels/${REEL_ID}`, {
    ...publishedReel(),
    likeCount: 2,
    shadowCount: 99,
  });
  await rejects(service.setReelLike(likeRequest()), "data-loss");
});

// ---------------------------------------------------------------------------
// setReelLike
// ---------------------------------------------------------------------------

test("replaying one requestId neither double-counts nor writes twice", async () => {
  const { db, service } = engagementFixture();
  const first = await service.setReelLike(likeRequest());
  const second = await service.setReelLike(likeRequest());
  assert.deepEqual(second, first);
  assert.equal(db.data(`reels/${REEL_ID}`).likeCount, 1);
  assert.equal(
    db.paths(`reels/${REEL_ID}/likes/`).length,
    1,
    "exactly one like edge",
  );
  // A replay is free: the rate budget was charged once, not twice.
  assert.equal(rateState(db, "reel.like").count, 1);
});

test("a different requestId reusing one operation identity is refused", async () => {
  const { service } = engagementFixture();
  await service.setReelLike(likeRequest());
  // Same requestId, different input: the ledger proves the mismatch.
  await rejects(
    service.setReelLike(likeRequest({ liked: false })),
    "already-exists",
  );
});

test("unliking removes the edge, decrements once, and never goes negative", async () => {
  const { db, service } = engagementFixture();
  await service.setReelLike(likeRequest());
  const unliked = await service.setReelLike(
    likeRequest({ liked: false, requestId: "like-request-0002" }),
  );
  assert.deepEqual(unliked, {
    reelId: REEL_ID,
    liked: false,
    changed: true,
    likeCount: 0,
  });
  assert.equal(db.paths(`reels/${REEL_ID}/likes/`).length, 0);

  // Unliking again is a no-op, not a second decrement.
  const repeat = await service.setReelLike(
    likeRequest({ liked: false, requestId: "like-request-0003" }),
  );
  assert.equal(repeat.changed, false);
  assert.equal(repeat.likeCount, 0);
  assert.equal(db.data(`reels/${REEL_ID}`).likeCount, 0);
});

test("a counter desynchronized out of band refuses to go negative", async () => {
  const { db, service } = engagementFixture();
  await service.setReelLike(likeRequest());
  // The edge exists but the counter was corrupted to zero out of band.
  db.seed(`reels/${REEL_ID}`, { ...publishedReel(), likeCount: 0 });
  await rejects(
    service.setReelLike(likeRequest({ liked: false, requestId: "like-x-0002" })),
    "data-loss",
  );
  assert.equal(db.data(`reels/${REEL_ID}`).likeCount, 0);
});

test("the like budget is charged before any graph read and then refuses", async () => {
  const { db, service } = engagementFixture({
    limits: {
      ...DEFAULT_LIMITS,
      like: { maxEvents: 2, windowMs: 60_000 },
    },
  });
  await service.setReelLike(likeRequest());
  await service.setReelLike(
    likeRequest({ liked: false, requestId: "like-request-0002" }),
  );
  await rejects(
    service.setReelLike(likeRequest({ requestId: "like-request-0003" })),
    "resource-exhausted",
  );
  assert.equal(rateState(db, "reel.like").count, 2);
});

test("an unverified account cannot like, but a verified one can", async () => {
  const { service } = engagementFixture();
  await rejects(
    service.setReelLike({
      auth: { uid: VIEWER, token: { email_verified: false } },
      data: { reelId: REEL_ID, liked: true, requestId: "like-request-0009" },
    }),
    "failed-precondition",
  );
});

test("likes reject unsupported input shapes", async () => {
  const { service } = engagementFixture();
  await rejects(
    service.setReelLike(likeRequest({ extra: true })),
    "invalid-argument",
  );
  await rejects(service.setReelLike(likeRequest({ liked: "yes" })), "invalid-argument");
  await rejects(service.setReelLike(likeRequest({ requestId: "short" })), "invalid-argument");
  await rejects(service.setReelLike(likeRequest({ reelId: "a/b" })), "invalid-argument");
});

// ---------------------------------------------------------------------------
// Availability, moderation and blocks
// ---------------------------------------------------------------------------

test("an expired Reel accepts neither a like nor a comment", async () => {
  const { service } = engagementFixture({
    availability: { hours: 24 },
    clock: () => NOW_MS + 25 * 60 * 60 * 1000,
  });
  await rejects(service.setReelLike(likeRequest()), "failed-precondition");
  await rejects(service.createReelComment(commentRequest()), "failed-precondition");
});

test("a Reel exactly at its deadline is already closed to engagement", async () => {
  const { service } = engagementFixture({
    availability: { hours: 24 },
    clock: () => NOW_MS + 24 * 60 * 60 * 1000,
  });
  await rejects(service.setReelLike(likeRequest()), "failed-precondition");
});

test("a hidden or expired-status Reel accepts no new engagement", async () => {
  for (const reel of [{ moderationStatus: "hidden" }, { status: "expired" }]) {
    const { service } = engagementFixture({ reel });
    await rejects(service.setReelLike(likeRequest()), "data-loss");
    await rejects(service.createReelComment(commentRequest()), "data-loss");
  }
});

test("a deleted Reel accepts neither engagement nor comment deletion", async () => {
  const { db, service } = engagementFixture();
  db.seed(`reels/${REEL_ID}`, {
    schemaVersion: 1,
    status: "deleted",
    authorId: AUTHOR,
    moderationStatusAtDeletion: "visible",
    moderationEvidence: {
      evidenceVersion: 1,
      publishedAt: new Date(NOW_MS),
      metadataFingerprint: "a".repeat(64),
    },
    deletedAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  });
  await rejects(service.setReelLike(likeRequest()), "data-loss");
  await rejects(
    service.deleteReelComment({
      auth: { uid: VIEWER, token: { email_verified: true } },
      data: {
        reelId: REEL_ID,
        commentId: "any-comment",
        requestId: "delete-request-0001",
      },
    }),
    "not-found",
  );
});

test("a block in either direction stops likes and comments", async () => {
  for (const [blocker, blocked] of [[VIEWER, AUTHOR], [AUTHOR, VIEWER]]) {
    const { db, service } = engagementFixture();
    db.seed(`users/${blocker}/blocked/${blocked}`, {
      uid: blocked,
      blockedAt: new Date(NOW_MS),
    });
    await rejects(service.setReelLike(likeRequest()), "failed-precondition");
    await rejects(service.createReelComment(commentRequest()), "failed-precondition");
    assert.equal(db.data(`reels/${REEL_ID}`).likeCount, undefined);
  }
});

test("a suspended author's Reel and a muted viewer both refuse engagement", async () => {
  const suspended = engagementFixture();
  suspended.db.seed(`users/${AUTHOR}`, { uid: AUTHOR, banned: true });
  await rejects(suspended.service.setReelLike(likeRequest()), "permission-denied");

  const muted = engagementFixture();
  muted.db.seed(`restrictions/${VIEWER}`, {
    type: "communicationMute",
    expiresAt: null,
  });
  await rejects(muted.service.setReelLike(likeRequest()), "permission-denied");

  const mutedAuthor = engagementFixture();
  mutedAuthor.db.seed(`restrictions/${AUTHOR}`, {
    type: "communicationMute",
    expiresAt: null,
  });
  await rejects(
    mutedAuthor.service.createReelComment(commentRequest()),
    "permission-denied",
  );
});

test("an author may engage with their own Reel without a self-block read", async () => {
  const { service } = engagementFixture();
  const result = await service.setReelLike({
    auth: { uid: AUTHOR, token: { email_verified: true } },
    data: { reelId: REEL_ID, liked: true, requestId: "self-like-0001" },
  });
  assert.equal(result.likeCount, 1);
});

// ---------------------------------------------------------------------------
// createReelComment / deleteReelComment
// ---------------------------------------------------------------------------

test("a comment stores server-resolved identity and an exact schema", async () => {
  const { db, service } = engagementFixture();
  const result = await service.createReelComment(commentRequest());
  const stored = db.data(`reels/${REEL_ID}/comments/${result.commentId}`);
  assert.deepEqual(Object.keys(stored).sort(), [
    "authorId",
    "authorName",
    "createdAt",
    "durationSeconds",
    "reelId",
    "schemaVersion",
    "text",
    "type",
  ]);
  assert.equal(stored.authorId, VIEWER);
  // Not a client-supplied name: the canonical public profile's.
  assert.equal(stored.authorName, `Name ${VIEWER}`);
  assert.equal(stored.reelId, REEL_ID);
  assert.equal(stored.type, "text");
  assert.equal(stored.durationSeconds, null);
  assert.equal(stored.text, "Real words from a real person");
});

test("replaying a comment requestId returns the first result and one document", async () => {
  const { db, service } = engagementFixture();
  const first = await service.createReelComment(commentRequest());
  const second = await service.createReelComment(commentRequest());
  assert.deepEqual(second, first);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);
  assert.equal(rateState(db, "reel.comment").count, 1);
});

test("comment text is normalized and bounded", async () => {
  const { db, service } = engagementFixture();
  const trimmed = await service.createReelComment(
    commentRequest({ text: "   padded   ", requestId: "comment-pad-0001" }),
  );
  assert.equal(
    db.data(`reels/${REEL_ID}/comments/${trimmed.commentId}`).text,
    "padded",
  );
  await rejects(
    service.createReelComment(commentRequest({ text: "   ", requestId: "comment-e-0001" })),
    "invalid-argument",
  );
  await rejects(
    service.createReelComment(
      commentRequest({
        text: "x".repeat(MAX_REEL_COMMENT_LENGTH + 1),
        requestId: "comment-long-0001",
      }),
    ),
    "invalid-argument",
  );
});

test("deleting a comment decrements exactly once and is idempotent on replay", async () => {
  const { db, service } = engagementFixture();
  const created = await service.createReelComment(commentRequest());
  const second = await service.createReelComment(
    commentRequest({ requestId: "comment-request-0002", text: "Another" }),
  );
  assert.equal(second.commentCount, 2);

  const deleteRequest = {
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: {
      reelId: REEL_ID,
      commentId: created.commentId,
      requestId: "delete-request-0001",
    },
  };
  const deleted = await service.deleteReelComment(deleteRequest);
  assert.deepEqual(deleted, {
    reelId: REEL_ID,
    commentId: created.commentId,
    deleted: true,
    commentCount: 1,
  });
  const replayed = await service.deleteReelComment(deleteRequest);
  assert.deepEqual(replayed, deleted);
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
});

test("only the comment's author may delete it", async () => {
  const { service } = engagementFixture();
  const created = await service.createReelComment(commentRequest());
  for (const uid of [AUTHOR, OTHER]) {
    await rejects(
      service.deleteReelComment({
        auth: { uid, token: { email_verified: true } },
        data: {
          reelId: REEL_ID,
          commentId: created.commentId,
          requestId: `delete-foreign-${uid}`,
        },
      }),
      "permission-denied",
    );
  }
});

test("a comment stays deletable after the Reel expires or is hidden", async () => {
  for (const reel of [{}, { moderationStatus: "hidden" }]) {
    const { db, service } = engagementFixture();
    const created = await service.createReelComment(commentRequest());
    db.seed(`reels/${REEL_ID}`, {
      ...publishedReel({ ...reel, status: "expired" }),
      commentCount: 1,
    });
    const deleted = await service.deleteReelComment({
      auth: { uid: VIEWER, token: { email_verified: false } },
      data: {
        reelId: REEL_ID,
        commentId: created.commentId,
        requestId: "delete-after-expiry-01",
      },
    });
    assert.equal(deleted.commentCount, 0);
  }
});

test("comment deletion refuses to drive the counter negative", async () => {
  const { db, service } = engagementFixture();
  const created = await service.createReelComment(commentRequest());
  db.seed(`reels/${REEL_ID}`, { ...publishedReel(), commentCount: 0 });
  await rejects(
    service.deleteReelComment({
      auth: { uid: VIEWER, token: { email_verified: false } },
      data: {
        reelId: REEL_ID,
        commentId: created.commentId,
        requestId: "delete-negative-001",
      },
    }),
    "data-loss",
  );
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 0);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
});

test("comment deletion stays available to an unverified muted active author", async () => {
  const { db, service } = engagementFixture();
  const created = await service.createReelComment(commentRequest());
  db.seed(`restrictions/${VIEWER}`, {
    type: "communicationMute",
    expiresAt: null,
  });
  const deleted = await service.deleteReelComment({
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: {
      reelId: REEL_ID,
      commentId: created.commentId,
      requestId: "delete-muted-00001",
    },
  });
  assert.equal(deleted.deleted, true);
});

test("comment deletion refuses an inactive account", async () => {
  const { db, service } = engagementFixture();
  const created = await service.createReelComment(commentRequest());
  db.seed(`users/${VIEWER}`, { uid: VIEWER, banned: true });
  await rejects(
    service.deleteReelComment({
      auth: { uid: VIEWER, token: { email_verified: false } },
      data: {
        reelId: REEL_ID,
        commentId: created.commentId,
        requestId: "delete-banned-0001",
      },
    }),
    "permission-denied",
  );
});

// ---------------------------------------------------------------------------
// getReelViewV2
// ---------------------------------------------------------------------------

test("the view projects counters, callerLiked and a bounded comment page", async () => {
  const { service } = engagementFixture();
  await service.setReelLike(likeRequest());
  await service.createReelComment(commentRequest());

  const view = await service.getReelViewV2(viewRequest());
  assert.equal(view.schemaVersion, 2);
  assert.equal(view.reel.id, REEL_ID);
  assert.equal(view.reel.likeCount, 1);
  assert.equal(view.reel.commentCount, 1);
  assert.equal(view.reel.callerLiked, true);
  assert.equal(view.commentsTruncated, false);
  assert.equal(view.nextCommentCursor, null);
  assert.equal(view.comments.length, 1);
  assert.deepEqual(Object.keys(view.comments[0]).sort(), [
    "authorId",
    "authorName",
    "authorPhotoUrl",
    "commentId",
    "createdAtMillis",
    "durationSeconds",
    "schemaVersion",
    "text",
    "type",
  ]);
  assert.equal(view.comments[0].authorPhotoUrl, null);

  // Another viewer sees the same counters with their own callerLiked.
  const otherView = await service.getReelViewV2({
    auth: { uid: OTHER, token: { email_verified: false } },
    data: { reelId: REEL_ID },
  });
  assert.equal(otherView.reel.likeCount, 1);
  assert.equal(otherView.reel.callerLiked, false);
});

test("a legacy Reel with no counters views as zero", async () => {
  const { service } = engagementFixture();
  const view = await service.getReelViewV2(viewRequest());
  assert.equal(view.reel.likeCount, 0);
  assert.equal(view.reel.commentCount, 0);
  assert.equal(view.reel.callerLiked, false);
  assert.deepEqual(view.comments, []);
});

test("the comment page is bounded and its cursor pages forward exactly once", async () => {
  let tick = 0;
  const { service } = engagementFixture({ clock: () => NOW_MS + tick });
  for (let index = 0; index < 4; index += 1) {
    tick = index * 1000;
    await service.createReelComment(
      commentRequest({
        text: `Comment ${index}`,
        requestId: `comment-page-000${index}`,
      }),
    );
  }
  tick = 10_000;
  const first = await service.getReelViewV2(viewRequest({ commentLimit: 2 }));
  assert.equal(first.comments.length, 2);
  assert.equal(first.commentsTruncated, true);
  assert.notEqual(first.nextCommentCursor, null);
  assert.deepEqual(
    first.comments.map(({ text }) => text),
    ["Comment 0", "Comment 1"],
  );

  const second = await service.getReelViewV2(
    viewRequest({ commentLimit: 2, commentCursor: first.nextCommentCursor }),
  );
  assert.deepEqual(
    second.comments.map(({ text }) => text),
    ["Comment 2", "Comment 3"],
  );
  assert.equal(second.commentsTruncated, false);
  assert.equal(second.nextCommentCursor, null);
});

test("the view refuses an oversized limit and a foreign or malformed cursor", async () => {
  const { service } = engagementFixture();
  await rejects(
    service.getReelViewV2(viewRequest({ commentLimit: MAX_REEL_THREAD_COMMENTS + 1 })),
    "invalid-argument",
  );
  await rejects(service.getReelViewV2(viewRequest({ commentLimit: 0 })), "invalid-argument");
  await rejects(
    service.getReelViewV2(viewRequest({ commentCursor: "not-a-cursor!" })),
    "invalid-argument",
  );
  const foreign = encodeReelCommentCursor({
    reelId: "another_reel",
    id: "abc",
    createdAtMillis: NOW_MS,
  });
  await rejects(
    service.getReelViewV2(viewRequest({ commentCursor: foreign })),
    "invalid-argument",
  );
  await rejects(
    service.getReelViewV2(viewRequest({ unexpected: 1 })),
    "invalid-argument",
  );
});

test("the view withholds a blocked commenter but keeps the aggregate count", async () => {
  const { db, service } = engagementFixture();
  await service.createReelComment(commentRequest());
  await service.createReelComment({
    auth: { uid: OTHER, token: { email_verified: true } },
    data: {
      reelId: REEL_ID,
      text: "From the other person",
      requestId: "comment-other-00001",
    },
  });
  db.seed(`users/${VIEWER}/blocked/${OTHER}`, {
    uid: OTHER,
    blockedAt: new Date(NOW_MS),
  });

  const view = await service.getReelViewV2(viewRequest());
  assert.equal(view.reel.commentCount, 2, "the aggregate never leaks the block");
  assert.equal(view.comments.length, 1);
  assert.equal(view.comments[0].authorId, VIEWER);
});

test("every view refusal is one envelope, so it is not a per-Reel oracle", async () => {
  // A caller banks Reel ids from listReelsV2 while access is normal, then
  // polls this callable. Distinct codes would answer "did they block me",
  // "were they suspended or muted", "did staff hide it", "is it expired",
  // "does it exist" — one message answers none of them.
  const cases = [];

  const blocked = engagementFixture();
  blocked.db.seed(`users/${AUTHOR}/blocked/${VIEWER}`, {
    uid: VIEWER,
    blockedAt: new Date(NOW_MS),
  });
  cases.push(blocked.service.getReelViewV2(viewRequest()));

  const suspended = engagementFixture();
  suspended.db.seed(`users/${AUTHOR}`, { uid: AUTHOR, disabled: true });
  cases.push(suspended.service.getReelViewV2(viewRequest()));

  const muted = engagementFixture();
  muted.db.seed(`restrictions/${AUTHOR}`, {
    type: "communicationMute",
    expiresAt: null,
  });
  cases.push(muted.service.getReelViewV2(viewRequest()));

  const hidden = engagementFixture({ reel: { moderationStatus: "hidden" } });
  cases.push(hidden.service.getReelViewV2(viewRequest()));

  const expired = engagementFixture({
    availability: { hours: 24 },
    clock: () => NOW_MS + 25 * 60 * 60 * 1000,
  });
  cases.push(expired.service.getReelViewV2(viewRequest()));

  const missing = engagementFixture();
  cases.push(missing.service.getReelViewV2(viewRequest({ reelId: "no_such" })));

  for (const pending of cases) {
    await assert.rejects(pending, (error) => {
      assert.equal(error.code, "permission-denied");
      assert.equal(error.message, "This Reel is unavailable.");
      return true;
    });
  }
});

test("the view still reports the caller's own request faults distinctly", async () => {
  const { db, service } = engagementFixture({
    limits: { ...DEFAULT_LIMITS, view: { maxEvents: 1, windowMs: 60_000 } },
  });
  await service.getReelViewV2(viewRequest());
  // A rate refusal describes the caller, not another account's state.
  await rejects(service.getReelViewV2(viewRequest()), "resource-exhausted");
  assert.equal(rateState(db, "reel.view").count, 1);
  await rejects(service.getReelViewV2(viewRequest({ commentLimit: 99 })), "invalid-argument");
});

test("an expired Reel still charges the view budget before it is refused", async () => {
  const { db, service } = engagementFixture({
    availability: { hours: 24 },
    clock: () => NOW_MS + 25 * 60 * 60 * 1000,
  });
  await rejects(service.getReelViewV2(viewRequest()), "permission-denied");
  assert.equal(rateState(db, "reel.view").count, 1);
});

test("a malformed comment is withheld without failing the page", async () => {
  const { db, service } = engagementFixture();
  const created = await service.createReelComment(commentRequest());
  db.seed(`reels/${REEL_ID}/comments/forged-comment`, {
    schemaVersion: 1,
    type: "text",
    reelId: REEL_ID,
    authorId: OTHER,
    authorName: "Impostor",
    text: "planted",
    durationSeconds: null,
    createdAt: new Date(NOW_MS + 1),
    isStaffAnnouncement: true,
  });
  const view = await service.getReelViewV2(viewRequest());
  assert.equal(view.comments.length, 1);
  assert.equal(view.comments[0].commentId, created.commentId);
});

// ---------------------------------------------------------------------------
// Feed projection
// ---------------------------------------------------------------------------

test("listReelsV2 carries engagement while listReels stays byte-frozen", async () => {
  const { service } = engagementFixture();
  await service.setReelLike(likeRequest());
  await service.createReelComment(commentRequest());

  const v2 = await service.listReelsV2({
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: { cursor: null, limit: 5 },
  });
  assert.equal(v2.items.length, 1);
  assert.equal(v2.items[0].likeCount, 1);
  assert.equal(v2.items[0].commentCount, 1);
  assert.equal(v2.items[0].callerLiked, true);

  const v1 = await service.listReels({
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: { cursor: null, limit: 5 },
  });
  assert.equal(v1.items.length, 1);
  for (const key of ["likeCount", "commentCount", "callerLiked", "availability"]) {
    assert.equal(
      Object.prototype.hasOwnProperty.call(v1.items[0], key),
      false,
      `v1 feed must not carry ${key}`,
    );
  }
});

test("a legacy Reel reaches the v2 feed with zeroed engagement", async () => {
  const { service } = engagementFixture();
  const v2 = await service.listReelsV2({
    auth: { uid: OTHER, token: { email_verified: false } },
    data: { cursor: null, limit: 5 },
  });
  assert.equal(v2.items[0].likeCount, 0);
  assert.equal(v2.items[0].commentCount, 0);
  assert.equal(v2.items[0].callerLiked, false);
});

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

test("deleting a Reel purges its likes and comments through the cleanup worker", async () => {
  const { db, service } = engagementFixture();
  await service.setReelLike(likeRequest());
  await service.createReelComment(commentRequest());
  assert.equal(db.paths(`reels/${REEL_ID}/likes/`).length, 1);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);

  // The production database exposes a bulk recursive delete; the shared test
  // double does not, so attach one that behaves the same way.
  db.recursiveDelete = async (reference) => {
    const prefix = `${reference.collectionPath ?? reference.path}/`;
    for (const path of db.paths(prefix)) db._documents.delete(path);
  };

  await service.deleteReel({
    auth: { uid: AUTHOR, token: { email_verified: false } },
    data: { reelId: REEL_ID, requestId: "delete-reel-000001" },
  });
  const outboxId = db.paths("reelCleanupOutbox/")[0].split("/")[1];
  await service.processCleanupOutbox(outboxId);

  assert.equal(db.paths(`reels/${REEL_ID}/likes/`).length, 0);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 0);
  // The moderation tombstone survives; only the engagement went away.
  assert.equal(db.data(`reels/${REEL_ID}`).status, "deleted");
});

test("a cleanup row can never strip engagement from a still-published Reel", async () => {
  // Regression for the adversarial finding: a cleanup row names only a
  // reelId, and the abandoned-draft sweep writes one whose reservation id is
  // derived from (uid, requestId) with no binding to a Reel's published
  // state. Purging on the row's word alone destroyed OTHER PEOPLE'S comments
  // under live content and left the counters permanently inflated above the
  // surviving edges. The root's current state is the authority.
  const { db, service } = engagementFixture();
  await service.setReelLike(likeRequest());
  await service.createReelComment({
    auth: { uid: OTHER, token: { email_verified: true } },
    data: {
      reelId: REEL_ID,
      text: "Someone else's words",
      requestId: "comment-victim-0001",
    },
  });
  db.recursiveDelete = async (reference) => {
    const prefix = `${reference.collectionPath ?? reference.path}/`;
    for (const path of db.paths(prefix)) db._documents.delete(path);
  };

  // A canonical abandoned-draft cleanup row pointing at the live, published
  // Reel — the exact shape expireAbandonedReelDrafts writes.
  const outboxId = digest("reel-cleanup", REEL_ID).slice(0, 40);
  db.seed(`reelCleanupOutbox/${outboxId}`, {
    schemaVersion: 1,
    kind: "reelMediaCleanup",
    ownerId: AUTHOR,
    reelId: REEL_ID,
    storagePaths: [`reels/${AUTHOR}/${REEL_ID}/media.jpg`],
    status: "pending",
    attemptCount: 0,
    phase: "delete",
    nextAttemptAt: new Date(NOW_MS),
    leaseToken: null,
    leaseUntil: null,
    lastErrorCode: null,
    createdAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  });
  const result = await service.processCleanupOutbox(outboxId);

  assert.equal(result.engagement, "liveRoot");
  assert.equal(db.data(`reels/${REEL_ID}`).status, "published");
  assert.equal(db.paths(`reels/${REEL_ID}/likes/`).length, 1);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
  // Counters and edges still agree — no fabricated social proof.
  assert.equal(db.data(`reels/${REEL_ID}`).likeCount, 1);
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);
});

test("the real expiry retention chain purges engagement at its purge date", async () => {
  const clockState = { nowMs: NOW_MS };
  const { db, service } = engagementFixture({
    availability: { hours: 24 },
    clock: () => clockState.nowMs,
  });
  await service.setReelLike(likeRequest());
  await service.createReelComment(commentRequest());
  db.recursiveDelete = async (reference) => {
    const prefix = `${reference.collectionPath ?? reference.path}/`;
    for (const path of db.paths(prefix)) db._documents.delete(path);
  };

  // Drive the genuine chain: the sweep expires the Reel and enqueues the
  // retention row, retention holds the originals, and only the purge phase
  // at purgeAt removes them — and the engagement with them.
  clockState.nowMs = NOW_MS + 25 * 60 * 60 * 1000;
  const swept = await service.expirePublishedReels({ limit: 10 });
  assert.deepEqual(swept.expired, [REEL_ID]);
  assert.equal(db.data(`reels/${REEL_ID}`).status, "expired");
  // The counters survive expiry untouched; only a purge removes them.
  assert.equal(db.data(`reels/${REEL_ID}`).likeCount, 1);

  const outboxPath = db.paths("reelCleanupOutbox/")[0];
  const outboxId = outboxPath.split("/").at(-1);
  await service.processCleanupOutbox(outboxId);
  assert.equal(
    db.paths(`reels/${REEL_ID}/comments/`).length,
    1,
    "retention must not purge engagement",
  );

  clockState.nowMs = db.data(outboxPath).purgeAt.getTime();
  await service.processCleanupOutbox(outboxId);
  assert.equal(db.paths(`reels/${REEL_ID}/likes/`).length, 0);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 0);
  assert.equal(db.data(`reels/${REEL_ID}`).status, "expired");
  assert.ok(db.data(`reels/${REEL_ID}`).purgedAt, "evidence tombstone written");
});

test("engagement cleanup is skipped, not fatal, without a bulk delete", async () => {
  const { db, service } = engagementFixture();
  await service.createReelComment(commentRequest());
  await service.deleteReel({
    auth: { uid: AUTHOR, token: { email_verified: false } },
    data: { reelId: REEL_ID, requestId: "delete-reel-000002" },
  });
  const outboxId = db.paths("reelCleanupOutbox/")[0].split("/")[1];
  const result = await service.processCleanupOutbox(outboxId);
  assert.equal(result.completed, true);
});

// ---------------------------------------------------------------------------
// Stored-shape guards
// ---------------------------------------------------------------------------

test("the like edge guard rejects a forged or repointed edge", () => {
  const canonical = {
    schemaVersion: 1,
    userId: VIEWER,
    reelId: REEL_ID,
    createdAt: new Date(NOW_MS),
  };
  const snapshot = (data) => ({ exists: true, id: VIEWER, data: () => data });
  assert.equal(validateReelLike(snapshot(canonical), REEL_ID, VIEWER), true);
  assert.equal(validateReelLike({ exists: false }, REEL_ID, VIEWER), false);
  for (const bad of [
    { ...canonical, userId: OTHER },
    { ...canonical, reelId: "another_reel" },
    { ...canonical, schemaVersion: 2 },
    { ...canonical, createdAt: "yesterday" },
    { ...canonical, extra: true },
  ]) {
    assert.throws(() => validateReelLike(snapshot(bad), REEL_ID, VIEWER), {
      code: "data-loss",
    });
  }
});

test("the comment guard rejects every off-contract stored shape", () => {
  const canonical = {
    schemaVersion: 1,
    type: "text",
    reelId: REEL_ID,
    authorId: VIEWER,
    authorName: "Name",
    text: "hello",
    durationSeconds: null,
    createdAt: new Date(NOW_MS),
  };
  const snapshot = (data) => ({ exists: true, id: "c1", data: () => data });
  assert.equal(validateReelComment(snapshot(canonical), REEL_ID).text, "hello");
  assert.throws(() => validateReelComment({ exists: false }, REEL_ID), {
    code: "not-found",
  });
  for (const bad of [
    { ...canonical, type: "voice" },
    { ...canonical, reelId: "another_reel" },
    { ...canonical, authorName: "  padded  " },
    { ...canonical, authorName: "x".repeat(81) },
    { ...canonical, text: "" },
    { ...canonical, text: "x".repeat(MAX_REEL_COMMENT_LENGTH + 1) },
    { ...canonical, durationSeconds: 12 },
    { ...canonical, createdAt: null },
    { ...canonical, moderatorPinned: true },
  ]) {
    assert.throws(() => validateReelComment(snapshot(bad), REEL_ID), {
      code: "data-loss",
    });
  }
});

test("a comment cursor round-trips and refuses tampering", () => {
  const cursor = encodeReelCommentCursor({
    reelId: REEL_ID,
    id: "comment-1",
    createdAtMillis: NOW_MS,
  });
  assert.deepEqual(decodeReelCommentCursor(cursor, { reelId: REEL_ID }), {
    schemaVersion: 1,
    kind: "reelComment",
    reelId: REEL_ID,
    id: "comment-1",
    createdAtMillis: NOW_MS,
  });
  assert.throws(() => decodeReelCommentCursor(cursor, { reelId: "other" }), {
    code: "invalid-argument",
  });
  const forged = Buffer.from(
    JSON.stringify({
      schemaVersion: 1,
      kind: "reelComment",
      reelId: REEL_ID,
      id: "comment-1",
      createdAtMillis: NOW_MS,
      admin: true,
    }),
    "utf8",
  ).toString("base64url");
  assert.throws(() => decodeReelCommentCursor(forged, { reelId: REEL_ID }), {
    code: "invalid-argument",
  });
});

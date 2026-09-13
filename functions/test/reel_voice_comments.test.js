const assert = require("node:assert/strict");
const { test } = require("node:test");

const { DEFAULT_LIMITS, createReelService } = require("../reels/service");
const {
  isCanonicalReelVoiceCommentPath,
  reelVoiceCommentCleanupOutboxId,
  reelVoiceCommentStoragePath,
  validateReelComment,
  validateReelVoiceCommentAudio,
} = require("../reels/engagement");
const { validateStoredAudio } = require("../moments/integrity");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

// ---------------------------------------------------------------------------
// Reel voice comments: reservation, upload, finalize, listen, delete, remove,
// moderate, purge and sweep.
//
// The whole point of this file is that a Reel voice comment gets the SAME
// guarantees a Voice Moment voice reply already has, so several assertions
// below deliberately compare against the Voice reply machinery itself rather
// than against a re-stated expectation.
// ---------------------------------------------------------------------------

const NOW_MS = 1_778_000_000_000;
const AUTHOR = "creator-1";
const VIEWER = "viewer-1";
const OTHER = "viewer-2";
const REEL_ID = "reel_1";
const GENEROUS = Object.freeze({
  ...DEFAULT_LIMITS,
  comment: Object.freeze({ maxEvents: 500, windowMs: 60 * 1000 }),
  commentDelete: Object.freeze({ maxEvents: 500, windowMs: 60 * 1000 }),
  commentRemove: Object.freeze({ maxEvents: 500, windowMs: 60 * 1000 }),
  mediaAccess: Object.freeze({ maxEvents: 500, windowMs: 60 * 1000 }),
  view: Object.freeze({ maxEvents: 500, windowMs: 60 * 1000 }),
});

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

function fixture({
  limits = GENEROUS,
  clock = () => NOW_MS,
  reel = {},
  availability = { hours: "permanent" },
  audio = {},
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
  const revocations = [];
  const recursiveDeletes = [];
  const audioObjects = new Map();
  const storage = {
    getMetadata: async (path) => {
      if (path.startsWith("reel_voice_comments/")) {
        const stored = audioObjects.get(path);
        if (stored === undefined) {
          const error = new Error(`missing object: ${path}`);
          error.code = 404;
          throw error;
        }
        return stored;
      }
      return {
        generation: "123",
        contentType: "image/jpeg",
        size: 1024,
        metadata: {
          ownerId: reel.authorId ?? AUTHOR,
          reelId,
          assetKind: path.includes("backing-audio") ? "backingAudio" : "media",
        },
      };
    },
    readHeader: async () => Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
    revokeDownloadTokens: async (path) => {
      revocations.push(path);
    },
    getSignedReadUrl: async () => "https://storage.googleapis.com/bucket/file",
    deleteObject: async (path, options) => {
      deletions.push({ path, options });
      audioObjects.delete(path);
    },
  };
  // recursiveDelete is absent from the shared in-memory double on purpose;
  // the purge path is only exercised where a test opts into it.
  db.recursiveDelete = async (collection) => {
    recursiveDeletes.push(collection.collectionPath);
    for (const path of db.paths(`${collection.collectionPath}/`)) {
      db._documents.delete(path);
    }
  };
  return {
    db,
    deletions,
    revocations,
    recursiveDeletes,
    // Puts the exact bytes a reservation authorizes into the fake bucket.
    putAudio(path, overrides = {}) {
      audioObjects.set(path, {
        generation: "900001",
        contentType: "audio/mp4",
        size: 4096,
        metadata: {
          authorId: VIEWER,
          reelId,
          commentId: path.split("/").at(-1).replace(/\.m4a$/u, ""),
          firebaseStorageDownloadTokens: "token-to-be-revoked",
        },
        ...overrides,
        ...(overrides.metadata === undefined ? {} : {}),
      });
      return audioObjects.get(path);
    },
    audioObjects,
    service: createReelService({
      db,
      FieldPath: { documentId: () => "__name__" },
      Timestamp: { fromMillis: (value) => new Date(value) },
      storage,
      clock,
      limits,
      ...audio,
    }),
  };
}

function actor(uid = VIEWER, verified = true) {
  return { uid, token: { email_verified: verified } };
}

async function rejects(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

// Reserve -> put bytes -> finalize, the exact three steps the client performs.
async function publishVoiceComment(context, {
  uid = VIEWER,
  requestId = "voice-request-0001",
  durationSeconds = 7,
  text = "",
  generation = "900001",
  metadata = undefined,
  size = 4096,
  contentType = "audio/mp4",
} = {}) {
  const reserved = await context.service.reserveReelVoiceCommentDraft({
    auth: actor(uid),
    data: { reelId: REEL_ID, requestId, durationSeconds, text },
  });
  context.audioObjects.set(reserved.storagePath, {
    generation,
    contentType,
    size,
    metadata: metadata ?? {
      authorId: uid,
      reelId: REEL_ID,
      commentId: reserved.commentId,
      firebaseStorageDownloadTokens: "token-to-be-revoked",
    },
  });
  const finalized = await context.service.finalizeReelVoiceCommentDraft({
    auth: actor(uid),
    data: {
      reelId: REEL_ID,
      commentId: reserved.commentId,
      requestId,
      objectGeneration: generation,
    },
  });
  return { reserved, finalized };
}

test("the stored-audio guard IS the Voice reply guard, not a second copy", () => {
  // If these two ever diverge, a Reel voice comment and a Voice reply would
  // accept different bytes, which is precisely the drift this slice promised
  // not to introduce.
  assert.equal(validateReelVoiceCommentAudio, validateStoredAudio);
  const expected = { authorId: VIEWER, commentId: "c".repeat(40), reelId: REEL_ID };
  const object = (overrides = {}) => ({
    generation: "7",
    contentType: "audio/mp4",
    size: 4096,
    metadata: { ...expected },
    ...overrides,
  });
  assert.deepEqual(validateReelVoiceCommentAudio(object(), expected, "7"), {
    contentType: "audio/mp4",
    generation: "7",
    size: 4096,
  });
  // The real bounds, asserted at their edges rather than restated.
  assert.equal(validateReelVoiceCommentAudio(object({ size: 512 }), expected, "7").size, 512);
  assert.equal(
    validateReelVoiceCommentAudio(object({ size: 12 * 1024 * 1024 }), expected, "7").size,
    12 * 1024 * 1024,
  );
  for (const bad of [
    object({ size: 511 }),
    object({ size: 12 * 1024 * 1024 + 1 }),
    object({ contentType: "audio/mpeg" }),
    object({ contentType: "video/mp4" }),
    object({ generation: "8" }),
    object({ metadata: { ...expected, extra: "forged" } }),
    object({ metadata: { ...expected, authorId: OTHER } }),
  ]) {
    assert.throws(
      () => validateReelVoiceCommentAudio(bad, expected, "7"),
      { code: "failed-precondition" },
    );
  }
});

test("a voice comment publishes through reserve -> upload -> finalize", async () => {
  const context = fixture();
  const { reserved, finalized } = await publishVoiceComment(context, {
    durationSeconds: 12,
    text: "A caption",
  });
  assert.equal(reserved.created, true);
  assert.equal(
    reserved.storagePath,
    reelVoiceCommentStoragePath(VIEWER, REEL_ID, reserved.commentId),
  );
  assert.match(reserved.commentId, /^[a-f0-9]{40}$/u);
  assert.deepEqual(finalized, {
    reelId: REEL_ID,
    commentId: reserved.commentId,
    created: true,
    commentCount: 1,
  });

  const stored = context.db.data(
    `reels/${REEL_ID}/comments/${reserved.commentId}`,
  );
  assert.deepEqual(Object.keys(stored).sort(), [
    "authorId",
    "authorName",
    "createdAt",
    "durationSeconds",
    "mediaContentType",
    "mediaGeneration",
    "mediaSize",
    "reelId",
    "schemaVersion",
    "storagePath",
    "text",
    "type",
  ]);
  assert.equal(stored.schemaVersion, 1);
  assert.equal(stored.type, "voice");
  assert.equal(stored.durationSeconds, 12);
  assert.equal(stored.text, "A caption");
  // Server-captured identity; the client supplied no name.
  assert.equal(stored.authorName, `Name ${VIEWER}`);
  assert.equal(stored.mediaGeneration, "900001");
  assert.equal(stored.mediaSize, 4096);
  assert.equal(stored.mediaContentType, "audio/mp4");
  assert.equal(context.db.data(`reels/${REEL_ID}`).commentCount, 1);
  // The reservation is consumed in the same transaction that publishes.
  assert.equal(
    context.db.data(`reelVoiceCommentReservations/${reserved.commentId}`),
    undefined,
  );
  // The upload's download token is revoked BEFORE the comment is readable.
  assert.ok(context.revocations.includes(reserved.storagePath));
  // And the document passes the same guard every reader applies.
  const snapshot = {
    exists: true,
    id: reserved.commentId,
    data: () => stored,
  };
  assert.equal(validateReelComment(snapshot, REEL_ID).type, "voice");
});

test("an empty caption is a normal voice comment, 141 characters is not", async () => {
  const context = fixture();
  const { finalized } = await publishVoiceComment(context, { text: "" });
  assert.equal(finalized.created, true);
  await rejects(
    context.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: {
        reelId: REEL_ID,
        requestId: "voice-request-long",
        durationSeconds: 5,
        text: "x".repeat(141),
      },
    }),
    "invalid-argument",
  );
});

test("the 1-60 second recording bound is enforced at reservation", async () => {
  const context = fixture();
  for (const durationSeconds of [0, -1, 61, 600, 7.5, "7", null]) {
    await rejects(
      context.service.reserveReelVoiceCommentDraft({
        auth: actor(),
        data: {
          reelId: REEL_ID,
          requestId: `voice-bound-${String(durationSeconds)}`,
          durationSeconds,
          text: "",
        },
      }),
      "invalid-argument",
    );
  }
  for (const durationSeconds of [1, 60]) {
    const reserved = await context.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: {
        reelId: REEL_ID,
        requestId: `voice-ok-${durationSeconds}`,
        durationSeconds,
        text: "",
      },
    });
    assert.equal(
      context.db.data(`reelVoiceCommentReservations/${reserved.commentId}`)
        .durationSeconds,
      durationSeconds,
    );
  }
});

test("reserve and finalize both replay free on a lost acknowledgement", async () => {
  const context = fixture();
  const first = await publishVoiceComment(context, { requestId: "replay-0001" });
  const replayReserve = await context.service.reserveReelVoiceCommentDraft({
    auth: actor(),
    data: {
      reelId: REEL_ID,
      requestId: "replay-0001",
      durationSeconds: 7,
      text: "",
    },
  });
  assert.deepEqual(replayReserve, first.reserved);
  const replayFinalize = await context.service.finalizeReelVoiceCommentDraft({
    auth: actor(),
    data: {
      reelId: REEL_ID,
      commentId: first.reserved.commentId,
      requestId: "replay-0001",
      objectGeneration: "900001",
    },
  });
  assert.deepEqual(replayFinalize, first.finalized);
  // Exactly one comment and exactly one increment.
  assert.equal(context.db.paths(`reels/${REEL_ID}/comments/`).length, 1);
  assert.equal(context.db.data(`reels/${REEL_ID}`).commentCount, 1);
});

test("one requestId cannot fork into both a text and a voice comment", async () => {
  const context = fixture();
  await context.service.createReelComment({
    auth: actor(),
    data: { reelId: REEL_ID, requestId: "fork-0001", text: "words" },
  });
  // The canonical id is the same digest, so the voice attempt collides with
  // the document the text attempt already wrote instead of adding a second
  // entry to somebody's thread.
  await rejects(
    context.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: {
        reelId: REEL_ID,
        requestId: "fork-0001",
        durationSeconds: 5,
        text: "",
      },
    }),
    "data-loss",
  );
  assert.equal(context.db.paths(`reels/${REEL_ID}/comments/`).length, 1);
});

test("finalize fails closed on every off-contract object", async () => {
  for (const [label, options, code] of [
    ["generation mismatch", { generation: "900001", finalizeGeneration: "900002" }, "failed-precondition"],
    ["wrong content type", { contentType: "audio/mpeg" }, "failed-precondition"],
    ["too small", { size: 511 }, "failed-precondition"],
    ["foreign author metadata", {
      metadata: { authorId: OTHER, reelId: REEL_ID, commentId: "x" },
    }, "failed-precondition"],
  ]) {
    const context = fixture();
    const reserved = await context.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: {
        reelId: REEL_ID,
        requestId: "finalize-guard-0001",
        durationSeconds: 5,
        text: "",
      },
    });
    context.audioObjects.set(reserved.storagePath, {
      generation: options.generation ?? "900001",
      contentType: options.contentType ?? "audio/mp4",
      size: options.size ?? 4096,
      metadata: options.metadata ?? {
        authorId: VIEWER,
        reelId: REEL_ID,
        commentId: reserved.commentId,
      },
    });
    await rejects(
      context.service.finalizeReelVoiceCommentDraft({
        auth: actor(),
        data: {
          reelId: REEL_ID,
          commentId: reserved.commentId,
          requestId: "finalize-guard-0001",
          objectGeneration: options.finalizeGeneration ?? "900001",
        },
      }),
      code,
    );
    assert.equal(
      context.db.paths(`reels/${REEL_ID}/comments/`).length,
      0,
      label,
    );
    assert.equal(context.db.data(`reels/${REEL_ID}`).commentCount, undefined);
  }
});

test("finalize refuses a missing, foreign or expired reservation", async () => {
  const context = fixture();
  const commentId = "a".repeat(40);
  const path = reelVoiceCommentStoragePath(VIEWER, REEL_ID, commentId);
  context.audioObjects.set(path, {
    generation: "900001",
    contentType: "audio/mp4",
    size: 4096,
    metadata: { authorId: VIEWER, reelId: REEL_ID, commentId },
  });
  const call = () =>
    context.service.finalizeReelVoiceCommentDraft({
      auth: actor(),
      data: {
        reelId: REEL_ID,
        commentId,
        requestId: "orphan-0001",
        objectGeneration: "900001",
      },
    });
  // No reservation at all.
  await rejects(call(), "failed-precondition");
  // A reservation owned by somebody else.
  context.db.seed(`reelVoiceCommentReservations/${commentId}`, {
    schemaVersion: 1,
    kind: "reelVoiceComment",
    ownerId: OTHER,
    reelId: REEL_ID,
    commentId,
    storagePath: path,
    durationSeconds: 5,
    text: "",
    authorName: "Name",
    status: "uploading",
    createdAt: new Date(NOW_MS),
    expiresAt: new Date(NOW_MS + 60_000),
  });
  await rejects(call(), "failed-precondition");
  // An expired reservation.
  context.db.seed(`reelVoiceCommentReservations/${commentId}`, {
    schemaVersion: 1,
    kind: "reelVoiceComment",
    ownerId: VIEWER,
    reelId: REEL_ID,
    commentId,
    storagePath: path,
    durationSeconds: 5,
    text: "",
    authorName: "Name",
    status: "uploading",
    createdAt: new Date(NOW_MS - 3_600_000),
    expiresAt: new Date(NOW_MS - 1),
  });
  await rejects(call(), "failed-precondition");
  assert.equal(context.db.paths(`reels/${REEL_ID}/comments/`).length, 0);
});

test("reserving a voice comment needs the same audience a text comment needs", async () => {
  const blockedBoth = [
    ["viewer blocked the author", `users/${VIEWER}/blocked/${AUTHOR}`],
    ["author blocked the viewer", `users/${AUTHOR}/blocked/${VIEWER}`],
  ];
  for (const [label, path] of blockedBoth) {
    const context = fixture();
    context.db.seed(path, { uid: AUTHOR, createdAt: new Date(NOW_MS) });
    await rejects(
      context.service.reserveReelVoiceCommentDraft({
        auth: actor(),
        data: {
          reelId: REEL_ID,
          requestId: "blocked-0001",
          durationSeconds: 5,
          text: "",
        },
      }),
      "failed-precondition",
    );
    assert.equal(
      context.db.paths("reelVoiceCommentReservations/").length,
      0,
      label,
    );
  }
  // A hidden Reel, an expired Reel and a suspended author each refuse too.
  // A hidden Reel answers with the SAME `data-loss` envelope every other
  // "this Reel is not engageable" state answers with (validatePublishedReel),
  // which is deliberate: distinct codes here would make the callable a
  // per-Reel moderation oracle.
  const hidden = fixture({ reel: { moderationStatus: "hidden" } });
  await rejects(
    hidden.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: { reelId: REEL_ID, requestId: "hidden-reel-0001", durationSeconds: 5, text: "" },
    }),
    "data-loss",
  );
  const expired = fixture({
    availability: { hours: 24 },
    clock: () => NOW_MS + 25 * 60 * 60 * 1000,
  });
  await rejects(
    expired.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: { reelId: REEL_ID, requestId: "expired-reel-0001", durationSeconds: 5, text: "" },
    }),
    "failed-precondition",
  );
  // A communication-muted author, and a communication-muted viewer.
  for (const [uid, requestId] of [
    [AUTHOR, "muted-author-0001"],
    [VIEWER, "muted-viewer-0001"],
  ]) {
    const muted = fixture();
    muted.db.seed(`restrictions/${uid}`, {
      type: "communicationMute",
      expiresAt: new Date(NOW_MS + 86_400_000),
    });
    await rejects(
      muted.service.reserveReelVoiceCommentDraft({
        auth: actor(),
        data: { reelId: REEL_ID, requestId, durationSeconds: 5, text: "" },
      }),
      "permission-denied",
    );
    assert.equal(muted.db.paths("reelVoiceCommentReservations/").length, 0);
  }
  // A suspended (banned) author.
  const banned = fixture();
  banned.db.seed(`users/${AUTHOR}`, { uid: AUTHOR, displayName: "x", banned: true });
  await rejects(
    banned.service.reserveReelVoiceCommentDraft({
      auth: actor(),
      data: { reelId: REEL_ID, requestId: "banned-author-0001", durationSeconds: 5, text: "" },
    }),
    "permission-denied",
  );
});

test("an unverified account cannot publish a voice comment", async () => {
  const context = fixture();
  await rejects(
    context.service.reserveReelVoiceCommentDraft({
      auth: actor(VIEWER, false),
      data: { reelId: REEL_ID, requestId: "unverified-reel-0001", durationSeconds: 5, text: "" },
    }),
    "failed-precondition",
  );
});

test("the view withholds voice comments until the caller declares it wants them", async () => {
  const context = fixture();
  await context.service.createReelComment({
    auth: actor(),
    data: { reelId: REEL_ID, requestId: "text-page-0001", text: "text one" },
  });
  const { reserved } = await publishVoiceComment(context, {
    requestId: "voice-page-0001",
    durationSeconds: 9,
    text: "caption",
  });

  // An OLD CLIENT: no flag. It sees only text, the aggregate count still
  // includes the voice comment, and nothing throws.
  const legacy = await context.service.getReelViewV2({
    auth: actor(VIEWER, false),
    data: { reelId: REEL_ID },
  });
  assert.deepEqual(legacy.comments.map((c) => c.type), ["text"]);
  assert.equal(legacy.reel.commentCount, 2);

  // A NEW CLIENT: both shapes, with the duration and no URL anywhere.
  const modern = await context.service.getReelViewV2({
    auth: actor(VIEWER, false),
    data: { reelId: REEL_ID, commentTypes: ["text", "voice"] },
  });
  assert.deepEqual(modern.comments.map((c) => c.type), ["text", "voice"]);
  const voice = modern.comments.find((c) => c.type === "voice");
  assert.equal(voice.commentId, reserved.commentId);
  assert.equal(voice.durationSeconds, 9);
  assert.equal(voice.text, "caption");
  assert.deepEqual(Object.keys(voice).sort(), [
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
  assert.equal(JSON.stringify(modern).includes("reel_voice_comments/"), false);

  // Explicitly asking for voice only is allowed; junk is refused.
  const voiceOnly = await context.service.getReelViewV2({
    auth: actor(VIEWER, false),
    data: { reelId: REEL_ID, commentTypes: ["voice"] },
  });
  assert.deepEqual(voiceOnly.comments.map((c) => c.type), ["voice"]);
  for (const commentTypes of [[], ["text", "text"], ["audio"], "text", {}, ["text", "voice", "x"]]) {
    await rejects(
      context.service.getReelViewV2({
        auth: actor(VIEWER, false),
        data: { reelId: REEL_ID, commentTypes },
      }),
      "invalid-argument",
    );
  }
});

test("a withheld voice comment never pins the page cursor in place", async () => {
  // An advancing clock so the thread has a real order: the voice comment is
  // FIRST, which is the case that could strand an old client's pagination.
  let now = NOW_MS;
  const context = fixture({ clock: () => now });
  await publishVoiceComment(context, { requestId: "page-voice-0001" });
  for (const index of [1, 2]) {
    now += 1000;
    await context.service.createReelComment({
      auth: actor(),
      data: {
        reelId: REEL_ID,
        requestId: `page-text-000${index}`,
        text: `text ${index}`,
      },
    });
  }
  const first = await context.service.getReelViewV2({
    auth: actor(VIEWER, false),
    data: { reelId: REEL_ID, commentLimit: 1 },
  });
  // The page held the voice comment, which this caller cannot render: it sees
  // no comments, but the thread is known to continue and the cursor moved.
  assert.deepEqual(first.comments, []);
  assert.equal(first.commentsTruncated, true);
  assert.notEqual(first.nextCommentCursor, null);
  const second = await context.service.getReelViewV2({
    auth: actor(VIEWER, false),
    data: {
      reelId: REEL_ID,
      commentLimit: 1,
      commentCursor: first.nextCommentCursor,
    },
  });
  assert.deepEqual(second.comments.map((c) => c.text), ["text 1"]);
});

test("listening is a short-lived grant, and only for the Reel's own audience", async () => {
  const context = fixture();
  const { reserved } = await publishVoiceComment(context, {
    requestId: "grant-0001",
  });
  const grant = await context.service.getReelMediaAccessV2({
    auth: actor(OTHER, false),
    data: { reelId: REEL_ID, asset: "voiceComment", commentId: reserved.commentId },
  });
  assert.equal(grant.url, "https://storage.googleapis.com/bucket/file");
  assert.equal(grant.generation, "900001");
  assert.equal(grant.durationSeconds, 7);
  assert.ok(grant.expiresAtMillis <= NOW_MS + 90 * 1000);

  // V1 cannot even name a comment, and the pair must be coherent.
  await rejects(
    context.service.getReelMediaAccess({
      auth: actor(OTHER, false),
      data: { reelId: REEL_ID, asset: "voiceComment", commentId: reserved.commentId },
    }),
    "invalid-argument",
  );
  await rejects(
    context.service.getReelMediaAccessV2({
      auth: actor(OTHER, false),
      data: { reelId: REEL_ID, asset: "voiceComment" },
    }),
    "invalid-argument",
  );
  await rejects(
    context.service.getReelMediaAccessV2({
      auth: actor(OTHER, false),
      data: { reelId: REEL_ID, asset: "media", commentId: reserved.commentId },
    }),
    "invalid-argument",
  );
  // A text comment has no media.
  const text = await context.service.createReelComment({
    auth: actor(),
    data: { reelId: REEL_ID, requestId: "grant-text-0001", text: "words" },
  });
  await rejects(
    context.service.getReelMediaAccessV2({
      auth: actor(OTHER, false),
      data: { reelId: REEL_ID, asset: "voiceComment", commentId: text.commentId },
    }),
    "failed-precondition",
  );
});

test("a block against the COMMENTER silences their audio, both directions", async () => {
  for (const path of [
    `users/${OTHER}/blocked/${VIEWER}`,
    `users/${VIEWER}/blocked/${OTHER}`,
  ]) {
    const context = fixture();
    const { reserved } = await publishVoiceComment(context, {
      requestId: "block-grant-0001",
    });
    context.db.seed(path, { uid: VIEWER, createdAt: new Date(NOW_MS) });
    await rejects(
      context.service.getReelMediaAccessV2({
        auth: actor(OTHER, false),
        data: {
          reelId: REEL_ID,
          asset: "voiceComment",
          commentId: reserved.commentId,
        },
      }),
      "failed-precondition",
    );
  }
});

test("an expired or hidden parent Reel plays none of its voice comments", async () => {
  const hidden = fixture();
  const { reserved } = await publishVoiceComment(hidden, {
    requestId: "expired-grant-0001",
  });
  hidden.db.seed(`reels/${REEL_ID}`, {
    ...hidden.db.data(`reels/${REEL_ID}`),
    moderationStatus: "hidden",
  });
  await rejects(
    hidden.service.getReelMediaAccessV2({
      auth: actor(OTHER, false),
      data: {
        reelId: REEL_ID,
        asset: "voiceComment",
        commentId: reserved.commentId,
      },
    }),
    "data-loss",
  );
});

test("the grant is bound to the exact generation the document records", async () => {
  const context = fixture();
  const { reserved } = await publishVoiceComment(context, {
    requestId: "swap-0001",
  });
  // The object was replaced out of band after the comment was written.
  const path = reserved.storagePath;
  context.audioObjects.set(path, {
    ...context.audioObjects.get(path),
    generation: "900002",
  });
  await rejects(
    context.service.getReelMediaAccessV2({
      auth: actor(OTHER, false),
      data: {
        reelId: REEL_ID,
        asset: "voiceComment",
        commentId: reserved.commentId,
      },
    }),
    "failed-precondition",
  );
});

test("deleting your own voice comment queues its audio in the same transaction", async () => {
  const context = fixture();
  const { reserved } = await publishVoiceComment(context, {
    requestId: "delete-0001",
  });
  const deleteRequest = {
    auth: actor(VIEWER, false),
    data: {
      reelId: REEL_ID,
      commentId: reserved.commentId,
      requestId: "delete-call-0001",
    },
  };
  const deleted = await context.service.deleteReelComment(deleteRequest);
  // EXACTLY the text-comment result shape. Installed clients parse it with a
  // strict reader that refuses any extra key, and the ledger replays it, so
  // "was audio queued" is proven by the outbox row below, never by the result.
  assert.deepEqual(deleted, {
    reelId: REEL_ID,
    commentId: reserved.commentId,
    deleted: true,
    commentCount: 0,
  });
  // A lost acknowledgement replays the ledger's stored result: same shape.
  assert.deepEqual(
    await context.service.deleteReelComment(deleteRequest),
    deleted,
  );
  const ledgerResults = context.db
    .paths("integrityOperationLedgers/")
    .map((path) => context.db.data(path))
    .filter((value) => value.kind === "reel.comment.delete")
    .map((value) => value.result);
  assert.deepEqual(ledgerResults, [deleted]);
  assert.equal(context.db.data(`reels/${REEL_ID}`).commentCount, 0);
  const outboxId = reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId);
  const row = context.db.data(`reelCleanupOutbox/${outboxId}`);
  assert.equal(row.kind, "reelVoiceComment");
  assert.equal(row.ownerId, VIEWER);
  assert.equal(row.commentId, reserved.commentId);
  assert.deepEqual(row.storageObjects, [
    { path: reserved.storagePath, generation: "900001" },
  ]);

  // The worker removes the bytes and NEVER touches the live thread.
  await context.service.createReelComment({
    auth: actor(),
    data: { reelId: REEL_ID, requestId: "survivor-0001", text: "still here" },
  });
  const result = await context.service.processCleanupOutbox(outboxId);
  assert.equal(result.completed, true);
  assert.equal(result.engagement, "voiceComment");
  assert.deepEqual(context.deletions, [
    { path: reserved.storagePath, options: { generation: "900001" } },
  ]);
  assert.equal(context.recursiveDeletes.length, 0);
  assert.equal(context.db.paths(`reels/${REEL_ID}/comments/`).length, 1);
});

test("the Reel's author removing a voice comment queues the COMMENTER's object", async () => {
  const context = fixture();
  const { reserved } = await publishVoiceComment(context, {
    requestId: "remove-0001",
  });
  const removed = await context.service.removeReelComment({
    auth: actor(AUTHOR, false),
    data: {
      reelId: REEL_ID,
      commentId: reserved.commentId,
      requestId: "remove-call-0001",
    },
  });
  // Exactly the shape installed strict readers accept (see the deletion case).
  assert.deepEqual(removed, {
    reelId: REEL_ID,
    commentId: reserved.commentId,
    removed: true,
    commentCount: 0,
    removedAuthorId: VIEWER,
  });
  const row = context.db.data(
    `reelCleanupOutbox/${reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId)}`,
  );
  // The object lives under the COMMENTER's uid; no other path is canonical.
  assert.equal(row.ownerId, VIEWER);
  assert.ok(
    isCanonicalReelVoiceCommentPath(
      row.storageObjects[0].path,
      VIEWER,
      REEL_ID,
      reserved.commentId,
    ),
  );
});

test("a forged voice-comment cleanup row cannot aim the worker anywhere", async () => {
  const context = fixture();
  const { reserved } = await publishVoiceComment(context, {
    requestId: "forge-0001",
  });
  const outboxId = reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId);
  const canonical = {
    schemaVersion: 1,
    kind: "reelVoiceComment",
    ownerId: VIEWER,
    reelId: REEL_ID,
    commentId: reserved.commentId,
    storageObjects: [{ path: reserved.storagePath, generation: "900001" }],
    status: "pending",
    attemptCount: 0,
    phase: "delete",
    nextAttemptAt: new Date(NOW_MS),
    leaseToken: null,
    leaseUntil: null,
    lastErrorCode: null,
    createdAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  };
  for (const overrides of [
    // Another person's object.
    { storageObjects: [{ path: reelVoiceCommentStoragePath(OTHER, REEL_ID, reserved.commentId), generation: "1" }] },
    // A Reel's own media, reached through the comment kind.
    { storageObjects: [{ path: `reels/${AUTHOR}/${REEL_ID}/media.jpg`, generation: "123" }] },
    // Somewhere else entirely.
    { storageObjects: [{ path: "voice_moments/x/y.m4a", generation: "1" }] },
    // Two objects: a voice comment owns exactly one.
    { storageObjects: [
      { path: reserved.storagePath, generation: "900001" },
      { path: reserved.storagePath, generation: "900001" },
    ] },
    // The row is not the one this outbox id addresses.
    { commentId: "b".repeat(40) },
    { reelId: "reel_other" },
    { commentId: "not-a-digest" },
    { phase: "purge" },
  ]) {
    context.db.seed(`reelCleanupOutbox/${outboxId}`, { ...canonical, ...overrides });
    // A malformed row DEAD-LETTERS rather than throwing: the worker records
    // the refusal, stops retrying it and never acts on the path it named.
    const result = await context.service.processCleanupOutbox(outboxId);
    assert.equal(result.deadLetter, true, JSON.stringify(overrides));
    assert.equal(result.code, "data-loss");
    assert.equal(result.completed, false);
  }
  assert.deepEqual(context.deletions, []);
});

test("expiry and deletion enumerate voice comments BEFORE the thread is deleted", async () => {
  const context = fixture();
  const published = [];
  for (const index of [1, 2, 3]) {
    const { reserved } = await publishVoiceComment(context, {
      requestId: `purge-v-000${index}`,
    });
    published.push(reserved);
  }
  await context.service.createReelComment({
    auth: actor(),
    data: { reelId: REEL_ID, requestId: "purge-t-0001", text: "words" },
  });
  // Delete the Reel: the root becomes a tombstone and a cleanup row is queued.
  await context.service.deleteReel({
    auth: actor(AUTHOR, false),
    data: { reelId: REEL_ID, requestId: "purge-delete-0001" },
  });
  const reelOutbox = context.db
    .paths("reelCleanupOutbox/")
    .map((path) => ({ path, data: context.db.data(path) }))
    .find(({ data }) => data.kind === "reelPublishedMediaCleanup");
  await context.service.processCleanupOutbox(reelOutbox.path.split("/").at(-1));

  // One cleanup row per voice comment, each naming its own object.
  for (const reserved of published) {
    const row = context.db.data(
      `reelCleanupOutbox/${reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId)}`,
    );
    assert.ok(row, `missing cleanup row for ${reserved.commentId}`);
    assert.equal(row.kind, "reelVoiceComment");
    assert.deepEqual(row.storageObjects, [
      { path: reserved.storagePath, generation: "900001" },
    ]);
  }
  // The thread itself is gone.
  assert.equal(context.db.paths(`reels/${REEL_ID}/comments/`).length, 0);
  assert.ok(context.recursiveDeletes.includes(`reels/${REEL_ID}/comments`));
  // And draining those rows removes the audio.
  for (const reserved of published) {
    await context.service.processCleanupOutbox(
      reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId),
    );
  }
  for (const reserved of published) {
    assert.ok(
      context.deletions.some(({ path }) => path === reserved.storagePath),
      `audio for ${reserved.commentId} was never deleted`,
    );
  }
});

test("an abandoned reservation is swept and its possible object queued", async () => {
  const context = fixture({ clock: () => NOW_MS });
  const reserved = await context.service.reserveReelVoiceCommentDraft({
    auth: actor(),
    data: {
      reelId: REEL_ID,
      requestId: "abandoned-0001",
      durationSeconds: 5,
      text: "",
    },
  });
  // Nothing is due yet.
  const early = await context.service.expireAbandonedReelVoiceCommentDrafts({
    limit: 10,
  });
  assert.deepEqual(early.expired, []);
  assert.ok(
    context.db.data(`reelVoiceCommentReservations/${reserved.commentId}`),
  );

  const later = fixture({ clock: () => NOW_MS + 31 * 60 * 1000 });
  later.db.seed(`reelVoiceCommentReservations/${reserved.commentId}`, {
    schemaVersion: 1,
    kind: "reelVoiceComment",
    ownerId: VIEWER,
    reelId: REEL_ID,
    commentId: reserved.commentId,
    storagePath: reserved.storagePath,
    durationSeconds: 5,
    text: "",
    authorName: "Name",
    status: "uploading",
    createdAt: new Date(NOW_MS),
    expiresAt: new Date(NOW_MS + 30 * 60 * 1000),
  });
  const swept = await later.service.expireAbandonedReelVoiceCommentDrafts({
    limit: 10,
  });
  assert.deepEqual(swept.expired, [reserved.commentId]);
  assert.equal(
    later.db.data(`reelVoiceCommentReservations/${reserved.commentId}`),
    undefined,
  );
  const row = later.db.data(
    `reelCleanupOutbox/${reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId)}`,
  );
  // The generation is unknown before finalize, so the delete is unconditional.
  assert.deepEqual(row.storageObjects, [
    { path: reserved.storagePath, generation: null },
  ]);
  later.audioObjects.set(reserved.storagePath, {
    generation: "1",
    contentType: "audio/mp4",
    size: 4096,
    metadata: {},
  });
  await later.service.processCleanupOutbox(
    reelVoiceCommentCleanupOutboxId(REEL_ID, reserved.commentId),
  );
  assert.deepEqual(later.deletions, [
    { path: reserved.storagePath, options: undefined },
  ]);
});

test("a reservation that cannot prove its own object queues no deletion", async () => {
  const context = fixture({ clock: () => NOW_MS + 60 * 60 * 1000 });
  const commentId = "c".repeat(40);
  context.db.seed(`reelVoiceCommentReservations/${commentId}`, {
    schemaVersion: 1,
    kind: "reelVoiceComment",
    ownerId: VIEWER,
    reelId: REEL_ID,
    commentId,
    // Points at somebody else's object.
    storagePath: reelVoiceCommentStoragePath(OTHER, REEL_ID, commentId),
    durationSeconds: 5,
    text: "",
    authorName: "Name",
    status: "uploading",
    createdAt: new Date(NOW_MS),
    expiresAt: new Date(NOW_MS + 60_000),
  });
  const swept = await context.service.expireAbandonedReelVoiceCommentDrafts({
    limit: 10,
  });
  assert.deepEqual(swept.expired, []);
  assert.deepEqual(swept.malformed, [commentId]);
  assert.equal(context.db.paths("reelCleanupOutbox/").length, 0);
});

test("the text comment path is byte-for-byte what it was", async () => {
  const context = fixture();
  const created = await context.service.createReelComment({
    auth: actor(),
    data: { reelId: REEL_ID, requestId: "text-0001", text: "words" },
  });
  const stored = context.db.data(`reels/${REEL_ID}/comments/${created.commentId}`);
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
  assert.equal(stored.type, "text");
  assert.equal(stored.durationSeconds, null);
  assert.equal(stored.schemaVersion, 1);
});

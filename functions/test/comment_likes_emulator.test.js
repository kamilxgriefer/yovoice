// ADR-230 comment likes on a real Firestore (the emulator), with the
// production SDK's FieldPath, Timestamp, transactions and getAll: the Yeel
// toggle under concurrency, and getReelViewV2's includeCommentLikes, whose
// two production queries (`commentKey in [...]` on the counters and
// `userId == viewer && commentKey in [...]` on the edges) are exactly the
// shapes the commentLikes composite index serves. The Voice side runs in
// moment_integrity.test.js, which is an emulator suite too.
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const assert = require("node:assert/strict");
const { after, test } = require("node:test");
const { deleteApp, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");

const { REEL_COMMENT_SCHEMA_VERSION } = require("../reels/engagement");
const { createReelService } = require("../reels/service");

// Its own emulator namespace (the moment_expiry.test.js reasoning): this
// suite seeds published, permanent Voice Moments and Yeels, and
// moment_integrity.test.js asserts on whole-collection feed results in the
// shared project id that `firebase emulators:exec --project` exports to every
// suite. The emulator keeps one database per project id.
const app = initializeApp(
  { projectId: `${process.env.GCLOUD_PROJECT}-comment-likes` },
  `comment-likes-${process.pid}`,
);
const db = getFirestore(app);
const RUN = `${process.pid}-${Date.now()}`;
const NOW_MS = Date.now();
const quiet = { warn() {}, info() {}, debug() {}, error() {} };

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

function publicProfile(uid) {
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
    updatedAt: Timestamp.fromMillis(NOW_MS - 60_000),
    username: null,
    usernameSearch: null,
    website: null,
  };
}

async function seed(entries) {
  const batch = db.batch();
  for (const [path, data] of entries) batch.set(db.doc(path), data);
  await batch.commit();
}

test("Yeel comment likes toggle exactly once and the flagged view reads them back", async () => {
  const author = `cle-author-${RUN}`;
  const viewers = [0, 1, 2].map((index) => `cle-viewer-${index}-${RUN}`);
  const reelId = `cle_reel_${RUN}`.replaceAll("-", "_");
  const firstComment = "e".repeat(40);
  const secondComment = "f".repeat(40);
  const at = Timestamp.fromMillis(NOW_MS - 3_600_000);
  const comment = (commentId, createdAt, text) => [
    `reels/${reelId}/comments/${commentId}`,
    {
      schemaVersion: REEL_COMMENT_SCHEMA_VERSION,
      reelId,
      authorId: author,
      authorName: "Creator",
      durationSeconds: null,
      text,
      type: "text",
      createdAt,
    },
  ];
  await seed([
    ...[author, ...viewers].flatMap((uid) => [
      [`users/${uid}`, { role: "user" }],
      [`publicProfiles/${uid}`, publicProfile(uid)],
    ]),
    [`reels/${reelId}`, {
      schemaVersion: 1,
      status: "published",
      moderationStatus: "visible",
      authorId: author,
      authorName: "Creator",
      media: {
        kind: "image",
        contentType: "image/jpeg",
        size: 1024,
        generation: "123",
        durationMs: 0,
        storagePath: `reels/${author}/${reelId}/media.jpg`,
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
      sortKey: `${String(NOW_MS).padStart(13, "0")}_${reelId}`,
      publishedAt: at,
      updatedAt: at,
      commentCount: 2,
    }],
    comment(firstComment, at, "first"),
    comment(secondComment, Timestamp.fromMillis(NOW_MS - 3_000_000), "second"),
  ]);
  const reels = createReelService({
    db,
    FieldPath,
    Timestamp,
    storage: {
      getMetadata: async () => ({}),
      readHeader: async () => Buffer.alloc(0),
      revokeDownloadTokens: async () => {},
      getSignedReadUrl: async () => "",
      deleteObject: async () => {},
    },
    log: quiet,
  });
  const toggle = (uid, commentId, liked, requestId) => reels.setReelCommentLikeV1({
    auth: { uid, token: { email_verified: true } },
    data: { commentId, liked, reelId, requestId },
  });

  const results = await Promise.all(viewers.map((uid, index) =>
    toggle(uid, firstComment, true, `cle-like-${index}-${RUN}`)));
  assert.deepEqual(results.map((result) => result.likeCount).sort(), [1, 2, 3]);
  await toggle(viewers[0], secondComment, true, `cle-like-second-${RUN}`);
  await toggle(viewers[2], firstComment, false, `cle-unlike-${RUN}`);
  const counter = await db
    .doc(`commentLikeCounters/r:${reelId}:${firstComment}`)
    .get();
  assert.equal(counter.data().likeCount, 2);

  const view = (uid, data = {}) => reels.getReelViewV2({
    auth: { uid, token: {} },
    data: { reelId, ...data },
  });
  const unflagged = await view(viewers[0]);
  assert.equal(Object.hasOwn(unflagged, "commentLikes"), false);
  const flagged = await view(viewers[0], { includeCommentLikes: true });
  assert.deepEqual(flagged.commentLikes, {
    [firstComment]: { likeCount: 2, callerLiked: true },
    [secondComment]: { likeCount: 1, callerLiked: true },
  });
  const other = await view(viewers[2], { includeCommentLikes: true });
  assert.deepEqual(other.commentLikes, {
    [firstComment]: { likeCount: 2, callerLiked: false },
    [secondComment]: { likeCount: 1, callerLiked: false },
  });
  // The comment documents keep their exact stored shape.
  const stored = await db.doc(`reels/${reelId}/comments/${firstComment}`).get();
  assert.deepEqual(Object.keys(stored.data()).sort(), [
    "authorId",
    "authorName",
    "createdAt",
    "durationSeconds",
    "reelId",
    "schemaVersion",
    "text",
    "type",
  ]);
});

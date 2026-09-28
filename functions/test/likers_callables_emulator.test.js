// ADR-230: the three "See who liked" list callables end to end against a
// real Firestore (the emulator), with the production SDK's FieldPath,
// Timestamp and getAll: two pages per target through a real
// likerPageCursors document, the flat commentLikes store filtered by
// commentKey, and a real Servers V1 channel. Run with:
//   firebase emulators:exec --only firestore --project demo-yovoice \
//     "cd functions && node --test test/likers_callables_emulator.test.js"
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

const { createMomentIntegrityService, momentStoragePath } = require("../moments/integrity");
const { REEL_COMMENT_SCHEMA_VERSION } = require("../reels/engagement");
const { createReelService } = require("../reels/service");
const { createServerMessageReactionService } = require("../servers/message_reactions");
const { LIKERS_ACTIVATION_PATH } = require("../engagement/likers_activation");
const { seedServerMessaging } = require("./helpers/server_message_fixture");

// Its own emulator namespace (the moment_expiry.test.js reasoning): this
// suite seeds published, permanent Voice Moments and Yeels, and
// moment_integrity.test.js asserts on whole-collection feed results in the
// shared project id that `firebase emulators:exec --project` exports to every
// suite. The emulator keeps one database per project id.
const app = initializeApp(
  { projectId: `${process.env.GCLOUD_PROJECT}-likers-callables` },
  `likers-callables-${process.pid}`,
);
const db = getFirestore(app);
const RUN = `${process.pid}-${Date.now()}`;
const NOW_MS = Date.now();
const quiet = { warn() {}, info() {}, debug() {}, error() {} };

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

async function seed(entries) {
  for (let start = 0; start < entries.length; start += 400) {
    const batch = db.batch();
    for (const [path, data] of entries.slice(start, start + 400)) {
      batch.set(db.doc(path), data);
    }
    await batch.commit();
  }
}

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

function person(uid, user = {}) {
  return [
    [`users/${uid}`, { role: "user", ...user }],
    [`publicProfiles/${uid}`, publicProfile(uid)],
  ];
}

function viewer(uid) {
  return [
    ...person(uid),
    [`vipGrants/${uid}`, {
      source: "testerProgram",
      expiresAt: null,
      revoked: false,
      grantedBy: "emulator",
    }],
  ];
}

async function activate() {
  await db.doc(LIKERS_ACTIVATION_PATH).set({
    schemaVersion: 1,
    enabled: true,
    serverMessagesEnabled: true,
    updatedAt: Timestamp.fromMillis(NOW_MS - 1_000),
  });
}

// 36 likers, every third hides its likes (24 visible: a full page and 4);
// all 36 edges share ONE createdAt so only the __name__ tiebreak orders them.
// Returns the expected visible order.
function likers(prefix, edge) {
  const entries = [];
  const visible = [];
  const shared = Timestamp.fromMillis(NOW_MS - 60_000);
  for (let index = 0; index < 36; index += 1) {
    const uid = `${prefix}-${RUN}-${String(index).padStart(2, "0")}`;
    const hidden = index % 3 === 0;
    entries.push(...person(uid, hidden ? { likesHidden: true } : {}));
    entries.push(edge(uid, shared));
    if (!hidden) visible.push(uid);
  }
  return { entries, visible: visible.sort().reverse() };
}

async function everyPage(fetch) {
  const listed = [];
  let cursor = null;
  let pages = 0;
  do {
    const page = await fetch(cursor);
    assert.equal(page.hasMore, page.nextCursor !== null);
    listed.push(...page.likers.map((row) => row.userId));
    cursor = page.nextCursor;
    pages += 1;
  } while (cursor !== null && pages < 10);
  return { listed, pages };
}

test("listVoiceMomentLikersV1 pages a Moment and a comment on a real Firestore", async () => {
  await activate();
  const me = `vme-viewer-${RUN}`;
  const author = `vme-author-${RUN}`;
  const momentId = `vme-moment-${RUN}`;
  const commentId = `vme-comment-${RUN}`;
  const at = Timestamp.fromMillis(NOW_MS - 3_600_000);
  const moment = likers("vme-m", (uid, createdAt) => [
    `voiceMoments/${momentId}/likes/${uid}`,
    { schemaVersion: 1, userId: uid, momentId, createdAt },
  ]);
  const commentKey = `v:${momentId}:${commentId}`;
  const comment = likers("vme-c", (uid, createdAt) => [
    `commentLikes/${commentKey}:${uid}`,
    {
      schemaVersion: 1,
      parentKind: "voiceMoment",
      parentId: momentId,
      commentId,
      commentKey,
      userId: uid,
      createdAt,
    },
  ]);
  await seed([
    ...viewer(me),
    ...person(author),
    [`voiceMoments/${momentId}`, {
      audioUrl: null,
      authorId: author,
      authorName: "Author",
      authorPhotoUrl: null,
      caption: "",
      commentCount: 1,
      createdAt: at,
      durationSeconds: 10,
      isDeleted: false,
      isPublished: true,
      likeCount: 36,
      mediaContentType: "audio/mp4",
      mediaGeneration: "1001",
      mediaSize: 4096,
      publishedAt: at,
      replyToMomentId: null,
      schemaVersion: 2,
      status: "published",
      storagePath: momentStoragePath(author, momentId),
      updatedAt: at,
    }],
    [`voiceMoments/${momentId}/comments/${commentId}`, {
      audioUrl: null,
      authorId: author,
      authorName: "Author",
      authorPhotoUrl: null,
      createdAt: at,
      durationSeconds: null,
      mediaContentType: null,
      mediaGeneration: null,
      mediaSize: null,
      schemaVersion: 2,
      storagePath: null,
      text: "hello",
      type: "text",
    }],
    ...moment.entries,
    ...comment.entries,
  ]);
  const moments = createMomentIntegrityService({
    db,
    FieldPath,
    Timestamp,
    storage: {
      getMetadata: async () => ({}),
      getSignedReadUrl: async () => "",
      revokeDownloadTokens: async () => {},
    },
    logger: quiet,
  });
  const call = (data) => moments.listVoiceMomentLikersV1({
    auth: { uid: me, token: {} },
    data,
  });
  const momentPages = await everyPage((cursor) => call({
    momentId,
    ...(cursor ? { cursor } : {}),
  }));
  assert.deepEqual(momentPages.listed, moment.visible);
  assert.equal(momentPages.pages, 2);
  const commentPages = await everyPage((cursor) => call({
    momentId,
    commentId,
    ...(cursor ? { cursor } : {}),
  }));
  assert.deepEqual(commentPages.listed, comment.visible);
  assert.equal(commentPages.pages, 2);
});

test("listReelLikersV1 pages a Yeel and a comment on a real Firestore", async () => {
  await activate();
  const me = `rle-viewer-${RUN}`;
  const author = `rle-author-${RUN}`;
  const reelId = `rle_reel_${RUN}`;
  const commentId = `rle-comment-${RUN}`;
  const at = Timestamp.fromMillis(NOW_MS - 3_600_000);
  const reel = likers("rle-r", (uid, createdAt) => [
    `reels/${reelId}/likes/${uid}`,
    { schemaVersion: 1, userId: uid, reelId, createdAt },
  ]);
  const commentKey = `r:${reelId}:${commentId}`;
  const comment = likers("rle-c", (uid, createdAt) => [
    `commentLikes/${commentKey}:${uid}`,
    {
      schemaVersion: 1,
      parentKind: "reel",
      parentId: reelId,
      commentId,
      commentKey,
      userId: uid,
      createdAt,
    },
  ]);
  await seed([
    ...viewer(me),
    ...person(author, { profileVisibility: "private" }),
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
    }],
    [`reels/${reelId}/comments/${commentId}`, {
      schemaVersion: REEL_COMMENT_SCHEMA_VERSION,
      reelId,
      authorId: author,
      authorName: "Creator",
      durationSeconds: null,
      text: "hello",
      type: "text",
      createdAt: at,
    }],
    ...reel.entries,
    ...comment.entries,
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
  const call = (data) => reels.listReelLikersV1({ auth: { uid: me, token: {} }, data });
  const reelPages = await everyPage((cursor) => call({
    reelId,
    ...(cursor ? { cursor } : {}),
  }));
  assert.deepEqual(reelPages.listed, reel.visible);
  assert.equal(reelPages.pages, 2);
  const commentPages = await everyPage((cursor) => call({
    reelId,
    commentId,
    ...(cursor ? { cursor } : {}),
  }));
  assert.deepEqual(commentPages.listed, comment.visible);
  assert.equal(commentPages.pages, 2);
});

test("listServerChannelMessageReactorsV1 pages a real Servers V1 channel message", async () => {
  await activate();
  const seeded = await seedServerMessaging(db, Timestamp, { label: "lre", nowMs: NOW_MS });
  const me = seeded.users.member;
  await seed([
    [`publicProfiles/${me}`, publicProfile(me)],
    [`vipGrants/${me}`, {
      source: "testerProgram",
      expiresAt: null,
      revoked: false,
    }],
  ]);
  const reactions = {};
  const entries = [];
  const expected = [];
  for (let index = 0; index < 24; index += 1) {
    const uid = `lre-${RUN}-${String(index).padStart(2, "0")}`;
    entries.push(...person(uid));
    entries.push([`clubs/${seeded.serverId}/members/${uid}`, {
      userId: uid,
      displayName: uid,
      photoUrl: null,
      role: "member",
      isOnline: false,
      joinedAt: seeded.now,
      invitedBy: null,
      authorizationRevision: 1,
    }]);
    reactions[uid] = index % 2 === 0 ? "👍" : "❤️";
  }
  await seed(entries);
  const uids = Object.keys(reactions).sort();
  expected.push(
    ...uids.filter((uid) => reactions[uid] === "❤️"),
    ...uids.filter((uid) => reactions[uid] === "👍"),
  );
  const target = await seeded.message("text", { reactions });
  const service = createServerMessageReactionService({ db, Timestamp });
  const pages = await everyPage((cursor) => service.listServerChannelMessageReactorsV1({
    auth: { uid: me, token: {} },
    data: {
      serverId: seeded.serverId,
      channelId: target.channelId,
      messageId: target.id,
      ...(cursor ? { cursor } : {}),
    },
  }));
  assert.deepEqual(pages.listed, expected);
  assert.equal(pages.pages, 2);
});

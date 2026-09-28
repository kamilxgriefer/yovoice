// getPageV1 and getPagePostV1 (ADR-233 §2.5) against the Firestore emulator:
// the uniform pageUnavailable refusal, what the owner sees of their own
// Page, cursor pages without a header, followerCount from users/{P}, the
// Zdjęcia tab, the pinned post, the viewer flags (D13, D14) and a post with
// its comments.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-profile-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { createPagesReadService } = require("../pages/reads");
const {
  PAGE_COMMENT_VIEW_KEYS,
  PAGE_HEADER_KEYS,
  PAGE_POST_RESPONSE_KEYS,
  PAGE_RESPONSE_KEYS,
  PAGE_VIEWER_KEYS,
  encodeItemCursor,
} = require("../pages/views");
const {
  DAY_MS,
  clearActivation,
  commentDoc,
  freshUid,
  newCommentId,
  newPostId,
  pageDoc,
  photoMedia,
  postDoc,
  request,
  seedAccount,
  seedFollowEdge,
  seedPage,
  setActivation,
  silentLogger,
  testerGrant,
  voiceMedia,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const nowMs = 1_900_000_000_000;

function service() {
  return createPagesReadService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
}

function getPage(viewer, pageId, { tab = "wall", cursor = null, verified = true } = {}) {
  return service().getPageV1(request(viewer, { pageId, tab, cursor }, { verified }));
}

function getPost(viewer, postId, commentCursor = null) {
  return service().getPagePostV1(request(viewer, { postId, commentCursor }));
}

function unavailable(error) {
  assert.equal(error.code, "permission-denied");
  assert.equal(error.message, "This Page is unavailable.");
  assert.equal(error.details?.reason, "pageUnavailable");
  return true;
}

async function viewerAccount(options = {}) {
  const uid = freshUid("pgpv");
  await seedAccount(db, uid, nowMs, options);
  return uid;
}

async function pageWithPosts({ page = {}, user = {}, grant = testerGrant(), posts = [] } = {}) {
  const pageId = freshUid("pgpp");
  await seedPage(db, pageId, nowMs, { page, user, grant });
  const written = [];
  for (const [index, overrides] of posts.entries()) {
    const postId = newPostId();
    const media = overrides.kind === "photo"
      ? photoMedia(pageId, postId, 2)
      : overrides.kind === "voice" ? voiceMedia(pageId, postId) : [];
    const data = postDoc(pageId, postId, nowMs - (index + 1) * 1000, { media, ...overrides });
    await db.doc(`pagePosts/${postId}`).set(data);
    written.push(data);
  }
  return { pageId, posts: written };
}

beforeEach(() => setActivation(db));
after(() => clearActivation(db));

// ------------------------------------------------------------------ Page

test("every hidden Page answers the one uniform pageUnavailable", async () => {
  const viewer = await viewerAccount();
  const now = Timestamp.fromMillis(nowMs);
  const variants = [
    { page: { ownerPaused: true } },
    { page: { suspended: true, suspendedAt: now, suspensionReason: "spam" } },
    { page: { status: "hidden", lapsedAt: now } },
    { page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - 30 * DAY_MS) } },
    { user: { banned: true } },
  ];
  for (const variant of variants) {
    const { pageId } = await pageWithPosts(variant);
    await assert.rejects(getPage(viewer, pageId), unavailable, JSON.stringify(variant));
  }
  await assert.rejects(getPage(viewer, freshUid("pgmissing")), unavailable);
  const blockedByPage = await pageWithPosts();
  await db.doc(`users/${blockedByPage.pageId}/blocked/${viewer}`).set({ at: now });
  await assert.rejects(getPage(viewer, blockedByPage.pageId), unavailable);
  const blockedByViewer = await pageWithPosts();
  await db.doc(`users/${viewer}/blocked/${blockedByViewer.pageId}`).set({ at: now });
  await assert.rejects(getPage(viewer, blockedByViewer.pageId), unavailable);
  const malformed = await pageWithPosts();
  await db.doc(`pages/${malformed.pageId}`).update({ listed: true });
  await assert.rejects(getPage(viewer, malformed.pageId), unavailable);
  // An ordinary account without a Page: the same refusal (the resolver then
  // opens the personal profile).
  const person = await viewerAccount();
  await assert.rejects(getPage(viewer, person), unavailable);
  // The switch itself is not hidden behind the uniform refusal.
  await clearActivation(db);
  await assert.rejects(getPage(viewer, person), (error) =>
    error.details?.reason === "pagesNotEnabled");
});

test("a visitor's first page: exact header, viewer flags, pinned once, published only", async () => {
  const viewer = await viewerAccount();
  const { pageId, posts } = await pageWithPosts({
    user: { followerCount: 12 },
    posts: [
      {},
      { kind: "photo", text: "" },
      { status: "held", heldAt: Timestamp.fromMillis(nowMs) },
      { kind: "voice" },
    ],
  });
  const pinnedId = posts[3].postId;
  await db.doc(`pages/${pageId}`).update({ postCount: 3, listed: true, pinnedPostId: pinnedId,
    lastPostAt: Timestamp.fromMillis(nowMs) });
  await db.doc(`pagePosts/${pinnedId}/likes/${viewer}`).set({
    schemaVersion: 1, userId: viewer, postId: pinnedId, createdAt: Timestamp.fromMillis(nowMs),
  });
  const response = await getPage(viewer, pageId);
  assert.deepEqual(Object.keys(response).sort(), [...PAGE_RESPONSE_KEYS]);
  assert.deepEqual(Object.keys(response.page).sort(), [...PAGE_HEADER_KEYS]);
  assert.equal(response.page.followerCount, 12, "read from users/{P}");
  assert.equal(response.page.postCount, 3);
  assert.equal(response.page.state, "active");
  assert.equal(response.page.onYoVoiceSinceMs, nowMs);
  assert.deepEqual(Object.keys(response.viewer).sort(), [...PAGE_VIEWER_KEYS]);
  assert.deepEqual(response.viewer,
    { isOwner: false, following: false, canFollow: true, canMessage: true });
  assert.equal(response.pinned.postId, pinnedId);
  assert.equal(response.pinned.pinned, true);
  assert.equal(response.pinned.callerLiked, true);
  // Held posts never reach a visitor; the pinned post is not repeated.
  assert.deepEqual(response.posts.map((post) => post.postId),
    [posts[0].postId, posts[1].postId]);
  assert.equal(response.hasMore, false);

  // Following: the flags follow the edge.
  await seedFollowEdge(db, viewer, pageId, nowMs);
  const followed = await getPage(viewer, pageId);
  assert.deepEqual([followed.viewer.following, followed.viewer.canFollow], [true, false]);
  // An unverified viewer may read but is not offered Follow or Message.
  const unverified = await getPage(await viewerAccount(), pageId, { verified: false });
  assert.deepEqual([unverified.viewer.canFollow, unverified.viewer.canMessage], [false, false]);

  // Zdjęcia: photos only, no pinned slot.
  const photos = await getPage(viewer, pageId, { tab: "photos" });
  assert.deepEqual(photos.posts.map((post) => post.postId), [posts[1].postId]);
  assert.equal(photos.pinned, null);
  assert.equal(photos.posts[0].media.length, 2);
});

test("cursor pages carry no header; paging is complete and ordered", async () => {
  const viewer = await viewerAccount();
  const { pageId, posts } = await pageWithPosts({
    posts: Array.from({ length: 25 }, () => ({})),
  });
  const first = await getPage(viewer, pageId);
  assert.equal(first.posts.length, 20);
  assert.equal(first.hasMore, true);
  const second = await getPage(viewer, pageId, { cursor: first.nextCursor });
  assert.deepEqual([second.page, second.viewer, second.pinned], [null, null, null]);
  assert.deepEqual([...first.posts, ...second.posts].map((post) => post.postId),
    posts.map((post) => post.postId));
  assert.equal(second.hasMore, false);
  await assert.rejects(getPage(viewer, pageId, {
    cursor: encodeItemCursor({ t: nowMs, id: newCommentId() }),
  }), (error) => error.code === "invalid-argument");
  await assert.rejects(service().getPageV1(request(viewer, { pageId, tab: "about", cursor: null })),
    (error) => error.code === "invalid-argument");
});

test("the owner sees every state of their own Page and their held posts", async () => {
  const { pageId, posts } = await pageWithPosts({
    page: { ownerPaused: true },
    posts: [{}, { status: "held", heldAt: Timestamp.fromMillis(nowMs) },
      { status: "removed", removedAt: Timestamp.fromMillis(nowMs), removedReason: "spam" }],
  });
  const own = await getPage(pageId, pageId);
  assert.equal(own.page.state, "paused");
  assert.deepEqual(own.viewer,
    { isOwner: true, following: false, canFollow: false, canMessage: false });
  assert.deepEqual(own.posts.map((post) => [post.postId, post.state]), [
    [posts[0].postId, "published"],
    [posts[1].postId, "held"],
  ]);
  // Suspended beats paused; a lapsed grant shows as readOnly to the owner.
  await db.doc(`pages/${pageId}`).update({
    suspended: true,
    suspendedAt: Timestamp.fromMillis(nowMs),
    suspensionReason: "spam",
  });
  assert.equal((await getPage(pageId, pageId)).page.state, "suspended");
  const lapsed = await pageWithPosts({ grant: null });
  assert.equal((await getPage(lapsed.pageId, lapsed.pageId)).page.state, "readOnly");
});

test("a lapsed Page reads as readOnly and takes no new followers (D14)", async () => {
  const viewer = await viewerAccount();
  const { pageId } = await pageWithPosts({
    grant: testerGrant({ revoked: true }),
    posts: [{}],
  });
  const response = await getPage(viewer, pageId);
  assert.equal(response.page.state, "readOnly");
  assert.equal(response.viewer.canFollow, false);
  assert.equal(response.posts.length, 1, "the wall stays readable");
});

test("canMessage is the DM decision after D13", async () => {
  const { pageId } = await pageWithPosts({ user: { messagePrivacy: "peopleYouFollow" } });
  const person = await viewerAccount();
  const pageViewer = freshUid("pgpvp");
  await seedPage(db, pageViewer, nowMs);
  for (const uid of [person, pageViewer]) {
    await db.doc(`users/${pageId}/following/${uid}`).set({
      uid, followedAt: Timestamp.fromMillis(nowMs),
    });
  }
  assert.equal((await getPage(person, pageId)).viewer.canMessage, true);
  assert.equal((await getPage(pageViewer, pageId)).viewer.canMessage, false,
    "a follow edge to a Page account never opens DMs");
  await db.doc(`restrictions/${person}`).set({ type: "communicationMute", expiresAt: null });
  assert.equal((await getPage(person, pageId)).viewer.canMessage, false);
});

test("the linked server is shown only while active, public and the owner's", async () => {
  const viewer = await viewerAccount();
  const pageId = freshUid("pgpl");
  const serverId = `srv_${pageId.slice(-12)}`;
  await seedPage(db, pageId, nowMs, {
    page: {
      kind: "community",
      category: "fan_club",
      business: null,
      community: { rules: "Be kind.", linkedServerId: serverId },
    },
  });
  const server = {
    serverSchemaVersion: 1,
    serverType: "community",
    templateVersion: 1,
    type: "community",
    serverActivationState: "active",
    status: "active",
    revision: 1,
    privacy: "public",
    ownerId: pageId,
    name: "Fan club",
  };
  await db.doc(`clubs/${serverId}`).set(server);
  const shown = await getPage(viewer, pageId);
  assert.deepEqual(shown.page.about.community,
    { rules: "Be kind.", linkedServer: { serverId, name: "Fan club", serverType: "community" } });
  assert.equal(shown.page.about.business, null);
  await db.doc(`clubs/${serverId}`).update({ privacy: "private" });
  assert.equal((await getPage(viewer, pageId)).page.about.community.linkedServer, null);
});

// ------------------------------------------------------------------ post

test("a post with its comments: exact, paged, blocked authors hidden", async () => {
  const viewer = await viewerAccount({ displayName: "Viewer Name" });
  const { pageId, posts } = await pageWithPosts({ posts: [{ commentCount: 30 }] });
  const post = posts[0];
  const commenter = await viewerAccount({ displayName: "Commenter" });
  const blocked = await viewerAccount({ displayName: "Blocked" });
  await db.doc(`users/${viewer}/blocked/${blocked}`).set({ at: Timestamp.fromMillis(nowMs) });
  const written = [];
  const authors = [pageId, viewer, blocked, ...Array(22).fill(commenter)];
  for (const [index, authorId] of authors.entries()) {
    const commentId = newCommentId();
    const data = commentDoc(post, commentId, authorId, nowMs - index * 1000);
    await db.doc(`pagePostComments/${commentId}`).set(data);
    written.push(data);
  }
  const broken = newCommentId();
  await db.doc(`pagePostComments/${broken}`).set({
    ...commentDoc(post, broken, commenter, nowMs - 5500),
    extra: true,
  });

  const first = await getPost(viewer, post.postId);
  assert.deepEqual(Object.keys(first).sort(), [...PAGE_POST_RESPONSE_KEYS]);
  assert.equal(first.post.postId, post.postId);
  assert.equal(first.post.commentCount, 30);
  assert.equal(first.comments.length, 20);
  for (const row of first.comments) {
    assert.deepEqual(Object.keys(row).sort(), [...PAGE_COMMENT_VIEW_KEYS]);
  }
  assert.deepEqual(first.comments.slice(0, 2).map((row) => [row.authorId, row.isOwnPage]),
    [[pageId, true], [viewer, false]]);
  assert.equal(first.comments[1].authorName, "Viewer Name");
  assert.equal(first.comments.some((row) => row.authorId === blocked), false);
  assert.equal(first.hasMoreComments, true);
  const second = await getPost(viewer, post.postId, first.nextCommentCursor);
  const all = [...first.comments, ...second.comments].map((row) => row.commentId);
  assert.deepEqual(all, written.filter((row) => row.authorId !== blocked)
    .map((row) => row.commentId));
  assert.equal(second.hasMoreComments, false);

  await assert.rejects(getPost(viewer, post.postId, encodeItemCursor({ t: nowMs, id: post.postId })),
    (error) => error.code === "invalid-argument");
  await assert.rejects(getPost(viewer, "pp_nope"), (error) => error.code === "invalid-argument");
});

test("held posts reach only the owner; removed and deleted posts reach nobody", async () => {
  const viewer = await viewerAccount();
  const at = Timestamp.fromMillis(nowMs);
  const { pageId, posts } = await pageWithPosts({
    posts: [
      { status: "held", heldAt: at },
      { status: "removed", removedAt: at, removedReason: "spam" },
      { status: "deleted", deletedAt: at },
    ],
  });
  await assert.rejects(getPost(viewer, posts[0].postId), unavailable);
  assert.equal((await getPost(pageId, posts[0].postId)).post.state, "held");
  for (const post of posts.slice(1)) {
    await assert.rejects(getPost(viewer, post.postId), unavailable);
    await assert.rejects(getPost(pageId, post.postId), unavailable);
  }
  await assert.rejects(getPost(viewer, newPostId()), unavailable);
  // A published post of a Page that blocked the viewer is unavailable too.
  const blocking = await pageWithPosts({ posts: [{}] });
  await db.doc(`users/${blocking.pageId}/blocked/${viewer}`).set({ at });
  await assert.rejects(getPost(viewer, blocking.posts[0].postId), unavailable);
});

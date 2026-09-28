// listPagePostLikersV1 (ADR-233 §2.6, package B4): the ADR-230 "See who
// liked" matrix on a Page post, end to end against the Firestore emulator:
// both activation switches in order, the likers gate, the parent authorized
// with canViewPage + `published` inside the uniform refusal, the one liker
// predicate, and two pages through a real likerPageCursors document.
//
// Its own emulator namespace (the likers_callables_emulator.test.js
// reasoning): it writes appConfig/likersV1 and appConfig/pagesV1, which other
// suites in the shared project id read.
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");
const { deleteApp, initializeApp } = require("firebase-admin/app");
const { Timestamp, getFirestore } = require("firebase-admin/firestore");

const { createPagesEngagementService } = require("../pages/engagement");
const { PAGE_POST_ID_PATTERN } = require("../pages/contract");
const { LIKERS_ACTIVATION_PATH } = require("../engagement/likers_activation");
const { LIKERS_TARGET_TYPES } = require("../engagement/liker_cursors");
const {
  LIKERS_INPUT,
  LIKERS_PAGE_POST_ID,
  LIKERS_RESPONSE_KEYS,
  LIKER_ROW_KEYS,
} = require("../engagement/likers_paging");
const { PAGES_ACTIVATION_PATH } = require("../pages/activation");
const {
  DAY_MS,
  freshUid,
  newPostId,
  pagesActivation,
  postDoc,
  request,
  seedAccount,
  seedPage,
  silentLogger,
  testerGrant,
} = require("./helpers/pages_fixture");

const app = initializeApp(
  { projectId: `${process.env.GCLOUD_PROJECT}-pages-likers` },
  `pages-likers-${process.pid}`,
);
const db = getFirestore(app);
const NOW_MS = Date.now();
let nowMs = NOW_MS;

function likersActivation(enabled = true) {
  return {
    schemaVersion: 1,
    enabled,
    serverMessagesEnabled: false,
    updatedAt: Timestamp.fromMillis(NOW_MS - 1000),
  };
}

beforeEach(async () => {
  nowMs += 60_000;
  await Promise.all([
    db.doc(LIKERS_ACTIVATION_PATH).set(likersActivation()),
    db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation()),
  ]);
});

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

function service() {
  return createPagesEngagementService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
}

function rejectsWith(promise, code, reason = undefined) {
  return assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `${error.code}: ${error.message}`);
    if (reason !== undefined) assert.equal(error.details?.reason, reason, error.message);
    return true;
  });
}

function likeEdge(userId, postId, atMs) {
  return { schemaVersion: 1, userId, postId, createdAt: Timestamp.fromMillis(atMs) };
}

/// A Page with one published post and a VIP viewer (the likers gate).
async function scene({ page = {}, post = {}, grant } = {}) {
  const owner = freshUid("pglk");
  const viewer = freshUid("pglk");
  await seedPage(db, owner, nowMs, { page, ...(grant === undefined ? {} : { grant }) });
  await seedAccount(db, viewer, nowMs, { displayName: "Viewer VIP" });
  await db.doc(`vipGrants/${viewer}`).set(testerGrant());
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(owner, postId, nowMs - DAY_MS, post));
  return { owner, viewer, postId };
}

function list(uid, postId, cursor = null) {
  return request(uid, { postId, cursor }, { verified: false });
}

test("the pagePost target is additive to the ADR-230 contract", async () => {
  assert.equal(LIKERS_PAGE_POST_ID.source, PAGE_POST_ID_PATTERN.source);
  assert.ok(LIKERS_TARGET_TYPES.includes("pagePost"));
  assert.deepEqual([...LIKERS_INPUT.pagePost.allowed], ["cursor", "postId"]);
  const { viewer, postId } = await scene();
  for (const data of [
    { postId, cursor: null, limit: 50 },
    { postId: "pp_short", cursor: null },
    { postId, commentId: "x", cursor: null },
    { cursor: null },
    { postId, cursor: "not-a-token" },
  ]) {
    await rejectsWith(service().listPagePostLikersV1(request(viewer, data)), "invalid-argument");
  }
});

test("switches, then the likers gate, each with its own reason", async () => {
  const { owner, viewer, postId } = await scene();
  await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation({
    readAccess: "disabled", writeAccess: "disabled",
  }));
  await db.doc(LIKERS_ACTIVATION_PATH).set(likersActivation(false));
  await rejectsWith(service().listPagePostLikersV1(list(viewer, postId)),
    "failed-precondition", "pagesNotEnabled");
  await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation());
  await rejectsWith(service().listPagePostLikersV1(list(viewer, postId)),
    "failed-precondition", "likersNotEnabled");
  await db.doc(LIKERS_ACTIVATION_PATH).set(likersActivation());
  const plain = freshUid("pglk");
  await seedAccount(db, plain, nowMs);
  await rejectsWith(service().listPagePostLikersV1(list(plain, postId)),
    "failed-precondition", "likersAccessRequired");
  // The owner of the Page is a canonical-grant VIP too, and sees the list.
  const own = await service().listPagePostLikersV1(list(owner, postId));
  assert.deepEqual(own.likers, []);
});

test("two pages through a real cursor; hidden likers skipped; you always see yourself", async () => {
  const { owner, viewer, postId } = await scene();
  const likers = [];
  for (let index = 0; index < 23; index += 1) {
    const uid = freshUid("pglk-liker");
    likers.push(uid);
  }
  await Promise.all(likers.map((uid, index) => seedAccount(db, uid, nowMs, {
    displayName: `Liker ${String(index).padStart(2, "0")}`,
    user: index === 1 ? { likesHidden: true }
      : index === 2 ? { profileVisibility: "private" } : {},
  })));
  await db.doc(`users/${likers[3]}/blocked/${viewer}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  const batch = db.batch();
  likers.forEach((uid, index) => {
    batch.set(db.doc(`pagePosts/${postId}/likes/${uid}`), likeEdge(uid, postId, nowMs - index * 1000));
  });
  // The viewer's own like (newest) and a malformed edge (skipped, consumed).
  batch.set(db.doc(`pagePosts/${postId}/likes/${viewer}`), likeEdge(viewer, postId, nowMs + 1000));
  const broken = freshUid("pglk-broken");
  batch.set(db.doc(`pagePosts/${postId}/likes/${broken}`), {
    ...likeEdge(broken, postId, nowMs - 500), extra: true,
  });
  await batch.commit();

  const first = await service().listPagePostLikersV1(list(viewer, postId));
  assert.deepEqual(Object.keys(first).sort(), [...LIKERS_RESPONSE_KEYS]);
  assert.equal(first.likers.length, 20);
  assert.equal(first.hasMore, true);
  assert.match(first.nextCursor, /^[A-Za-z0-9_-]{43}$/u);
  for (const row of first.likers) {
    assert.deepEqual(Object.keys(row).sort(), [...LIKER_ROW_KEYS]);
    assert.equal(row.photoUrl, null);
    assert.equal(row.reaction, null);
  }
  assert.equal(first.likers[0].userId, viewer);
  const second = await service().listPagePostLikersV1(list(viewer, postId, first.nextCursor));
  assert.equal(second.hasMore, false);
  assert.equal(second.nextCursor, null);
  const listed = [...first.likers, ...second.likers].map((row) => row.userId);
  // 23 likers - 3 hidden (likesHidden, private, blocks the viewer) + the viewer.
  assert.equal(listed.length, 21);
  for (const hidden of [likers[1], likers[2], likers[3], broken]) {
    assert.equal(listed.includes(hidden), false);
  }
  assert.equal(new Set(listed).size, listed.length);
  // A cursor is bound to its viewer and its post.
  await rejectsWith(service().listPagePostLikersV1(list(owner, postId, first.nextCursor)),
    "invalid-argument");
});

test("the parent: readOnly lists; held, missing, paused and blocked refuse uniformly", async () => {
  const readOnly = await scene({
    page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) }, grant: null,
  });
  assert.equal((await service().listPagePostLikersV1(list(readOnly.viewer, readOnly.postId)))
    .hasMore, false);

  const held = await scene({ post: { status: "held", heldAt: Timestamp.fromMillis(nowMs) } });
  const paused = await scene({ page: { ownerPaused: true } });
  const blocked = await scene();
  await db.doc(`users/${blocked.owner}/blocked/${blocked.viewer}`)
    .set({ blockedAt: Timestamp.fromMillis(nowMs) });
  const missing = await scene();
  for (const { viewer, postId } of [
    held,
    paused,
    blocked,
    { viewer: missing.viewer, postId: newPostId() },
  ]) {
    await assert.rejects(service().listPagePostLikersV1(list(viewer, postId)), (error) => {
      assert.equal(error.code, "permission-denied");
      assert.equal(error.message, "This content is unavailable.");
      return true;
    });
  }
});

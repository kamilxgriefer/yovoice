// Page post engagement (ADR-233 §2.6, package B4): pagePostEngagementV1
// (like, unlike, comment, deleteComment), the owner's `pagePostComment` bell
// row and its push source check, against the Firestore emulator. The Auth
// account-age limit runs against an injected Auth record AND, when the Auth
// emulator is up (`--only auth,firestore`), against the real Admin getUser.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-engagement-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  LEDGER_KINDS,
  PAGES_ENGAGEMENT_RATE_LIMITS,
  createPagesEngagementService,
} = require("../pages/engagement");
const {
  PAGE_COMMENT_LINK_TLDS,
  PAGE_COMMENT_RESPONSE_KEYS,
  PAGE_DELETE_COMMENT_RESPONSE_KEYS,
  PAGE_LIKE_KEYS,
  PAGE_LIKE_RESPONSE_KEYS,
  PAGE_NEW_ACCOUNT_MS,
  commentHasLink,
  normalizeCommentText,
  pageCommentIdFor,
  pageCommentTargetLabel,
} = require("../pages/engagement_contract");
const { PAGES_SAFETY_ACTIONS } = require("../pages/activation");
const { PAGE_COMMENT_KEYS, pageCommentMalformedReason } = require("../pages/post_contract");
const { PAGE_COMMENT_VIEW_KEYS } = require("../pages/views");
const { pagePostCommentSourceIsCurrent } = require("../notifications/engagement_source");
const { notificationSourceIsCurrent } = require("../notifications/social_source");
const {
  DAY_MS,
  clearActivation,
  freshUid,
  newCommentId,
  newPostId,
  postDoc,
  request,
  seedAccount,
  seedPage,
  setActivation,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const BASE_MS = 1_900_000_000_000;
let nowMs = BASE_MS;
const RELAXED = Object.freeze(Object.fromEntries(Object.keys(PAGES_ENGAGEMENT_RATE_LIMITS)
  .map((scope) => [scope, { maxEvents: 1000, windowMs: 60_000 }])));
const OLD_ACCOUNT_MS = BASE_MS - 365 * DAY_MS;

beforeEach(async () => {
  nowMs += 10 * 60_000;
  await setActivation(db);
});

after(async () => {
  await clearActivation(db);
});

function fakeAuth(createdAtMs = OLD_ACCOUNT_MS) {
  const calls = [];
  return {
    calls,
    getUser: async (uid) => {
      calls.push(uid);
      const at = typeof createdAtMs === "function" ? createdAtMs(uid) : createdAtMs;
      return { uid, metadata: { creationTime: new Date(at).toUTCString() } };
    },
  };
}

function harness({ rateLimits = RELAXED, authAdmin = fakeAuth(), clock = () => nowMs } = {}) {
  const logger = silentLogger();
  const service = createPagesEngagementService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock,
    logger,
    rateLimits,
    authAdmin,
  });
  return { service, logger, authAdmin };
}

function rejectsWith(promise, code, reason = undefined) {
  return assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `${error.code}: ${error.message}`);
    if (reason !== undefined) assert.equal(error.details?.reason, reason, error.message);
    return true;
  });
}

let sequence = 0;
function requestId(label = "req") {
  sequence += 1;
  return `${label}-${BASE_MS}-${sequence}`;
}

function sortedKeys(value) {
  return Object.keys(value).sort();
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

/// A running Page with one published post, and a visitor.
async function scene({ page = {}, post = {}, grant, visitorUser = {} } = {}) {
  const owner = freshUid("pgeng");
  const visitor = freshUid("pgeng");
  await seedPage(db, owner, nowMs, { page, ...(grant === undefined ? {} : { grant }) });
  await seedAccount(db, visitor, nowMs, { user: visitorUser, displayName: "Ola Nowak" });
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(owner, postId, nowMs - 60_000, post));
  return { owner, visitor, postId };
}

function like(uid, postId, op = "like", options = {}) {
  return request(uid, { requestId: requestId(op), op, postId }, options);
}

function commentOn(uid, postId, text = "Looks great!", options = {}) {
  return request(uid, { requestId: requestId("comment"), op: "comment", postId, text }, options);
}

function deleteComment(uid, commentId, options = {}) {
  return request(uid, { requestId: requestId("delete"), op: "deleteComment", commentId }, options);
}

// ------------------------------------------------------------------ input

test("exact input: the op first, then its exact keys and each value", async () => {
  const { service } = harness();
  const uid = freshUid("pgeng");
  const postId = newPostId();
  for (const data of [
    null,
    { requestId: requestId(), op: "share", postId },
    { requestId: requestId(), op: "like", postId, text: "x" },
    { requestId: requestId(), op: "like" },
    { requestId: requestId(), op: "like", postId: "pp_short" },
    { requestId: requestId(), op: "comment", postId },
    { requestId: requestId(), op: "comment", postId, text: "   " },
    { requestId: requestId(), op: "comment", postId, text: "x".repeat(1001) },
    { requestId: requestId(), op: "comment", postId, text: "bad\u0007bell" },
    { requestId: requestId(), op: "comment", postId, text: "rtl‮override" },
    { requestId: requestId(), op: "deleteComment", commentId: postId },
    { requestId: requestId(), op: "deleteComment", commentId: newCommentId(), postId },
    { requestId: "short", op: "like", postId },
  ]) {
    await rejectsWith(service.pagePostEngagementV1(request(uid, data)), "invalid-argument");
  }
  await rejectsWith(service.pagePostEngagementV1(request(null, { op: "like" })), "unauthenticated");
  // Like and comment need a verified e-mail; deleteComment does not.
  await rejectsWith(service.pagePostEngagementV1(like(uid, postId, "like", { verified: false })),
    "failed-precondition");
  assert.equal(normalizeCommentText("  Hi\r\nthere 👨‍👩‍👧 "), "Hi\nthere 👨‍👩‍👧");
  assert.equal(normalizeCommentText("x".repeat(1000)).length, 1000);
});

test("the link filter refuses URLs and domain-shaped tokens, not sentences", async () => {
  for (const text of [
    "see https://example.com",
    "HTTP://X",
    "www.example",
    "bit.ly/x",
    "example.com",
    "example . com",
    "example .pl",
    "sklep.shop",
    "ｅｘａｍｐｌｅ．ｃｏｍ",
    "strona。com",
    "foo.co.uk",
  ]) {
    assert.equal(commentHasLink(text), true, text);
    assert.throws(() => normalizeCommentText(text), (error) =>
      error.code === "invalid-argument" && error.details?.reason === "commentLinks");
  }
  for (const text of [
    "Świetne! Co dalej?",
    "Zrobiliśmy to itp. Co teraz?",
    "Loved it. Me too",
    "e.g. me",
    "example.company rocks",
    "Version 2.0 is out",
    "a.com",
  ]) {
    assert.equal(commentHasLink(text), false, text);
  }
  assert.equal(PAGE_COMMENT_LINK_TLDS.length, 20);
});

// ------------------------------------------------------------------ likes

test("like and unlike: exact edge, counter, replay, idempotent repeat", async () => {
  const { service } = harness();
  const { owner, visitor, postId } = await scene();
  const data = { requestId: requestId("like"), op: "like", postId };
  const liked = await service.pagePostEngagementV1(request(visitor, data));
  assert.deepEqual(sortedKeys(liked), [...PAGE_LIKE_RESPONSE_KEYS]);
  assert.deepEqual(liked, {
    schemaVersion: 1, op: "like", postId, liked: true, changed: true, likeCount: 1,
  });
  const edge = await dataOf(`pagePosts/${postId}/likes/${visitor}`);
  assert.deepEqual(sortedKeys(edge), [...PAGE_LIKE_KEYS]);
  assert.equal(edge.userId, visitor);
  assert.equal(edge.postId, postId);
  assert.equal(edge.createdAt.toMillis(), nowMs);
  assert.equal((await dataOf(`pagePosts/${postId}`)).likeCount, 1);
  // The same request replays its answer; a new like changes nothing.
  assert.deepEqual(await service.pagePostEngagementV1(request(visitor, data)), liked);
  await rejectsWith(service.pagePostEngagementV1(request(visitor,
    { ...data, postId: newPostId() })), "already-exists");
  const again = await service.pagePostEngagementV1(like(visitor, postId));
  assert.equal(again.changed, false);
  assert.equal(again.likeCount, 1);
  // The owner may like their own post.
  assert.equal((await service.pagePostEngagementV1(like(owner, postId))).likeCount, 2);

  const unliked = await service.pagePostEngagementV1(like(visitor, postId, "unlike"));
  assert.deepEqual(unliked, {
    schemaVersion: 1, op: "unlike", postId, liked: false, changed: true, likeCount: 1,
  });
  assert.equal(await dataOf(`pagePosts/${postId}/likes/${visitor}`), null);
  const repeat = await service.pagePostEngagementV1(like(visitor, postId, "unlike"));
  assert.equal(repeat.changed, false);
  assert.equal((await dataOf(`pagePosts/${postId}`)).likeCount, 1);
  const ledger = await db.collection("integrityOperationLedgers")
    .where("kind", "==", LEDGER_KINDS.like).where("ownerId", "==", visitor).get();
  assert.equal(ledger.size, 2);
});

test("likes work while readOnly; blocked, paused, suspended, hidden and held refuse uniformly", async () => {
  const { service } = harness();
  const readOnly = await scene({
    page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) },
    grant: null,
  });
  assert.equal((await service.pagePostEngagementV1(like(readOnly.visitor, readOnly.postId)))
    .changed, true);

  const cases = [
    await scene({ page: { ownerPaused: true } }),
    await scene({ page: { suspended: true, suspendedAt: Timestamp.fromMillis(nowMs),
      suspensionReason: "impersonation" } }),
    await scene({ page: { status: "hidden", lapsedAt: Timestamp.fromMillis(nowMs - 40 * DAY_MS) },
      grant: null }),
    await scene({ page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - 31 * DAY_MS) },
      grant: null }),
    await scene({ post: { status: "held", heldAt: Timestamp.fromMillis(nowMs) } }),
  ];
  const blocked = await scene();
  await db.doc(`users/${blocked.owner}/blocked/${blocked.visitor}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  cases.push(blocked);
  const missing = await scene();
  cases.push({ ...missing, postId: newPostId() });
  for (const { visitor, postId } of cases) {
    await rejectsWith(service.pagePostEngagementV1(like(visitor, postId)),
      "permission-denied", "pageUnavailable");
  }
  // A muted caller cannot like.
  const muted = await scene();
  await db.doc(`restrictions/${muted.visitor}`).set({ type: "communicationMute", expiresAt: null });
  await rejectsWith(service.pagePostEngagementV1(like(muted.visitor, muted.postId)),
    "permission-denied");
});

test("an unlike of a held edge never gets stuck behind a block, a mute or a hold", async () => {
  const { service } = harness();
  const { owner, visitor, postId } = await scene();
  await service.pagePostEngagementV1(like(visitor, postId));
  await db.doc(`users/${owner}/blocked/${visitor}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  await db.doc(`restrictions/${visitor}`).set({ type: "communicationMute", expiresAt: null });
  const unliked = await service.pagePostEngagementV1(like(visitor, postId, "unlike"));
  // The post is no longer visible to the caller, so the answer hides the count.
  assert.deepEqual(unliked, {
    schemaVersion: 1, op: "unlike", postId, liked: false, changed: true, likeCount: null,
  });
  assert.equal((await dataOf(`pagePosts/${postId}`)).likeCount, 0);

  const held = await scene();
  await service.pagePostEngagementV1(like(held.visitor, held.postId));
  await db.doc(`pagePosts/${held.postId}`).update({ status: "held", heldAt: Timestamp.fromMillis(nowMs) });
  assert.equal((await service.pagePostEngagementV1(like(held.visitor, held.postId, "unlike")))
    .changed, true);
  // An unlike WITHOUT an edge is an ordinary audience-checked call.
  await rejectsWith(service.pagePostEngagementV1(like(held.visitor, held.postId, "unlike")),
    "permission-denied", "pageUnavailable");

  // A hard-deleted post whose cleanup has not run yet: the edge still goes.
  const gone = await scene();
  await service.pagePostEngagementV1(like(gone.visitor, gone.postId));
  await db.doc(`pagePosts/${gone.postId}`).delete();
  const late = await service.pagePostEngagementV1(like(gone.visitor, gone.postId, "unlike"));
  assert.equal(late.changed, true);
  assert.equal(late.likeCount, null);
  assert.equal(await dataOf(`pagePosts/${gone.postId}/likes/${gone.visitor}`), null);
});

test("a broken counter or edge is data-loss for a like, never for an unlike", async () => {
  const { service, logger } = harness();
  const { visitor, postId } = await scene({ post: { likeCount: -1 } });
  await rejectsWith(service.pagePostEngagementV1(like(visitor, postId)), "data-loss");

  const malformed = await scene();
  await db.doc(`pagePosts/${malformed.postId}/likes/${malformed.visitor}`).set({ userId: "someone" });
  await rejectsWith(service.pagePostEngagementV1(like(malformed.visitor, malformed.postId)),
    "data-loss");
  await db.doc(`pagePosts/${malformed.postId}`).update({ likeCount: 1 });
  const removed = await service.pagePostEngagementV1(like(malformed.visitor, malformed.postId,
    "unlike"));
  assert.equal(removed.changed, true);
  assert.equal(await dataOf(`pagePosts/${malformed.postId}/likes/${malformed.visitor}`), null);
  assert.equal((await dataOf(`pagePosts/${malformed.postId}`)).likeCount, 0);

  const zero = await scene();
  await service.pagePostEngagementV1(like(zero.visitor, zero.postId));
  await db.doc(`pagePosts/${zero.postId}`).update({ likeCount: 0 });
  const stuck = await service.pagePostEngagementV1(like(zero.visitor, zero.postId, "unlike"));
  assert.equal(stuck.changed, true);
  assert.equal(stuck.likeCount, null);
  assert.equal((await dataOf(`pagePosts/${zero.postId}`)).likeCount, 0);
  assert.ok(logger.entries.some((entry) => entry.args[0] === "pages like count underflow"));
});

// --------------------------------------------------------------- comments

test("comment: exact document, counter, CommentView and the owner's bell row", async () => {
  const { service } = harness();
  const { owner, visitor, postId } = await scene();
  const data = { requestId: requestId("comment"), op: "comment", postId, text: " Świetne ciasto! " };
  const result = await service.pagePostEngagementV1(request(visitor, data));
  assert.deepEqual(sortedKeys(result), [...PAGE_COMMENT_RESPONSE_KEYS]);
  assert.deepEqual(sortedKeys(result.comment), [...PAGE_COMMENT_VIEW_KEYS]);
  const commentId = pageCommentIdFor(visitor, data.requestId);
  assert.deepEqual(result, {
    schemaVersion: 1,
    op: "comment",
    postId,
    commentCount: 1,
    comment: {
      commentId,
      authorId: visitor,
      authorName: "Ola Nowak",
      text: "Świetne ciasto!",
      createdAtMs: nowMs,
      isOwnPage: false,
    },
  });
  const stored = await dataOf(`pagePostComments/${commentId}`);
  assert.deepEqual(sortedKeys(stored), [...PAGE_COMMENT_KEYS]);
  assert.equal(pageCommentMalformedReason(stored, commentId), null);
  assert.equal(stored.pageId, owner);
  assert.equal((await dataOf(`pagePosts/${postId}`)).commentCount, 1);

  const row = await dataOf(`users/${owner}/notifications/pagePostComment_${commentId}`);
  assert.equal(row.type, "pagePostComment");
  assert.equal(row.actorId, visitor);
  assert.equal(row.actorName, "Ola Nowak");
  assert.equal(row.actorPhotoUrl, null);
  assert.equal(row.targetId, postId);
  assert.equal(row.targetSubId, commentId);
  // Human-readable: builds that render an unknown type as `system` show it.
  assert.equal(row.targetLabel, "New comment on your Page post from Ola Nowak");
  assert.equal(row.sourcePath, `pagePostComments/${commentId}`);
  assert.equal(row.isRead, false);
  assert.equal(row.bellSuppressed, false);
  assert.equal(row.dedupeKey, `pagePostComment_${commentId}`);
  assert.ok(row.createdAt instanceof Timestamp);
  assert.equal(JSON.stringify(row).includes("Świetne"), false, "the comment text stays out of the row");

  // Replay: the same answer, no second comment.
  assert.deepEqual(await service.pagePostEngagementV1(request(visitor, data)), result);
  assert.equal((await dataOf(`pagePosts/${postId}`)).commentCount, 1);

  // The owner commenting on their own post gets no row.
  const own = await service.pagePostEngagementV1(commentOn(owner, postId, "Thanks!"));
  assert.equal(own.comment.isOwnPage, true);
  const ownRows = await db.collection(`users/${owner}/notifications`).get();
  assert.equal(ownRows.size, 1);
});

test("comment refusals: readOnly (live), comments off, paused, mute, unverified, block, switch", async () => {
  const { service } = harness();
  // Stored "active", but the owner's grant expired by time: LIVE readOnly.
  const lapsed = await scene({ grant: {
    source: "testerProgram", expiresAt: Timestamp.fromMillis(nowMs - 1000),
    revoked: false, grantedBy: "owner-console",
  } });
  await rejectsWith(service.pagePostEngagementV1(commentOn(lapsed.visitor, lapsed.postId)),
    "failed-precondition", "pageReadOnly");
  const readOnly = await scene({
    page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) }, grant: null,
  });
  await rejectsWith(service.pagePostEngagementV1(commentOn(readOnly.visitor, readOnly.postId)),
    "failed-precondition", "pageReadOnly");
  // ...while a like on the same readOnly Page still works (D14).
  assert.equal((await service.pagePostEngagementV1(like(readOnly.visitor, readOnly.postId)))
    .changed, true);

  const off = await scene({ post: { commentsEnabled: false } });
  await rejectsWith(service.pagePostEngagementV1(commentOn(off.visitor, off.postId)),
    "failed-precondition", "pageCommentsOff");

  const paused = await scene({ page: { ownerPaused: true } });
  await rejectsWith(service.pagePostEngagementV1(commentOn(paused.visitor, paused.postId)),
    "permission-denied", "pageUnavailable");
  await rejectsWith(service.pagePostEngagementV1(commentOn(paused.owner, paused.postId)),
    "failed-precondition", "pagePaused");

  const muted = await scene();
  await db.doc(`restrictions/${muted.visitor}`).set({ type: "communicationMute", expiresAt: null });
  await rejectsWith(service.pagePostEngagementV1(commentOn(muted.visitor, muted.postId)),
    "permission-denied");
  await rejectsWith(service.pagePostEngagementV1(commentOn(muted.owner, muted.postId, "Hi",
    { verified: false })), "failed-precondition");

  const blocked = await scene();
  await db.doc(`users/${blocked.visitor}/blocked/${blocked.owner}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  await rejectsWith(service.pagePostEngagementV1(commentOn(blocked.visitor, blocked.postId)),
    "permission-denied", "pageUnavailable");

  const links = await scene();
  await rejectsWith(service.pagePostEngagementV1(commentOn(links.visitor, links.postId,
    "Kup na bit.ly/x")), "invalid-argument", "commentLinks");

  // writeAccess off while reading is on: no comments, likes still work.
  const switched = await scene();
  await setActivation(db, { writeAccess: "disabled" });
  await rejectsWith(service.pagePostEngagementV1(commentOn(switched.visitor, switched.postId)),
    "failed-precondition", "pagesNotEnabled");
  assert.equal((await service.pagePostEngagementV1(like(switched.visitor, switched.postId)))
    .changed, true);
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });
  await rejectsWith(service.pagePostEngagementV1(like(switched.visitor, switched.postId, "unlike")),
    "failed-precondition", "pagesNotEnabled");
  for (const scenario of [lapsed, readOnly, off, paused, muted, blocked, links, switched]) {
    assert.equal((await db.collection("pagePostComments")
      .where("postId", "==", scenario.postId).get()).size, 0);
  }
});

test("a muted Page owner gets no bell row; the comment still lands", async () => {
  const { service } = harness();
  const { owner, visitor, postId } = await scene();
  await db.doc(`restrictions/${owner}`).set({ type: "communicationMute", expiresAt: null });
  const result = await service.pagePostEngagementV1(commentOn(visitor, postId));
  assert.equal(result.commentCount, 1);
  assert.equal((await db.collection(`users/${owner}/notifications`).get()).size, 0);
});

test("new accounts by FIREBASE AUTH age: 3/min; a backdated users.createdAt changes nothing", async () => {
  const { service, authAdmin } = harness({
    rateLimits: PAGES_ENGAGEMENT_RATE_LIMITS,
    authAdmin: fakeAuth(() => nowMs - DAY_MS),
  });
  const { visitor, postId } = await scene({
    visitorUser: { createdAt: Timestamp.fromMillis(nowMs - 400 * DAY_MS) },
  });
  for (let index = 0; index < 3; index += 1) {
    await service.pagePostEngagementV1(commentOn(visitor, postId, `Comment ${index}`));
  }
  await rejectsWith(service.pagePostEngagementV1(commentOn(visitor, postId, "Fourth")),
    "resource-exhausted");
  // Memoised per instance: one Auth read for four calls.
  assert.deepEqual(authAdmin.calls, [visitor]);

  const established = harness({ rateLimits: PAGES_ENGAGEMENT_RATE_LIMITS });
  const older = await scene();
  for (let index = 0; index < 4; index += 1) {
    await established.service.pagePostEngagementV1(commentOn(older.visitor, older.postId,
      `Comment ${index}`));
  }
  assert.equal(PAGE_NEW_ACCOUNT_MS, 7 * DAY_MS);

  // An unreadable Auth record is treated as new (the stricter limit).
  const failing = harness({
    rateLimits: PAGES_ENGAGEMENT_RATE_LIMITS,
    authAdmin: { getUser: async () => { throw Object.assign(new Error("x"), { code: "auth/internal-error" }); } },
  });
  const unknown = await scene();
  for (let index = 0; index < 3; index += 1) {
    await failing.service.pagePostEngagementV1(commentOn(unknown.visitor, unknown.postId,
      `Comment ${index}`));
  }
  await rejectsWith(failing.service.pagePostEngagementV1(commentOn(unknown.visitor,
    unknown.postId, "Fourth")), "resource-exhausted");
});

test("the default Auth path reads the real account's creation time", async (t) => {
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    t.skip("needs the Auth emulator (--only auth,firestore)");
    return;
  }
  const { getAuth } = require("firebase-admin/auth");
  const realNow = () => Date.now();
  const service = createPagesEngagementService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: realNow,
    logger: silentLogger(),
  });
  const owner = freshUid("pgeng");
  const visitor = freshUid("pgeng");
  await getAuth().createUser({ uid: visitor, email: `${visitor}@example.com`, emailVerified: true });
  await seedPage(db, owner, Date.now());
  await seedAccount(db, visitor, Date.now(), {
    user: { createdAt: Timestamp.fromMillis(Date.now() - 400 * DAY_MS) },
  });
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(owner, postId, Date.now() - 60_000));
  for (let index = 0; index < 3; index += 1) {
    await service.pagePostEngagementV1(commentOn(visitor, postId, `Comment ${index}`));
  }
  await rejectsWith(service.pagePostEngagementV1(commentOn(visitor, postId, "Fourth")),
    "resource-exhausted");
  await getAuth().deleteUser(visitor);
});

// ---------------------------------------------------------- deleteComment

test("deleteComment: author or owner, with the kill switch on, muted and unverified", async () => {
  assert.ok(PAGES_SAFETY_ACTIONS.includes("pagePostEngagementV1.deleteComment"));
  const { service } = harness();
  const { owner, visitor, postId } = await scene();
  const first = await service.pagePostEngagementV1(commentOn(visitor, postId, "One"));
  const second = await service.pagePostEngagementV1(commentOn(visitor, postId, "Two"));
  const stranger = freshUid("pgeng");
  await seedAccount(db, stranger, nowMs);
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });
  await db.doc(`restrictions/${visitor}`).set({ type: "communicationMute", expiresAt: null });
  await db.doc(`restrictions/${owner}`).set({ type: "communicationMute", expiresAt: null });

  // Anyone else, and a missing comment, get the same refusal.
  await rejectsWith(service.pagePostEngagementV1(deleteComment(stranger,
    first.comment.commentId)), "permission-denied", "pageUnavailable");
  await rejectsWith(service.pagePostEngagementV1(deleteComment(visitor, newCommentId())),
    "permission-denied", "pageUnavailable");

  const byAuthor = await service.pagePostEngagementV1(deleteComment(visitor,
    first.comment.commentId, { verified: false }));
  assert.deepEqual(sortedKeys(byAuthor), [...PAGE_DELETE_COMMENT_RESPONSE_KEYS]);
  assert.deepEqual(byAuthor, {
    schemaVersion: 1, op: "deleteComment", postId, commentId: first.comment.commentId, deleted: true,
  });
  assert.equal(await dataOf(`pagePostComments/${first.comment.commentId}`), null);
  assert.equal(await dataOf(`users/${owner}/notifications/pagePostComment_${first.comment.commentId}`),
    null);
  assert.equal((await dataOf(`pagePosts/${postId}`)).commentCount, 1);

  // The owner deletes a visitor's comment; the owner already cleared its row.
  await db.doc(`users/${owner}/notifications/pagePostComment_${second.comment.commentId}`).delete();
  await service.pagePostEngagementV1(deleteComment(owner, second.comment.commentId,
    { verified: false }));
  assert.equal(await dataOf(`pagePostComments/${second.comment.commentId}`), null);
  assert.equal((await dataOf(`pagePosts/${postId}`)).commentCount, 0);
});

test("deleteComment never trips over a missing or broken post", async () => {
  const { service, logger } = harness();
  const { owner, visitor, postId } = await scene();
  const made = await service.pagePostEngagementV1(commentOn(visitor, postId));
  await db.doc(`pagePosts/${postId}`).update({ commentCount: 0 });
  await service.pagePostEngagementV1(deleteComment(owner, made.comment.commentId));
  assert.equal((await dataOf(`pagePosts/${postId}`)).commentCount, 0);
  assert.ok(logger.entries.some((entry) => entry.args[0] === "pages comment count underflow"));

  const other = await service.pagePostEngagementV1(commentOn(visitor, postId, "Again"));
  await db.doc(`pagePosts/${postId}`).delete();
  await service.pagePostEngagementV1(deleteComment(visitor, other.comment.commentId));
  assert.equal(await dataOf(`pagePostComments/${other.comment.commentId}`), null);
});

// -------------------------------------------------------- push source check

test("the pagePostComment push source check follows the comment, the post and the switch", async () => {
  const { service } = harness();
  const { owner, visitor, postId } = await scene();
  const made = await service.pagePostEngagementV1(commentOn(visitor, postId));
  const commentId = made.comment.commentId;
  const rowPath = `users/${owner}/notifications/pagePostComment_${commentId}`;
  const check = async () => notificationSourceIsCurrent({
    recipientId: owner,
    notificationId: `pagePostComment_${commentId}`,
    notification: await dataOf(rowPath),
    firestore: db,
    nowMs,
  });
  assert.equal(await check(), true);
  // A forged row (another source, another post, self) is never current.
  const row = await dataOf(rowPath);
  for (const forged of [
    { ...row, sourcePath: `pagePostComments/${newCommentId()}` },
    { ...row, targetId: newPostId() },
    { ...row, actorId: owner },
    { ...row, sourcePath: `reels/x/comments/${commentId}` },
  ]) {
    assert.equal(await pagePostCommentSourceIsCurrent({
      recipientId: owner, notification: forged, reader: db, firestore: db, nowMs,
    }), false);
  }
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });
  assert.equal(await check(), false, "the kill switch silences the push");
  await setActivation(db);
  await db.doc(`users/${owner}/blocked/${visitor}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  assert.equal(await check(), false, "a block silences the push");
  await db.doc(`users/${owner}/blocked/${visitor}`).delete();
  await db.doc(`pagePosts/${postId}`).update({ status: "held", heldAt: Timestamp.fromMillis(nowMs) });
  assert.equal(await check(), false, "a held post silences the push");
  await db.doc(`pagePosts/${postId}`).update({ status: "published", heldAt: null });
  assert.equal(await check(), true);
  await service.pagePostEngagementV1(deleteComment(visitor, commentId));
  assert.equal(await pagePostCommentSourceIsCurrent({
    recipientId: owner, notification: row, reader: db, firestore: db, nowMs,
  }), false, "a deleted comment never pushes");
});

// The whole push path for the row a comment writes: the trigger's handler
// revalidates the source, honours the "Comments and mentions" switch
// (momentComment) and sends the generic lock-screen body with the Page title.
test("the owner's bell row pushes once, and the comments switch silences it", async () => {
  const { handleNotificationCreated } = require("../notifications/push");
  const { service } = harness();
  const sent = [];
  const messaging = {
    sendEachForMulticast: async (message) => {
      sent.push(message);
      return { responses: message.tokens.map(() => ({ success: true })) };
    },
  };
  const deliver = async (owner, commentId) => {
    const reference = db.doc(`users/${owner}/notifications/pagePostComment_${commentId}`);
    await handleNotificationCreated({
      id: `pages-push-${commentId}`,
      params: { userId: owner, notificationId: `pagePostComment_${commentId}` },
      data: await reference.get(),
    }, { messaging });
    return (await reference.get()).data();
  };

  const { owner, visitor, postId } = await scene();
  await db.doc(`users/${owner}/fcmTokens/token-${owner}`).set({ updatedAt: Timestamp.now() });
  const made = await service.pagePostEngagementV1(commentOn(visitor, postId, "Pyszne!"));
  const row = await deliver(owner, made.comment.commentId);
  assert.equal(row.pushDeliveryStatus, "sent");
  assert.equal(sent.length, 1);
  assert.equal(sent[0].notification.title, "Ola Nowak commented on your Page post");
  assert.equal(sent[0].notification.body, "Tap to open YO Voice");
  assert.equal(sent[0].data.type, "pagePostComment");
  assert.equal(sent[0].data.targetId, postId);
  assert.equal(sent[0].data.targetSubId, made.comment.commentId);
  assert.equal(JSON.stringify(sent[0]).includes("Pyszne"), false);

  await db.doc(`users/${owner}`).update({ "notificationPreferences.momentComment": false });
  const quiet = await service.pagePostEngagementV1(commentOn(visitor, postId, "Again"));
  const skipped = await deliver(owner, quiet.comment.commentId);
  assert.equal(skipped.pushDeliveryStatus, "skipped");
  assert.equal(skipped.pushSkipReason, "preference-disabled");
  assert.equal(sent.length, 1);
});

test("the comment row label puts the attribution first and caps the commenter's name", () => {
  assert.equal(pageCommentTargetLabel("Ola Nowak"), "New comment on your Page post from Ola Nowak");
  assert.equal(pageCommentTargetLabel("   "), "New comment on your Page post from someone");
  assert.equal(pageCommentTargetLabel(null), "New comment on your Page post from someone");
  // A 108-character name written to read as a YO Voice notice (audit
  // 2026-09-28): the attribution survives, the name is cut to 40.
  const spoof = "YO Voice Security: your Page is suspended. Reply with your e-mail code to the YO Voice Support account now!!";
  const label = pageCommentTargetLabel(spoof);
  assert.equal(label.startsWith("New comment on your Page post from YO Voice Security"), true);
  assert.equal(label.endsWith("…"), true);
  assert.equal(Array.from(label).length <= 120, true);
  assert.equal(Array.from(label).length, "New comment on your Page post from ".length + 40);
  // Emoji are never split into a lone surrogate.
  const emoji = pageCommentTargetLabel("💜".repeat(60));
  assert.equal(emoji.isWellFormed(), true);
});

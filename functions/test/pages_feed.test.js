// getPagesFeedV1 (ADR-233 §2.5) against the Firestore emulator: the k-way
// merge over `pageId in` chunks, pageVisibility/v1 applied BEFORE querying,
// the per-Page audience check, the refill scan cap, stale-index pruning, the
// cursor contract and the pinned read budget.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-feed-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  PAGES_FEED_INDEX_WINDOW,
  PAGES_FEED_IN_CHUNK,
  PAGES_FEED_MAX_CHUNKS,
  PAGES_FEED_PAGE_SIZE,
  PAGES_FEED_QUERY_LIMIT,
  PAGES_FEED_SCAN_CAP,
  createPagesReadService,
  pagesFeedReadBudget,
} = require("../pages/reads");
const {
  PAGES_FEED_RESPONSE_KEYS,
  PAGE_CARD_KEYS,
  PAGE_POST_VIEW_KEYS,
  decodeItemCursor,
  encodeItemCursor,
} = require("../pages/views");
const {
  DAY_MS,
  clearActivation,
  freshUid,
  newPostId,
  postDoc,
  request,
  seedAccount,
  seedFollowEdge,
  seedPage,
  setActivation,
  setFollowIndex,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const BASE_MS = 1_900_000_000_000;
const nowMs = BASE_MS;

/// Counts what the service reads: getAll references, and query runs and
/// returned documents per collection. Activation and rate reads use doc()
/// and runTransaction and are fixed (3), so they are not proxied.
function counting(inner) {
  const counts = { getAllDocs: 0, queries: {}, queryDocs: {}, inLists: [] };
  const wrapQuery = (query, collection) => new Proxy(query, {
    get(target, property) {
      const value = target[property];
      if (property === "get") {
        return async () => {
          const snapshot = await target.get();
          counts.queries[collection] = (counts.queries[collection] ?? 0) + 1;
          counts.queryDocs[collection] = (counts.queryDocs[collection] ?? 0) + snapshot.size;
          return snapshot;
        };
      }
      if (["where", "orderBy", "startAfter", "limit"].includes(property)) {
        return (...args) => {
          if (property === "where" && args[1] === "in" && args[0] === "pageId") {
            counts.inLists.push([...args[2]]);
          }
          return wrapQuery(value.apply(target, args), collection);
        };
      }
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const firestore = new Proxy(inner, {
    get(target, property) {
      if (property === "collection") {
        return (path) => wrapQuery(target.collection(path), path);
      }
      if (property === "getAll") {
        return async (...references) => {
          counts.getAllDocs += references.length;
          return target.getAll(...references);
        };
      }
      const value = target[property];
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const total = () => 3 + counts.getAllDocs +
    Object.values(counts.queryDocs).reduce((sum, value) => sum + Math.max(value, 0), 0) +
    Object.values(counts.queries).reduce((sum, value) => sum + value, 0);
  return { firestore, counts, total };
}

function service(firestore = db, logger = silentLogger()) {
  return createPagesReadService({
    firestore,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger,
  });
}

function feed(viewer, cursor = null, firestore = db) {
  return service(firestore).getPagesFeedV1(request(viewer, { cursor }));
}

async function viewerAccount() {
  const viewer = freshUid("pgfv");
  await seedAccount(db, viewer, nowMs);
  return viewer;
}

/// A Page the viewer follows (edge + page + owner), with posts at the given
/// createdAt offsets (ms before now). Returns {pageId, posts:[{postId, t}]}.
async function followedPage(viewer, { page = {}, offsets = [], edge = true } = {}) {
  const pageId = freshUid("pgfp");
  await seedPage(db, pageId, nowMs, { page });
  if (edge) await seedFollowEdge(db, viewer, pageId, nowMs);
  const posts = offsets.map((offset) => ({ postId: newPostId(), t: nowMs - offset }));
  await Promise.all(posts.map(({ postId, t }) =>
    db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, t))));
  return { pageId, posts };
}

function newestFirst(posts) {
  return [...posts].sort((left, right) =>
    right.t - left.t || (left.postId < right.postId ? 1 : left.postId > right.postId ? -1 : 0));
}

async function markNotViewable(pageId, reason) {
  await db.doc("pageVisibility/v1").set({
    schemaVersion: 1,
    notViewable: { [pageId]: reason },
    readOnlySince: {},
    updatedAt: Timestamp.fromMillis(nowMs),
  }, { merge: true });
}

beforeEach(() => setActivation(db));
after(() => clearActivation(db));

test("the read budget and paging constants are pinned", () => {
  assert.equal(PAGES_FEED_PAGE_SIZE, 20);
  assert.equal(PAGES_FEED_SCAN_CAP, 60);
  assert.equal(PAGES_FEED_INDEX_WINDOW, 300);
  assert.equal(PAGES_FEED_IN_CHUNK, 30);
  assert.equal(PAGES_FEED_QUERY_LIMIT, 21);
  assert.equal(PAGES_FEED_MAX_CHUNKS, 10);
  // fixed 6 + chunks x 21 + refills 4 x 21 + contexts 5 x 60 + likes 20 +
  // suggestions (41 + 3 x 40).
  assert.equal(pagesFeedReadBudget(1), 6 + 21 + 84 + 300 + 20 + 161);
  assert.equal(pagesFeedReadBudget(PAGES_FEED_MAX_CHUNKS), 6 + 210 + 84 + 300 + 20 + 161);
});

test("the feed is off until readAccess allows the caller", async () => {
  const viewer = await viewerAccount();
  await clearActivation(db);
  await assert.rejects(feed(viewer), (error) => {
    assert.equal(error.details?.reason, "pagesNotEnabled");
    return true;
  });
  await setActivation(db, { readAccess: "testers", writeAccess: "disabled",
    testerUids: ["someone-else"] });
  await assert.rejects(feed(viewer), (error) => error.details?.reason === "pagesNotEnabled");
  await setActivation(db, { readAccess: "testers", writeAccess: "disabled",
    testerUids: [viewer] });
  const response = await feed(viewer);
  assert.deepEqual(Object.keys(response).sort(), [...PAGES_FEED_RESPONSE_KEYS]);
  assert.deepEqual([response.posts, response.nextCursor, response.hasMore], [[], null, false]);
});

test("a malformed cursor is refused before any read, even the switch", async () => {
  const viewer = await viewerAccount();
  await clearActivation(db);
  const probe = counting(db);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  for (const cursor of [
    encode({ v: 1, t: nowMs, id: "pp_short" }),
    encode({ v: 1, t: "now", id: newPostId() }),
    "!!",
  ]) {
    await assert.rejects(feed(viewer, cursor, probe.firestore), (error) => {
      assert.equal(error.code, "invalid-argument");
      return true;
    });
  }
  assert.equal(probe.counts.getAllDocs, 0);
  assert.deepEqual(probe.counts.queries, {});
  await assert.rejects(service().getPagesFeedV1(request(viewer, { cursor: null, extra: 1 })),
    (error) => error.code === "invalid-argument");
});

test("posts from 31 followed Pages merge newest first across two chunks, id as the tiebreak", async () => {
  const viewer = await viewerAccount();
  const pages = [];
  for (let index = 0; index < 31; index += 1) {
    // Every Page posts once at the SAME instant and once at its own time, so
    // the order across chunks is decided by the id tiebreak.
    pages.push(await followedPage(viewer, { offsets: [60_000, 1000 * (index + 1)] }));
  }
  await setFollowIndex(db, viewer, pages.map((page) => page.pageId), nowMs);
  const probe = counting(db);
  const first = await feed(viewer, null, probe.firestore);
  assert.deepEqual(probe.counts.inLists.map((ids) => ids.length), [30, 1],
    "31 ids = two `in` chunks");
  const expected = newestFirst(pages.flatMap((page) => page.posts));
  assert.equal(first.posts.length, 20);
  assert.deepEqual(first.posts.map((post) => post.postId),
    expected.slice(0, 20).map((post) => post.postId));
  for (const post of first.posts) {
    assert.deepEqual(Object.keys(post).sort(), [...PAGE_POST_VIEW_KEYS]);
    assert.equal(post.state, "published");
  }
  assert.equal(first.hasMore, true);
  assert.deepEqual(decodeItemCursor(first.nextCursor, "post"),
    { t: expected[19].t, id: expected[19].postId });
  assert.ok(probe.total() <= pagesFeedReadBudget(2), `${probe.total()} reads`);

  const collected = [...first.posts];
  let cursor = first.nextCursor;
  while (cursor !== null) {
    const next = await feed(viewer, cursor);
    assert.equal(next.suggestions, null, "suggestions come on the first page only");
    collected.push(...next.posts);
    cursor = next.nextCursor;
  }
  assert.deepEqual(collected.map((post) => post.postId), expected.map((post) => post.postId));
});

test("pageVisibility drops Pages BEFORE querying; per-Page checks catch the rest", async () => {
  const viewer = await viewerAccount();
  const pages = [];
  for (let index = 0; index < 30; index += 1) {
    pages.push(await followedPage(viewer, { offsets: [index * 1000 + 10] }));
  }
  const paused = await followedPage(viewer, { page: { ownerPaused: true }, offsets: [1] });
  await markNotViewable(paused.pageId, "paused");
  // Blocked either way, readOnly past 30 days: not in the index as hidden,
  // refused by the per-Page check.
  const blocked = await followedPage(viewer, { offsets: [2] });
  await db.doc(`users/${blocked.pageId}/blocked/${viewer}`).set({ blockedAt: Timestamp.now() });
  const lapsedLong = await followedPage(viewer, {
    page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - 31 * DAY_MS) },
    offsets: [3],
  });
  const lapsedRecent = await followedPage(viewer, {
    page: { status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) },
    offsets: [4],
  });
  await setFollowIndex(db, viewer, [
    ...pages.map((page) => page.pageId),
    paused.pageId,
    blocked.pageId,
    lapsedLong.pageId,
    lapsedRecent.pageId,
  ], nowMs);
  const probe = counting(db);
  const response = await feed(viewer, null, probe.firestore);
  // 34 ids minus the one notViewable = 33 = two chunks, never three, and
  // the paused Page is in neither.
  assert.equal(probe.counts.inLists.length, 2);
  assert.deepEqual(probe.counts.inLists.map((ids) => ids.length), [30, 3]);
  assert.equal(probe.counts.inLists.flat().includes(paused.pageId), false);
  const shown = new Set(response.posts.map((post) => post.pageId));
  assert.equal(shown.has(paused.pageId), false);
  assert.equal(shown.has(blocked.pageId), false);
  assert.equal(shown.has(lapsedLong.pageId), false);
  assert.equal(shown.has(lapsedRecent.pageId), true, "readOnly Pages stay readable");
  assert.equal(response.posts[0].pageId, lapsedRecent.pageId);

  // With exactly 30 visible ids left, one chunk suffices.
  const second = await viewerAccount();
  const few = [];
  for (let index = 0; index < 30; index += 1) {
    few.push(await followedPage(second, { offsets: [index + 1] }));
  }
  const hidden = await followedPage(second, { page: { ownerPaused: true }, offsets: [0] });
  await markNotViewable(hidden.pageId, "paused");
  await setFollowIndex(db, second, [...few.map((page) => page.pageId), hidden.pageId], nowMs);
  const single = counting(db);
  await feed(second, null, single.firestore);
  assert.equal(single.counts.inLists.length, 1);
  assert.equal(single.counts.inLists[0].length, 30);
});

test("the refill scan cap ends a page of hidden posts early with a cursor", async () => {
  const viewer = await viewerAccount();
  const suspended = [];
  for (let index = 0; index < 25; index += 1) {
    // Suspended in the Page document, but the visibility index lags (never
    // written here): only the per-Page check hides these 75 posts.
    suspended.push(await followedPage(viewer, {
      page: {
        suspended: true,
        suspendedAt: Timestamp.fromMillis(nowMs),
        suspensionReason: "spam",
      },
      offsets: [index * 10 + 1, index * 10 + 2, index * 10 + 3],
    }));
  }
  const visible = await followedPage(viewer, { offsets: [DAY_MS] });
  await setFollowIndex(db, viewer,
    [...suspended.map((page) => page.pageId), visible.pageId], nowMs);
  const hiddenPosts = newestFirst(suspended.flatMap((page) => page.posts));

  const first = await feed(viewer);
  assert.equal(first.posts.length, 0);
  assert.equal(first.hasMore, true);
  assert.deepEqual(decodeItemCursor(first.nextCursor, "post"),
    { t: hiddenPosts[59].t, id: hiddenPosts[59].postId }, "cursor after the 60th consumed");
  const second = await feed(viewer, first.nextCursor);
  assert.deepEqual(second.posts.map((post) => post.postId), [visible.posts[0].postId]);
  assert.equal(second.hasMore, false);
  assert.equal(second.nextCursor, null);
});

test("a stale index id (no edge, or no Page) is dropped and pruned", async () => {
  const viewer = await viewerAccount();
  const kept = await followedPage(viewer, { offsets: [10] });
  const noEdge = await followedPage(viewer, { offsets: [5], edge: false });
  const gone = freshUid("pgfgone");
  await seedFollowEdge(db, viewer, gone, nowMs);
  const orphan = newPostId();
  await db.doc(`pagePosts/${orphan}`).set(postDoc(gone, orphan, nowMs - 1));
  await setFollowIndex(db, viewer, [kept.pageId, noEdge.pageId, gone], nowMs);
  const response = await feed(viewer);
  assert.deepEqual(response.posts.map((post) => post.pageId), [kept.pageId]);
  const index = (await db.doc(`pageFollowIndex/${viewer}`).get()).data();
  assert.deepEqual(index.pageIds, [kept.pageId]);
});

test("callerLiked, malformed posts and first-page suggestions", async () => {
  const viewer = await viewerAccount();
  const followed = await followedPage(viewer, { offsets: [30, 20, 10] });
  const [liked, malformed] = followed.posts;
  await db.doc(`pagePosts/${liked.postId}/likes/${viewer}`).set({
    schemaVersion: 1,
    userId: viewer,
    postId: liked.postId,
    createdAt: Timestamp.fromMillis(nowMs),
  });
  await db.doc(`pagePosts/${malformed.postId}`).update({ junk: true });
  await setFollowIndex(db, viewer, [followed.pageId], nowMs);
  // A listed Page the viewer does not follow is suggested; the followed one
  // never is; a Page renamed in the last 7 days waits.
  const suggested = freshUid("pgfs");
  await seedPage(db, suggested, nowMs, {
    page: { postCount: 1, listed: true, lastPostAt: Timestamp.fromMillis(nowMs + DAY_MS) },
  });
  const renamed = freshUid("pgfr");
  await seedPage(db, renamed, nowMs, {
    page: {
      postCount: 1,
      listed: true,
      lastPostAt: Timestamp.fromMillis(nowMs + DAY_MS),
      nameChangedAt: Timestamp.fromMillis(nowMs - DAY_MS),
    },
  });
  await db.doc(`pages/${followed.pageId}`).update({
    postCount: 3,
    listed: true,
    lastPostAt: Timestamp.fromMillis(nowMs + 2 * DAY_MS),
  });
  const logger = silentLogger();
  const response = await service(db, logger).getPagesFeedV1(request(viewer, { cursor: null }));
  assert.deepEqual(response.posts.map((post) => [post.postId, post.callerLiked]), [
    [followed.posts[2].postId, false],
    [liked.postId, true],
  ]);
  assert.equal(logger.entries.some((entry) =>
    entry.args[0] === "pages malformed record skipped" &&
    JSON.stringify(entry.args[1]).includes("pagePost")), true);
  const ids = response.suggestions.map((card) => card.pageId);
  assert.equal(ids.includes(suggested), true);
  assert.equal(ids.includes(followed.pageId), false);
  assert.equal(ids.includes(renamed), false);
  assert.ok(response.suggestions.length <= 10);
  for (const card of response.suggestions) {
    assert.deepEqual(Object.keys(card).sort(), [...PAGE_CARD_KEYS]);
    assert.equal(card.viewerFollows, false);
  }
  await db.doc(`pages/${suggested}`).update({ listed: false, postCount: 0 });
  await db.doc(`pages/${renamed}`).update({ listed: false, postCount: 0 });
  await db.doc(`pages/${followed.pageId}`).update({ listed: false, postCount: 0 });
});

test("an inactive viewer is refused; an empty index is an empty feed", async () => {
  const viewer = await viewerAccount();
  const empty = await feed(viewer);
  assert.deepEqual(empty.posts, []);
  assert.ok(Array.isArray(empty.suggestions));
  await db.doc(`users/${viewer}`).update({ banned: true });
  await assert.rejects(feed(viewer), (error) => error.code === "permission-denied");
  // A well-formed cursor for a post that does not exist simply resumes there.
  const other = await viewerAccount();
  const response = await feed(other, encodeItemCursor({ t: nowMs, id: newPostId() }));
  assert.equal(response.suggestions, null);
});

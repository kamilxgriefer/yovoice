// findPagesV1 (ADR-233 §2.7) against the Firestore emulator: suggest,
// search and the followed-Pages panel, with every exclusion (self, followed,
// blocked, notViewable, renamed in the last 7 days) and the cursors.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-find-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { createPagesReadService } = require("../pages/reads");
const { createPagesLifecycleService } = require("../pages/lifecycle");
const { createDisplayNameService } = require("../profile/display_name");
const { FIND_PAGES_RESPONSE_KEYS, PAGE_CARD_KEYS } = require("../pages/views");
const {
  DAY_MS,
  clearActivation,
  freshUid,
  pageDoc,
  request,
  seedAccount,
  seedOwner,
  seedFollowEdge,
  seedPage,
  setActivation,
  setFollowIndex,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const nowMs = 1_900_000_000_000;
// A search prefix no other suite uses, so the global `pages` collection of the
// shared emulator cannot leak into these assertions.
const PREFIX = "zqxfind";
const created = [];

function service() {
  return createPagesReadService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
}

function find(viewer, mode, query = null, cursor = null) {
  return service().findPagesV1(request(viewer, { mode, query, cursor }));
}

async function listedPage(name, { lastPostOffset = 0, page = {}, baseDays = 10 } = {}) {
  const pageId = freshUid("pgfind");
  await seedPage(db, pageId, nowMs, {
    page: {
      displayName: name,
      postCount: 1,
      listed: true,
      lastPostAt: Timestamp.fromMillis(nowMs + baseDays * DAY_MS - lastPostOffset),
      ...page,
    },
  });
  created.push(pageId);
  return pageId;
}

async function viewerAccount() {
  const uid = freshUid("pgfindv");
  await seedAccount(db, uid, nowMs);
  return uid;
}

beforeEach(() => setActivation(db));
after(async () => {
  await Promise.all(created.map((pageId) =>
    db.doc(`pages/${pageId}`).update({ listed: false, postCount: 0 })));
  await clearActivation(db);
});

test("input is exact and the search query is 2-60 folded characters", async () => {
  const viewer = await viewerAccount();
  for (const data of [
    { mode: "discover", query: null, cursor: null },
    { mode: "suggest", query: "ab", cursor: null },
    { mode: "search", query: "a", cursor: null },
    { mode: "search", query: "x".repeat(61), cursor: null },
    { mode: "search", query: null, cursor: null },
    { mode: "suggest", query: null },
  ]) {
    await assert.rejects(service().findPagesV1(request(viewer, data)),
      (error) => error.code === "invalid-argument", JSON.stringify(data));
  }
});

test("search matches a folded prefix and excludes blocked, hidden and renamed Pages", async () => {
  const viewer = await viewerAccount();
  const cafe = await listedPage(`${PREFIX} Kawiarnia`);
  const bakery = await listedPage(`${PREFIX} Piekarnia`);
  const followedPage = await listedPage(`${PREFIX} Obserwowana`);
  const blocked = await listedPage(`${PREFIX} Zablokowana`);
  const hidden = await listedPage(`${PREFIX} Ukryta`);
  const renamed = await listedPage(`${PREFIX} Nowa nazwa`, {
    page: { nameChangedAt: Timestamp.fromMillis(nowMs - 2 * DAY_MS) },
  });
  const renamedLongAgo = await listedPage(`${PREFIX} Stara zmiana`, {
    page: { nameChangedAt: Timestamp.fromMillis(nowMs - 8 * DAY_MS) },
  });
  await listedPage("Other prefix entirely");
  await db.doc(`users/${blocked}/blocked/${viewer}`).set({ at: Timestamp.fromMillis(nowMs) });
  await db.doc("pageVisibility/v1").set({
    schemaVersion: 1,
    notViewable: { [hidden]: "suspended" },
    readOnlySince: {},
    updatedAt: Timestamp.fromMillis(nowMs),
  }, { merge: true });
  await seedFollowEdge(db, viewer, followedPage, nowMs);
  await setFollowIndex(db, viewer, [followedPage], nowMs);

  const response = await find(viewer, "search", `  ${PREFIX.toUpperCase()} `);
  assert.deepEqual(Object.keys(response).sort(), [...FIND_PAGES_RESPONSE_KEYS]);
  const ids = response.pages.map((card) => card.pageId);
  assert.deepEqual(new Set(ids), new Set([cafe, bakery, followedPage, renamedLongAgo]));
  for (const card of response.pages) {
    assert.deepEqual(Object.keys(card).sort(), [...PAGE_CARD_KEYS]);
  }
  assert.equal(response.pages.find((card) => card.pageId === followedPage).viewerFollows, true,
    "search keeps followed Pages and says so");
  assert.equal(response.pages.find((card) => card.pageId === cafe).viewerFollows, false);
  assert.equal(ids.includes(renamed), false);
  // Ordered by the folded name.
  const names = response.pages.map((card) => card.displayName.toLowerCase());
  assert.deepEqual(names, [...names].sort());
  // Your own Page is never suggested to you, even when it matches.
  const own = await find(cafe, "search", PREFIX);
  assert.equal(own.pages.some((card) => card.pageId === cafe), false);
});

test("suggest pages newest first, excludes followed Pages, and pages with a cursor", async () => {
  const viewer = await viewerAccount();
  const ids = [];
  for (let index = 0; index < 23; index += 1) {
    ids.push(await listedPage(`${PREFIX} Sugestia ${index}`, {
      lastPostOffset: index * 1000,
      baseDays: 20,
    }));
  }
  await seedFollowEdge(db, viewer, ids[0], nowMs);
  await setFollowIndex(db, viewer, [ids[0]], nowMs);
  const first = await find(viewer, "suggest");
  const firstIds = first.pages.map((card) => card.pageId);
  assert.equal(firstIds.includes(ids[0]), false);
  assert.deepEqual(firstIds.slice(0, 20), ids.slice(1, 21));
  assert.equal(first.hasMore, true);
  const second = await find(viewer, "suggest", null, first.nextCursor);
  assert.deepEqual(second.pages.map((card) => card.pageId).slice(0, 2), ids.slice(21, 23));
  await assert.rejects(find(viewer, "search", PREFIX, first.nextCursor),
    (error) => error.code === "invalid-argument");
});

test("the followed-Pages panel pages the index newest first and returns only viewable Pages", async () => {
  const viewer = await viewerAccount();
  const followed = [];
  for (let index = 0; index < 23; index += 1) {
    const pageId = freshUid("pgfollow");
    await seedPage(db, pageId, nowMs, {
      page: index === 5 ? { ownerPaused: true } : {},
    });
    await seedFollowEdge(db, viewer, pageId, nowMs);
    followed.push(pageId);
  }
  const noEdge = freshUid("pgnoedge");
  await seedPage(db, noEdge, nowMs);
  await setFollowIndex(db, viewer, [...followed, noEdge], nowMs);

  const first = await find(viewer, "following");
  const newest = [noEdge, ...[...followed].reverse()];
  // 20 ids consumed: the stale one and the paused one are not returned.
  assert.deepEqual(first.pages.map((card) => card.pageId),
    newest.slice(0, 20).filter((id) => id !== noEdge && id !== followed[5]));
  assert.equal(first.pages.every((card) => card.viewerFollows), true);
  assert.equal(first.hasMore, true);
  const index = (await db.doc(`pageFollowIndex/${viewer}`).get()).data();
  assert.equal(index.pageIds.includes(noEdge), false, "the stale hint is pruned");
  const second = await find(viewer, "following", null, first.nextCursor);
  assert.deepEqual(second.pages.map((card) => card.pageId), newest.slice(20));
  assert.equal(second.hasMore, false);
});

test("the 7-day rename exclusion boundary: 7 days minus 1 ms is out, exactly 7 days is in", async () => {
  const viewer = await viewerAccount();
  const almost = await listedPage(`${PREFIX} Granica prawie`, {
    page: { nameChangedAt: Timestamp.fromMillis(nowMs - 7 * DAY_MS + 1) },
  });
  const exact = await listedPage(`${PREFIX} Granica dokladnie`, {
    page: { nameChangedAt: Timestamp.fromMillis(nowMs - 7 * DAY_MS) },
  });
  const ids = (await find(viewer, "search", `${PREFIX} granica`)).pages.map((card) => card.pageId);
  assert.equal(ids.includes(almost), false);
  assert.equal(ids.includes(exact), true);
});

// S-M6: a rename while paused, then resume, keeps the Page out of Find (search
// and suggest) until day 7 after the rename, not after the resume.
test("rename while paused, resume, and the Page stays out of Find until day 7", async () => {
  let clockMs = nowMs + 400 * DAY_MS;
  const clock = () => clockMs;
  const owner = freshUid("pgflow");
  await seedOwner(db, owner, { nowMs: clockMs });
  await db.doc(`pages/${owner}`).set(pageDoc(owner, clockMs, {
    ownerPaused: true,
    listed: false,
    postCount: 1,
    // Newest of every seeded Page, so suggest's first page would show it.
    lastPostAt: Timestamp.fromMillis(clockMs + 5000 * DAY_MS),
  }));
  created.push(owner);
  const viewer = await viewerAccount();
  const name = `${PREFIX} Przemianowana`;
  await createDisplayNameService({
    firestore: db, TimestampImpl: Timestamp, clock, syncAuthDisplayName: async () => {},
  }).updateMyDisplayName(request(owner, { displayName: name }));
  const renamedAtMs = clockMs;
  // The publicProfiles projection (the trigger's job in production).
  await db.doc(`publicProfiles/${owner}`).update({ displayName: name });
  clockMs += 60_000;
  const resumed = await createPagesLifecycleService({
    firestore: db, TimestampImpl: Timestamp, clock, logger: silentLogger(),
  }).managePageV1(request(owner, {
    requestId: `req-resume-${freshUid()}`, op: "resume",
  }));
  assert.equal(resumed.ownerPaused, false);
  assert.equal((await db.doc(`pages/${owner}`).get()).data().listed, true);

  const reads = createPagesReadService({
    firestore: db, TimestampImpl: Timestamp, clock, logger: silentLogger(),
  });
  const findAt = async (mode, query) => (await reads.findPagesV1(request(viewer, {
    mode, query, cursor: null,
  }))).pages.map((card) => card.pageId);
  for (const atMs of [renamedAtMs + 60_000, renamedAtMs + 7 * DAY_MS - 1]) {
    clockMs = atMs;
    assert.equal((await findAt("search", `${PREFIX} przemian`)).includes(owner), false);
    assert.equal((await findAt("suggest", null)).includes(owner), false);
  }
  clockMs = renamedAtMs + 7 * DAY_MS;
  assert.equal((await findAt("search", `${PREFIX} przemian`)).includes(owner), true);
  assert.equal((await findAt("suggest", null)).includes(owner), true);
});

// setFollow's Premium Pages branch (ADR-233 §2.3) against the Firestore
// emulator: following a running Page (edges + the index hint), the uniform
// refusal for readOnly / hidden / paused / suspended / switched-off Pages,
// a grant that expired by time refused before any sweep, the follow-churn
// scope, unfollow with the kill switch on, and the Creator path unchanged.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-follow-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { setFollow } = require("../friends/social_graph");
const { PAGE_FOLLOW_INDEX_KEYS } = require("../pages/follows");
const {
  DAY_MS,
  clearActivation,
  freshUid,
  pageDoc,
  request,
  seedAccount,
  seedPage,
  setActivation,
  testerGrant,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const runFollow = setFollow.run ?? setFollow;
const UNIFORM = "This creator is not accepting followers.";

function follow(viewer, pageId, following = true) {
  return runFollow(request(viewer, { targetUserId: pageId, following }));
}

function refusedUniformly(error) {
  assert.equal(error.code, "failed-precondition");
  assert.equal(error.message, UNIFORM);
  return true;
}

async function scenario({ page = {}, grant = testerGrant(), user = {} } = {}) {
  const nowMs = Date.now();
  const pageId = freshUid("pgf");
  const viewer = freshUid("pgv");
  await seedPage(db, pageId, nowMs, { page, grant, user });
  await seedAccount(db, viewer, nowMs);
  return { pageId, viewer, nowMs };
}

async function indexOf(uid) {
  const snapshot = await db.doc(`pageFollowIndex/${uid}`).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function edgesOf(viewer, pageId) {
  const [following, follower] = await Promise.all([
    db.doc(`users/${viewer}/following/${pageId}`).get(),
    db.doc(`users/${pageId}/followers/${viewer}`).get(),
  ]);
  return [following.exists, follower.exists];
}

beforeEach(() => setActivation(db));
after(() => clearActivation(db));

test("following a running Page writes both edges, the counters and the index hint", async () => {
  const { pageId, viewer } = await scenario();
  assert.deepEqual(await follow(viewer, pageId), { changed: true, following: true });
  assert.deepEqual(await edgesOf(viewer, pageId), [true, true]);
  const index = await indexOf(viewer);
  assert.deepEqual(Object.keys(index).sort(), [...PAGE_FOLLOW_INDEX_KEYS]);
  assert.deepEqual(index.pageIds, [pageId]);
  assert.equal(index.schemaVersion, 1);
  assert.equal((await db.doc(`users/${pageId}`).get()).data().followerCount, 1);
  // The owner is still notified of a follow (§2.3).
  const notifications = await db.collection(`users/${pageId}/notifications`).get();
  assert.equal(notifications.docs.some((doc) => doc.data().type === "follow"), true);
  // A second follow of another Page appends in follow order.
  const other = await scenario();
  await follow(viewer, other.pageId);
  assert.deepEqual((await indexOf(viewer)).pageIds, [pageId, other.pageId]);
});

test("readOnly, hidden, paused, suspended and switched-off Pages refuse uniformly", async () => {
  const now = Timestamp.fromMillis(Date.now());
  const variants = [
    { page: { status: "readOnly", lapsedAt: now }, grant: null },
    { page: { status: "hidden", lapsedAt: now }, grant: null },
    { page: { ownerPaused: true } },
    { page: { suspended: true, suspendedAt: now, suspensionReason: "spam" } },
  ];
  for (const variant of variants) {
    const { pageId, viewer } = await scenario(variant);
    await assert.rejects(follow(viewer, pageId), refusedUniformly, JSON.stringify(variant.page));
    assert.deepEqual(await edgesOf(viewer, pageId), [false, false]);
    assert.equal(await indexOf(viewer), null);
  }
  // A malformed Page is no Page.
  const malformed = await scenario();
  await db.doc(`pages/${malformed.pageId}`).update({ listed: true });
  await assert.rejects(follow(malformed.viewer, malformed.pageId), refusedUniformly);
  // The kill switch hides Pages, so they take no followers either.
  const off = await scenario();
  await clearActivation(db);
  await assert.rejects(follow(off.viewer, off.pageId), refusedUniformly);
  await setActivation(db, { readAccess: "testers", writeAccess: "testers",
    testerUids: [off.pageId] });
  await assert.rejects(follow(off.viewer, off.pageId), refusedUniformly);
  await setActivation(db, { readAccess: "testers", writeAccess: "testers",
    testerUids: [off.viewer] });
  assert.equal((await follow(off.viewer, off.pageId)).changed, true);
});

test("a grant that expired by time refuses follows before any sweep runs", async () => {
  const { pageId, viewer } = await scenario({
    grant: testerGrant({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }),
  });
  // The stored Page still says active: only the live capability knows.
  assert.equal((await db.doc(`pages/${pageId}`).get()).data().status, "active");
  await assert.rejects(follow(viewer, pageId), refusedUniformly);
  // A paid entitlement does not count while PAGES_ALLOW_PAID_SOURCE is false.
  await db.doc(`entitlements/${pageId}`).set({
    isPremium: true,
    status: "active",
    premiumIdentityEnabled: true,
    currentPeriodEnd: Timestamp.fromMillis(Date.now() + 30 * DAY_MS),
  });
  await assert.rejects(follow(viewer, pageId), refusedUniformly);
  // lapseEnabled:false freezes the downgrade: the stored status rules.
  await setActivation(db, { lapseEnabled: false });
  assert.equal((await follow(viewer, pageId)).changed, true);
});

test("the fourth follow of one Page in 24 h is refused; unfollows never are", async () => {
  const { pageId, viewer } = await scenario();
  for (let round = 0; round < 3; round += 1) {
    assert.equal((await follow(viewer, pageId)).changed, true);
    assert.equal((await follow(viewer, pageId, false)).changed, true);
  }
  await assert.rejects(follow(viewer, pageId), (error) => {
    assert.equal(error.code, "resource-exhausted");
    return true;
  });
  assert.deepEqual(await edgesOf(viewer, pageId), [false, false]);
  // The scope is per Page: another Page is unaffected.
  const other = await scenario();
  assert.equal((await follow(viewer, other.pageId)).changed, true);
});

test("unfollow works with the kill switch on and drops the index hint", async () => {
  const { pageId, viewer } = await scenario();
  await follow(viewer, pageId);
  await clearActivation(db);
  assert.deepEqual(await follow(viewer, pageId, false), { changed: true, following: false });
  assert.deepEqual(await edgesOf(viewer, pageId), [false, false]);
  assert.deepEqual((await indexOf(viewer)).pageIds, []);
  // A stale hint without an edge (a block removed the edges) is repaired too.
  await db.doc(`pageFollowIndex/${viewer}`).set({
    schemaVersion: 1,
    pageIds: [pageId, "another-page"],
    updatedAt: Timestamp.now(),
  });
  assert.deepEqual(await follow(viewer, pageId, false), { changed: false, following: false });
  assert.deepEqual((await indexOf(viewer)).pageIds, ["another-page"]);
  // A malformed index is rewritten canonically.
  await db.doc(`pageFollowIndex/${viewer}`).set({ pageIds: ["x", "x"], junk: 1 });
  await follow(viewer, pageId, false);
  const repaired = await indexOf(viewer);
  assert.deepEqual(Object.keys(repaired).sort(), [...PAGE_FOLLOW_INDEX_KEYS]);
  assert.deepEqual(repaired.pageIds, ["x"]);
});

test("the Creator path is unchanged and writes no Page index", async () => {
  const nowMs = Date.now();
  const creator = freshUid("pgc");
  const viewer = freshUid("pgv");
  await seedAccount(db, viewer, nowMs);
  await seedAccount(db, creator, nowMs, {
    user: {
      accountType: "creator",
      premiumIdentity: true,
      creatorAgeVerified: true,
      creatorAudienceEnabled: true,
    },
  });
  await db.doc(`entitlements/${creator}`).set({
    status: "active",
    isPremium: true,
    premiumIdentityEnabled: true,
    creatorEnabled: true,
    currentPeriodEnd: Timestamp.fromMillis(nowMs + DAY_MS),
  });
  // Works with Pages switched off: the Creator path never reads the switch.
  await clearActivation(db);
  assert.deepEqual(await follow(viewer, creator), { changed: true, following: true });
  assert.deepEqual(await edgesOf(viewer, creator), [true, true]);
  assert.equal(await indexOf(viewer), null);
  // An ordinary account (no Page, no Creator) is refused as before.
  const plain = freshUid("pgp");
  await seedAccount(db, plain, nowMs);
  await setActivation(db);
  await assert.rejects(follow(viewer, plain), refusedUniformly);
});

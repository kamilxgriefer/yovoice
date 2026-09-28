// getPagePostMediaAccessV1 (ADR-233 §2.5, package B2) against the Firestore
// emulator, with the REAL Pages Storage adapter over an in-memory bucket.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-media-access-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { createPagesMediaStorageAdapter } = require("../pages/media_storage");
const {
  PAGE_MEDIA_ACCESS_RESPONSE_KEYS,
  PAGE_MEDIA_GRANT_KEYS,
  PAGE_MEDIA_GRANT_TTL_MS,
  PAGE_STAFF_ROLES,
  PAGES_MEDIA_RATE_LIMITS,
  createPagesMediaAccessService,
} = require("../pages/media_access");
const {
  DAY_MS,
  clearActivation,
  freshUid,
  newMediaId,
  newPostId,
  photoMedia,
  postDoc,
  request,
  seedAccount,
  seedPage,
  setActivation,
  silentLogger,
  voiceMedia,
} = require("./helpers/pages_fixture");
const { FakeBucket, STRIPPED_JPEG } = require("./helpers/pages_media_fixture");

const db = getFirestore();
let nowMs = 1_900_000_000_000;

beforeEach(async () => {
  nowMs += DAY_MS;
  await setActivation(db);
});

after(async () => {
  await clearActivation(db);
});

function harness({ rateLimits = PAGES_MEDIA_RATE_LIMITS } = {}) {
  const bucket = new FakeBucket({ nowMs: () => nowMs });
  const access = createPagesMediaAccessService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(bucket),
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
    rateLimits,
  });
  return { bucket, access };
}

function rejectsWith(promise, code, reason = undefined) {
  return assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `${error.code}: ${error.message}`);
    if (reason !== undefined) assert.equal(error.details?.reason, reason, error.message);
    return true;
  });
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

/// A running Page with one photo post (two photos) whose objects exist.
async function photoPost(h, overrides = {}) {
  const pageId = freshUid("pgmedia");
  await seedPage(db, pageId, nowMs, { page: { postCount: 1, listed: true } });
  const postId = newPostId();
  const media = photoMedia(pageId, postId, 2).map((entry) => {
    const generation = h.bucket.put(entry.storagePath, STRIPPED_JPEG, {
      contentType: "image/jpeg", token: false,
    });
    return { ...entry, generation };
  });
  await db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, nowMs, {
    kind: "photo", media, ...overrides,
  }));
  return { pageId, postId, media };
}

async function viewer() {
  const uid = freshUid("viewer");
  await seedAccount(db, uid, nowMs);
  return uid;
}

async function staff(role = "moderator", mirror = role) {
  const uid = freshUid("staff");
  await seedAccount(db, uid, nowMs, { user: { role: mirror } });
  return uid;
}

async function reported(postId, pageId, reportId = "report-1") {
  await db.doc(`pagePostOpenReports/${postId}`).set({
    schemaVersion: 1, postId, pageId, count: 1, lastReportId: reportId,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
}

test("a viewer gets exact, 90-second, generation-bound grants in request order", async () => {
  const h = harness();
  const { postId, media } = await photoPost(h);
  const uid = await viewer();
  const ids = [media[1].mediaId, media[0].mediaId];
  const response = await h.access.getPagePostMediaAccessV1(request(uid, { postId, mediaIds: ids },
    { verified: false }));
  assert.deepEqual(Object.keys(response).sort(), [...PAGE_MEDIA_ACCESS_RESPONSE_KEYS]);
  assert.deepEqual(response.grants.map((grant) => grant.mediaId), ids);
  for (const grant of response.grants) {
    assert.deepEqual(Object.keys(grant).sort(), [...PAGE_MEDIA_GRANT_KEYS]);
    assert.equal(grant.expiresAtMs, nowMs + PAGE_MEDIA_GRANT_TTL_MS);
    assert.match(grant.url, /^https:\/\/storage\.googleapis\.com\//u);
  }
  assert.deepEqual(h.bucket.signed.map((entry) => entry.generation),
    [media[1].generation, media[0].generation]);
  // Memoised for 60 s per instance: no second signature.
  nowMs += 30_000;
  const again = await h.access.getPagePostMediaAccessV1(request(uid, { postId, mediaIds: ids }));
  assert.deepEqual(again.grants, response.grants);
  assert.equal(h.bucket.signed.length, 2);
  nowMs += 31_000;
  await h.access.getPagePostMediaAccessV1(request(uid, { postId, mediaIds: ids }));
  assert.equal(h.bucket.signed.length, 4);
});

test("mediaId -> path comes only from the post: foreign or malformed ids are refused", async () => {
  const h = harness();
  const { postId, media } = await photoPost(h);
  const uid = await viewer();
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
    { postId, mediaIds: [newMediaId()] })), "invalid-argument");
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
    { postId, mediaIds: ["page_posts/x/y/z.jpg"] })), "invalid-argument");
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
    { postId, mediaIds: [media[0].mediaId, media[0].mediaId] })), "invalid-argument");
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
    { postId: "pp_short", mediaIds: [media[0].mediaId] })), "invalid-argument");
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
    { postId, mediaIds: [media[0].mediaId], storagePath: "x" })), "invalid-argument");
  // A missing post is the uniform refusal.
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
    { postId: newPostId(), mediaIds: [media[0].mediaId] })), "permission-denied", "pageUnavailable");
});

test("blocked, paused, held-for-visitor and switched-off are uniform refusals", async () => {
  const h = harness();
  const { pageId, postId, media } = await photoPost(h);
  const uid = await viewer();
  const ask = (caller = uid) => h.access.getPagePostMediaAccessV1(request(caller,
    { postId, mediaIds: [media[0].mediaId] }));

  await db.doc(`users/${pageId}/blocked/${uid}`).set({ uid, blockedAt: Timestamp.fromMillis(nowMs) });
  await rejectsWith(ask(), "permission-denied", "pageUnavailable");
  await db.doc(`users/${pageId}/blocked/${uid}`).delete();
  await ask();

  await db.doc(`pages/${pageId}`).update({ ownerPaused: true, listed: false });
  await rejectsWith(ask(), "permission-denied", "pageUnavailable");
  // The owner still sees their own paused Page's media.
  await ask(pageId);
  await db.doc(`pages/${pageId}`).update({ ownerPaused: false, listed: true });

  await db.doc(`pagePosts/${postId}`).update({ status: "held", heldAt: Timestamp.fromMillis(nowMs) });
  await rejectsWith(ask(), "permission-denied", "pageUnavailable");
  // Held media reach the owner (with the notice) ...
  await ask(pageId);
  await db.doc(`pagePosts/${postId}`).update({
    status: "removed", removedAt: Timestamp.fromMillis(nowMs), removedReason: "spam",
  });
  // ... but a removed post is staff-only.
  await rejectsWith(ask(pageId), "permission-denied", "pageUnavailable");

  await clearActivation(db);
  await rejectsWith(ask(), "failed-precondition", "pagesNotEnabled");
});

test("staff open held, removed and deleted evidence with a report, and every grant is audited", async () => {
  const h = harness();
  const moderator = await staff("moderator");
  for (const status of ["held", "removed", "deleted"]) {
    const at = Timestamp.fromMillis(nowMs);
    const extra = status === "held"
      ? { heldAt: at }
      : status === "removed"
        ? { removedAt: at, removedReason: "spam" }
        : { deletedAt: at, moderationEvidence: { evidenceVersion: 1, metadataFingerprint: "a".repeat(64) } };
    const { pageId, postId, media } = await photoPost(h, { status, ...extra });
    const ask = (caller, ids = [media[0].mediaId, media[1].mediaId], role = "moderator") =>
      h.access.getPagePostMediaAccessV1(request(caller, { postId, mediaIds: ids }, { role }));
    // No report on it: staff get the uniform refusal too.
    await rejectsWith(ask(moderator), "permission-denied", "pageUnavailable");
    await reported(postId, pageId, `report-${status}`);
    const response = await ask(moderator);
    assert.equal(response.grants.length, 2);
    const audit = await db.collection("pageStaffMediaAudit").where("postId", "==", postId).get();
    assert.equal(audit.size, 2);
    for (const row of audit.docs) {
      assert.deepEqual(Object.keys(row.data()).sort(), ["at", "mediaId", "postId", "reportId", "staffUid"]);
      assert.equal(row.data().staffUid, moderator);
      assert.equal(row.data().reportId, `report-${status}`);
    }
    // An ordinary account, even one claiming the role, is refused.
    const pretender = await staff("moderator", "user");
    await rejectsWith(ask(pretender), "permission-denied", "pageUnavailable");
    await rejectsWith(ask(await viewer(), undefined, null), "permission-denied", "pageUnavailable");
  }
});

test("the staff branch works with the kill switch on; ordinary viewers do not", async () => {
  const h = harness();
  const { pageId, postId, media } = await photoPost(h, {
    status: "held", heldAt: Timestamp.fromMillis(nowMs),
  });
  await reported(postId, pageId);
  await clearActivation(db);
  for (const role of PAGE_STAFF_ROLES) {
    const uid = await staff(role);
    const response = await h.access.getPagePostMediaAccessV1(request(uid,
      { postId, mediaIds: [media[0].mediaId] }, { role }));
    assert.equal(response.grants.length, 1);
  }
  await rejectsWith(h.access.getPagePostMediaAccessV1(request(await viewer(),
    { postId, mediaIds: [media[0].mediaId] })), "failed-precondition", "pagesNotEnabled");
  // support and auditor are not report staff.
  for (const role of ["support", "auditor"]) {
    const uid = await staff(role);
    await rejectsWith(h.access.getPagePostMediaAccessV1(request(uid,
      { postId, mediaIds: [media[0].mediaId] }, { role })), "failed-precondition", "pagesNotEnabled");
  }
});

test("staff open a PUBLISHED post only while a report on it is open, blocked or switched off", async () => {
  const h = harness();
  const moderator = await staff("moderator");
  const { pageId, postId, media } = await photoPost(h);
  // The Page blocked the moderator: the viewer branch refuses.
  await db.doc(`users/${pageId}/blocked/${moderator}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  const ask = () => h.access.getPagePostMediaAccessV1(request(moderator,
    { postId, mediaIds: [media[0].mediaId] }, { role: "moderator" }));
  await rejectsWith(ask(), "permission-denied", "pageUnavailable");
  await reported(postId, pageId, "report-open");
  assert.equal((await ask()).grants.length, 1);
  let audit = await db.collection("pageStaffMediaAudit").where("postId", "==", postId).get();
  assert.equal(audit.size, 1);
  assert.equal(audit.docs[0].data().reportId, "report-open");
  // With the kill switch on it still works (evidence review).
  await clearActivation(db);
  assert.equal((await ask()).grants.length, 1);
  // Once every report closed, a published post is the viewers' again.
  await db.doc(`pagePostOpenReports/${postId}`).update({ count: 0 });
  await rejectsWith(ask(), "permission-denied", "pageUnavailable");
  await setActivation(db);
  await rejectsWith(ask(), "permission-denied", "pageUnavailable");
  audit = await db.collection("pageStaffMediaAudit").where("postId", "==", postId).get();
  assert.equal(audit.size, 2);
});

test("a voice clip grant, and the per-minute, hourly and daily caps", async () => {
  const limits = {
    "pages.media": { maxEvents: 60, windowMs: 60_000 },
    "pages.mediaHourly": { maxEvents: 3, windowMs: 60 * 60_000 },
    "pages.mediaDaily": { maxEvents: 5, windowMs: DAY_MS },
  };
  const h = harness({ rateLimits: limits });
  const pageId = freshUid("pgvoice");
  await seedPage(db, pageId, nowMs, { page: { postCount: 1, listed: true } });
  const postId = newPostId();
  const [clip] = voiceMedia(pageId, postId);
  await db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, nowMs, { kind: "voice", media: [clip] }));
  const uid = await viewer();
  const ask = () => h.access.getPagePostMediaAccessV1(request(uid, { postId, mediaIds: [clip.mediaId] }));
  const first = await ask();
  assert.equal(first.grants[0].mediaId, clip.mediaId);
  await ask();
  await ask();
  await rejectsWith(ask(), "resource-exhausted");
  nowMs += 61 * 60_000;
  await ask();
  await ask();
  await rejectsWith(ask(), "resource-exhausted");
  assert.equal(PAGES_MEDIA_RATE_LIMITS["pages.media"].maxEvents, 60);
  assert.equal(PAGES_MEDIA_RATE_LIMITS["pages.mediaHourly"].maxEvents, 600);
  assert.equal(PAGES_MEDIA_RATE_LIMITS["pages.mediaDaily"].maxEvents, 3000);
  assert.equal(await dataOf(`pagePosts/${postId}`) !== null, true);
});

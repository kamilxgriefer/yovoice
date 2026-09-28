// Page posts (ADR-233 §2.4, package B2): reservePagePostMediaV1,
// publishPagePostV1 and managePagePostV1, against the Firestore emulator.
// Storage is an in-memory bucket (helpers/pages_media_fixture.js) under the
// REAL Pages Storage adapter and the REAL trusted probe (reels/probe.js), so
// the magic-number sniff, the m4a duration and the JPEG metadata walk all run
// on real bytes: a GPS-tagged JPEG, a stripped copy and a 3 s AAC clip.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-posts-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { createTrustedGcsMediaProbe } = require("../reels/probe");
const { createPagesMediaStorageAdapter } = require("../pages/media_storage");
const { createPagesMaintenanceService } = require("../pages/maintenance");
const {
  MANAGE_RESPONSE_KEYS,
  PAGES_POST_RATE_LIMITS,
  createPagesPostService,
} = require("../pages/posts");
const {
  PAGE_BUDGET_KEYS,
  PAGE_MEDIA_LEASE_KEYS,
  PAGE_MEDIA_RESERVATION_KEYS,
  PAGE_MEDIA_RESERVATION_TTL_MS,
  pageBudgetDay,
  pagePostMediaJobReferences,
  releaseHeldPagePostMediaJobs,
} = require("../pages/media_contract");
const { PAGE_POST_VIEW_KEYS } = require("../pages/views");
const { pagePostMalformedReason } = require("../pages/post_contract");
const {
  PAGE_EVIDENCE_RETENTION_KEYS,
  PAGE_EVIDENCE_RETENTION_MS,
} = require("../pages/report_contract");
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
  seedPage,
  setActivation,
  silentLogger,
} = require("./helpers/pages_fixture");
const {
  FakeBucket,
  GPS_JPEG,
  PNG_BYTES,
  STRIPPED_JPEG,
  VOICE_M4A,
  VOICE_M4A_MS,
  WEBP_BYTES,
} = require("./helpers/pages_media_fixture");

const db = getFirestore();
const BASE_MS = 1_900_000_000_000;
let nowMs = BASE_MS;
const RELAXED = Object.freeze(Object.fromEntries(Object.keys(PAGES_POST_RATE_LIMITS)
  .map((scope) => [scope, { maxEvents: 1000, windowMs: 60_000 }])));

beforeEach(async () => {
  // A fresh UTC day at 08:00 per test, so the budget day never rolls over
  // mid-test.
  nowMs = (Math.floor(nowMs / DAY_MS) + 1) * DAY_MS + 8 * 60 * 60 * 1000;
  await setActivation(db);
});

after(async () => {
  await clearActivation(db);
});

function harness({ rateLimits = PAGES_POST_RATE_LIMITS } = {}) {
  const bucket = new FakeBucket({ nowMs: () => nowMs });
  const storage = createPagesMediaStorageAdapter(bucket);
  const logger = silentLogger();
  const maintenance = createPagesMaintenanceService({
    firestore: db, storage, TimestampImpl: Timestamp, clock: () => nowMs, logger,
  });
  const posts = createPagesPostService({
    firestore: db,
    storage,
    probeMedia: createTrustedGcsMediaProbe(bucket),
    maintenance,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger,
    rateLimits,
  });
  return { bucket, storage, maintenance, posts, logger };
}

function sortedKeys(value) {
  return Object.keys(value).sort();
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

function photoItems(count, size = STRIPPED_JPEG.length) {
  return Array.from({ length: count }, (_, index) => ({
    index, contentType: "image/jpeg", size, width: 32, height: 24, durationMs: null,
  }));
}

function voiceItems(durationMs = 3000, size = VOICE_M4A.length) {
  return [{ index: 0, contentType: "audio/mp4", size, width: null, height: null, durationMs }];
}

function reserveData(kind, items, overrides = {}) {
  return { requestId: requestId("reserve"), kind, items, ...overrides };
}

function upload(bucket, item, bytes, { contentType = null, metadata = null, headers = {} } = {}) {
  return bucket.put(item.storagePath, bytes, {
    contentType: contentType ?? (item.storagePath.endsWith(".jpg") ? "image/jpeg" : "audio/mp4"),
    metadata: metadata ?? item.metadata,
    headers,
  });
}

function publishData(kind, { postId = null, mediaIds = [], text = "", commentsEnabled = true } = {}) {
  return { requestId: requestId("publish"), postId, kind, text, mediaIds, commentsEnabled };
}

async function pageWithOwner(pageOverrides = {}, options = {}) {
  const uid = freshUid("pgpost");
  await seedPage(db, uid, nowMs, { page: pageOverrides, ...options });
  return uid;
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

/// Reserve + upload the stripped fixture for every item.
async function reservedPhotos(h, uid, count = 1) {
  const reserved = await h.posts.reservePagePostMediaV1(
    request(uid, reserveData("photo", photoItems(count))));
  for (const item of reserved.items) upload(h.bucket, item, STRIPPED_JPEG);
  return reserved;
}

// ------------------------------------------------------------------ reserve

test("reserve: exact input, server-allocated ids, exact documents, replay", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  // A client postId is not part of the contract (S-m8).
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(1), { postId: newPostId() }))), "invalid-argument");
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", [{ ...photoItems(1)[0], contentType: "image/png" }]))), "invalid-argument");
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(11)))), "invalid-argument");
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", [{ ...photoItems(1)[0], size: 4 * 1024 * 1024 + 1 }]))), "invalid-argument");
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("voice", voiceItems(61_000)))), "invalid-argument");

  const data = reserveData("photo", photoItems(2));
  const reserved = await h.posts.reservePagePostMediaV1(request(uid, data));
  assert.deepEqual(sortedKeys(reserved), ["items", "postId"]);
  assert.match(reserved.postId, /^pp_[a-f0-9]{40}$/u);
  assert.equal(reserved.items.length, 2);
  for (const item of reserved.items) {
    assert.deepEqual(sortedKeys(item), ["expiresAt", "mediaId", "metadata", "storagePath"]);
    assert.match(item.mediaId, /^pm_[a-f0-9]{40}$/u);
    assert.equal(item.storagePath, `page_posts/${uid}/${reserved.postId}/${item.mediaId}.jpg`);
    assert.deepEqual(item.metadata, {
      yovoicePageId: uid,
      yovoicePostId: reserved.postId,
      yovoiceMediaId: item.mediaId,
      yovoiceMediaType: "image",
    });
    assert.equal(item.expiresAt, nowMs + PAGE_MEDIA_RESERVATION_TTL_MS);
    const stored = await dataOf(`pagePostMediaReservations/${item.mediaId}`);
    assert.deepEqual(sortedKeys(stored), [...PAGE_MEDIA_RESERVATION_KEYS]);
    assert.equal(stored.status, "uploading");
    assert.equal(stored.size, STRIPPED_JPEG.length);
  }
  const lease = await dataOf(`pagePostMediaLeases/${uid}`);
  assert.deepEqual(sortedKeys(lease), [...PAGE_MEDIA_LEASE_KEYS]);
  assert.deepEqual(lease.mediaIds, reserved.items.map((item) => item.mediaId));
  const budget = await dataOf(`pagePostBudgets/${uid}_${pageBudgetDay(nowMs)}`);
  assert.deepEqual(sortedKeys(budget), [...PAGE_BUDGET_KEYS]);
  // Bytes and reservations are charged AT RESERVE.
  assert.equal(budget.reservations, 2);
  assert.equal(budget.bytes, 2 * STRIPPED_JPEG.length);
  assert.equal(budget.posts, 0);
  // Same requestId: the same set, charged once.
  assert.deepEqual(await h.posts.reservePagePostMediaV1(request(uid, data)), reserved);
  assert.equal((await dataOf(`pagePostBudgets/${uid}_${pageBudgetDay(nowMs)}`)).reservations, 2);
});

test("reserve: one open lease per owner; a new set only after it expires", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  await h.posts.reservePagePostMediaV1(request(uid, reserveData("photo", photoItems(1))));
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("voice", voiceItems()))), "resource-exhausted", "pageUploadInProgress");
  nowMs += PAGE_MEDIA_RESERVATION_TTL_MS + 1;
  const next = await h.posts.reservePagePostMediaV1(request(uid, reserveData("voice", voiceItems())));
  assert.equal(next.items[0].storagePath.endsWith(".m4a"), true);
});

test("reserve: the daily budget refuses the 31st media reservation and 11th post", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner();
  for (let round = 0; round < 3; round += 1) {
    await h.posts.reservePagePostMediaV1(request(uid, reserveData("photo", photoItems(10))));
    nowMs += PAGE_MEDIA_RESERVATION_TTL_MS + 1;
  }
  assert.equal((await dataOf(`pagePostBudgets/${uid}_${pageBudgetDay(nowMs)}`)).reservations, 30);
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(1)))), "resource-exhausted", "pagePostBudget");

  // Posts: ten text posts a day, the eleventh is refused (and so is a reserve).
  const other = await pageWithOwner();
  for (let index = 0; index < 10; index += 1) {
    await h.posts.publishPagePostV1(request(other, publishData("text", { text: `Post ${index}` })));
  }
  await rejectsWith(h.posts.publishPagePostV1(request(other,
    publishData("text", { text: "One more" }))), "resource-exhausted", "pagePostBudget");
  await rejectsWith(h.posts.reservePagePostMediaV1(request(other,
    reserveData("photo", photoItems(1)))), "resource-exhausted", "pagePostBudget");
  assert.equal((await dataOf(`pages/${other}`)).postCount, 10);
});

test("reserve, publish, pin: switched off, gated, muted and unverified are refused", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(uid, postId, nowMs));

  await clearActivation(db);
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(1)))), "failed-precondition", "pagesNotEnabled");
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "Hi" }))), "failed-precondition", "pagesNotEnabled");
  await rejectsWith(h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId, op: "pin" })), "failed-precondition", "pagesNotEnabled");
  await setActivation(db, { readAccess: "testers", writeAccess: "testers", testerUids: [freshUid()] });
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "Hi" }))), "failed-precondition", "pagesNotEnabled");
  await setActivation(db);

  // Unverified e-mail.
  const unverified = { verified: false };
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(1)), unverified)), "failed-precondition");
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "Hi" }), unverified)), "failed-precondition");
  await rejectsWith(h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId, op: "pin" }, unverified)), "failed-precondition");

  // Communication mute.
  await db.doc(`restrictions/${uid}`).set({ type: "communicationMute", expiresAt: null });
  await rejectsWith(h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(1)))), "permission-denied");
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "Hi" }))), "permission-denied");
  await rejectsWith(h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId, op: "pin" })), "permission-denied");
  await db.doc(`restrictions/${uid}`).delete();

  // No canonical grant: the gate refuses; staffPreview never passes.
  const ungated = await pageWithOwner({}, { grant: null });
  await rejectsWith(h.posts.reservePagePostMediaV1(request(ungated,
    reserveData("photo", photoItems(1)), { role: "moderator" })),
  "failed-precondition", "pageAccessRequired");
  // A paused or suspended Page takes no posts.
  const paused = await pageWithOwner({ ownerPaused: true });
  await rejectsWith(h.posts.reservePagePostMediaV1(request(paused,
    reserveData("photo", photoItems(1)))), "failed-precondition", "pagePaused");
  const suspended = await pageWithOwner({
    suspended: true, suspendedAt: Timestamp.fromMillis(nowMs), suspensionReason: "spam",
  });
  await rejectsWith(h.posts.publishPagePostV1(request(suspended,
    publishData("text", { text: "Hi" }))), "failed-precondition", "pageSuspended");
  // Not a Page at all.
  const person = freshUid("person");
  await seedAccount(db, person, nowMs);
  await db.doc(`vipGrants/${person}`).set({
    source: "testerProgram", expiresAt: null, revoked: false, grantedBy: "owner-console",
  });
  await rejectsWith(h.posts.publishPagePostV1(request(person,
    publishData("text", { text: "Hi" }))), "failed-precondition", "pageNotFound");
});

// ------------------------------------------------------------------ publish

test("publish: a photo post, probed, hardened, exact, one transaction", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  const reserved = await reservedPhotos(h, uid, 2);
  const mediaIds = reserved.items.map((item) => item.mediaId).reverse();
  const view = await h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: reserved.postId, mediaIds, text: "  Nowe ciasto\r\ndziś 👨\u200d👩\u200d👧  ",
  })));
  assert.deepEqual(sortedKeys(view), [...PAGE_POST_VIEW_KEYS]);
  assert.equal(view.postId, reserved.postId);
  assert.equal(view.state, "published");
  assert.equal(view.text, "Nowe ciasto\ndziś 👨\u200d👩\u200d👧");
  // Display order is the publish order.
  assert.deepEqual(view.media.map((entry) => entry.mediaId), mediaIds);
  assert.deepEqual(view.media[0], {
    mediaId: mediaIds[0], type: "image", contentType: "image/jpeg",
    width: 32, height: 24, durationMs: null,
  });

  const post = await dataOf(`pagePosts/${reserved.postId}`);
  assert.equal(pagePostMalformedReason(post, reserved.postId), null);
  assert.equal(post.media[0].generation, h.bucket.metadataOf(post.media[0].storagePath).generation);
  // The client-minted download token is revoked.
  for (const entry of post.media) {
    assert.equal(h.bucket.metadataOf(entry.storagePath).metadata.firebaseStorageDownloadTokens,
      undefined);
  }
  for (const item of reserved.items) {
    assert.equal(await dataOf(`pagePostMediaReservations/${item.mediaId}`), null);
  }
  assert.equal(await dataOf(`pagePostMediaLeases/${uid}`), null);
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.postCount, 1);
  assert.equal(page.listed, true);
  assert.equal(page.lastPostAt.toMillis(), nowMs);
  assert.equal((await dataOf(`pagePostBudgets/${uid}_${pageBudgetDay(nowMs)}`)).posts, 1);
  // A media post without its upload is refused.
  await rejectsWith(h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: newPostId(), mediaIds: [reserved.items[0].mediaId],
  }))), "failed-precondition");
});

test("publish: replay of the same request is free and identical", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  const data = publishData("text", { text: "Otwarte od 7." });
  const first = await h.posts.publishPagePostV1(request(uid, data));
  for (let index = 0; index < 5; index += 1) {
    assert.deepEqual(await h.posts.publishPagePostV1(request(uid, data)), first);
  }
  assert.equal((await dataOf(`pages/${uid}`)).postCount, 1);
  // The 3/10 min rate is for new work only.
  await h.posts.publishPagePostV1(request(uid, publishData("text", { text: "Two" })));
  await h.posts.publishPagePostV1(request(uid, publishData("text", { text: "Three" })));
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "Four" }))), "resource-exhausted");
});

test("publish: a GPS-tagged JPEG is refused; the stripped copy is accepted", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  const reserved = await h.posts.reservePagePostMediaV1(request(uid,
    reserveData("photo", photoItems(1, GPS_JPEG.length))));
  upload(h.bucket, reserved.items[0], GPS_JPEG);
  await rejectsWith(h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: reserved.postId, mediaIds: [reserved.items[0].mediaId],
  }))), "failed-precondition", "pageMediaMetadata");
  assert.equal(await dataOf(`pagePosts/${reserved.postId}`), null);

  nowMs += PAGE_MEDIA_RESERVATION_TTL_MS + 1;
  const clean = await reservedPhotos(h, uid, 1);
  await h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: clean.postId, mediaIds: [clean.items[0].mediaId],
  })));
  assert.equal((await dataOf(`pagePosts/${clean.postId}`)).status, "published");
});

test("publish: PNG or WebP bytes, a size, metadata, header or frame mismatch are refused", async () => {
  const h = harness({ rateLimits: RELAXED });
  for (const [bytes, options] of [
    [PNG_BYTES, {}],
    [WEBP_BYTES, {}],
    // Declared size differs from the object.
    [Buffer.concat([STRIPPED_JPEG, Buffer.alloc(3)]), {}],
    // Wrong binding metadata.
    [STRIPPED_JPEG, { metadata: "wrong" }],
    // Wrong stored content type.
    [STRIPPED_JPEG, { contentType: "image/png" }],
    // HTTP headers storage.rules would refuse (audit 2026-09-28).
    [STRIPPED_JPEG, { headers: { contentEncoding: "gzip" } }],
    [STRIPPED_JPEG, { headers: { cacheControl: "public, max-age=31536000" } }],
    [STRIPPED_JPEG, { headers: { contentDisposition: "attachment; filename=\"invoice.html\"" } }],
    // The declared size is not the JPEG frame's (the "pixel bomb" rule).
    [STRIPPED_JPEG, { declared: { width: 64, height: 48 } }],
  ]) {
    const uid = await pageWithOwner();
    const items = photoItems(1).map((entry) => ({ ...entry, ...(options.declared ?? {}) }));
    const reserved = await h.posts.reservePagePostMediaV1(request(uid,
      reserveData("photo", items)));
    const item = reserved.items[0];
    upload(h.bucket, item, bytes, {
      contentType: options.contentType ?? null,
      metadata: options.metadata === "wrong"
        ? { ...item.metadata, yovoicePostId: newPostId() }
        : null,
      headers: options.headers ?? {},
    });
    await rejectsWith(h.posts.publishPagePostV1(request(uid, publishData("photo", {
      postId: reserved.postId, mediaIds: [item.mediaId],
    }))), "failed-precondition", "pageMediaInvalid");
    assert.equal(await dataOf(`pagePosts/${reserved.postId}`), null);
  }
});

test("publish: a voice clip stores the probe's duration; a false declaration is refused", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner();
  const reserved = await h.posts.reservePagePostMediaV1(request(uid,
    reserveData("voice", voiceItems(3000))));
  upload(h.bucket, reserved.items[0], VOICE_M4A);
  const view = await h.posts.publishPagePostV1(request(uid, publishData("voice", {
    postId: reserved.postId, mediaIds: [reserved.items[0].mediaId],
  })));
  assert.equal(view.media[0].durationMs, VOICE_M4A_MS);
  assert.equal((await dataOf(`pagePosts/${reserved.postId}`)).media[0].durationMs, VOICE_M4A_MS);

  const liar = await pageWithOwner();
  const lie = await h.posts.reservePagePostMediaV1(request(liar,
    reserveData("voice", voiceItems(30_000))));
  upload(h.bucket, lie.items[0], VOICE_M4A);
  await rejectsWith(h.posts.publishPagePostV1(request(liar, publishData("voice", {
    postId: lie.postId, mediaIds: [lie.items[0].mediaId],
  }))), "failed-precondition", "pageMediaInvalid");
  // A photo id on a voice post, and an id outside the upload, are refused.
  await rejectsWith(h.posts.publishPagePostV1(request(liar, publishData("photo", {
    postId: lie.postId, mediaIds: [lie.items[0].mediaId],
  }))), "invalid-argument");
});

test("publish: text rules, and the gate is re-derived at publish time", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner();
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "   \u200d " }))), "invalid-argument");
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "evil \u202e txt" }))), "invalid-argument");
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "x".repeat(5001) }))), "invalid-argument");
  await rejectsWith(h.posts.publishPagePostV1(request(uid,
    publishData("text", { text: "Hi", postId: newPostId() }))), "invalid-argument");

  const reserved = await reservedPhotos(h, uid, 1);
  // The grant is revoked between reserve and publish.
  await db.doc(`vipGrants/${uid}`).update({ revoked: true });
  await rejectsWith(h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: reserved.postId, mediaIds: [reserved.items[0].mediaId],
  }))), "failed-precondition", "pageAccessRequired");
  // An expired upload cannot publish.
  await db.doc(`vipGrants/${uid}`).update({ revoked: false });
  nowMs += PAGE_MEDIA_RESERVATION_TTL_MS + 1;
  await rejectsWith(h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: reserved.postId, mediaIds: [reserved.items[0].mediaId],
  }))), "deadline-exceeded", "pageUploadExpired");
});

test("publish restores a lapsed Page whose capability is live again", async () => {
  const h = harness();
  const lapsedAt = Timestamp.fromMillis(nowMs - 5 * DAY_MS);
  const uid = await pageWithOwner({ status: "readOnly", lapsedAt });
  await db.doc("pageVisibility/v1").set({
    schemaVersion: 1,
    notViewable: {},
    readOnlySince: { [uid]: lapsedAt.toMillis() },
    updatedAt: Timestamp.fromMillis(nowMs),
  }, { merge: true });
  await h.posts.publishPagePostV1(request(uid, publishData("text", { text: "Back!" })));
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "active");
  assert.equal(page.lapsedAt, null);
  assert.equal(page.listed, true);
  const visibility = await dataOf("pageVisibility/v1");
  assert.equal(visibility.readOnlySince?.[uid], undefined);
});

// ------------------------------------------------------------------ manage

test("manage: pin, unpin and comments on/off, exact response", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner();
  const view = await h.posts.publishPagePostV1(request(uid, publishData("text", { text: "Pin me" })));
  const pinned = await h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: view.postId, op: "pin" }));
  assert.deepEqual(sortedKeys(pinned), [...MANAGE_RESPONSE_KEYS]);
  assert.deepEqual(pinned, {
    schemaVersion: 1, op: "pin", postId: view.postId, deleted: false, pinned: true,
    commentsEnabled: true,
  });
  assert.equal((await dataOf(`pages/${uid}`)).pinnedPostId, view.postId);
  const off = await h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: view.postId, op: "setCommentsEnabled", commentsEnabled: false }));
  assert.equal(off.commentsEnabled, false);
  assert.equal((await dataOf(`pagePosts/${view.postId}`)).commentsEnabled, false);
  const unpinned = await h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: view.postId, op: "unpin" }));
  assert.equal(unpinned.pinned, false);
  assert.equal((await dataOf(`pages/${uid}`)).pinnedPostId, null);

  // A held post cannot be pinned; someone else's post is the uniform refusal.
  const heldId = newPostId();
  await db.doc(`pagePosts/${heldId}`).set(postDoc(uid, heldId, nowMs, {
    status: "held", heldAt: Timestamp.fromMillis(nowMs),
  }));
  await rejectsWith(h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: heldId, op: "pin" })), "failed-precondition");
  const stranger = await pageWithOwner();
  await rejectsWith(h.posts.managePagePostV1(request(stranger,
    { requestId: requestId(), postId: view.postId, op: "pin" })), "permission-denied", "pageUnavailable");
  await rejectsWith(h.posts.managePagePostV1(request(stranger,
    { requestId: requestId(), postId: newPostId(), op: "pin" })), "permission-denied", "pageUnavailable");
  // The postId format is checked first.
  await rejectsWith(h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: "pp_nope", op: "bogus" })), "invalid-argument");
});

test("delete: a published post with no report is hard-deleted and cleaned up", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner();
  const reserved = await reservedPhotos(h, uid, 2);
  const view = await h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: reserved.postId, mediaIds: reserved.items.map((item) => item.mediaId),
  })));
  await h.posts.managePagePostV1(request(uid, { requestId: requestId(), postId: view.postId, op: "pin" }));
  // Likes and comments to clean up, more than one batch of comments.
  const fan = freshUid("fan");
  await seedAccount(db, fan, nowMs);
  await db.doc(`pagePosts/${view.postId}/likes/${fan}`).set({
    schemaVersion: 1, userId: fan, postId: view.postId, createdAt: Timestamp.fromMillis(nowMs),
  });
  const post = await dataOf(`pagePosts/${view.postId}`);
  const writer = db.bulkWriter();
  for (let index = 0; index < 405; index += 1) {
    const commentId = newCommentId();
    writer.set(db.doc(`pagePostComments/${commentId}`), commentDoc(post, commentId, fan, nowMs + index));
  }
  await writer.close();

  // Deletion is a safety action: kill switch on, muted, unverified.
  await clearActivation(db);
  await db.doc(`restrictions/${uid}`).set({ type: "communicationMute", expiresAt: null });
  const result = await h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: view.postId, op: "delete" }, { verified: false }));
  assert.deepEqual(result, {
    schemaVersion: 1, op: "delete", postId: view.postId, deleted: true, pinned: false,
    commentsEnabled: true,
  });
  assert.equal(await dataOf(`pagePosts/${view.postId}`), null);
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.postCount, 0);
  assert.equal(page.pinnedPostId, null);
  assert.equal(page.listed, false);
  // Best-effort cleanup ran: objects, likes, comments, jobs all gone.
  for (const entry of post.media) {
    assert.equal(h.bucket.metadataOf(entry.storagePath), null);
    assert.equal(await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`), null);
  }
  assert.equal((await db.collection(`pagePosts/${view.postId}/likes`).get()).size, 0);
  assert.equal((await db.collection("pagePostComments").where("postId", "==", view.postId).get()).size, 0);
  assert.equal(await dataOf(`pagePostCleanupJobs/${view.postId}`), null);
  // Gone: a later delete is the uniform refusal.
  await rejectsWith(h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: view.postId, op: "delete" })), "permission-denied", "pageUnavailable");
});

test("delete: a reported, held or removed post becomes a tombstone with held media", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner({ postCount: 1, listed: true });
  const reportedId = newPostId();
  const media = photoMedia(uid, reportedId, 2);
  const reported = postDoc(uid, reportedId, nowMs, { kind: "photo", media, evidenceHold: true });
  await db.doc(`pagePosts/${reportedId}`).set(reported);
  await db.doc(`pagePostOpenReports/${reportedId}`).set({
    schemaVersion: 1, postId: reportedId, pageId: uid, count: 1, lastReportId: "report-abc",
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  for (const entry of media) {
    h.bucket.put(entry.storagePath, STRIPPED_JPEG, { contentType: "image/jpeg", token: false });
  }
  const stored = await Promise.all(media.map((entry) => h.bucket.metadataOf(entry.storagePath)));
  await db.doc(`pagePosts/${reportedId}`).update({
    media: media.map((entry, index) => ({ ...entry, generation: stored[index].generation })),
  });

  await clearActivation(db);
  await h.posts.managePagePostV1(request(uid, { requestId: requestId(), postId: reportedId, op: "delete" }));
  const tombstone = await dataOf(`pagePosts/${reportedId}`);
  assert.equal(pagePostMalformedReason(tombstone, reportedId), null);
  assert.equal(tombstone.status, "deleted");
  assert.equal(tombstone.text, reported.text);
  assert.equal(tombstone.media.length, 2);
  assert.equal(tombstone.moderationEvidence.evidenceVersion, 1);
  assert.match(tombstone.moderationEvidence.metadataFingerprint, /^[a-f0-9]{64}$/u);
  assert.equal((await dataOf(`pages/${uid}`)).postCount, 0);
  for (const entry of media) {
    const job = await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`);
    assert.equal(job.heldBy, "report-abc");
  }
  // Every tombstone is capped at 90 days (audit 2026-09-28).
  const retention = await dataOf(`pageEvidenceRetention/${reportedId}`);
  assert.deepEqual(Object.keys(retention).sort(), [...PAGE_EVIDENCE_RETENTION_KEYS]);
  assert.equal(retention.reason, "ownerDelete");
  assert.equal(retention.pageId, uid);
  assert.equal(retention.purgeAt.toMillis(), nowMs + PAGE_EVIDENCE_RETENTION_MS);
  // The worker never touches a held job; the bytes are still evidence.
  nowMs += 60 * 60 * 1000;
  await h.maintenance.processDeletionJobs();
  for (const entry of media) assert.notEqual(h.bucket.metadataOf(entry.storagePath), null);

  // Resolution (the reporting package) releases them in its transaction.
  await db.runTransaction(async (transaction) => {
    const refs = pagePostMediaJobReferences(db, tombstone);
    const snapshots = await transaction.getAll(...refs);
    assert.equal(releaseHeldPagePostMediaJobs(transaction, snapshots, Timestamp.fromMillis(nowMs)), 2);
  });
  await h.maintenance.processDeletionJobs();
  for (const entry of media) {
    assert.equal(h.bucket.metadataOf(entry.storagePath), null);
    assert.equal(await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`), null);
  }
  // Deleting a tombstone again is a no-op success.
  const again = await h.posts.managePagePostV1(request(uid,
    { requestId: requestId(), postId: reportedId, op: "delete" }));
  assert.equal(again.deleted, true);

  // Held with NO open report left (audit 2026-09-28): a tombstone, but its
  // media jobs are NOT held, because no open report could ever release them.
  const heldId = newPostId();
  const heldMedia = photoMedia(uid, heldId, 1);
  await db.doc(`pagePosts/${heldId}`).set(postDoc(uid, heldId, nowMs, {
    kind: "photo", media: heldMedia, status: "held", heldAt: Timestamp.fromMillis(nowMs),
  }));
  await h.posts.managePagePostV1(request(uid, { requestId: requestId(), postId: heldId, op: "delete" }));
  assert.equal((await dataOf(`pagePosts/${heldId}`)).status, "deleted");
  assert.equal(await dataOf(`pagePostMediaDeletionJobs/${heldMedia[0].mediaId}`), null,
    "no object existed, so the unheld job finished at once");
  assert.equal((await dataOf(`pageEvidenceRetention/${heldId}`)).reason, "ownerDelete");

  // A malformed open-report record still reads as reported (fail closed).
  const murkyId = newPostId();
  const murkyMedia = photoMedia(uid, murkyId, 1);
  await db.doc(`pagePosts/${murkyId}`).set(postDoc(uid, murkyId, nowMs, {
    kind: "photo", media: murkyMedia,
  }));
  await db.doc(`pagePostOpenReports/${murkyId}`).set({ count: "many" });
  await h.posts.managePagePostV1(request(uid, { requestId: requestId(), postId: murkyId, op: "delete" }));
  assert.equal((await dataOf(`pagePostMediaDeletionJobs/${murkyMedia[0].mediaId}`)).heldBy,
    "moderationHold");

  // Removed, report already resolved: tombstone, media no longer held.
  const removedId = newPostId();
  const removedMedia = photoMedia(uid, removedId, 1);
  await db.doc(`pagePosts/${removedId}`).set(postDoc(uid, removedId, nowMs, {
    kind: "photo", media: removedMedia, status: "removed",
    removedAt: Timestamp.fromMillis(nowMs), removedReason: "restrictedCategory",
  }));
  await h.posts.managePagePostV1(request(uid, { requestId: requestId(), postId: removedId, op: "delete" }));
  assert.equal((await dataOf(`pagePosts/${removedId}`)).status, "deleted");
  assert.equal(await dataOf(`pagePostMediaDeletionJobs/${removedMedia[0].mediaId}`), null,
    "no object existed, so the unheld job finished at once");

  // 90 days later every tombstone of this account is purged with its
  // likes and comments: none outlives the cap.
  await db.doc(`pagePosts/${removedId}/likes/fan-1`).set({ userId: "fan-1" });
  nowMs += PAGE_EVIDENCE_RETENTION_MS + 1;
  const purged = await h.maintenance.purgeDueEvidence({ limit: 50 });
  assert.equal(purged.purged >= 3, true, JSON.stringify(purged));
  for (const id of [heldId, removedId, murkyId]) {
    assert.equal(await dataOf(`pagePosts/${id}`), null, id);
    assert.equal(await dataOf(`pageEvidenceRetention/${id}`), null, id);
  }
  await h.maintenance.processCleanupJobs();
  assert.equal(await dataOf(`pagePosts/${removedId}/likes/fan-1`), null);
});

test("delete survives a Storage outage: the durable jobs finish later", async () => {
  const h = harness({ rateLimits: RELAXED });
  const uid = await pageWithOwner();
  const reserved = await reservedPhotos(h, uid, 1);
  const view = await h.posts.publishPagePostV1(request(uid, publishData("photo", {
    postId: reserved.postId, mediaIds: [reserved.items[0].mediaId],
  })));
  const objectPath = reserved.items[0].storagePath;
  h.bucket.failDelete.add(objectPath);
  await h.posts.managePagePostV1(request(uid, { requestId: requestId(), postId: view.postId, op: "delete" }));
  const job = await dataOf(`pagePostMediaDeletionJobs/${reserved.items[0].mediaId}`);
  assert.equal(job.attempts, 1);
  assert.equal(job.heldBy, null);
  assert.notEqual(h.bucket.metadataOf(objectPath), null);
  h.bucket.failDelete.delete(objectPath);
  nowMs += 10 * 60 * 1000;
  await h.maintenance.processDeletionJobs();
  assert.equal(h.bucket.metadataOf(objectPath), null);
  assert.equal(await dataOf(`pagePostMediaDeletionJobs/${reserved.items[0].mediaId}`), null);
});

test("the Page document written by a publish stays canonical", async () => {
  const h = harness();
  const uid = await pageWithOwner();
  await h.posts.publishPagePostV1(request(uid, publishData("text", { text: "Hello" })));
  const { pageMalformedReason } = require("../pages/contract");
  assert.equal(pageMalformedReason(await dataOf(`pages/${uid}`), uid), null);
  assert.equal(pageMalformedReason(pageDoc(uid, nowMs), uid), null);
});

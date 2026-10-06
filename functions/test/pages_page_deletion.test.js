// An owner's Page deletion (ADR-236) against the Firestore emulator:
// managePageDeletionV1 (status, request, restore, purgeNow, clearPosts), the
// durable purge and "delete all posts" worker, the 3-day reminder, the
// re-create memory (7-day cooldown, remembered suspension) read by
// managePageV1 create, and resume / update against a deletion record.
const assert = require("node:assert/strict");
const { beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
// Its own Firestore namespace (the pages_deletion.test.js pattern): the
// worker queries scan whole collections.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const SUITE_PROJECT = `${BASE_PROJECT}-pages-page-deletion`;
process.env.GCLOUD_PROJECT = SUITE_PROJECT;

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: SUITE_PROJECT });

const { UID_KEYED_DOCUMENTS } = require("../account/stages");
const { createPagesAccountDeletion } = require("../pages/account_deletion");
const { PAGE_KEYS } = require("../pages/contract");
const {
  MANAGE_PAGE_DELETION_OPS,
  PAGES_DELETION_RATE_LIMITS,
  PAGES_DELETION_WORK_LIMITS,
  PAGE_DELETION_KEYS,
  PAGE_DELETION_REMINDER_BEFORE_MS,
  PAGE_DELETION_REMINDER_LABEL,
  PAGE_DELETION_STATE_KEYS,
  PAGE_DELETION_WINDOW_MS,
  PAGE_MEMORY_KEYS,
  PAGE_POST_CLEAR_JOB_KEYS,
  PAGE_RECREATE_COOLDOWN_MS,
  createPagesDeletionService,
} = require("../pages/deletion");
const { pageFollowCarryJobDocument } = require("../pages/follow_carry");
const { createPagesLifecycleService } = require("../pages/lifecycle");
const { createPagesMaintenanceService } = require("../pages/maintenance");
const { newReservation, pageMediaIdFor, pagePostIdFor } = require("../pages/media_contract");
const { PAGE_EVIDENCE_RETENTION_MS } = require("../pages/report_contract");
const {
  DAY_MS,
  clearActivation,
  commentDoc,
  createInput,
  freshUid,
  newCommentId,
  newPostId,
  photoMedia,
  postDoc,
  request,
  seedAccount,
  seedFollowEdge,
  seedOwner,
  seedPage,
  setActivation,
  setFollowIndex,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
let nowMs = 1_900_000_000_000;

async function wipe(collection) {
  const rows = await db.collection(collection).get();
  await Promise.all(rows.docs.map((document) => document.ref.delete()));
}

beforeEach(async () => {
  nowMs += 400 * DAY_MS;
  await Promise.all(["pageDeletions", "pagePostClearJobs", "pageMemory"].map(wipe));
  await setActivation(db);
});

function recordingStorage() {
  const deletes = [];
  return {
    deletes,
    async getMetadata() { return { generation: "1700000000000009" }; },
    async deleteObject(storagePath, { generation }) { deletes.push({ storagePath, generation }); },
    async listObjects() { return { objects: [], nextPageToken: null }; },
  };
}

function deletionService({
  logger = silentLogger(),
  storage = recordingStorage(),
  limits = PAGES_DELETION_WORK_LIMITS,
  rateLimits = PAGES_DELETION_RATE_LIMITS,
  stages = undefined,
} = {}) {
  const service = createPagesDeletionService({
    firestore: db,
    storage,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger,
    limits,
    rateLimits,
    ...(stages ? { stages } : {}),
  });
  return { service, storage, logger };
}

function lifecycle() {
  return createPagesLifecycleService({
    firestore: db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
}

function call(service, uid, op, options = {}) {
  return service.managePageDeletionV1(request(uid, { op }, options));
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function rejectsWith(promise, code, reason = undefined) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, error.message);
    if (reason !== undefined) assert.equal(error.details?.reason, reason);
    return true;
  });
}

async function visibilityOf(uid) {
  const index = await dataOf("pageVisibility/v1");
  return index?.notViewable?.[uid] ?? null;
}

/// A running Page with `count` published text posts, oldest first.
async function seedRunningPage({ count = 0, page = {}, user = {}, prefix = "pdel" } = {}) {
  const uid = freshUid(prefix);
  await seedPage(db, uid, nowMs, {
    user,
    page: {
      postCount: count,
      listed: count > 0,
      lastPostAt: count > 0 ? Timestamp.fromMillis(nowMs - 1000) : null,
      ...page,
    },
  });
  const posts = [];
  for (let index = 0; index < count; index += 1) {
    const postId = newPostId();
    await db.doc(`pagePosts/${postId}`).set(postDoc(uid, postId, nowMs - 60_000 + index));
    posts.push(postId);
  }
  return { uid, posts };
}

async function addFollower(pageId, { withIndex = true, notificationId = null } = {}) {
  const follower = freshUid("pdelf");
  await seedAccount(db, follower, nowMs, { user: { followingCount: 1 } });
  await seedFollowEdge(db, follower, pageId, nowMs);
  if (notificationId !== null) {
    const id = `follow_${follower}_${notificationId}`;
    await Promise.all([
      db.doc(`users/${follower}/following/${pageId}`).update({ notificationId: id }),
      db.doc(`users/${pageId}/followers/${follower}`).update({ notificationId: id }),
      db.doc(`users/${pageId}/notifications/${id}`).set({ type: "follow", actorId: follower }),
    ]);
  }
  if (withIndex) await setFollowIndex(db, follower, [pageId], nowMs);
  return follower;
}

// ------------------------------------------------------------------ input

test("the op list, the exact input and the caller are checked before anything is read", async () => {
  assert.deepEqual([...MANAGE_PAGE_DELETION_OPS],
    ["status", "request", "restore", "purgeNow", "clearPosts"]);
  const { service } = deletionService();
  const uid = freshUid("pdelin");
  await rejectsWith(service.managePageDeletionV1(request(null, { op: "status" })), "unauthenticated");
  await rejectsWith(service.managePageDeletionV1(request(uid, { op: "delete" })), "invalid-argument");
  await rejectsWith(service.managePageDeletionV1(request(uid, { op: "status", pageId: uid })),
    "invalid-argument");
  await rejectsWith(service.managePageDeletionV1(request(uid, {})), "invalid-argument");
  // Only restore needs a verified e-mail.
  await rejectsWith(call(service, uid, "restore", { verified: false }), "failed-precondition");
  const state = await call(service, uid, "status", { verified: false });
  assert.deepEqual(Object.keys(state).sort(), [...PAGE_DELETION_STATE_KEYS]);
  assert.deepEqual(state, {
    schemaVersion: 1,
    pageId: uid,
    pageExists: false,
    deletion: null,
    postsClearing: null,
    recreateAllowedAtMs: null,
  });
});

test("status has its own rate budget", async () => {
  const { service } = deletionService({
    rateLimits: { ...PAGES_DELETION_RATE_LIMITS,
      "pages.deletionStatus": { maxEvents: 2, windowMs: 60_000 } },
  });
  const uid = freshUid("pdelrate");
  await call(service, uid, "status");
  await call(service, uid, "status");
  await rejectsWith(call(service, uid, "status"), "resource-exhausted");
});

// ---------------------------------------------------------------- request

test("request pauses the Page and writes the 30-day record in one transaction", async () => {
  const { uid } = await seedRunningPage({ count: 2 });
  const { service } = deletionService();
  const state = await call(service, uid, "request");
  assert.deepEqual(state, {
    schemaVersion: 1,
    pageId: uid,
    pageExists: true,
    deletion: {
      state: "pending",
      requestedAtMs: nowMs,
      deleteAtMs: nowMs + PAGE_DELETION_WINDOW_MS,
    },
    postsClearing: null,
    recreateAllowedAtMs: null,
  });
  const page = await dataOf(`pages/${uid}`);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS], "the Page keeps its exact 26 keys");
  assert.equal(page.ownerPaused, true);
  assert.equal(page.listed, false);
  assert.equal(page.postCount, 2, "nothing is deleted yet");
  assert.equal(await visibilityOf(uid), "paused");
  const record = await dataOf(`pageDeletions/${uid}`);
  assert.deepEqual(Object.keys(record).sort(), [...PAGE_DELETION_KEYS]);
  assert.equal(record.state, "pending");
  assert.equal(record.pausedBefore, false);
  assert.equal(record.deleteAt.toMillis(), nowMs + 30 * DAY_MS);
  assert.equal(record.dueAt.toMillis(), nowMs + 30 * DAY_MS);
  assert.equal(record.reminderAt.toMillis(),
    nowMs + PAGE_DELETION_WINDOW_MS - PAGE_DELETION_REMINDER_BEFORE_MS);
  assert.equal(record.reminderAt.toMillis(), nowMs + 27 * DAY_MS);

  // Idempotent: a second request, a day later, keeps the first date.
  const requestedAtMs = nowMs;
  nowMs += DAY_MS;
  const again = await call(service, uid, "request");
  assert.equal(again.deletion.requestedAtMs, requestedAtMs);
  assert.equal(again.deletion.deleteAtMs, requestedAtMs + PAGE_DELETION_WINDOW_MS);
  assert.equal((await dataOf(`pageDeletions/${uid}`)).deleteAt.toMillis(),
    requestedAtMs + PAGE_DELETION_WINDOW_MS);
  assert.deepEqual(await call(service, uid, "status"), again);
});

test("request is a safety action: kill switch, no capability, muted, unverified", async () => {
  const uid = freshUid("pdelsafe");
  await seedPage(db, uid, nowMs, { grant: null });
  await db.doc(`restrictions/${uid}`).set({ type: "communicationMute", expiresAt: null });
  await clearActivation(db);
  const { service } = deletionService();
  const state = await call(service, uid, "request", { verified: false });
  assert.equal(state.deletion.state, "pending");
  assert.equal((await dataOf(`pages/${uid}`)).ownerPaused, true);
  // An account without a Page has nothing to delete.
  await rejectsWith(call(service, freshUid("pdelnone"), "request"),
    "failed-precondition", "pageNotFound");
});

test("request remembers that the Page was already paused", async () => {
  const { uid } = await seedRunningPage({ page: { ownerPaused: true, listed: false } });
  const { service } = deletionService();
  await call(service, uid, "request");
  assert.equal((await dataOf(`pageDeletions/${uid}`)).pausedBefore, true);
});

test("a malformed Page is still paused and still queued for deletion", async () => {
  const { uid } = await seedRunningPage();
  await db.doc(`pages/${uid}`).update({ extraKey: true });
  const { service, logger } = deletionService();
  const state = await call(service, uid, "request");
  assert.equal(state.deletion.state, "pending");
  assert.equal((await dataOf(`pages/${uid}`)).ownerPaused, true);
  assert.equal(logger.entries.some((entry) => entry.level === "error"), true);

  // Taking it back works on a malformed Page too: the record goes (no sweep
  // may delete a Page whose owner asked for it back) and the Page document
  // is left exactly as it is.
  const before = await dataOf(`pages/${uid}`);
  const restored = await call(service, uid, "restore");
  assert.equal(restored.deletion, null);
  assert.equal(restored.pageExists, true);
  assert.equal(await dataOf(`pageDeletions/${uid}`), null);
  assert.deepEqual(await dataOf(`pages/${uid}`), before);
  nowMs += 31 * DAY_MS;
  await service.sweep();
  assert.notEqual(await dataOf(`pages/${uid}`), null);
});

// ---------------------------------------------------------------- restore

test("restore removes the record and resumes the Page; it needs the switch, the e-mail and the capability",
  async () => {
    const { uid } = await seedRunningPage({ count: 1 });
    const { service } = deletionService();
    await call(service, uid, "request");

    await clearActivation(db);
    await rejectsWith(call(service, uid, "restore"), "failed-precondition", "pagesNotEnabled");
    await setActivation(db);
    await db.doc(`vipGrants/${uid}`).delete();
    await rejectsWith(call(service, uid, "restore"), "failed-precondition", "pageAccessRequired");
    assert.notEqual(await dataOf(`pageDeletions/${uid}`), null, "a refused restore changes nothing");
    assert.equal((await dataOf(`pages/${uid}`)).ownerPaused, true);

    await db.doc(`vipGrants/${uid}`).set({
      source: "testerProgram", expiresAt: null, revoked: false, grantedBy: "owner-console",
    });
    nowMs += 5 * DAY_MS;
    const state = await call(service, uid, "restore");
    assert.deepEqual(state, {
      schemaVersion: 1, pageId: uid, pageExists: true, deletion: null, postsClearing: null,
      recreateAllowedAtMs: null,
    });
    assert.equal(await dataOf(`pageDeletions/${uid}`), null);
    const page = await dataOf(`pages/${uid}`);
    assert.equal(page.ownerPaused, false);
    assert.equal(page.listed, true, "posts and listing come back");
    assert.equal(page.postCount, 1);
    assert.equal(await visibilityOf(uid), null);
    // Idempotent with nothing pending (and no gate: nothing to restore).
    await db.doc(`vipGrants/${uid}`).delete();
    assert.equal((await call(service, uid, "restore")).deletion, null);
  });

test("restore returns the Page to what it was: paused before, private profile, suspended, lapsed",
  async () => {
    const { service } = deletionService();

    const pausedBefore = (await seedRunningPage({ page: { ownerPaused: true, listed: false } })).uid;
    await call(service, pausedBefore, "request");
    await call(service, pausedBefore, "restore");
    assert.equal((await dataOf(`pages/${pausedBefore}`)).ownerPaused, true);
    assert.equal(await dataOf(`pageDeletions/${pausedBefore}`), null);

    const wentPrivate = (await seedRunningPage()).uid;
    await call(service, wentPrivate, "request");
    await db.doc(`users/${wentPrivate}`).update({ profileVisibility: "private" });
    await call(service, wentPrivate, "restore");
    assert.equal((await dataOf(`pages/${wentPrivate}`)).ownerPaused, true,
      "a private profile keeps the Page paused (the resume rule)");
    assert.equal(await dataOf(`pageDeletions/${wentPrivate}`), null);

    const suspended = (await seedRunningPage({ page: {
      suspended: true, suspendedAt: Timestamp.fromMillis(nowMs), suspensionReason: "spam",
    } })).uid;
    await call(service, suspended, "request");
    await call(service, suspended, "restore");
    const suspendedPage = await dataOf(`pages/${suspended}`);
    assert.equal(suspendedPage.suspended, true);
    assert.equal(suspendedPage.ownerPaused, true, "a suspended Page is left as it is");
    assert.equal(await dataOf(`pageDeletions/${suspended}`), null);

    const lapsed = (await seedRunningPage({ page: {
      status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS),
    } })).uid;
    await call(service, lapsed, "request");
    await call(service, lapsed, "restore");
    const lapsedPage = await dataOf(`pages/${lapsed}`);
    assert.equal(lapsedPage.status, "active", "a live capability restores a lapsed Page");
    assert.equal(lapsedPage.lapsedAt, null);
    assert.equal(lapsedPage.ownerPaused, false);
  });

// ------------------------------------------- managePageV1 against a record

test("managePageV1 resume cancels a pending deletion; update and resume refuse once it is purging",
  async () => {
    const { uid } = await seedRunningPage({ count: 1 });
    const { service } = deletionService();
    await call(service, uid, "request");
    const resumed = await lifecycle().managePageV1(request(uid, {
      requestId: `req-resume-${uid}`, op: "resume",
    }));
    assert.deepEqual(Object.keys(resumed).sort(), ["kind", "ownerPaused", "pageId", "status"]);
    assert.equal(resumed.ownerPaused, false);
    assert.equal(await dataOf(`pageDeletions/${uid}`), null,
      "a resumed Page can never be swept later");

    await call(service, uid, "request");
    await db.doc(`pageDeletions/${uid}`).update({ state: "purging" });
    await rejectsWith(lifecycle().managePageV1(request(uid, {
      requestId: `req-resume2-${uid}`, op: "resume",
    })), "failed-precondition", "pageNotFound");
    await rejectsWith(lifecycle().managePageV1(request(uid, {
      requestId: `req-update-${uid}`,
      op: "update",
      category: "cafe_restaurant",
      description: "New text.",
      business: { website: null, email: null, phone: null, address: null, hours: null,
        legalNotice: null },
      community: null,
    })), "failed-precondition", "pageNotFound");
    await rejectsWith(call(service, uid, "restore"), "failed-precondition", "pageDeletionInProgress");
    assert.equal((await dataOf(`pages/${uid}`)).ownerPaused, true);
  });

// ------------------------------------------------------------------ worker

/// A Page with every kind of post, followers, an open upload and records.
async function seedFullPage() {
  const uid = freshUid("pdelfull");
  const otherPage = freshUid("pdelother");
  const now = Timestamp.fromMillis(nowMs);
  await seedPage(db, uid, nowMs, {
    user: { followerCount: 3 },
    page: { postCount: 2, listed: true, lastPostAt: now },
  });
  await seedPage(db, otherPage, nowMs, { page: { postCount: 1, listed: true, lastPostAt: now } });

  const clean = newPostId();
  const cleanMedia = photoMedia(uid, clean, 2);
  await db.doc(`pagePosts/${clean}`).set(postDoc(uid, clean, nowMs - 5000, {
    kind: "photo", media: cleanMedia, likeCount: 1, commentCount: 1 }));
  const reported = newPostId();
  const reportedMedia = photoMedia(uid, reported, 1);
  await db.doc(`pagePosts/${reported}`).set(postDoc(uid, reported, nowMs - 4000, {
    kind: "photo", media: reportedMedia, evidenceHold: true }));
  await db.doc(`pagePostOpenReports/${reported}`).set({
    schemaVersion: 1, postId: reported, pageId: uid, count: 1, lastReportId: "report-open-9",
    updatedAt: now });
  // A moderator removed this one; its report is closed.
  const removed = newPostId();
  const removedMedia = photoMedia(uid, removed, 1);
  await db.doc(`pagePosts/${removed}`).set(postDoc(uid, removed, nowMs - 3000, {
    kind: "photo", media: removedMedia, status: "removed", removedAt: now, removedReason: "spam" }));
  // An earlier owner delete left this tombstone with its own retention row.
  const tombstone = newPostId();
  await db.doc(`pagePosts/${tombstone}`).set(postDoc(uid, tombstone, nowMs - 2000, {
    status: "deleted", deletedAt: now,
    moderationEvidence: { evidenceVersion: 1, metadataFingerprint: "a".repeat(64) } }));
  const tombstonePurgeAt = Timestamp.fromMillis(nowMs + 10 * DAY_MS);
  await db.doc(`pageEvidenceRetention/${tombstone}`).set({
    schemaVersion: 1, postId: tombstone, pageId: uid, reason: "ownerDelete",
    purgeAt: tombstonePurgeAt, createdAt: now });

  // A comment the OWNER wrote on somebody else's Page: it belongs to the
  // account, which stays.
  const theirPost = newPostId();
  await db.doc(`pagePosts/${theirPost}`).set(postDoc(otherPage, theirPost, nowMs, { commentCount: 1 }));
  const ownComment = newCommentId();
  await db.doc(`pagePostComments/${ownComment}`).set(
    commentDoc({ postId: theirPost, pageId: otherPage }, ownComment, uid, nowMs));

  const requestId = `req-${freshUid()}`;
  const uploadMedia = pageMediaIdFor(uid, requestId, 0);
  const reservation = newReservation({
    pageId: uid, postId: pagePostIdFor(uid, requestId, "media"), mediaId: uploadMedia,
    item: { index: 0, size: 2000, width: 10, height: 10, durationMs: null },
    kind: "photo", requestId, now, expiresAt: Timestamp.fromMillis(nowMs + 900_000),
  });
  await db.doc(`pagePostMediaReservations/${uploadMedia}`).set(reservation);
  await db.doc(`pagePostMediaLeases/${uid}`).set({ schemaVersion: 1, ownerId: uid });
  await db.doc(`pagePostBudgets/${uid}_20300101`).set({ schemaVersion: 1, pageId: uid });
  await db.doc(`pageFollowCarryJobs/${uid}`).set(pageFollowCarryJobDocument({
    pageId: uid, now, nextAttemptAt: now }));
  // The Pages the ACCOUNT follows stay its own.
  await db.doc(`pageFollowIndex/${uid}`).set({ schemaVersion: 1, pageIds: [otherPage], updatedAt: now });

  const followers = [
    await addFollower(uid, { notificationId: "n1" }),
    await addFollower(uid),
    await addFollower(uid, { withIndex: false }),
  ];
  return {
    uid, otherPage, clean, cleanMedia, reported, reportedMedia, removed, removedMedia,
    tombstone, tombstonePurgeAt, theirPost, ownComment, reservation, uploadMedia, followers,
  };
}

async function followerEdges(uid) {
  return (await db.collection(`users/${uid}/followers`).get()).size;
}

test("nothing is purged before the date; the owner is reminded once, 3 days before", async () => {
  const { uid } = await seedRunningPage({ count: 1 });
  const { service } = deletionService();
  await call(service, uid, "request");
  const deleteAtMs = nowMs + PAGE_DELETION_WINDOW_MS;

  nowMs += 26 * DAY_MS;
  let line = await service.sweep();
  assert.equal(line.reminders.sent, 0);
  assert.equal(line.deletions.processed, 0);

  nowMs += DAY_MS + 1000;
  line = await service.sweep();
  assert.equal(line.reminders.sent, 1);
  assert.equal(line.deletions.processed, 0, "day 27 is not day 30");
  const notices = await db.collection(`users/${uid}/notifications`).get();
  assert.equal(notices.size, 1);
  const notice = notices.docs[0];
  assert.equal(notice.id, `pageLapse_deletionSoon_${deleteAtMs}`);
  assert.equal(notice.data().type, "pageLapse");
  assert.equal(notice.data().lapsePhase, "deletionSoon");
  assert.equal(notice.data().targetLabel, PAGE_DELETION_REMINDER_LABEL);
  assert.equal(notice.data().targetId, uid);
  assert.equal((await dataOf(`pageDeletions/${uid}`)).reminderAt, null);

  line = await service.sweep();
  assert.equal(line.reminders.sent, 0, "one reminder only");
  assert.notEqual(await dataOf(`pages/${uid}`), null);
  assert.notEqual(await dataOf(`pagePosts/${(await db.collection("pagePosts")
    .where("pageId", "==", uid).get()).docs[0].id}`), null);
});

test("after 30 days the purge removes posts, followers, storage, records and then the Page",
  async () => {
    const s = await seedFullPage();
    const { service, storage } = deletionService();
    await call(service, s.uid, "request");
    nowMs += 30 * DAY_MS + 1000;

    // Enough rounds for every step of this small Page.
    for (let run = 0; run < 3 && await dataOf(`pageDeletions/${s.uid}`) !== null; run += 1) {
      await service.sweep();
    }
    assert.equal(await dataOf(`pageDeletions/${s.uid}`), null);
    assert.equal(await dataOf(`pages/${s.uid}`), null);
    assert.equal(await visibilityOf(s.uid), null, "the Page and its index entry go together");

    // Posts: the clean one is gone with its jobs.
    assert.equal(await dataOf(`pagePosts/${s.clean}`), null);
    assert.equal((await dataOf(`pagePostCleanupJobs/${s.clean}`)).reason, "pageDeleted");
    // Reported: a tombstone, bytes held, retained for at most 90 days.
    const reported = await dataOf(`pagePosts/${s.reported}`);
    assert.equal(reported.status, "deleted");
    assert.match(reported.moderationEvidence.metadataFingerprint, /^[a-f0-9]{64}$/u);
    const reportedJob = await dataOf(`pagePostMediaDeletionJobs/${s.reportedMedia[0].mediaId}`);
    assert.equal(reportedJob.heldBy, "report-open-9");
    assert.equal(reportedJob.reason, "pageDeleted");
    const retention = await dataOf(`pageEvidenceRetention/${s.reported}`);
    assert.equal(retention.reason, "ownerDelete");
    assert.equal(retention.purgeAt.toMillis(), nowMs + PAGE_EVIDENCE_RETENTION_MS);
    // Removed by a moderator, report closed: a tombstone too (the single
    // owner-delete rule), with unheld bytes.
    assert.equal((await dataOf(`pagePosts/${s.removed}`)).status, "deleted");
    assert.notEqual(await dataOf(`pageEvidenceRetention/${s.removed}`), null);
    // An earlier tombstone keeps its OWN retention date.
    assert.equal((await dataOf(`pagePosts/${s.tombstone}`)).status, "deleted");
    assert.equal((await dataOf(`pageEvidenceRetention/${s.tombstone}`)).purgeAt.toMillis(),
      s.tombstonePurgeAt.toMillis());

    // Followers: edges, mirrors, counters, hints and the follow bell row.
    assert.equal(await followerEdges(s.uid), 0);
    for (const follower of s.followers) {
      assert.equal(await dataOf(`users/${follower}/following/${s.uid}`), null);
      assert.equal((await dataOf(`users/${follower}`)).followingCount, 0);
    }
    assert.deepEqual((await dataOf(`pageFollowIndex/${s.followers[0]}`)).pageIds, []);
    assert.equal((await db.collection(`users/${s.uid}/notifications`)
      .where("type", "==", "follow").get()).size, 0);
    assert.equal((await dataOf(`users/${s.uid}`)).followerCount, 0);

    // Storage: unheld objects and the open upload; held evidence is skipped.
    const deleted = new Set(storage.deletes.map((entry) => entry.storagePath));
    for (const entry of [...s.cleanMedia, ...s.removedMedia]) {
      assert.equal(deleted.has(entry.storagePath), true);
      assert.equal(await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`), null);
    }
    assert.equal(deleted.has(s.reportedMedia[0].storagePath), false);
    assert.equal(deleted.has(s.reservation.storagePath), true);
    assert.equal(await dataOf(`pagePostMediaReservations/${s.uploadMedia}`), null);

    // Records and Page-keyed jobs.
    assert.equal(await dataOf(`pagePostBudgets/${s.uid}_20300101`), null);
    assert.equal(await dataOf(`pageFollowCarryJobs/${s.uid}`), null);
    assert.equal(await dataOf(`pagePostMediaLeases/${s.uid}`), null);

    // The ACCOUNT stays: its profile, the Pages it follows, its comments.
    assert.notEqual(await dataOf(`users/${s.uid}`), null);
    assert.notEqual(await dataOf(`publicProfiles/${s.uid}`), null);
    assert.deepEqual((await dataOf(`pageFollowIndex/${s.uid}`)).pageIds, [s.otherPage]);
    assert.notEqual(await dataOf(`pagePostComments/${s.ownComment}`), null);
    assert.equal((await dataOf(`pagePosts/${s.theirPost}`)).commentCount, 1);
    assert.notEqual(await dataOf(`pages/${s.otherPage}`), null);

    // The memory: the 7-day cooldown, no suspension, expiring with it.
    const memory = await dataOf(`pageMemory/${s.uid}`);
    assert.deepEqual(Object.keys(memory).sort(), [...PAGE_MEMORY_KEYS]);
    assert.equal(memory.suspension, null);
    assert.equal(memory.recreateAllowedAt.toMillis(), memory.deletedAt.toMillis() + 7 * DAY_MS);
    assert.equal(memory.expiresAt.toMillis(), memory.recreateAllowedAt.toMillis());
    const state = await call(service, s.uid, "status");
    assert.equal(state.pageExists, false);
    assert.equal(state.deletion, null);
    assert.equal(state.recreateAllowedAtMs, memory.recreateAllowedAt.toMillis());
  });

test("the Page document outlives every follower edge (the existence checks never flip early)",
  async () => {
    const { uid } = await seedRunningPage({ count: 1, user: { followerCount: 3 } });
    for (let index = 0; index < 3; index += 1) await addFollower(uid);
    // One follower and one step at a time.
    const limits = { ...PAGES_DELETION_WORK_LIMITS, edgePage: 1, deletionRounds: 1 };
    const { service } = deletionService({ limits });
    await call(service, uid, "request");
    nowMs += 31 * DAY_MS;
    let sawEdgesShrink = false;
    for (let run = 0; run < 40; run += 1) {
      await service.processDueDeletions();
      const [page, edges] = await Promise.all([dataOf(`pages/${uid}`), followerEdges(uid)]);
      if (edges > 0) {
        assert.notEqual(page, null, "pages/{uid} exists while an edge remains");
        assert.equal(page.ownerPaused, true);
        if (edges < 3) sawEdgesShrink = true;
      }
      if (page === null) {
        assert.equal(edges, 0);
        break;
      }
    }
    assert.equal(sawEdgesShrink, true, "the run was stepped one edge at a time");
    assert.equal(await dataOf(`pages/${uid}`), null);
    assert.equal(await dataOf(`pageDeletions/${uid}`), null);
  });

test("a failing step backs the record off and never stops the next record", async () => {
  const failing = (await seedRunningPage({ count: 1, prefix: "pdelbad" })).uid;
  const fine = (await seedRunningPage({ count: 1, prefix: "pdelok" })).uid;
  const real = createPagesAccountDeletion({
    db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
  const stages = {
    ...real,
    processPosts: (uid, ...rest) => {
      if (uid === failing) {
        const error = new Error("boom");
        error.code = "unavailable";
        throw error;
      }
      return real.processPosts(uid, ...rest);
    },
  };
  const { service, logger } = deletionService({ stages });
  await call(service, failing, "request");
  nowMs += 1000;
  await call(service, fine, "request");
  nowMs += 31 * DAY_MS;
  const line = await service.processDueDeletions();
  assert.equal(line.failed, 1);
  const record = await dataOf(`pageDeletions/${failing}`);
  assert.equal(record.state, "purging");
  assert.equal(record.attempts, 1);
  assert.equal(record.dueAt.toMillis() > nowMs, true, "backed off");
  assert.notEqual(await dataOf(`pages/${failing}`), null);
  assert.equal(await dataOf(`pages/${fine}`), null, "the next record was purged");
  // No uid in the log line.
  for (const entry of logger.entries) {
    assert.equal(JSON.stringify(entry.args).includes(failing), false);
  }
});

test("a malformed deletion record is never purged", async () => {
  const { uid } = await seedRunningPage({ count: 1 });
  const { service, logger } = deletionService();
  await call(service, uid, "request");
  await db.doc(`pageDeletions/${uid}`).update({
    state: "weird", dueAt: Timestamp.fromMillis(nowMs - 1000),
  });
  await service.sweep();
  assert.notEqual(await dataOf(`pages/${uid}`), null);
  assert.equal(logger.entries.some((entry) => entry.level === "error"), true);
  // The owner's next request rewrites it; a restore removes it.
  const state = await call(service, uid, "request");
  assert.equal(state.deletion.state, "pending");
  assert.equal(state.deletion.requestedAtMs, nowMs);
});

// --------------------------------------------------------------- purgeNow

test("purgeNow needs a pending deletion and removes a small Page before it answers", async () => {
  const { uid, posts } = await seedRunningPage({ count: 2, user: { followerCount: 1 } });
  const follower = await addFollower(uid);
  const { service } = deletionService();
  await rejectsWith(call(service, uid, "purgeNow"),
    "failed-precondition", "pageDeletionNotRequested");
  assert.notEqual(await dataOf(`pages/${uid}`), null);

  await call(service, uid, "request");
  // The inline pass is bounded: let the worker finish what is left.
  let state = await call(service, uid, "purgeNow", { verified: false });
  for (let run = 0; run < 3 && state.pageExists; run += 1) {
    await service.sweep();
    state = await call(service, uid, "status");
  }
  assert.equal(state.pageExists, false);
  assert.equal(state.deletion, null);
  assert.equal(state.recreateAllowedAtMs, nowMs + PAGE_RECREATE_COOLDOWN_MS);
  for (const postId of posts) assert.equal(await dataOf(`pagePosts/${postId}`), null);
  assert.equal(await dataOf(`users/${follower}/following/${uid}`), null);
  // Nothing is left to restore.
  assert.equal((await call(service, uid, "restore")).deletion, null);
  assert.equal(await dataOf(`pages/${uid}`), null);
});

// ------------------------------------------------- re-create and the memory

test("create waits out the 7-day cooldown and then consumes the memory", async () => {
  const uid = freshUid("pdelre");
  await seedOwner(db, uid, { nowMs });
  const first = await lifecycle().managePageV1(request(uid, createInput()));
  assert.equal(first.status, "active");
  const { service } = deletionService();
  await call(service, uid, "request");
  let state = await call(service, uid, "purgeNow");
  for (let run = 0; run < 3 && state.pageExists; run += 1) {
    await service.sweep();
    state = await call(service, uid, "status");
  }
  const allowedAtMs = state.recreateAllowedAtMs;
  assert.equal(allowedAtMs, nowMs + 7 * DAY_MS);

  nowMs += 6 * DAY_MS;
  await assert.rejects(lifecycle().managePageV1(request(uid, createInput())), (error) => {
    assert.equal(error.code, "failed-precondition");
    assert.equal(error.details.reason, "pageRecreateCooldown");
    assert.equal(error.details.retryAtMs, allowedAtMs);
    return true;
  });
  assert.equal(await dataOf(`pages/${uid}`), null);

  nowMs += DAY_MS + 1000;
  assert.equal((await call(service, uid, "status")).recreateAllowedAtMs, null);
  const again = await lifecycle().managePageV1(request(uid, createInput()));
  assert.deepEqual(Object.keys(again).sort(), ["kind", "ownerPaused", "pageId", "status"]);
  const page = await dataOf(`pages/${uid}`);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS]);
  assert.equal(page.suspended, false);
  assert.equal(page.postCount, 0, "a new Page starts from zero");
  assert.equal(await dataOf(`pageMemory/${uid}`), null);
});

test("a suspension survives delete and re-create", async () => {
  const uid = freshUid("pdelsus");
  const suspendedAt = Timestamp.fromMillis(nowMs - DAY_MS);
  await seedPage(db, uid, nowMs, { page: {
    suspended: true, suspendedAt, suspensionReason: "scam",
  } });
  const { service } = deletionService();
  await call(service, uid, "request");
  let state = await call(service, uid, "purgeNow");
  for (let run = 0; run < 3 && state.pageExists; run += 1) {
    await service.sweep();
    state = await call(service, uid, "status");
  }
  const memory = await dataOf(`pageMemory/${uid}`);
  assert.equal(memory.suspension.suspensionReason, "scam");
  assert.equal(memory.suspension.suspendedAt.toMillis(), suspendedAt.toMillis());
  assert.equal(memory.expiresAt, null, "a remembered suspension never expires by time");

  // The memory slice leaves it alone, cooldown or not.
  nowMs += 40 * DAY_MS;
  assert.equal((await service.expireMemory()).removed, 0);
  assert.notEqual(await dataOf(`pageMemory/${uid}`), null);

  const created = await lifecycle().managePageV1(request(uid, createInput()));
  assert.equal(created.pageId, uid);
  const page = await dataOf(`pages/${uid}`);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS]);
  assert.equal(page.suspended, true);
  assert.equal(page.suspensionReason, "scam");
  assert.equal(page.suspendedAt.toMillis(), suspendedAt.toMillis());
  assert.equal(page.listed, false);
  assert.equal(await visibilityOf(uid), "suspended");
  assert.equal(await dataOf(`pageMemory/${uid}`), null, "the suspension lives in the Page again");
});

test("a second finish of the same purge writes nothing: the remembered suspension stays", async () => {
  // purgeNow's inline pass beside the worker, or the SDK retrying a commit
  // whose response was lost: the last step runs twice. The second run finds
  // the record gone and must not rewrite the memory from a Page that is no
  // longer there (that would drop the suspension the first run remembered).
  const uid = freshUid("pdeldup");
  const suspendedAt = Timestamp.fromMillis(nowMs - DAY_MS);
  await seedPage(db, uid, nowMs, { page: {
    suspended: true, suspendedAt, suspensionReason: "scam",
  } });
  const real = createPagesAccountDeletion({
    db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
  let finishes = 0;
  const stages = {
    ...real,
    removePage: async (pageId, options) => {
      finishes += 1;
      const removed = await real.removePage(pageId, options);
      const memory = await dataOf(`pageMemory/${pageId}`);
      nowMs += 60_000;
      assert.equal(await real.removePage(pageId, options), false, "the second finish is a no-op");
      assert.deepEqual(await dataOf(`pageMemory/${pageId}`), memory, "the memory is not rewritten");
      return removed;
    },
  };
  const { service } = deletionService({ stages });
  await call(service, uid, "request");
  let state = await call(service, uid, "purgeNow");
  for (let run = 0; run < 3 && state.pageExists; run += 1) {
    await service.sweep();
    state = await call(service, uid, "status");
  }
  assert.equal(finishes, 1);
  assert.equal(state.pageExists, false);
  const memory = await dataOf(`pageMemory/${uid}`);
  assert.equal(memory.suspension.suspensionReason, "scam");
  assert.equal(memory.suspension.suspendedAt.toMillis(), suspendedAt.toMillis());
  assert.equal(memory.expiresAt, null);

  // Without its record the last step never deletes a Page either: a Page
  // that exists and has no purging record is not this step's to remove.
  const other = (await seedRunningPage({ count: 0, prefix: "pdelkeep" })).uid;
  const guard = ([record]) => record.exists && record.data().state === "purging";
  assert.equal(await real.removePage(other, {
    reads: [db.doc(`pageDeletions/${other}`)], guard,
  }), false);
  assert.notEqual(await dataOf(`pages/${other}`), null);
});

test("the slice stops picking up records once its time budget is used", async () => {
  const first = (await seedRunningPage({ count: 1, prefix: "pdelbud" })).uid;
  const second = (await seedRunningPage({ count: 1, prefix: "pdelbud" })).uid;
  const real = createPagesAccountDeletion({
    db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
  // Every page of posts "takes" the whole budget.
  const stages = {
    ...real,
    processPosts: (...args) => {
      nowMs += PAGES_DELETION_WORK_LIMITS.sweepBudgetMs;
      return real.processPosts(...args);
    },
  };
  const { service } = deletionService({ stages });
  await call(service, first, "request");
  nowMs += 1000;
  await call(service, second, "request");
  nowMs += 31 * DAY_MS;
  const result = await service.sweep();
  assert.equal(result.deletions.processed, 2);
  assert.equal(result.deletions.done, 1);
  assert.equal(result.deletions.hasMore, true, "the rest is due again on the next run");
  assert.equal(await dataOf(`pages/${first}`), null);
  // The second record was not even claimed; the next run purges it.
  assert.equal((await dataOf(`pageDeletions/${second}`)).state, "pending");
  assert.notEqual(await dataOf(`pages/${second}`), null);
  const next = await service.sweep();
  assert.equal(next.deletions.done, 1);
  assert.equal(await dataOf(`pages/${second}`), null);
});

test("an expired memory without a suspension is removed; a malformed one refuses create", async () => {
  const gone = freshUid("pdelmem");
  const now = Timestamp.fromMillis(nowMs);
  await db.doc(`pageMemory/${gone}`).set({
    schemaVersion: 1, pageId: gone, deletedAt: now,
    recreateAllowedAt: Timestamp.fromMillis(nowMs + 7 * DAY_MS),
    suspension: null, expiresAt: Timestamp.fromMillis(nowMs + 7 * DAY_MS), updatedAt: now,
  });
  const { service } = deletionService();
  assert.equal((await service.expireMemory()).removed, 0);
  nowMs += 7 * DAY_MS + 1;
  assert.equal((await service.expireMemory()).removed, 1);
  assert.equal(await dataOf(`pageMemory/${gone}`), null);

  const broken = freshUid("pdelbroken");
  await seedOwner(db, broken, { nowMs });
  await db.doc(`pageMemory/${broken}`).set({ schemaVersion: 1, pageId: broken });
  await rejectsWith(lifecycle().managePageV1(request(broken, createInput())), "data-loss");
  assert.equal(await dataOf(`pages/${broken}`), null);
  // The state view only loses the date.
  assert.equal((await call(service, broken, "status")).recreateAllowedAtMs, null);
});

// -------------------------------------------------------------- clearPosts

test("clearPosts removes every post and keeps the Page, its followers and its budget", async () => {
  const s = await seedFullPage();
  await db.doc(`pages/${s.uid}`).update({ pinnedPostId: s.clean });
  await clearActivation(db);
  const { service } = deletionService();
  const state = await call(service, s.uid, "clearPosts", { verified: false });
  assert.equal(state.pageExists, true);
  assert.equal(state.deletion, null);
  assert.equal(state.postsClearing, null, "a small Page is cleared before the call returns");
  assert.equal(await dataOf(`pagePostClearJobs/${s.uid}`), null);

  const page = await dataOf(`pages/${s.uid}`);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS]);
  assert.equal(page.postCount, 0);
  assert.equal(page.pinnedPostId, null);
  assert.equal(page.listed, false);
  assert.equal(page.ownerPaused, false, "the Page keeps running");
  assert.equal(await dataOf(`pagePosts/${s.clean}`), null);
  assert.equal((await dataOf(`pagePostCleanupJobs/${s.clean}`)).reason, "postsCleared");
  assert.equal((await dataOf(`pagePosts/${s.reported}`)).status, "deleted");
  assert.equal((await dataOf(`pageEvidenceRetention/${s.reported}`)).reason, "ownerDelete");
  assert.equal((await dataOf(`pagePostMediaDeletionJobs/${s.reportedMedia[0].mediaId}`)).heldBy,
    "report-open-9");
  assert.equal((await dataOf(`pagePosts/${s.removed}`)).status, "deleted");
  assert.equal((await dataOf(`pageEvidenceRetention/${s.tombstone}`)).purgeAt.toMillis(),
    s.tombstonePurgeAt.toMillis());

  // Followers, the budget and the account's own things are untouched.
  assert.equal(await followerEdges(s.uid), 3);
  assert.equal((await dataOf(`users/${s.uid}`)).followerCount, 3);
  assert.notEqual(await dataOf(`pagePostBudgets/${s.uid}_20300101`), null);
  assert.notEqual(await dataOf(`pagePostComments/${s.ownComment}`), null);
  assert.equal(await dataOf(`pageMemory/${s.uid}`), null);
  await rejectsWith(call(service, freshUid("pdelnopage"), "clearPosts"),
    "failed-precondition", "pageNotFound");
});

test("a post published after clearPosts survives; the worker finishes a large Page", async () => {
  const { uid, posts } = await seedRunningPage({ count: 4 });
  // Nothing inline, two posts per pass, one pass per run.
  const limits = { ...PAGES_DELETION_WORK_LIMITS, inlineClearRounds: 0, clearRounds: 1 };
  const stages = createPagesAccountDeletion({
    db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
    limits: { posts: 2, comments: 25, storage: 25, records: 200 },
  });
  const { service } = deletionService({ limits, stages });
  const state = await call(service, uid, "clearPosts");
  assert.deepEqual(state.postsClearing, { requestedAtMs: nowMs });
  const job = await dataOf(`pagePostClearJobs/${uid}`);
  assert.deepEqual(Object.keys(job).sort(), [...PAGE_POST_CLEAR_JOB_KEYS]);

  // The owner publishes while the job runs.
  nowMs += 60_000;
  const fresh = newPostId();
  await db.doc(`pagePosts/${fresh}`).set(postDoc(uid, fresh, nowMs));
  await db.doc(`pages/${uid}`).update({ postCount: 5 });

  let line = await service.processDueClearJobs();
  assert.equal(line.hasMore, true);
  assert.equal((await dataOf(`pages/${uid}`)).postCount, 3);
  assert.notEqual((await dataOf(`pagePostClearJobs/${uid}`)).cursor, null);
  for (let run = 0; run < 5 && await dataOf(`pagePostClearJobs/${uid}`) !== null; run += 1) {
    line = await service.processDueClearJobs();
  }
  assert.equal(await dataOf(`pagePostClearJobs/${uid}`), null);
  for (const postId of posts) assert.equal(await dataOf(`pagePosts/${postId}`), null);
  assert.notEqual(await dataOf(`pagePosts/${fresh}`), null, "published after the request");
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.postCount, 1);
  assert.equal(page.listed, true);
  assert.equal((await call(service, uid, "status")).postsClearing, null);

  // A second request moves the boundary and takes the newer post too.
  nowMs += 60_000;
  await call(service, uid, "clearPosts");
  await service.processDueClearJobs();
  assert.equal(await dataOf(`pagePosts/${fresh}`), null);
  assert.equal((await dataOf(`pages/${uid}`)).postCount, 0);
});

// ------------------------------------------------------- wiring, inventory

test("pagesMaintenance runs the pageDeletion slice and account deletion knows the new records",
  async () => {
    const { uid } = await seedRunningPage({ count: 1 });
    const storage = recordingStorage();
    const maintenance = createPagesMaintenanceService({
      firestore: db, storage, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
    });
    const { service } = deletionService();
    await call(service, uid, "request");
    await call(service, uid, "purgeNow");
    const results = await maintenance.run();
    assert.deepEqual(Object.keys(results.pageDeletion).sort(),
      ["clearJobs", "deletions", "memory", "reminders"]);
    assert.equal(await dataOf(`pages/${uid}`), null);
    for (const name of ["pageDeletions", "pagePostClearJobs", "pageMemory"]) {
      assert.equal(UID_KEYED_DOCUMENTS.includes(name), true, name);
    }
  });

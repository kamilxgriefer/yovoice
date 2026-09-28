// Premium Pages in the ADR-206 account-deletion stages (ADR-233 §2.11,
// package B5) against the Firestore emulator: the Page and its visibility
// entry, posts (hard delete, or a retained tombstone while a report is
// open), the comments the account wrote, Page media by exact path and
// generation (held evidence skipped), the records, and the ≤ 90-day
// evidence retention purged by pagesMaintenance or by the resolution.
const assert = require("node:assert/strict");
const { beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
// Its own Firestore namespace (the account_deletion.test.js pattern): the
// suites share one emulator, and these seed listed Pages, open reports and
// whole-collection sweeps that must neither see nor disturb a neighbour's.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const SUITE_PROJECT = `${BASE_PROJECT}-pages-deletion`;
process.env.GCLOUD_PROJECT = SUITE_PROJECT;

const { getApps, initializeApp } = require("firebase-admin/app");
const { FieldPath, FieldValue, getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: SUITE_PROJECT });

const { createAccountDeletionStages, UID_KEYED_DOCUMENTS } = require("../account/stages");
const { createPagesAccountDeletion, PAGES_DELETION_QUERIES } = require("../pages/account_deletion");
const { createPagesMaintenanceService } = require("../pages/maintenance");
const { createPagesMediaStorageAdapter } = require("../pages/media_storage");
const { PAGE_EVIDENCE_RETENTION_MS } = require("../pages/report_contract");
const {
  newReservation,
  pageMediaDeletionJob,
  pageMediaIdFor,
  pagePostIdFor,
} = require("../pages/media_contract");
const {
  DAY_MS,
  commentDoc,
  freshUid,
  newCommentId,
  newPostId,
  photoMedia,
  postDoc,
  seedAccount,
  seedPage,
  silentLogger,
} = require("./helpers/pages_fixture");
const { FakeBucket } = require("./helpers/pages_media_fixture");

const db = getFirestore();
let nowMs = 1_900_000_000_000;

beforeEach(async () => {
  nowMs += 200 * DAY_MS;
  // The retention slice scans the whole collection: start from none.
  const rows = await db.collection("pageEvidenceRetention").get();
  await Promise.all(rows.docs.map((document) => document.ref.delete()));
});

function recordingBucket() {
  const deletes = [];
  return {
    deletes,
    name: "demo",
    async deleteFiles() {},
    file(path, options = {}) {
      return {
        async delete(settings = {}) {
          deletes.push({ path, generation: options.generation ?? null, settings });
        },
      };
    },
  };
}

function stagesFor(bucket) {
  const logger = silentLogger();
  return createAccountDeletionStages({
    db,
    FieldValue,
    FieldPath,
    authAdmin: { async revokeRefreshTokens() {}, async deleteUser() {} },
    resolveBucket: () => bucket,
    deleteTrustedPrefix: async () => ({ deleted: true }),
    logger,
    pages: createPagesAccountDeletion({ db, TimestampImpl: Timestamp, clock: () => nowMs, logger }),
  });
}

async function runToEnd(stages, stage, uid) {
  let cursor = null;
  const details = [];
  for (let round = 0; round < 60; round += 1) {
    const outcome = await stages.runStage(stage, { uid, cursor, row: {} });
    details.push(outcome.details);
    if (outcome.done) return details;
    cursor = outcome.cursor;
  }
  throw new Error(`${stage} did not finish`);
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

/// A Page account with a clean post (likes, a visitor comment and its bell
/// row), a REPORTED post, an owner-deleted tombstone, an open upload, the
/// records, and one comment the account wrote on somebody else's Page.
async function seedPageAccount() {
  const uid = freshUid("delpage");
  const visitor = freshUid("delvis");
  const otherPage = freshUid("delother");
  await seedPage(db, uid, nowMs, { page: { postCount: 2, listed: true,
    lastPostAt: Timestamp.fromMillis(nowMs) } });
  await seedAccount(db, visitor, nowMs);
  await seedPage(db, otherPage, nowMs, { page: { postCount: 1, listed: true,
    lastPostAt: Timestamp.fromMillis(nowMs) } });
  await db.doc("pageVisibility/v1").set({
    schemaVersion: 1,
    notViewable: { [uid]: "paused" },
    readOnlySince: {},
    updatedAt: Timestamp.fromMillis(nowMs),
  });

  const clean = newPostId();
  const cleanMedia = photoMedia(uid, clean, 2);
  await db.doc(`pagePosts/${clean}`).set(postDoc(uid, clean, nowMs - 3000, {
    kind: "photo", media: cleanMedia, likeCount: 1, commentCount: 1 }));
  await db.doc(`pagePosts/${clean}/likes/${visitor}`).set({
    schemaVersion: 1, userId: visitor, postId: clean, createdAt: Timestamp.fromMillis(nowMs) });
  const visitorComment = newCommentId();
  await db.doc(`pagePostComments/${visitorComment}`).set(
    commentDoc({ postId: clean, pageId: uid }, visitorComment, visitor, nowMs));

  const reported = newPostId();
  const reportedMedia = photoMedia(uid, reported, 1);
  await db.doc(`pagePosts/${reported}`).set(postDoc(uid, reported, nowMs - 2000, {
    kind: "photo", media: reportedMedia, evidenceHold: true }));
  await db.doc(`pagePostOpenReports/${reported}`).set({
    schemaVersion: 1, postId: reported, pageId: uid, count: 1, lastReportId: "report-open-1",
    updatedAt: Timestamp.fromMillis(nowMs) });

  const tombstone = newPostId();
  const tombstoneMedia = photoMedia(uid, tombstone, 1);
  await db.doc(`pagePosts/${tombstone}`).set(postDoc(uid, tombstone, nowMs - 1000, {
    kind: "photo", media: tombstoneMedia, status: "deleted", deletedAt: Timestamp.fromMillis(nowMs),
    moderationEvidence: { evidenceVersion: 1, metadataFingerprint: "a".repeat(64) } }));

  // The comment the account wrote on another Page's post, with its bell row.
  const theirPost = newPostId();
  await db.doc(`pagePosts/${theirPost}`).set(postDoc(otherPage, theirPost, nowMs, { commentCount: 1 }));
  const ownComment = newCommentId();
  await db.doc(`pagePostComments/${ownComment}`).set(
    commentDoc({ postId: theirPost, pageId: otherPage }, ownComment, uid, nowMs));
  await db.doc(`users/${otherPage}/notifications/pagePostComment_${ownComment}`).set({
    type: "pagePostComment", sourcePath: `pagePostComments/${ownComment}` });

  // An open upload, its lease, a budget row and the side records.
  const requestId = `req-${freshUid()}`;
  const uploadPost = pagePostIdFor(uid, requestId, "media");
  const uploadMedia = pageMediaIdFor(uid, requestId, 0);
  const now = Timestamp.fromMillis(nowMs);
  const reservation = newReservation({
    pageId: uid, postId: uploadPost, mediaId: uploadMedia,
    item: { index: 0, size: 2000, width: 10, height: 10, durationMs: null },
    kind: "photo", requestId, now, expiresAt: Timestamp.fromMillis(nowMs + 900_000),
  });
  await db.doc(`pagePostMediaReservations/${uploadMedia}`).set(reservation);
  await db.doc(`pagePostMediaLeases/${uid}`).set({ schemaVersion: 1, ownerId: uid });
  await db.doc(`pagePostBudgets/${uid}_20300101`).set({ schemaVersion: 1, pageId: uid });
  await db.doc(`pageAdultRefusals/${uid}`).set({ schemaVersion: 1, refusedAt: now });
  await db.doc(`pageFollowIndex/${uid}`).set({ schemaVersion: 1, pageIds: [otherPage], updatedAt: now });
  return {
    uid, visitor, otherPage, clean, cleanMedia, visitorComment, reported, reportedMedia,
    tombstone, tombstoneMedia, theirPost, ownComment, reservation,
  };
}

test("content, storage and records remove a Page account and keep only open-report evidence", async () => {
  const s = await seedPageAccount();
  const bucket = recordingBucket();
  const stages = stagesFor(bucket);

  await runToEnd(stages, "content", s.uid);
  assert.equal(await dataOf(`pages/${s.uid}`), null);
  assert.equal((await dataOf("pageVisibility/v1")).notViewable[s.uid], undefined,
    "the Page and its index entry go together");
  // The clean post is gone; its likes and comments are queued; its media too.
  assert.equal(await dataOf(`pagePosts/${s.clean}`), null);
  assert.equal((await dataOf(`pagePostCleanupJobs/${s.clean}`)).reason, "accountDeleted");
  for (const entry of s.cleanMedia) {
    assert.equal((await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`)).heldBy, null);
  }
  // The owner-deleted tombstone with no open report is not kept.
  assert.equal(await dataOf(`pagePosts/${s.tombstone}`), null);
  // The reported post becomes a tombstone; its bytes are held; it is retained.
  const kept = await dataOf(`pagePosts/${s.reported}`);
  assert.equal(kept.status, "deleted");
  assert.match(kept.moderationEvidence.metadataFingerprint, /^[a-f0-9]{64}$/u);
  assert.equal((await dataOf(`pagePostMediaDeletionJobs/${s.reportedMedia[0].mediaId}`)).heldBy,
    "report-open-1");
  const retention = await dataOf(`pageEvidenceRetention/${s.reported}`);
  assert.equal(retention.reason, "accountDeleted");
  assert.equal(retention.purgeAt.toMillis(), nowMs + PAGE_EVIDENCE_RETENTION_MS);
  // The comment the account wrote elsewhere, with its counter and bell row.
  assert.equal(await dataOf(`pagePostComments/${s.ownComment}`), null);
  assert.equal((await dataOf(`pagePosts/${s.theirPost}`)).commentCount, 0);
  assert.equal(await dataOf(`users/${s.otherPage}/notifications/pagePostComment_${s.ownComment}`), null);
  // A second content run is a no-op that still finishes.
  await runToEnd(stages, "content", s.uid);
  assert.equal((await dataOf(`pagePosts/${s.reported}`)).status, "deleted");

  await runToEnd(stages, "storage", s.uid);
  const byPath = new Map(bucket.deletes.map((entry) => [entry.path, entry]));
  for (const entry of [...s.cleanMedia, ...s.tombstoneMedia]) {
    assert.equal(byPath.has(entry.storagePath), true, "an unheld object is deleted");
    assert.equal(byPath.get(entry.storagePath).settings.ifGenerationMatch, entry.generation);
    assert.equal(await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`), null);
  }
  assert.equal(byPath.has(s.reportedMedia[0].storagePath), false, "held evidence is skipped");
  assert.notEqual(await dataOf(`pagePostMediaDeletionJobs/${s.reportedMedia[0].mediaId}`), null);
  assert.equal(byPath.has(s.reservation.storagePath), true, "an open upload is removed");
  assert.equal(await dataOf(`pagePostMediaReservations/${s.reservation.mediaId}`), null);

  await runToEnd(stages, "records", s.uid);
  for (const name of ["pageFollowIndex", "pagePostMediaLeases", "pageAdultRefusals"]) {
    assert.equal(UID_KEYED_DOCUMENTS.includes(name), true);
    assert.equal(await dataOf(`${name}/${s.uid}`), null, name);
  }
  assert.equal(await dataOf(`pagePostBudgets/${s.uid}_20300101`), null);
  // Somebody else's Page is untouched.
  assert.notEqual(await dataOf(`pages/${s.otherPage}`), null);
});

test("retained evidence is purged after 90 days by pagesMaintenance, media released", async () => {
  const s = await seedPageAccount();
  const stages = stagesFor(recordingBucket());
  await runToEnd(stages, "content", s.uid);
  const bucket = new FakeBucket({ nowMs: () => nowMs });
  const maintenance = createPagesMaintenanceService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(bucket),
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  assert.equal((await maintenance.purgeDueEvidence()).purged, 0, "not due yet");
  nowMs += PAGE_EVIDENCE_RETENTION_MS;
  const line = await maintenance.purgeDueEvidence();
  assert.equal(line.purged >= 1, true);
  assert.equal(await dataOf(`pagePosts/${s.reported}`), null);
  assert.equal(await dataOf(`pageEvidenceRetention/${s.reported}`), null);
  assert.equal(await dataOf(`pagePostOpenReports/${s.reported}`), null);
  assert.equal((await dataOf(`pagePostMediaDeletionJobs/${s.reportedMedia[0].mediaId}`)).heldBy, null);
  assert.notEqual(await dataOf(`pagePostCleanupJobs/${s.reported}`), null);
});

test("a resolution before 90 days makes the retained tombstone due at once", async () => {
  const s = await seedPageAccount();
  await runToEnd(stagesFor(recordingBucket()), "content", s.uid);
  // What pages/moderation.js writes when the last open report resolves.
  await db.doc(`pageEvidenceRetention/${s.reported}`).update({ purgeAt: Timestamp.fromMillis(nowMs) });
  const deletion = createPagesAccountDeletion({ db, TimestampImpl: Timestamp, clock: () => nowMs,
    logger: silentLogger() });
  assert.equal(await deletion.purgeRetainedPost(s.reported), true);
  assert.equal(await dataOf(`pagePosts/${s.reported}`), null);
  assert.equal(await deletion.purgeRetainedPost(s.reported), false, "idempotent");
});

test("the deletion queries page through real documents", async () => {
  const uid = freshUid("delq");
  const posts = [newPostId(), newPostId(), newPostId()];
  for (const [index, postId] of posts.entries()) {
    await db.doc(`pagePosts/${postId}`).set(postDoc(uid, postId, nowMs - index));
  }
  const first = await PAGES_DELETION_QUERIES.authorPosts(db, uid).limit(2).get();
  assert.deepEqual(first.docs.map((doc) => doc.id), posts.slice(0, 2));
  const last = first.docs[1];
  const rest = await PAGES_DELETION_QUERIES.authorPosts(db, uid)
    .startAfter(last.data().createdAt, last.id).limit(5).get();
  assert.deepEqual(rest.docs.map((doc) => doc.id), [posts[2]]);
  const [heldMedia, freeMedia] = photoMedia(uid, posts[0], 2);
  await db.doc(`pagePostMediaDeletionJobs/${heldMedia.mediaId}`).set(pageMediaDeletionJob({
    storagePath: heldMedia.storagePath, generation: "5", reason: "ownerDelete", heldBy: "r1",
    now: Timestamp.fromMillis(nowMs) }));
  await db.doc(`pagePostMediaDeletionJobs/${freeMedia.mediaId}`).set(pageMediaDeletionJob({
    storagePath: freeMedia.storagePath, generation: "6", reason: "ownerDelete", heldBy: null,
    now: Timestamp.fromMillis(nowMs) }));
  const jobs = await PAGES_DELETION_QUERIES.unheldJobsUnder(db, uid).get();
  assert.deepEqual(jobs.docs.map((doc) => doc.id), [freeMedia.mediaId]);
  // A uid that merely shares a prefix is outside the range.
  const unrelated = await PAGES_DELETION_QUERIES.unheldJobsUnder(db, uid.slice(0, -1)).get();
  assert.equal(unrelated.docs.some((doc) => doc.id === freeMedia.mediaId), false);
  for (const postId of posts) await db.doc(`pagePosts/${postId}`).delete();
});

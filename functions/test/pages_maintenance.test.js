// pagesMaintenance (ADR-233 §2.12, package B2) against the Firestore
// emulator, with the REAL Pages Storage adapter over an in-memory bucket:
// reservation expiry, media deletion jobs, post cleanup jobs and the daily
// orphan sweep, each bounded.
const assert = require("node:assert/strict");
const { beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-maintenance-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { createPagesMediaStorageAdapter } = require("../pages/media_storage");
const {
  ORPHAN_MIN_AGE_MS,
  ORPHAN_SWEEP_EVERY_MS,
  createPagesMaintenanceService,
} = require("../pages/maintenance");
const {
  PAGE_MEDIA_RESERVATION_TTL_MS,
  newReservation,
  pageMediaDeletionJob,
  pageMediaIdFor,
  pageMediaUploadMetadata,
  pagePostCleanupJob,
  pagePostIdFor,
} = require("../pages/media_contract");
const {
  DAY_MS,
  freshUid,
  newCommentId,
  newPostId,
  photoMedia,
  postDoc,
  silentLogger,
} = require("./helpers/pages_fixture");
const { FakeBucket, STRIPPED_JPEG } = require("./helpers/pages_media_fixture");

const db = getFirestore();
let nowMs = 1_900_000_000_000;

beforeEach(async () => {
  nowMs += DAY_MS;
  // The orphan sweep's cursor is global state: every test starts a fresh pass.
  await db.doc("pageMaintenanceState/orphanSweep").delete();
});

function harness({ limits } = {}) {
  const bucket = new FakeBucket({ nowMs: () => nowMs });
  const logger = silentLogger();
  const maintenance = createPagesMaintenanceService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(bucket),
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger,
    ...(limits ? { limits } : {}),
  });
  return { bucket, maintenance, logger };
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

/// A reservation set + lease exactly as reservePagePostMediaV1 writes them.
async function reservation(ownerId, { count = 1, expiresInMs = PAGE_MEDIA_RESERVATION_TTL_MS } = {}) {
  const requestId = `req-${freshUid()}`;
  const postId = pagePostIdFor(ownerId, requestId, "media");
  const now = Timestamp.fromMillis(nowMs);
  const expiresAt = Timestamp.fromMillis(nowMs + expiresInMs);
  const reservations = [];
  for (let index = 0; index < count; index += 1) {
    const mediaId = pageMediaIdFor(ownerId, requestId, index);
    const value = newReservation({
      pageId: ownerId,
      postId,
      mediaId,
      item: { index, size: STRIPPED_JPEG.length, width: 32, height: 24, durationMs: null },
      kind: "photo",
      requestId,
      now,
      expiresAt,
    });
    await db.doc(`pagePostMediaReservations/${mediaId}`).set(value);
    reservations.push(value);
  }
  await db.doc(`pagePostMediaLeases/${ownerId}`).set({
    schemaVersion: 1,
    ownerId,
    postId,
    requestId,
    mediaIds: reservations.map((value) => value.mediaId),
    status: "uploading",
    expiresAt,
  });
  return { postId, reservations };
}

test("an expired reservation: claimed, object deleted by generation, then reservation and lease", async () => {
  const h = harness();
  const owner = freshUid("pgexp");
  const { reservations } = await reservation(owner, { count: 2, expiresInMs: -1 });
  // One object was uploaded, the other never was.
  const uploaded = reservations[0];
  h.bucket.put(uploaded.storagePath, STRIPPED_JPEG, {
    contentType: "image/jpeg", metadata: pageMediaUploadMetadata(uploaded),
  });
  const live = freshUid("pglive");
  const { reservations: liveSet } = await reservation(live);

  // Drain (other suites may leave expired reservations in the emulator).
  let expired = 0;
  for (let pass = 0; pass < 20; pass += 1) {
    const line = await h.maintenance.expireReservations();
    expired += line.expired;
    if (!line.hasMore) break;
  }
  assert.equal(expired >= 2, true);
  assert.equal(h.bucket.metadataOf(uploaded.storagePath), null);
  assert.equal(h.bucket.deleted.some((entry) => entry.objectPath === uploaded.storagePath), true);
  for (const value of reservations) {
    assert.equal(await dataOf(`pagePostMediaReservations/${value.mediaId}`), null);
  }
  assert.equal(await dataOf(`pagePostMediaLeases/${owner}`), null);
  // A live set is untouched.
  assert.notEqual(await dataOf(`pagePostMediaReservations/${liveSet[0].mediaId}`), null);
  assert.notEqual(await dataOf(`pagePostMediaLeases/${live}`), null);
});

test("an expired reservation never removes a NEWER lease of the same owner", async () => {
  const h = harness();
  const owner = freshUid("pglease");
  const { reservations } = await reservation(owner, { expiresInMs: -1 });
  // The owner started a new set after the old one expired.
  const next = await reservation(owner);
  for (let pass = 0; pass < 20; pass += 1) {
    if (!(await h.maintenance.expireReservations()).hasMore) break;
  }
  assert.equal(await dataOf(`pagePostMediaReservations/${reservations[0].mediaId}`), null);
  assert.equal((await dataOf(`pagePostMediaLeases/${owner}`)).postId, next.postId);
});

test("deletion jobs: held jobs are skipped, due jobs delete by generation, failures back off", async () => {
  const h = harness();
  const pageId = freshUid("pgjobs");
  const postId = newPostId();
  const [free, held, failing, superseded] = photoMedia(pageId, postId, 4);
  const now = Timestamp.fromMillis(nowMs);
  const generation = (entry) => h.bucket.put(entry.storagePath, STRIPPED_JPEG, { contentType: "image/jpeg" });
  const jobs = [
    [free, generation(free), null],
    [held, generation(held), "report-9"],
    [failing, generation(failing), null],
  ];
  // A job whose generation is not the live one never deletes the live object.
  const liveGeneration = generation(superseded);
  jobs.push([superseded, String(Number(liveGeneration) - 1), null]);
  for (const [entry, gen, heldBy] of jobs) {
    await db.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`).set(pageMediaDeletionJob({
      storagePath: entry.storagePath, generation: gen, reason: "ownerDelete", heldBy, now,
    }));
  }
  h.bucket.failDelete.add(failing.storagePath);
  await h.maintenance.processDeletionJobs();
  assert.equal(h.bucket.metadataOf(free.storagePath), null);
  assert.equal(await dataOf(`pagePostMediaDeletionJobs/${free.mediaId}`), null);
  assert.notEqual(h.bucket.metadataOf(held.storagePath), null);
  assert.equal((await dataOf(`pagePostMediaDeletionJobs/${held.mediaId}`)).attempts, 0);
  const retried = await dataOf(`pagePostMediaDeletionJobs/${failing.mediaId}`);
  assert.equal(retried.attempts, 1);
  assert.equal(retried.nextAttemptAt.toMillis(), nowMs + 60_000);
  assert.notEqual(h.bucket.metadataOf(superseded.storagePath), null, "the live generation stays");
  assert.equal(await dataOf(`pagePostMediaDeletionJobs/${superseded.mediaId}`), null);
  // Not due before its backoff; due after.
  h.bucket.failDelete.delete(failing.storagePath);
  await h.maintenance.processDeletionJobs();
  assert.notEqual(h.bucket.metadataOf(failing.storagePath), null);
  nowMs += 60_000;
  await h.maintenance.processDeletionJobs();
  assert.equal(h.bucket.metadataOf(failing.storagePath), null);
  await db.doc(`pagePostMediaDeletionJobs/${held.mediaId}`).delete();
});

test("the orphan sweep deletes only old, unreferenced, unreserved, unowned objects; bounded and resumable", async () => {
  const h = harness({ limits: { reservations: 50, deletionJobs: 50, cleanupJobs: 20, orphans: 4 } });
  const pageId = freshUid("pgorph");
  const old = nowMs - ORPHAN_MIN_AGE_MS - 1;
  const put = (objectPath, createdAtMs = old) =>
    h.bucket.put(objectPath, STRIPPED_JPEG, { contentType: "image/jpeg", createdAtMs });

  // Referenced by a post (published) and by a tombstone.
  const livePostId = newPostId();
  const [referenced, unusedInPost] = photoMedia(pageId, livePostId, 2);
  await db.doc(`pagePosts/${livePostId}`).set(postDoc(pageId, livePostId, nowMs, {
    kind: "photo", media: [referenced],
  }));
  put(referenced.storagePath);
  // Uploaded for the set but not published with the post: an orphan.
  put(unusedInPost.storagePath);
  // Reserved (a live upload): kept.
  const { reservations } = await reservation(pageId);
  put(reservations[0].storagePath);
  // Owned by a held deletion job (evidence): kept.
  const heldPostId = newPostId();
  const [heldEntry] = photoMedia(pageId, heldPostId, 1);
  const heldGeneration = put(heldEntry.storagePath);
  await db.doc(`pagePostMediaDeletionJobs/${heldEntry.mediaId}`).set(pageMediaDeletionJob({
    storagePath: heldEntry.storagePath, generation: heldGeneration, reason: "ownerDelete",
    heldBy: "report-3", now: Timestamp.fromMillis(nowMs),
  }));
  // No post, no reservation, no job: an orphan.
  const [orphan] = photoMedia(pageId, newPostId(), 1);
  put(orphan.storagePath);
  // An orphan younger than 1 h: kept for now.
  const [young] = photoMedia(pageId, newPostId(), 1);
  put(young.storagePath, nowMs - 60_000);
  // A name this feature never writes.
  put(`page_posts/${pageId}/garbage.bin`);

  const first = await h.maintenance.sweepOrphans();
  assert.equal(first.ran, true);
  assert.equal(first.listed, 4);
  assert.equal(first.hasMore, true);
  let passes = 1;
  let line = first;
  while (line.hasMore) {
    line = await h.maintenance.sweepOrphans();
    passes += 1;
    assert.equal(passes < 10, true);
  }
  assert.notEqual(h.bucket.metadataOf(referenced.storagePath), null);
  assert.notEqual(h.bucket.metadataOf(reservations[0].storagePath), null);
  assert.notEqual(h.bucket.metadataOf(heldEntry.storagePath), null);
  assert.notEqual(h.bucket.metadataOf(young.storagePath), null);
  assert.equal(h.bucket.metadataOf(unusedInPost.storagePath), null);
  assert.equal(h.bucket.metadataOf(orphan.storagePath), null);
  assert.equal(h.bucket.metadataOf(`page_posts/${pageId}/garbage.bin`), null);
  // A completed pass waits a day.
  assert.deepEqual(await h.maintenance.sweepOrphans(), { ran: false });
  nowMs += ORPHAN_SWEEP_EVERY_MS;
  assert.equal((await h.maintenance.sweepOrphans()).ran, true);
  await db.doc(`pagePostMediaDeletionJobs/${heldEntry.mediaId}`).delete();
});

test("post cleanup: likes and comments of a hard-deleted post, never of a live one", async () => {
  const h = harness();
  const pageId = freshUid("pgclean");
  const goneId = newPostId();
  const writer = db.bulkWriter();
  for (let index = 0; index < 3; index += 1) {
    writer.set(db.doc(`pagePosts/${goneId}/likes/liker-${index}`), { userId: `liker-${index}` });
    writer.set(db.collection("pagePostComments").doc(), { postId: goneId, text: `c${index}` });
  }
  const liveId = newPostId();
  writer.set(db.doc(`pagePosts/${liveId}`), postDoc(pageId, liveId, nowMs));
  writer.set(db.collection("pagePostComments").doc(), { postId: liveId, text: "keep" });
  await writer.close();
  const now = Timestamp.fromMillis(nowMs);
  await db.doc(`pagePostCleanupJobs/${goneId}`).set(pagePostCleanupJob({
    postId: goneId, pageId, reason: "ownerDelete", now,
  }));
  await db.doc(`pagePostCleanupJobs/${liveId}`).set(pagePostCleanupJob({
    postId: liveId, pageId, reason: "ownerDelete", now,
  }));
  await h.maintenance.processCleanupJobs();
  assert.equal((await db.collection(`pagePosts/${goneId}/likes`).get()).size, 0);
  assert.equal((await db.collection("pagePostComments").where("postId", "==", goneId).get()).size, 0);
  assert.equal(await dataOf(`pagePostCleanupJobs/${goneId}`), null);
  // A job that finds its post alive deletes nothing and is dropped (logged).
  assert.equal((await db.collection("pagePostComments").where("postId", "==", liveId).get()).size, 1);
  assert.equal(await dataOf(`pagePostCleanupJobs/${liveId}`), null);
  assert.equal(h.logger.entries.some((entry) => entry.level === "error" &&
    entry.args[0] === "pages post cleanup found a live post"), true);
});

// B4: a hard-deleted post's comments take the owner's pagePostComment bell
// rows with them (built from the job's pageId); other rows stay.
test("post cleanup retires each deleted comment's bell row on the Page owner", async () => {
  const h = harness();
  const pageId = freshUid("pgclean");
  const goneId = newPostId();
  const now = Timestamp.fromMillis(nowMs);
  const commentIds = [newCommentId(), newCommentId()];
  const writer = db.bulkWriter();
  for (const commentId of commentIds) {
    writer.set(db.doc(`pagePostComments/${commentId}`), { postId: goneId, pageId, text: "c" });
    writer.set(db.doc(`users/${pageId}/notifications/pagePostComment_${commentId}`), {
      type: "pagePostComment", sourcePath: `pagePostComments/${commentId}`,
    });
  }
  writer.set(db.doc(`users/${pageId}/notifications/follow_someone`), { type: "follow" });
  await writer.close();
  await db.doc(`pagePostCleanupJobs/${goneId}`).set(pagePostCleanupJob({
    postId: goneId, pageId, reason: "ownerDelete", now,
  }));
  await h.maintenance.processPostCleanupJob(goneId);
  for (const commentId of commentIds) {
    assert.equal(await dataOf(`pagePostComments/${commentId}`), null);
    assert.equal(await dataOf(`users/${pageId}/notifications/pagePostComment_${commentId}`), null);
  }
  assert.notEqual(await dataOf(`users/${pageId}/notifications/follow_someone`), null);
  assert.equal(await dataOf(`pagePostCleanupJobs/${goneId}`), null);
});

test("run: every slice reports, and one failing slice never stops the next", async () => {
  const h = harness();
  const results = await h.maintenance.run();
  assert.deepEqual(Object.keys(results), [
    "reservations", "evidenceRetention", "pageDeletion", "deletionJobs", "cleanupJobs", "lapse",
    "followCarry", "orphans",
  ]);
  // ADR-236: an owner's Page deletion runs BEFORE the job slices (the media
  // and cleanup jobs it queues go in the same run); its four parts report.
  // "Delete all posts" jobs come before the purges: their posts are still
  // public while they wait, a purged Page is already hidden.
  assert.deepEqual(Object.keys(results.pageDeletion),
    ["reminders", "clearJobs", "deletions", "memory"]);
  assert.equal(typeof results.pageDeletion.deletions.processed, "number");
  // Package B5: the lapse slice runs hourly; with no activation document the
  // brake is on (downgrades frozen) and the slice still reports.
  assert.equal(typeof results.lapse.ran, "boolean");
  assert.equal(typeof results.evidenceRetention.processed, "number");
  // ADR-234: the follower carry-over slice reports its bounded run.
  assert.equal(typeof results.followCarry.processed, "number");
  assert.equal(results.followCarry.batches <= 10, true);
  const broken = createPagesMaintenanceService({
    firestore: db,
    storage: {
      ...createPagesMediaStorageAdapter(h.bucket),
      listObjects: async () => { throw Object.assign(new Error("down"), { code: 503 }); },
    },
    TimestampImpl: Timestamp,
    clock: () => nowMs + ORPHAN_SWEEP_EVERY_MS * 2,
    logger: h.logger,
  });
  const line = await broken.run();
  assert.deepEqual(line.orphans, { failed: true });
  assert.equal(typeof line.deletionJobs.processed, "number");
  assert.equal(h.logger.entries.some((entry) => entry.level === "error" &&
    entry.args[0] === "pages maintenance slice failed" && entry.args[1].slice === "orphans"), true);
});

test("run: the lapse backstop runs before followCarry, and a failing followCarry slice never "
  + "stops the orphan slice", async () => {
  const h = harness();
  const calls = [];
  const maintenance = createPagesMaintenanceService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(h.bucket),
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: h.logger,
    followCarry: { processDueJobs: async () => {
      calls.push("followCarry");
      throw Object.assign(new Error("down"), { code: 14 });
    } },
    lapse: { sweep: async () => {
      calls.push("lapse");
      return { ran: true };
    } },
  });
  const line = await maintenance.run();
  assert.deepEqual(line.followCarry, { failed: true });
  assert.deepEqual(line.lapse, { ran: true });
  assert.equal(typeof line.orphans.ran, "boolean");
  assert.deepEqual(calls, ["lapse", "followCarry"],
    "a slow carry-over never delays a lapse transition");
  assert.equal(h.logger.entries.some((entry) => entry.level === "error" &&
    entry.args[0] === "pages maintenance slice failed" && entry.args[1].slice === "followCarry" &&
    entry.args[1].code === 14), true);
});

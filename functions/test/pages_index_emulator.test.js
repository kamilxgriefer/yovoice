// Every Premium Pages read query (ADR-233 §1.12, package B3) against the
// Firestore emulator, the composite index each one needs in
// firestore.indexes.json, and the operator's read-only index smoke
// (scripts/smoke_pages_indexes.js). The emulator serves any query without an
// index, so the production proof is the smoke after the index deploy; this
// suite proves the smoke runs the production shapes and that each shape has
// its declared index.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-index-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { FieldPath, getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { PAGES_READ_QUERIES } = require("../pages/reads");
const { PAGES_MAINTENANCE_QUERIES } = require("../pages/maintenance");
const { pageMediaDeletionJob, pagePostCleanupJob } = require("../pages/media_contract");
const {
  EXPECTED_PROJECT,
  assertProject,
  parseArgs,
  smoke,
} = require("../scripts/smoke_pages_indexes");
const {
  commentDoc,
  freshUid,
  newCommentId,
  newPostId,
  pageDoc,
  photoMedia,
  postDoc,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const NOW = 1_900_000_000_000;
const indexes = JSON.parse(fs.readFileSync(
  path.join(__dirname, "..", "..", "firestore.indexes.json"),
  "utf8",
)).indexes;

function declared(collectionGroup, fields) {
  return indexes.some((index) =>
    index.collectionGroup === collectionGroup &&
    index.queryScope === "COLLECTION" &&
    JSON.stringify(index.fields.map((field) => [field.fieldPath, field.order])) ===
      JSON.stringify(fields));
}

test("each read query shape has its composite index declared", () => {
  const expected = [
    ["pagePosts", [["pageId", "ASCENDING"], ["status", "ASCENDING"],
      ["createdAt", "DESCENDING"], ["__name__", "DESCENDING"]]],
    ["pagePosts", [["pageId", "ASCENDING"], ["status", "ASCENDING"], ["kind", "ASCENDING"],
      ["createdAt", "DESCENDING"], ["__name__", "DESCENDING"]]],
    ["pagePostComments", [["postId", "ASCENDING"], ["createdAt", "DESCENDING"],
      ["__name__", "DESCENDING"]]],
    ["pages", [["listed", "ASCENDING"], ["lastPostAt", "DESCENDING"],
      ["__name__", "DESCENDING"]]],
    ["pages", [["listed", "ASCENDING"], ["nameSearch", "ASCENDING"],
      ["__name__", "ASCENDING"]]],
    // B2: pagesMaintenance's due, unheld media deletion jobs.
    ["pagePostMediaDeletionJobs", [["heldBy", "ASCENDING"], ["nextAttemptAt", "ASCENDING"]]],
    // B5: account deletion (posts, comments, unheld media under a uid) and
    // the hourly lapse sweep.
    ["pagePosts", [["authorId", "ASCENDING"], ["createdAt", "DESCENDING"],
      ["__name__", "DESCENDING"]]],
    ["pagePostComments", [["authorId", "ASCENDING"], ["createdAt", "DESCENDING"],
      ["__name__", "DESCENDING"]]],
    ["pages", [["status", "ASCENDING"], ["lapsedAt", "ASCENDING"], ["__name__", "ASCENDING"]]],
    ["pagePostMediaDeletionJobs", [["heldBy", "ASCENDING"], ["storagePath", "ASCENDING"]]],
  ];
  for (const [collectionGroup, fields] of expected) {
    assert.equal(declared(collectionGroup, fields), true,
      `${collectionGroup} ${JSON.stringify(fields)}`);
  }
  // No collection-group query is introduced (ADR-233 Appendix A).
  const pagesIndexes = indexes.filter((index) =>
    ["pages", "pagePosts", "pagePostComments", "pagePostMediaDeletionJobs",
      "pagePostMediaReservations", "pagePostCleanupJobs", "pageEvidenceRetention",
      "pagePostBudgets"].includes(index.collectionGroup));
  assert.equal(pagesIndexes.every((index) => index.queryScope === "COLLECTION"), true);
});

test("every builder runs on real documents, including its startAfter page", async () => {
  const pageId = freshUid("pgidx");
  const id = FieldPath.documentId();
  const at = (offset) => Timestamp.fromMillis(NOW - offset);
  await db.doc(`pages/${pageId}`).set(pageDoc(pageId, NOW, {
    displayName: "Zzindex Page",
    postCount: 3,
    listed: true,
    lastPostAt: at(0),
  }));
  const posts = [];
  for (const [index, overrides] of [{}, { status: "held", heldAt: at(0) }, { kind: "photo" }]
    .entries()) {
    const postId = newPostId();
    const data = postDoc(pageId, postId, NOW - index * 1000, {
      ...overrides,
      media: overrides.kind === "photo" ? photoMedia(pageId, postId) : [],
    });
    await db.doc(`pagePosts/${postId}`).set(data);
    posts.push(data);
  }
  for (let index = 0; index < 3; index += 1) {
    const commentId = newCommentId();
    await db.doc(`pagePostComments/${commentId}`)
      .set(commentDoc(posts[0], commentId, pageId, NOW - index));
  }
  const run = async (query, limit = 1) => {
    const first = await query.limit(limit).get();
    const second = first.empty
      ? first
      : await query.startAfter(first.docs[first.docs.length - 1]).limit(10).get();
    return [first.size, second.size];
  };
  assert.deepEqual(await run(PAGES_READ_QUERIES.feedChunk(db, id, [pageId])), [1, 1]);
  assert.deepEqual(await run(PAGES_READ_QUERIES.wall(db, id, pageId, ["published"], "wall")),
    [1, 1]);
  assert.deepEqual(await run(PAGES_READ_QUERIES.wall(db, id, pageId, ["published", "held"],
    "wall")), [1, 2]);
  assert.deepEqual(await run(PAGES_READ_QUERIES.wall(db, id, pageId, ["published"], "photos")),
    [1, 0]);
  assert.deepEqual(await run(PAGES_READ_QUERIES.comments(db, id, posts[0].postId)), [1, 2]);
  const suggested = await PAGES_READ_QUERIES.suggest(db, id).limit(50).get();
  assert.equal(suggested.docs.some((doc) => doc.id === pageId), true);
  const searched = await PAGES_READ_QUERIES.search(db, id, "zzindex").get();
  assert.deepEqual(searched.docs.map((doc) => doc.id), [pageId]);
  await db.doc(`pages/${pageId}`).update({ listed: false, postCount: 0 });
});

test("every pagesMaintenance query runs on real documents with a startAfter page", async () => {
  const now = Timestamp.fromMillis(NOW);
  const earlier = (offset) => Timestamp.fromMillis(NOW - offset);
  const pageId = freshUid("pgjob");
  const postId = newPostId();
  const [unheld, held, later] = photoMedia(pageId, postId, 3);
  await Promise.all([
    db.doc(`pagePostMediaDeletionJobs/${unheld.mediaId}`).set({
      ...pageMediaDeletionJob({ storagePath: unheld.storagePath, generation: "7",
        reason: "ownerDelete", heldBy: null, now: earlier(2000) }),
    }),
    db.doc(`pagePostMediaDeletionJobs/${held.mediaId}`).set({
      ...pageMediaDeletionJob({ storagePath: held.storagePath, generation: "8",
        reason: "ownerDelete", heldBy: "report-1", now: earlier(2000) }),
    }),
    db.doc(`pagePostMediaDeletionJobs/${later.mediaId}`).set({
      ...pageMediaDeletionJob({ storagePath: later.storagePath, generation: "9",
        reason: "ownerDelete", heldBy: null, now: Timestamp.fromMillis(NOW + 60_000) }),
    }),
    db.doc(`pagePostCleanupJobs/${postId}`).set(pagePostCleanupJob({
      postId, pageId, reason: "ownerDelete", now: earlier(1000),
    })),
    db.doc(`pagePostMediaReservations/${unheld.mediaId}`).set({ expiresAt: earlier(500) }),
  ]);
  const ids = async (query) => (await query.limit(50).get()).docs.map((doc) => doc.id);
  const jobs = await ids(PAGES_MAINTENANCE_QUERIES.dueDeletionJobs(db, now));
  assert.equal(jobs.includes(unheld.mediaId), true);
  assert.equal(jobs.includes(held.mediaId), false, "a held job is never due");
  assert.equal(jobs.includes(later.mediaId), false, "a future job is not due yet");
  assert.equal((await ids(PAGES_MAINTENANCE_QUERIES.dueCleanupJobs(db, now))).includes(postId), true);
  assert.equal((await ids(PAGES_MAINTENANCE_QUERIES.expiredReservations(db, now)))
    .includes(unheld.mediaId), true);
  for (const query of [
    PAGES_MAINTENANCE_QUERIES.dueDeletionJobs(db, now),
    PAGES_MAINTENANCE_QUERIES.dueCleanupJobs(db, now),
    PAGES_MAINTENANCE_QUERIES.expiredReservations(db, now),
  ]) {
    const first = await query.limit(1).get();
    assert.equal(first.size, 1);
    await query.startAfter(first.docs[0]).limit(10).get();
  }
  await Promise.all([unheld, held, later].map((entry) =>
    db.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`).delete()));
  await db.doc(`pagePostCleanupJobs/${postId}`).delete();
  await db.doc(`pagePostMediaReservations/${unheld.mediaId}`).delete();
});

// B4: listPagePostLikersV1's candidate query, through the ADR-230 fetcher,
// on real edges with a startAfter page (no composite index: single-field).
test("the post likers candidates page newest first with the id tiebreak", async () => {
  const { PAGES_ENGAGEMENT_QUERIES } = require("../pages/engagement");
  const { queryCandidateFetcher } = require("../engagement/likers_paging");
  const postId = newPostId();
  const at = Timestamp.fromMillis(NOW);
  const likers = ["liker-a", "liker-b", "liker-c"];
  await Promise.all(likers.map((uid, index) => db.doc(`pagePosts/${postId}/likes/${uid}`).set({
    schemaVersion: 1, userId: uid, postId, createdAt: index === 2 ? Timestamp.fromMillis(NOW - 1) : at,
  })));
  const fetch = queryCandidateFetcher({
    query: PAGES_ENGAGEMENT_QUERIES.postLikes(db, postId),
    documentIdField: FieldPath.documentId(),
    toLikerId: (doc) => doc.id,
  });
  const first = await fetch(null, 2);
  assert.deepEqual(first.map((row) => row.likerId), ["liker-b", "liker-a"]);
  const second = await fetch(first[1].position, 2);
  assert.deepEqual(second.map((row) => row.likerId), ["liker-c"]);
  // No composite index is declared for the likes subcollection.
  assert.equal(indexes.some((index) => index.collectionGroup === "likes" &&
    index.fields.some((field) => field.fieldPath === "postId")), false);
});

test("the smoke refuses any project but production and validates its ids", () => {
  assert.throws(() => assertProject(parseArgs([]), null), /--project must be/);
  assert.throws(() => assertProject(parseArgs(["--project", "demo-yovoice"]), null),
    /--project must be/);
  assert.throws(() => assertProject(parseArgs(["--project", EXPECTED_PROJECT]), "other"),
    /refusing/);
  assert.throws(() => parseArgs(["--page", "a/b"]), /valid uid/);
  assert.throws(() => parseArgs(["--post", "pp_123"]), /Page post id/);
  assert.throws(() => parseArgs(["--limit", "5"]), /Unknown argument/);
});

test("the smoke runs every production shape and prints no identity", async () => {
  const pageId = freshUid("pgsmoke");
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, NOW));
  const report = await smoke({
    db,
    args: parseArgs(["--project", EXPECTED_PROJECT, "--page", pageId, "--post", postId]),
  });
  assert.equal(report.ok, true, JSON.stringify(report));
  assert.equal(report.results.length, 22);
  assert.equal(report.results.every((row) => row.result === "PASS"), true);
  const printed = JSON.stringify(report);
  assert.equal(printed.includes(pageId), false);
  assert.equal(printed.includes(postId), false);
  // Synthetic ids still prove the shapes.
  const synthetic = await smoke({ db, args: parseArgs(["--project", EXPECTED_PROJECT]) });
  assert.equal(synthetic.ok, true);
});

test("a failing query is reported as FAIL with its code, not thrown", async () => {
  const error = new Error("9 FAILED_PRECONDITION: The query requires an index.\nlink");
  error.code = 9;
  const query = {
    where: () => query,
    orderBy: () => query,
    startAfter: () => query,
    limit: () => query,
    get: async () => { throw error; },
  };
  const report = await smoke({
    db: { collection: () => query },
    args: parseArgs(["--project", EXPECTED_PROJECT]),
  });
  assert.equal(report.ok, false);
  assert.equal(report.results.every((row) => row.result === "FAIL" && row.code === 9), true);
  assert.equal(report.results[0].message, "9 FAILED_PRECONDITION: The query requires an index.");
});

// B5: the evidence-retention slice on real rows with a startAfter page (the
// lapse sweep and the deletion queries run on real documents in
// pages_lapse.test.js and pages_deletion.test.js).
test("the evidence-retention query returns only due rows, oldest first", async () => {
  const due = newPostId();
  const later = newPostId();
  const pageId = freshUid("pgret");
  const row = (postId, purgeAtMs) => ({
    schemaVersion: 1, postId, pageId, reason: "accountDeleted",
    purgeAt: Timestamp.fromMillis(purgeAtMs), createdAt: Timestamp.fromMillis(NOW - 1),
  });
  await db.doc(`pageEvidenceRetention/${due}`).set(row(due, NOW - 10));
  await db.doc(`pageEvidenceRetention/${later}`).set(row(later, NOW + 10));
  const query = PAGES_MAINTENANCE_QUERIES.dueEvidenceRetention(db, Timestamp.fromMillis(NOW));
  const first = await query.limit(1).get();
  assert.equal(first.docs.map((doc) => doc.id).includes(later), false);
  await query.startAfter(first.docs[0]).limit(10).get();
  await db.doc(`pageEvidenceRetention/${due}`).delete();
  await db.doc(`pageEvidenceRetention/${later}`).delete();
});

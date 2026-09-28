// ADR-230 §1.5: the likers page query shape against a real Firestore.
// `orderBy(createdAt desc, __name__ desc) + startAfter(ts, id)` has never run
// in production (getVoiceMomentViewV2 uses createdAt alone, without a cursor),
// so this proves, with many edges sharing ONE createdAt, that paging returns
// every edge exactly once, for a likes subcollection and for the flat
// commentLikes store filtered by commentKey, with the cursor round-tripped
// through a real likerPageCursors document (Timestamp in, Timestamp out).
// Run with:
//   firebase emulators:exec --only firestore --project demo-yovoice \
//     "cd functions && node --test test/likers_paging_emulator.test.js"
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const assert = require("node:assert/strict");
const { after, test } = require("node:test");
const { deleteApp, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");

const { likersTargetKey } = require("../engagement/liker_cursors");
const {
  queryCandidateFetcher,
  runLikersPage,
} = require("../engagement/likers_paging");

// Its own emulator namespace (the moment_expiry.test.js reasoning): this
// suite seeds published, permanent Voice Moments and Yeels, and
// moment_integrity.test.js asserts on whole-collection feed results in the
// shared project id that `firebase emulators:exec --project` exports to every
// suite. The emulator keeps one database per project id.
const app = initializeApp(
  { projectId: `${process.env.GCLOUD_PROJECT}-likers-paging` },
  `likers-paging-${process.pid}`,
);
const db = getFirestore(app);
const RUN = `${process.pid}-${Date.now()}`;
const VIEWER = `viewer-${RUN}`;
const NOW_MS = Date.now();

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

async function seed(entries) {
  for (let start = 0; start < entries.length; start += 400) {
    const batch = db.batch();
    for (const [path, data] of entries.slice(start, start + 400)) {
      batch.set(db.doc(path), data);
    }
    await batch.commit();
  }
}

async function everyPage({ targetType, ids, query, toLikerId }) {
  const targetKey = likersTargetKey({ targetType, ids });
  const listed = [];
  let cursor = null;
  let pages = 0;
  do {
    const now = Timestamp.now();
    const { response } = await runLikersPage({
      db,
      Timestamp,
      viewerId: VIEWER,
      targetType,
      targetKey,
      cursor,
      timing: { nowMs: now.toMillis(), now },
      fetchCandidates: queryCandidateFetcher({
        query,
        documentIdField: FieldPath.documentId(),
        toLikerId,
      }),
      // Everyone visible: this test is about the query, not the predicate.
      resolveVisible: async (take) => take.map((candidate) => ({
        userId: candidate.likerId,
        displayName: "N",
        photoUrl: null,
        reaction: null,
      })),
    });
    listed.push(...response.likers.map((row) => row.userId));
    if (response.nextCursor !== null) {
      const stored = await db.doc(`likerPageCursors/${response.nextCursor}`).get();
      assert.equal(typeof stored.data().afterCreatedAt.toMillis, "function");
      assert.equal(stored.data().viewerId, VIEWER);
    }
    cursor = response.nextCursor;
    pages += 1;
  } while (cursor !== null && pages < 20);
  return { listed, pages };
}

test("voiceMoments/{m}/likes pages by (createdAt desc, __name__ desc) with equal times", async () => {
  const momentId = `moment-${RUN}`;
  const shared = Timestamp.fromMillis(NOW_MS - 60_000);
  const older = Timestamp.fromMillis(NOW_MS - 120_000);
  const entries = [];
  const expected = [];
  // 30 edges at one createdAt, 12 older ones: 42 in total, 3 pages.
  for (let index = 0; index < 42; index += 1) {
    const uid = `liker-${RUN}-${String(index).padStart(2, "0")}`;
    entries.push([`voiceMoments/${momentId}/likes/${uid}`, {
      schemaVersion: 1,
      userId: uid,
      momentId,
      createdAt: index < 30 ? shared : older,
    }]);
  }
  await seed(entries);
  const sharedIds = entries.slice(0, 30).map(([path]) => path.split("/").at(-1)).sort().reverse();
  const olderIds = entries.slice(30).map(([path]) => path.split("/").at(-1)).sort().reverse();
  expected.push(...sharedIds, ...olderIds);

  const { listed, pages } = await everyPage({
    targetType: "voiceMoment",
    ids: [momentId],
    query: db.collection(`voiceMoments/${momentId}/likes`),
    toLikerId: (doc) => (doc.data().userId === doc.id ? doc.id : null),
  });
  assert.equal(pages, 3);
  assert.deepEqual(listed, expected);
});

test("commentLikes filtered by commentKey pages with equal times and no foreign keys", async () => {
  const momentId = `moment-${RUN}`;
  const commentId = `comment-${RUN}`;
  const commentKey = `v:${momentId}:${commentId}`;
  const otherKey = `v:${momentId}:other-${RUN}`;
  const shared = Timestamp.fromMillis(NOW_MS - 30_000);
  const entries = [];
  for (let index = 0; index < 27; index += 1) {
    const uid = `cl-${RUN}-${String(index).padStart(2, "0")}`;
    for (const key of [commentKey, otherKey]) {
      entries.push([`commentLikes/${key}:${uid}`, {
        schemaVersion: 1,
        parentKind: "voiceMoment",
        parentId: momentId,
        commentId: key === commentKey ? commentId : `other-${RUN}`,
        commentKey: key,
        userId: uid,
        createdAt: shared,
      }]);
    }
  }
  await seed(entries);
  const expected = entries
    .filter(([, data]) => data.commentKey === commentKey)
    .map(([path]) => path.split("/").at(-1))
    .sort()
    .reverse()
    .map((id) => id.slice(commentKey.length + 1));

  const { listed, pages } = await everyPage({
    targetType: "voiceMomentComment",
    ids: [momentId, commentId],
    query: db.collection("commentLikes").where("commentKey", "==", commentKey),
    toLikerId: (doc) => {
      const data = doc.data();
      return doc.id === `${commentKey}:${data.userId}` ? data.userId : null;
    },
  });
  assert.equal(pages, 2);
  assert.deepEqual(listed, expected);
});

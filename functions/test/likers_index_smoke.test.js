const assert = require("node:assert/strict");
const { after, before, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-likers-index-smoke-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  EXPECTED_PROJECT,
  assertProject,
  parseArgs,
  smoke,
} = require("../scripts/smoke_likers_indexes");
const { commentLikeKey } = require("../engagement/comment_likes");

// The operator's index smoke (docs/DEPLOYMENT.md, "See who liked"). The
// emulator cannot prove a production index; these tests prove the script
// runs the production query shapes end to end, pages with startAfter, never
// writes and never prints an identity.

const db = getFirestore();
const MOMENT = "smoke-moment";
const REEL = "smoke-reel";
const COMMENT = "smoke-comment";
const VIEWER = "smokeviewer0000000000000001";
const LIKERS = Array.from({ length: 25 }, (_, index) =>
  `smokeliker${String(index).padStart(17, "0")}`);
const CREATED_AT = Timestamp.fromMillis(1_830_000_000_000);

// Only this suite's own documents: other suites share the emulator.
async function clear() {
  const keys = [
    commentLikeKey("voiceMoment", MOMENT, COMMENT),
    commentLikeKey("reel", REEL, COMMENT),
  ];
  const snapshots = await Promise.all([
    db.collection(`voiceMoments/${MOMENT}/likes`).get(),
    db.collection(`reels/${REEL}/likes`).get(),
    db.collection("commentLikes").where("commentKey", "in", keys).get(),
  ]);
  await Promise.all([
    ...snapshots.flatMap((snapshot) => snapshot.docs.map((doc) => doc.ref.delete())),
    ...keys.map((key) => db.doc(`commentLikeCounters/${key}`).delete()),
  ]);
}

before(async () => {
  await clear();
  const key = commentLikeKey("voiceMoment", MOMENT, COMMENT);
  const batch = db.batch();
  // Every edge shares ONE createdAt, so the second page exists only through
  // the __name__ tiebreak.
  for (const uid of [...LIKERS, VIEWER]) {
    batch.set(db.doc(`voiceMoments/${MOMENT}/likes/${uid}`), {
      schemaVersion: 1, userId: uid, momentId: MOMENT, createdAt: CREATED_AT,
    });
    batch.set(db.doc(`reels/${REEL}/likes/${uid}`), {
      schemaVersion: 1, userId: uid, reelId: REEL, createdAt: CREATED_AT,
    });
    batch.set(db.doc(`commentLikes/${key}:${uid}`), {
      schemaVersion: 1,
      parentKind: "voiceMoment",
      parentId: MOMENT,
      commentId: COMMENT,
      commentKey: key,
      userId: uid,
      createdAt: CREATED_AT,
    });
  }
  batch.set(db.doc(`commentLikeCounters/${key}`), {
    schemaVersion: 1,
    parentKind: "voiceMoment",
    parentId: MOMENT,
    commentId: COMMENT,
    commentKey: key,
    likeCount: LIKERS.length + 1,
    updatedAt: CREATED_AT,
  });
  await batch.commit();
});

after(clear);

test("the smoke refuses any project but production and validates its ids", () => {
  assert.throws(() => assertProject(parseArgs([]), null), /--project must be/);
  assert.throws(
    () => assertProject(parseArgs(["--project", "demo-yovoice"]), null),
    /--project must be/,
  );
  assert.throws(
    () => assertProject(parseArgs(["--project", EXPECTED_PROJECT]), "other-project"),
    /refusing/,
  );
  assert.throws(() => parseArgs(["--moment", "a/b"]), /safe id/);
  assert.throws(() => parseArgs(["--moment-comment", "only-one"]), /parentId/);
  assert.throws(() => parseArgs(["--viewer", "a/b"]), /valid uid/);
  assert.throws(() => parseArgs(["--limit", "5"]), /Unknown argument/);
  assert.deepEqual(parseArgs(["--reel-comment", "r1/c1"]).reelComment, {
    parentId: "r1",
    commentId: "c1",
  });
});

test("the smoke pages every target through the production queries and prints no identity", async () => {
  const report = await smoke({
    db,
    args: parseArgs([
      "--moment", MOMENT,
      "--reel", REEL,
      "--moment-comment", `${MOMENT}/${COMMENT}`,
      "--reel-comment", `${REEL}/${COMMENT}`,
      "--viewer", VIEWER,
    ]),
  });
  assert.equal(report.ok, true, JSON.stringify(report));
  const byQuery = Object.fromEntries(report.results.map((row) => [row.query, row]));
  // 26 edges at one createdAt: 21 on the first page, 5 after the tiebreak.
  for (const label of [
    "voiceMoment likes (createdAt desc, __name__ desc)",
    "reel likes (createdAt desc, __name__ desc)",
    "voiceMomentComment commentLikes (commentKey, createdAt desc, __name__ desc)",
  ]) {
    assert.equal(byQuery[label].firstPage, 21, label);
    assert.equal(byQuery[label].secondPage, 5, label);
  }
  assert.equal(byQuery["voiceMomentComment purge (commentKey ==)"].edges, 26);
  assert.deepEqual(
    {
      likeCount: byQuery["voiceMomentComment view state (counters in; userId, commentKey in)"].likeCount,
      callerLiked: byQuery["voiceMomentComment view state (counters in; userId, commentKey in)"].callerLiked,
    },
    { likeCount: 26, callerLiked: true },
  );
  // An empty target still runs (and in production still proves) the index.
  const empty = byQuery["reelComment commentLikes (commentKey, createdAt desc, __name__ desc)"];
  assert.equal(empty.result, "PASS");
  assert.deepEqual([empty.firstPage, empty.secondPage], [0, 0]);

  const printed = JSON.stringify(report);
  for (const uid of [...LIKERS, VIEWER]) {
    assert.equal(printed.includes(uid), false, "a uid reached the report");
  }
  assert.equal(printed.includes(commentLikeKey("voiceMoment", MOMENT, COMMENT)), false);
});

test("a failing query is reported as FAIL with its code, not thrown", async () => {
  const failing = {
    collection() {
      const error = new Error("9 FAILED_PRECONDITION: The query requires an index.\nlink");
      error.code = 9;
      const query = {
        doc: () => ({ collection: () => query }),
        where: () => query,
        orderBy: () => query,
        startAfter: () => query,
        limit: () => query,
        get: async () => { throw error; },
      };
      return query;
    },
  };
  const report = await smoke({
    db: failing,
    args: parseArgs(["--moment", MOMENT]),
  });
  assert.equal(report.ok, false);
  assert.deepEqual(report.results, [{
    query: "voiceMoment likes (createdAt desc, __name__ desc)",
    result: "FAIL",
    code: 9,
    message: "9 FAILED_PRECONDITION: The query requires an index.",
  }]);
  // No target means nothing was proven: not ok.
  assert.equal((await smoke({ db, args: parseArgs([]) })).ok, false);
});

// The operator activation switch (scripts/set_likers_activation.js) lives
// beside the smoke: both are the DEPLOYMENT.md "See who liked" runbook.
const activationScript = require("../scripts/set_likers_activation");
const {
  assertLikersEnabled,
  LIKERS_SURFACES,
} = require("../engagement/likers_activation");

test("the activation script dry-runs by default, writes the exact shape, and rolls back", async () => {
  const reference = db.doc("appConfig/likersV1");
  // A stale revision-1 document with listedSince reads as OFF.
  await reference.set({
    schemaVersion: 1,
    enabled: true,
    serverMessagesEnabled: true,
    listedSince: null,
    updatedAt: CREATED_AT,
  });
  const on = activationScript.parseArgs([
    "--project", activationScript.EXPECTED_PROJECT,
    "--enabled", "true",
    "--server-messages", "true",
  ]);
  const dry = await activationScript.run({ db, args: on });
  assert.deepEqual(dry.before, { content: false, serverMessages: false });
  assert.deepEqual(dry.requested, { content: true, serverMessages: true });
  assert.equal("listedSince" in (await reference.get()).data(), true, "dry run wrote");

  const applied = await activationScript.run({ db, args: { ...on, apply: true } });
  assert.deepEqual(applied.after, { content: true, serverMessages: true });
  const stored = (await reference.get()).data();
  assert.deepEqual(Object.keys(stored).sort(), [
    "enabled",
    "schemaVersion",
    "serverMessagesEnabled",
    "updatedAt",
  ]);
  await assertLikersEnabled({ db, surface: LIKERS_SURFACES.SERVER_MESSAGE });

  const contentOnly = await activationScript.run({
    db,
    args: { ...on, serverMessagesEnabled: false, apply: true },
  });
  assert.deepEqual(contentOnly.after, { content: true, serverMessages: false });
  await assertLikersEnabled({ db, surface: LIKERS_SURFACES.CONTENT });
  await assert.rejects(
    assertLikersEnabled({ db, surface: LIKERS_SURFACES.SERVER_MESSAGE }),
    (error) => error.details?.reason === "likersNotEnabled",
  );

  const rollback = await activationScript.run({
    db,
    args: { ...on, enabled: false, apply: true },
  });
  assert.deepEqual(rollback.after, { content: false, serverMessages: false });
  await assert.rejects(
    assertLikersEnabled({ db, surface: LIKERS_SURFACES.CONTENT }),
    (error) => error.details?.reason === "likersNotEnabled",
  );
  await reference.delete();
});

test("the activation script validates its flags and project", () => {
  assert.throws(() => activationScript.parseArgs(["--enabled", "true"]), /both required/);
  assert.throws(
    () => activationScript.parseArgs(["--enabled", "yes", "--server-messages", "true"]),
    /true or false/,
  );
  assert.throws(
    () => activationScript.assertProject(
      activationScript.parseArgs(["--project", "demo", "--enabled", "false", "--server-messages", "false"]),
      null,
    ),
    /--project must be/,
  );
  assert.throws(() => activationScript.parseArgs(["--listed-since", "x"]), /Unknown argument/);
});

// Comment likes (ADR-230): every comment-document deletion fires
// onMomentCommentDeleted / onReelCommentDeleted, and handleCommentDeleted
// purges that comment's commentLikes edges and its commentLikeCounters row
// FIRST, before notification retirement and the mention-record cleanup.
// Runs against the Firestore emulator (the production query and batch
// shapes), like engagement_notifications.test.js.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const {
  COMMENT_RETRY_WINDOW_MS,
  handleMomentCommentDeleted,
  handleReelCommentDeleted,
} = require("../notifications/engagement");
const { COMMENT_LIKE_PURGE_BATCH_SIZE } = require("../engagement/comment_likes");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
const emulatorTest = (name, fn) => test(
  `Comment like purge: ${name}`,
  { skip: enabled ? false : "Requires an explicit localhost emulator." },
  fn,
);

const NOW_MS = Date.now();
const touched = [];

after(async () => {
  for (const reference of touched) await reference.delete().catch(() => {});
});

function id(prefix) {
  return `clp-${prefix}-${randomUUID().slice(0, 8)}`;
}

function event(params, { time = new Date(NOW_MS).toISOString() } = {}) {
  return { id: `cloud-event-${randomUUID()}`, time, params, data: null };
}

async function seedLikes(parentKind, parentId, commentId, count) {
  const prefix = parentKind === "voiceMoment" ? "v" : "r";
  const commentKey = `${prefix}:${parentId}:${commentId}`;
  const createdAt = Timestamp.fromMillis(NOW_MS - 60_000);
  for (let start = 0; start < count; start += 400) {
    const batch = db.batch();
    for (let index = start; index < Math.min(count, start + 400); index += 1) {
      const userId = `clp-u-${String(index).padStart(4, "0")}`;
      const reference = db.doc(`commentLikes/${commentKey}:${userId}`);
      touched.push(reference);
      batch.set(reference, {
        schemaVersion: 1,
        parentKind,
        parentId,
        commentId,
        commentKey,
        userId,
        createdAt,
      });
    }
    await batch.commit();
  }
  const counter = db.doc(`commentLikeCounters/${commentKey}`);
  touched.push(counter);
  await counter.set({
    schemaVersion: 1,
    parentKind,
    parentId,
    commentId,
    commentKey,
    likeCount: count,
    updatedAt: Timestamp.fromMillis(NOW_MS - 60_000),
  });
  return commentKey;
}

async function remaining(commentKey) {
  const edges = await db.collection("commentLikes")
    .where("commentKey", "==", commentKey)
    .get();
  const counter = await db.doc(`commentLikeCounters/${commentKey}`).get();
  return { edges: edges.size, counter: counter.exists };
}

// Records the order in which the handler touches collections and documents.
function recordingDb(log, { failCommentLikes = false } = {}) {
  return new Proxy(db, {
    get(target, property) {
      if (property === "collection") {
        return (path) => {
          log.push(`collection:${path}`);
          if (failCommentLikes && path === "commentLikes") {
            const failing = {
              where: () => failing,
              limit: () => failing,
              get: async () => {
                const error = new Error("backend unavailable");
                error.code = "unavailable";
                throw error;
              },
            };
            return failing;
          }
          return target.collection(path);
        };
      }
      if (property === "doc") {
        return (path) => {
          log.push(`doc:${path.split("/")[0]}`);
          return target.doc(path);
        };
      }
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

emulatorTest("a Voice comment's likes go, in batches, before notification retirement", async () => {
  const momentId = id("moment");
  const commentId = id("comment");
  const count = COMMENT_LIKE_PURGE_BATCH_SIZE + 50;
  const commentKey = await seedLikes("voiceMoment", momentId, commentId, count);
  // A sibling comment's likes are untouched.
  const siblingKey = await seedLikes("voiceMoment", momentId, id("sibling"), 3);
  assert.deepEqual(await remaining(commentKey), { edges: count, counter: true });

  const log = [];
  const result = await handleMomentCommentDeleted(
    event({ momentId, commentId }),
    { firestore: recordingDb(log) },
  );
  assert.deepEqual(result, { retired: 0 });
  assert.deepEqual(await remaining(commentKey), { edges: 0, counter: false });
  assert.deepEqual(await remaining(siblingKey), { edges: 3, counter: true });

  const lastPurge = log.lastIndexOf("doc:commentLikeCounters");
  const firstRetirement = log.findIndex((entry) =>
    entry === "doc:notificationDeliveryEvents" || entry === "doc:commentMentions");
  assert.ok(log.indexOf("collection:commentLikes") === 0, log.join(","));
  assert.ok(lastPurge >= 0 && firstRetirement > lastPurge, log.join(","));
  // Two pages: 400, then a short page of 50 that ends the loop.
  assert.equal(log.filter((entry) => entry === "collection:commentLikes").length, 2);

  // A redelivery is a no-op.
  assert.deepEqual(
    await handleMomentCommentDeleted(event({ momentId, commentId })),
    { retired: 0 },
  );
  assert.deepEqual(await remaining(commentKey), { edges: 0, counter: false });
});

emulatorTest("a Yeel comment's likes are purged the same way", async () => {
  const reelId = id("reel").replaceAll("-", "_");
  const commentId = "d".repeat(40);
  const commentKey = await seedLikes("reel", reelId, commentId, 5);
  await handleReelCommentDeleted(event({ reelId, commentId }));
  assert.deepEqual(await remaining(commentKey), { edges: 0, counter: false });
});

emulatorTest("inside the retry window a purge failure rethrows so the trigger retries", async () => {
  const momentId = id("moment");
  const commentId = id("comment");
  const log = [];
  await assert.rejects(
    handleMomentCommentDeleted(event({ momentId, commentId }), {
      firestore: recordingDb(log, { failCommentLikes: true }),
      nowMs: NOW_MS + COMMENT_RETRY_WINDOW_MS - 1_000,
    }),
    (error) => error.code === "unavailable",
  );
  // Nothing after the purge ran.
  assert.equal(
    log.some((entry) => entry === "doc:notificationDeliveryEvents"),
    false,
  );
});

emulatorTest("a stale event logs the abandoned purge and still retires notifications", async () => {
  const momentId = id("moment");
  const commentId = id("comment");
  const log = [];
  const errors = [];
  const original = logger.error;
  logger.error = (message, payload) => errors.push([message, payload]);
  try {
    const result = await handleMomentCommentDeleted(event({ momentId, commentId }), {
      firestore: recordingDb(log, { failCommentLikes: true }),
      nowMs: NOW_MS + COMMENT_RETRY_WINDOW_MS + 1_000,
    });
    assert.deepEqual(result, { retired: 0 });
  } finally {
    logger.error = original;
  }
  assert.deepEqual(errors, [["comment like purge abandoned", {
    surface: "moment",
    parentId: momentId,
    commentId,
    code: "unavailable",
  }]]);
  assert.ok(log.includes("doc:notificationDeliveryEvents"), log.join(","));
});

emulatorTest("an id no toggle accepts holds no likes and is skipped", async () => {
  const log = [];
  await handleMomentCommentDeleted(
    event({ momentId: "legacy moment id", commentId: "c:1" }),
    { firestore: recordingDb(log) },
  );
  assert.equal(log.includes("collection:commentLikes"), false);
});

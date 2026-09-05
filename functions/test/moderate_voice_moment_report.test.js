const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { moderateReport } = require("../moderation/reports");
const {
  digest,
} = require("../integrity/guards");
const {
  momentStoragePath,
  voiceReplyStoragePath,
} = require("../moments/integrity");

const db = getFirestore();
const run = moderateReport.run ?? moderateReport;
const MODERATOR = "vmr-moderator";
const AUTHOR = "vmr-author";
const REPORTER = "vmr-reporter";
const MOMENT_ID = "vmr-moment-01";
const COMMENT_ID = "a1b2c3d4e5f60718293a";
const ROOT_REPORT_ID = "vmr-report-root";
const SECOND_ROOT_REPORT_ID = "vmr-report-root-second";
const COMMENT_REPORT_ID = "vmr-report-comment";
const SECOND_COMMENT_REPORT_ID = "vmr-report-comment-second";
const MISSING_REPORT_ID = "vmr-report-missing";
const DELETING_REPORT_ID = "vmr-report-deleting";
const NOW_MS = 1_820_000_000_000;

function request(reportId, requestId) {
  return {
    auth: {
      uid: MODERATOR,
      token: {
        role: "moderator",
        email: "vmr-moderator@example.invalid",
        email_verified: true,
        auth_time: Math.floor(Date.now() / 1000),
      },
    },
    data: {
      reportId,
      requestId,
      action: "removeAndResolve",
      resolution: "contentRemoved",
      moderatorNote: "canonical Voice Moment moderation test",
    },
  };
}

function publishedMoment(overrides = {}) {
  const createdAt = Timestamp.fromMillis(NOW_MS);
  return {
    schemaVersion: 2,
    authorId: AUTHOR,
    authorName: "Voice author",
    authorPhotoUrl: null,
    caption: "reported voice",
    durationSeconds: 8,
    audioUrl: null,
    storagePath: momentStoragePath(AUTHOR, MOMENT_ID),
    mediaGeneration: "1001",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
    replyToMomentId: null,
    isPublished: true,
    isDeleted: false,
    status: "published",
    likeCount: 0,
    commentCount: 0,
    createdAt,
    updatedAt: createdAt,
    publishedAt: createdAt,
    expiresAt: Timestamp.fromMillis(NOW_MS + 24 * 60 * 60_000),
    ...overrides,
  };
}

function voiceComment() {
  return {
    schemaVersion: 2,
    type: "voice",
    authorId: AUTHOR,
    authorName: "Voice author",
    authorPhotoUrl: null,
    text: "",
    audioUrl: null,
    storagePath: voiceReplyStoragePath(AUTHOR, MOMENT_ID, COMMENT_ID),
    durationSeconds: 7,
    mediaGeneration: "2002",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
    createdAt: Timestamp.fromMillis(NOW_MS),
  };
}

function voiceReport(targetType, overrides = {}) {
  const isComment = targetType === "voiceMomentComment";
  const { selfContained = false, ...reportOverrides } = overrides;
  return {
    schemaVersion: 2,
    reporterId: REPORTER,
    targetType,
    conversationId: null,
    messageId: null,
    momentId: MOMENT_ID,
    commentId: isComment ? COMMENT_ID : null,
    roomId: null,
    clubId: null,
    channelId: null,
    note: "",
    reason: "harassment",
    status: "open",
    createdAt: Timestamp.fromMillis(NOW_MS),
    updatedAt: Timestamp.fromMillis(NOW_MS),
    ...(selfContained
      ? {
          targetId: isComment ? COMMENT_ID : MOMENT_ID,
          reportedUserId: AUTHOR,
          contextPath: isComment
            ? `voiceMoments/${MOMENT_ID}/comments/${COMMENT_ID}`
            : `voiceMoments/${MOMENT_ID}`,
        }
      : {}),
    ...reportOverrides,
  };
}

async function deleteTree(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function clear() {
  await Promise.all([
    deleteTree(db.doc(`voiceMoments/${MOMENT_ID}`)),
    db.doc(`reports/${ROOT_REPORT_ID}`).delete(),
    db.doc(`reports/${SECOND_ROOT_REPORT_ID}`).delete(),
    db.doc(`reports/${COMMENT_REPORT_ID}`).delete(),
    db.doc(`reports/${SECOND_COMMENT_REPORT_ID}`).delete(),
    db.doc(`reports/${MISSING_REPORT_ID}`).delete(),
    db.doc(`reports/${DELETING_REPORT_ID}`).delete(),
    db.doc(`users/${MODERATOR}`).delete(),
    db.doc(`momentCapacityLedgers/${AUTHOR}`).delete(),
    db.doc(
      `contentCleanupOutbox/${digest("moment-cleanup", MOMENT_ID)}`,
    ).delete(),
    db.doc(
      `contentCleanupOutbox/${digest(
        "comment-cleanup",
        MOMENT_ID,
        COMMENT_ID,
      )}`,
    ).delete(),
  ]);
  const audits = await db
    .collection("adminAuditLogs")
    .where("targetId", "in", [
      ROOT_REPORT_ID,
      SECOND_ROOT_REPORT_ID,
      COMMENT_REPORT_ID,
      SECOND_COMMENT_REPORT_ID,
      MISSING_REPORT_ID,
      DELETING_REPORT_ID,
    ])
    .get();
  await Promise.all(audits.docs.map((entry) => entry.ref.delete()));
}

beforeEach(async () => {
  await clear();
  await db.doc(`users/${MODERATOR}`).set({
    uid: MODERATOR,
    displayName: "Voice moderator",
    role: "moderator",
  });
});

after(clear);

test("removeAndResolve queues canonical root cleanup and replays idempotently", async () => {
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(publishedMoment()),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(
      voiceReport("voiceMoment", { selfContained: true }),
    ),
  ]);

  const first = await run(request(ROOT_REPORT_ID, "vmr-remove-root-01"));
  assert.equal(first.status, "resolved");
  assert.equal(first.contentRemoved, true);
  const root = (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data();
  assert.equal(root.isDeleted, true);
  assert.equal(root.isPublished, false);
  assert.equal(root.status, "deleting");
  const outboxId = digest("moment-cleanup", MOMENT_ID);
  const outbox = (await db.doc(`contentCleanupOutbox/${outboxId}`).get()).data();
  assert.equal(outbox.requestedBy, AUTHOR);
  assert.equal(outbox.requestedReason, "staffModeration");
  assert.deepEqual(outbox.objectPaths, [momentStoragePath(AUTHOR, MOMENT_ID)]);
  assert.equal(
    (await db.doc(`momentCapacityLedgers/${AUTHOR}`).get()).data().revision,
    1,
  );

  const replay = await run(request(ROOT_REPORT_ID, "vmr-remove-root-01"));
  assert.equal(replay.replayed, true);
  assert.equal(replay.contentRemoved, true);
  assert.equal(
    (await db.doc(`momentCapacityLedgers/${AUTHOR}`).get()).data().revision,
    1,
  );
  const audits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", ROOT_REPORT_ID)
    .get();
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].data().details.contentRemoved, true);
});

test("multiple root reports converge after the first removal", async () => {
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(publishedMoment()),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(voiceReport("voiceMoment")),
    db.doc(`reports/${SECOND_ROOT_REPORT_ID}`).set(
      voiceReport("voiceMoment", { selfContained: true }),
    ),
  ]);

  const [first, second] = await Promise.all([
    run(request(ROOT_REPORT_ID, "vmr-root-race-first")),
    run(request(SECOND_ROOT_REPORT_ID, "vmr-root-race-second")),
  ]);

  assert.equal(first.contentRemoved, true);
  assert.equal(second.status, "resolved");
  assert.equal(second.contentRemoved, true);
  assert.equal(
    (await db.doc(`momentCapacityLedgers/${AUTHOR}`).get()).data().revision,
    1,
    "the losing report must not touch capacity a second time",
  );
  assert.equal(
    (await db.doc(
      `contentCleanupOutbox/${digest("moment-cleanup", MOMENT_ID)}`,
    ).get()).exists,
    true,
  );
});

test("missing and author-deleting roots resolve as already removed", async () => {
  await db.doc(`reports/${MISSING_REPORT_ID}`).set(
    voiceReport("voiceMoment", { selfContained: true }),
  );
  const missing = await run(
    request(MISSING_REPORT_ID, "vmr-already-missing"),
  );
  assert.equal(missing.status, "resolved");
  assert.equal(missing.contentRemoved, true);
  const missingReport = (await db.doc(`reports/${MISSING_REPORT_ID}`).get())
    .data();
  assert.equal(missingReport.status, "resolved");
  assert.equal(missingReport.contentRemoved, true);
  const missingAudits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", MISSING_REPORT_ID)
    .get();
  assert.equal(missingAudits.size, 1);
  assert.equal(missingAudits.docs[0].data().details.contentRemoved, true);
  const missingReplay = await run(
    request(MISSING_REPORT_ID, "vmr-already-missing"),
  );
  assert.equal(missingReplay.replayed, true);
  assert.equal(missingReplay.contentRemoved, true);

  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(
      publishedMoment({
        isDeleted: true,
        isPublished: false,
        status: "deleting",
      }),
    ),
    db.doc(`reports/${DELETING_REPORT_ID}`).set(
      voiceReport("voiceMomentComment", { selfContained: true }),
    ),
  ]);
  const deleting = await run(
    request(DELETING_REPORT_ID, "vmr-author-delete-race"),
  );
  assert.equal(deleting.status, "resolved");
  assert.equal(deleting.contentRemoved, true);
  const deletingReport = (await db.doc(`reports/${DELETING_REPORT_ID}`).get())
    .data();
  assert.equal(deletingReport.status, "resolved");
  assert.equal(deletingReport.contentRemoved, true);
  const deletingAudits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", DELETING_REPORT_ID)
    .get();
  assert.equal(deletingAudits.size, 1);
  assert.equal(deletingAudits.docs[0].data().details.contentRemoved, true);
  assert.equal(
    (await db.doc(`momentCapacityLedgers/${AUTHOR}`).get()).exists,
    false,
    "an already-deleting root must not spend capacity again",
  );
});

test("an existing report can remove expired evidence without resurrecting it", async () => {
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(
      publishedMoment({
        isPublished: false,
        status: "expired",
        updatedAt: Timestamp.fromMillis(NOW_MS + 24 * 60 * 60_000),
      }),
    ),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(voiceReport("voiceMoment")),
  ]);
  const result = await run(request(ROOT_REPORT_ID, "vmr-expired-root-01"));
  assert.equal(result.contentRemoved, true);
  const root = (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data();
  assert.equal(root.status, "deleting");
  assert.equal(root.isPublished, false);
});

test("Build 19 legacy published Moments remain safely removable", async () => {
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set({
      schemaVersion: 1,
      authorId: AUTHOR,
      authorName: "Legacy voice author",
      authorPhotoUrl: null,
      caption: "reported legacy voice",
      durationSeconds: 8,
      audioUrl: "https://legacy.invalid/token",
      storagePath: momentStoragePath(AUTHOR, MOMENT_ID),
      replyToMomentId: null,
      isPublished: true,
      isDeleted: false,
      status: "published",
      likeCount: 0,
      commentCount: 0,
      createdAt: Timestamp.fromMillis(NOW_MS),
      updatedAt: Timestamp.fromMillis(NOW_MS),
      publishedAt: Timestamp.fromMillis(NOW_MS),
    }),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(voiceReport("voiceMoment")),
  ]);

  const result = await run(request(ROOT_REPORT_ID, "vmr-legacy-root-01"));
  assert.equal(result.contentRemoved, true);
  const root = (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data();
  assert.equal(root.status, "deleting");
  assert.equal(root.isDeleted, true);
  const outbox = (await db.doc(
    `contentCleanupOutbox/${digest("moment-cleanup", MOMENT_ID)}`,
  ).get()).data();
  assert.deepEqual(outbox.objectPaths, [momentStoragePath(AUTHOR, MOMENT_ID)]);
});

test("voice-comment moderation decrements once and queues its author-owned media", async () => {
  await db.doc(`voiceMoments/${MOMENT_ID}`).set(
    publishedMoment({ commentCount: 1 }),
  );
  await Promise.all([
    db.doc(
      `voiceMoments/${MOMENT_ID}/comments/${COMMENT_ID}`,
    ).set(voiceComment()),
    db.doc(`reports/${COMMENT_REPORT_ID}`).set(
      voiceReport("voiceMomentComment"),
    ),
  ]);

  const result = await run(
    request(COMMENT_REPORT_ID, "vmr-remove-comment-01"),
  );
  assert.equal(result.contentRemoved, true);
  assert.equal(
    (await db.doc(
      `voiceMoments/${MOMENT_ID}/comments/${COMMENT_ID}`,
    ).get()).exists,
    false,
  );
  assert.equal(
    (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data().commentCount,
    0,
  );
  const outboxId = digest("comment-cleanup", MOMENT_ID, COMMENT_ID);
  const outbox = (await db.doc(`contentCleanupOutbox/${outboxId}`).get()).data();
  assert.equal(outbox.requestedBy, AUTHOR);
  assert.deepEqual(outbox.objectPaths, [
    voiceReplyStoragePath(AUTHOR, MOMENT_ID, COMMENT_ID),
  ]);
});

test("multiple comment reports converge after the comment disappears", async () => {
  await db.doc(`voiceMoments/${MOMENT_ID}`).set(
    publishedMoment({ commentCount: 1 }),
  );
  await Promise.all([
    db.doc(
      `voiceMoments/${MOMENT_ID}/comments/${COMMENT_ID}`,
    ).set(voiceComment()),
    db.doc(`reports/${COMMENT_REPORT_ID}`).set(
      voiceReport("voiceMomentComment"),
    ),
    db.doc(`reports/${SECOND_COMMENT_REPORT_ID}`).set(
      voiceReport("voiceMomentComment", { selfContained: true }),
    ),
  ]);

  const [first, second] = await Promise.all([
    run(request(COMMENT_REPORT_ID, "vmr-comment-race-first")),
    run(request(SECOND_COMMENT_REPORT_ID, "vmr-comment-race-second")),
  ]);
  assert.equal(first.contentRemoved, true);
  assert.equal(second.status, "resolved");
  assert.equal(second.contentRemoved, true);
  assert.equal(
    (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data().commentCount,
    0,
  );
});

test("a self-contained report cannot misattribute a live target author", async () => {
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(publishedMoment()),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(
      voiceReport("voiceMoment", {
        selfContained: true,
        reportedUserId: "vmr-different-author",
      }),
    ),
  ]);

  await assert.rejects(
    run(request(ROOT_REPORT_ID, "vmr-author-mismatch")),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(
    (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data().status,
    "published",
  );
  assert.equal(
    (await db.doc(`reports/${ROOT_REPORT_ID}`).get()).data().status,
    "open",
  );
});

test("an already-deleting root still cannot be misattributed", async () => {
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(
      publishedMoment({
        isDeleted: true,
        isPublished: false,
        status: "deleting",
      }),
    ),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(
      voiceReport("voiceMoment", {
        selfContained: true,
        reportedUserId: "vmr-different-author",
      }),
    ),
  ]);

  await assert.rejects(
    run(request(ROOT_REPORT_ID, "vmr-deleting-author-mismatch")),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(
    (await db.doc(`reports/${ROOT_REPORT_ID}`).get()).data().status,
    "open",
  );
});

test("draft content and ambiguous Voice report references fail atomically", async () => {
  const draft = publishedMoment({
    isPublished: false,
    status: "uploading",
    audioUrl: null,
    mediaGeneration: null,
    mediaSize: null,
    mediaContentType: null,
    publishedAt: null,
  });
  delete draft.expiresAt;
  await Promise.all([
    db.doc(`voiceMoments/${MOMENT_ID}`).set(draft),
    db.doc(`reports/${ROOT_REPORT_ID}`).set(
      voiceReport("voiceMoment", { targetId: MOMENT_ID }),
    ),
  ]);

  await assert.rejects(
    run(request(ROOT_REPORT_ID, "vmr-reject-ambiguous")),
    (error) => error.code === "failed-precondition",
  );
  let report = (await db.doc(`reports/${ROOT_REPORT_ID}`).get()).data();
  assert.equal(report.status, "open");
  assert.equal(report.lastRequestId, undefined);

  await db.doc(`reports/${ROOT_REPORT_ID}`).set(
    voiceReport("voiceMoment"),
  );
  await assert.rejects(
    run(request(ROOT_REPORT_ID, "vmr-reject-draft-01")),
    (error) => error.code === "failed-precondition",
  );
  report = (await db.doc(`reports/${ROOT_REPORT_ID}`).get()).data();
  assert.equal(report.status, "open");
  assert.equal(report.lastRequestId, undefined);
  assert.equal(
    (await db.doc(`voiceMoments/${MOMENT_ID}`).get()).data().status,
    "uploading",
  );
});

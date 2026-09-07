const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { moderateReport } = require("../moderation/reports");
const { createReelService } = require("../reels/service");
const { digest } = require("../integrity/guards");

// ---------------------------------------------------------------------------
// STAFF REMOVAL of a reported Reel comment, through moderateReport.
//
// This is the half the Reel service cannot own: removal is an action on a
// REPORT, so it has to move the report's state machine, write the audit
// record and remove the content in one transaction, and it must be safe to
// replay. Everything here runs against the real Firestore emulator because
// the transaction semantics are the thing under test.
// ---------------------------------------------------------------------------

const db = getFirestore();
const run = moderateReport.run ?? moderateReport;
const MODERATOR = "rcm-moderator";
const REEL_AUTHOR = "rcm-reel-author";
const COMMENT_AUTHOR = "rcm-comment-author";
const REPORTER = "rcm-reporter";
const REEL_ID = "rcm-reel-01";
const COMMENT_ID = "0123456789abcdef0123456789abcdef01234567";
const SECOND_COMMENT_ID = "89abcdef0123456789abcdef0123456789abcdef";
const REPORT_ID = "rcm-report-01";
const SECOND_REPORT_ID = "rcm-report-02";
const GONE_REPORT_ID = "rcm-report-gone";
const TOMBSTONE_REPORT_ID = "rcm-report-tombstone";
const BROKEN_REPORT_ID = "rcm-report-broken";
const COUNTER_REPORT_ID = "rcm-report-counter";
const ALL_REPORT_IDS = [
  REPORT_ID,
  SECOND_REPORT_ID,
  GONE_REPORT_ID,
  TOMBSTONE_REPORT_ID,
  BROKEN_REPORT_ID,
  COUNTER_REPORT_ID,
];
const NOW_MS = 1_820_000_000_000;
const REPORTED_TEXT = "You are worthless and everyone knows it";

function request(reportId, requestId, overrides = {}) {
  return {
    auth: {
      uid: MODERATOR,
      token: {
        role: "moderator",
        email: "rcm-moderator@example.invalid",
        email_verified: true,
        auth_time: Math.floor(Date.now() / 1000),
      },
    },
    data: {
      reportId,
      requestId,
      action: "removeAndResolve",
      resolution: "contentRemoved",
      moderatorNote: "canonical Reel comment moderation test",
      ...overrides,
    },
  };
}

function composition() {
  return {
    caption: "A real Reel",
    crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
    filter: "original",
    trimStartMs: 0,
    trimEndMs: 0,
    textOverlays: [],
    linkOverlays: [],
    originalAudioVolume: 0,
    backingAudioVolume: 0,
    audioTrimStartMs: 0,
    audioRightsAttested: false,
    audioAttribution: "",
  };
}

function publishedReel(overrides = {}) {
  return {
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId: REEL_AUTHOR,
    authorName: "Reel author",
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "123",
      durationMs: 0,
      storagePath: `reels/${REEL_AUTHOR}/${REEL_ID}/media.jpg`,
    },
    backingAudio: null,
    composition: composition(),
    sortKey: `${String(NOW_MS).padStart(13, "0")}_${REEL_ID}`,
    commentCount: 1,
    likeCount: 0,
    publishedAt: Timestamp.fromMillis(NOW_MS),
    updatedAt: Timestamp.fromMillis(NOW_MS),
    ...overrides,
  };
}

/// The real Reel service, over the real emulator. The two removal
/// authorities have to compose against ONE Firestore, and an in-memory
/// double cannot prove that.
const reelService = createReelService({
  db,
  FieldPath,
  Timestamp,
  storage: {
    getMetadata: async () => ({}),
    readHeader: async () => Buffer.alloc(0),
    revokeDownloadTokens: async () => {},
    getSignedReadUrl: async () => "",
    deleteObject: async () => {},
  },
});

function authorRemoval(commentId, requestId) {
  return {
    auth: { uid: REEL_AUTHOR, token: { email_verified: true } },
    data: { reelId: REEL_ID, commentId, requestId },
  };
}

/// The rate-limit and operation-ledger documents an author removal leaves
/// behind, so this file cleans up after itself in a shared emulator.
function authorRemovalArtifacts(requestIds) {
  return [
    db.doc(
      `privateRateLimits/${digest("rate", "reel.commentRemove", REEL_AUTHOR)}`,
    ),
    ...requestIds.map((requestId) => db.doc(
      `integrityOperationLedgers/${digest(
        "operation",
        "reel.comment.remove",
        REEL_AUTHOR,
        requestId,
      )}`,
    )),
  ];
}

function reelComment(overrides = {}) {
  return {
    schemaVersion: 1,
    type: "text",
    reelId: REEL_ID,
    authorId: COMMENT_AUTHOR,
    authorName: "Comment author",
    text: REPORTED_TEXT,
    durationSeconds: null,
    createdAt: Timestamp.fromMillis(NOW_MS),
    ...overrides,
  };
}

/// Byte-for-byte the document createReelCommentReport writes.
function reelCommentReport(overrides = {}) {
  const commentId = overrides.commentId ?? COMMENT_ID;
  return {
    schemaVersion: 2,
    reporterId: REPORTER,
    targetType: "reelComment",
    targetId: commentId,
    reportedUserId: COMMENT_AUTHOR,
    contextPath: `reels/${REEL_ID}/comments/${commentId}`,
    reelId: REEL_ID,
    commentId,
    reelAuthorId: REEL_AUTHOR,
    targetTextSnapshot: REPORTED_TEXT,
    note: "",
    reason: "harassment",
    status: "open",
    createdAt: Timestamp.fromMillis(NOW_MS),
    ...overrides,
  };
}

async function deleteTree(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

const AUTHOR_REMOVAL_REQUEST_IDS = [
  "rcm-author-removes-01",
  "rcm-author-second-01",
];

async function clear() {
  await Promise.all([
    deleteTree(db.doc(`reels/${REEL_ID}`)),
    ...ALL_REPORT_IDS.map((id) => db.doc(`reports/${id}`).delete()),
    db.doc(`users/${MODERATOR}`).delete(),
    db.doc(`users/${REEL_AUTHOR}`).delete(),
    ...authorRemovalArtifacts(AUTHOR_REMOVAL_REQUEST_IDS)
      .map((reference) => reference.delete()),
  ]);
  const audits = await db
    .collection("adminAuditLogs")
    .where("targetId", "in", ALL_REPORT_IDS)
    .get();
  await Promise.all(audits.docs.map((entry) => entry.ref.delete()));
}

beforeEach(async () => {
  await clear();
  await Promise.all([
    db.doc(`users/${MODERATOR}`).set({
      uid: MODERATOR,
      displayName: "Reel comment moderator",
      role: "moderator",
    }),
    db.doc(`users/${REEL_AUTHOR}`).set({
      uid: REEL_AUTHOR,
      displayName: "Reel author",
    }),
  ]);
});

after(clear);

test("removeAndResolve deletes the comment, decrements once and replays " +
  "idempotently", async () => {
  await Promise.all([
    db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 2 })),
    db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
    db.doc(`reels/${REEL_ID}/comments/${SECOND_COMMENT_ID}`).set(
      reelComment({ text: "an untouched neighbour" }),
    ),
    db.doc(`reports/${REPORT_ID}`).set(reelCommentReport()),
  ]);

  const first = await run(request(REPORT_ID, "rcm-remove-0001"));
  assert.equal(first.status, "resolved");
  assert.equal(first.contentRemoved, true);
  assert.equal(
    (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
    false,
  );
  // The neighbouring comment is untouched: removal is scoped to the target.
  assert.equal(
    (await db.doc(`reels/${REEL_ID}/comments/${SECOND_COMMENT_ID}`).get())
      .exists,
    true,
  );
  assert.equal((await db.doc(`reels/${REEL_ID}`).get()).data().commentCount, 1);

  // The reporter's evidence is never rewritten by triage — including the
  // text snapshot, which is what an appeal is judged against.
  const stored = (await db.doc(`reports/${REPORT_ID}`).get()).data();
  assert.equal(stored.status, "resolved");
  assert.equal(stored.contentRemoved, true);
  assert.equal(stored.targetTextSnapshot, REPORTED_TEXT);
  assert.equal(stored.reporterId, REPORTER);
  assert.equal(stored.reportedUserId, COMMENT_AUTHOR);
  assert.equal(stored.resolvedBy, MODERATOR);

  const replay = await run(request(REPORT_ID, "rcm-remove-0001"));
  assert.equal(replay.replayed, true);
  assert.equal(replay.contentRemoved, true);
  assert.equal(
    (await db.doc(`reels/${REEL_ID}`).get()).data().commentCount,
    1,
    "a replay must not decrement a second time",
  );

  const audits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", REPORT_ID)
    .get();
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].data().actorId, MODERATOR);
  assert.equal(audits.docs[0].data().action, "report_removeAndResolve");
  assert.equal(audits.docs[0].data().details.contentRemoved, true);
  // This moderator really did the removal, and the trail says so.
  assert.equal(audits.docs[0].data().details.contentAlreadyRemoved, false);
});

test("a comment the Reel's author already removed converges instead of " +
  "stranding the report", async () => {
  // The author's own removal path and staff removal race by design. The
  // report proves the comment existed when it was filed; its absence now is
  // a successful outcome, not a reason to leave a safety report open forever.
  await Promise.all([
    db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 0 })),
    db.doc(`reports/${GONE_REPORT_ID}`).set(reelCommentReport()),
  ]);

  const result = await run(request(GONE_REPORT_ID, "rcm-converge-0001"));
  assert.equal(result.status, "resolved");
  assert.equal(result.contentRemoved, true);
  assert.equal(
    (await db.doc(`reels/${REEL_ID}`).get()).data().commentCount,
    0,
    "an already-removed comment must not decrement anything",
  );
  // AND the audit trail does not let this moderator's record claim a removal
  // somebody else performed. `contentRemoved` is the OUTCOME — the words are
  // gone — and `contentAlreadyRemoved` is WHO made them so. Telling the two
  // apart is what turns "the author cleared the comment before staff reached
  // it" into a countable pattern instead of a guess.
  const audits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", GONE_REPORT_ID)
    .get();
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].data().details.contentRemoved, true);
  assert.equal(audits.docs[0].data().details.contentAlreadyRemoved, true);
});

test("two reports on one comment decrement the counter exactly once",
  async () => {
    await Promise.all([
      db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 })),
      db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
      db.doc(`reports/${REPORT_ID}`).set(reelCommentReport()),
      db.doc(`reports/${SECOND_REPORT_ID}`).set(
        reelCommentReport({ reporterId: "rcm-reporter-two" }),
      ),
    ]);

    const first = await run(request(REPORT_ID, "rcm-race-first"));
    const second = await run(request(SECOND_REPORT_ID, "rcm-race-second"));

    assert.equal(first.contentRemoved, true);
    assert.equal(second.status, "resolved");
    assert.equal(second.contentRemoved, true);
    assert.equal(
      (await db.doc(`reels/${REEL_ID}`).get()).data().commentCount,
      0,
    );
  });

test("an orphan comment under a deletion tombstone is still removed, and " +
  "the tombstone is not written", async () => {
  const tombstone = {
    schemaVersion: 1,
    status: "deleted",
    authorId: REEL_AUTHOR,
    moderationStatusAtDeletion: "visible",
    moderationEvidence: {
      evidenceVersion: 1,
      publishedAt: Timestamp.fromMillis(NOW_MS),
      metadataFingerprint: "a".repeat(64),
    },
    deletedAt: Timestamp.fromMillis(NOW_MS),
    updatedAt: Timestamp.fromMillis(NOW_MS),
  };
  await Promise.all([
    db.doc(`reels/${REEL_ID}`).set(tombstone),
    db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
    db.doc(`reports/${TOMBSTONE_REPORT_ID}`).set(reelCommentReport()),
  ]);

  const result = await run(request(TOMBSTONE_REPORT_ID, "rcm-tombstone-01"));
  assert.equal(result.contentRemoved, true);
  assert.equal(
    (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
    false,
    "the reported words must not wait on the cleanup worker",
  );
  // A deletion tombstone carries an exact key set with no commentCount.
  // Writing one onto it would corrupt the evidence record.
  const root = (await db.doc(`reels/${REEL_ID}`).get()).data();
  assert.deepEqual(Object.keys(root).sort(), Object.keys(tombstone).sort());
  assert.equal(root.commentCount, undefined);
});

test("a Reel that holds a comment while claiming zero fails closed",
  async () => {
    await Promise.all([
      db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 0 })),
      db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
      db.doc(`reports/${COUNTER_REPORT_ID}`).set(reelCommentReport()),
    ]);

    await assert.rejects(
      run(request(COUNTER_REPORT_ID, "rcm-counter-0001")),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        return true;
      },
    );
    // Nothing half-applied: no negative counter, and the report stays open.
    assert.equal(
      (await db.doc(`reels/${REEL_ID}`).get()).data().commentCount,
      0,
    );
    assert.equal(
      (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
      true,
    );
    const stored = (await db.doc(`reports/${COUNTER_REPORT_ID}`).get()).data();
    assert.equal(stored.status, "open");
  });

test("a report whose target identity is incomplete cannot remove anything",
  async () => {
    for (const [label, overrides] of [
      ["no text snapshot", { targetTextSnapshot: undefined }],
      ["mismatched contextPath", { contextPath: `reels/${REEL_ID}/comments/x` }],
      ["targetId that is not the commentId", { targetId: REEL_ID }],
      ["no reelId", { reelId: undefined }],
      ["no reelAuthorId", { reelAuthorId: undefined }],
      ["v1 schema", { schemaVersion: 1 }],
    ]) {
      await db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 }));
      await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment());
      const report = reelCommentReport();
      for (const [key, value] of Object.entries(overrides)) {
        if (value === undefined) delete report[key];
        else report[key] = value;
      }
      await db.doc(`reports/${BROKEN_REPORT_ID}`).set(report);

      await assert.rejects(
        run(request(BROKEN_REPORT_ID, `rcm-broken-${passcode(label)}`)),
        (error) => {
          assert.equal(
            error.code,
            "failed-precondition",
            `${label} should be refused as invalid evidence`,
          );
          return true;
        },
      );
      assert.equal(
        (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
        true,
        `${label} must not remove the comment`,
      );
      await db.doc(`reports/${BROKEN_REPORT_ID}`).delete();
    }
  });

test("a report naming the wrong author cannot be used to remove a comment",
  async () => {
    await Promise.all([
      db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 })),
      db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
      db.doc(`reports/${BROKEN_REPORT_ID}`).set(
        reelCommentReport({ reportedUserId: "rcm-someone-else" }),
      ),
    ]);

    await assert.rejects(
      run(request(BROKEN_REPORT_ID, "rcm-wrong-author-01")),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        return true;
      },
    );
    assert.equal(
      (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
      true,
    );
  });

test("resolving without removing leaves the comment in place", async () => {
  await Promise.all([
    db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 })),
    db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
    db.doc(`reports/${REPORT_ID}`).set(reelCommentReport()),
  ]);

  const result = await run(
    request(REPORT_ID, "rcm-not-a-violation", {
      action: "resolve",
      resolution: "notAViolation",
    }),
  );
  assert.equal(result.status, "resolved");
  assert.equal(result.contentRemoved, false);
  assert.equal(
    (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
    true,
  );
  assert.equal((await db.doc(`reels/${REEL_ID}`).get()).data().commentCount, 1);
});

test("a caller who is not active staff removes nothing", async () => {
  await Promise.all([
    db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 })),
    db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
    db.doc(`reports/${REPORT_ID}`).set(reelCommentReport()),
  ]);

  // No role claim at all; a claim with no server-written mirror; and the
  // Reel's own author, who has authority over the thread but none over a
  // report.
  const callers = [
    { uid: REPORTER, token: { email_verified: true, auth_time: nowSeconds() } },
    {
      uid: "rcm-forged-mod",
      token: {
        role: "moderator",
        email_verified: true,
        auth_time: nowSeconds(),
      },
    },
    {
      uid: REEL_AUTHOR,
      token: { email_verified: true, auth_time: nowSeconds() },
    },
  ];
  for (const auth of callers) {
    await assert.rejects(
      run({ auth, data: request(REPORT_ID, "rcm-not-staff-01").data }),
      (error) => {
        assert.equal(error.code, "permission-denied");
        return true;
      },
    );
  }
  assert.equal(
    (await db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).get()).exists,
    true,
  );
  assert.equal(
    (await db.doc(`reports/${REPORT_ID}`).get()).data().status,
    "open",
  );
});

// ---------------------------------------------------------------------------
// The two removal authorities, composed against one Firestore.
//
// A Reel author and a moderator can act on the same comment, in either order,
// with no coordination between them. Between the two of them the counter must
// move exactly once and neither may be left holding a broken state — that is
// the whole point of building the author path as a sibling of staff removal
// rather than as a shortcut around it.
// ---------------------------------------------------------------------------

test("the author removing first leaves the moderator a converged report",
  async () => {
    await Promise.all([
      db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 })),
      db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
      db.doc(`reports/${REPORT_ID}`).set(reelCommentReport()),
    ]);

    const removed = await reelService.removeReelComment(
      authorRemoval(COMMENT_ID, AUTHOR_REMOVAL_REQUEST_IDS[0]),
    );
    assert.deepEqual(removed, {
      reelId: REEL_ID,
      commentId: COMMENT_ID,
      removed: true,
      commentCount: 0,
      removedAuthorId: COMMENT_AUTHOR,
    });
    assert.equal((await db.doc(`reels/${REEL_ID}`).get()).data().commentCount, 0);

    const moderated = await run(request(REPORT_ID, "rcm-after-author-01"));
    assert.equal(moderated.status, "resolved");
    assert.equal(moderated.contentRemoved, true);
    const trail = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", REPORT_ID)
      .get();
    assert.equal(
      trail.docs[0].data().details.contentAlreadyRemoved,
      true,
      "the trail must show the author got there first",
    );
    assert.equal(
      (await db.doc(`reels/${REEL_ID}`).get()).data().commentCount,
      0,
      "the counter moved once between the two authorities, not twice",
    );
    // The words survive in the report even though the author destroyed the
    // document — which is what an appeal has to be judged against.
    assert.equal(
      (await db.doc(`reports/${REPORT_ID}`).get()).data().targetTextSnapshot,
      REPORTED_TEXT,
    );
  });

test("the moderator removing first leaves the author nothing to remove",
  async () => {
    await Promise.all([
      db.doc(`reels/${REEL_ID}`).set(publishedReel({ commentCount: 1 })),
      db.doc(`reels/${REEL_ID}/comments/${COMMENT_ID}`).set(reelComment()),
      db.doc(`reports/${REPORT_ID}`).set(reelCommentReport()),
    ]);

    const moderated = await run(request(REPORT_ID, "rcm-before-author-01"));
    assert.equal(moderated.contentRemoved, true);
    assert.equal((await db.doc(`reels/${REEL_ID}`).get()).data().commentCount, 0);

    await assert.rejects(
      reelService.removeReelComment(
        authorRemoval(COMMENT_ID, AUTHOR_REMOVAL_REQUEST_IDS[1]),
      ),
      (error) => {
        assert.equal(error.code, "not-found");
        return true;
      },
    );
    assert.equal(
      (await db.doc(`reels/${REEL_ID}`).get()).data().commentCount,
      0,
      "a refused author removal must not decrement below zero",
    );
  });

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function passcode(label) {
  return label.replace(/[^a-z]/giu, "").slice(0, 20).padEnd(8, "x");
}

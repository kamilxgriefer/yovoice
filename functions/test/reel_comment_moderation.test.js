const assert = require("node:assert/strict");
const { test } = require("node:test");

const { DEFAULT_LIMITS, createReelService } = require("../reels/service");
const { digest } = require("../integrity/guards");
const { MAX_REEL_COMMENT_LENGTH } = require("../reels/engagement");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

// ---------------------------------------------------------------------------
// Reel COMMENT moderation: the reporter's path into the shared `reports`
// queue, and the Reel author's authority over their own thread.
//
// Staff removal is NOT exercised here — it is an action on a report, lives in
// functions/moderation/reports.js and needs the real Firestore + Auth
// emulators. See moderate_reel_comment_report.test.js for that half.
// ---------------------------------------------------------------------------

const NOW_MS = 1_778_000_000_000;
const AUTHOR = "reel-author-1";
const COMMENTER = "commenter-1";
const REPORTER = "reporter-1";
const OTHER_REPORTER = "reporter-2";
const REEL_ID = "reel_1";

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

function publishedReel({
  id = REEL_ID,
  authorId = AUTHOR,
  moderationStatus = "visible",
  status = "published",
} = {}) {
  return {
    schemaVersion: 1,
    status,
    moderationStatus,
    authorId,
    authorName: `Creator ${authorId}`,
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "123",
      durationMs: 0,
      storagePath: `reels/${authorId}/${id}/media.jpg`,
    },
    backingAudio: null,
    composition: composition(),
    sortKey: `${String(NOW_MS).padStart(13, "0")}_${id}`,
    publishedAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  };
}

function publicProfile(uid, displayName) {
  return {
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: null,
    displayName,
    displayNameSearch: displayName.toLowerCase(),
    followerCount: 0,
    followingCount: 0,
    friendCount: 0,
    learningLanguages: [],
    nativeLanguage: null,
    photoUrl: null,
    premiumIdentity: null,
    schemaVersion: 1,
    spokenLanguages: [],
    statusMessage: "",
    uid,
    updatedAt: new Date(NOW_MS),
    username: uid,
    usernameSearch: uid,
    website: null,
  };
}

function fixture({
  limits = DEFAULT_LIMITS,
  clock = () => NOW_MS,
  reel = {},
  availability = { hours: "permanent" },
} = {}) {
  const db = new InMemoryFirestore();
  for (const uid of [AUTHOR, COMMENTER, REPORTER, OTHER_REPORTER]) {
    db.seed(`users/${uid}`, { uid, displayName: `Name ${uid}` });
    db.seed(`publicProfiles/${uid}`, publicProfile(uid, `Name ${uid}`));
  }
  const reelId = reel.id ?? REEL_ID;
  db.seed(`reels/${reelId}`, publishedReel(reel));
  if (availability !== null) {
    db.seed(`reelAvailability/${reelId}`, {
      schemaVersion: 2,
      status: "published",
      ownerId: reel.authorId ?? AUTHOR,
      reelId,
      availabilityHours: availability.hours,
      createdAt: new Date(NOW_MS),
      publishedAt: new Date(NOW_MS),
      ...(availability.hours === "permanent"
        ? {}
        : { expiresAt: new Date(NOW_MS + availability.hours * 3_600_000) }),
      updatedAt: new Date(NOW_MS),
    });
  }
  const storage = {
    getMetadata: async () => ({
      generation: "123",
      contentType: "image/jpeg",
      size: 1024,
      metadata: { ownerId: reel.authorId ?? AUTHOR, reelId, assetKind: "media" },
    }),
    readHeader: async () => Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
    revokeDownloadTokens: async () => {},
    getSignedReadUrl: async () => "https://storage.googleapis.com/bucket/file",
    deleteObject: async () => {},
  };
  return {
    db,
    service: createReelService({
      db,
      FieldPath: { documentId: () => "__name__" },
      Timestamp: { fromMillis: (value) => new Date(value) },
      storage,
      clock,
      limits,
    }),
  };
}

function actor(uid, { verified = true } = {}) {
  return { uid, token: { email_verified: verified } };
}

function commentRequest(overrides = {}) {
  const { uid = COMMENTER, ...data } = overrides;
  return {
    auth: actor(uid),
    data: {
      reelId: REEL_ID,
      text: "You are worthless and everyone knows it",
      requestId: "comment-request-0001",
      ...data,
    },
  };
}

function reportRequest(overrides = {}) {
  const { uid = REPORTER, ...data } = overrides;
  return {
    auth: actor(uid, { verified: false }),
    data: {
      reelId: REEL_ID,
      commentId: "placeholder",
      reason: "harassment",
      requestId: "report-request-0001",
      ...data,
    },
  };
}

function removeRequest(overrides = {}) {
  const { uid = AUTHOR, ...data } = overrides;
  return {
    auth: actor(uid, { verified: false }),
    data: {
      reelId: REEL_ID,
      commentId: "placeholder",
      requestId: "remove-request-0001",
      ...data,
    },
  };
}

async function rejects(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

function rateState(db, scope) {
  return db.paths("privateRateLimits/")
    .map((path) => db.data(path))
    .find((value) => value.scope === scope);
}

/// Posts one comment and returns its server-derived id.
async function seedComment(service, overrides = {}) {
  const created = await service.createReelComment(commentRequest(overrides));
  return created.commentId;
}

// ---------------------------------------------------------------------------
// createReelCommentReport
// ---------------------------------------------------------------------------

test("a reported Reel comment reaches the queue with everything a " +
  "moderator needs to act", async () => {
  const { db, service } = fixture();
  const commentId = await seedComment(service);

  const filed = await service.createReelCommentReport(
    reportRequest({ commentId, note: "This is the third one today" }),
  );
  assert.equal(filed.created, true);
  // Its own report-id namespace, so reporting a Reel and reporting a comment
  // on that Reel can never collide on one document.
  assert.equal(
    filed.reportId,
    digest("reel-comment-report", REPORTER, REEL_ID, commentId).slice(0, 40),
  );
  assert.notEqual(
    filed.reportId,
    digest("reel-report", REPORTER, REEL_ID).slice(0, 40),
  );

  const report = db.data(`reports/${filed.reportId}`);
  assert.deepEqual(Object.keys(report).sort(), [
    "commentId",
    "contextPath",
    "createdAt",
    "note",
    "reason",
    "reelAuthorId",
    "reelId",
    "reporterId",
    "reportedUserId",
    "schemaVersion",
    "status",
    "targetId",
    "targetTextSnapshot",
    "targetType",
  ].sort());
  assert.equal(report.schemaVersion, 2);
  assert.equal(report.targetType, "reelComment");
  assert.equal(report.targetId, commentId);
  assert.equal(report.reelId, REEL_ID);
  assert.equal(report.commentId, commentId);
  assert.equal(report.reporterId, REPORTER);
  assert.equal(report.reportedUserId, COMMENTER);
  assert.equal(report.reelAuthorId, AUTHOR);
  assert.equal(report.contextPath, `reels/${REEL_ID}/comments/${commentId}`);
  assert.equal(report.reason, "harassment");
  assert.equal(report.note, "This is the third one today");
  // The words themselves. reels/{id}/comments/{id} is unreadable by every
  // client including staff, so without this a moderator decides a harassment
  // report having never seen the harassment.
  assert.equal(
    report.targetTextSnapshot,
    "You are worthless and everyone knows it",
  );
  assert.ok(report.targetTextSnapshot.length <= MAX_REEL_COMMENT_LENGTH);
  // No workflow field a reporter could pre-set.
  assert.equal(report.status, "open");
  assert.equal(report.assignedTo, undefined);
  assert.equal(report.resolution, undefined);
});

test("replaying one report requestId returns the original receipt and " +
  "spends nothing more", async () => {
  const { db, service } = fixture();
  const commentId = await seedComment(service);

  const first = await service.createReelCommentReport(
    reportRequest({ commentId }),
  );
  const replay = await service.createReelCommentReport(
    reportRequest({ commentId }),
  );
  assert.deepEqual(replay, first);
  assert.equal(
    db.paths("reports/").length,
    1,
    "a replay must not create a second queue entry",
  );
  assert.equal(rateState(db, "reel.report").count, 1);
});

test("a fresh requestId cannot manufacture duplicate queue entries for one " +
  "target, and is still charged", async () => {
  const { db, service } = fixture();
  const commentId = await seedComment(service);

  await service.createReelCommentReport(reportRequest({ commentId }));
  const second = await service.createReelCommentReport(
    reportRequest({ commentId, requestId: "report-request-0002" }),
  );
  assert.equal(second.created, false);
  assert.equal(db.paths("reports/").length, 1);
  // Deduplicated, but NOT free: only an exact ledger replay is free, so a
  // reporter cannot use the dedupe path as an unmetered endpoint.
  assert.equal(rateState(db, "reel.report").count, 2);
});

test("reusing one requestId under different input is refused", async () => {
  const { service } = fixture();
  const commentId = await seedComment(service);
  await service.createReelCommentReport(reportRequest({ commentId }));
  await rejects(
    service.createReelCommentReport(
      reportRequest({ commentId, reason: "spam" }),
    ),
    "already-exists",
  );
});

test("two reporters produce two independent reports for one comment",
  async () => {
    const { db, service } = fixture();
    const commentId = await seedComment(service);
    const first = await service.createReelCommentReport(
      reportRequest({ commentId }),
    );
    const second = await service.createReelCommentReport(
      reportRequest({ commentId, uid: OTHER_REPORTER }),
    );
    assert.notEqual(first.reportId, second.reportId);
    assert.equal(second.created, true);
    assert.equal(db.paths("reports/").length, 2);
  });

test("you cannot report your own comment", async () => {
  const { service } = fixture();
  const commentId = await seedComment(service);
  await rejects(
    service.createReelCommentReport(reportRequest({ commentId, uid: COMMENTER })),
    "failed-precondition",
  );
});

test("every 'nothing here to report' state answers with ONE envelope",
  async () => {
    // A missing comment, a deletion tombstone and a purged-expiry tombstone
    // must be indistinguishable: a uniform refusal keeps this off the list of
    // endpoints that can be used as an existence oracle.
    const missing = fixture();
    const commentId = await seedComment(missing.service);
    await rejects(
      missing.service.createReelCommentReport(
        reportRequest({ commentId: "0123456789abcdef0123456789abcdef01234567" }),
      ),
      "not-found",
    );

    const deleted = fixture();
    const deletedComment = await seedComment(deleted.service);
    deleted.db.seed(`reels/${REEL_ID}`, {
      schemaVersion: 1,
      status: "deleted",
      authorId: AUTHOR,
      moderationStatusAtDeletion: "visible",
      moderationEvidence: {
        evidenceVersion: 1,
        publishedAt: new Date(NOW_MS),
        metadataFingerprint: "a".repeat(64),
      },
      deletedAt: new Date(NOW_MS),
      updatedAt: new Date(NOW_MS),
    });
    await rejects(
      deleted.service.createReelCommentReport(
        reportRequest({ commentId: deletedComment }),
      ),
      "not-found",
    );

    const purged = fixture();
    const purgedComment = await seedComment(purged.service);
    purged.db.seed(`reels/${REEL_ID}`, {
      schemaVersion: 1,
      status: "expired",
      authorId: AUTHOR,
      moderationStatusAtExpiry: "visible",
      moderationEvidence: {
        evidenceVersion: 1,
        publishedAt: new Date(NOW_MS),
        expiredAt: new Date(NOW_MS),
        availabilityHours: 24,
        metadataFingerprint: "b".repeat(64),
      },
      expiredAt: new Date(NOW_MS),
      purgedAt: new Date(NOW_MS),
      updatedAt: new Date(NOW_MS),
    });
    await rejects(
      purged.service.createReelCommentReport(
        reportRequest({ commentId: purgedComment }),
      ),
      "not-found",
    );

    assert.equal(missing.db.paths("reports/").length, 0);
    assert.equal(deleted.db.paths("reports/").length, 0);
    assert.equal(purged.db.paths("reports/").length, 0);
  });

test("a REFUSED report costs the same as a filed one, so probing is metered",
  async () => {
    // The refusal envelope is uniform, which stops it from saying WHICH half
    // of a (reelId, commentId) pair is real. That only matters if the probe
    // is also bounded — an unmetered endpoint can be polled until the shape
    // of the silence gives the answer away. createReelReport charges after
    // its existence checks and is therefore free to probe; this one is not.
    const { db, service } = fixture({
      limits: {
        ...DEFAULT_LIMITS,
        report: { maxEvents: 3, windowMs: 600_000 },
      },
    });
    for (let attempt = 0; attempt < 3; attempt += 1) {
      await rejects(
        service.createReelCommentReport(
          reportRequest({
            commentId: "0123456789abcdef0123456789abcdef0123456f",
            requestId: `probe-request-000${attempt}`,
          }),
        ),
        "not-found",
      );
    }
    assert.equal(rateState(db, "reel.report").count, 3);
    await rejects(
      service.createReelCommentReport(
        reportRequest({
          commentId: "0123456789abcdef0123456789abcdef0123456f",
          requestId: "probe-request-0009",
        }),
      ),
      "resource-exhausted",
    );
  });

test("a hidden or expired Reel does not freeze its comments out of " +
  "reporting", async () => {
  // Moderation hiding the Reel, and availability expiring it, both retire it
  // from the feed. Neither erases the words underneath, and somebody who saw
  // them must still be able to say so.
  const hidden = fixture();
  const hiddenComment = await seedComment(hidden.service);
  hidden.db.seed(`reels/${REEL_ID}`, {
    ...publishedReel(),
    moderationStatus: "hidden",
    commentCount: 1,
  });
  const hiddenReport = await hidden.service.createReelCommentReport(
    reportRequest({ commentId: hiddenComment }),
  );
  assert.equal(hiddenReport.created, true);

  const expired = fixture({ availability: { hours: 24 } });
  const expiredComment = await seedComment(expired.service);
  expired.db.seed(`reels/${REEL_ID}`, {
    ...publishedReel({ status: "expired" }),
    commentCount: 1,
  });
  const expiredReport = await expired.service.createReelCommentReport(
    reportRequest({ commentId: expiredComment }),
  );
  assert.equal(expiredReport.created, true);
});

test("one account gets one reporting allowance across Reels and Reel " +
  "comments", async () => {
  const { db, service } = fixture({
    limits: {
      ...DEFAULT_LIMITS,
      report: { maxEvents: 2, windowMs: 600_000 },
    },
  });
  const commentId = await seedComment(service);

  await service.createReelReport({
    auth: actor(REPORTER, { verified: false }),
    data: { reelId: REEL_ID, reason: "spam", requestId: "reel-report-000001" },
  });
  await service.createReelCommentReport(reportRequest({ commentId }));
  assert.equal(rateState(db, "reel.report").count, 2);
  await rejects(
    service.createReelCommentReport(
      reportRequest({ commentId, requestId: "report-request-0009" }),
    ),
    "resource-exhausted",
  );
});

test("unknown or missing report fields are refused before anything is read",
  async () => {
    const { service } = fixture();
    const commentId = await seedComment(service);
    await rejects(
      service.createReelCommentReport(
        reportRequest({ commentId, targetType: "reelComment" }),
      ),
      "invalid-argument",
    );
    await rejects(
      service.createReelCommentReport(reportRequest({ commentId, reason: "rude" })),
      "invalid-argument",
    );
    await rejects(
      service.createReelCommentReport(
        reportRequest({ commentId, requestId: "short" }),
      ),
      "invalid-argument",
    );
    // reporterId is never an input: it is the callable's auth uid.
    await rejects(
      service.createReelCommentReport(
        reportRequest({ commentId, reporterId: OTHER_REPORTER }),
      ),
      "invalid-argument",
    );
  });

// ---------------------------------------------------------------------------
// removeReelComment — the Reel author's own authority
// ---------------------------------------------------------------------------

test("the Reel's author removes another person's comment, exactly once",
  async () => {
    const { db, service } = fixture();
    const commentId = await seedComment(service);
    assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);

    const removed = await service.removeReelComment(
      removeRequest({ commentId }),
    );
    assert.deepEqual(removed, {
      reelId: REEL_ID,
      commentId,
      removed: true,
      commentCount: 0,
      removedAuthorId: COMMENTER,
    });
    assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 0);
    assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 0);

    // The one durable trace that an author removed somebody else's words.
    const ledger = db.paths("integrityOperationLedgers/")
      .map((path) => db.data(path))
      .find((value) => value.kind === "reel.comment.remove");
    assert.equal(ledger.ownerId, AUTHOR);
    assert.equal(ledger.result.removedAuthorId, COMMENTER);
    assert.equal(ledger.result.commentId, commentId);
  });

test("replaying an author removal neither deletes twice nor decrements twice",
  async () => {
    const { db, service } = fixture();
    const first = await seedComment(service);
    const second = await seedComment(
      service,
      { requestId: "comment-request-0002" },
    );
    assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 2);

    const removed = await service.removeReelComment(
      removeRequest({ commentId: first }),
    );
    const replay = await service.removeReelComment(
      removeRequest({ commentId: first }),
    );
    assert.deepEqual(replay, removed);
    assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);
    assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
    assert.ok(db.data(`reels/${REEL_ID}/comments/${second}`));
    // A replay is free.
    assert.equal(rateState(db, "reel.commentRemove").count, 1);
  });

test("a new requestId against an already-removed comment is absence, not a " +
  "second decrement", async () => {
  const { db, service } = fixture();
  const commentId = await seedComment(service);
  await service.removeReelComment(removeRequest({ commentId }));
  await rejects(
    service.removeReelComment(
      removeRequest({ commentId, requestId: "remove-request-0002" }),
    ),
    "not-found",
  );
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 0);
});

test("nobody but the Reel's author holds this authority", async () => {
  const { db, service } = fixture();
  const commentId = await seedComment(service);

  // A stranger.
  await rejects(
    service.removeReelComment(removeRequest({ commentId, uid: REPORTER })),
    "permission-denied",
  );
  // THE COMMENT'S OWN AUTHOR, deliberately. Removing your own words is
  // deleteReelComment's job; this endpoint is about owning the Reel, and
  // keeping the two separate is what makes "the author cleared somebody
  // else's comment" a distinguishable fact afterwards.
  await rejects(
    service.removeReelComment(
      removeRequest({ commentId, uid: COMMENTER, requestId: "remove-req-0003" }),
    ),
    "permission-denied",
  );
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);
  assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
});

test("the Reel's author may also clear their own comment from their own Reel",
  async () => {
    const { db, service } = fixture();
    const commentId = await seedComment(service, { uid: AUTHOR });
    const removed = await service.removeReelComment(
      removeRequest({ commentId }),
    );
    assert.equal(removed.removed, true);
    assert.equal(removed.removedAuthorId, AUTHOR);
    assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 0);
  });

test("a hidden or expired Reel is still the author's to clear", async () => {
  const hidden = fixture();
  const hiddenComment = await seedComment(hidden.service);
  hidden.db.seed(`reels/${REEL_ID}`, {
    ...publishedReel(),
    moderationStatus: "hidden",
    commentCount: 1,
  });
  assert.equal(
    (await hidden.service.removeReelComment(
      removeRequest({ commentId: hiddenComment }),
    )).commentCount,
    0,
  );

  const expired = fixture({ availability: { hours: 24 } });
  const expiredComment = await seedComment(expired.service);
  expired.db.seed(`reels/${REEL_ID}`, {
    ...publishedReel({ status: "expired" }),
    commentCount: 1,
  });
  assert.equal(
    (await expired.service.removeReelComment(
      removeRequest({ commentId: expiredComment }),
    )).commentCount,
    0,
  );
});

test("a deleted or purged Reel has no thread left to moderate", async () => {
  const deleted = fixture();
  const deletedComment = await seedComment(deleted.service);
  deleted.db.seed(`reels/${REEL_ID}`, {
    schemaVersion: 1,
    status: "deleted",
    authorId: AUTHOR,
    moderationStatusAtDeletion: "visible",
    moderationEvidence: {
      evidenceVersion: 1,
      publishedAt: new Date(NOW_MS),
      metadataFingerprint: "a".repeat(64),
    },
    deletedAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  });
  await rejects(
    deleted.service.removeReelComment(
      removeRequest({ commentId: deletedComment }),
    ),
    "not-found",
  );

  const purged = fixture();
  const purgedComment = await seedComment(purged.service);
  purged.db.seed(`reels/${REEL_ID}`, {
    schemaVersion: 1,
    status: "expired",
    authorId: AUTHOR,
    moderationStatusAtExpiry: "visible",
    moderationEvidence: {
      evidenceVersion: 1,
      publishedAt: new Date(NOW_MS),
      expiredAt: new Date(NOW_MS),
      availabilityHours: 24,
      metadataFingerprint: "b".repeat(64),
    },
    expiredAt: new Date(NOW_MS),
    purgedAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  });
  await rejects(
    purged.service.removeReelComment(
      removeRequest({ commentId: purgedComment }),
    ),
    "not-found",
  );
});

test("a banned Reel author cannot use the removal path", async () => {
  const { db, service } = fixture();
  const commentId = await seedComment(service);
  db.seed(`users/${AUTHOR}`, { uid: AUTHOR, displayName: "Gone", banned: true });
  await rejects(
    service.removeReelComment(removeRequest({ commentId })),
    "permission-denied",
  );
  assert.equal(db.data(`reels/${REEL_ID}`).commentCount, 1);
});

test("clearing a raid never spends the budget for deleting your own words",
  async () => {
    // commentRemove and commentDelete are separate scopes on purpose: an
    // author who has just cleared a brigade off their Reel must still be able
    // to delete their own comment somewhere else.
    const { db, service } = fixture({
      limits: {
        ...DEFAULT_LIMITS,
        commentRemove: { maxEvents: 1, windowMs: 600_000 },
      },
    });
    const first = await seedComment(service);
    const second = await seedComment(
      service,
      { requestId: "comment-request-0002" },
    );
    const own = await seedComment(
      service,
      { uid: AUTHOR, requestId: "comment-request-0003" },
    );

    await service.removeReelComment(removeRequest({ commentId: first }));
    await rejects(
      service.removeReelComment(
        removeRequest({ commentId: second, requestId: "remove-request-0002" }),
      ),
      "resource-exhausted",
    );
    // The author's own comment still goes through the self-delete path.
    const deleted = await service.deleteReelComment({
      auth: actor(AUTHOR, { verified: false }),
      data: {
        reelId: REEL_ID,
        commentId: own,
        requestId: "delete-request-0001",
      },
    });
    assert.equal(deleted.deleted, true);
    assert.equal(db.paths(`reels/${REEL_ID}/comments/`).length, 1);
  });

test("removal input is exact: no smuggled fields, no borrowed authority",
  async () => {
    const { service } = fixture();
    const commentId = await seedComment(service);
    await rejects(
      service.removeReelComment(
        removeRequest({ commentId, authorId: AUTHOR }),
      ),
      "invalid-argument",
    );
    await rejects(
      service.removeReelComment(removeRequest({ commentId, reelId: "" })),
      "invalid-argument",
    );
    await rejects(
      service.removeReelComment({ auth: actor(AUTHOR), data: {} }),
      "invalid-argument",
    );
    await rejects(
      service.removeReelComment({ auth: null, data: { reelId: REEL_ID } }),
      "unauthenticated",
    );
  });

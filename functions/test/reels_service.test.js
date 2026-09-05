const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  DEFAULT_LIMITS,
  MAX_REEL_AUTHORS_PER_REQUEST,
  MAX_REEL_SCAN_PER_REQUEST,
  REEL_FEED_BATCH_SIZE,
  createReelService,
} = require("../reels/service");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const AUTHOR = "creator-1";
const VIEWER = "viewer-1";
const REEL_ID = "reel_1";

function composition() {
  return {
    caption: "A real Reel",
    crop: {
      scalePermille: 1000,
      offsetXPermille: 0,
      offsetYPermille: 0,
    },
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

function canonicalSortKey(rank, id) {
  return `${String(NOW_MS - rank).padStart(13, "0")}_${id}`;
}

function publishedReel({
  id = REEL_ID,
  authorId = AUTHOR,
  moderationStatus = "visible",
  sortKey = canonicalSortKey(0, id),
} = {}) {
  return {
    schemaVersion: 1,
    status: "published",
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
    sortKey,
    publishedAt: new Date(NOW_MS),
    updatedAt: new Date(NOW_MS),
  };
}

function seedPublished(db, options = {}) {
  const reel = publishedReel(options);
  db.seed(`reels/${options.id ?? REEL_ID}`, reel);
  return reel;
}

function serviceWithPublishedReel({
  limits = DEFAULT_LIMITS,
  moderationStatus = "visible",
  seedDefault = true,
  onDelete,
} = {}) {
  const db = new InMemoryFirestore();
  const deletions = [];
  db.seed(`users/${VIEWER}`, { uid: VIEWER, displayName: "Viewer" });
  db.seed(`users/${AUTHOR}`, { uid: AUTHOR, displayName: "Creator" });
  if (seedDefault) seedPublished(db, { moderationStatus });
  const storage = {
    getMetadata: async () => ({}),
    readHeader: async () => Buffer.alloc(0),
    revokeDownloadTokens: async () => {},
    getSignedReadUrl: async () => "https://storage.googleapis.com/bucket/file",
    async deleteObject(path, options) {
      deletions.push({ path, options });
      if (onDelete) await onDelete(path, options);
    },
  };
  return {
    db,
    deletions,
    service: createReelService({
      db,
      FieldPath: { documentId: () => "__name__" },
      Timestamp: { fromMillis: (value) => new Date(value) },
      storage,
      clock: () => NOW_MS,
      limits,
    }),
  };
}

function reportRequest(overrides = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: {
      reelId: REEL_ID,
      requestId: "report-request-0001",
      reason: "spam",
      note: "",
      ...overrides,
    },
  };
}

function listRequest({ cursor = null, limit = 20 } = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: { cursor, limit },
  };
}

function rateState(db, scope) {
  return db.paths("privateRateLimits/")
    .map((path) => db.data(path))
    .find((value) => value.scope === scope);
}

test("Reel reports are real, idempotent and stored for moderation", async () => {
  const { db, service } = serviceWithPublishedReel();
  const first = await service.createReelReport(reportRequest());
  assert.deepEqual(await service.createReelReport(reportRequest()), first);
  assert.equal(first.created, true);

  const stored = db.data(`reports/${first.reportId}`);
  assert.deepEqual(
    {
      reporterId: stored.reporterId,
      targetType: stored.targetType,
      targetId: stored.targetId,
      reportedUserId: stored.reportedUserId,
      contextPath: stored.contextPath,
      reason: stored.reason,
      note: stored.note,
      status: stored.status,
    },
    {
      reporterId: VIEWER,
      targetType: "reel",
      targetId: REEL_ID,
      reportedUserId: AUTHOR,
      contextPath: `reels/${REEL_ID}`,
      reason: "spam",
      note: "",
      status: "open",
    },
  );
  assert.equal(db.paths("reports/").length, 1);
});

test("new request ids for an existing Reel report remain rate limited", async () => {
  const { db, service } = serviceWithPublishedReel({
    limits: {
      ...DEFAULT_LIMITS,
      report: { maxEvents: 2, windowMs: 60_000 },
    },
  });
  const firstRequest = reportRequest();
  const first = await service.createReelReport(firstRequest);
  const duplicate = await service.createReelReport(
    reportRequest({ requestId: "report-request-0002" }),
  );
  assert.deepEqual(duplicate, { reportId: first.reportId, created: false });
  assert.equal(rateState(db, "reel.report").count, 2);

  assert.deepEqual(
    await service.createReelReport(firstRequest),
    first,
    "an exact completed replay remains free",
  );
  await assert.rejects(
    service.createReelReport(
      reportRequest({ requestId: "report-request-0003" }),
    ),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(rateState(db, "reel.report").count, 2);
  assert.equal(db.paths("reports/").length, 1);
});

test("Reel reports reject unsupported input shapes", async () => {
  const { service } = serviceWithPublishedReel();
  await assert.rejects(
    service.createReelReport(reportRequest({ forgedAuthorId: AUTHOR })),
    (error) => error.code === "invalid-argument",
  );
});

test("feed cursor advances only through the last item actually scanned", async () => {
  const { db, service } = serviceWithPublishedReel({ seedDefault: false });
  const filteredAuthor = "filtered-author";
  const firstAuthor = "first-author";
  const secondAuthor = "second-author";
  const thirdAuthor = "third-author";
  db.seed(`users/${filteredAuthor}`, { disabled: true });
  for (const uid of [firstAuthor, secondAuthor, thirdAuthor]) {
    db.seed(`users/${uid}`, { uid });
  }
  seedPublished(db, {
    id: "filtered",
    authorId: filteredAuthor,
    sortKey: canonicalSortKey(0, "filtered"),
  });
  seedPublished(db, {
    id: "first",
    authorId: firstAuthor,
    sortKey: canonicalSortKey(1, "first"),
  });
  seedPublished(db, {
    id: "second",
    authorId: secondAuthor,
    sortKey: canonicalSortKey(2, "second"),
  });
  seedPublished(db, {
    id: "third",
    authorId: thirdAuthor,
    sortKey: canonicalSortKey(3, "third"),
  });

  const firstPage = await service.listReels(listRequest({ limit: 2 }));
  assert.deepEqual(firstPage.items.map((item) => item.id), ["first", "second"]);
  assert.equal(firstPage.nextCursor, canonicalSortKey(2, "second"));

  const secondPage = await service.listReels(listRequest({
    cursor: firstPage.nextCursor,
    limit: 2,
  }));
  assert.deepEqual(secondPage.items.map((item) => item.id), ["third"]);
  assert.equal(secondPage.nextCursor, null);
});

test("an early page break does not let a later poisoned cursor hide safe items",
  async () => {
    const { db, service } = serviceWithPublishedReel({ seedDefault: false });
    for (const uid of ["poison-author-a", "poison-author-b", "poison-author-c"]) {
      db.seed(`users/${uid}`, { uid });
    }
    seedPublished(db, {
      id: "safe-a",
      authorId: "poison-author-a",
      sortKey: canonicalSortKey(0, "safe-a"),
    });
    seedPublished(db, {
      id: "safe-b",
      authorId: "poison-author-b",
      sortKey: canonicalSortKey(1, "safe-b"),
    });
    seedPublished(db, {
      id: "poison",
      authorId: "poison-author-c",
      sortKey: "000000000000x_poison",
    });

    const first = await service.listReels(listRequest({ limit: 1 }));
    assert.deepEqual(first.items.map((item) => item.id), ["safe-a"]);
    assert.equal(first.nextCursor, canonicalSortKey(0, "safe-a"));

    const second = await service.listReels(listRequest({
      cursor: first.nextCursor,
      limit: 1,
    }));
    assert.deepEqual(second.items.map((item) => item.id), ["safe-b"]);
    assert.equal(second.nextCursor, null);
  });

test("feed scan amplification is capped and repeated authors are request-cached",
  async () => {
    const repeated = serviceWithPublishedReel({ seedDefault: false });
    repeated.db.seed(`users/${AUTHOR}`, { uid: AUTHOR, disabled: true });
    for (let rank = 0; rank < 30; rank += 1) {
      const id = `repeated-${String(rank).padStart(2, "0")}`;
      seedPublished(repeated.db, {
        id,
        authorId: AUTHOR,
        sortKey: canonicalSortKey(rank, id),
      });
    }
    const emptyPage = await repeated.service.listReels(listRequest());
    assert.deepEqual(emptyPage.items, []);
    assert.notEqual(emptyPage.nextCursor, null);
    assert.equal(repeated.db.metrics.queryDocumentReads, MAX_REEL_SCAN_PER_REQUEST);
    assert.equal(
      repeated.db.metrics.queryCalls,
      Math.ceil(MAX_REEL_SCAN_PER_REQUEST / REEL_FEED_BATCH_SIZE),
    );
    assert.equal(
      repeated.db.metrics.getAllDocumentReads,
      MAX_REEL_SCAN_PER_REQUEST + 4,
      "each scanned Reel adds one server-only availability read",
    );

    const unique = serviceWithPublishedReel({ seedDefault: false });
    for (let rank = 0; rank < 30; rank += 1) {
      const id = `unique-${String(rank).padStart(2, "0")}`;
      const authorId = `disabled-author-${String(rank).padStart(2, "0")}`;
      unique.db.seed(`users/${authorId}`, { disabled: true });
      seedPublished(unique.db, {
        id,
        authorId,
        sortKey: canonicalSortKey(rank, id),
      });
    }
    const uniquePage = await unique.service.listReels(listRequest());
    assert.deepEqual(uniquePage.items, []);
    assert.equal(
      uniquePage.nextCursor,
      canonicalSortKey(7, "unique-07"),
      "prefetched authors beyond the budget must not be skipped",
    );
    assert.ok(
      unique.db.metrics.queryDocumentReads <= MAX_REEL_SCAN_PER_REQUEST,
    );
    assert.equal(
      unique.db.metrics.getAllDocumentReads,
      MAX_REEL_AUTHORS_PER_REQUEST * 5,
    );
    assert.ok(
      unique.db.metrics.queryDocumentReads +
        unique.db.metrics.getAllDocumentReads <=
        MAX_REEL_SCAN_PER_REQUEST + MAX_REEL_AUTHORS_PER_REQUEST * 5,
    );
    const nextUniquePage = await unique.service.listReels(listRequest({
      cursor: uniquePage.nextCursor,
    }));
    assert.equal(
      nextUniquePage.nextCursor,
      canonicalSortKey(15, "unique-15"),
    );
  });

test("an author can delete a hidden Reel without retaining public content",
  async () => {
    const { db, deletions, service } = serviceWithPublishedReel({
      moderationStatus: "hidden",
    });
    const report = { targetId: REEL_ID, status: "resolved" };
    const audit = { targetId: REEL_ID, action: "hide" };
    db.seed("reports/reel-report-evidence", report);
    db.seed("adminAuditLogs/reel-audit-evidence", audit);

    assert.deepEqual(await service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: true } },
      data: { reelId: REEL_ID, requestId: "delete-hidden-reel-0001" },
    }), { reelId: REEL_ID, deleted: true });

    const tombstone = db.data(`reels/${REEL_ID}`);
    assert.deepEqual(Object.keys(tombstone).sort(), [
      "authorId",
      "deletedAt",
      "moderationEvidence",
      "moderationStatusAtDeletion",
      "schemaVersion",
      "status",
      "updatedAt",
    ]);
    assert.equal(tombstone.status, "deleted");
    assert.equal(tombstone.moderationStatusAtDeletion, "hidden");
    assert.deepEqual(Object.keys(tombstone.moderationEvidence).sort(), [
      "evidenceVersion",
      "metadataFingerprint",
      "publishedAt",
    ]);
    assert.equal(tombstone.moderationEvidence.evidenceVersion, 1);
    assert.match(
      tombstone.moderationEvidence.metadataFingerprint,
      /^[a-f0-9]{64}$/u,
    );

    const outboxPath = db.paths("reelCleanupOutbox/")[0];
    const outbox = db.data(outboxPath);
    assert.equal(outbox.kind, "reelPublishedMediaCleanup");
    assert.deepEqual(outbox.storageObjects, [{
      path: `reels/${AUTHOR}/${REEL_ID}/media.jpg`,
      generation: "123",
    }]);
    await service.processCleanupOutbox(outboxPath.split("/").at(-1));
    assert.deepEqual(deletions, [{
      path: `reels/${AUTHOR}/${REEL_ID}/media.jpg`,
      options: { generation: "123" },
    }]);
    assert.equal(db.data(outboxPath).status, "completed");
    assert.deepEqual(db.data("reports/reel-report-evidence"), report);
    assert.deepEqual(db.data("adminAuditLogs/reel-audit-evidence"), audit);
  });

test("an unverified communication-muted active author can delete their Reel",
  async () => {
    const { db, service } = serviceWithPublishedReel();
    db.seed(`restrictions/${AUTHOR}`, {
      type: "communicationMute",
      expiresAt: null,
    });

    assert.deepEqual(await service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: false } },
      data: { reelId: REEL_ID, requestId: "delete-muted-reel-0001" },
    }), { reelId: REEL_ID, deleted: true });
    assert.equal(db.data(`reels/${REEL_ID}`).status, "deleted");
    assert.equal(db.paths("reelCleanupOutbox/").length, 1);
    assert.equal(rateState(db, "reel.delete").count, 1);
  });

test("relaxed deletion still rejects an inactive owner", async () => {
  const { db, service } = serviceWithPublishedReel();
  db.seed(`users/${AUTHOR}`, { uid: AUTHOR, disabled: true });
  db.seed(`restrictions/${AUTHOR}`, {
    type: "communicationMute",
    expiresAt: null,
  });

  await assert.rejects(
    service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: false } },
      data: { reelId: REEL_ID, requestId: "delete-inactive-reel-0001" },
    }),
    (error) => error.code === "permission-denied",
  );
  assert.equal(db.data(`reels/${REEL_ID}`).status, "published");
  assert.equal(db.paths("reelCleanupOutbox/").length, 0);
  assert.equal(rateState(db, "reel.delete"), undefined);
});

test("delete converges after a lost acknowledgement with a fresh request id",
  async () => {
    const { db, service } = serviceWithPublishedReel({
      moderationStatus: "hidden",
    });
    const first = await service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: true } },
      data: { reelId: REEL_ID, requestId: "delete-lost-ack-0001" },
    });
    const tombstone = structuredClone(db.data(`reels/${REEL_ID}`));
    const second = await service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: true } },
      data: { reelId: REEL_ID, requestId: "delete-lost-ack-0002" },
    });

    assert.deepEqual(second, first);
    assert.deepEqual(db.data(`reels/${REEL_ID}`), tombstone);
    assert.equal(db.paths("reelCleanupOutbox/").length, 1);
    assert.equal(rateState(db, "reel.delete").count, 2);
  });

test("delete reconciliation rejects foreign and malformed tombstones",
  async () => {
    const foreign = serviceWithPublishedReel({ moderationStatus: "hidden" });
    await foreign.service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: true } },
      data: { reelId: REEL_ID, requestId: "delete-owned-first-0001" },
    });
    await assert.rejects(
      foreign.service.deleteReel({
        auth: { uid: VIEWER, token: { email_verified: true } },
        data: { reelId: REEL_ID, requestId: "delete-foreign-second-0001" },
      }),
      (error) => error.code === "permission-denied",
    );

    const malformed = serviceWithPublishedReel({ moderationStatus: "hidden" });
    await malformed.service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: true } },
      data: { reelId: REEL_ID, requestId: "delete-malformed-first-0001" },
    });
    malformed.db.seed(`reels/${REEL_ID}`, {
      ...malformed.db.data(`reels/${REEL_ID}`),
      caption: "must not survive deletion",
    });
    await assert.rejects(
      malformed.service.deleteReel({
        auth: { uid: AUTHOR, token: { email_verified: true } },
        data: { reelId: REEL_ID, requestId: "delete-malformed-second-0001" },
      }),
      (error) => error.code === "data-loss",
    );
  });

test("Reel deletion rejects other authors and cross-Reel cleanup paths",
  async () => {
    const foreign = serviceWithPublishedReel({ moderationStatus: "hidden" });
    await assert.rejects(
      foreign.service.deleteReel({
        auth: { uid: VIEWER, token: { email_verified: true } },
        data: { reelId: REEL_ID, requestId: "delete-foreign-reel-0001" },
      }),
      (error) => error.code === "permission-denied",
    );

    const corrupt = serviceWithPublishedReel({ moderationStatus: "hidden" });
    await corrupt.service.deleteReel({
      auth: { uid: AUTHOR, token: { email_verified: true } },
      data: { reelId: REEL_ID, requestId: "delete-corrupt-reel-0001" },
    });
    const outboxPath = corrupt.db.paths("reelCleanupOutbox/")[0];
    const outbox = corrupt.db.data(outboxPath);
    corrupt.db.seed(outboxPath, {
      ...outbox,
      storageObjects: [{
        path: `reels/${AUTHOR}/another-reel/media.jpg`,
        generation: "123",
      }],
    });
    assert.deepEqual(
      await corrupt.service.processCleanupOutbox(outboxPath.split("/").at(-1)),
      {
        outboxId: outboxPath.split("/").at(-1),
        completed: false,
        deadLetter: true,
        code: "data-loss",
      },
    );
    assert.equal(corrupt.db.data(outboxPath).status, "deadLetter");
    assert.equal(corrupt.db.data(outboxPath).lastErrorCode, "data-loss");
    assert.deepEqual(corrupt.deletions, []);
  });

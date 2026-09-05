const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  FieldValue,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DEFAULT_LIMITS,
  VOICE_MOMENT_V2_READ_BUDGETS,
  canonicalCommentId,
  createMomentIntegrityService,
  momentStoragePath,
  voiceReplyStoragePath,
} = require("../moments/integrity");
const {
  createDirectMessagingService,
  directMediaStoragePath,
} = require("../messaging/direct_integrity");
const { createMomentMigrationService } = require("../moments/migration");
const { operationIdentity } = require("../integrity/guards");

const db = getFirestore();
const A = "mmi-alice";
const B = "mmi-bob";
const C = "mmi-charlie";
const USERS = [A, B, C];
// Report-target fixtures. Rooms and Clubs are not otherwise part of this
// suite, so every id here is namespaced and torn down in reset().
const PRIVATE_ROOM = "mmi-report-room";
const PUBLIC_ROOM = "mmi-report-public";
const LOUNGE_ROOM = "mmi-report-lounge";
const REPORT_CLUB = "mmi-report-club";
const ROOM_MESSAGE = "room-message-0001";
const CLUB_CHANNEL = "general";
const CLUB_MESSAGE = "club-message-0001";
let nowMs = 1_810_000_000_000;
let storage;

class FakeStorage {
  constructor() {
    this.objects = new Map();
    this.deleted = [];
    this.revoked = [];
    this.signedGrants = [];
    this.metadataReads = 0;
    this.beforeSignedRead = null;
  }

  put(
    path,
    {
      authorId,
      momentId,
      commentId,
      contentType = "audio/mp4",
      generation = "1001",
      size = 4096,
      extraMetadata = {},
    },
  ) {
    const custom = {
      authorId,
      momentId,
      ...(commentId ? { commentId } : {}),
      firebaseStorageDownloadTokens: "durable-test-token",
      ...extraMetadata,
    };
    this.objects.set(path, {
      contentType,
      generation,
      size: String(size),
      metadata: custom,
    });
  }

  async getMetadata(path) {
    this.metadataReads += 1;
    const metadata = this.objects.get(path);
    if (!metadata) throw new Error(`Missing fake object: ${path}`);
    return metadata;
  }

  async getDownloadUrl(path) {
    return `https://storage.example.invalid/${encodeURIComponent(path)}`;
  }

  async revokeDownloadTokens(path) {
    const object = this.objects.get(path);
    if (!object) throw new Error(`Missing fake object: ${path}`);
    delete object.metadata.firebaseStorageDownloadTokens;
    this.revoked.push(path);
    return object;
  }

  async getSignedReadUrl(path, { expiresAtMs, generation }) {
    this.signedGrants.push({ path, expiresAtMs, generation });
    if (this.beforeSignedRead) await this.beforeSignedRead();
    return `https://storage.googleapis.com/test-bucket/${encodeURIComponent(
      path,
    )}?generation=${generation}&signature=short-lived`;
  }

  async deleteObject(path, { ignoreNotFound = false } = {}) {
    if (!this.objects.has(path) && !ignoreNotFound) {
      throw new Error(`Missing fake object: ${path}`);
    }
    this.deleted.push(path);
    this.objects.delete(path);
  }
}

function request(uid, data, verified = true) {
  return {
    auth: {
      uid,
      token: { email_verified: verified, email: `${uid}@example.invalid` },
    },
    data,
  };
}

function momentService(limitOverrides = {}, options = {}) {
  return createMomentIntegrityService({
    db,
    FieldPath,
    Timestamp,
    storage,
    clock: () => nowMs,
    limits: { ...DEFAULT_LIMITS, ...limitOverrides },
    ...options,
  });
}

async function deleteQuery(query) {
  const snapshot = await query.get();
  for (const document of snapshot.docs) {
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(document.ref);
    } else {
      await document.ref.delete();
    }
  }
}

async function reset() {
  for (const uid of USERS) {
    await Promise.all([
      db.doc(`users/${uid}`).delete(),
      db.doc(`publicProfiles/${uid}`).delete(),
      db.doc(`restrictions/${uid}`).delete(),
      db.doc(`momentCapacityLedgers/${uid}`).delete(),
      deleteTree(db.doc(`friendshipGuards/${uid}`)),
      deleteQuery(db.collection("voiceMoments").where("authorId", "==", uid)),
      deleteQuery(
        db.collection("integrityOperationLedgers").where("ownerId", "==", uid),
      ),
      deleteQuery(
        db.collection("integrityPreflightLedgers").where("ownerId", "==", uid),
      ),
      deleteQuery(
        db.collection("privateRateLimits").where("ownerId", "==", uid),
      ),
      deleteQuery(
        db
          .collection("voiceMomentUploadReservations")
          .where("ownerId", "==", uid),
      ),
      deleteQuery(
        db
          .collection("directMessageUploadReservations")
          .where("ownerId", "==", uid),
      ),
      deleteQuery(db.collection("reports").where("reporterId", "==", uid)),
      deleteQuery(
        db
          .collection("voiceMomentReportReceipts")
          .where("ownerId", "==", uid),
      ),
      deleteQuery(
        db.collection("contentCleanupOutbox").where("requestedBy", "==", uid),
      ),
    ]);
  }
  for (const first of USERS) {
    for (const second of USERS) {
      if (first !== second) {
        await db.doc(`users/${first}/blocked/${second}`).delete();
        await db.doc(`users/${first}/following/${second}`).delete();
      }
    }
  }
  await db.doc("conversations/mmi-report-conversation").delete();
  for (const roomId of [PRIVATE_ROOM, PUBLIC_ROOM, LOUNGE_ROOM]) {
    await deleteTree(db.doc(`rooms/${roomId}`));
  }
  await deleteTree(db.doc(`clubs/${REPORT_CLUB}`));
}

async function deleteTree(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
    return;
  }
  await reference.delete();
}

async function seed(uid, overrides = {}) {
  await Promise.all([
    db.doc(`users/${uid}`).set({
      uid,
      displayName: `Private ${uid}`,
      photoUrl: `https://private.invalid/${uid}.png`,
      ...overrides,
    }),
    db.doc(`publicProfiles/${uid}`).set({
      uid,
      displayName: `Public ${uid}`,
      username: uid,
      displayNameSearch: `public ${uid}`.toLowerCase(),
      usernameSearch: uid.toLowerCase(),
      photoUrl: `https://public.invalid/${uid}.png`,
      bannerUrl: null,
      bio: "",
      country: "",
      nativeLanguage: "",
      spokenLanguages: [],
      learningLanguages: [],
      website: null,
      statusMessage: "",
      accountType: "personal",
      premiumIdentity: false,
      friendCount: 0,
      followerCount: 0,
      followingCount: 0,
      schemaVersion: 1,
      updatedAt: Timestamp.fromMillis(nowMs),
    }),
  ]);
}

async function publish(
  service,
  {
    uid = B,
    reserveRequestId = `reserve-${uid}`,
    finalizeRequestId = `finalize-${uid}`,
    caption = "Canonical Moment",
    durationSeconds = 12,
    generation = "1001",
    availabilityHours = undefined,
  } = {},
) {
  const reserved = await service.reserveMomentDraft(
    request(uid, {
      caption,
      durationSeconds,
      requestId: reserveRequestId,
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: uid,
    momentId: reserved.momentId,
    generation,
  });
  await service.finalizeMomentDraft(
    request(uid, {
      momentId: reserved.momentId,
      objectGeneration: generation,
      requestId: finalizeRequestId,
      // Absent by default on purpose: most of this suite publishes exactly the
      // way pre-availability clients do, which must stay the 24-hour story.
      ...(availabilityHours === undefined ? {} : { availabilityHours }),
    }),
  );
  return reserved;
}

beforeEach(async () => {
  nowMs = 1_810_000_000_000;
  storage = new FakeStorage();
  await reset();
  await Promise.all(USERS.map((uid) => seed(uid)));
});

after(reset);

test("Voice Moment v2 read budgets stay below the release latency gates", () => {
  assert.deepEqual(VOICE_MOMENT_V2_READ_BUDGETS, {
    feedTypical: 85,
    feedFollowingTypical: 95,
    feedWorst: 115,
    viewTypical: 98,
    viewWorst: 126,
  });
  assert.ok(VOICE_MOMENT_V2_READ_BUDGETS.feedTypical < 100);
  assert.ok(VOICE_MOMENT_V2_READ_BUDGETS.feedFollowingTypical < 100);
  assert.ok(VOICE_MOMENT_V2_READ_BUDGETS.viewTypical < 100);
  assert.ok(VOICE_MOMENT_V2_READ_BUDGETS.feedWorst < 180);
  assert.ok(VOICE_MOMENT_V2_READ_BUDGETS.viewWorst < 180);
});

test("v2 feed and detail project safe current identity without media secrets", async () => {
  const service = momentService();
  const published = await publish(service);
  await db.doc(`publicProfiles/${B}`).update({
    displayName: "Current public Bob",
    photoUrl: "https://public.invalid/current-bob.png",
  });

  const feed = await service.getVoiceMomentsFeedV2(request(A, {}));
  assert.equal(feed.schemaVersion, 2);
  assert.equal(feed.moments.length, 1);
  assert.equal(feed.moments[0].momentId, published.momentId);
  assert.equal(feed.moments[0].authorName, "Current public Bob");
  assert.equal(feed.moments[0].authorPhotoUrl, null);
  assert.match(feed.moments[0].reportReceipt, /^[A-Za-z0-9_-]{43}$/u);
  for (const forbidden of [
    "audioUrl",
    "storagePath",
    "mediaGeneration",
    "mediaContentType",
    "mediaSize",
  ]) {
    assert.equal(Object.hasOwn(feed.moments[0], forbidden), false);
  }

  const view = await service.getVoiceMomentViewV2(
    request(A, { momentId: published.momentId }),
  );
  assert.equal(view.moment.momentId, published.momentId);
  assert.equal(view.moment.authorName, "Current public Bob");
  assert.match(view.moment.reportReceipt, /^[A-Za-z0-9_-]{43}$/u);
  assert.equal(Object.hasOwn(view.moment, "audioUrl"), false);
  assert.equal(Object.hasOwn(view.moment, "storagePath"), false);
});

test("v2 feed cursor pages a stable order without duplicates", async () => {
  const service = momentService();
  const published = [];
  for (let index = 0; index < 5; index += 1) {
    nowMs += 1_000;
    published.push(await publish(service, {
      reserveRequestId: `reserve-page-${index}`,
      finalizeRequestId: `finalize-page-${index}`,
      caption: `Page ${index}`,
      generation: `${2_000 + index}`,
    }));
  }

  const first = await service.getVoiceMomentsFeedV2(request(A, { limit: 2 }));
  assert.deepEqual(Object.keys(first).sort(), [
    "hasMore",
    "moments",
    "nextCursor",
    "scannedCount",
    "schemaVersion",
  ]);
  assert.equal(first.hasMore, true);
  assert.equal(typeof first.nextCursor, "string");
  assert.equal(first.scannedCount, 2);

  const second = await service.getVoiceMomentsFeedV2(request(A, {
    limit: 2,
    cursor: first.nextCursor,
  }));
  const third = await service.getVoiceMomentsFeedV2(request(A, {
    limit: 2,
    cursor: second.nextCursor,
  }));
  const ids = [...first.moments, ...second.moments, ...third.moments]
    .map((moment) => moment.momentId);
  assert.equal(new Set(ids).size, 5);
  assert.deepEqual(ids, published.reverse().map((item) => item.momentId));
  assert.equal(second.hasMore, true);
  assert.equal(third.hasMore, false);
  assert.equal(third.nextCursor, null);
  assert.equal(third.scannedCount, 1);

  await Promise.all(published.map((item, index) =>
    db.doc(`voiceMoments/${item.momentId}`).update({
      likeCount: index * 10,
    })));
  const popularFirst = await service.getVoiceMomentsFeedV2(request(A, {
    limit: 2,
    sortMode: "popular",
  }));
  const popularSecond = await service.getVoiceMomentsFeedV2(request(A, {
    limit: 2,
    sortMode: "popular",
    cursor: popularFirst.nextCursor,
  }));
  const popularCounts = [...popularFirst.moments, ...popularSecond.moments]
    .map((moment) => moment.likeCount);
  assert.deepEqual(popularCounts, [40, 30, 20, 10]);
  await assert.rejects(
    service.getVoiceMomentsFeedV2(request(A, {
      limit: 2,
      sortMode: "recent",
      cursor: popularFirst.nextCursor,
    })),
    (error) => error.code === "invalid-argument",
  );

  await assert.rejects(
    service.getVoiceMomentsFeedV2(request(A, {
      limit: 2,
      feedMode: "following",
      cursor: first.nextCursor,
    })),
    (error) => error.code === "invalid-argument",
  );

  await assert.rejects(
    service.getVoiceMomentsFeedV2(request(A, {
      limit: 2,
      cursor: "not-a-real-cursor",
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("v2 following feed accepts only canonical social edges after audience gates", async () => {
  const service = momentService();
  const bob = await publish(service, {
    reserveRequestId: "reserve-following-bob",
    finalizeRequestId: "finalize-following-bob",
  });
  nowMs += 1_000;
  const charlie = await publish(service, {
    uid: C,
    reserveRequestId: "reserve-following-charlie",
    finalizeRequestId: "finalize-following-charlie",
    generation: "3001",
  });

  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {
      feedMode: "following",
    }))).moments,
    [],
  );
  await db.doc(`users/${A}/following/${B}`).set({ uid: B });
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {
      feedMode: "following",
    }))).moments,
    [],
  );
  await db.doc(`users/${A}/following/${B}`).set({
    uid: B,
    followedAt: Timestamp.fromMillis(nowMs),
  });
  await Promise.all([
    db.doc(`friendshipGuards/${A}/friends/${C}`).set({
      schemaVersion: 1,
      ownerId: A,
      friendId: C,
      establishedAt: Timestamp.fromMillis(nowMs),
    }),
    db.doc(`friendshipGuards/${C}/friends/${A}`).set({
      schemaVersion: 1,
      ownerId: C,
      friendId: A,
      establishedAt: Timestamp.fromMillis(nowMs),
    }),
  ]);
  const social = await service.getVoiceMomentsFeedV2(request(A, {
    feedMode: "following",
  }));
  assert.deepEqual(
    social.moments.map((moment) => moment.momentId),
    [charlie.momentId, bob.momentId],
  );

  await db.doc(`users/${B}`).update({ profileVisibility: "private" });
  const privateFiltered = await service.getVoiceMomentsFeedV2(request(A, {
    feedMode: "following",
  }));
  assert.deepEqual(
    privateFiltered.moments.map((moment) => moment.momentId),
    [charlie.momentId],
  );
  await assert.rejects(
    service.getVoiceMomentsFeedV2(request(A, {
      feedMode: "following",
      sortMode: "popular",
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("v2 detail cursor pages comments and is bound to its parent", async () => {
  const service = momentService();
  const firstMoment = await publish(service, {
    reserveRequestId: "reserve-comment-page-root",
    finalizeRequestId: "finalize-comment-page-root",
  });
  const secondMoment = await publish(service, {
    uid: C,
    reserveRequestId: "reserve-comment-page-other",
    finalizeRequestId: "finalize-comment-page-other",
    generation: "3001",
  });
  const created = [];
  for (let index = 0; index < 5; index += 1) {
    nowMs += 1_000;
    created.push(await service.createMomentComment(request(A, {
      momentId: firstMoment.momentId,
      text: `Comment ${index}`,
      requestId: `comment-page-${index}`,
    })));
  }

  const first = await service.getVoiceMomentViewV2(request(A, {
    momentId: firstMoment.momentId,
    commentLimit: 2,
  }));
  assert.deepEqual(Object.keys(first).sort(), [
    "comments",
    "commentsTruncated",
    "moment",
    "nextCommentCursor",
    "schemaVersion",
    "topReactions",
  ]);
  assert.equal(first.commentsTruncated, true);
  assert.equal(typeof first.nextCommentCursor, "string");

  const second = await service.getVoiceMomentViewV2(request(A, {
    momentId: firstMoment.momentId,
    commentLimit: 2,
    commentCursor: first.nextCommentCursor,
  }));
  const third = await service.getVoiceMomentViewV2(request(A, {
    momentId: firstMoment.momentId,
    commentLimit: 2,
    commentCursor: second.nextCommentCursor,
  }));
  assert.deepEqual(
    [...first.comments, ...second.comments, ...third.comments]
      .map((comment) => comment.commentId),
    created.map((comment) => comment.commentId),
  );
  assert.equal(third.commentsTruncated, false);
  assert.equal(third.nextCommentCursor, null);

  await assert.rejects(
    service.getVoiceMomentViewV2(request(A, {
      momentId: secondMoment.momentId,
      commentCursor: first.nextCommentCursor,
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("v2 audience is fail-closed for private, one-sided friendship and blocks", async () => {
  const service = momentService();
  const published = await publish(service);
  await db.doc(`users/${B}`).update({ profileVisibility: "private" });
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
  await assert.rejects(
    service.getVoiceMomentViewV2(
      request(A, { momentId: published.momentId }),
    ),
    (error) => error.code === "permission-denied",
  );
  assert.equal(
    (await service.getVoiceMomentsFeedV2(request(B, {}))).moments.length,
    1,
  );

  await db.doc(`users/${B}`).update({ profileVisibility: "friends" });
  await db.doc(`friendshipGuards/${A}/friends/${B}`).set({
    schemaVersion: 1,
    ownerId: A,
    friendId: B,
    establishedAt: Timestamp.fromMillis(nowMs),
  });
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
  await db.doc(`friendshipGuards/${B}/friends/${A}`).set({
    schemaVersion: 1,
    ownerId: B,
    friendId: A,
    establishedAt: Timestamp.fromMillis(nowMs),
  });
  assert.equal(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments.length,
    1,
  );

  await db.doc(`users/${B}/blocked/${A}`).set({ createdAt: Timestamp.now() });
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
});

test("v2 reads reject inactive or restricted principals and the exact expiry boundary", async () => {
  const service = momentService();
  const published = await publish(service);

  await db.doc(`restrictions/${B}`).set({ type: "communicationMute" });
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
  await db.doc(`restrictions/${B}`).delete();
  await db.doc(`users/${B}`).update({ disabled: true });
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
  await db.doc(`users/${B}`).update({ disabled: false });

  await db.doc(`restrictions/${A}`).set({ type: "communicationMute" });
  await assert.rejects(
    service.getVoiceMomentViewV2(
      request(A, { momentId: published.momentId }),
    ),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`restrictions/${A}`).delete();

  nowMs += 24 * 60 * 60_000;
  await assert.rejects(
    service.getVoiceMomentViewV2(
      request(A, { momentId: published.momentId }),
    ),
    (error) => error.code === "permission-denied",
  );
  assert.deepEqual(
    (await service.getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
});

test("v2 rechecks expiry at response time instead of request admission", async () => {
  const published = await publish(momentService(), {
    reserveRequestId: "reserve-response-expiry",
    finalizeRequestId: "finalize-response-expiry",
  });
  const expiresAt = (await db.doc(`voiceMoments/${published.momentId}`).get())
    .data().expiresAt.toMillis();
  const expiringService = () => {
    let calls = 0;
    return momentService({}, {
      clock: () => calls++ === 0 ? expiresAt - 1 : expiresAt,
    });
  };

  assert.deepEqual(
    (await expiringService().getVoiceMomentsFeedV2(request(A, {}))).moments,
    [],
  );
  await assert.rejects(
    expiringService().getVoiceMomentViewV2(
      request(A, { momentId: published.momentId }),
    ),
    (error) => error.code === "permission-denied",
  );
});

test("private Voice Moments cannot leak through playback or engagement", async () => {
  const service = momentService();
  const published = await publish(service);
  await db.doc(`users/${B}`).update({ profileVisibility: "private" });

  for (const operation of [
    () => service.getVoiceMomentMediaAccess(
      request(A, { momentId: published.momentId }),
    ),
    () => service.setMomentLike(
      request(A, {
        momentId: published.momentId,
        liked: true,
        requestId: "private-like-01",
      }),
    ),
    () => service.createMomentComment(
      request(A, {
        momentId: published.momentId,
        text: "must stay private",
        requestId: "private-comment-01",
      }),
    ),
  ]) {
    await assert.rejects(operation(), (error) =>
      ["permission-denied", "failed-precondition"].includes(error.code));
  }
  assert.equal(storage.signedGrants.length, 0);
});

test("detail hides comments and reaction identities after their authors become private", async () => {
  const service = momentService();
  const published = await publish(service);
  await service.createMomentComment(
    request(C, {
      momentId: published.momentId,
      text: "visible before privacy change",
      requestId: "comment-child-privacy",
    }),
  );
  await service.setMomentLike(
    request(C, {
      momentId: published.momentId,
      liked: true,
      requestId: "reaction-child-privacy",
    }),
  );
  await db.doc(`users/${C}`).update({ profileVisibility: "private" });

  const view = await service.getVoiceMomentViewV2(
    request(A, { momentId: published.momentId }),
  );
  assert.deepEqual(view.comments, []);
  assert.deepEqual(view.topReactions, []);
  assert.equal(view.moment.commentCount, 1);
  assert.equal(view.moment.likeCount, 1);
});

test("Voice Moment reporting has no missing/private/blocked/expired oracle", async () => {
  const service = momentService();
  const published = await publish(service);
  const report = (momentId, requestId) =>
    service.createContentReport(
      request(A, {
        targetType: "voiceMoment",
        momentId,
        reason: "safety report",
        requestId,
      }, false),
    );
  const expectHidden = (promise) =>
    assert.rejects(promise, (error) => error.code === "permission-denied");

  await db.doc(`users/${B}`).update({ profileVisibility: "private" });
  await expectHidden(report(published.momentId, "report-private-01"));
  await expectHidden(report("missing-moment", "report-missing-01"));

  await db.doc(`users/${B}`).update({ profileVisibility: "public" });
  await db.doc(`users/${A}/blocked/${B}`).set({ createdAt: Timestamp.now() });
  await expectHidden(report(published.momentId, "report-blocked-01"));
  await db.doc(`users/${A}/blocked/${B}`).delete();

  nowMs += 24 * 60 * 60_000;
  await expectHidden(report(published.momentId, "report-expired-01"));
});

test("reporting cannot reveal a guessed comment hidden by its author's privacy", async () => {
  const service = momentService();
  const published = await publish(service);
  const comment = await service.createMomentComment(
    request(C, {
      momentId: published.momentId,
      text: "later hidden",
      requestId: "hidden-report-comment",
    }),
  );
  const report = (commentId, requestId) =>
    service.createContentReport(
      request(A, {
        targetType: "voiceMomentComment",
        momentId: published.momentId,
        commentId,
        reason: "safety report",
        requestId,
      }, false),
    );
  const expectHidden = (promise) =>
    assert.rejects(promise, (error) => error.code === "permission-denied");

  await db.doc(`users/${C}`).update({ profileVisibility: "private" });
  await expectHidden(report(comment.commentId, "report-private-child"));
  await expectHidden(report("guessed-comment-id", "report-missing-child"));

  await db.doc(`users/${C}`).update({ profileVisibility: "public" });
  await db.doc(`users/${C}/blocked/${A}`).set({ createdAt: Timestamp.now() });
  await expectHidden(report(comment.commentId, "report-blocked-child"));
});

test("v2 report receipt preserves safety reporting across block and mute races", async () => {
  const service = momentService();
  const published = await publish(service, {
    reserveRequestId: "reserve-receipt-report",
    finalizeRequestId: "finalize-receipt-report",
  });
  const projected = await service.getVoiceMomentViewV2(
    request(A, { momentId: published.momentId }),
  );
  const receipt = projected.moment.reportReceipt;
  assert.match(receipt, /^[A-Za-z0-9_-]{43}$/u);

  await Promise.all([
    db.doc(`users/${B}/blocked/${A}`).set({
      createdAt: Timestamp.fromMillis(nowMs),
    }),
    db.doc(`restrictions/${A}`).set({ type: "communicationMute" }),
  ]);
  const reportRequest = request(A, {
    targetType: "voiceMoment",
    momentId: published.momentId,
    reason: "harassment",
    requestId: "receipt-report-01",
    reportReceipt: receipt,
  }, false);
  const created = await service.createContentReport(reportRequest);
  const report = (await db.doc(`reports/${created.reportId}`).get()).data();
  assert.equal(report.targetId, published.momentId);
  assert.equal(report.reportedUserId, B);
  assert.equal(report.contextPath, `voiceMoments/${published.momentId}`);
  assert.equal(
    (await db.collection("voiceMomentReportReceipts")
      .where("ownerId", "==", A).get()).empty,
    true,
  );
  // Lost-ack retry replays from the operation ledger after the one-shot
  // capability has been consumed.
  assert.deepEqual(await service.createContentReport(reportRequest), created);
});

test("v2 comment receipt is target-bound and hides guessed or expired tokens", async () => {
  const service = momentService();
  const published = await publish(service, {
    reserveRequestId: "reserve-comment-receipt",
    finalizeRequestId: "finalize-comment-receipt",
  });
  const comment = await service.createMomentComment(request(C, {
    momentId: published.momentId,
    text: "reportable reply",
    requestId: "comment-receipt-create",
  }));
  const secondComment = await service.createMomentComment(request(C, {
    momentId: published.momentId,
    text: "second reportable reply",
    requestId: "comment-receipt-create-02",
  }));
  const projected = await service.getVoiceMomentViewV2(
    request(A, { momentId: published.momentId }),
  );
  const receipt = projected.comments
    .find((item) => item.commentId === comment.commentId)
    .reportReceipt;
  const secondReceipt = projected.comments
    .find((item) => item.commentId === secondComment.commentId)
    .reportReceipt;
  await db.doc(`users/${C}/blocked/${A}`).set({
    createdAt: Timestamp.fromMillis(nowMs),
  });

  const created = await service.createContentReport(request(A, {
    targetType: "voiceMomentComment",
    momentId: published.momentId,
    commentId: comment.commentId,
    reason: "harassment",
    requestId: "comment-receipt-report",
    reportReceipt: receipt,
  }, false));
  const report = (await db.doc(`reports/${created.reportId}`).get()).data();
  assert.equal(report.targetId, comment.commentId);
  assert.equal(report.reportedUserId, C);
  assert.equal(
    report.contextPath,
    `voiceMoments/${published.momentId}/comments/${comment.commentId}`,
  );

  await assert.rejects(
    service.createContentReport(request(A, {
      targetType: "voiceMomentComment",
      momentId: published.momentId,
      commentId: "guessed-comment-id",
      reason: "harassment",
      requestId: "guessed-receipt-01",
      reportReceipt: secondReceipt,
    }, false)),
    (error) => error.code === "permission-denied",
  );
  nowMs += 10 * 60_000;
  await assert.rejects(
    service.createContentReport(request(A, {
      targetType: "voiceMomentComment",
      momentId: published.momentId,
      commentId: secondComment.commentId,
      reason: "harassment",
      requestId: "expired-receipt-01",
      reportReceipt: secondReceipt,
    }, false)),
    (error) => error.code === "permission-denied",
  );

  nowMs -= 10 * 60_000;
  const refreshed = await service.getVoiceMomentViewV2(
    request(A, { momentId: published.momentId }),
  );
  // The comment author block correctly prevents issuing a fresh receipt.
  assert.deepEqual(refreshed.comments, []);
});

test("draft reservation and finalize bind canonical identity and immutable media", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "  Hello voice  ",
      durationSeconds: 9,
      requestId: "reserve-main1",
    }),
  );
  const replay = await service.reserveMomentDraft(
    request(A, {
      caption: "  Hello voice  ",
      durationSeconds: 9,
      requestId: "reserve-main1",
    }),
  );
  assert.deepEqual(replay, reserved);
  assert.match(reserved.momentId, /^[a-f0-9]{20}$/u);
  assert.equal(reserved.storagePath, momentStoragePath(A, reserved.momentId));

  let moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().authorName, `Public ${A}`);
  assert.equal(moment.data().caption, "Hello voice");
  assert.equal(moment.data().isPublished, false);
  assert.equal(moment.data().likeCount, 0);

  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "99123",
  });
  const finalized = await service.finalizeMomentDraft(
    request(A, {
      momentId: reserved.momentId,
      objectGeneration: "99123",
      requestId: "final-main01",
    }),
  );
  assert.equal(finalized.published, true);
  assert.deepEqual(
    await service.finalizeMomentDraft(
      request(A, {
        momentId: reserved.momentId,
        objectGeneration: "99123",
        requestId: "final-main01",
      }),
    ),
    finalized,
  );
  moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().isPublished, true);
  assert.equal(moment.data().status, "published");
  assert.equal(moment.data().mediaGeneration, "99123");
  assert.equal(moment.data().storagePath, reserved.storagePath);
  assert.equal(moment.data().audioUrl, null);
  assert.deepEqual(storage.revoked, [reserved.storagePath]);
  assert.equal(
    storage.objects.get(reserved.storagePath).metadata
      .firebaseStorageDownloadTokens,
    undefined,
  );

  await assert.rejects(
    service.finalizeMomentDraft(
      request(A, {
        momentId: reserved.momentId,
        objectGeneration: "99123",
        requestId: "final-twice1",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
});

test("private media grants re-authorize every playback and expire quickly", async () => {
  const service = momentService();
  const { momentId, storagePath } = await publish(service, {
    uid: B,
    generation: "4401",
  });
  const access = await service.getVoiceMomentMediaAccess(
    request(
      A,
      {
        momentId,
      },
      false,
    ),
  );
  assert.equal(access.schemaVersion, 1);
  assert.equal(access.mediaGeneration, "4401");
  assert.equal(access.mediaContentType, "audio/mp4");
  assert.equal(access.mediaSize, 4096);
  assert.equal(access.expiresAtMillis, nowMs + 90_000);
  assert.match(access.url, /^https:\/\/storage[.]googleapis[.]com\//u);
  assert.deepEqual(storage.signedGrants, [
    {
      path: storagePath,
      expiresAtMs: nowMs + 90_000,
      generation: "4401",
    },
  ]);

  await db.doc(`users/${A}/blocked/${B}`).set({ blockedAt: Timestamp.now() });
  await assert.rejects(
    service.getVoiceMomentMediaAccess(request(A, { momentId })),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(storage.signedGrants.length, 1);
});

test("private media grant never outlives Moment expiry", async () => {
  const service = momentService();
  const { momentId } = await publish(service, {
    uid: B,
    generation: "4402",
  });
  await db.doc(`voiceMoments/${momentId}`).update({
    expiresAt: Timestamp.fromMillis(nowMs + 15_000),
  });
  const access = await service.getVoiceMomentMediaAccess(
    request(A, {
      momentId,
    }),
  );
  assert.equal(access.expiresAtMillis, nowMs + 15_000);

  nowMs += 15_000;
  await assert.rejects(
    service.getVoiceMomentMediaAccess(request(A, { momentId })),
    (error) => error.code === "failed-precondition",
  );
});

test("legacy published Moments receive secure generation-bound playback grants", async () => {
  const service = momentService();
  const momentId = "legacy-playback-00001";
  const storagePath = momentStoragePath(B, momentId);
  storage.put(storagePath, {
    authorId: B,
    momentId,
    generation: "44021",
  });
  await db.doc(`voiceMoments/${momentId}`).set({
    authorId: B,
    authorName: "Legacy display name",
    authorPhotoUrl: null,
    caption: "Legacy playback",
    audioUrl: "https://firebasestorage.googleapis.com/legacy-token",
    storagePath,
    durationSeconds: 9,
    likeCount: 0,
    commentCount: 0,
    replyToMomentId: null,
    isPublished: true,
    createdAt: Timestamp.fromMillis(nowMs - 20_000),
    updatedAt: Timestamp.fromMillis(nowMs - 10_000),
    publishedAt: Timestamp.fromMillis(nowMs - 10_000),
  });

  const access = await service.getVoiceMomentMediaAccess(
    request(A, { momentId }),
  );

  assert.equal(access.mediaGeneration, "44021");
  assert.equal(access.mediaContentType, "audio/mp4");
  assert.equal(access.mediaSize, 4096);
  assert.equal(storage.signedGrants.at(-1).path, storagePath);
  assert.equal(
    storage.objects.get(storagePath).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
  // Playback compatibility is read-only. The audited bulk migration remains
  // the sole writer of canonical schema and child/counter reconciliation.
  assert.equal(
    (await db.doc(`voiceMoments/${momentId}`).get()).data().schemaVersion,
    undefined,
  );
});

test("expired legacy Moments fail before Storage metadata or signing", async () => {
  const service = momentService();
  const momentId = "legacy-expired-00001";
  const storagePath = momentStoragePath(B, momentId);
  storage.put(storagePath, {
    authorId: B,
    momentId,
    generation: "44022",
  });
  await db.doc(`voiceMoments/${momentId}`).set({
    authorId: B,
    caption: "Expired legacy playback",
    audioUrl: "https://firebasestorage.googleapis.com/legacy-token",
    storagePath,
    durationSeconds: 9,
    likeCount: 0,
    commentCount: 0,
    replyToMomentId: null,
    isPublished: true,
    createdAt: Timestamp.fromMillis(nowMs - 100_000),
    expiresAt: Timestamp.fromMillis(nowMs),
  });
  const metadataReads = storage.metadataReads;
  const signedGrants = storage.signedGrants.length;

  await assert.rejects(
    service.getVoiceMomentMediaAccess(request(A, { momentId })),
    (error) => error.code === "failed-precondition" &&
      /expired/u.test(error.message),
  );
  assert.equal(storage.metadataReads, metadataReads);
  assert.equal(storage.signedGrants.length, signedGrants);
});

test("a canonical reply under a legacy parent keeps exact media binding", async () => {
  const service = momentService();
  const momentId = "legacy-reply-parent1";
  const commentId = "legacyreply000000000";
  const storagePath = momentStoragePath(B, momentId);
  const replyPath = voiceReplyStoragePath(C, momentId, commentId);
  storage.put(storagePath, {
    authorId: B,
    momentId,
    generation: "44023",
  });
  storage.put(replyPath, {
    authorId: C,
    momentId,
    commentId,
    generation: "44024",
  });
  await db.doc(`voiceMoments/${momentId}`).set({
    authorId: B,
    caption: "Legacy parent with a canonical reply",
    audioUrl: "https://firebasestorage.googleapis.com/legacy-token",
    storagePath,
    durationSeconds: 9,
    likeCount: 0,
    commentCount: 1,
    replyToMomentId: null,
    isPublished: true,
    createdAt: Timestamp.fromMillis(nowMs - 20_000),
  });
  await db.doc(`voiceMoments/${momentId}/comments/${commentId}`).set({
    schemaVersion: 2,
    type: "voice",
    authorId: C,
    authorName: `Public ${C}`,
    authorPhotoUrl: null,
    text: "",
    audioUrl: null,
    storagePath: replyPath,
    durationSeconds: 4,
    // The object carries 44024. A legacy parent must not weaken this exact
    // generation binding for its otherwise canonical reply.
    mediaGeneration: "44025",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
    createdAt: Timestamp.fromMillis(nowMs - 10_000),
  });
  const signedGrants = storage.signedGrants.length;

  await assert.rejects(
    service.getVoiceMomentMediaAccess(
      request(A, { momentId, commentId }),
    ),
    (error) => error.code === "failed-precondition" &&
      /generation does not match/u.test(error.message),
  );
  assert.equal(storage.signedGrants.length, signedGrants);
});

test("media grant recheck closes a block race before returning the URL", async () => {
  const service = momentService();
  const { momentId } = await publish(service, {
    uid: B,
    generation: "4403",
  });
  storage.beforeSignedRead = async () => {
    await db.doc(`users/${A}/blocked/${B}`).set({
      blockedAt: Timestamp.fromMillis(nowMs),
    });
  };
  await assert.rejects(
    service.getVoiceMomentMediaAccess(request(A, { momentId })),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(storage.signedGrants.length, 1);
});

test("a one-second recording publishes through the canonical draft contract", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "One second",
      durationSeconds: 1,
      requestId: "reserve-one-second",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "1000000000000001",
    size: 1024,
  });

  const finalized = await service.finalizeMomentDraft(
    request(A, {
      momentId: reserved.momentId,
      objectGeneration: "1000000000000001",
      requestId: "finalize-one-second",
    }),
  );

  assert.equal(finalized.published, true);
  const moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().durationSeconds, 1);
  assert.equal(moment.data().mediaSize, 1024);
  assert.equal(moment.data().status, "published");
});

test("unverified actors cannot reserve or finalize Voice Moment uploads", async () => {
  const service = momentService();
  await assert.rejects(
    service.reserveMomentDraft(
      request(
        A,
        {
          caption: "Unverified reserve",
          durationSeconds: 1,
          requestId: "reserve-unverified",
        },
        false,
      ),
    ),
    (error) => error.code === "failed-precondition",
  );

  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Verified reserve",
      durationSeconds: 1,
      requestId: "reserve-before-unverified-finalize",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "1000000000000002",
    size: 1024,
  });
  await assert.rejects(
    service.finalizeMomentDraft(
      request(
        A,
        {
          momentId: reserved.momentId,
          objectGeneration: "1000000000000002",
          requestId: "finalize-unverified",
        },
        false,
      ),
    ),
    (error) => error.code === "failed-precondition",
  );
  const moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().isPublished, false);
  assert.equal(moment.data().status, "uploading");
});

test("Moment creation requires an exact HTTPS public identity projection", async () => {
  const service = momentService();
  await db.doc(`publicProfiles/${A}`).delete();
  await assert.rejects(
    service.reserveMomentDraft(
      request(A, {
        caption: "No projection",
        durationSeconds: 12,
        requestId: "reserve-nopublic",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );

  await seed(A);
  await db
    .doc(`publicProfiles/${A}`)
    .update({ photoUrl: "javascript:alert(1)" });
  await assert.rejects(
    service.reserveMomentDraft(
      request(A, {
        caption: "Poisoned projection",
        durationSeconds: 12,
        requestId: "reserve-badpublic",
      }),
    ),
    (error) => error.code === "data-loss",
  );
});

test("finalize rejects forged metadata, generation, MIME and size", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Upload",
      durationSeconds: 8,
      requestId: "reserve-bad01",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: B,
    momentId: reserved.momentId,
    generation: "2001",
  });
  await assert.rejects(
    service.finalizeMomentDraft(
      request(A, {
        momentId: reserved.momentId,
        objectGeneration: "2001",
        requestId: "final-bad001",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "2002",
    contentType: "text/html",
    size: 50_000_000,
  });
  await assert.rejects(
    service.finalizeMomentDraft(
      request(A, {
        momentId: reserved.momentId,
        objectGeneration: "wrong",
        requestId: "final-bad002",
      }),
    ),
    (error) =>
      error.code === "invalid-argument" || error.code === "failed-precondition",
  );
  const moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().isPublished, false);
  assert.equal(moment.data().audioUrl, null);
});

test("upload reservation server-time window blocks distinct-id bursts but not replay", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 2, windowMs: 1_000 },
  });
  const first = request(A, {
    caption: "One",
    durationSeconds: 5,
    requestId: "reserve-limit1",
  });
  await service.reserveMomentDraft(first);
  await service.reserveMomentDraft(first);
  await service.reserveMomentDraft(
    request(A, {
      caption: "Two",
      durationSeconds: 5,
      requestId: "reserve-limit2",
    }),
  );
  await assert.rejects(
    service.reserveMomentDraft(
      request(A, {
        caption: "Three",
        durationSeconds: 5,
        requestId: "reserve-limit3",
      }),
    ),
    (error) => error.code === "resource-exhausted",
  );
  nowMs += 1_001;
  const afterWindow = await service.reserveMomentDraft(
    request(A, {
      caption: "Four",
      durationSeconds: 5,
      requestId: "reserve-limit4",
    }),
  );
  assert.match(afterWindow.momentId, /^[a-f0-9]{20}$/u);
});

test("invalid caller-selected Moment targets consume committed attempt budgets", async () => {
  const oneAttempt = { maxEvents: 1, windowMs: 60_000 };
  const service = momentService({
    like: oneAttempt,
    uploadReserve: oneAttempt,
    comment: oneAttempt,
    delete: oneAttempt,
    report: oneAttempt,
    mediaAccess: oneAttempt,
    mediaAccessHourly: { maxEvents: 20, windowMs: 60 * 60_000 },
  });
  const missingMoment = "missing-moment-cost";
  const missingComment = "missing-comment-cost";
  const operations = [
    ["like", () => service.setMomentLike(request(A, {
      liked: true,
      momentId: missingMoment,
      requestId: "cost-like-attempt",
    }))],
    ["uploadReserve", () => service.reserveVoiceCommentDraft(request(A, {
      durationSeconds: 2,
      momentId: missingMoment,
      requestId: "cost-voice-reserve",
      text: "",
    }))],
    ["comment", () => service.createMomentComment(request(A, {
      momentId: missingMoment,
      requestId: "cost-comment-attempt",
      text: "bounded",
    }))],
    ["delete", () => service.deleteMomentComment(request(A, {
      commentId: missingComment,
      momentId: missingMoment,
      requestId: "cost-comment-delete",
    }))],
    ["delete", () => service.deleteMoment(request(B, {
      momentId: missingMoment,
      requestId: "cost-moment-delete",
    }))],
    ["report", () => service.createContentReport(request(A, {
      momentId: missingMoment,
      reason: "Safety report",
      requestId: "cost-report-attempt",
      targetType: "voiceMoment",
    }, false))],
  ];

  for (const [scope, invoke] of operations) {
    await assert.rejects(
      invoke(),
      (error) => error.code !== "resource-exhausted",
      `${scope} first target denial should consume its attempt`,
    );
    await assert.rejects(
      invoke(),
      (error) => error.code === "resource-exhausted",
      `${scope} retry must stop before rereading the target`,
    );
  }

  await assert.rejects(
    service.getVoiceMomentMediaAccess(request(C, { momentId: missingMoment })),
    (error) => error.code !== "resource-exhausted",
  );
  await assert.rejects(
    service.getVoiceMomentMediaAccess(request(C, { momentId: missingMoment })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(storage.metadataReads, 0);
});

test("concurrent like intents are exactly once and never make a negative count", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const attempts = await Promise.all(
    Array.from({ length: 8 }, (_, index) =>
      service.setMomentLike(
        request(A, {
          liked: true,
          momentId,
          requestId: `like-add-${index}`,
        }),
      ),
    ),
  );
  assert.equal(attempts.filter((result) => result.changed).length, 1);
  let [moment, like] = await Promise.all([
    db.doc(`voiceMoments/${momentId}`).get(),
    db.doc(`voiceMoments/${momentId}/likes/${A}`).get(),
  ]);
  assert.equal(moment.data().likeCount, 1);
  assert.equal(like.data().userId, A);

  const removals = await Promise.all(
    Array.from({ length: 5 }, (_, index) =>
      service.setMomentLike(
        request(A, {
          liked: false,
          momentId,
          requestId: `like-del-${index}`,
        }),
      ),
    ),
  );
  assert.equal(removals.filter((result) => result.changed).length, 1);
  [moment, like] = await Promise.all([
    db.doc(`voiceMoments/${momentId}`).get(),
    db.doc(`voiceMoments/${momentId}/likes/${A}`).get(),
  ]);
  assert.equal(moment.data().likeCount, 0);
  assert.equal(like.exists, false);

  await db.doc(`voiceMoments/${momentId}/likes/${A}`).set({
    schemaVersion: 1,
    userId: A,
    momentId,
    createdAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service.setMomentLike(
      request(A, {
        liked: false,
        momentId,
        requestId: "like-negative",
      }),
    ),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.doc(`voiceMoments/${momentId}/likes/${A}`).get()).exists,
    true,
  );
});

test("comments are canonical, replay-safe and transactionally counted", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const same = request(A, {
    momentId,
    requestId: "comment-same1",
    text: "  A real comment  ",
  });
  const replayResults = await Promise.all(
    Array.from({ length: 6 }, () => service.createMomentComment(same)),
  );
  assert.equal(
    new Set(replayResults.map((result) => result.commentId)).size,
    1,
  );

  await Promise.all(
    Array.from({ length: 5 }, (_, index) =>
      service.createMomentComment(
        request(A, {
          momentId,
          requestId: `comment-many${index}`,
          text: `comment ${index}`,
        }),
      ),
    ),
  );
  const [moment, comments] = await Promise.all([
    db.doc(`voiceMoments/${momentId}`).get(),
    db.collection(`voiceMoments/${momentId}/comments`).get(),
  ]);
  assert.equal(moment.data().commentCount, 6);
  assert.equal(comments.size, 6);
  const first = comments.docs.find(
    (doc) => doc.id === replayResults[0].commentId,
  );
  assert.equal(first.data().authorName, `Public ${A}`);
  assert.equal(first.data().text, "A real comment");

  await assert.rejects(
    service.createMomentComment(
      request(A, {
        momentId,
        requestId: "comment-forge",
        text: "text",
        authorId: B,
      }),
    ),
    (error) => error.code === "invalid-argument",
  );
});

test("blocks and active sanctions prevent likes and comments", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(
    service.setMomentLike(
      request(A, {
        liked: true,
        momentId,
        requestId: "like-blocked1",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  await assert.rejects(
    service.createMomentComment(
      request(A, {
        momentId,
        requestId: "comment-block1",
        text: "blocked",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${B}/blocked/${A}`).delete();
  await db.doc(`restrictions/${A}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    service.createMomentComment(
      request(A, {
        momentId,
        requestId: "comment-muted1",
        text: "muted",
      }),
    ),
    (error) => error.code === "permission-denied",
  );
});

test("comment deletion decrements once and fails closed on corrupt counters", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const created = await service.createMomentComment(
    request(A, {
      momentId,
      requestId: "comment-delete-source",
      text: "delete me",
    }),
  );
  const deletionRequest = request(A, {
    commentId: created.commentId,
    momentId,
    requestId: "comment-delete-op1",
  });
  const deleted = await service.deleteMomentComment(deletionRequest);
  assert.deepEqual(await service.deleteMomentComment(deletionRequest), deleted);
  assert.equal(
    (
      await db
        .doc(`voiceMoments/${momentId}/comments/${created.commentId}`)
        .get()
    ).exists,
    false,
  );
  assert.equal(
    (await db.doc(`voiceMoments/${momentId}`).get()).data().commentCount,
    0,
  );

  const second = await service.createMomentComment(
    request(A, {
      momentId,
      requestId: "comment-corrupt-source",
      text: "keep me",
    }),
  );
  await db.doc(`voiceMoments/${momentId}`).update({ commentCount: 0 });
  await assert.rejects(
    service.deleteMomentComment(
      request(A, {
        commentId: second.commentId,
        momentId,
        requestId: "comment-corrupt-del",
      }),
    ),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (
      await db
        .doc(`voiceMoments/${momentId}/comments/${second.commentId}`)
        .get()
    ).exists,
    true,
  );
});

test("Moment deletion queues canonical cleanup and ignores forged storage paths", async () => {
  const service = momentService();
  const { momentId, storagePath } = await publish(service, { uid: A });
  const commentId = "0123456789abcdefabcd";
  const canonicalReply = voiceReplyStoragePath(B, momentId, commentId);
  const victimPath = "voice_moments/victim/should-not-delete.m4a";
  storage.put(canonicalReply, {
    authorId: B,
    momentId,
    commentId,
    generation: "333",
  });
  storage.put(victimPath, {
    authorId: "victim",
    momentId: "should-not-delete",
    generation: "444",
  });
  await db.doc(`voiceMoments/${momentId}/comments/${commentId}`).set({
    schemaVersion: 2,
    type: "voice",
    authorId: B,
    authorName: `Public ${B}`,
    authorPhotoUrl: null,
    text: "",
    audioUrl: "https://storage.example.invalid/reply",
    storagePath: victimPath,
    durationSeconds: 4,
    mediaGeneration: "333",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
    createdAt: Timestamp.fromMillis(nowMs),
  });
  await db.doc(`voiceMoments/${momentId}`).update({ commentCount: 1 });

  const deletion = await service.deleteMoment(
    request(A, {
      momentId,
      requestId: "moment-delete1",
    }),
  );
  const capacity = (await db.doc(`momentCapacityLedgers/${A}`).get()).data();
  assert.equal(capacity.ownerId, A);
  assert.equal(capacity.revision, 2, "publish + delete each advance the mutex");
  const outbox = await db
    .doc(`contentCleanupOutbox/${deletion.outboxId}`)
    .get();
  assert.deepEqual(outbox.data().objectPaths, [storagePath]);
  assert.equal(outbox.data().status, "pending");
  await service.processCleanupOutbox(deletion.outboxId);
  assert.ok(storage.deleted.includes(storagePath));
  assert.ok(storage.deleted.includes(canonicalReply));
  assert.equal(storage.deleted.includes(victimPath), false);
  assert.equal(storage.objects.has(victimPath), true);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).exists, false);
  assert.equal(
    (await db.doc(`contentCleanupOutbox/${deletion.outboxId}`).get()).data()
      .status,
    "completed",
  );
});

test("content reports are canonical, idempotent and DM participant-bound", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const reportRequest = request(A, {
    targetType: "voiceMoment",
    momentId,
    reason: "Harassment",
    requestId: "report-moment1",
  });
  const first = await service.createContentReport(reportRequest);
  assert.deepEqual(await service.createContentReport(reportRequest), first);
  const report = await db.doc(`reports/${first.reportId}`).get();
  assert.equal(report.data().reporterId, A);
  assert.equal(report.data().targetType, "voiceMoment");
  assert.equal(report.data().status, "open");

  const conversationRef = db.doc("conversations/mmi-report-conversation");
  await conversationRef.set({ participantIds: [A, B] });
  await conversationRef.collection("messages").doc("message-0001").set({
    senderId: B,
    content: "reported",
  });
  await assert.rejects(
    service.createContentReport(
      request(C, {
        targetType: "directMessage",
        conversationId: "mmi-report-conversation",
        messageId: "message-0001",
        reason: "Not mine",
        requestId: "report-denied1",
      }),
    ),
    (error) => error.code === "permission-denied",
  );
  const direct = await service.createContentReport(
    request(A, {
      targetType: "directMessage",
      conversationId: "mmi-report-conversation",
      messageId: "message-0001",
      reason: "Abusive",
      requestId: "report-direct1",
    }),
  );
  assert.equal(direct.created, true);
});

// ---------------------------------------------------------------------------
// Report targets that are not Moments: room chat and Club channel chat.
//
// The membership refusals below are the part that matters. A report target is
// the one input a caller fully controls, so an endpoint that answers
// "not-found" for a room or Club the caller cannot see is an existence oracle
// for private spaces. Every refusal here therefore asserts the CODE, not just
// that the call failed.
// ---------------------------------------------------------------------------

async function seedRoom(
  roomId,
  { hostId = B, visibility = "private", clubId = "" } = {},
) {
  await db.doc(`rooms/${roomId}`).set({
    hostId,
    visibility,
    ...(clubId ? { clubId } : {}),
    title: `Room ${roomId}`,
  });
  await db.doc(`rooms/${roomId}/messages/${ROOM_MESSAGE}`).set({
    senderId: hostId,
    content: "reported room message",
  });
}

async function seedClub({
  status = "active",
  deletionInProgress = false,
  ownerId = B,
} = {}) {
  await db.doc(`clubs/${REPORT_CLUB}`).set({
    ownerId,
    status,
    deletionInProgress,
    name: "Report Club",
  });
  await db.doc(`clubs/${REPORT_CLUB}/channels/${CLUB_CHANNEL}`).set({
    name: "general",
  });
  await db
    .doc(
      `clubs/${REPORT_CLUB}/channels/${CLUB_CHANNEL}/messages/${CLUB_MESSAGE}`,
    )
    .set({
      senderId: ownerId,
      clubId: REPORT_CLUB,
      content: "reported club message",
    });
}

function roomReport(uid, requestId, overrides = {}) {
  return request(uid, {
    targetType: "roomMessage",
    roomId: PRIVATE_ROOM,
    messageId: ROOM_MESSAGE,
    reason: "Harassment",
    requestId,
    ...overrides,
  });
}

function clubReport(uid, requestId, overrides = {}) {
  return request(uid, {
    targetType: "clubMessage",
    clubId: REPORT_CLUB,
    channelId: CLUB_CHANNEL,
    messageId: CLUB_MESSAGE,
    reason: "Harassment",
    requestId,
    ...overrides,
  });
}

test("reporting is not gated on email verification", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  // requireActor's default is { verified: true }; firestore.rules' own
  // reports/{reportId} create rule is deliberately NOT gated on
  // isVerified() because reporting is a safety action. The callable must
  // agree with the written policy.
  const result = await service.createContentReport(
    request(
      A,
      {
        targetType: "voiceMoment",
        momentId,
        reason: "Harassment",
        requestId: "report-unverified1",
      },
      false,
    ),
  );
  assert.equal(result.created, true);
  const report = await db.doc(`reports/${result.reportId}`).get();
  assert.equal(report.data().reporterId, A);
});

test("room messages are reportable by people who can see the room", async () => {
  const service = momentService();
  await seedRoom(PRIVATE_ROOM);

  // A private room's own host.
  const byHost = await service.createContentReport(
    roomReport(B, "report-room-host1"),
  );
  assert.equal(byHost.created, true);
  const hostReport = await db.doc(`reports/${byHost.reportId}`).get();
  assert.equal(hostReport.data().schemaVersion, 2);
  assert.equal(hostReport.data().targetType, "roomMessage");
  assert.equal(hostReport.data().roomId, PRIVATE_ROOM);
  assert.equal(hostReport.data().messageId, ROOM_MESSAGE);
  assert.equal(hostReport.data().status, "open");

  // A roomMembers row is authority on its own, exactly as the rules'
  // `|| isRoomMember(roomId)` branch on rooms/{id}/messages read is.
  await db.doc(`rooms/${PRIVATE_ROOM}/roomMembers/${A}`).set({
    userId: A,
    role: "member",
  });
  const byMember = await service.createContentReport(
    roomReport(A, "report-room-member1"),
  );
  assert.equal(byMember.created, true);

  // A host-admitted participant of a non-Club room.
  await db.doc(`rooms/${PRIVATE_ROOM}/participants/${C}`).set({
    userId: C,
    admittedBy: B,
  });
  const byParticipant = await service.createContentReport(
    roomReport(C, "report-room-participant1"),
  );
  assert.equal(byParticipant.created, true);

  // A public room's chat is previewable without joining.
  await seedRoom(PUBLIC_ROOM, { visibility: "public" });
  const byStranger = await service.createContentReport(
    roomReport(A, "report-room-public1", { roomId: PUBLIC_ROOM }),
  );
  assert.equal(byStranger.created, true);
});

test("a room message report refuses anyone who cannot read the room", async () => {
  const service = momentService();
  await seedRoom(PRIVATE_ROOM);

  // No membership of any kind.
  await assert.rejects(
    service.createContentReport(roomReport(A, "report-room-denied1")),
    (error) => error.code === "permission-denied",
  );

  // A self-forged participant row: `admittedBy` is not the current host,
  // which is exactly what isHostAdmittedRoomParticipant() refuses.
  await db.doc(`rooms/${PRIVATE_ROOM}/participants/${A}`).set({
    userId: A,
    admittedBy: A,
  });
  await assert.rejects(
    service.createContentReport(roomReport(A, "report-room-denied2")),
    (error) => error.code === "permission-denied",
  );

  // THE ORACLE TEST. A message id that does not exist in a room the
  // caller cannot read must answer permission-denied, never not-found —
  // otherwise the endpoint reports on the contents of private rooms.
  await assert.rejects(
    service.createContentReport(
      roomReport(A, "report-room-denied3", { messageId: "no-such-message" }),
    ),
    (error) => error.code === "permission-denied",
  );

  // Same for a room that does not exist at all: the caller must not be
  // able to tell a missing room from one they are not in.
  await assert.rejects(
    service.createContentReport(
      roomReport(A, "report-room-denied4", { roomId: "mmi-no-such-room" }),
    ),
    (error) => error.code === "permission-denied",
  );

  // A member reporting a message that genuinely is not there still gets
  // not-found — the oracle is closed by membership, not by hiding every
  // outcome from everybody.
  await db.doc(`rooms/${PRIVATE_ROOM}/roomMembers/${A}`).set({
    userId: A,
    role: "member",
  });
  await assert.rejects(
    service.createContentReport(
      roomReport(A, "report-room-missing1", { messageId: "no-such-message" }),
    ),
    (error) => error.code === "not-found",
  );
});

test("a Club lounge room follows canonical Club membership", async () => {
  const service = momentService();
  await seedClub();
  await seedRoom(LOUNGE_ROOM, { clubId: REPORT_CLUB });

  await assert.rejects(
    service.createContentReport(
      roomReport(A, "report-lounge-denied1", { roomId: LOUNGE_ROOM }),
    ),
    (error) => error.code === "permission-denied",
  );

  await db.doc(`clubs/${REPORT_CLUB}/members/${A}`).set({
    userId: A,
    role: "member",
  });
  const admitted = await service.createContentReport(
    roomReport(A, "report-lounge-ok1", { roomId: LOUNGE_ROOM }),
  );
  assert.equal(admitted.created, true);
});

test("Club channel messages are reportable by active Club members only", async () => {
  const service = momentService();
  await seedClub();

  await assert.rejects(
    service.createContentReport(clubReport(A, "report-club-denied1")),
    (error) => error.code === "permission-denied",
  );

  await db.doc(`clubs/${REPORT_CLUB}/members/${A}`).set({
    userId: A,
    role: "member",
  });
  const filed = await service.createContentReport(
    clubReport(A, "report-club-ok1"),
  );
  assert.equal(filed.created, true);
  const stored = await db.doc(`reports/${filed.reportId}`).get();
  assert.equal(stored.data().schemaVersion, 2);
  assert.equal(stored.data().targetType, "clubMessage");
  assert.equal(stored.data().clubId, REPORT_CLUB);
  assert.equal(stored.data().channelId, CLUB_CHANNEL);
  assert.equal(stored.data().messageId, CLUB_MESSAGE);

  // A member banned inside the Club keeps the row and loses the read.
  await db.doc(`clubs/${REPORT_CLUB}/members/${C}`).set({
    userId: C,
    role: "member",
    banned: true,
  });
  await assert.rejects(
    service.createContentReport(clubReport(C, "report-club-denied2")),
    (error) => error.code === "permission-denied",
  );

  // A membership row that names somebody else is not this caller's.
  await db.doc(`clubs/${REPORT_CLUB}/members/${B}`).set({
    userId: A,
    role: "member",
  });
  await assert.rejects(
    service.createContentReport(clubReport(B, "report-club-denied3")),
    (error) => error.code === "permission-denied",
  );

  // The same oracle test as rooms: a non-member must not learn whether a
  // Club, a channel or a message exists.
  await assert.rejects(
    service.createContentReport(
      clubReport(C, "report-club-denied4", { clubId: "mmi-no-such-club" }),
    ),
    (error) => error.code === "permission-denied",
  );
  await assert.rejects(
    service.createContentReport(
      clubReport(C, "report-club-denied5", { channelId: "no-such-channel" }),
    ),
    (error) => error.code === "permission-denied",
  );
});

test("a suspended or deleting Club stops being reportable", async () => {
  const service = momentService();
  await seedClub({ status: "suspended" });
  await db.doc(`clubs/${REPORT_CLUB}/members/${A}`).set({
    userId: A,
    role: "member",
  });
  await assert.rejects(
    service.createContentReport(clubReport(A, "report-club-suspended1")),
    (error) => error.code === "permission-denied",
  );

  await db.doc(`clubs/${REPORT_CLUB}`).update({ status: "active" });
  await db.doc(`clubs/${REPORT_CLUB}`).update({ deletionInProgress: true });
  await assert.rejects(
    service.createContentReport(clubReport(A, "report-club-deleting1")),
    (error) => error.code === "permission-denied",
  );
});

test("the new report targets reject conflicting id combinations", async () => {
  const service = momentService();
  await seedRoom(PRIVATE_ROOM);
  await seedClub();
  await db.doc(`rooms/${PRIVATE_ROOM}/roomMembers/${A}`).set({
    userId: A,
    role: "member",
  });
  await db.doc(`clubs/${REPORT_CLUB}/members/${A}`).set({
    userId: A,
    role: "member",
  });

  await assert.rejects(
    service.createContentReport(
      roomReport(A, "report-conflict1", { momentId: "smuggled" }),
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(
      roomReport(A, "report-conflict2", { clubId: REPORT_CLUB }),
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(
      clubReport(A, "report-conflict3", { roomId: PRIVATE_ROOM }),
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(
      clubReport(A, "report-conflict4", { channelId: undefined }),
    ),
    (error) => error.code === "invalid-argument",
  );
  // The pre-existing targets must stay closed against the new ids.
  await assert.rejects(
    service.createContentReport(
      request(A, {
        targetType: "voiceMoment",
        momentId: "whatever",
        roomId: PRIVATE_ROOM,
        reason: "Harassment",
        requestId: "report-conflict5",
      }),
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(
      request(A, {
        targetType: "roomMessage",
        roomId: PRIVATE_ROOM,
        reason: "Harassment",
        requestId: "report-conflict6",
      }),
    ),
    (error) => error.code === "invalid-argument",
  );
});

test("a report carries an optional bounded reporter note", async () => {
  const service = momentService();
  const { momentId } = await publish(service);

  const withNote = await service.createContentReport(
    request(A, {
      targetType: "voiceMoment",
      momentId,
      reason: "harassment",
      note: "  They named my employer.  ",
      requestId: "report-note1",
    }),
  );
  const stored = await db.doc(`reports/${withNote.reportId}`).get();
  assert.equal(stored.data().note, "They named my employer.");

  // Absent and empty both persist as "", the same shape the v1
  // client-written path uses, so one Moderation Center field renders both.
  const withoutNote = await service.createContentReport(
    request(C, {
      targetType: "voiceMoment",
      momentId,
      reason: "harassment",
      requestId: "report-note2",
    }),
  );
  assert.equal(
    (await db.doc(`reports/${withoutNote.reportId}`).get()).data().note,
    "",
  );

  await assert.rejects(
    service.createContentReport(
      request(B, {
        targetType: "voiceMoment",
        momentId,
        reason: "harassment",
        note: "x".repeat(301),
        requestId: "report-note3",
      }),
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(
      request(B, {
        targetType: "voiceMoment",
        momentId,
        reason: "harassment",
        note: 42,
        requestId: "report-note4",
      }),
    ),
    (error) => error.code === "invalid-argument",
  );
});

test("the operation identity of an existing report target is unchanged", async () => {
  // REGRESSION PIN, not a new behaviour. createContentReport is deployed
  // and live, so every report already filed has a ledger entry whose
  // inputHash was computed over exactly these six keys. Adding roomId,
  // clubId, channelId or note to the hashed input for a target that does
  // not use them would silently re-key every one of those ledgers: the
  // next replay of an already-filed report would stop replaying and start
  // answering already-exists. This asserts the composition, so that
  // cannot happen by accident.
  const service = momentService();
  const { momentId } = await publish(service);
  const result = await service.createContentReport(
    request(A, {
      targetType: "voiceMoment",
      momentId,
      reason: "Harassment",
      requestId: "report-hashpin1",
    }),
  );
  const identity = operationIdentity("content.report", A, "report-hashpin1", {
    reason: "Harassment",
    targetType: "voiceMoment",
    conversationId: null,
    messageId: null,
    momentId,
    commentId: null,
  });
  const ledger = await db.doc(`integrityOperationLedgers/${identity.id}`).get();
  assert.equal(ledger.exists, true);
  assert.equal(ledger.data().inputHash, identity.inputHash);
  assert.deepEqual(ledger.data().result, result);
});

test("comment and like distinct-id bursts are independently rate limited", async () => {
  const service = momentService({
    comment: { maxEvents: 2, windowMs: 1_000 },
    like: { maxEvents: 2, windowMs: 1_000 },
  });
  const { momentId } = await publish(service);
  await service.createMomentComment(
    request(A, {
      momentId,
      requestId: "rate-comment1",
      text: "one",
    }),
  );
  await service.createMomentComment(
    request(A, {
      momentId,
      requestId: "rate-comment2",
      text: "two",
    }),
  );
  await assert.rejects(
    service.createMomentComment(
      request(A, {
        momentId,
        requestId: "rate-comment3",
        text: "three",
      }),
    ),
    (error) => error.code === "resource-exhausted",
  );
  await service.setMomentLike(
    request(A, {
      liked: true,
      momentId,
      requestId: "rate-like001",
    }),
  );
  await service.setMomentLike(
    request(A, {
      liked: true,
      momentId,
      requestId: "rate-like002",
    }),
  );
  await assert.rejects(
    service.setMomentLike(
      request(A, {
        liked: true,
        momentId,
        requestId: "rate-like003",
      }),
    ),
    (error) => error.code === "resource-exhausted",
  );
});

test("canonical comment IDs are stable but scoped by actor and parent", () => {
  assert.equal(
    canonicalCommentId(A, "moment-0001", "request-0001"),
    canonicalCommentId(A, "moment-0001", "request-0001"),
  );
  assert.notEqual(
    canonicalCommentId(A, "moment-0001", "request-0001"),
    canonicalCommentId(B, "moment-0001", "request-0001"),
  );
});

test("voice comments use expiring draft-first reservations and exact-once finalize", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const reserved = await service.reserveVoiceCommentDraft(
    request(A, {
      durationSeconds: 7,
      momentId,
      requestId: "voice-reserve1",
      text: "voice reply",
    }),
  );
  assert.equal(
    reserved.storagePath,
    voiceReplyStoragePath(A, momentId, reserved.commentId),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    commentId: reserved.commentId,
    momentId,
    generation: "7001",
  });
  const finalizeRequest = request(A, {
    commentId: reserved.commentId,
    momentId,
    objectGeneration: "7001",
    requestId: "voice-finalize1",
  });
  const finalized = await service.finalizeVoiceCommentDraft(finalizeRequest);
  assert.deepEqual(
    await service.finalizeVoiceCommentDraft(finalizeRequest),
    finalized,
  );
  const comment = await db
    .doc(`voiceMoments/${momentId}/comments/${reserved.commentId}`)
    .get();
  assert.equal(comment.data().schemaVersion, 2);
  assert.equal(comment.data().type, "voice");
  assert.equal(comment.data().authorName, `Public ${A}`);
  assert.equal(comment.data().mediaGeneration, "7001");
  assert.equal(comment.data().audioUrl, null);
  assert.equal(
    (await db.doc(`voiceMomentUploadReservations/${reserved.commentId}`).get())
      .exists,
    false,
  );
  assert.equal(
    (await db.doc(`voiceMoments/${momentId}`).get()).data().commentCount,
    1,
  );
  const access = await service.getVoiceMomentMediaAccess(
    request(C, {
      momentId,
      commentId: reserved.commentId,
    }),
  );
  assert.equal(access.mediaGeneration, "7001");
  assert.equal(storage.signedGrants.at(-1).path, reserved.storagePath);
  const signedGrantCount = storage.signedGrants.length;
  await db.doc(`users/${C}/blocked/${A}`).set({
    blockedAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service.getVoiceMomentMediaAccess(
      request(C, {
        momentId,
        commentId: reserved.commentId,
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(storage.signedGrants.length, signedGrantCount);

  await db.doc(`users/${C}/blocked/${A}`).delete();
  await db.doc(`users/${A}/blocked/${C}`).set({
    blockedAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service.getVoiceMomentMediaAccess(
      request(C, {
        momentId,
        commentId: reserved.commentId,
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(storage.signedGrants.length, signedGrantCount);

  await db.doc(`users/${A}/blocked/${C}`).delete();
  await db.doc(`restrictions/${A}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    service.getVoiceMomentMediaAccess(
      request(C, {
        momentId,
        commentId: reserved.commentId,
      }),
    ),
    (error) => error.code === "permission-denied",
  );
  assert.equal(storage.signedGrants.length, signedGrantCount);
});

test("generic cleanup worker removes private direct-message attachment objects", async () => {
  const conversationId = "direct-cleanup-conversation";
  const messageId = `m_${"d".repeat(40)}`;
  const objectPath = `message_attachments/${A}/${conversationId}/${messageId}.jpg`;
  storage.objects.set(objectPath, {
    contentType: "image/jpeg",
    generation: "1",
    size: "2048",
    metadata: {},
  });
  const outboxId = "direct-cleanup-outbox";
  await db.doc(`contentCleanupOutbox/${outboxId}`).set({
    schemaVersion: 1,
    kind: "directMessageAttachment",
    rootPath: `conversations/${conversationId}/messages/${messageId}`,
    objectPaths: [objectPath],
    status: "pending",
    attemptCount: 0,
    requestedBy: A,
    requestedReason: "authorDeletedMessage",
    createdAt: Timestamp.fromMillis(nowMs),
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  const result = await momentService().processCleanupOutbox(outboxId);
  assert.equal(result.completed, true);
  assert.deepEqual(storage.deleted, [objectPath]);
  assert.equal(storage.objects.has(objectPath), false);
});

test("expired direct video reservations clean every canonical video format", async () => {
  const directService = createDirectMessagingService({
    db,
    Timestamp,
    storage,
    clock: () => nowMs,
  });
  const fixtures = [
    { contentType: "video/mp4", extension: "mp4", hex: "a" },
    { contentType: "video/quicktime", extension: "mov", hex: "b" },
    { contentType: "video/webm", extension: "webm", hex: "c" },
  ];

  for (const fixture of fixtures) {
    const conversationId = `direct-video-cleanup-${fixture.extension}`;
    const messageId = `m_${fixture.hex.repeat(40)}`;
    const objectPath = directMediaStoragePath(
      A,
      conversationId,
      messageId,
      "video",
      fixture.contentType,
    );
    storage.objects.set(objectPath, {
      contentType: fixture.contentType,
      generation: "1",
      size: "4096",
      metadata: {},
    });
    await db.doc(`directMessageUploadReservations/${messageId}`).set({
      schemaVersion: 1,
      ownerId: A,
      conversationId,
      messageId,
      storagePath: objectPath,
      type: "video",
      contentType: fixture.contentType,
      status: "uploading",
      expiresAt: Timestamp.fromMillis(nowMs - 1),
    });
  }

  const expired = await directService.expireAbandonedAttachmentReservations({
    limit: 10,
  });
  assert.deepEqual(expired.expired.sort(), fixtures.map(
    (fixture) => `m_${fixture.hex.repeat(40)}`,
  ));
  assert.deepEqual(expired.malformed, []);

  const outboxes = await db
    .collection("contentCleanupOutbox")
    .where("requestedReason", "==", "expiredUploadReservation")
    .get();
  assert.equal(outboxes.size, fixtures.length);
  for (const outbox of outboxes.docs) {
    const [objectPath] = outbox.data().objectPaths;
    const result = await momentService().processCleanupOutbox(outbox.id);
    assert.equal(result.completed, true);
    assert.equal(storage.objects.has(objectPath), false);
  }
});

test("direct video cleanup rejects noncanonical extensions and paths", async () => {
  const messageId = `m_${"d".repeat(40)}`;
  const conversationId = "direct-video-cleanup-denial";
  const canonicalPrefix = `message_attachments/${A}/${conversationId}/${messageId}`;
  const maliciousPaths = [
    `${canonicalPrefix}.exe`,
    `message_attachments/${B}/${conversationId}/${messageId}.mov`,
    `${canonicalPrefix}.mov/escape`,
  ];

  for (const [index, objectPath] of maliciousPaths.entries()) {
    storage.objects.set(objectPath, {
      contentType: "video/quicktime",
      generation: "1",
      size: "4096",
      metadata: {},
    });
    const outboxId = `direct-video-cleanup-denial-${index}`;
    await db.doc(`contentCleanupOutbox/${outboxId}`).set({
      schemaVersion: 1,
      kind: "directMessageAttachmentReservation",
      rootPath: `directMessageUploadReservations/${messageId}`,
      objectPaths: [objectPath],
      status: "pending",
      attemptCount: 0,
      requestedBy: A,
      requestedReason: "expiredUploadReservation",
      createdAt: Timestamp.fromMillis(nowMs),
      updatedAt: Timestamp.fromMillis(nowMs),
    });
    await assert.rejects(
      momentService().processCleanupOutbox(outboxId),
      (error) => error.code === "data-loss",
    );
    assert.equal(storage.objects.has(objectPath), true);
    assert.equal(storage.deleted.includes(objectPath), false);
  }
});

test("expired voice reservation cannot finalize and scheduler deletes its orphan", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const reserved = await service.reserveVoiceCommentDraft(
    request(A, {
      durationSeconds: 7,
      momentId,
      requestId: "voice-expired1",
      text: "expired",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    commentId: reserved.commentId,
    momentId,
    generation: "7002",
  });
  nowMs += 31 * 60_000;
  await assert.rejects(
    service.finalizeVoiceCommentDraft(
      request(A, {
        commentId: reserved.commentId,
        momentId,
        objectGeneration: "7002",
        requestId: "voice-exp-fin1",
      }),
    ),
    (error) => error.code === "failed-precondition",
  );
  const expired = await service.expireAbandonedVoiceCommentDrafts({
    limit: 10,
  });
  assert.deepEqual(expired.expired, [reserved.commentId]);
  assert.equal(
    (await db.doc(`voiceMomentUploadReservations/${reserved.commentId}`).get())
      .exists,
    false,
  );
  const outboxes = await db
    .collection("contentCleanupOutbox")
    .where("requestedReason", "==", "expiredUploadReservation")
    .get();
  assert.equal(outboxes.size, 1);
  await service.processCleanupOutbox(outboxes.docs[0].id);
  assert.equal(storage.objects.has(reserved.storagePath), false);
  assert.deepEqual(
    await service.expireAbandonedVoiceCommentDrafts({ limit: 10 }),
    { expired: [], malformed: [], nextCursor: null, hasMore: false },
  );
});

test("the same invalid root finalize retry consumes quota before every Storage read", async () => {
  const service = momentService({
    finalize: { maxEvents: 2, windowMs: 60_000 },
  });
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "preflight",
      durationSeconds: 8,
      requestId: "preflight-res1",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: B,
    momentId: reserved.momentId,
    generation: "8801",
  });
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await assert.rejects(
      service.finalizeMomentDraft(
        request(A, {
          momentId: reserved.momentId,
          objectGeneration: "8801",
          requestId: "preflight-bad1",
        }),
      ),
      (error) => error.code === "failed-precondition",
    );
  }
  assert.equal(storage.metadataReads, 2);
  await assert.rejects(
    service.finalizeMomentDraft(
      request(A, {
        momentId: reserved.momentId,
        objectGeneration: "8801",
        requestId: "preflight-bad1",
      }),
    ),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(storage.metadataReads, 2);
});

test("completed root finalize replay is free and performs no second Storage read", async () => {
  const service = momentService({
    finalize: { maxEvents: 1, windowMs: 60_000 },
  });
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "completed preflight",
      durationSeconds: 8,
      requestId: "preflight-done-res1",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "8802",
  });
  const finalizeRequest = request(A, {
    momentId: reserved.momentId,
    objectGeneration: "8802",
    requestId: "preflight-done-fin1",
  });
  const first = await service.finalizeMomentDraft(finalizeRequest);
  assert.equal(storage.metadataReads, 1);
  assert.deepEqual(await service.finalizeMomentDraft(finalizeRequest), first);
  assert.equal(storage.metadataReads, 1);
});

test("the same invalid voice-reply finalize retry is bounded before Storage", async () => {
  const service = momentService({
    finalize: { maxEvents: 2, windowMs: 60_000 },
  });
  const { momentId } = await publish(service, {
    uid: B,
    reserveRequestId: "reply-quota-parent-r1",
    finalizeRequestId: "reply-quota-parent-f1",
  });
  const reserved = await service.reserveVoiceCommentDraft(
    request(A, {
      durationSeconds: 5,
      momentId,
      requestId: "reply-quota-res1",
      text: "bounded reply",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: B,
    commentId: reserved.commentId,
    momentId,
    generation: "8803",
  });
  const baselineReads = storage.metadataReads;
  const finalizeRequest = request(A, {
    commentId: reserved.commentId,
    momentId,
    objectGeneration: "8803",
    requestId: "reply-quota-fin1",
  });
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await assert.rejects(
      service.finalizeVoiceCommentDraft(finalizeRequest),
      (error) => error.code === "failed-precondition",
    );
  }
  assert.equal(storage.metadataReads, baselineReads + 2);
  await assert.rejects(
    service.finalizeVoiceCommentDraft(finalizeRequest),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(storage.metadataReads, baselineReads + 2);
});

test("completed voice-reply finalize replay is free and skips Storage", async () => {
  const service = momentService({
    finalize: { maxEvents: 1, windowMs: 60_000 },
  });
  const { momentId } = await publish(service, {
    uid: B,
    reserveRequestId: "reply-replay-parent-r1",
    finalizeRequestId: "reply-replay-parent-f1",
  });
  const reserved = await service.reserveVoiceCommentDraft(
    request(A, {
      durationSeconds: 5,
      momentId,
      requestId: "reply-replay-res1",
      text: "replayed reply",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    commentId: reserved.commentId,
    momentId,
    generation: "8804",
  });
  const finalizeRequest = request(A, {
    commentId: reserved.commentId,
    momentId,
    objectGeneration: "8804",
    requestId: "reply-replay-fin1",
  });
  const first = await service.finalizeVoiceCommentDraft(finalizeRequest);
  const readsAfterFirst = storage.metadataReads;
  assert.deepEqual(
    await service.finalizeVoiceCommentDraft(finalizeRequest),
    first,
  );
  assert.equal(storage.metadataReads, readsAfterFirst);
});

test("cleanup paginates comments and quarantines malformed voice identities", async () => {
  const service = momentService({}, { cleanupPageSize: 2 });
  const { momentId, storagePath } = await publish(service, { uid: A });
  for (let index = 0; index < 5; index += 1) {
    const commentId = `${index}`.padStart(20, "0");
    const authorId = index === 2 ? "bad/author" : B;
    await db.doc(`voiceMoments/${momentId}/comments/${commentId}`).set({
      schemaVersion: 2,
      type: "voice",
      authorId,
      authorName: "Voice",
      authorPhotoUrl: null,
      text: "",
      audioUrl: "https://storage.example.invalid/reply",
      storagePath: "forged/path.m4a",
      durationSeconds: 4,
      mediaGeneration: "1",
      mediaSize: 4096,
      mediaContentType: "audio/mp4",
      createdAt: Timestamp.fromMillis(nowMs),
    });
    if (authorId === B) {
      storage.put(voiceReplyStoragePath(B, momentId, commentId), {
        authorId: B,
        commentId,
        momentId,
        generation: "1",
      });
    }
  }
  await db.doc(`voiceMoments/${momentId}`).update({ commentCount: 5 });
  const deletion = await service.deleteMoment(
    request(A, {
      momentId,
      requestId: "delete-paged1",
    }),
  );
  let result = await service.processCleanupOutbox(deletion.outboxId);
  assert.equal(result.completed, false);
  result = await service.processCleanupOutbox(deletion.outboxId);
  assert.equal(result.completed, false);
  result = await service.processCleanupOutbox(deletion.outboxId);
  assert.equal(result.completed, true);
  assert.ok(storage.deleted.includes(storagePath));
  const quarantine = await db
    .collection("contentCleanupQuarantine")
    .where("outboxId", "==", deletion.outboxId)
    .get();
  assert.equal(quarantine.size, 1);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).exists, false);
});

test("abandoned draft query cannot be starved by fresh low-id drafts", async () => {
  const service = momentService();
  const freshTime = Timestamp.fromMillis(nowMs);
  for (let index = 0; index < 5; index += 1) {
    const id = `${index}`.padStart(20, "0");
    await db.doc(`voiceMoments/${id}`).set({
      status: "uploading",
      isPublished: false,
      isDeleted: false,
      authorId: A,
      storagePath: momentStoragePath(A, id),
      createdAt: freshTime,
    });
  }
  const oldId = "ffffffffffffffffffff";
  await db.doc(`voiceMoments/${oldId}`).set({
    status: "uploading",
    isPublished: false,
    isDeleted: false,
    authorId: A,
    storagePath: momentStoragePath(A, oldId),
    createdAt: Timestamp.fromMillis(nowMs - 2 * 60 * 60_000),
  });
  const result = await service.expireAbandonedMomentDrafts({
    olderThanMs: 60 * 60_000,
    limit: 2,
  });
  assert.deepEqual(result.expired, [oldId]);
  assert.equal(
    (await db.doc(`voiceMoments/${oldId}`).get()).data().status,
    "deleting",
  );
  for (let index = 0; index < 5; index += 1) {
    const id = `${index}`.padStart(20, "0");
    assert.equal(
      (await db.doc(`voiceMoments/${id}`).get()).data().status,
      "uploading",
    );
  }
});

test("like and comment counter overflow fail without edge creation", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  await db.doc(`voiceMoments/${momentId}`).update({
    likeCount: Number.MAX_SAFE_INTEGER,
  });
  await assert.rejects(
    service.setMomentLike(
      request(A, {
        liked: true,
        momentId,
        requestId: "like-overflow1",
      }),
    ),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.doc(`voiceMoments/${momentId}/likes/${A}`).get()).exists,
    false,
  );
  await db.doc(`voiceMoments/${momentId}`).update({
    likeCount: 0,
    commentCount: Number.MAX_SAFE_INTEGER,
  });
  await assert.rejects(
    service.createMomentComment(
      request(A, {
        momentId,
        requestId: "comm-overflow1",
        text: "must fail",
      }),
    ),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.collection(`voiceMoments/${momentId}/comments`).get()).size,
    0,
  );
});

test("legacy Moment and child schemas migrate in place before secure deletion", async () => {
  const service = momentService();
  const momentId = "1234567890abcdefghij";
  const commentId = "abcdefghij1234567890";
  const path = momentStoragePath(B, momentId);
  storage.put(path, {
    authorId: B,
    momentId,
    generation: "9101",
  });
  await db.doc(`voiceMoments/${momentId}`).set({
    authorId: B,
    authorName: "Forged Legacy Name",
    authorPhotoUrl: null,
    caption: "Legacy",
    audioUrl: "https://storage.example.invalid/legacy",
    storagePath: path,
    durationSeconds: 10,
    likeCount: 999,
    commentCount: 999,
    replyToMomentId: null,
    isPublished: true,
    createdAt: Timestamp.fromMillis(nowMs - 10_000),
    updatedAt: Timestamp.fromMillis(nowMs - 5_000),
    publishedAt: Timestamp.fromMillis(nowMs - 5_000),
  });
  await db.doc(`voiceMoments/${momentId}/comments/${commentId}`).set({
    type: "text",
    authorId: A,
    authorName: "Legacy Alice",
    authorPhotoUrl: null,
    text: "legacy comment",
    createdAt: Timestamp.fromMillis(nowMs - 1_000),
  });
  await db.doc(`voiceMoments/${momentId}/likes/${A}`).set({
    userId: A,
    createdAt: Timestamp.fromMillis(nowMs - 1_000),
  });
  const migrator = createMomentMigrationService({
    db,
    FieldPath,
    Timestamp,
    storage,
    clock: () => nowMs,
  });
  assert.equal(
    (await migrator.migrateMoment({ momentId, dryRun: true })).status,
    "ready",
  );
  const applied = await migrator.migrateMoment({ momentId, dryRun: false });
  assert.equal(applied.status, "migrated");
  const migrated = await db.doc(`voiceMoments/${momentId}`).get();
  assert.equal(migrated.data().schemaVersion, 2);
  assert.equal(migrated.data().authorName, `Public ${B}`);
  assert.equal(migrated.data().likeCount, 1);
  assert.equal(migrated.data().commentCount, 1);
  assert.equal(
    (
      await db.doc(`voiceMoments/${momentId}/comments/${commentId}`).get()
    ).data().schemaVersion,
    2,
  );
  assert.equal(
    (await migrator.migrateMoment({ momentId, dryRun: false })).status,
    "alreadyMigrated",
  );

  await service.deleteMomentComment(
    request(A, {
      commentId,
      momentId,
      requestId: "legacy-comment-delete",
    }),
  );
  const deletion = await service.deleteMoment(
    request(B, {
      momentId,
      requestId: "legacy-moment-delete",
    }),
  );
  await service.processCleanupOutbox(deletion.outboxId);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).exists, false);
});

test("media hardening preserves an expired Moment deadline and lifecycle", async () => {
  const service = momentService();
  const { momentId, storagePath } = await publish(service, {
    uid: B,
    generation: "9151",
  });
  const expiresAt = Timestamp.fromMillis(nowMs - 1_000);
  await db.doc(`voiceMoments/${momentId}`).update({
    audioUrl: "https://firebasestorage.googleapis.com/legacy-token",
    expiresAt,
    isPublished: false,
    status: "expired",
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  storage.objects.get(storagePath).metadata.firebaseStorageDownloadTokens =
    "legacy-token";

  const migrator = createMomentMigrationService({
    db,
    FieldPath,
    Timestamp,
    storage,
    clock: () => nowMs,
  });
  assert.equal(
    (await migrator.migrateMoment({ momentId, dryRun: true })).status,
    "ready",
  );
  assert.equal(
    (await migrator.migrateMoment({ momentId, dryRun: false })).status,
    "migrated",
  );
  const migrated = (await db.doc(`voiceMoments/${momentId}`).get()).data();
  assert.equal(migrated.audioUrl, null);
  assert.equal(migrated.status, "expired");
  assert.equal(migrated.isPublished, false);
  assert.equal(migrated.expiresAt.toMillis(), expiresAt.toMillis());
  assert.equal(migrated.mediaGeneration, "9151");
  assert.equal(
    storage.objects.get(storagePath).metadata.firebaseStorageDownloadTokens,
    undefined,
  );
  assert.equal(
    (await migrator.migrateMoment({ momentId, dryRun: false })).status,
    "alreadyMigrated",
  );
});

test("a migration conflict still revokes every referenced reply token", async () => {
  const service = momentService();
  const { momentId } = await publish(service, {
    uid: B,
    generation: "9152",
  });
  const replyIds = ["11111111111111111111", "22222222222222222222"];
  for (const [index, commentId] of replyIds.entries()) {
    const authorId = index === 0 ? A : C;
    const storagePath = voiceReplyStoragePath(authorId, momentId, commentId);
    storage.put(storagePath, {
      authorId,
      commentId,
      momentId,
      generation: `916${index}`,
    });
    await db.doc(`voiceMoments/${momentId}/comments/${commentId}`).set({
      schemaVersion: 2,
      type: "voice",
      authorId,
      authorName: `Public ${authorId}`,
      authorPhotoUrl: `https://public.invalid/${authorId}.png`,
      text: "reply",
      audioUrl: "https://firebasestorage.googleapis.com/legacy-token",
      storagePath,
      durationSeconds: 7,
      mediaGeneration: `916${index}`,
      mediaSize: 4096,
      mediaContentType: "audio/mp4",
      createdAt: Timestamp.fromMillis(nowMs),
    });
  }
  await db.doc(`voiceMoments/${momentId}`).update({ commentCount: 2 });

  const migrator = createMomentMigrationService({
    db,
    FieldPath,
    Timestamp,
    storage,
    clock: () => nowMs,
  });
  const result = await migrator.migrateMoment({
    momentId,
    dryRun: false,
    maxRelated: 1,
  });
  assert.equal(result.status, "conflict");
  assert.equal(result.mediaHardening.revoked, 2);
  for (const [index, commentId] of replyIds.entries()) {
    const authorId = index === 0 ? A : C;
    const storagePath = voiceReplyStoragePath(authorId, momentId, commentId);
    assert.equal(
      storage.objects.get(storagePath).metadata.firebaseStorageDownloadTokens,
      undefined,
    );
  }
});

test("Moment migration aborts atomically when a child changes after inspection", async () => {
  const momentId = "fedcba98765432100123";
  const commentId = "00112233445566778899";
  const path = momentStoragePath(C, momentId);
  storage.put(path, {
    authorId: C,
    momentId,
    generation: "9201",
  });
  const rootRef = db.doc(`voiceMoments/${momentId}`);
  const commentRef = rootRef.collection("comments").doc(commentId);
  await rootRef.set({
    authorId: C,
    authorName: "Legacy C",
    authorPhotoUrl: null,
    caption: "Atomic legacy",
    audioUrl: "https://forged.invalid/audio",
    storagePath: path,
    durationSeconds: 15,
    likeCount: 0,
    commentCount: 1,
    replyToMomentId: null,
    isPublished: true,
    createdAt: Timestamp.fromMillis(nowMs - 10_000),
    updatedAt: Timestamp.fromMillis(nowMs - 5_000),
    publishedAt: Timestamp.fromMillis(nowMs - 5_000),
  });
  await commentRef.set({
    type: "text",
    authorId: A,
    authorName: "Legacy A",
    authorPhotoUrl: null,
    text: "before race",
    createdAt: Timestamp.fromMillis(nowMs - 1_000),
  });
  const migrator = createMomentMigrationService({
    db,
    FieldPath,
    Timestamp,
    storage,
    clock: () => nowMs,
    beforeApply: async () => commentRef.update({ text: "raced" }),
  });
  await assert.rejects(
    migrator.migrateMoment({ momentId, dryRun: false }),
    (error) => error.code === "aborted",
  );
  assert.equal((await rootRef.get()).data().schemaVersion, undefined);
  const comment = (await commentRef.get()).data();
  assert.equal(comment.schemaVersion, undefined);
  assert.equal(comment.text, "raced");
});

test("cleanup worker rejects a forged outbox instead of becoming a delete oracle", async () => {
  const service = momentService();
  const victimPath = "voice_moments/victim/valuable.m4a";
  storage.put(victimPath, {
    authorId: "victim",
    momentId: "valuable",
    generation: "1",
  });
  const outboxId = "forged-cleanup-entry";
  await db.doc(`contentCleanupOutbox/${outboxId}`).set({
    schemaVersion: 1,
    kind: "voiceMoment",
    rootPath: "voiceMoments/legitimateMoment",
    objectPaths: [victimPath],
    status: "pending",
    attemptCount: 0,
    requestedBy: A,
    createdAt: Timestamp.fromMillis(nowMs),
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service.processCleanupOutbox(outboxId),
    (error) => error.code === "data-loss",
  );
  assert.equal(storage.objects.has(victimPath), true);
  await db.doc(`contentCleanupOutbox/${outboxId}`).delete();
});

// ---------------------------------------------------------------------------
// 24-hour story expiry (2026-08). The contract both product halves build to:
// finalize stamps `expiresAt` exactly `createdAt + 24h`, an author holds at
// most 10 simultaneously active Moments, and a Moment the scheduled sweep
// has flipped to `status: "expired"` refuses new engagement while its author
// keeps the right to delete it. The literal 10 and 24h below are the
// contract's numbers on purpose — they must not silently follow a constant.
// ---------------------------------------------------------------------------

const DAY_MS = 24 * 60 * 60 * 1000;

test("finalize stamps expiresAt exactly 24 hours after the stored createdAt", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Expiring story",
      durationSeconds: 8,
      requestId: "reserve-expiry-01",
    }),
  );
  const reservedAtMs = nowMs;

  // Publish 47 minutes later. The deadline must anchor on the STORED
  // createdAt, not on the finalize request's clock — the client derives
  // chain order and the countdown badge from the exact equality
  // `expiresAt == createdAt + 24h`, so a drift here is a visible bug.
  nowMs += 47 * 60_000;
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "77001",
  });
  const finalized = await service.finalizeMomentDraft(
    request(A, {
      momentId: reserved.momentId,
      objectGeneration: "77001",
      requestId: "finalize-expiry-01",
    }),
  );
  assert.equal(finalized.published, true);

  const moment = (
    await db.doc(`voiceMoments/${reserved.momentId}`).get()
  ).data();
  assert.equal(moment.createdAt.toMillis(), reservedAtMs);
  assert.ok(moment.expiresAt instanceof Timestamp, "expiresAt is stamped");
  assert.equal(
    moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
    DAY_MS,
    "expiresAt is exactly createdAt + 24h",
  );

  // Replay must return the stored result without moving the deadline.
  await service.finalizeMomentDraft(
    request(A, {
      momentId: reserved.momentId,
      objectGeneration: "77001",
      requestId: "finalize-expiry-01",
    }),
  );
  const replayed = (
    await db.doc(`voiceMoments/${reserved.momentId}`).get()
  ).data();
  assert.equal(replayed.expiresAt.toMillis(), moment.expiresAt.toMillis());
});

test("a full active shelf consumes reserve quota before its exact cap query", async () => {
  const batch = db.batch();
  for (let index = 0; index < 10; index += 1) {
    batch.set(db.doc(`voiceMoments/quota-cap-${index}`), {
      authorId: A,
      isPublished: true,
    });
  }
  await batch.commit();
  const service = momentService({
    uploadReserve: { maxEvents: 2, windowMs: 60_000 },
  });
  const reserveRequest = request(A, {
    caption: "Quota-bound eleventh",
    durationSeconds: 5,
    requestId: "quota-cap-reserve1",
  });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    await assert.rejects(
      service.reserveMomentDraft(reserveRequest),
      (error) =>
        error.code === "resource-exhausted" && /10 active/u.test(error.message),
    );
  }
  const rate = await db
    .collection("privateRateLimits")
    .where("ownerId", "==", A)
    .where("scope", "==", "moment.uploadReserve")
    .get();
  assert.equal(rate.size, 1);
  assert.equal(rate.docs[0].data().count, 2);

  await assert.rejects(
    service.reserveMomentDraft(reserveRequest),
    (error) =>
      error.code === "resource-exhausted" &&
      /Too many requests/u.test(error.message),
  );

  // The same logical reserve may succeed once both the quota window and a
  // capacity slot have genuinely opened.
  nowMs += 60_001;
  await db.doc("voiceMoments/quota-cap-0").delete();
  const reserved = await service.reserveMomentDraft(reserveRequest);
  assert.equal(reserved.created, true);
});

test("the active-story cap refuses an eleventh live Moment and frees on expiry", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
    finalize: { maxEvents: 100, windowMs: 60_000 },
  });

  // One story published at T0, nine more two hours later, so exactly one
  // of the ten expires first.
  await publish(service, {
    uid: A,
    reserveRequestId: "cap-r-00",
    finalizeRequestId: "cap-f-00",
    generation: "80000",
  });
  nowMs += 2 * 60 * 60_000;
  for (let index = 1; index < 10; index += 1) {
    const suffix = String(index).padStart(2, "0");
    await publish(service, {
      uid: A,
      reserveRequestId: `cap-r-${suffix}`,
      finalizeRequestId: `cap-f-${suffix}`,
      generation: `800${suffix}`,
    });
  }

  await assert.rejects(
    service.reserveMomentDraft(
      request(A, {
        caption: "Eleventh story",
        durationSeconds: 5,
        requestId: "cap-r-10",
      }),
    ),
    (error) =>
      error.code === "resource-exhausted" && /10 active/u.test(error.message),
    "the eleventh reserve is refused while ten stories are live",
  );

  // Another author is not affected by A's cap.
  const other = await service.reserveMomentDraft(
    request(B, {
      caption: "Someone else's story",
      durationSeconds: 5,
      requestId: "cap-r-other",
    }),
  );
  assert.equal(other.created, true);

  // T0 + 24h + 1min: only the FIRST story has expired (the other nine run
  // until T0 + 26h), so exactly one active slot is free. The earlier refused
  // attempt was metered, but its quota window has also elapsed, so the same
  // logical request may now succeed safely.
  nowMs += 22 * 60 * 60_000 + 60_000;
  const eleventh = await service.reserveMomentDraft(
    request(A, {
      caption: "Eleventh story",
      durationSeconds: 5,
      requestId: "cap-r-10",
    }),
  );
  assert.equal(eleventh.created, true);
});

test("unpublished drafts do not count against the active-story cap", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
  });
  // Eleven reservations, none finalized: the cap counts LIVE stories, not
  // reservations, so every one of these must pass.
  for (let index = 0; index < 11; index += 1) {
    const reserved = await service.reserveMomentDraft(
      request(A, {
        caption: `Draft ${index}`,
        durationSeconds: 5,
        requestId: `draft-cap-${String(index).padStart(2, "0")}`,
      }),
    );
    assert.equal(reserved.created, true);
  }
});

test("concurrent finalize caps eleven pre-reserved drafts at ten active Moments", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
    finalize: { maxEvents: 100, windowMs: 60_000 },
  });
  const drafts = [];

  // Reservation deliberately ignores unpublished drafts. Reserve every
  // recording first to reproduce the old reserve-many/finalize-many bypass.
  for (let index = 0; index < 11; index += 1) {
    const suffix = String(index).padStart(2, "0");
    const reserved = await service.reserveMomentDraft(
      request(A, {
        caption: `Prepared draft ${index}`,
        durationSeconds: 5,
        requestId: `final-cap-r-${suffix}`,
      }),
    );
    const generation = `87${suffix}`;
    storage.put(reserved.storagePath, {
      authorId: A,
      momentId: reserved.momentId,
      generation,
    });
    drafts.push({ ...reserved, generation, suffix });
  }

  // Nine fill all but one slot. The cap is re-evaluated in every publish
  // transaction, and the current unpublished draft is not counted as an
  // already-active Moment.
  for (const draft of drafts.slice(0, 9)) {
    const result = await service.finalizeMomentDraft(
      request(A, {
        momentId: draft.momentId,
        objectGeneration: draft.generation,
        requestId: `final-cap-f-${draft.suffix}`,
      }),
    );
    assert.equal(result.published, true);
  }

  // Both remaining drafts race for the final slot. The query read belongs to
  // the same transaction as the publish write, so exactly one wins and the
  // other retries against a full shelf before returning resource-exhausted.
  const boundaryResults = await Promise.allSettled(
    drafts.slice(9).map((draft) =>
      service.finalizeMomentDraft(
        request(A, {
          momentId: draft.momentId,
          objectGeneration: draft.generation,
          requestId: `final-cap-f-${draft.suffix}`,
        }),
      ),
    ),
  );
  const published = boundaryResults.filter(
    (result) => result.status === "fulfilled",
  );
  const refused = boundaryResults.filter(
    (result) => result.status === "rejected",
  );
  assert.equal(published.length, 1, "exactly one transaction fills slot ten");
  assert.equal(refused.length, 1, "exactly one transaction is refused");
  assert.equal(refused[0].reason.code, "resource-exhausted");
  assert.match(refused[0].reason.message, /10 active/u);

  const snapshots = await Promise.all(
    drafts.map((draft) => db.doc(`voiceMoments/${draft.momentId}`).get()),
  );
  assert.equal(
    snapshots.filter((snapshot) => snapshot.data().isPublished === true).length,
    10,
  );
  const unpublished = snapshots.filter(
    (snapshot) => snapshot.data().isPublished === false,
  );
  assert.equal(unpublished.length, 1);
  assert.equal(unpublished[0].data().status, "uploading");
  const capacity = (await db.doc(`momentCapacityLedgers/${A}`).get()).data();
  assert.equal(
    capacity.revision,
    10,
    "only successful publishes advance the mutex",
  );
});

test("more than 100 newer drafts cannot hide old active Moments from capacity", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 200, windowMs: 60_000 },
    finalize: { maxEvents: 200, windowMs: 60_000 },
  });

  // Nine canonical published Moments establish the old shelf and revision.
  for (let index = 0; index < 9; index += 1) {
    const suffix = String(index).padStart(2, "0");
    await publish(service, {
      uid: A,
      reserveRequestId: `deep-cap-r-${suffix}`,
      finalizeRequestId: `deep-cap-f-${suffix}`,
      generation: `88${suffix}`,
      availabilityHours: "permanent",
    });
  }

  // These are all newer than the active shelf. The former newest-100 scan
  // saw only filler and under-counted nine permanent Moments as zero.
  const fillerBatch = db.batch();
  for (let index = 0; index < 120; index += 1) {
    const suffix = String(index).padStart(3, "0");
    fillerBatch.set(db.doc(`voiceMoments/deep-filler-${suffix}`), {
      schemaVersion: 2,
      authorId: A,
      isPublished: false,
      isDeleted: false,
      status: "uploading",
      createdAt: Timestamp.fromMillis(nowMs + index + 1),
    });
  }
  await fillerBatch.commit();

  const contenders = [];
  for (let index = 0; index < 2; index += 1) {
    const reserved = await service.reserveMomentDraft(
      request(A, {
        caption: `Deep contender ${index}`,
        durationSeconds: 5,
        requestId: `deep-contender-r-0${index}`,
      }),
    );
    const generation = `889${index}`;
    storage.put(reserved.storagePath, {
      authorId: A,
      momentId: reserved.momentId,
      generation,
    });
    contenders.push({ ...reserved, generation, index });
  }

  const results = await Promise.allSettled(
    contenders.map((draft) =>
      service.finalizeMomentDraft(
        request(A, {
          momentId: draft.momentId,
          objectGeneration: draft.generation,
          requestId: `deep-contender-f-0${draft.index}`,
        }),
      ),
    ),
  );
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  const refused = results.filter((result) => result.status === "rejected");
  assert.equal(refused.length, 1);
  assert.equal(refused[0].reason.code, "resource-exhausted");

  const published = await db
    .collection("voiceMoments")
    .where("authorId", "==", A)
    .where("isPublished", "==", true)
    .get();
  assert.equal(published.size, 10, "the deep shelf never exceeds ten");
  assert.equal(
    (await db.doc(`momentCapacityLedgers/${A}`).get()).data().revision,
    10,
  );

  // Reserve is advisory, but it uses the same exact query and should now
  // refuse despite all 120 newer unpublished documents.
  await assert.rejects(
    service.reserveMomentDraft(
      request(A, {
        caption: "Hidden eleventh",
        durationSeconds: 5,
        requestId: "deep-cap-eleventh",
      }),
    ),
    (error) => error.code === "resource-exhausted",
  );
});

test("a sweeper-expired Moment refuses likes and comments but the author still deletes it", async () => {
  const service = momentService();
  const reserved = await publish(service, {
    uid: B,
    reserveRequestId: "exp-r-01",
    finalizeRequestId: "exp-f-01",
  });

  // The exact flip expireVoiceMomentsSchedule performs — nothing else moves.
  await db.doc(`voiceMoments/${reserved.momentId}`).update({
    isPublished: false,
    status: "expired",
    updatedAt: Timestamp.fromMillis(nowMs),
  });

  await assert.rejects(
    service.setMomentLike(
      request(A, {
        liked: true,
        momentId: reserved.momentId,
        requestId: "exp-like-01",
      }),
    ),
    (error) =>
      error.code === "failed-precondition" && /expired/u.test(error.message),
  );
  await assert.rejects(
    service.createMomentComment(
      request(A, {
        momentId: reserved.momentId,
        requestId: "exp-comment-01",
        text: "too late",
      }),
    ),
    (error) =>
      error.code === "failed-precondition" && /expired/u.test(error.message),
  );

  const deleted = await service.deleteMoment(
    request(B, {
      momentId: reserved.momentId,
      requestId: "exp-del-01",
    }),
  );
  assert.equal(deleted.deletionQueued, true);
});

test("the deadline itself stops all engagement before the sweeper runs", async () => {
  const service = momentService();
  const reserved = await publish(service, {
    uid: B,
    reserveRequestId: "deadline-root-r1",
    finalizeRequestId: "deadline-root-f1",
  });
  const momentRef = db.doc(`voiceMoments/${reserved.momentId}`);
  const deadlineMs = (await momentRef.get()).data().expiresAt.toMillis();

  // Every engagement path remains available one millisecond before the
  // server-authored deadline.
  nowMs = deadlineMs - 1;
  await service.setMomentLike(
    request(A, {
      liked: true,
      momentId: reserved.momentId,
      requestId: "deadline-like-before",
    }),
  );
  await service.createMomentComment(
    request(A, {
      momentId: reserved.momentId,
      requestId: "deadline-text-before",
      text: "just in time",
    }),
  );
  const voiceBefore = await service.reserveVoiceCommentDraft(
    request(A, {
      durationSeconds: 5,
      momentId: reserved.momentId,
      requestId: "deadline-voice-before",
      text: "before",
    }),
  );
  storage.put(voiceBefore.storagePath, {
    authorId: A,
    commentId: voiceBefore.commentId,
    momentId: reserved.momentId,
    generation: "910001",
  });
  await service.finalizeVoiceCommentDraft(
    request(A, {
      commentId: voiceBefore.commentId,
      momentId: reserved.momentId,
      objectGeneration: "910001",
      requestId: "deadline-final-before",
    }),
  );
  const voiceAfter = await service.reserveVoiceCommentDraft(
    request(A, {
      durationSeconds: 5,
      momentId: reserved.momentId,
      requestId: "deadline-voice-pending",
      text: "pending",
    }),
  );
  storage.put(voiceAfter.storagePath, {
    authorId: A,
    commentId: voiceAfter.commentId,
    momentId: reserved.momentId,
    generation: "910002",
  });

  async function assertEngagementRejected(suffix) {
    await assert.rejects(
      service.setMomentLike(
        request(A, {
          liked: false,
          momentId: reserved.momentId,
          requestId: `deadline-like-${suffix}`,
        }),
      ),
      (error) =>
        error.code === "failed-precondition" && /expired/u.test(error.message),
    );
    await assert.rejects(
      service.createMomentComment(
        request(A, {
          momentId: reserved.momentId,
          requestId: `deadline-text-${suffix}`,
          text: "too late",
        }),
      ),
      (error) =>
        error.code === "failed-precondition" && /expired/u.test(error.message),
    );
    await assert.rejects(
      service.reserveVoiceCommentDraft(
        request(A, {
          durationSeconds: 5,
          momentId: reserved.momentId,
          requestId: `deadline-reserve-${suffix}`,
          text: "too late",
        }),
      ),
      (error) =>
        error.code === "failed-precondition" && /expired/u.test(error.message),
    );
    await assert.rejects(
      service.finalizeVoiceCommentDraft(
        request(A, {
          commentId: voiceAfter.commentId,
          momentId: reserved.momentId,
          objectGeneration: "910002",
          requestId: `deadline-final-${suffix}`,
        }),
      ),
      (error) =>
        error.code === "failed-precondition" && /expired/u.test(error.message),
    );
  }

  // The root is still `published`: this proves callable-time enforcement,
  // not the scheduled status flip.
  nowMs = deadlineMs;
  await assertEngagementRejected("exact");
  assert.equal((await momentRef.get()).data().status, "published");
  nowMs = deadlineMs + 1;
  await assertEngagementRejected("after");

  const deleted = await service.deleteMoment(
    request(B, {
      momentId: reserved.momentId,
      requestId: "deadline-delete-after",
    }),
  );
  assert.equal(deleted.deletionQueued, true);
});

test("a legacy published Moment without expiresAt stays canonical and likeable", async () => {
  const service = momentService();
  const reserved = await publish(service, {
    uid: B,
    reserveRequestId: "leg-r-01",
    finalizeRequestId: "leg-f-01",
  });
  // Production still holds pre-expiry documents with no expiresAt at all.
  // Strip the field to reproduce that exact legacy shape.
  await db.doc(`voiceMoments/${reserved.momentId}`).update({
    expiresAt: FieldValue.delete(),
  });

  const liked = await service.setMomentLike(
    request(A, {
      liked: true,
      momentId: reserved.momentId,
      requestId: "leg-like-01",
    }),
  );
  assert.equal(liked.likeCount, 1);

  // A present-but-garbage expiresAt is corruption, not legacy.
  await db.doc(`voiceMoments/${reserved.momentId}`).update({
    expiresAt: "tomorrow",
  });
  await assert.rejects(
    service.setMomentLike(
      request(A, {
        liked: false,
        momentId: reserved.momentId,
        requestId: "leg-like-02",
      }),
    ),
    (error) => error.code === "data-loss",
  );
});

// ---------------------------------------------------------------------------
// Operator-chosen availability (2026-08, amends the 24h contract above).
//
// finalizeMomentDraft accepts an OPTIONAL `availabilityHours`: any safe whole
// number from 24 through 720 stamps `expiresAt = createdAt + hours`, the
// literal string "permanent" writes NO expiresAt field at all, absent defaults
// to 24 (the deployed behaviour, byte for byte), and anything else is
// invalid-argument. Null expiresAt now MEANS permanent — visible until the
// author deletes it — so a permanent Moment occupies an active-cap slot
// forever and only deletion frees it. The boundary and arbitrary numbers
// below are the contract's numbers on purpose; they must not silently follow
// an implementation constant.
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60 * 1000;

test("boundary and arbitrary availability hours stamp exact deadlines", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
    finalize: { maxEvents: 100, windowMs: 60_000 },
  });
  for (const hours of [24, 25, 48, 719, 720]) {
    const reserved = await service.reserveMomentDraft(
      request(A, {
        caption: `Available ${hours}h`,
        durationSeconds: 6,
        requestId: `avail-r-${hours}`,
      }),
    );
    const reservedAtMs = nowMs;
    // Finalize minutes after reserve: the deadline must anchor on the
    // STORED createdAt, exactly as the 24-hour contract already requires.
    nowMs += 5 * 60_000;
    storage.put(reserved.storagePath, {
      authorId: A,
      momentId: reserved.momentId,
      generation: `9${hours}`,
    });
    const finalized = await service.finalizeMomentDraft(
      request(A, {
        availabilityHours: hours,
        momentId: reserved.momentId,
        objectGeneration: `9${hours}`,
        requestId: `avail-f-${hours}`,
      }),
    );
    assert.equal(finalized.published, true);
    const moment = (
      await db.doc(`voiceMoments/${reserved.momentId}`).get()
    ).data();
    assert.equal(moment.createdAt.toMillis(), reservedAtMs);
    assert.equal(
      moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
      hours * HOUR_MS,
      `expiresAt is exactly createdAt + ${hours}h`,
    );
  }
});

test("'permanent' publishes with no expiresAt field written at all", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Keep until deleted",
      durationSeconds: 9,
      requestId: "perm-r-0001",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "91001",
  });
  const finalized = await service.finalizeMomentDraft(
    request(A, {
      availabilityHours: "permanent",
      momentId: reserved.momentId,
      objectGeneration: "91001",
      requestId: "perm-f-0001",
    }),
  );
  assert.equal(finalized.published, true);

  const moment = (
    await db.doc(`voiceMoments/${reserved.momentId}`).get()
  ).data();
  // The key itself must be ABSENT — not null, not a far-future timestamp.
  // Null-vs-absent is load-bearing: the sweeper's range filter skips missing
  // fields, and every client surface reads a missing deadline as permanent.
  assert.equal(
    Object.prototype.hasOwnProperty.call(moment, "expiresAt"),
    false,
    "a permanent Moment carries no expiresAt key",
  );
  assert.equal(moment.isPublished, true);
  assert.equal(moment.status, "published");

  // And it is a first-class published Moment: engageable like any other.
  const liked = await service.setMomentLike(
    request(B, {
      liked: true,
      momentId: reserved.momentId,
      requestId: "perm-like-01",
    }),
  );
  assert.equal(liked.likeCount, 1);
});

test("availabilityHours rejects out-of-range, fractional, and non-number values", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Never publishes",
      durationSeconds: 7,
      requestId: "avail-bad-r-01",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "92001",
  });
  const invalid = [
    23,
    721,
    0,
    -24,
    23.5,
    720.5,
    1,
    8760,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
    Number.MAX_SAFE_INTEGER + 1,
    "24",
    "720",
    "Permanent",
    "PERMANENT",
    "forever",
    null,
    true,
    false,
    [24],
    { hours: 24 },
  ];
  for (const [index, value] of invalid.entries()) {
    await assert.rejects(
      service.finalizeMomentDraft(
        request(A, {
          availabilityHours: value,
          momentId: reserved.momentId,
          objectGeneration: "92001",
          requestId: `avail-bad-f-${String(index).padStart(2, "0")}`,
        }),
      ),
      (error) => error.code === "invalid-argument",
      `must refuse availabilityHours: ${JSON.stringify(value)}`,
    );
  }
  // Refused before any transaction: the draft never published.
  const moment = (
    await db.doc(`voiceMoments/${reserved.momentId}`).get()
  ).data();
  assert.equal(moment.isPublished, false);
  assert.equal(moment.status, "uploading");
});

test("absent and explicit 24 share the deployed operation identity", async () => {
  // REGRESSION PIN, the same reasoning as the content-report hash pin above.
  // finalizeMomentDraft is deployed and live: every publish already ledgered
  // hashed exactly { momentId, objectGeneration }. The default availability
  // must keep that hash — otherwise a pre-availability client's retry of an
  // already-published finalize stops replaying and starts answering
  // already-exists. And an explicit 24 IS the default, so it must hash
  // identically too rather than becoming a "different request" that refuses
  // its own replay.
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Hash pinned",
      durationSeconds: 5,
      requestId: "avail-hash-r-01",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "94001",
  });
  const finalized = await service.finalizeMomentDraft(
    request(A, {
      momentId: reserved.momentId,
      objectGeneration: "94001",
      requestId: "avail-hash-f-01",
    }),
  );
  const identity = operationIdentity("moment.finalize", A, "avail-hash-f-01", {
    momentId: reserved.momentId,
    objectGeneration: "94001",
  });
  const ledger = await db.doc(`integrityOperationLedgers/${identity.id}`).get();
  assert.equal(ledger.exists, true);
  assert.equal(ledger.data().inputHash, identity.inputHash);

  // A retry that names the default explicitly is the SAME request: replay.
  assert.deepEqual(
    await service.finalizeMomentDraft(
      request(A, {
        availabilityHours: 24,
        momentId: reserved.momentId,
        objectGeneration: "94001",
        requestId: "avail-hash-f-01",
      }),
    ),
    finalized,
  );
  assert.equal(
    (await db.doc(`momentCapacityLedgers/${A}`).get()).data().revision,
    1,
    "an idempotent finalize replay must not advance the capacity mutex",
  );
  const moment = (
    await db.doc(`voiceMoments/${reserved.momentId}`).get()
  ).data();
  assert.equal(
    moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
    DAY_MS,
    "the default availability is still exactly 24 hours",
  );
});

test("a finalize retry with a different availability is refused, never silently replayed", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(
    request(A, {
      caption: "Forty-eight hours",
      durationSeconds: 8,
      requestId: "avail-replay-r-01",
    }),
  );
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "95001",
  });
  const finalized = await service.finalizeMomentDraft(
    request(A, {
      availabilityHours: 48,
      momentId: reserved.momentId,
      objectGeneration: "95001",
      requestId: "avail-replay-f-01",
    }),
  );

  // Same requestId, same value: an honest retry replays the stored result.
  assert.deepEqual(
    await service.finalizeMomentDraft(
      request(A, {
        availabilityHours: 48,
        momentId: reserved.momentId,
        objectGeneration: "95001",
        requestId: "avail-replay-f-01",
      }),
    ),
    finalized,
  );

  // Same requestId, DIFFERENT availability: a different request wearing a
  // used id. It must answer already-exists — silently returning the stored
  // result would let a caller believe the new duration took effect.
  for (const changed of [49, 720, "permanent", undefined]) {
    await assert.rejects(
      service.finalizeMomentDraft(
        request(A, {
          momentId: reserved.momentId,
          objectGeneration: "95001",
          requestId: "avail-replay-f-01",
          ...(changed === undefined ? {} : { availabilityHours: changed }),
        }),
      ),
      (error) => error.code === "already-exists",
      `a changed availability (${JSON.stringify(changed)}) must not replay`,
    );
  }

  // The document kept the original arbitrary 48-hour deadline through all
  // of it.
  const moment = (
    await db.doc(`voiceMoments/${reserved.momentId}`).get()
  ).data();
  assert.equal(
    moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
    48 * HOUR_MS,
  );
});

test("permanent Moments hold active-cap slots forever and free them only on delete", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
    finalize: { maxEvents: 100, windowMs: 60_000 },
    delete: { maxEvents: 100, windowMs: 60_000 },
  });
  const permanentIds = [];
  for (let index = 0; index < 10; index += 1) {
    const suffix = String(index).padStart(2, "0");
    const reserved = await publish(service, {
      uid: A,
      reserveRequestId: `permcap-r-${suffix}`,
      finalizeRequestId: `permcap-f-${suffix}`,
      generation: `86${suffix}`,
      availabilityHours: "permanent",
    });
    permanentIds.push(reserved.momentId);
  }

  // A year on, every 24-hour story would be long gone — the ten permanent
  // ones still occupy every slot, because "active" honestly includes a
  // published Moment with no deadline.
  nowMs += 365 * DAY_MS;
  await assert.rejects(
    service.reserveMomentDraft(
      request(A, {
        caption: "Eleventh permanent",
        durationSeconds: 5,
        requestId: "permcap-r-10",
      }),
    ),
    (error) =>
      error.code === "resource-exhausted" && /10 active/u.test(error.message),
    "ten permanent Moments still fill the cap a year later",
  );

  // Deletion is the author's only exit from a permanent Moment and frees the
  // slot immediately. A year has also moved the metered refusal into a fresh
  // quota window, so the same logical requestId may now succeed.
  await service.deleteMoment(
    request(A, {
      momentId: permanentIds[0],
      requestId: "permcap-del-01",
    }),
  );
  const eleventh = await service.reserveMomentDraft(
    request(A, {
      caption: "Eleventh permanent",
      durationSeconds: 5,
      requestId: "permcap-r-10",
    }),
  );
  assert.equal(eleventh.created, true);
});

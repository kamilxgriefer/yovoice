const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { FieldPath, getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DEFAULT_LIMITS,
  canonicalCommentId,
  createMomentIntegrityService,
  momentStoragePath,
  voiceReplyStoragePath,
} = require("../moments/integrity");
const {
  createMomentMigrationService,
} = require("../moments/migration");

const db = getFirestore();
const A = "mmi-alice";
const B = "mmi-bob";
const C = "mmi-charlie";
const USERS = [A, B, C];
let nowMs = 1_810_000_000_000;
let storage;

class FakeStorage {
  constructor() {
    this.objects = new Map();
    this.deleted = [];
    this.metadataReads = 0;
  }

  put(path, {
    authorId,
    momentId,
    commentId,
    contentType = "audio/mp4",
    generation = "1001",
    size = 4096,
    extraMetadata = {},
  }) {
    const custom = {
      authorId,
      momentId,
      ...(commentId ? { commentId } : {}),
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
      deleteQuery(db.collection("voiceMoments").where("authorId", "==", uid)),
      deleteQuery(db.collection("integrityOperationLedgers").where("ownerId", "==", uid)),
      deleteQuery(db.collection("integrityPreflightLedgers").where("ownerId", "==", uid)),
      deleteQuery(db.collection("privateRateLimits").where("ownerId", "==", uid)),
      deleteQuery(db.collection("voiceMomentUploadReservations").where("ownerId", "==", uid)),
      deleteQuery(db.collection("reports").where("reporterId", "==", uid)),
      deleteQuery(db.collection("contentCleanupOutbox").where("requestedBy", "==", uid)),
    ]);
  }
  for (const first of USERS) {
    for (const second of USERS) {
      if (first !== second) {
        await db.doc(`users/${first}/blocked/${second}`).delete();
      }
    }
  }
  await db.doc("conversations/mmi-report-conversation").delete();
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

async function publish(service, {
  uid = B,
  reserveRequestId = `reserve-${uid}`,
  finalizeRequestId = `finalize-${uid}`,
  caption = "Canonical Moment",
  durationSeconds = 12,
  generation = "1001",
} = {}) {
  const reserved = await service.reserveMomentDraft(request(uid, {
    caption,
    durationSeconds,
    requestId: reserveRequestId,
  }));
  storage.put(reserved.storagePath, {
    authorId: uid,
    momentId: reserved.momentId,
    generation,
  });
  await service.finalizeMomentDraft(request(uid, {
    momentId: reserved.momentId,
    objectGeneration: generation,
    requestId: finalizeRequestId,
  }));
  return reserved;
}

beforeEach(async () => {
  nowMs = 1_810_000_000_000;
  storage = new FakeStorage();
  await reset();
  await Promise.all(USERS.map((uid) => seed(uid)));
});

after(reset);

test("draft reservation and finalize bind canonical identity and immutable media", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "  Hello voice  ",
    durationSeconds: 9,
    requestId: "reserve-main1",
  }));
  const replay = await service.reserveMomentDraft(request(A, {
    caption: "  Hello voice  ",
    durationSeconds: 9,
    requestId: "reserve-main1",
  }));
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
  const finalized = await service.finalizeMomentDraft(request(A, {
    momentId: reserved.momentId,
    objectGeneration: "99123",
    requestId: "final-main01",
  }));
  assert.equal(finalized.published, true);
  assert.deepEqual(
    await service.finalizeMomentDraft(request(A, {
      momentId: reserved.momentId,
      objectGeneration: "99123",
      requestId: "final-main01",
    })),
    finalized,
  );
  moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().isPublished, true);
  assert.equal(moment.data().status, "published");
  assert.equal(moment.data().mediaGeneration, "99123");
  assert.equal(moment.data().storagePath, reserved.storagePath);

  await assert.rejects(
    service.finalizeMomentDraft(request(A, {
      momentId: reserved.momentId,
      objectGeneration: "99123",
      requestId: "final-twice1",
    })),
    (error) => error.code === "failed-precondition",
  );
});

test("Moment creation requires an exact HTTPS public identity projection", async () => {
  const service = momentService();
  await db.doc(`publicProfiles/${A}`).delete();
  await assert.rejects(
    service.reserveMomentDraft(request(A, {
      caption: "No projection",
      durationSeconds: 12,
      requestId: "reserve-nopublic",
    })),
    (error) => error.code === "failed-precondition",
  );

  await seed(A);
  await db.doc(`publicProfiles/${A}`).update({ photoUrl: "javascript:alert(1)" });
  await assert.rejects(
    service.reserveMomentDraft(request(A, {
      caption: "Poisoned projection",
      durationSeconds: 12,
      requestId: "reserve-badpublic",
    })),
    (error) => error.code === "data-loss",
  );
});

test("finalize rejects forged metadata, generation, MIME and size", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Upload",
    durationSeconds: 8,
    requestId: "reserve-bad01",
  }));
  storage.put(reserved.storagePath, {
    authorId: B,
    momentId: reserved.momentId,
    generation: "2001",
  });
  await assert.rejects(
    service.finalizeMomentDraft(request(A, {
      momentId: reserved.momentId,
      objectGeneration: "2001",
      requestId: "final-bad001",
    })),
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
    service.finalizeMomentDraft(request(A, {
      momentId: reserved.momentId,
      objectGeneration: "wrong",
      requestId: "final-bad002",
    })),
    (error) => error.code === "invalid-argument" ||
      error.code === "failed-precondition",
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
  await service.reserveMomentDraft(request(A, {
    caption: "Two",
    durationSeconds: 5,
    requestId: "reserve-limit2",
  }));
  await assert.rejects(
    service.reserveMomentDraft(request(A, {
      caption: "Three",
      durationSeconds: 5,
      requestId: "reserve-limit3",
    })),
    (error) => error.code === "resource-exhausted",
  );
  nowMs += 1_001;
  const afterWindow = await service.reserveMomentDraft(request(A, {
    caption: "Four",
    durationSeconds: 5,
    requestId: "reserve-limit4",
  }));
  assert.match(afterWindow.momentId, /^[a-f0-9]{20}$/u);
});

test("concurrent like intents are exactly once and never make a negative count", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const attempts = await Promise.all(Array.from({ length: 8 }, (_, index) =>
    service.setMomentLike(request(A, {
      liked: true,
      momentId,
      requestId: `like-add-${index}`,
    }))));
  assert.equal(attempts.filter((result) => result.changed).length, 1);
  let [moment, like] = await Promise.all([
    db.doc(`voiceMoments/${momentId}`).get(),
    db.doc(`voiceMoments/${momentId}/likes/${A}`).get(),
  ]);
  assert.equal(moment.data().likeCount, 1);
  assert.equal(like.data().userId, A);

  const removals = await Promise.all(Array.from({ length: 5 }, (_, index) =>
    service.setMomentLike(request(A, {
      liked: false,
      momentId,
      requestId: `like-del-${index}`,
    }))));
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
    service.setMomentLike(request(A, {
      liked: false,
      momentId,
      requestId: "like-negative",
    })),
    (error) => error.code === "data-loss",
  );
  assert.equal((await db.doc(`voiceMoments/${momentId}/likes/${A}`).get()).exists, true);
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
  assert.equal(new Set(replayResults.map((result) => result.commentId)).size, 1);

  await Promise.all(Array.from({ length: 5 }, (_, index) =>
    service.createMomentComment(request(A, {
      momentId,
      requestId: `comment-many${index}`,
      text: `comment ${index}`,
    }))));
  const [moment, comments] = await Promise.all([
    db.doc(`voiceMoments/${momentId}`).get(),
    db.collection(`voiceMoments/${momentId}/comments`).get(),
  ]);
  assert.equal(moment.data().commentCount, 6);
  assert.equal(comments.size, 6);
  const first = comments.docs.find((doc) => doc.id === replayResults[0].commentId);
  assert.equal(first.data().authorName, `Public ${A}`);
  assert.equal(first.data().text, "A real comment");

  await assert.rejects(
    service.createMomentComment(request(A, {
      momentId,
      requestId: "comment-forge",
      text: "text",
      authorId: B,
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("blocks and active sanctions prevent likes and comments", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(
    service.setMomentLike(request(A, {
      liked: true,
      momentId,
      requestId: "like-blocked1",
    })),
    (error) => error.code === "failed-precondition",
  );
  await assert.rejects(
    service.createMomentComment(request(A, {
      momentId,
      requestId: "comment-block1",
      text: "blocked",
    })),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${B}/blocked/${A}`).delete();
  await db.doc(`restrictions/${A}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    service.createMomentComment(request(A, {
      momentId,
      requestId: "comment-muted1",
      text: "muted",
    })),
    (error) => error.code === "permission-denied",
  );
});

test("comment deletion decrements once and fails closed on corrupt counters", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const created = await service.createMomentComment(request(A, {
    momentId,
    requestId: "comment-delete-source",
    text: "delete me",
  }));
  const deletionRequest = request(A, {
    commentId: created.commentId,
    momentId,
    requestId: "comment-delete-op1",
  });
  const deleted = await service.deleteMomentComment(deletionRequest);
  assert.deepEqual(await service.deleteMomentComment(deletionRequest), deleted);
  assert.equal((await db.doc(
    `voiceMoments/${momentId}/comments/${created.commentId}`,
  ).get()).exists, false);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).data().commentCount, 0);

  const second = await service.createMomentComment(request(A, {
    momentId,
    requestId: "comment-corrupt-source",
    text: "keep me",
  }));
  await db.doc(`voiceMoments/${momentId}`).update({ commentCount: 0 });
  await assert.rejects(
    service.deleteMomentComment(request(A, {
      commentId: second.commentId,
      momentId,
      requestId: "comment-corrupt-del",
    })),
    (error) => error.code === "data-loss",
  );
  assert.equal((await db.doc(
    `voiceMoments/${momentId}/comments/${second.commentId}`,
  ).get()).exists, true);
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

  const deletion = await service.deleteMoment(request(A, {
    momentId,
    requestId: "moment-delete1",
  }));
  const outbox = await db.doc(`contentCleanupOutbox/${deletion.outboxId}`).get();
  assert.deepEqual(outbox.data().objectPaths, [storagePath]);
  assert.equal(outbox.data().status, "pending");
  await service.processCleanupOutbox(deletion.outboxId);
  assert.ok(storage.deleted.includes(storagePath));
  assert.ok(storage.deleted.includes(canonicalReply));
  assert.equal(storage.deleted.includes(victimPath), false);
  assert.equal(storage.objects.has(victimPath), true);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).exists, false);
  assert.equal(
    (await db.doc(`contentCleanupOutbox/${deletion.outboxId}`).get()).data().status,
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
    service.createContentReport(request(C, {
      targetType: "directMessage",
      conversationId: "mmi-report-conversation",
      messageId: "message-0001",
      reason: "Not mine",
      requestId: "report-denied1",
    })),
    (error) => error.code === "permission-denied",
  );
  const direct = await service.createContentReport(request(A, {
    targetType: "directMessage",
    conversationId: "mmi-report-conversation",
    messageId: "message-0001",
    reason: "Abusive",
    requestId: "report-direct1",
  }));
  assert.equal(direct.created, true);
});

test("comment and like distinct-id bursts are independently rate limited", async () => {
  const service = momentService({
    comment: { maxEvents: 2, windowMs: 1_000 },
    like: { maxEvents: 2, windowMs: 1_000 },
  });
  const { momentId } = await publish(service);
  await service.createMomentComment(request(A, {
    momentId,
    requestId: "rate-comment1",
    text: "one",
  }));
  await service.createMomentComment(request(A, {
    momentId,
    requestId: "rate-comment2",
    text: "two",
  }));
  await assert.rejects(
    service.createMomentComment(request(A, {
      momentId,
      requestId: "rate-comment3",
      text: "three",
    })),
    (error) => error.code === "resource-exhausted",
  );
  await service.setMomentLike(request(A, {
    liked: true,
    momentId,
    requestId: "rate-like001",
  }));
  await service.setMomentLike(request(A, {
    liked: true,
    momentId,
    requestId: "rate-like002",
  }));
  await assert.rejects(
    service.setMomentLike(request(A, {
      liked: true,
      momentId,
      requestId: "rate-like003",
    })),
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
  const reserved = await service.reserveVoiceCommentDraft(request(A, {
    durationSeconds: 7,
    momentId,
    requestId: "voice-reserve1",
    text: "voice reply",
  }));
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
  assert.deepEqual(await service.finalizeVoiceCommentDraft(finalizeRequest), finalized);
  const comment = await db.doc(
    `voiceMoments/${momentId}/comments/${reserved.commentId}`,
  ).get();
  assert.equal(comment.data().schemaVersion, 2);
  assert.equal(comment.data().type, "voice");
  assert.equal(comment.data().authorName, `Public ${A}`);
  assert.equal(comment.data().mediaGeneration, "7001");
  assert.equal((await db.doc(
    `voiceMomentUploadReservations/${reserved.commentId}`,
  ).get()).exists, false);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).data().commentCount, 1);
});

test("expired voice reservation cannot finalize and scheduler deletes its orphan", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  const reserved = await service.reserveVoiceCommentDraft(request(A, {
    durationSeconds: 7,
    momentId,
    requestId: "voice-expired1",
    text: "expired",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    commentId: reserved.commentId,
    momentId,
    generation: "7002",
  });
  nowMs += 31 * 60_000;
  await assert.rejects(
    service.finalizeVoiceCommentDraft(request(A, {
      commentId: reserved.commentId,
      momentId,
      objectGeneration: "7002",
      requestId: "voice-exp-fin1",
    })),
    (error) => error.code === "failed-precondition",
  );
  const expired = await service.expireAbandonedVoiceCommentDrafts({ limit: 10 });
  assert.deepEqual(expired.expired, [reserved.commentId]);
  assert.equal((await db.doc(
    `voiceMomentUploadReservations/${reserved.commentId}`,
  ).get()).exists, false);
  const outboxes = await db.collection("contentCleanupOutbox")
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

test("invalid finalize preflights consume server quota before Storage reads", async () => {
  const service = momentService({
    finalize: { maxEvents: 2, windowMs: 60_000 },
  });
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "preflight",
    durationSeconds: 8,
    requestId: "preflight-res1",
  }));
  storage.put(reserved.storagePath, {
    authorId: B,
    momentId: reserved.momentId,
    generation: "8801",
  });
  for (const id of ["preflight-bad1", "preflight-bad2"]) {
    await assert.rejects(
      service.finalizeMomentDraft(request(A, {
        momentId: reserved.momentId,
        objectGeneration: "8801",
        requestId: id,
      })),
      (error) => error.code === "failed-precondition",
    );
  }
  assert.equal(storage.metadataReads, 2);
  await assert.rejects(
    service.finalizeMomentDraft(request(A, {
      momentId: reserved.momentId,
      objectGeneration: "8801",
      requestId: "preflight-bad3",
    })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(storage.metadataReads, 2);
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
  const deletion = await service.deleteMoment(request(A, {
    momentId,
    requestId: "delete-paged1",
  }));
  let result = await service.processCleanupOutbox(deletion.outboxId);
  assert.equal(result.completed, false);
  result = await service.processCleanupOutbox(deletion.outboxId);
  assert.equal(result.completed, false);
  result = await service.processCleanupOutbox(deletion.outboxId);
  assert.equal(result.completed, true);
  assert.ok(storage.deleted.includes(storagePath));
  const quarantine = await db.collection("contentCleanupQuarantine")
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
  assert.equal((await db.doc(`voiceMoments/${oldId}`).get()).data().status, "deleting");
  for (let index = 0; index < 5; index += 1) {
    const id = `${index}`.padStart(20, "0");
    assert.equal((await db.doc(`voiceMoments/${id}`).get()).data().status, "uploading");
  }
});

test("like and comment counter overflow fail without edge creation", async () => {
  const service = momentService();
  const { momentId } = await publish(service);
  await db.doc(`voiceMoments/${momentId}`).update({
    likeCount: Number.MAX_SAFE_INTEGER,
  });
  await assert.rejects(
    service.setMomentLike(request(A, {
      liked: true,
      momentId,
      requestId: "like-overflow1",
    })),
    (error) => error.code === "data-loss",
  );
  assert.equal((await db.doc(`voiceMoments/${momentId}/likes/${A}`).get()).exists, false);
  await db.doc(`voiceMoments/${momentId}`).update({
    likeCount: 0,
    commentCount: Number.MAX_SAFE_INTEGER,
  });
  await assert.rejects(
    service.createMomentComment(request(A, {
      momentId,
      requestId: "comm-overflow1",
      text: "must fail",
    })),
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
  assert.equal((await migrator.migrateMoment({ momentId, dryRun: true })).status, "ready");
  const applied = await migrator.migrateMoment({ momentId, dryRun: false });
  assert.equal(applied.status, "migrated");
  const migrated = await db.doc(`voiceMoments/${momentId}`).get();
  assert.equal(migrated.data().schemaVersion, 2);
  assert.equal(migrated.data().authorName, `Public ${B}`);
  assert.equal(migrated.data().likeCount, 1);
  assert.equal(migrated.data().commentCount, 1);
  assert.equal((await db.doc(
    `voiceMoments/${momentId}/comments/${commentId}`,
  ).get()).data().schemaVersion, 2);
  assert.equal(
    (await migrator.migrateMoment({ momentId, dryRun: false })).status,
    "alreadyMigrated",
  );

  await service.deleteMomentComment(request(A, {
    commentId,
    momentId,
    requestId: "legacy-comment-delete",
  }));
  const deletion = await service.deleteMoment(request(B, {
    momentId,
    requestId: "legacy-moment-delete",
  }));
  await service.processCleanupOutbox(deletion.outboxId);
  assert.equal((await db.doc(`voiceMoments/${momentId}`).get()).exists, false);
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

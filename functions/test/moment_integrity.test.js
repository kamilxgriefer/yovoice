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
  canonicalCommentId,
  createMomentIntegrityService,
  momentStoragePath,
  voiceReplyStoragePath,
} = require("../moments/integrity");
const {
  createMomentMigrationService,
} = require("../moments/migration");
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

async function publish(service, {
  uid = B,
  reserveRequestId = `reserve-${uid}`,
  finalizeRequestId = `finalize-${uid}`,
  caption = "Canonical Moment",
  durationSeconds = 12,
  generation = "1001",
  availabilityHours = undefined,
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
    // Absent by default on purpose: most of this suite publishes exactly the
    // way pre-availability clients do, which must stay the 24-hour story.
    ...(availabilityHours === undefined ? {} : { availabilityHours }),
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

test("a one-second recording publishes through the canonical draft contract", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "One second",
    durationSeconds: 1,
    requestId: "reserve-one-second",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "1000000000000001",
    size: 1024,
  });

  const finalized = await service.finalizeMomentDraft(request(A, {
    momentId: reserved.momentId,
    objectGeneration: "1000000000000001",
    requestId: "finalize-one-second",
  }));

  assert.equal(finalized.published, true);
  const moment = await db.doc(`voiceMoments/${reserved.momentId}`).get();
  assert.equal(moment.data().durationSeconds, 1);
  assert.equal(moment.data().mediaSize, 1024);
  assert.equal(moment.data().status, "published");
});

test("unverified actors cannot reserve or finalize Voice Moment uploads", async () => {
  const service = momentService();
  await assert.rejects(
    service.reserveMomentDraft(request(A, {
      caption: "Unverified reserve",
      durationSeconds: 1,
      requestId: "reserve-unverified",
    }, false)),
    (error) => error.code === "failed-precondition",
  );

  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Verified reserve",
    durationSeconds: 1,
    requestId: "reserve-before-unverified-finalize",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "1000000000000002",
    size: 1024,
  });
  await assert.rejects(
    service.finalizeMomentDraft(request(A, {
      momentId: reserved.momentId,
      objectGeneration: "1000000000000002",
      requestId: "finalize-unverified",
    }, false)),
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

// ---------------------------------------------------------------------------
// Report targets that are not Moments: room chat and Club channel chat.
//
// The membership refusals below are the part that matters. A report target is
// the one input a caller fully controls, so an endpoint that answers
// "not-found" for a room or Club the caller cannot see is an existence oracle
// for private spaces. Every refusal here therefore asserts the CODE, not just
// that the call failed.
// ---------------------------------------------------------------------------

async function seedRoom(roomId, { hostId = B, visibility = "private", clubId = "" } = {}) {
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
    .doc(`clubs/${REPORT_CLUB}/channels/${CLUB_CHANNEL}/messages/${CLUB_MESSAGE}`)
    .set({ senderId: ownerId, clubId: REPORT_CLUB, content: "reported club message" });
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
  const result = await service.createContentReport(request(A, {
    targetType: "voiceMoment",
    momentId,
    reason: "Harassment",
    requestId: "report-unverified1",
  }, false));
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
    service.createContentReport(request(A, {
      targetType: "voiceMoment",
      momentId: "whatever",
      roomId: PRIVATE_ROOM,
      reason: "Harassment",
      requestId: "report-conflict5",
    })),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(request(A, {
      targetType: "roomMessage",
      roomId: PRIVATE_ROOM,
      reason: "Harassment",
      requestId: "report-conflict6",
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("a report carries an optional bounded reporter note", async () => {
  const service = momentService();
  const { momentId } = await publish(service);

  const withNote = await service.createContentReport(request(A, {
    targetType: "voiceMoment",
    momentId,
    reason: "harassment",
    note: "  They named my employer.  ",
    requestId: "report-note1",
  }));
  const stored = await db.doc(`reports/${withNote.reportId}`).get();
  assert.equal(stored.data().note, "They named my employer.");

  // Absent and empty both persist as "", the same shape the v1
  // client-written path uses, so one Moderation Center field renders both.
  const withoutNote = await service.createContentReport(request(C, {
    targetType: "voiceMoment",
    momentId,
    reason: "harassment",
    requestId: "report-note2",
  }));
  assert.equal(
    (await db.doc(`reports/${withoutNote.reportId}`).get()).data().note,
    "",
  );

  await assert.rejects(
    service.createContentReport(request(B, {
      targetType: "voiceMoment",
      momentId,
      reason: "harassment",
      note: "x".repeat(301),
      requestId: "report-note3",
    })),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.createContentReport(request(B, {
      targetType: "voiceMoment",
      momentId,
      reason: "harassment",
      note: 42,
      requestId: "report-note4",
    })),
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
  const result = await service.createContentReport(request(A, {
    targetType: "voiceMoment",
    momentId,
    reason: "Harassment",
    requestId: "report-hashpin1",
  }));
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

test("generic cleanup worker removes private direct-message attachment objects", async () => {
  const conversationId = "direct-cleanup-conversation";
  const messageId = `m_${"d".repeat(40)}`;
  const objectPath =
    `message_attachments/${A}/${conversationId}/${messageId}.jpg`;
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
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Expiring story",
    durationSeconds: 8,
    requestId: "reserve-expiry-01",
  }));
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
  const finalized = await service.finalizeMomentDraft(request(A, {
    momentId: reserved.momentId,
    objectGeneration: "77001",
    requestId: "finalize-expiry-01",
  }));
  assert.equal(finalized.published, true);

  const moment = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
  assert.equal(moment.createdAt.toMillis(), reservedAtMs);
  assert.ok(moment.expiresAt instanceof Timestamp, "expiresAt is stamped");
  assert.equal(
    moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
    DAY_MS,
    "expiresAt is exactly createdAt + 24h",
  );

  // Replay must return the stored result without moving the deadline.
  await service.finalizeMomentDraft(request(A, {
    momentId: reserved.momentId,
    objectGeneration: "77001",
    requestId: "finalize-expiry-01",
  }));
  const replayed = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
  assert.equal(replayed.expiresAt.toMillis(), moment.expiresAt.toMillis());
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
    service.reserveMomentDraft(request(A, {
      caption: "Eleventh story",
      durationSeconds: 5,
      requestId: "cap-r-10",
    })),
    (error) => error.code === "resource-exhausted" &&
      /10 active/u.test(error.message),
    "the eleventh reserve is refused while ten stories are live",
  );

  // Another author is not affected by A's cap.
  const other = await service.reserveMomentDraft(request(B, {
    caption: "Someone else's story",
    durationSeconds: 5,
    requestId: "cap-r-other",
  }));
  assert.equal(other.created, true);

  // T0 + 24h + 1min: only the FIRST story has expired (the other nine run
  // until T0 + 26h), so exactly one active slot is free — and the refused
  // transaction consumed nothing, so the very same requestId succeeds now.
  nowMs += 22 * 60 * 60_000 + 60_000;
  const eleventh = await service.reserveMomentDraft(request(A, {
    caption: "Eleventh story",
    durationSeconds: 5,
    requestId: "cap-r-10",
  }));
  assert.equal(eleventh.created, true);
});

test("unpublished drafts do not count against the active-story cap", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
  });
  // Eleven reservations, none finalized: the cap counts LIVE stories, not
  // reservations, so every one of these must pass.
  for (let index = 0; index < 11; index += 1) {
    const reserved = await service.reserveMomentDraft(request(A, {
      caption: `Draft ${index}`,
      durationSeconds: 5,
      requestId: `draft-cap-${String(index).padStart(2, "0")}`,
    }));
    assert.equal(reserved.created, true);
  }
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
    service.setMomentLike(request(A, {
      liked: true,
      momentId: reserved.momentId,
      requestId: "exp-like-01",
    })),
    (error) => error.code === "failed-precondition" &&
      /expired/u.test(error.message),
  );
  await assert.rejects(
    service.createMomentComment(request(A, {
      momentId: reserved.momentId,
      requestId: "exp-comment-01",
      text: "too late",
    })),
    (error) => error.code === "failed-precondition" &&
      /expired/u.test(error.message),
  );

  const deleted = await service.deleteMoment(request(B, {
    momentId: reserved.momentId,
    requestId: "exp-del-01",
  }));
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

  const liked = await service.setMomentLike(request(A, {
    liked: true,
    momentId: reserved.momentId,
    requestId: "leg-like-01",
  }));
  assert.equal(liked.likeCount, 1);

  // A present-but-garbage expiresAt is corruption, not legacy.
  await db.doc(`voiceMoments/${reserved.momentId}`).update({
    expiresAt: "tomorrow",
  });
  await assert.rejects(
    service.setMomentLike(request(A, {
      liked: false,
      momentId: reserved.momentId,
      requestId: "leg-like-02",
    })),
    (error) => error.code === "data-loss",
  );
});

// ---------------------------------------------------------------------------
// Operator-chosen availability (2026-08, amends the 24h contract above).
//
// finalizeMomentDraft accepts an OPTIONAL `availabilityHours`: exactly one of
// 24 / 72 / 168 / 720 stamps `expiresAt = createdAt + hours`, the literal
// string "permanent" writes NO expiresAt field at all, absent defaults to 24
// (the deployed behaviour, byte for byte), and anything else is
// invalid-argument. Null expiresAt now MEANS permanent — visible until the
// author deletes it — so a permanent Moment occupies an active-cap slot
// forever and only deletion frees it. The whitelist numbers below are the
// contract's numbers on purpose; they must not silently follow a constant.
// ---------------------------------------------------------------------------

const HOUR_MS = 60 * 60 * 1000;

test("each whitelisted availability stamps exactly createdAt + hours", async () => {
  const service = momentService({
    uploadReserve: { maxEvents: 100, windowMs: 60_000 },
    finalize: { maxEvents: 100, windowMs: 60_000 },
  });
  for (const hours of [24, 72, 168, 720]) {
    const reserved = await service.reserveMomentDraft(request(A, {
      caption: `Available ${hours}h`,
      durationSeconds: 6,
      requestId: `avail-r-${hours}`,
    }));
    const reservedAtMs = nowMs;
    // Finalize minutes after reserve: the deadline must anchor on the
    // STORED createdAt, exactly as the 24-hour contract already requires.
    nowMs += 5 * 60_000;
    storage.put(reserved.storagePath, {
      authorId: A,
      momentId: reserved.momentId,
      generation: `9${hours}`,
    });
    const finalized = await service.finalizeMomentDraft(request(A, {
      availabilityHours: hours,
      momentId: reserved.momentId,
      objectGeneration: `9${hours}`,
      requestId: `avail-f-${hours}`,
    }));
    assert.equal(finalized.published, true);
    const moment = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
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
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Keep until deleted",
    durationSeconds: 9,
    requestId: "perm-r-0001",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "91001",
  });
  const finalized = await service.finalizeMomentDraft(request(A, {
    availabilityHours: "permanent",
    momentId: reserved.momentId,
    objectGeneration: "91001",
    requestId: "perm-f-0001",
  }));
  assert.equal(finalized.published, true);

  const moment = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
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
  const liked = await service.setMomentLike(request(B, {
    liked: true,
    momentId: reserved.momentId,
    requestId: "perm-like-01",
  }));
  assert.equal(liked.likeCount, 1);
});

test("every availabilityHours outside the strict whitelist is refused", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Never publishes",
    durationSeconds: 7,
    requestId: "avail-bad-r-01",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "92001",
  });
  const invalid = [
    48, 0, -24, 23.5, 1, 8760, Number.NaN,
    "24", "720", "Permanent", "PERMANENT", "forever",
    null, true, false, [24], { hours: 24 },
  ];
  for (const [index, value] of invalid.entries()) {
    await assert.rejects(
      service.finalizeMomentDraft(request(A, {
        availabilityHours: value,
        momentId: reserved.momentId,
        objectGeneration: "92001",
        requestId: `avail-bad-f-${String(index).padStart(2, "0")}`,
      })),
      (error) => error.code === "invalid-argument",
      `must refuse availabilityHours: ${JSON.stringify(value)}`,
    );
  }
  // Refused before any transaction: the draft never published.
  const moment = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
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
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Hash pinned",
    durationSeconds: 5,
    requestId: "avail-hash-r-01",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "94001",
  });
  const finalized = await service.finalizeMomentDraft(request(A, {
    momentId: reserved.momentId,
    objectGeneration: "94001",
    requestId: "avail-hash-f-01",
  }));
  const identity = operationIdentity("moment.finalize", A, "avail-hash-f-01", {
    momentId: reserved.momentId,
    objectGeneration: "94001",
  });
  const ledger = await db.doc(`integrityOperationLedgers/${identity.id}`).get();
  assert.equal(ledger.exists, true);
  assert.equal(ledger.data().inputHash, identity.inputHash);

  // A retry that names the default explicitly is the SAME request: replay.
  assert.deepEqual(
    await service.finalizeMomentDraft(request(A, {
      availabilityHours: 24,
      momentId: reserved.momentId,
      objectGeneration: "94001",
      requestId: "avail-hash-f-01",
    })),
    finalized,
  );
  const moment = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
  assert.equal(
    moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
    DAY_MS,
    "the default availability is still exactly 24 hours",
  );
});

test("a finalize retry with a different availability is refused, never silently replayed", async () => {
  const service = momentService();
  const reserved = await service.reserveMomentDraft(request(A, {
    caption: "Seventy-two hours",
    durationSeconds: 8,
    requestId: "avail-replay-r-01",
  }));
  storage.put(reserved.storagePath, {
    authorId: A,
    momentId: reserved.momentId,
    generation: "95001",
  });
  const finalized = await service.finalizeMomentDraft(request(A, {
    availabilityHours: 72,
    momentId: reserved.momentId,
    objectGeneration: "95001",
    requestId: "avail-replay-f-01",
  }));

  // Same requestId, same value: an honest retry replays the stored result.
  assert.deepEqual(
    await service.finalizeMomentDraft(request(A, {
      availabilityHours: 72,
      momentId: reserved.momentId,
      objectGeneration: "95001",
      requestId: "avail-replay-f-01",
    })),
    finalized,
  );

  // Same requestId, DIFFERENT availability: a different request wearing a
  // used id. It must answer already-exists — silently returning the stored
  // result would let a caller believe the new duration took effect.
  for (const changed of [168, "permanent", undefined]) {
    await assert.rejects(
      service.finalizeMomentDraft(request(A, {
        momentId: reserved.momentId,
        objectGeneration: "95001",
        requestId: "avail-replay-f-01",
        ...(changed === undefined ? {} : { availabilityHours: changed }),
      })),
      (error) => error.code === "already-exists",
      `a changed availability (${JSON.stringify(changed)}) must not replay`,
    );
  }

  // The document kept the original 72-hour deadline through all of it.
  const moment = (await db.doc(`voiceMoments/${reserved.momentId}`).get()).data();
  assert.equal(
    moment.expiresAt.toMillis() - moment.createdAt.toMillis(),
    72 * HOUR_MS,
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
    service.reserveMomentDraft(request(A, {
      caption: "Eleventh permanent",
      durationSeconds: 5,
      requestId: "permcap-r-10",
    })),
    (error) => error.code === "resource-exhausted" &&
      /10 active/u.test(error.message),
    "ten permanent Moments still fill the cap a year later",
  );

  // Deletion is the author's only exit from a permanent Moment, and it
  // frees the slot immediately — and the refused reserve consumed neither
  // ledger nor rate budget, so the very same requestId succeeds now.
  await service.deleteMoment(request(A, {
    momentId: permanentIds[0],
    requestId: "permcap-del-01",
  }));
  const eleventh = await service.reserveMomentDraft(request(A, {
    caption: "Eleventh permanent",
    durationSeconds: 5,
    requestId: "permcap-r-10",
  }));
  assert.equal(eleventh.created, true);
});

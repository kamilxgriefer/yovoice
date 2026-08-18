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
  canonicalConversationId,
  canonicalPairKey,
  createDirectMessagingService,
} = require("../messaging/direct_integrity");
const {
  createDirectMigrationService,
} = require("../messaging/direct_migration");

const db = getFirestore();
const A = "dmi-alice";
const B = "dmi-bob";
const C = "dmi-charlie";
const D = "dmi-dana";
const MIXED_LOWER = "aMixedUser";
const MIXED_UPPER = "BMixedUser";
const OPAQUE_SPACE = "opaque uid";
const OPAQUE_UNICODE = "Żółw-用户";
const USERS = [
  A,
  B,
  C,
  D,
  MIXED_LOWER,
  MIXED_UPPER,
  OPAQUE_SPACE,
  OPAQUE_UNICODE,
];
let nowMs = 1_800_000_000_000;

function request(uid, data, verified = true) {
  return {
    auth: {
      uid,
      token: { email_verified: verified, email: `${uid}@example.invalid` },
    },
    data,
  };
}

function directService(limitOverrides = {}, options = {}) {
  return createDirectMessagingService({
    db,
    Timestamp,
    clock: () => nowMs,
    limits: { ...DEFAULT_LIMITS, ...limitOverrides },
    ...options,
  });
}

async function deleteQuery(query) {
  const snapshot = await query.get();
  await Promise.all(snapshot.docs.map(async (document) => {
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(document.ref);
    } else {
      await document.ref.delete();
    }
  }));
}

async function reset() {
  const conversationIds = [];
  for (let index = 0; index < USERS.length; index += 1) {
    for (let other = index + 1; other < USERS.length; other += 1) {
      conversationIds.push(canonicalConversationId(USERS[index], USERS[other]));
    }
  }
  await Promise.all([
    deleteQuery(db.collection("contentCleanupOutbox")),
    deleteQuery(db.collection("contentCleanupQuarantine")),
    ...USERS.map((uid) => db.doc(`users/${uid}`).delete()),
    ...USERS.map((uid) => db.doc(`publicProfiles/${uid}`).delete()),
    ...USERS.map((uid) => db.doc(`restrictions/${uid}`).delete()),
    ...conversationIds.map(async (id) => {
      const ref = db.doc(`conversations/${id}`);
      if (typeof db.recursiveDelete === "function") await db.recursiveDelete(ref);
      else await ref.delete();
    }),
    ...conversationIds.map((id) => {
      const participants = USERS.filter((uid) => id.includes(uid));
      return Promise.resolve(participants);
    }),
  ]);
  for (const uid of USERS) {
    await Promise.all([
      deleteQuery(db.collection("integrityOperationLedgers").where("ownerId", "==", uid)),
      deleteQuery(db.collection("privateRateLimits").where("ownerId", "==", uid)),
      deleteQuery(db.collection("directReactionEvents").where("actorId", "==", uid)),
      deleteQuery(db.collection("directMessageUploadReservations").where("ownerId", "==", uid)),
      deleteQuery(db.collection("integrityPreflightLedgers").where("ownerId", "==", uid)),
    ]);
  }
  for (let index = 0; index < USERS.length; index += 1) {
    for (let other = index + 1; other < USERS.length; other += 1) {
      await db.doc(
        `directConversationPairs/${canonicalPairKey(USERS[index], USERS[other])}`,
      ).delete();
      await Promise.all([
        db.doc(`users/${USERS[index]}/blocked/${USERS[other]}`).delete(),
        db.doc(`users/${USERS[other]}/blocked/${USERS[index]}`).delete(),
        db.doc(`users/${USERS[index]}/following/${USERS[other]}`).delete(),
        db.doc(`users/${USERS[other]}/following/${USERS[index]}`).delete(),
        db.doc(
          `friendshipGuards/${USERS[index]}/friends/${USERS[other]}`,
        ).delete(),
        db.doc(
          `friendshipGuards/${USERS[other]}/friends/${USERS[index]}`,
        ).delete(),
      ]);
    }
  }
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

async function open(service, first = A, second = B, requestId = "open-0001") {
  return service.openDirectConversation(request(first, {
    requestId,
    targetUserId: second,
  }));
}

beforeEach(async () => {
  nowMs = 1_800_000_000_000;
  await reset();
  await Promise.all(USERS.map((uid) => seed(uid)));
});

after(reset);

test("openDirectConversation binds one canonical pair and canonical identity", async () => {
  const service = directService();
  const first = await open(service);
  const replay = await open(service);
  assert.deepEqual(replay, first);
  assert.equal(first.created, true);
  assert.equal(first.conversationId, canonicalConversationId(A, B));

  const [conversation, guard, messages] = await Promise.all([
    db.doc(`conversations/${first.conversationId}`).get(),
    db.doc(`directConversationPairs/${canonicalPairKey(A, B)}`).get(),
    db.collection(`conversations/${first.conversationId}/messages`).get(),
  ]);
  assert.equal(guard.data().conversationId, first.conversationId);
  assert.deepEqual(conversation.data().participantIds, [A, B]);
  assert.equal(conversation.data().participantNames[A], `Public ${A}`);
  assert.equal(conversation.data().participantEmails[A], "");
  assert.equal(conversation.data().schemaVersion, 2);
  assert.equal(messages.size, 0);

  await assert.rejects(
    service.openDirectConversation(request(A, {
      requestId: "open-evil",
      targetUserId: C,
      participantNames: { [C]: "forged" },
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("concurrent opens cannot create duplicate conversations", async () => {
  const service = directService();
  const results = await Promise.all(
    Array.from({ length: 8 }, (_, index) => open(
      service,
      index % 2 === 0 ? A : B,
      index % 2 === 0 ? B : A,
      `open-race-${index}`,
    )),
  );
  assert.equal(new Set(results.map((result) => result.conversationId)).size, 1);
  assert.equal(results.filter((result) => result.created).length, 1);
  const conversations = await db
    .collection("conversations")
    .where("pairKey", "==", canonicalPairKey(A, B))
    .get();
  assert.equal(conversations.size, 1);
});

test("mixed-case opaque UIDs use one stable order from open through send", async () => {
  const service = directService();
  const opened = await open(
    service,
    MIXED_LOWER,
    MIXED_UPPER,
    "open-mixed01",
  );
  const conversation = await db.doc(`conversations/${opened.conversationId}`).get();
  assert.deepEqual(conversation.data().participantIds, [MIXED_UPPER, MIXED_LOWER]);
  const sent = await service.sendDirectMessage(request(MIXED_LOWER, {
    conversationId: opened.conversationId,
    requestId: "send-mixed01",
    text: "Case-sensitive hello",
  }));
  assert.ok(sent.messageId);
  assert.equal(
    (await db.doc(`conversations/${opened.conversationId}`).get())
      .data().unreadCounts[MIXED_UPPER],
    1,
  );
});

test("opaque Auth UIDs are preserved byte-for-byte, including spaces and Unicode", async () => {
  const service = directService();
  const opened = await open(
    service,
    OPAQUE_SPACE,
    OPAQUE_UNICODE,
    "open-opaque01",
  );
  const root = await db.doc(`conversations/${opened.conversationId}`).get();
  const expected = [OPAQUE_SPACE, OPAQUE_UNICODE]
    .sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
  assert.deepEqual(root.data().participantIds, expected);
  const sent = await service.sendDirectMessage(request(OPAQUE_UNICODE, {
    conversationId: opened.conversationId,
    requestId: "send-opaque01",
    text: "Opaque identity",
  }));
  assert.equal(
    (await db.doc(
      `conversations/${opened.conversationId}/messages/${sent.messageId}`,
    ).get()).data().senderId,
    OPAQUE_UNICODE,
  );
});

test("missing or poisoned public identity projection fails closed", async () => {
  const service = directService();
  await db.doc(`publicProfiles/${B}`).delete();
  await assert.rejects(
    open(service, A, B, "open-no-public"),
    (error) => error.code === "failed-precondition",
  );
  assert.equal((await db.doc(
    `conversations/${canonicalConversationId(A, B)}`,
  ).get()).exists, false);

  await seed(B);
  await db.doc(`publicProfiles/${B}`).update({ email: "poison@example.invalid" });
  await assert.rejects(
    open(service, A, B, "open-bad-public"),
    (error) => error.code === "data-loss",
  );
  await db.doc(`publicProfiles/${B}`).set({
    ...(await db.doc(`publicProfiles/${A}`).get()).data(),
    uid: B,
    displayName: `Public ${B}`,
    username: B,
    displayNameSearch: `public ${B}`,
    usernameSearch: B,
    photoUrl: "http://public.invalid/insecure.png",
  });
  await assert.rejects(
    open(service, A, B, "open-http-public"),
    (error) => error.code === "data-loss",
  );
});

test("send is atomic, replay-safe and increments unread exactly once", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  const input = request(A, {
    conversationId,
    requestId: "send-0001",
    text: "  Hello Bob  ",
  });
  const results = await Promise.all(
    Array.from({ length: 6 }, () => service.sendDirectMessage(input)),
  );
  assert.equal(new Set(results.map((result) => result.messageId)).size, 1);
  const [conversation, messages] = await Promise.all([
    db.doc(`conversations/${conversationId}`).get(),
    db.collection(`conversations/${conversationId}/messages`).get(),
  ]);
  assert.equal(messages.size, 1);
  assert.equal(messages.docs[0].data().content, "Hello Bob");
  assert.deepEqual(messages.docs[0].data().readBy, [A]);
  assert.equal(conversation.data().unreadCounts[A], 0);
  assert.equal(conversation.data().unreadCounts[B], 1);
  assert.equal(conversation.data().lastMessageId, results[0].messageId);

  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId,
      requestId: "send-0001",
      text: "different payload",
    })),
    (error) => error.code === "already-exists",
  );
});

test("different send request ids serialize counters under concurrency", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  await Promise.all(Array.from({ length: 8 }, (_, index) =>
    service.sendDirectMessage(request(A, {
      conversationId,
      requestId: `send-many-${index}`,
      text: `message ${index}`,
    }))));
  const [conversation, messages] = await Promise.all([
    db.doc(`conversations/${conversationId}`).get(),
    db.collection(`conversations/${conversationId}/messages`).get(),
  ]);
  assert.equal(messages.size, 8);
  assert.equal(conversation.data().unreadCounts[B], 8);
  assert.equal(conversation.data().unreadCounts[A], 0);
});

test("private image attachments are reserved, storage-bound and finalized once", async () => {
  const metadata = new Map();
  const storage = {
    async getMetadata(path) {
      const value = metadata.get(path);
      if (!value) throw Object.assign(new Error("missing"), { code: "not-found" });
      return value;
    },
    getObjectReference(path) {
      return `gs://yovoice-test.appspot.com/${path}`;
    },
  };
  const service = directService({}, { storage });
  const { conversationId } = await open(service);
  const reserved = await service.reserveDirectMessageAttachment(request(A, {
    conversationId,
    type: "image",
    contentType: "image/jpeg",
    requestId: "media-reserve-1",
  }));
  assert.match(reserved.messageId, /^m_[a-f0-9]{40}$/u);
  assert.equal(reserved.type, "image");
  assert.equal((await db.doc(
    `directMessageUploadReservations/${reserved.messageId}`,
  ).get()).data().ownerId, A);

  metadata.set(reserved.storagePath, {
    size: "2048",
    contentType: "image/jpeg",
    generation: "17",
    metadata: {
      yovoiceConversationId: conversationId,
      yovoiceMessageId: reserved.messageId,
      yovoiceMessagePath:
        `conversations/${conversationId}/messages/${reserved.messageId}`,
      yovoiceMediaType: "image",
      yovoiceOwnerUid: "victim-forgery",
    },
  });
  await assert.rejects(
    service.finalizeDirectMessageAttachment(request(A, {
      conversationId,
      messageId: reserved.messageId,
      objectGeneration: "17",
      requestId: "media-finalize-bad",
    })),
    (error) => error.code === "failed-precondition",
  );

  metadata.get(reserved.storagePath).metadata.yovoiceOwnerUid = A;
  const finalized = await service.finalizeDirectMessageAttachment(request(A, {
    conversationId,
    messageId: reserved.messageId,
    objectGeneration: "17",
    requestId: "media-finalize-good",
  }));
  assert.equal(finalized.created, true);
  const message = await db.doc(
    `conversations/${conversationId}/messages/${reserved.messageId}`,
  ).get();
  assert.equal(message.data().type, "image");
  assert.equal(message.data().mediaUrl, `gs://yovoice-test.appspot.com/${reserved.storagePath}`);
  assert.equal((await db.doc(
    `directMessageUploadReservations/${reserved.messageId}`,
  ).get()).exists, false);
  assert.equal((await db.doc(`conversations/${conversationId}`).get())
    .data().unreadCounts[B], 1);

  const replay = await service.finalizeDirectMessageAttachment(request(A, {
    conversationId,
    messageId: reserved.messageId,
    objectGeneration: "17",
    requestId: "media-finalize-good",
  }));
  assert.deepEqual(replay, finalized);
});

test("attachment reservations reject forged media contracts and blocked peers", async () => {
  const service = directService({}, {
    storage: {
      async getMetadata() { throw new Error("not reached"); },
      getObjectReference(path) { return `gs://test/${path}`; },
    },
  });
  const { conversationId } = await open(service);
  await assert.rejects(
    service.reserveDirectMessageAttachment(request(A, {
      conversationId,
      type: "image",
      contentType: "text/html",
      requestId: "media-bad-mime",
    })),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service.reserveDirectMessageAttachment(request(A, {
      conversationId,
      type: "image",
      contentType: "image/png",
      durationSeconds: 12,
      requestId: "media-image-duration",
    })),
    (error) => error.code === "invalid-argument",
  );
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(
    service.reserveDirectMessageAttachment(request(A, {
      conversationId,
      type: "voice",
      contentType: "audio/mp4",
      durationSeconds: 4,
      requestId: "media-blocked",
    })),
    (error) => error.code === "failed-precondition",
  );
});

test("expired direct upload reservations queue canonical orphan cleanup", async () => {
  const service = directService({}, {
    storage: {
      async getMetadata() { throw new Error("not reached"); },
      getObjectReference(path) { return `gs://test/${path}`; },
    },
  });
  const { conversationId } = await open(service);
  const reserved = await service.reserveDirectMessageAttachment(request(A, {
    conversationId,
    type: "voice",
    contentType: "audio/mp4",
    durationSeconds: 5,
    requestId: "media-expiry-1",
  }));
  nowMs += 16 * 60_000;
  const expired = await service.expireAbandonedAttachmentReservations();
  assert.deepEqual(expired.expired, [reserved.messageId]);
  assert.equal((await db.doc(
    `directMessageUploadReservations/${reserved.messageId}`,
  ).get()).exists, false);
  const outboxes = await db.collection("contentCleanupOutbox")
    .where("kind", "==", "directMessageAttachmentReservation")
    .get();
  assert.equal(outboxes.size, 1);
  assert.deepEqual(outboxes.docs[0].data().objectPaths, [reserved.storagePath]);
});

test("reply linkage, author-only edits and one-way deletion are enforced", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  const sent = await service.sendDirectMessage(request(A, {
    conversationId,
    requestId: "send-parent",
    text: "parent",
  }));
  const reply = await service.sendDirectMessage(request(B, {
    conversationId,
    replyToMessageId: sent.messageId,
    requestId: "send-reply1",
    text: "reply",
  }));
  const replyDoc = await db.doc(
    `conversations/${conversationId}/messages/${reply.messageId}`,
  ).get();
  assert.equal(replyDoc.data().replyToMessageId, sent.messageId);
  assert.equal(replyDoc.data().replyToSenderId, A);

  await assert.rejects(
    service.editDirectMessage(request(B, {
      conversationId,
      messageId: sent.messageId,
      requestId: "edit-wrong",
      text: "stolen",
    })),
    (error) => error.code === "permission-denied",
  );
  await service.editDirectMessage(request(A, {
    conversationId,
    messageId: sent.messageId,
    requestId: "edit-own-1",
    text: "edited parent",
  }));
  const deleted = await service.deleteDirectMessage(request(A, {
    conversationId,
    messageId: sent.messageId,
    requestId: "delete-own1",
  }));
  assert.equal(deleted.deleted ?? deleted.changed, true);
  const replay = await service.deleteDirectMessage(request(A, {
    conversationId,
    messageId: sent.messageId,
    requestId: "delete-own1",
  }));
  assert.deepEqual(replay, deleted);
  const message = await db.doc(
    `conversations/${conversationId}/messages/${sent.messageId}`,
  ).get();
  assert.equal(message.data().isDeleted, true);
  assert.equal(message.data().content, "");

  await assert.rejects(
    service.editDirectMessage(request(A, {
      conversationId,
      messageId: sent.messageId,
      requestId: "edit-deleted",
      text: "resurrect",
    })),
    (error) => error.code === "failed-precondition",
  );
});

test("blocks, sanctions, inactive users and unverified actors fail closed", async () => {
  const service = directService();
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(open(service), (error) => error.code === "failed-precondition");
  await db.doc(`users/${B}/blocked/${A}`).delete();
  await db.doc(`restrictions/${A}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    open(service, A, B, "open-muted1"),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`restrictions/${A}`).delete();
  await db.doc(`users/${B}`).update({ disabled: true });
  await assert.rejects(
    open(service, A, B, "open-disabled"),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${B}`).update({ disabled: false });
  await assert.rejects(
    service.openDirectConversation(request(A, {
      requestId: "open-unverif",
      targetUserId: B,
    }, false)),
    (error) => error.code === "failed-precondition",
  );
});

test("direct-message privacy modes are enforced from server-owned graph state", async () => {
  const service = directService();

  // Existing accounts have no field, so the documented backwards-compatible
  // default remains everyone.
  const defaultOpen = await open(service, A, B, "privacy-default");
  assert.equal(defaultOpen.created, true);

  await db.doc(`users/${D}`).update({ messagePrivacy: "peopleYouFollow" });
  await assert.rejects(
    open(service, C, D, "privacy-follow-deny"),
    (error) => error.code === "permission-denied",
  );
  // The direction is recipient D -> sender C. C following D is not enough.
  await db.doc(`users/${C}/following/${D}`).set({
    uid: D,
    followedAt: Timestamp.now(),
  });
  await assert.rejects(
    open(service, C, D, "privacy-follow-wrong-way"),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${D}/following/${C}`).set({
    uid: C,
    followedAt: Timestamp.now(),
  });
  const followedOpen = await open(service, C, D, "privacy-follow-allow");
  assert.equal(followedOpen.created, true);

  await db.doc(`users/${B}`).update({ messagePrivacy: "friends" });
  await db.doc(`friendshipGuards/${A}/friends/${B}`).set({
    ownerId: A,
    friendId: B,
    schemaVersion: 1,
    establishedAt: Timestamp.now(),
  });
  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId: defaultOpen.conversationId,
      requestId: "privacy-one-guard",
      text: "one forged or stranded half must not be enough",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`friendshipGuards/${B}/friends/${A}`).set({
    ownerId: B,
    friendId: A,
    schemaVersion: 1,
    establishedAt: Timestamp.now(),
  });
  const friendSend = await service.sendDirectMessage(request(A, {
    conversationId: defaultOpen.conversationId,
    requestId: "privacy-two-guards",
    text: "both canonical halves allow a friend",
  }));
  assert.equal(friendSend.created, true);

  await db.doc(`users/${B}`).update({ messagePrivacy: "nobody" });
  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId: defaultOpen.conversationId,
      requestId: "privacy-nobody",
      text: "an existing thread is not a bypass",
    })),
    (error) => error.code === "permission-denied",
  );
  await assert.rejects(
    service.reserveDirectMessageAttachment(request(A, {
      conversationId: defaultOpen.conversationId,
      type: "voice",
      contentType: "audio/mp4",
      durationSeconds: 1,
      requestId: "privacy-nobody-media",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${D}`).update({ messagePrivacy: "nobody" });
  await assert.rejects(
    open(service, C, D, "privacy-nobody-open"),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${B}`).update({ messagePrivacy: "future-unknown-value" });
  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId: defaultOpen.conversationId,
      requestId: "privacy-malformed",
      text: "unknown values fail closed",
    })),
    (error) => error.code === "data-loss",
  );
});

test("changing message privacy during an upload prevents media finalization", async () => {
  const metadata = new Map();
  const service = directService({}, {
    storage: {
      async getMetadata(path) {
        return metadata.get(path);
      },
      getObjectReference(path) {
        return `gs://yovoice-test.appspot.com/${path}`;
      },
    },
  });
  const { conversationId } = await open(service, A, B, "privacy-media-open");
  const reserved = await service.reserveDirectMessageAttachment(request(A, {
    conversationId,
    type: "image",
    contentType: "image/png",
    requestId: "privacy-media-reserve",
  }));
  metadata.set(reserved.storagePath, {
    size: "2048",
    contentType: "image/png",
    generation: "21",
    metadata: {
      yovoiceConversationId: conversationId,
      yovoiceMessageId: reserved.messageId,
      yovoiceMessagePath:
        `conversations/${conversationId}/messages/${reserved.messageId}`,
      yovoiceMediaType: "image",
      yovoiceOwnerUid: A,
    },
  });

  await db.doc(`users/${B}`).update({ messagePrivacy: "nobody" });
  const finalizeInput = request(A, {
    conversationId,
    messageId: reserved.messageId,
    objectGeneration: "21",
    requestId: "privacy-media-finalize",
  });
  await assert.rejects(
    service.finalizeDirectMessageAttachment(finalizeInput),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await db.doc(
    `conversations/${conversationId}/messages/${reserved.messageId}`,
  ).get()).exists, false);
  assert.equal((await db.doc(
    `directMessageUploadReservations/${reserved.messageId}`,
  ).get()).exists, true);

  // The failed finalization is retry-safe: once the recipient deliberately
  // re-opens DMs, the same reservation/request id can complete exactly once.
  await db.doc(`users/${B}`).update({ messagePrivacy: "everyone" });
  const result = await service.finalizeDirectMessageAttachment(finalizeInput);
  assert.equal(result.created, true);
  assert.equal((await db.collection(
    `conversations/${conversationId}/messages`,
  ).get()).size, 1);
});

test("malformed canonical counters prevent partial sends", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  await db.doc(`conversations/${conversationId}`).update({
    [`unreadCounts.${B}`]: -1,
  });
  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId,
      requestId: "send-negative",
      text: "must fail",
    })),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.collection(`conversations/${conversationId}/messages`).get()).size,
    0,
  );
});

test("participant-owned preferences compose without lost updates", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  await Promise.all([
    service.setDirectConversationPreference(request(A, {
      conversationId,
      enabled: true,
      preference: "muted",
      requestId: "pref-alice1",
    })),
    service.setDirectConversationPreference(request(B, {
      conversationId,
      enabled: true,
      preference: "muted",
      requestId: "pref-bob001",
    })),
  ]);
  const conversation = await db.doc(`conversations/${conversationId}`).get();
  assert.deepEqual(conversation.data().mutedBy, [A, B]);
});

test("server-time fixed windows stop bursts while replay is free", async () => {
  const service = directService({
    open: { maxEvents: 2, windowMs: 1_000 },
  });
  await open(service, A, B, "open-limit1");
  await open(service, A, B, "open-limit1");
  await open(service, A, B, "open-limit2");
  await assert.rejects(
    open(service, A, B, "open-limit3"),
    (error) => error.code === "resource-exhausted",
  );
  nowMs += 1_001;
  const result = await open(service, A, B, "open-limit4");
  assert.equal(result.conversationId, canonicalConversationId(A, B));
});

test("BEFORE migration a legacy root is FORKED, not adopted — which is why the migration RUN is still outstanding", async () => {
  // Pins the pre-migration behaviour so the cost of not running the
  // migration is visible in the suite rather than only in production.
  // With a legacy root at `A_B` and no pair guard, `openDirectConversation`
  // falls back to the derived `dm_` id and binds THAT — the legacy thread
  // and its history are left behind untouched, not adopted. Only
  // `migrateDirectIntegrityConversation` adopts in place (the test
  // below). See ADR-062.
  const legacyId = `${A}_${B}`;
  const legacyRef = db.doc(`conversations/${legacyId}`);
  await legacyRef.set({
    participantIds: [A, B],
    participantNames: { [A]: "Legacy Alice", [B]: "Legacy Bob" },
    participantPhotoUrls: { [A]: "", [B]: "" },
    unreadCounts: { [A]: 0, [B]: 1 },
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "legacy",
    lastMessageType: "text",
    lastMessageSenderId: A,
    createdAt: Timestamp.fromMillis(nowMs - 10_000),
    updatedAt: Timestamp.fromMillis(nowMs - 5_000),
  });
  const legacyBefore = (await legacyRef.get()).data();
  assert.equal((await db.doc(
    `directConversationPairs/${canonicalPairKey(A, B)}`,
  ).get()).exists, false);

  const opened = await open(directService(), A, B, "open-prefork1");

  assert.equal(opened.conversationId, canonicalConversationId(A, B));
  assert.notEqual(opened.conversationId, legacyId);
  assert.equal(opened.created, true);

  // The legacy root is untouched — no adoption, no partial rewrite.
  assert.deepEqual((await legacyRef.get()).data(), legacyBefore);
  // And the pair is now bound to the NEW id, permanently, unless the
  // migration is run first.
  assert.equal(
    (await db.doc(`directConversationPairs/${canonicalPairKey(A, B)}`).get())
      .data().conversationId,
    canonicalConversationId(A, B),
  );
});

test("legacy history migrates in place and every guarded operation remains usable", async () => {
  const legacyId = `${A}_${B}`;
  const rootRef = db.doc(`conversations/${legacyId}`);
  await rootRef.set({
    participantIds: [A, B],
    participantNames: { [A]: "Legacy Alice", [B]: "Legacy Bob" },
    participantEmails: { [A]: "private@old.invalid", [B]: "private@old.invalid" },
    participantPhotoUrls: { [A]: "", [B]: "" },
    unreadCounts: { [A]: 0, [B]: 1 },
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "legacy",
    lastMessageType: "text",
    lastMessageSenderId: A,
    createdAt: Timestamp.fromMillis(nowMs - 10_000),
    updatedAt: Timestamp.fromMillis(nowMs - 5_000),
  });
  await rootRef.collection("messages").doc("legacy-message1").set({
    conversationId: legacyId,
    senderId: A,
    type: "text",
    content: "legacy",
    mediaUrl: null,
    durationSeconds: null,
    sentAt: Timestamp.fromMillis(nowMs - 5_000),
    readBy: [A],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  });
  const migrator = createDirectMigrationService({
    db,
    FieldPath,
    Timestamp,
    clock: () => nowMs,
  });
  const dryRun = await migrator.migrateDirectConversation({
    conversationId: legacyId,
    dryRun: true,
  });
  assert.equal(dryRun.status, "ready");
  assert.equal((await rootRef.get()).data().schemaVersion, undefined);
  const applied = await migrator.migrateDirectConversation({
    conversationId: legacyId,
    dryRun: false,
  });
  assert.equal(applied.status, "migrated");
  const migrated = await rootRef.get();
  assert.equal(migrated.data().schemaVersion, 2);
  assert.equal(migrated.data().participantEmails[A], "");
  assert.equal(migrated.data().lastMessageSequence, 1);
  assert.equal(
    (await rootRef.collection("messages").doc("legacy-message1").get())
      .data().sequence,
    1,
  );
  const migrationReplay = await migrator.migrateDirectConversation({
    conversationId: legacyId,
    dryRun: false,
  });
  assert.equal(migrationReplay.status, "alreadyMigrated");

  const service = directService();
  const opened = await open(service, A, B, "open-legacy1");
  assert.equal(opened.conversationId, legacyId);
  assert.equal(opened.created, false);
  const sent = await service.sendDirectMessage(request(A, {
    conversationId: legacyId,
    requestId: "send-legacy1",
    text: "new message",
  }));
  await service.editDirectMessage(request(A, {
    conversationId: legacyId,
    messageId: sent.messageId,
    requestId: "edit-legacy1",
    text: "edited new message",
  }));
  await service.setDirectTyping(request(B, {
    conversationId: legacyId,
    isTyping: true,
    requestId: "type-legacy1",
  }));
  await service.setDirectMessageReaction(request(B, {
    conversationId: legacyId,
    messageId: sent.messageId,
    emoji: "❤️",
    requestId: "react-legacy",
  }));
  const read = await service.markDirectConversationRead(request(B, {
    conversationId: legacyId,
    requestId: "read-legacy1",
  }));
  assert.equal(read.completed, true);
  assert.ok((await rootRef.collection("messages").doc(sent.messageId).get())
    .data().readBy.includes(B));
});

test("direct migration aborts atomically when a child changes after inspection", async () => {
  const legacyId = `${C}_${D}`;
  const rootRef = db.doc(`conversations/${legacyId}`);
  const messageRef = rootRef.collection("messages").doc("legacy-race-message");
  await rootRef.set({
    participantIds: [C, D],
    participantNames: { [C]: "Legacy C", [D]: "Legacy D" },
    participantEmails: { [C]: "c@old.invalid", [D]: "d@old.invalid" },
    participantPhotoUrls: { [C]: "", [D]: "" },
    unreadCounts: { [C]: 0, [D]: 1 },
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "before race",
    lastMessageType: "text",
    lastMessageSenderId: C,
    createdAt: Timestamp.fromMillis(nowMs - 10_000),
    updatedAt: Timestamp.fromMillis(nowMs - 5_000),
  });
  await messageRef.set({
    conversationId: legacyId,
    senderId: C,
    type: "text",
    content: "before race",
    mediaUrl: null,
    durationSeconds: null,
    sentAt: Timestamp.fromMillis(nowMs - 5_000),
    readBy: [C],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  });
  const migrator = createDirectMigrationService({
    db,
    FieldPath,
    Timestamp,
    clock: () => nowMs,
    beforeApply: async () => messageRef.update({ content: "raced" }),
  });
  await assert.rejects(
    migrator.migrateDirectConversation({
      conversationId: legacyId,
      dryRun: false,
    }),
    (error) => error.code === "aborted",
  );
  assert.equal((await rootRef.get()).data().schemaVersion, undefined);
  const message = (await messageRef.get()).data();
  assert.equal(message.schemaVersion, undefined);
  assert.equal(message.content, "raced");
});

test("missing or conflicting pair guards fail closed on every mutation", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  const sent = await service.sendDirectMessage(request(A, {
    conversationId,
    requestId: "send-guard01",
    text: "guarded",
  }));
  const guardRef = db.doc(`directConversationPairs/${canonicalPairKey(A, B)}`);
  await guardRef.delete();
  const operations = [
    () => service.sendDirectMessage(request(A, {
      conversationId,
      requestId: "send-noguard",
      text: "denied",
    })),
    () => service.editDirectMessage(request(A, {
      conversationId,
      messageId: sent.messageId,
      requestId: "edit-noguard",
      text: "denied",
    })),
    () => service.markDirectConversationRead(request(B, {
      conversationId,
      requestId: "read-noguard",
    })),
    () => service.setDirectTyping(request(B, {
      conversationId,
      isTyping: true,
      requestId: "type-noguard",
    })),
  ];
  for (const operation of operations) {
    await assert.rejects(operation(), (error) => error.code === "data-loss");
  }
  await guardRef.set({
    schemaVersion: 1,
    pairKey: canonicalPairKey(A, B),
    conversationId: "wrong-conversation",
    participantIds: [A, B],
    createdAt: Timestamp.fromMillis(nowMs),
  });
  await assert.rejects(
    service.setDirectConversationPreference(request(A, {
      conversationId,
      enabled: true,
      preference: "muted",
      requestId: "pref-badguard",
    })),
    (error) => error.code === "data-loss",
  );
});

test("legacy underscore collision is reported and never auto-applied", async () => {
  const ids = ["a", "b_c", "a_b", "c"];
  await Promise.all(ids.map((uid) => seed(uid)));
  const collisionId = "a_b_c";
  await db.doc(`conversations/${collisionId}`).set({
    participantIds: ["a_b", "c"],
    participantNames: { a_b: "AB", c: "C" },
    participantEmails: { a_b: "", c: "" },
    participantPhotoUrls: { a_b: "", c: "" },
    unreadCounts: { a_b: 0, c: 0 },
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "",
    lastMessageType: "text",
    lastMessageSenderId: "",
    createdAt: Timestamp.fromMillis(nowMs),
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  const migrator = createDirectMigrationService({
    db,
    FieldPath,
    Timestamp,
    clock: () => nowMs,
  });
  const result = await migrator.migrateDirectConversation({
    conversationId: collisionId,
    dryRun: false,
  });
  assert.equal(result.status, "conflict");
  assert.ok(result.issues.includes("legacyIdCollision"));
  assert.ok(result.conflictId);
  assert.equal((await db.doc(`conversations/${collisionId}`).get())
    .data().schemaVersion, undefined);
  assert.equal((await db.doc(
    `directConversationPairs/${canonicalPairKey("a_b", "c")}`,
  ).get()).exists, false);
  await Promise.all(ids.map((uid) => db.doc(`users/${uid}`).delete()));
  await Promise.all(ids.map((uid) => db.doc(`publicProfiles/${uid}`).delete()));
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(db.doc(`conversations/${collisionId}`));
  }
  await db.doc(`directMigrationConflicts/${result.conflictId}`).delete();
});

test("read receipts advance in bounded server cursors and reactions are actor-owned", async () => {
  const service = directService({}, { readPageSize: 2 });
  const { conversationId } = await open(service);
  const sent = [];
  for (let index = 0; index < 5; index += 1) {
    sent.push(await service.sendDirectMessage(request(A, {
      conversationId,
      requestId: `send-receipt${index}`,
      text: `receipt ${index}`,
    })));
  }
  const first = await service.markDirectConversationRead(request(B, {
    conversationId,
    requestId: "read-page001",
  }));
  assert.equal(first.completed, false);
  assert.equal((await db.doc(`conversations/${conversationId}`).get())
    .data().unreadCounts[B], 5);
  const replay = await service.markDirectConversationRead(request(B, {
    conversationId,
    requestId: "read-page001",
  }));
  assert.deepEqual(replay, first);
  let completed = false;
  for (let index = 2; index <= 4 && !completed; index += 1) {
    const result = await service.markDirectConversationRead(request(B, {
      conversationId,
      requestId: `read-page00${index}`,
    }));
    completed = result.completed;
  }
  assert.equal(completed, true);
  const messages = await db.collection(`conversations/${conversationId}/messages`).get();
  assert.equal(messages.docs.every((message) => message.data().readBy.includes(B)), true);
  assert.equal((await db.doc(`conversations/${conversationId}`).get())
    .data().unreadCounts[B], 0);

  const reaction = await service.setDirectMessageReaction(request(B, {
    conversationId,
    messageId: sent[0].messageId,
    emoji: "🔥",
    requestId: "react-owned1",
  }));
  assert.equal(reaction.changed, true);
  assert.deepEqual(
    (await db.doc(
      `conversations/${conversationId}/messages/${sent[0].messageId}`,
    ).get()).data().reactions,
    { [B]: "🔥" },
  );
  assert.deepEqual(
    await service.setDirectMessageReaction(request(B, {
      conversationId,
      messageId: sent[0].messageId,
      emoji: "🔥",
      requestId: "react-owned1",
    })),
    reaction,
  );
  await assert.rejects(
    service.setDirectMessageReaction(request(B, {
      conversationId,
      messageId: sent[0].messageId,
      emoji: "🔥".repeat(100),
      requestId: "react-too-big",
    })),
    (error) => error.code === "invalid-argument",
  );
});

test("counter overflow fails without a message write", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  await db.doc(`conversations/${conversationId}`).update({
    lastMessageSequence: Number.MAX_SAFE_INTEGER,
  });
  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId,
      requestId: "send-overflow",
      text: "must not commit",
    })),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.collection(`conversations/${conversationId}/messages`).get()).size,
    0,
  );
  await db.doc(`conversations/${conversationId}`).update({
    lastMessageSequence: 0,
    [`unreadCounts.${B}`]: Number.MAX_SAFE_INTEGER,
  });
  await assert.rejects(
    service.sendDirectMessage(request(A, {
      conversationId,
      requestId: "send-unread-overflow",
      text: "must not commit either",
    })),
    (error) => error.code === "data-loss",
  );
  assert.equal(
    (await db.collection(`conversations/${conversationId}/messages`).get()).size,
    0,
  );
});

test("typing rechecks peer activity and bilateral blocks", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  await db.doc(`users/${B}/blocked/${A}`).set({ userId: A });
  await assert.rejects(
    service.setDirectTyping(request(A, {
      conversationId,
      isTyping: true,
      requestId: "typing-blocked",
    })),
    (error) => error.code === "failed-precondition",
  );
  assert.deepEqual(
    (await db.doc(`conversations/${conversationId}`).get()).data().typing,
    {},
  );
  await db.doc(`users/${B}/blocked/${A}`).delete();
  await db.doc(`users/${B}`).update({ disabled: true });
  await assert.rejects(
    service.setDirectTyping(request(A, {
      conversationId,
      isTyping: true,
      requestId: "typing-inactive",
    })),
    (error) => error.code === "permission-denied",
  );
});

test("canonical message schema passes while extra or missing keys fail closed", async () => {
  const service = directService();
  const { conversationId } = await open(service);
  const sent = await service.sendDirectMessage(request(A, {
    conversationId,
    requestId: "send-schema01",
    text: "canonical",
  }));
  await service.editDirectMessage(request(A, {
    conversationId,
    messageId: sent.messageId,
    requestId: "edit-schema01",
    text: "still canonical",
  }));
  const messageRef = db.doc(
    `conversations/${conversationId}/messages/${sent.messageId}`,
  );
  await messageRef.update({ injectedAdmin: true });
  await assert.rejects(
    service.setDirectMessageReaction(request(B, {
      conversationId,
      messageId: sent.messageId,
      emoji: "👍",
      requestId: "react-extra01",
    })),
    (error) => error.code === "data-loss",
  );
  await messageRef.update({
    injectedAdmin: FieldValue.delete(),
    replyToContent: FieldValue.delete(),
  });
  await assert.rejects(
    service.editDirectMessage(request(A, {
      conversationId,
      messageId: sent.messageId,
      requestId: "edit-missing1",
      text: "must fail",
    })),
    (error) => error.code === "data-loss",
  );
});

const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DEFAULT_COMMUNITY_LIMITS,
  createCommunityMessagingService,
} = require("../messaging/community_integrity");

const db = getFirestore();
const ALICE = "community-alice";
const BOB = "community-bob";
const GUEST = "community-guest";
const ROOM = "community-room";
const ROOM_TWO = "community-room-two";
const PRIVATE_ROOM = "private-community-room";
const CLUB = "community-club";
const CHANNEL = "general";
let nowMs = 1_900_000_000_000;

function request(uid, data, verified = true) {
  return {
    auth: {
      uid,
      token: { email_verified: verified, email: `${uid}@example.invalid` },
    },
    data,
  };
}

function service(limitOverrides = {}) {
  return createCommunityMessagingService({
    db,
    Timestamp,
    clock: () => nowMs,
    limits: { ...DEFAULT_COMMUNITY_LIMITS, ...limitOverrides },
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
  await Promise.all([
    ...[ALICE, BOB, GUEST].map((uid) => db.doc(`users/${uid}`).delete()),
    ...[ALICE, BOB, GUEST].map((uid) => db.doc(`restrictions/${uid}`).delete()),
    ...[ROOM, ROOM_TWO, PRIVATE_ROOM].map(async (roomId) => {
      const reference = db.doc(`rooms/${roomId}`);
      if (typeof db.recursiveDelete === "function") {
        await db.recursiveDelete(reference);
      } else {
        await reference.delete();
      }
    }),
    (async () => {
      const reference = db.doc(`clubs/${CLUB}`);
      if (typeof db.recursiveDelete === "function") {
        await db.recursiveDelete(reference);
      } else {
        await reference.delete();
      }
    })(),
    deleteQuery(db.collection("integrityOperationLedgers")),
    deleteQuery(db.collection("privateRateLimits")),
    deleteQuery(db.collection("privateRoomMessageCooldowns")),
  ]);
}

async function seedUser(uid, overrides = {}) {
  await db.doc(`users/${uid}`).set({
    uid,
    displayName: `Name ${uid}`,
    banned: false,
    disabled: false,
    deleted: false,
    ...overrides,
  });
}

async function seedRoom({
  roomId = ROOM,
  hostId = ALICE,
  visibility = "public",
  slowModeSeconds = 0,
  clubId = null,
} = {}) {
  await db.doc(`rooms/${roomId}`).set({
    hostId,
    name: roomId,
    visibility,
    status: "active",
    isLive: false,
    roomType: "community",
    slowModeSeconds,
    updatedAt: Timestamp.fromMillis(nowMs - 1000),
    ...(clubId ? { clubId, roomKind: "clubLounge" } : {}),
  });
  await db.doc(`rooms/${roomId}/roomMembers/${hostId}`).set({
    userId: hostId,
    role: "owner",
    displayName: `Name ${hostId}`,
  });
}

async function addRoomMember(roomId, uid, overrides = {}) {
  await db.doc(`rooms/${roomId}/roomMembers/${uid}`).set({
    userId: uid,
    role: "member",
    displayName: `Name ${uid}`,
    ...overrides,
  });
}

async function addParticipant(roomId, uid, overrides = {}) {
  await db.doc(`rooms/${roomId}/participants/${uid}`).set({
    userId: uid,
    role: "speaker",
    displayName: `Name ${uid}`,
    ...overrides,
  });
}

async function seedClub() {
  await db.doc(`clubs/${CLUB}`).set({
    ownerId: ALICE,
    name: "Community Club",
    status: "active",
    deletionInProgress: false,
  });
  await Promise.all([
    db.doc(`clubs/${CLUB}/members/${ALICE}`).set({
      userId: ALICE,
      role: "owner",
      displayName: `Name ${ALICE}`,
    }),
    db.doc(`clubs/${CLUB}/members/${BOB}`).set({
      userId: BOB,
      role: "member",
      displayName: `Name ${BOB}`,
    }),
    db.doc(`clubs/${CLUB}/members/${GUEST}`).set({
      userId: GUEST,
      role: "guest",
      displayName: `Name ${GUEST}`,
    }),
    db.doc(`clubs/${CLUB}/channels/${CHANNEL}`).set({
      name: "General",
      type: "chat",
    }),
  ]);
}

beforeEach(async () => {
  nowMs = 1_900_000_000_000;
  await reset();
  await Promise.all([seedUser(ALICE), seedUser(BOB), seedUser(GUEST)]);
  await Promise.all([seedRoom(), seedClub()]);
  await addRoomMember(ROOM, BOB);
});

after(reset);

test("room send derives identity, nulls media and replays exactly once", async () => {
  const messaging = service();
  const payload = {
    requestId: "room-send-0001",
    roomId: ROOM,
    text: "  hello room  ",
  };
  const first = await messaging.sendRoomMessage(request(BOB, payload));
  const replay = await messaging.sendRoomMessage(request(BOB, payload));
  assert.deepEqual(replay, first);

  const messages = await db.collection(`rooms/${ROOM}/messages`).get();
  assert.equal(messages.size, 1);
  assert.deepEqual(messages.docs[0].data(), {
    senderId: BOB,
    senderName: `Name ${BOB}`,
    senderPhotoUrl: null,
    text: "hello room",
    createdAt: Timestamp.fromMillis(nowMs),
    reactions: {},
  });

  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, { ...payload, text: "changed" })),
    (error) => error.code === "already-exists",
  );
  assert.equal((await db.collection(`rooms/${ROOM}/messages`).get()).size, 1);
});

test("concurrent duplicate room sends create one message and one ledger", async () => {
  const messaging = service();
  const payload = {
    requestId: "room-race-0001",
    roomId: ROOM,
    text: "one event",
  };
  const results = await Promise.all(
    Array.from({ length: 8 }, () => messaging.sendRoomMessage(request(BOB, payload))),
  );
  assert.equal(new Set(results.map((result) => result.messageId)).size, 1);
  assert.equal((await db.collection(`rooms/${ROOM}/messages`).get()).size, 1);
  assert.equal((await db.collection("integrityOperationLedgers").get()).size, 1);
});

test("room scope N+1 is atomic and separate users/resources remain independent", async () => {
  const messaging = service({
    roomScope: { maxEvents: 2, windowMs: 10_000 },
    roomAttempt: { maxEvents: 20, windowMs: 60_000 },
  });
  await seedRoom({ roomId: ROOM_TWO });
  await addRoomMember(ROOM_TWO, BOB);
  for (let index = 0; index < 2; index += 1) {
    await messaging.sendRoomMessage(request(BOB, {
      requestId: `room-limit-000${index}`,
      roomId: ROOM,
      text: `message ${index}`,
    }));
  }
  const before = await db.collection("privateRateLimits").get();
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "room-limit-0002",
      roomId: ROOM,
      text: "denied",
    })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await db.collection(`rooms/${ROOM}/messages`).get()).size, 2);
  assert.equal((await db.collection("privateRateLimits").get()).size, before.size);

  await messaging.sendRoomMessage(request(BOB, {
    requestId: "room-other-0001",
    roomId: ROOM_TWO,
    text: "other room",
  }));
  await messaging.sendRoomMessage(request(ALICE, {
    requestId: "room-alice-0001",
    roomId: ROOM,
    text: "other user",
  }));
  assert.equal((await db.collection(`rooms/${ROOM_TWO}/messages`).get()).size, 1);
  assert.equal((await db.collection(`rooms/${ROOM}/messages`).get()).size, 3);
});

test("room slow mode denies a second member send but exempts the host", async () => {
  await db.doc(`rooms/${ROOM}`).update({ slowModeSeconds: 30 });
  const messaging = service();
  await messaging.sendRoomMessage(request(BOB, {
    requestId: "room-slow-0001",
    roomId: ROOM,
    text: "first",
  }));
  nowMs += 1000;
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "room-slow-0002",
      roomId: ROOM,
      text: "too soon",
    })),
    (error) => error.code === "resource-exhausted",
  );
  await messaging.sendRoomMessage(request(ALICE, {
    requestId: "room-slow-host",
    roomId: ROOM,
    text: "host response",
  }));
  nowMs += 30_000;
  await messaging.sendRoomMessage(request(BOB, {
    requestId: "room-slow-0003",
    roomId: ROOM,
    text: "after cooldown",
  }));
  assert.equal((await db.collection(`rooms/${ROOM}/messages`).get()).size, 3);
});

test("private room requires canonical membership or host admission", async () => {
  await seedRoom({ roomId: PRIVATE_ROOM, visibility: "private" });
  await addParticipant(PRIVATE_ROOM, BOB);
  const messaging = service();
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "private-deny-0001",
      roomId: PRIVATE_ROOM,
      text: "not admitted",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`rooms/${PRIVATE_ROOM}/participants/${BOB}`).update({
    admittedBy: ALICE,
  });
  await messaging.sendRoomMessage(request(BOB, {
    requestId: "private-allow-0001",
    roomId: PRIVATE_ROOM,
    text: "admitted",
  }));
  assert.equal(
    (await db.collection(`rooms/${PRIVATE_ROOM}/messages`).get()).size,
    1,
  );
});

test("Club lounge rejects a guest even with a forged participant row", async () => {
  await seedRoom({ roomId: PRIVATE_ROOM, visibility: "private", clubId: CLUB });
  await addParticipant(PRIVATE_ROOM, GUEST);
  const messaging = service();
  await assert.rejects(
    messaging.sendRoomMessage(request(GUEST, {
      requestId: "lounge-guest-0001",
      roomId: PRIVATE_ROOM,
      text: "guest injection",
    })),
    (error) => error.code === "permission-denied",
  );
  assert.equal(
    (await db.collection(`rooms/${PRIVATE_ROOM}/messages`).get()).size,
    0,
  );
});

test("room send rejects unverified, inactive, muted and malformed authority", async () => {
  const messaging = service();
  const payload = {
    requestId: "room-auth-0001",
    roomId: ROOM,
    text: "blocked",
  };
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, payload, false)),
    (error) => error.code === "failed-precondition",
  );
  await db.doc(`users/${BOB}`).update({ authDeletedAt: Timestamp.fromMillis(nowMs) });
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, { ...payload, requestId: "room-auth-0002" })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${BOB}`).update({ authDeletedAt: null });
  await db.doc(`restrictions/${BOB}`).set({ type: "communicationMute", expiresAt: null });
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, { ...payload, requestId: "room-auth-0003" })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`restrictions/${BOB}`).delete();
  await db.doc(`rooms/${ROOM}/roomMembers/${BOB}`).update({ userId: ALICE });
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, { ...payload, requestId: "room-auth-0004" })),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await db.collection(`rooms/${ROOM}/messages`).get()).size, 0);
});

test("denied room attempts consume a durable target-independent quota", async () => {
  const messaging = service({
    roomAttempt: { maxEvents: 2, windowMs: 60_000 },
  });
  for (let index = 0; index < 2; index += 1) {
    await assert.rejects(
      messaging.sendRoomMessage(request(BOB, {
        requestId: `missing-room-${index}`,
        roomId: `missing-room-${index}`,
        text: "probe",
      })),
      (error) => error.code === "not-found",
    );
  }

  const attempt = (await db.collection("privateRateLimits")
    .where("scope", "==", "room.message.send.attempt")
    .where("ownerId", "==", BOB)
    .get()).docs[0];
  assert.ok(attempt);
  assert.equal(attempt.data().count, 2);

  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "missing-room-blocked-before-target",
      roomId: "another-missing-room",
      text: "probe",
    })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await attempt.ref.get()).data().count, 2);
});

test("authorization, restriction and slow-mode denials all charge attempts", async () => {
  const messaging = service({
    roomAttempt: { maxEvents: 5, windowMs: 60_000 },
  });
  await seedRoom({ roomId: PRIVATE_ROOM, visibility: "private" });
  await addParticipant(PRIVATE_ROOM, BOB);
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "attempt-private-denied",
      roomId: PRIVATE_ROOM,
      text: "denied",
    })),
    (error) => error.code === "permission-denied",
  );

  await db.doc(`users/${BOB}`).update({ authDeletedAt: Timestamp.fromMillis(nowMs) });
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "attempt-inactive-denied",
      roomId: ROOM,
      text: "denied",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${BOB}`).update({ authDeletedAt: null });

  await db.doc(`restrictions/${BOB}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "attempt-muted-denied",
      roomId: ROOM,
      text: "denied",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`restrictions/${BOB}`).delete();

  await db.doc(`rooms/${ROOM}`).update({ slowModeSeconds: 30 });
  const successfulPayload = {
    requestId: "attempt-success",
    roomId: ROOM,
    text: "first",
  };
  const successfulResult = await messaging.sendRoomMessage(
    request(BOB, successfulPayload),
  );
  assert.deepEqual(
    await messaging.sendRoomMessage(request(BOB, successfulPayload)),
    successfulResult,
  );
  await assert.rejects(
    messaging.sendRoomMessage(request(BOB, {
      requestId: "attempt-slow-mode-denied",
      roomId: ROOM,
      text: "too soon",
    })),
    (error) => error.code === "resource-exhausted",
  );

  const attempt = (await db.collection("privateRateLimits")
    .where("scope", "==", "room.message.send.attempt")
    .where("ownerId", "==", BOB)
    .get()).docs[0];
  assert.ok(attempt);
  // Three authorization denials + one success + one slow-mode denial.
  // Replaying the completed success is intentionally free.
  assert.equal(attempt.data().count, 5);
});

test("club send is canonical, idempotent and rejects guests or wrong channels", async () => {
  const messaging = service();
  const payload = {
    channelId: CHANNEL,
    clubId: CLUB,
    requestId: "club-send-0001",
    text: "  hello club  ",
  };
  const first = await messaging.sendClubMessage(request(BOB, payload));
  assert.deepEqual(await messaging.sendClubMessage(request(BOB, payload)), first);
  const messages = await db.collection(
    `clubs/${CLUB}/channels/${CHANNEL}/messages`,
  ).get();
  assert.equal(messages.size, 1);
  assert.deepEqual(messages.docs[0].data(), {
    clubId: CLUB,
    channelId: CHANNEL,
    senderId: BOB,
    senderName: `Name ${BOB}`,
    senderPhotoUrl: null,
    content: "hello club",
    sentAt: Timestamp.fromMillis(nowMs),
    editedAt: null,
    isDeleted: false,
  });

  await assert.rejects(
    messaging.sendClubMessage(request(GUEST, {
      ...payload,
      requestId: "club-guest-0001",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`clubs/${CLUB}/channels/voice-only`).set({ type: "voice" });
  await assert.rejects(
    messaging.sendClubMessage(request(BOB, {
      ...payload,
      channelId: "voice-only",
      requestId: "club-voice-0001",
    })),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(messages.size, 1);
});

test("announcement channel accepts moderators but rejects ordinary members", async () => {
  const announcement = "announcements";
  await db.doc(`clubs/${CLUB}/channels/${announcement}`).set({
    name: "Announcements",
    type: "announcement",
  });
  const messaging = service();
  await assert.rejects(
    messaging.sendClubMessage(request(BOB, {
      channelId: announcement,
      clubId: CLUB,
      requestId: "announcement-member",
      text: "member injection",
    })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`clubs/${CLUB}/members/${BOB}`).update({ role: "moderator" });
  await messaging.sendClubMessage(request(BOB, {
    channelId: announcement,
    clubId: CLUB,
    requestId: "announcement-moderator",
    text: "authorized notice",
  }));
  assert.equal(
    (await db.collection(
      `clubs/${CLUB}/channels/${announcement}/messages`,
    ).get()).size,
    1,
  );
});

test("invalid Club targets consume a durable target-independent quota", async () => {
  const messaging = service({
    clubAttempt: { maxEvents: 2, windowMs: 60_000 },
  });
  for (let index = 0; index < 2; index += 1) {
    await assert.rejects(
      messaging.sendClubMessage(request(BOB, {
        channelId: `missing-channel-${index}`,
        clubId: CLUB,
        requestId: `missing-club-target-${index}`,
        text: "probe",
      })),
      (error) => error.code === "not-found",
    );
  }

  const attempt = (await db.collection("privateRateLimits")
    .where("scope", "==", "club.message.send.attempt")
    .where("ownerId", "==", BOB)
    .get()).docs[0];
  assert.ok(attempt);
  assert.equal(attempt.data().count, 2);
  await assert.rejects(
    messaging.sendClubMessage(request(BOB, {
      channelId: "another-missing-channel",
      clubId: CLUB,
      requestId: "missing-club-target-blocked",
      text: "probe",
    })),
    (error) => error.code === "resource-exhausted",
  );
});

test("club N+1 and concurrent replay do not create extra messages", async () => {
  const messaging = service({
    clubScope: { maxEvents: 2, windowMs: 10_000 },
    clubAttempt: { maxEvents: 20, windowMs: 60_000 },
  });
  const duplicate = {
    channelId: CHANNEL,
    clubId: CLUB,
    requestId: "club-race-0001",
    text: "race",
  };
  const results = await Promise.all(
    Array.from({ length: 6 }, () => messaging.sendClubMessage(request(BOB, duplicate))),
  );
  assert.equal(new Set(results.map((result) => result.messageId)).size, 1);
  await messaging.sendClubMessage(request(BOB, {
    ...duplicate,
    requestId: "club-limit-0001",
    text: "second",
  }));
  await assert.rejects(
    messaging.sendClubMessage(request(BOB, {
      ...duplicate,
      requestId: "club-limit-0002",
      text: "denied",
    })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(
    (await db.collection(`clubs/${CLUB}/channels/${CHANNEL}/messages`).get()).size,
    2,
  );
});

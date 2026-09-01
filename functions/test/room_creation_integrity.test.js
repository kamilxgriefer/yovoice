const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  FieldValue,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const {
  DEFAULT_ROOM_CREATION_POLICY,
  boundedLegacyRoomQuery,
  canonicalRoomId,
  createRoomCreationService,
} = require("../rooms/creation");
const {
  adaptCommunityJoined,
  adaptRoomCreated,
} = require("../achievements/sources");

const db = getFirestore();
const HOST = "room-integrity-host";
const MEMBER = "room-integrity-member";
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

function input(requestId, overrides = {}) {
  return {
    requestId,
    name: "Canonical room",
    description: "A bounded room",
    category: "talk",
    visibility: "public",
    language: "English",
    maxParticipants: 50,
    roomType: "community",
    targetAudience: "everyone",
    topicTags: ["voice"],
    roomGuidelines: "Be kind",
    conversationStyle: null,
    newcomerFriendly: false,
    showFormat: null,
    experience: "community",
    topic: "",
    audienceCanSpeak: true,
    handRaisingEnabled: false,
    ...overrides,
  };
}

function service(overrides = {}) {
  return createRoomCreationService({
    db,
    FieldValue,
    Timestamp,
    clock: () => nowMs,
    policy: { ...DEFAULT_ROOM_CREATION_POLICY, ...overrides },
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
  for (const uid of [HOST, MEMBER]) {
    await Promise.all([
      db.doc(`users/${uid}`).delete(),
      db.doc(`restrictions/${uid}`).delete(),
      db.doc(`privateRoomHostGuards/${uid}`).delete(),
      deleteQuery(db.collection("integrityOperationLedgers")
        .where("ownerId", "==", uid)),
      deleteQuery(db.collection("privateRoomCreationAttempts")
        .where("ownerId", "==", uid)),
      deleteQuery(db.collection("privateRoomVoiceStartAttempts")
        .where("ownerId", "==", uid)),
      deleteQuery(db.collection("privateRateLimits")
        .where("ownerId", "==", uid)),
      deleteQuery(db.collection("privateRoomVoiceStartGuards")
        .where("ownerId", "==", uid)),
      deleteQuery(db.collection("rooms").where("hostId", "==", uid)),
    ]);
  }
  await deleteQuery(db.collection("privateRoomVoiceStartGuards"));
  const dormant = db.doc("rooms/room-integrity-dormant");
  if (typeof db.recursiveDelete === "function") await db.recursiveDelete(dormant);
  else await dormant.delete();
  const club = db.doc("clubs/room-integrity-club");
  if (typeof db.recursiveDelete === "function") await db.recursiveDelete(club);
  else {
    await club.collection("members").doc(MEMBER).delete();
    await club.delete();
  }
}

async function seedUser(uid = HOST, overrides = {}) {
  await db.doc(`users/${uid}`).set({
    uid,
    displayName: uid === HOST ? "Canonical Host" : "Canonical Member",
    photoUrl: "https://private.invalid/never-copy.png",
    ...overrides,
  });
}

beforeEach(async () => {
  nowMs = 1_900_000_000_000;
  await reset();
  await Promise.all([seedUser(HOST), seedUser(MEMBER)]);
});

after(reset);

test("createRoom emits the exact canonical root and community owner graph", async () => {
  const result = await service().createRoom(request(HOST, input("create-exact-0001")));
  const roomSnapshot = await db.doc(`rooms/${result.roomId}`).get();
  const room = roomSnapshot.data();
  assert.equal(result.roomId, canonicalRoomId(HOST, "create-exact-0001"));
  assert.deepEqual(Object.keys(room).sort(), [
    "approvalRequired", "audienceCanSpeak", "autoMuteNewUsers", "category",
    "createdAt", "description", "experience", "handRaisingEnabled",
    "hostId", "hostName", "hostPhotoUrl", "imageUrl", "isLive", "language",
    "maxParticipants", "memberCount", "membersCanStartVoice", "name",
    "participantCount", "roomGuidelines", "roomType", "slowModeSeconds",
    "stageLimit", "status", "targetAudience", "topic", "topicTags",
    "updatedAt", "visibility",
  ].sort());
  assert.equal(room.hostName, "Canonical Host");
  assert.equal(room.hostPhotoUrl, null);
  assert.equal(room.imageUrl, null);
  assert.equal(room.isLive, false);
  assert.equal(room.memberCount, 1);
  assert.equal(room.participantCount, 0);

  const ownerSnapshot = await db.doc(
    `rooms/${result.roomId}/roomMembers/${HOST}`,
  ).get();
  assert.deepEqual(Object.keys(ownerSnapshot.data()).sort(), [
    "displayName", "joinedAt", "photoUrl", "role", "userId",
  ]);
  assert.equal(ownerSnapshot.data().photoUrl, null);
  assert.equal(ownerSnapshot.data().role, "owner");
  assert.ok(adaptRoomCreated({
    roomId: result.roomId,
    room,
    sourceCreatedAt: roomSnapshot.createTime,
  }));
  assert.ok(adaptCommunityJoined({
    kind: "room",
    communityId: result.roomId,
    userId: HOST,
    sourceCreatedAt: ownerSnapshot.createTime,
  }));
});

test("temporary create atomically emits the exact host participant", async () => {
  const result = await service().createRoom(request(HOST, input(
    "create-temp-0001",
    { roomType: "temporary" },
  )));
  const room = (await db.doc(`rooms/${result.roomId}`).get()).data();
  assert.equal(room.isLive, true);
  assert.equal(room.participantCount, 1);
  assert.equal(room.memberCount, 0);
  const participant = (await db.doc(
    `rooms/${result.roomId}/participants/${HOST}`,
  ).get()).data();
  assert.deepEqual(Object.keys(participant).sort(), [
    "displayName", "isHandRaised", "isMuted", "isSpeaker", "joinedAt",
    "photoUrl", "role", "updatedAt", "userId",
  ]);
  assert.equal(participant.photoUrl, null);
  assert.equal(participant.role, "host");
});

test("global N/N+1 quota is committed before capacity graph reads", async () => {
  const create = service({ maxEvents: 2, maxActiveRooms: 10 });
  await create.createRoom(request(HOST, input("quota-room-0001")));
  await create.createRoom(request(HOST, input("quota-room-0002")));
  await assert.rejects(
    create.createRoom(request(HOST, input("quota-room-0003"))),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await db.collection("rooms").where("hostId", "==", HOST).get()).size, 2);
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).docs[0].data();
  assert.equal(rate.scope, "room.create.global");
  assert.equal(rate.count, 2);
  assert.equal((await db.collection("privateRoomCreationAttempts")
    .where("ownerId", "==", HOST).get()).size, 0);
});

test("same request replays once; conflicting reuse fails without a mutation", async () => {
  const create = service();
  const first = await create.createRoom(request(HOST, input("replay-room-0001")));
  assert.deepEqual(
    await create.createRoom(request(HOST, input("replay-room-0001"))),
    first,
  );
  await assert.rejects(
    create.createRoom(request(HOST, input("replay-room-0001", {
      name: "Conflicting room",
    }))),
    (error) => error.code === "already-exists",
  );
  assert.equal((await db.collection("rooms").where("hostId", "==", HOST).get()).size, 1);
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).docs[0].data();
  assert.equal(rate.count, 1);
});

test("concurrent duplicate requests produce one root and one roster row", async () => {
  const create = service();
  const results = await Promise.all(Array.from({ length: 8 }, () =>
    create.createRoom(request(HOST, input("concurrent-room-0001")))));
  assert.equal(new Set(results.map((result) => result.roomId)).size, 1);
  const roomId = results[0].roomId;
  assert.equal((await db.collection("rooms").where("hostId", "==", HOST).get()).size, 1);
  assert.equal((await db.collection(`rooms/${roomId}/roomMembers`).get()).size, 1);
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).docs[0].data();
  assert.equal(rate.count, 1);
});

test("active cap denies atomically, charges attempts, and prunes a closed room", async () => {
  const create = service({ maxActiveRooms: 2, maxEvents: 6 });
  const first = await create.createRoom(request(HOST, input("cap-room-0001")));
  await create.createRoom(request(HOST, input("cap-room-0002")));
  await assert.rejects(
    create.createRoom(request(HOST, input("cap-room-0003"))),
    (error) => error.code === "resource-exhausted",
  );
  await assert.rejects(
    create.createRoom(request(HOST, input("cap-room-0003"))),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await db.collection("rooms").where("hostId", "==", HOST).get()).size, 2);
  let rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).docs[0].data();
  assert.equal(rate.count, 3, "a replayed capacity denial is not charged twice");
  await db.doc(`rooms/${first.roomId}`).update({ status: "closed" });
  const replacement = await create.createRoom(request(HOST, input("cap-room-0004")));
  assert.ok((await db.doc(`rooms/${replacement.roomId}`).get()).exists);
  rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).docs[0].data();
  assert.equal(rate.count, 4);
});

test("inactive and communication-restricted actors leave no integrity mutation", async () => {
  await db.doc(`restrictions/${HOST}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    service().createRoom(request(HOST, input("restricted-room-0001"))),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await db.collection("rooms").where("hostId", "==", HOST).get()).size, 0);
  assert.equal((await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).size, 0);
  assert.equal((await db.collection("privateRoomCreationAttempts")
    .where("ownerId", "==", HOST).get()).size, 0);
  assert.equal((await db.collection("integrityOperationLedgers")
    .where("ownerId", "==", HOST).get()).size, 0);
  assert.equal((await db.doc(`privateRoomHostGuards/${HOST}`).get()).exists, false);
});

test("legacy bootstrap query is hard-bounded even for a conceptual 10k graph", () => {
  const calls = [];
  const fakeQuery = {
    where(field, operator, value) {
      calls.push(["where", field, operator, value]);
      return this;
    },
    limit(value) {
      calls.push(["limit", value]);
      return this;
    },
  };
  const fakeDb = {
    collection(name) {
      assert.equal(name, "rooms");
      return fakeQuery;
    },
  };
  const conceptualLegacyGraph = Array.from({ length: 10_000 });
  assert.equal(conceptualLegacyGraph.length, 10_000);
  assert.equal(boundedLegacyRoomQuery(fakeDb, HOST, 20), fakeQuery);
  assert.deepEqual(calls.at(-1), ["limit", 21]);
});

test("unknown input and unverified actors fail before quota admission", async () => {
  await assert.rejects(
    service().createRoom(request(HOST, {
      ...input("unknown-room-0001"),
      hostId: MEMBER,
    })),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    service().createRoom(request(
      HOST,
      input("unverified-room-0001"),
      false,
    )),
    (error) => error.code === "failed-precondition",
  );
  assert.equal((await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).size, 0);
});

function startInput(requestId, sessionId = `${requestId}-session`) {
  return { requestId, roomId: "room-integrity-dormant", sessionId };
}

async function seedDormantRoom(overrides = {}) {
  await db.doc("rooms/room-integrity-dormant").set({
    hostId: HOST,
    hostName: "Canonical Host",
    name: "Dormant room",
    visibility: "public",
    status: "active",
    roomType: "community",
    experience: "community",
    isLive: false,
    participantCount: 0,
    memberCount: 1,
    ...overrides,
  });
}

test("startRoomVoice creates one canonical session and replays idempotently", async () => {
  await seedDormantRoom();
  const start = service();
  const payload = startInput("voice-start-0001", "voice-session-0001");
  const first = await start.startRoomVoice(request(HOST, payload));
  assert.deepEqual(first, {
    schemaVersion: 1,
    roomId: "room-integrity-dormant",
    sessionId: "voice-session-0001",
    started: true,
  });
  assert.deepEqual(await start.startRoomVoice(request(HOST, payload)), first);
  const room = (await db.doc("rooms/room-integrity-dormant").get()).data();
  assert.equal(room.isLive, true);
  assert.equal(room.voiceSessionId, "voice-session-0001");
  assert.equal(room.endedAt, undefined);
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST)
    .where("scope", "==", "room.voice.start.global").get()).docs[0].data();
  assert.equal(rate.count, 1);
  await assert.rejects(
    start.startRoomVoice(request(HOST, {
      ...payload,
      sessionId: "voice-session-conflict",
    })),
    (error) => error.code === "already-exists",
  );
});

test("concurrent voice-start replay produces one session and one quota event", async () => {
  await seedDormantRoom();
  const start = service();
  const payload = startInput("voice-concurrent-0001", "voice-session-race");
  const results = await Promise.all(Array.from({ length: 8 }, () =>
    start.startRoomVoice(request(HOST, payload))));
  assert.equal(new Set(results.map((result) => result.sessionId)).size, 1);
  const ledgers = await db.collection("integrityOperationLedgers")
    .where("ownerId", "==", HOST)
    .where("kind", "==", "room.voice.start").get();
  assert.equal(ledgers.size, 1);
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST)
    .where("scope", "==", "room.voice.start.global").get()).docs[0].data();
  assert.equal(rate.count, 1);
});

test("voice cooldown denial is committed, retry-safe and does not relaunch", async () => {
  await seedDormantRoom();
  const start = service({ startCooldownMs: 60_000, startMaxEvents: 5 });
  await start.startRoomVoice(request(
    HOST,
    startInput("voice-cooldown-0001", "voice-session-first"),
  ));
  await db.doc("rooms/room-integrity-dormant").update({ isLive: false });
  const denied = startInput("voice-cooldown-0002", "voice-session-denied");
  await assert.rejects(
    start.startRoomVoice(request(HOST, denied)),
    (error) => error.code === "resource-exhausted",
  );
  await assert.rejects(
    start.startRoomVoice(request(HOST, denied)),
    (error) => error.code === "resource-exhausted",
  );
  let room = (await db.doc("rooms/room-integrity-dormant").get()).data();
  assert.equal(room.isLive, false);
  assert.equal(room.voiceSessionId, "voice-session-first");
  let rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST)
    .where("scope", "==", "room.voice.start.global").get()).docs[0].data();
  assert.equal(rate.count, 2, "cooldown replay is not charged twice");

  nowMs += 60_001;
  const recovered = await start.startRoomVoice(request(
    HOST,
    startInput("voice-cooldown-0003", "voice-session-after-wait"),
  ));
  assert.equal(recovered.started, true);
  room = (await db.doc("rooms/room-integrity-dormant").get()).data();
  assert.equal(room.voiceSessionId, "voice-session-after-wait");
  rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST)
    .where("scope", "==", "room.voice.start.global").get()).docs[0].data();
  assert.equal(rate.count, 3);
});

test("active club members retain server-authorized lounge start", async () => {
  await seedDormantRoom({
    hostId: "another-host",
    clubId: "room-integrity-club",
    roomKind: "clubLounge",
    visibility: "private",
  });
  await db.doc("clubs/room-integrity-club").set({
    status: "active",
    deletionInProgress: false,
  });
  await db.doc(`clubs/room-integrity-club/members/${MEMBER}`).set({
    userId: MEMBER,
    role: "member",
    banned: false,
  });
  const result = await service().startRoomVoice(request(
    MEMBER,
    startInput("voice-club-0001", "voice-club-session"),
  ));
  assert.equal(result.started, true);
});

test("voice cooldown is shared by every actor authorized for one host-room", async () => {
  await seedDormantRoom({
    hostId: "another-host",
    clubId: "room-integrity-club",
    roomKind: "clubLounge",
    visibility: "private",
  });
  await db.doc("clubs/room-integrity-club").set({
    status: "active",
    deletionInProgress: false,
  });
  for (const uid of [HOST, MEMBER]) {
    await db.doc(`clubs/room-integrity-club/members/${uid}`).set({
      userId: uid,
      role: "member",
      banned: false,
    });
  }
  const start = service({ startCooldownMs: 60_000 });
  await start.startRoomVoice(request(
    MEMBER,
    startInput("voice-shared-cooldown-0001", "voice-shared-session-first"),
  ));
  await db.doc("rooms/room-integrity-dormant").update({ isLive: false });
  await assert.rejects(
    start.startRoomVoice(request(
      HOST,
      startInput("voice-shared-cooldown-0002", "voice-shared-session-second"),
    )),
    (error) => error.code === "resource-exhausted",
  );
  const guards = await db.collection("privateRoomVoiceStartGuards").get();
  assert.equal(guards.size, 1);
  assert.equal(guards.docs[0].data().ownerId, "another-host");
  assert.equal(guards.docs[0].data().startedById, MEMBER);
  assert.equal(
    (await db.doc("rooms/room-integrity-dormant").get()).data().isLive,
    false,
  );
});

test("restricted voice start makes no room, rate, guard or ledger mutation", async () => {
  await seedDormantRoom();
  await db.doc(`restrictions/${HOST}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    service().startRoomVoice(request(
      HOST,
      startInput("voice-restricted-0001", "voice-restricted-session"),
    )),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await db.doc("rooms/room-integrity-dormant").get()).data().isLive, false);
  assert.equal((await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST).get()).size, 0);
  assert.equal((await db.collection("privateRoomVoiceStartGuards")
    .where("ownerId", "==", HOST).get()).size, 0);
  assert.equal((await db.collection("integrityOperationLedgers")
    .where("ownerId", "==", HOST).get()).size, 0);
});

test("random missing room ids are actor-wide N/N+1 bounded before target reads", async () => {
  const start = service({ startMaxEvents: 2 });
  for (const suffix of ["0001", "0002"]) {
    await assert.rejects(
      start.startRoomVoice(request(HOST, {
        requestId: `voice-missing-${suffix}`,
        roomId: `missing-room-${suffix}`,
        sessionId: `missing-session-${suffix}`,
      })),
      (error) => error.code === "not-found",
    );
  }
  await assert.rejects(
    start.startRoomVoice(request(HOST, {
      requestId: "voice-missing-0003",
      roomId: "missing-room-0003",
      sessionId: "missing-session-0003",
    })),
    (error) => error.code === "resource-exhausted",
  );
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST)
    .where("scope", "==", "room.voice.start.global").get()).docs[0].data();
  assert.equal(rate.count, 2);
  assert.equal((await db.collection("integrityOperationLedgers")
    .where("ownerId", "==", HOST)
    .where("kind", "==", "room.voice.start").get()).size, 2);
  assert.equal((await db.collection("privateRoomVoiceStartAttempts")
    .where("ownerId", "==", HOST).get()).size, 0);
  assert.equal((await db.collection("privateRoomVoiceStartGuards")
    .where("ownerId", "==", HOST).get()).size, 0);
});

test("unauthorized target denial is terminal and creates no target guard", async () => {
  await seedDormantRoom({ hostId: "another-host" });
  const payload = startInput(
    "voice-unauthorized-0001",
    "voice-unauthorized-session",
  );
  const start = service({ startMaxEvents: 2 });
  await assert.rejects(
    start.startRoomVoice(request(HOST, payload)),
    (error) => error.code === "permission-denied",
  );
  await assert.rejects(
    start.startRoomVoice(request(HOST, payload)),
    (error) => error.code === "permission-denied",
  );
  const rate = (await db.collection("privateRateLimits")
    .where("ownerId", "==", HOST)
    .where("scope", "==", "room.voice.start.global").get()).docs[0].data();
  assert.equal(rate.count, 1);
  assert.equal((await db.collection("privateRoomVoiceStartGuards")
    .where("ownerId", "==", HOST).get()).size, 0);
});

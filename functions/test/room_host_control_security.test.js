// Host room lifecycle/moderation must update durable Firestore authority and
// the active LiveKit control plane together.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  executeDeleteRoom,
  executeEndRoomVoice,
  executeLeaveRoom,
  executeModerateRoomParticipant,
  executeRemoveRoomParticipant,
  executeSetOwnParticipantMute,
  executeSetRoomStatus,
} = require("../rooms/participants");

const db = getFirestore();
const P = "rhc-";
const HOST = `${P}host`;
const GUEST = `${P}guest`;

function request(uid, data) {
  return { auth: { uid, token: {} }, data };
}

function fakeControl() {
  const calls = [];
  return {
    calls,
    async endRoom(roomId) {
      calls.push(["endRoom", roomId]);
    },
    async revokeParticipant(roomId, uid) {
      calls.push(["revokeParticipant", roomId, uid]);
    },
    async setParticipantPermissions(roomId, uid, permissions) {
      calls.push(["setParticipantPermissions", roomId, uid, permissions]);
    },
  };
}

function fakeBucket({ fail = false } = {}) {
  const calls = [];
  return {
    calls,
    name: "yovoice-test.firebasestorage.app",
    async deleteFiles(options) {
      calls.push(options);
      if (fail) {
        const error = new Error("Storage unavailable");
        error.code = "storage-unavailable";
        throw error;
      }
    },
  };
}

async function wipeOwn() {
  const rooms = await db.collection("rooms").get();
  await Promise.all(
    rooms.docs
      .filter((document) => document.id.startsWith(P))
      .map((document) => db.recursiveDelete(document.ref)),
  );
  await Promise.all([
    db.collection("restrictions").doc(HOST).delete(),
    db.collection("restrictions").doc(GUEST).delete(),
    db.collection("users").doc(HOST).delete(),
    db.collection("users").doc(GUEST).delete(),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(HOST)),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(GUEST)),
  ]);
}

async function seedRoom(roomId, overrides = {}) {
  await db.collection("rooms").doc(roomId).set({
    hostId: HOST,
    status: "active",
    isLive: true,
    participantCount: 2,
    ...overrides,
  });
}

async function seedParticipant(roomId, uid = GUEST, overrides = {}) {
  await db
    .collection("rooms")
    .doc(roomId)
    .collection("participants")
    .doc(uid)
    .set({
      userId: uid,
      role: "speaker",
      isSpeaker: true,
      isMuted: false,
      ...overrides,
    });
}

async function seedSession(roomId, uid = GUEST) {
  await db.collection("activeVoiceSessions").doc(uid)
    .collection("rooms").doc(roomId).set({
      userId: uid,
      roomId,
      participantIdentity: uid,
      expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
    });
}

beforeEach(async () => {
  await wipeOwn();
  await Promise.all([
    db.collection("users").doc(HOST).set({ banned: false }),
    db.collection("users").doc(GUEST).set({ banned: false }),
  ]);
});

describe("host room control", () => {
  test("host removal decrements exactly and revokes the active identity", async () => {
    const roomId = `${P}remove`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await seedSession(roomId);
    await executeRemoveRoomParticipant(
      request(HOST, { roomId, participantId: GUEST }),
      control,
    );
    const [room, participant] = await Promise.all([
      db.collection("rooms").doc(roomId).get(),
      db.collection("rooms").doc(roomId)
        .collection("participants").doc(GUEST).get(),
    ]);
    assert.equal(room.data().participantCount, 1);
    assert.equal(participant.exists, false);
    assert.equal(
      (await db.collection("activeVoiceSessions").doc(GUEST)
        .collection("rooms").doc(roomId).get()).exists,
      false,
    );
    assert.deepEqual(control.calls, [["revokeParticipant", roomId, GUEST]]);
  });

  test("self leave atomically clears roster, count and session before revocation", async () => {
    const roomId = `${P}self-leave`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await seedSession(roomId);
    await executeLeaveRoom(request(GUEST, { roomId }), control);
    const [room, participant, session] = await Promise.all([
      db.collection("rooms").doc(roomId).get(),
      db.collection("rooms").doc(roomId)
        .collection("participants").doc(GUEST).get(),
      db.collection("activeVoiceSessions").doc(GUEST)
        .collection("rooms").doc(roomId).get(),
    ]);
    assert.equal(room.data().participantCount, 1);
    assert.equal(participant.exists, false);
    assert.equal(session.exists, false);
    assert.deepEqual(control.calls, [["revokeParticipant", roomId, GUEST]]);
  });

  test("temporary host cannot abandon a live room through self leave", async () => {
    const roomId = `${P}host-leave`;
    const control = fakeControl();
    await seedRoom(roomId, { roomType: "temporary" });
    await seedParticipant(roomId, HOST, { role: "host" });
    await assert.rejects(
      executeLeaveRoom(request(HOST, { roomId }), control),
      (error) => error?.code === "failed-precondition",
    );
    assert.equal(
      (await db.collection("rooms").doc(roomId)
        .collection("participants").doc(HOST).get()).exists,
      true,
    );
    assert.deepEqual(control.calls, []);
  });

  test("a non-host cannot remove or control a participant", async () => {
    const roomId = `${P}remove-denied`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await seedSession(roomId);
    await assert.rejects(
      executeRemoveRoomParticipant(
        request(GUEST, { roomId, participantId: HOST }),
        control,
      ),
      (error) => error?.code === "permission-denied",
    );
    assert.deepEqual(control.calls, []);
  });

  test("host cannot restore a suspended room with a stale client", async () => {
    const roomId = `${P}suspended`;
    const control = fakeControl();
    await seedRoom(roomId, { status: "suspended", isLive: false });
    await assert.rejects(
      executeSetRoomStatus(
        request(HOST, { roomId, status: "active" }),
        control,
      ),
      (error) => error?.code === "failed-precondition",
    );
    assert.deepEqual(control.calls, []);
  });

  test("closing a room disconnects LiveKit and clears participants", async () => {
    const roomId = `${P}close`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await executeSetRoomStatus(
      request(HOST, { roomId, status: "closed" }),
      control,
    );
    const room = await db.collection("rooms").doc(roomId).get();
    const participants = await room.ref.collection("participants").get();
    assert.equal(room.data().status, "closed");
    assert.equal(room.data().isLive, false);
    assert.equal(room.data().participantCount, 0);
    assert.equal(participants.empty, true);
    assert.equal(
      (await db.collection("activeVoiceSessions").doc(GUEST)
        .collection("rooms").doc(roomId).get()).exists,
      false,
    );
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  test("host unmute or promotion never clears staff serverMuted", async () => {
    const roomId = `${P}staff-muted`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId, GUEST, {
      role: "listener",
      isSpeaker: false,
      isMuted: false,
      hostMuted: true,
      serverMuted: true,
    });
    await executeModerateRoomParticipant(
      request(HOST, {
        roomId,
        participantId: GUEST,
        isMuted: true,
      }),
      control,
    );
    const afterHostMute = await db.collection("rooms").doc(roomId)
      .collection("participants").doc(GUEST).get();
    assert.equal(afterHostMute.data().hostMuted, true);
    assert.equal(afterHostMute.data().isMuted, false);
    assert.equal(afterHostMute.data().serverMuted, true);

    await executeModerateRoomParticipant(
      request(HOST, {
        roomId,
        participantId: GUEST,
        isMuted: false,
        isSpeaker: true,
      }),
      control,
    );
    const participant = await db.collection("rooms").doc(roomId)
      .collection("participants").doc(GUEST).get();
    assert.equal(participant.data().hostMuted, false);
    assert.equal(participant.data().serverMuted, true);
    assert.equal(participant.data().isMuted, false);
    assert.equal(participant.data().role, "speaker");
    assert.equal(control.calls.at(-1)[3].canPublish, false);
  });

  test("self unmute updates LiveKit but respects active communication mute", async () => {
    const roomId = `${P}self-mute`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await db.collection("restrictions").doc(GUEST).set({
      type: "communicationMute",
      expiresAt: Timestamp.fromMillis(Date.now() + 60_000),
    });
    await executeSetOwnParticipantMute(
      request(GUEST, { roomId, isMuted: false }),
      control,
    );
    assert.equal(control.calls[0][3].canPublish, false);
    assert.equal(control.calls[0][3].canPublishData, false);
  });

  test("delete is recursive, but Club Lounges require the Club lifecycle", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    const roomId = `${P}delete`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await db.collection("rooms").doc(roomId)
      .collection("messages").doc("one").set({ text: "x" });
    await executeDeleteRoom(request(HOST, { roomId }), control, bucket);
    assert.equal((await db.collection("rooms").doc(roomId).get()).exists, false);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
    assert.deepEqual(bucket.calls, [
      { prefix: `room_images/${roomId}/`, force: true },
    ]);

    const loungeId = `${P}lounge`;
    await seedRoom(loungeId, {
      clubId: `${P}club`,
      roomKind: "clubLounge",
    });
    await assert.rejects(
      executeDeleteRoom(request(HOST, { roomId: loungeId }), control),
      (error) => error?.code === "failed-precondition",
    );

    const suspendedId = `${P}delete-suspended`;
    await seedRoom(suspendedId, { status: "suspended", isLive: false });
    await assert.rejects(
      executeDeleteRoom(request(HOST, { roomId: suspendedId }), control),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("delete keeps a retryable tombstone when media cleanup fails", async () => {
    const roomId = `${P}delete-media-retry`;
    const control = fakeControl();
    await seedRoom(roomId);
    await assert.rejects(
      executeDeleteRoom(
        request(HOST, { roomId }),
        control,
        fakeBucket({ fail: true }),
      ),
      (error) => error?.code === "unavailable",
    );
    const tombstone = await db.collection("rooms").doc(roomId).get();
    assert.equal(tombstone.exists, true);
    assert.equal(tombstone.data().deletionInProgress, true);
    assert.equal(tombstone.data().status, "closed");

    await executeDeleteRoom(
      request(HOST, { roomId }),
      control,
      fakeBucket(),
    );
    assert.equal((await tombstone.ref.get()).exists, false);
  });

  test("ending voice fails closed for moderated rooms", async () => {
    const roomId = `${P}end-suspended`;
    const control = fakeControl();
    await seedRoom(roomId, { status: "quarantined" });
    await assert.rejects(
      executeEndRoomVoice(request(HOST, { roomId }), control),
      (error) => error?.code === "failed-precondition",
    );
  });
});

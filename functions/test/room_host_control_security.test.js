// Host room lifecycle/moderation must update durable Firestore authority and
// the active LiveKit control plane together.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");

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
// A third identity that never calls anything: it exists only to be STILL IN
// THE ROOM while somebody else leaves or ends it, which is what separates
// "the room is empty" from "the counter says the room is empty".
const OTHER = `${P}other`;

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
    db.collection("users").doc(OTHER).delete(),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(HOST)),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(GUEST)),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(OTHER)),
  ]);
}

// seedRoom() always writes `status`. A large share of production rooms
// predate `roomType`, `experience` and `status` entirely, and the liveness
// drop has to default them the way firestore.rules' own `.get(field,
// default)` reads do — so this seeder writes the bare document instead.
async function seedLegacyRoom(roomId, overrides = {}) {
  await db.collection("rooms").doc(roomId).set({
    hostId: HOST,
    name: "Legacy room",
    visibility: "public",
    isLive: true,
    participantCount: 1,
    membersCanStartVoice: true,
    ...overrides,
  });
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

  test("self mute updates only the roster and skips the LiveKit control plane", async () => {
    const roomId = `${P}self-mute`;
    const control = fakeControl();
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await executeSetOwnParticipantMute(
      request(GUEST, { roomId, isMuted: true }),
      control,
    );
    const participant = await db.collection("rooms").doc(roomId)
      .collection("participants").doc(GUEST).get();
    assert.equal(participant.data().isMuted, true);
    assert.deepEqual(control.calls, []);
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

  // --- The last person out ends the session, in EVERY room ------------
  //
  // `isLive` used to drop at zero participants only for a Club lounge. A
  // Community room whose host enabled `membersCanStartVoice`, started by a
  // MEMBER who then leaves last, had no exit at all: `endRoomVoiceSelf` is
  // host-only and there is no scheduled sweeper. It stayed `isLive: true,
  // participantCount: 0` forever and kept advertising itself through
  // `watchLivePublicRooms` on Home and Discover.

  test("a member-started Community room drops liveness when its last participant leaves", async () => {
    const roomId = `${P}member-started`;
    const control = fakeControl();
    await seedRoom(roomId, {
      participantCount: 1,
      roomType: "community",
      membersCanStartVoice: true,
    });
    // The member who started the voice session is the only one in it; the
    // host never joined.
    await seedParticipant(roomId, GUEST, { role: "listener", isSpeaker: false });
    await seedSession(roomId, GUEST);

    const result = await executeLeaveRoom(request(GUEST, { roomId }), control);

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(room.data().isLive, false);
    assert.equal(room.data().participantCount, 0);
    assert.notEqual(room.data().endedAt, undefined);
    assert.equal(result.endedVoiceSession, true);
    // The LiveKit room is torn down rather than one identity revoked, so an
    // already-issued token cannot keep publishing into an ended session.
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
    assert.equal(
      (await db.collection("activeVoiceSessions").doc(GUEST)
        .collection("rooms").doc(roomId).get()).exists,
      false,
    );
  });

  test("the legacy room shape — no roomType, no experience, no status — ends the same way", async () => {
    const roomId = `${P}legacy-shape`;
    const control = fakeControl();
    await seedLegacyRoom(roomId);
    await seedParticipant(roomId, GUEST, { role: "listener", isSpeaker: false });

    const result = await executeLeaveRoom(request(GUEST, { roomId }), control);

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(room.data().status, undefined);
    assert.equal(room.data().isLive, false);
    assert.equal(room.data().participantCount, 0);
    assert.equal(result.endedVoiceSession, true);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  test("a room that is not live, or already being deleted, is not re-ended on leave", async () => {
    const control = fakeControl();
    const dormantId = `${P}leave-dormant`;
    await seedRoom(dormantId, { isLive: false, participantCount: 1 });
    await seedParticipant(dormantId, GUEST);
    await executeLeaveRoom(request(GUEST, { roomId: dormantId }), control);
    const dormant = await db.collection("rooms").doc(dormantId).get();
    assert.equal(dormant.data().endedAt, undefined);
    assert.equal(dormant.data().participantCount, 0);

    const deletingId = `${P}leave-deleting`;
    await seedRoom(deletingId, {
      participantCount: 1,
      deletionInProgress: true,
    });
    await seedParticipant(deletingId, GUEST);
    await executeLeaveRoom(request(GUEST, { roomId: deletingId }), control);
    const deleting = await db.collection("rooms").doc(deletingId).get();
    // executeDeleteRoom owns this room's teardown; the leave must not write a
    // second endedAt over it or call endRoom a second time.
    assert.equal(deleting.data().endedAt, undefined);
    assert.deepEqual(control.calls, [
      ["revokeParticipant", dormantId, GUEST],
      ["revokeParticipant", deletingId, GUEST],
    ]);
  });

  test("ANTI-TRAP: a stale-low participantCount cannot evict the people still in the room", async () => {
    const roomId = `${P}stale-counter`;
    const control = fakeControl();
    // The counter says one person is here. The roster says two are.
    await seedRoom(roomId, { participantCount: 1 });
    await seedParticipant(roomId, GUEST);
    await seedParticipant(roomId, OTHER);

    // Deliberately asserts state only, with no reference to the new return
    // field: this case must read identically before and after the change,
    // because what it pins is that the generalised drop is roster-derived.
    // A counter-only generalisation passes every other case here and fails
    // this one by ending a room two people are still talking in.
    await executeLeaveRoom(request(GUEST, { roomId }), control);

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(room.data().isLive, true);
    assert.equal(room.data().endedAt, undefined);
    assert.deepEqual(control.calls, [["revokeParticipant", roomId, GUEST]]);
    assert.equal(
      (await db.collection("rooms").doc(roomId)
        .collection("participants").doc(OTHER).get()).exists,
      true,
    );
  });

  test("REGRESSION: the Club lounge drop stays counter-derived, exactly as it was", async () => {
    const roomId = `${P}lounge-leave`;
    const control = fakeControl();
    await seedRoom(roomId, {
      participantCount: 1,
      clubId: `${P}club`,
      roomKind: "clubLounge",
    });
    await seedParticipant(roomId, GUEST);
    // A stale row the lounge branch deliberately does NOT consult: its
    // condition is `roomKind == 'clubLounge' && nextCount === 0`, unchanged,
    // because the client's own lounge leave transaction mirrors it and the
    // two must not drift.
    await seedParticipant(roomId, OTHER);

    await executeLeaveRoom(request(GUEST, { roomId }), control);

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(room.data().isLive, false);
    assert.notEqual(room.data().endedAt, undefined);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  // --- Ending voice on a room somebody just joined ---------------------

  test("onlyIfEmpty leaves an occupied room live instead of evicting whoever just joined", async () => {
    const roomId = `${P}end-occupied`;
    const control = fakeControl();
    // Exactly the shape room_service.dart's shouldEndVoiceOnLeaving() hits:
    // it read participantCount as 1, decided it was the last one out, and by
    // the time the callable runs somebody else is on the roster.
    await seedRoom(roomId, { participantCount: 1 });
    await seedParticipant(roomId, HOST, { role: "host" });
    await seedParticipant(roomId, GUEST);
    await seedSession(roomId, GUEST);

    const result = await executeEndRoomVoice(
      request(HOST, { roomId, onlyIfEmpty: true }),
      control,
    );

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(room.data().isLive, true);
    assert.equal(room.data().participantCount, 1);
    assert.equal(result.ended, false);
    assert.equal(result.success, true);
    assert.equal(
      (await db.collection("rooms").doc(roomId)
        .collection("participants").doc(GUEST).get()).exists,
      true,
    );
    assert.equal(
      (await db.collection("activeVoiceSessions").doc(GUEST)
        .collection("rooms").doc(roomId).get()).exists,
      true,
    );
    assert.deepEqual(control.calls, []);
  });

  test("onlyIfEmpty still ends a room holding nothing but the caller's own row", async () => {
    const roomId = `${P}end-empty`;
    const control = fakeControl();
    await seedRoom(roomId, { participantCount: 1 });
    await seedParticipant(roomId, HOST, { role: "host" });

    const result = await executeEndRoomVoice(
      request(HOST, { roomId, onlyIfEmpty: true }),
      control,
    );

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(result.ended, true);
    assert.equal(room.data().isLive, false);
    assert.equal(room.data().participantCount, 0);
    assert.equal((await room.ref.collection("participants").get()).empty, true);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  // THE MAJORITY PRODUCTION SHAPE: no `status` FIELD AT ALL.
  //
  // 25 of the 45 rooms in production predate the field. firestore.rules reads
  // it as `.get('status','active')` everywhere, so the ruleset authorises the
  // client's `isLive: true` write on these rooms — and every callable that
  // gated on a bare `room.status !== "active"` then refused to act on the very
  // same room. That disagreement is the defect: voice could be switched ON and
  // never switched off, and the token call answered with the exact sentence
  // this whole change exists to remove.
  test("a room with NO status field can still end its voice session", async () => {
    const roomId = `${P}legacy-no-status`;
    const control = fakeControl();
    await seedRoom(roomId, { participantCount: 0 });
    // Remove the field entirely — absent, not "active", not empty string.
    await db.collection("rooms").doc(roomId).update({
      status: FieldValue.delete(),
    });
    const before = await db.collection("rooms").doc(roomId).get();
    assert.equal(before.data().status, undefined, "fixture must have no status");

    const result = await executeEndRoomVoice(request(HOST, { roomId }), control);

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(result.ended, true);
    assert.equal(room.data().isLive, false);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  test("a room with NO status field is still refused once it is being deleted", async () => {
    const roomId = `${P}legacy-no-status-deleting`;
    const control = fakeControl();
    await seedRoom(roomId, { participantCount: 0, deletionInProgress: true });
    await db.collection("rooms").doc(roomId).update({
      status: FieldValue.delete(),
    });

    await assert.rejects(
      () => executeEndRoomVoice(request(HOST, { roomId }), control),
      (error) => error.code === "failed-precondition",
      "defaulting an absent status to active must not also defeat the deletion guard",
    );
    assert.deepEqual(control.calls, []);
  });

  // An EXPLICIT non-active status is still refused. This is what proves the
  // default loosens nothing moderation depends on: a suspended or closed room
  // always carries the field, because moderation writes it.
  test("an explicitly suspended room is still refused", async () => {
    const roomId = `${P}suspended`;
    const control = fakeControl();
    await seedRoom(roomId, { participantCount: 0, status: "suspended" });

    await assert.rejects(
      () => executeEndRoomVoice(request(HOST, { roomId }), control),
      (error) => error.code === "failed-precondition",
    );
    assert.deepEqual(control.calls, []);
  });

  // THE SHAPE THE CLIENT ACTUALLY PRODUCES. room_service.dart's leave path
  // calls `leaveRoomSelf` FIRST and only then this callable, so by the time
  // `onlyIfEmpty` is evaluated the caller holds no participant row at all.
  // The two cases below pin both outcomes of that ordering.
  test("onlyIfEmpty ends the room when the caller has ALREADY left and nobody remains", async () => {
    const roomId = `${P}end-empty-after-leave`;
    const control = fakeControl();
    await seedRoom(roomId, { participantCount: 0 });

    const result = await executeEndRoomVoice(
      request(HOST, { roomId, onlyIfEmpty: true }),
      control,
    );

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(result.ended, true);
    assert.equal(room.data().isLive, false);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  test("onlyIfEmpty leaves the room live when the caller has already left but a guest remains", async () => {
    const roomId = `${P}end-occupied-after-leave`;
    const control = fakeControl();
    // A stale-LOW counter is the whole hazard: it says empty, the roster does
    // not, and the roster is what must win.
    await seedRoom(roomId, { participantCount: 0 });
    await seedParticipant(roomId, GUEST);

    const result = await executeEndRoomVoice(
      request(HOST, { roomId, onlyIfEmpty: true }),
      control,
    );

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(result.ended, false);
    assert.equal(room.data().isLive, true);
    assert.equal(
      (await room.ref.collection("participants").doc(GUEST).get()).exists,
      true,
    );
    assert.deepEqual(control.calls, []);
  });

  test("REGRESSION: the host's explicit End Room still ends it for everyone", async () => {
    const roomId = `${P}end-explicit`;
    const control = fakeControl();
    await seedRoom(roomId, { participantCount: 2 });
    await seedParticipant(roomId, HOST, { role: "host" });
    await seedParticipant(roomId, GUEST);

    // No reference to the new return field: an omitted `onlyIfEmpty` must
    // behave exactly as it did before, so this case reads identically on
    // both sides of the change.
    await executeEndRoomVoice(request(HOST, { roomId }), control);

    const room = await db.collection("rooms").doc(roomId).get();
    assert.equal(room.data().isLive, false);
    assert.equal(room.data().participantCount, 0);
    assert.equal((await room.ref.collection("participants").get()).empty, true);
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });
});

// The scheduled repair for a room left `isLive: true` with an empty roster.
//
// The two properties worth more than all the others: it must CLOSE a room
// that no client can ever close, and it must NEVER close one somebody is in
// or one that only just went live. Every test below is one of those two.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

// ITS OWN FIRESTORE NAMESPACE, AND IT HAS TO BE. Every other suite here
// works on rooms it named itself and can clean up by prefix; this one's
// SUBJECT is a query over the whole `rooms` collection, so a room left live
// by a suite running beside it lands in `scanned` and `closed` and makes
// these assertions read whatever the machine's scheduling did that morning.
// `node --test test/*.test.js` runs the files in parallel, so sharing is not
// hypothetical — it is the default. The Firestore emulator keeps one
// database per project id, so deriving a distinct id buys full isolation
// (and lets `wipeRooms()` below clear the collection outright) without
// touching the production module to make it testable.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const SWEEP_PROJECT = `${BASE_PROJECT}-sweeper`;
process.env.GCLOUD_PROJECT = SWEEP_PROJECT;

if (getApps().length === 0) initializeApp({ projectId: SWEEP_PROJECT });

const {
  GRACE_PERIOD_SECONDS,
  MAX_LIVE_ROOM_SCAN,
  ageAnchor,
  sweepStrandedLiveRooms,
} = require("../rooms/liveness_sweeper");

const db = getFirestore();
const P = "rls-";
const HOST = `${P}host`;
const GUEST = `${P}guest`;

// A fixed clock. The sweep dates every room against this, so "old" and
// "young" below are exact rather than dependent on how long the suite runs.
const NOW_MILLIS = 1_800_000_000_000;
const now = () => Timestamp.fromMillis(NOW_MILLIS);
const AGED = Timestamp.fromMillis(
  NOW_MILLIS - (GRACE_PERIOD_SECONDS + 60) * 1000,
);
const FRESH = Timestamp.fromMillis(NOW_MILLIS - 30 * 1000);

function fakeControl({ failOn = null } = {}) {
  const calls = [];
  return {
    calls,
    async endRoom(roomId) {
      calls.push(["endRoom", roomId]);
      if (failOn === roomId) throw new Error("LiveKit unavailable");
    },
    async revokeParticipant(roomId, uid) {
      calls.push(["revokeParticipant", roomId, uid]);
    },
  };
}

// The whole collection, not a prefix: this suite owns its own project (see
// the header), and a leftover live room from an earlier test is precisely
// what would corrupt the global counters these tests assert on.
async function wipeRooms() {
  const rooms = await db.collection("rooms").get();
  await Promise.all(
    rooms.docs.map((document) => db.recursiveDelete(document.ref)),
  );
  await Promise.all([
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(HOST)),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(GUEST)),
  ]);
}

// The exact document the coordinator leaves behind when `startVoice`
// succeeds and `joinRoom` fails: live, active, counter at zero, and no
// `participants` subcollection at all.
async function seedStrandedRoom(roomId, overrides = {}) {
  await db.collection("rooms").doc(roomId).set({
    hostId: HOST,
    name: "Stranded room",
    visibility: "public",
    status: "active",
    isLive: true,
    participantCount: 0,
    updatedAt: AGED,
    ...overrides,
  });
}

async function seedParticipant(roomId, uid = GUEST) {
  await db
    .collection("rooms")
    .doc(roomId)
    .collection("participants")
    .doc(uid)
    .set({ userId: uid, role: "listener", isSpeaker: false });
}

async function seedSession(roomId, uid) {
  await db.collection("activeVoiceSessions").doc(uid)
    .collection("rooms").doc(roomId)
    .set({
      userId: uid,
      roomId,
      participantIdentity: uid,
      expiresAt: Timestamp.fromMillis(NOW_MILLIS + 300_000),
    });
}

function readRoom(roomId) {
  return db.collection("rooms").doc(roomId).get();
}

beforeEach(wipeRooms);

describe("stranded live room sweep", () => {
  test("closes the room the failed start→join window leaves behind", async () => {
    const roomId = `${P}stranded`;
    const control = fakeControl();
    await seedStrandedRoom(roomId);

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.closed, 1);
    assert.deepEqual(outcome.closedRoomIds, [roomId]);
    assert.equal(outcome.failed, 0);
    assert.equal(outcome.truncated, false);

    const room = (await readRoom(roomId)).data();
    assert.equal(room.isLive, false);
    assert.equal(room.participantCount, 0);
    assert.ok(room.endedAt instanceof Timestamp, "endedAt is stamped");
    assert.deepEqual(control.calls, [["endRoom", roomId]]);
  });

  test("clears the activeVoiceSessions mirror the way an End Room does", async () => {
    const roomId = `${P}mirror`;
    const control = fakeControl();
    await seedStrandedRoom(roomId);
    // A token was issued before the join failed, so the server-only mirror
    // can outlive the roster row that was never written.
    await seedSession(roomId, GUEST);

    await sweepStrandedLiveRooms({ roomControl: control, now });

    const session = await db.collection("activeVoiceSessions").doc(GUEST)
      .collection("rooms").doc(roomId).get();
    assert.equal(session.exists, false);
  });

  // THE ONE THAT MATTERS MOST. A sweep that evicts live participants is
  // worse than the ghost room it was written to remove.
  test("ANTI-TRAP: a room with anyone on its roster is never closed", async () => {
    const roomId = `${P}occupied`;
    const control = fakeControl();
    // Counter says zero — stale-low, the exact shape that would fool a
    // count-based check — while a real participant is still in the room.
    await seedStrandedRoom(roomId, { participantCount: 0 });
    await seedParticipant(roomId);

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.closed, 0);
    assert.equal(outcome.skippedOccupied, 1);
    assert.equal((await readRoom(roomId)).data().isLive, true);
    assert.deepEqual(control.calls, [], "no LiveKit call for an occupied room");
  });

  // THE OTHER ONE THAT MATTERS MOST. This is the window the sweep exists
  // alongside, not the one it may interrupt.
  test("ANTI-TRAP: a room inside its start→join window is left alone", async () => {
    const roomId = `${P}young`;
    const control = fakeControl();
    await seedStrandedRoom(roomId, { updatedAt: FRESH });

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.closed, 0);
    assert.equal(outcome.skippedYoung, 1);
    assert.equal((await readRoom(roomId)).data().isLive, true);
    assert.deepEqual(control.calls, []);
  });

  test("a legacy room with no status field is swept, not skipped", async () => {
    const roomId = `${P}legacy`;
    const control = fakeControl();
    // 25 of the 45 production rooms carry no `status`. A
    // `where("status","==","active")` clause would drop every one of them.
    const reference = db.collection("rooms").doc(roomId);
    await reference.set({
      hostId: HOST,
      name: "Legacy room",
      visibility: "public",
      isLive: true,
      participantCount: 0,
      updatedAt: AGED,
    });

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.closed, 1);
    assert.equal((await reference.get()).data().isLive, false);
  });

  test("a deleting or moderated room is left to the path that owns it", async () => {
    const deletingId = `${P}deleting`;
    const suspendedId = `${P}suspended`;
    const control = fakeControl();
    await seedStrandedRoom(deletingId, { deletionInProgress: true });
    await seedStrandedRoom(suspendedId, { status: "suspended" });

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.closed, 0);
    assert.equal(outcome.skippedInactive, 2);
    // Neither room may be written: executeDeleteRoom and
    // executeSetRoomStatus own those teardowns, and a stamped `endedAt`
    // here would race a teardown that already committed.
    assert.equal((await readRoom(deletingId)).data().isLive, true);
    assert.equal((await readRoom(suspendedId)).data().isLive, true);
    assert.deepEqual(control.calls, []);
  });

  test("a dormant room is not a candidate at all", async () => {
    const roomId = `${P}dormant`;
    const control = fakeControl();
    await seedStrandedRoom(roomId, { isLive: false });

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.scanned, 0);
    assert.equal(outcome.closed, 0);
  });

  test("a live room with no datable field is refused rather than guessed", async () => {
    const roomId = `${P}unanchored`;
    const control = fakeControl();
    await db.collection("rooms").doc(roomId).set({
      hostId: HOST,
      visibility: "public",
      status: "active",
      isLive: true,
      participantCount: 0,
    });

    const outcome = await sweepStrandedLiveRooms({ roomControl: control, now });

    assert.equal(outcome.closed, 0);
    assert.equal(outcome.skippedUnanchored, 1);
    assert.equal((await readRoom(roomId)).data().isLive, true);
  });

  test("one room's LiveKit failure costs neither the others nor visibility", async () => {
    const badId = `${P}a-fails`;
    const goodId = `${P}b-succeeds`;
    const control = fakeControl({ failOn: badId });
    await seedStrandedRoom(badId);
    await seedStrandedRoom(goodId);

    // The failure is re-raised in aggregate so Cloud Scheduler shows a red
    // run rather than a green one that quietly did nothing.
    await assert.rejects(
      () => sweepStrandedLiveRooms({ roomControl: control, now }),
      /failed for 1 of 2 rooms/,
    );

    // Both Firestore writes still committed — the sweep did not abandon the
    // healthy room, and the failed one is already repaired in the durable
    // authority even though its SFU room could not be reclaimed.
    assert.equal((await readRoom(badId)).data().isLive, false);
    assert.equal((await readRoom(goodId)).data().isLive, false);
  });

  test("the scan bound is reported rather than silently applied", async () => {
    const control = fakeControl();
    await Promise.all(
      Array.from({ length: 3 }, (_, index) =>
        seedStrandedRoom(`${P}bound-${index}`),
      ),
    );

    const outcome = await sweepStrandedLiveRooms({
      roomControl: control,
      now,
      maxRooms: 2,
    });

    assert.equal(outcome.truncated, true);
    assert.equal(outcome.scanned, 2);
    assert.equal(outcome.closed, 2);
    // The remainder is not lost: closing rooms only shrinks the candidate
    // set, so the next run picks it up.
    const second = await sweepStrandedLiveRooms({
      roomControl: fakeControl(),
      now,
      maxRooms: 2,
    });
    assert.equal(second.closed, 1);
    assert.equal(second.truncated, false);
  });

  test("the grace period cannot be configured below one minute", async () => {
    const roomId = `${P}floor`;
    const control = fakeControl();
    await seedStrandedRoom(roomId, { updatedAt: FRESH });

    // 30 seconds old, asked to sweep at a 0-second grace: the floor keeps it.
    const outcome = await sweepStrandedLiveRooms({
      roomControl: control,
      now,
      gracePeriodSeconds: 0,
    });

    assert.equal(outcome.closed, 0);
    assert.equal(outcome.skippedYoung, 1);
  });

  // A log line that says a room failed without saying WHY is the failure
  // mode this asserts against: firebase-functions overwrites a `message` key
  // on the payload with a synthetic stack unless a real Error is among the
  // arguments, so the obvious `{ message: error.message }` loses the reason.
  test("a per-room failure log carries the real reason, not a synthetic stack", async () => {
    const roomId = `${P}log-detail`;
    const control = fakeControl({ failOn: roomId });
    await seedStrandedRoom(roomId);

    const { logger } = require("firebase-functions");
    const original = logger.error;
    const entries = [];
    logger.error = (...args) => entries.push(args);
    try {
      await assert.rejects(() =>
        sweepStrandedLiveRooms({ roomControl: control, now }),
      );
    } finally {
      logger.error = original;
    }

    assert.equal(entries.length, 1);
    const [, second, payload] = entries[0];
    assert.ok(second instanceof Error, "the Error is passed as an argument");
    assert.equal(second.message, "LiveKit unavailable");
    assert.deepEqual(payload, { roomId });
    assert.ok(
      !("message" in payload),
      "no `message` key, which the logger would overwrite",
    );
  });

  test("the caps are the documented ones", () => {
    assert.equal(GRACE_PERIOD_SECONDS, 300);
    assert.equal(MAX_LIVE_ROOM_SCAN, 200);
  });
});

describe("age anchor", () => {
  test("updatedAt leads, createdAt is the fallback, absent is null", () => {
    const older = Timestamp.fromMillis(1000);
    const newer = Timestamp.fromMillis(9000);
    assert.equal(ageAnchor({ updatedAt: newer, createdAt: older }), 9000);
    assert.equal(ageAnchor({ createdAt: older }), 1000);
    assert.equal(ageAnchor({}), null);
    assert.equal(ageAnchor(null), null);
  });

  test("a Date is accepted as well as a Timestamp", () => {
    assert.equal(ageAnchor({ updatedAt: new Date(4000) }), 4000);
  });
});

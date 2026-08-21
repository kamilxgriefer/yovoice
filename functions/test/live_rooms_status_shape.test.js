// The live-room read behind the admin dashboard and the staff overview —
// and the ONE document shape it must never drop.
//
// 25 of the 45 production rooms carry no `status` field at all.
// `where("status", "==", "active")` matches only documents where the field
// is PRESENT and equal, so both surfaces were counting a minority of the
// rooms that were actually live. This file pins the reading that
// `roomIsActive()` and firestore.rules' own
// `resource.data.get('status', 'active')` already share: ABSENT MEANS
// ACTIVE, and a legacy room is not a suspended one.
//
// Assertions here are MEMBERSHIP BY ID rather than totals, because the
// `rooms` collection is shared with every other test file in the suite and
// a total is not a fact any single file owns.
//
//   firebase emulators:exec --only auth,firestore --project demo-yovoice \
//     'npm --prefix functions test'

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  LIVE_ROOM_SCAN_LIMIT,
  listLiveActiveRoomDocs,
} = require("../rooms/live_rooms");

const db = getFirestore();

// Sorts deliberately LATE. `node --test` runs the suite's files in
// parallel against one emulator, the staff overview lists live rooms with a
// bare `limit(5)` and no `orderBy` — so Firestore returns them in document-
// name order — and fixtures that sorted early would push another file's
// room out of that window. These are also wiped after every test rather
// than only at the end, so they are live for as short a time as possible.
const P = "zz-live-rooms-";
const HOST = `${P}host`;

const LEGACY = `${P}legacy-no-status`;
const EXPLICIT = `${P}explicit-active`;
const SUSPENDED = `${P}suspended`;
const CLOSED = `${P}closed`;
const DORMANT_LEGACY = `${P}legacy-not-live`;

const ALL_ROOMS = [LEGACY, EXPLICIT, SUSPENDED, CLOSED, DORMANT_LEGACY];

/// The majority production shape: no `status` key at all. Written the long
/// way rather than with `status: undefined`, because the Admin SDK would
/// reject that and the ABSENCE is the whole point of the fixture.
function legacyRoom(overrides = {}) {
  return {
    hostId: HOST,
    name: "Legacy room",
    visibility: "public",
    isLive: true,
    participantCount: 1,
    ...overrides,
  };
}

async function seed() {
  await Promise.all([
    db.collection("rooms").doc(LEGACY).set(legacyRoom()),
    db
      .collection("rooms")
      .doc(EXPLICIT)
      .set(legacyRoom({ name: "Explicit room", status: "active" })),
    db
      .collection("rooms")
      .doc(SUSPENDED)
      .set(legacyRoom({ name: "Suspended room", status: "suspended" })),
    db
      .collection("rooms")
      .doc(CLOSED)
      .set(legacyRoom({ name: "Closed room", status: "closed" })),
    db
      .collection("rooms")
      .doc(DORMANT_LEGACY)
      .set(legacyRoom({ name: "Dormant legacy room", isLive: false })),
  ]);
}

async function wipe() {
  await Promise.all(
    ALL_ROOMS.map((id) => db.collection("rooms").doc(id).delete()),
  );
}

async function liveRoomIds(options = {}) {
  const { docs } = await listLiveActiveRoomDocs(options);
  return docs.map((document) => document.id);
}

beforeEach(seed);
afterEach(wipe);

describe("listLiveActiveRoomDocs", () => {
  // THE ONE THAT MATTERS. Under the two-equality query this room was
  // invisible to both staff surfaces, and it is the majority shape.
  test("a live room with NO status field is included", async () => {
    const ids = await liveRoomIds();

    assert.ok(
      ids.includes(LEGACY),
      "a room with no `status` field reads as active, exactly as " +
        "firestore.rules' .get('status', 'active') reads it",
    );
    assert.ok(ids.includes(EXPLICIT), "an explicit active room still counts");
  });

  // The other direction, and the reason absent-means-active loosens nothing:
  // moderation always writes an EXPLICIT value, so every genuinely inactive
  // room carries the field.
  test("an explicitly inactive room is excluded, legacy shape or not", async () => {
    const ids = await liveRoomIds();

    assert.ok(!ids.includes(SUSPENDED), "a suspended room is not live");
    assert.ok(!ids.includes(CLOSED), "a closed room is not live");
  });

  test("a dormant room is not a candidate, even with no status field", async () => {
    const ids = await liveRoomIds();

    assert.ok(!ids.includes(DORMANT_LEGACY));
  });

  // A silently truncated count is the same under-reporting defect this
  // module exists to fix, arriving by a different route.
  test("reaching the scan bound is reported, not swallowed", async () => {
    const bounded = await listLiveActiveRoomDocs({ maxRooms: 1 });

    // The fixtures alone put at least two live rooms in the collection.
    assert.equal(bounded.truncated, true);
    assert.ok(bounded.docs.length <= 1);

    const full = await listLiveActiveRoomDocs();
    assert.equal(full.truncated, false);
    assert.ok(full.docs.length <= LIVE_ROOM_SCAN_LIMIT);
  });

  test("a caller cannot raise the scan bound above the module's ceiling", async () => {
    const { docs } = await listLiveActiveRoomDocs({
      maxRooms: LIVE_ROOM_SCAN_LIMIT * 10,
    });

    assert.ok(docs.length <= LIVE_ROOM_SCAN_LIMIT);
  });
});

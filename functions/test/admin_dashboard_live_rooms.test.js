// getAdminDashboard's `liveRooms` figure, and the room shape it used to
// pretend did not exist.
//
// The count ran `where("status", "==", "active").where("isLive", "==",
// true).count()`. That matches only documents where `status` is PRESENT and
// equal, and 25 of the 45 production rooms carry no `status` field at all —
// so the owner's dashboard reported a fraction of the rooms that were
// actually live. `roomIsActive()` (commit b7c6d99) had already settled the
// reading everywhere else: absent means active, exactly as firestore.rules'
// `resource.data.get('status', 'active')` reads it.
//
// The counts here are aggregates over collections shared with every other
// test file in the suite, so no global before/after total is this file's to
// assert. The integration seam pins that the dashboard publishes the exact
// status-shape-safe reader length; live_rooms_status_shape.test.js pins the
// real legacy-active versus explicitly suspended reader behavior.
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
  getAdminDashboard,
  loadAdminDashboardStats,
} = require("../admin/dashboard");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const run = getAdminDashboard.run ?? getAdminDashboard;

// Sorts deliberately LATE: `node --test` runs the suite's files in parallel
// against one emulator, and the staff overview lists live rooms with a bare
// `limit(5)` in document-name order. An early-sorting fixture here would
// push that file's rooms out of its own listing.
const P = "zz-admin-dash-";
const OWNER_UID = `${P}owner`;
const LEGACY_ROOM = `${P}legacy-room`;

const legacyRoomRef = () => db.collection("rooms").doc(LEGACY_ROOM);

/// No `status` key at all — the shape the two-equality query dropped.
const LEGACY_ROOM_DATA = {
  hostId: OWNER_UID,
  name: "Legacy dashboard room",
  visibility: "public",
  isLive: true,
  participantCount: 1,
};

async function wipe() {
  await Promise.all([
    db.collection("users").doc(OWNER_UID).delete(),
    legacyRoomRef().delete(),
  ]);
}

async function seed() {
  await Promise.all([
    db.collection("users").doc(OWNER_UID).set({ role: "superAdmin" }),
    legacyRoomRef().set(LEGACY_ROOM_DATA),
  ]);
}

const asOwner = () =>
  run({
    auth: { uid: OWNER_UID, token: { role: "superAdmin" } },
    data: {},
  });

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER_UID);
  await wipe();
  await seed();
});

afterEach(wipe);

describe("getAdminDashboard", () => {
  test("the dashboard derives liveRooms from the status-shape-safe reader", async () => {
    // Other files create and retire rooms concurrently in the shared emulator,
    // so a before/after global-count delta is inherently racy. Inject the
    // reader result at the seam and prove the dashboard publishes its exact
    // length; live_rooms_status_shape.test.js independently proves that the
    // real reader includes a live legacy room and excludes it once suspended.
    const result = await loadAdminDashboardStats({
      listLiveRooms: async ({ surface }) => {
        assert.equal(surface, "getAdminDashboard");
        return { docs: [{ id: LEGACY_ROOM }] };
      },
    });
    assert.equal(result.liveRooms, 1);
  });

  test("the other totals are still real aggregates", async () => {
    const result = await asOwner();

    assert.ok(result.users >= 1);
    // Every live room is a room, and the legacy one is in both totals.
    assert.ok(result.rooms >= 1);
    assert.ok(result.rooms >= result.liveRooms);
    assert.ok(result.liveRooms >= 1);
    assert.equal(typeof result.clubs, "number");
  });

  // The owner gate itself is covered in full by
  // privileged_staff_authorization.test.js and is deliberately not
  // duplicated here.
});

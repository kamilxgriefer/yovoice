// Regression coverage for the Admin Center room browser's status filter.
//
// ADR-093 settled that an absent `status` means active: `firestore.rules`
// reads the field as `.get('status', 'active')`, `roomIsActive()` mirrors
// that default, and 25 of the 45 rooms in production carry no `status` at
// all. `listAdminRooms` did not get the memo. Its "active" filter was a
// literal `where("status", "==", "active")`, so it recognised 9 of the 34
// rooms the rules call active — while `mapRoom` in the SAME callable already
// reported those 25 legacy rooms as `status: "active"` to the browser. The
// unfiltered list showed a room as active and the "active" filter denied it
// existed.
//
// These cases pin the boundary from both sides: absence is included, an
// EXPLICIT non-active value is still excluded, and the non-"active" filters
// still resolve server-side as an indexed equality.
//
//   firebase emulators:exec --only auth,firestore --project demo-yovoice \
//     'npm --prefix functions test'

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { listAdminRooms } = require("../admin/rooms");

const db = getFirestore();
const run = (callable) => callable.run ?? callable;

const P = "admin-room-list-";
const MOD = `${P}moderator`;

// Oldest to newest, so `orderBy("updatedAt", "desc")` returns them in the
// reverse of this order and the paging cases below have a fixed sequence.
const LEGACY_ROOM = `${P}legacy`;
const ACTIVE_ROOM = `${P}active`;
const CLOSED_ROOM = `${P}closed`;
const SUSPENDED_ROOM = `${P}suspended`;

const ALL_ROOMS = [LEGACY_ROOM, ACTIVE_ROOM, CLOSED_ROOM, SUSPENDED_ROOM];

function request(data = {}) {
  return { auth: { uid: MOD, token: { role: "moderator" } }, data };
}

// The suite shares one emulator and other files seed rooms with
// `Timestamp.now()`. Anchoring these fixtures in the far future makes them
// the newest documents in `rooms` under `orderBy("updatedAt", "desc")`, so
// the cursor cases below page through a known sequence no matter what else
// is in the collection.
const FUTURE_ANCHOR_MS = Date.UTC(2300, 0, 1);

function at(offsetSeconds) {
  return Timestamp.fromMillis(FUTURE_ANCHOR_MS + offsetSeconds * 1000);
}

// The production majority shape: no `status`, no `roomType`, no `experience`.
async function seedLegacyRoom(roomId, overrides = {}) {
  await db.collection("rooms").doc(roomId).set({
    hostId: `${P}host`,
    name: "Legacy room",
    visibility: "public",
    isLive: true,
    participantCount: 1,
    updatedAt: at(1000),
    ...overrides,
  });
}

async function seedRoom(roomId, overrides = {}) {
  await db.collection("rooms").doc(roomId).set({
    hostId: `${P}host`,
    name: "Modern room",
    visibility: "public",
    status: "active",
    roomType: "community",
    experience: "community",
    isLive: true,
    participantCount: 2,
    updatedAt: at(2000),
    ...overrides,
  });
}

async function resetFixtures() {
  await Promise.all([
    db.collection("users").doc(MOD).delete(),
    ...ALL_ROOMS.map((id) => db.collection("rooms").doc(id).delete()),
  ]);

  await Promise.all([
    db.collection("users").doc(MOD).set({ role: "moderator" }),
    seedLegacyRoom(LEGACY_ROOM, { updatedAt: at(1000) }),
    seedRoom(ACTIVE_ROOM, { status: "active", updatedAt: at(2000) }),
    seedRoom(CLOSED_ROOM, { status: "closed", updatedAt: at(3000) }),
    seedRoom(SUSPENDED_ROOM, { status: "suspended", updatedAt: at(4000) }),
  ]);
}

async function listIds(data) {
  const result = await run(listAdminRooms)(request(data));
  return {
    ids: result.rooms.map((room) => room.id).filter((id) => id.startsWith(P)),
    nextCursorId: result.nextCursorId,
  };
}

beforeEach(resetFixtures);

afterEach(async () => {
  await Promise.all([
    db.collection("users").doc(MOD).delete(),
    ...ALL_ROOMS.map((id) => db.collection("rooms").doc(id).delete()),
  ]);
});

describe("listAdminRooms status filtering", () => {
  test("an unfiltered listing still returns every room, legacy included",
    async () => {
      const { ids } = await listIds({ limit: 100 });

      for (const id of ALL_ROOMS) {
        assert.ok(ids.includes(id), `${id} missing from the unfiltered list`);
      }
    });

  test("the unfiltered listing already reports a legacy room as active",
    async () => {
      const result = await run(listAdminRooms)(request({ limit: 100 }));
      const legacy = result.rooms.find((room) => room.id === LEGACY_ROOM);

      // `mapRoom` defaults the absent field, which is precisely why the
      // literal `where` clause contradicted the callable's own output.
      assert.equal(legacy.status, "active");
    });

  test("filtering by active includes a room with no status field", async () => {
    const { ids } = await listIds({ limit: 100, status: "active" });

    assert.ok(
      ids.includes(LEGACY_ROOM),
      "a legacy room the rules treat as active was dropped by the filter",
    );
    assert.ok(ids.includes(ACTIVE_ROOM));
  });

  test("filtering by active still excludes an explicitly moderated room",
    async () => {
      const { ids } = await listIds({ limit: 100, status: "active" });

      // The half of ADR-093 that proves the default did not widen anything:
      // moderation writes an EXPLICIT value, and it is still honoured.
      assert.ok(!ids.includes(CLOSED_ROOM), "a closed room leaked into active");
      assert.ok(
        !ids.includes(SUSPENDED_ROOM),
        "a suspended room leaked into active",
      );
    });

  test("a non-active filter stays an exact match and never absorbs legacy rooms",
    async () => {
      for (const [status, expected] of [
        ["closed", CLOSED_ROOM],
        ["suspended", SUSPENDED_ROOM],
      ]) {
        const { ids } = await listIds({ limit: 100, status });

        assert.deepEqual(ids, [expected], `status=${status}`);
      }
    });

  test("an unknown status matches nothing rather than everything", async () => {
    const { ids } = await listIds({ limit: 100, status: "archived" });

    assert.deepEqual(ids, []);
  });

  test("search composes with the active filter", async () => {
    const { ids } = await listIds({
      limit: 100,
      status: "active",
      search: "legacy",
    });

    assert.deepEqual(ids, [LEGACY_ROOM]);
  });
});

describe("listAdminRooms cursor semantics under in-memory filtering", () => {
  test("an empty page still advances the cursor, so paging reaches the rooms behind it",
    async () => {
      // Newest first, one document per page: suspended, closed, active,
      // legacy. The first two fail the in-memory active filter and show
      // nothing — and must still hand back a cursor, or the browser stops two
      // documents into a database with active rooms right behind them.
      const expected = [
        [[], SUSPENDED_ROOM],
        [[], CLOSED_ROOM],
        [[ACTIVE_ROOM], ACTIVE_ROOM],
        [[LEGACY_ROOM], LEGACY_ROOM],
      ];

      let cursorId = null;
      const collected = [];

      for (const [expectedIds, expectedCursor] of expected) {
        const page = await listIds({
          limit: 1,
          status: "active",
          ...(cursorId ? { cursorId } : {}),
        });

        assert.deepEqual(page.ids, expectedIds);
        assert.equal(
          page.nextCursorId,
          expectedCursor,
          "the cursor must name the last document SCANNED, not the last shown",
        );

        collected.push(...page.ids);
        cursorId = page.nextCursorId;
      }

      assert.deepEqual(collected, [ACTIVE_ROOM, LEGACY_ROOM]);
    });
});

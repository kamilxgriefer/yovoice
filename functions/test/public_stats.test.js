// publicStats/live — the three real numbers replacing the hardcoded
// "2,481 people talking right now" on the marketing site.
//
// The load-bearing claims proved here are: the freshness bound is the token
// TTL and is enforced by the real Firestore query; people are counted, not
// sessions; a forged or wrongly-shaped mirror row contributes nobody; and a
// failed run publishes NOTHING, so the previously published document keeps its
// last good values instead of collapsing to a zero that would read as
// "nobody is here".

const assert = require("node:assert/strict");
const { after, before, describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { Timestamp, getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  LIVE_SESSION_FRESHNESS_SECONDS,
  MAX_LIVE_SESSION_SCAN,
  PUBLIC_STATS_SCHEMA_VERSION,
  PublicStatsError,
  canonicalSessionUser,
  computePublicStats,
  countCollection,
  distinctLiveSpeakers,
  fetchFreshVoiceSessions,
  publishPublicStats,
} = require("../stats/public_stats");
const {
  VOICE_TOKEN_TTL_SECONDS,
} = require("../livekit/token");
const { writeActiveVoiceSession } = require("../livekit/sessions");

const db = getFirestore();

// Test files run in parallel and several of them seed their own
// activeVoiceSessions rows with a future expiry, so no assertion here may
// depend on a database-wide total. Everything is scoped to this prefix.
const P = "pstats-";
const ALICE = `${P}alice`;
const BOB = `${P}bob`;
const ROOM_A = `${P}room-a`;
const ROOM_B = `${P}room-b`;
const COUNT_FIXTURE = `${P}countFixture`;
const STATS_DOCUMENT = db.collection("publicStatsTest").doc(`${P}live`);

function sessionDocument(path, data) {
  return { ref: { path }, data: () => data };
}

function canonicalRow(userId, roomId) {
  return sessionDocument(`activeVoiceSessions/${userId}/rooms/${roomId}`, {
    userId,
    roomId,
    participantIdentity: userId,
  });
}

function ownRows(documents) {
  return documents.filter((document) => document.ref.path.includes(P));
}

async function seedSession(userId, roomId, expiresAt) {
  // Written through the production writer so the stored shape is exactly what
  // createLiveKitToken produces, not a hand-rolled approximation of it.
  await db.runTransaction(async (transaction) => {
    writeActiveVoiceSession(transaction, { userId, roomId, expiresAt });
  });
}

async function wipe() {
  const owners = [ALICE, BOB];
  const rooms = [ROOM_A, ROOM_B];
  await Promise.all([
    ...owners.flatMap((userId) => rooms.map((roomId) => db
      .collection("activeVoiceSessions").doc(userId)
      .collection("rooms").doc(roomId).delete())),
    STATS_DOCUMENT.delete(),
  ]);
  const fixture = await db.collection(COUNT_FIXTURE).get();
  await Promise.all(fixture.docs.map((document) => document.ref.delete()));
}

before(wipe);
after(wipe);

describe("public stats — the freshness bound", () => {
  test("the bound is derived from the token TTL and cannot drift", () => {
    // activeVoiceSessions carries no heartbeat: expiresAt is set once per
    // token mint. Restating "5 minutes" as a literal here would let a TTL
    // change silently start counting people who are provably gone.
    assert.equal(LIVE_SESSION_FRESHNESS_SECONDS, VOICE_TOKEN_TTL_SECONDS);
    assert.equal(LIVE_SESSION_FRESHNESS_SECONDS, 300);
  });

  test("the real collection-group query returns fresh rows and drops expired ones",
    async () => {
      const now = Date.now();
      await Promise.all([
        seedSession(ALICE, ROOM_A, Timestamp.fromMillis(now + 120_000)),
        // A client that crashed: nothing deletes this row, so only the
        // freshness bound keeps it out of the published number.
        seedSession(BOB, ROOM_B, Timestamp.fromMillis(now - 1_000)),
      ]);

      const documents = ownRows(await fetchFreshVoiceSessions({ now }));
      const paths = documents.map((document) => document.ref.path).sort();

      assert.deepEqual(paths, [
        `activeVoiceSessions/${ALICE}/rooms/${ROOM_A}`,
      ]);
      assert.equal(distinctLiveSpeakers(documents), 1);
    });

  test("a live participant stops being counted once the mint window passes",
    async () => {
      const now = Date.now();
      await seedSession(ALICE, ROOM_A, Timestamp.fromMillis(now + 60_000));

      const inWindow = ownRows(await fetchFreshVoiceSessions({ now }));
      assert.equal(distinctLiveSpeakers(inWindow), 1);

      // The same row, evaluated after its expiry. The person may well still be
      // in the room — the client never re-mints — which is exactly why this
      // number is a lower bound and not a measurement.
      const afterWindow = ownRows(
        await fetchFreshVoiceSessions({ now: now + 61_000 }),
      );
      assert.equal(distinctLiveSpeakers(afterWindow), 0);
    });
});

describe("public stats — counting people, not sessions", () => {
  test("one account in two rooms is one person", () => {
    assert.equal(
      distinctLiveSpeakers([
        canonicalRow(ALICE, ROOM_A),
        canonicalRow(ALICE, ROOM_B),
      ]),
      1,
    );
  });

  test("two accounts are two people", () => {
    assert.equal(
      distinctLiveSpeakers([
        canonicalRow(ALICE, ROOM_A),
        canonicalRow(BOB, ROOM_B),
      ]),
      2,
    );
  });

  test("a second device in the same room reuses one document id", async () => {
    const now = Date.now();
    await seedSession(ALICE, ROOM_A, Timestamp.fromMillis(now + 120_000));
    await seedSession(ALICE, ROOM_A, Timestamp.fromMillis(now + 180_000));

    const documents = ownRows(await fetchFreshVoiceSessions({ now }));
    assert.equal(documents.length, 1);
    assert.equal(distinctLiveSpeakers(documents), 1);
  });

  test("one account in two rooms is one person through the real query",
    async () => {
      const now = Date.now();
      await Promise.all([
        seedSession(ALICE, ROOM_A, Timestamp.fromMillis(now + 120_000)),
        seedSession(ALICE, ROOM_B, Timestamp.fromMillis(now + 120_000)),
      ]);

      const documents = ownRows(await fetchFreshVoiceSessions({ now }));
      assert.equal(documents.length, 2);
      assert.equal(distinctLiveSpeakers(documents), 1);
    });
});

describe("public stats — only canonical mirror rows count", () => {
  test("a canonical row resolves to its owning uid", () => {
    assert.equal(canonicalSessionUser(canonicalRow(ALICE, ROOM_A)), ALICE);
  });

  test("a root rooms document is not a voice session", () => {
    // collectionGroup("rooms") matches the root rooms collection too.
    assert.equal(
      canonicalSessionUser(sessionDocument(`rooms/${ROOM_A}`, {
        userId: ALICE,
        roomId: ROOM_A,
        participantIdentity: ALICE,
      })),
      null,
    );
    assert.equal(distinctLiveSpeakers([
      sessionDocument(`rooms/${ROOM_A}`, { userId: ALICE, roomId: ROOM_A }),
    ]), 0);
  });

  test("a row whose payload disagrees with its own path contributes nobody",
    () => {
      const forgedOwner = sessionDocument(
        `activeVoiceSessions/${ALICE}/rooms/${ROOM_A}`,
        { userId: BOB, roomId: ROOM_A, participantIdentity: BOB },
      );
      const forgedIdentity = sessionDocument(
        `activeVoiceSessions/${ALICE}/rooms/${ROOM_A}`,
        { userId: ALICE, roomId: ROOM_A, participantIdentity: BOB },
      );
      const forgedRoom = sessionDocument(
        `activeVoiceSessions/${ALICE}/rooms/${ROOM_A}`,
        { userId: ALICE, roomId: ROOM_B, participantIdentity: ALICE },
      );

      assert.equal(canonicalSessionUser(forgedOwner), null);
      assert.equal(canonicalSessionUser(forgedIdentity), null);
      assert.equal(canonicalSessionUser(forgedRoom), null);
      assert.equal(
        distinctLiveSpeakers([forgedOwner, forgedIdentity, forgedRoom]),
        0,
      );
    });

  test("a deeper or shallower path contributes nobody", () => {
    assert.equal(
      canonicalSessionUser(sessionDocument(
        `activeVoiceSessions/${ALICE}/rooms/${ROOM_A}/extra/leaf`,
        { userId: ALICE, roomId: ROOM_A, participantIdentity: ALICE },
      )),
      null,
    );
    assert.equal(
      canonicalSessionUser(sessionDocument(
        `activeVoiceSessions/${ALICE}`,
        { userId: ALICE, roomId: ROOM_A, participantIdentity: ALICE },
      )),
      null,
    );
  });
});

describe("public stats — the read bound", () => {
  test("exceeding the scan bound fails loudly instead of publishing a truncated number",
    () => {
      const rows = Array.from(
        { length: MAX_LIVE_SESSION_SCAN + 1 },
        (_, index) => canonicalRow(`${P}u${index}`, ROOM_A),
      );
      assert.throws(
        () => distinctLiveSpeakers(rows),
        (error) => error instanceof PublicStatsError &&
          /exceeded its 2000 document bound/.test(error.message),
      );
    });

  test("a truncated scan writes nothing", async () => {
    let written = 0;
    await assert.rejects(
      () => publishPublicStats({
        maxSessions: 2,
        fetchSessions: async () => [
          canonicalRow(ALICE, ROOM_A),
          canonicalRow(BOB, ROOM_A),
          canonicalRow(`${P}carol`, ROOM_A),
        ],
        countAccounts: async () => 10,
        countRooms: async () => 4,
        writeStats: async () => { written += 1; },
      }),
      PublicStatsError,
    );
    assert.equal(written, 0);
  });
});

describe("public stats — real count() aggregates", () => {
  test("count() reports the real total of a collection", async () => {
    const before = await countCollection(COUNT_FIXTURE);
    await Promise.all([
      db.collection(COUNT_FIXTURE).doc(`${P}one`).set({ seeded: true }),
      db.collection(COUNT_FIXTURE).doc(`${P}two`).set({ seeded: true }),
      db.collection(COUNT_FIXTURE).doc(`${P}three`).set({ seeded: true }),
    ]);
    const after = await countCollection(COUNT_FIXTURE);

    assert.equal(before, 0);
    assert.equal(after, 3);
  });

  test("a count() total that goes DOWN is reported honestly", async () => {
    await db.collection(COUNT_FIXTURE).doc(`${P}one`).delete();
    // Current totals, not lifetime creation counters. Deleting an account or
    // a room lowers the published figure; the operator has to accept that or
    // fund a monotonic counter.
    assert.equal(await countCollection(COUNT_FIXTURE), 2);
  });

  test("a missing or malformed aggregate throws rather than returning zero",
    async () => {
      const malformed = {
        collection: () => ({
          count: () => ({ get: async () => ({ data: () => ({}) }) }),
        }),
      };
      await assert.rejects(
        () => countCollection("users", malformed),
        (error) => error instanceof PublicStatsError &&
          /did not return a usable total/.test(error.message),
      );
    });
});

describe("public stats — the published document", () => {
  test("the shape is exactly the aggregates plus a timestamp", async () => {
    const document = await publishPublicStats({
      fetchSessions: async () => [
        canonicalRow(ALICE, ROOM_A),
        canonicalRow(ALICE, ROOM_B),
        canonicalRow(BOB, ROOM_A),
      ],
      countAccounts: async () => 1_204,
      countRooms: async () => 318,
      writeStats: (payload) => STATS_DOCUMENT.set(payload),
    });

    assert.deepEqual(Object.keys(document).sort(), [
      "accountsCreated",
      "peopleTalkingNow",
      "roomsCreated",
      "schemaVersion",
      "updatedAt",
    ]);

    const stored = (await STATS_DOCUMENT.get()).data();
    assert.equal(stored.schemaVersion, PUBLIC_STATS_SCHEMA_VERSION);
    assert.equal(stored.peopleTalkingNow, 2);
    assert.equal(stored.accountsCreated, 1_204);
    assert.equal(stored.roomsCreated, 318);
    assert.ok(stored.updatedAt instanceof Timestamp);
    for (const key of ["peopleTalkingNow", "accountsCreated", "roomsCreated"]) {
      assert.ok(Number.isSafeInteger(stored[key]), `${key} is an integer`);
    }
    // Nothing identifying may reach a publicly readable document.
    assert.equal(JSON.stringify(stored).includes(ALICE), false);
    assert.equal(JSON.stringify(stored).includes(ROOM_A), false);
  });

  test("a genuine zero is published — silence is the presentation layer's job",
    async () => {
      const document = await publishPublicStats({
        fetchSessions: async () => [],
        countAccounts: async () => 7,
        countRooms: async () => 2,
        writeStats: async () => {},
      });
      assert.equal(document.peopleTalkingNow, 0);
      assert.equal(document.accountsCreated, 7);
    });
});

describe("public stats — a failed run keeps the last good values", () => {
  const sources = [
    ["the voice session source", {
      fetchSessions: async () => { throw new Error("sessions unavailable"); },
    }],
    ["the accounts aggregate", {
      countAccounts: async () => { throw new Error("users unavailable"); },
    }],
    ["the rooms aggregate", {
      countRooms: async () => { throw new Error("rooms unavailable"); },
    }],
  ];

  for (const [label, override] of sources) {
    test(`${label} failing writes nothing`, async () => {
      let written = 0;
      await assert.rejects(
        () => publishPublicStats({
          fetchSessions: async () => [canonicalRow(ALICE, ROOM_A)],
          countAccounts: async () => 5,
          countRooms: async () => 1,
          writeStats: async () => { written += 1; },
          ...override,
        }),
        /unavailable/,
      );
      assert.equal(written, 0);
    });
  }

  test("two sources failing at once surface one error, not an unhandled rejection",
    async () => {
      await assert.rejects(
        () => computePublicStats({
          fetchSessions: async () => { throw new Error("sessions unavailable"); },
          countAccounts: async () => { throw new Error("users unavailable"); },
          countRooms: async () => 1,
        }),
        /sessions unavailable/,
      );
      // Give the second rejection a turn to become unhandled if it were.
      await new Promise((resolve) => setImmediate(resolve));
    });

  test("the previously published document survives a failed run byte for byte",
    async () => {
      await publishPublicStats({
        fetchSessions: async () => [canonicalRow(ALICE, ROOM_A)],
        countAccounts: async () => 42,
        countRooms: async () => 9,
        writeStats: (payload) => STATS_DOCUMENT.set(payload),
      });
      const good = (await STATS_DOCUMENT.get()).data();
      assert.equal(good.peopleTalkingNow, 1);

      await assert.rejects(
        () => publishPublicStats({
          fetchSessions: async () => { throw new Error("sessions unavailable"); },
          countAccounts: async () => 0,
          countRooms: async () => 0,
          writeStats: (payload) => STATS_DOCUMENT.set(payload),
        }),
        /sessions unavailable/,
      );

      const afterFailure = (await STATS_DOCUMENT.get()).data();
      assert.deepEqual(afterFailure, good);
      assert.equal(afterFailure.peopleTalkingNow, 1);
      assert.equal(afterFailure.accountsCreated, 42);
      assert.equal(afterFailure.roomsCreated, 9);
      // The staleness is visible only through updatedAt, which did not move.
      assert.equal(
        afterFailure.updatedAt.toMillis(),
        good.updatedAt.toMillis(),
      );
    });
});

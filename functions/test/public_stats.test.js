// publicStats/live — the real numbers replacing the hardcoded
// "2,481 people talking right now" on the marketing site.
//
// This document is world-readable (firestore.rules, `match /publicStats/live`,
// `allow get: if true`), so the load-bearing claims proved here are about what
// reaches the public, not only about arithmetic:
//
//   - the published key set is EXACTLY { schemaVersion, activeAccounts,
//     existingRooms, updatedAt } and contains nothing identifying;
//   - `peopleTalkingNow` is absent, and the publisher does not read voice
//     sessions at all — the dormant scan cannot be triggered by a caller;
//   - the account figure is counted from `publicProfiles`, never from `users`,
//     because `users` retains banned, disabled and Auth-orphaned rows;
//   - a current total that goes DOWN is published honestly, which is why the
//     fields are not named `accountsCreated` / `roomsCreated`;
//   - a failed run publishes NOTHING, so the previously published document
//     keeps its last good values instead of collapsing to a zero that would
//     read as "nobody is here".
//
// The last group of cases covers the deliberately unpublished live-presence
// scan. They are kept because the code is kept; see the header of
// ../stats/public_stats.js for why it is not wired to the publisher.

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
  ACTIVE_ACCOUNTS_COLLECTION,
  LIVE_SESSION_FRESHNESS_SECONDS,
  MAX_LIVE_SESSION_SCAN,
  PUBLIC_STATS_SCHEMA_VERSION,
  PublicStatsError,
  ROOMS_COLLECTION,
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
// Stand-ins for `publicProfiles` and `rooms`. The real collections cannot be
// counted in an assertion here: several suites run in parallel against one
// emulator and seed both, so any database-wide total is a race. Which
// collection the publisher actually reads is proved separately, and exactly,
// by the recording-database case below.
const ACCOUNT_FIXTURE = `${P}accountFixture`;
const ROOM_FIXTURE = `${P}roomFixture`;
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
  for (const name of [COUNT_FIXTURE, ACCOUNT_FIXTURE, ROOM_FIXTURE]) {
    const fixture = await db.collection(name).get();
    await Promise.all(fixture.docs.map((document) => document.ref.delete()));
  }
}

before(wipe);
after(wipe);

describe("public stats — the freshness bound (dormant, unpublished path)", () => {
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

describe("public stats — counting people, not sessions (dormant path)", () => {
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

describe("public stats — only canonical mirror rows count (dormant path)", () => {
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

describe("public stats — the read bound (dormant path)", () => {
  test("exceeding the scan bound fails loudly instead of returning a truncated number",
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
    // Current totals, not lifetime creation counters. Deleting an account or a
    // room lowers the published figure. That is exactly why the fields are
    // named `activeAccounts` and `existingRooms`: `accountsCreated` and
    // `roomsCreated` would be describing monotonic counters this function has
    // never computed, and a public "created" number that shrinks is a quieter
    // version of the fabricated figure this feature exists to delete.
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
        () => countCollection("publicProfiles", malformed),
        (error) => error instanceof PublicStatsError &&
          /did not return a usable total/.test(error.message),
      );
    });
});

describe("public stats — the account figure is not counted from `users`", () => {
  test("the account source is `publicProfiles` and the room source is `rooms`",
    async () => {
      // The exact collection each default reads is the whole claim here, so it
      // is recorded rather than reasoned about. `users` would overstate the
      // product: it is private account state that retains banned and disabled
      // rows, and on 2026-08-16 a production sweep found 18 of its 33
      // documents were Auth orphans with no Firebase Auth account behind them.
      // `publicProfiles` is the server-owned projection that treats Auth as
      // the existence authority — that a lingering `users` document cannot
      // recreate one is proved in public_profiles_security.test.js.
      const queried = [];
      const recording = {
        collection: (name) => {
          queried.push(name);
          return {
            count: () => ({ get: async () => ({ data: () => ({ count: 7 }) }) }),
          };
        },
      };

      const stats = await computePublicStats({
        countAccounts: () => countCollection(ACTIVE_ACCOUNTS_COLLECTION, recording),
        countRooms: () => countCollection(ROOMS_COLLECTION, recording),
      });

      assert.deepEqual(queried.sort(), ["publicProfiles", "rooms"]);
      assert.equal(queried.includes("users"), false);
      assert.equal(stats.activeAccounts, 7);
      assert.equal(stats.existingRooms, 7);
    });

  test("the published figures are the real counts of their own collections",
    async () => {
      await Promise.all([
        db.collection(ACCOUNT_FIXTURE).doc(`${P}a`).set({ seeded: true }),
        db.collection(ACCOUNT_FIXTURE).doc(`${P}b`).set({ seeded: true }),
        db.collection(ROOM_FIXTURE).doc(`${P}r1`).set({ seeded: true }),
        db.collection(ROOM_FIXTURE).doc(`${P}r2`).set({ seeded: true }),
        db.collection(ROOM_FIXTURE).doc(`${P}r3`).set({ seeded: true }),
      ]);

      const stats = await computePublicStats({
        countAccounts: () => countCollection(ACCOUNT_FIXTURE),
        countRooms: () => countCollection(ROOM_FIXTURE),
      });

      assert.equal(stats.activeAccounts, 2);
      assert.equal(stats.existingRooms, 3);
    });
});

describe("public stats — the published document", () => {
  test("the shape is exactly the two aggregates plus a version and a timestamp",
    async () => {
      const document = await publishPublicStats({
        countAccounts: async () => 1_204,
        countRooms: async () => 318,
        writeStats: (payload) => STATS_DOCUMENT.set(payload),
      });

      // This key set is the entire public exposure of the project. Every
      // addition to it is readable by anyone on the internet, unauthenticated,
      // forever — so the assertion is exhaustive on purpose and a new field
      // must be added here deliberately rather than arriving with a refactor.
      assert.deepEqual(Object.keys(document).sort(), [
        "activeAccounts",
        "existingRooms",
        "schemaVersion",
        "updatedAt",
      ]);

      const stored = (await STATS_DOCUMENT.get()).data();
      assert.deepEqual(Object.keys(stored).sort(), [
        "activeAccounts",
        "existingRooms",
        "schemaVersion",
        "updatedAt",
      ]);
      assert.equal(stored.schemaVersion, PUBLIC_STATS_SCHEMA_VERSION);
      assert.equal(stored.activeAccounts, 1_204);
      assert.equal(stored.existingRooms, 318);
      assert.ok(stored.updatedAt instanceof Timestamp);
      for (const key of ["activeAccounts", "existingRooms"]) {
        assert.ok(Number.isSafeInteger(stored[key]), `${key} is an integer`);
      }
      // Nothing identifying may reach a publicly readable document.
      assert.equal(JSON.stringify(stored).includes(ALICE), false);
      assert.equal(JSON.stringify(stored).includes(ROOM_A), false);
    });

  test("no live-presence field is published, under any name", async () => {
    const document = await publishPublicStats({
      countAccounts: async () => 7,
      countRooms: async () => 2,
      writeStats: (payload) => STATS_DOCUMENT.set(payload),
    });
    const stored = (await STATS_DOCUMENT.get()).data();

    // `activeVoiceSessions.expiresAt` is a token-issuance TTL that is never
    // renewed and is not cleaned up after a crash, so a room of twelve people
    // an hour into a conversation would publish ZERO. A field whose error
    // grows with the thing it measures is not a lower bound worth shipping;
    // the honest state is that the field does not exist yet. It is introduced
    // once, correctly, from the LiveKit webhook's `achievementVoiceSessions`.
    for (const key of ["peopleTalkingNow", "liveSpeakers", "peopleTalking"]) {
      assert.equal(key in document, false, `${key} must not be published`);
      assert.equal(key in stored, false, `${key} must not be stored`);
    }
  });

  test("the publisher never reads voice sessions — the dormant scan is not reachable through it",
    async () => {
      // If the scan were still wired in, this would reject. It is the only
      // check that would notice the dormant path being quietly reconnected —
      // and reconnecting it without the COLLECTION_GROUP index on
      // `rooms.expiresAt` throws FAILED_PRECONDITION on every scheduled run
      // in production, where no emulator test would ever see it.
      const document = await publishPublicStats({
        fetchSessions: async () => {
          throw new Error("the publisher must not scan voice sessions");
        },
        countAccounts: async () => 7,
        countRooms: async () => 2,
        writeStats: async () => {},
      });
      assert.equal(document.activeAccounts, 7);
    });

  test("a genuine zero is published — silence is the presentation layer's job",
    async () => {
      const document = await publishPublicStats({
        countAccounts: async () => 0,
        countRooms: async () => 0,
        writeStats: async () => {},
      });
      assert.equal(document.activeAccounts, 0);
      assert.equal(document.existingRooms, 0);
    });
});

describe("public stats — a failed run keeps the last good values", () => {
  const sources = [
    ["the accounts aggregate", {
      countAccounts: async () => {
        throw new Error("publicProfiles unavailable");
      },
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

  test("both sources failing at once surface one error, not an unhandled rejection",
    async () => {
      await assert.rejects(
        () => computePublicStats({
          countAccounts: async () => {
            throw new Error("publicProfiles unavailable");
          },
          countRooms: async () => { throw new Error("rooms unavailable"); },
        }),
        /publicProfiles unavailable/,
      );
      // Give the second rejection a turn to become unhandled if it were.
      await new Promise((resolve) => setImmediate(resolve));
    });

  test("the previously published document survives a failed run byte for byte",
    async () => {
      await publishPublicStats({
        countAccounts: async () => 42,
        countRooms: async () => 9,
        writeStats: (payload) => STATS_DOCUMENT.set(payload),
      });
      const good = (await STATS_DOCUMENT.get()).data();
      assert.equal(good.activeAccounts, 42);

      await assert.rejects(
        () => publishPublicStats({
          countAccounts: async () => {
            throw new Error("publicProfiles unavailable");
          },
          countRooms: async () => 0,
          writeStats: (payload) => STATS_DOCUMENT.set(payload),
        }),
        /unavailable/,
      );

      const afterFailure = (await STATS_DOCUMENT.get()).data();
      assert.deepEqual(afterFailure, good);
      assert.equal(afterFailure.activeAccounts, 42);
      assert.equal(afterFailure.existingRooms, 9);
      // The staleness is visible only through updatedAt, which did not move.
      assert.equal(
        afterFailure.updatedAt.toMillis(),
        good.updatedAt.toMillis(),
      );
    });
});

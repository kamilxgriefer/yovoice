// ADR-230 §1.4: opaque server-stored likers cursors.
const assert = require("node:assert/strict");
const { describe, test } = require("node:test");
const { HttpsError } = require("firebase-functions/v2/https");

const {
  LIKERS_CURSOR_KEYS,
  LIKERS_CURSOR_TTL_MS,
  likersTargetKey,
  newCursorToken,
  requireLikersCursorToken,
  resolveLikersCursor,
  storeLikersCursor,
} = require("../engagement/liker_cursors");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_820_000_000_000;
const VIEWER = "viewer-uid-1";
const LIKER = "liker-uid-with-a-recognisable-name";
const Timestamp = Object.freeze({ fromMillis: (millis) => new Date(millis) });
const timing = Object.freeze({ nowMs: NOW_MS, now: new Date(NOW_MS) });

const MOMENT_KEY = likersTargetKey({ targetType: "voiceMoment", ids: ["m1"] });
const HEART_KEY = likersTargetKey({
  targetType: "serverMessage", ids: ["s1", "c1", "msg1"], emoji: "❤️",
});

function invalidArgument(error) {
  assert.ok(error instanceof HttpsError, String(error));
  assert.equal(error.code, "invalid-argument");
  assert.equal(error.message, "cursor is invalid.");
  return true;
}

async function storeContent(db, overrides = {}) {
  return storeLikersCursor({
    db,
    Timestamp,
    viewerId: VIEWER,
    targetType: "voiceMoment",
    targetKey: MOMENT_KEY,
    position: { createdAt: new Date(NOW_MS - 5_000), id: LIKER },
    timing,
    ...overrides,
  });
}

function resolve(db, token, overrides = {}) {
  return resolveLikersCursor({
    db,
    token,
    viewerId: VIEWER,
    targetType: "voiceMoment",
    targetKey: MOMENT_KEY,
    nowMs: NOW_MS + 1_000,
    ...overrides,
  });
}

describe("tokens", () => {
  test("32 random bytes, base64url, 43 characters", () => {
    for (let index = 0; index < 20; index += 1) {
      assert.match(newCursorToken(), /^[A-Za-z0-9_-]{43}$/u);
    }
    assert.throws(() => newCursorToken(() => Buffer.alloc(16)), TypeError);
  });

  test("the token decodes to no uid and no time", async () => {
    const db = new InMemoryFirestore();
    const token = await storeContent(db);
    const decoded = Buffer.from(token, "base64url");
    assert.equal(decoded.length, 32);
    for (const leak of [LIKER, VIEWER, String(NOW_MS), String(NOW_MS - 5_000), "m1"]) {
      assert.equal(token.includes(leak), false, leak);
      assert.equal(decoded.includes(Buffer.from(leak)), false, leak);
    }
    // The position lives only in the server-only document.
    assert.equal(db.data(`likerPageCursors/${token}`).afterId, LIKER);
  });

  test("input validation: absent/null is the first page, anything else must match", () => {
    assert.equal(requireLikersCursorToken(undefined), null);
    assert.equal(requireLikersCursorToken(null), null);
    for (const value of ["", "A".repeat(42), "A".repeat(44), `${"A".repeat(42)}=`, 7, {}]) {
      assert.throws(() => requireLikersCursorToken(value), invalidArgument);
    }
  });
});

describe("store and resolve", () => {
  test("round trip for content and server positions", async () => {
    const db = new InMemoryFirestore();
    const token = await storeContent(db);
    const stored = db.data(`likerPageCursors/${token}`);
    assert.deepEqual(Object.keys(stored).sort(), [...LIKERS_CURSOR_KEYS]);
    assert.equal(stored.expiresAt.getTime() - stored.createdAt.getTime(), LIKERS_CURSOR_TTL_MS);
    assert.equal(LIKERS_CURSOR_TTL_MS, 15 * 60_000);
    const position = await resolve(db, token);
    assert.equal(position.id, LIKER);
    assert.equal(position.createdAt.getTime(), NOW_MS - 5_000);
    // Reusable until it expires.
    assert.deepEqual(await resolve(db, token), position);

    const serverToken = await storeLikersCursor({
      db, Timestamp, viewerId: VIEWER, targetType: "serverMessage",
      targetKey: HEART_KEY, position: { emojiIndex: 0, uid: LIKER }, timing,
    });
    assert.deepEqual(await resolve(db, serverToken, {
      targetType: "serverMessage", targetKey: HEART_KEY,
    }), { emojiIndex: 0, uid: LIKER });
    assert.equal(await resolve(db, null), null);
  });

  test("foreign viewer, other target, other emoji or expiry is invalid-argument", async () => {
    const db = new InMemoryFirestore();
    const token = await storeContent(db);
    const serverToken = await storeLikersCursor({
      db, Timestamp, viewerId: VIEWER, targetType: "serverMessage",
      targetKey: HEART_KEY, position: { emojiIndex: 0, uid: LIKER }, timing,
    });
    const refusals = [
      [token, { viewerId: "someone-else" }],
      [token, { targetKey: likersTargetKey({ targetType: "voiceMoment", ids: ["m2"] }) }],
      [token, {
        targetType: "voiceMomentComment",
        targetKey: likersTargetKey({ targetType: "voiceMomentComment", ids: ["m1", "c1"] }),
      }],
      [token, {
        targetType: "reel",
        targetKey: likersTargetKey({ targetType: "reel", ids: ["m1"] }),
      }],
      [serverToken, {
        targetType: "serverMessage",
        targetKey: likersTargetKey({
          targetType: "serverMessage", ids: ["s1", "c1", "msg1"], emoji: "🔥",
        }),
      }],
      [serverToken, {
        targetType: "serverMessage",
        targetKey: likersTargetKey({ targetType: "serverMessage", ids: ["s1", "c1", "msg1"] }),
      }],
      // A server cursor presented to a content target with its key.
      [serverToken, { targetKey: HEART_KEY }],
      [token, { nowMs: NOW_MS + LIKERS_CURSOR_TTL_MS }],
      [token, { nowMs: NOW_MS + LIKERS_CURSOR_TTL_MS + 1 }],
      ["B".repeat(43), {}],
    ];
    for (const [value, overrides] of refusals) {
      await assert.rejects(resolve(db, value, overrides), invalidArgument, JSON.stringify(overrides));
    }
  });

  test("missing, extra or mistyped stored keys are invalid-argument", async () => {
    const mutations = {
      missingAfterUid: (data) => { delete data.afterUid; },
      extraKey: (data) => { data.limit = 50; },
      schemaVersion: (data) => { data.schemaVersion = 2; },
      ttlMismatch: (data) => { data.expiresAt = new Date(NOW_MS + 60 * 60_000); },
      stringExpiry: (data) => { data.expiresAt = "later"; },
      serverFieldsOnContent: (data) => { data.afterEmojiIndex = 0; },
      missingPosition: (data) => { data.afterCreatedAt = null; },
      pathInId: (data) => { data.afterId = "a/b"; },
    };
    for (const [label, mutate] of Object.entries(mutations)) {
      const db = new InMemoryFirestore();
      const token = await storeContent(db);
      const data = db.data(`likerPageCursors/${token}`);
      mutate(data);
      db.seed(`likerPageCursors/${token}`, data);
      await assert.rejects(resolve(db, token), invalidArgument, label);
    }
    const db = new InMemoryFirestore();
    const serverToken = await storeLikersCursor({
      db, Timestamp, viewerId: VIEWER, targetType: "serverMessage",
      targetKey: HEART_KEY, position: { emojiIndex: 0, uid: LIKER }, timing,
    });
    const data = db.data(`likerPageCursors/${serverToken}`);
    data.afterEmojiIndex = 6;
    db.seed(`likerPageCursors/${serverToken}`, data);
    await assert.rejects(resolve(db, serverToken, {
      targetType: "serverMessage", targetKey: HEART_KEY,
    }), invalidArgument);
  });

  test("a malformed position is never stored", async () => {
    const db = new InMemoryFirestore();
    for (const position of [
      null,
      { createdAt: undefined, id: LIKER },
      { createdAt: { nested: true }, id: LIKER },
      { createdAt: new Date(NOW_MS), id: "" },
      { createdAt: new Date(NOW_MS), id: "a/b" },
    ]) {
      await assert.rejects(storeContent(db, { position }), (error) => error.code === "data-loss");
    }
    for (const position of [{ emojiIndex: 6, uid: LIKER }, { emojiIndex: 0, uid: "" }, { emojiIndex: 0.5, uid: LIKER }]) {
      await assert.rejects(storeLikersCursor({
        db, Timestamp, viewerId: VIEWER, targetType: "serverMessage",
        targetKey: HEART_KEY, position, timing,
      }), (error) => error.code === "data-loss");
    }
    assert.equal(db.paths("likerPageCursors/").length, 0);
  });

  test("a malformed but consumed edge's scalar createdAt still pages", async () => {
    const db = new InMemoryFirestore();
    const token = await storeContent(db, { position: { createdAt: "2026-09-28", id: LIKER } });
    assert.deepEqual(await resolve(db, token), { createdAt: "2026-09-28", id: LIKER });
  });

  test("firestore.indexes.json deletes expired cursors by TTL", () => {
    const { fieldOverrides } = require("../../firestore.indexes.json");
    const overrides = fieldOverrides.filter((entry) =>
      entry.collectionGroup === "likerPageCursors");
    assert.deepEqual(overrides, [{
      collectionGroup: "likerPageCursors",
      fieldPath: "expiresAt",
      ttl: true,
      indexes: [],
    }]);
  });

  test("the target key covers type, every id and the emoji filter", () => {
    const keys = new Set([
      likersTargetKey({ targetType: "voiceMoment", ids: ["a"] }),
      likersTargetKey({ targetType: "reel", ids: ["a"] }),
      likersTargetKey({ targetType: "voiceMomentComment", ids: ["a", "b"] }),
      likersTargetKey({ targetType: "reelComment", ids: ["a", "b"] }),
      likersTargetKey({ targetType: "serverMessage", ids: ["a", "b", "c"] }),
      likersTargetKey({ targetType: "serverMessage", ids: ["a", "b", "c"], emoji: "❤️" }),
      likersTargetKey({ targetType: "serverMessage", ids: ["a", "b", "d"] }),
    ]);
    assert.equal(keys.size, 7);
    for (const key of keys) assert.match(key, /^[a-f0-9]{64}$/u);
    assert.throws(() => likersTargetKey({ targetType: "dm", ids: ["a"] }), TypeError);
    assert.throws(
      () => likersTargetKey({ targetType: "reel", ids: ["a"], emoji: "❤️" }),
      TypeError,
    );
  });
});

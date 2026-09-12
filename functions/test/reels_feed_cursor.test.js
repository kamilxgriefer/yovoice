const assert = require("node:assert/strict");
const { test } = require("node:test");

const { FEED_CURSOR_PATTERN, validateFeedCursor, validateSortKey } =
  require("../reels/contract");
const {
  FEED_MODES,
  decodeFeedCursor,
  deriveFeedSeed,
  encodeFeedCursor,
  feedModeFor,
  mintFeedSeed,
  randomFeedSeed,
} = require("../reels/ranking");

const UID = "viewer-1";
const SEED = "0123456789abcdef";
const POSITION = "1778000000000_reel-a";

test("the v2 grammar cannot collide with the legacy bare-sortKey form", () => {
  const legacy = POSITION;
  const v2 = `f1.d.${SEED}.${POSITION}`;
  assert.equal(FEED_CURSOR_PATTERN.test(legacy), false);
  assert.equal(FEED_CURSOR_PATTERN.test(v2), true);
  // Both grammars are accepted by the v2 validator; only the legacy one is
  // accepted by validateSortKey, which v1 keeps using unchanged.
  assert.equal(validateFeedCursor(legacy), legacy);
  assert.equal(validateFeedCursor(v2), v2);
  assert.equal(validateSortKey(legacy), legacy);
  assert.throws(
    () => validateSortKey(v2),
    (error) => error.code === "invalid-argument",
  );
  assert.ok(v2.length <= 164);
});

test("a rejected cursor reuses the existing client-visible message", () => {
  for (const bad of [
    "",
    "f1.x.0123456789abcdef.1778000000000_reel-a",
    "f1.d.0123456789ABCDEF.1778000000000_reel-a",
    "f1.d.0123456789abcde.1778000000000_reel-a",
    "f1.d.0123456789abcdef.177800000000_reel-a",
    "f2.d.0123456789abcdef.1778000000000_reel-a",
    `f1.d.${SEED}.${POSITION}.extra`,
    `f1.d.${SEED}.1778000000000_${"x".repeat(129)}`,
    42,
    null,
  ]) {
    assert.throws(
      () => validateFeedCursor(bad),
      (error) =>
        error.code === "invalid-argument" && error.message === "cursor is invalid.",
      `expected rejection for ${String(bad)}`,
    );
  }
});

test("encode and decode round-trip every mode", () => {
  for (const mode of Object.values(FEED_MODES)) {
    const cursor = encodeFeedCursor({ mode, seed: SEED, position: POSITION });
    assert.equal(cursor, `f1.${mode}.${SEED}.${POSITION}`);
    assert.deepEqual(decodeFeedCursor(cursor, { mode, uid: UID }), {
      seed: SEED,
      position: POSITION,
      legacy: false,
    });
  }
});

test("encoding refuses a non-canonical position or a malformed seed", () => {
  assert.throws(
    () => encodeFeedCursor({ mode: "d", seed: SEED, position: "not-a-sort-key" }),
    TypeError,
  );
  assert.throws(
    () => encodeFeedCursor({ mode: "d", seed: "short", position: POSITION }),
    TypeError,
  );
  assert.throws(
    () => encodeFeedCursor({ mode: "z", seed: SEED, position: POSITION }),
    TypeError,
  );
});

test("a cursor whose mode disagrees with the request is rejected", () => {
  const discover = encodeFeedCursor({
    mode: FEED_MODES.discover,
    seed: SEED,
    position: POSITION,
  });
  assert.throws(
    () => decodeFeedCursor(discover, { mode: FEED_MODES.own, uid: UID }),
    (error) =>
      error.code === "invalid-argument" && error.message === "cursor is invalid.",
  );
  assert.throws(
    () =>
      decodeFeedCursor(discover, {
        mode: FEED_MODES.discoverIncludingSeen,
        uid: UID,
      }),
    (error) => error.code === "invalid-argument",
  );
});

test("a legacy in-flight cursor still ranks, deterministically", () => {
  const decoded = decodeFeedCursor(POSITION, {
    mode: FEED_MODES.discover,
    uid: UID,
  });
  assert.equal(decoded.position, POSITION);
  assert.equal(decoded.legacy, true);
  assert.match(decoded.seed, /^[0-9a-f]{16}$/u);
  // The same (uid, position) must derive the same seed on every retry, or a
  // retried page would silently reorder under the user.
  assert.equal(decoded.seed, deriveFeedSeed(UID, POSITION));
  assert.notEqual(deriveFeedSeed("other-viewer", POSITION), decoded.seed);
  assert.notEqual(deriveFeedSeed(UID, "1778000000001_reel-b"), decoded.seed);
});

test("a null cursor means mint, not decode", () => {
  assert.equal(decodeFeedCursor(null, { mode: "d", uid: UID }), null);
  assert.equal(decodeFeedCursor(undefined, { mode: "d", uid: UID }), null);
});

test("mode is derived from scope and includeSeen", () => {
  assert.equal(feedModeFor({ scope: "discover", includeSeen: false }), "d");
  assert.equal(feedModeFor({ scope: "discover", includeSeen: true }), "s");
  assert.equal(feedModeFor({ scope: "own", includeSeen: false }), "o");
});

test("the seed minter is validated and the default one is 64 real bits", () => {
  assert.equal(mintFeedSeed(() => SEED), SEED);
  assert.throws(() => mintFeedSeed(() => "nope"), TypeError);
  assert.throws(() => mintFeedSeed(() => null), TypeError);
  assert.throws(() => mintFeedSeed("not-a-function"), TypeError);
  const seeds = new Set();
  for (let index = 0; index < 200; index += 1) {
    const seed = randomFeedSeed();
    assert.match(seed, /^[0-9a-f]{16}$/u);
    seeds.add(seed);
  }
  assert.equal(seeds.size, 200);
});

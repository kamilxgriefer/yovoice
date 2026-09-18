const assert = require("node:assert/strict");
const { test } = require("node:test");

const logger = require("firebase-functions/logger");
const { fail } = require("../integrity/guards");

// RC-10 (backend). `fail()` is the single refusal primitive of this backend —
// ~300 call sites across ~40 modules — and the callable framework logs NOTHING
// for an explicitly thrown HttpsError. Every one of the 34 production 500s in
// the 2026-09-14 window therefore carried zero application log lines, which is
// how a total publishing outage stayed invisible for 2.2 days.
//
// Spying on the exact logger module `integrity/guards.js` requires is the same
// seam test/room_liveness_sweeper.test.js already uses.
function captureWarnings(body) {
  const original = logger.warn;
  const entries = [];
  logger.warn = (...args) => entries.push(args);
  try {
    body();
  } finally {
    logger.warn = original;
  }
  return entries;
}

test("a data-loss refusal logs exactly one structured warn and still throws",
  () => {
    const entries = captureWarnings(() => {
      assert.throws(
        () => fail("data-loss", "The canonical public profile is malformed."),
        (error) => {
          assert.equal(error.code, "data-loss");
          assert.equal(
            error.message,
            "The canonical public profile is malformed.",
          );
          return true;
        },
      );
    });

    assert.equal(entries.length, 1);
    const [message, payload] = entries[0];
    assert.equal(message, "integrity refusal");
    // Exactly {code, reason, fn} — nothing else may ride along, because every
    // one of the 300 call sites passes a static author-written English string
    // and that is the only reason central logging is privacy-safe here.
    assert.deepEqual(Object.keys(payload).sort(), ["code", "fn", "reason"]);
    assert.equal(payload.code, "data-loss");
    assert.equal(payload.reason, "The canonical public profile is malformed.");
  });

test("an internal refusal is logged and every routine refusal stays silent",
  () => {
    const internal = captureWarnings(() => {
      assert.throws(
        () => fail("internal", "The server could not complete the request."),
        (error) => error.code === "internal",
      );
    });
    assert.equal(internal.length, 1);
    assert.equal(internal[0][1].code, "internal");

    // In a healthy system this logs approximately nothing: a block, a quota, a
    // bad argument and a missing document are all expected outcomes, and if
    // they were logged here the signal above would be worthless.
    for (const code of [
      "permission-denied",
      "failed-precondition",
      "resource-exhausted",
      "invalid-argument",
      "already-exists",
      "not-found",
      "unauthenticated",
      "aborted",
      "unavailable",
    ]) {
      const entries = captureWarnings(() => {
        assert.throws(
          () => fail(code, "A routine refusal."),
          (error) => error.code === code,
        );
      });
      assert.deepEqual(entries, [], `${code} must not be logged`);
    }
  });

test("the logged function name comes from the Cloud Run environment", () => {
  const originalTarget = process.env.FUNCTION_TARGET;
  const originalService = process.env.K_SERVICE;
  try {
    process.env.FUNCTION_TARGET = "getVoiceMomentsFeedV2";
    delete process.env.K_SERVICE;
    let entries = captureWarnings(() => {
      assert.throws(() => fail("data-loss", "A refusal."));
    });
    assert.equal(entries[0][1].fn, "getVoiceMomentsFeedV2");

    delete process.env.FUNCTION_TARGET;
    process.env.K_SERVICE = "finalizereeldraftv2";
    entries = captureWarnings(() => {
      assert.throws(() => fail("internal", "A refusal."));
    });
    assert.equal(entries[0][1].fn, "finalizereeldraftv2");

    delete process.env.K_SERVICE;
    entries = captureWarnings(() => {
      assert.throws(() => fail("data-loss", "A refusal."));
    });
    assert.equal(entries[0][1].fn, null);
  } finally {
    if (originalTarget === undefined) delete process.env.FUNCTION_TARGET;
    else process.env.FUNCTION_TARGET = originalTarget;
    if (originalService === undefined) delete process.env.K_SERVICE;
    else process.env.K_SERVICE = originalService;
  }
});

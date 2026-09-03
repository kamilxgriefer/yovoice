const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  REGION,
  REEL_CALLABLE_METHODS,
  createReelFunctions,
} = require("../reels");

function fakeRuntime(calls = []) {
  const service = {};
  for (const method of Object.values(REEL_CALLABLE_METHODS)) {
    service[method] = async (request) => {
      calls.push({ method, request });
      return { method };
    };
  }
  service.expireAbandonedReelDrafts = async () => ({ expired: [] });
  service.processCleanupOutbox = async (outboxId) => ({
    outboxId,
    completed: true,
  });
  return {
    db: {
      collection() {
        return {
          where() { return this; },
          limit() { return this; },
          async get() { return { size: 0, docs: [] }; },
        };
      },
    },
    FieldPath: { documentId: () => ({}) },
    service,
  };
}

function fakeRegistrars(registrations) {
  const register = (kind) => (options, handler) => {
    const value = { kind, options: { ...options }, handler };
    registrations.push(value);
    return value;
  };
  return {
    onCall: register("callable"),
    onDocumentCreated: register("created"),
    onSchedule: register("schedule"),
  };
}

test("Reel export map registers bounded callables and private maintenance", () => {
  const registrations = [];
  const functions = createReelFunctions({
    runtime: fakeRuntime(),
    registrars: fakeRegistrars(registrations),
    enforceAppCheck: true,
  });
  assert.deepEqual(
    Object.keys(functions).sort(),
    [
      ...Object.keys(REEL_CALLABLE_METHODS),
      "expireAbandonedReelDraftsSchedule",
      "processPendingReelCleanupSchedule",
      "onReelCleanupOutboxCreated",
    ].sort(),
  );
  const callables = registrations.filter(({ kind }) => kind === "callable");
  assert.equal(callables.length, Object.keys(REEL_CALLABLE_METHODS).length);
  for (const callable of callables) {
    assert.equal(callable.options.region, REGION);
    assert.equal(callable.options.enforceAppCheck, true);
    assert.equal(callable.options.consumeAppCheckToken, true);
  }
  const created = registrations.find(({ kind }) => kind === "created");
  assert.equal(created.options.document, "reelCleanupOutbox/{outboxId}");
  assert.equal(created.options.retry, true);
});

test("callable bindings preserve only Firebase Auth identity and data", async () => {
  const calls = [];
  const functions = createReelFunctions({
    runtime: fakeRuntime(calls),
    registrars: fakeRegistrars([]),
  });
  await functions.listReels.handler({
    auth: { uid: "opaque-user", token: { email_verified: true } },
    app: { forged: true },
    data: { cursor: null, limit: 10 },
    rawRequest: { headers: { "x-user": "attacker" } },
  });
  assert.deepEqual(calls[0], {
    method: "listReels",
    request: {
      auth: { uid: "opaque-user", token: { email_verified: true } },
      data: { cursor: null, limit: 10 },
    },
  });
});

const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  REGION,
  REEL_CLEANUP_BATCH_SIZE,
  REEL_CLEANUP_MAX_BATCHES,
  REEL_CALLABLE_METHODS,
  REEL_EXPIRY_BATCH_SIZE,
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
  service.expirePublishedReels = async () => ({ expired: [] });
  service.processCleanupOutbox = async (outboxId) => ({
    outboxId,
    completed: true,
  });
  service.processReadyCleanupOutbox = async ({ limit }) => {
    calls.push({ method: "processReadyCleanupOutbox", limit });
    return {
      processed: 0,
      completed: 0,
      failed: [],
      hasMore: false,
      limit,
    };
  };
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
      "expirePublishedReelsSchedule",
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

test("cleanup schedule delegates bounded retry and lease selection", async () => {
  const calls = [];
  const functions = createReelFunctions({
    runtime: fakeRuntime(calls),
    registrars: fakeRegistrars([]),
    cleanupBatchSize: 17,
  });
  const result = await functions.processPendingReelCleanupSchedule.handler();
  assert.deepEqual(calls, [{
    method: "processReadyCleanupOutbox",
    limit: 17,
  }]);
  assert.equal(result.batchSize, 17);
  assert.equal(result.batches, 1);
  assert.equal(result.hasMore, false);
});

test("cleanup schedule drains bounded pages faster than expiry can produce", async () => {
  const calls = [];
  const runtime = fakeRuntime(calls);
  runtime.service.processReadyCleanupOutbox = async ({ limit }) => {
    calls.push({ method: "processReadyCleanupOutbox", limit });
    return {
      processed: limit,
      completed: limit,
      failed: [],
      hasMore: true,
    };
  };
  const functions = createReelFunctions({
    runtime,
    registrars: fakeRegistrars([]),
  });
  const result = await functions.processPendingReelCleanupSchedule.handler();

  assert.equal(calls.length, REEL_CLEANUP_MAX_BATCHES);
  assert.ok(calls.every(({ limit }) => limit === REEL_CLEANUP_BATCH_SIZE));
  assert.equal(
    result.processed,
    REEL_CLEANUP_BATCH_SIZE * REEL_CLEANUP_MAX_BATCHES,
  );
  assert.equal(result.batches, REEL_CLEANUP_MAX_BATCHES);
  assert.equal(result.hasMore, true);
  // Expiry can enqueue at most this many rows per ten-minute run. Cleanup
  // has the asserted capacity every five minutes, without relying on triggers.
  assert.ok(result.processed >= REEL_EXPIRY_BATCH_SIZE);
});

test("cleanup schedule keeps scanning when a cursor advanced without work",
  async () => {
    const calls = [];
    const runtime = fakeRuntime(calls);
    const pages = [
      { processed: 0, completed: 0, failed: [], hasMore: true },
      { processed: 1, completed: 1, failed: [], hasMore: false },
    ];
    runtime.service.processReadyCleanupOutbox = async ({ limit }) => {
      calls.push({ method: "processReadyCleanupOutbox", limit });
      return pages.shift();
    };
    const functions = createReelFunctions({
      runtime,
      registrars: fakeRegistrars([]),
      cleanupBatchSize: 2,
    });

    const result = await functions.processPendingReelCleanupSchedule.handler();

    assert.equal(calls.length, 2);
    assert.equal(result.batches, 2);
    assert.equal(result.processed, 1);
    assert.equal(result.completed, 1);
    assert.equal(result.hasMore, false);
  });

test("cleanup create trigger logs a terminal dead letter with safe fields",
  async () => {
    const runtime = fakeRuntime();
    runtime.service.processCleanupOutbox = async (outboxId) => ({
      outboxId,
      completed: false,
      deadLetter: true,
      code: "data-loss",
      message: "must not be logged",
      storageObjects: [{ path: "must/not/be/logged" }],
    });
    const errors = [];
    const functions = createReelFunctions({
      runtime,
      registrars: fakeRegistrars([]),
      log: { error: (...args) => errors.push(args) },
    });

    const result = await functions.onReelCleanupOutboxCreated.handler({
      data: { exists: true },
      params: { outboxId: "malformed-outbox" },
    });

    assert.equal(result.deadLetter, true);
    assert.deepEqual(errors, [[
      "Reel cleanup trigger reached dead letter",
      {
        outboxId: "malformed-outbox",
        deadLetter: true,
        code: "data-loss",
      },
    ]]);
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

const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  AchievementOutboxValidationError,
  OUTBOX_RETENTION_MS,
  buildAchievementOutboxRecord,
  createAchievementRuntime,
  normalizeAchievementOutboxRecord,
} = require("../achievements/runtime");
const {
  InMemoryAchievementRepository,
} = require("./helpers/in_memory_achievement_repository");

const NOW = new Date("2026-08-16T12:00:00.000Z");

function messageEvent(overrides = {}) {
  return {
    sourceType: "dmMessageCreated",
    sourceKey: "conversations/c-1/messages/m-1",
    beneficiaryId: "user-1",
    actorId: "user-1",
    metric: "messages",
    mode: "increment",
    delta: 1,
    occurredAt: NOW,
    ...overrides,
  };
}

describe("achievement runtime and durable outbox", () => {
  test("builds a deterministic bounded-retention outbox record", () => {
    const first = buildAchievementOutboxRecord(messageEvent(), NOW);
    const second = buildAchievementOutboxRecord(messageEvent(), NOW);
    assert.deepEqual(first, second);
    assert.match(first.eventId, /^v1_[a-f0-9]{64}$/u);
    assert.equal(
      first.expiresAt.getTime() - first.createdAt.getTime(),
      OUTBOX_RETENTION_MS,
    );
    assert.equal(
      normalizeAchievementOutboxRecord(first, first.eventId).eventId,
      first.eventId,
    );
  });

  test("tampered identity, payload and retention fail closed", () => {
    const record = buildAchievementOutboxRecord(messageEvent(), NOW);
    assert.throws(
      () => normalizeAchievementOutboxRecord({
        ...record,
        event: { ...record.event, beneficiaryId: "other-user" },
      }, record.eventId),
      AchievementOutboxValidationError,
    );
    assert.throws(
      () => normalizeAchievementOutboxRecord({
        ...record,
        expiresAt: new Date(record.expiresAt.getTime() + 1),
      }, record.eventId),
      AchievementOutboxValidationError,
    );
    assert.throws(
      () => normalizeAchievementOutboxRecord(record, "wrong-id"),
      AchievementOutboxValidationError,
    );
  });

  test("processing the same outbox concurrently is exactly once", async () => {
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", {});
    const runtime = createAchievementRuntime({ repository, clock: () => NOW });
    const record = buildAchievementOutboxRecord(messageEvent(), NOW);
    const results = await Promise.all([
      runtime.processOutboxRecord(record, record.eventId),
      runtime.processOutboxRecord(record, record.eventId),
      runtime.processOutboxRecord(record, record.eventId),
    ]);
    assert.equal(results.filter((result) => result.outcome === "applied").length, 1);
    assert.equal(results.filter((result) => result.outcome === "replayed").length, 2);
    assert.equal(repository.progressFor("user-1").verifiedMetrics.messages, 1);
    assert.equal(repository.notificationEntries("user-1").length, 1);
  });

  test("a canonical source also emits one deterministic active-day event", async () => {
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", {});
    const runtime = createAchievementRuntime({ repository, clock: () => NOW });
    const first = await runtime.processSourceEvent(messageEvent());
    const replay = await runtime.processSourceEvent(messageEvent());
    assert.equal(first.results.length, 2);
    assert.equal(replay.results.every((result) => result.outcome === "replayed"), true);
    const progress = repository.progressFor("user-1");
    assert.equal(progress.verifiedMetrics.messages, 1);
    assert.equal(progress.verifiedMetrics.activeDays, 1);
  });

  test("a second qualifying event on the same user-day replays the active day instead of colliding", async () => {
    // 2026-08-18 production incident: the second message of a user-day
    // derived the same active-day eventId with a different fingerprint,
    // failed closed, and the at-least-once trigger retried forever.
    const errors = [];
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", {});
    const runtime = createAchievementRuntime({
      repository,
      clock: () => NOW,
      logger: { error: (...args) => errors.push(args) },
    });
    const first = await runtime.processSourceEvent(messageEvent());
    const second = await runtime.processSourceEvent(messageEvent({
      sourceKey: "conversations/c-1/messages/m-2",
      occurredAt: new Date(NOW.getTime() + 90_000),
    }));
    assert.deepEqual(
      first.results.map((result) => result.outcome),
      ["applied", "applied"],
    );
    assert.deepEqual(
      second.results.map((result) => result.outcome),
      ["applied", "replayed"],
    );
    const progress = repository.progressFor("user-1");
    assert.equal(progress.verifiedMetrics.messages, 2);
    assert.equal(progress.verifiedMetrics.activeDays, 1);
    // A clean same-day replay is not a collision and reports nothing.
    assert.equal(errors.length, 0);
  });
});

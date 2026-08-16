const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  AchievementEngine,
} = require("../achievements/engine");
const {
  AchievementSelectionError,
  selectAchievementTitle,
} = require("../achievements/selection");
const { InMemoryAchievementRepository } = require(
  "./helpers/in_memory_achievement_repository",
);

const UID = "selection-user";
const NOW = new Date("2026-08-16T13:00:00.000Z");

function setup(user = {}) {
  const repository = new InMemoryAchievementRepository();
  repository.seedUser(UID, { uid: UID, ...user });
  return repository;
}

describe("server-side achievement title selection", () => {
  test("an unverified legacy title cannot be selected", async () => {
    const timestamp = new Date("2026-08-01T10:00:00.000Z");
    const repository = setup({
      roomCount: 5,
      unlockedTitleIds: ["rooms_1"],
      unlockedTitleTimestamps: { rooms_1: timestamp },
    });
    await assert.rejects(
      selectAchievementTitle({
        repository,
        uid: UID,
        titleId: "rooms_1",
        clock: () => NOW,
      }),
      (error) => error instanceof AchievementSelectionError &&
        error.code === "failed-precondition",
    );
    assert.equal(repository.progressFor(UID), undefined);
    assert.equal(repository.user(UID).selectedTitleId, undefined);
    assert.deepEqual(repository.user(UID).unlockedTitleTimestamps.rooms_1, timestamp);
  });

  test("a forged legacy title becomes selectable only after a source verifies it", async () => {
    const repository = setup({
      messageCount: 10000,
      unlockedTitleIds: ["messages_1", "messages_10000"],
      selectedTitleId: "messages_10000",
    });
    await assert.rejects(
      selectAchievementTitle({
        repository,
        uid: UID,
        titleId: "messages_1",
        clock: () => NOW,
      }),
      (error) => error instanceof AchievementSelectionError &&
        error.code === "failed-precondition",
    );

    const engine = new AchievementEngine({ repository, clock: () => NOW });
    await engine.process({
      sourceType: "dmMessageCreated",
      sourceKey: "conversations/c/messages/server-verified",
      beneficiaryId: UID,
      actorId: UID,
      metric: "messages",
      mode: "increment",
      delta: 1,
      occurredAt: NOW,
    });
    const selected = await selectAchievementTitle({
      repository,
      uid: UID,
      titleId: "messages_1",
      clock: () => new Date(NOW.getTime() + 1),
    });

    assert.deepEqual(selected, {
      outcome: "updated",
      selectedTitleId: "messages_1",
    });
    assert.deepEqual(repository.user(UID).unlockedTitleIds, ["messages_1"]);
    assert.equal(repository.user(UID).messageCount, 1);
  });

  test("a verified title is selectable and null explicitly clears it", async () => {
    const repository = setup();
    repository.seedProgress(UID, {
      verifiedMetrics: { messages: 1 },
      peakMetrics: { messages: 1 },
      verifiedUnlockedTitleIds: ["messages_1"],
      verifiedUnlockedTitleTimestamps: { messages_1: NOW },
      legacyMetricFloors: {},
      legacyUnlockedTitleIds: [],
      legacyUnlockedTitleTimestamps: {},
    });
    await selectAchievementTitle({
      repository,
      uid: UID,
      titleId: "messages_1",
      clock: () => NOW,
    });
    const cleared = await selectAchievementTitle({
      repository,
      uid: UID,
      titleId: null,
      clock: () => new Date(NOW.getTime() + 1000),
    });
    assert.deepEqual(cleared, { outcome: "updated", selectedTitleId: null });
    assert.equal(repository.progressFor(UID).selectedTitleId, null);
    assert.equal(repository.user(UID).selectedTitleId, null);
  });

  test("locked, unknown and malformed titles fail closed without changing projection", async () => {
    const repository = setup({ unlockedTitleIds: ["rooms_1"] });
    for (const titleId of ["rooms_10", "not-in-catalog", 42]) {
      await assert.rejects(
        selectAchievementTitle({
          repository,
          uid: UID,
          titleId,
          clock: () => NOW,
        }),
        (error) => error instanceof AchievementSelectionError &&
          ["failed-precondition", "invalid-argument"].includes(error.code),
      );
    }
    assert.equal(repository.progressFor(UID), undefined);
    assert.equal(repository.user(UID).selectedTitleId, undefined);
  });

  test("selecting an already-selected verified title is an idempotent no-op", async () => {
    const repository = setup();
    repository.seedProgress(UID, {
      verifiedMetrics: { messages: 1 },
      peakMetrics: { messages: 1 },
      verifiedUnlockedTitleIds: ["messages_1"],
      verifiedUnlockedTitleTimestamps: { messages_1: NOW },
      legacyMetricFloors: {},
      legacyUnlockedTitleIds: [],
      legacyUnlockedTitleTimestamps: {},
      selectedTitleId: "messages_1",
    });
    const result = await selectAchievementTitle({
      repository,
      uid: UID,
      titleId: "messages_1",
      clock: () => NOW,
    });
    assert.deepEqual(result, {
      outcome: "unchanged",
      selectedTitleId: "messages_1",
    });
    assert.equal(repository.progressFor(UID).selectedTitleId, "messages_1");
  });

  test("selection never creates a deleted profile", async () => {
    const repository = new InMemoryAchievementRepository();
    await assert.rejects(
      selectAchievementTitle({
        repository,
        uid: UID,
        titleId: null,
        clock: () => NOW,
      }),
      (error) => error instanceof AchievementSelectionError && error.code === "not-found",
    );
    assert.equal(repository.user(UID), undefined);
  });

  test("selection preserves an opaque Auth UID instead of trimming into a neighbour", async () => {
    const spacedUid = " selection-user ";
    const repository = new InMemoryAchievementRepository();
    repository.seedUser(UID, { uid: UID, unlockedTitleIds: [] });
    repository.seedUser(spacedUid, {
      uid: spacedUid,
    });
    repository.seedProgress(spacedUid, {
      verifiedMetrics: { rooms: 1 },
      peakMetrics: { rooms: 1 },
      verifiedUnlockedTitleIds: ["rooms_1"],
      verifiedUnlockedTitleTimestamps: { rooms_1: NOW },
      legacyMetricFloors: {},
      legacyUnlockedTitleIds: [],
      legacyUnlockedTitleTimestamps: {},
    });

    await selectAchievementTitle({
      repository,
      uid: spacedUid,
      titleId: "rooms_1",
      clock: () => NOW,
    });

    assert.equal(repository.user(spacedUid).selectedTitleId, "rooms_1");
    assert.equal(repository.user(UID).selectedTitleId, undefined);
    await assert.rejects(
      selectAchievementTitle({
        repository,
        uid: "bad\u0000uid",
        titleId: null,
        clock: () => NOW,
      }),
      (error) => error instanceof AchievementSelectionError &&
        error.code === "invalid-argument",
    );
  });
});

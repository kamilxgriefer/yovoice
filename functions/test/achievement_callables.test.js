const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  CALLABLE_OPTIONS,
  createSelectMyAchievementTitleHandler,
} = require("../achievements/callables");
const {
  InMemoryAchievementRepository,
} = require("./helpers/in_memory_achievement_repository");

const NOW = new Date("2026-08-16T12:00:00.000Z");

function handlerFor(repository) {
  return createSelectMyAchievementTitleHandler({ repository, clock: () => NOW });
}

describe("auth-bound achievement title callable", () => {
  test("keeps web App Check disabled until external web setup exists", () => {
    assert.deepEqual(CALLABLE_OPTIONS, {
      region: "europe-west1",
      enforceAppCheck: false,
    });
  });

  test("requires auth and rejects every beneficiary-smuggling field", async () => {
    const repository = new InMemoryAchievementRepository();
    const handler = handlerFor(repository);
    await assert.rejects(
      handler({ data: { titleId: null } }),
      (error) => error.code === "unauthenticated",
    );
    await assert.rejects(
      handler({
        auth: { uid: "user-1" },
        data: { titleId: null, uid: "victim" },
      }),
      (error) => error.code === "invalid-argument",
    );
  });

  // The client has always sent `titleId` PLUS `requestId`, and this handler
  // accepted the single key `titleId` and nothing else — so every real call
  // failed `invalid-argument`, which the client does not treat as a fallback
  // condition and therefore rethrows. Server-side title selection was dead in
  // production until `requestId` was accepted here.
  test("accepts the requestId the client actually sends", async () => {
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", {});
    repository.seedProgress("user-1", {
      verifiedUnlockedTitleIds: ["messages_1"],
      verifiedUnlockedTitleTimestamps: { messages_1: NOW },
    });
    const result = await handlerFor(repository)({
      auth: { uid: "user-1" },
      data: { titleId: "messages_1", requestId: "abcd1234efgh" },
    });
    assert.equal(result.selectedTitleId, "messages_1");
  });

  test("requestId stays optional and every other key is still refused", async () => {
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", {});
    repository.seedProgress("user-1", {
      verifiedUnlockedTitleIds: ["messages_1"],
      verifiedUnlockedTitleTimestamps: { messages_1: NOW },
    });
    const handler = handlerFor(repository);

    const withoutRequestId = await handler({
      auth: { uid: "user-1" },
      data: { titleId: "messages_1" },
    });
    assert.equal(withoutRequestId.selectedTitleId, "messages_1");

    for (const data of [
      { titleId: "messages_1", uid: "victim" },
      { titleId: "messages_1", requestId: "ok-value", beneficiaryId: "victim" },
      { requestId: "ok-value" },
      { titleId: "messages_1", requestId: "" },
      { titleId: "messages_1", requestId: 12345 },
      { titleId: "messages_1", requestId: "x".repeat(65) },
    ]) {
      await assert.rejects(
        handler({ auth: { uid: "user-1" }, data }),
        (error) => error.code === "invalid-argument",
        `expected ${JSON.stringify(data)} to be refused`,
      );
    }
  });

  test("forged legacy titles confer no selection right", async () => {
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", {
      unlockedTitleIds: ["messages_1"],
      selectedTitleId: "messages_1",
    });
    await assert.rejects(
      handlerFor(repository)({
        auth: { uid: "user-1" },
        data: { titleId: "messages_1" },
      }),
      (error) => error.code === "failed-precondition",
    );
  });

  test("selects only a verified title for the exact opaque Auth UID", async () => {
    const uid = " user-1 ";
    const repository = new InMemoryAchievementRepository();
    repository.seedUser(uid, {});
    repository.seedUser("user-1", {});
    repository.seedProgress(uid, {
      verifiedUnlockedTitleIds: ["messages_1"],
      verifiedUnlockedTitleTimestamps: { messages_1: NOW },
    });
    const result = await handlerFor(repository)({
      auth: { uid },
      data: { titleId: "messages_1" },
    });
    assert.equal(result.outcome, "updated");
    assert.equal(repository.progressFor(uid).selectedTitleId, "messages_1");
    assert.equal(repository.progressFor("user-1"), undefined);
  });

  test("banned accounts cannot select even verified titles", async () => {
    const repository = new InMemoryAchievementRepository();
    repository.seedUser("user-1", { banned: true });
    repository.seedProgress("user-1", {
      verifiedUnlockedTitleIds: ["messages_1"],
    });
    await assert.rejects(
      handlerFor(repository)({
        auth: { uid: "user-1" },
        data: { titleId: "messages_1" },
      }),
      (error) => error.code === "permission-denied",
    );
  });

  test("the callable module exposes no public increment endpoint", () => {
    const exported = Object.keys(require("../achievements/callables"));
    assert.equal(exported.some((name) => /increment|progress|unlock/iu.test(name)), false);
  });
});

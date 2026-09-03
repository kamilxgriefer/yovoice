const assert = require("node:assert/strict");
const { test } = require("node:test");

const { createReelStorageAdapter } = require("../reels/storage");

test("storage adapter revokes durable tokens with generation precondition", async () => {
  const calls = [];
  const file = {
    async setMetadata(value, options) {
      calls.push({ value, options });
      return [{ generation: "7", metadata: value.metadata }];
    },
  };
  const adapter = createReelStorageAdapter({ file: () => file });
  await adapter.revokeDownloadTokens("reels/u/r/media.jpg", {
    generation: "7",
    metadata: {
      ownerId: "u",
      reelId: "r",
      assetKind: "media",
      firebaseStorageDownloadTokens: "durable-token",
    },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].value.metadata.firebaseStorageDownloadTokens, null);
  assert.deepEqual(calls[0].options, { ifGenerationMatch: "7" });
  assert.equal(calls[0].value.metadata.ownerId, "u");
});

test("published Reel cleanup deletes only the recorded object generation", async () => {
  const calls = [];
  const adapter = createReelStorageAdapter({
    file: (path) => ({
      async delete(options) {
        calls.push({ path, options });
      },
    }),
  });

  await adapter.deleteObject("reels/u/r/media.jpg", { generation: "7001" });
  assert.deepEqual(calls, [{
    path: "reels/u/r/media.jpg",
    options: { ignoreNotFound: true, ifGenerationMatch: "7001" },
  }]);
});

test("cleanup fails closed for malformed or stale generations", async () => {
  let deletes = 0;
  const stale = Object.assign(new Error("conditionNotMet"), { code: 412 });
  const adapter = createReelStorageAdapter({
    file: () => ({
      async delete() {
        deletes += 1;
        throw stale;
      },
    }),
  });

  await assert.rejects(
    adapter.deleteObject("reels/u/r/media.jpg", { generation: "not-a-generation" }),
    (error) => error.code === "data-loss",
  );
  assert.equal(deletes, 0);

  await assert.rejects(
    adapter.deleteObject("reels/u/r/media.jpg", { generation: "7001" }),
    (error) => error === stale,
  );
  assert.equal(deletes, 1, "a 412 must not be converted into cleanup success");
});

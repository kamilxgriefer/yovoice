const assert = require("node:assert/strict");
const { test } = require("node:test");

const { createBucketStorageAdapter } = require("../moments/integrity");

test("private-media adapter revokes tokens with an object-generation CAS", async () => {
  const calls = [];
  const file = {
    async setMetadata(metadata, options) {
      calls.push({ metadata, options });
      return [{ generation: "101", metadata: metadata.metadata }];
    },
  };
  const adapter = createBucketStorageAdapter({
    name: "test-bucket",
    file(path) {
      assert.equal(path, "voice_moments/u/m.m4a");
      return file;
    },
  });
  const updated = await adapter.revokeDownloadTokens("voice_moments/u/m.m4a", {
    generation: "101",
    metadata: {
      authorId: "u",
      momentId: "m",
      firebaseStorageDownloadTokens: "permanent-token",
    },
  });
  assert.equal(updated.generation, "101");
  assert.deepEqual(calls, [
    {
      metadata: {
        metadata: {
          authorId: "u",
          momentId: "m",
          firebaseStorageDownloadTokens: null,
        },
      },
      options: { ifGenerationMatch: "101" },
    },
  ]);
});

test("private-media adapter signs a generation-bound V4 read grant", async () => {
  const calls = [];
  const file = {
    async getSignedUrl(options) {
      calls.push(options);
      return ["https://storage.googleapis.com/test-bucket/object?signed=yes"];
    },
  };
  const adapter = createBucketStorageAdapter({
    name: "test-bucket",
    file() {
      return file;
    },
  });
  const expiresAtMs = 1_900_000_000_000;
  const url = await adapter.getSignedReadUrl("voice_moments/u/m.m4a", {
    expiresAtMs,
    generation: "202",
  });
  assert.equal(
    url,
    "https://storage.googleapis.com/test-bucket/object?signed=yes",
  );
  assert.deepEqual(calls, [
    {
      version: "v4",
      action: "read",
      expires: expiresAtMs,
      queryParams: { generation: "202" },
    },
  ]);
});

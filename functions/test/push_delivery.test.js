const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  FCM_MULTICAST_LIMIT,
  FIRESTORE_CLEANUP_BATCH_SIZE,
  MAX_ACTIVE_FCM_TOKENS_PER_USER,
  MAX_FCM_TOKEN_DOCUMENT_READS,
  chunks,
  planTokenDocuments,
  sendMulticastInChunks,
} = require("../notifications/push_delivery");

describe("bounded FCM token registry", () => {
  test("only the newest bounded device set is delivered and overflow is pruned",
    () => {
      const docs = Array.from(
        { length: MAX_FCM_TOKEN_DOCUMENT_READS + 50 },
        (_, index) => ({
          id: `token-${index}`,
          ref: { path: `users/u/fcmTokens/token-${index}` },
        }),
      );
      const plan = planTokenDocuments(docs);

      assert.equal(plan.tokens.length, MAX_ACTIVE_FCM_TOKENS_PER_USER);
      assert.deepEqual(
        plan.tokens,
        docs.slice(0, MAX_ACTIVE_FCM_TOKENS_PER_USER).map((doc) => doc.id),
      );
      assert.equal(
        plan.overflowReferences.length,
        MAX_FCM_TOKEN_DOCUMENT_READS - MAX_ACTIVE_FCM_TOKENS_PER_USER,
      );
      assert.ok(
        plan.tokens.every((token) => !token.endsWith("500")),
        "documents beyond the bounded read cannot enter delivery",
      );
    });

  test("cleanup batching stays below Firestore's 500-write hard limit", () => {
    const batches = chunks(
      Array.from({ length: 1001 }, (_, index) => index),
      FIRESTORE_CLEANUP_BATCH_SIZE,
    );
    assert.deepEqual(batches.map((batch) => batch.length), [450, 450, 101]);
    assert.ok(batches.every((batch) => batch.length < 500));
  });
});

describe("FCM multicast chunking", () => {
  test("1001 tokens are sent as 500, 500 and 1", async () => {
    const calls = [];
    const tokens = Array.from({ length: 1001 }, (_, index) => `t-${index}`);
    const messaging = {
      async sendEachForMulticast(message) {
        calls.push(message.tokens);
        return {
          responses: message.tokens.map(() => ({ success: true })),
        };
      },
    };

    const outcome = await sendMulticastInChunks({
      tokens,
      messaging,
      buildMessage: (tokenChunk) => ({ tokens: tokenChunk }),
    });

    assert.equal(FCM_MULTICAST_LIMIT, 500);
    assert.deepEqual(calls.map((call) => call.length), [500, 500, 1]);
    assert.equal(outcome.attempted, 1001);
    assert.deepEqual(outcome.staleTokens, []);
  });

  test("permanent token failures are identified without exposing tokens in errors",
    async () => {
      const messaging = {
        async sendEachForMulticast(message) {
          return {
            responses: message.tokens.map((token) => token === "stale"
              ? {
                  success: false,
                  error: { code: "messaging/registration-token-not-registered" },
                }
              : {
                  success: false,
                  error: { code: "messaging/internal-error", message: token },
                }),
          };
        },
      };

      const outcome = await sendMulticastInChunks({
        tokens: ["stale", "sensitive-token"],
        messaging,
        buildMessage: (tokens) => ({ tokens }),
      });

      assert.deepEqual(outcome.staleTokens, ["stale"]);
      assert.deepEqual(outcome.failures, [{ code: "messaging/internal-error" }]);
      assert.equal(JSON.stringify(outcome).includes("sensitive-token"), false);
    });

  test("a whole-batch transport failure does not skip later chunks", async () => {
    let calls = 0;
    const messaging = {
      async sendEachForMulticast(message) {
        calls += 1;
        if (calls === 1) {
          throw Object.assign(new Error("transport down"), {
            code: "messaging/server-unavailable",
          });
        }
        return { responses: message.tokens.map(() => ({ success: true })) };
      },
    };

    const outcome = await sendMulticastInChunks({
      tokens: Array.from({ length: 501 }, (_, index) => `token-${index}`),
      messaging,
      buildMessage: (tokens) => ({ tokens }),
    });

    assert.equal(calls, 2);
    assert.deepEqual(outcome.batchErrors, [{
      code: "messaging/server-unavailable",
      tokenCount: 500,
    }]);
    assert.equal(outcome.attempted, 501);
  });
});

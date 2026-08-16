const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const { getApps, initializeApp } = require("firebase-admin/app");
const { Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: "premium-expiry-test" });

const {
  PREMIUM_EXPIRY_PAGE_SIZE,
  expirePremiumIdentityPages,
} = require("../premium/entitlements");

function fixture(count) {
  return Array.from({ length: count }, (_, index) => ({
    id: `premium-${index}`,
    ref: { path: `entitlements/premium-${index}` },
  }));
}

describe("Premium expiry pagination", () => {
  test("451 expiries are committed as bounded 200/200/51 pages", async () => {
    const pending = fixture(451);
    const queriedLimits = [];
    const writeCounts = [];

    const outcome = await expirePremiumIdentityPages({
      now: Timestamp.fromMillis(10_000),
      fetchPage: async ({ limit }) => {
        queriedLimits.push(limit);
        return pending.slice(0, limit);
      },
      commitPage: async (documents) => {
        writeCounts.push(documents.length * 2);
        pending.splice(0, documents.length);
        return documents.length;
      },
    });

    assert.deepEqual(outcome, {
      expiredCount: 451,
      pages: 3,
      truncated: false,
    });
    assert.deepEqual(queriedLimits, [200, 200, 200]);
    assert.deepEqual(writeCounts, [400, 400, 102]);
    assert.ok(writeCounts.every((writes) => writes < 500));
    assert.equal(pending.length, 0);
  });

  test("the invocation cap is explicit and reports remaining work", async () => {
    const pending = fixture(5);
    const outcome = await expirePremiumIdentityPages({
      now: Timestamp.fromMillis(10_000),
      pageSize: 2,
      maxPages: 2,
      fetchPage: async ({ limit }) => pending.slice(0, limit),
      commitPage: async (documents) => {
        pending.splice(0, documents.length);
        return documents.length;
      },
    });

    assert.deepEqual(outcome, {
      expiredCount: 4,
      pages: 2,
      truncated: true,
    });
    assert.equal(pending.length, 1);
  });

  test("page size cannot exceed the two-writes-per-entitlement budget", async () => {
    await assert.rejects(
      () => expirePremiumIdentityPages({
        pageSize: PREMIUM_EXPIRY_PAGE_SIZE + 1,
        fetchPage: async () => [],
      }),
      /pageSize must be between/,
    );
  });
});

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

test("notification delivery ledger TTL is deployable from Firebase config", () => {
  const indexesPath = path.resolve(__dirname, "../../firestore.indexes.json");
  const config = JSON.parse(readFileSync(indexesPath, "utf8"));
  const overrides = config.fieldOverrides.filter((override) =>
    override.collectionGroup === "notificationDeliveryEvents" &&
    override.fieldPath === "expiresAt",
  );

  assert.equal(overrides.length, 1);
  assert.equal(overrides[0].ttl, true);
  // A fieldOverride replaces automatic indexing. The ledger is point-read by
  // its digest and never queried by expiresAt, so explicitly keeping no index
  // avoids a write-cost regression while TTL remains managed and deployable.
  assert.deepEqual(overrides[0].indexes, []);
});

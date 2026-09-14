const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

test("server deletion can query every user follow mirror", () => {
  const indexesPath = path.resolve(__dirname, "../../firestore.indexes.json");
  const config = JSON.parse(readFileSync(indexesPath, "utf8"));
  const overrides = config.fieldOverrides.filter((override) =>
    override.collectionGroup === "serverFollows" &&
    override.fieldPath === "serverId",
  );

  assert.equal(overrides.length, 1);
  assert.ok(overrides[0].indexes.some((index) =>
    index.order === "ASCENDING" &&
    index.queryScope === "COLLECTION_GROUP",
  ));
});

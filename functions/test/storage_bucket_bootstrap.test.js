const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const READ_BUCKET = [
  "require('./index.js');",
  "const { getApps } = require('firebase-admin/app');",
  "process.stdout.write(String(getApps()[0].options.storageBucket ?? ''));",
].join(" ");

function importedBucket({ override } = {}) {
  const env = { ...process.env };
  delete env.FIREBASE_STORAGE_BUCKET;
  delete env.STORAGE_BUCKET;
  delete env.GCLOUD_STORAGE_BUCKET;
  env.GCLOUD_PROJECT = "yovoice-bootstrap-test";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-bootstrap-test",
    storageBucket: "yovoice-bootstrap-test.firebasestorage.app",
  });
  if (override) env.FIREBASE_STORAGE_BUCKET = override;
  return execFileSync(process.execPath, ["-e", READ_BUCKET], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    env,
  });
}

test("Functions bootstrap preserves the FIREBASE_CONFIG Storage bucket", () => {
  assert.equal(
    importedBucket(),
    "yovoice-bootstrap-test.firebasestorage.app",
  );
});

test("an explicit Storage bucket override still wins", () => {
  assert.equal(
    importedBucket({ override: "explicit-bucket.firebasestorage.app" }),
    "explicit-bucket.firebasestorage.app",
  );
});

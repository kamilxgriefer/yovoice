const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
process.env.LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY ?? "devkey123";
process.env.LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET ??
  "devsecret123devsecret123devsecret123";
process.env.LIVEKIT_URL = process.env.LIVEKIT_URL ??
  "wss://yovoice-3f7j9fb7.livekit.cloud";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const {
  acceptDirectCall,
  cancelDirectCall,
  createDirectCallToken,
  declineDirectCall,
  endDirectCall,
  startDirectCall,
} = require("../calls/direct_calls");
const { createLiveKitToken } = require("../livekit/token");

function minInstances(callable) {
  const configured = callable?.__endpoint?.minInstances;
  return Number.isSafeInteger(configured) ? configured : 0;
}

test("only latency-critical call setup endpoints keep one warm instance", () => {
  assert.equal(minInstances(createLiveKitToken), 1);
  assert.equal(minInstances(startDirectCall), 1);
  assert.equal(minInstances(createDirectCallToken), 1);

  for (const callable of [
    acceptDirectCall,
    declineDirectCall,
    cancelDirectCall,
    endDirectCall,
  ]) {
    assert.equal(minInstances(callable), 0);
  }
});

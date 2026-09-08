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
const {
  SELF_MUTE_CALLABLE_OPTIONS,
  deleteRoomSelf,
  endRoomVoiceSelf,
  leaveRoomSelf,
  moderateRoomParticipantSelf,
  removeRoomParticipantSelf,
  setOwnRoomParticipantMute,
  setRoomStatusSelf,
} = require("../rooms/participants");

function minInstances(callable) {
  const configured = callable?.__endpoint?.minInstances;
  return Number.isSafeInteger(configured) ? configured : 0;
}

function boundSecretNames(callable) {
  // firebase-functions v2 records `secrets` on the deploy manifest endpoint
  // as secretEnvironmentVariables; absent means nothing is mounted.
  return (callable?.__endpoint?.secretEnvironmentVariables ?? [])
    .map((secret) => secret.key);
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

test("self-mute is the only warm room-participant callable and mounts no LiveKit secrets", () => {
  // Unmute is server-first (ADR-149): the tap waits on this callable before
  // the microphone opens, so it keeps one warm instance. Its handler never
  // reaches the LiveKit control plane, so it binds no LiveKit secrets — a
  // future LiveKit call added there must bring its own options object rather
  // than silently reusing CALLABLE_OPTIONS.
  assert.equal(SELF_MUTE_CALLABLE_OPTIONS.minInstances, 1);
  assert.equal(SELF_MUTE_CALLABLE_OPTIONS.secrets, undefined);
  assert.equal(minInstances(setOwnRoomParticipantMute), 1);
  assert.deepEqual(boundSecretNames(setOwnRoomParticipantMute), []);
  assert.equal(
    setOwnRoomParticipantMute.__endpoint.secretEnvironmentVariables,
    undefined,
  );

  // Every other room-participant callable does call LiveKit and stays cold.
  for (const callable of [
    deleteRoomSelf,
    endRoomVoiceSelf,
    leaveRoomSelf,
    moderateRoomParticipantSelf,
    removeRoomParticipantSelf,
    setRoomStatusSelf,
  ]) {
    assert.equal(minInstances(callable), 0);
    assert.deepEqual(
      boundSecretNames(callable),
      ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"],
    );
  }
  assert.deepEqual(
    moderateRoomParticipantSelf.__endpoint.secretEnvironmentVariables,
    [{ key: "LIVEKIT_API_KEY" }, { key: "LIVEKIT_API_SECRET" }],
  );
});

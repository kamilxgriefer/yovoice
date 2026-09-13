"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { test } = require("node:test");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const INSPECT = [
  "const { declaredParams } = require('firebase-functions/params');",
  "const exported = require('./index.js');",
  "process.stdout.write(JSON.stringify({",
  "names: declaredParams.map((param) => param.name).sort(),",
  "exports: Object.keys(exported).sort(),",
  "}));",
].join(" ");
const INSPECT_PODCAST_SOURCE_ENABLE = [
  "require('firebase-admin/app').initializeApp();",
  "const { declaredParams } = require('firebase-functions/params');",
  "const { createServersV1Functions } = require('./servers/registration');",
  "const exported = createServersV1Functions({ enablePodcastRecording: true });",
  "process.stdout.write(JSON.stringify({",
  "names: declaredParams.map((param) => param.name).sort(),",
  "exports: Object.keys(exported).sort(),",
  "}));",
].join(" ");
const INSPECT_GIPHY_SOURCE_ENABLE = [
  "const { declaredParams } = require('firebase-functions/params');",
  "const { createGifFunctions } = require('./media/gif/catalog');",
  "const registrars = { onCall: (options, handler) => ({ options, handler }) };",
  "const exported = createGifFunctions({",
  "providerName: 'giphy', runtime: {}, registrars,",
  "});",
  "process.stdout.write(JSON.stringify({",
  "names: declaredParams.map((param) => param.name).sort(),",
  "exports: Object.keys(exported).sort(),",
  "}));",
].join(" ");

function discover(overrides = {}) {
  const env = { ...process.env };
  for (const name of [
    "GIF_PROVIDER",
    "STRIPE_BILLING_EXPORTS",
    "YOVOICE_SERVERS_V1",
    "YOVOICE_ENFORCE_SERVERS_APP_CHECK",
    "YOVOICE_PODCAST_RECORDING_ENABLED",
    "K_SERVICE",
    "FUNCTION_TARGET",
  ]) delete env[name];
  env.GCLOUD_PROJECT = "yovoice-optional-secret-test";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-optional-secret-test",
    storageBucket: "yovoice-optional-secret-test.firebasestorage.app",
  });
  Object.assign(env, overrides);
  return JSON.parse(execFileSync(process.execPath, ["-e", INSPECT], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    env,
    stdio: ["ignore", "pipe", "inherit"],
  }));
}

function discoverPodcastSourceEnable() {
  const env = { ...process.env };
  for (const name of ["K_SERVICE", "FUNCTION_TARGET"]) delete env[name];
  env.GCLOUD_PROJECT = "yovoice-optional-secret-test";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-optional-secret-test",
    storageBucket: "yovoice-optional-secret-test.firebasestorage.app",
  });
  return JSON.parse(execFileSync(
    process.execPath,
    ["-e", INSPECT_PODCAST_SOURCE_ENABLE],
    {
      cwd: FUNCTIONS_DIR,
      encoding: "utf8",
      env,
      stdio: ["ignore", "pipe", "inherit"],
    },
  ));
}

function discoverGiphySourceEnable() {
  const env = { ...process.env };
  for (const name of ["GIF_PROVIDER", "K_SERVICE", "FUNCTION_TARGET"]) {
    delete env[name];
  }
  return JSON.parse(execFileSync(
    process.execPath,
    ["-e", INSPECT_GIPHY_SOURCE_ENABLE],
    {
      cwd: FUNCTIONS_DIR,
      encoding: "utf8",
      env,
      stdio: ["ignore", "pipe", "inherit"],
    },
  ));
}

test("deploy discovery does not require optional secrets while their surfaces are off", () => {
  const result = discover({
    GIF_PROVIDER: "none",
    YOVOICE_SERVERS_V1: "enabled",
    YOVOICE_PODCAST_RECORDING_ENABLED: "false",
  });
  assert.ok(!result.names.includes("GIPHY_API_KEY"));
  assert.ok(!result.names.includes("PODCAST_EGRESS_GCP_CREDENTIALS"));
  assert.ok(result.names.includes("LIVEKIT_API_KEY"));
  assert.ok(result.exports.includes("getGifCatalog"));
  assert.ok(result.exports.includes("searchGifs"));
  assert.ok(result.exports.includes("reportGifAsset"));
  assert.ok(result.exports.includes("createServerV1"));
  assert.ok(!result.exports.includes("startServerPodcastRecordingV1"));
  assert.ok(!result.exports.includes("reconcileServerPodcastEgressSchedule"));
});

test("each optional secret appears only when its own surface is source-enabled", () => {
  // Firebase reads functions/.env after endpoint discovery. Even an injected
  // legacy value cannot change the production export map: the bundled catalog
  // is selected in source and therefore always deploys without GIPHY_API_KEY.
  const originals = discover({ GIF_PROVIDER: "giphy" });
  assert.ok(!originals.names.includes("GIPHY_API_KEY"));
  assert.ok(originals.exports.includes("searchGifs"));
  assert.ok(originals.exports.includes("reportGifAsset"));

  const gifs = discoverGiphySourceEnable();
  assert.ok(gifs.names.includes("GIPHY_API_KEY"));
  assert.ok(gifs.exports.includes("searchGifs"));

  // Podcast is deliberately source-controlled. This exercises deploy
  // discovery without an injected runtime and proves that only the explicit
  // source option constructs the service and declares its credential.
  const podcast = discoverPodcastSourceEnable();
  assert.ok(podcast.names.includes("PODCAST_EGRESS_GCP_CREDENTIALS"));
  assert.ok(podcast.exports.includes("startServerPodcastRecordingV1"));
  assert.ok(podcast.exports.includes("reconcileServerPodcastEgressSchedule"));
});

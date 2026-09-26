"use strict";

// The keep-warm pinger (ops/keep_warm.js, ADR-XXX, cost plan C3) replaces
// every minInstances warm instance with one five-minute schedule that sends
// an unauthenticated, empty callable request to twelve hot paths. Three
// properties make that safe, and each is proved here:
//   1. The ping carries nothing: no Authorization header, no App Check
//      header, `{"data":null}` as the body, to the real public URL.
//   2. A ping can never do work: every target, loaded from the REAL export
//      map and driven through the real callable wrapper over HTTP, answers
//      401 UNAUTHENTICATED with Firestore and Auth tripwired, so any read,
//      write or token check before the refusal would fail the test.
//   3. The pinger never throws and never logs above INFO, whatever the
//      targets answer, so it cannot fire the "Backend ERROR logs" alert
//      (severity >= ERROR) or fail its Scheduler job.

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { test } = require("node:test");

const {
  KEEP_WARM_LOG_MESSAGE,
  KEEP_WARM_PING_TIMEOUT_MS,
  KEEP_WARM_REQUEST_BODY,
  KEEP_WARM_TARGETS,
  KEEP_WARM_USER_AGENT,
  keepWarmCallableUrl,
  keepWarmHotPathsSchedule,
  pingKeepWarmTargets,
  resolveKeepWarmProjectId,
} = require("../ops/keep_warm");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
// No test in this process may reach a real backend: PRODUCTION_ENV below
// derives the real production URLs, so a default parameter that silently fell
// back to the global fetch would ping production. Every test injects its own
// fetch; this one only fails loudly.
globalThis.fetch = async (url) => {
  throw new Error(`keep_warm.test.js must not fetch ${url}`);
};
const PRODUCTION_ENV = Object.freeze({ GCLOUD_PROJECT: "yovoice-ec54a" });

const EXPECTED_TARGETS = Object.freeze([
  // Direct messages.
  "sendDirectMessage",
  "openDirectConversation",
  // Direct calls, including the answer (cold in production since ADR-197).
  "startDirectCall",
  "acceptDirectCall",
  "createDirectCallToken",
  // Servers voice join, then Servers text send.
  "startServerChannelSessionV1",
  "createServerChannelTokenV1",
  "sendClubMessage",
  // Reel publish.
  "reserveReelDraftV2",
  "finalizeReelDraftV2",
  // Both feeds.
  "getVoiceMomentsFeedV2",
  "listReelsV2",
]);

function recordingLog() {
  const entries = [];
  const record = (severity) => (message, fields) => {
    entries.push({ severity, message, fields });
  };
  return {
    entries,
    log: {
      debug: record("DEBUG"),
      info: record("INFO"),
      warn: record("WARNING"),
      error: record("ERROR"),
    },
  };
}

function response(status) {
  let cancelled = false;
  return {
    status,
    body: {
      cancel: async () => {
        cancelled = true;
      },
    },
    get cancelled() {
      return cancelled;
    },
  };
}

test("the target list is exactly the twelve hot paths of the cost plan", () => {
  assert.deepEqual([...KEEP_WARM_TARGETS], [...EXPECTED_TARGETS]);
  assert.ok(Object.isFrozen(KEEP_WARM_TARGETS));
  assert.equal(new Set(KEEP_WARM_TARGETS).size, KEEP_WARM_TARGETS.length);
  // The retired Rooms entry points are deliberately NOT pinged (cost plan C1).
  for (const retired of [
    "createLiveKitToken",
    "sendRoomMessage",
    "startRoomVoice",
    "setOwnRoomParticipantMute",
  ]) {
    assert.equal(KEEP_WARM_TARGETS.includes(retired), false, retired);
  }
});

test("the schedule is every five minutes, one small instance, no retries, never warm itself", () => {
  const endpoint = keepWarmHotPathsSchedule.__endpoint;
  assert.deepEqual(endpoint.region, ["europe-west1"]);
  assert.equal(endpoint.platform, "gcfv2");
  assert.equal(endpoint.scheduleTrigger.schedule, "every 5 minutes");
  assert.equal(endpoint.scheduleTrigger.timeZone, "UTC");
  assert.equal(endpoint.scheduleTrigger.retryConfig.retryCount, 0);
  assert.equal(endpoint.maxInstances, 1);
  assert.equal(endpoint.availableMemoryMb, 256);
  assert.equal(endpoint.timeoutSeconds, 60);
  // Unset options serialize as a reset marker (null in the deploy manifest),
  // which the CLI deploys as the platform default of 0.
  assert.equal(JSON.parse(JSON.stringify(endpoint)).minInstances, null);
  assert.equal(endpoint.secretEnvironmentVariables, undefined);
  // Every ping's own deadline fits well inside the function timeout.
  assert.ok(KEEP_WARM_PING_TIMEOUT_MS <= 15_000);
});

test("the URL is the public callable URL of this project and region", () => {
  assert.equal(resolveKeepWarmProjectId(PRODUCTION_ENV), "yovoice-ec54a");
  assert.equal(resolveKeepWarmProjectId({
    FIREBASE_CONFIG: JSON.stringify({ projectId: "yovoice-ec54a" }),
  }), "yovoice-ec54a");
  assert.equal(resolveKeepWarmProjectId({
    GOOGLE_CLOUD_PROJECT: "yovoice-ec54a",
  }), "yovoice-ec54a");
  assert.equal(resolveKeepWarmProjectId({}), null);
  assert.equal(resolveKeepWarmProjectId({ FIREBASE_CONFIG: "{not json" }), null);
  // Nothing that could redirect the URL to another host is accepted.
  assert.equal(resolveKeepWarmProjectId({ GCLOUD_PROJECT: "evil.example/x" }), null);
  assert.equal(resolveKeepWarmProjectId({ GCLOUD_PROJECT: "a@b" }), null);
  assert.equal(
    keepWarmCallableUrl("yovoice-ec54a", "sendDirectMessage"),
    "https://europe-west1-yovoice-ec54a.cloudfunctions.net/sendDirectMessage",
  );
});

test("each ping is one parallel POST with no Authorization, no App Check and no data", async () => {
  const calls = [];
  const pending = [];
  const fetchImpl = (url, init) => {
    calls.push({ url, init });
    return new Promise((resolve) => pending.push(() => resolve(response(401))));
  };
  const { entries, log } = recordingLog();
  const run = pingKeepWarmTargets({ env: PRODUCTION_ENV, fetchImpl, log });

  // All twelve requests are in flight before any of them has answered.
  assert.equal(calls.length, EXPECTED_TARGETS.length);
  for (const release of pending) release();
  const results = await run;

  assert.deepEqual(
    calls.map(({ url }) => url),
    EXPECTED_TARGETS.map((name) =>
      `https://europe-west1-yovoice-ec54a.cloudfunctions.net/${name}`),
  );
  for (const { init } of calls) {
    assert.equal(init.method, "POST");
    assert.deepEqual(Object.keys(init.headers).sort(), ["content-type", "user-agent"]);
    assert.equal(init.headers["content-type"], "application/json");
    assert.equal(init.headers["user-agent"], KEEP_WARM_USER_AGENT);
    for (const header of Object.keys(init.headers)) {
      assert.notEqual(header.toLowerCase(), "authorization");
      assert.notEqual(header.toLowerCase(), "x-firebase-appcheck");
    }
    assert.equal(init.body, KEEP_WARM_REQUEST_BODY);
    assert.deepEqual(JSON.parse(init.body), { data: null });
    assert.equal(init.redirect, "manual");
    assert.ok(init.signal instanceof AbortSignal);
  }
  assert.deepEqual(results.map(({ target, status }) => [target, status]),
    EXPECTED_TARGETS.map((name) => [name, 401]));
  assert.equal(entries.length, EXPECTED_TARGETS.length);
  for (const entry of entries) {
    assert.equal(entry.severity, "INFO");
    assert.equal(entry.message, KEEP_WARM_LOG_MESSAGE);
    assert.deepEqual(Object.keys(entry.fields).sort(), ["ms", "status", "target"]);
    assert.ok(Number.isSafeInteger(entry.fields.ms) && entry.fields.ms >= 0);
  }
});

test("timeouts, non-401 answers and network failures are logged at INFO and never thrown", async () => {
  const behaviour = {
    sendDirectMessage: () => Promise.resolve(response(401)),
    openDirectConversation: () => Promise.resolve(response(200)),
    startDirectCall: () => Promise.resolve(response(404)),
    acceptDirectCall: () => Promise.resolve(response(500)),
    createDirectCallToken: () => Promise.resolve(response(503)),
    startServerChannelSessionV1: () => Promise.resolve(response(302)),
    createServerChannelTokenV1: (init) => new Promise((_, reject) => {
      // Never answers: only the pinger's own AbortSignal.timeout ends it.
      init.signal.addEventListener("abort", () => reject(init.signal.reason));
    }),
    sendClubMessage: () => Promise.reject(new TypeError("fetch failed")),
    reserveReelDraftV2: () => {
      throw new Error("synchronous fetch failure");
    },
    finalizeReelDraftV2: () => Promise.resolve({}),
    getVoiceMomentsFeedV2: () => Promise.resolve(null),
    listReelsV2: () => Promise.reject(Object.assign(new Error("aborted"), {
      name: "AbortError",
    })),
  };
  const fetchImpl = (url, init) =>
    behaviour[url.slice(url.lastIndexOf("/") + 1)](init);
  const { entries, log } = recordingLog();

  const results = await pingKeepWarmTargets({
    env: PRODUCTION_ENV,
    fetchImpl,
    log,
    timeoutMs: 40,
  });

  assert.deepEqual(
    Object.fromEntries(results.map(({ target, status }) => [target, status])),
    {
      sendDirectMessage: 401,
      openDirectConversation: 200,
      startDirectCall: 404,
      acceptDirectCall: 500,
      createDirectCallToken: 503,
      startServerChannelSessionV1: 302,
      createServerChannelTokenV1: "timeout",
      sendClubMessage: "network-error",
      reserveReelDraftV2: "network-error",
      finalizeReelDraftV2: "invalid-response",
      getVoiceMomentsFeedV2: "invalid-response",
      listReelsV2: "timeout",
    },
  );
  const timedOut = results.find(({ target }) =>
    target === "createServerChannelTokenV1");
  assert.ok(timedOut.ms >= 30, `timeout measured ${timedOut.ms} ms`);
  assert.equal(entries.length, EXPECTED_TARGETS.length);
  assert.deepEqual([...new Set(entries.map(({ severity }) => severity))], ["INFO"]);
});

test("a throwing logger or a missing project never fails the run", async () => {
  const throwingLog = {
    info: () => {
      throw new Error("logging backend down");
    },
    warn: () => assert.fail("never warns"),
    error: () => assert.fail("never errors"),
  };
  const results = await pingKeepWarmTargets({
    env: PRODUCTION_ENV,
    fetchImpl: async () => response(401),
    log: throwingLog,
  });
  assert.equal(results.length, EXPECTED_TARGETS.length);

  for (const env of [{}, { FUNCTIONS_EMULATOR: "true", ...PRODUCTION_ENV }]) {
    const { entries, log } = recordingLog();
    let fetched = 0;
    const skipped = await pingKeepWarmTargets({
      env,
      fetchImpl: async () => {
        fetched += 1;
        return response(401);
      },
      log,
    });
    assert.deepEqual(skipped, []);
    assert.equal(fetched, 0);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].severity, "INFO");
    assert.equal(entries[0].message, "keep-warm skipped");
  }

  // A fetch that is not a function (a runtime without global fetch).
  const { entries, log } = recordingLog();
  assert.deepEqual(
    await pingKeepWarmTargets({ env: PRODUCTION_ENV, fetchImpl: null, log }),
    [],
  );
  assert.equal(entries[0].severity, "INFO");
});

test("the scheduled handler completes without throwing when every ping fails", async () => {
  // run() is the raw handler the Scheduler invocation awaits; a throw there
  // is what the scheduler wrapper would error-log and answer with a 500.
  const originalFetch = globalThis.fetch;
  const originalProject = process.env.GCLOUD_PROJECT;
  const originalEmulator = process.env.FUNCTIONS_EMULATOR;
  const originalWrite = process.stdout.write;
  const lines = [];
  globalThis.fetch = async () => {
    throw new TypeError("fetch failed");
  };
  process.env.GCLOUD_PROJECT = "yovoice-ec54a";
  delete process.env.FUNCTIONS_EMULATOR;
  process.stdout.write = (chunk, ...rest) => {
    const text = String(chunk);
    if (text.includes("keep-warm")) {
      lines.push(text);
      return true;
    }
    return originalWrite.call(process.stdout, chunk, ...rest);
  };
  try {
    await keepWarmHotPathsSchedule.run({ jobName: "test" });
  } finally {
    process.stdout.write = originalWrite;
    globalThis.fetch = originalFetch;
    if (originalProject === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = originalProject;
    if (originalEmulator !== undefined) {
      process.env.FUNCTIONS_EMULATOR = originalEmulator;
    }
  }
  // The real firebase-functions logger wrote one INFO line per target.
  const entries = lines.map((line) => JSON.parse(line));
  assert.equal(entries.length, EXPECTED_TARGETS.length);
  for (const entry of entries) {
    assert.equal(entry.severity, "INFO");
    assert.equal(entry.message, KEEP_WARM_LOG_MESSAGE);
    assert.equal(entry.status, "network-error");
  }
});

// Loads the REAL export map in a child process, tripwires every Firestore and
// Auth entry point, serves each exported callable over a local HTTP server
// through the real firebase-functions callable wrapper, and runs the real
// pinger against it. The emulator hosts point at a closed port, so even a
// bypassed tripwire could not reach a real database: it would time out and
// fail the 401 assertion instead.
const INTEGRATION = String.raw`
const http = require("node:http");
const exported = require("./index.js");
const admin = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { KEEP_WARM_TARGETS, pingKeepWarmTargets } = require("./ops/keep_warm");

const touched = [];
// Built before anything is armed, like a module-level reference would be.
const preBuiltReference = admin.getFirestore().doc("keepWarm/probe");
function tripwire(prototype, label, methods) {
  for (const method of methods) {
    const descriptor = Object.getOwnPropertyDescriptor(prototype, method);
    if (!descriptor || typeof descriptor.value !== "function") continue;
    prototype[method] = function tripped() {
      touched.push(label + "." + method);
      throw new Error("tripwire: " + label + "." + method);
    };
  }
}
// AggregateQuery is a type-only export; take its prototype from an instance
// built before anything is armed.
tripwire(
  Object.getPrototypeOf(admin.getFirestore().collection("keepWarm").count()),
  "aggregate",
  ["get"],
);
tripwire(admin.Firestore.prototype, "firestore", [
  "collection", "collectionGroup", "doc", "getAll", "runTransaction",
  "batch", "bulkWriter", "listCollections", "recursiveDelete", "bundle",
]);
tripwire(admin.DocumentReference.prototype, "document", [
  "get", "set", "update", "create", "delete", "listCollections", "onSnapshot",
]);
tripwire(admin.CollectionReference.prototype, "collection", [
  "add", "listDocuments",
]);
tripwire(admin.Query.prototype, "query", ["get", "stream", "onSnapshot"]);
tripwire(admin.WriteBatch.prototype, "batch", ["commit"]);
tripwire(admin.Transaction.prototype, "transaction", ["get", "getAll"]);
for (let proto = Object.getPrototypeOf(getAuth());
  proto && proto !== Object.prototype;
  proto = Object.getPrototypeOf(proto)) {
  tripwire(proto, "auth", Object.getOwnPropertyNames(proto)
    .filter((name) => name !== "constructor"));
}

const severities = [];
const unstructured = [];
const pingLines = [];
const originalOut = process.stdout.write.bind(process.stdout);
const capture = (chunk) => {
  for (const line of String(chunk).split("\n")) {
    if (!line.trim()) continue;
    try {
      const entry = JSON.parse(line);
      if (entry.message === "keep-warm ping") pingLines.push(entry);
      else if (typeof entry.severity === "string") severities.push(entry.severity);
      else unstructured.push(line.slice(0, 200));
    } catch (_) {
      unstructured.push(line.slice(0, 200));
    }
  }
  return true;
};
process.stdout.write = capture;
process.stderr.write = capture;

const seen = {};
const server = http.createServer((req, res) => {
  const name = decodeURIComponent(req.url.slice(1));
  const chunks = [];
  req.on("data", (chunk) => chunks.push(chunk));
  req.on("end", async () => {
    const raw = Buffer.concat(chunks).toString("utf8");
    seen[name] = {
      method: req.method,
      authorization: req.headers.authorization ?? null,
      appCheck: req.headers["x-firebase-appcheck"] ?? null,
      userAgent: req.headers["user-agent"] ?? null,
      body: raw,
      answer: null,
      threw: false,
    };
    const callable = exported[name];
    if (typeof callable !== "function") {
      res.statusCode = 404;
      res.end();
      return;
    }
    req.body = JSON.parse(raw);
    req.header = req.get = (key) => req.headers[String(key).toLowerCase()];
    res.status = (code) => {
      res.statusCode = code;
      return res;
    };
    res.send = (body) => {
      seen[name].answer = body?.error?.status ?? null;
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify(body));
      return res;
    };
    try {
      await callable(req, res);
    } catch (_) {
      seen[name].threw = true;
      if (!res.writableEnded) {
        res.statusCode = 599;
        res.end();
      }
    }
  });
});

server.listen(0, "127.0.0.1", async () => {
  const { port } = server.address();
  const results = await pingKeepWarmTargets({
    env: {},
    urlFor: (name) => "http://127.0.0.1:" + port + "/" + name,
    timeoutMs: 20000,
  });
  server.close();
  const touchedByPings = [...touched];
  // Negative control: the tripwires do fire, for a pre-built reference and
  // for Auth, so an empty list above is evidence rather than a dead probe.
  for (const probe of [
    () => preBuiltReference.get(),
    () => getAuth().getUser("keep-warm-probe"),
  ]) {
    try {
      await probe();
    } catch (_) {
      // Expected: the tripwire throws.
    }
  }
  originalOut(JSON.stringify({
    targets: KEEP_WARM_TARGETS,
    results,
    seen,
    touched: touchedByPings,
    probeTouched: touched.slice(touchedByPings.length),
    severities,
    unstructured,
    pingLines,
  }), () => process.exit(0));
});
`;

test("every target refuses the real ping with 401 before any Firestore or Auth access", () => {
  const env = { ...process.env };
  for (const name of [
    "K_SERVICE",
    "FUNCTION_TARGET",
    "STRIPE_BILLING_EXPORTS",
    "GIF_PROVIDER",
    "YOVOICE_SERVERS_V1",
    "YOVOICE_PODCAST_RECORDING_ENABLED",
    "FIREBASE_STORAGE_BUCKET",
    "STORAGE_BUCKET",
    "GCLOUD_STORAGE_BUCKET",
    "FUNCTIONS_EMULATOR",
  ]) delete env[name];
  env.GCLOUD_PROJECT = "yovoice-keep-warm-test";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-keep-warm-test",
    storageBucket: "yovoice-keep-warm-test.firebasestorage.app",
  });
  // A closed port: nothing in this child can reach a real backend.
  env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:9";
  env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9";
  env.LIVEKIT_API_KEY = "devkey123";
  env.LIVEKIT_API_SECRET = "devsecret123devsecret123devsecret123";
  env.LIVEKIT_URL = "wss://keep-warm.invalid";

  const outcome = JSON.parse(execFileSync(process.execPath, ["-e", INTEGRATION], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    env,
    stdio: ["ignore", "pipe", "inherit"],
    timeout: 120_000,
  }));

  assert.deepEqual(outcome.targets, [...EXPECTED_TARGETS]);
  // The tripwires work (negative control)...
  assert.deepEqual(outcome.probeTouched, ["document.get", "auth.getUser"]);
  // ...and no handler constructed a reference, read, wrote or checked a token.
  assert.deepEqual(outcome.touched, []);
  for (const name of EXPECTED_TARGETS) {
    const request = outcome.seen[name];
    assert.ok(request, `${name} was not pinged`);
    assert.equal(request.method, "POST", name);
    assert.equal(request.authorization, null, name);
    assert.equal(request.appCheck, null, name);
    assert.equal(request.userAgent, KEEP_WARM_USER_AGENT, name);
    assert.equal(request.body, KEEP_WARM_REQUEST_BODY, name);
    assert.equal(request.threw, false, name);
    assert.equal(request.answer, "UNAUTHENTICATED", name);
  }
  assert.deepEqual(
    outcome.results.map(({ target, status }) => [target, status]),
    EXPECTED_TARGETS.map((name) => [name, 401]),
  );
  // Neither a target nor the wrapper logged at WARNING or above: the 401s
  // cannot reach the "Backend ERROR logs" alert, and a 401 is a 4xx, which
  // the 5xx request-count alert does not count.
  for (const severity of outcome.severities) {
    assert.ok(
      ["DEBUG", "INFO"].includes(severity),
      `unexpected ${severity} log; unstructured: ${JSON.stringify(outcome.unstructured)}`,
    );
  }
  // The pinger's own lines went through the real logger at INFO.
  assert.equal(outcome.pingLines.length, EXPECTED_TARGETS.length);
  for (const line of outcome.pingLines) {
    assert.equal(line.severity, "INFO");
    assert.equal(line.status, 401);
  }
});

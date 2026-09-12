// Independent QA regressions for slice S4 (Servers V1 registration and durable
// dispatch behind YOVOICE_SERVERS_V1). Written without reusing the author's
// helpers; every expectation below comes from docs/Servers.md "Callable
// contract", the Stage B binding convention and the dispatcher's own stated
// invariants ("reads only", "never completes uncertain work", "only transient
// failures redeliver"). Emulator cases use a fresh project id per test.

const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { randomBytes, randomUUID } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

const { HttpsError } = require("firebase-functions/v2/https");
const {
  DISPATCHER_EXPORTS, OUTBOX_COLLECTION, SERVER_CALLABLE_METHODS, SERVERS_V1_EXPORT_NAMES, SWEEP_EXPORTS,
  authBoundRequest, createServersV1Functions, createServersV1Runtime, describeOutboxJob, isTransientFailure,
} = require("../servers/registration");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const DOCS_SERVERS = path.resolve(FUNCTIONS_DIR, "..", "docs", "Servers.md");
const CALLABLES = Object.keys(SERVER_CALLABLE_METHODS);
const TRIGGER = "onServerControlOutboxCreated";
const SCHEDULE = "processPendingServerControlOutboxSchedule";
const NOW = 1_900_000_000_000;
const GATE_MESSAGE = "YOVOICE_SERVERS_V1 must be exactly enabled or disabled.";
const APP_CHECK_MESSAGE = "YOVOICE_ENFORCE_SERVERS_APP_CHECK must be exactly true or false.";
const HEX64 = () => randomBytes(32).toString("hex");

/*
|--------------------------------------------------------------------------
| Child-process cold starts (one per gate value, cached)
|--------------------------------------------------------------------------
*/

const INSPECT = [
  "const exported = require('./index.js');",
  "const root = process.cwd() + '/servers/';",
  "const endpoints = {};",
  "for (const name of Object.keys(exported)) {",
  "  const fn = exported[name]; let endpoint = null;",
  "  try { endpoint = JSON.parse(JSON.stringify(fn && fn.__endpoint ? fn.__endpoint : null)); } catch (e) { endpoint = 'unserializable'; }",
  "  endpoints[name] = { type: typeof fn, length: typeof fn === 'function' ? fn.length : null, endpoint };",
  "}",
  "const cache = Object.keys(require.cache);",
  "process.stdout.write(JSON.stringify({",
  "  exportNames: Object.keys(exported).sort(),",
  "  registrationCached: cache.includes(root + 'registration.js'),",
  "  serversModules: cache.filter((k) => k.startsWith(root)).map((k) => k.slice(root.length)).sort(),",
  "  endpoints,",
  "}));",
].join("\n");

function childEnvironment(overrides) {
  const env = { ...process.env };
  for (const name of [
    "STRIPE_BILLING_EXPORTS", "GIF_PROVIDER", "YOVOICE_SERVERS_V1", "YOVOICE_ENFORCE_SERVERS_APP_CHECK",
    "K_SERVICE", "FUNCTION_TARGET", "FIREBASE_STORAGE_BUCKET", "STORAGE_BUCKET", "GCLOUD_STORAGE_BUCKET",
  ]) delete env[name];
  env.GCLOUD_PROJECT = "yovoice-independent-qa";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-independent-qa", storageBucket: "yovoice-independent-qa.firebasestorage.app",
  });
  for (const [name, value] of Object.entries(overrides)) if (value !== undefined) env[name] = value;
  return env;
}

const coldStarts = new Map();
function coldStart(overrides) {
  const key = JSON.stringify(overrides);
  if (!coldStarts.has(key)) {
    const child = spawnSync(process.execPath, ["-e", INSPECT], {
      cwd: FUNCTIONS_DIR, encoding: "utf8", env: childEnvironment(overrides), maxBuffer: 64 * 1024 * 1024,
    });
    let inspection = null;
    if (child.status === 0) inspection = JSON.parse(child.stdout);
    coldStarts.set(key, { status: child.status, stderr: child.stderr, inspection });
  }
  return coldStarts.get(key);
}

function docsCallableNames() {
  const lines = fs.readFileSync(DOCS_SERVERS, "utf8").split("\n");
  const start = lines.findIndex((line) => /^#{1,6} .*Callable contract/u.test(line));
  assert.ok(start >= 0, "docs/Servers.md must carry a Callable contract heading");
  const names = [];
  for (const line of lines.slice(start + 1)) {
    if (/^#{1,6} /u.test(line)) break;
    const match = /^\| `([A-Za-z]+V1)` \|/u.exec(line);
    if (match) names.push(match[1]);
  }
  return names;
}

test("QA gate: absent, empty and exactly `disabled` register nothing and load no registration module", () => {
  for (const value of [undefined, "", "disabled"]) {
    const run = coldStart({ YOVOICE_SERVERS_V1: value });
    assert.equal(run.status, 0, `gate=${JSON.stringify(value)} must load: ${run.stderr}`);
    assert.equal(run.inspection.registrationCached, false);
    assert.ok(!run.inspection.serversModules.includes("registration.js"));
    for (const name of SERVERS_V1_EXPORT_NAMES) assert.ok(!run.inspection.exportNames.includes(name), name);
  }
});

test("QA gate: only exactly `enabled` registers; case, spelling, boolean spellings and whitespace variants fail at require time with the documented message", () => {
  const enabled = coldStart({ YOVOICE_SERVERS_V1: "enabled" });
  assert.equal(enabled.status, 0, enabled.stderr);
  assert.equal(enabled.inspection.registrationCached, true);
  for (const name of SERVERS_V1_EXPORT_NAMES) assert.ok(enabled.inspection.exportNames.includes(name), name);
  for (const value of ["Enabled", "true", "1", "on", "enabled "]) {
    const run = coldStart({ YOVOICE_SERVERS_V1: value });
    assert.notEqual(run.status, 0, `gate=${JSON.stringify(value)} must refuse to load`);
    assert.ok(run.stderr.includes(GATE_MESSAGE), `gate=${JSON.stringify(value)} stderr: ${run.stderr.slice(0, 400)}`);
  }
});

test("QA gate on: the export delta is exactly the twenty-one documented callables plus the two dispatcher exports and the sweep, and every pre-existing export is structurally unchanged", () => {
  const off = coldStart({ YOVOICE_SERVERS_V1: undefined }).inspection;
  const on = coldStart({ YOVOICE_SERVERS_V1: "enabled" }).inspection;
  const documented = docsCallableNames();
  assert.equal(documented.length, 21);
  assert.deepEqual(CALLABLES, documented, "registration table must list the documented names in the documented order");
  const expected = [...documented, ...DISPATCHER_EXPORTS, ...SWEEP_EXPORTS].sort();
  assert.deepEqual(on.exportNames.filter((name) => !off.exportNames.includes(name)), expected);
  assert.deepEqual(off.exportNames.filter((name) => !on.exportNames.includes(name)), []);
  for (const name of off.exportNames) assert.deepEqual(on.endpoints[name], off.endpoints[name], name);
  for (const name of expected) {
    assert.equal(on.endpoints[name].type, "function", name);
    assert.deepEqual(on.endpoints[name].endpoint.region, ["europe-west1"], name);
  }
});

test("QA gate on: the App Check switch is the strict boolean helper, read only inside the gate", () => {
  const lax = coldStart({ YOVOICE_SERVERS_V1: "enabled", YOVOICE_ENFORCE_SERVERS_APP_CHECK: " TRUE " });
  assert.equal(lax.status, 0, lax.stderr);
  const bad = coldStart({ YOVOICE_SERVERS_V1: "enabled", YOVOICE_ENFORCE_SERVERS_APP_CHECK: "yes" });
  assert.notEqual(bad.status, 0);
  assert.ok(bad.stderr.includes(APP_CHECK_MESSAGE), bad.stderr.slice(0, 400));
  // With the gate off the switch is never read: an invalid value is harmless.
  const ignored = coldStart({ YOVOICE_SERVERS_V1: "disabled", YOVOICE_ENFORCE_SERVERS_APP_CHECK: "yes" });
  assert.equal(ignored.status, 0, ignored.stderr);
});

/*
|--------------------------------------------------------------------------
| In-process boundary: fake registrars, fake runtime
|--------------------------------------------------------------------------
*/

function registrars(list) {
  const register = (kind) => (options, handler) => {
    const entry = { kind, options, handler };
    list.push(entry);
    return entry;
  };
  return { onCall: register("callable"), onDocumentCreated: register("created"), onSchedule: register("schedule") };
}

function recordingLog() {
  const lines = [];
  const at = (level) => (message, payload) => lines.push({ level, message, payload });
  return { lines, info: at("info"), warn: at("warn"), error: at("error") };
}

function memoryDb(documents, reads) {
  return {
    collection: (name) => ({
      doc: (id) => ({
        get: async () => {
          reads.push(`${name}/${id}`);
          const data = documents.get(`${name}/${id}`);
          return { exists: data !== undefined, data: () => data };
        },
      }),
    }),
  };
}

function fakeRuntime({ methods = {}, workers = {}, documents = new Map(), reads = [], clock = () => NOW } = {}) {
  const services = {};
  for (const [name, service] of Object.entries(SERVER_CALLABLE_METHODS)) {
    (services[service] ??= {})[name] = methods[name] ?? (async () => ({ ok: name }));
  }
  return {
    db: memoryDb(documents, reads),
    FieldPath: { documentId: () => "__name__" },
    clock,
    ...services,
    projection: { processServerControlOutboxPage: workers.projection ?? (async () => ({ propagationComplete: true })) },
    convergence: { processServerConvergencePage: workers.convergence ?? (async () => ({ cleanupPending: false })) },
    sessionControl: { processServerSessionEndPage: workers.sessionEnd ?? (async () => ({ cleanupPending: false })) },
    staleness: { stageStaleServerChannelSessions: workers.staleness ?? (async () => ({
      scanned: 0, truncated: false, skippedLegacy: 0, skippedUnbound: 0, skippedYoung: 0,
      skippedOccupied: 0, providerUnavailable: 0, changed: 0, staged: [],
    })) },
  };
}

function build(options = {}) {
  const list = [];
  const log = recordingLog();
  const runtime = options.runtime ?? fakeRuntime(options);
  const functions = createServersV1Functions({
    runtime, registrars: registrars(list), log, enforceAppCheck: options.enforceAppCheck, dispatch: options.dispatch ?? {},
  });
  return { functions, list, log, runtime };
}

function pendingJob(overrides = {}) {
  return {
    schemaVersion: 1, kind: "memberJoined", serverId: "server-1", userId: "member-1", membershipRevision: 2,
    status: "pending", cursor: null, convergenceVersion: 1, rtcTargets: [], grantStatus: "completed",
    grantCursor: null, rtcStatus: "completed", rtcTargetIndex: 0, rtcRecipientCursor: null, bridgeLeaseId: null,
    bridgeLeaseExpiresAtMillis: 0, retryAfterMillis: 0, lastErrorCode: null, contentCleanupPending: false, ...overrides,
  };
}

const withCode = (code) => (error) => error instanceof HttpsError && error.code === code;

test("QA binding: identity comes only from request.auth.uid; uid-like payload keys, transport properties and token claims never replace it", async () => {
  const nested = { auth: { uid: "nested-forged" }, list: [{ uid: "array-forged" }] };
  const payload = {
    uid: "forged", ownerId: "forged", callerId: "forged", auth: { uid: "forged" }, context: { auth: { uid: "forged" } },
    nested, requestId: "a".repeat(16),
  };
  const request = {
    auth: { uid: "real-user", token: { email_verified: true, uid: "claim-forged", sub: "claim-forged" } },
    data: payload,
    rawRequest: { headers: { authorization: "Bearer forged", "x-uid": "forged" } },
    app: { appId: "forged" }, instanceIdToken: "forged", uid: "forged",
  };
  const bound = authBoundRequest(request);
  assert.deepEqual(Object.keys(bound).sort(), ["auth", "data"]);
  assert.deepEqual(Object.keys(bound.auth).sort(), ["token", "uid"]);
  assert.equal(bound.auth.uid, "real-user");
  assert.equal(bound.data, payload, "payload is handed through by reference");
  assert.equal(bound.data.nested, nested, "nested objects keep their identity");
  assert.equal(bound.data.nested.list[0].uid, "array-forged", "arrays are not rewritten");
  assert.notEqual(bound.auth.token, request.auth.token, "token is copied, not shared");

  const received = [];
  const { functions } = build({ methods: { joinServerV1: async (value) => { received.push(value); return { joined: true }; } } });
  assert.deepEqual(await functions.joinServerV1.handler(request), { joined: true });
  assert.equal(received.length, 1);
  assert.equal(received[0].auth.uid, "real-user");
  assert.equal(received[0].data, payload);
  assert.deepEqual(Object.keys(received[0]).sort(), ["auth", "data"]);
});

test("QA binding: every malformed or missing Auth context is `unauthenticated` before any factory runs; email verification is left to the factory", async () => {
  let calls = 0;
  const { functions } = build({ methods: { leaveServerV1: async (value) => { calls += 1; return value.auth; } } });
  const handler = functions.leaveServerV1.handler;
  const data = { serverId: "s", requestId: "r".repeat(12) };
  for (const auth of [undefined, null, {}, { uid: "" }, { uid: 42 }, { uid: "has/slash" }, { uid: "x".repeat(129) }, { uid: null, token: { uid: "y" } }]) {
    await assert.rejects(handler({ auth, data, uid: "forged" }), withCode("unauthenticated"), JSON.stringify(auth));
  }
  assert.equal(calls, 0);
  // The wrapper binds with verified:false; operations.execute enforces
  // verification per operation (proved against the emulator below).
  const unverified = await handler({ auth: { uid: "real-user", token: { email_verified: false } }, data });
  assert.deepEqual(unverified, { uid: "real-user", token: { email_verified: false } });
  assert.equal(calls, 1);
});

test("QA binding: App Check enforcement and limited-use consumption flip together on the twenty-one callables only, and only for a boolean true", () => {
  for (const [value, expected] of [[true, true], [false, false], [undefined, false], ["true", false], [1, false]]) {
    const { list } = build({ enforceAppCheck: value });
    const callables = list.filter((entry) => entry.kind === "callable");
    assert.equal(callables.length, 21);
    for (const entry of callables) {
      assert.equal(entry.options.enforceAppCheck, expected, `enforceAppCheck=${String(value)}`);
      assert.equal(entry.options.consumeAppCheckToken, expected, `enforceAppCheck=${String(value)}`);
    }
    for (const entry of list.filter((item) => item.kind !== "callable")) {
      assert.ok(!("enforceAppCheck" in entry.options) && !("consumeAppCheckToken" in entry.options));
    }
  }
});

test("QA binding: the registered map is exactly the twenty-four names with the documented options and secret bindings", () => {
  const { functions, list } = build();
  assert.deepEqual(Object.keys(functions).sort(), [...SERVERS_V1_EXPORT_NAMES].sort());
  assert.ok(Object.isFrozen(functions));
  assert.equal(list.length, 24);
  for (const entry of list) {
    assert.equal(entry.options.region, "europe-west1");
    assert.equal(typeof entry.handler, "function");
  }
  const secretNames = (entry) => (entry.options.secrets ?? []).map((secret) => secret.name).sort();
  for (const name of CALLABLES) {
    const entry = functions[name];
    assert.equal(entry.kind, "callable");
    assert.equal(entry.options.minInstances, 0);
    assert.equal(entry.options.maxInstances, 50);
    if (name === "createServerChannelTokenV1" || name === "endServerChannelSessionV1") {
      assert.deepEqual(secretNames(entry), ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"]);
      assert.equal(entry.options.timeoutSeconds, 120);
    } else {
      assert.deepEqual(secretNames(entry), []);
      assert.equal(entry.options.timeoutSeconds, 60);
    }
  }
  assert.equal(functions[TRIGGER].options.document, `${OUTBOX_COLLECTION}/{operationId}`);
  assert.equal(functions[TRIGGER].options.retry, true);
  assert.equal(functions[TRIGGER].options.maxInstances, 10);
  assert.equal(functions[SCHEDULE].options.schedule, "every 5 minutes");
  assert.equal(functions[SCHEDULE].options.timeZone, "Etc/UTC");
  assert.equal(functions[SCHEDULE].options.maxInstances, 1);
  assert.equal(functions[TRIGGER].options.timeoutSeconds, 300);
  assert.equal(functions[SCHEDULE].options.timeoutSeconds, 300);
});

test("QA binding: construction refuses missing registrars, missing factory methods and out-of-range dispatch limits", () => {
  assert.throws(() => createServersV1Functions({ runtime: fakeRuntime(), registrars: { onCall() {}, onSchedule() {} }, log: recordingLog() }),
    /Missing Cloud Functions registrar: onDocumentCreated/u);
  const runtime = fakeRuntime();
  delete runtime.memberships.transferServerOwnershipV1;
  assert.throws(() => createServersV1Functions({ runtime, registrars: registrars([]), log: recordingLog() }),
    /Missing Servers V1 method memberships\.transferServerOwnershipV1/u);
  for (const dispatch of [{ timeBudgetMs: 999 }, { timeBudgetMs: 290_001 }, { triggerMaxPages: 0 }, { scheduleScanPageSize: 101 }, { scheduleScanLimit: 1001 }]) {
    assert.throws(() => build({ dispatch }), withCode("invalid-argument"), JSON.stringify(dispatch));
  }
  assert.throws(() => build({ dispatch: { random: "not-a-function" } }), /random must be a function/u);
});

test("QA errors: factory HttpsErrors pass through as the same instance; everything else becomes a fixed `internal` with no message, details or path in the log", async () => {
  const structured = new HttpsError("permission-denied", "You cannot manage this server.", { reason: "role" });
  const cases = {
    updateServerV1: async () => { throw structured; },
    createServerChannelV1: async () => { throw new Error("clubs/srv_secret/members/other-user-uid missing at /workspace/functions/servers/channels.js:12"); },
    updateServerChannelV1: async () => { throw Object.assign(new Error("permission-denied disguised"), { code: "permission-denied" }); },
    reorderServerChannelsV1: async () => { throw Object.assign(new TypeError("bad"), { code: "../users/other-uid" }); },
    setServerChannelAccessV1: async () => { throw Object.assign(new Error("grpc"), { code: 14 }); },
    archiveServerChannelV1: async () => { throw null; },
    deleteServerChannelV1: async () => { throw new HttpsError("internal", "factory-owned internal", { keep: true }); },
  };
  const { functions, log } = build({ methods: cases });
  const request = { auth: { uid: "real-user", token: {} }, data: {} };
  await assert.rejects(functions.updateServerV1.handler(request), (error) => error === structured);
  await assert.rejects(functions.deleteServerChannelV1.handler(request), (error) => error instanceof HttpsError &&
    error.code === "internal" && error.message === "factory-owned internal" && error.details?.keep === true);
  assert.equal(log.lines.length, 0, "pass-through failures are not logged by the boundary");

  const expectations = [
    ["createServerChannelV1", "internal", "Error"],
    ["updateServerChannelV1", "permission-denied", "Error"],
    ["reorderServerChannelsV1", "internal", "TypeError"],
    ["setServerChannelAccessV1", "14", "Error"],
    ["archiveServerChannelV1", "internal", "Error"],
  ];
  for (const [name, code, className] of expectations) {
    await assert.rejects(functions[name].handler(request), (error) => {
      assert.ok(error instanceof HttpsError, name);
      assert.equal(error.code, "internal", name);
      assert.equal(error.message, "The server operation could not be completed.", name);
      assert.equal(error.details, undefined, name);
      const visible = JSON.stringify(error.toJSON());
      assert.ok(!/clubs\/|other-user-uid|other-uid|\.js:\d+|disguised/u.test(visible), visible);
      return true;
    });
    const line = log.lines.at(-1);
    assert.equal(line.level, "error");
    assert.equal(line.message, "servers.callable_failed");
    assert.deepEqual(line.payload, { callable: name, code, name: className });
  }
  assert.equal(log.lines.length, expectations.length);
});

test("QA errors: every failure code contract.js can raise is a valid HttpsError code, and the transient classification is exact", () => {
  const source = fs.readFileSync(path.resolve(FUNCTIONS_DIR, "servers", "contract.js"), "utf8");
  const codes = new Set([...source.matchAll(/fail\("([a-z-]+)"/gu)].map((match) => match[1]));
  assert.ok(codes.size > 0);
  const valid = new Set(["invalid-argument", "failed-precondition", "permission-denied", "not-found", "already-exists",
    "resource-exhausted", "unauthenticated", "aborted", "unavailable", "internal", "data-loss", "deadline-exceeded",
    "cancelled", "unknown", "out-of-range", "unimplemented"]);
  for (const code of codes) assert.ok(valid.has(code), code);
  for (const code of valid) {
    const transient = ["aborted", "cancelled", "deadline-exceeded", "resource-exhausted", "unavailable", "unknown"].includes(code);
    assert.equal(isTransientFailure(new HttpsError(code, "x")), transient, code);
    // A plain object carrying a transient string code is not an HttpsError.
    assert.equal(isTransientFailure({ code }), false, code);
  }
  for (const number of [1, 2, 4, 8, 10, 14]) assert.equal(isTransientFailure({ code: number }), true, String(number));
  for (const number of [0, 3, 5, 6, 7, 9, 11, 12, 13, 15, 16, 14.5, -14]) assert.equal(isTransientFailure({ code: number }), false, String(number));
  for (const value of [null, undefined, "14", new Error("14"), { code: "14" }]) assert.equal(isTransientFailure(value), false);
});

test("QA dispatch: describeOutboxJob boundaries are exact — leases and backoff hold strictly past `now`, non-numeric hints do not hold, and shape drift is unsupported", () => {
  const eligible = { route: "convergence", reason: "eligible" };
  assert.deepEqual(describeOutboxJob(pendingJob(), NOW), eligible);
  assert.deepEqual(describeOutboxJob(pendingJob({ bridgeLeaseId: "l", bridgeLeaseExpiresAtMillis: NOW }), NOW), eligible);
  assert.deepEqual(describeOutboxJob(pendingJob({ bridgeLeaseId: "l", bridgeLeaseExpiresAtMillis: NOW + 1 }), NOW), { route: "convergence", reason: "leased" });
  assert.deepEqual(describeOutboxJob(pendingJob({ bridgeLeaseId: "", bridgeLeaseExpiresAtMillis: NOW + 1 }), NOW), eligible);
  assert.deepEqual(describeOutboxJob(pendingJob({ bridgeLeaseId: "l", bridgeLeaseExpiresAtMillis: String(NOW + 1) }), NOW), eligible);
  assert.deepEqual(describeOutboxJob(pendingJob({ retryAfterMillis: NOW }), NOW), eligible);
  assert.deepEqual(describeOutboxJob(pendingJob({ retryAfterMillis: NOW + 1 }), NOW), { route: "convergence", reason: "backoff" });
  assert.deepEqual(describeOutboxJob(pendingJob({ retryAfterMillis: Number.NaN }), NOW), eligible);
  for (const drift of [
    { status: "pending " }, { status: "PENDING" }, { status: "failed" }, { schemaVersion: "1" }, { schemaVersion: 2 },
    { convergenceVersion: "1" }, { convergenceVersion: 2 }, { kind: "memberjoined" }, { kind: "sessionend" },
  ]) {
    assert.deepEqual(describeOutboxJob(pendingJob(drift), NOW), { route: null, reason: "unsupported" }, JSON.stringify(drift));
  }
  for (const value of [null, undefined, [], "pending", 1, pendingJob({ status: "completed", kind: "nope" })]) {
    assert.deepEqual(describeOutboxJob(value, NOW), { route: null, reason: "unsupported" });
  }
  assert.deepEqual(describeOutboxJob(pendingJob({ status: "completed", convergenceVersion: 9 }), NOW), { route: null, reason: "completed" });
  assert.deepEqual(describeOutboxJob({ schemaVersion: 1, kind: "sessionEnd", status: "pending", leaseId: "l", leaseExpiresAtMillis: NOW }, NOW), { route: "sessionEnd", reason: "eligible" });
  assert.deepEqual(describeOutboxJob({ schemaVersion: 1, kind: "sessionEnd", status: "pending", leaseId: "l", leaseExpiresAtMillis: NOW + 1 }, NOW), { route: "sessionEnd", reason: "leased" });
  assert.deepEqual(describeOutboxJob({ schemaVersion: 1, kind: "serverMetadata", status: "pending" }, NOW), { route: "projection", reason: "eligible" });
});

test("QA dispatch: an operationId outside the id grammar is reported unsupported without a read and without a rethrow", async () => {
  const reads = [];
  let workerCalls = 0;
  const { functions, log } = build({ reads, workers: { convergence: async () => { workerCalls += 1; return { cleanupPending: false }; } } });
  for (const operationId of [undefined, "", "../x", "a b", "x".repeat(129), 42, null]) {
    const line = await functions[TRIGGER].handler({ params: { operationId } });
    assert.deepEqual(line, { source: "trigger", operationId: null, kind: null, outcome: "unsupported", pages: 0, processed: 0, code: null });
  }
  await assert.doesNotReject(functions[TRIGGER].handler({}));
  assert.deepEqual(reads, []);
  assert.equal(workerCalls, 0);
  assert.ok(log.lines.every((line) => line.level === "warn" && line.message === "servers.dispatch"));
});

test("QA dispatch: a transient worker failure rethrows the same error for platform redelivery; structured refusals and programming faults return normally as `rejected`", async () => {
  const documents = new Map([[`${OUTBOX_COLLECTION}/${"1".repeat(64)}`, pendingJob()]]);
  const failures = [
    [new HttpsError("unavailable", "provider down"), "failed", "unavailable"],
    [Object.assign(new Error("aborted txn"), { code: 10 }), "failed", "10"],
    [new HttpsError("permission-denied", "clubs/srv/members/other-uid refuses"), "rejected", "permission-denied"],
    [new HttpsError("invalid-argument", "job shape"), "rejected", "invalid-argument"],
    [new TypeError("Cannot read properties of undefined"), "rejected", "internal"],
    [Object.assign(new Error("grpc"), { code: 3 }), "rejected", "3"],
  ];
  for (const [thrown, outcome, code] of failures) {
    const { functions, log } = build({ documents, workers: { convergence: async () => { throw thrown; } } });
    const invocation = functions[TRIGGER].handler({ params: { operationId: "1".repeat(64) } });
    if (outcome === "failed") {
      await assert.rejects(invocation, (error) => error === thrown);
    } else {
      const line = await invocation;
      assert.equal(line.outcome, "rejected");
      assert.equal(line.code, code);
    }
    assert.equal(log.lines.length, 1);
    assert.equal(log.lines[0].level, "error");
    assert.deepEqual(log.lines[0].payload, {
      source: "trigger", operationId: "1".repeat(64), kind: "memberJoined", outcome, pages: 0, processed: 0, code,
    });
    assert.ok(!JSON.stringify(log.lines[0].payload).includes("other-uid"));
  }
});

test("QA dispatch: a worker that reports remaining work without visible progress stops as `stalled`, and the trigger page budget stops as `exhausted`", async () => {
  const id = "2".repeat(64);
  const documents = new Map([[`${OUTBOX_COLLECTION}/${id}`, pendingJob()]]);
  let calls = 0;
  const stalled = build({ documents, workers: { convergence: async () => { calls += 1; return { cleanupPending: true, processed: 0 }; } } });
  let line = await stalled.functions[TRIGGER].handler({ params: { operationId: id } });
  assert.equal(line.outcome, "stalled");
  assert.equal(line.pages, 1);
  assert.equal(calls, 1);

  calls = 0;
  const progressing = build({
    documents, dispatch: { triggerMaxPages: 2 },
    workers: { convergence: async () => {
      calls += 1;
      const current = documents.get(`${OUTBOX_COLLECTION}/${id}`);
      documents.set(`${OUTBOX_COLLECTION}/${id}`, { ...current, grantCursor: `page-${calls}` });
      return { cleanupPending: true, processed: 3 };
    } },
  });
  line = await progressing.functions[TRIGGER].handler({ params: { operationId: id } });
  assert.equal(line.outcome, "exhausted");
  assert.equal(line.pages, 2);
  assert.equal(line.processed, 6);
  assert.equal(calls, 2);
});

test("QA dispatch: a worker result without a work-remaining signal must not be reported `completed` (uncertain work is never completed)", async () => {
  const id = "3".repeat(64);
  const documents = new Map([[`${OUTBOX_COLLECTION}/${id}`, pendingJob()]]);
  for (const result of [undefined, {}, { processed: 1 }]) {
    const { functions } = build({ documents, workers: { convergence: async () => result } });
    const line = await functions[TRIGGER].handler({ params: { operationId: id } });
    assert.notEqual(line.outcome, "completed", `worker result ${JSON.stringify(result)} left the job pending`);
  }
});

/*
|--------------------------------------------------------------------------
| Emulator: real factories through the boundary, real Firestore under the
| dispatcher with injected clock and instrumented workers
|--------------------------------------------------------------------------
*/

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const emulator = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const apps = [];
after(async () => {
  const { deleteApp } = require("firebase-admin/app");
  await Promise.all(apps.map((app) => deleteApp(app)));
});
const emulatorTest = (name, fn) => test(`QA emulator: ${name}`, { skip: emulator ? false : "Requires explicit localhost Firestore emulator." }, fn);

function freshDb() {
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, Timestamp, FieldPath } = require("firebase-admin/firestore");
  const app = initializeApp({ projectId: `demo-yovoice-s4qa-${randomUUID().slice(0, 8)}` }, `s4qa-${randomUUID()}`);
  apps.push(app);
  return { db: getFirestore(app), Timestamp, FieldPath };
}

const creationInput = (overrides = {}) => ({
  requestId: randomUUID(), serverType: "community", templateVersion: 1, name: "QA server",
  description: "", privacy: "public", defaultLanguage: "English", ...overrides,
});

async function realFixture() {
  const { db, Timestamp } = freshDb();
  let nowMs = NOW;
  const livekit = {
    assertSupported() {},
    async mintToken() { throw new Error("QA: provider must not be reached"); },
    async revokeParticipant() { throw new Error("QA: provider must not be reached"); },
    async endRoom() { throw new Error("QA: provider must not be reached"); },
    async roomOccupancy() { throw new Error("QA: provider must not be reached"); },
  };
  const runtime = createServersV1Runtime({ db, Timestamp, clock: () => nowMs, livekit });
  const { functions, log } = build({ runtime });
  const call = (name, uid, data, token = { email_verified: true }) => functions[name].handler({
    auth: { uid, token }, data, rawRequest: { headers: { "x-uid": "forged" } },
  });
  async function user(label) {
    const uid = `${label}-${randomUUID()}`;
    await db.doc(`users/${uid}`).set({ displayName: `QA ${label}`, status: "active" });
    return uid;
  }
  const serversOwnedBy = async (uid) => (await db.collection("clubs").where("ownerId", "==", uid).get()).size;
  return { db, functions, log, call, user, serversOwnedBy };
}

emulatorTest("createServerV1 rejects every uid-like or unknown payload key with invalid-argument and writes nothing; an unverified caller is refused by the factory", async () => {
  const f = await realFixture();
  const owner = await f.user("owner");
  const stranger = await f.user("stranger");
  for (const key of ["uid", "ownerId", "callerId", "auth", "context", "hostId", "serverOwnerId"]) {
    const data = creationInput({ [key]: key === "auth" || key === "context" ? { uid: stranger } : stranger });
    await assert.rejects(f.call("createServerV1", owner, data), (error) => {
      assert.ok(error instanceof HttpsError && error.code === "invalid-argument", key);
      assert.ok(!error.message.includes(stranger) && !error.message.includes(owner), error.message);
      return true;
    });
  }
  await assert.rejects(f.call("createServerV1", owner, creationInput(), { email_verified: false }), withCode("failed-precondition"));
  await assert.rejects(f.call("createServerV1", owner, creationInput(), {}), withCode("failed-precondition"));
  await assert.rejects(f.functions.createServerV1.handler({ data: creationInput(), uid: owner }), withCode("unauthenticated"));
  assert.equal(await f.serversOwnedBy(owner), 0);
  assert.equal(await f.serversOwnedBy(stranger), 0);
  assert.equal((await f.db.collection("clubs").get()).size, 0);
  assert.equal(f.log.lines.length, 0);
});

emulatorTest("requestId replay returns the identical receipt; a different input under the same requestId is refused with already-exists and creates nothing", async () => {
  const f = await realFixture();
  const owner = await f.user("owner");
  const data = creationInput();
  const first = await f.call("createServerV1", owner, data);
  assert.equal(first.alreadyExisted, false);
  const replay = await f.call("createServerV1", owner, { ...data });
  assert.deepEqual(replay, { ...first, alreadyExisted: true });
  await assert.rejects(f.call("createServerV1", owner, { ...data, name: "Renamed" }), withCode("already-exists"));
  await assert.rejects(f.call("createServerV1", owner, { ...data, serverType: "friends", privacy: "inviteOnly" }), withCode("already-exists"));
  assert.equal(await f.serversOwnedBy(owner), 1);
  const other = await f.user("other");
  // The same requestId under another identity is a different operation.
  const theirs = await f.call("createServerV1", other, { ...data });
  assert.notEqual(theirs.serverId, first.serverId);
  assert.equal(theirs.alreadyExisted, false);
  assert.equal(f.log.lines.length, 0);
});

emulatorTest("contract.js refusals reach the client as invalid-argument with fixed messages: no ids, paths, stacks or details", async () => {
  const f = await realFixture();
  const owner = await f.user("owner");
  const refusals = [
    creationInput({ serverType: "family", privacy: "public" }),
    creationInput({ templateVersion: 2 }),
    creationInput({ serverType: "guild" }),
    creationInput({ name: "" }),
    creationInput({ privacy: "secret" }),
  ];
  for (const data of refusals) {
    await assert.rejects(f.call("createServerV1", owner, data), (error) => {
      assert.ok(error instanceof HttpsError && error.code === "invalid-argument", JSON.stringify(data));
      const visible = JSON.stringify(error.toJSON());
      assert.ok(!visible.includes(owner) && !visible.includes(data.requestId) && !/clubs\/|users\/|\.js:\d+|\n\s+at /u.test(visible), visible);
      assert.equal(error.details, undefined);
      return true;
    });
  }
  assert.equal(await f.serversOwnedBy(owner), 0);
  assert.equal(f.log.lines.length, 0);
});

async function dispatchFixture(dispatch = {}) {
  const { db, FieldPath } = freshDb();
  let nowMs = NOW;
  const calls = [];
  const workers = { convergence: null };
  const runtime = fakeRuntime({ clock: () => nowMs, workers: {
    convergence: async (input) => { calls.push(input); return workers.convergence(input); },
  } });
  runtime.db = db;
  runtime.FieldPath = FieldPath;
  const { functions, log } = build({ runtime, dispatch: { random: () => "0".repeat(64), ...dispatch } });
  const outbox = db.collection(OUTBOX_COLLECTION);
  const read = async (id) => (await outbox.doc(id).get()).data();
  return {
    db, outbox, read, calls, workers, functions, log,
    advance: (ms) => { nowMs += ms; },
    trigger: (id, event = {}) => functions[TRIGGER].handler({ params: { operationId: id }, ...event }),
    sweep: () => functions[SCHEDULE].handler({ scheduleTime: new Date(NOW).toISOString() }),
    complete: async (id) => outbox.doc(id).update({ status: "completed" }),
  };
}

emulatorTest("platform redelivery of a completed job is idempotent: the live document, not the event snapshot, decides and the worker runs once", async () => {
  const f = await dispatchFixture();
  const id = HEX64();
  await f.outbox.doc(id).set(pendingJob());
  f.workers.convergence = async () => { await f.complete(id); return { cleanupPending: false, processed: 1 }; };
  const first = await f.trigger(id);
  assert.equal(first.outcome, "completed");
  assert.equal(first.pages, 1);
  const stale = { data: { data: () => pendingJob() } };
  const second = await f.trigger(id, stale);
  assert.equal(second.outcome, "completed");
  assert.equal(second.pages, 0);
  assert.deepEqual(f.calls, [{ operationId: id }]);
  assert.equal((await f.read(id)).status, "completed");
});

emulatorTest("an unsupported schema, version or kind is reported, never dispatched, and the document is byte-identical afterwards", async () => {
  const f = await dispatchFixture();
  f.workers.convergence = async () => { throw new Error("must not be asked"); };
  const variants = [pendingJob({ schemaVersion: 2 }), pendingJob({ convergenceVersion: 2 }), pendingJob({ kind: "memberBanned" }), pendingJob({ status: "failed" })];
  for (const variant of variants) {
    const id = HEX64();
    await f.outbox.doc(id).set(variant);
    const before = await f.read(id);
    const line = await f.trigger(id);
    assert.equal(line.outcome, "unsupported", JSON.stringify(variant));
    assert.equal(line.kind, variant.kind === "memberBanned" ? null : variant.kind);
    assert.deepEqual(await f.read(id), before);
  }
  const missing = await f.trigger(HEX64());
  assert.equal(missing.outcome, "missing");
  assert.deepEqual(f.calls, []);
  assert.equal(f.log.lines.filter((line) => line.level === "error").length, 0);
});

emulatorTest("a lease held by another worker, an unexpired backoff, recoveryRequired and contentCleanupPending are all left exactly as found", async () => {
  const f = await dispatchFixture();
  const leased = HEX64();
  const backed = HEX64();
  const recovery = HEX64();
  const content = HEX64();
  await f.outbox.doc(leased).set(pendingJob({ bridgeLeaseId: "other-instance", bridgeLeaseExpiresAtMillis: NOW + 30_000 }));
  await f.outbox.doc(backed).set(pendingJob({ retryAfterMillis: NOW + 30_000 }));
  await f.outbox.doc(recovery).set(pendingJob());
  await f.outbox.doc(content).set(pendingJob({ kind: "channelDelete", contentCleanupPending: true }));
  const snapshots = Object.fromEntries(await Promise.all([leased, backed, recovery, content].map(async (id) => [id, await f.read(id)])));
  f.workers.convergence = async ({ operationId }) => (operationId === recovery
    ? { cleanupPending: true, recoveryRequired: true, processed: 0 }
    : { cleanupPending: true, contentCleanupPending: true, rtcCleanupPending: false, processed: 0 });
  assert.equal((await f.trigger(leased)).outcome, "leased");
  assert.equal((await f.trigger(backed)).outcome, "backoff");
  assert.deepEqual(f.calls, []);
  f.advance(29_999);
  assert.equal((await f.trigger(leased)).outcome, "leased", "a lease holds until its expiry millisecond");
  assert.equal((await f.trigger(backed)).outcome, "backoff");
  assert.deepEqual(f.calls, []);
  const recovered = await f.trigger(recovery);
  assert.equal(recovered.outcome, "recoveryRequired");
  assert.equal(recovered.pages, 1);
  const cleanup = await f.trigger(content);
  assert.equal(cleanup.outcome, "contentCleanupPending");
  assert.equal(cleanup.pages, 1);
  assert.deepEqual(f.calls.map((call) => call.operationId), [recovery, content]);
  for (const id of [leased, backed, recovery, content]) assert.deepEqual(await f.read(id), snapshots[id], id);
  assert.equal(f.log.lines.filter((line) => line.level === "error").length, 0);
});

emulatorTest("the schedule sweep stops at its wall-clock budget between jobs, reports hasMore and leaves the unvisited jobs pending", async () => {
  const f = await dispatchFixture({ timeBudgetMs: 1_000 });
  const ids = [HEX64(), HEX64(), HEX64(), HEX64()].sort();
  for (const id of ids) await f.outbox.doc(id).set(pendingJob());
  await f.outbox.doc(HEX64()).set(pendingJob({ status: "completed" }));
  f.workers.convergence = async ({ operationId }) => {
    f.advance(600);
    await f.complete(operationId);
    return { cleanupPending: false, processed: 1 };
  };
  const counts = await f.sweep();
  assert.deepEqual(counts, { scanned: 2, completed: 2, deferred: 0, rejected: 0, failed: 0, unsupported: 0, hasMore: true });
  assert.deepEqual(f.calls.map((call) => call.operationId), ids.slice(0, 2));
  for (const id of ids.slice(2)) assert.deepEqual(await f.read(id), pendingJob(), id);
  const sweepLine = f.log.lines.find((line) => line.message === "servers.dispatch_sweep");
  assert.deepEqual(sweepLine.payload, counts);
});

emulatorTest("the schedule sweep stops inside a multi-page job at the budget as `exhausted` (deferred) and a rejected job never throws out of the sweep", async () => {
  const f = await dispatchFixture({ timeBudgetMs: 1_000, scheduleMaxPagesPerJob: 4 });
  const [first, second, third] = [HEX64(), HEX64(), HEX64()].sort();
  for (const id of [first, second, third]) await f.outbox.doc(id).set(pendingJob());
  let pages = 0;
  f.workers.convergence = async ({ operationId }) => {
    if (operationId === second) throw new HttpsError("failed-precondition", "clubs/x refuses");
    f.advance(600);
    pages += 1;
    await f.outbox.doc(operationId).update({ grantCursor: `page-${pages}` });
    return { cleanupPending: true, processed: 2 };
  };
  const counts = await f.sweep();
  assert.deepEqual(counts, { scanned: 1, completed: 0, deferred: 1, rejected: 0, failed: 0, unsupported: 0, hasMore: true });
  assert.equal(pages, 2, "two pages fit in the budget, the third is refused before starting");
  assert.equal((await f.read(second)).status, "pending");

  // A fresh, unhurried sweep over the same collection: the rejected job is
  // tallied and logged, the others advance by at most four pages each.
  const g = await dispatchFixture({ scheduleMaxPagesPerJob: 4 });
  for (const id of [first, second, third]) await g.outbox.doc(id).set(pendingJob());
  let calls = 0;
  g.workers.convergence = async ({ operationId }) => {
    if (operationId === second) throw new HttpsError("failed-precondition", "clubs/x refuses");
    calls += 1;
    await g.outbox.doc(operationId).update({ grantCursor: `page-${calls}` });
    return { cleanupPending: true, processed: 1 };
  };
  const relaxed = await g.sweep();
  assert.deepEqual(relaxed, { scanned: 3, completed: 0, deferred: 2, rejected: 1, failed: 0, unsupported: 0, hasMore: false });
  assert.equal(calls, 8);
  const errors = g.log.lines.filter((line) => line.level === "error");
  assert.equal(errors.length, 1);
  assert.deepEqual(errors[0].payload, { source: "schedule", operationId: second, kind: "memberJoined", outcome: "rejected", pages: 0, processed: 0, code: "failed-precondition" });
});

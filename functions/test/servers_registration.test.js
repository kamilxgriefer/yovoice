const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const path = require("node:path");
const { after, test } = require("node:test");

// Servers V1 registration and durable dispatch (servers/registration.js,
// ADR-176). Three layers, deliberately separate:
//   1. the cold-start contract of functions/index.js, observed the only way
//      it can be — by requiring the module in a fresh process per gate value;
//   2. the registration boundary with fake registrars and a fake runtime:
//      export map, options, Auth binding, error mapping, dispatch outcomes;
//   3. the real reviewed factories against an explicitly selected localhost
//      emulator: a held server written through the registered callable, the
//      structured denials, and the dispatcher driving real outbox jobs under
//      the workers' own leases.
// Nothing here activates a server for production: the one emulator-only
// activation below is the same isolated fixture step the convergence suite
// uses, because a membership job needs an active server to exist at all.

const { HttpsError } = require("firebase-functions/v2/https");
const {
  DEFAULT_DISPATCH_LIMITS, DISPATCHER_EXPORTS, OUTBOX_COLLECTION, REGION,
  SECRET_BOUND_CALLABLES, SERVER_CALLABLE_METHODS, SERVERS_V1_EXPORT_NAMES, SWEEP_EXPORTS,
  authBoundRequest, createServersV1Dispatcher, createServersV1Functions,
  createServersV1Runtime, describeOutboxJob, isTransientFailure,
} = require("../servers/registration");
const { canonicalServerId } = require("../servers/contract");
const { operationIdentity } = require("../integrity/guards");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const CALLABLE_NAMES = Object.keys(SERVER_CALLABLE_METHODS);
const LIVEKIT_SECRETS = ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"];
const TRIGGER = "onServerControlOutboxCreated";
const SCHEDULE = "processPendingServerControlOutboxSchedule";
const SWEEP = "sweepStaleServerChannelSessionsSchedule";
const NOW = 1_900_000_000_000;

/*
|--------------------------------------------------------------------------
| 1. Cold start per gate value
|--------------------------------------------------------------------------
*/

const INSPECT = [
  "const exported = require('./index.js');",
  "const root = process.cwd() + '/servers/';",
  "const cache = Object.keys(require.cache);",
  "const endpoints = {};",
  "for (const name of Object.keys(exported)) {",
  "  const endpoint = exported[name]?.__endpoint;",
  "  if (!endpoint) continue;",
  "  endpoints[name] = {",
  "    region: endpoint.region, minInstances: endpoint.minInstances,",
  "    secrets: (endpoint.secretEnvironmentVariables ?? []).map((item) => item.key).sort(),",
  "    callable: Boolean(endpoint.callableTrigger),",
  "    document: endpoint.eventTrigger?.eventFilterPathPatterns?.document ?? null,",
  "    retry: endpoint.eventTrigger?.retry ?? null,",
  "    schedule: endpoint.scheduleTrigger?.schedule ?? null,",
  "    timeZone: endpoint.scheduleTrigger?.timeZone ?? null,",
  "  };",
  "}",
  "process.stdout.write(JSON.stringify({",
  "  exportNames: Object.keys(exported).sort(),",
  "  serversModules: cache.filter((key) => key.startsWith(root)).map((key) => key.slice(root.length)).sort(),",
  "  livekitSdk: cache.filter((key) => key.includes('/node_modules/livekit-server-sdk/')).length,",
  "  endpoints,",
  "}));",
].join(" ");

function coldStartEnvironment(gate) {
  const env = { ...process.env };
  // The production map: functions/.env names no Stripe exports, no GIF
  // provider and no Servers gate. The shell must not leak any of them in.
  for (const name of [
    "STRIPE_BILLING_EXPORTS", "GIF_PROVIDER", "YOVOICE_SERVERS_V1", "YOVOICE_ENFORCE_SERVERS_APP_CHECK",
    "K_SERVICE", "FUNCTION_TARGET", "FIREBASE_STORAGE_BUCKET", "STORAGE_BUCKET", "GCLOUD_STORAGE_BUCKET",
  ]) delete env[name];
  env.GCLOUD_PROJECT = "yovoice-module-graph-test";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-module-graph-test",
    storageBucket: "yovoice-module-graph-test.firebasestorage.app",
  });
  if (gate !== undefined) env.YOVOICE_SERVERS_V1 = gate;
  return env;
}

const inspections = new Map();
function coldStart(gate) {
  const key = gate ?? "";
  if (!inspections.has(key)) {
    inspections.set(key, JSON.parse(execFileSync(process.execPath, ["-e", INSPECT], {
      cwd: FUNCTIONS_DIR, encoding: "utf8", env: coldStartEnvironment(gate), stdio: ["ignore", "pipe", "ignore"],
    })));
  }
  return inspections.get(key);
}

// The V1 registration surface: every module only servers/registration.js
// pulls onto the cold-start graph. The legacy Club/room boundary adapters
// deployed today already require three pure contract modules from the same
// directory (capacity guards, the versioned contract and the RTC binding
// check) so that old callables can refuse V1 targets; those are pinned
// separately below and are not this gate's doing.
const REGISTRATION_MODULES = Object.freeze([
  "registration.js", "creation.js", "channels.js", "invites.js", "memberships.js", "sessions.js", "session_participation.js", "operations.js",
  "convergence.js", "convergence_runtime.js", "convergence_lifecycle.js", "session_control.js",
  "session_staleness.js", "session_livekit.js", "session_contract.js", "session_authority.js", "authority.js",
  "documents.js", "templates.js",
]);
const LEGACY_BOUNDARY_MODULES = Object.freeze(["capacity.js", "contract.js", "rtc_binding.js"]);

test("Registration: an absent gate registers no Servers V1 name and loads no registration module", () => {
  const off = coldStart(undefined);
  assert.deepEqual(off.exportNames.filter((name) => SERVERS_V1_EXPORT_NAMES.includes(name)), []);
  assert.deepEqual(off.serversModules.filter((name) => REGISTRATION_MODULES.includes(name)), []);
  assert.deepEqual(off.serversModules, [...LEGACY_BOUNDARY_MODULES]);
  assert.equal(off.livekitSdk, 0);
});

test("Registration: `disabled` is byte-for-byte the same cold start as absent", () => {
  assert.deepEqual(coldStart("disabled"), coldStart(undefined));
});

test("Registration: `enabled` adds exactly the twenty-one callables, two dispatcher exports and the sweep, and nothing else", () => {
  const off = coldStart(undefined);
  const on = coldStart("enabled");
  assert.deepEqual(on.exportNames, [...off.exportNames, ...SERVERS_V1_EXPORT_NAMES].sort());
  assert.equal(SERVERS_V1_EXPORT_NAMES.length, 24);
  assert.equal(Object.keys(SERVER_CALLABLE_METHODS).length, 21);
  assert.ok(on.serversModules.includes("registration.js"));
  for (const factory of [
    "creation.js", "channels.js", "invites.js", "memberships.js", "sessions.js", "session_participation.js", "convergence.js",
    "convergence_runtime.js", "convergence_lifecycle.js", "session_control.js", "session_staleness.js", "operations.js",
  ]) assert.ok(on.serversModules.includes(factory), factory);
  // The LiveKit SDK stays a first-use require even with the gate on.
  assert.equal(on.livekitSdk, 0);
  // Enabling the gate changes nothing about the endpoints deployed today.
  for (const [name, endpoint] of Object.entries(off.endpoints)) {
    assert.deepEqual(on.endpoints[name], endpoint, name);
  }
  for (const name of CALLABLE_NAMES) {
    const endpoint = on.endpoints[name];
    assert.deepEqual(endpoint.region, [REGION], name);
    assert.equal(endpoint.minInstances, 0, `${name} must scale to zero`);
    assert.equal(endpoint.callable, true, name);
    assert.deepEqual(endpoint.secrets, SECRET_BOUND_CALLABLES.includes(name) ? LIVEKIT_SECRETS : [], name);
  }
  assert.deepEqual(on.endpoints[TRIGGER], {
    region: [REGION], minInstances: null, secrets: LIVEKIT_SECRETS, callable: false,
    document: `${OUTBOX_COLLECTION}/{operationId}`, retry: true, schedule: null, timeZone: null,
  });
  assert.deepEqual(on.endpoints[SCHEDULE], {
    region: [REGION], minInstances: null, secrets: LIVEKIT_SECRETS, callable: false,
    document: null, retry: null, schedule: "every 5 minutes", timeZone: "Etc/UTC",
  });
  // The stale-generation sweep (ADR-180) reaches the provider, so it binds the
  // same secrets as the other two workers and runs on the legacy sweep's cadence.
  assert.deepEqual(on.endpoints[SWEEP], {
    region: [REGION], minInstances: null, secrets: LIVEKIT_SECRETS, callable: false,
    document: null, retry: null, schedule: "every 5 minutes", timeZone: "Etc/UTC",
  });
});

test("Registration: any other gate value fails the cold start loudly", () => {
  // Whitespace and case variants are values too: nothing is trimmed or folded,
  // so `enabled ` is a typo that must fail the load rather than ship twenty-four
  // functions (functions/index.js strictEnabledEnvironment).
  for (const gate of [
    "true", "Enabled", "yes", "1", "on",
    "enabled ", " enabled", "enabled\n", "enabled\t", "ENABLED", "disabled ", " disabled",
  ]) {
    assert.throws(
      () => execFileSync(process.execPath, ["-e", "require('./index.js');"], {
        cwd: FUNCTIONS_DIR, encoding: "utf8", env: coldStartEnvironment(gate), stdio: ["ignore", "ignore", "pipe"],
      }),
      (error) => {
        assert.match(error.stderr, /YOVOICE_SERVERS_V1 must be exactly enabled or disabled\./u, gate);
        return true;
      },
      gate,
    );
  }
});

/*
|--------------------------------------------------------------------------
| 2. Registration boundary with fake registrars and a fake runtime
|--------------------------------------------------------------------------
*/

function fakeRegistrars(registrations) {
  const register = (kind) => (options, handler) => {
    const registered = { kind, options: { ...options }, handler };
    registrations.push(registered);
    return registered;
  };
  return { onCall: register("callable"), onDocumentCreated: register("created"), onSchedule: register("schedule") };
}

function recordingLog() {
  const lines = [];
  const record = (level) => (message, payload) => lines.push({ level, message, payload });
  return { lines, info: record("info"), warn: record("warn"), error: record("error") };
}

// Documents: Map of "collection/id" -> data or absent. `where` is only
// reached by the schedule, which the emulator layer covers.
function fakeDb(documents) {
  return {
    collection: (name) => ({
      doc: (id) => ({
        get: async () => {
          const data = documents.has(`${name}/${id}`) ? documents.get(`${name}/${id}`) : null;
          return { exists: data !== null, data: () => data };
        },
      }),
    }),
  };
}

function fakeRuntime({ calls = [], documents = new Map(), workers = {}, clock = () => NOW, methods = {} } = {}) {
  const services = {};
  for (const [name, service] of Object.entries(SERVER_CALLABLE_METHODS)) {
    (services[service] ??= {})[name] = methods[name] ?? (async (request) => {
      calls.push({ name, request });
      return { name };
    });
  }
  return {
    db: fakeDb(documents),
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

function convergenceJob(overrides = {}) {
  return {
    schemaVersion: 1, kind: "memberJoined", serverId: "server-1", userId: "member-1", membershipRevision: 2,
    operationId: "a".repeat(64), status: "pending", cursor: null, convergenceVersion: 1, rtcTargets: [],
    grantStatus: "completed", grantCursor: null, rtcStatus: "completed", rtcTargetIndex: 0,
    rtcRecipientCursor: null, bridgeLeaseId: null, bridgeLeaseExpiresAtMillis: 0, retryAfterMillis: 0,
    lastErrorCode: null, contentCleanupPending: false, ...overrides,
  };
}

const request = (uid, data, extra = {}) => ({ auth: { uid, token: { email_verified: true } }, data, ...extra });
const rejects = (promise, code) => assert.rejects(promise, (error) => error instanceof HttpsError && error.code === code);

test("Registration: the export map is exactly twenty-four names with the callable and worker options", () => {
  const registrations = [];
  const functions = createServersV1Functions({
    runtime: fakeRuntime(), registrars: fakeRegistrars(registrations), log: recordingLog(),
  });
  assert.deepEqual(Object.keys(functions).sort(), [...SERVERS_V1_EXPORT_NAMES].sort());
  assert.deepEqual(DISPATCHER_EXPORTS, [TRIGGER, SCHEDULE]);
  assert.deepEqual(SWEEP_EXPORTS, [SWEEP]);
  assert.equal(registrations.filter((item) => item.kind === "callable").length, 21);
  assert.equal(registrations.filter((item) => item.kind === "created").length, 1);
  assert.equal(registrations.filter((item) => item.kind === "schedule").length, 2);
  for (const name of CALLABLE_NAMES) {
    const { options } = functions[name];
    assert.equal(options.region, REGION, name);
    assert.equal(options.minInstances, 0, name);
    assert.equal(options.maxInstances, 50, name);
    assert.equal(options.enforceAppCheck, false, name);
    assert.equal(options.consumeAppCheckToken, false, name);
    if (SECRET_BOUND_CALLABLES.includes(name)) {
      assert.equal(options.timeoutSeconds, 120, name);
      assert.deepEqual(options.secrets.map((secret) => secret.name), LIVEKIT_SECRETS, name);
    } else {
      assert.equal(options.timeoutSeconds, 60, name);
      assert.equal("secrets" in options, false, name);
    }
  }
  const trigger = functions[TRIGGER].options;
  assert.equal(trigger.document, `${OUTBOX_COLLECTION}/{operationId}`);
  assert.equal(trigger.retry, true);
  assert.equal(trigger.region, REGION);
  assert.equal(trigger.maxInstances, 10);
  assert.equal(trigger.memory, "512MiB");
  assert.equal(trigger.timeoutSeconds, 300);
  assert.deepEqual(trigger.secrets.map((secret) => secret.name), LIVEKIT_SECRETS);
  const schedule = functions[SCHEDULE].options;
  assert.equal(schedule.schedule, "every 5 minutes");
  assert.equal(schedule.timeZone, "Etc/UTC");
  assert.equal(schedule.region, REGION);
  assert.equal(schedule.maxInstances, 1);
  assert.equal(schedule.timeoutSeconds, 300);
  assert.deepEqual(schedule.secrets.map((secret) => secret.name), LIVEKIT_SECRETS);
  const sweep = functions[SWEEP].options;
  assert.equal(sweep.schedule, "every 5 minutes");
  assert.equal(sweep.timeZone, "Etc/UTC");
  assert.equal(sweep.region, REGION);
  assert.equal(sweep.maxInstances, 1);
  assert.equal(sweep.timeoutSeconds, 300);
  assert.deepEqual(sweep.secrets.map((secret) => secret.name), LIVEKIT_SECRETS);
  // The time budget always leaves the worker deadline room for one more page.
  assert.ok(DEFAULT_DISPATCH_LIMITS.timeBudgetMs < trigger.timeoutSeconds * 1000 - 60_000);
});

test("Registration: the sweep schedule asks the staleness worker once and logs its counts, never the staged ids", async () => {
  const log = recordingLog();
  let invocations = 0;
  const staged = [{ serverId: "clubs/private", channelId: "c", roomId: "r", sessionId: "s", endOperationId: "e" }];
  const functions = createServersV1Functions({
    runtime: fakeRuntime({ workers: { staleness: async () => { invocations += 1; return {
      scanned: 3, truncated: false, skippedLegacy: 1, skippedUnbound: 0, skippedYoung: 1,
      skippedOccupied: 0, providerUnavailable: 0, changed: 0, staged,
    }; } } }),
    registrars: fakeRegistrars([]), log,
  });
  const line = await functions[SWEEP].handler();
  assert.equal(invocations, 1);
  assert.equal(line.staged, 1);
  assert.deepEqual(log.lines, [{ level: "info", message: "servers.stale_session_sweep", payload: line }]);
  assert.equal(JSON.stringify(log.lines).includes("clubs/private"), false);
  const warned = recordingLog();
  const unavailable = createServersV1Functions({
    runtime: fakeRuntime({ workers: { staleness: async () => ({
      scanned: 1, truncated: false, skippedLegacy: 0, skippedUnbound: 0, skippedYoung: 0,
      skippedOccupied: 0, providerUnavailable: 1, changed: 0, staged: [],
    }) } }),
    registrars: fakeRegistrars([]), log: warned,
  });
  await unavailable[SWEEP].handler();
  assert.deepEqual(warned.lines.map((entry) => entry.level), ["warn"]);
});

test("Registration: the App Check switch flips enforcement and consumption together on every callable", () => {
  const functions = createServersV1Functions({
    runtime: fakeRuntime(), registrars: fakeRegistrars([]), enforceAppCheck: true, log: recordingLog(),
  });
  for (const name of CALLABLE_NAMES) {
    assert.equal(functions[name].options.enforceAppCheck, true, name);
    assert.equal(functions[name].options.consumeAppCheckToken, true, name);
  }
  assert.equal("enforceAppCheck" in functions[TRIGGER].options, false);
});

test("Registration: a registered callable keeps the Auth uid, discards transport identity and passes the payload through untouched", async () => {
  const calls = [];
  const functions = createServersV1Functions({
    runtime: fakeRuntime({ calls }), registrars: fakeRegistrars([]), log: recordingLog(),
  });
  const data = { requestId: "r-1", serverId: "server-1", ownerId: "attacker" };
  const result = await functions.updateServerV1.handler({
    auth: { uid: "user-1", token: { email_verified: true, role: "user" } },
    data,
    rawRequest: { headers: { "x-forged-uid": "attacker" } },
    instanceIdToken: "device",
  });
  assert.deepEqual(result, { name: "updateServerV1" });
  assert.equal(calls.length, 1);
  assert.deepEqual(Object.keys(calls[0].request).sort(), ["auth", "data"]);
  assert.equal(calls[0].request.data, data);
  assert.deepEqual(calls[0].request.auth, { uid: "user-1", token: { email_verified: true, role: "user" } });
  // Every name routes to its own factory method, by identical name.
  for (const name of CALLABLE_NAMES) await functions[name].handler(request("user-1", {}));
  assert.deepEqual(calls.slice(1).map((call) => call.name), CALLABLE_NAMES);
});

test("Registration: an unauthenticated or malformed identity is refused before any factory runs", async () => {
  const calls = [];
  const functions = createServersV1Functions({
    runtime: fakeRuntime({ calls }), registrars: fakeRegistrars([]), log: recordingLog(),
  });
  await rejects(functions.createServerV1.handler({ data: {} }), "unauthenticated");
  await rejects(functions.createServerV1.handler({ auth: {}, data: {} }), "unauthenticated");
  await rejects(functions.createServerV1.handler({ auth: { uid: "bad/uid" }, data: {} }), "unauthenticated");
  assert.throws(() => authBoundRequest({ auth: { uid: "" }, data: {} }), (error) => error.code === "unauthenticated");
  assert.equal(calls.length, 0);
});

test("Registration: factory HttpsErrors reach the caller unchanged and anything else becomes `internal` without its message", async () => {
  const log = recordingLog();
  const structured = new HttpsError("permission-denied", "clubs/private-server is not yours");
  const functions = createServersV1Functions({
    runtime: fakeRuntime({
      methods: {
        updateServerV1: async () => { throw structured; },
        joinServerV1: async () => { throw new TypeError("clubs/secret-path broke"); },
        leaveServerV1: async () => { throw Object.assign(new Error("grpc"), { code: 14 }); },
      },
    }),
    registrars: fakeRegistrars([]),
    log,
  });
  await assert.rejects(functions.updateServerV1.handler(request("user-1", {})), (error) => error === structured);
  await assert.rejects(functions.joinServerV1.handler(request("user-1", {})), (error) => {
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, "internal");
    assert.equal(error.message, "The server operation could not be completed.");
    return true;
  });
  await rejects(functions.leaveServerV1.handler(request("user-1", {})), "internal");
  assert.deepEqual(log.lines, [
    { level: "error", message: "servers.callable_failed", payload: { callable: "joinServerV1", code: "internal", name: "TypeError" } },
    { level: "error", message: "servers.callable_failed", payload: { callable: "leaveServerV1", code: "14", name: "Error" } },
  ]);
  assert.equal(JSON.stringify(log.lines).includes("secret-path"), false);
});

test("Registration: a missing factory method or registrar fails at construction, never at the first call", () => {
  const runtime = fakeRuntime();
  delete runtime.sessions.endServerChannelSessionV1;
  assert.throws(
    () => createServersV1Functions({ runtime, registrars: fakeRegistrars([]), log: recordingLog() }),
    /Missing Servers V1 method sessions\.endServerChannelSessionV1\./u,
  );
  const withoutSweep = fakeRuntime();
  delete withoutSweep.staleness;
  assert.throws(
    () => createServersV1Functions({ runtime: withoutSweep, registrars: fakeRegistrars([]), log: recordingLog() }),
    /Missing Servers V1 worker staleness\.stageStaleServerChannelSessions\./u,
  );
  const { onSchedule, ...partial } = fakeRegistrars([]);
  assert.throws(
    () => createServersV1Functions({ runtime: fakeRuntime(), registrars: partial, log: recordingLog() }),
    /Missing Cloud Functions registrar: onSchedule\./u,
  );
  assert.throws(() => createServersV1Dispatcher({ runtime: { db: {} } }), TypeError);
  assert.throws(() => createServersV1Dispatcher({ runtime: fakeRuntime(), timeBudgetMs: 10 }),
    (error) => error.code === "invalid-argument");
  assert.throws(() => createServersV1Runtime({ db: fakeDb(new Map()), clock: "now" }), TypeError);
});

test("Registration: describeOutboxJob classifies leases, backoff, completion and unsupported shapes", () => {
  const now = NOW;
  assert.deepEqual(describeOutboxJob(null, now), { route: null, reason: "unsupported" });
  assert.deepEqual(describeOutboxJob({ schemaVersion: 2, kind: "memberJoined", status: "pending" }, now), { route: null, reason: "unsupported" });
  assert.deepEqual(describeOutboxJob({ schemaVersion: 1, kind: "unknownKind", status: "pending" }, now), { route: null, reason: "unsupported" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ status: "completed" }), now), { route: null, reason: "completed" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ status: "failed" }), now), { route: null, reason: "unsupported" });
  assert.deepEqual(describeOutboxJob(convergenceJob(), now), { route: "convergence", reason: "eligible" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ convergenceVersion: undefined }), now), { route: null, reason: "unsupported" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ bridgeLeaseId: "lease", bridgeLeaseExpiresAtMillis: now + 1 }), now), { route: "convergence", reason: "leased" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ bridgeLeaseId: "lease", bridgeLeaseExpiresAtMillis: now }), now), { route: "convergence", reason: "eligible" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ retryAfterMillis: now + 1 }), now), { route: "convergence", reason: "backoff" });
  assert.deepEqual(describeOutboxJob(convergenceJob({ retryAfterMillis: now }), now), { route: "convergence", reason: "eligible" });
  for (const kind of ["memberLeft", "memberRoleChanged", "sessionParticipantChanged", "channelAccess", "channelArchive", "channelDelete", "ownershipTransferred"]) {
    assert.deepEqual(describeOutboxJob(convergenceJob({ kind }), now), { route: "convergence", reason: "eligible" }, kind);
  }
  const sessionEnd = { schemaVersion: 1, kind: "sessionEnd", status: "pending", cursor: null, leaseId: null, leaseExpiresAtMillis: 0 };
  assert.deepEqual(describeOutboxJob(sessionEnd, now), { route: "sessionEnd", reason: "eligible" });
  assert.deepEqual(describeOutboxJob({ ...sessionEnd, leaseId: "lease", leaseExpiresAtMillis: now + 1 }, now), { route: "sessionEnd", reason: "leased" });
  assert.deepEqual(describeOutboxJob({ ...sessionEnd, leaseId: "lease", leaseExpiresAtMillis: now }, now), { route: "sessionEnd", reason: "eligible" });
  assert.deepEqual(describeOutboxJob({ ...sessionEnd, status: "completed" }, now), { route: null, reason: "completed" });
  assert.deepEqual(describeOutboxJob({ schemaVersion: 1, kind: "serverMetadata", status: "pending", grantStatus: "pending" }, now), { route: "projection", reason: "eligible" });
});

test("Registration: the trigger rethrows only transient worker failures and reports the rest", async () => {
  assert.equal(isTransientFailure(new HttpsError("unavailable", "x")), true);
  assert.equal(isTransientFailure(new HttpsError("aborted", "x")), true);
  assert.equal(isTransientFailure(new HttpsError("failed-precondition", "x")), false);
  assert.equal(isTransientFailure(new HttpsError("internal", "x")), false);
  assert.equal(isTransientFailure(Object.assign(new Error("grpc"), { code: 10 })), true);
  assert.equal(isTransientFailure(Object.assign(new Error("grpc"), { code: 5 })), false);
  assert.equal(isTransientFailure(new TypeError("x")), false);

  const operationId = "b".repeat(64);
  const documents = new Map([[`${OUTBOX_COLLECTION}/${operationId}`, convergenceJob({ operationId })]]);
  const failures = [
    [new HttpsError("unavailable", "provider"), "failed", "unavailable"],
    [Object.assign(new Error("firestore aborted"), { code: 10 }), "failed", "10"],
    [new HttpsError("failed-precondition", "The convergence job needs reconciliation."), "rejected", "failed-precondition"],
    [new TypeError("clubs/x broke"), "rejected", "internal"],
  ];
  for (const [failure, outcome, code] of failures) {
    const log = recordingLog();
    let invocations = 0;
    const dispatcher = createServersV1Dispatcher({
      runtime: fakeRuntime({ documents, workers: { convergence: async () => { invocations += 1; throw failure; } } }),
      log,
    });
    const event = { params: { operationId } };
    if (outcome === "failed") {
      await assert.rejects(dispatcher.onServerControlOutboxCreated(event), (error) => error === failure);
    } else {
      assert.equal((await dispatcher.onServerControlOutboxCreated(event)).outcome, "rejected");
    }
    assert.equal(invocations, 1);
    assert.deepEqual(log.lines, [{
      level: "error", message: "servers.dispatch",
      payload: { source: "trigger", operationId, kind: "memberJoined", outcome, pages: 0, processed: 0, code },
    }]);
    assert.equal(JSON.stringify(log.lines).includes("clubs/x"), false);
  }
});

test("Registration: the trigger reports missing and unsupported documents without calling a worker", async () => {
  let invocations = 0;
  const documents = new Map([[`${OUTBOX_COLLECTION}/${"c".repeat(64)}`, { schemaVersion: 1, kind: "sessionEnd", status: "failed" }]]);
  const log = recordingLog();
  const dispatcher = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents, workers: { sessionEnd: async () => { invocations += 1; } } }), log,
  });
  assert.equal((await dispatcher.onServerControlOutboxCreated({ params: { operationId: "../x" } })).outcome, "unsupported");
  assert.equal((await dispatcher.onServerControlOutboxCreated({})).outcome, "unsupported");
  assert.equal((await dispatcher.onServerControlOutboxCreated({ params: { operationId: "d".repeat(64) } })).outcome, "missing");
  assert.equal((await dispatcher.onServerControlOutboxCreated({ params: { operationId: "c".repeat(64) } })).outcome, "unsupported");
  assert.equal(invocations, 0);
  assert.deepEqual(log.lines.map((line) => line.level), ["warn", "warn", "info", "info"]);
});

test("Registration: the trigger loop stops at a stalled document, at its page budget and at its time budget", async () => {
  const operationId = "e".repeat(64);
  const key = `${OUTBOX_COLLECTION}/${operationId}`;
  // A worker that reports remaining work without visibly advancing the job
  // (a lease race, a settled no-op) stops the loop after one page.
  let documents = new Map([[key, convergenceJob({ operationId, rtcStatus: "pending", rtcTargets: [{}], rtcTargetIndex: 0 })]]);
  let stalled = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents, workers: { convergence: async () => ({ cleanupPending: true, processed: 0 }) } }),
    log: recordingLog(),
  });
  assert.deepEqual(await stalled.onServerControlOutboxCreated({ params: { operationId } }), {
    source: "trigger", operationId, kind: "memberJoined", outcome: "stalled", pages: 1, processed: 0, code: null,
  });
  // A worker that keeps advancing the job yields to the schedule at the page budget.
  documents = new Map([[key, convergenceJob({ operationId, rtcStatus: "pending", rtcTargets: [{}, {}, {}, {}, {}], rtcTargetIndex: 0 })]]);
  const advancing = async () => {
    const current = documents.get(key);
    documents.set(key, { ...current, rtcTargetIndex: current.rtcTargetIndex + 1 });
    return { cleanupPending: true, processed: 3 };
  };
  const budgeted = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents, workers: { convergence: advancing } }), log: recordingLog(), triggerMaxPages: 2,
  });
  assert.deepEqual(await budgeted.onServerControlOutboxCreated({ params: { operationId } }), {
    source: "trigger", operationId, kind: "memberJoined", outcome: "exhausted", pages: 2, processed: 6, code: null,
  });
  // The wall-clock budget ends a loop that could still page.
  let ticks = 0;
  const clock = () => NOW + (ticks++ > 2 ? DEFAULT_DISPATCH_LIMITS.timeBudgetMs : 0);
  const timed = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents, workers: { convergence: advancing }, clock }), log: recordingLog(),
  });
  const report = await timed.onServerControlOutboxCreated({ params: { operationId } });
  assert.equal(report.outcome, "exhausted");
  assert.equal(report.pages, 1);
  // Deferred outcomes are reported verbatim and never repaired.
  documents = new Map([[key, convergenceJob({ operationId, rtcStatus: "recoveryRequired", rtcTargets: [{}], rtcTargetIndex: 0 })]]);
  const recovery = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents, workers: { convergence: async () => ({ cleanupPending: true, recoveryRequired: true, processed: 1 }) } }),
    log: recordingLog(),
  });
  assert.equal((await recovery.onServerControlOutboxCreated({ params: { operationId } })).outcome, "recoveryRequired");
  const content = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents, workers: { convergence: async () => ({
      cleanupPending: true, contentCleanupPending: true, rtcCleanupPending: false, processed: 0,
    }) } }),
    log: recordingLog(),
  });
  assert.equal((await content.onServerControlOutboxCreated({ params: { operationId } })).outcome, "contentCleanupPending");
});

test("Registration: a worker result without a work-remaining boolean is refused, never completed", async () => {
  const operationId = "f".repeat(64);
  const key = `${OUTBOX_COLLECTION}/${operationId}`;
  // Every reviewed worker states its page with a boolean. Anything else — a
  // stub, a renamed field, a truthy-but-not-boolean value — is uncertain work,
  // and uncertain work is never completed.
  for (const result of [undefined, null, {}, { processed: 1 }, { cleanupPending: "false" }, { cleanupPending: 0 }]) {
    const documents = new Map([[key, convergenceJob({ operationId })]]);
    const log = recordingLog();
    const dispatcher = createServersV1Dispatcher({
      runtime: fakeRuntime({ documents, workers: { convergence: async () => result } }), log,
    });
    const report = await dispatcher.onServerControlOutboxCreated({ params: { operationId } });
    const label = JSON.stringify(result ?? null);
    assert.equal(report.outcome, "rejected", label);
    assert.equal(report.code, "invalid-worker-result", label);
    assert.equal(report.kind, "memberJoined", label);
    assert.equal(report.pages, 1, label);
    // Refusing is not repairing: the job is left exactly as it was found.
    assert.deepEqual(documents.get(key), convergenceJob({ operationId }), label);
    assert.deepEqual(log.lines.map((line) => line.level), ["error"], label);
    assert.equal(log.lines[0].payload.code, "invalid-worker-result", label);
  }
  // The projection worker reports completion positively instead, and a missing
  // `propagationComplete` is refused for the same reason.
  const projectionDocuments = new Map([[key, { schemaVersion: 1, kind: "serverMetadata", status: "pending" }]]);
  const projection = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents: projectionDocuments, workers: { projection: async () => ({ processed: 2 }) } }),
    log: recordingLog(),
  });
  const projected = await projection.onServerControlOutboxCreated({ params: { operationId } });
  assert.equal(projected.outcome, "rejected");
  assert.equal(projected.code, "invalid-worker-result");
  // ...while the boolean the reviewed workers do return still completes.
  const settled = createServersV1Dispatcher({
    runtime: fakeRuntime({ documents: projectionDocuments, workers: { projection: async () => ({ propagationComplete: true }) } }),
    log: recordingLog(),
  });
  assert.equal((await settled.onServerControlOutboxCreated({ params: { operationId } })).outcome, "completed");
});

test("Registration: a job another lease holder settles mid-invocation is reported busy, not completed", async () => {
  // A busy page is what both reviewed workers return when they find the job
  // under someone else's lease: nothing written, work still remaining
  // (servers/session_control.js, servers/convergence_runtime.js). If that
  // holder finishes while this page runs, the completion is theirs, not this
  // invocation's, and reporting it as `completed` would credit a lost race
  // with work it never did.
  const operationId = "9".repeat(64);
  const key = `${OUTBOX_COLLECTION}/${operationId}`;
  const documents = new Map([[key, convergenceJob({ operationId })]]);
  const log = recordingLog();
  const dispatcher = createServersV1Dispatcher({
    runtime: fakeRuntime({
      documents,
      workers: { convergence: async () => {
        documents.set(key, { ...documents.get(key), status: "completed" });
        return { cleanupPending: true, processed: 0 };
      } },
    }),
    log,
  });
  assert.deepEqual(await dispatcher.onServerControlOutboxCreated({ params: { operationId } }), {
    source: "trigger", operationId, kind: "memberJoined", outcome: "busy", pages: 1, processed: 0, code: null,
  });
  // Deferred, not a failure: the schedule needs no error line to revisit it.
  assert.deepEqual(log.lines.map((line) => line.level), ["info"]);
  // A redelivery that finds the job completed without running a page is a
  // plain completion: `busy` describes this invocation's own race, nothing else.
  const redelivered = await dispatcher.onServerControlOutboxCreated({ params: { operationId } });
  assert.equal(redelivered.outcome, "completed");
  assert.equal(redelivered.pages, 0);

  // The same race on the session end the finding named.
  const endId = "8".repeat(64);
  const endKey = `${OUTBOX_COLLECTION}/${endId}`;
  const endJob = { schemaVersion: 1, kind: "sessionEnd", status: "pending", cursor: null, leaseId: null, leaseExpiresAtMillis: 0 };
  const endDocuments = new Map([[endKey, endJob]]);
  const endLog = recordingLog();
  const endDispatcher = createServersV1Dispatcher({
    runtime: fakeRuntime({
      documents: endDocuments,
      workers: { sessionEnd: async () => {
        endDocuments.set(endKey, { ...endDocuments.get(endKey), status: "completed" });
        return { cleanupPending: true, processed: 0 };
      } },
    }),
    log: endLog,
  });
  const ended = await endDispatcher.onServerControlOutboxCreated({ params: { operationId: endId } });
  assert.equal(ended.outcome, "busy");
  assert.equal(ended.kind, "sessionEnd");
  assert.equal(endLog.lines.at(-1).payload.outcome, "busy");

  // A holder that is still holding is still reported as the lease it is.
  const leasedId = "7".repeat(64);
  const leasedKey = `${OUTBOX_COLLECTION}/${leasedId}`;
  const leasedDocuments = new Map([[leasedKey, convergenceJob({ operationId: leasedId })]]);
  const leased = createServersV1Dispatcher({
    runtime: fakeRuntime({
      documents: leasedDocuments,
      workers: { convergence: async () => {
        leasedDocuments.set(leasedKey, {
          ...leasedDocuments.get(leasedKey), bridgeLeaseId: "other-instance", bridgeLeaseExpiresAtMillis: NOW + 30_000,
        });
        return { cleanupPending: true, processed: 0 };
      } },
    }),
    log: recordingLog(),
  });
  assert.equal((await leased.onServerControlOutboxCreated({ params: { operationId: leasedId } })).outcome, "leased");
});

/*
|--------------------------------------------------------------------------
| 3. Real factories against the explicitly selected localhost emulator
|--------------------------------------------------------------------------
*/

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const projectId = "demo-yovoice-servers-registration";
let db;
let app;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp({ projectId }, `servers-registration-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });
const emulatorTest = (name, fn) => test(`Registration: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator.",
}, fn);

const creationInput = (overrides = {}) => ({
  requestId: randomUUID(), serverType: "community", templateVersion: 1, name: "Registered server",
  description: "", privacy: "public", defaultLanguage: "English", ...overrides,
});

async function fixture() {
  let nowMs = NOW;
  const clock = () => nowMs;
  const calls = { minted: [], removed: [], ended: [] };
  // Deterministic provider-control seam, the same one the convergence suite
  // uses: these tests prove dispatch and binding, not Cloud connectivity.
  const livekit = {
    assertSupported() {},
    async mintToken(value) {
      calls.minted.push(value);
      const token = `test-only-${randomUUID()}`;
      return {
        serverUrl: "wss://test-fixture.livekit.cloud", token, participantToken: token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid, participantName: value.participantName,
        expiresAtMillis: nowMs + 300_000,
        permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources, sessionRole: value.sessionRole,
        serverId: value.binding.serverId, channelId: value.binding.channelId, roomId: value.binding.roomId,
        sessionId: value.binding.sessionId,
      };
    },
    async revokeParticipant(roomName, userId) {
      calls.removed.push({ roomName, userId });
      return { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 };
    },
    async endRoom(roomName) { calls.ended.push(roomName); return {}; },
    async roomOccupancy() { return { present: false, participantCount: 0 }; },
  };
  const real = createServersV1Runtime({ db, Timestamp, clock, livekit });
  const workerCalls = [];
  const runtime = {
    ...real,
    convergence: {
      processServerConvergencePage: async (input) => {
        workerCalls.push(input);
        return real.convergence.processServerConvergencePage(input);
      },
    },
  };
  const log = recordingLog();
  const functions = createServersV1Functions({ runtime, registrars: fakeRegistrars([]), log });
  const call = (name, uid, data) => functions[name].handler({
    auth: { uid, token: { email_verified: true } }, data,
    rawRequest: { headers: { "x-forged-uid": "attacker" } },
  });
  async function user(label) {
    const uid = `${label}-${randomUUID()}`;
    await db.doc(`users/${uid}`).set({ displayName: `Registration ${label}`, status: "active" });
    return uid;
  }
  async function activatedServer() {
    const owner = await user("owner");
    const created = await call("createServerV1", owner, creationInput());
    const root = db.doc(`clubs/${created.serverId}`);
    // Isolated emulator activation only. There is no shipped activation path.
    await root.update({ status: "active", serverActivationState: "active" });
    const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
    for (const anchor of anchors.docs) {
      await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: owner });
    }
    return { owner, serverId: created.serverId, root };
  }
  async function joinJob(serverId) {
    const member = await user("member");
    const requestId = randomUUID();
    const result = await call("joinServerV1", member, { serverId, requestId });
    assert.equal(result.joined, true);
    const operationId = operationIdentity("server.join.v1", member, requestId, { serverId }).id;
    const reference = db.doc(`${OUTBOX_COLLECTION}/${operationId}`);
    assert.equal((await reference.get()).data().status, "pending");
    return { member, operationId, reference };
  }
  const trigger = (operationId) => functions[TRIGGER].handler({ params: { operationId } });
  return {
    runtime, real, functions, log, calls, workerCalls, call, user, activatedServer, joinJob, trigger, clock,
    advance: (ms) => { nowMs += ms; },
  };
}

emulatorTest("createServerV1 through the registered callable writes the held server exactly as creation.js does, bound to the Auth uid", async () => {
  const f = await fixture();
  const owner = await f.user("owner");
  const data = creationInput({ serverType: "friends", privacy: "inviteOnly", defaultLanguage: "Polish" });
  const result = await f.call("createServerV1", owner, data);
  assert.deepEqual(Object.keys(result).sort(), ["alreadyExisted", "channelIds", "defaultChannelId", "serverId"]);
  assert.equal(result.alreadyExisted, false);
  // The identity comes from Auth, not from the payload, and the graph is the
  // canonical held shape of docs/Servers.md "Sessions".
  assert.equal(result.serverId, canonicalServerId(owner, data.requestId, "friends"));
  const root = (await db.doc(`clubs/${result.serverId}`).get()).data();
  assert.equal(root.serverSchemaVersion, 1);
  assert.equal(root.status, "preparing");
  assert.equal(root.serverActivationState, "held");
  assert.equal(root.ownerId, owner);
  assert.equal(root.ownerName, "Registration owner");
  assert.equal(root.memberCount, 1);
  const members = await db.collection(`clubs/${result.serverId}/members`).get();
  assert.deepEqual(members.docs.map((doc) => doc.id), [owner]);
  const anchors = await db.collection("rooms").where("serverId", "==", result.serverId).get();
  assert.ok(anchors.size > 0);
  for (const anchor of anchors.docs) {
    const room = anchor.data();
    assert.equal(room.status, "preparing");
    assert.equal(room.serverActivationState, "held");
    assert.equal(room.visibility, "private");
    assert.equal(room.isLive, false);
    assert.equal(room.hostId, null);
    assert.equal(room.serverOwnerId, owner);
  }
  // Replaying the same request through the boundary and through the raw
  // factory recovers the same graph: nothing was added or renamed on the way.
  const replayed = await f.call("createServerV1", owner, data);
  assert.deepEqual(replayed, { ...result, alreadyExisted: true });
  const raw = await f.real.creation.createServerV1(request(owner, data));
  assert.deepEqual(raw, { ...result, alreadyExisted: true });
  assert.equal(f.log.lines.length, 0);
});

emulatorTest("denied paths keep the factories' structured codes: unauthenticated, invalid-argument and permission-denied", async () => {
  const f = await fixture();
  const owner = await f.user("owner");
  const stranger = await f.user("stranger");
  await rejects(f.functions.createServerV1.handler({ data: creationInput() }), "unauthenticated");
  // An unlisted field is refused as a whole; nothing is written for it.
  const forged = creationInput({ ownerId: stranger });
  await rejects(f.call("createServerV1", owner, forged), "invalid-argument");
  assert.equal((await db.doc(`clubs/${canonicalServerId(owner, forged.requestId, "community")}`).get()).exists, false);
  await rejects(f.call("createServerV1", owner, creationInput({ templateVersion: 2 })), "invalid-argument");
  const created = await f.call("createServerV1", owner, creationInput());
  const patch = { requestId: randomUUID(), expectedRevision: 1, patch: { name: "Renamed by a stranger" } };
  // A held private target and a missing one deny identically: authorization
  // precedes existence disclosure.
  await rejects(f.call("updateServerV1", stranger, { serverId: created.serverId, ...patch }), "permission-denied");
  await rejects(f.call("updateServerV1", stranger, { serverId: "missing-server", ...patch }), "permission-denied");
  await rejects(f.call("joinServerV1", stranger, { serverId: created.serverId, requestId: randomUUID() }), "permission-denied");
  assert.equal((await db.doc(`clubs/${created.serverId}`).get()).data().name, "Registered server");
  assert.equal(f.log.lines.length, 0);
});

emulatorTest("the outbox trigger drives a real memberJoined job through the reviewed runtime to completion, once", async () => {
  const f = await fixture();
  const { serverId } = await f.activatedServer();
  const { operationId, reference } = await f.joinJob(serverId);
  const line = await f.trigger(operationId);
  assert.deepEqual(line, {
    source: "trigger", operationId, kind: "memberJoined", outcome: "completed", pages: 1, processed: 0, code: null,
  });
  assert.deepEqual(f.workerCalls, [{ operationId }]);
  const settled = (await reference.get()).data();
  assert.equal(settled.status, "completed");
  assert.equal(settled.bridgeLeaseId, null);
  // Redelivery of the same event is a read-only no-op.
  assert.equal((await f.trigger(operationId)).outcome, "completed");
  assert.equal(f.workerCalls.length, 1);
  assert.deepEqual(f.log.lines.map((entry) => [entry.level, entry.message]), [
    ["info", "servers.dispatch"], ["info", "servers.dispatch"],
  ]);
});

emulatorTest("the trigger respects the worker's lease and retry hint and never touches the job itself", async () => {
  const f = await fixture();
  const { serverId } = await f.activatedServer();
  const leased = await f.joinJob(serverId);
  await leased.reference.update({ bridgeLeaseId: `lease-${randomUUID()}`, bridgeLeaseExpiresAtMillis: f.clock() + 60_000 });
  const before = (await leased.reference.get()).data();
  assert.equal((await f.trigger(leased.operationId)).outcome, "leased");
  assert.deepEqual((await leased.reference.get()).data(), before);
  assert.equal(f.workerCalls.length, 0);
  f.advance(60_001);
  assert.equal((await f.trigger(leased.operationId)).outcome, "completed");
  assert.equal((await leased.reference.get()).data().status, "completed");
  assert.equal(f.workerCalls.length, 1);

  const hinted = await f.joinJob(serverId);
  await hinted.reference.update({ retryAfterMillis: f.clock() + 30_000 });
  assert.equal((await f.trigger(hinted.operationId)).outcome, "backoff");
  assert.equal(f.workerCalls.length, 1);
  f.advance(30_000);
  assert.equal((await f.trigger(hinted.operationId)).outcome, "completed");
  assert.equal(f.workerCalls.length, 2);
});

emulatorTest("the schedule sweeps pending jobs from a random start with one wrap-around and reports counts", async () => {
  const f = await fixture();
  const { serverId } = await f.activatedServer();
  const first = await f.joinJob(serverId);
  const second = await f.joinJob(serverId);
  // A start above every SHA-256 id proves the wrap-around; a start below
  // proves the direct pass. Neither needs a persisted cursor or an index.
  const sweep = (start) => createServersV1Dispatcher({ runtime: f.runtime, log: f.log, random: () => start })
    .processPendingServerControlOutbox();
  const counts = await sweep("f".repeat(64));
  assert.equal(counts.completed >= 2, true);
  assert.equal(counts.scanned, counts.completed + counts.deferred + counts.rejected + counts.failed + counts.unsupported);
  assert.equal(counts.hasMore, false);
  assert.equal((await first.reference.get()).data().status, "completed");
  assert.equal((await second.reference.get()).data().status, "completed");
  const ids = f.workerCalls.map((call) => call.operationId);
  assert.ok(ids.includes(first.operationId) && ids.includes(second.operationId));
  const third = await f.joinJob(serverId);
  const again = await sweep("0".repeat(64));
  assert.equal(again.completed >= 1, true);
  assert.equal((await third.reference.get()).data().status, "completed");
  assert.deepEqual(f.log.lines.filter((entry) => entry.message === "servers.dispatch_sweep").map((entry) => entry.payload), [counts, again]);
  // A start cursor outside the id grammar cannot silently narrow the sweep.
  await assert.rejects(
    createServersV1Dispatcher({ runtime: f.runtime, log: f.log, random: () => "not-hex" }).processPendingServerControlOutbox(),
    TypeError,
  );
});

emulatorTest("a session end the callable already settled is reported completed without a worker call", async () => {
  const f = await fixture();
  const { owner, serverId, root } = await f.activatedServer();
  const channels = await root.collection("channels").get();
  const channel = channels.docs.find((doc) => doc.data().kind === "voice") ?? channels.docs.find((doc) => doc.data().roomId);
  const started = await f.call("startServerChannelSessionV1", owner, { serverId, channelId: channel.id, requestId: randomUUID() });
  assert.equal(typeof started.sessionId, "string");
  const ended = await f.call("endServerChannelSessionV1", owner, {
    serverId, channelId: channel.id, sessionId: started.sessionId, requestId: randomUUID(),
  });
  assert.equal(ended.cleanupPending, false);
  assert.deepEqual(f.calls.ended.length, 1);
  const line = await f.trigger(ended.operationId);
  assert.equal(line.kind, "sessionEnd");
  assert.equal(line.outcome, "completed");
  assert.equal(line.pages, 0);
  assert.equal(f.workerCalls.length, 0);
  assert.equal((await db.doc(`${OUTBOX_COLLECTION}/${ended.operationId}`).get()).data().status, "completed");
});

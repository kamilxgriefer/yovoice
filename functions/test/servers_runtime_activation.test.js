"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const { HttpsError } = require("firebase-functions/v2/https");
const {
  ACTIVATION_CONFIG_PATH,
  ACTIVATION_UNAVAILABLE_REASON,
  SERVER_CALLABLE_METHODS,
  canonicalActivationConfig,
  createServersV1ActivationGate,
  createServersV1Functions,
} = require("../servers/registration");

function config(overrides = {}) {
  return { schemaVersion: 1, callableAccess: "disabled", testerUids: [],
    workersEnabled: false, revision: 1, ...overrides };
}

function memoryDb(state) {
  const snapshot = (path) => {
    if (state.error) throw state.error;
    const data = state.documents.get(path);
    return { exists: data !== undefined, data: () => data };
  };
  return {
    doc: (path) => ({ get: async () => snapshot(path) }),
    collection: (name) => ({
      doc: (id) => ({ get: async () => snapshot(`${name}/${id}`) }),
    }),
  };
}

function recordingLog() {
  const lines = [];
  const record = (level) => (message, payload) => lines.push({ level, message, payload });
  return { lines, info: record("info"), warn: record("warn"), error: record("error") };
}

function registrars() {
  const register = (options, handler) => ({ options, handler });
  return { onCall: register, onDocumentCreated: register, onSchedule: register };
}

function runtime(db, calls) {
  const services = {};
  for (const [name, service] of Object.entries(SERVER_CALLABLE_METHODS)) {
    (services[service] ??= {})[name] = async () => { calls.push(name); return { name }; };
  }
  services.familyMemories.expireServerFamilyMemoryUploadReservations = async () => ({ processed: 0, hasMore: false, expired: [] });
  services.familyMemories.processPendingFamilyMemoryDeletionJobs = async () => ({ processed: 0, hasMore: false, completed: [] });
  services.companyFiles.expireServerCompanyFileUploadReservations = async () => ({ processed: 0, hasMore: false, expired: [] });
  services.companyFiles.processPendingCompanyFileDeletionJobs = async () => ({ processed: 0, hasMore: false, completed: [] });
  return {
    db, FieldPath: { documentId: () => "__name__" }, clock: () => 1_900_000_000_000, ...services,
    projection: { processServerControlOutboxPage: async () => ({ propagationComplete: true }) },
    convergence: { processServerConvergencePage: async () => ({ cleanupPending: false }) },
    sessionControl: { processServerSessionEndPage: async () => ({ cleanupPending: false }) },
    staleness: { stageStaleServerChannelSessions: async () => {
      calls.push("staleness");
      return { scanned: 0, truncated: false, skippedLegacy: 0, skippedUnbound: 0,
        skippedYoung: 0, skippedOccupied: 0, providerUnavailable: 0, changed: 0, staged: [] };
    } },
  };
}

const withCode = (code) => (error) => error instanceof HttpsError && error.code === code;
const withActivationReason = (error) =>
  error instanceof HttpsError &&
  error.code === "failed-precondition" &&
  error.details?.reason === ACTIVATION_UNAVAILABLE_REASON;

test("runtime activation configuration is exact and absent means disabled", () => {
  assert.deepEqual(canonicalActivationConfig({ exists: false }), {
    schemaVersion: 1, callableAccess: "disabled", testerUids: [], workersEnabled: false, revision: 0,
  });
  assert.deepEqual(canonicalActivationConfig({ exists: true, data: () => config({
    callableAccess: "testers", testerUids: ["tester-a"], workersEnabled: true,
  }) }), config({ callableAccess: "testers", testerUids: ["tester-a"], workersEnabled: true }));
  for (const malformed of [
    { ...config(), extra: true },
    config({ schemaVersion: 2 }),
    config({ callableAccess: "enabled" }),
    config({ callableAccess: "all", testerUids: ["stale-tester"] }),
    config({ callableAccess: "testers", testerUids: ["same", "same"] }),
    config({ revision: 0 }),
  ]) assert.throws(() => canonicalActivationConfig({ exists: true, data: () => malformed }));
});

test("runtime gate is fail-closed, cohort-bound and uncached", async () => {
  const state = { documents: new Map() };
  const gate = createServersV1ActivationGate({ db: memoryDb(state), log: recordingLog() });
  await assert.rejects(gate.requireCallable("tester-a"), withActivationReason);
  assert.equal(await gate.workersEnabled(), false);

  state.documents.set(ACTIVATION_CONFIG_PATH, config({
    callableAccess: "testers", testerUids: ["tester-a"], workersEnabled: true,
  }));
  assert.equal((await gate.requireCallable("tester-a")).callableAccess, "testers");
  await assert.rejects(gate.requireCallable("tester-b"), withActivationReason);
  assert.equal(await gate.workersEnabled(), true);

  state.documents.set(ACTIVATION_CONFIG_PATH, config({ callableAccess: "all", revision: 2 }));
  assert.equal((await gate.requireCallable("tester-b")).revision, 2);
  state.error = Object.assign(new Error("offline"), { code: 14 });
  await assert.rejects(gate.requireCallable("tester-a"), withCode("unavailable"));
  await assert.rejects(gate.workersEnabled(), withCode("unavailable"));
});

test("all registered callables and maintenance workers consult the runtime gate before product work", async () => {
  const state = { documents: new Map([[ACTIVATION_CONFIG_PATH, config()]]) };
  const calls = [];
  const functions = createServersV1Functions({
    runtime: runtime(memoryDb(state), calls), registrars: registrars(), log: recordingLog(),
    enablePodcastRecording: false,
  });
  const request = { auth: { uid: "tester-a", token: { email_verified: true } }, data: {} };
  await assert.rejects(functions.createServerV1.handler(request), withActivationReason);
  assert.deepEqual(calls, []);
  const paused = await functions.sweepStaleServerChannelSessionsSchedule.handler();
  assert.equal(paused.activationDisabled, true);
  assert.deepEqual(calls, []);

  state.documents.set(ACTIVATION_CONFIG_PATH, config({
    callableAccess: "testers", testerUids: ["tester-a"], workersEnabled: true, revision: 2,
  }));
  assert.deepEqual(await functions.createServerV1.handler(request), { name: "createServerV1" });
  await functions.sweepStaleServerChannelSessionsSchedule.handler();
  assert.deepEqual(calls, ["createServerV1", "staleness"]);
});

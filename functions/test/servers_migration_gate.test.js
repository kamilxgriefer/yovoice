"use strict";

// The old-client gate's data contract and evaluator. Pure: no SDK, no
// emulator, no clock. The rules half of the same gate (that a migrated root
// really does deny the installed client's bare orderBy('position') query) is
// proven against a live emulator by firestore-tests/server_rules.test.js.

const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  CLIENT_GATE_ID, CLIENT_GATE_PATH, CLIENT_PLATFORMS,
  assessClientGate, canonicalClientGate, clientMeetsGate, evaluateClientCensus,
} = require("../servers/migration_gate");

const ATTESTOR = "gate-attestor-uid-3a91";
const FLOORS = Object.fromEntries(CLIENT_PLATFORMS.map((platform) => [platform, 42]));

function snapshot(data) {
  return data === null ? { exists: false, data: () => undefined } : { exists: true, data: () => data };
}

function gateData(changes = {}) {
  return {
    schemaVersion: 1, gateId: CLIENT_GATE_ID, minimumClientVersion: "1.9.0",
    minimumClientBuild: 42, platformMinimumBuild: { ...FLOORS },
    status: "satisfied", attestedBy: ATTESTOR, attestedAt: new Date(1_800_000_000_000),
    revision: 7, updatedAt: new Date(1_800_000_000_000), ...changes,
  };
}

const rejects = (fn, code) => assert.throws(fn, (error) => error.code === code);

// A census that actually observes something on every platform the gate pins a
// floor on. Anything less is "unknown", not "none" — see the empty-census
// tests below and evaluateClientCensus.
function fullCensus(build = 42, sessions = 200) {
  return CLIENT_PLATFORMS.map((platform) => ({ platform, build, sessions }));
}

test("the gate path is the one the apply engine and Rules both name", () => {
  assert.equal(CLIENT_GATE_PATH, `serverMigrationGates/${CLIENT_GATE_ID}`);
  assert.equal(CLIENT_GATE_PATH.split("/").length, 2);
});

test("a canonical published gate round-trips every field", () => {
  const gate = canonicalClientGate(snapshot(gateData()));
  assert.equal(gate.minimumClientBuild, 42);
  assert.equal(gate.minimumClientVersion, "1.9.0");
  assert.equal(gate.status, "satisfied");
  assert.equal(gate.revision, 7);
  assert.equal(gate.attestedBy, ATTESTOR);
  assert.deepEqual(Object.keys(gate.platformMinimumBuild).sort(), [...CLIENT_PLATFORMS].sort());
});

test("an absent or malformed gate is an OPEN gate, never an absent constraint", () => {
  rejects(() => canonicalClientGate(snapshot(null)), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ schemaVersion: 2 }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ gateId: "other" }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ minimumClientVersion: "1.9" }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ minimumClientBuild: 0 }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ minimumClientBuild: 1.5 }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ status: "closed" }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ revision: -1 }))), "failed-precondition");
});

test("a satisfied gate must be attributed, and an open one must not be", () => {
  rejects(() => canonicalClientGate(snapshot(gateData({ attestedBy: null }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ attestedAt: null }))), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({ status: "open" }))), "failed-precondition");
  const open = canonicalClientGate(snapshot(gateData({ status: "open", attestedBy: null, attestedAt: null })));
  assert.equal(open.status, "open");
  assert.equal(open.attestedBy, null);
});

test("every platform needs a floor and no platform floor may sit below the gate minimum", () => {
  const missing = gateData();
  delete missing.platformMinimumBuild.web;
  rejects(() => canonicalClientGate(snapshot(missing)), "failed-precondition");
  rejects(() => canonicalClientGate(snapshot(gateData({
    platformMinimumBuild: { ...FLOORS, android: 41 },
  }))), "failed-precondition");
  // A STRICTER platform floor is legitimate: a platform can require more.
  const strict = canonicalClientGate(snapshot(gateData({
    platformMinimumBuild: { ...FLOORS, ios: 99 },
  })));
  assert.equal(strict.platformMinimumBuild.ios, 99);
});

test("a client claim is compatible only on a known platform at or above its floor", () => {
  const gate = canonicalClientGate(snapshot(gateData({ platformMinimumBuild: { ...FLOORS, ios: 99 } })));
  assert.equal(clientMeetsGate(gate, { platform: "android", build: 42 }), true);
  assert.equal(clientMeetsGate(gate, { platform: "android", build: 41 }), false);
  assert.equal(clientMeetsGate(gate, { platform: "ios", build: 42 }), false);
  assert.equal(clientMeetsGate(gate, { platform: "ios", build: 99 }), true);
  // No benefit of the doubt for anything unrecognisable.
  assert.equal(clientMeetsGate(gate, { platform: "fuchsia", build: 10_000 }), false);
  assert.equal(clientMeetsGate(gate, { platform: "web", build: "42" }), false);
  assert.equal(clientMeetsGate(gate, { platform: "web", build: 42.5 }), false);
  assert.equal(clientMeetsGate(gate, null), false);
  assert.equal(clientMeetsGate(gate, []), false);
});

test("an absent census is UNKNOWN, never zero", () => {
  const gate = canonicalClientGate(snapshot(gateData()));
  const observed = evaluateClientCensus(gate, null);
  assert.equal(observed.supplied, false);
  assert.equal(observed.incompatibleSessions, null);
  const assessment = assessClientGate({ snapshot: snapshot(gateData()), expectedRevision: 7, census: null });
  assert.equal(assessment.satisfied, false);
  assert.deepEqual(assessment.reasons, ["client-compatibility-census-not-supplied"]);
});

test("a census counts incompatible sessions and names their platforms", () => {
  const gate = canonicalClientGate(snapshot(gateData()));
  // Every platform the gate pins a floor on is observed, or the census is
  // "unknown" before any counting happens (see the empty-census test).
  const observed = evaluateClientCensus(gate, [
    { platform: "android", build: 42, sessions: 900 },
    { platform: "ios", build: 41, sessions: 17 },
    { platform: "web", build: 40, sessions: 3 },
    { platform: "macos", build: 50, sessions: 5 },
    { platform: "windows", build: 42, sessions: 2 },
    { platform: "linux", build: 42, sessions: 1 },
  ]);
  assert.equal(observed.compatibleSessions, 908);
  assert.equal(observed.incompatibleSessions, 20);
  assert.deepEqual(observed.platforms, ["ios", "web"]);
  assert.deepEqual(observed.observedPlatforms, [...CLIENT_PLATFORMS].sort());
});

test("a session on an unknown platform is counted as incompatible, not skipped", () => {
  const gate = canonicalClientGate(snapshot(gateData()));
  const observed = evaluateClientCensus(gate, [
    ...fullCensus(42, 10), { platform: "tizen", build: 999, sessions: 4 },
  ]);
  assert.equal(observed.incompatibleSessions, 4);
  assert.equal(observed.compatibleSessions, 60);
  // An unknown platform never joins the observed-coverage set either: a
  // census of nothing but unknown platforms observes nothing.
  assert.deepEqual(observed.platforms, []);
  assert.deepEqual(observed.observedPlatforms, [...CLIENT_PLATFORMS].sort());
  assert.equal(evaluateClientCensus(gate, [{ platform: "tizen", build: 999, sessions: 4 }]).supplied, false);
});

test("the assessment refuses on an unsatisfied gate, a revision drift and a live old cohort", () => {
  const open = assessClientGate({
    snapshot: snapshot(gateData({ status: "open", attestedBy: null, attestedAt: null })),
    expectedRevision: 7, census: fullCensus(),
  });
  assert.deepEqual(open.reasons, ["client-compatibility-gate-not-satisfied"]);

  const drifted = assessClientGate({
    snapshot: snapshot(gateData({ revision: 8 })), expectedRevision: 7, census: fullCensus(),
  });
  assert.deepEqual(drifted.reasons, ["client-compatibility-gate-revision-mismatch"]);

  const cohort = assessClientGate({
    snapshot: snapshot(gateData()), expectedRevision: 7,
    census: [...fullCensus(), { platform: "android", build: 41, sessions: 1 }],
  });
  assert.deepEqual(cohort.reasons, ["incompatible-client-cohort-observed"]);
  assert.equal(cohort.observed.incompatibleSessions, 1);

  const clean = assessClientGate({
    snapshot: snapshot(gateData()), expectedRevision: 7, census: fullCensus(42, 1200),
  });
  assert.equal(clean.satisfied, true);
  assert.deepEqual(clean.reasons, []);
});

// P1-2 / F1. `[]` used to be read as SUPPLIED and satisfied the gate with
// literally zero observations; a census of all-zero rows did the same. The
// gate that exists to stop every installed client losing its channel list
// passed by the ABSENCE of evidence. Both are "unknown" now, and both refuse
// through the reason that already existed for an absent census.
test("an empty, all-zero or partially covering census is UNKNOWN and refuses, exactly as an absent one does", () => {
  const gate = canonicalClientGate(snapshot(gateData()));
  for (const census of [
    [],
    CLIENT_PLATFORMS.map((platform) => ({ platform, build: 41, sessions: 0 })),
    CLIENT_PLATFORMS.map((platform) => ({ platform, build: 99, sessions: 0 })),
    [{ platform: "android", build: 42, sessions: 1200 }],
    fullCensus().slice(1),
    fullCensus().map((entry, index) => (index === 0 ? { ...entry, sessions: 0 } : entry)),
  ]) {
    const observed = evaluateClientCensus(gate, census);
    assert.equal(observed.supplied, false, JSON.stringify(census));
    assert.equal(observed.incompatibleSessions, null);
    assert.equal(observed.compatibleSessions, null);
    const assessed = assessClientGate({ snapshot: snapshot(gateData()), expectedRevision: 7, census });
    assert.equal(assessed.satisfied, false, JSON.stringify(census));
    assert.deepEqual(assessed.reasons, ["client-compatibility-census-not-supplied"]);
  }
  // The control case is unchanged: a census absent entirely still refuses.
  assert.deepEqual(
    assessClientGate({ snapshot: snapshot(gateData()), expectedRevision: 7, census: null }).reasons,
    ["client-compatibility-census-not-supplied"],
  );
});

test("an unpinned revision is a closed gate and a malformed census is refused", () => {
  const unpinned = assessClientGate({ snapshot: snapshot(gateData()), expectedRevision: null, census: fullCensus() });
  assert.equal(unpinned.satisfied, false);
  assert.deepEqual(unpinned.reasons, ["client-compatibility-gate-revision-required"]);
  for (const expectedRevision of [undefined, 0, -1, 1.5, "7"]) {
    assert.deepEqual(
      assessClientGate({ snapshot: snapshot(gateData()), expectedRevision, census: fullCensus() }).reasons,
      ["client-compatibility-gate-revision-required"],
    );
  }
  const gate = canonicalClientGate(snapshot(gateData()));
  rejects(() => evaluateClientCensus(gate, "none"), "failed-precondition");
  rejects(() => evaluateClientCensus(gate, [{ platform: "web", build: 42, sessions: -1 }]), "failed-precondition");
  rejects(() => evaluateClientCensus(gate, [null]), "failed-precondition");
});

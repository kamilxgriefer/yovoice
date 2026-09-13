"use strict";

// Independent QA for the migration-engine remediations of ADR-189 and for
// ADR-188's enforcement point inside the engine. Pure: no SDK, no emulator, no
// clock, no network — every assertion is a pure-function result or a direct
// reading of an exported registry.
//
// This file deliberately does NOT re-test the engine's stage machinery, which
// servers_migration_apply.test.js proves against a live emulator. It tests the
// three properties the audit found stated but not enforced:
//
//   P1-2 / F1 an empty or all-zero census satisfied the old-client gate;
//   F2       a bound room's cover was stranded, unprobed and unrefused;
//   F3       "write mode is emulator-only" was a caller ASSERTION;
//   F4       ADR-F was the only load-bearing blocker with no flag;
//   F5       `rootPostImage` was called with a hardcoded sourceKind.
//
// P1-1 (bound rooms discovered by forward pointer only) is a transactional
// read and is therefore proven in the emulator file, not here; what IS pinned
// here is the registry entry that makes its stranded-cover half refusable.
// The behavioural proof is in servers_migration_apply.test.js — "the fixture
// is genuinely pointer-blind", "a live, history-bearing room bound only by
// clubId defers its root", "apply mode … writes nothing for a pointer-blind
// root" and "an idle, history-free bound room found only by the back-pointer
// does not block its root". The source-text checks below are a tripwire for a
// refactor, not evidence that the query runs (ADR-007).

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { test } = require("node:test");

const {
  STRANDED_IF_NON_EMPTY, V1_CLIENT_READ_PATHS, V1_MANAGEMENT_CAPABILITIES,
  channelPostImage, createLegacyMigrationApplyEngine, familyMigrationAllowed,
  managementParityExists, rootPostImage,
} = require("../servers/migration_apply");
const { CLIENT_PLATFORMS, assessClientGate, evaluateClientCensus, canonicalClientGate } = require("../servers/migration_gate");

const APPLY_SOURCE = path.join(__dirname, "..", "servers", "migration_apply.js");
const throwsCode = (fn, code) => assert.throws(fn, (error) => error.code === code);

const firestore = { collection: () => ({}), doc: () => ({}), runTransaction: async () => {} };
const Timestamp = { fromMillis: (millis) => ({ millis }) };

function gate(changes = {}) {
  return {
    exists: true,
    data: () => ({
      schemaVersion: 1, gateId: "clientCompatibilityV1", minimumClientVersion: "1.9.0",
      minimumClientBuild: 42,
      platformMinimumBuild: Object.fromEntries(CLIENT_PLATFORMS.map((platform) => [platform, 42])),
      status: "satisfied", attestedBy: "qa-attestor-uid", attestedAt: new Date(1_800_000_000_000),
      revision: 7, updatedAt: new Date(1_800_000_000_000), ...changes,
    }),
  };
}

const fullCensus = (sessions = 25) => CLIENT_PLATFORMS.map((platform) => ({ platform, build: 42, sessions }));

test("QA census: zero observations never becomes an observation of zero", () => {
  const canonical = canonicalClientGate(gate());
  // The whole point: `null` and `[]` must give the SAME answer, because they
  // are the same statement — nobody looked.
  const absent = evaluateClientCensus(canonical, null);
  const empty = evaluateClientCensus(canonical, []);
  assert.equal(absent.supplied, empty.supplied);
  assert.equal(absent.incompatibleSessions, empty.incompatibleSessions);
  assert.equal(empty.supplied, false);
  // A complete statement that every platform is below the floor with zero
  // measured sessions is the sharpest case: it is not "no incompatible users".
  const allZero = CLIENT_PLATFORMS.map((platform) => ({ platform, build: 1, sessions: 0 }));
  assert.equal(evaluateClientCensus(canonical, allZero).supplied, false);
  // Partial coverage says nothing about the platforms it omits.
  assert.equal(evaluateClientCensus(canonical, fullCensus().slice(2)).supplied, false);
  // And the gate reports the refusal, with no other reason invented.
  for (const census of [null, [], allZero, fullCensus().slice(2)]) {
    const assessed = assessClientGate({ snapshot: gate(), expectedRevision: 7, census });
    assert.equal(assessed.satisfied, false);
    assert.deepEqual(assessed.reasons, ["client-compatibility-census-not-supplied"]);
  }
  // A real census still passes, so the fix is a refusal and not a wall.
  assert.equal(assessClientGate({ snapshot: gate(), expectedRevision: 7, census: fullCensus() }).satisfied, true);
});

test("QA stranding: a bound room's cover is a refusable resource, consuming the roomAnchor flag", () => {
  const entry = STRANDED_IF_NON_EMPTY.find((item) => item.resource === "boundRoomArtwork");
  assert.ok(entry, "boundRoomArtwork must be a probed stranded resource");
  assert.equal(entry.capability, "roomAnchor");
  assert.equal(entry.reason, "bound-room-artwork-would-lose-its-read-path");
  // The flag it reads must be false, or the refusal is dead code.
  assert.equal(V1_CLIENT_READ_PATHS.roomAnchor, false);
  // Every entry's capability must exist in the registry — a typo would make a
  // refusal silently unreachable, which is the failure class this fixes.
  for (const item of STRANDED_IF_NON_EMPTY) {
    assert.equal(typeof V1_CLIENT_READ_PATHS[item.capability], "boolean", item.resource);
  }
  // And the probe really counts it: the counter is declared, not incidental.
  const source = fs.readFileSync(APPLY_SOURCE, "utf8");
  assert.ok(source.includes("observed.boundRoomArtwork += 1"),
    "probeStrandedResources must count a bound room's imageUrl");
  assert.ok(source.includes('.where("clubId", "==", mapping.provenance.sourceId)'),
    "readBoundRooms must enumerate by the clubId back-pointer, as the Rules and the deletion sweep do");
  assert.ok(source.includes("club_lounge_${mapping.provenance.sourceId}"),
    "readBoundRooms must include the lazy lounge fallback clubs/deletion.js asserts is a real state");
});

test("QA write mode: apply is refused unless the emulator host and the project are OBSERVED, not asserted", () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const build = (overrides) => createLegacyMigrationApplyEngine({
    firestore, Timestamp, projectId: "demo-yovoice-qa", emulator: true, mode: "apply", ...overrides,
  });
  try {
    // A caller asserting `emulator: true` against a real project id, or with
    // no emulator host at all, is exactly the future caller this guards.
    delete process.env.FIRESTORE_EMULATOR_HOST;
    throwsCode(() => build({}), "failed-precondition");
    process.env.FIRESTORE_EMULATOR_HOST = "firestore.googleapis.com:443";
    throwsCode(() => build({}), "failed-precondition");
    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8085";
    throwsCode(() => build({ projectId: "yovoice-ec54a" }), "failed-precondition");
    throwsCode(() => build({ emulator: false }), "failed-precondition");
    // All three observations agreeing is the only way through.
    assert.equal(typeof build({}), "object");
    // Dry run is unaffected by any of it.
    delete process.env.FIRESTORE_EMULATOR_HOST;
    assert.equal(typeof createLegacyMigrationApplyEngine({
      firestore, Timestamp, projectId: "yovoice-ec54a", emulator: false, mode: "dryRun",
    }), "object");
  } finally {
    if (host === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = host;
  }
});

test("QA ADR-F: the management-parity gate sits beside the family gate and is refused from the same place", () => {
  assert.equal(managementParityExists(), true);
  assert.equal(familyMigrationAllowed(), false, "ADR-E still defers families; that has not changed");
  assert.equal(Object.values(V1_MANAGEMENT_CAPABILITIES).every((value) => value === true), true);
  const source = fs.readFileSync(APPLY_SOURCE, "utf8");
  assert.ok(source.includes('refuse("management-parity-slice-does-not-exist-yet")'));
  assert.ok(source.includes('refuse("family-migration-deferred-until-v1-rules-branches-exist")'));
  // The ADR-F refusal must be evaluated BEFORE any work that could be mistaken
  // for progress — same position ADR-E's is.
  assert.ok(source.indexOf('refuse("management-parity-slice-does-not-exist-yet")') <
    source.indexOf('refuse("family-migration-deferred-until-v1-rules-branches-exist")'));
});

test("QA provenance: rootPostImage is refused for the wrong sourceKind, so a hardcoded one cannot hide", () => {
  // A paid Club: the case that must classify away from the free allowance.
  const club = rootPostImage({
    sourceKind: "club", sourceId: "club-a", serverType: "community",
    entitlementPolicyId: "legacyCommunityPremiumV1", memberCount: 3, state: "complete",
  });
  assert.equal(club.entitlementPolicyId, "legacyCommunityPremiumV1");
  assert.equal(club.migration.sourceKind, "club");
  // An adopted room with the room policy is fine...
  const room = rootPostImage({
    sourceKind: "room", sourceId: "room-a", serverType: "community",
    entitlementPolicyId: "legacyRoomV1", memberCount: 1, state: "complete",
  });
  assert.equal(room.migration.sourceKind, "room");
  // ...and the same policy with a hardcoded "club" throws with the WRONG
  // diagnosis, which is precisely why the call site must pass the plan's own
  // provenance. This assertion is what fails if that regresses.
  throwsCode(() => rootPostImage({
    sourceKind: "club", sourceId: "room-a", serverType: "community",
    entitlementPolicyId: "legacyRoomV1", memberCount: 1, state: "complete",
  }), "internal");
  const source = fs.readFileSync(APPLY_SOURCE, "utf8");
  assert.ok(source.includes("sourceKind: mapping.provenance.sourceKind"),
    "the root stage must pass the plan's provenance, never a literal");
  assert.ok(!/sourceKind: "club", sourceId: mapping\.provenance\.sourceId/u.test(source),
    "the hardcoded sourceKind must be gone");
});

test("QA privacy: only the exact legacy false flag can become an all-members V1 channel", () => {
  const image = (isPrivate, present = true) => {
    const channel = { type: "chat", position: 0 };
    if (present) channel.isPrivate = isPrivate;
    return channelPostImage({ serverId: "server", channel, historySource: { kind: "channelMessages" } });
  };
  assert.deepEqual(image(false).reasons, []);
  assert.deepEqual(image(true).reasons, ["restricted-legacy-channel-requires-access-mapping"]);
  for (const value of [null, 0, 1, "false", "true", {}, []]) {
    assert.deepEqual(image(value).reasons, ["channel-privacy-flag-missing-or-malformed"]);
  }
  assert.deepEqual(image(undefined, false).reasons, ["channel-privacy-flag-missing-or-malformed"]);
});

test("QA gate pin: the assessor and CLI both refuse an omitted reviewed revision", () => {
  const assessed = assessClientGate({ snapshot: gate(), expectedRevision: null, census: fullCensus() });
  assert.equal(assessed.satisfied, false);
  assert.deepEqual(assessed.reasons, ["client-compatibility-gate-revision-required"]);
  const cli = require("../scripts/servers_migration_apply_dry_run");
  const parsed = cli.parseArguments(["--out", "/tmp/yovoice-gate-pin"]);
  assert.equal(parsed.ok, false);
  assert.match(parsed.message, /--gate-revision.*required/u);
});

test("QA census CLI: an empty census file is refused before any Firestore client exists or any manifest is written", async () => {
  // P1-2's CLI leg (the audit's A5): `--census empty.json` parsed to `[]` and
  // reached the engine as SUPPLIED. The engine now refuses it; the CLI refuses
  // it first, with the reason, and never opens a client or an --out directory.
  const cli = require("../scripts/servers_migration_apply_dry_run");
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "yovoice-census-qa-"));
  try {
    const empty = path.join(directory, "empty.json");
    fs.writeFileSync(empty, "[]");
    const parsed = cli.readCensus(empty);
    assert.equal(parsed.ok, false);
    assert.match(parsed.message, /observed nothing/u);
    // An all-zero census is well-formed JSON, so it parses — and it is the
    // ENGINE that refuses it (the census test above, and the emulator suite).
    // Refusing it in two places with two different rules would drift.
    const allZero = path.join(directory, "all-zero.json");
    fs.writeFileSync(allZero, JSON.stringify(CLIENT_PLATFORMS.map((platform) => ({ platform, build: 41, sessions: 0 }))));
    assert.equal(cli.readCensus(allZero).ok, true);
    assert.equal(evaluateClientCensus(canonicalClientGate(gate()), cli.readCensus(allZero).value).supplied, false);

    const out = path.join(directory, "out");
    const errors = [];
    const code = await cli.run({
      argv: ["--out", out, "--gate-revision", "7", "--census", empty],
      env: { GCLOUD_PROJECT: "demo-yovoice-qa", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8085" },
      stdout: () => {}, stderr: (text) => errors.push(text),
    });
    assert.equal(code, cli.EXIT_REFUSED);
    assert.equal(fs.existsSync(out), false, "a refused run must not create its --out directory");
    assert.match(errors.join("\n"), /observed nothing/u);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

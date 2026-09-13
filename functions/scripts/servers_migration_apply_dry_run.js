#!/usr/bin/env node
//
// Dry run of the legacy Club/room migration APPLY ENGINE.
//
//   node functions/scripts/servers_migration_apply_dry_run.js --out <dir> \
//     [--run-id <id>] --gate-revision N [--census <file.json>] \
//     [--page-size N] [--max-roots N]
//   node functions/scripts/servers_migration_apply_dry_run.js --out <dir> --allow-project <projectId>
//
// This script is DRY RUN ONLY and has no flag that makes it write. It runs the
// read-only collector, feeds its mapping report to the apply engine in
// `dryRun` mode, and reports what the engine WOULD write together with every
// refusal. Write mode exists solely to prove the engine against a local
// emulator and is reachable only from `functions/test/servers_migration_apply.test.js`;
// the engine itself refuses write mode unless the target is an emulator.
//
// The run REFUSES (exit 2) unless FIRESTORE_EMULATOR_HOST points at a local
// emulator, or the operator passes --allow-project with the exact project id
// the admin app resolves. A production run stays read-only either way.
//
// Output: <dir>/apply-manifest.json and <dir>/apply-manifest.sha256. Both hold
// source ids and member counts, so they are created 0600 inside a 0700
// directory and an existing manifest is never overwritten. Stdout carries
// counts and closed-set refusal reasons only.
//
// Exit codes: 0 success, 1 runtime failure, 2 refusal or malformed arguments.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { MAX_PAGE_RECORDS } = require("../servers/migration_inventory");
const {
  DEFAULT_OPTIONS, MAX_COLLECTOR_ROOTS, createLegacyMigrationCollector, manifestDigest, serializeManifest,
} = require("../servers/migration_collector");
const { MAX_ROOTS_PER_RUN, createLegacyMigrationApplyEngine } = require("../servers/migration_apply");
const { MAX_CENSUS_ENTRIES } = require("../servers/migration_gate");

const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const EXIT_REFUSED = 2;
const APP_NAME = "servers-migration-apply-dry-run";
const LOCAL_EMULATOR_HOST = /^(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}$/u;
const PROJECT_ID = /^[a-z][a-z0-9-]{0,62}$/u;
const RUN_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const INTEGER = /^[0-9]{1,9}$/u;
const FILE_MODE = 0o600;
const DIRECTORY_MODE = 0o700;
const MAX_CENSUS_BYTES = 64 * 1024;
const USAGE = "Usage: node functions/scripts/servers_migration_apply_dry_run.js --out <dir> " +
  "[--run-id <id>] --gate-revision N [--census <file.json>] [--page-size N] [--max-roots N] " +
  "[--allow-project <projectId>]";
const FAILURE_REASONS = Object.freeze({
  "invalid-argument": "apply-engine-rejected-the-run-options",
  "failed-precondition": "apply-engine-refused-the-run-preconditions",
  internal: "apply-engine-internal-consistency-check-failed",
});
const FILESYSTEM_CODE = /^E[A-Z]{1,15}$/u;
const SAFE_CODE = /^[A-Za-z][A-Za-z0-9_.-]{0,63}$/u;

function failureLine(error) {
  const raw = error?.code;
  const code = typeof raw === "string" && SAFE_CODE.test(raw) ? raw
    : Number.isSafeInteger(raw) && raw >= 0 && raw <= 999 ? String(raw) : "none";
  const reason = Object.hasOwn(FAILURE_REASONS, code) ? FAILURE_REASONS[code]
    : FILESYSTEM_CODE.test(code) ? "manifest-output-write-failed" : "firestore-read-or-runtime-failure";
  return `servers migration apply dry-run failed: ${reason} (code ${code})`;
}

function malformed(message) {
  return { ok: false, message: `${message}\n${USAGE}` };
}

function parseArguments(argv) {
  if (!Array.isArray(argv) || argv.some((value) => typeof value !== "string")) {
    return malformed("Arguments are invalid.");
  }
  const specs = { "--out": "out", "--run-id": "runId", "--gate-revision": "gateRevision",
    "--census": "census", "--page-size": "pageSize", "--max-roots": "maxRoots",
    "--allow-project": "allowProject" };
  const seen = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const key = specs[flag];
    if (!key) return malformed(`Unknown argument: ${JSON.stringify(flag)}.`);
    if (Object.hasOwn(seen, key)) return malformed(`Duplicate argument: ${flag}.`);
    const value = argv[index + 1];
    if (typeof value !== "string" || value.length === 0 || value.startsWith("--")) {
      return malformed(`${flag} requires a value.`);
    }
    seen[key] = value;
  }
  if (!Object.hasOwn(seen, "out")) return malformed("--out <dir> is required.");
  const bounded = (key, min, max, fallback) => {
    if (!Object.hasOwn(seen, key)) return fallback;
    const value = INTEGER.test(seen[key]) ? Number(seen[key]) : Number.NaN;
    return value >= min && value <= max ? value : null;
  };
  const pageSize = bounded("pageSize", 1, MAX_PAGE_RECORDS, DEFAULT_OPTIONS.pageSize);
  if (pageSize === null) return malformed(`--page-size must be an integer between 1 and ${MAX_PAGE_RECORDS}.`);
  const maxRoots = bounded("maxRoots", 1, MAX_COLLECTOR_ROOTS, DEFAULT_OPTIONS.maxRoots);
  if (maxRoots === null) return malformed(`--max-roots must be an integer between 1 and ${MAX_COLLECTOR_ROOTS}.`);
  const gateRevision = bounded("gateRevision", 1, Number.MAX_SAFE_INTEGER - 1, null);
  if (gateRevision === null) return malformed("--gate-revision with the reviewed positive revision is required.");
  const runId = Object.hasOwn(seen, "runId") ? seen.runId : "dry-run";
  if (!RUN_ID.test(runId)) return malformed("--run-id is not a usable identifier.");
  const allowProject = Object.hasOwn(seen, "allowProject") ? seen.allowProject : null;
  if (allowProject !== null && !PROJECT_ID.test(allowProject)) return malformed("--allow-project is not a project id.");
  return { ok: true, value: { out: seen.out, runId, gateRevision, census: seen.census ?? null,
    pageSize, maxRoots, allowProject } };
}

/**
 * The installed-base census is operator evidence, never derived: nothing in
 * this repository observes live client versions. A missing file is a refusal,
 * not an implied zero.
 */
function readCensus(file) {
  if (file === null) return { ok: true, value: null };
  let text;
  try {
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size > MAX_CENSUS_BYTES) {
      return { ok: false, message: "Refusing: --census must name a small JSON file." };
    }
    text = fs.readFileSync(file, "utf8");
  } catch {
    return { ok: false, message: "Refusing: --census file could not be read." };
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { ok: false, message: "Refusing: --census is not valid JSON." };
  }
  if (!Array.isArray(parsed) || parsed.length > MAX_CENSUS_ENTRIES) {
    return { ok: false, message: `Refusing: --census must be an array of at most ${MAX_CENSUS_ENTRIES} entries.` };
  }
  // An empty census is zero OBSERVATIONS, not an observation of zero, and it
  // reaches an operator through a one-character edit or an analytics export
  // that returned no rows. The engine refuses it too (`evaluateClientCensus`),
  // so this is defence in depth rather than the only guard — but it refuses
  // here with the reason, before a manifest is written.
  if (parsed.length === 0) {
    return { ok: false, message: "Refusing: --census observed nothing. An empty census is not evidence that no " +
      "incompatible client exists; supply a real one, or omit the flag and read the refusal." };
  }
  return { ok: true, value: parsed };
}

function resolveProjectId(env) {
  for (const key of ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"]) {
    if (typeof env[key] === "string" && env[key].length > 0) return env[key];
  }
  if (typeof env.FIREBASE_CONFIG === "string" && env.FIREBASE_CONFIG.length > 0) {
    try {
      const config = JSON.parse(env.FIREBASE_CONFIG);
      if (config && typeof config.projectId === "string" && config.projectId.length > 0) return config.projectId;
    } catch {
      return null;
    }
  }
  return null;
}

// Pure: decides whether a run may open a Firestore client at all. It never
// touches firebase-admin, so a refusal cannot have connected anywhere.
function accessDecision({ env, allowProject }) {
  const projectId = resolveProjectId(env);
  if (projectId === null || !PROJECT_ID.test(projectId)) {
    return { allowed: false, message: "Refusing: no project id in GCLOUD_PROJECT, GOOGLE_CLOUD_PROJECT or FIREBASE_CONFIG." };
  }
  if (allowProject !== null && allowProject !== projectId) {
    return { allowed: false, message: "Refusing: --allow-project does not exactly match the admin app project id." };
  }
  const host = env.FIRESTORE_EMULATOR_HOST;
  if (typeof host === "string" && host.length > 0) {
    if (!LOCAL_EMULATOR_HOST.test(host)) {
      return { allowed: false, message: "Refusing: FIRESTORE_EMULATOR_HOST must name a local emulator (127.0.0.1, localhost or [::1])." };
    }
    return { allowed: true, projectId, emulator: true };
  }
  if (allowProject === null) {
    return { allowed: false, message: "Refusing: set FIRESTORE_EMULATOR_HOST to a local emulator, or pass --allow-project " +
      "<projectId> for a separately approved read-only dry run." };
  }
  return { allowed: true, projectId, emulator: false };
}

function summaryLines(manifest, collected, manifestPath, digestPath, digest) {
  const { summary } = manifest;
  const dispositions = Object.entries(summary.dispositions)
    .map(([key, count]) => `${key}=${count}`).sort();
  const refusals = Object.entries(summary.refusalReasons)
    .map(([reason, count]) => `${reason}=${count}`).sort();
  const gate = manifest.clientGate.observed;
  return [
    "servers migration apply dry-run: planned writes only (no writes performed)",
    `project: ${manifest.projectId} emulator: ${manifest.emulator} mode: ${manifest.mode}`,
    `collector: roots=${collected.summary.roots.total} mappingRecords=${collected.summary.roots.includedInMapping} ` +
      `dispositions=${JSON.stringify(collected.summary.mapping.dispositions)}`,
    `roots considered: ${summary.roots}`,
    `dispositions: ${dispositions.length > 0 ? dispositions.join(" ") : "none"}`,
    `refusal reasons: ${refusals.length > 0 ? refusals.join(", ") : "none"}`,
    `client gate: path=${manifest.clientGate.path} expectedRevision=${manifest.clientGate.expectedRevision ?? "unpinned"} ` +
      `censusSupplied=${manifest.clientGate.censusSupplied}` +
      (gate ? ` status=${gate.status} minimumClientBuild=${gate.minimumClientBuild} ` +
        `incompatibleSessions=${gate.incompatibleSessions}` : " observed=not-reached"),
    `familyMigrationAllowed: ${manifest.familyMigrationAllowed} (ADR-E)`,
    `open gates: ${manifest.openGates.join(", ")}`,
    `applyReady: ${manifest.applyReady}`,
    `writeCount: ${manifest.writeCount}`,
    `manifest: ${manifestPath}`,
    `digest: sha256 ${digest} (${digestPath})`,
  ].join("\n");
}

async function run({ argv, env, stdout, stderr }) {
  const parsed = parseArguments(argv);
  if (!parsed.ok) { stderr(parsed.message); return EXIT_REFUSED; }
  const census = readCensus(parsed.value.census);
  if (!census.ok) { stderr(census.message); return EXIT_REFUSED; }
  const decision = accessDecision({ env, allowProject: parsed.value.allowProject });
  if (!decision.allowed) { stderr(decision.message); return EXIT_REFUSED; }
  const outDir = path.resolve(parsed.value.out);
  const manifestPath = path.join(outDir, "apply-manifest.json");
  const digestPath = path.join(outDir, "apply-manifest.sha256");
  if (fs.existsSync(manifestPath) || fs.existsSync(digestPath)) {
    stderr(`Refusing: ${outDir} already holds an apply manifest; choose an empty --out directory.`);
    return EXIT_REFUSED;
  }
  let app = null;
  try {
    fs.mkdirSync(outDir, { recursive: true, mode: DIRECTORY_MODE });
    const { deleteApp, initializeApp } = require("firebase-admin/app");
    const { Timestamp, getFirestore } = require("firebase-admin/firestore");
    app = initializeApp({ projectId: decision.projectId }, APP_NAME);
    try {
      const firestore = getFirestore(app);
      const collector = createLegacyMigrationCollector({
        firestore, projectId: decision.projectId, emulator: decision.emulator,
      });
      const collected = await collector.collect({ pageSize: parsed.value.pageSize, maxRoots: parsed.value.maxRoots });
      if (collected.mappingReport === null) {
        stderr("Refusing: the collector produced no mapping report to apply.");
        return EXIT_REFUSED;
      }
      const mappings = collected.mappingReport.mappings.slice(0, MAX_ROOTS_PER_RUN);
      const engine = createLegacyMigrationApplyEngine({
        firestore, Timestamp, projectId: decision.projectId, emulator: decision.emulator, mode: "dryRun",
      });
      const manifest = await engine.run({
        runId: parsed.value.runId, mappings, planDigest: collected.mappingReport.reportDigest,
        expectedGateRevision: parsed.value.gateRevision, clientCensus: census.value,
      });
      const text = serializeManifest({ ...manifest, collectorSummary: collected.summary });
      const digest = manifestDigest(text);
      fs.writeFileSync(manifestPath, text, { encoding: "utf8", flag: "wx", mode: FILE_MODE });
      fs.writeFileSync(digestPath, `${digest}  apply-manifest.json\n`, { encoding: "utf8", flag: "wx", mode: FILE_MODE });
      stdout(summaryLines(manifest, collected, manifestPath, digestPath, digest));
      return EXIT_SUCCESS;
    } finally {
      await deleteApp(app);
    }
  } catch (error) {
    stderr(failureLine(error));
    return EXIT_FAILURE;
  }
}

if (require.main === module) {
  run({
    argv: process.argv.slice(2), env: process.env,
    stdout: (text) => fs.writeSync(1, `${text}\n`),
    stderr: (text) => fs.writeSync(2, `${text}\n`),
  }).then((code) => process.exit(code), (error) => {
    fs.writeSync(2, `${failureLine(error)}\n`);
    process.exit(EXIT_FAILURE);
  });
}

module.exports = { DIRECTORY_MODE, EXIT_FAILURE, EXIT_REFUSED, EXIT_SUCCESS, FILE_MODE,
  accessDecision, failureLine, parseArguments, readCensus, run };

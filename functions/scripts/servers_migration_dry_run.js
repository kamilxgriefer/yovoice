#!/usr/bin/env node
//
// Read-only dry run of the legacy Club/room migration inventory collector.
//
//   node functions/scripts/servers_migration_dry_run.js --out <dir> [--page-size N] [--max-roots N]
//     [--max-total-records N]
//   node functions/scripts/servers_migration_dry_run.js --out <dir> --allow-project <projectId>
//
// The run REFUSES (exit 2) unless FIRESTORE_EMULATOR_HOST points at a local
// emulator, or the operator passes --allow-project with the exact project id
// the admin app resolves from GCLOUD_PROJECT / GOOGLE_CLOUD_PROJECT /
// FIREBASE_CONFIG. A production run is a separate approved step and is still
// read-only: the collector never constructs a write, batch or transaction.
//
// Output: <dir>/manifest.json (the versioned manifest, record IDs only inside
// page data) and <dir>/manifest.sha256 (sha256sum-format digest binding the
// manifest bytes). Both files hold member and host UIDs, so they are created
// 0600 inside a 0700 directory. An existing manifest is never overwritten.
// Stdout carries counts only, never record IDs, names, bodies or media, and
// stderr carries a closed-set failure reason with an error code, never an SDK
// or filesystem message (those quote paths and document IDs).
//
// Exit codes: 0 success, 1 runtime failure, 2 refusal or malformed arguments.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { MAX_PAGE_RECORDS } = require("../servers/migration_inventory");
const {
  DEFAULT_OPTIONS, MAX_COLLECTOR_ROOTS, MAX_TOTAL_RECORDS, MIN_TOTAL_RECORDS,
  createLegacyMigrationCollector, manifestDigest, serializeManifest,
} = require("../servers/migration_collector");

const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const EXIT_REFUSED = 2;
const APP_NAME = "servers-migration-dry-run";
const LOCAL_EMULATOR_HOST = /^(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}$/u;
const PROJECT_ID = /^[a-z][a-z0-9-]{0,62}$/u;
const INTEGER = /^[0-9]{1,9}$/u;
const FILE_MODE = 0o600;
const DIRECTORY_MODE = 0o700;
const USAGE = "Usage: node functions/scripts/servers_migration_dry_run.js --out <dir> " +
  "[--page-size N] [--max-roots N] [--max-total-records N] [--allow-project <projectId>]";
// A failure reason is chosen from this closed set by error code alone, so no
// SDK, gRPC or filesystem message text can reach the operator's terminal.
const FAILURE_REASONS = Object.freeze({
  "invalid-argument": "collector-rejected-the-run-options",
  internal: "collector-internal-consistency-check-failed",
});
const FILESYSTEM_CODE = /^E[A-Z]{1,15}$/u;
const SAFE_CODE = /^[A-Za-z][A-Za-z0-9_.-]{0,63}$/u;

function failureLine(error) {
  const raw = error?.code;
  const code = typeof raw === "string" && SAFE_CODE.test(raw) ? raw
    : Number.isSafeInteger(raw) && raw >= 0 && raw <= 999 ? String(raw) : "none";
  const reason = Object.hasOwn(FAILURE_REASONS, code) ? FAILURE_REASONS[code]
    : FILESYSTEM_CODE.test(code) ? "manifest-output-write-failed" : "firestore-read-or-runtime-failure";
  return `servers migration dry-run failed: ${reason} (code ${code})`;
}

function malformed(message) {
  return { ok: false, message: `${message}\n${USAGE}` };
}

function parseArguments(argv) {
  if (!Array.isArray(argv) || argv.some((value) => typeof value !== "string")) return malformed("Arguments are invalid.");
  const specs = { "--out": "out", "--page-size": "pageSize", "--max-roots": "maxRoots",
    "--max-total-records": "maxTotalRecords", "--allow-project": "allowProject" };
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
  const bounded = (key, min, max) => {
    if (!Object.hasOwn(seen, key)) return DEFAULT_OPTIONS[key];
    const value = INTEGER.test(seen[key]) ? Number(seen[key]) : Number.NaN;
    return value >= min && value <= max ? value : null;
  };
  const pageSize = bounded("pageSize", 1, MAX_PAGE_RECORDS);
  if (pageSize === null) return malformed(`--page-size must be an integer between 1 and ${MAX_PAGE_RECORDS}.`);
  const maxRoots = bounded("maxRoots", 1, MAX_COLLECTOR_ROOTS);
  if (maxRoots === null) return malformed(`--max-roots must be an integer between 1 and ${MAX_COLLECTOR_ROOTS}.`);
  const maxTotalRecords = bounded("maxTotalRecords", MIN_TOTAL_RECORDS, MAX_TOTAL_RECORDS);
  if (maxTotalRecords === null) {
    return malformed(`--max-total-records must be an integer between ${MIN_TOTAL_RECORDS} and ${MAX_TOTAL_RECORDS}.`);
  }
  const allowProject = Object.hasOwn(seen, "allowProject") ? seen.allowProject : null;
  if (allowProject !== null && !PROJECT_ID.test(allowProject)) return malformed("--allow-project is not a project id.");
  return { ok: true, value: { out: seen.out, pageSize, maxRoots, maxTotalRecords, allowProject } };
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
      "<projectId> for a separately approved read-only production run." };
  }
  return { allowed: true, projectId, emulator: false };
}

function summaryLines(manifest, manifestPath, digestPath, digest) {
  const { collector, summary } = manifest;
  const scopes = Object.entries(summary.records.byScope).map(([scope, count]) => `${scope}=${count}`).join(" ");
  const dispositions = summary.mapping.dispositions
    ? Object.entries(summary.mapping.dispositions).map(([key, count]) => `${key}=${count}`).join(" ")
    : "not-computed";
  const reasons = Object.entries(summary.unresolvedReasons).map(([reason, count]) => `${reason}=${count}`);
  return [
    "servers migration dry-run: read-only inventory and mapping (no writes)",
    `project: ${manifest.projectId} emulator: ${manifest.emulator}`,
    `budgets: pageSize=${collector.pageSize} maxRoots=${collector.maxRoots} ` +
      `maxPagesPerRoot=${collector.maxPagesPerRoot} maxRecordsPerRoot=${collector.maxRecordsPerRoot} ` +
      `maxTotalRecords=${collector.maxTotalRecords}`,
    `roots: clubs=${summary.roots.clubs} rooms=${summary.roots.rooms} total=${summary.roots.total} ` +
      `discoveryTruncated=${summary.roots.discoveryTruncated}`,
    `inventory: inventoried=${summary.roots.inventoried} structurallyConsistent=${summary.roots.structurallyConsistent} ` +
      `unresolvedRoots=${summary.roots.unresolved}`,
    `pages: ${summary.pages} records: total=${summary.records.total} ${scopes}`,
    `mapping: computed=${summary.mapping.computed} ${dispositions} bindingIssues=${summary.mapping.bindingIssues ?? "n/a"}`,
    `unresolved reasons: ${reasons.length > 0 ? reasons.join(", ") : "none"}`,
    `fullInventoryComplete: ${manifest.fullInventoryComplete}`,
    `applyReady: ${manifest.applyReady}`,
    `writeCount: ${manifest.writeCount}`,
    `manifest: ${manifestPath}`,
    `digest: sha256 ${digest} (${digestPath})`,
    `digestPurpose: ${manifest.digestPurpose}`,
  ].join("\n");
}

async function run({ argv, env, stdout, stderr }) {
  const parsed = parseArguments(argv);
  if (!parsed.ok) { stderr(parsed.message); return EXIT_REFUSED; }
  const decision = accessDecision({ env, allowProject: parsed.value.allowProject });
  if (!decision.allowed) { stderr(decision.message); return EXIT_REFUSED; }
  const outDir = path.resolve(parsed.value.out);
  const manifestPath = path.join(outDir, "manifest.json");
  const digestPath = path.join(outDir, "manifest.sha256");
  if (fs.existsSync(manifestPath) || fs.existsSync(digestPath)) {
    stderr(`Refusing: ${outDir} already holds a manifest; choose an empty --out directory.`);
    return EXIT_REFUSED;
  }
  let app = null;
  try {
    fs.mkdirSync(outDir, { recursive: true, mode: DIRECTORY_MODE });
    const { deleteApp, initializeApp } = require("firebase-admin/app");
    const { getFirestore } = require("firebase-admin/firestore");
    app = initializeApp({ projectId: decision.projectId }, APP_NAME);
    try {
      const collector = createLegacyMigrationCollector({
        firestore: getFirestore(app), projectId: decision.projectId, emulator: decision.emulator,
      });
      const manifest = await collector.collect({ pageSize: parsed.value.pageSize, maxRoots: parsed.value.maxRoots,
        maxTotalRecords: parsed.value.maxTotalRecords });
      const text = serializeManifest(manifest);
      const digest = manifestDigest(text);
      // Both files carry member and host UIDs: owner-only from the moment they
      // exist ("wx" always creates, so the mode is never left to an older file).
      fs.writeFileSync(manifestPath, text, { encoding: "utf8", flag: "wx", mode: FILE_MODE });
      fs.writeFileSync(digestPath, `${digest}  manifest.json\n`, { encoding: "utf8", flag: "wx", mode: FILE_MODE });
      stdout(summaryLines(manifest, manifestPath, digestPath, digest));
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
  accessDecision, failureLine, parseArguments, run };

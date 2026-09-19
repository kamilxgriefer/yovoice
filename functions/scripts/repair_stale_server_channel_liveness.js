#!/usr/bin/env node
//
// One-off repair of server channel LIVE badges left behind before the
// empty-generation grace and the drift sweep existed (ADR-180 amendment).
//
//   node functions/scripts/repair_stale_server_channel_liveness.js --project <projectId>            # DRY RUN
//   node functions/scripts/repair_stale_server_channel_liveness.js --project <projectId> --apply    # writes
//   [--max-servers N]   (default and maximum 5000)
//
// DRY RUN BY DEFAULT: without --apply nothing is written. It visits every
// versioned server (`clubs where serverSchemaVersion == 1`), reads the channels
// whose public projection says `liveness.isLive == true`, and classifies each
// one with exactly the classifier the scheduled sweep uses
// (servers/session_staleness.js classifyChannelProjection):
//
//   ok-live                 a live generation backs it; the sweep owns it
//   reset-null-session      no generation claims the channel; --apply resets
//                           the projection with the terminal fence
//   reset-terminal-session  it names an ending/ended/failed/missing session
//                           and its anchor is idle; --apply clears the
//                           pointer and the projection (revision + 1)
//   unresolved              anything else, including a live-looking
//                           generation older than 24 h: never written here
//                           (this script holds no provider credential; the
//                           sweep resets such a badge once LiveKit reports
//                           the room empty)
//   ok-idle / changed       the projection changed while the script ran
//
// Every write is one transaction per channel that re-reads the channel, its
// anchor room and the named session and applies only when the classification
// and the named generation are unchanged, so a projection that names a newer
// live generation is never cleared. A second --apply finds nothing to do.
//
// The run REFUSES (exit 2) without an explicit --project, and when
// FIRESTORE_EMULATOR_HOST names anything but a local emulator. Without the
// emulator variable it uses Application Default Credentials against the named
// project. Output carries server/channel document ids and classifications
// only — no user data.
//
// Exit codes: 0 success, 1 runtime failure, 2 refusal or malformed arguments.
"use strict";

const fs = require("node:fs");

const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const EXIT_REFUSED = 2;
const APP_NAME = "repair-stale-server-channel-liveness";
const LOCAL_EMULATOR_HOST = /^(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}$/u;
const PROJECT_ID = /^[a-z][a-z0-9-]{0,62}$/u;
const INTEGER = /^[0-9]{1,9}$/u;
const MAX_SERVERS = 5000;
const SAFE_CODE = /^[A-Za-z][A-Za-z0-9_.-]{0,63}$/u;
const USAGE = "Usage: node functions/scripts/repair_stale_server_channel_liveness.js --project <projectId> " +
  "[--apply] [--max-servers N]";
const CLASSIFICATIONS = Object.freeze([
  "ok-live", "ok-idle", "reset-null-session", "reset-terminal-session", "unresolved", "changed",
]);

function malformed(message) {
  return { ok: false, message: `${message}\n${USAGE}` };
}

function parseArguments(argv) {
  if (!Array.isArray(argv) || argv.some((value) => typeof value !== "string")) return malformed("Arguments are invalid.");
  const values = { project: null, apply: false, maxServers: MAX_SERVERS };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (seen.has(flag)) return malformed(`Duplicate argument: ${flag}.`);
    seen.add(flag);
    if (flag === "--apply") { values.apply = true; continue; }
    if (flag !== "--project" && flag !== "--max-servers") return malformed(`Unknown argument: ${JSON.stringify(flag)}.`);
    const value = argv[index + 1];
    if (typeof value !== "string" || value.length === 0 || value.startsWith("--")) return malformed(`${flag} requires a value.`);
    index += 1;
    if (flag === "--project") {
      if (!PROJECT_ID.test(value)) return malformed("--project is not a project id.");
      values.project = value;
    } else {
      const parsed = INTEGER.test(value) ? Number(value) : Number.NaN;
      if (!(parsed >= 1 && parsed <= MAX_SERVERS)) return malformed(`--max-servers must be an integer between 1 and ${MAX_SERVERS}.`);
      values.maxServers = parsed;
    }
  }
  if (values.project === null) return malformed("--project <projectId> is required, also for a dry run.");
  return { ok: true, value: values };
}

// Pure: decides whether a run may open a Firestore client at all.
function accessDecision({ env, project }) {
  const host = env.FIRESTORE_EMULATOR_HOST;
  if (typeof host === "string" && host.length > 0) {
    if (!LOCAL_EMULATOR_HOST.test(host)) {
      return { allowed: false, message: "Refusing: FIRESTORE_EMULATOR_HOST must name a local emulator (127.0.0.1, localhost or [::1])." };
    }
    return { allowed: true, projectId: project, emulator: true };
  }
  return { allowed: true, projectId: project, emulator: false };
}

function failureLine(error) {
  const raw = error?.code;
  const code = typeof raw === "string" && SAFE_CODE.test(raw) ? raw
    : Number.isSafeInteger(raw) && raw >= 0 && raw <= 999 ? String(raw) : "none";
  return `server channel liveness repair failed: firestore-read-or-runtime-failure (code ${code})`;
}

/** The repair script holds no LiveKit credential: a max-age candidate stays
 * `unresolved` here and is left to the provider-backed sweep. */
const NO_PROVIDER = Object.freeze({
  assertSupported() { throw new Error("The repair script has no media provider."); },
  async roomOccupancy() { throw new Error("The repair script has no media provider."); },
});

async function repairAll({ firestore, Timestamp, apply, maxServers, line }) {
  const { createServerSessionStalenessService } = require("../servers/session_staleness");
  const staleness = createServerSessionStalenessService({ db: firestore, Timestamp, livekit: NO_PROVIDER });
  const counts = Object.fromEntries(CLASSIFICATIONS.map((name) => [name, 0]));
  let writes = 0;
  let channels = 0;
  const { visited, truncated } = await staleness.forEachVersionedServer({ maxServers, start: null }, async (server) => {
    for (const channelId of await staleness.liveProjectionIds(server.id)) {
      channels += 1;
      const result = await staleness.repairChannelProjection({ serverId: server.id, channelId, apply, useProvider: false });
      const classification = CLASSIFICATIONS.includes(result.classification) ? result.classification : "unresolved";
      counts[classification] += 1;
      if (result.applied) writes += 1;
      const note = result.maxAge ? " (live-looking for over 24 h; the sweep resets it once the provider reports the room empty)"
        : classification.startsWith("reset-") ? (result.applied ? " (repaired)" : " (dry run: would repair)") : "";
      line(`${classification} ${server.id}/${channelId}${note}`);
    }
  });
  return { visited, truncated, channels, counts, writes };
}

async function run({ argv, env, stdout, stderr }) {
  const parsed = parseArguments(argv);
  if (!parsed.ok) { stderr(parsed.message); return EXIT_REFUSED; }
  const decision = accessDecision({ env, project: parsed.value.project });
  if (!decision.allowed) { stderr(decision.message); return EXIT_REFUSED; }
  const { apply, maxServers } = parsed.value;
  let app = null;
  try {
    const { deleteApp, initializeApp } = require("firebase-admin/app");
    const { Timestamp, getFirestore } = require("firebase-admin/firestore");
    app = initializeApp({ projectId: decision.projectId }, APP_NAME);
    try {
      stdout(`server channel liveness repair: ${apply ? "APPLY (writes)" : "DRY RUN (no writes)"}`);
      stdout(`project: ${decision.projectId} emulator: ${decision.emulator}`);
      const summary = await repairAll({ firestore: getFirestore(app), Timestamp, apply, maxServers, line: stdout });
      stdout(`servers visited: ${summary.visited}${summary.truncated ? " (truncated: raise --max-servers)" : ""}`);
      stdout(`live projections examined: ${summary.channels}`);
      stdout(`classifications: ${CLASSIFICATIONS.map((name) => `${name}=${summary.counts[name]}`).join(" ")}`);
      stdout(`writes: ${summary.writes}`);
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

module.exports = { CLASSIFICATIONS, EXIT_FAILURE, EXIT_REFUSED, EXIT_SUCCESS, MAX_SERVERS,
  accessDecision, parseArguments, run };

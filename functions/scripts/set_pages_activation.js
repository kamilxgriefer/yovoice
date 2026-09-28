#!/usr/bin/env node
//
// Operator switch for Premium Pages (ADR-233 §2.1): appConfig/pagesV1.
//
//   # Read only: print the current canonical state and the planned document.
//   node scripts/set_pages_activation.js --project yovoice-ec54a \
//     --read testers --write testers --testers uidA,uidB --lapse true
//   # Write it (exact shape, replacing the whole document), then read back.
//   node scripts/set_pages_activation.js --project yovoice-ec54a \
//     --read testers --write testers --testers uidA,uidB --lapse true --apply
//   # Kill switch / rollback (no deploy needed; safety actions keep working):
//   node scripts/set_pages_activation.js --project yovoice-ec54a \
//     --read disabled --write disabled --lapse false --apply
//
// The document is written with set() WITHOUT merge, so a stale key cannot
// survive and silently keep the feature off. `revision` is the stored
// canonical revision + 1 (1 for a missing or malformed document). After
// writing, the stored document is read back through the same
// canonicalPagesActivation the callables use, and the script fails unless
// the callables will see exactly what was requested. Activation itself is an
// owner decision with preconditions (docs/DEPLOYMENT.md, "Premium Pages").

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const {
  PAGES_ACCESS_MODES,
  PAGES_ACTIVATION_PATH,
  canonicalPagesActivation,
  malformedPagesActivationReason,
} = require("../pages/activation");

const EXPECTED_PROJECT = "yovoice-ec54a";

function parseBoolean(flag, value) {
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${flag} must be true or false.`);
}

function parseMode(flag, value) {
  if (!PAGES_ACCESS_MODES.includes(value)) {
    throw new Error(`${flag} must be one of ${PAGES_ACCESS_MODES.join(", ")}.`);
  }
  return value;
}

function parseArgs(argv) {
  const args = {
    project: null,
    readAccess: null,
    writeAccess: null,
    testerUids: [],
    lapseEnabled: null,
    apply: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--project") args.project = argv[++index] ?? null;
    else if (arg === "--read") args.readAccess = parseMode(arg, argv[++index]);
    else if (arg === "--write") args.writeAccess = parseMode(arg, argv[++index]);
    else if (arg === "--testers") {
      args.testerUids = String(argv[++index] ?? "")
        .split(",")
        .map((uid) => uid.trim())
        .filter((uid) => uid.length > 0);
    } else if (arg === "--lapse") args.lapseEnabled = parseBoolean(arg, argv[++index]);
    else if (arg === "--apply") args.apply = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (args.readAccess === null || args.writeAccess === null || args.lapseEnabled === null) {
    throw new Error("--read, --write and --lapse are all required.");
  }
  return args;
}

function assertProject(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(
      `--project must be ${EXPECTED_PROJECT} (received: ${args.project ?? "none"}).`,
    );
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error(`Runtime project is ${resolvedProject}, refusing to run against it.`);
  }
}

function plannedDocument(args, revision) {
  return {
    schemaVersion: 1,
    readAccess: args.readAccess,
    writeAccess: args.writeAccess,
    testerUids: [...args.testerUids],
    lapseEnabled: args.lapseEnabled,
    revision,
  };
}

function describe(activation) {
  return {
    readAccess: activation.readAccess,
    writeAccess: activation.writeAccess,
    testerCount: activation.testerUids.length,
    lapseEnabled: activation.lapseEnabled,
    revision: activation.revision,
  };
}

async function run({ db, args }) {
  const reference = db.doc(PAGES_ACTIVATION_PATH);
  const beforeActivation = canonicalPagesActivation(await reference.get());
  const planned = plannedDocument(args, beforeActivation.revision + 1);
  // Refuse a document the callables would read as DISABLED: the operator
  // asked for something else, and silence would look like success.
  const malformed = malformedPagesActivationReason(planned);
  if (malformed !== null) {
    throw new Error(`The requested configuration is invalid (${malformed}).`);
  }
  const before = describe(beforeActivation);
  const requested = describe(canonicalPagesActivation({
    exists: true,
    data: () => planned,
  }));
  if (!args.apply) {
    return { mode: "READ ONLY (dry run; pass --apply to write)", before, requested };
  }
  await reference.set(planned);
  const afterActivation = canonicalPagesActivation(await reference.get());
  const after = describe(afterActivation);
  if (JSON.stringify(after) !== JSON.stringify(requested) ||
      JSON.stringify(afterActivation.testerUids) !== JSON.stringify(planned.testerUids)) {
    throw new Error(
      `Read-back mismatch: callables will see ${JSON.stringify(after)}, ` +
      `requested ${JSON.stringify(requested)}.`,
    );
  }
  return { mode: "APPLIED", before, after };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertProject(args, process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null);
  if (getApps().length === 0) {
    initializeApp({ credential: applicationDefault(), projectId: EXPECTED_PROJECT });
  }
  console.log(JSON.stringify(await run({ db: getFirestore(), args }), null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(String(error.message ?? error));
    process.exit(1);
  });
}

module.exports = {
  EXPECTED_PROJECT,
  assertProject,
  parseArgs,
  plannedDocument,
  run,
};

#!/usr/bin/env node
//
// Operator switch for "See who liked" (ADR-230): appConfig/likersV1.
//
//   # Read only: print the current canonical state and the planned document.
//   node scripts/set_likers_activation.js --project yovoice-ec54a \
//     --enabled true --server-messages true
//   # Write it (exact shape, replacing the whole document), then read back.
//   node scripts/set_likers_activation.js --project yovoice-ec54a \
//     --enabled true --server-messages true --apply
//   # Rollback: the same with --enabled false (no deploy needed).
//
// The document is written with set() WITHOUT merge, so a stale key (for
// example an old `listedSince`) cannot survive and silently keep the feature
// off. After writing, the stored document is read back through the same
// canonicalLikersActivation the callables use, and the script fails unless
// the callables will see exactly what was requested. Activation itself is an
// owner decision with preconditions (docs/DEPLOYMENT.md, "See who liked").

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const {
  LIKERS_ACTIVATION_PATH,
  canonicalLikersActivation,
} = require("../engagement/likers_activation");

const EXPECTED_PROJECT = "yovoice-ec54a";

function parseBoolean(flag, value) {
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${flag} must be true or false.`);
}

function parseArgs(argv) {
  const args = { project: null, enabled: null, serverMessagesEnabled: null, apply: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--project") args.project = argv[++index] ?? null;
    else if (arg === "--enabled") args.enabled = parseBoolean(arg, argv[++index]);
    else if (arg === "--server-messages") {
      args.serverMessagesEnabled = parseBoolean(arg, argv[++index]);
    } else if (arg === "--apply") args.apply = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (args.enabled === null || args.serverMessagesEnabled === null) {
    throw new Error("--enabled and --server-messages are both required.");
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

function plannedDocument({ enabled, serverMessagesEnabled }, updatedAt) {
  return { schemaVersion: 1, enabled, serverMessagesEnabled, updatedAt };
}

function describe(activation) {
  return {
    content: activation.enabled === true,
    serverMessages: activation.enabled === true &&
      activation.serverMessagesEnabled === true,
  };
}

async function run({ db, args, serverTimestamp = () => FieldValue.serverTimestamp() }) {
  const reference = db.doc(LIKERS_ACTIVATION_PATH);
  const before = describe(canonicalLikersActivation(await reference.get()));
  const requested = describe(args);
  if (!args.apply) {
    return { mode: "READ ONLY (dry run; pass --apply to write)", before, requested };
  }
  await reference.set(plannedDocument(args, serverTimestamp()));
  const after = describe(canonicalLikersActivation(await reference.get()));
  if (after.content !== requested.content ||
      after.serverMessages !== requested.serverMessages) {
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

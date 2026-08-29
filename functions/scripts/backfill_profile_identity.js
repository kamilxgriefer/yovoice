#!/usr/bin/env node
// Bounded, resumable repair of denormalized profile identity snapshots.
//
// Dry-run first, then apply the exact same convergent operation:
//   node scripts/backfill_profile_identity.js --project yovoice-ec54a
//   node scripts/backfill_profile_identity.js --project yovoice-ec54a --apply
//
// Apply mode stores its cursor in privateMigrationState. CLI output remains
// aggregate-only and never emits a uid, document path, email or avatar URL.

const EXPECTED_PROJECT = "yovoice-ec54a";
const DEFAULT_MAX_USERS = 500;
const MAX_USERS_PER_RUN = 5000;
const STATE_PATH = "privateMigrationState/profileIdentityBackfill";

function parseArgs(argv) {
  const args = {
    apply: false,
    restart: false,
    project: null,
    maxUsers: DEFAULT_MAX_USERS,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") args.apply = true;
    else if (argument === "--restart") args.restart = true;
    else if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--max-users") {
      const value = Number.parseInt(argv[++index], 10);
      if (
        Number.isSafeInteger(value) &&
        value > 0 &&
        value <= MAX_USERS_PER_RUN
      ) {
        args.maxUsers = value;
      }
    }
  }
  return args;
}

function assertProject(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(`--project must be ${EXPECTED_PROJECT}.`);
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error(
      `Runtime project is ${resolvedProject}; refusing to continue.`,
    );
  }
}

async function runBackfill({ database, syncIdentity, args }) {
  const { FieldPath, FieldValue } = require("firebase-admin/firestore");
  const stateReference = database.doc(STATE_PATH);
  let cursor = null;

  if (args.apply) {
    if (args.restart) {
      await stateReference.delete();
    } else {
      const state = await stateReference.get();
      cursor = state.exists ? (state.data()?.lastUid ?? null) : null;
    }
  }

  let query = database
    .collection("users")
    .orderBy(FieldPath.documentId())
    .limit(args.maxUsers);
  if (cursor) query = query.startAfter(cursor);
  const users = await query.get();

  const report = {
    mode: args.apply ? "apply" : "dry-run",
    scannedUsers: 0,
    affectedUsers: 0,
    plannedWrites: 0,
    conversationsScanned: 0,
    clubMirrorsScanned: 0,
    momentsScanned: 0,
    skippedInactiveUsers: 0,
    reachedEnd: users.size < args.maxUsers,
    continuationStored: false,
  };

  // Failed work never advances the cursor. Replaying the previous group is
  // safe because syncProfileIdentity is convergent and idempotent.
  const concurrency = 4;
  for (let offset = 0; offset < users.docs.length; offset += concurrency) {
    const page = users.docs.slice(offset, offset + concurrency);
    const results = await Promise.all(
      page.map((user) => syncIdentity(user.id, { apply: args.apply })),
    );
    for (const result of results) {
      report.scannedUsers += 1;
      report.plannedWrites += result.writes;
      report.conversationsScanned += result.conversations;
      report.clubMirrorsScanned += result.clubMirrorsScanned;
      report.momentsScanned += result.moments;
      if (result.writes > 0) report.affectedUsers += 1;
      if (result.sourceUnavailable) report.skippedInactiveUsers += 1;
    }
    if (args.apply) {
      await stateReference.set({
        lastUid: page[page.length - 1].id,
        updatedAt: FieldValue.serverTimestamp(),
      });
      report.continuationStored = true;
    }
  }

  if (args.apply && report.reachedEnd) {
    await stateReference.delete();
    report.continuationStored = false;
  }
  return report;
}

async function main() {
  const {
    applicationDefault,
    getApps,
    initializeApp,
  } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  const args = parseArgs(process.argv.slice(2));
  const resolvedProject =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null;
  assertProject(args, resolvedProject);
  if (getApps().length === 0) {
    initializeApp({
      credential: applicationDefault(),
      projectId: EXPECTED_PROJECT,
    });
  }
  const { syncProfileIdentity } = require("../profile/fanout");
  const report = await runBackfill({
    database: getFirestore(),
    syncIdentity: syncProfileIdentity,
    args,
  });
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

function writeFatalError(_error, stream = process.stderr) {
  // Deliberately ignore the SDK error body: it can contain resource paths.
  stream.write("Profile identity backfill failed.\n");
}

if (require.main === module) {
  main().catch((error) => {
    // Admin SDK errors can include full resource paths and therefore UIDs.
    // The operator gets a stable failure plus a non-zero exit; detailed
    // diagnostics belong in access-controlled runtime logs, not CLI output.
    writeFatalError(error);
    process.exitCode = 1;
  });
}

module.exports = { assertProject, parseArgs, runBackfill, writeFatalError };

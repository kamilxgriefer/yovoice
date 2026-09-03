#!/usr/bin/env node
// Build 18 wrote canonical private DM objects before the trusted
// `yovoiceFinalized` marker existed. This bounded, resumable tool revokes the
// old Firebase bearer token, revalidates the exact Firestore binding and real
// media bytes, and only then adds the marker with an object-generation CAS.
//
// Cutover order (never skip a gate): deploy the new finalizer Functions to
// 100%, drain in-flight uploads, enter a maintenance/freeze window, then run a
// full dry-run from the beginning (no --start-page-token):
//   node scripts/migrate_direct_attachment_markers.js \
//     --project yovoice-ec54a
//
// Review the aggregate inventory, then apply through reachedEnd=true while the
// freeze remains active:
//   node scripts/migrate_direct_attachment_markers.js \
//     --project yovoice-ec54a --apply --maintenance-window-confirmed
//
// Run two more complete dry-runs from the beginning and require
// releaseReady=true on both. Only then deploy the strict Storage Rules and
// smoke-test both Build 18 and Build 19 image/voice attachments. This tool does
// not claim or imply that any production migration has already run.

const EXPECTED_PROJECT = "yovoice-ec54a";
const EXPECTED_STORAGE_BUCKET = "yovoice-ec54a.firebasestorage.app";
const DEFAULT_MAX_OBJECTS = 250;
const MAX_OBJECTS_PER_RUN = 100_000;
const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;
const STATE_PATH = "privateMigrationState/directAttachmentMarkerBackfill";

function parseArgs(argv) {
  const args = {
    apply: false,
    restart: false,
    maintenanceWindowConfirmed: false,
    project: null,
    maxObjects: DEFAULT_MAX_OBJECTS,
    pageSize: DEFAULT_PAGE_SIZE,
    startPageToken: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") args.apply = true;
    else if (argument === "--restart") args.restart = true;
    else if (argument === "--maintenance-window-confirmed") {
      args.maintenanceWindowConfirmed = true;
    }
    else if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--start-page-token") {
      const value = argv[++index] ?? null;
      if (typeof value !== "string" || value.length === 0 || value.length > 4096) {
        throw new Error("--start-page-token is invalid.");
      }
      args.startPageToken = value;
    }
    else if (argument === "--max-objects") {
      const value = Number.parseInt(argv[++index], 10);
      if (!Number.isSafeInteger(value) || value < 1 ||
          value > MAX_OBJECTS_PER_RUN) {
        throw new Error("--max-objects is outside the safe bound.");
      }
      args.maxObjects = value;
    } else if (argument === "--page-size") {
      const value = Number.parseInt(argv[++index], 10);
      if (!Number.isSafeInteger(value) || value < 1 || value > MAX_PAGE_SIZE) {
        throw new Error("--page-size is outside the safe bound.");
      }
      args.pageSize = value;
    } else {
      throw new Error("Unsupported argument.");
    }
  }
  if (args.restart && !args.apply) {
    throw new Error("--restart is valid only with --apply.");
  }
  if (args.apply && !args.maintenanceWindowConfirmed) {
    throw new Error("--apply requires --maintenance-window-confirmed.");
  }
  if (args.apply && args.startPageToken !== null) {
    throw new Error("--start-page-token is for read-only dry-runs only.");
  }
  return args;
}

function assertProject(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(`--project must be exactly ${EXPECTED_PROJECT}.`);
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error("Runtime project does not match the pinned project.");
  }
}

function emptyReport(args) {
  return {
    mode: args.apply ? "apply" : "dry-run",
    boundedToObjects: args.maxObjects,
    objectsScanned: 0,
    eligible: 0,
    finalized: 0,
    alreadyFinalized: 0,
    invalid: 0,
    missing: 0,
    raced: 0,
    tokensFound: 0,
    tokensRevoked: 0,
    reachedEnd: false,
    continuationStored: false,
    releaseReady: false,
    nextPageToken: null,
  };
}

async function runMigration({ db, migration, FieldValue, args }) {
  const stateRef = db.doc(STATE_PATH);
  let pageToken = args.apply ? null : (args.startPageToken ?? null);
  if (args.apply) {
    if (args.restart) {
      await stateRef.delete();
    } else {
      const state = await stateRef.get();
      if (state.exists) {
        const stored = state.data() ?? {};
        if (stored.schemaVersion !== 1 ||
            typeof stored.nextPageToken !== "string" ||
            stored.nextPageToken.length === 0 ||
            stored.nextPageToken.length > 4096) {
          throw new Error("Stored migration state is malformed; audit before restart.");
        }
        pageToken = stored.nextPageToken;
      }
    }
  }

  const report = emptyReport(args);
  while (report.objectsScanned < args.maxObjects) {
    const remaining = args.maxObjects - report.objectsScanned;
    const page = await migration.migrateDirectAttachmentPage({
      pageToken,
      maxResults: Math.min(args.pageSize, remaining),
      dryRun: !args.apply,
    });
    for (const key of [
      "objectsScanned",
      "eligible",
      "finalized",
      "alreadyFinalized",
      "invalid",
      "missing",
      "raced",
      "tokensFound",
      "tokensRevoked",
    ]) {
      report[key] += page[key];
    }

    pageToken = page.nextPageToken;
    if (args.apply) {
      if (pageToken === null) {
        await stateRef.delete();
        report.continuationStored = false;
      } else {
        await stateRef.set({
          schemaVersion: 1,
          nextPageToken: pageToken,
          updatedAt: FieldValue.serverTimestamp(),
        });
        report.continuationStored = true;
      }
    }
    if (!page.hasMore) {
      report.reachedEnd = true;
      break;
    }
    if (page.objectsScanned === 0) {
      throw new Error("Storage inventory did not advance.");
    }
  }
  report.nextPageToken = report.reachedEnd ? null : pageToken;
  report.releaseReady =
    !args.apply &&
    args.startPageToken === null &&
    report.reachedEnd &&
    report.eligible === 0 &&
    report.invalid === 0 &&
    report.missing === 0 &&
    report.raced === 0 &&
    report.tokensFound === 0;
  return report;
}

async function main() {
  const {
    applicationDefault,
    getApps,
    initializeApp,
  } = require("firebase-admin/app");
  const { FieldValue, getFirestore } = require("firebase-admin/firestore");
  const { getStorage } = require("firebase-admin/storage");
  const {
    createDirectAttachmentMigrationService,
  } = require("../messaging/direct_attachment_migration");
  const { createBucketStorageAdapter } = require("../moments/integrity");
  const { createTrustedGcsMediaProbe } = require("../reels/probe");

  const args = parseArgs(process.argv.slice(2));
  const resolvedProject =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null;
  assertProject(args, resolvedProject);
  if (getApps().length === 0) {
    initializeApp({
      credential: applicationDefault(),
      projectId: EXPECTED_PROJECT,
      storageBucket: EXPECTED_STORAGE_BUCKET,
    });
  }
  const db = getFirestore();
  const bucket = getStorage().bucket();
  if (bucket.name !== EXPECTED_STORAGE_BUCKET) {
    throw new Error("Runtime Storage bucket does not match the pinned bucket.");
  }
  const migration = createDirectAttachmentMigrationService({
    db,
    storage: createBucketStorageAdapter(bucket),
    mediaProbe: createTrustedGcsMediaProbe(bucket),
  });
  const report = await runMigration({ db, migration, FieldValue, args });
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

function writeFatalError(_error, stream = process.stderr) {
  // SDK errors may include object paths, UIDs or opaque pagination tokens.
  stream.write("Direct attachment marker migration failed.\n");
}

if (require.main === module) {
  main().catch((error) => {
    writeFatalError(error);
    process.exitCode = 1;
  });
}

module.exports = {
  DEFAULT_MAX_OBJECTS,
  DEFAULT_PAGE_SIZE,
  EXPECTED_PROJECT,
  EXPECTED_STORAGE_BUCKET,
  MAX_OBJECTS_PER_RUN,
  MAX_PAGE_SIZE,
  STATE_PATH,
  assertProject,
  emptyReport,
  parseArgs,
  runMigration,
  writeFatalError,
};

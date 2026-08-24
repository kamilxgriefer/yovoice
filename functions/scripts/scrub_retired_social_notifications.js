#!/usr/bin/env node
// Bounded, resumable cleanup for ADR-041's retired pair-lifetime social
// notification ids. Run dry first, then apply only after all three legacy
// social triggers have been deleted and verified absent.

const {
  getApps,
  initializeApp,
  applicationDefault,
} = require("firebase-admin/app");
const {
  FieldPath,
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");
const {
  socialNotificationSourceIsCurrent,
} = require("../notifications/social_source");

const EXPECTED_PROJECT = "yovoice-ec54a";
const SOCIAL_TYPES = new Set(["friendRequest", "friendAccepted", "follow"]);
const DEFAULT_BATCH_SIZE = 100;
const DEFAULT_MAX_DOCUMENTS = 500;
const MAX_DOCUMENTS_PER_RUN = 5000;
const STATE_PATH = "privateMigrationState/retiredSocialNotifications";

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: EXPECTED_PROJECT,
  });
}

function parseArgs(argv) {
  const args = {
    apply: false,
    restart: false,
    project: null,
    batchSize: DEFAULT_BATCH_SIZE,
    maxDocuments: DEFAULT_MAX_DOCUMENTS,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") args.apply = true;
    else if (argument === "--restart") args.restart = true;
    else if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--batch-size") {
      const value = Number.parseInt(argv[++index], 10);
      if (Number.isSafeInteger(value) && value >= 1 && value <= 200) {
        args.batchSize = value;
      }
    } else if (argument === "--max-documents") {
      const value = Number.parseInt(argv[++index], 10);
      if (
        Number.isSafeInteger(value) &&
        value >= 1 &&
        value <= MAX_DOCUMENTS_PER_RUN
      ) {
        args.maxDocuments = value;
      }
    }
  }
  return args;
}

function assertArgs(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(`--project must be ${EXPECTED_PROJECT}.`);
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error(`Runtime project is ${resolvedProject}; refusing to run.`);
  }
}

function isRetiredSocialNotification(document) {
  const segments = document.ref.path.split("/");
  if (
    segments.length !== 4 ||
    segments[0] !== "users" ||
    segments[2] !== "notifications"
  ) {
    return false;
  }
  const data = document.data() ?? {};
  return (
    SOCIAL_TYPES.has(data.type) &&
    typeof data.actorId === "string" &&
    data.actorId.length > 0 &&
    document.id === `${data.type}_${data.actorId}`
  );
}

function emptyReport(args) {
  return {
    mode: args.apply ? "apply" : "dry-run",
    boundedToDocuments: args.maxDocuments,
    scanned: 0,
    plannedDeletes: 0,
    appliedDeletes: 0,
    reachedEnd: false,
    continuationStored: false,
  };
}

async function scrubRetiredSocialNotifications({
  db,
  args,
  queryFactory,
  beforeCommit,
}) {
  const report = emptyReport(args);
  const stateRef = db.doc(STATE_PATH);
  let cursorPath = null;
  if (args.apply && !args.restart) {
    const state = await stateRef.get();
    cursorPath = state.exists ? state.data()?.lastPath ?? null : null;
  }

  while (report.scanned < args.maxDocuments) {
    const pageSize = Math.min(
      args.batchSize,
      args.maxDocuments - report.scanned,
    );
    // Tests inject a fixture-owned collection query because Node runs test
    // files concurrently against one emulator. Production deliberately uses
    // the global collection-group sweep.
    let query = (queryFactory
      ? queryFactory()
      : db
          .collectionGroup("notifications")
          .orderBy(FieldPath.documentId())
    ).limit(pageSize);
    if (cursorPath) query = query.startAfter(cursorPath);
    const page = await query.get();
    if (page.empty) {
      report.reachedEnd = true;
      if (args.apply) await stateRef.delete();
      break;
    }

    const retired = [];
    for (const document of page.docs) {
      if (!isRetiredSocialNotification(document)) continue;
      const segments = document.ref.path.split("/");
      const sourceIsCurrent = await socialNotificationSourceIsCurrent({
        recipientId: segments[1],
        notificationId: document.id,
        notification: document.data(),
        firestore: db,
      });
      if (!sourceIsCurrent) retired.push(document);
    }
    report.plannedDeletes += retired.length;
    cursorPath = page.docs[page.docs.length - 1].ref.path;
    if (args.apply) {
      const batch = db.batch();
      for (const document of retired) {
        batch.delete(document.ref, {lastUpdateTime: document.updateTime});
      }
      batch.set(stateRef, {
        lastPath: cursorPath,
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (beforeCommit) await beforeCommit({retired, cursorPath});
      await batch.commit();
      report.appliedDeletes += retired.length;
      report.continuationStored = true;
    }
    report.scanned += page.size;
    if (page.size < pageSize) {
      report.reachedEnd = true;
      report.continuationStored = false;
      if (args.apply) await stateRef.delete();
      break;
    }
  }
  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const resolvedProject =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null;
  assertArgs(args, resolvedProject);
  const report = await scrubRetiredSocialNotifications({
    db: getFirestore(),
    args,
  });
  console.log(JSON.stringify(report));
}

function sanitizedErrorCode(error) {
  const code = error?.code;
  if (Number.isSafeInteger(code) && code >= 0 && code <= 99) return `${code}`;
  if (
    typeof code === "string" &&
    /^[A-Za-z0-9._-]{1,64}$/.test(code)
  ) {
    return code;
  }
  return "unknown";
}

if (require.main === module) {
  main().catch((error) => {
    // This migration promises aggregate-only output. Firestore error messages
    // can contain full resource paths, so never print the raw message here.
    console.error(
      `scrub_retired_social_notifications failed (${sanitizedErrorCode(error)}).`,
    );
    process.exitCode = 1;
  });
}

module.exports = {
  EXPECTED_PROJECT,
  MAX_DOCUMENTS_PER_RUN,
  parseArgs,
  assertArgs,
  isRetiredSocialNotification,
  sanitizedErrorCode,
  scrubRetiredSocialNotifications,
};

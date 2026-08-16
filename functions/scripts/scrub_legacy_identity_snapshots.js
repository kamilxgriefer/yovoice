#!/usr/bin/env node
// Bounded, resumable removal of historical private/stale identity snapshots.
//
// Run each phase in dry-run mode first, then apply it explicitly:
//   node scripts/scrub_legacy_identity_snapshots.js \
//     --project yovoice-ec54a --phase conversations
//   node scripts/scrub_legacy_identity_snapshots.js \
//     --project yovoice-ec54a --phase conversations --apply
//
// Apply mode stores its cursor in privateMigrationState (Admin-only) so the
// CLI output stays aggregate-only and never prints a uid, document path or
// email. Every phase is idempotent and capped per invocation.

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

const EXPECTED_PROJECT = "yovoice-ec54a";
const PHASES = new Set([
  "conversations",
  "friendRequests",
  "following",
  "followers",
]);
const DEFAULT_BATCH_SIZE = 100;
const DEFAULT_MAX_DOCUMENTS = 500;
const MAX_DOCUMENTS_PER_RUN = 5000;

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
    phase: null,
    batchSize: DEFAULT_BATCH_SIZE,
    maxDocuments: DEFAULT_MAX_DOCUMENTS,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") args.apply = true;
    else if (argument === "--restart") args.restart = true;
    else if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--phase") args.phase = argv[++index] ?? null;
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
  if (!PHASES.has(args.phase)) {
    throw new Error(`--phase must be one of: ${[...PHASES].join(", ")}.`);
  }
}

function baseQuery(db, phase) {
  const source = phase === "conversations"
    ? db.collection("conversations")
    : db.collectionGroup(phase);
  return source.orderBy(FieldPath.documentId());
}

function scrubPlan(document, phase) {
  const data = document.data() ?? {};
  if (phase === "conversations") {
    const emails = data.participantEmails;
    if (!emails || typeof emails !== "object" || Array.isArray(emails)) {
      return null;
    }
    const scrubbed = Object.fromEntries(
      Object.keys(emails).map((uid) => [uid, ""]),
    );
    const changed = Object.values(emails).some((value) => value !== "");
    return changed
      ? { kind: "update", data: { participantEmails: scrubbed } }
      : null;
  }
  if (phase === "friendRequests") {
    return Object.prototype.hasOwnProperty.call(data, "senderEmail")
      ? { kind: "update", data: { senderEmail: FieldValue.delete() } }
      : null;
  }

  const followedAt = data.followedAt;
  if (!followedAt || typeof followedAt.toDate !== "function") {
    return { kind: "conflict" };
  }
  const keys = Object.keys(data).sort();
  const exact =
    keys.length === 2 &&
    keys[0] === "followedAt" &&
    keys[1] === "uid" &&
    data.uid === document.id;
  return exact
    ? null
    : {
        kind: "replace",
        data: { uid: document.id, followedAt },
      };
}

function emptyReport(args) {
  return {
    phase: args.phase,
    mode: args.apply ? "apply" : "dry-run",
    boundedToDocuments: args.maxDocuments,
    scanned: 0,
    plannedScrubs: 0,
    conflicts: 0,
    appliedScrubs: 0,
    reachedEnd: false,
    continuationStored: false,
  };
}

async function scrubIdentitySnapshots({ db, args }) {
  const report = emptyReport(args);
  const stateRef = db.doc(`privateMigrationState/legacyIdentity_${args.phase}`);
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
    let query = baseQuery(db, args.phase).limit(pageSize);
    if (cursorPath) {
      const cursor = await db.doc(cursorPath).get();
      if (!cursor.exists) {
        throw new Error("Stored migration cursor no longer exists; audit it before --restart.");
      }
      query = query.startAfter(cursor);
    }
    const page = await query.get();
    if (page.empty) {
      report.reachedEnd = true;
      if (args.apply) await stateRef.delete();
      break;
    }

    const plans = page.docs.map((document) => ({
      document,
      plan: scrubPlan(document, args.phase),
    }));
    for (const { plan } of plans) {
      if (plan?.kind === "conflict") report.conflicts += 1;
      else if (plan) report.plannedScrubs += 1;
    }

    cursorPath = page.docs[page.docs.length - 1].ref.path;
    if (args.apply) {
      const batch = db.batch();
      for (const { document, plan } of plans) {
        if (!plan || plan.kind === "conflict") continue;
        if (plan.kind === "replace") batch.set(document.ref, plan.data);
        else batch.update(document.ref, plan.data);
        report.appliedScrubs += 1;
      }
      batch.set(stateRef, {
        phase: args.phase,
        lastPath: cursorPath,
        updatedAt: FieldValue.serverTimestamp(),
      });
      await batch.commit();
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
  const report = await scrubIdentitySnapshots({
    db: getFirestore(),
    args,
  });
  console.log(JSON.stringify(report));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  EXPECTED_PROJECT,
  PHASES,
  MAX_DOCUMENTS_PER_RUN,
  parseArgs,
  assertArgs,
  scrubPlan,
  scrubIdentitySnapshots,
};

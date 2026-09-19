#!/usr/bin/env node
// Bounded, resumable backfill for accounts that were Auth-deleted BEFORE
// ADR-206 shipped.
//
// Those accounts still carry a retained `users/{uid}` document — with the
// e-mail address, display name, username, bio, country, languages and every
// counter — because the deployed `onAuthUserDeleted` trigger deliberately
// merged `{disabled, isOnline:false, premiumIdentity:false, authDeletedAt}`
// and kept the document. The new pipeline deletes it, but only for accounts
// deleted after the deploy; this script enqueues one `accountDeletionOutbox`
// row per historical account so the same bounded teardown runs for them too.
//
// IT WRITES NOTHING WITHOUT `--apply`. Running it against production is a
// production data operation and is deliberately a human step — no agent
// workflow runs it. Read the dry-run output first; every row it would enqueue
// is printed with the uid and whether a live Auth account still exists.
//
// `--project` IS MANDATORY AND HAS NO DEFAULT. This script enqueues real
// deletions; a default of "the ambient project, else production" is one
// forgotten export away from erasing live accounts, and the flag used to be
// accepted and then ignored, which is worse than not offering it.
//
//   node functions/scripts/backfill_account_deletion.js --project yovoice-ec54a
//   node functions/scripts/backfill_account_deletion.js --project yovoice-ec54a --apply
//   node functions/scripts/backfill_account_deletion.js --project yovoice-ec54a --max-documents 50
//
// SAFETY: a `users/{uid}` whose Auth account still EXISTS is skipped, loudly.
// `authDeletedAt` is set by the trigger, so its presence normally means the
// identity is gone — but a uid that resolves in Auth is a live account, and
// enqueuing it would delete a real user. The check is per uid, against Auth,
// and a lookup failure skips rather than proceeds.

const {
  getApps,
  initializeApp,
  applicationDefault,
} = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const {
  FieldPath,
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");

const EXPECTED_PROJECT = "yovoice-ec54a";
const DEFAULT_BATCH_SIZE = 100;
const DEFAULT_MAX_DOCUMENTS = 200;
const MAX_DOCUMENTS_PER_RUN = 5000;
const STATE_PATH = "privateMigrationState/accountDeletionBackfill";

/**
 * The project id, from `--project` and nowhere else.
 *
 * Read before `initializeApp`, so the SDK can never be pointed at a default.
 * A `GCLOUD_PROJECT` that disagrees is a refusal rather than a silent
 * override: the two disagreeing is exactly the state in which somebody
 * believes they are on staging.
 */
function requiredProjectId(argv) {
  const index = argv.indexOf("--project");
  const value = index >= 0 ? argv[index + 1] : null;
  if (typeof value !== "string" || value === "" || value.startsWith("--")) {
    console.error(
      "[account-deletion-backfill] refusing to run without an explicit " +
        "--project. There is no default.\n" +
        "  node functions/scripts/backfill_account_deletion.js --project " +
        `${EXPECTED_PROJECT}`,
    );
    process.exit(2);
  }
  const ambient = process.env.GCLOUD_PROJECT;
  if (ambient && ambient !== value) {
    console.error(
      `[account-deletion-backfill] refusing to run: --project ${value} ` +
        `disagrees with GCLOUD_PROJECT ${ambient}.`,
    );
    process.exit(2);
  }
  return value;
}

const PROJECT_ID = requiredProjectId(process.argv.slice(2));
process.env.GCLOUD_PROJECT = PROJECT_ID;

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: PROJECT_ID,
  });
}

const {
  OUTBOX_COLLECTION,
  initialOutboxRow,
  outboxIdForUid,
} = require("../account/outbox");
const { mintReporterTombstone } = require("../account/retention");

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
    // Already consumed by requiredProjectId() before the SDK was initialised;
    // skipped here only so its value is not mistaken for a positional.
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

async function authAccountExists(uid) {
  try {
    await getAuth().getUser(uid);
    return true;
  } catch (error) {
    if (error?.code === "auth/user-not-found") return false;
    // An unknown Auth error must never be read as "the account is gone".
    throw error;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const db = getFirestore();
  const stateReference = db.doc(STATE_PATH);

  if (args.restart && args.apply) await stateReference.delete();
  const state = await stateReference.get();
  let cursor = args.restart ? null : (state.data()?.lastUid ?? null);

  let scanned = 0;
  let enqueued = 0;
  let skippedLiveAuth = 0;
  let skippedExisting = 0;

  console.log(
    `[account-deletion-backfill] ${args.apply ? "APPLY" : "DRY RUN"} ` +
      `project=${PROJECT_ID} ` +
      `maxDocuments=${args.maxDocuments}`,
  );

  while (scanned < args.maxDocuments) {
    let query = db
      .collection("users")
      .orderBy(FieldPath.documentId())
      .limit(Math.min(args.batchSize, args.maxDocuments - scanned));
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const document of snapshot.docs) {
      cursor = document.id;
      scanned += 1;
      const data = document.data() ?? {};
      // The exact marker the deployed trigger wrote. Nothing else identifies a
      // historically retired account.
      if (!data.authDeletedAt) continue;

      if (await authAccountExists(document.id)) {
        skippedLiveAuth += 1;
        console.log(
          `  SKIP  ${document.id} — authDeletedAt is set but the Auth ` +
            "account still exists; this is a LIVE user",
        );
        continue;
      }

      const outboxId = outboxIdForUid(document.id);
      if (!outboxId) {
        skippedExisting += 1;
        continue;
      }
      const reference = db.collection(OUTBOX_COLLECTION).doc(outboxId);
      if ((await reference.get()).exists) {
        skippedExisting += 1;
        continue;
      }

      enqueued += 1;
      console.log(
        `  ${args.apply ? "ENQUEUE" : "WOULD ENQUEUE"}  ${document.id}` +
          `${data.email ? " (has a retained e-mail address)" : ""}`,
      );
      if (args.apply) {
        await reference.create(initialOutboxRow({
          uid: document.id,
          source: "authTrigger",
          reporterTombstone: mintReporterTombstone(),
          now: FieldValue.serverTimestamp(),
        }));
      }
    }

    if (args.apply) {
      await stateReference.set(
        { lastUid: cursor, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    if (snapshot.size < args.batchSize) break;
  }

  console.log(
    `[account-deletion-backfill] scanned=${scanned} enqueued=${enqueued} ` +
      `skippedLiveAuth=${skippedLiveAuth} skippedExisting=${skippedExisting} ` +
      `cursor=${cursor ?? "(start)"}`,
  );
  if (!args.apply) {
    console.log(
      "[account-deletion-backfill] dry run only — nothing was written. " +
        "Re-run with --apply to enqueue.",
    );
  }
}

main().catch((error) => {
  console.error("[account-deletion-backfill] failed", error);
  process.exit(1);
});

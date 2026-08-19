#!/usr/bin/env node
//
// Repair for the 2026-08-18 achievement incident (see Decisions.md ADR-081
// and docs/Sessions/2026-08-19-achievement-ledger-retry-loop.md).
//
//   node scripts/repair_achievement_canonical_ledger.js --project yovoice-ec54a           # dry run
//   node scripts/repair_achievement_canonical_ledger.js --project yovoice-ec54a --apply   # writes
//
// Two scopes, both idempotent:
//
// 1. achievementEvents (sourceType == "activeDay"): entries written before
//    the fix carry a fingerprint derived from the exact time of the first
//    qualifying event of that user-day. The fixed engine derives the
//    canonical content from (uid, UTC day) alone. This script rewrites each
//    pre-fix entry to the canonical day-start form THROUGH THE SAME MODULES
//    the engine uses (adaptActiveDay + eventIdFor + eventFingerprint), so
//    the two can never disagree. The previous values stay on the document in
//    audit fields. A document is touched only after its identity re-derives
//    exactly: recomputed doc id AND stored sourceKeyHash AND stored
//    fingerprint must all match the reconstruction from stored fields.
//
// 2. achievementMigrations: the pre-fix failUser wrote, for a user whose
//    bootstrap never committed, a partial record ({status, failureCode,
//    updatedAt} only) that the pre-fix beginUser could never accept again —
//    wedging the reconciler on that user. Such records are rewritten in
//    place to a well-formed pre-bootstrap failure record that the fixed
//    beginUser re-initializes on its next run. Nothing is deleted.
//
// Apply gates itself: it first completes a full dry scan and refuses to
// write anything if that scan found any anomaly. Anomalies are reported and
// never touched. Output redacts uids. Deploy the fixed functions BEFORE
// running --apply; the repair is safe either way, but only the fixed build
// stops the retry loops.

const { createHash } = require("node:crypto");
const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: "yovoice-ec54a",
  });
}

const {
  eventFingerprint,
  eventIdFor,
  normalizeAchievementEvent,
} = require("../achievements/engine");
const { adaptActiveDay } = require("../achievements/sources");
const { MIGRATION_SCHEMA_VERSION } = require("../achievements/migration");

const EXPECTED_PROJECT = "yovoice-ec54a";
const POISON_KEYS = ["failureCode", "status", "updatedAt"];

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function redact(uid) {
  return typeof uid === "string" && uid.length > 8 ? `${uid.slice(0, 8)}…` : "<invalid>";
}

function parseArgs(argv) {
  const args = { apply: false, project: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--apply") args.apply = true;
    else if (argv[i] === "--project") args.project = argv[++i] ?? null;
  }
  return args;
}

function timestampDate(value) {
  return typeof value?.toDate === "function"
    ? value.toDate()
    : value instanceof Date
      ? value
      : null;
}

// Classifies one activeDay ledger document. Returns
// { kind: "canonical" | "repairable" | "anomaly", ... }.
function classifyActiveDayEntry(id, data) {
  const occurred = timestampDate(data.sourceOccurredAt);
  if (!occurred || typeof data.beneficiaryId !== "string") {
    return { kind: "anomaly", reason: "missing beneficiaryId or sourceOccurredAt" };
  }
  const canonicalEvent = adaptActiveDay({
    uid: data.beneficiaryId,
    occurredAt: occurred,
  });
  if (!canonicalEvent) {
    return { kind: "anomaly", reason: "stored fields do not derive an activeDay event" };
  }
  const normalized = normalizeAchievementEvent(canonicalEvent);
  if (eventIdFor(normalized) !== id) {
    return { kind: "anomaly", reason: "document id does not re-derive from stored fields" };
  }
  if (sha256(normalized.sourceKey) !== data.sourceKeyHash) {
    return { kind: "anomaly", reason: "stored sourceKeyHash does not match reconstruction" };
  }
  const canonicalFingerprint = eventFingerprint(normalized);
  if (data.eventFingerprint === canonicalFingerprint) {
    return { kind: "canonical" };
  }
  // The only accepted non-canonical form is the pre-fix one: fingerprinted
  // at the stored exact observation time.
  const preFixFingerprint = eventFingerprint({
    ...normalized,
    occurredAt: occurred,
  });
  if (data.eventFingerprint !== preFixFingerprint) {
    return { kind: "anomaly", reason: "stored fingerprint matches neither canonical nor pre-fix form" };
  }
  return {
    kind: "repairable",
    canonicalFingerprint,
    canonicalOccurredAt: normalized.occurredAt,
  };
}

function isPoisonMigrationRecord(data) {
  return data !== null && typeof data === "object" &&
    Object.keys(data).sort().join(",") === POISON_KEYS.join(",") &&
    data.status === "failed";
}

async function scanActiveDayEntries(db) {
  const snapshot = await db.collection("achievementEvents")
    .where("sourceType", "==", "activeDay")
    .get();
  const results = [];
  for (const doc of snapshot.docs) {
    results.push({ id: doc.id, data: doc.data(), ...classifyActiveDayEntry(doc.id, doc.data()) });
  }
  return results;
}

async function scanPoisonMigrationRecords(db) {
  const snapshot = await db.collection("achievementMigrations")
    .where("status", "==", "failed")
    .limit(50)
    .get();
  return snapshot.docs
    .map((doc) => ({ uid: doc.id, data: doc.data() }))
    .filter((entry) => isPoisonMigrationRecord(entry.data));
}

async function repairActiveDayEntry(db, entry, now) {
  await db.runTransaction(async (transaction) => {
    const reference = db.collection("achievementEvents").doc(entry.id);
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw new Error(`vanished: ${entry.id}`);
    const fresh = classifyActiveDayEntry(entry.id, snapshot.data());
    if (fresh.kind === "canonical") return; // repaired concurrently — idempotent
    if (fresh.kind !== "repairable") throw new Error(`no longer repairable: ${entry.id}`);
    transaction.update(reference, {
      eventFingerprint: fresh.canonicalFingerprint,
      sourceOccurredAt: fresh.canonicalOccurredAt,
      previousEventFingerprint: snapshot.data().eventFingerprint,
      previousSourceOccurredAt: snapshot.data().sourceOccurredAt,
      fingerprintRepairedAt: now,
      repairNote: "ADR-081 activeDay canonical day-start repair",
    });
  });
}

async function repairPoisonMigrationRecord(db, uid, now) {
  await db.runTransaction(async (transaction) => {
    const reference = db.collection("achievementMigrations").doc(uid);
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return; // nothing left to repair
    const data = snapshot.data();
    if (!isPoisonMigrationRecord(data)) return; // already healthy or repaired
    transaction.set(reference, {
      schemaVersion: MIGRATION_SCHEMA_VERSION,
      uid,
      status: "failed",
      failureCode: "canonical-reconciliation-failed",
      attemptCount: 1,
      updatedAt: now,
      repairedAt: now,
      repairNote: "ADR-081 rewrite of partial pre-fix failure record",
    });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.project !== EXPECTED_PROJECT) {
    console.error(`Refusing to run: --project must be exactly ${EXPECTED_PROJECT}.`);
    process.exit(1);
  }
  const db = getFirestore();
  const now = new Date();

  const activeDayEntries = await scanActiveDayEntries(db);
  const poisonRecords = await scanPoisonMigrationRecords(db);
  const repairable = activeDayEntries.filter((entry) => entry.kind === "repairable");
  const canonical = activeDayEntries.filter((entry) => entry.kind === "canonical");
  const anomalies = activeDayEntries.filter((entry) => entry.kind === "anomaly");

  console.log(`activeDay ledger entries: ${activeDayEntries.length} total, ` +
    `${canonical.length} already canonical, ${repairable.length} repairable, ` +
    `${anomalies.length} anomalies`);
  for (const entry of repairable) {
    console.log(`  repairable ${entry.id}`);
    console.log(`    beneficiary ${redact(entry.data.beneficiaryId)} ` +
      `day ${timestampDate(entry.data.sourceOccurredAt)?.toISOString().slice(0, 10)}`);
    console.log(`    fingerprint ${entry.data.eventFingerprint.slice(0, 12)}… → ` +
      `${entry.canonicalFingerprint.slice(0, 12)}…`);
  }
  for (const entry of anomalies) {
    console.log(`  ANOMALY ${entry.id}: ${entry.reason}`);
  }
  console.log(`poisoned migration records: ${poisonRecords.length}`);
  for (const record of poisonRecords) {
    console.log(`  poisoned ${redact(record.uid)} ` +
      `(keys: ${Object.keys(record.data).sort().join(",")})`);
  }

  if (!args.apply) {
    console.log("\nDry run only. Re-run with --apply to write the repairs above.");
    process.exit(0);
  }
  if (anomalies.length > 0) {
    console.error("\nRefusing to apply: anomalies present. Investigate them first.");
    process.exit(1);
  }

  let repairedEntries = 0;
  for (const entry of repairable) {
    await repairActiveDayEntry(db, entry, now);
    repairedEntries += 1;
  }
  let repairedRecords = 0;
  for (const record of poisonRecords) {
    await repairPoisonMigrationRecord(db, record.uid, now);
    repairedRecords += 1;
  }
  console.log(`\nApplied: ${repairedEntries} ledger entries rewritten to canonical form, ` +
    `${repairedRecords} migration records rewritten to well-formed failure records.`);
  console.log("Re-run without --apply to verify everything now reports canonical/none.");
}

main().then(
  () => process.exit(process.exitCode ?? 0),
  (error) => {
    console.error("REPAIR FAILED:", error.message);
    process.exit(1);
  },
);

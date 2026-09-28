#!/usr/bin/env node
//
// Read-only census of vipGrants/* for "See who liked" (ADR-230).
//
//   node scripts/census_vip_grants.js --project yovoice-ec54a
//
// Only a CANONICAL grant (utils/likers_access.js canonicalLikersVipGrant)
// authorizes seeing likers. Before activation, the operator runs this and
// confirms with Kamil that every grant he expects to count is canonical. A
// non-canonical grant is repaired by the operator, never by widening the
// predicate.
//
// Output is aggregate ONLY: counts per (sorted key set, source, canonical).
// No uid, name, email or grantedBy value is ever printed. It never writes.

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldPath } = require("firebase-admin/firestore");

const { canonicalLikersVipGrant } = require("../utils/likers_access");

const EXPECTED_PROJECT = "yovoice-ec54a";
const PAGE_SIZE = 300;

function parseArgs(argv) {
  const args = { project: null };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--project") args.project = argv[++index] ?? null;
    else throw new Error(`Unknown argument: ${arg}`);
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

// The source is printed only when it is one of a small set of known words;
// anything else is bucketed so a free-text value can never leak.
function sourceLabel(value) {
  if (typeof value !== "string") return `<${value === null ? "null" : typeof value}>`;
  return ["testerProgram", "legacyRoleMigration", "admin"].includes(value)
    ? value
    : "<other string>";
}

// Key names are schema, not user data; a key outside the documented grant
// vocabulary is still bucketed rather than echoed.
const KNOWN_KEYS = new Set([
  "active", "expiresAt", "grantedAt", "grantedBy", "revoked", "revokedAt",
  "source", "updatedAt", "uid", "userId", "reason", "plan", "tier",
]);

function keySetLabel(data) {
  const keys = Object.keys(data ?? {}).sort()
    .map((key) => (KNOWN_KEYS.has(key) ? key : "<other>"));
  return `{${[...new Set(keys)].join(",")}}`;
}

function censusRow(data, nowMs) {
  return [
    keySetLabel(data),
    sourceLabel(data?.source),
    canonicalLikersVipGrant(data, nowMs) ? "canonical" : "NOT canonical",
  ].join(" | ");
}

async function census({
  db,
  nowMs = Date.now(),
  pageSize = PAGE_SIZE,
  documentIdField = FieldPath.documentId(),
}) {
  const counts = new Map();
  let total = 0;
  let last = null;
  for (;;) {
    let query = db.collection("vipGrants").orderBy(documentIdField).limit(pageSize);
    if (last !== null) query = query.startAfter(last);
    const page = await query.get();
    for (const doc of page.docs) {
      const row = censusRow(doc.data(), nowMs);
      counts.set(row, (counts.get(row) ?? 0) + 1);
      total += 1;
    }
    if (page.docs.length < pageSize) break;
    last = page.docs[page.docs.length - 1].id;
  }
  return {
    total,
    canonical: [...counts.entries()]
      .filter(([row]) => row.endsWith("| canonical"))
      .reduce((sum, [, count]) => sum + count, 0),
    rows: Object.fromEntries([...counts.entries()].sort(([a], [b]) => (a < b ? -1 : 1))),
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertProject(args, process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null);
  if (getApps().length === 0) {
    initializeApp({ credential: applicationDefault(), projectId: EXPECTED_PROJECT });
  }
  const report = await census({ db: getFirestore() });
  console.log("MODE: READ ONLY (no writes)");
  console.log(JSON.stringify(report, null, 2));
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
  census,
  censusRow,
  parseArgs,
};

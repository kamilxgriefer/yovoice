#!/usr/bin/env node
//
// Backfill for the publicBadges mirror.
//
//   node scripts/backfill_badges.js --project yovoice-ec54a            # dry run
//   node scripts/backfill_badges.js --project yovoice-ec54a --apply    # writes
//
// YOVOICE_PROTECTED_OWNER_UID must be exported in the environment (same
// value as the Secret Manager secret) — derivation refuses to run
// without the owner guard, because failing safe would demote the real
// owner's badge.
//
// Derives the badge every account SHOULD have — through the same
// deriveBadge() the triggers use, so the two can never disagree — and
// reports the difference against what exists. Dry run is the default;
// --apply is explicit; the project is pinned and anything else refused.
//
// Writes ONLY publicBadges documents. User documents, roles, grants and
// Auth claims are never touched, in either mode.
//
// Apply GATES ITSELF: it first completes a full dry scan, and refuses to
// write anything if that scan found any invalid role or any conflict.
// The badge mirror must not be built on top of an anomaly — fix the
// source first, then run again.
//
// Output is aggregate only. No uid, email or display name is printed.

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

// The badge module reaches utils/firestore, which resolves getFirestore()
// AT LOAD — so the app must exist before that require. Tests initialize
// their own app first and skip this branch.
if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: "yovoice-ec54a",
  });
}

const {
  STAFF_ROLES,
  USER_ROLES,
  protectedOwnerConfigured,
} = require("../utils/roles");
const {
  deriveBadge,
  derivePublicRole,
  BADGE_SCHEMA_VERSION,
  fetchAuthUserOrNull,
  syncPublicBadgeForUser,
} = require("../badges/public_badges");

const EXPECTED_PROJECT = "yovoice-ec54a";
const BATCH_SIZE = 200;

const BADGE_FIELDS = new Set([
  "staffRole",
  "isVip",
  "schemaVersion",
  "updatedAt",
]);

function parseArgs(argv) {
  const args = { apply: false, project: null, batchSize: BATCH_SIZE };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--project") args.project = argv[++i] ?? null;
    else if (arg === "--batch-size") args.batchSize = Number(argv[++i]) || BATCH_SIZE;
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
    throw new Error(
      `Runtime project is ${resolvedProject}, refusing to run against it.`,
    );
  }
}

/// The owner guard must be evaluable BEFORE any derivation runs. Without
/// the secret, derivePublicRole() fails safe and would demote the real
/// owner's badge to superModerator — a wrong write this script must
/// refuse to plan, let alone apply.
function assertOwnerGuard() {
  if (!protectedOwnerConfigured()) {
    throw new Error(
      "YOVOICE_PROTECTED_OWNER_UID is not set; refusing to derive badges " +
        "without the owner guard.",
    );
  }
}

function emptyReport() {
  return {
    scannedUsers: 0,
    scannedBadges: 0,
    authOrphans: 0,
    disabledAuthAccounts: 0,
    staffBadges: 0,
    vipOnlyBadges: 0,
    staffVipBadges: 0,
    toCreate: 0,
    toUpdate: 0,
    toDelete: 0,
    upToDate: 0,
    invalidRoles: 0,
    unconfirmedSuperAdmins: 0,
    conflicts: 0,
    appliedWrites: 0,
    appliedDeletes: 0,
  };
}

/// Compares an existing badge document with the derived one. `updatedAt`
/// is excluded — it is a write timestamp, not derived state.
function badgeMatches(existing, derived) {
  if (!existing) return false;
  // A document carrying fields outside the schema never matches: the
  // sync's merge-free set() will normalise it, and it is counted as a
  // conflict so the operator knows something else wrote here.
  for (const key of Object.keys(existing)) {
    if (!BADGE_FIELDS.has(key)) return false;
  }
  return (
    existing.staffRole === derived.staffRole &&
    existing.isVip === derived.isVip &&
    existing.schemaVersion === derived.schemaVersion
  );
}

/// One pass over users (and the badge collection, for orphans),
/// producing the plan. `uidPrefix` is a TEST SEAM: the emulator runs
/// suites in parallel over one database, so tests bound the scan to
/// their own fixtures. Production runs pass nothing and scan everything.
async function scan({
  db,
  args,
  uidPrefix = null,
  report = emptyReport(),
  fetchAuthUser = fetchAuthUserOrNull,
}) {
  const plans = [];

  let query = db.collection("users").orderBy("__name__");
  if (uidPrefix) {
    query = query.startAt(uidPrefix).endAt(`${uidPrefix}`);
  }

  let cursor = null;
  for (;;) {
    let page = query.limit(args.batchSize);
    if (cursor) page = page.startAfter(cursor);
    const snapshot = await page.get();
    if (snapshot.empty) break;

    for (const document of snapshot.docs) {
      report.scannedUsers += 1;
      const uid = document.id;
      const authUser = await fetchAuthUser(uid);
      const authActive = authUser !== null && authUser?.disabled !== true;
      if (authUser === null) report.authOrphans += 1;
      if (authUser?.disabled === true) report.disabledAuthAccounts += 1;
      // Auth owns identity existence. A historical users/{uid} record may
      // remain after deletion, but it must never be sufficient to plan a new
      // public role/VIP projection.
      const user = authActive ? (document.data() ?? {}) : null;

      if (user !== null) {
        const rawRole = String(user.role ?? USER_ROLES.USER);
        if (!STAFF_ROLES.has(rawRole)) report.invalidRoles += 1;
        // Counted, not blocking: the fail-safe (superModerator) badge is
        // exactly what should be written for a forged superAdmin — refusing
        // to apply would preserve whatever badge the anomaly already has.
        if (derivePublicRole(uid, user).unconfirmedSuperAdmin) {
          report.unconfirmedSuperAdmins += 1;
        }
      }

      const grantSnapshot = await db.collection("vipGrants").doc(uid).get();
      const grant = grantSnapshot.exists ? grantSnapshot.data() : null;
      const badgeSnapshot = await db.collection("publicBadges").doc(uid).get();
      const existing = badgeSnapshot.exists ? badgeSnapshot.data() : null;

      const derived = deriveBadge({ uid, user, grant });

      if (derived === null) {
        if (existing) {
          report.toDelete += 1;
          plans.push({ uid, action: "delete" });
        } else {
          report.upToDate += 1;
        }
        continue;
      }

      const isStaff = derived.staffRole !== USER_ROLES.USER;
      if (isStaff && derived.isVip) report.staffVipBadges += 1;
      else if (isStaff) report.staffBadges += 1;
      else report.vipOnlyBadges += 1;

      if (badgeMatches(existing, derived)) {
        report.upToDate += 1;
        continue;
      }

      if (existing) {
        report.toUpdate += 1;
        const extraFields = Object.keys(existing).some(
          (key) => !BADGE_FIELDS.has(key),
        );
        if (extraFields) report.conflicts += 1;
      } else {
        report.toCreate += 1;
      }
      plans.push({ uid, action: "write", badge: derived });
    }

    cursor = snapshot.docs[snapshot.docs.length - 1].id;
    if (snapshot.size < args.batchSize) break;
  }

  // Orphans: a badge whose user document is gone must be removed — a
  // deleted account may not keep a public badge.
  let badgeQuery = db.collection("publicBadges").orderBy("__name__");
  if (uidPrefix) {
    badgeQuery = badgeQuery.startAt(uidPrefix).endAt(`${uidPrefix}`);
  }
  const badgeSnapshot = await badgeQuery.get();
  for (const document of badgeSnapshot.docs) {
    report.scannedBadges += 1;
    const userSnapshot = await db.collection("users").doc(document.id).get();
    if (!userSnapshot.exists) {
      report.toDelete += 1;
      plans.push({ uid: document.id, action: "delete" });
    }
  }

  return { report, plans };
}

async function backfill({
  db,
  args,
  uidPrefix = null,
  fetchAuthUser = fetchAuthUserOrNull,
}) {
  assertOwnerGuard();
  const { report, plans } = await scan({
    db,
    args,
    uidPrefix,
    fetchAuthUser,
  });

  if (!args.apply) return report;

  // The self-gate: nothing is written on top of an anomaly.
  if (report.invalidRoles > 0 || report.conflicts > 0) {
    throw new Error(
      `Refusing --apply: ${report.invalidRoles} invalid role(s) and ` +
        `${report.conflicts} conflict(s) found. Fix the source data first.`,
    );
  }

  for (const plan of plans) {
    // Re-read both Auth and Firestore at apply time. A deletion/disablement or
    // role change between planning and apply must converge to CURRENT state,
    // never recreate a badge from the stale dry-run page.
    const outcome = await syncPublicBadgeForUser(plan.uid, {
      database: db,
      fetchAuthUser,
    });
    if (outcome.outcome === "written") report.appliedWrites += 1;
    if (outcome.outcome === "removed") report.appliedDeletes += 1;
  }

  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const resolved =
    process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null;
  assertProject(args, resolved);

  const report = await backfill({ db: getFirestore(), args });
  console.log(args.apply ? "MODE: APPLY" : "MODE: DRY RUN (no writes)");
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(String(error.message ?? error));
    process.exit(1);
  });
}

module.exports = {
  parseArgs,
  assertProject,
  assertOwnerGuard,
  badgeMatches,
  scan,
  backfill,
  emptyReport,
  EXPECTED_PROJECT,
  BADGE_SCHEMA_VERSION,
};

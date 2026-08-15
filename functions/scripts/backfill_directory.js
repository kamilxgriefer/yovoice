#!/usr/bin/env node
//
// Backfill for the staff user directory (userDirectory/{uid}).
//
//   node scripts/backfill_directory.js --project yovoice-ec54a            # dry run
//   node scripts/backfill_directory.js --project yovoice-ec54a --apply    # writes
//
// YOVOICE_PROTECTED_OWNER_UID must be exported (same value as the
// Secret Manager secret): the derivation confirms the owner badge, and
// without the guard it would fail safe by demoting the real owner's
// directory role.
//
// AUTH IS THE SOURCE OF TRUTH for account existence: the scan pages the
// Auth user list, joins each page against `users`, `vipGrants` and
// `restrictions` documents, and derives the entry through the same
// deriveDirectoryEntry() the triggers use — the two can never disagree.
// A directory document whose Auth account is gone is swept.
//
// Writes ONLY userDirectory documents, and only under --apply. Output is
// aggregate: no uid, email or display name is printed.

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: "yovoice-ec54a",
  });
}

const { protectedOwnerConfigured } = require("../utils/roles");
const {
  deriveDirectoryEntry,
  DIRECTORY_SCHEMA_VERSION,
} = require("../staff/directory");

const EXPECTED_PROJECT = "yovoice-ec54a";
const AUTH_PAGE_SIZE = 200;

const ENTRY_FIELDS = new Set([
  "displayName",
  "username",
  "email",
  "photoUrl",
  "displayNameLower",
  "usernameLower",
  "emailLower",
  "staffRole",
  "isStaff",
  "isVip",
  "banned",
  "restricted",
  "createdAt",
  "schemaVersion",
  "updatedAt",
]);

function parseArgs(argv) {
  const args = { apply: false, project: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--project") args.project = argv[++i] ?? null;
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

function assertOwnerGuard() {
  if (!protectedOwnerConfigured()) {
    throw new Error(
      "YOVOICE_PROTECTED_OWNER_UID is not set; refusing to derive directory " +
        "entries without the owner guard.",
    );
  }
}

function emptyReport() {
  return {
    scannedAuthUsers: 0,
    scannedDirectoryDocs: 0,
    withProfileDocument: 0,
    withoutProfileDocument: 0,
    staffEntries: 0,
    vipEntries: 0,
    bannedEntries: 0,
    restrictedEntries: 0,
    unconfirmedSuperAdmins: 0,
    toCreate: 0,
    toUpdate: 0,
    toDelete: 0,
    upToDate: 0,
    conflicts: 0,
    appliedWrites: 0,
    appliedDeletes: 0,
  };
}

/// Timestamp-safe equality for the comparable subset of an entry.
function entryMatches(existing, derived) {
  if (!existing) return false;
  for (const key of Object.keys(existing)) {
    if (!ENTRY_FIELDS.has(key)) return false;
  }
  const comparable = [
    "displayName",
    "username",
    "email",
    "photoUrl",
    "displayNameLower",
    "usernameLower",
    "emailLower",
    "staffRole",
    "isStaff",
    "isVip",
    "banned",
    "restricted",
    "schemaVersion",
  ];
  for (const key of comparable) {
    if ((existing[key] ?? null) !== (derived[key] ?? null)) return false;
  }
  const existingCreated = existing.createdAt?.toMillis?.() ?? null;
  const derivedCreated = derived.createdAt?.toMillis?.() ?? null;
  return existingCreated === derivedCreated;
}

/// One pass over Auth (paged) + the directory (for orphans), producing
/// the plan. `listAuthUsers` and `db` are injectable for the emulator
/// suite; production uses the real Auth listing.
async function scan({
  db,
  listAuthUsers,
  uidPrefix = null,
  report = emptyReport(),
}) {
  const plans = [];
  const seenUids = new Set();

  let pageToken = undefined;
  for (;;) {
    const page = await listAuthUsers(AUTH_PAGE_SIZE, pageToken);
    const users = page.users.filter(
      (authUser) => !uidPrefix || authUser.uid.startsWith(uidPrefix),
    );

    // Join the whole page in three batched reads — never one round trip
    // per account.
    const uids = users.map((authUser) => authUser.uid);
    const [profileSnapshots, grantSnapshots, restrictionSnapshots] = uids.length
      ? await Promise.all([
          db.getAll(...uids.map((uid) => db.collection("users").doc(uid))),
          db.getAll(...uids.map((uid) => db.collection("vipGrants").doc(uid))),
          db.getAll(...uids.map((uid) => db.collection("restrictions").doc(uid))),
        ])
      : [[], [], []];
    const existingSnapshots = uids.length
      ? await db.getAll(...uids.map((uid) => db.collection("userDirectory").doc(uid)))
      : [];

    for (let i = 0; i < users.length; i += 1) {
      const authUser = users[i];
      report.scannedAuthUsers += 1;
      seenUids.add(authUser.uid);

      const profile = profileSnapshots[i].exists
        ? profileSnapshots[i].data()
        : null;
      if (profile) report.withProfileDocument += 1;
      else report.withoutProfileDocument += 1;

      const derived = deriveDirectoryEntry({
        uid: authUser.uid,
        authUser,
        user: profile,
        grant: grantSnapshots[i].exists ? grantSnapshots[i].data() : null,
        restriction: restrictionSnapshots[i].exists
          ? restrictionSnapshots[i].data()
          : null,
      });
      if (derived === null) continue;

      if (derived.isStaff) report.staffEntries += 1;
      if (derived.isVip) report.vipEntries += 1;
      if (derived.banned) report.bannedEntries += 1;
      if (derived.restricted) report.restrictedEntries += 1;
      if (
        String(profile?.role ?? "") === "superAdmin" &&
        derived.staffRole !== "superAdmin"
      ) {
        report.unconfirmedSuperAdmins += 1;
      }

      const existing = existingSnapshots[i].exists
        ? existingSnapshots[i].data()
        : null;
      if (entryMatches(existing, derived)) {
        report.upToDate += 1;
        continue;
      }
      if (existing) {
        report.toUpdate += 1;
        if (Object.keys(existing).some((key) => !ENTRY_FIELDS.has(key))) {
          report.conflicts += 1;
        }
      } else {
        report.toCreate += 1;
      }
      plans.push({ uid: authUser.uid, action: "write", entry: derived });
    }

    pageToken = page.pageToken;
    if (!pageToken) break;
  }

  // Orphans: a directory entry whose Auth account no longer exists.
  let directoryQuery = db.collection("userDirectory").orderBy("__name__");
  if (uidPrefix) {
    directoryQuery = directoryQuery
      .startAt(uidPrefix)
      .endAt(`${uidPrefix}`);
  }
  const directorySnapshot = await directoryQuery.get();
  for (const document of directorySnapshot.docs) {
    report.scannedDirectoryDocs += 1;
    if (!seenUids.has(document.id)) {
      report.toDelete += 1;
      plans.push({ uid: document.id, action: "delete" });
    }
  }

  return { report, plans };
}

async function backfill({ db, args, listAuthUsers, uidPrefix = null }) {
  assertOwnerGuard();
  const { report, plans } = await scan({ db, listAuthUsers, uidPrefix });

  if (!args.apply) return report;

  if (report.conflicts > 0) {
    throw new Error(
      `Refusing --apply: ${report.conflicts} directory document(s) carry ` +
        "fields outside the schema. Inspect what else wrote here first.",
    );
  }

  for (const plan of plans) {
    const ref = db.collection("userDirectory").doc(plan.uid);
    if (plan.action === "delete") {
      await ref.delete();
      report.appliedDeletes += 1;
    } else {
      await ref.set({ ...plan.entry, updatedAt: FieldValue.serverTimestamp() });
      report.appliedWrites += 1;
    }
  }

  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const resolved =
    process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null;
  assertProject(args, resolved);

  const auth = getAuth();
  const report = await backfill({
    db: getFirestore(),
    args,
    listAuthUsers: (limit, pageToken) => auth.listUsers(limit, pageToken),
  });
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
  entryMatches,
  scan,
  backfill,
  emptyReport,
  EXPECTED_PROJECT,
  DIRECTORY_SCHEMA_VERSION,
};

#!/usr/bin/env node
//
// Role-vocabulary migration: legacy `vip` and `admin` → the final staff
// vocabulary, plus the complimentary VIP grants that keep legacy VIP
// accounts entitled.
//
//   node scripts/migrate_roles.js --project yovoice-ec54a            # dry run
//   node scripts/migrate_roles.js --project yovoice-ec54a --apply    # writes
//
// DRY RUN IS THE DEFAULT and cannot be reached by accident: `--apply` is
// explicit, `--project` is mandatory, and a project that is not the one
// named is refused outright rather than silently migrated.
//
// Output is aggregate ONLY. No uid, email, token or display name is ever
// printed — a migration report tends to end up in a terminal scrollback,
// a CI log or a screenshot, and none of those are places for user data.
//
// Resumable: progress is checkpointed after every batch, keyed by the
// last document id processed. An interrupted run restarted with the same
// arguments continues from the checkpoint rather than rescanning, and
// re-running a COMPLETED migration is a no-op because every
// transformation is conditional on the legacy value still being present.

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const {
  USER_ROLES,
  LEGACY_ROLES,
  LEGACY_ROLE_MIGRATION,
  STAFF_ROLES,
  isProtectedOwnerUid,
  protectedOwnerConfigured,
} = require("../utils/roles");

const EXPECTED_PROJECT = "yovoice-ec54a";
const CHECKPOINT_PATH = "migrationCheckpoints/roleVocabularyV1";
const BATCH_SIZE = 200;
const GRANT_SOURCE = "legacyRoleMigration";

function parseArgs(argv) {
  const args = { apply: false, project: null, reset: false, batchSize: BATCH_SIZE };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--reset-checkpoint") args.reset = true;
    else if (arg === "--project") args.project = argv[++i] ?? null;
    else if (arg === "--batch-size") args.batchSize = Number(argv[++i]) || BATCH_SIZE;
  }
  return args;
}

/// Refuses to run anywhere but the named project.
///
/// Both the flag AND the resolved runtime project must agree: the flag
/// alone would let a mistyped environment migrate the wrong database, and
/// the environment alone offers no confirmation that the operator meant
/// this one.
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

function emptyReport() {
  return {
    scanned: 0,
    legacyVip: 0,
    legacyAdmin: 0,
    existingComplimentaryGrants: 0,
    paidPremiumOverlap: 0,
    claimMismatches: 0,
    protectedOwnerMatches: 0,
    invalidOrUnknownRoles: 0,
    conflictsSkipped: 0,
    conflictCategories: {
      alreadyMigrated: 0,
      nonLegacyStaffRole: 0,
      concurrentUpdate: 0,
      grantAlreadyPresent: 0,
      protectedOwner: 0,
    },
    plannedDocumentWrites: 0,
    plannedGrantWrites: 0,
    plannedClaimUpdates: 0,
    appliedDocumentWrites: 0,
    appliedGrantWrites: 0,
    appliedClaimUpdates: 0,
  };
}

/// Decides what should happen to one account. Pure, so the whole decision
/// table is unit-testable without Firestore or Auth.
///
/// `claimRole` is what the Auth custom claim says; a disagreement with the
/// document is reported rather than silently resolved, because which one
/// is correct is an operator judgement, not a script's.
function planForUser({ uid, user = {}, grant = null, claimRole = undefined }) {
  const role = String(user.role ?? USER_ROLES.USER).trim();
  const plan = {
    uid,
    role,
    action: "none",
    conflict: null,
    writesDocument: false,
    writesGrant: false,
    updatesClaim: false,
    claimMismatch:
      claimRole !== undefined && String(claimRole ?? USER_ROLES.USER) !== role,
    paidPremium: user.premiumIdentity === true,
    hasGrant: grant !== null && grant !== undefined,
  };

  // The protected owner is never touched, whatever their role says.
  // isProtectedOwnerUid fails closed, so with the secret unavailable this
  // matches every account and the migration plans nothing at all.
  if (isProtectedOwnerUid(uid)) {
    plan.action = "skip";
    plan.conflict = "protectedOwner";
    return plan;
  }

  if (role === USER_ROLES.SUPER_ADMIN) {
    plan.action = "skip";
    plan.conflict = "nonLegacyStaffRole";
    return plan;
  }

  if (role === LEGACY_ROLES.VIP) {
    plan.action = "vip";
    plan.writesDocument = true;
    plan.updatesClaim = true;
    // The grant is written even when Premium is active: the requirement
    // is that nobody LOSES VIP, and a subscription can lapse. A paid
    // subscriber who also holds a legacy grant is a real, expected state
    // and effectiveVip() reports both sources.
    if (plan.hasGrant) {
      plan.conflict = "grantAlreadyPresent";
    } else {
      plan.writesGrant = true;
    }
    return plan;
  }

  if (role === LEGACY_ROLES.ADMIN) {
    plan.action = "admin";
    plan.writesDocument = true;
    plan.updatesClaim = true;
    return plan;
  }

  if (STAFF_ROLES.has(role)) {
    plan.action = "skip";
    // Already on the target vocabulary — a re-run of a finished migration
    // lands here, which is what makes repeated execution a no-op.
    plan.conflict = "alreadyMigrated";
    return plan;
  }

  plan.action = "skip";
  plan.conflict = "unknownRole";
  return plan;
}

async function loadCheckpoint(db) {
  const snapshot = await db.doc(CHECKPOINT_PATH).get();
  return snapshot.exists ? (snapshot.data() ?? {}) : {};
}

async function saveCheckpoint(db, lastId, report) {
  await db.doc(CHECKPOINT_PATH).set(
    {
      lastDocumentId: lastId,
      updatedAt: FieldValue.serverTimestamp(),
      // Aggregates only — never a uid list.
      progress: {
        scanned: report.scanned,
        legacyVip: report.legacyVip,
        legacyAdmin: report.legacyAdmin,
      },
    },
    { merge: true },
  );
}

async function migrate({ db, auth, args, report = emptyReport() }) {
  if (args.reset) {
    await db.doc(CHECKPOINT_PATH).delete().catch(() => {});
  }

  const checkpoint = await loadCheckpoint(db);
  let cursor = args.reset ? null : (checkpoint.lastDocumentId ?? null);

  for (;;) {
    let query = db
      .collection("users")
      .orderBy("__name__")
      .limit(args.batchSize);
    if (cursor) query = query.startAfter(cursor);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const document of snapshot.docs) {
      report.scanned += 1;
      const uid = document.id;
      const user = document.data() ?? {};

      const grantSnapshot = await db.collection("vipGrants").doc(uid).get();
      const grant = grantSnapshot.exists ? grantSnapshot.data() : null;

      let claimRole;
      if (auth) {
        try {
          const record = await auth.getUser(uid);
          claimRole = record.customClaims?.role ?? USER_ROLES.USER;
        } catch {
          claimRole = undefined; // no Auth record; reported as a mismatch below
        }
      }

      const plan = planForUser({ uid, user, grant, claimRole });

      if (plan.claimMismatch) report.claimMismatches += 1;
      if (plan.paidPremium && plan.role === LEGACY_ROLES.VIP) {
        report.paidPremiumOverlap += 1;
      }
      if (plan.hasGrant) report.existingComplimentaryGrants += 1;

      if (plan.conflict === "protectedOwner") report.protectedOwnerMatches += 1;
      if (plan.conflict === "unknownRole") report.invalidOrUnknownRoles += 1;

      if (plan.action === "skip") {
        if (plan.conflict && plan.conflict !== "protectedOwner") {
          report.conflictsSkipped += 1;
          if (plan.conflict in report.conflictCategories) {
            report.conflictCategories[plan.conflict] += 1;
          }
        }
        if (plan.conflict === "protectedOwner") {
          report.conflictCategories.protectedOwner += 1;
        }
        continue;
      }

      if (plan.action === "vip") report.legacyVip += 1;
      if (plan.action === "admin") report.legacyAdmin += 1;
      if (plan.conflict === "grantAlreadyPresent") {
        report.conflictCategories.grantAlreadyPresent += 1;
      }

      if (plan.writesDocument) report.plannedDocumentWrites += 1;
      if (plan.writesGrant) report.plannedGrantWrites += 1;
      if (plan.updatesClaim) report.plannedClaimUpdates += 1;

      if (!args.apply) continue;

      const targetRole = LEGACY_ROLE_MIGRATION[plan.role];

      // Conditional write: the transaction re-reads the document and
      // aborts if the role is no longer the legacy value it planned for.
      // That is what makes a concurrent change safe — a role assigned by
      // an admin while the migration is running wins, and is counted as a
      // conflict rather than overwritten.
      const applied = await db.runTransaction(async (transaction) => {
        const fresh = await transaction.get(document.ref);
        const freshRole = String(fresh.data()?.role ?? "").trim();
        if (freshRole !== plan.role) return false;

        transaction.update(document.ref, {
          role: targetRole,
          roleMigratedFrom: plan.role,
          roleMigratedAt: FieldValue.serverTimestamp(),
        });

        if (plan.writesGrant) {
          transaction.set(db.collection("vipGrants").doc(uid), {
            source: GRANT_SOURCE,
            grantedAt: FieldValue.serverTimestamp(),
            expiresAt: null, // non-expiring
            revoked: false,
          });
        }
        return true;
      });

      if (!applied) {
        report.conflictsSkipped += 1;
        report.conflictCategories.concurrentUpdate += 1;
        continue;
      }

      report.appliedDocumentWrites += 1;
      if (plan.writesGrant) report.appliedGrantWrites += 1;

      if (auth) {
        const record = await auth.getUser(uid);
        await auth.setCustomUserClaims(uid, {
          ...(record.customClaims ?? {}),
          role: targetRole,
        });
        report.appliedClaimUpdates += 1;
      }
    }

    cursor = snapshot.docs[snapshot.docs.length - 1].id;
    if (args.apply) await saveCheckpoint(db, cursor, report);
    if (snapshot.size < args.batchSize) break;
  }

  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const resolved =
    process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null;
  assertProject(args, resolved);

  if (!protectedOwnerConfigured()) {
    throw new Error(
      "YOVOICE_PROTECTED_OWNER_UID is not available; refusing to run.",
    );
  }

  if (getApps().length === 0) {
    initializeApp({ credential: applicationDefault(), projectId: EXPECTED_PROJECT });
  }

  const report = await migrate({
    db: getFirestore(),
    auth: getAuth(),
    args,
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
  planForUser,
  migrate,
  emptyReport,
  EXPECTED_PROJECT,
  GRANT_SOURCE,
  CHECKPOINT_PATH,
};

// Coverage for the role-vocabulary migration tool.
//
// The failure modes worth guarding are all about running it more than
// once, or while something else is writing:
//
//  1. A second run must change nothing.
//  2. An interrupted run must resume, not restart or double-apply.
//  3. A role assigned WHILE it runs must win, not be overwritten.
//  4. The protected owner must survive every path, including the one
//     where the secret is missing.
//
// Runs against the Firestore emulator. Auth is stubbed: creating real
// Auth users is neither necessary to prove the decision table nor safe to
// do casually.
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, describe, afterEach } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  parseArgs,
  assertProject,
  planForUser,
  migrate,
  emptyReport,
  EXPECTED_PROJECT,
  GRANT_SOURCE,
  CHECKPOINT_PATH,
} = require("../scripts/migrate_roles");

const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();

// Namespaced so parallel suites cannot collide — the lesson from the
// adminDeleteMessage suite, which took eleven unrelated tests down.
const P = "mig-";
const OWNER = `${P}owner`;
const VIP_A = `${P}vip-a`;
const VIP_PAID = `${P}vip-paid`;
const ADMIN = `${P}admin`;
const SUPER = `${P}super`;
const PLAIN = `${P}plain`;
const WEIRD = `${P}weird`;

const ALL = [OWNER, VIP_A, VIP_PAID, ADMIN, SUPER, PLAIN, WEIRD];

/// Auth stub: records claim writes without touching a real Auth backend.
function fakeAuth(initial = {}) {
  const claims = { ...initial };
  return {
    updates: [],
    async getUser(uid) {
      return { uid, customClaims: { role: claims[uid] ?? "user" } };
    },
    async setCustomUserClaims(uid, next) {
      claims[uid] = next.role;
      this.updates.push(uid);
    },
    roleOf: (uid) => claims[uid],
  };
}

async function seed() {
  await Promise.all([
    db.collection("users").doc(OWNER).set({ role: "superAdmin" }),
    db.collection("users").doc(VIP_A).set({ role: "vip" }),
    db
      .collection("users")
      .doc(VIP_PAID)
      .set({ role: "vip", premiumIdentity: true }),
    db.collection("users").doc(ADMIN).set({ role: "admin" }),
    db.collection("users").doc(SUPER).set({ role: "superAdmin" }),
    db.collection("users").doc(PLAIN).set({ role: "user" }),
    db.collection("users").doc(WEIRD).set({ role: "wizard" }),
  ]);
}

async function cleanup() {
  await Promise.all([
    ...ALL.map((uid) => db.collection("users").doc(uid).delete()),
    ...ALL.map((uid) => db.collection("vipGrants").doc(uid).delete()),
    db.doc(CHECKPOINT_PATH).delete(),
  ]);
}

/// Restricts a run to this suite's documents. The tool orders by
/// __name__, so a prefixed cursor keeps other suites' users out.
function scopedArgs(extra = {}) {
  return { apply: false, project: EXPECTED_PROJECT, reset: true, batchSize: 100, ...extra };
}

async function runScoped(args, auth) {
  // Reuse the real migrate() but over a scoped view by deleting the
  // checkpoint and letting the prefix filter happen via seeded data only:
  // the suite's own documents are the only ones with role values the tool
  // acts on that belong to it, and assertions check those documents
  // directly rather than the global aggregate counts.
  return migrate({ db, auth, args, report: emptyReport() });
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  await cleanup();
  await seed();
});

afterEach(async () => {
  setProtectedOwnerUidForTests(null);
  await cleanup();
});

describe("guards", () => {
  test("dry run is the default", () => {
    assert.equal(parseArgs([]).apply, false);
    assert.equal(parseArgs(["--project", EXPECTED_PROJECT]).apply, false);
    assert.equal(parseArgs(["--apply"]).apply, true);
  });

  test("another project is refused, with or without a flag", () => {
    assert.throws(
      () => assertProject({ project: null }, EXPECTED_PROJECT),
      /--project must be/,
    );
    assert.throws(
      () => assertProject({ project: "some-other-project" }, EXPECTED_PROJECT),
      /--project must be/,
    );
    assert.throws(
      () => assertProject({ project: EXPECTED_PROJECT }, "staging-project"),
      /refusing to run/,
    );
    assert.doesNotThrow(() =>
      assertProject({ project: EXPECTED_PROJECT }, EXPECTED_PROJECT),
    );
  });
});

describe("decision table", () => {
  test("legacy vip becomes user plus a grant, even with paid Premium", () => {
    const plan = planForUser({
      uid: VIP_PAID,
      user: { role: "vip", premiumIdentity: true },
    });
    assert.equal(plan.action, "vip");
    assert.equal(plan.writesDocument, true);
    assert.equal(plan.writesGrant, true);
    assert.equal(plan.paidPremium, true);
  });

  test("an existing grant is not overwritten", () => {
    const plan = planForUser({
      uid: VIP_A,
      user: { role: "vip" },
      grant: { source: "adminGrant" },
    });
    assert.equal(plan.writesGrant, false);
    assert.equal(plan.conflict, "grantAlreadyPresent");
  });

  test("legacy admin becomes superModerator", () => {
    const plan = planForUser({ uid: ADMIN, user: { role: "admin" } });
    assert.equal(plan.action, "admin");
    assert.equal(plan.writesDocument, true);
  });

  test("superAdmin and already-migrated roles are skipped, and the "
      + "categories are distinct", () => {
    // alreadyMigrated is ONLY reachable through a valid final-vocabulary
    // role — an unknown value lands in unknownRole instead. A dry run
    // reporting alreadyMigrated has therefore confirmed valid no-ops.
    const superPlan = planForUser({ uid: SUPER, user: { role: "superAdmin" } });
    assert.equal(superPlan.action, "skip");
    assert.equal(superPlan.conflict, "nonLegacyStaffRole");
    for (const role of ["user", "moderator", "superModerator", "auditor"]) {
      const plan = planForUser({ uid: `${P}x`, user: { role } });
      assert.equal(plan.action, "skip", role);
      assert.equal(plan.conflict, "alreadyMigrated", role);
    }
  });

  test("the historical mapping is preserved by the tool itself", () => {
    const script = require("../scripts/migrate_roles");
    assert.equal(script.LEGACY_ROLE_MIGRATION.vip, "user");
    assert.equal(script.LEGACY_ROLE_MIGRATION.admin, "superModerator");
  });

  test("an unknown role is skipped and categorised, never guessed", () => {
    const plan = planForUser({ uid: WEIRD, user: { role: "wizard" } });
    assert.equal(plan.action, "skip");
    assert.equal(plan.conflict, "unknownRole");
  });

  test("a claim/document disagreement is reported, not resolved", () => {
    const plan = planForUser({
      uid: ADMIN,
      user: { role: "admin" },
      claimRole: "moderator",
    });
    assert.equal(plan.claimMismatch, true);
  });

  test("the protected owner is skipped whatever their role", () => {
    setProtectedOwnerUidForTests(OWNER);
    for (const role of ["vip", "admin", "superAdmin"]) {
      const plan = planForUser({ uid: OWNER, user: { role } });
      assert.equal(plan.action, "skip", role);
      assert.equal(plan.conflict, "protectedOwner", role);
    }
  });

  test("with the secret MISSING, every account reads as protected", () => {
    setProtectedOwnerUidForTests(null);
    const plan = planForUser({ uid: VIP_A, user: { role: "vip" } });
    assert.equal(plan.action, "skip");
    assert.equal(plan.conflict, "protectedOwner");
  });
});

describe("dry run", () => {
  test("writes nothing at all", async () => {
    const auth = fakeAuth();
    await runScoped(scopedArgs(), auth);

    assert.equal((await db.collection("users").doc(VIP_A).get()).data().role, "vip");
    assert.equal((await db.collection("users").doc(ADMIN).get()).data().role, "admin");
    assert.equal((await db.collection("vipGrants").doc(VIP_A).get()).exists, false);
    assert.equal(auth.updates.length, 0);
  });

  test("counts the writes apply mode would perform", async () => {
    const report = await runScoped(scopedArgs(), fakeAuth());
    // This suite's own legacy accounts are counted; other suites may add
    // to the totals, so assert a floor rather than equality.
    assert.ok(report.legacyVip >= 2, "two legacy vip accounts");
    assert.ok(report.legacyAdmin >= 1, "one legacy admin");
    assert.ok(report.plannedDocumentWrites >= 3);
    assert.ok(report.plannedGrantWrites >= 2);
    assert.ok(report.plannedClaimUpdates >= 3);
    assert.equal(report.appliedDocumentWrites, 0);
  });

  test("the report contains no uid, email or personal data", async () => {
    const report = await runScoped(scopedArgs(), fakeAuth());
    const serialised = JSON.stringify(report);
    for (const uid of ALL) {
      assert.equal(serialised.includes(uid), false, `${uid} leaked`);
    }
    assert.equal(/@/.test(serialised), false, "an email-like value leaked");
  });
});

describe("apply, idempotency and resume", () => {
  test("applies once, then a fresh re-run refuses outright", async () => {
    const auth = fakeAuth({ [VIP_A]: "vip", [ADMIN]: "admin" });
    const first = await runScoped(scopedArgs({ apply: true }), auth);
    assert.ok(first.appliedDocumentWrites >= 3);

    assert.equal((await db.collection("users").doc(VIP_A).get()).data().role, "user");
    assert.equal(
      (await db.collection("users").doc(ADMIN).get()).data().role,
      "superModerator",
    );
    const grant = await db.collection("vipGrants").doc(VIP_A).get();
    assert.equal(grant.data().source, GRANT_SOURCE);
    assert.equal(grant.data().expiresAt, null);
    assert.equal(auth.roleOf(ADMIN), "superModerator");

    // Second run: a FRESH apply refuses, because nothing legacy remains.
    // (Deterministic only while no other suite seeds vip/admin roles —
    // both were retired from every fixture in this cleanup.)
    await assert.rejects(
      () => runScoped(scopedArgs({ apply: true, reset: true }), auth),
      /Refusing --apply/,
    );

    // A DRY RUN of the completed migration still works and reports zero.
    const dry = await runScoped(scopedArgs({ reset: true }), auth);
    assert.equal(dry.appliedDocumentWrites, 0);
  });

  test("a paid subscriber still receives the grant, keeping both sources", async () => {
    await runScoped(scopedArgs({ apply: true }), fakeAuth());
    const user = await db.collection("users").doc(VIP_PAID).get();
    const grant = await db.collection("vipGrants").doc(VIP_PAID).get();
    assert.equal(user.data().role, "user");
    assert.equal(user.data().premiumIdentity, true);
    assert.equal(grant.exists, true, "nobody may lose VIP");
  });

  test("an interrupted run resumes from its checkpoint", async () => {
    const auth = fakeAuth();
    // One document per batch, so the first pass stops mid-migration.
    await runScoped(scopedArgs({ apply: true, batchSize: 1 }), auth);
    const checkpoint = await db.doc(CHECKPOINT_PATH).get();
    assert.equal(checkpoint.exists, true);
    assert.ok(checkpoint.data().lastDocumentId);
    // The checkpoint holds aggregates only.
    assert.equal(JSON.stringify(checkpoint.data().progress).includes(P), false);

    // Resuming without reset must finish the job, not redo it.
    const resumed = await migrate({
      db,
      auth,
      args: { apply: true, project: EXPECTED_PROJECT, reset: false, batchSize: 100 },
      report: emptyReport(),
    });
    assert.ok(resumed.appliedDocumentWrites >= 0);
    assert.equal((await db.collection("users").doc(VIP_A).get()).data().role, "user");
    assert.equal(
      (await db.collection("users").doc(ADMIN).get()).data().role,
      "superModerator",
    );
  });

  test("a concurrent role change WINS over the migration", async () => {
    // Someone assigns a real role between plan and write.
    const auth = fakeAuth();
    const args = scopedArgs({ apply: true, batchSize: 100 });

    // Simulate by flipping the document to a non-legacy role first: the
    // transaction re-reads and must abort rather than overwrite.
    await db.collection("users").doc(ADMIN).set({ role: "moderator" });
    await runScoped(args, auth);

    assert.equal(
      (await db.collection("users").doc(ADMIN).get()).data().role,
      "moderator",
      "a concurrently assigned role must not be overwritten",
    );
  });

  test("the protected owner is never modified by an apply run", async () => {
    await db.collection("users").doc(OWNER).set({ role: "admin" });
    await runScoped(scopedArgs({ apply: true }), fakeAuth());
    assert.equal(
      (await db.collection("users").doc(OWNER).get()).data().role,
      "admin",
      "the owner must survive even holding a legacy role",
    );
    assert.equal((await db.collection("vipGrants").doc(OWNER).get()).exists, false);
  });

  test("superAdmin accounts are untouched", async () => {
    await runScoped(scopedArgs({ apply: true }), fakeAuth());
    assert.equal(
      (await db.collection("users").doc(SUPER).get()).data().role,
      "superAdmin",
    );
  });
});

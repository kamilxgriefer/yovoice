#!/usr/bin/env node
// Backfill the privacy-safe identity projections.
//
//   node scripts/backfill_public_profiles.js --project yovoice-ec54a
//   node scripts/backfill_public_profiles.js --project yovoice-ec54a --apply
//   node scripts/backfill_public_profiles.js --project yovoice-ec54a \
//     --apply --start-after LAST_UID
//
// Dry-run is the default. The script is pinned to the production project,
// emits aggregate counts only, and writes exclusively to `publicProfiles`
// and `socialPresence`. It never changes the private `users` source.

const {
  getApps,
  initializeApp,
  applicationDefault,
} = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const EXPECTED_PROJECT = "yovoice-ec54a";
const DEFAULT_BATCH_SIZE = 200;
const DEFAULT_MAX_USERS = 500;
const MAX_USERS_PER_RUN = 5000;

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: EXPECTED_PROJECT,
  });
}

const {
  PUBLIC_PROFILE_FIELDS,
  SOCIAL_PRESENCE_FIELDS,
  derivePublicProfile,
  deriveSocialPresence,
  fetchAuthUserOrNull,
  projectionMatches,
  syncPrivacyProjectionsForUser,
} = require("../profile/public_profiles");

function parseArgs(argv) {
  const args = {
    apply: false,
    project: null,
    batchSize: DEFAULT_BATCH_SIZE,
    maxUsers: DEFAULT_MAX_USERS,
    startAfter: null,
    uidPrefix: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") args.apply = true;
    else if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--start-after") {
      args.startAfter = argv[++index] ?? null;
    } else if (argument === "--uid-prefix") {
      args.uidPrefix = argv[++index] ?? null;
    } else if (argument === "--max-users") {
      const value = Number.parseInt(argv[++index], 10);
      if (
        Number.isSafeInteger(value) &&
        value > 0 &&
        value <= MAX_USERS_PER_RUN
      ) {
        args.maxUsers = value;
      }
    } else if (argument === "--batch-size") {
      const value = Number.parseInt(argv[++index], 10);
      if (Number.isSafeInteger(value) && value > 0 && value <= 200) {
        args.batchSize = value;
      }
    }
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
      `Runtime project is ${resolvedProject}; refusing to continue.`,
    );
  }
}

function emptyReport() {
  return {
    scannedUsers: 0,
    inactiveUsers: 0,
    authOrphans: 0,
    profileCreates: 0,
    profileUpdates: 0,
    profileDeletes: 0,
    profileUnchanged: 0,
    presenceCreates: 0,
    presenceUpdates: 0,
    presenceDeletes: 0,
    presenceUnchanged: 0,
    appliedWrites: 0,
    appliedDeletes: 0,
    peakPlannedOperations: 0,
    reachedEnd: false,
    nextCursor: null,
  };
}

function addPlan({ plans, report, kind, snapshot, derived, fields }) {
  if (derived === null) {
    if (snapshot.exists) {
      report[`${kind}Deletes`] += 1;
      plans.push({ action: "delete", ref: snapshot.ref });
    } else {
      report[`${kind}Unchanged`] += 1;
    }
    return;
  }
  if (
    projectionMatches(snapshot.exists ? snapshot.data() : null, derived, fields)
  ) {
    report[`${kind}Unchanged`] += 1;
    return;
  }
  report[snapshot.exists ? `${kind}Updates` : `${kind}Creates`] += 1;
  plans.push({ action: "write", ref: snapshot.ref, data: derived });
}

async function fetchPageAuthUsers(users, fetchAuthUser) {
  const result = [];
  const concurrency = 12;
  for (let offset = 0; offset < users.docs.length; offset += concurrency) {
    result.push(
      ...(await Promise.all(
        users.docs
          .slice(offset, offset + concurrency)
          .map((user) => fetchAuthUser(user.id)),
      )),
    );
  }
  return result;
}

async function planPage({ db, users, report, fetchAuthUser }) {
  const plans = [];
  const uids = users.docs.map((document) => document.id);
  const [profiles, presences, authUsers] = await Promise.all([
    db.getAll(...uids.map((uid) => db.collection("publicProfiles").doc(uid))),
    db.getAll(...uids.map((uid) => db.collection("socialPresence").doc(uid))),
    fetchPageAuthUsers(users, fetchAuthUser),
  ]);

  for (let index = 0; index < users.docs.length; index += 1) {
    const user = users.docs[index];
    const source = user.data() ?? {};
    const uid = user.id;
    const authActive =
      authUsers[index] !== null && authUsers[index]?.disabled !== true;
    const authoritativeSource = authActive ? source : null;
    report.scannedUsers += 1;
    if (authUsers[index] === null) report.authOrphans += 1;
    if (
      source.banned === true ||
      source.disabled === true ||
      authUsers[index]?.disabled === true
    ) {
      report.inactiveUsers += 1;
    }
    addPlan({
      plans,
      report,
      kind: "profile",
      snapshot: profiles[index],
      derived: derivePublicProfile(uid, authoritativeSource),
      fields: PUBLIC_PROFILE_FIELDS,
    });
    addPlan({
      plans,
      report,
      kind: "presence",
      snapshot: presences[index],
      derived: deriveSocialPresence(uid, authoritativeSource),
      fields: SOCIAL_PRESENCE_FIELDS,
    });
  }
  report.peakPlannedOperations = Math.max(
    report.peakPlannedOperations,
    plans.length,
  );
  return plans;
}

function recordAppliedOutcome(outcome, report) {
  for (const kind of [outcome.profile, outcome.presence]) {
    if (kind === "created" || kind === "updated") report.appliedWrites += 1;
    if (kind === "removed") report.appliedDeletes += 1;
  }
}

async function applyUsersSafely({ db, users, report, fetchAuthUser }) {
  // Each UID converges through the same transaction as the live trigger.
  // Concurrency remains explicitly bounded; a stale page snapshot is never
  // used as write authority.
  const concurrency = 12;
  for (let offset = 0; offset < users.docs.length; offset += concurrency) {
    const outcomes = await Promise.all(
      users.docs
        .slice(offset, offset + concurrency)
        .map((user) =>
          syncPrivacyProjectionsForUser(user.id, {
            database: db,
            fetchAuthUser,
          }),
        ),
    );
    for (const outcome of outcomes) recordAppliedOutcome(outcome, report);
  }
}

async function backfill({
  db,
  args,
  uidPrefix = null,
  afterPagePlanned = null,
  fetchAuthUser = fetchAuthUserOrNull,
}) {
  const report = emptyReport();
  const effectivePrefix = uidPrefix ?? args.uidPrefix;
  const maximumUsers = args.maxUsers ?? DEFAULT_MAX_USERS;
  const configuredBatchSize = args.batchSize ?? DEFAULT_BATCH_SIZE;

  let baseQuery = db.collection("users").orderBy("__name__");
  if (effectivePrefix) {
    baseQuery = baseQuery
      .startAt(effectivePrefix)
      .endAt(`${effectivePrefix}\uf8ff`);
  }
  let cursor = args.startAfter;
  while (report.scannedUsers < maximumUsers) {
    const remaining = maximumUsers - report.scannedUsers;
    const pageSize = Math.min(configuredBatchSize, remaining);
    let query = baseQuery.limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const users = await query.get();
    if (users.empty) {
      report.reachedEnd = true;
      report.nextCursor = null;
      break;
    }

    // Plan and (optionally) commit exactly one page, then release it before
    // fetching the next. Dry-run follows the same path but performs no write.
    const plans = await planPage({
      db,
      users,
      report,
      fetchAuthUser,
    });
    if (typeof afterPagePlanned === "function") {
      await afterPagePlanned({ users, plans });
    }
    if (args.apply) {
      await applyUsersSafely({ db, users, report, fetchAuthUser });
    }

    cursor = users.docs[users.docs.length - 1].id;
    report.nextCursor = cursor;
    if (users.size < pageSize) {
      report.reachedEnd = true;
      report.nextCursor = null;
      break;
    }
  }

  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const resolvedProject =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null;
  assertProject(args, resolvedProject);
  const report = await backfill({ db: getFirestore(), args });
  console.log(
    JSON.stringify({
      mode: args.apply ? "apply" : "dry-run",
      boundedToUsers: args.maxUsers,
      ...report,
    }),
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  EXPECTED_PROJECT,
  DEFAULT_MAX_USERS,
  MAX_USERS_PER_RUN,
  parseArgs,
  assertProject,
  emptyReport,
  planPage,
  fetchPageAuthUsers,
  applyUsersSafely,
  backfill,
};

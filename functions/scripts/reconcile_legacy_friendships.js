#!/usr/bin/env node
// Operator-only reconciliation for explicitly reviewed legacy friendships.
//
// Dry-run is mandatory first:
//   node scripts/reconcile_legacy_friendships.js \
//     --project yovoice-ec54a --allowlist /secure/reviewed-pairs.json
//
// Apply requires the digest emitted by that dry-run:
//   node scripts/reconcile_legacy_friendships.js \
//     --project yovoice-ec54a --allowlist /secure/reviewed-pairs.json \
//     --apply --confirm-digest <dry-run digest>
//
// The script never discovers or scans friendships. It considers only the
// explicit pairs in the reviewed file, defaults to dry-run, emits aggregate
// counts only, and creates the two exact server friendship guards atomically.
// Legacy mirrors were client-writable and are not proof by themselves. An
// operator must place a pair here only after independent, server-trusted
// evidence has been reviewed; this script merely re-validates that decision.
// Reviewed file schema:
//   {"schemaVersion":2,"reviewedPairs":[
//     {"firstUserId":"uid-a","secondUserId":"uid-b",
//      "legacyEstablishedAt":{"seconds":1754672178,
//                             "nanoseconds":468123000}}
//   ]}

const { createHash } = require("node:crypto");
const { readFileSync, statSync } = require("node:fs");

const {
  applicationDefault,
  getApps,
  initializeApp,
} = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const EXPECTED_PROJECT = "yovoice-ec54a";
const MANIFEST_SCHEMA_VERSION = 2;
const MAX_REVIEWED_PAIRS = 100;
const MAX_ALLOWLIST_BYTES = 64 * 1024;
const UID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/u;
const DIGEST_PATTERN = /^[a-f0-9]{64}$/u;

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    projectId: EXPECTED_PROJECT,
  });
}

const { restrictionIsActive } = require("../notifications/canonical");

const CONFLICT = Object.freeze({
  authUserMissing: "auth-user-missing",
  authUserDisabled: "auth-user-disabled",
  emailUnverified: "email-unverified",
  profileMissing: "profile-missing",
  profileInactive: "profile-inactive",
  profileIdentityMismatch: "profile-identity-mismatch",
  mirrorMissing: "legacy-mirror-missing",
  mirrorShapeInvalid: "legacy-mirror-shape-invalid",
  mirrorTimestampInvalid: "legacy-mirror-timestamp-invalid",
  mirrorTimestampMismatch: "legacy-mirror-timestamp-mismatch",
  blocked: "blocked",
  restricted: "communication-restricted",
  guardInconsistent: "friendship-guard-inconsistent",
  guardShapeInvalid: "friendship-guard-shape-invalid",
  guardTimestampMismatch: "friendship-guard-timestamp-mismatch",
});

class ReconciliationRefusal extends Error {
  constructor(message, report) {
    super(message);
    this.name = "ReconciliationRefusal";
    this.report = report;
  }
}

function parseArgs(argv) {
  const args = {
    apply: false,
    project: null,
    allowlistPath: null,
    confirmDigest: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") {
      args.apply = true;
    } else if (argument === "--project") {
      args.project = argv[++index] ?? null;
    } else if (argument === "--allowlist") {
      args.allowlistPath = argv[++index] ?? null;
    } else if (argument === "--confirm-digest") {
      args.confirmDigest = argv[++index] ?? null;
    } else {
      throw new Error("Unknown argument; refusing to continue.");
    }
  }
  return args;
}

function assertArgs(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(`--project must be ${EXPECTED_PROJECT}.`);
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error("Runtime project does not match the pinned project.");
  }
  if (typeof args.allowlistPath !== "string" || !args.allowlistPath) {
    throw new Error("--allowlist is required.");
  }
  if (args.apply && !DIGEST_PATTERN.test(args.confirmDigest ?? "")) {
    throw new Error(
      "--apply requires --confirm-digest from a successful dry-run.",
    );
  }
  if (!args.apply && args.confirmDigest !== null) {
    throw new Error("--confirm-digest is valid only with --apply.");
  }
}

function exactKeys(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index]);
}

function normalizeManifest(input) {
  if (!exactKeys(input, ["schemaVersion", "reviewedPairs"]) ||
      input.schemaVersion !== MANIFEST_SCHEMA_VERSION ||
      !Array.isArray(input.reviewedPairs) ||
      input.reviewedPairs.length === 0 ||
      input.reviewedPairs.length > MAX_REVIEWED_PAIRS) {
    throw new Error("The reviewed allowlist has an invalid envelope.");
  }

  const seen = new Set();
  const reviewedPairs = input.reviewedPairs.map((candidate) => {
    if (!exactKeys(candidate, [
      "firstUserId",
      "secondUserId",
      "legacyEstablishedAt",
    ])) {
      throw new Error("A reviewed pair has an invalid shape.");
    }
    const firstCandidate = candidate.firstUserId;
    const secondCandidate = candidate.secondUserId;
    const establishedAt = candidate.legacyEstablishedAt;
    if (!UID_PATTERN.test(firstCandidate ?? "") ||
        !UID_PATTERN.test(secondCandidate ?? "") ||
        firstCandidate === secondCandidate ||
        !exactKeys(establishedAt, ["nanoseconds", "seconds"]) ||
        !Number.isSafeInteger(establishedAt.seconds) ||
        establishedAt.seconds <= 0 ||
        !Number.isInteger(establishedAt.nanoseconds) ||
        establishedAt.nanoseconds < 0 ||
        establishedAt.nanoseconds > 999_999_999 ||
        // Firestore persists timestamps at microsecond precision. A finer
        // value could not be reproduced exactly in a canonical guard.
        establishedAt.nanoseconds % 1_000 !== 0) {
      throw new Error("A reviewed pair contains invalid values.");
    }
    try {
      // Let the Admin SDK enforce Firestore's supported timestamp range too.
      new Timestamp(establishedAt.seconds, establishedAt.nanoseconds);
    } catch (_) {
      throw new Error("A reviewed pair contains invalid values.");
    }
    const [firstUserId, secondUserId] =
      [firstCandidate, secondCandidate].sort();
    const pairKey = `${firstUserId}\u0000${secondUserId}`;
    if (seen.has(pairKey)) {
      throw new Error("The reviewed allowlist contains a duplicate pair.");
    }
    seen.add(pairKey);
    return {
      firstUserId,
      secondUserId,
      legacyEstablishedAt: {
        seconds: establishedAt.seconds,
        nanoseconds: establishedAt.nanoseconds,
      },
    };
  });
  reviewedPairs.sort((first, second) => {
    const firstKey = `${first.firstUserId}\u0000${first.secondUserId}`;
    const secondKey = `${second.firstUserId}\u0000${second.secondUserId}`;
    return firstKey < secondKey ? -1 : firstKey > secondKey ? 1 : 0;
  });
  return { schemaVersion: MANIFEST_SCHEMA_VERSION, reviewedPairs };
}

function allowlistDigest(manifest) {
  return createHash("sha256")
    .update(JSON.stringify(normalizeManifest(manifest)))
    .digest("hex");
}

function loadAllowlist(path) {
  const stat = statSync(path);
  if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_ALLOWLIST_BYTES) {
    throw new Error("The reviewed allowlist file is empty or too large.");
  }
  return normalizeManifest(JSON.parse(readFileSync(path, "utf8")));
}

function timestampParts(value) {
  if (!value || typeof value.toMillis !== "function" ||
      !Number.isSafeInteger(value.seconds) ||
      !Number.isInteger(value.nanoseconds) ||
      value.nanoseconds < 0 || value.nanoseconds > 999_999_999) {
    return null;
  }
  return { seconds: value.seconds, nanoseconds: value.nanoseconds };
}

function timestampsEqual(first, second) {
  return first !== null && second !== null &&
    first.seconds === second.seconds &&
    first.nanoseconds === second.nanoseconds;
}

function compareTimestamps(first, second) {
  if (first.seconds !== second.seconds) {
    return first.seconds < second.seconds ? -1 : 1;
  }
  if (first.nanoseconds === second.nanoseconds) return 0;
  return first.nanoseconds < second.nanoseconds ? -1 : 1;
}

function profileConflict(snapshot, userId) {
  if (!snapshot.exists) return CONFLICT.profileMissing;
  const data = snapshot.data() ?? {};
  if (Object.hasOwn(data, "uid") && data.uid !== userId) {
    return CONFLICT.profileIdentityMismatch;
  }
  if (data.banned === true || data.disabled === true ||
      data.deleted === true || data.status === "deleted") {
    return CONFLICT.profileInactive;
  }
  return null;
}

function exactLegacyMirror(snapshot, friendId, expectedTimestamp) {
  if (!snapshot.exists) return { conflict: CONFLICT.mirrorMissing };
  const data = snapshot.data() ?? {};
  const establishedAt = timestampParts(data.createdAt);
  if (!exactKeys(data, ["createdAt", "userId"]) ||
      data.userId !== friendId ||
      establishedAt === null) {
    return { conflict: CONFLICT.mirrorShapeInvalid };
  }
  if (!timestampsEqual(establishedAt, expectedTimestamp)) {
    return { conflict: CONFLICT.mirrorTimestampMismatch };
  }
  return { conflict: null };
}

function exactCanonicalGuard(snapshot, ownerId, friendId) {
  if (!snapshot.exists) {
    return { exists: false, conflict: null, timestamp: null };
  }
  const data = snapshot.data() ?? {};
  const establishedAt = timestampParts(data.establishedAt);
  if (!exactKeys(data, [
    "establishedAt",
    "friendId",
    "ownerId",
    "schemaVersion",
  ]) || data.ownerId !== ownerId || data.friendId !== friendId ||
      data.schemaVersion !== 1 || establishedAt === null) {
    return {
      exists: true,
      conflict: CONFLICT.guardShapeInvalid,
      timestamp: null,
    };
  }
  return {
    exists: true,
    conflict: null,
    timestamp: establishedAt,
  };
}

function pairReferences(db, pair) {
  const { firstUserId: first, secondUserId: second } = pair;
  return [
    db.doc(`users/${first}`),
    db.doc(`users/${second}`),
    db.doc(`users/${first}/friends/${second}`),
    db.doc(`users/${second}/friends/${first}`),
    db.doc(`users/${first}/blocked/${second}`),
    db.doc(`users/${second}/blocked/${first}`),
    db.doc(`restrictions/${first}`),
    db.doc(`restrictions/${second}`),
    db.doc(`friendshipGuards/${first}/friends/${second}`),
    db.doc(`friendshipGuards/${second}/friends/${first}`),
  ];
}

function evaluatePairState(pair, snapshots, nowMillis) {
  const firstProfile = profileConflict(snapshots[0], pair.firstUserId);
  if (firstProfile) return { status: "conflict", reason: firstProfile };
  const secondProfile = profileConflict(snapshots[1], pair.secondUserId);
  if (secondProfile) return { status: "conflict", reason: secondProfile };
  const nowTimestamp = timestampParts(Timestamp.fromMillis(nowMillis));
  if (nowTimestamp === null ||
      compareTimestamps(pair.legacyEstablishedAt, nowTimestamp) > 0) {
    return { status: "conflict", reason: CONFLICT.mirrorTimestampInvalid };
  }

  const firstMirror = exactLegacyMirror(
    snapshots[2],
    pair.secondUserId,
    pair.legacyEstablishedAt,
  );
  if (firstMirror.conflict) {
    return { status: "conflict", reason: firstMirror.conflict };
  }
  const secondMirror = exactLegacyMirror(
    snapshots[3],
    pair.firstUserId,
    pair.legacyEstablishedAt,
  );
  if (secondMirror.conflict) {
    return { status: "conflict", reason: secondMirror.conflict };
  }
  if (snapshots[4].exists || snapshots[5].exists) {
    return { status: "conflict", reason: CONFLICT.blocked };
  }
  if (restrictionIsActive(
    snapshots[6].exists ? snapshots[6].data() : null,
    nowMillis,
  ) || restrictionIsActive(
    snapshots[7].exists ? snapshots[7].data() : null,
    nowMillis,
  )) {
    return { status: "conflict", reason: CONFLICT.restricted };
  }

  const firstGuard = exactCanonicalGuard(
    snapshots[8],
    pair.firstUserId,
    pair.secondUserId,
  );
  const secondGuard = exactCanonicalGuard(
    snapshots[9],
    pair.secondUserId,
    pair.firstUserId,
  );
  if (firstGuard.exists !== secondGuard.exists) {
    return { status: "conflict", reason: CONFLICT.guardInconsistent };
  }
  if (firstGuard.conflict || secondGuard.conflict) {
    return { status: "conflict", reason: CONFLICT.guardShapeInvalid };
  }
  if (!firstGuard.exists) return { status: "eligible" };
  if (!timestampsEqual(firstGuard.timestamp, pair.legacyEstablishedAt) ||
      !timestampsEqual(secondGuard.timestamp, pair.legacyEstablishedAt) ||
      !timestampsEqual(firstGuard.timestamp, secondGuard.timestamp)) {
    return { status: "conflict", reason: CONFLICT.guardTimestampMismatch };
  }
  return { status: "alreadyCanonical" };
}

async function authPairConflict(auth, pair) {
  let users;
  try {
    users = await Promise.all([
      auth.getUser(pair.firstUserId),
      auth.getUser(pair.secondUserId),
    ]);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return CONFLICT.authUserMissing;
    throw new Error("Firebase Authentication could not be re-read safely.");
  }
  if (users.some((user) => user.disabled === true)) {
    return CONFLICT.authUserDisabled;
  }
  if (users.some((user) => user.emailVerified !== true)) {
    return CONFLICT.emailUnverified;
  }
  return null;
}

async function inspectPair({ db, auth, pair, nowMillis }) {
  const authConflict = await authPairConflict(auth, pair);
  if (authConflict) return { status: "conflict", reason: authConflict };
  const snapshots = await db.getAll(...pairReferences(db, pair));
  return evaluatePairState(pair, snapshots, nowMillis);
}

async function inspectAllowlist({ db, auth, manifest, nowMillis }) {
  const states = [];
  const concurrency = 8;
  for (let offset = 0; offset < manifest.reviewedPairs.length; offset += concurrency) {
    states.push(...await Promise.all(
      manifest.reviewedPairs.slice(offset, offset + concurrency).map((pair) =>
        inspectPair({ db, auth, pair, nowMillis }),
      ),
    ));
  }
  return states;
}

function aggregateReport({ args, digest, states, appliedPairs = 0 }) {
  const conflictReasons = {};
  for (const state of states) {
    if (state.status !== "conflict") continue;
    conflictReasons[state.reason] = (conflictReasons[state.reason] ?? 0) + 1;
  }
  return {
    mode: args.apply ? "apply" : "dry-run",
    boundedToPairs: MAX_REVIEWED_PAIRS,
    allowlistDigest: digest,
    reviewedPairs: states.length,
    eligiblePairs: states.filter((state) => state.status === "eligible").length,
    alreadyCanonicalPairs: states.filter(
      (state) => state.status === "alreadyCanonical",
    ).length,
    conflicts: states.filter((state) => state.status === "conflict").length,
    conflictReasons: Object.fromEntries(
      Object.entries(conflictReasons).sort(([first], [second]) =>
        first.localeCompare(second),
      ),
    ),
    appliedPairs,
    appliedGuards: appliedPairs * 2,
  };
}

function refusalFor(report) {
  return new ReconciliationRefusal(
    "The reviewed allowlist is no longer eligible; no new writes were started.",
    report,
  );
}

async function reconcilePairAtomically({ db, auth, pair, nowMillis }) {
  // Auth and Firestore do not share a transaction boundary. Re-read Auth
  // immediately before the Firestore transaction, then re-read every
  // Firestore predicate inside that transaction before either guard is made.
  const authConflict = await authPairConflict(auth, pair);
  if (authConflict) return { status: "conflict", reason: authConflict };

  return db.runTransaction(async (transaction) => {
    const refs = pairReferences(db, pair);
    const snapshots = await transaction.getAll(...refs);
    const state = evaluatePairState(pair, snapshots, nowMillis);
    if (state.status !== "eligible") return state;
    const establishedAt = new Timestamp(
      pair.legacyEstablishedAt.seconds,
      pair.legacyEstablishedAt.nanoseconds,
    );
    transaction.create(refs[8], {
      ownerId: pair.firstUserId,
      friendId: pair.secondUserId,
      schemaVersion: 1,
      establishedAt,
    });
    transaction.create(refs[9], {
      ownerId: pair.secondUserId,
      friendId: pair.firstUserId,
      schemaVersion: 1,
      establishedAt,
    });
    return { status: "applied" };
  });
}

async function reconcileLegacyFriendships({
  db,
  auth,
  args,
  manifest,
  clock = Date.now,
  beforeApply = null,
  beforePairApply = null,
}) {
  const normalized = normalizeManifest(manifest);
  const digest = allowlistDigest(normalized);
  if (args.apply && args.confirmDigest !== digest) {
    throw new Error("The allowlist digest changed after review; refusing apply.");
  }

  const initialStates = await inspectAllowlist({
    db,
    auth,
    manifest: normalized,
    nowMillis: clock(),
  });
  const initialReport = aggregateReport({ args, digest, states: initialStates });
  if (!args.apply) return initialReport;
  if (initialReport.conflicts > 0) throw refusalFor(initialReport);

  if (typeof beforeApply === "function") await beforeApply();
  // A second complete readiness pass ensures a change between dry planning
  // and apply prevents every write, not merely the affected pair's write.
  const readinessStates = await inspectAllowlist({
    db,
    auth,
    manifest: normalized,
    nowMillis: clock(),
  });
  const readinessReport = aggregateReport({ args, digest, states: readinessStates });
  if (readinessReport.conflicts > 0) throw refusalFor(readinessReport);

  let appliedPairs = 0;
  const finalStates = [];
  for (let index = 0; index < normalized.reviewedPairs.length; index += 1) {
    if (typeof beforePairApply === "function") await beforePairApply(index);
    const state = await reconcilePairAtomically({
      db,
      auth,
      pair: normalized.reviewedPairs[index],
      nowMillis: clock(),
    });
    finalStates.push(state);
    if (state.status === "applied") appliedPairs += 1;
    if (state.status === "conflict") {
      throw new ReconciliationRefusal(
        "A reviewed pair changed during apply; remaining pairs were not written.",
        aggregateReport({ args, digest, states: finalStates, appliedPairs }),
      );
    }
  }
  // Applied pairs are now canonical; expose their reviewed eligibility plus
  // the exact number of writes without retaining any identities in output.
  return aggregateReport({
    args,
    digest,
    states: readinessStates,
    appliedPairs,
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const resolvedProject =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null;
  assertArgs(args, resolvedProject);
  const manifest = loadAllowlist(args.allowlistPath);
  const report = await reconcileLegacyFriendships({
    db: getFirestore(),
    auth: getAuth(),
    args,
    manifest,
  });
  console.log(JSON.stringify(report));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(JSON.stringify({
      status: "refused",
      message: error instanceof ReconciliationRefusal
        ? error.message
        : "The reconciliation could not be completed safely.",
      ...(error instanceof ReconciliationRefusal ? { report: error.report } : {}),
    }));
    process.exitCode = 1;
  });
}

module.exports = {
  CONFLICT,
  EXPECTED_PROJECT,
  MANIFEST_SCHEMA_VERSION,
  MAX_REVIEWED_PAIRS,
  ReconciliationRefusal,
  aggregateReport,
  allowlistDigest,
  assertArgs,
  authPairConflict,
  evaluatePairState,
  exactCanonicalGuard,
  exactLegacyMirror,
  inspectAllowlist,
  inspectPair,
  loadAllowlist,
  normalizeManifest,
  parseArgs,
  reconcileLegacyFriendships,
  reconcilePairAtomically,
};

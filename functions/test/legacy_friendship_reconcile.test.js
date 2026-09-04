const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const {
  CONFLICT,
  EXPECTED_PROJECT,
  ReconciliationRefusal,
  allowlistDigest,
  assertArgs,
  normalizeManifest,
  parseArgs,
  reconcileLegacyFriendships,
} = require("../scripts/reconcile_legacy_friendships");

const db = getFirestore();
const FIRST = "legacy-friend-reconcile-a";
const SECOND = "legacy-friend-reconcile-b";
const ESTABLISHED_AT = Object.freeze({
  seconds: 1_754_672_178,
  nanoseconds: 468_123_000,
});
const ESTABLISHED_AT_MILLIS =
  ESTABLISHED_AT.seconds * 1000 +
  Math.floor(ESTABLISHED_AT.nanoseconds / 1_000_000);

function firestoreTimestamp(parts = ESTABLISHED_AT) {
  return new Timestamp(parts.seconds, parts.nanoseconds);
}

class FakeAuth {
  constructor(overrides = {}) {
    this.overrides = overrides;
    this.reads = new Map();
  }

  async getUser(uid) {
    this.reads.set(uid, (this.reads.get(uid) ?? 0) + 1);
    const override = this.overrides[uid];
    if (override === "missing") {
      const error = new Error("not found");
      error.code = "auth/user-not-found";
      throw error;
    }
    return {
      uid,
      disabled: false,
      emailVerified: true,
      ...(override ?? {}),
    };
  }
}

function manifest(overrides = {}) {
  return {
    schemaVersion: 2,
    reviewedPairs: [{
      firstUserId: FIRST,
      secondUserId: SECOND,
      legacyEstablishedAt: { ...ESTABLISHED_AT },
      ...overrides,
    }],
  };
}

function dryRunArgs() {
  return {
    apply: false,
    project: EXPECTED_PROJECT,
    allowlistPath: "/operator/reviewed.json",
    confirmDigest: null,
  };
}

function applyArgs(reviewedManifest = manifest()) {
  return {
    ...dryRunArgs(),
    apply: true,
    confirmDigest: allowlistDigest(reviewedManifest),
  };
}

async function wipe() {
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${FIRST}`)),
    db.recursiveDelete(db.doc(`users/${SECOND}`)),
    db.recursiveDelete(db.doc(`friendshipGuards/${FIRST}`)),
    db.recursiveDelete(db.doc(`friendshipGuards/${SECOND}`)),
    db.doc(`restrictions/${FIRST}`).delete(),
    db.doc(`restrictions/${SECOND}`).delete(),
  ]);
}

async function seedEligible() {
  const createdAt = firestoreTimestamp();
  await Promise.all([
    db.doc(`users/${FIRST}`).set({ uid: FIRST, disabled: false, banned: false }),
    db.doc(`users/${SECOND}`).set({ uid: SECOND, disabled: false, banned: false }),
    db.doc(`users/${FIRST}/friends/${SECOND}`).set({ userId: SECOND, createdAt }),
    db.doc(`users/${SECOND}/friends/${FIRST}`).set({ userId: FIRST, createdAt }),
  ]);
}

async function guardSnapshots() {
  return db.getAll(
    db.doc(`friendshipGuards/${FIRST}/friends/${SECOND}`),
    db.doc(`friendshipGuards/${SECOND}/friends/${FIRST}`),
  );
}

beforeEach(async () => {
  await wipe();
  await seedEligible();
});
after(wipe);

test("CLI defaults to dry-run and requires a pinned reviewed allowlist", () => {
  assert.deepEqual(
    parseArgs([
      "--project",
      EXPECTED_PROJECT,
      "--allowlist",
      "/operator/reviewed.json",
    ]),
    dryRunArgs(),
  );
  assert.doesNotThrow(() => assertArgs(dryRunArgs(), EXPECTED_PROJECT));
  assert.throws(
    () => assertArgs({ ...dryRunArgs(), project: "other" }, EXPECTED_PROJECT),
    /--project/u,
  );
  assert.throws(
    () => assertArgs({ ...dryRunArgs(), apply: true }, EXPECTED_PROJECT),
    /confirm-digest/u,
  );
  assert.throws(
    () => parseArgs(["--discover-friendships"]),
    /Unknown argument/u,
  );
});

test("allowlist normalization rejects duplicate, ambiguous and extra data", () => {
  assert.throws(
    () => normalizeManifest({
      ...manifest(),
      reviewedPairs: [
        manifest().reviewedPairs[0],
        {
          firstUserId: SECOND,
          secondUserId: FIRST,
          legacyEstablishedAt: { ...ESTABLISHED_AT },
        },
      ],
    }),
    /duplicate pair/u,
  );
  assert.throws(
    () => normalizeManifest(manifest({ unreviewedEvidence: true })),
    /invalid shape/u,
  );
  assert.throws(
    () => normalizeManifest(manifest({ secondUserId: FIRST })),
    /invalid values/u,
  );
  assert.throws(
    () => normalizeManifest({
      schemaVersion: 2,
      reviewedPairs: [{
        firstUserId: FIRST,
        secondUserId: SECOND,
        legacyEstablishedAtMillis: ESTABLISHED_AT_MILLIS,
      }],
    }),
    /invalid shape/u,
  );
  assert.throws(
    () => normalizeManifest(manifest({
      legacyEstablishedAt: {
        ...ESTABLISHED_AT,
        nanoseconds: 1_000_000_000,
      },
    })),
    /invalid values/u,
  );
  assert.throws(
    () => normalizeManifest(manifest({
      legacyEstablishedAt: {
        ...ESTABLISHED_AT,
        nanoseconds: ESTABLISHED_AT.nanoseconds + 1,
      },
    })),
    /invalid values/u,
  );
  assert.throws(
    () => normalizeManifest(manifest({
      legacyEstablishedAt: { ...ESTABLISHED_AT, precision: "lost" },
    })),
    /invalid values/u,
  );
});

test("allowlist digest binds the complete nanosecond timestamp", () => {
  const sameMillisecond = manifest({
    legacyEstablishedAt: {
      ...ESTABLISHED_AT,
      nanoseconds: ESTABLISHED_AT.nanoseconds + 1_000,
    },
  });

  assert.equal(
    Math.floor(
      sameMillisecond.reviewedPairs[0].legacyEstablishedAt.nanoseconds /
      1_000_000,
    ),
    Math.floor(ESTABLISHED_AT.nanoseconds / 1_000_000),
  );
  assert.notEqual(allowlistDigest(sameMillisecond), allowlistDigest(manifest()));
});

test("dry-run is aggregate-only and cannot create friendship guards", async () => {
  const report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });

  assert.equal(report.mode, "dry-run");
  assert.equal(report.reviewedPairs, 1);
  assert.equal(report.eligiblePairs, 1);
  assert.equal(report.conflicts, 0);
  assert.equal(report.appliedGuards, 0);
  assert.equal(JSON.stringify(report).includes(FIRST), false);
  assert.equal(JSON.stringify(report).includes(SECOND), false);
  assert.equal((await guardSnapshots()).every((item) => !item.exists), true);
});

test("apply requires the exact digest before reading or writing", async () => {
  const auth = new FakeAuth();
  await assert.rejects(
    reconcileLegacyFriendships({
      db,
      auth,
      args: { ...dryRunArgs(), apply: true, confirmDigest: "0".repeat(64) },
      manifest: manifest(),
    }),
    /digest changed/u,
  );
  assert.equal(auth.reads.size, 0);
  assert.equal((await guardSnapshots()).every((item) => !item.exists), true);
});

test("apply atomically creates exact bilateral guards and is idempotent", async () => {
  const reviewedManifest = manifest();
  const auth = new FakeAuth();
  const first = await reconcileLegacyFriendships({
    db,
    auth,
    args: applyArgs(reviewedManifest),
    manifest: reviewedManifest,
  });
  assert.equal(first.appliedPairs, 1);
  assert.equal(first.appliedGuards, 2);
  assert.equal(auth.reads.get(FIRST), 3);
  assert.equal(auth.reads.get(SECOND), 3);

  const guards = await guardSnapshots();
  assert.deepEqual(guards[0].data(), {
    ownerId: FIRST,
    friendId: SECOND,
    schemaVersion: 1,
    establishedAt: firestoreTimestamp(),
  });
  assert.deepEqual(guards[1].data(), {
    ownerId: SECOND,
    friendId: FIRST,
    schemaVersion: 1,
    establishedAt: firestoreTimestamp(),
  });

  const second = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: applyArgs(reviewedManifest),
    manifest: reviewedManifest,
  });
  assert.equal(second.alreadyCanonicalPairs, 1);
  assert.equal(second.appliedPairs, 0);
  assert.equal(second.appliedGuards, 0);
});

test("forged or nanosecond-mismatched legacy mirrors are never blessed", async () => {
  await db.doc(`users/${FIRST}/friends/${SECOND}`).set({
    userId: SECOND,
    createdAt: firestoreTimestamp(),
    clientSuppliedProof: true,
  });
  const report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflicts, 1);
  assert.equal(report.conflictReasons[CONFLICT.mirrorShapeInvalid], 1);

  await db.doc(`users/${FIRST}/friends/${SECOND}`).set({
    userId: SECOND,
    createdAt: firestoreTimestamp({
      ...ESTABLISHED_AT,
      nanoseconds: ESTABLISHED_AT.nanoseconds + 1_000,
    }),
  });
  const timestampReport = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(
    timestampReport.conflictReasons[CONFLICT.mirrorTimestampMismatch],
    1,
  );
  assert.equal((await guardSnapshots()).every((item) => !item.exists), true);
});

test("a reviewed source timestamp cannot be future within the same millisecond", async () => {
  const report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
    clock: () => ESTABLISHED_AT_MILLIS,
  });
  assert.equal(report.conflictReasons[CONFLICT.mirrorTimestampInvalid], 1);
  assert.equal((await guardSnapshots()).every((item) => !item.exists), true);
});

test("one-sided or malformed canonical guards fail closed", async () => {
  await db.doc(`friendshipGuards/${FIRST}/friends/${SECOND}`).set({
    ownerId: FIRST,
    friendId: SECOND,
    schemaVersion: 1,
    establishedAt: firestoreTimestamp(),
  });
  let report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.guardInconsistent], 1);

  await db.doc(`friendshipGuards/${SECOND}/friends/${FIRST}`).set({
    ownerId: SECOND,
    friendId: FIRST,
    schemaVersion: 1,
    establishedAt: firestoreTimestamp(),
    migratedByClient: true,
  });
  report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.guardShapeInvalid], 1);
});

test("canonical guards must match the reviewed nanosecond exactly", async () => {
  const sameMillisecondButDifferent = firestoreTimestamp({
    ...ESTABLISHED_AT,
    nanoseconds: ESTABLISHED_AT.nanoseconds + 1_000,
  });
  assert.equal(
    sameMillisecondButDifferent.toMillis(),
    firestoreTimestamp().toMillis(),
  );
  await Promise.all([
    db.doc(`friendshipGuards/${FIRST}/friends/${SECOND}`).set({
      ownerId: FIRST,
      friendId: SECOND,
      schemaVersion: 1,
      establishedAt: firestoreTimestamp(),
    }),
    db.doc(`friendshipGuards/${SECOND}/friends/${FIRST}`).set({
      ownerId: SECOND,
      friendId: FIRST,
      schemaVersion: 1,
      establishedAt: sameMillisecondButDifferent,
    }),
  ]);

  const report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.guardTimestampMismatch], 1);
});

test("Auth, account, block and restriction state are all authoritative", async () => {
  let report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth({ [FIRST]: "missing" }),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.authUserMissing], 1);

  report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth({ [FIRST]: { disabled: true } }),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.authUserDisabled], 1);

  report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth({ [FIRST]: { emailVerified: false } }),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.emailUnverified], 1);

  await db.doc(`users/${FIRST}`).update({ banned: true });
  report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.profileInactive], 1);
  await db.doc(`users/${FIRST}`).update({ banned: false });

  await db.doc(`users/${FIRST}/blocked/${SECOND}`).set({
    createdAt: Timestamp.now(),
  });
  report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.blocked], 1);
  await db.doc(`users/${FIRST}/blocked/${SECOND}`).delete();

  await db.doc(`restrictions/${SECOND}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  report = await reconcileLegacyFriendships({
    db,
    auth: new FakeAuth(),
    args: dryRunArgs(),
    manifest: manifest(),
  });
  assert.equal(report.conflictReasons[CONFLICT.restricted], 1);
  assert.equal((await guardSnapshots()).every((item) => !item.exists), true);
});

test("the apply transaction re-reads predicates after readiness checks", async () => {
  const reviewedManifest = manifest();
  await assert.rejects(
    reconcileLegacyFriendships({
      db,
      auth: new FakeAuth(),
      args: applyArgs(reviewedManifest),
      manifest: reviewedManifest,
      beforePairApply: async (index) => {
        assert.equal(index, 0);
        await db.doc(`users/${SECOND}/blocked/${FIRST}`).set({
          createdAt: Timestamp.now(),
        });
      },
    }),
    (error) => error instanceof ReconciliationRefusal &&
      error.report.conflictReasons[CONFLICT.blocked] === 1,
  );
  assert.equal((await guardSnapshots()).every((item) => !item.exists), true);
});

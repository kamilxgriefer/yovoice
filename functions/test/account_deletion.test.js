// ADR-206 — self-service account deletion.
//
// The suite this feature lives or dies by is the TRUTHFULNESS test at the
// bottom: after a full pipeline run against a seeded account, the seeded
// e-mail address must appear in NO document in the emulator, and the Storage
// bucket must have been asked to clear every uid-owned prefix. Everything
// above it exists to make that outcome reachable safely — the ordering rule
// that keeps `admin.auth().deleteUser` away from an unfinished or
// dead-lettered row, the lease that survives a dead instance, and the Auth
// trigger's two entry points.
//
// Against HEAD (before this change) the truthfulness test and the
// "onAuthUserDeleted deletes users/{uid}" test both fail: the deployed trigger
// deliberately RETAINED users/{uid}, e-mail included.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

// Its own Firestore namespace, for the reason club_self_deletion.test.js
// documents: `node --test test/*.test.js` runs suites in parallel against one
// shared emulator database per project id, and this suite seeds `users/*`
// documents and then asserts that a string appears in NO document. A
// neighbouring suite's fixture would make that assertion read whatever the
// scheduler did that run.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const DELETION_PROJECT = `${BASE_PROJECT}-account-deletion`;
process.env.GCLOUD_PROJECT = DELETION_PROJECT;

if (getApps().length === 0) {
  initializeApp({ projectId: DELETION_PROJECT });
}

const { FieldPath, FieldValue } = require("firebase-admin/firestore");
const {
  MAX_ATTEMPT_MILLIS,
  advanceOutboxStage,
  claimOutboxRow,
  completeOutboxRow,
  enqueueAccountDeletionOutbox,
  executeDeleteAccountSelf,
  outboxReference,
  processAccountDeletionOutbox,
  processReadyAccountDeletionOutbox,
  recordOutboxFailure,
} = require("../account/deletion");
const {
  LEASE_MS,
  MAX_ABANDONED_ATTEMPTS,
  MAX_ATTEMPTS,
  OUTBOX_COLLECTION,
  STAGE_ORDER,
  backoffMs,
  mayDeleteAuthUser,
  outboxIdForUid,
  stageIndex,
} = require("../account/outbox");
const {
  DELETED_IDENTITY_NAME,
  PLAIN_SUBCOLLECTIONS,
  UID_KEYED_DOCUMENTS,
  createAccountDeletionStages,
  uidStoragePrefixes,
} = require("../account/stages");
const {
  deletedAccountEmailDigest,
  deletedReportId,
  deletedReporterId,
  isReporterTombstone,
  mintReporterTombstone,
} = require("../account/retention");
const { handleAuthUserDeleted } = require("../profile/public_profiles");
const { deleteTrustedPrefix } = require("../media/cleanup");

const db = getFirestore();
const P = "acctdel-";
const SUBJECT = `${P}subject`;
const PEER = `${P}peer`;
const SERVER = `${P}server`;
const EMAIL = "acctdel-subject@example-yovoice-test.invalid";
const SALT = "account-deletion-test-salt-0123456789";

function request(uid, { authTimeSecondsAgo = 5 } = {}) {
  return {
    auth: {
      uid,
      token: {
        auth_time: Math.floor(Date.now() / 1000) - authTimeSecondsAgo,
      },
    },
    data: {},
  };
}

function fakeAuthAdmin() {
  const calls = [];
  return {
    calls,
    async revokeRefreshTokens(uid) {
      calls.push(["revoke", uid]);
    },
    async deleteUser(uid) {
      calls.push(["delete", uid]);
    },
  };
}

function fakeBucket({ failPrefixes = [] } = {}) {
  const prefixes = [];
  return {
    name: "yovoice-test.firebasestorage.app",
    prefixes,
    async deleteFiles(options) {
      prefixes.push(options.prefix);
      if (failPrefixes.includes(options.prefix)) {
        const error = new Error("Storage unavailable");
        error.code = "storage-unavailable";
        throw error;
      }
    },
    file(objectPath) {
      return { async delete() { return objectPath; } };
    },
  };
}

function stagesWith({ authAdmin, bucket, limits = {}, environment = {} } = {}) {
  return createAccountDeletionStages({
    db,
    FieldValue,
    FieldPath,
    authAdmin: authAdmin ?? fakeAuthAdmin(),
    resolveBucket: () => bucket ?? fakeBucket(),
    deleteTrustedPrefix,
    logger: { info() {}, warn() {}, error() {} },
    limits,
    environment,
  });
}

async function wipe() {
  const outboxId = outboxIdForUid(SUBJECT);
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(SUBJECT)),
    db.recursiveDelete(db.collection("users").doc(PEER)),
    db.recursiveDelete(db.collection("clubs").doc(SERVER)),
    db.recursiveDelete(db.collection("friendshipGuards").doc(SUBJECT)),
    db.recursiveDelete(db.collection("friendshipGuards").doc(PEER)),
    db.collection(OUTBOX_COLLECTION).doc(outboxId).delete(),
    db.collection("appConfig").doc("accountDeletion").delete(),
  ]);
  for (const name of [
    ...UID_KEYED_DOCUMENTS,
    "voiceMoments",
    "reels",
    "conversations",
    "reports",
    "privateRateLimits",
    "adminAuditLogs",
  ]) {
    const snapshot = await db.collection(name).limit(200).get();
    if (snapshot.empty) continue;
    const batch = db.batch();
    for (const document of snapshot.docs) {
      if (document.id.startsWith(P) ||
          document.id === SUBJECT ||
          JSON.stringify(document.data() ?? {}).includes(SUBJECT)) {
        batch.delete(document.ref);
      }
    }
    await batch.commit();
  }
  // Digest rows are keyed by an opaque hash and carry NO uid by design, so the
  // uid-shaped filter above cannot find them. That is the retention working —
  // the fixture just has to clear them wholesale.
  const digests = await db.collection("deletedAccountDigests").limit(200).get();
  if (!digests.empty) {
    const batch = db.batch();
    for (const document of digests.docs) batch.delete(document.ref);
    await batch.commit();
  }
}

async function enableSwitch(enabled = true) {
  await db.collection("appConfig").doc("accountDeletion").set({ enabled });
}

/** A full, production-shaped account: identity, graph, content, messages. */
async function seedAccount({ banned = false } = {}) {
  const user = db.collection("users").doc(SUBJECT);
  const peer = db.collection("users").doc(PEER);
  await Promise.all([
    user.set({
      uid: SUBJECT,
      email: EMAIL,
      displayName: "Deletion Subject",
      username: "deletionsubject",
      bio: "a bio that must not survive",
      friendCount: 1,
      followerCount: 1,
      followingCount: 1,
      banned,
      ...(banned ? { bannedUntil: null } : {}),
    }),
    peer.set({
      uid: PEER,
      email: "peer@example-yovoice-test.invalid",
      displayName: "Peer",
      friendCount: 1,
      followerCount: 1,
      followingCount: 1,
    }),
    db.collection("publicProfiles").doc(SUBJECT).set({ uid: SUBJECT }),
    db.collection("userDirectory").doc(SUBJECT).set({
      uid: SUBJECT,
      email: EMAIL,
    }),
    db.collection("entitlements").doc(SUBJECT).set({ isPremium: false }),
    db.collection("reportLimits").doc(SUBJECT).set({ count: 3 }),
  ]);

  await Promise.all([
    user.collection("friends").doc(PEER).set({ uid: PEER }),
    peer.collection("friends").doc(SUBJECT).set({
      uid: SUBJECT,
      displayName: "Deletion Subject",
    }),
    db.collection("friendshipGuards").doc(SUBJECT)
      .collection("friends").doc(PEER).set({ establishedAt: Timestamp.now() }),
    db.collection("friendshipGuards").doc(PEER)
      .collection("friends").doc(SUBJECT).set({ establishedAt: Timestamp.now() }),
    user.collection("following").doc(PEER).set({ uid: PEER }),
    peer.collection("followers").doc(SUBJECT).set({ uid: SUBJECT }),
    user.collection("followers").doc(PEER).set({ uid: PEER }),
    peer.collection("following").doc(SUBJECT).set({ uid: SUBJECT }),
    user.collection("fcmTokens").doc("token-1").set({ platform: "ios" }),
    user.collection("notifications").doc("n1").set({ actorId: PEER }),
    user.collection("reelViews").doc("r1").set({ viewedAt: Timestamp.now() }),
    user.collection("momentViews").doc("m1").set({ viewedAt: Timestamp.now() }),
    user.collection("clubs").doc(SERVER).set({ serverId: SERVER }),
  ]);

  await Promise.all([
    db.collection("clubs").doc(SERVER).set({
      ownerId: SUBJECT,
      ownerName: "Deletion Subject",
      memberCount: 2,
    }),
    db.collection("clubs").doc(SERVER).collection("members").doc(SUBJECT).set({
      uid: SUBJECT,
      role: "owner",
      displayName: "Deletion Subject",
      photoUrl: "https://example.invalid/a.png",
    }),
    db.collection("voiceMoments").doc(`${P}moment`).set({
      authorId: SUBJECT,
      authorName: "Deletion Subject",
      caption: "hello",
    }),
    db.collection("reels").doc(`${P}reel`).set({
      authorId: SUBJECT,
      authorName: "Deletion Subject",
    }),
    db.collection("conversations").doc(`${P}conv`).set({
      schemaVersion: 2,
      participantIds: [SUBJECT, PEER],
      participantNames: { [SUBJECT]: "Deletion Subject", [PEER]: "Peer" },
      participantPhotoUrls: { [SUBJECT]: "https://example.invalid/a.png", [PEER]: "" },
      participantEmails: { [SUBJECT]: "", [PEER]: "" },
    }),
    db.collection("adminAuditLogs").doc(`${P}audit-target`).set({
      actorId: PEER,
      actorEmail: "staff@example-yovoice-test.invalid",
      actorRole: "moderator",
      action: "user.ban",
      targetType: "user",
      targetId: SUBJECT,
      // functions/utils/audit.js writes the affected user's E-MAIL here.
      targetLabel: EMAIL,
      details: {},
      createdAt: Timestamp.now(),
    }),
    db.collection("adminAuditLogs").doc(`${P}audit-actor`).set({
      actorId: SUBJECT,
      actorEmail: EMAIL,
      actorRole: "moderator",
      action: "room.close",
      targetType: "room",
      targetId: `${P}room`,
      targetLabel: "A room",
      details: {},
      createdAt: Timestamp.now(),
    }),
    db.collection("reports").doc(`${SUBJECT}_user_${PEER}`).set({
      reporterId: SUBJECT,
      targetType: "user",
      targetId: PEER,
      reportedUserId: PEER,
      reason: "spam",
      note: "",
      status: "open",
      createdAt: Timestamp.now(),
    }),
  ]);
}

/** Runs the whole pipeline to completion, the way the worker would. */
async function runPipeline(stages, { maxRounds = 40 } = {}) {
  const outboxId = outboxIdForUid(SUBJECT);
  let last = null;
  for (let round = 0; round < maxRounds; round += 1) {
    last = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages,
      log: { info() {}, error() {} },
    });
    if (last.completed || last.failed) break;
    const snapshot = await db.collection(OUTBOX_COLLECTION).doc(outboxId).get();
    if (snapshot.data()?.status === "completed") break;
  }
  return last;
}

describe("account deletion: contract helpers", () => {
  test("the outbox id is a salted-free sha256 and never the raw uid", () => {
    const id = outboxIdForUid(SUBJECT);
    assert.match(id, /^[0-9a-f]{64}$/u);
    assert.ok(!id.includes(SUBJECT));
    assert.equal(outboxIdForUid("bad/uid"), null);
  });

  test("auth deletion is refused from every stage except `auth`", () => {
    for (const stage of STAGE_ORDER) {
      assert.equal(
        mayDeleteAuthUser({ stage, status: "processing" }),
        stage === "auth",
        stage,
      );
    }
  });

  test("a dead-lettered or completed row can never reach auth deletion", () => {
    assert.equal(mayDeleteAuthUser({ stage: "auth", status: "deadLetter" }), false);
    assert.equal(mayDeleteAuthUser({ stage: "auth", status: "completed" }), false);
    assert.equal(mayDeleteAuthUser(null), false);
  });

  test("auth is second to last, and finalize is last", () => {
    assert.equal(stageIndex("auth"), STAGE_ORDER.length - 2);
    assert.equal(STAGE_ORDER[STAGE_ORDER.length - 1], "finalize");
  });

  test("backoff grows and is capped", () => {
    assert.ok(backoffMs(1) < backoffMs(4));
    assert.ok(backoffMs(20) <= 30 * 60 * 1000);
  });

  test("the ban digest is salted, and absent without a salt or an e-mail", () => {
    const digest = deletedAccountEmailDigest(EMAIL, { salt: SALT });
    assert.match(digest, /^[0-9a-f]{64}$/u);
    assert.ok(!digest.includes(EMAIL));
    assert.equal(
      deletedAccountEmailDigest(EMAIL, { salt: SALT }),
      deletedAccountEmailDigest(` ${EMAIL.toUpperCase()} `, { salt: SALT }),
      "the digest normalizes case and whitespace so a ban survives a retype",
    );
    assert.notEqual(
      deletedAccountEmailDigest(EMAIL, { salt: SALT }),
      deletedAccountEmailDigest(EMAIL, { salt: `${SALT}x` }),
    );
    assert.equal(deletedAccountEmailDigest(EMAIL, { salt: "short" }), null);
    assert.equal(deletedAccountEmailDigest("", { salt: SALT }), null);
  });

  test("a reporter tombstone is random, not a hash of the uid", () => {
    const first = mintReporterTombstone();
    const second = mintReporterTombstone();
    assert.ok(isReporterTombstone(first));
    assert.notEqual(first, second);
    assert.match(deletedReporterId(first), /^deleted:[0-9a-f]{32}$/u);
    assert.equal(
      deletedReportId(`${SUBJECT}_user_${PEER}`, SUBJECT, first),
      `deleted-${first}_user_${PEER}`,
    );
    assert.equal(deletedReportId(`other_user_${PEER}`, SUBJECT, first), null);
  });
});

describe("account deletion: the callable", () => {
  beforeEach(async () => {
    await wipe();
  });

  test("refuses an unauthenticated caller", async () => {
    await assert.rejects(
      () => executeDeleteAccountSelf({ data: {} }, { database: db }),
      (error) => error.code === "unauthenticated",
    );
  });

  test("refuses a stale sign-in — the server half of re-authentication", async () => {
    await enableSwitch(true);
    await seedAccount();
    await assert.rejects(
      () => executeDeleteAccountSelf(
        request(SUBJECT, { authTimeSecondsAgo: 60 * 60 }),
        { database: db },
      ),
      (error) => error.code === "failed-precondition" &&
        error.details?.reason === "recent-authentication-required",
    );
    const snapshot = await db.collection("users").doc(SUBJECT).get();
    assert.equal(snapshot.data()?.disabled, undefined);
  });

  test("is fail-closed: a MISSING appConfig document disables it", async () => {
    await seedAccount();
    await assert.rejects(
      () => executeDeleteAccountSelf(request(SUBJECT), { database: db }),
      (error) => error.code === "failed-precondition" &&
        error.details?.reason === "account-deletion-disabled",
    );
    const snapshot = await db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT)).get();
    assert.equal(snapshot.exists, false);
  });

  test("an explicit enabled:false also refuses", async () => {
    await enableSwitch(false);
    await seedAccount();
    await assert.rejects(
      () => executeDeleteAccountSelf(request(SUBJECT), { database: db }),
      (error) => error.code === "failed-precondition",
    );
  });

  test("marks the account and enqueues exactly one row", async () => {
    await enableSwitch(true);
    await seedAccount();
    const result = await executeDeleteAccountSelf(request(SUBJECT), {
      database: db,
    });
    assert.equal(result.state, "pending");
    assert.equal(result.alreadyRequested, false);

    const user = await db.collection("users").doc(SUBJECT).get();
    assert.equal(user.data()?.disabled, true);
    assert.equal(user.data()?.isOnline, false);
    assert.equal(user.data()?.accountDeletion?.state, "pending");
    assert.equal(user.data()?.accountDeletion?.schemaVersion, 1);

    const row = await db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT)).get();
    assert.equal(row.exists, true);
    assert.equal(row.data()?.uid, SUBJECT);
    assert.equal(row.data()?.stage, "revoke");
    assert.equal(row.data()?.status, "pending");
    assert.equal(row.data()?.attemptCount, 0);
    assert.ok(isReporterTombstone(row.data()?.reporterTombstone));
  });

  test("a repeat call resumes and does NOT reset the stage or cursor", async () => {
    await enableSwitch(true);
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const reference = db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT));
    await reference.update({ stage: "social", cursor: { step: 3 } });

    const second = await executeDeleteAccountSelf(request(SUBJECT), {
      database: db,
    });
    assert.equal(second.alreadyRequested, true);
    assert.equal(second.state, "pending");
    const row = await reference.get();
    assert.equal(row.data()?.stage, "social");
    assert.deepEqual(row.data()?.cursor, { step: 3 });
  });

  test("the attempt budget is consumed before any state is disclosed", async () => {
    await enableSwitch(true);
    // No users/{uid} at all: the call still costs the caller a slot, so a
    // missing, foreign and pending account are indistinguishable by cost.
    for (let index = 0; index < 5; index += 1) {
      await assert.rejects(
        () => executeDeleteAccountSelf(request(SUBJECT), { database: db }),
        (error) => error.code === "not-found",
      );
    }
    await assert.rejects(
      () => executeDeleteAccountSelf(request(SUBJECT), { database: db }),
      (error) => error.code === "resource-exhausted",
    );
  });
});

describe("account deletion: the leased worker", () => {
  beforeEach(async () => {
    await wipe();
    await enableSwitch(true);
  });

  test("a duplicate trigger delivery is a no-op while the lease is held", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    const first = await claimOutboxRow(reference, outboxId, { database: db });
    assert.equal(first.claimed, true);
    const second = await claimOutboxRow(reference, outboxId, { database: db });
    assert.equal(second.claimed, false);
    assert.equal(second.reason, "leased");

    const duplicate = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages: stagesWith(),
      log: { info() {}, error() {} },
    });
    assert.equal(duplicate.processed, false);
    assert.equal(duplicate.reason, "leased");
  });

  test("an expired lease is reclaimed", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);
    await claimOutboxRow(reference, outboxId, { database: db });

    const later = Date.now() + 10 * 60 * 1000;
    const reclaim = await claimOutboxRow(reference, outboxId, {
      database: db,
      nowMs: () => later,
    });
    assert.equal(reclaim.claimed, true);
    assert.equal(reclaim.row.attemptCount, 2);
  });

  test("a failure defers with backoff and the eighth attempt dead-letters", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    const explodingStages = {
      runStage: async () => {
        const error = new Error("stage exploded");
        error.code = "unavailable";
        throw error;
      },
    };

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      const outcome = await processAccountDeletionOutbox(outboxId, {
        database: db,
        stages: explodingStages,
        // Each call pretends to be far enough in the future that the previous
        // backoff has elapsed; the backoff itself is asserted below.
        nowMs: () => Date.now() + attempt * 60 * 60 * 1000,
        log: { info() {}, error() {} },
      });
      assert.equal(outcome.failed, true, `attempt ${attempt}`);
      const row = await reference.get();
      assert.equal(row.data()?.lastErrorCode, "unavailable");
      if (attempt < MAX_ATTEMPTS) {
        assert.equal(row.data()?.status, "pending", `attempt ${attempt}`);
        assert.ok(row.data()?.nextAttemptAt, `attempt ${attempt}`);
      } else {
        assert.equal(row.data()?.status, "deadLetter");
        assert.equal(row.data()?.nextAttemptAt, null);
        assert.ok(row.data()?.deadLetterAt);
      }
    }
  });

  // ---------------------------------------------------------------- B7
  // An attempt whose budget equalled its lease routinely STARTED its last
  // stage step at the lease boundary and finished after it, so the 2-minute
  // sweep re-claimed the row legitimately while the first worker was still
  // running.
  test("an attempt's budget always ends inside its own lease", () => {
    assert.ok(
      MAX_ATTEMPT_MILLIS < LEASE_MS,
      `attempt budget ${MAX_ATTEMPT_MILLIS}ms must be under the lease ${LEASE_MS}ms`,
    );
  });

  test("a worker whose lease expired cannot stamp a stage on the new owner", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    const first = await claimOutboxRow(reference, outboxId, { database: db });
    assert.equal(first.claimed, true);

    // The lease runs out and the sweep re-claims the row, legitimately.
    const second = await claimOutboxRow(reference, outboxId, {
      database: db,
      nowMs: () => Date.now() + 10 * 60 * 1000,
    });
    assert.equal(second.claimed, true);
    assert.notEqual(second.leaseToken, first.leaseToken);

    const before = await reference.get();
    assert.equal(before.data()?.stage, STAGE_ORDER[0]);

    // The first worker is still executing and reaches its stage marker. Before
    // the guard this was a bare `update`: it stamped `stage: "auth"` onto a row
    // the second worker holds at stage 0, `mayDeleteAuthUser` then passed, and
    // admin.auth().deleteUser ran with content, social edges and Storage
    // objects still in place.
    const stamped = await advanceOutboxStage(reference, first.leaseToken, "auth", {
      database: db,
    });
    assert.equal(stamped, false);

    const after = await reference.get();
    assert.equal(after.data()?.stage, STAGE_ORDER[0]);
    assert.equal(after.data()?.leaseToken, second.leaseToken);
    assert.equal(mayDeleteAuthUser(after.data()), false);

    // The rightful owner still advances its own row.
    assert.equal(
      await advanceOutboxStage(reference, second.leaseToken, "auth", {
        database: db,
      }),
      true,
    );
    assert.equal((await reference.get()).data()?.stage, "auth");
  });

  // ---------------------------------------------------------------- B8
  test("leases that make progress do not spend the retry budget", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    // A stage that keeps asking for another page: exactly the shape of an
    // account with more edges, conversations or content than one lease can
    // walk. `maxSteps: 1` makes each attempt do one page and hand the row back.
    const pagingStages = {
      runStage: async (stage, { cursor }) => ({
        done: false,
        cursor: { page: (cursor?.page ?? 0) + 1 },
        details: {},
      }),
    };

    const leases = MAX_ATTEMPTS + 1;
    for (let attempt = 1; attempt <= leases; attempt += 1) {
      const outcome = await processAccountDeletionOutbox(outboxId, {
        database: db,
        stages: pagingStages,
        maxSteps: 1,
        nowMs: () => Date.now() + attempt * 60 * 60 * 1000,
        log: { info() {}, warn() {}, error() {} },
      });
      assert.equal(outcome.processed, true, `lease ${attempt}`);
      assert.equal(outcome.completed, false, `lease ${attempt}`);
    }

    const progressed = await reference.get();
    assert.equal(progressed.data()?.status, "pending");
    assert.equal(progressed.data()?.attemptCount, leases);
    assert.equal(progressed.data()?.failureCount, 0);

    // Now ONE transient error. With a single counter doing both jobs this row
    // dead-lettered here — nine leases is "attemptCount >= 8" — and the user,
    // who had been told the account was being deleted, kept their e-mail
    // address in `users/{uid}` until a human noticed.
    const outcome = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages: {
        runStage: async () => {
          const error = new Error("one bad page");
          error.code = "unavailable";
          throw error;
        },
      },
      nowMs: () => Date.now() + (leases + 1) * 60 * 60 * 1000,
      log: { info() {}, warn() {}, error() {} },
    });
    assert.equal(outcome.failed, true);

    const row = await reference.get();
    assert.equal(row.data()?.status, "pending");
    assert.equal(row.data()?.failureCount, 1);
    assert.ok(row.data()?.nextAttemptAt);
    assert.equal(row.data()?.deadLetterAt, undefined);
  });

  // ----------------------------------------------------------- MEDIUM-1
  // A worker that DIES mid-attempt is not a worker that fails. It writes no
  // `lastErrorCode`, spends no `failureCount`, serves no backoff and logs
  // nothing, because nothing of it survives. Before the abandonment budget the
  // row went straight back to `processing` on the next sweep and did so for
  // ever: an unbounded crash loop whose only symptom was a person whose
  // deletion never finished and no signal anywhere that it had stopped.
  test("a row that keeps killing its worker dead-letters instead of looping for ever", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    // One iteration is one instance that claims the row and then dies: the row
    // is left `processing` and the lease simply lapses. The FIRST claim takes
    // the row from `pending`, so it abandons nothing; the counter therefore
    // trails the claims by exactly one, and eight claims leave it at seven.
    const sweepAt = (sweep) => Date.now() + (sweep + 1) * (LEASE_MS + 60_000);
    for (let sweep = 0; sweep < MAX_ABANDONED_ATTEMPTS; sweep += 1) {
      const claim = await claimOutboxRow(reference, outboxId, {
        database: db,
        nowMs: () => sweepAt(sweep),
      });
      assert.equal(claim.claimed, true, `sweep ${sweep}`);
    }
    const before = await reference.get();
    assert.equal(before.data()?.status, "processing");
    assert.equal(before.data()?.abandonedCount, MAX_ABANDONED_ATTEMPTS - 1);
    // The point of the second counter: none of this is visible to the first.
    assert.equal(before.data()?.failureCount, 0);
    assert.equal(before.data()?.lastErrorCode, null);

    const warnings = [];
    const outcome = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages: stagesWith(),
      nowMs: () => sweepAt(MAX_ABANDONED_ATTEMPTS),
      log: {
        info() {},
        error() {},
        warn: (message, payload) => warnings.push({ message, payload }),
      },
    });

    // WITHOUT THE BOUND this claim succeeds and the loop goes round again.
    assert.equal(outcome.processed, false);
    assert.equal(outcome.reason, "lease-abandoned");
    assert.equal(outcome.deadLetter, true);

    const row = await reference.get();
    assert.equal(row.data()?.status, "deadLetter");
    assert.equal(row.data()?.lastErrorCode, "lease-abandoned");
    assert.equal(row.data()?.nextAttemptAt, null);
    assert.ok(row.data()?.deadLetterAt);

    // A terminal row is not a signal. Every worker that touched this row died,
    // so this warning is the ONLY thing an operator can be paged on.
    const signal = warnings.find((entry) =>
      entry.message === "account deletion abandoned its lease too many times");
    assert.ok(signal, "the abandonment must produce a structured warning");
    assert.equal(signal.payload.uid, SUBJECT);
    assert.equal(signal.payload.abandonedCount, MAX_ABANDONED_ATTEMPTS);
    assert.equal(signal.payload.maxAbandonedAttempts, MAX_ABANDONED_ATTEMPTS);
    assert.equal(signal.payload.deadLetter, true);

    // And the account is told, so the app stops saying "being deleted".
    const account = await db.collection("users").doc(SUBJECT).get();
    assert.equal(account.data()?.accountDeletion?.state, "deadLetter");
  });

  test("one orderly hand-back clears the abandonment budget", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    // Seven claims: the first abandons nothing, so six of the eight are spent
    // and the budget is deep but not exhausted. The paging attempt below is
    // the eighth claim, which is still inside the ceiling.
    const sweepAt = (sweep) => Date.now() + (sweep + 1) * (LEASE_MS + 60_000);
    for (let sweep = 0; sweep < MAX_ABANDONED_ATTEMPTS - 1; sweep += 1) {
      await claimOutboxRow(reference, outboxId, {
        database: db,
        nowMs: () => sweepAt(sweep),
      });
    }
    assert.equal(
      (await reference.get()).data()?.abandonedCount,
      MAX_ABANDONED_ATTEMPTS - 2,
    );

    // A long deletion that loses an instance now and then is NOT a poison
    // pill, and must never be dead-lettered by this budget. One attempt that
    // pages and hands the row back resets it.
    const paging = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages: {
        runStage: async (stage, { cursor }) => ({
          done: false,
          cursor: { page: (cursor?.page ?? 0) + 1 },
          details: {},
        }),
      },
      maxSteps: 1,
      nowMs: () => sweepAt(MAX_ABANDONED_ATTEMPTS - 1),
      log: { info() {}, warn() {}, error() {} },
    });
    assert.equal(paging.processed, true);

    const row = await reference.get();
    assert.equal(row.data()?.status, "pending");
    assert.equal(row.data()?.abandonedCount, 0);

    // So the very next lost instance starts from a full budget rather than
    // tipping the row over the edge.
    const reclaim = await claimOutboxRow(reference, outboxId, {
      database: db,
      nowMs: () => sweepAt(MAX_ABANDONED_ATTEMPTS),
    });
    assert.equal(reclaim.claimed, true);
    assert.equal(reclaim.row.abandonedCount, 0);
  });

  test("a dead-lettered row NEVER calls deleteUser", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);
    // Park the row exactly where the damage would be: at `auth`, dead.
    await reference.update({ stage: "auth", status: "deadLetter" });

    const authAdmin = fakeAuthAdmin();
    const outcome = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages: stagesWith({ authAdmin }),
      log: { info() {}, error() {} },
    });
    assert.equal(outcome.processed, false);
    assert.equal(outcome.reason, "deadLetter");
    assert.deepEqual(authAdmin.calls, []);
  });

  test("the worker refuses to run the auth stage out of order", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);
    // A corrupted row claiming stage `auth` while `mayDeleteAuthUser` is told
    // otherwise: the worker must refuse rather than delete the identity.
    await reference.update({ stage: "auth" });

    const authAdmin = fakeAuthAdmin();
    const stages = stagesWith({ authAdmin });
    const guarded = {
      runStage: (stage, context) => {
        assert.notEqual(stage, "auth", "auth must not be reached here");
        return stages.runStage(stage, context);
      },
    };
    // Simulate the invariant breaking underneath the worker.
    await reference.update({ status: "deadLetter" });
    const outcome = await processAccountDeletionOutbox(outboxId, {
      database: db,
      stages: guarded,
      log: { info() {}, error() {} },
    });
    assert.equal(outcome.processed, false);
    assert.deepEqual(authAdmin.calls, []);
  });

  test("a stage resumes from its persisted cursor across attempts", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outboxId = outboxIdForUid(SUBJECT);
    const reference = outboxReference(db, outboxId);

    const seen = [];
    const stages = stagesWith();
    const budgeted = {
      runStage: async (stage, context) => {
        seen.push([stage, context.cursor]);
        return stages.runStage(stage, context);
      },
    };

    // One step per attempt forces the cursor to be the only thing carrying
    // progress between invocations.
    await processAccountDeletionOutbox(outboxId, {
      database: db, stages: budgeted, maxSteps: 1,
      log: { info() {}, error() {} },
    });
    const afterFirst = (await reference.get()).data();
    assert.equal(afterFirst.status, "pending");

    await processAccountDeletionOutbox(outboxId, {
      database: db, stages: budgeted, maxSteps: 1,
      log: { info() {}, error() {} },
    });
    const afterSecond = (await reference.get()).data();
    assert.notDeepEqual(
      [afterFirst.stage, afterFirst.cursor],
      [afterSecond.stage, afterSecond.cursor],
      "the second attempt must have made progress from the persisted cursor",
    );
    assert.ok(seen.length >= 2);
  });

  test("the account's own deletion state moves pending -> running -> deadLetter", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const userReference = db.collection("users").doc(SUBJECT);
    assert.equal(
      (await userReference.get()).data()?.accountDeletion?.state,
      "pending",
    );

    const outboxId = outboxIdForUid(SUBJECT);
    const slow = {
      runStage: async () => ({ done: false, cursor: { step: 0 } }),
    };
    await processAccountDeletionOutbox(outboxId, {
      database: db, stages: slow, maxSteps: 1,
      log: { info() {}, error() {} },
    });
    // The one thing a signed-in client can observe about its own deletion:
    // `allow get: if isOwner(userId)` keeps working after `disabled: true`.
    const running = (await userReference.get()).data()?.accountDeletion;
    assert.equal(running.state, "running");
    assert.equal(running.schemaVersion, 1, "the mark's other fields survive");
    assert.equal(running.source, "app");

    const exploding = {
      runStage: async () => {
        const error = new Error("stage exploded");
        error.code = "unavailable";
        throw error;
      },
    };
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      await processAccountDeletionOutbox(outboxId, {
        database: db,
        stages: exploding,
        nowMs: () => Date.now() + attempt * 60 * 60 * 1000,
        log: { info() {}, error() {} },
      });
    }
    assert.equal(
      (await userReference.get()).data()?.accountDeletion?.state,
      "deadLetter",
      "a user who asked to be deleted must be told the truth, not shown a spinner",
    );
  });

  test("the retry sweep runs the real composite-index queries", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outcome = await processReadyAccountDeletionOutbox({
      database: db,
      stages: stagesWith(),
      log: { info() {}, error() {} },
    });
    assert.ok(outcome.scanned >= 1);
  });
});

describe("account deletion: the Auth trigger's two entry points", () => {
  beforeEach(async () => {
    await wipe();
  });

  test("with a stage:auth row, users/{uid} is DELETED — no retained e-mail", async () => {
    await seedAccount();
    const outboxId = outboxIdForUid(SUBJECT);
    await db.collection(OUTBOX_COLLECTION).doc(outboxId).set({
      schemaVersion: 1,
      uid: SUBJECT,
      stage: "auth",
      status: "processing",
    });

    const outcome = await handleAuthUserDeleted(SUBJECT, { database: db });
    assert.equal(outcome.outcome, "deleted");

    const user = await db.collection("users").doc(SUBJECT).get();
    assert.equal(user.exists, false, "the e-mail-bearing document must be gone");
    const row = await db.collection(OUTBOX_COLLECTION).doc(outboxId).get();
    assert.equal(row.data()?.status, "completed");
    for (const name of [
      "publicProfiles", "socialPresence", "publicBadges",
      "userDirectory", "marketingConsents",
    ]) {
      assert.equal(
        (await db.collection(name).doc(SUBJECT).get()).exists,
        false,
        name,
      );
    }
  });

  test("a row still at an earlier stage keeps the fail-safe merge", async () => {
    await seedAccount();
    const outboxId = outboxIdForUid(SUBJECT);
    await db.collection(OUTBOX_COLLECTION).doc(outboxId).set({
      schemaVersion: 1,
      uid: SUBJECT,
      stage: "social",
      status: "pending",
    });

    const outcome = await handleAuthUserDeleted(SUBJECT, { database: db });
    assert.equal(outcome.outcome, "retired");
    const user = await db.collection("users").doc(SUBJECT).get();
    assert.equal(user.exists, true);
    assert.equal(user.data()?.disabled, true);
  });

  test("with NO row, the legacy merge still runs AND a row is enqueued", async () => {
    await seedAccount();
    const enqueued = [];
    const outcome = await handleAuthUserDeleted(SUBJECT, {
      database: db,
      enqueueDeletion: async (uid) => {
        enqueued.push(uid);
        return enqueueAccountDeletionOutbox(uid, { database: db });
      },
    });
    assert.equal(outcome.outcome, "retired");
    assert.equal(outcome.enqueued, true);
    assert.deepEqual(enqueued, [SUBJECT]);

    const user = await db.collection("users").doc(SUBJECT).get();
    assert.equal(user.exists, true, "the fail-safe merge still freezes it");
    assert.equal(user.data()?.disabled, true);
    assert.ok(user.data()?.authDeletedAt);

    const row = await db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT)).get();
    assert.equal(row.exists, true);
    assert.equal(row.data()?.source, "authTrigger");
    assert.equal(row.data()?.stage, "revoke");
  });

  test("enqueuing twice creates exactly one row", async () => {
    const first = await enqueueAccountDeletionOutbox(SUBJECT, { database: db });
    const second = await enqueueAccountDeletionOutbox(SUBJECT, { database: db });
    assert.equal(first.enqueued, true);
    assert.equal(second.enqueued, false);
    assert.equal(second.reason, "exists");
  });
});

describe("account deletion: the stages", () => {
  beforeEach(async () => {
    await wipe();
    await enableSwitch(true);
  });

  test("the social stage removes BOTH sides of every edge and fixes counters", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith());

    const peer = await db.collection("users").doc(PEER).get();
    assert.equal(peer.data()?.friendCount, 0);
    assert.equal(peer.data()?.followerCount, 0);
    assert.equal(peer.data()?.followingCount, 0);
    for (const [path, label] of [
      [`users/${PEER}/friends/${SUBJECT}`, "peer friend mirror"],
      [`users/${PEER}/followers/${SUBJECT}`, "peer follower mirror"],
      [`users/${PEER}/following/${SUBJECT}`, "peer following mirror"],
      [`friendshipGuards/${SUBJECT}/friends/${PEER}`, "own guard"],
      [`friendshipGuards/${PEER}/friends/${SUBJECT}`, "peer guard"],
    ]) {
      assert.equal((await db.doc(path).get()).exists, false, label);
    }
    for (const name of PLAIN_SUBCOLLECTIONS) {
      const snapshot = await db.collection("users").doc(SUBJECT)
        .collection(name).limit(1).get();
      assert.equal(snapshot.empty, true, name);
    }
  });

  test("the messaging stage anonymizes the peer's thread without breaking it", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith());

    const conversation = await db.collection("conversations")
      .doc(`${P}conv`).get();
    assert.equal(conversation.exists, true, "the peer keeps their thread");
    const data = conversation.data() ?? {};
    assert.equal(data.participantNames[SUBJECT], DELETED_IDENTITY_NAME);
    assert.equal(data.participantPhotoUrls[SUBJECT], "");
    assert.equal(data.participantNames[PEER], "Peer");
    // The exact key set direct_integrity.js validates on every read.
    assert.deepEqual(Object.keys(data).sort(), [
      "participantEmails", "participantIds", "participantNames",
      "participantPhotoUrls", "schemaVersion",
    ]);
    assert.ok(data.participantNames[SUBJECT].length > 0);
    assert.ok(data.participantNames[SUBJECT].length <= 80);
  });

  test("the storage stage sweeps every uid-owned prefix, and a failure retries", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const prefixes = uidStoragePrefixes(SUBJECT);
    const failing = fakeBucket({ failPrefixes: [prefixes[0]] });
    const stages = stagesWith({ bucket: failing });
    await assert.rejects(
      () => stages.runStage("storage", { uid: SUBJECT, cursor: null }),
      (error) => error.code === "storage-cleanup-incomplete",
    );

    const working = fakeBucket();
    const outcome = await runPipeline(stagesWith({ bucket: working }));
    assert.equal(outcome.completed, true);
    assert.deepEqual(working.prefixes.sort(), [...prefixes].sort());
  });

  test("a banned account leaves a salted digest; a normal account leaves nothing", async () => {
    await seedAccount({ banned: true });
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith({
      environment: { YOVOICE_DELETED_ACCOUNT_DIGEST_SALT: SALT },
    }));
    const digestId = deletedAccountEmailDigest(EMAIL, { salt: SALT });
    const digest = await db.collection("deletedAccountDigests").doc(digestId).get();
    assert.equal(digest.exists, true);
    assert.equal(digest.data()?.reason, "ban");
    assert.equal(
      JSON.stringify(digest.data()).includes(EMAIL),
      false,
      "the digest row must not carry the e-mail address",
    );

    await wipe();
    await enableSwitch(true);
    await seedAccount({ banned: false });
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith({
      environment: { YOVOICE_DELETED_ACCOUNT_DIGEST_SALT: SALT },
    }));
    const none = await db.collection("deletedAccountDigests")
      .doc(deletedAccountEmailDigest(EMAIL, { salt: SALT })).get();
    assert.equal(none.exists, false);
  });

  test("without a salt no digest is written — never an unsalted one", async () => {
    await seedAccount({ banned: true });
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith({ environment: {} }));
    const snapshot = await db.collection("deletedAccountDigests").limit(5).get();
    assert.equal(snapshot.empty, true);

    // `retention.js` states that the skip is VISIBLE rather than silent, and a
    // log line does not make it so: logs age out, and the operator who has to
    // notice that deleting a banned account reset the ban reads rows.
    const row = await db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT)).get();
    assert.equal(row.data()?.banDigestSkipped, true);
  });

  test("a configured salt leaves no skip marker behind", async () => {
    await seedAccount({ banned: true });
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith({
      environment: { YOVOICE_DELETED_ACCOUNT_DIGEST_SALT: SALT },
    }));
    const row = await db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT)).get();
    assert.notEqual(row.data()?.banDigestSkipped, true);
  });

  test("a report the user FILED is retained as evidence but re-keyed", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const row = await db.collection(OUTBOX_COLLECTION)
      .doc(outboxIdForUid(SUBJECT)).get();
    const tombstone = row.data()?.reporterTombstone;
    await runPipeline(stagesWith());

    const original = await db.collection("reports")
      .doc(`${SUBJECT}_user_${PEER}`).get();
    assert.equal(original.exists, false, "the uid must leave the document PATH");

    const rekeyed = await db.collection("reports")
      .doc(`deleted-${tombstone}_user_${PEER}`).get();
    assert.equal(rekeyed.exists, true, "third-party abuse evidence is retained");
    assert.equal(rekeyed.data()?.reporterId, deletedReporterId(tombstone));
    assert.equal(rekeyed.data()?.reportedUserId, PEER);
    assert.equal(rekeyed.data()?.reason, "spam");
  });

  test("the audit trail survives, but its e-mail addresses do not", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith());

    const target = await db.collection("adminAuditLogs")
      .doc(`${P}audit-target`).get();
    assert.equal(target.exists, true, "moderation accountability is retained");
    assert.equal(target.data()?.targetId, SUBJECT, "the pseudonym stays");
    assert.equal(target.data()?.action, "user.ban");
    assert.equal(
      target.data()?.targetLabel,
      null,
      "the affected user's e-mail must not outlive the account",
    );
    assert.equal(
      target.data()?.actorEmail,
      "staff@example-yovoice-test.invalid",
      "the STAFF member's own e-mail is not this deletion's to erase",
    );

    const actor = await db.collection("adminAuditLogs")
      .doc(`${P}audit-actor`).get();
    assert.equal(actor.exists, true);
    assert.equal(actor.data()?.actorId, SUBJECT);
    assert.equal(actor.data()?.actorEmail, null);
    assert.equal(actor.data()?.targetLabel, "A room", "unrelated labels stay");
  });

  test("owned servers survive with the deleted user's identity anonymized", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    await runPipeline(stagesWith());

    const server = await db.collection("clubs").doc(SERVER).get();
    assert.equal(server.exists, true, "a server must not be bricked");
    assert.equal(server.data()?.ownerName, DELETED_IDENTITY_NAME);
    assert.equal(server.data()?.ownerId, SUBJECT, "ownership stays bound");
    const member = await db.collection("clubs").doc(SERVER)
      .collection("members").doc(SUBJECT).get();
    assert.equal(member.data()?.displayName, DELETED_IDENTITY_NAME);
    assert.equal(member.data()?.photoUrl, null);
    assert.equal(member.data()?.role, "owner", "the owner invariant holds");
  });

  test("finalize deletes the subcollections even when users/{uid} is already gone", async () => {
    // The reachable shape this guards. `onAuthUserDeleted` deletes the ROOT
    // users/{uid} document on its own the moment the Auth identity goes, and
    // the `auth` stage runs immediately before `finalize`. A Firestore
    // subcollection does not belong to its parent document, so the rows below
    // outlive the document above them — and nothing else in the pipeline walks
    // this path again. A `finalize` that returns early on a missing snapshot
    // orphans them permanently: they are personal data about the deleted
    // person, under a document id no client can reach to clean up.
    const user = db.collection("users").doc(SUBJECT);
    await Promise.all([
      user.collection("friends").doc(PEER).set({ uid: PEER }),
      user.collection("blocked").doc(PEER).set({ uid: PEER }),
      user.collection("momentViews").doc("m1").set({ viewedAt: Timestamp.now() }),
    ]);
    // Exactly what handleAuthUserDeleted leaves behind: no root document, and
    // the subcollections untouched under it.
    await user.delete();
    assert.equal((await user.get()).exists, false, "precondition: no root document");
    for (const name of ["friends", "blocked", "momentViews"]) {
      const before = await user.collection(name).limit(1).get();
      assert.equal(before.empty, false, `precondition: ${name} is populated`);
    }

    const outcome = await stagesWith().runStage("finalize", { uid: SUBJECT });
    assert.equal(outcome.done, true);
    assert.equal(outcome.details.userDocument, "absent", "the case is reported, not hidden");
    assert.equal(outcome.details.subcollections, "deleted");

    for (const name of ["friends", "blocked", "momentViews"]) {
      const after = await user.collection(name).limit(1).get();
      assert.equal(after.empty, true, `${name} survived finalize as an orphan`);
    }
  });

  test("finalize still deletes the document and its subcollections together", async () => {
    const user = db.collection("users").doc(SUBJECT);
    await Promise.all([
      user.set({ uid: SUBJECT, email: EMAIL }),
      user.collection("momentViews").doc("m1").set({ viewedAt: Timestamp.now() }),
    ]);

    const outcome = await stagesWith().runStage("finalize", { uid: SUBJECT });
    assert.equal(outcome.details.userDocument, "deleted");
    assert.equal(outcome.details.subcollections, "deleted");
    assert.equal((await user.get()).exists, false);
    assert.equal((await user.collection("momentViews").limit(1).get()).empty, true);
  });
});

describe("account deletion: truthfulness", () => {
  beforeEach(async () => {
    await wipe();
    await enableSwitch(true);
  });

  test("after a full run the seeded e-mail appears in NO document", async () => {
    await seedAccount();
    const authAdmin = fakeAuthAdmin();
    const bucket = fakeBucket();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const outcome = await runPipeline(stagesWith({ authAdmin, bucket }));
    assert.equal(outcome.completed, true, "the pipeline must reach completed");

    assert.deepEqual(
      authAdmin.calls,
      [["revoke", SUBJECT], ["delete", SUBJECT]],
      "tokens are revoked first and the Auth identity is deleted last",
    );
    assert.deepEqual(
      bucket.prefixes.sort(),
      [...uidStoragePrefixes(SUBJECT)].sort(),
      "every uid-owned Storage prefix was swept",
    );

    assert.equal(
      (await db.collection("users").doc(SUBJECT).get()).exists,
      false,
      "users/{uid} — the document that used to keep the e-mail forever",
    );
    for (const name of UID_KEYED_DOCUMENTS) {
      assert.equal(
        (await db.collection(name).doc(SUBJECT).get()).exists,
        false,
        name,
      );
    }
    for (const name of ["voiceMoments", "reels"]) {
      const snapshot = await db.collection(name)
        .where("authorId", "==", SUBJECT).limit(1).get();
      assert.equal(snapshot.empty, true, name);
    }

    // The real assertion: walk every collection this suite can reach and
    // prove the e-mail string is nowhere in it.
    const collections = await db.listCollections();
    const offenders = [];
    for (const collection of collections) {
      const snapshot = await collection.limit(300).get();
      for (const document of snapshot.docs) {
        if (JSON.stringify(document.data() ?? {}).includes(EMAIL)) {
          offenders.push(document.ref.path);
        }
      }
    }
    assert.deepEqual(offenders, [], "the e-mail address survived somewhere");
  });

  test("the account is frozen the moment deletion is requested", async () => {
    await seedAccount();
    await executeDeleteAccountSelf(request(SUBJECT), { database: db });
    const user = await db.collection("users").doc(SUBJECT).get();
    // accountIsActive() in firestore.rules reads exactly this field, so the
    // sweep walks a stable snapshot rather than racing fresh writes.
    assert.equal(user.data()?.disabled, true);
  });
});

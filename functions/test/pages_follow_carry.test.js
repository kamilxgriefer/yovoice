// The follower carry-over of a new Page (ADR-234, pages/follow_carry.js)
// against the Firestore emulator: the pure decision table and job contract,
// sliced and resumable runs, idempotency, the full-index rule, races with
// unfollow and setUserBlock, deleted followers and Pages, Page states that
// never stop it, failures with backoff, and the worker's due-job slice.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
// Its own Firestore namespace (the pages_lapse.test.js pattern): the due-job
// slice scans the whole pageFollowCarryJobs collection, which every suite
// that creates a Page writes to.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const SUITE_PROJECT = `${BASE_PROJECT}-pages-follow-carry`;
process.env.GCLOUD_PROJECT = SUITE_PROJECT;

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: SUITE_PROJECT });

const { setFollow, setUserBlock } = require("../friends/social_graph");
const {
  PAGE_FOLLOW_CARRY_HANDOFF_MS,
  PAGE_FOLLOW_CARRY_JOB_KEYS,
  PAGE_FOLLOW_CARRY_LIMITS,
  PAGE_FOLLOW_CARRY_OUTCOMES,
  PAGE_FOLLOW_CARRY_QUERIES,
  canonicalPageFollowCarryJob,
  carryDecision,
  createPagesFollowCarryService,
  pageFollowCarryJobDocument,
} = require("../pages/follow_carry");
const {
  PAGE_FOLLOW_INDEX_KEYS,
  PAGE_FOLLOW_INDEX_MAX,
  canonicalPageFollowIndex,
  pageFollowToggleReference,
} = require("../pages/follows");
const {
  DAY_MS,
  clearActivation,
  freshUid,
  request,
  seedAccount,
  seedFollowEdge,
  seedPage,
  setActivation,
  setFollowIndex,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const runFollow = setFollow.run ?? setFollow;
const runBlock = setUserBlock.run ?? setUserBlock;
let nowMs = 1_900_000_000_000;

beforeEach(async () => {
  nowMs += DAY_MS;
  await setActivation(db);
  const jobs = await db.collection("pageFollowCarryJobs").get();
  await Promise.all(jobs.docs.map((document) => document.ref.delete()));
});

after(() => clearActivation(db));

function service({ firestore = db, limits = PAGE_FOLLOW_CARRY_LIMITS, logger = silentLogger() } = {}) {
  return {
    logger,
    carry: createPagesFollowCarryService({
      firestore,
      TimestampImpl: Timestamp,
      clock: () => nowMs,
      logger,
      limits,
    }),
  };
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function seedJob(pageId, overrides = {}) {
  const now = Timestamp.fromMillis(nowMs);
  await db.doc(`pageFollowCarryJobs/${pageId}`).set({
    ...pageFollowCarryJobDocument({ pageId, now, nextAttemptAt: now }),
    ...overrides,
  });
}

/// A running Page with `count` followers (canonical edges, active accounts),
/// written in batches. Returns {pageId, followers (sorted by id)}.
async function pageWithFollowers(count, { page = {} } = {}) {
  const pageId = freshUid("pgcarry");
  await seedPage(db, pageId, nowMs, { page, user: { followerCount: count } });
  const followers = Array.from({ length: count }, (_, index) =>
    `${pageId}-f${String(index).padStart(4, "0")}`);
  const at = Timestamp.fromMillis(nowMs);
  for (let start = 0; start < followers.length; start += 150) {
    const batch = db.batch();
    for (const follower of followers.slice(start, start + 150)) {
      batch.set(db.doc(`users/${follower}`), {
        uid: follower, displayName: "Follower", status: "active", role: "user",
        profileVisibility: "public", followerCount: 0, followingCount: 1,
      });
      batch.set(db.doc(`users/${follower}/following/${pageId}`), { uid: pageId, followedAt: at });
      batch.set(db.doc(`users/${pageId}/followers/${follower}`), { uid: follower, followedAt: at });
    }
    await batch.commit();
  }
  return { pageId, followers: [...followers].sort() };
}

function noIdentityIn(logger, ids) {
  const printed = JSON.stringify(logger.entries);
  for (const id of ids) assert.equal(printed.includes(id), false, "a log line names an id");
}

// ------------------------------------------------------------- contract

const snapshot = (data) => ({ exists: data !== null, data: () => data });
const edge = (uid) => snapshot({ uid, followedAt: Timestamp.fromMillis(1) });
const activeUser = { uid: "f", status: "active", role: "user" };
const index = (pageIds, malformed = false) => ({ exists: true, malformed, pageIds });

test("carryDecision: the full table", () => {
  const base = {
    pageId: "page-1",
    followerId: "fan-1",
    followerUser: activeUser,
    followingEdge: edge("page-1"),
    followerEdge: edge("fan-1"),
    followerBlocksPage: false,
    pageBlocksFollower: false,
    index: index([]),
  };
  const outcome = (overrides) => carryDecision({ ...base, ...overrides });
  assert.deepEqual(outcome({}), { outcome: "carry", pageIds: ["page-1"] });
  assert.equal(outcome({ followerId: "page-1" }).outcome, "invalid");
  assert.equal(outcome({ followerId: "a/b" }).outcome, "invalid");
  assert.equal(outcome({ followingEdge: snapshot(null) }).outcome, "noEdge");
  assert.equal(outcome({ followerEdge: snapshot(null) }).outcome, "noEdge");
  assert.equal(outcome({ followingEdge: edge("other-page") }).outcome, "noEdge", "uid mismatch");
  assert.equal(outcome({ followerEdge: edge("someone-else") }).outcome, "noEdge", "uid mismatch");
  for (const gone of [null, { ...activeUser, status: "deleted" }, { ...activeUser, deleted: true },
    { ...activeUser, authDeletedAt: Timestamp.fromMillis(1) }]) {
    assert.equal(outcome({ followerUser: gone }).outcome, "gone", JSON.stringify(gone));
  }
  // Banned and disabled followers are carried: their edges exist, and every
  // reader re-checks the viewer's own account.
  for (const kept of [{ ...activeUser, banned: true }, { ...activeUser, disabled: true }]) {
    assert.equal(outcome({ followerUser: kept }).outcome, "carry", JSON.stringify(kept));
  }
  assert.equal(outcome({ followerBlocksPage: true }).outcome, "blocked");
  assert.equal(outcome({ pageBlocksFollower: true }).outcome, "blocked");
  assert.deepEqual(outcome({ index: index(["x", "page-1"]) }), { outcome: "already", pageIds: null });
  assert.deepEqual(outcome({ index: index(["x", "page-1"], true) }),
    { outcome: "already", pageIds: ["x", "page-1"] }, "a malformed index is repaired");
  assert.deepEqual(outcome({ index: index(["a", "b"]) }).pageIds, ["a", "b", "page-1"]);

  const full = Array.from({ length: PAGE_FOLLOW_INDEX_MAX }, (_, slot) => `p${slot}`);
  const evicted = outcome({ index: index(full) });
  assert.equal(evicted.outcome, "carryEvict");
  assert.equal(evicted.pageIds.length, PAGE_FOLLOW_INDEX_MAX);
  assert.equal(evicted.pageIds[evicted.pageIds.length - 1], "page-1");
  assert.equal(evicted.pageIds.includes("p0"), false, "the oldest hint goes");
  assert.equal(evicted.pageIds[0], "p1");
  assert.deepEqual([...PAGE_FOLLOW_CARRY_OUTCOMES].sort(),
    ["already", "blocked", "carry", "carryEvict", "gone", "invalid", "noEdge"]);
});

test("the job document is exact; a malformed one is reported, never trusted", () => {
  const now = Timestamp.fromMillis(nowMs);
  const fresh = pageFollowCarryJobDocument({ pageId: "page-1", now, nextAttemptAt: now });
  assert.deepEqual(Object.keys(fresh).sort(), [...PAGE_FOLLOW_CARRY_JOB_KEYS]);
  const valid = canonicalPageFollowCarryJob(snapshot(fresh), "page-1");
  assert.equal(valid.exists, true);
  assert.equal(valid.malformed, false);
  assert.equal(valid.job.afterId, null);
  assert.deepEqual(canonicalPageFollowCarryJob(snapshot(null), "page-1"),
    { exists: false, malformed: false, job: null });
  for (const broken of [
    { ...fresh, extra: 1 },
    { ...fresh, pageId: "page-2" },
    { ...fresh, schemaVersion: 2 },
    { ...fresh, afterId: "a/b" },
    { ...fresh, afterId: "page-1" },
    { ...fresh, scanned: -1 },
    { ...fresh, attempts: 1.5 },
    { ...fresh, carried: 3, scanned: 2 },
    { ...fresh, evicted: 1, carried: 0, scanned: 1 },
    { ...fresh, nextAttemptAt: nowMs },
    (({ updatedAt: _u, ...rest }) => rest)(fresh),
  ]) {
    const result = canonicalPageFollowCarryJob(snapshot(broken), "page-1");
    assert.equal(result.malformed, true, JSON.stringify(broken));
    assert.equal(result.job, null);
  }
});

test("a malformed job is logged and restarted from the first follower", async () => {
  const { pageId, followers } = await pageWithFollowers(2);
  await seedJob(pageId, { afterId: followers[1], scanned: "lots" });
  const { carry, logger } = service();
  assert.deepEqual(await carry.runJob(pageId), { outcome: "completed", batches: 1 });
  assert.ok(logger.entries.some((entry) => entry.level === "error" &&
    entry.args[0] === "pages follow carry-over job malformed"));
  for (const follower of followers) {
    assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [pageId]);
  }
  assert.equal(await dataOf(`pageFollowCarryJobs/${pageId}`), null);
});

// ------------------------------------------------ runs and idempotency

test("250 followers in slices of 100: the cursor advances, the job completes, P once each", async () => {
  const { pageId, followers } = await pageWithFollowers(250);
  await seedJob(pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs + PAGE_FOLLOW_CARRY_HANDOFF_MS) });
  const limits = { ...PAGE_FOLLOW_CARRY_LIMITS, runBatches: 1 };
  const { carry, logger } = service({ limits });

  assert.deepEqual(await carry.runJob(pageId, { maxBatches: 1 }), { outcome: "progress", batches: 1 });
  let job = await dataOf(`pageFollowCarryJobs/${pageId}`);
  assert.equal(job.afterId, followers[99]);
  assert.equal(job.scanned, 100);
  assert.equal(job.carried, 100);
  assert.equal(job.attempts, 0);
  assert.equal(job.nextAttemptAt.toMillis(), nowMs, "due for the worker at once");
  assert.equal(await dataOf(`pageFollowIndex/${followers[100]}`), null, "not reached yet");

  nowMs += 60_000;
  assert.deepEqual(await carry.runJob(pageId, { maxBatches: 1 }), { outcome: "progress", batches: 1 });
  job = await dataOf(`pageFollowCarryJobs/${pageId}`);
  assert.equal(job.afterId, followers[199]);
  assert.equal(job.scanned, 200);
  assert.deepEqual(await carry.runJob(pageId, { maxBatches: 1 }), { outcome: "completed", batches: 1 });
  assert.equal(await dataOf(`pageFollowCarryJobs/${pageId}`), null);

  const indexes = await db.getAll(...followers.map((follower) => db.doc(`pageFollowIndex/${follower}`)));
  for (const snapshot of indexes) {
    const data = snapshot.data();
    assert.deepEqual(Object.keys(data).sort(), [...PAGE_FOLLOW_INDEX_KEYS]);
    assert.deepEqual(data.pageIds, [pageId]);
    assert.equal(canonicalPageFollowIndex(snapshot, snapshot.id).malformed, false);
  }
  const done = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over completed");
  assert.deepEqual(done.args[1], {
    outcome: "completed", scanned: 250, carried: 250, already: 0, skipped: 0, evicted: 0,
  });
  // The counter and the edges are untouched.
  assert.equal((await dataOf(`users/${pageId}`)).followerCount, 250);

  // A re-run over a completed set rewrites nothing.
  const before = new Map(indexes.map((snapshot) => [snapshot.id, snapshot.updateTime.toMillis()]));
  await seedJob(pageId);
  assert.equal((await carry.runJob(pageId, { maxBatches: 5 })).outcome, "completed");
  const again = await db.getAll(...followers.map((follower) => db.doc(`pageFollowIndex/${follower}`)));
  for (const snapshot of again) {
    assert.equal(snapshot.updateTime.toMillis(), before.get(snapshot.id), "no write on a re-run");
  }
  const second = logger.entries.filter((entry) => entry.args[0] === "pages follow carry-over completed")[1];
  assert.equal(second.args[1].already, 250);
  assert.equal(second.args[1].carried, 0);
  noIdentityIn(logger, [pageId, ...followers]);
});

test("a full index drops its oldest hint for the new Page and logs a count", async () => {
  const { pageId, followers: [follower] } = await pageWithFollowers(1);
  const full = Array.from({ length: PAGE_FOLLOW_INDEX_MAX }, (_, slot) => `old-page-${slot}`);
  await setFollowIndex(db, follower, full, nowMs);
  await seedJob(pageId);
  const { carry, logger } = service();
  assert.equal((await carry.runJob(pageId)).outcome, "completed");
  const ids = (await dataOf(`pageFollowIndex/${follower}`)).pageIds;
  assert.equal(ids.length, PAGE_FOLLOW_INDEX_MAX);
  assert.equal(ids[ids.length - 1], pageId);
  assert.equal(ids.includes("old-page-0"), false);
  const warn = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over index full");
  assert.equal(warn.level, "warn");
  assert.deepEqual(warn.args[1], { count: 1 });
  const done = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over completed");
  assert.equal(done.args[1].evicted, 1);
});

// ---------------------------------------------------------------- races

test("an unfollow before the slice leaves no hint; a slice then an unfollow drops it", async () => {
  const { pageId, followers: [early, late] } = await pageWithFollowers(2);
  await runFollow(request(early, { targetUserId: pageId, following: false }));
  await seedJob(pageId);
  const { carry } = service();
  await carry.runJob(pageId);
  assert.equal(await dataOf(`pageFollowIndex/${early}`), null);
  assert.deepEqual((await dataOf(`pageFollowIndex/${late}`)).pageIds, [pageId]);
  await runFollow(request(late, { targetUserId: pageId, following: false }));
  assert.deepEqual((await dataOf(`pageFollowIndex/${late}`)).pageIds, []);
  // The listed follower whose edge went between the list and the
  // transaction is re-read there and skipped.
  assert.equal(await carry.carryFollower(pageId, early), "noEdge");
  assert.equal(await dataOf(`pageFollowIndex/${early}`), null);
});

test("setUserBlock in either direction before the slice leaves no hint", async () => {
  const { pageId, followers: [blocksPage, blockedByPage, kept] } = await pageWithFollowers(3);
  await runBlock(request(blocksPage, { targetUserId: pageId, blocked: true }));
  await runBlock(request(pageId, { targetUserId: blockedByPage, blocked: true }));
  // setUserBlock removed both edges in its own transaction.
  assert.equal(await dataOf(`users/${pageId}/followers/${blocksPage}`), null);
  await seedJob(pageId);
  const { carry } = service();
  await carry.runJob(pageId);
  assert.equal(await dataOf(`pageFollowIndex/${blocksPage}`), null);
  assert.equal(await dataOf(`pageFollowIndex/${blockedByPage}`), null);
  assert.deepEqual((await dataOf(`pageFollowIndex/${kept}`)).pageIds, [pageId]);
});

test("a legacy pair with an edge and a block document is skipped", async () => {
  const { pageId, followers: [legacy, reverse] } = await pageWithFollowers(2);
  await db.doc(`users/${legacy}/blocked/${pageId}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  await db.doc(`users/${pageId}/blocked/${reverse}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  await seedJob(pageId);
  const { carry, logger } = service();
  await carry.runJob(pageId);
  assert.equal(await dataOf(`pageFollowIndex/${legacy}`), null);
  assert.equal(await dataOf(`pageFollowIndex/${reverse}`), null);
  const done = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over completed");
  assert.equal(done.args[1].skipped, 2);
});

// ------------------------------------------------- Page state, deletion

test("a missing or deleted follower gets no index document", async () => {
  const { pageId, followers: [missing, deleted, authDeleted] } = await pageWithFollowers(3);
  await db.doc(`users/${missing}`).delete();
  await db.doc(`users/${deleted}`).update({ status: "deleted" });
  await db.doc(`users/${authDeleted}`).update({ authDeletedAt: Timestamp.fromMillis(nowMs) });
  await seedJob(pageId);
  const { carry } = service();
  await carry.runJob(pageId);
  for (const follower of [missing, deleted, authDeleted]) {
    assert.equal(await dataOf(`pageFollowIndex/${follower}`), null, follower);
  }
});

test("a deleted Page deletes its job without writing anything", async () => {
  const { pageId, followers } = await pageWithFollowers(2);
  await seedJob(pageId);
  await db.doc(`pages/${pageId}`).delete();
  const { carry, logger } = service();
  assert.deepEqual(await carry.runJob(pageId), { outcome: "noPage", batches: 0 });
  assert.equal(await dataOf(`pageFollowCarryJobs/${pageId}`), null);
  for (const follower of followers) assert.equal(await dataOf(`pageFollowIndex/${follower}`), null);
  const done = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over completed");
  assert.equal(done.args[1].outcome, "noPage");
  assert.deepEqual(await carry.runJob(pageId), { outcome: "noJob", batches: 0 });
});

test("a Page deleted during a run stops it before the next batch", async () => {
  const { pageId, followers } = await pageWithFollowers(3);
  await seedJob(pageId);
  // The account-deletion content stage removes pages/{P} right after the
  // first follower transaction of the run.
  let transactions = 0;
  const deletingAfterFirst = new Proxy(db, {
    get(target, property) {
      if (property === "runTransaction") {
        return async (...args) => {
          const outcome = await target.runTransaction(...args);
          transactions += 1;
          if (transactions === 1) await target.doc(`pages/${pageId}`).delete();
          return outcome;
        };
      }
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const { carry, logger } = service({
    firestore: deletingAfterFirst,
    limits: { ...PAGE_FOLLOW_CARRY_LIMITS, batchSize: 1, concurrency: 1 },
  });
  assert.deepEqual(await carry.runJob(pageId, { maxBatches: 3 }), { outcome: "noPage", batches: 1 });
  assert.deepEqual((await dataOf(`pageFollowIndex/${followers[0]}`)).pageIds, [pageId]);
  for (const follower of followers.slice(1)) {
    assert.equal(await dataOf(`pageFollowIndex/${follower}`), null, "no hint after the Page went");
  }
  assert.equal(await dataOf(`pageFollowCarryJobs/${pageId}`), null);
  const done = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over completed");
  assert.deepEqual(done.args[1], {
    outcome: "noPage", scanned: 1, carried: 1, already: 0, skipped: 0, evicted: 0,
  });
  noIdentityIn(logger, [pageId, ...followers]);
});

test("paused, readOnly, hidden and suspended Pages are still carried over", async () => {
  const at = Timestamp.fromMillis(nowMs);
  for (const page of [
    { ownerPaused: true },
    { status: "readOnly", lapsedAt: at },
    { status: "hidden", lapsedAt: at },
    { ownerPaused: true, suspended: true, suspendedAt: at, suspensionReason: "spam" },
  ]) {
    const { pageId, followers: [follower] } = await pageWithFollowers(1, { page });
    await seedJob(pageId);
    assert.equal((await service().carry.runJob(pageId)).outcome, "completed", JSON.stringify(page));
    assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [pageId]);
  }
  // The kill switch does not stop it either: a hint grants nothing.
  await clearActivation(db);
  const { pageId, followers: [follower] } = await pageWithFollowers(1);
  // No server field marks a follower's age; every account may follow (D11).
  await db.doc(`users/${follower}`).update({ creatorAgeVerified: false });
  await seedJob(pageId);
  assert.equal((await service().carry.runJob(pageId)).outcome, "completed");
  assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [pageId]);
});

// ------------------------------------------------------ failures, logs

function failingTransactions(inner) {
  return new Proxy(inner, {
    get(target, property) {
      if (property === "runTransaction") {
        return async () => { throw Object.assign(new Error("contention"), { code: "aborted" }); };
      }
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

test("a failing batch backs off, keeps the cursor, and alerts from 5 attempts", async () => {
  const { pageId, followers } = await pageWithFollowers(2);
  await seedJob(pageId);
  const { carry, logger } = service({ firestore: failingTransactions(db) });
  assert.deepEqual(await carry.runJob(pageId), { outcome: "retry", batches: 1 });
  let job = await dataOf(`pageFollowCarryJobs/${pageId}`);
  assert.equal(job.attempts, 1);
  assert.equal(job.nextAttemptAt.toMillis(), nowMs + 60_000);
  assert.equal(job.afterId, null);
  const retry = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over retry");
  assert.equal(retry.level, "warn");
  assert.deepEqual(retry.args[1], { attempts: 1, code: "aborted" });
  assert.equal(logger.entries.some((entry) => entry.args[0] === "pages follow carry-over stuck"), false);

  await db.doc(`pageFollowCarryJobs/${pageId}`).update({ attempts: 4 });
  await carry.runJob(pageId);
  job = await dataOf(`pageFollowCarryJobs/${pageId}`);
  assert.equal(job.attempts, 5);
  const stuck = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over stuck");
  assert.equal(stuck.level, "error");
  assert.deepEqual(stuck.args[1], { attempts: 5, code: "aborted" });
  noIdentityIn(logger, [pageId, ...followers]);

  // Once the store recovers the job finishes from where it stood.
  const healthy = service();
  assert.equal((await healthy.carry.runJob(pageId)).outcome, "completed");
  for (const follower of followers) {
    assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [pageId]);
  }
});

// ------------------------------------------------------- the worker slice

test("processDueJobs takes only due jobs, within jobsPerRun and runBatches", async () => {
  const due = await pageWithFollowers(3);
  const later = await pageWithFollowers(1);
  await seedJob(due.pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs - 1) });
  await seedJob(later.pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs + PAGE_FOLLOW_CARRY_HANDOFF_MS) });
  const { carry } = service();
  const line = await carry.processDueJobs();
  assert.equal(line.processed, 1);
  assert.equal(line.completed, 1);
  assert.equal(await dataOf(`pageFollowCarryJobs/${due.pageId}`), null);
  assert.notEqual(await dataOf(`pageFollowCarryJobs/${later.pageId}`), null, "not due yet");
  assert.equal(await dataOf(`pageFollowIndex/${later.followers[0]}`), null);
  for (const follower of due.followers) {
    assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [due.pageId]);
  }

  // Bounds: 2 followers a batch, 2 batches a run, 1 job a run.
  nowMs += PAGE_FOLLOW_CARRY_HANDOFF_MS;
  const big = await pageWithFollowers(5);
  await seedJob(big.pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs - 2) });
  const bounded = service({
    limits: { ...PAGE_FOLLOW_CARRY_LIMITS, batchSize: 2, runBatches: 2, jobsPerRun: 1 },
  });
  // `big` is the oldest due job (nextAttemptAt ascending), so it runs first.
  const first = await bounded.carry.processDueJobs();
  assert.equal(first.processed, 1);
  assert.equal(first.batches, 2);
  assert.equal(first.hasMore, true);
  const job = await dataOf(`pageFollowCarryJobs/${big.pageId}`);
  assert.equal(job.scanned, 4);
  assert.equal(job.afterId, big.followers[3]);
  const carried = (await db.getAll(...big.followers.map((follower) =>
    db.doc(`pageFollowIndex/${follower}`)))).filter((snapshot) => snapshot.exists).length;
  assert.equal(carried, 4, "2 batches x 2 followers, no more");
  let rounds = 0;
  while ((await db.collection("pageFollowCarryJobs").where("nextAttemptAt", "<=",
    Timestamp.fromMillis(nowMs)).get()).size > 0 && rounds < 10) {
    await bounded.carry.processDueJobs();
    rounds += 1;
  }
  for (const follower of [...big.followers, ...later.followers]) {
    assert.equal((await dataOf(`pageFollowIndex/${follower}`)).pageIds.length, 1, follower);
  }
});

test("processDueJobs isolates a job that fails before its batches; the next due job runs", async () => {
  const broken = await pageWithFollowers(1);
  const healthy = await pageWithFollowers(2);
  // The broken job is the older one, so it is taken first.
  await seedJob(broken.pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs - 2), attempts: 2 });
  await seedJob(healthy.pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs - 1) });
  const brokenJob = `pageFollowCarryJobs/${broken.pageId}`;
  const failingRead = new Proxy(db, {
    get(target, property) {
      if (property === "getAll") {
        return async (...refs) => {
          if (refs[0]?.path === brokenJob) {
            throw Object.assign(new Error("unavailable"), { code: 14 });
          }
          return target.getAll(...refs);
        };
      }
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const { carry, logger } = service({ firestore: failingRead });
  const line = await carry.processDueJobs();
  assert.equal(line.processed, 2);
  assert.equal(line.retried, 1);
  assert.equal(line.completed, 1);
  // The healthy job still completed.
  assert.equal(await dataOf(`pageFollowCarryJobs/${healthy.pageId}`), null);
  for (const follower of healthy.followers) {
    assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [healthy.pageId]);
  }
  // The broken one backed off like any failure: attempts + 1, its backoff.
  const job = await dataOf(brokenJob);
  assert.equal(job.attempts, 3);
  assert.equal(job.nextAttemptAt.toMillis() > nowMs, true);
  assert.equal(await dataOf(`pageFollowIndex/${broken.followers[0]}`), null);
  const retry = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over retry");
  assert.equal(retry.level, "warn");
  assert.deepEqual(retry.args[1], { attempts: 3, code: 14 });
  noIdentityIn(logger, [broken.pageId, healthy.pageId, ...broken.followers, ...healthy.followers]);
});

test("the worker's query builders run on real documents with a startAfter page", async () => {
  const { pageId, followers } = await pageWithFollowers(3);
  await seedJob(pageId, { nextAttemptAt: Timestamp.fromMillis(nowMs - 1) });
  const now = Timestamp.fromMillis(nowMs);
  const dueFirst = await PAGE_FOLLOW_CARRY_QUERIES.dueJobs(db, now).limit(1).get();
  assert.equal(dueFirst.docs[0].id, pageId);
  await PAGE_FOLLOW_CARRY_QUERIES.dueJobs(db, now).startAfter(dueFirst.docs[0]).limit(5).get();
  const page = await PAGE_FOLLOW_CARRY_QUERIES.followers(db, pageId).limit(2).get();
  assert.deepEqual(page.docs.map((document) => document.id), followers.slice(0, 2));
  const rest = await PAGE_FOLLOW_CARRY_QUERIES.followers(db, pageId).startAfter(followers[1]).limit(5).get();
  assert.deepEqual(rest.docs.map((document) => document.id), followers.slice(2));
});

test("the carry-over is invisible to the social graph: no counter, edge or row", async () => {
  const { pageId, followers: [follower] } = await pageWithFollowers(1);
  await seedAccount(db, `${pageId}-other`, nowMs);
  await seedFollowEdge(db, `${pageId}-other`, pageId, nowMs);
  await seedJob(pageId);
  const before = await dataOf(`users/${follower}`);
  await service().carry.runJob(pageId);
  assert.deepEqual(await dataOf(`users/${follower}`), before);
  assert.equal((await dataOf(`users/${pageId}`)).followerCount, 1);
  assert.equal((await db.collection(`users/${pageId}/notifications`).get()).size, 0);
  assert.equal((await pageFollowToggleReference(db, follower, pageId).get()).exists, false,
    "no follow-churn row is charged");
});

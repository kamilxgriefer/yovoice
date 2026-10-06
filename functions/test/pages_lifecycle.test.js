// managePageV1 and the Page hooks on existing profile callables (ADR-233
// §2.2), against the Firestore emulator.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-lifecycle-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  MANAGE_PAGE_FIELDS,
  MANAGE_PAGE_OPS,
  MANAGE_PAGE_SAFETY_OPS,
  PAGE_ADULT_REFUSAL_COOLDOWN_MS,
  PAGES_LIFECYCLE_RATE_LIMITS,
  createPagesLifecycleService,
} = require("../pages/lifecycle");
const {
  PAGE_ERRORS,
  PAGE_KEYS,
  clearedPageContact,
  emptyPageBusiness,
  pageMalformedReason,
  pageNameSearch,
} = require("../pages/contract");
const { PAGE_FOLLOW_CARRY_HANDOFF_MS } = require("../pages/follow_carry");
const { PAGE_FOLLOW_INDEX_KEYS } = require("../pages/follows");
const { createDisplayNameService } = require("../profile/display_name");
const {
  derivePublicProfile,
  setCreatorAudienceEnabledHandler,
} = require("../profile/public_profiles");
const { operationIdentity, rateLimitReference } = require("../integrity/guards");
const {
  DAY_MS,
  businessFields,
  clearActivation,
  createInput,
  freshUid,
  pageDoc,
  paidEntitlement,
  request,
  seedAccount,
  seedFollowEdge,
  seedOwner,
  setActivation,
  setFollowIndex,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const BASE_MS = 1_900_000_000_000;
let nowMs = BASE_MS;

function service({
  logger = silentLogger(),
  rateLimits = PAGES_LIFECYCLE_RATE_LIMITS,
  followCarry = undefined,
} = {}) {
  return createPagesLifecycleService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger,
    rateLimits,
    ...(followCarry ? { followCarry } : {}),
  });
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

/// A Creator whose audience is ON, backed by paid Premium (no VIP grant),
/// with a projection that matches the user record exactly.
async function creatorWithAudience({ followerCount = 2, publicDoc = {} } = {}) {
  const uid = freshUid("pgcr");
  const user = {
    accountType: "creator",
    premiumIdentity: true,
    creatorAgeVerified: true,
    creatorAudienceEnabled: true,
    followerCount,
    followingCount: 0,
  };
  await seedOwner(db, uid, {
    nowMs,
    grant: null,
    user,
    entitlement: paidEntitlement(nowMs, { creatorEnabled: true }),
    publicDoc: {
      accountType: "creator",
      premiumIdentity: true,
      creatorAudienceVisible: true,
      followerCount,
      ...publicDoc,
    },
  });
  return uid;
}

async function pageOf(uid) {
  const snapshot = await db.doc(`pages/${uid}`).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function visibilityOf(uid) {
  const snapshot = await db.doc("pageVisibility/v1").get();
  const data = snapshot.exists ? snapshot.data() : { notViewable: {}, readOnlySince: {} };
  return {
    notViewable: data.notViewable?.[uid] ?? null,
    readOnlySince: data.readOnlySince?.[uid] ?? null,
  };
}

function reason(expected) {
  return (error) => {
    assert.equal(error.details?.reason, expected, `${error.code}: ${error.message}`);
    return true;
  };
}

async function owner(options = {}) {
  const uid = freshUid();
  await seedOwner(db, uid, { nowMs, ...options });
  return uid;
}

async function ownerWithPage(pageOverrides = {}, options = {}) {
  const uid = await owner(options);
  await db.doc(`pages/${uid}`).set(pageDoc(uid, nowMs, pageOverrides));
  return uid;
}

function updateInput(overrides = {}) {
  return {
    requestId: `req-upd-${Math.random().toString(36).slice(2, 12)}`,
    op: "update",
    category: "shop",
    description: "New description",
    business: businessFields({ phone: "+48600100200" }),
    community: null,
    ...overrides,
  };
}

const op = (name) => ({
  requestId: `req-${name}-${Math.random().toString(36).slice(2, 12)}`,
  op: name,
});

beforeEach(async () => {
  nowMs = BASE_MS;
  await setActivation(db);
});

after(() => clearActivation(db));

// ------------------------------------------------------------------ create

test("create writes the exact Page, its ledger and returns the owner result", async () => {
  const uid = await owner();
  const input = createInput();
  const result = await service().managePageV1(request(uid, input));
  assert.deepEqual(result, { pageId: uid, kind: "business", status: "active", ownerPaused: false });

  const page = await pageOf(uid);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS]);
  assert.equal(page.pageId, uid);
  assert.equal(page.ownerId, uid);
  assert.equal(page.displayName, "Kawiarnia Pod Lipą");
  assert.equal(page.nameSearch, pageNameSearch("Kawiarnia Pod Lipą"));
  assert.equal(page.listed, false);
  assert.equal(page.postCount, 0);
  assert.equal(page.business.website, "https://example.com/");
  assert.equal(page.community, null);
  assert.equal(page.adultAttestedAt.toMillis(), nowMs);
  assert.equal(page.adultAttestationMethod, "self_declared_birth_date");
  assert.equal(page.consentVersion, 1);
  assert.deepEqual(await visibilityOf(uid), { notViewable: null, readOnlySince: null });

  // An exact replay returns the stored result; a different operation on the
  // same requestId is refused.
  assert.deepEqual(await service().managePageV1(request(uid, input)), result);
  await assert.rejects(
    service().managePageV1(request(uid, { ...input, category: "shop" })),
    (error) => error.code === "already-exists",
  );
  // A new request finds the Page.
  await assert.rejects(
    service().managePageV1(request(uid, createInput())),
    reason("pageExists"),
  );
});

test("create input is exact per op", async () => {
  const uid = await owner();
  const api = service();
  for (const data of [
    null,
    { ...createInput(), extra: 1 },
    (({ birthDate: _b, ...rest }) => rest)(createInput()),
    { ...createInput(), consentVersion: 2 },
    { ...createInput(), birthDate: 19900101 },
    { ...createInput(), op: "delete" },
    { ...createInput(), requestId: "short" },
    { requestId: "req-pause-extra", op: "pause", kind: "business" },
  ]) {
    await assert.rejects(api.managePageV1(request(uid, data)),
      (error) => error.code === "invalid-argument", JSON.stringify(data));
  }
  assert.deepEqual(MANAGE_PAGE_FIELDS.pause, ["requestId", "op"]);
  await assert.rejects(api.managePageV1(request(null, createInput())),
    (error) => error.code === "unauthenticated");
});

test("create refuses a non-public profile, a reserved name and a missing projection", async () => {
  const privateUid = await owner({ user: { profileVisibility: "friends" } });
  await assert.rejects(service().managePageV1(request(privateUid, createInput())),
    reason("pageProfileNotPublic"));

  const reservedUid = await owner({ publicDoc: { displayName: "YO Voice Support" } });
  await assert.rejects(service().managePageV1(request(reservedUid, createInput())),
    reason("pageNameReserved"));
  const tickUid = await owner({ publicDoc: { displayName: "Kawiarnia ✓" } });
  await assert.rejects(service().managePageV1(request(tickUid, createInput())),
    reason("pageNameReserved"));

  const noProjection = await owner();
  await db.doc(`publicProfiles/${noProjection}`).delete();
  await assert.rejects(service().managePageV1(request(noProjection, createInput())),
    (error) => error.code === "failed-precondition");
  for (const uid of [privateUid, reservedUid, tickUid, noProjection]) {
    assert.equal(await pageOf(uid), null);
    assert.equal(await dataOf(`pageFollowCarryJobs/${uid}`), null);
  }
});

test("the gate admits canonical grants and paid Premium; staff preview and no grant are refused", async () => {
  const noGrant = await owner({ grant: null });
  await assert.rejects(service().managePageV1(request(noGrant, createInput())),
    reason("pageAccessRequired"));

  // ADR-234: paid Premium (Stripe) and an admin-granted entitlement create.
  const paidOnly = await owner({
    grant: null,
    entitlement: paidEntitlement(nowMs, { source: "stripe" }),
    user: { premiumIdentity: true },
  });
  const paid = await service().managePageV1(request(paidOnly, createInput()));
  assert.equal(paid.status, "active");
  assert.notEqual(await pageOf(paidOnly), null);
  const adminPaid = await owner({
    grant: null,
    entitlement: paidEntitlement(nowMs, { source: "admin", plan: "monthly" }),
  });
  await service().managePageV1(request(adminPaid, createInput()));
  assert.notEqual(await pageOf(adminPaid), null);
  // An expired or identity-less entitlement still refuses.
  for (const entitlement of [
    paidEntitlement(nowMs, { currentPeriodEnd: Timestamp.fromMillis(nowMs - 1) }),
    paidEntitlement(nowMs, { status: "expired", isPremium: false }),
    paidEntitlement(nowMs, { premiumIdentityEnabled: false }),
  ]) {
    const lapsed = await owner({ grant: null, entitlement });
    await assert.rejects(service().managePageV1(request(lapsed, createInput())),
      reason("pageAccessRequired"), JSON.stringify(entitlement));
    assert.equal(await pageOf(lapsed), null);
  }

  const moderator = await owner({ grant: null, user: { role: "moderator" } });
  await assert.rejects(
    service().managePageV1(request(moderator, createInput(), { role: "moderator" })),
    reason("pageAccessRequired"),
  );

  const expired = await owner({
    grant: { source: "testerProgram", revoked: false, expiresAt: Timestamp.fromMillis(nowMs - 1) },
  });
  await assert.rejects(service().managePageV1(request(expired, createInput())),
    reason("pageAccessRequired"));
});

// ------------------------------------------------ followers (ADR-234)

test("create succeeds on an account with followers and carries every follower over", async () => {
  assert.equal("hasAudience" in PAGE_ERRORS, false, "the refusal is retired");
  const uid = await owner({ user: { followerCount: 4 } });
  const [f1, f2, f3, f4] = [freshUid("pgf1"), freshUid("pgf2"), freshUid("pgf3"),
    freshUid("pgf4")];
  for (const follower of [f1, f2, f3, f4]) {
    await seedAccount(db, follower, nowMs);
    await seedFollowEdge(db, follower, uid, nowMs);
  }
  // f1 follows other Pages already (order kept, the new Page appended); f2
  // has no index; f3 already holds the Page (no write); f4 is an old pair
  // that is blocked (edge plus block): never carried.
  await setFollowIndex(db, f1, ["page-a", "page-b"], nowMs - 5_000);
  await setFollowIndex(db, f3, ["page-c", uid], nowMs - 7_000);
  await db.doc(`users/${uid}/blocked/${f4}`).set({ blockedAt: Timestamp.fromMillis(nowMs) });
  const logger = silentLogger();

  const result = await service({ logger }).managePageV1(request(uid, createInput()));
  assert.deepEqual(result, { pageId: uid, kind: "business", status: "active", ownerPaused: false });

  const f1Index = await dataOf(`pageFollowIndex/${f1}`);
  assert.deepEqual(Object.keys(f1Index).sort(), [...PAGE_FOLLOW_INDEX_KEYS]);
  assert.deepEqual(f1Index.pageIds, ["page-a", "page-b", uid]);
  assert.deepEqual((await dataOf(`pageFollowIndex/${f2}`)).pageIds, [uid]);
  const f3Index = await dataOf(`pageFollowIndex/${f3}`);
  assert.deepEqual(f3Index.pageIds, ["page-c", uid]);
  assert.equal(f3Index.updatedAt.toMillis(), nowMs - 7_000, "an index that holds the Page is not rewritten");
  assert.equal(await dataOf(`pageFollowIndex/${f4}`), null, "a blocked pair is never carried");

  // Nothing about the edges or the counter changes: they are shared.
  assert.equal((await dataOf(`users/${uid}`)).followerCount, 4);
  for (const follower of [f1, f2, f3, f4]) {
    assert.equal((await dataOf(`users/${follower}/following/${uid}`)).uid, uid);
  }
  assert.equal(await dataOf(`pageFollowCarryJobs/${uid}`), null, "a small account completes at once");
  const done = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over completed");
  assert.deepEqual(done.args[1], {
    outcome: "completed", scanned: 4, carried: 2, already: 1, skipped: 1, evicted: 0,
  });
  const printed = JSON.stringify(logger.entries);
  for (const id of [uid, f1, f2, f3, f4]) assert.equal(printed.includes(id), false);
  // No follow notification or rate-limit row is written for a carry-over.
  const notifications = await db.collection(`users/${uid}/notifications`).get();
  assert.equal(notifications.size, 0);
});

test("create on a Creator with audience on switches it off in the same commit", async () => {
  const uid = await creatorWithAudience({ followerCount: 1 });
  const follower = freshUid("pgcf");
  await seedAccount(db, follower, nowMs);
  await seedFollowEdge(db, follower, uid, nowMs);
  // Before: a paid Creator whose followers are publicly listable.
  assert.equal((await dataOf(`publicProfiles/${uid}`)).creatorAudienceVisible, true);

  await service().managePageV1(request(uid, createInput()));
  const user = await dataOf(`users/${uid}`);
  assert.equal(user.creatorAudienceEnabled, false);
  assert.equal(user.followerCount, 1, "the counter moves to the Page as is");
  const projection = await dataOf(`publicProfiles/${uid}`);
  const { updatedAt, ...projected } = projection;
  assert.notEqual(updatedAt, undefined);
  assert.deepEqual(projected, derivePublicProfile(uid, user));
  assert.equal(projection.creatorAudienceVisible, false);
  assert.equal(projection.followerCount, 0);
  assert.equal(projection.followingCount, 0);
  assert.equal(projection.accountType, "creator", "the Creator identity itself stays");
  assert.deepEqual((await dataOf(`pageFollowIndex/${follower}`)).pageIds, [uid]);
  assert.notEqual(await pageOf(uid), null);

  // Re-enabling stays refused while the Page exists.
  await assert.rejects(
    setCreatorAudienceEnabledHandler(
      request(uid, { enabled: true, requestId: "req-creator-back-on" }),
      { database: db, now: Timestamp.fromMillis(nowMs) },
    ),
    reason("pageActive"),
  );
  assert.equal((await dataOf(`users/${uid}`)).creatorAudienceEnabled, false);
});

test("a refused create on a Creator-audience account changes nothing", async () => {
  const reserved = await creatorWithAudience({ publicDoc: { displayName: "YO Voice Support" } });
  await assert.rejects(service().managePageV1(request(reserved, createInput())),
    reason("pageNameReserved"));
  const today = new Date(nowMs);
  const minor = await creatorWithAudience();
  await db.doc(`users/${minor}`).update({ creatorAgeVerified: false });
  await assert.rejects(
    service().managePageV1(request(minor, createInput({
      birthDate: `${today.getUTCFullYear() - 16}-01-01`,
    }))),
    reason("pageAdultRequired"),
  );
  for (const uid of [reserved, minor]) {
    assert.equal((await dataOf(`users/${uid}`)).creatorAudienceEnabled, true);
    assert.equal((await dataOf(`publicProfiles/${uid}`)).creatorAudienceVisible, true);
    assert.equal(await dataOf(`pageFollowCarryJobs/${uid}`), null);
    assert.equal(await pageOf(uid), null);
  }
});

test("a replayed create writes no second job and runs no second slice", async () => {
  const uid = await owner({ user: { followerCount: 1 } });
  const calls = [];
  const followCarry = { runJob: async (pageId, options) => {
    calls.push([pageId, options]);
    return { outcome: "progress", batches: 1 };
  } };
  const input = createInput();
  const result = await service({ followCarry }).managePageV1(request(uid, input));
  assert.deepEqual(calls, [[uid, { maxBatches: 1 }]]);
  const job = await dataOf(`pageFollowCarryJobs/${uid}`);
  assert.equal(job.schemaVersion, 1);
  assert.equal(job.pageId, uid);
  assert.equal(job.afterId, null);
  assert.equal(job.createdAt.toMillis(), nowMs);
  assert.equal(job.nextAttemptAt.toMillis(), nowMs + PAGE_FOLLOW_CARRY_HANDOFF_MS);
  await db.doc(`pageFollowCarryJobs/${uid}`).delete();

  nowMs += 1_000;
  assert.deepEqual(await service({ followCarry }).managePageV1(request(uid, input)), result);
  assert.equal(calls.length, 1, "a replay runs no slice");
  assert.equal(await dataOf(`pageFollowCarryJobs/${uid}`), null, "a replay writes no job");
});

test("a failing first slice never fails the create: the job waits for the worker", async () => {
  const uid = await owner({ user: { followerCount: 2 } });
  const logger = silentLogger();
  const followCarry = { runJob: async () => {
    throw Object.assign(new Error("unavailable"), { code: 14 });
  } };
  const result = await service({ logger, followCarry }).managePageV1(request(uid, createInput()));
  assert.equal(result.status, "active");
  assert.notEqual(await pageOf(uid), null);
  const job = await dataOf(`pageFollowCarryJobs/${uid}`);
  assert.equal(job.nextAttemptAt.toMillis(), nowMs + PAGE_FOLLOW_CARRY_HANDOFF_MS);
  assert.equal(job.attempts, 0);
  const deferred = logger.entries.find((entry) => entry.args[0] === "pages follow carry-over deferred");
  assert.equal(deferred.level, "warn");
  assert.deepEqual(deferred.args[1], { code: 14 });
  await db.doc(`pageFollowCarryJobs/${uid}`).delete();
});

test("activation: disabled and non-tester callers get pagesNotEnabled", async () => {
  const uid = await owner();
  await clearActivation(db);
  await assert.rejects(service().managePageV1(request(uid, createInput())),
    reason("pagesNotEnabled"));
  await setActivation(db, { readAccess: "testers", writeAccess: "testers", testerUids: ["someone-else"] });
  await assert.rejects(service().managePageV1(request(uid, createInput())),
    reason("pagesNotEnabled"));
  await setActivation(db, { readAccess: "all", writeAccess: "disabled" });
  await assert.rejects(service().managePageV1(request(uid, createInput())),
    reason("pagesNotEnabled"));
  await setActivation(db, { readAccess: "testers", writeAccess: "testers", testerUids: [uid] });
  await service().managePageV1(request(uid, createInput()));
  assert.notEqual(await pageOf(uid), null);
});

test("the create budget is charged before activation, the gate and validation", async () => {
  const uid = await owner({ grant: null });
  const limited = service({
    rateLimits: { ...PAGES_LIFECYCLE_RATE_LIMITS, "pages.create": { maxEvents: 3, windowMs: DAY_MS } },
  });
  await clearActivation(db);
  await assert.rejects(limited.managePageV1(request(uid, createInput())), reason("pagesNotEnabled"));
  await setActivation(db);
  await assert.rejects(limited.managePageV1(request(uid, createInput())), reason("pageAccessRequired"));
  await db.doc(`vipGrants/${uid}`).set({ source: "testerProgram", expiresAt: null, revoked: false });
  await assert.rejects(limited.managePageV1(request(uid, createInput({ category: "gambling" }))),
    (error) => error.code === "invalid-argument");
  await assert.rejects(limited.managePageV1(request(uid, createInput())),
    (error) => error.code === "resource-exhausted");
  assert.equal(await pageOf(uid), null);
});

// ------------------------------------------------------------------- adult

test("adult check: the ledger hash never covers the date, and nothing records it", async () => {
  const uid = await owner();
  const logger = silentLogger();
  const input = createInput({ birthDate: "1990-05-17" });
  const result = await service({ logger }).managePageV1(request(uid, input));
  // Same requestId, another ADULT date: an exact replay (the hash covers
  // {adultEligibility:true}, not the date), never "already-exists".
  assert.deepEqual(
    await service({ logger }).managePageV1(request(uid, { ...input, birthDate: "1975-01-02" })),
    result,
  );
  const identity = operationIdentity("pages.page.create.v1", uid, input.requestId, {
    op: "create",
    kind: "business",
    category: "cafe_restaurant",
    description: "Coffee and cake.",
    business: { ...businessFields(), website: "https://example.com/" },
    community: null,
    consentVersion: 1,
    adultEligibility: true,
  });
  const ledger = (await db.doc(`integrityOperationLedgers/${identity.id}`).get()).data();
  assert.equal(ledger.inputHash, identity.inputHash);
  const stored = JSON.stringify([ledger, await pageOf(uid), logger.entries]);
  for (const fragment of ["1990", "1975", "05-17", "01-02"]) {
    assert.equal(stored.includes(fragment), false, fragment);
  }
});

test("adult check: under 18 writes a dateless refusal that blocks for 30 days", async () => {
  const uid = await owner();
  const logger = silentLogger();
  const today = new Date(nowMs);
  const minor = `${today.getUTCFullYear() - 16}-01-01`;
  await assert.rejects(
    service({ logger }).managePageV1(request(uid, createInput({ birthDate: minor }))),
    (error) => {
      assert.equal(error.details?.reason, "pageAdultRequired");
      assert.equal(error.message, "You must be 18 or older to run a Page.");
      return true;
    },
  );
  const refusal = (await db.doc(`pageAdultRefusals/${uid}`).get()).data();
  assert.deepEqual(Object.keys(refusal).sort(), ["refusedAt", "schemaVersion"]);
  assert.equal(refusal.refusedAt.toMillis(), nowMs);
  assert.equal(JSON.stringify(logger.entries).includes(minor), false);

  // An adult date within 30 days is still refused, before the date is read.
  nowMs += PAGE_ADULT_REFUSAL_COOLDOWN_MS - 1;
  await assert.rejects(service().managePageV1(request(uid, createInput())),
    reason("pageAdultRequired"));
  nowMs += 1;
  await service().managePageV1(request(uid, createInput()));
  assert.notEqual(await pageOf(uid), null);
});

test("adult check: a missing or malformed date is invalid; Creator attestation skips it", async () => {
  const uid = await owner();
  await assert.rejects(service().managePageV1(request(uid, createInput({ birthDate: null }))),
    (error) => error.code === "invalid-argument" && /birthDate is required/.test(error.message));
  await assert.rejects(service().managePageV1(request(uid, createInput({ birthDate: "17.05.1990" }))),
    (error) => error.code === "invalid-argument");
  assert.equal((await db.doc(`pageAdultRefusals/${uid}`).get()).exists, false);

  const attested = await owner({ user: { creatorAgeVerified: true } });
  await service().managePageV1(request(attested, createInput({ birthDate: null })));
  assert.notEqual(await pageOf(attested), null);
});

// -------------------------------------------- preconditions: mute + e-mail

test("muted and unverified accounts cannot create, update or resume; pause still works", async () => {
  const muted = await owner({ mute: true });
  await assert.rejects(service().managePageV1(request(muted, createInput())),
    (error) => error.code === "permission-denied" && /cannot communicate/.test(error.message));

  const pagedMuted = await ownerWithPage({ ownerPaused: false }, { mute: true });
  await assert.rejects(service().managePageV1(request(pagedMuted, updateInput())),
    (error) => error.code === "permission-denied");
  await assert.rejects(service().managePageV1(request(pagedMuted, op("resume"))),
    (error) => error.code === "permission-denied");
  const paused = await service().managePageV1(request(pagedMuted, op("pause")));
  assert.equal(paused.ownerPaused, true);

  const unverified = await ownerWithPage();
  for (const data of [createInput(), updateInput(), op("resume")]) {
    await assert.rejects(
      service().managePageV1(request(unverified, data, { verified: false })),
      (error) => error.code === "failed-precondition" && /Verify your email/.test(error.message),
      data.op,
    );
  }
  const unverifiedPause = await service().managePageV1(
    request(unverified, op("pause"), { verified: false }),
  );
  assert.equal(unverifiedPause.ownerPaused, true);
});

// ------------------------------------------------------ pause and resume

test("pause and resume move the Page and the visibility index together", async () => {
  const uid = await ownerWithPage({ postCount: 2, listed: true, lastPostAt: Timestamp.fromMillis(nowMs - 5) });
  const other = await ownerWithPage();
  // Seed another entry the pause must not disturb.
  await service().managePageV1(request(other, op("pause")));

  nowMs += 1_000;
  const paused = await service().managePageV1(request(uid, op("pause")));
  assert.equal(paused.ownerPaused, true);
  let page = await pageOf(uid);
  assert.equal(page.ownerPaused, true);
  assert.equal(page.listed, false);
  assert.equal(page.updatedAt.toMillis(), nowMs);
  assert.deepEqual(await visibilityOf(uid), { notViewable: "paused", readOnlySince: null });
  assert.equal((await visibilityOf(other)).notViewable, "paused");

  // Idempotent: a second pause writes nothing.
  nowMs += 1_000;
  await service().managePageV1(request(uid, op("pause")));
  assert.equal((await pageOf(uid)).updatedAt.toMillis(), nowMs - 1_000);

  const resumed = await service().managePageV1(request(uid, op("resume")));
  assert.equal(resumed.ownerPaused, false);
  page = await pageOf(uid);
  assert.equal(page.ownerPaused, false);
  assert.equal(page.listed, true);
  assert.deepEqual(await visibilityOf(uid), { notViewable: null, readOnlySince: null });
  assert.equal((await visibilityOf(other)).notViewable, "paused");
});

test("resume re-checks the public profile and the current name", async () => {
  const uid = await ownerWithPage({ ownerPaused: true });
  await db.doc(`users/${uid}`).update({ profileVisibility: "private" });
  await assert.rejects(service().managePageV1(request(uid, op("resume"))),
    reason("pageProfileNotPublic"));
  await db.doc(`users/${uid}`).update({ profileVisibility: "public" });
  await db.doc(`publicProfiles/${uid}`).update({ displayName: "Y0 Voice Official" });
  await assert.rejects(service().managePageV1(request(uid, op("resume"))),
    reason("pageNameReserved"));
  assert.equal((await pageOf(uid)).ownerPaused, true);
  await db.doc(`publicProfiles/${uid}`).update({ displayName: "Kawiarnia Pod Lipą" });
  await service().managePageV1(request(uid, op("resume")));
  assert.equal((await pageOf(uid)).ownerPaused, false);
});

test("pause on a missing Page is pageNotFound; a suspended Page cannot resume or update", async () => {
  const none = await owner();
  await assert.rejects(service().managePageV1(request(none, op("pause"))), reason("pageNotFound"));
  await assert.rejects(service().managePageV1(request(none, op("resume"))), reason("pageNotFound"));

  const suspended = await ownerWithPage({
    ownerPaused: true,
    suspended: true,
    suspendedAt: Timestamp.fromMillis(nowMs - 1),
    suspensionReason: "impersonation",
  });
  await assert.rejects(service().managePageV1(request(suspended, op("resume"))), reason("pageSuspended"));
  await assert.rejects(service().managePageV1(request(suspended, updateInput())), reason("pageSuspended"));
});

// ------------------------------------------------------------------ update

test("update validates for the Page's kind, is allowed while paused and replays exactly", async () => {
  const uid = await ownerWithPage({ ownerPaused: true });
  const input = updateInput();
  const result = await service().managePageV1(request(uid, input));
  assert.deepEqual(result, { pageId: uid, kind: "business", status: "active", ownerPaused: true });
  const page = await pageOf(uid);
  assert.equal(page.category, "shop");
  assert.equal(page.description, "New description");
  assert.equal(page.business.phone, "+48600100200");
  assert.equal(page.ownerPaused, true);
  assert.deepEqual(await service().managePageV1(request(uid, input)), result);

  // Clearing contact fields is an ordinary update.
  await service().managePageV1(request(uid, updateInput({
    business: businessFields({ website: null }),
  })));
  assert.equal((await pageOf(uid)).business.website, null);

  await assert.rejects(service().managePageV1(request(uid, updateInput({ category: "fan_club" }))),
    (error) => error.code === "invalid-argument");
  await assert.rejects(service().managePageV1(request(uid, updateInput({
    business: null,
    community: { rules: null, linkedServerId: null },
  }))), (error) => error.code === "invalid-argument");
});

test("a write with a live capability restores a lapsed Page", async () => {
  const lapsedAt = Timestamp.fromMillis(nowMs - 3 * DAY_MS);
  const uid = await ownerWithPage({ status: "readOnly", lapsedAt });
  const hiddenUid = await ownerWithPage({ status: "hidden", lapsedAt, ownerPaused: true });
  // Seed the index as the lapse writer would have.
  await db.doc("pageVisibility/v1").set({
    readOnlySince: { [uid]: lapsedAt.toMillis() },
    notViewable: { [hiddenUid]: "hidden" },
  }, { merge: true });
  await db.doc("pageVisibility/v1").set({ schemaVersion: 1, updatedAt: lapsedAt }, { merge: true });

  const updated = await service().managePageV1(request(uid, updateInput()));
  assert.equal(updated.status, "active");
  assert.equal((await pageOf(uid)).lapsedAt, null);
  assert.deepEqual(await visibilityOf(uid), { notViewable: null, readOnlySince: null });

  const resumed = await service().managePageV1(request(hiddenUid, op("resume")));
  assert.equal(resumed.status, "active");
  assert.deepEqual(await visibilityOf(hiddenUid), { notViewable: null, readOnlySince: null });
});

test("a lapsed owner without capability cannot update, but can still pause", async () => {
  const uid = await ownerWithPage({}, { grant: null });
  await assert.rejects(service().managePageV1(request(uid, updateInput())),
    reason("pageAccessRequired"));
  await assert.rejects(service().managePageV1(request(uid, op("resume"))),
    reason("pageAccessRequired"));
  assert.equal((await service().managePageV1(request(uid, op("pause")))).ownerPaused, true);
});

// ---------------------------------------------------------- linked server

async function seedServer(serverId, ownerId, overrides = {}) {
  await db.doc(`clubs/${serverId}`).set({
    serverSchemaVersion: 1,
    serverType: "community",
    templateVersion: 1,
    type: "community",
    serverActivationState: "active",
    status: "active",
    revision: 1,
    privacy: "public",
    ownerId,
    ...overrides,
  });
}

test("a linked server must be an active public Community or Podcast server the owner runs", async () => {
  const uid = await owner();
  const stranger = freshUid("pgsrv");
  const own = `srv_${uid.slice(3, 20)}_own`;
  const theirs = `srv_${uid.slice(3, 20)}_theirs`;
  const privateServer = `srv_${uid.slice(3, 20)}_private`;
  const podcast = `srv_${uid.slice(3, 20)}_podcast`;
  await seedServer(own, uid);
  await seedServer(theirs, stranger);
  await seedServer(privateServer, uid, { privacy: "private" });
  await seedServer(podcast, uid, { serverType: "podcast" });
  const communityInput = (linkedServerId) => createInput({
    kind: "community",
    category: "fan_club",
    business: null,
    community: { rules: "Be kind.", linkedServerId },
  });
  for (const serverId of [theirs, privateServer, "srv_missing"]) {
    await assert.rejects(service().managePageV1(request(uid, communityInput(serverId))),
      reason("pageLinkedServerInvalid"), serverId);
  }
  await service().managePageV1(request(uid, communityInput(own)));
  assert.equal((await pageOf(uid)).community.linkedServerId, own);
  await service().managePageV1(request(uid, updateInput({
    category: "sport",
    business: null,
    community: { rules: null, linkedServerId: podcast },
  })));
  assert.equal((await pageOf(uid)).community.linkedServerId, podcast);
});

// ---------------------------------------------------------- display name

function displayNameService() {
  return createDisplayNameService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    syncAuthDisplayName: async () => {},
  });
}

test("a rename moves the Page mirror, paused or not, and a reserved name is refused", async () => {
  for (const ownerPaused of [false, true]) {
    const uid = await ownerWithPage({ ownerPaused });
    nowMs += 1_000;
    await displayNameService().updateMyDisplayName(request(uid, { displayName: "  Nowa Kawiarnia  " }));
    const page = await pageOf(uid);
    assert.equal(page.displayName, "Nowa Kawiarnia");
    assert.equal(page.nameSearch, "nowa kawiarnia");
    assert.equal(page.nameChangedAt.toMillis(), nowMs);
    assert.equal(page.ownerPaused, ownerPaused);

    const other = await ownerWithPage({ ownerPaused });
    await assert.rejects(
      displayNameService().updateMyDisplayName(request(other, { displayName: "VIP Support" })),
      reason("pageNameReserved"),
    );
    assert.equal((await db.doc(`users/${other}`).get()).data().displayName, "Kawiarnia Pod Lipą");
    assert.equal((await pageOf(other)).nameChangedAt, null);
  }
  // A MALFORMED Page fails the rename closed (data-loss, recorded in
  // ADR-233 and SECURITY.md): the name-safety check cannot be skipped by
  // corrupting the Page, and an operator repairs the document.
  const broken = await owner();
  await db.doc(`pages/${broken}`).set({ ...pageDoc(broken, nowMs), unexpectedKey: 1 });
  await assert.rejects(
    displayNameService().updateMyDisplayName(request(broken, { displayName: "Nowa Nazwa" })),
    (error) => error.code === "data-loss",
  );
  assert.equal((await db.doc(`users/${broken}`).get()).data().displayName, "Kawiarnia Pod Lipą");
  assert.equal((await pageOf(broken)).displayName, "Kawiarnia Pod Lipą");

  // An account without a Page may still use any valid name.
  const plain = await owner();
  await displayNameService().updateMyDisplayName(request(plain, { displayName: "VIP Support" }));
  assert.equal((await db.doc(`users/${plain}`).get()).data().displayName, "VIP Support");
  assert.equal(await pageOf(plain), null);
});

// ------------------------------------------------------- Creator audience

test("Creator audience cannot be enabled while a Page exists; disabling still works", async () => {
  const uid = await ownerWithPage({ ownerPaused: true }, {
    user: {
      accountType: "creator",
      premiumIdentity: true,
      creatorAgeVerified: true,
      creatorAudienceEnabled: false,
    },
    entitlement: {
      status: "active",
      isPremium: true,
      premiumIdentityEnabled: true,
      creatorEnabled: true,
      currentPeriodEnd: Timestamp.fromMillis(nowMs + DAY_MS),
    },
  });
  const now = Timestamp.fromMillis(nowMs);
  await assert.rejects(
    setCreatorAudienceEnabledHandler(
      request(uid, { enabled: true, requestId: "req-creator-on" }),
      { database: db, now },
    ),
    reason("pageActive"),
  );
  assert.equal((await db.doc(`users/${uid}`).get()).data().creatorAudienceEnabled, false);
  const off = await setCreatorAudienceEnabledHandler(
    request(uid, { enabled: false, requestId: "req-creator-off" }),
    { database: db, now },
  );
  assert.equal(off.creatorAudienceEnabled, false);

  await db.doc(`pages/${uid}`).delete();
  const on = await setCreatorAudienceEnabledHandler(
    request(uid, { enabled: true, requestId: "req-creator-on-2" }),
    { database: db, now },
  );
  assert.equal(on.creatorAudienceEnabled, true);
});

// ------------------------------------------------- clearContact (ADR-241)

const FULL_CONTACT = Object.freeze({
  website: "https://example.com/",
  email: "kontakt@example.com",
  phone: "+48585550142",
  address: "ul. Garncarska 8, 80-894 Gdańsk",
  hours: "Wt–Pt 11:00–18:00",
  legalNotice: "Pracownia Glina sp. z o.o., NIP 5830000000",
});

test("clearContact is an op with the pause input and the unchanged owner result", async () => {
  assert.deepEqual([...MANAGE_PAGE_OPS], ["create", "update", "pause", "resume", "clearContact"]);
  assert.deepEqual([...MANAGE_PAGE_SAFETY_OPS], ["pause", "clearContact"]);
  assert.deepEqual(MANAGE_PAGE_FIELDS.clearContact, ["requestId", "op"]);
  // The fields older clients send are untouched.
  assert.deepEqual(MANAGE_PAGE_FIELDS.update,
    ["requestId", "op", "category", "description", "business", "community"]);
  assert.deepEqual(MANAGE_PAGE_FIELDS.pause, ["requestId", "op"]);
  assert.deepEqual(MANAGE_PAGE_FIELDS.resume, ["requestId", "op"]);

  const uid = await ownerWithPage({ business: { ...FULL_CONTACT }, ownerPaused: true });
  const api = service();
  for (const data of [
    { op: "clearContact" },
    { ...op("clearContact"), extra: 1 },
    { ...op("clearContact"), business: null },
    { ...op("clearContact"), requestId: "x" },
  ]) {
    await assert.rejects(api.managePageV1(request(uid, data)),
      (error) => error.code === "invalid-argument", JSON.stringify(data));
  }
  await assert.rejects(api.managePageV1(request(null, op("clearContact"))),
    (error) => error.code === "unauthenticated");
  assert.deepEqual((await pageOf(uid)).business, { ...FULL_CONTACT });

  nowMs += 1_000;
  const result = await api.managePageV1(request(uid, op("clearContact")));
  assert.deepEqual(result, { pageId: uid, kind: "business", status: "active", ownerPaused: true });
  const page = await pageOf(uid);
  assert.deepEqual(page.business, emptyPageBusiness());
  assert.equal(page.updatedAt.toMillis(), nowMs);
  // Still the exact canonical Page: every other field is as it was.
  assert.equal(pageMalformedReason(page, uid), null);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS]);
  assert.equal(page.category, "cafe_restaurant");
  assert.equal(page.description, "Coffee and cake.");
  assert.equal(page.ownerPaused, true);
  assert.equal(page.status, "active");

  // Idempotent: a second call writes nothing and answers the same.
  nowMs += 1_000;
  assert.deepEqual(await api.managePageV1(request(uid, op("clearContact"))), result);
  assert.equal((await pageOf(uid)).updatedAt.toMillis(), nowMs - 1_000);
});

test("clearContact works while lapsed, suspended, muted, unverified and with the kill switch on", async () => {
  const lapsedAt = Timestamp.fromMillis(nowMs - 3 * DAY_MS);
  // Lapsed: no grant and no entitlement, the Page read-only, then hidden.
  const readOnly = await ownerWithPage(
    { business: { ...FULL_CONTACT }, status: "readOnly", lapsedAt, postCount: 3 },
    { grant: null },
  );
  const hidden = await ownerWithPage(
    { business: { ...FULL_CONTACT }, status: "hidden", lapsedAt },
    { grant: null },
  );
  const suspended = await ownerWithPage({
    business: { ...FULL_CONTACT },
    suspended: true,
    suspendedAt: Timestamp.fromMillis(nowMs - 1),
    suspensionReason: "impersonation",
  });
  const muted = await ownerWithPage({ business: { ...FULL_CONTACT } }, { mute: true });
  const unverified = await ownerWithPage({ business: { ...FULL_CONTACT } });
  const visibilityBefore = (await db.doc("pageVisibility/v1").get()).data() ?? null;

  // What the ordinary editor answers for the same owners.
  await assert.rejects(service().managePageV1(request(readOnly, updateInput())),
    reason("pageAccessRequired"));
  await assert.rejects(service().managePageV1(request(suspended, updateInput())),
    reason("pageSuspended"));
  await assert.rejects(service().managePageV1(request(muted, updateInput())),
    (error) => error.code === "permission-denied");

  // The kill switch (and a missing activation document) stop nothing here.
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });
  const owners = [readOnly, hidden, suspended, muted, unverified];
  const rateRows = () => Promise.all(owners.map(async (uid) => {
    const snapshot = await rateLimitReference(db, "pages.update", uid).get();
    return snapshot.exists ? snapshot.data() : null;
  }));
  const ratesBefore = await rateRows();
  // Only the owners who tried the ordinary editor above were charged.
  assert.deepEqual(ratesBefore.map((row) => row !== null), [true, false, true, true, false]);

  const lapsedResult = await service().managePageV1(request(readOnly, op("clearContact")));
  assert.deepEqual(lapsedResult,
    { pageId: readOnly, kind: "business", status: "readOnly", ownerPaused: false });
  const lapsedPage = await pageOf(readOnly);
  assert.deepEqual(lapsedPage.business, emptyPageBusiness());
  // No capability, so nothing is restored: the lapse and its clock stay.
  assert.equal(lapsedPage.status, "readOnly");
  assert.equal(lapsedPage.lapsedAt.toMillis(), lapsedAt.toMillis());
  assert.equal(lapsedPage.postCount, 3);
  assert.equal(pageMalformedReason(lapsedPage, readOnly), null);

  const hiddenResult = await service().managePageV1(request(hidden, op("clearContact")));
  assert.equal(hiddenResult.status, "hidden");
  assert.deepEqual((await pageOf(hidden)).business, emptyPageBusiness());

  await service().managePageV1(request(suspended, op("clearContact")));
  const suspendedPage = await pageOf(suspended);
  assert.deepEqual(suspendedPage.business, emptyPageBusiness());
  assert.equal(suspendedPage.suspended, true);
  assert.equal(suspendedPage.suspensionReason, "impersonation");
  assert.equal(pageMalformedReason(suspendedPage, suspended), null);

  await service().managePageV1(request(muted, op("clearContact")));
  assert.deepEqual((await pageOf(muted)).business, emptyPageBusiness());

  await service().managePageV1(request(unverified, op("clearContact"), { verified: false }));
  assert.deepEqual((await pageOf(unverified)).business, emptyPageBusiness());

  // A safety action: no rate budget is charged and the visibility index and
  // the ledger are never written.
  assert.deepEqual(await rateRows(), ratesBefore);
  assert.deepEqual((await db.doc("pageVisibility/v1").get()).data() ?? null, visibilityBefore);
  for (const uid of owners) {
    const ledgers = await db.collection("integrityOperationLedgers")
      .where("ownerId", "==", uid).get();
    assert.equal(ledgers.size, 0, uid);
  }
});

test("clearContact acts on the caller's own Page only, and needs a Page", async () => {
  const none = await owner();
  await assert.rejects(service().managePageV1(request(none, op("clearContact"))),
    reason("pageNotFound"));

  const other = await ownerWithPage({ business: { ...FULL_CONTACT } });
  const caller = await ownerWithPage({ business: { ...FULL_CONTACT } });
  // The Page is the caller's uid; no input can name another Page.
  await assert.rejects(
    service().managePageV1(request(caller, { ...op("clearContact"), pageId: other })),
    (error) => error.code === "invalid-argument",
  );
  await service().managePageV1(request(caller, op("clearContact")));
  assert.deepEqual((await pageOf(caller)).business, emptyPageBusiness());
  assert.deepEqual((await pageOf(other)).business, { ...FULL_CONTACT });
});

test("clearContact leaves a community Page as it is", async () => {
  const uid = await ownerWithPage({
    kind: "community",
    category: "hobby_crafts",
    business: null,
    community: { rules: "Be kind.", linkedServerId: null },
  }, { grant: null });
  const before = await pageOf(uid);
  nowMs += 1_000;
  const result = await service().managePageV1(request(uid, op("clearContact")));
  assert.deepEqual(result, { pageId: uid, kind: "community", status: "active", ownerPaused: false });
  assert.deepEqual(await pageOf(uid), before);
});

test("clearContact survives a malformed Page and still empties its contact details", async () => {
  const uid = await owner();
  await db.doc(`pages/${uid}`).set({
    ...pageDoc(uid, nowMs, { business: { ...FULL_CONTACT } }),
    unexpected: true,
  });
  const logger = silentLogger();
  await service({ logger }).managePageV1(request(uid, op("clearContact")));
  assert.deepEqual((await pageOf(uid)).business, emptyPageBusiness());
  assert.ok(logger.entries.some((entry) => entry.args[0] === "pages malformed page on a safety action"));

  // The pure rule: what is stored, per kind, and when nothing is written.
  assert.equal(clearedPageContact({ kind: "business", business: emptyPageBusiness() }), undefined);
  assert.deepEqual(
    clearedPageContact({ kind: "business", business: { ...emptyPageBusiness(), phone: "+48600100200" } }),
    emptyPageBusiness(),
  );
  assert.deepEqual(clearedPageContact({ kind: "business", business: "broken" }), emptyPageBusiness());
  assert.deepEqual(clearedPageContact({ kind: "business", business: null }), emptyPageBusiness());
  assert.equal(clearedPageContact({ kind: "community", business: null }), undefined);
  assert.equal(clearedPageContact({ kind: "community", business: { website: "https://x.pl" } }), null);
});

// ------------------------------------------------------- safety tolerance

test("pause survives a malformed Page and a malformed index; other writes refuse", async () => {
  const uid = await owner();
  await db.doc(`pages/${uid}`).set({ ...pageDoc(uid, nowMs), unexpected: true });
  const logger = silentLogger();
  const paused = await service({ logger }).managePageV1(request(uid, op("pause")));
  assert.equal(paused.ownerPaused, true);
  assert.equal((await pageOf(uid)).ownerPaused, true);
  assert.ok(logger.entries.some((entry) => entry.args[0] === "pages malformed page on a safety action"));
  assert.equal((await visibilityOf(uid)).notViewable, "paused");

  // A non-safety write refuses a malformed Page.
  await assert.rejects(service().managePageV1(request(uid, updateInput())),
    (error) => error.code === "data-loss");

  // A broken index never blocks a pause, and refuses every other write.
  const indexRef = db.doc("pageVisibility/v1");
  const saved = (await indexRef.get()).data();
  try {
    await indexRef.set({ schemaVersion: 1, notViewable: "broken", readOnlySince: {}, updatedAt: saved.updatedAt });
    const second = await ownerWithPage();
    const indexLogger = silentLogger();
    const result = await service({ logger: indexLogger }).managePageV1(request(second, op("pause")));
    assert.equal(result.ownerPaused, true);
    assert.equal((await pageOf(second)).ownerPaused, true);
    assert.ok(indexLogger.entries.some((entry) =>
      entry.args[0] === "pages visibility index malformed on a safety action"));
    await assert.rejects(service().managePageV1(request(second, op("resume"))),
      (error) => error.code === "data-loss");
  } finally {
    await indexRef.set(saved);
  }
});

// The Premium Pages lapse transitions (ADR-233 §2.8, package B5) against the
// Firestore emulator: the capability triggers, the hourly sweep, the Day-0
// and Day-23 notices, the 30-day boundary, restores, lapseEnabled, the race
// a stale sweep must lose, and the badge that follows the Page.
const assert = require("node:assert/strict");
const { beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
// Its own Firestore namespace (the account_deletion.test.js pattern): the
// suites share one emulator, and these seed listed Pages, open reports and
// whole-collection sweeps that must neither see nor disturb a neighbour's.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const SUITE_PROJECT = `${BASE_PROJECT}-pages-lapse`;
process.env.GCLOUD_PROJECT = SUITE_PROJECT;

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: SUITE_PROJECT });

const {
  PAGES_LAPSE_QUERIES,
  createPagesLapseService,
  lapseDecision,
} = require("../pages/lapse_service");
const { PAGE_READ_ONLY_WINDOW_MS } = require("../pages/lapse");
const { PAGE_LAPSE_NOTICES, PAGE_LAPSE_WARNING_AFTER_MS } = require("../pages/report_contract");
const { syncPublicBadgeForUser } = require("../badges/public_badges");
const {
  DAY_MS,
  freshUid,
  pageDoc,
  paidEntitlement,
  seedPage,
  setActivation,
  clearActivation,
  silentLogger,
  testerGrant,
} = require("./helpers/pages_fixture");

const db = getFirestore();
let nowMs = 1_900_000_000_000;

beforeEach(async () => {
  nowMs += 60 * DAY_MS;
  await setActivation(db, { lapseEnabled: true });
  await db.doc("pageMaintenanceState/lapseSweep").delete();
  await db.doc("pageVisibility/v1").delete();
  // The sweep scans the whole collection: every test starts from none.
  const pages = await db.collection("pages").get();
  await Promise.all(pages.docs.map((document) => document.ref.delete()));
});

function service({ firestore = db, limits } = {}) {
  const logger = silentLogger();
  return {
    logger,
    lapse: createPagesLapseService({
      firestore,
      TimestampImpl: Timestamp,
      clock: () => nowMs,
      logger,
      ...(limits ? { limits } : {}),
    }),
  };
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function visibility() {
  return (await dataOf("pageVisibility/v1")) ?? { notViewable: {}, readOnlySince: {} };
}

async function notificationsOf(uid) {
  const snapshot = await db.collection(`users/${uid}/notifications`).get();
  return snapshot.docs.map((document) => ({ id: document.id, ...document.data() }));
}

const badgeAuth = async () => ({ disabled: false });

test("lapseDecision: the §2.8 table, the Day-23 warning and the brake", () => {
  const at = (ms) => Timestamp.fromMillis(ms);
  const base = { status: "active", lapsedAt: null };
  assert.equal(lapseDecision({ page: base, capabilityAllowed: true, lapseEnabled: true, nowMs }), "none");
  assert.equal(lapseDecision({ page: base, capabilityAllowed: false, lapseEnabled: true, nowMs }), "readOnly");
  assert.equal(lapseDecision({ page: base, capabilityAllowed: false, lapseEnabled: false, nowMs }), "frozen");
  const lapsed = (ms) => ({ status: "readOnly", lapsedAt: at(nowMs - ms) });
  assert.equal(lapseDecision({ page: lapsed(DAY_MS), capabilityAllowed: false, lapseEnabled: true, nowMs }), "none");
  assert.equal(lapseDecision({ page: lapsed(PAGE_LAPSE_WARNING_AFTER_MS), capabilityAllowed: false,
    lapseEnabled: true, nowMs }), "warn");
  assert.equal(lapseDecision({ page: lapsed(PAGE_LAPSE_WARNING_AFTER_MS), capabilityAllowed: false,
    lapseEnabled: true, nowMs, warned: true }), "none");
  assert.equal(lapseDecision({ page: lapsed(PAGE_READ_ONLY_WINDOW_MS - 1), capabilityAllowed: false,
    lapseEnabled: true, nowMs, warned: true }), "none");
  assert.equal(lapseDecision({ page: lapsed(PAGE_READ_ONLY_WINDOW_MS), capabilityAllowed: false,
    lapseEnabled: true, nowMs }), "hidden");
  assert.equal(lapseDecision({ page: lapsed(PAGE_READ_ONLY_WINDOW_MS), capabilityAllowed: false,
    lapseEnabled: false, nowMs }), "none", "the brake freezes the hide too");
  for (const page of [lapsed(DAY_MS), { status: "hidden", lapsedAt: at(nowMs - 40 * DAY_MS) }]) {
    assert.equal(lapseDecision({ page, capabilityAllowed: true, lapseEnabled: false, nowMs }), "restore",
      "restores run with the brake on");
  }
});

test("a revoked grant turns the Page read-only at once: index, listed and the Day-0 notice", async () => {
  const uid = freshUid("lapse");
  await seedPage(db, uid, nowMs, { page: { postCount: 3, listed: true, lastPostAt: Timestamp.fromMillis(nowMs) } });
  await db.doc(`vipGrants/${uid}`).set(testerGrant({ revoked: true }));
  const { lapse } = service();
  assert.deepEqual(await lapse.handleCapabilityChange(uid), { outcome: "readOnly" });
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "readOnly");
  assert.equal(page.lapsedAt.toMillis(), nowMs);
  assert.equal(page.listed, false, "a read-only Page leaves Find");
  assert.equal((await visibility()).readOnlySince[uid], nowMs);
  const notices = await notificationsOf(uid);
  assert.equal(notices.length, 1);
  assert.equal(notices[0].type, "pageLapse");
  assert.equal(notices[0].targetLabel, PAGE_LAPSE_NOTICES.readOnly);
  assert.equal(notices[0].actorName, "YO Voice");
  assert.equal(notices[0].lapsePhase, "readOnly");
  assert.equal(/[a-z][A-Z]/u.test(notices[0].targetLabel), false, "no raw key reaches old builds");
  // A second delivery of the same event changes nothing.
  assert.deepEqual(await lapse.handleCapabilityChange(uid), { outcome: "none" });
  assert.equal((await notificationsOf(uid)).length, 1);
});

test("a time-expired grant lapses through the hourly sweep (no write fires a trigger)", async () => {
  const uid = freshUid("lapse");
  await seedPage(db, uid, nowMs, {
    grant: testerGrant({ expiresAt: Timestamp.fromMillis(nowMs - 1) }),
  });
  const { lapse } = service();
  const line = await lapse.sweep();
  assert.equal(line.ran, true);
  assert.equal(line.transitions, 1);
  assert.equal(line.completed, true);
  assert.equal((await dataOf(`pages/${uid}`)).status, "readOnly");
  // Within the hour the slice does not run again.
  assert.deepEqual(await lapse.sweep(), { ran: false });
});

test("Day 23 warns once, Day 30 hides, and nothing is deleted", async () => {
  const uid = freshUid("lapse");
  await seedPage(db, uid, nowMs, {
    grant: null,
    page: {
      status: "readOnly",
      lapsedAt: Timestamp.fromMillis(nowMs - PAGE_LAPSE_WARNING_AFTER_MS - 1000),
      postCount: 2,
    },
  });
  const { lapse } = service();
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "warned" });
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "none" }, "warned once");
  const warnings = (await notificationsOf(uid)).filter((row) => row.lapsePhase === "hidingSoon");
  assert.equal(warnings.length, 1);
  assert.equal(warnings[0].targetLabel, PAGE_LAPSE_NOTICES.hidingSoon);

  // One millisecond before the boundary: still read-only.
  const lapsedAtMs = (await dataOf(`pages/${uid}`)).lapsedAt.toMillis();
  nowMs = lapsedAtMs + PAGE_READ_ONLY_WINDOW_MS - 1;
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "none" });
  nowMs = lapsedAtMs + PAGE_READ_ONLY_WINDOW_MS;
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "hidden" });
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "hidden");
  assert.equal(page.lapsedAt.toMillis(), lapsedAtMs, "lapsedAt is kept");
  assert.equal(page.postCount, 2, "nothing is deleted");
  const index = await visibility();
  assert.equal(index.notViewable[uid], "hidden");
  assert.equal(index.readOnlySince[uid], undefined);
});

test("a returning grant restores a hidden Page completely, trigger and sweep alike", async () => {
  const uid = freshUid("lapse");
  const other = freshUid("lapse");
  const lapsed = {
    status: "hidden",
    lapsedAt: Timestamp.fromMillis(nowMs - 40 * DAY_MS),
    postCount: 4,
  };
  await seedPage(db, uid, nowMs, { page: lapsed });
  await seedPage(db, other, nowMs, { page: { ...lapsed, status: "readOnly",
    lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) } });
  const { lapse } = service();
  assert.deepEqual(await lapse.handleCapabilityChange(uid), { outcome: "restored" });
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "active");
  assert.equal(page.lapsedAt, null);
  assert.equal(page.listed, true);
  const line = await lapse.sweep();
  assert.equal(line.transitions, 1, "the sweep restores the other one");
  assert.equal((await dataOf(`pages/${other}`)).status, "active");
  const index = await visibility();
  assert.equal(index.notViewable[uid], undefined);
  assert.equal(index.readOnlySince[other], undefined);
});

test("a paid-only Page lapses exactly like a VIP one (ADR-234)", async () => {
  const uid = freshUid("lapsepaid");
  await seedPage(db, uid, nowMs, {
    grant: null,
    entitlement: paidEntitlement(nowMs, { source: "stripe" }),
    page: { postCount: 1, listed: true, lastPostAt: Timestamp.fromMillis(nowMs) },
  });
  const { lapse } = service();
  assert.deepEqual(await lapse.handleCapabilityChange(uid), { outcome: "none" },
    "paid Premium is a live capability");
  // What the premium expiry worker (or a Stripe webhook) writes; the write
  // fires onPageCapabilityEntitlementChanged.
  await db.doc(`entitlements/${uid}`).set({
    isPremium: false,
    status: "expired",
    premiumIdentityEnabled: false,
    creatorEnabled: false,
    canCreateClubs: false,
  }, { merge: true });
  assert.deepEqual(await lapse.handleCapabilityChange(uid), { outcome: "readOnly" });
  let page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "readOnly");
  assert.equal(page.lapsedAt.toMillis(), nowMs);
  assert.equal(page.listed, false);
  const dayZero = await notificationsOf(uid);
  assert.equal(dayZero.length, 1);
  assert.equal(dayZero[0].lapsePhase, "readOnly");

  const lapsedAtMs = nowMs;
  nowMs = lapsedAtMs + PAGE_LAPSE_WARNING_AFTER_MS;
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "warned" });
  assert.equal((await notificationsOf(uid)).filter((row) => row.lapsePhase === "hidingSoon").length, 1);
  nowMs = lapsedAtMs + PAGE_READ_ONLY_WINDOW_MS;
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "hidden" });
  assert.equal((await visibility()).notViewable[uid], "hidden");

  // Renewal restores the Page completely.
  await db.doc(`entitlements/${uid}`).set(paidEntitlement(nowMs, { source: "stripe" }));
  assert.deepEqual(await lapse.handleCapabilityChange(uid), { outcome: "restored" });
  page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "active");
  assert.equal(page.lapsedAt, null);
  assert.equal(page.listed, true);
  assert.equal((await visibility()).notViewable[uid], undefined);
});

test("a paid period that ends with no write lapses through the sweep; grace stays active", async () => {
  const ended = freshUid("lapsepaid");
  const grace = freshUid("lapsepaid");
  const admin = freshUid("lapsepaid");
  await seedPage(db, ended, nowMs, {
    grant: null,
    entitlement: paidEntitlement(nowMs, { currentPeriodEnd: Timestamp.fromMillis(nowMs + 1000) }),
  });
  await seedPage(db, grace, nowMs, {
    grant: null,
    entitlement: paidEntitlement(nowMs, { status: "grace" }),
  });
  await seedPage(db, admin, nowMs, {
    grant: null,
    entitlement: paidEntitlement(nowMs, { source: "admin", plan: "monthly" }),
  });
  nowMs += 2000;
  const { lapse } = service();
  const line = await lapse.sweep();
  assert.equal(line.transitions, 1);
  assert.equal((await dataOf(`pages/${ended}`)).status, "readOnly");
  assert.equal((await dataOf(`pages/${grace}`)).status, "active");
  assert.equal((await dataOf(`pages/${admin}`)).status, "active");
});

test("lapseEnabled false freezes every downgrade and still restores", async () => {
  await setActivation(db, { lapseEnabled: false });
  const revoked = freshUid("lapse");
  const lapsed = freshUid("lapse");
  const back = freshUid("lapse");
  await seedPage(db, revoked, nowMs, { grant: null });
  await seedPage(db, lapsed, nowMs, { grant: null, page: {
    status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - 31 * DAY_MS) } });
  await seedPage(db, back, nowMs, { page: {
    status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) } });
  const { lapse } = service();
  assert.deepEqual(await lapse.reconcilePage(revoked), { outcome: "frozen" });
  assert.deepEqual(await lapse.reconcilePage(lapsed), { outcome: "none" });
  const line = await lapse.sweep();
  assert.equal(line.transitions, 1);
  assert.equal((await dataOf(`pages/${revoked}`)).status, "active");
  assert.equal((await dataOf(`pages/${lapsed}`)).status, "readOnly");
  assert.equal((await dataOf(`pages/${back}`)).status, "active");
  // A missing switch is the brake too (fail closed).
  await clearActivation(db);
  assert.deepEqual(await lapse.reconcilePage(revoked), { outcome: "frozen" });
});

test("race: a stale sweep capability read cannot overwrite a trigger restore", async () => {
  const uid = freshUid("lapse");
  await seedPage(db, uid, nowMs, { page: {
    status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - 2 * DAY_MS) } });
  // The sweep's pre-read saw NO grant (it read just before the owner was
  // re-granted); by the time it acts, the trigger has restored the Page.
  const staleView = new Proxy(db, {
    get(target, property) {
      if (property === "getAll") {
        return async (...references) => {
          const snapshots = await target.getAll(...references);
          return snapshots.map((snapshot) => (snapshot.ref.path.startsWith("vipGrants/")
            ? { exists: false, ref: snapshot.ref, data: () => undefined }
            : snapshot));
        };
      }
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const { lapse: trigger } = service();
  assert.deepEqual(await trigger.handleCapabilityChange(uid), { outcome: "restored" });
  // The stale pre-read would even DOWNGRADE the now-active Page; the
  // transaction re-derives from the real grant and does nothing.
  const { lapse: stale } = service({ firestore: staleView });
  const line = await stale.sweep({ force: true });
  assert.equal(line.transitions, 0);
  const page = await dataOf(`pages/${uid}`);
  assert.equal(page.status, "active");
  assert.equal(page.lapsedAt, null);
});

test("the sweep is bounded and resumes by cursor, including the null-lapsedAt phase", async () => {
  const owners = [freshUid("lapse"), freshUid("lapse"), freshUid("lapse")];
  for (const uid of owners) await seedPage(db, uid, nowMs, { grant: null });
  const { lapse } = service({ limits: { batchSize: 2, batchesPerRun: 1 } });
  const first = await lapse.sweep();
  assert.equal(first.scanned, 2);
  assert.equal(first.completed, false);
  const state = await dataOf("pageMaintenanceState/lapseSweep");
  assert.equal(state.phase, "active");
  assert.equal(state.afterLapsedAtMs, null);
  const second = await lapse.sweep();
  assert.equal(second.scanned >= 1, true);
  let completed = second.completed;
  for (let round = 0; round < 5 && !completed; round += 1) completed = (await lapse.sweep()).completed;
  assert.equal(completed, true);
  for (const uid of owners) assert.equal((await dataOf(`pages/${uid}`)).status, "readOnly");
});

test("the sweep query pages through real documents with both cursor kinds", async () => {
  const a = freshUid("lapseq");
  const b = freshUid("lapseq");
  await db.doc(`pages/${a}`).set(pageDoc(a, nowMs));
  await db.doc(`pages/${b}`).set(pageDoc(b, nowMs, {
    status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - DAY_MS) }));
  const active = await PAGES_LAPSE_QUERIES.byStatus(db, "active").limit(1).get();
  assert.equal(active.docs[0].id, a);
  const afterActive = await PAGES_LAPSE_QUERIES.byStatus(db, "active").startAfter(null, a).limit(5).get();
  assert.equal(afterActive.size, 0);
  const afterReadOnly = await PAGES_LAPSE_QUERIES.byStatus(db, "readOnly")
    .startAfter(Timestamp.fromMillis(nowMs - DAY_MS), b).limit(5).get();
  assert.equal(afterReadOnly.size, 0);
});

test("the capability trigger costs one read for an account without a Page", async () => {
  const { lapse } = service();
  assert.deepEqual(await lapse.handleCapabilityChange(freshUid("nopage")), { outcome: "noPage" });
});

test("a malformed Page is never transitioned and is logged", async () => {
  const uid = freshUid("lapse");
  await seedPage(db, uid, nowMs, { grant: null });
  await db.doc(`pages/${uid}`).update({ status: "unknown" });
  const { lapse, logger } = service();
  assert.deepEqual(await lapse.reconcilePage(uid), { outcome: "malformed" });
  assert.equal(logger.entries.some((entry) => entry.args[0] === "pages lapse skipped a malformed page"), true);
});

test("the badge follows: readOnly keeps `page` with the rosette off; hidden drops `page`", async () => {
  const uid = freshUid("lapse");
  await seedPage(db, uid, nowMs);
  await syncPublicBadgeForUser(uid, { database: db, fetchAuthUser: badgeAuth });
  let badge = await dataOf(`publicBadges/${uid}`);
  assert.equal(badge.isVip, true);
  assert.equal(badge.page, "business");

  await db.doc(`vipGrants/${uid}`).set(testerGrant({ revoked: true }));
  const { lapse } = service();
  await lapse.handleCapabilityChange(uid);
  // onVipGrantChanged / onPageBadgeSourceChanged run this same derivation.
  await syncPublicBadgeForUser(uid, { database: db, fetchAuthUser: badgeAuth });
  badge = await dataOf(`publicBadges/${uid}`);
  assert.equal(badge.isVip, false, "a revoked grant turns the rosette off");
  assert.equal(badge.page, "business", "the Page is still visible while read-only");

  nowMs += PAGE_READ_ONLY_WINDOW_MS;
  await lapse.reconcilePage(uid);
  await syncPublicBadgeForUser(uid, { database: db, fetchAuthUser: badgeAuth });
  assert.equal(await dataOf(`publicBadges/${uid}`), null, "hidden: no page, no VIP, no badge");
});

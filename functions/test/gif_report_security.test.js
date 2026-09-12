const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.NODE_ENV = "test";
const { deleteApp, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const app = initializeApp({ projectId: "demo-yovoice-gif-report-security" });
const db = getFirestore(app);
const {
  createGifModeration, evidenceSnapshot, gifReportId, MAX_GIF_REPORT_EVIDENCE_LENGTH,
} = require("../media/gif/moderation");
const { createGifFunctions, createGifRuntime } = require("../media/gif/catalog");
const { createFakeGifProvider } = require("../media/gif/fake_provider");
const { gifCdnUrl } = require("../media/gif/gif_ref");
const { REPORT_ATTEMPT_LIMIT, REPORT_DAILY_LIMIT } = require("../media/gif/rate_limit");
const { moderateReport, SAFE_REPORT_ID, moderationAuditId } = require("../moderation/reports");
const { rateLimitReference } = require("../integrity/guards");

const REPORTER = "gif-security-reporter";
const MODERATOR = "gif-security-moderator";
const PROVIDER = "fake";
const GIF_ID = "fakeCat01";
const ASSET_PATH = `gifAssets/${PROVIDER}_${GIF_ID}`;
const nowMs = 1_900_000_000_000;
const silentLog = { info() {}, warn() {}, error() {} };
let callables;

function auth(uid = REPORTER, verified = true) {
  return { uid, token: { email_verified: verified } };
}

function report(gifId = GIF_ID, uid = REPORTER, overrides = {}) {
  return callables.reportGifAsset({
    auth: auth(uid, false),
    data: { provider: PROVIDER, gifId, reason: "sexual", requestId: `report-${gifId}`, ...overrides },
  });
}

function triage(reportId, overrides = {}) {
  return (moderateReport.run ?? moderateReport)({
    auth: { uid: MODERATOR, token: { role: "moderator", auth_time: Math.floor(Date.now() / 1000) } },
    data: { reportId, action: "removeAndResolve", resolution: "contentRemoved",
      requestId: "gif-sec-triage-001", ...overrides },
  });
}

async function seedAsset(id = GIF_ID, overrides = {}) {
  await db.doc(`gifAssets/${PROVIDER}_${id}`).set({
    schemaVersion: 1, provider: PROVIDER, gifId: id, rating: "g", title: "Happy cat",
    url: gifCdnUrl(PROVIDER, id), previewUrl: gifCdnUrl(PROVIDER, id),
    width: 200, height: 200, blocked: false, reportCount: 0, ...overrides,
  });
}

async function clear() {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
}

function functions(provider = createFakeGifProvider()) {
  return createGifFunctions({
    runtime: createGifRuntime({ db, provider, now: () => nowMs, log: silentLog }),
    providerName: PROVIDER,
    registrars: { onCall: (_options, handler) => handler },
  });
}

beforeEach(async () => {
  await clear();
  await db.doc(`users/${REPORTER}`).set({ uid: REPORTER, banned: false });
  await db.doc(`users/${MODERATOR}`).set({ uid: MODERATOR, displayName: "Mod", role: "moderator" });
  await seedAsset();
  callables = functions();
});

after(async () => { await clear(); await db.terminate(); await deleteApp(app); });

for (const stage of ["asset", "audit"]) {
  test(`a failed ${stage} write leaves no GIF block, terminal report or audit; the same request can retry`, async () => {
    const filed = await report();
    const original = db.runTransaction;
    db.runTransaction = function (callback, options) {
      return original.call(this, (transaction) => callback(new Proxy(transaction, {
        get(target, property) {
          const value = target[property];
          if (property === "set" || property === "create") return (reference, ...args) => {
            if ((stage === "asset" && reference.path === ASSET_PATH) ||
                (stage === "audit" && reference.path.startsWith("adminAuditLogs/"))) {
              throw new Error(`injected-${stage}-write-failure`);
            }
            return value.call(target, reference, ...args);
          };
          return typeof value === "function" ? value.bind(target) : value;
        },
      })), options);
    };
    try {
      await assert.rejects(triage(filed.reportId), new RegExp(`injected-${stage}-write-failure`, "u"));
    } finally {
      db.runTransaction = original;
    }
    assert.equal((await db.doc(ASSET_PATH).get()).data().blocked, false);
    assert.equal((await db.doc(`reports/${filed.reportId}`).get()).data().status, "open");
    assert.equal((await db.collection("adminAuditLogs").get()).size, 0);
    assert.equal((await triage(filed.reportId)).contentRemoved, true);
    assert.equal((await db.doc(ASSET_PATH).get()).data().blocked, true);
    assert.equal((await triage(filed.reportId)).replayed, true);
    assert.equal((await db.collection("adminAuditLogs").get()).size, 1);
  });
}

test("missing or mismatched GIF authority cannot be marked removed", async () => {
  const filed = await report();
  await db.doc(ASSET_PATH).delete();
  await assert.rejects(triage(filed.reportId), (error) => error.code === "failed-precondition");
  await seedAsset(GIF_ID, { gifId: "another" });
  await assert.rejects(triage(filed.reportId), (error) => error.code === "failed-precondition");
  assert.equal((await db.doc(`reports/${filed.reportId}`).get()).data().status, "open");
  assert.equal((await db.collection("adminAuditLogs").get()).size, 0);
});

test("replay repairs the optional suppression index without another block or audit", async () => {
  const filed = await report();
  await triage(filed.reportId);
  const asset = (await db.doc(ASSET_PATH).get()).data();
  await db.doc("gifBlocklist/current").delete();
  assert.equal((await triage(filed.reportId)).replayed, true);
  assert.deepEqual((await db.doc(ASSET_PATH).get()).data(), asset);
  assert.ok((await db.doc("gifBlocklist/current").get()).data().assetIds.includes(`${PROVIDER}_${GIF_ID}`));
  assert.equal((await db.collection("adminAuditLogs").get()).size, 1);
  assert.ok((await db.doc(`adminAuditLogs/${moderationAuditId(filed.reportId, "gif-sec-triage-001")}`).get()).exists);
});

test("malformed GIF evidence cannot authorize a moderation block", async () => {
  const filed = await report();
  const reference = db.doc(`reports/${filed.reportId}`);
  const canonical = (await reference.get()).data();
  for (const change of [
    { reportedUserId: REPORTER },
    { gifId: "different" },
    { reason: "not-a-reason" },
    { targetMediaUrl: "https://attacker.example/arbitrary.gif" },
    { targetTextSnapshot: "x".repeat(MAX_GIF_REPORT_EVIDENCE_LENGTH + 1) },
  ]) {
    await reference.set({ ...canonical, ...change });
    await assert.rejects(triage(filed.reportId), (error) => error.code === "failed-precondition");
    assert.equal((await db.doc(ASSET_PATH).get()).data().blocked, false);
    assert.equal((await reference.get()).data().status, "open");
  }
  assert.equal((await db.collection("adminAuditLogs").get()).size, 0);
});

test("opaque and maximum-length identities produce actionable bounded reports", async () => {
  const id = `gif.${"a".repeat(124)}`;
  await seedAsset(id, { title: "t".repeat(100) });
  const ids = new Set();
  for (const uid of ["user.name", "Żółw-用户", "u".repeat(128)]) {
    await db.doc(`users/${uid}`).set({ uid, banned: false });
    const filed = await report(id, uid, { requestId: "report-max-id-001" });
    assert.equal(SAFE_REPORT_ID.test(filed.reportId), true);
    assert.equal(filed.reportId, gifReportId(uid, PROVIDER, id));
    ids.add(filed.reportId);
    const stored = (await db.doc(`reports/${filed.reportId}`).get()).data();
    assert.ok(stored.targetTextSnapshot.startsWith(`${PROVIDER}:${id} — `));
    assert.ok(stored.targetTextSnapshot.length <= MAX_GIF_REPORT_EVIDENCE_LENGTH);
    assert.equal((await triage(filed.reportId)).status, "resolved");
    assert.equal((await report(id, uid, { requestId: "report-max-id-retry" })).created, false);
  }
  assert.equal(ids.size, 3);
  assert.equal((await db.doc(`gifAssets/${PROVIDER}_${id}`).get()).data().reportCount, 3);
});

test("report evidence is sanitized and retains the full provider/id within the shared maximum", () => {
  const id = "a".repeat(128);
  const text = evidenceSnapshot({ provider: "giphy", id, title: `\u202e${"t".repeat(100)}` });
  assert.equal(text.length, MAX_GIF_REPORT_EVIDENCE_LENGTH);
  assert.ok(text.startsWith(`giphy:${id} — `));
  assert.equal(text.includes("\u202e"), false);
});

test("search and safety reporting refuse missing, banned, disabled and deleted accounts", async () => {
  let providerCalls = 0;
  const provider = createFakeGifProvider();
  callables = functions({ ...provider, trending: async (input) => {
    providerCalls += 1;
    return provider.trending(input);
  } });
  for (const state of [null, { banned: true }, { disabled: true }, { deleted: true },
    { status: "deleted" }, { authDeletedAt: Timestamp.fromMillis(nowMs) }]) {
    if (state === null) await db.doc(`users/${REPORTER}`).delete();
    else await db.doc(`users/${REPORTER}`).set({ uid: REPORTER, ...state });
    const expected = state === null ? "not-found" : "permission-denied";
    await assert.rejects(callables.searchGifs({ auth: auth(), data: {} }), (error) => error.code === expected);
    await assert.rejects(report(), (error) => error.code === expected);
  }
  assert.equal(providerCalls, 0);
  assert.equal((await db.collection("reports").get()).size, 0);
  assert.equal((await db.doc(ASSET_PATH).get()).data().reportCount, 0);
});

test("a warm cached search still rechecks the account before returning media", async () => {
  const first = await callables.searchGifs({ auth: auth(), data: {} });
  assert.ok(first.items.length > 0);
  assert.equal((await callables.searchGifs({ auth: auth(), data: {} })).cacheHit, true);
  await db.doc(`users/${REPORTER}`).update({ banned: true });
  await assert.rejects(callables.searchGifs({ auth: auth(), data: {} }),
    (error) => error.code === "permission-denied");
});

test("an active unverified account can report while discovery is disabled", async () => {
  await db.doc("appConfig/gif").set({ enabled: false });
  assert.equal((await callables.getGifCatalog({ auth: auth(REPORTER, false), data: {} })).available, false);
  assert.equal((await report()).created, true);
});

test("refused report targets consume a bounded per-actor attempt quota", async () => {
  for (let index = 0; index < REPORT_ATTEMPT_LIMIT; index += 1) {
    await assert.rejects(report(`missing${index}`), (error) => error.code === "not-found");
  }
  await assert.rejects(report("missingAgain"), (error) => error.code === "resource-exhausted");
  const state = (await rateLimitReference(db, "gif.report.attempt", REPORTER).get()).data();
  assert.equal(state.count, REPORT_ATTEMPT_LIMIT);
  assert.equal((await db.collection("reports").get()).size, 0);
});

test("new-report quota is capped while exact-target retries remain one vote", async () => {
  let first;
  for (let index = 0; index < REPORT_DAILY_LIMIT; index += 1) {
    const id = `limit${index}`;
    await seedAsset(id);
    const filed = await report(id);
    if (index === 0) first = filed;
  }
  await seedAsset("overDaily");
  await assert.rejects(report("overDaily"), (error) => error.code === "resource-exhausted");
  const replay = await report("limit0");
  assert.equal(replay.created, false);
  assert.equal(replay.reportId, first.reportId);
  assert.equal((await db.doc(`gifAssets/${PROVIDER}_limit0`).get()).data().reportCount, 1);
  assert.equal((await db.collection("reports").get()).size, REPORT_DAILY_LIMIT);
  const state = (await rateLimitReference(db, "gif.report.create", REPORTER).get()).data();
  assert.equal(state.count, REPORT_DAILY_LIMIT);
});

test("concurrent duplicate reports consume attempts but create one report and daily vote", async () => {
  const results = await Promise.all([report(), report()]);
  assert.deepEqual(results.map((entry) => entry.created).sort(), [false, true]);
  assert.equal(results[0].reportId, results[1].reportId);
  assert.equal((await db.doc(ASSET_PATH).get()).data().reportCount, 1);
  assert.equal((await db.collection("reports").get()).size, 1);
  assert.equal((await rateLimitReference(db, "gif.report.attempt", REPORTER).get()).data().count, 2);
  assert.equal((await rateLimitReference(db, "gif.report.create", REPORTER).get()).data().count, 1);
});

test("the report transaction rechecks current account activity before committing a report", async () => {
  await db.doc(`users/${REPORTER}`).update({ disabled: true });
  await assert.rejects(createGifModeration({ db }).reportAsset({
    reporterId: REPORTER, provider: PROVIDER, gifId: GIF_ID, reason: "spam",
  }), (error) => error.code === "permission-denied");
  assert.equal((await db.collection("reports").get()).size, 0);
});

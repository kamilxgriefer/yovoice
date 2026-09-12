const assert = require("node:assert/strict");
const { after, before, beforeEach, test } = require("node:test");

// The three GIF callables, against the REAL Firestore emulator.
//
// Emulator-backed rather than in-memory on purpose: the cache, the token
// bucket and the hourly budget are all transaction-and-TTL behaviour, and an
// in-memory double that does not implement `FieldValue.increment` or real
// `Timestamp` comparison would prove the tests pass rather than the system
// works. The counts asserted below are real document reads and writes.
//
// Start the emulator first:  firebase emulators:start --only firestore

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";
process.env.NODE_ENV = "test";

const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const app = initializeApp(
  { projectId: process.env.GCLOUD_PROJECT },
  "gif-catalog-test",
);
const db = getFirestore(app);

const {
  availability,
  catalogResponse,
  createGifFunctions,
  createGifRuntime,
} = require("../media/gif/catalog");
const { createFakeGifProvider } = require("../media/gif/fake_provider");
const { createGifProvider } = require("../media/gif/provider");
const { GifProviderError } = require("../media/gif/provider");
const { GIF_RATING } = require("../media/gif/gif_ref");

const UID = "gif-catalog-tester";
const USERS = [UID, "someone-else", "another-account", "unrelated-account"];

/// The callable registrar, replaced by something that just hands back the
/// handler. Registering real Cloud Functions in a unit test would need the
/// whole functions framework and would test firebase-functions, not this.
function captureRegistrars() {
  const options = [];
  return {
    options,
    registrars: {
      onCall(callableOptions, handler) {
        options.push(callableOptions);
        return handler;
      },
    },
  };
}

function request(data = {}, uid = UID) {
  return {
    auth: { uid, token: { email_verified: true } },
    data,
  };
}

async function wipe(...collections) {
  for (const name of collections) {
    const snapshot = await db.collection(name).get();
    await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
  }
}

async function reset() {
  await wipe(
    "gifQueryCache",
    "gifAssets",
    "gifRateLimits",
    "gifProviderBudget",
    "gifBlocklist",
    "reports",
  );
  await db.doc("appConfig/gif").delete();
  await Promise.all(USERS.map((uid) => db.doc(`users/${uid}`).delete()));
}

const silentLog = { info() {}, warn() {}, error() {} };

function runtimeWith(provider, overrides = {}) {
  return createGifRuntime({
    db,
    provider,
    log: silentLog,
    ...overrides,
  });
}

before(reset);
beforeEach(async () => {
  await reset();
  await Promise.all(USERS.map((uid) => db.doc(`users/${uid}`).set({ uid, banned: false })));
});
after(reset);

// ---------------------------------------------------------------------------
// Availability — the "no key configured" contract, which is production today.
// ---------------------------------------------------------------------------

test("with no provider configured the catalog says so and binds no secret", async () => {
  const { registrars, options } = captureRegistrars();
  const exportsMap = createGifFunctions({
    runtime: runtimeWith(null),
    registrars,
    providerName: "none",
  });

  assert.deepEqual(Object.keys(exportsMap), ["getGifCatalog"]);
  assert.equal(options.length, 1);
  assert.equal(options[0].secrets, undefined);

  const answer = await exportsMap.getGifCatalog(request());
  assert.equal(answer.available, false);
  assert.equal(answer.reason, "not_configured");
  assert.equal(answer.provider, "none");
  assert.equal(answer.attribution, null);
  assert.equal(answer.ratingLabel, GIF_RATING);
  assert.ok(answer.categories.length > 0);
});

test("GIF_PROVIDER=none returns no adapter at all", () => {
  assert.equal(createGifProvider({ provider: "none" }), null);
  assert.equal(createGifProvider({ provider: "" }), null);
});

test("the fixture provider is refused outside the emulator and NODE_ENV=test", () => {
  assert.throws(
    () => createGifProvider({ provider: "fake", env: {} }),
    /only available in the emulator/u,
  );
  // ...and is available here, because this process really is a test run.
  assert.notEqual(createGifProvider({ provider: "fake" }), null);
});

test("a provider whose key is empty reports provider_not_configured", async () => {
  const unconfigured = {
    id: "giphy",
    attribution: { text: "Powered by GIPHY", required: true },
    isConfigured: false,
    search: async () => ({ items: [], nextCursor: null }),
    trending: async () => ({ items: [], nextCursor: null }),
    resolve: async () => ({ items: [], nextCursor: null }),
  };
  const state = await availability(runtimeWith(unconfigured));
  assert.equal(state.available, false);
  assert.equal(state.reason, "provider_not_configured");
});

test("appConfig/gif.enabled=false is an instant kill switch with no deploy", async () => {
  const runtime = runtimeWith(createFakeGifProvider());
  assert.equal((await availability(runtime)).available, true);

  await db.doc("appConfig/gif").set({ enabled: false });
  const stale = createGifRuntime({
    db,
    provider: createFakeGifProvider(),
    log: silentLog,
  });
  const state = await availability(stale);
  assert.equal(state.available, false);
  assert.equal(state.reason, "disabled");
  assert.equal(catalogResponse(state).available, false);
});

// ---------------------------------------------------------------------------
// searchGifs
// ---------------------------------------------------------------------------

function fakeFunctions(overrides = {}) {
  const { registrars, options } = captureRegistrars();
  const runtime = runtimeWith(createFakeGifProvider(), overrides);
  const exportsMap = createGifFunctions({
    runtime,
    registrars,
    providerName: "fake",
  });
  return { exportsMap, runtime, options };
}

test("a configured provider registers all three callables, two of them secret-bound", () => {
  const { exportsMap, options } = fakeFunctions();
  assert.deepEqual(Object.keys(exportsMap).sort(), [
    "getGifCatalog",
    "reportGifAsset",
    "searchGifs",
  ]);
  assert.equal(options[0].secrets, undefined);
  assert.equal(options[1].secrets.length, 1);
  assert.equal(options[2].secrets.length, 1);
  for (const option of options) {
    assert.equal(option.region, "europe-west1");
  }
});

test("a blank query is trending, and results are written to gifAssets first", async () => {
  const { exportsMap } = fakeFunctions();
  const page = await exportsMap.searchGifs(request({ query: "" }));

  assert.equal(page.degraded, false);
  assert.equal(page.cacheHit, false);
  assert.ok(page.items.length > 0);

  // Every item the client can see has a gifAssets document. That is the
  // invariant firestore.rules depends on: the send rule `exists()`-checks it.
  for (const item of page.items) {
    const snapshot = await db.doc(`gifAssets/${item.provider}_${item.id}`).get();
    assert.ok(snapshot.exists, `${item.id} was returned without being stored`);
    assert.equal(snapshot.data().rating, GIF_RATING);
  }
});

test("the response re-filter drops every asset that is not rated g", async () => {
  const { exportsMap } = fakeFunctions();
  const page = await exportsMap.searchGifs(request({ query: "", limit: 30 }));
  const ids = page.items.map((item) => item.id);

  // The fixture catalog deliberately contains one `pg` and one unrated asset.
  assert.ok(!ids.includes("fakeBad01"), "a pg-rated asset reached the client");
  assert.ok(!ids.includes("fakeBad02"), "an unrated asset reached the client");
  for (const item of page.items) assert.equal(item.rating, GIF_RATING);
});

test("a search hits the shared cache on the second call and costs the provider nothing", async () => {
  let providerCalls = 0;
  const counting = createFakeGifProvider();
  const wrapped = {
    ...counting,
    async search(input) {
      providerCalls += 1;
      return counting.search(input);
    },
  };
  const { registrars } = captureRegistrars();
  const exportsMap = createGifFunctions({
    runtime: runtimeWith(wrapped),
    registrars,
    providerName: "fake",
  });

  const first = await exportsMap.searchGifs(request({ query: "cat" }));
  assert.equal(first.cacheHit, false);
  assert.equal(providerCalls, 1);

  // A second, DIFFERENT caller: the cache is shared across accounts, which is
  // what makes a beta key survivable.
  const second = await exportsMap.searchGifs(
    request({ query: "cat" }, "someone-else"),
  );
  assert.equal(second.cacheHit, true);
  assert.equal(providerCalls, 1);
  assert.deepEqual(
    second.items.map((item) => item.id),
    first.items.map((item) => item.id),
  );

  // Only one budget slot was ever claimed, because a hit never reaches the
  // provider.
  const budget = await db.collection("gifProviderBudget").get();
  assert.equal(budget.size, 1);
  assert.equal(budget.docs[0].data().calls, 1);
});

test("query normalization collapses casing and whitespace into one cache entry", async () => {
  const { exportsMap } = fakeFunctions();
  await exportsMap.searchGifs(request({ query: "Kot" }));
  await exportsMap.searchGifs(request({ query: "  kot " }));
  await exportsMap.searchGifs(request({ query: "KOT" }));

  const cache = await db.collection("gifQueryCache").get();
  assert.equal(cache.size, 1);
});

test("a denylisted query returns empty results, neutral, with no provider call", async () => {
  let providerCalls = 0;
  const base = createFakeGifProvider();
  const { registrars } = captureRegistrars();
  const exportsMap = createGifFunctions({
    runtime: runtimeWith({
      ...base,
      async search(input) {
        providerCalls += 1;
        return base.search(input);
      },
    }),
    registrars,
    providerName: "fake",
  });

  const page = await exportsMap.searchGifs(request({ query: "porn cats" }));
  assert.deepEqual(page.items, []);
  assert.equal(page.degraded, false);
  assert.equal(providerCalls, 0);
  // Nothing is cached either — a denied query must not occupy a cache slot.
  assert.equal((await db.collection("gifQueryCache").get()).size, 0);
});

test("an ordinary word that merely contains a denied substring is not refused", async () => {
  const { exportsMap } = fakeFunctions();
  const page = await exportsMap.searchGifs(request({ query: "assassin" }));
  assert.equal(page.degraded, false);
  assert.equal((await db.collection("gifQueryCache").get()).size, 1);
});

test("the per-account limit refuses with resource-exhausted and a retry hint", async () => {
  const { exportsMap } = fakeFunctions();
  let refusal = null;
  // Burst capacity is 10. The eleventh call inside one second must be refused,
  // and the caller must be told when to come back.
  for (let index = 0; index < 12 && refusal === null; index += 1) {
    try {
      await exportsMap.searchGifs(request({ query: `q${index}` }));
    } catch (error) {
      refusal = error;
    }
  }
  assert.notEqual(refusal, null, "the bucket never refused");
  assert.equal(refusal.code, "resource-exhausted");
  assert.ok(refusal.details.retryAfterSeconds >= 1);

  // A different account is unaffected: the limit is per uid, not global.
  const other = await exportsMap.searchGifs(
    request({ query: "cat" }, "unrelated-account"),
  );
  assert.ok(other.items.length > 0);
});

test("an exhausted hourly budget degrades to cached trending instead of erroring", async () => {
  const { exportsMap } = fakeFunctions({ hourlyProviderBudget: 1 });
  // The single budgeted call warms the trending page...
  const warm = await exportsMap.searchGifs(request({ query: "" }));
  assert.ok(warm.items.length > 0);

  // ...and the next miss cannot claim a slot, so it degrades rather than 500s.
  const degraded = await exportsMap.searchGifs(request({ query: "kot" }));
  assert.equal(degraded.degraded, true);
  assert.ok(degraded.items.length > 0);
});

test("a provider error with no cache behind it surfaces as unavailable", async () => {
  const broken = {
    ...createFakeGifProvider(),
    async search() {
      throw new GifProviderError("boom", { status: 503, code: "provider_error" });
    },
  };
  const { registrars } = captureRegistrars();
  const exportsMap = createGifFunctions({
    runtime: runtimeWith(broken),
    registrars,
    providerName: "fake",
  });

  await assert.rejects(
    () => exportsMap.searchGifs(request({ query: "kot" })),
    (error) => {
      assert.equal(error.code, "unavailable");
      return true;
    },
  );
});

test("a revoked key trips the breaker, and the catalog then reports it", async () => {
  const revoked = {
    ...createFakeGifProvider(),
    async trending() {
      throw new GifProviderError("401", {
        status: 401,
        code: "provider_unauthorized",
      });
    },
  };
  const { registrars } = captureRegistrars();
  const runtime = runtimeWith(revoked);
  const exportsMap = createGifFunctions({
    runtime,
    registrars,
    providerName: "fake",
  });

  await assert.rejects(() => exportsMap.searchGifs(request({ query: "" })));
  assert.equal(runtime.breaker.open, true);
  assert.equal(runtime.breaker.code, "provider_unauthorized");

  const answer = await exportsMap.getGifCatalog(request());
  assert.equal(answer.available, false);
  assert.equal(answer.reason, "provider_unavailable");
});

test("searchGifs refuses an unknown input field rather than ignoring it", async () => {
  const { exportsMap } = fakeFunctions();
  await assert.rejects(
    () => exportsMap.searchGifs(request({ query: "kot", rating: "r" })),
    (error) => {
      assert.equal(error.code, "invalid-argument");
      // The important half: `rating` is not a parameter, so no client can ask
      // for anything looser than `g`.
      assert.match(error.message, /rating/u);
      return true;
    },
  );
});

test("searchGifs requires authentication", async () => {
  const { exportsMap } = fakeFunctions();
  await assert.rejects(
    () => exportsMap.searchGifs({ data: { query: "kot" } }),
    (error) => error.code === "unauthenticated",
  );
});

test("a suppressed asset disappears from a page that is already cached", async () => {
  const { exportsMap, runtime } = fakeFunctions();
  const first = await exportsMap.searchGifs(request({ query: "cat" }));
  const victim = first.items[0];
  assert.ok(victim);

  await runtime.moderation.blockAsset({
    provider: victim.provider,
    gifId: victim.id,
    blockedBy: "moderator-1",
  });

  // Same query, still inside the six-hour TTL, so this IS a cache hit — and
  // the blocked asset is gone from it anyway. That is the whole reason the
  // suppression index exists.
  const second = await exportsMap.searchGifs(
    request({ query: "cat" }, "another-account"),
  );
  assert.equal(second.cacheHit, true);
  assert.ok(!second.items.some((item) => item.id === victim.id));
});

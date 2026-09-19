"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

// ADR-210, option B: GIPHY search runs in the client, and the server resolves
// ONE chosen id at send time. These tests run with no emulator, no network and
// no key: the runtime is an in-memory double of exactly the surface the
// `resolveGif` handler touches, and the GIPHY adapter is the real one driven by
// an injected fetch, so rating pinning and URL derivation are the production
// code paths.

process.env.NODE_ENV = "test";

const { createGifFunctions, catalogResponse, createBreaker } =
  require("../media/gif/catalog");
const { createGiphyProvider } = require("../media/gif/giphy_provider");
const { gifCdnUrl } = require("../media/gif/gif_ref");
const {
  resolveMessageGif,
  sendableGifProviders,
} = require("../messaging/gif_message");

const UID = "resolver";
const silentLog = { info() {}, warn() {}, error() {} };

function giphyItem(overrides = {}) {
  return {
    id: "giphyGoodOne",
    title: "excited cat GIF",
    rating: "g",
    images: {
      fixed_height: {
        url: "https://media3.giphy.com/media/giphyGoodOne/200h.gif",
        width: "356",
        height: "200",
      },
      fixed_height_small: {
        url: "https://media3.giphy.com/media/giphyGoodOne/100h.gif",
        width: "178",
        height: "100",
      },
    },
    ...overrides,
  };
}

function recordingFetch(respond) {
  const calls = [];
  const impl = async (url) => {
    calls.push(url);
    return respond(url);
  };
  return { calls, impl };
}

function okJson(payload) {
  return { ok: true, status: 200, json: async () => payload };
}

/// The in-memory runtime. `assets` is the `gifAssets` collection keyed by
/// document id, which is what the send transaction later reads.
function fakeRuntime({
  provider,
  config = {},
  assets = new Map(),
  suppressed = new Set(),
  bucketAllowed = true,
  budget = 5,
  profile = { uid: UID, banned: false },
} = {}) {
  const state = { claims: 0, consumed: 0, writes: 0 };
  const breaker = createBreaker();
  const cache = {
    async readAsset(providerName, id) {
      const record = assets.get(`${providerName}_${id}`);
      return record ? { id: `${providerName}_${id}`, ...record } : null;
    },
    async suppressedAssetIds() {
      return suppressed;
    },
    async writeAssets(items) {
      const written = new Set();
      const blocked = new Set();
      for (const item of items) {
        const documentId = `${item.provider}_${item.id}`;
        const previous = assets.get(documentId);
        if (previous?.blocked === true) blocked.add(documentId);
        assets.set(documentId, {
          reportCount: 0,
          blocked: false,
          ...previous,
          schemaVersion: 1,
          provider: item.provider,
          gifId: item.id,
          title: item.title,
          rating: item.rating,
          url: item.full.url,
          previewUrl: item.preview.url,
          width: item.full.width,
          height: item.full.height,
        });
        state.writes += 1;
        written.add(documentId);
      }
      return { written, blocked };
    },
  };
  return {
    state,
    assets,
    runtime: {
      breaker,
      cache,
      db: {
        doc: (path) => ({
          get: async () => ({
            exists: path === `users/${UID}` && profile !== null,
            data: () => profile,
          }),
        }),
      },
      limiter: {
        async consume() {
          state.consumed += 1;
          return bucketAllowed
            ? { allowed: true, retryAfterSeconds: 0 }
            : { allowed: false, retryAfterSeconds: 7 };
        },
        async claimProviderCall() {
          state.claims += 1;
          return state.claims <= budget;
        },
      },
      log: silentLog,
      now: () => Date.now(),
      readConfig: async () => config,
      resolveProvider: () => provider,
    },
  };
}

function build(runtime, { resolveProviders = ["giphy"] } = {}) {
  const options = [];
  const callables = createGifFunctions({
    runtime: {
      ...runtime,
      resolveProvider: () => ({
        id: "yovoice",
        attribution: { text: "YO Voice Originals", required: false },
      }),
    },
    resolveRuntime: runtime,
    providerName: "yovoice",
    resolveProviders,
    registrars: {
      onCall(callableOptions, handler) {
        options.push(callableOptions);
        return handler;
      },
    },
  });
  return { callables, options };
}

function request(data, uid = UID) {
  return { auth: { uid, token: { email_verified: true } }, data };
}

function giphyWith(fetchImpl) {
  return createGiphyProvider({ apiKey: "test-only-not-a-key", fetchImpl });
}

test("resolveGif is not registered while no remote provider is source-enabled", () => {
  const { runtime } = fakeRuntime({ provider: null });
  const { callables } = build(runtime, { resolveProviders: [] });
  assert.equal(callables.resolveGif, undefined);
  assert.ok(callables.searchGifs);
});

test("only GIPHY can be enabled for resolve-by-id", () => {
  const { runtime } = fakeRuntime({ provider: null });
  assert.throws(() => build(runtime, { resolveProviders: ["yovoice"] }), TypeError);
  assert.throws(() => build(runtime, { resolveProviders: ["fake"] }), TypeError);
});

test("the catalog advertises resolvable providers only while available", () => {
  const available = { available: true, reason: null, provider: null };
  assert.deepEqual(
    catalogResponse(available, { resolvableProviders: ["giphy"] }).resolvableProviders,
    ["giphy"],
  );
  assert.deepEqual(
    catalogResponse({ available: false, reason: "disabled", provider: null }, {
      resolvableProviders: ["giphy"],
    }).resolvableProviders,
    [],
  );
  assert.deepEqual(catalogResponse(available).resolvableProviders, []);
});

test("getGifCatalog tells the client GIPHY is resolvable when enabled", async () => {
  const { runtime } = fakeRuntime({ provider: null });
  const { callables } = build(runtime);
  const catalog = await callables.getGifCatalog(request({}));
  assert.equal(catalog.provider, "yovoice");
  assert.deepEqual(catalog.resolvableProviders, ["giphy"]);
});

test("a first sighting fetches the id once with rating g and pins the CDN URL", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem() }));
  const { runtime, state, assets } = fakeRuntime({ provider: giphyWith(fetch.impl) });
  const { callables } = build(runtime);

  const result = await callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" }));

  assert.deepEqual(result.asset, {
    provider: "giphy",
    id: "giphyGoodOne",
    title: "excited cat",
    url: gifCdnUrl("giphy", "giphyGoodOne"),
    width: 356,
    height: 200,
    rating: "g",
  });
  assert.equal(fetch.calls.length, 1);
  const url = new URL(fetch.calls[0]);
  assert.equal(url.pathname, "/v1/gifs/giphyGoodOne");
  assert.equal(url.searchParams.get("rating"), "g");
  assert.equal(state.claims, 1);
  assert.equal(assets.get("giphy_giphyGoodOne").blocked, false);

  // Second resolve: the record answers, the provider and the budget do not.
  await callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" }));
  assert.equal(fetch.calls.length, 1);
  assert.equal(state.claims, 1);
  assert.equal(state.consumed, 2);
});

test("the resolved record is exactly what the send transaction accepts", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem() }));
  const { runtime, assets } = fakeRuntime({ provider: giphyWith(fetch.impl) });
  const { callables } = build(runtime);
  await callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" }));

  const record = assets.get("giphy_giphyGoodOne");
  const transaction = {
    get: async (reference) => {
      if (reference.path === "appConfig/gif") return { exists: true, data: () => ({ enabled: true }) };
      return { exists: true, data: () => record };
    },
  };
  const db = { doc: (path) => ({ path }) };
  const gif = await resolveMessageGif({
    db,
    transaction,
    gif: { provider: "giphy", id: "giphyGoodOne" },
    providerNames: ["yovoice", "giphy"],
  });
  assert.equal(gif.url, "https://media.giphy.com/media/giphyGoodOne/200h.gif");
  assert.equal(gif.title, "excited cat");
});

test("a non-g asset is refused and never written", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem({ rating: "pg-13" }) }));
  const { runtime, assets } = fakeRuntime({ provider: giphyWith(fetch.impl) });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.code === "failed-precondition" && error.details.code === "rating",
  );
  assert.equal(assets.size, 0);
});

test("a title that trips the static denylist is refused and never written", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem({ title: "nsfw dance GIF" }) }));
  const { runtime, assets } = fakeRuntime({ provider: giphyWith(fetch.impl) });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.details?.code === "filtered",
  );
  assert.equal(assets.size, 0);
});

test("a moderator block wins without contacting the provider", async () => {
  const fetch = recordingFetch(() => { throw new Error("must not fetch"); });
  const assets = new Map([["giphy_giphyGoodOne", {
    schemaVersion: 1, provider: "giphy", gifId: "giphyGoodOne", title: "cat",
    rating: "g", blocked: true, width: 200, height: 200,
  }]]);
  const { runtime } = fakeRuntime({ provider: giphyWith(fetch.impl), assets });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.details?.code === "blocked",
  );
  assert.equal(fetch.calls.length, 0);
});

test("a suppressed id is refused before the provider is called", async () => {
  const fetch = recordingFetch(() => { throw new Error("must not fetch"); });
  const { runtime } = fakeRuntime({
    provider: giphyWith(fetch.impl),
    suppressed: new Set(["giphy_giphyGoodOne"]),
  });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.details?.code === "blocked",
  );
  assert.equal(fetch.calls.length, 0);
});

test("the hourly budget refuses a new id without calling the provider", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem() }));
  const { runtime } = fakeRuntime({ provider: giphyWith(fetch.impl), budget: 0 });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.code === "resource-exhausted" &&
      error.details.code === "budget_exhausted",
  );
  assert.equal(fetch.calls.length, 0);
});

test("the per-account bucket is charged before anything else", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem() }));
  const { runtime, state } = fakeRuntime({ provider: giphyWith(fetch.impl), bucketAllowed: false });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.code === "resource-exhausted" && error.details.retryAfterSeconds === 7,
  );
  assert.equal(state.claims, 0);
  assert.equal(fetch.calls.length, 0);
});

test("a 401 trips the breaker and later resolves are refused as unavailable", async () => {
  const fetch = recordingFetch(() => ({ ok: false, status: 401, json: async () => ({}) }));
  const { runtime } = fakeRuntime({ provider: giphyWith(fetch.impl) });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.code === "unavailable",
  );
  assert.equal(runtime.breaker.open, true);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "otherId" })),
    (error) => error.code === "failed-precondition" &&
      error.details.code === "provider_unavailable",
  );
  assert.equal(fetch.calls.length, 1);
});

test("the kill switch and a missing key refuse before any charge", async () => {
  const killed = fakeRuntime({ provider: giphyWith(async () => okJson({})), config: { enabled: false } });
  await assert.rejects(
    build(killed.runtime).callables.resolveGif(request({ provider: "giphy", id: "a1" })),
    (error) => error.details?.code === "disabled",
  );
  assert.equal(killed.state.consumed, 0);

  const keyless = fakeRuntime({ provider: createGiphyProvider({ apiKey: "", fetchImpl: async () => okJson({}) }) });
  await assert.rejects(
    build(keyless.runtime).callables.resolveGif(request({ provider: "giphy", id: "a1" })),
    (error) => error.details?.code === "provider_not_configured",
  );
});

test("the request shape is exact and the provider must be resolvable", async () => {
  const { runtime } = fakeRuntime({ provider: giphyWith(async () => okJson({ data: giphyItem() })) });
  const { callables } = build(runtime);
  for (const data of [
    { provider: "yovoice", id: "yoFire01" },
    { provider: "giphy", id: "../x" },
    { provider: "giphy", id: "ok", url: "https://evil.example/x.gif" },
    { provider: "giphy" },
  ]) {
    await assert.rejects(callables.resolveGif(request(data)), (error) =>
      error.code === "invalid-argument", JSON.stringify(data));
  }
  await assert.rejects(
    callables.resolveGif({ auth: null, data: { provider: "giphy", id: "ok" } }),
    (error) => error.code === "unauthenticated",
  );
});

test("a mismatched provider answer is refused as unknown", async () => {
  const fetch = recordingFetch(() => okJson({ data: giphyItem({ id: "somethingElse" }) }));
  const { runtime, assets } = fakeRuntime({ provider: giphyWith(fetch.impl) });
  const { callables } = build(runtime);
  await assert.rejects(
    callables.resolveGif(request({ provider: "giphy", id: "giphyGoodOne" })),
    (error) => error.details?.code === "unknown_asset",
  );
  assert.equal(assets.size, 0);
});

// ---------------------------------------------------------------------------
// The send allow-set.
// ---------------------------------------------------------------------------

test("the send allow-set accepts a name, a list, and drops everything unserveable", () => {
  assert.deepEqual([...sendableGifProviders("yovoice")], ["yovoice"]);
  assert.deepEqual([...sendableGifProviders(["yovoice", "giphy"])], ["yovoice", "giphy"]);
  assert.deepEqual([...sendableGifProviders([" giphy ", "none", "", 7, null])], ["giphy"]);
  assert.deepEqual([...sendableGifProviders(null)], []);
  assert.deepEqual([...sendableGifProviders("none")], []);
});

function sendFixture(record, { enabled = true } = {}) {
  const reads = [];
  return {
    reads,
    db: { doc: (path) => ({ path }) },
    transaction: {
      get: async (reference) => {
        reads.push(reference.path);
        if (reference.path === "appConfig/gif") {
          return { exists: true, data: () => ({ enabled }) };
        }
        return record ? { exists: true, data: () => record } : { exists: false };
      },
    },
  };
}

const originalsRecord = {
  schemaVersion: 1, provider: "yovoice", gifId: "yoFire01", title: "That is fire",
  rating: "g", blocked: false, width: 320, height: 200,
};
const giphyRecord = {
  schemaVersion: 1, provider: "giphy", gifId: "giphyGoodOne", title: "excited cat",
  rating: "g", blocked: false, width: 356, height: 200,
};

test("both Originals and GIPHY send through one allow-set", async () => {
  for (const [gif, record, url] of [
    [{ provider: "yovoice", id: "yoFire01" }, originalsRecord, "asset://yovoice/gifs/yoFire01.gif"],
    [{ provider: "giphy", id: "giphyGoodOne" }, giphyRecord, "https://media.giphy.com/media/giphyGoodOne/200h.gif"],
  ]) {
    const fixture = sendFixture(record);
    const resolved = await resolveMessageGif({
      ...fixture,
      gif,
      providerName: "yovoice",
      providerNames: ["yovoice", "giphy"],
    });
    assert.equal(resolved.url, url);
    assert.deepEqual(fixture.reads, ["appConfig/gif", `gifAssets/${gif.provider}_${gif.id}`]);
  }
});

test("the legacy single provider still refuses the other provider", async () => {
  const fixture = sendFixture(giphyRecord);
  await assert.rejects(resolveMessageGif({
    ...fixture,
    gif: { provider: "giphy", id: "giphyGoodOne" },
    providerName: "yovoice",
  }), (error) => error.details?.code === "not_configured");
  assert.deepEqual(fixture.reads, []);
});

test("a provider outside the allow-set, or fake in production, is refused", async () => {
  const fixture = sendFixture(giphyRecord);
  await assert.rejects(resolveMessageGif({
    ...fixture,
    gif: { provider: "giphy", id: "giphyGoodOne" },
    providerNames: ["yovoice"],
  }), (error) => error.details?.code === "not_configured");

  const previous = process.env.NODE_ENV;
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  const functionsEmulator = process.env.FUNCTIONS_EMULATOR;
  process.env.NODE_ENV = "production";
  delete process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FUNCTIONS_EMULATOR;
  try {
    await assert.rejects(resolveMessageGif({
      ...sendFixture({ ...giphyRecord, provider: "fake" }),
      gif: { provider: "fake", id: "giphyGoodOne" },
      providerNames: ["yovoice", "giphy", "fake"],
    }), (error) => error.details?.code === "not_configured");
  } finally {
    process.env.NODE_ENV = previous;
    if (emulator !== undefined) process.env.FIRESTORE_EMULATOR_HOST = emulator;
    if (functionsEmulator !== undefined) process.env.FUNCTIONS_EMULATOR = functionsEmulator;
  }
});

test("a blocked or non-g GIPHY record is refused at send time", async () => {
  for (const [override, reason] of [
    [{ blocked: true }, "blocked"],
    [{ rating: "pg" }, "rating"],
  ]) {
    await assert.rejects(resolveMessageGif({
      ...sendFixture({ ...giphyRecord, ...override }),
      gif: { provider: "giphy", id: "giphyGoodOne" },
      providerNames: ["yovoice", "giphy"],
    }), (error) => error.details?.code === reason, reason);
  }
  await assert.rejects(resolveMessageGif({
    ...sendFixture(null),
    gif: { provider: "giphy", id: "neverResolved" },
    providerNames: ["yovoice", "giphy"],
  }), (error) => error.details?.code === "unknown_asset");
});

test("the kill switch refuses both providers", async () => {
  for (const [gif, record] of [
    [{ provider: "yovoice", id: "yoFire01" }, originalsRecord],
    [{ provider: "giphy", id: "giphyGoodOne" }, giphyRecord],
  ]) {
    await assert.rejects(resolveMessageGif({
      ...sendFixture(record, { enabled: false }),
      gif,
      providerNames: ["yovoice", "giphy"],
    }), (error) => error.details?.code === "disabled");
  }
});

test("the committed source registers no resolver and binds no GIPHY key", () => {
  const source = require("node:fs").readFileSync(
    require("node:path").join(__dirname, "..", "index.js"),
    "utf8",
  );
  assert.match(source, /const GIPHY_SEND_RESOLVE_ENABLED = false;/u);
  assert.match(source, /gifProviderNames: gifSendProviders/u);
});

test("source-enabling the resolver declares GIPHY_API_KEY on resolveGif only", () => {
  const { execFileSync } = require("node:child_process");
  const path = require("node:path");
  const inspect = (resolveProviders) => JSON.parse(execFileSync(process.execPath, ["-e", [
    "const { declaredParams } = require('firebase-functions/params');",
    "const { createGifFunctions } = require('./media/gif/catalog');",
    "const registrars = { onCall: (options, handler) => ({ options, handler }) };",
    "const exported = createGifFunctions({",
    `providerName: 'yovoice', resolveProviders: ${JSON.stringify(resolveProviders)},`,
    "runtime: {}, resolveRuntime: {}, registrars,",
    "});",
    "process.stdout.write(JSON.stringify({",
    "names: declaredParams.map((param) => param.name).sort(),",
    "secrets: Object.fromEntries(Object.entries(exported).map(([name, value]) =>",
    "[name, (value.options.secrets ?? []).map((secret) => secret.name)])),",
    "}));",
  ].join(" ")], {
    cwd: path.resolve(__dirname, ".."),
    encoding: "utf8",
    env: { ...process.env, GIF_PROVIDER: "" },
    stdio: ["ignore", "pipe", "inherit"],
  }));

  const off = inspect([]);
  assert.ok(!off.names.includes("GIPHY_API_KEY"));
  assert.equal(off.secrets.resolveGif, undefined);

  const on = inspect(["giphy"]);
  assert.ok(on.names.includes("GIPHY_API_KEY"));
  assert.deepEqual(on.secrets.resolveGif, ["GIPHY_API_KEY"]);
  assert.deepEqual(on.secrets.getGifCatalog, []);
  assert.deepEqual(on.secrets.searchGifs, []);
  assert.deepEqual(on.secrets.reportGifAsset, []);
});

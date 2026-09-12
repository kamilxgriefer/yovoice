const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

// The GIPHY adapter, tested with NO API KEY and NO NETWORK.
//
// `fetchImpl` is injectable precisely so this is possible: every parsing,
// normalization, URL-pinning, rating-mapping and error-mapping path is
// exercised against recorded fixture JSON. The one thing this cannot prove is
// that GIPHY's live CDN really serves the pinned template — that is what
// functions/scripts/gif_provider_smoke.js is for, and it is step 4 of the
// activation checklist for exactly this reason.

const {
  createGiphyProvider,
  normalizeGiphyItem,
  REQUEST_TIMEOUT_MS,
} = require("../media/gif/giphy_provider");
const { GifProviderError } = require("../media/gif/provider");
const { GIF_RATING, isPinnedGifUrl } = require("../media/gif/gif_ref");

const FIXTURE = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, "fixtures", "giphy_search_response.json"),
    "utf8",
  ),
);

function recordingFetch(payload, { status = 200, ok = true } = {}) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push({ url, options });
    return {
      ok,
      status,
      json: async () => payload,
    };
  };
  impl.calls = calls;
  return impl;
}

function provider(fetchImpl) {
  return createGiphyProvider({ apiKey: "test-key", fetchImpl });
}

test("rating=g is sent on every provider request and is not caller-controlled", async () => {
  const fetchImpl = recordingFetch(FIXTURE);
  const giphy = provider(fetchImpl);

  await giphy.search({ query: "cat", locale: "pl", limit: 10, cursor: null });
  await giphy.trending({ locale: "en", limit: 10, cursor: null });
  await giphy.resolve({ id: "giphyGoodOne" });

  assert.equal(fetchImpl.calls.length, 3);
  for (const call of fetchImpl.calls) {
    const url = new URL(call.url);
    assert.equal(url.searchParams.get("rating"), GIF_RATING);
    assert.equal(url.searchParams.get("api_key"), "test-key");
  }
  // The search call forwards the query and the locale, and nothing that could
  // identify a person: no uid, no device id, no install id.
  const search = new URL(fetchImpl.calls[0].url);
  assert.equal(search.searchParams.get("q"), "cat");
  assert.equal(search.searchParams.get("lang"), "pl");
  assert.deepEqual(
    [...search.searchParams.keys()].sort(),
    ["api_key", "bundle", "lang", "limit", "offset", "q", "rating"],
  );
});

test("the stored URL is derived from the pin, never copied from the response", () => {
  const evil = FIXTURE.data.find((item) => item.id === "giphyEvilUrl");
  const asset = normalizeGiphyItem(evil);

  assert.notEqual(asset, null);
  assert.equal(asset.full.url, "https://media.giphy.com/media/giphyEvilUrl/200h.gif");
  assert.ok(isPinnedGifUrl("giphy", "giphyEvilUrl", asset.full.url));
  // The attacker-controlled preview host fails the allowlist, so the preview
  // falls back to the pinned URL rather than pointing a client at evil.example.
  assert.equal(asset.preview.url, asset.full.url);
});

test("an id that could escape its URL path segment is dropped entirely", () => {
  const bad = FIXTURE.data.find((item) => item.id === "giphy/BadId");
  assert.equal(normalizeGiphyItem(bad), null);
});

test("titles are trimmed of the GIF suffix, bounded, and never empty", () => {
  const one = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyGoodOne"),
  );
  const two = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyGoodTwo"),
  );
  const none = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyNoTitle"),
  );

  assert.equal(one.title, "excited cat");
  assert.equal(two.title, "wesoly pies");
  assert.equal(none.title, "GIF");
});

test("ratings normalize, and anything unreadable becomes unrated rather than g", () => {
  const rated = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyRatedPg"),
  );
  const unrated = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyUnrated"),
  );
  const upper = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyGoodTwo"),
  );

  assert.equal(rated.rating, "pg");
  assert.equal(unrated.rating, "unrated");
  assert.equal(upper.rating, GIF_RATING);
});

test("dimensions come from the fixed-height rendition the pinned URL serves", () => {
  const asset = normalizeGiphyItem(
    FIXTURE.data.find((item) => item.id === "giphyGoodOne"),
  );
  assert.equal(asset.full.height, 200);
  assert.equal(asset.full.width, 356);
});

test("a page normalizes, drops what it must, and pages by offset", async () => {
  const giphy = provider(recordingFetch(FIXTURE));
  const page = await giphy.search({ query: "cat", locale: "en", limit: 10 });

  // Seven raw items in, six out: the malformed id is dropped here. The two
  // non-`g` items survive the adapter and are dropped by catalog.js, which is
  // where the re-filter lives.
  assert.equal(page.items.length, 6);
  assert.equal(page.nextCursor, "7");

  const second = await giphy.search({ query: "cat", cursor: "7", limit: 10 });
  assert.equal(second.nextCursor, "14");
});

test("the last page reports no cursor", async () => {
  const exhausted = {
    ...FIXTURE,
    pagination: { total_count: 7, count: 7, offset: 0 },
  };
  const giphy = provider(recordingFetch(exhausted));
  const page = await giphy.search({ query: "cat", limit: 10 });
  assert.equal(page.nextCursor, null);
});

test("a missing key fails as provider_not_configured, never as a generic error", async () => {
  const giphy = createGiphyProvider({
    apiKey: "   ",
    fetchImpl: recordingFetch(FIXTURE),
  });
  assert.equal(giphy.isConfigured, false);
  await assert.rejects(
    () => giphy.search({ query: "cat" }),
    (error) => {
      assert.ok(error instanceof GifProviderError);
      assert.equal(error.code, "provider_not_configured");
      return true;
    },
  );
});

test("401 and 403 map to provider_unauthorized so the breaker can trip on them", async () => {
  for (const status of [401, 403]) {
    const giphy = provider(recordingFetch({}, { ok: false, status }));
    await assert.rejects(
      () => giphy.trending({}),
      (error) => {
        assert.equal(error.code, "provider_unauthorized");
        assert.equal(error.status, status);
        return true;
      },
    );
  }
});

test("429 maps to provider_rate_limited and other statuses to provider_error", async () => {
  const limited = provider(recordingFetch({}, { ok: false, status: 429 }));
  await assert.rejects(
    () => limited.trending({}),
    (error) => error.code === "provider_rate_limited",
  );

  const broken = provider(recordingFetch({}, { ok: false, status: 503 }));
  await assert.rejects(
    () => broken.trending({}),
    (error) => error.code === "provider_error",
  );
});

test("an aborted request maps to provider_timeout", async () => {
  const giphy = provider(async () => {
    const error = new Error("aborted");
    error.name = "AbortError";
    throw error;
  });
  await assert.rejects(
    () => giphy.trending({}),
    (error) => error.code === "provider_timeout",
  );
});

test("headers and a delayed response body share one request deadline", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let deliverHeaders;
  let deliverBody;
  let signal;
  let bodyStarted;
  const readingBody = new Promise((resolve) => { bodyStarted = resolve; });
  const body = new Promise((resolve) => { deliverBody = resolve; });
  const giphy = provider((_url, options) => {
    signal = options.signal;
    return new Promise((resolve) => { deliverHeaders = resolve; });
  });
  const pending = giphy.trending({});
  // Spending two seconds on headers must leave only one second for the body.
  t.mock.timers.tick(2000);
  deliverHeaders({ ok: true, status: 200, json: () => {
    bodyStarted();
    return body;
  } });
  await readingBody;
  t.mock.timers.tick(REQUEST_TIMEOUT_MS - 2000 - 1);
  assert.equal(signal.aborted, false);
  t.mock.timers.tick(1);
  // Complete even an abort-ignoring body double, so a broken implementation
  // fails an assertion rather than hanging this regression indefinitely.
  deliverBody(FIXTURE);
  await assert.rejects(pending, (error) => error.code === "provider_timeout");
  assert.equal(signal.aborted, true);
});

test("an abort while reading the body is a timeout, not unreadable JSON", async () => {
  const giphy = provider(async () => ({
    ok: true,
    status: 200,
    json: async () => { throw Object.assign(new Error("aborted body"), { name: "AbortError" }); },
  }));
  await assert.rejects(giphy.search({ query: "cat" }),
    (error) => error.code === "provider_timeout");
});

test("completed body reads and JSON failures clear their deadline timers", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const signals = [];
  for (const valid of [true, false]) {
    const giphy = provider(async (_url, options) => {
      signals.push(options.signal);
      return { ok: true, status: 200, json: async () => {
        if (!valid) throw new SyntaxError("invalid JSON");
        return FIXTURE;
      } };
    });
    if (valid) assert.equal((await giphy.trending({})).items.length, 6);
    else await assert.rejects(giphy.trending({}), (error) => error.code === "provider_error");
  }
  t.mock.timers.tick(REQUEST_TIMEOUT_MS);
  assert.ok(signals.every((signal) => signal.aborted === false));
});

test("attribution is declared and marked required", () => {
  const giphy = provider(recordingFetch(FIXTURE));
  assert.equal(giphy.attribution.text, "Powered by GIPHY");
  assert.equal(giphy.attribution.required, true);
});

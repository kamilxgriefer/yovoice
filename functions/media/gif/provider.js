// The provider seam.
//
// Exactly one module in this project knows that a GIF provider exists as a
// remote HTTP API: the adapter selected here. Everything above it — the
// callables, the cache, the rate limiter, the moderation path, the client —
// speaks `GifAsset`, which is defined in normalize.js and is the same shape
// whichever adapter is loaded.
//
// That is what makes "swap the provider" a one-file change plus one config
// value plus one disjunct in the firestore.rules URL pin, rather than a
// rewrite. It is also what makes the whole feature testable with no API key at
// all: `fake_provider.js` implements this interface and is what the emulator
// and every functions test run against.

"use strict";

const { GIF_PROVIDERS, isServingProvider } = require("./gif_ref");

/// Every adapter must expose exactly this. Checked at construction rather than
/// trusted, because the failure mode of a half-implemented adapter is a
/// `TypeError` inside a callable — a 500 to a user — instead of a refused
/// deploy.
const PROVIDER_INTERFACE = Object.freeze([
  "search",
  "trending",
  "resolve",
]);

class GifProviderError extends Error {
  constructor(message, { status = 0, code = "provider_error" } = {}) {
    super(message);
    this.name = "GifProviderError";
    this.status = status;
    this.code = code;
  }
}

function assertProviderShape(provider) {
  if (!provider || typeof provider !== "object") {
    throw new TypeError("A GIF provider adapter is required.");
  }
  if (!isServingProvider(provider.id)) {
    throw new TypeError(`Unknown GIF provider id: ${String(provider.id)}.`);
  }
  for (const method of PROVIDER_INTERFACE) {
    if (typeof provider[method] !== "function") {
      throw new TypeError(
        `GIF provider ${provider.id} is missing ${method}().`,
      );
    }
  }
  const attribution = provider.attribution;
  if (
    !attribution ||
    typeof attribution.text !== "string" ||
    attribution.text.length === 0 ||
    typeof attribution.required !== "boolean"
  ) {
    throw new TypeError(
      `GIF provider ${provider.id} must declare its attribution.`,
    );
  }
  return provider;
}

/// True only where a fixture catalog is legitimate.
///
/// The emulator sets FIRESTORE_EMULATOR_HOST / FUNCTIONS_EMULATOR; the test
/// runner sets NODE_ENV=test. Neither is set in a deployed function, so the
/// fake provider cannot reach a user even if somebody sets GIF_PROVIDER=fake
/// in production — and `createGifProvider` throws there rather than silently
/// falling back to "disabled", so the misconfiguration is loud.
function isFixtureEnvironment(env = process.env) {
  return Boolean(
    env.FUNCTIONS_EMULATOR === "true" ||
      env.FIRESTORE_EMULATOR_HOST ||
      env.NODE_ENV === "test",
  );
}

/// Build the configured adapter, or `null` when nothing is configured.
///
/// `null` is a normal, expected answer — it is what production returns today —
/// and it is why `getGifCatalog` can bind no secret and still tell the truth.
function createGifProvider({
  provider = process.env.GIF_PROVIDER,
  apiKey = "",
  fetchImpl = undefined,
  now = () => Date.now(),
  env = process.env,
} = {}) {
  const selected = typeof provider === "string" ? provider.trim() : "";
  if (selected === "" || selected === GIF_PROVIDERS.none) return null;

  if (selected === GIF_PROVIDERS.fake) {
    if (!isFixtureEnvironment(env)) {
      // Deliberately a throw, following strictBooleanEnvironment() in
      // functions/index.js: a misconfigured environment fails the deployment
      // instead of quietly serving fixtures to real people.
      throw new Error(
        "GIF_PROVIDER=fake is only available in the emulator or under " +
          "NODE_ENV=test. Production must use giphy or none.",
      );
    }
    const { createFakeGifProvider } = require("./fake_provider");
    return assertProviderShape(createFakeGifProvider({ now }));
  }

  if (selected === GIF_PROVIDERS.giphy) {
    const { createGiphyProvider } = require("./giphy_provider");
    return assertProviderShape(createGiphyProvider({ apiKey, fetchImpl, now }));
  }

  throw new Error(`Unsupported GIF_PROVIDER: ${selected}.`);
}

module.exports = {
  GifProviderError,
  PROVIDER_INTERFACE,
  assertProviderShape,
  createGifProvider,
  isFixtureEnvironment,
};

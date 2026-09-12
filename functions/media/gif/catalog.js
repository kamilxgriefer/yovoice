// The three GIF callables, and the only place the API key is ever read.
//
//   getGifCatalog()   -> availability, attribution, categories, page size.
//                        BINDS NO SECRET, so it registers and answers honestly
//                        even when nothing is configured — which is what lets
//                        the client render a disabled, labelled GIF tab
//                        instead of a broken or faked one.
//   searchGifs(...)   -> a page of `GifAsset`. A blank query means trending,
//                        so trending is not a second function and not a second
//                        cold start.
//   reportGifAsset()  -> a `reports` document in the queue that already exists.
//
// Registration follows the Stripe precedent in functions/index.js exactly: the
// secret-bound exports register only when GIF_PROVIDER names a real provider,
// because defineSecret requires the secret to exist at deploy time and deploy
// discovery has to keep working before the key does.
//
// IMAGE BYTES NEVER PASS THROUGH HERE. We proxy metadata and search; the
// device fetches the image from the provider's CDN directly, because GIPHY's
// terms require hotlinking and forbid rehosting. See docs/SECURITY.md for what
// that means for the viewer's IP address.

"use strict";

const { logger } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const {
  activeProfile,
  fail,
  normalizeText,
  requireActor,
  requireExactInput,
  requireRequestId,
} = require("../../integrity/guards");
const { GIF_PROVIDERS, GIF_RATING, isServingProvider, isValidGifId } = require("./gif_ref");
const { createGifCache } = require("./cache");
const { createGifModeration, isValidReason } = require("./moderation");
const { createGifProvider, GifProviderError } = require("./provider");
const { createGifRateLimiter } = require("./rate_limit");
const { isDeniedQuery } = require("./denylist");
const {
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  normalizeCursor,
  normalizeLimit,
  normalizeLocale,
  normalizeQuery,
  queryCacheKey,
  queryFingerprint,
} = require("./normalize");

const REGION = "europe-west1";

/// Bound ONLY to the two callables that talk to the provider. `getGifCatalog`
/// deliberately does not bind it, so availability can be reported before the
/// secret exists.
const GIPHY_API_KEY = defineSecret("GIPHY_API_KEY");

/// Server-owned kill switch, same shape as `publicStats/live` and
/// `publicShowcase/live`: set `appConfig/gif.enabled = false` and the feature
/// is disabled and labelled on the next catalog fetch, with no deploy.
const CONFIG_DOCUMENT = Object.freeze({ collection: "appConfig", id: "gif" });
const CONFIG_TTL_MS = 30 * 1000;

/// Suggested searches, as KEYS rather than words. The client owns the EN/PL
/// copy (the app is bilingual and the server has no locale authority), and the
/// key is also the query it runs. Keeping them here means the set can change
/// without an app release.
const CATEGORY_KEYS = Object.freeze([
  "trending",
  "reactions",
  "love",
  "happy",
  "sad",
  "celebrate",
  "thankYou",
  "yes",
  "no",
  "hello",
  "goodbye",
  "animals",
]);

/// Once the provider says 401/403/429, stop asking for the rest of the hour.
/// Per instance, in memory: a shared breaker would need a document write on
/// every provider error, and the budget document already bounds the aggregate.
const BREAKER_WINDOW_MS = 60 * 60 * 1000;

function createBreaker({ now = () => Date.now() } = {}) {
  let openUntilMs = 0;
  let lastCode = null;
  return {
    get open() {
      return now() < openUntilMs;
    },
    get code() {
      return now() < openUntilMs ? lastCode : null;
    },
    trip(code) {
      openUntilMs = now() + BREAKER_WINDOW_MS;
      lastCode = code;
    },
    reset() {
      openUntilMs = 0;
      lastCode = null;
    },
  };
}

function createGifRuntime({
  db = null,
  provider = undefined,
  providerName = process.env.GIF_PROVIDER,
  apiKey = undefined,
  now = () => Date.now(),
  log = logger,
  hourlyProviderBudget = undefined,
} = {}) {
  const { getFirestore } = require("firebase-admin/firestore");
  const database = db ?? getFirestore();
  const cache = createGifCache({ db: database, now });
  const limiter = createGifRateLimiter({
    db: database,
    now,
    ...(hourlyProviderBudget === undefined ? {} : { hourlyProviderBudget }),
  });
  const moderation = createGifModeration({ db: database, now, cache });
  const breaker = createBreaker({ now });
  let configCache = { value: null, readAtMs: -Infinity };

  /// The configured provider, built lazily.
  ///
  /// Lazy because `apiKey` is a `defineSecret` value that is only readable
  /// inside a request, and eager construction would either read it at module
  /// load (it is not there yet) or force the secret onto `getGifCatalog`.
  function resolveProvider({ metadataOnly = false } = {}) {
    if (provider !== undefined) return provider;
    // getGifCatalog is a separate, secret-free Cloud Run function. Reading
    // GIPHY_API_KEY there always yields an unbound/missing secret, even when
    // searchGifs is correctly deployed. The catalog can attest configuration
    // and the kill switch only; search verifies the bound key and provider.
    const key = metadataOnly ? "" : (typeof apiKey === "function" ? apiKey() : apiKey);
    const selected = createGifProvider({ provider: providerName, apiKey: key ?? "" });
    return metadataOnly && selected
      ? { id: selected.id, attribution: selected.attribution }
      : selected;
  }

  async function readConfig() {
    const nowMs = now();
    if (nowMs - configCache.readAtMs < CONFIG_TTL_MS) return configCache.value;
    let value = null;
    try {
      const snapshot = await database
        .collection(CONFIG_DOCUMENT.collection)
        .doc(CONFIG_DOCUMENT.id)
        .get();
      value = snapshot.exists ? (snapshot.data() ?? {}) : {};
    } catch (_) {
      // An unreadable config document must not take the feature down; the
      // provider configuration below is the authority on availability.
      value = configCache.value ?? {};
    }
    configCache = { value, readAtMs: nowMs };
    return value;
  }

  return {
    breaker,
    cache,
    db: database,
    limiter,
    log,
    moderation,
    now,
    readConfig,
    resolveProvider,
  };
}

/// Shared availability policy. Metadata-only catalog requests report the
/// rollout/config state; provider requests additionally verify their bound
/// key and the breaker in that function instance.
async function availability(runtime, { metadataOnly = false } = {}) {
  const config = (await runtime.readConfig()) ?? {};
  if (config.enabled === false) {
    return { available: false, reason: "disabled", provider: null };
  }
  let provider = null;
  try {
    provider = runtime.resolveProvider({ metadataOnly });
  } catch (error) {
    runtime.log.error("gif.provider_misconfigured", {
      message: error?.message ?? "unknown",
    });
    return { available: false, reason: "not_configured", provider: null };
  }
  if (provider === null) {
    return { available: false, reason: "not_configured", provider: null };
  }
  if (provider.isConfigured === false) {
    return { available: false, reason: "provider_not_configured", provider };
  }
  if (runtime.breaker.open) {
    return { available: false, reason: "provider_unavailable", provider };
  }
  return { available: true, reason: null, provider };
}

function catalogResponse(state) {
  return {
    available: state.available,
    reason: state.reason,
    provider: state.provider?.id ?? GIF_PROVIDERS.none,
    attribution: state.provider?.attribution ?? null,
    categories: [...CATEGORY_KEYS],
    pageSize: DEFAULT_PAGE_SIZE,
    maxPageSize: MAX_PAGE_SIZE,
    ratingLabel: GIF_RATING,
    // Named so the client can render "Only GIFs rated G" honestly rather than
    // asserting a safety level it cannot verify.
    minimumQueryLength: 2,
  };
}

/// A `GifAsset` as it goes over the wire. Explicit rather than a spread, so a
/// field added to the stored record can never leak to a client by accident.
function wireAsset(asset) {
  return {
    provider: asset.provider,
    id: asset.id,
    title: asset.title,
    rating: asset.rating,
    previewUrl: asset.preview.url,
    url: asset.full.url,
    width: asset.full.width,
    height: asset.full.height,
  };
}

function createGifFunctions({
  runtime = null,
  registrars = { onCall },
  enforceAppCheck = false,
  log = logger,
  providerName = process.env.GIF_PROVIDER,
} = {}) {
  if (typeof registrars?.onCall !== "function") {
    throw new TypeError("Missing Cloud Functions registrar: onCall.");
  }
  const selected = typeof providerName === "string" ? providerName.trim() : "";
  const providerConfigured =
    selected !== "" && selected !== GIF_PROVIDERS.none && isServingProvider(selected);

  const baseOptions = {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 40,
    enforceAppCheck: enforceAppCheck === true,
    consumeAppCheckToken: false,
  };

  const resolved =
    runtime ??
    createGifRuntime({
      // The secret is read inside the request, never at module load.
      apiKey: () => GIPHY_API_KEY.value(),
      providerName,
    });

  const exportsMap = {};

  // ---------------------------------------------------------------------
  // getGifCatalog — no secret, always registered.
  // ---------------------------------------------------------------------
  exportsMap.getGifCatalog = registrars.onCall(baseOptions, async (request) => {
    requireActor(request, { verified: false });
    requireExactInput(request.data ?? {}, [], []);
    const state = await availability(resolved, { metadataOnly: true });
    return catalogResponse(state);
  });

  if (!providerConfigured) {
    // No provider: the two secret-bound callables are not registered at all.
    // A client calling them gets NOT_FOUND, which it never does, because
    // getGifCatalog already told it the feature is unavailable.
    return exportsMap;
  }

  const securedOptions = { ...baseOptions, secrets: [GIPHY_API_KEY] };

  // ---------------------------------------------------------------------
  // searchGifs — a blank query means trending.
  // ---------------------------------------------------------------------
  exportsMap.searchGifs = registrars.onCall(
    securedOptions,
    async (request) => {
      const auth = requireActor(request, { verified: false });
      const data = requireExactInput(
        request.data ?? {},
        ["query", "locale", "cursor", "limit"],
        [],
      );

      const state = await availability(resolved);
      if (!state.available) {
        throw new HttpsError(
          "failed-precondition",
          "GIFs are not available right now.",
          { code: state.reason ?? "not_configured" },
        );
      }

      // Charged BEFORE the cache is consulted: the limit bounds how much work
      // one account can ask this service to do, and a cache hit still costs a
      // read and an instance. Charging only on a miss would also let a caller
      // discover which queries are cached by measuring which ones are free.
      const budget = await resolved.limiter.consume(auth.uid);
      if (!budget.allowed) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many GIF searches. Please slow down.",
          { retryAfterSeconds: budget.retryAfterSeconds },
        );
      }
      activeProfile(await resolved.db.doc(`users/${auth.uid}`).get(), "Your");

      const query = normalizeQuery(data.query);
      const locale = normalizeLocale(data.locale);
      const cursor = normalizeCursor(data.cursor);
      const limit = normalizeLimit(data.limit);
      const kind = query.length === 0 ? "trending" : "search";
      const fingerprint = queryFingerprint(query);

      // Layer 3 of four. Neutral copy, no explanation, no error: telling
      // somebody which term tripped the filter is a map of the filter.
      if (kind === "search" && isDeniedQuery(query)) {
        resolved.log.info("gif.search", {
          ...fingerprint,
          kind,
          deniedTerm: true,
          cacheHit: false,
          resultCount: 0,
        });
        return {
          items: [],
          nextCursor: null,
          degraded: false,
          cacheHit: false,
          attribution: state.provider.attribution,
        };
      }

      const key = queryCacheKey({
        provider: state.provider.id,
        kind,
        query,
        locale,
        cursor,
        limit,
      });
      const suppressed = await resolved.cache.suppressedAssetIds();
      const isSuppressed = (item) =>
        suppressed.has(`${item.provider}_${item.id}`);

      const cached = await resolved.cache.readQuery(key);
      if (cached) {
        const items = cached.items.filter((item) => !isSuppressed(item));
        resolved.log.info("gif.search", {
          ...fingerprint,
          kind,
          cacheHit: true,
          cacheSource: cached.source,
          resultCount: items.length,
          degraded: false,
        });
        return {
          items,
          nextCursor: cached.nextCursor,
          degraded: false,
          cacheHit: true,
          attribution: state.provider.attribution,
        };
      }

      const claimed = await resolved.limiter.claimProviderCall();
      if (!claimed) {
        // The hour's budget is spent. Serve the freshest trending page we hold
        // and SAY SO, rather than erroring: a degraded picker is a working
        // picture, a 500 is not.
        const fallback = await resolved.cache.readQuery(
          queryCacheKey({
            provider: state.provider.id,
            kind: "trending",
            query: "",
            locale,
            cursor: null,
            limit: DEFAULT_PAGE_SIZE,
          }),
        );
        const items = (fallback?.items ?? []).filter(
          (item) => !isSuppressed(item),
        );
        resolved.log.warn("gif.search", {
          ...fingerprint,
          kind,
          cacheHit: false,
          budgetExhausted: true,
          degraded: true,
          resultCount: items.length,
        });
        return {
          items,
          nextCursor: null,
          degraded: true,
          cacheHit: false,
          attribution: state.provider.attribution,
        };
      }

      const startedAtMs = resolved.now();
      let page;
      try {
        page =
          kind === "trending"
            ? await state.provider.trending({ locale, limit, cursor })
            : await state.provider.search({ query, locale, limit, cursor });
      } catch (error) {
        const code =
          error instanceof GifProviderError ? error.code : "provider_error";
        const status = error instanceof GifProviderError ? error.status : 0;
        resolved.log.error("gif.provider_error", { code, status });
        if (
          code === "provider_unauthorized" ||
          code === "provider_rate_limited"
        ) {
          // A revoked key or a provider-side 429 must not be retried for the
          // rest of the hour; alerting on this log line is how the maintainer
          // finds out the key died instead of watching the feature rot.
          resolved.breaker.trip(code);
        }
        const stale = await resolved.cache.readQuery(key);
        if (stale) {
          return {
            items: stale.items.filter((item) => !isSuppressed(item)),
            nextCursor: stale.nextCursor,
            degraded: true,
            cacheHit: true,
            attribution: state.provider.attribution,
          };
        }
        throw new HttpsError("unavailable", "GIFs are unavailable right now.", {
          code,
        });
      }

      // Layer 2 of four: an item whose normalized rating is not exactly `g` is
      // dropped before it leaves this process, whatever the provider said.
      const rated = page.items.filter((item) => item.rating === GIF_RATING);

      // Written BEFORE the response is built. Every result is backed by the
      // durable record that message callables resolve in their transaction,
      // without holding a provider key or making another provider request.
      const { written, blocked } = await resolved.cache.writeAssets(rated);
      const items = rated.filter((item) => {
        const documentId = `${item.provider}_${item.id}`;
        return (
          written.has(documentId) &&
          !blocked.has(documentId) &&
          !isSuppressed(item)
        );
      });

      await resolved.cache.writeQuery(key, {
        kind,
        items: items.map(wireAsset),
        nextCursor: page.nextCursor,
      });

      resolved.log.info("gif.search", {
        ...fingerprint,
        kind,
        cacheHit: false,
        providerLatencyMs: resolved.now() - startedAtMs,
        resultCount: items.length,
        filteredByRating: page.items.length - rated.length,
        degraded: false,
      });

      return {
        items: items.map(wireAsset),
        nextCursor: page.nextCursor,
        degraded: false,
        cacheHit: false,
        attribution: state.provider.attribution,
      };
    },
  );

  // ---------------------------------------------------------------------
  // reportGifAsset — into the queue that already exists.
  // ---------------------------------------------------------------------
  exportsMap.reportGifAsset = registrars.onCall(
    securedOptions,
    async (request) => {
      // Reporting stays available to an authenticated but not-yet-verified
      // account, matching createReelReport and the `reports` create rule: a
      // safety action is never gated on email verification.
      const auth = requireActor(request, { verified: false });
      const data = requireExactInput(
        request.data ?? {},
        ["provider", "gifId", "reason", "note", "contextPath", "requestId"],
        ["provider", "gifId", "reason", "requestId"],
      );
      requireRequestId(data.requestId);
      const provider = typeof data.provider === "string" ? data.provider : "";
      if (!isServingProvider(provider)) {
        fail("invalid-argument", "provider is invalid.");
      }
      const gifId = data.gifId;
      if (!isValidGifId(gifId)) fail("invalid-argument", "gifId is invalid.");
      if (!isValidReason(data.reason)) {
        fail("invalid-argument", "reason is invalid.");
      }
      const note =
        data.note === null || data.note === undefined
          ? ""
          : normalizeText(data.note, 300, "note", { allowEmpty: true });

      await resolved.limiter.consumeReport(auth.uid);
      activeProfile(await resolved.db.doc(`users/${auth.uid}`).get(), "Your");

      const outcome = await resolved.moderation.reportAsset({
        reporterId: auth.uid,
        provider,
        gifId,
        reason: data.reason,
        note,
        contextPath: data.contextPath ?? null,
      });

      if (outcome?.error === "unknown_asset") {
        fail("not-found", "That GIF is no longer available.");
      }
      if (outcome?.error) {
        fail("invalid-argument", "That GIF cannot be reported.");
      }
      resolved.log.info("gif.report", {
        created: outcome.created === true,
        suppressed: outcome.suppressed === true,
      });
      return {
        reportId: outcome.reportId,
        created: outcome.created === true,
      };
    },
  );

  return exportsMap;
}

module.exports = {
  BREAKER_WINDOW_MS,
  CATEGORY_KEYS,
  CONFIG_DOCUMENT,
  GIPHY_API_KEY,
  availability,
  catalogResponse,
  createBreaker,
  createGifFunctions,
  createGifRuntime,
  wireAsset,
};

// GIPHY adapter — the ONLY module in this project that holds the API key or
// knows GIPHY's HTTP shape.
//
// Why GIPHY (ADR-172): its `g` rating is an editorially assigned, per-asset
// value with a decade of operational history and a staffed moderation team
// behind it, its non-English search relevance is the better-tested surface for
// a bilingual EN/PL product, and the proxy-in-front-of-GIPHY architecture has
// a strict-privacy peer running it in production. Its terms REQUIRE hotlinking
// and forbid rehosting, which is why this adapter returns CDN URLs and never
// bytes.
//
// `fetchImpl` is injectable and defaults to Node 22's global fetch — so this
// module adds no npm dependency, and every parsing, normalization, rating and
// error-mapping path is tested against recorded fixture JSON with no key.

"use strict";

const { GIF_PROVIDERS, GIF_RATING } = require("./gif_ref");
const { GifProviderError } = require("./provider");
const {
  DEFAULT_PAGE_SIZE,
  buildGifAsset,
  normalizeLimit,
} = require("./normalize");

const API_ROOT = "https://api.giphy.com/v1/gifs";
/// A search a person is waiting on. Longer than this and the picker should
/// show its retry state rather than hold a spinner; the callable's own
/// timeout is longer still. This budget covers headers AND response body.
const REQUEST_TIMEOUT_MS = 3000;

/// GIPHY's attribution requirement is contractual, not optional. The panel
/// footer renders this string; there is no code path that hides it while
/// results are on screen.
const GIPHY_ATTRIBUTION = Object.freeze({
  text: "Powered by GIPHY",
  required: true,
});

function readRendition(images, ...names) {
  if (!images || typeof images !== "object") return null;
  for (const name of names) {
    const rendition = images[name];
    if (rendition && typeof rendition === "object" && rendition.url) {
      return rendition;
    }
  }
  return null;
}

/// One raw GIPHY item -> one canonical `GifAsset`, or `null`.
///
/// Dimensions come from the FIXED-HEIGHT rendition because that is the
/// rendition the pinned CDN URL (`/200h.gif`) actually serves; taking them
/// from `original` would give the bubble a wrong aspect ratio and reintroduce
/// exactly the reflow the fixed-height choice exists to prevent.
function normalizeGiphyItem(item) {
  if (!item || typeof item !== "object") return null;
  const images = item.images;
  const fixedHeight = readRendition(images, "fixed_height", "original");
  const previewRendition = readRendition(
    images,
    "fixed_height_small",
    "fixed_height_downsampled",
    "fixed_height",
  );
  return buildGifAsset({
    provider: GIF_PROVIDERS.giphy,
    id: item.id,
    title: item.title,
    rating: item.rating,
    previewUrl: previewRendition?.url ?? null,
    width: fixedHeight?.width ?? null,
    height: fixedHeight?.height ?? null,
    sourceUrl: null,
  });
}

/// GIPHY paginates by offset. The cursor is the offset as a decimal string,
/// which satisfies normalize.js's cursor grammar and stays opaque to the
/// client — nothing above this module may assume what a cursor means.
function parseOffsetCursor(cursor) {
  if (typeof cursor !== "string" || cursor.length === 0) return 0;
  const parsed = Number.parseInt(cursor, 10);
  if (!Number.isSafeInteger(parsed) || parsed < 0 || parsed > 4999) return 0;
  return parsed;
}

function nextOffsetCursor({ offset, count, total }) {
  const consumed = offset + count;
  if (count === 0) return null;
  if (Number.isSafeInteger(total) && consumed >= total) return null;
  // GIPHY refuses offsets past 4999 on the search endpoint; stopping here is
  // an honest end-of-results rather than a 4xx the user would see as an error.
  if (consumed > 4999) return null;
  return String(consumed);
}

function createGiphyProvider({
  apiKey,
  fetchImpl = undefined,
  now = () => Date.now(),
} = {}) {
  const key = typeof apiKey === "string" ? apiKey.trim() : "";
  const doFetch = fetchImpl ?? globalThis.fetch;
  if (typeof doFetch !== "function") {
    throw new TypeError(
      "No fetch implementation available for the GIPHY adapter.",
    );
  }

  function assertConfigured() {
    if (key.length === 0) {
      // Never a generic failure: catalog.js maps this onto
      // `provider_not_configured`, which is what flips the client to its
      // disabled+labelled state instead of showing an error toast.
      throw new GifProviderError("GIPHY_API_KEY is not configured.", {
        code: "provider_not_configured",
      });
    }
  }

  async function request(path, params) {
    assertConfigured();
    const url = new URL(`${API_ROOT}${path}`);
    url.searchParams.set("api_key", key);
    // RATING IS SET HERE AND NOWHERE ELSE. It is not a parameter of any
    // callable, so no client — modified or not — can ask for anything looser.
    url.searchParams.set("rating", GIF_RATING);
    for (const [name, value] of Object.entries(params)) {
      if (value === null || value === undefined || value === "") continue;
      url.searchParams.set(name, String(value));
    }

    const controller = new AbortController();
    let timer;
    // One deadline is shared by both phases. Racing it as well as aborting
    // the fetch keeps even an abort-ignoring body reader from holding open the
    // callable; clearing at headers would leave response.json() unbounded.
    const deadline = new Promise((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new GifProviderError("GIPHY timed out.", { code: "provider_timeout" }));
      }, REQUEST_TIMEOUT_MS);
    });
    try {
      let response;
      try {
        response = await Promise.race([
          doFetch(url.toString(), {
            method: "GET",
            signal: controller.signal,
            headers: { accept: "application/json" },
          }),
          deadline,
        ]);
      } catch (error) {
        const aborted = controller.signal.aborted || error?.name === "AbortError";
        throw new GifProviderError(
          aborted ? "GIPHY timed out." : "GIPHY is unreachable.",
          { code: aborted ? "provider_timeout" : "provider_unreachable" },
        );
      }

      if (!response.ok) {
        const status = Number.isSafeInteger(response.status)
          ? response.status
          : 0;
        // 401/403 means the key was revoked or rejected. catalog.js opens the
        // circuit breaker on it and logs at error, because the alternative is a
        // feature that degrades silently for everyone.
        const code =
          status === 401 || status === 403
            ? "provider_unauthorized"
            : status === 429
              ? "provider_rate_limited"
              : "provider_error";
        throw new GifProviderError(`GIPHY responded ${status}.`, {
          status,
          code,
        });
      }

      try {
        return await Promise.race([response.json(), deadline]);
      } catch (error) {
        const aborted = controller.signal.aborted || error?.name === "AbortError";
        throw new GifProviderError(
          aborted ? "GIPHY timed out." : "GIPHY returned unreadable JSON.",
          {
            status: aborted ? 0 : response.status ?? 0,
            code: aborted ? "provider_timeout" : "provider_error",
          },
        );
      }
    } finally {
      clearTimeout(timer);
    }
  }

  function normalizePage(payload, offset) {
    const rawItems = Array.isArray(payload?.data) ? payload.data : [];
    const items = [];
    for (const raw of rawItems) {
      const asset = normalizeGiphyItem(raw);
      if (asset !== null) items.push(asset);
    }
    const total = payload?.pagination?.total_count;
    return {
      items,
      nextCursor: nextOffsetCursor({
        offset,
        count: rawItems.length,
        total: Number.isSafeInteger(total) ? total : null,
      }),
      fetchedAt: now(),
    };
  }

  async function search({ query, locale, limit, cursor } = {}) {
    const offset = parseOffsetCursor(cursor);
    const payload = await request("/search", {
      q: query,
      lang: locale,
      limit: normalizeLimit(limit, { fallback: DEFAULT_PAGE_SIZE }),
      offset,
      bundle: "messaging_non_clips",
    });
    return normalizePage(payload, offset);
  }

  async function trending({ locale, limit, cursor } = {}) {
    const offset = parseOffsetCursor(cursor);
    const payload = await request("/trending", {
      lang: locale,
      limit: normalizeLimit(limit, { fallback: DEFAULT_PAGE_SIZE }),
      offset,
      bundle: "messaging_non_clips",
    });
    return normalizePage(payload, offset);
  }

  async function resolve({ id } = {}) {
    const payload = await request(`/${encodeURIComponent(id)}`, {});
    const asset = normalizeGiphyItem(payload?.data);
    return { items: asset === null ? [] : [asset], nextCursor: null };
  }

  return Object.freeze({
    id: GIF_PROVIDERS.giphy,
    attribution: GIPHY_ATTRIBUTION,
    isConfigured: key.length > 0,
    search,
    trending,
    resolve,
  });
}

module.exports = {
  GIPHY_ATTRIBUTION,
  REQUEST_TIMEOUT_MS,
  createGiphyProvider,
  normalizeGiphyItem,
};

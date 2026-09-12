// Pure normalization for the GIF proxy: query text in, cache keys and
// `GifAsset` records out. No Firestore, no network, no clock — everything here
// is a function of its arguments, which is what makes the adapter tests
// meaningful without a key and the cache key reproducible across instances.

"use strict";

const crypto = require("node:crypto");

const {
  GIF_RATING,
  MAX_GIF_TITLE_LENGTH,
  gifCdnUrl,
  isAllowedPreviewUrl,
  isValidGifId,
} = require("./gif_ref");

const MAX_QUERY_LENGTH = 60;
const MAX_CURSOR_LENGTH = 128;
const CURSOR_PATTERN = /^[A-Za-z0-9_-]{1,128}$/u;
const LOCALE_PATTERN = /^[a-z]{2}$/u;
const DEFAULT_LOCALE = "en";
const SUPPORTED_LOCALES = Object.freeze(new Set(["en", "pl"]));

const MIN_PAGE_SIZE = 1;
const MAX_PAGE_SIZE = 30;
const DEFAULT_PAGE_SIZE = 24;

/// Control characters, bidi overrides and the ZWJ/ZWNJ family.
///
/// A provider title lands in a chat bubble, in a report a moderator reads, and
/// — on an old client that does not know `type:"gif"` — in a plain text
/// message. A right-to-left override in that string reverses the rest of the
/// line for every reader, which is a real and cheap spoofing primitive. It is
/// stripped here, once, at the only place titles enter the system.
const UNSAFE_TITLE_CHARACTERS = new RegExp(
  "[\\u0000-\\u001F\\u007F-\\u009F\\u200B-\\u200F\\u2028\\u2029" +
    "\\u202A-\\u202E\\u2066-\\u2069\\uFEFF]",
  "gu",
);

/// Query text as both the cache key and the provider see it.
///
/// Lowercased and whitespace-collapsed so "Kotek", "kotek" and " kotek "
/// are ONE cache entry rather than three, which is most of why a beta key
/// survives real traffic. Returns `""` for anything unusable, and `""` means
/// trending — trending is not a second endpoint.
function normalizeQuery(value) {
  if (typeof value !== "string") return "";
  const collapsed = value.replace(/\s+/gu, " ").trim().toLowerCase();
  if (collapsed.length === 0) return "";
  return collapsed.slice(0, MAX_QUERY_LENGTH);
}

/// Two characters, from the set the app actually ships. A locale is forwarded
/// to the provider for search relevance, so it must not become a free-text
/// channel to a third party.
function normalizeLocale(value) {
  if (typeof value !== "string") return DEFAULT_LOCALE;
  const lowered = value.trim().toLowerCase().slice(0, 2);
  if (!LOCALE_PATTERN.test(lowered)) return DEFAULT_LOCALE;
  return SUPPORTED_LOCALES.has(lowered) ? lowered : DEFAULT_LOCALE;
}

/// Opaque paging token. It goes straight back to the provider, so it is
/// grammar-checked rather than trusted; `null` means "first page".
function normalizeCursor(value) {
  if (typeof value !== "string" || value.length === 0) return null;
  if (value.length > MAX_CURSOR_LENGTH) return null;
  return CURSOR_PATTERN.test(value) ? value : null;
}

function normalizeLimit(value, { fallback = DEFAULT_PAGE_SIZE } = {}) {
  if (!Number.isSafeInteger(value)) return fallback;
  return Math.min(MAX_PAGE_SIZE, Math.max(MIN_PAGE_SIZE, value));
}

/// A provider title, made safe to store and render.
///
/// GIPHY titles routinely end in " GIF" or " GIF by <brand>", which reads as
/// noise once the thing is already labelled a GIF in the UI and in the
/// accessibility label. Trimming it is cosmetic; everything else here is not.
function sanitizeTitle(value, { fallback = "GIF", stripAttribution = true } = {}) {
  if (typeof value !== "string") return fallback;
  const stripped = value
    .replace(UNSAFE_TITLE_CHARACTERS, "")
    .replace(/\s+/gu, " ")
    .trim();
  const trimmed = stripAttribution
    ? stripped.replace(/\s+GIF(\s+by\s+.+)?$/iu, "").trim()
    : stripped;
  const chosen = trimmed.length > 0 ? trimmed : stripped;
  if (chosen.length === 0) return fallback;
  return chosen.length > MAX_GIF_TITLE_LENGTH
    ? chosen.slice(0, MAX_GIF_TITLE_LENGTH).trim()
    : chosen;
}

/// Providers spell ratings differently and occasionally not at all. Anything
/// this cannot read confidently becomes `"unrated"`, which the re-filter in
/// `catalog.js` then drops — an unknown rating is never treated as safe.
function normalizeRating(value) {
  if (typeof value !== "string") return "unrated";
  const lowered = value.trim().toLowerCase();
  if (lowered.length === 0) return "unrated";
  if (lowered === "g") return GIF_RATING;
  if (["pg", "pg-13", "pg13", "r", "nsfw", "y"].includes(lowered)) {
    return lowered;
  }
  return "unrated";
}

function positiveDimension(value, fallback) {
  const parsed = typeof value === "string" ? Number.parseInt(value, 10) : value;
  if (!Number.isFinite(parsed)) return fallback;
  const rounded = Math.round(parsed);
  if (rounded < 1 || rounded > 4096) return fallback;
  return rounded;
}

/// Build the canonical `GifAsset` from a provider's raw item.
///
/// The URL is DERIVED, never copied: `full.url` is always `gifCdnUrl(...)`, so
/// a compromised or merely sloppy provider response cannot introduce a URL
/// firestore.rules would then refuse — or worse, one it would accept while
/// pointing somewhere else. Returns `null` for anything that does not
/// normalize cleanly, and the caller drops it from the page.
function buildGifAsset({
  provider,
  id,
  title,
  rating,
  previewUrl,
  width,
  height,
  sourceUrl,
}) {
  if (!isValidGifId(id)) return null;
  const url = gifCdnUrl(provider, id);
  if (url === null) return null;
  const resolvedHeight = positiveDimension(height, 200);
  const resolvedWidth = positiveDimension(width, resolvedHeight);
  const preview = isAllowedPreviewUrl(provider, previewUrl) ? previewUrl : url;
  return Object.freeze({
    provider,
    id,
    title: sanitizeTitle(title),
    rating: normalizeRating(rating),
    preview: Object.freeze({
      url: preview,
      width: resolvedWidth,
      height: resolvedHeight,
    }),
    full: Object.freeze({
      url,
      width: resolvedWidth,
      height: resolvedHeight,
    }),
    sourceUrl: isAllowedPreviewUrl(provider, sourceUrl) ? sourceUrl : null,
  });
}

/// The shared cache key.
///
/// Every input that can change the answer is in it, and nothing that cannot.
/// It is a digest rather than a readable path for one reason that matters:
/// `gifQueryCache` document ids would otherwise be a public list of what
/// people are searching for, readable by anybody who could ever list that
/// collection. A digest is the same key for everyone and reveals nothing.
function queryCacheKey({
  provider,
  kind,
  query,
  locale,
  rating = GIF_RATING,
  cursor = null,
  limit,
}) {
  return crypto
    .createHash("sha256")
    .update(
      [provider, kind, query, locale, rating, cursor ?? "", String(limit)].join(
        "|",
      ),
    )
    .digest("hex");
}

/// What a log line may contain about a query: a digest prefix and a length.
/// Never the words. A search box is an intimate thing, and a log that keeps
/// the raw text is a per-user search history we promised not to hold.
function queryFingerprint(query) {
  return {
    queryHash: crypto
      .createHash("sha256")
      .update(query)
      .digest("hex")
      .slice(0, 12),
    queryLength: query.length,
  };
}

module.exports = {
  DEFAULT_LOCALE,
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  MAX_QUERY_LENGTH,
  MIN_PAGE_SIZE,
  buildGifAsset,
  normalizeCursor,
  normalizeLimit,
  normalizeLocale,
  normalizeQuery,
  normalizeRating,
  queryCacheKey,
  queryFingerprint,
  sanitizeTitle,
};

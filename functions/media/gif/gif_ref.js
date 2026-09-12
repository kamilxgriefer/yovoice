// The GIF reference model — one shape, shared by every surface.
//
// A "GIF" in YO Voice is never bytes we hold. It is a provider id plus a title
// plus a URL that points at the provider's own CDN, because GIPHY's terms
// REQUIRE hotlinking and forbid rehosting or mirroring their content. That is
// the reason there is no Storage object here and no egress on our bill: it is
// a licensing constraint first and a cost decision second.
//
// This module is deliberately dependency-free (no Firestore handle, no SDK, no
// firebase-functions import) so the URL pin, the id grammar and the document-id
// derivation can be required from a rules test, a smoke script, the messaging
// send path and the callables without dragging a runtime along. The client
// mirror is lib/features/media/data/models/gif_asset.dart; the two must agree
// on the URL template character for character so received messages retain the
// same pinned origin as catalog results.

"use strict";

/// Every provider this project knows how to speak to.
///
/// `none` is a real, first-class value: it is what production runs today and
/// what makes `getGifCatalog` answer `available:false` honestly instead of the
/// feature half-existing.
const GIF_PROVIDERS = Object.freeze({
  none: "none",
  giphy: "giphy",
  fake: "fake",
});

/// Providers that can actually serve results. `fake` is here because the
/// emulator and the test suite genuinely serve from it; `catalog.js` refuses
/// to select it outside those two environments.
const SERVING_PROVIDERS = Object.freeze(new Set([
  GIF_PROVIDERS.giphy,
  GIF_PROVIDERS.fake,
]));

/// The only rating this product ever asks for or accepts. Pinned as a
/// constant rather than a parameter so no call site can widen it.
const GIF_RATING = "g";

/// Provider asset ids. GIPHY ids are `[A-Za-z0-9]` in practice; the extra
/// three characters give a second provider room without reopening this
/// grammar, and every one of them is safe inside a URL path segment and
/// inside a Firestore document id. Critically it excludes `/`, `?`, `#`, `@`,
/// `%`, backslash and every whitespace character, which is what makes
/// `gifCdnUrl` unable to escape its own host.
///
/// The two lookaheads are not decoration. `.` and `..` are legal under the
/// character class but are a path traversal in a URL and are REFUSED BY
/// FIRESTORE as document ids, and `__name__`-shaped ids are reserved. Without
/// them a provider id of `..` would produce
/// `https://media.giphy.com/media/../200h.gif` and a write that fails at the
/// SDK rather than here. Found by test/gif_cache_and_limits.test.js.
const GIF_ID_PATTERN =
  /^(?!\.{1,2}$)(?!__.*__$)[A-Za-z0-9._-]{1,128}$/u;

/// Bound on the stored human label. It is what a bubble falls back to when the
/// CDN 404s, what an old client renders as plain text, and what a moderator
/// reads in a report — so it is small, mandatory and sanitized.
const MAX_GIF_TITLE_LENGTH = 100;

/// The CDN URL template, per provider.
///
/// THIS IS THE SECURITY CRUX OF THE WHOLE FEATURE. Room and club messages
/// carry the URL in the document, and resolveGifAsset reconstructs exactly
/// this string during the server-owned send. The sender's only freedom is
/// the id. Without that pin, `gif.url` would be an arbitrary-remote-image
/// primitive inside a chat: a tracking beacon that harvests the IP of every
/// person who opens the room. If Rules ever allow client message creation,
/// that write boundary must enforce the same exact pin.
///
/// `200h.gif` is GIPHY's fixed-height rendition alias. Fixed height is not an
/// arbitrary choice either — it means the bubble's height is known before a
/// byte is fetched, so a chat list never reflows when the image lands.
const GIF_CDN_TEMPLATES = Object.freeze({
  [GIF_PROVIDERS.giphy]: Object.freeze({
    prefix: "https://media.giphy.com/media/",
    suffix: "/200h.gif",
  }),
  // The fake provider serves no bytes at all. Its URL is syntactically valid
  // and resolvable by nothing, which is exactly right: a fixture must never
  // cause a real network fetch, and `YoGifView` renders its error placeholder.
  [GIF_PROVIDERS.fake]: Object.freeze({
    prefix: "https://fake.invalid/gif/",
    suffix: "/200h.gif",
  }),
});

/// Hosts whose bytes a client may be pointed at for a *preview* thumbnail.
///
/// Previews are not stored in a message and are never pinned by rules, so they
/// get a host allowlist instead. The character class deliberately excludes
/// `?`, `#`, `@` and backslash, so a preview URL cannot smuggle credentials or
/// a second authority past the host check.
const GIF_PREVIEW_HOST_PATTERNS = Object.freeze({
  [GIF_PROVIDERS.giphy]:
    /^https:\/\/(?:media[0-9]*|i)\.giphy\.com\/[A-Za-z0-9/._~%-]{1,300}$/u,
  [GIF_PROVIDERS.fake]: /^https:\/\/fake\.invalid\/[A-Za-z0-9/._~-]{1,300}$/u,
});

function isServingProvider(provider) {
  return SERVING_PROVIDERS.has(provider);
}

function isValidGifId(id) {
  return typeof id === "string" && GIF_ID_PATTERN.test(id);
}

/// The canonical CDN URL for one asset. Returns `null` rather than throwing so
/// a caller normalizing a page of provider results can drop one bad item
/// instead of losing the page.
function gifCdnUrl(provider, id) {
  const template = GIF_CDN_TEMPLATES[provider];
  if (!template || !isValidGifId(id)) return null;
  return `${template.prefix}${id}${template.suffix}`;
}

/// True when `url` is byte-for-byte the URL `gifCdnUrl` would produce.
/// Equality, never a regex: a pattern that "looks right" is how host-confusion
/// bugs get shipped.
function isPinnedGifUrl(provider, id, url) {
  const expected = gifCdnUrl(provider, id);
  return expected !== null && url === expected;
}

function isAllowedPreviewUrl(provider, url) {
  const pattern = GIF_PREVIEW_HOST_PATTERNS[provider];
  return Boolean(pattern) && typeof url === "string" && pattern.test(url);
}

/// `gifAssets` document id. Flat rather than nested so a transactional read costs
/// one path lookup, and prefixed by provider so two providers can never
/// collide on a shared id space.
function gifAssetDocumentId(provider, id) {
  if (!isServingProvider(provider) || !isValidGifId(id)) return null;
  return `${provider}_${id}`;
}

/// `<provider>:<id>` — the report `targetId`, and the only form a moderator
/// ever sees. Distinct from the document id on purpose: `:` cannot appear in a
/// Firestore document id, so the two can never be confused for one another.
function gifTargetId(provider, id) {
  if (!isServingProvider(provider) || !isValidGifId(id)) return null;
  return `${provider}:${id}`;
}

function parseGifTargetId(targetId) {
  if (typeof targetId !== "string") return null;
  const separator = targetId.indexOf(":");
  if (separator <= 0) return null;
  const provider = targetId.slice(0, separator);
  const id = targetId.slice(separator + 1);
  if (!isServingProvider(provider) || !isValidGifId(id)) return null;
  return { provider, id };
}

module.exports = {
  GIF_CDN_TEMPLATES,
  GIF_ID_PATTERN,
  GIF_PREVIEW_HOST_PATTERNS,
  GIF_PROVIDERS,
  GIF_RATING,
  MAX_GIF_TITLE_LENGTH,
  SERVING_PROVIDERS,
  gifAssetDocumentId,
  gifCdnUrl,
  gifTargetId,
  isAllowedPreviewUrl,
  isPinnedGifUrl,
  isServingProvider,
  isValidGifId,
  parseGifTargetId,
};

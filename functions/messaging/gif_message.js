// GIFs share the existing authoritative message writes. Only a provider/id
// crosses the request boundary; titles, dimensions and URLs come from the
// catalog's server-owned asset record inside the publishing transaction.
const { HttpsError } = require("firebase-functions/v2/https");
const { fail, normalizeText, requireExactInput } = require("../integrity/guards");
const {
  GIF_PROVIDERS,
  isPinnedGifUrl,
  isServingProvider,
  isValidGifId,
} = require("../media/gif/gif_ref");
const { sanitizeTitle } = require("../media/gif/normalize");
const { isFixtureEnvironment } = require("../media/gif/provider");

function messageInput(data, maximumTextLength) {
  const hasText = Object.prototype.hasOwnProperty.call(data, "text");
  const hasGif = Object.prototype.hasOwnProperty.call(data, "gif");
  if (hasText === hasGif) {
    fail("invalid-argument", "Provide exactly one of text or gif.");
  }
  if (hasText) return { text: normalizeText(data.text, maximumTextLength, "text") };
  const gif = requireExactInput(data.gif, ["provider", "id"], ["provider", "id"]);
  if (!isServingProvider(gif.provider) || !isValidGifId(gif.id)) {
    fail("invalid-argument", "The GIF reference is invalid.");
  }
  return { gif: { provider: gif.provider, id: gif.id } };
}

function gifMessageFallback(gif) {
  const title = sanitizeTitle(gif?.title, { stripAttribution: false });
  return title === "GIF" ? "GIF" : `GIF: ${title}`;
}

function isCanonicalMessageGif(gif) {
  if (!gif || typeof gif !== "object" || Array.isArray(gif)) return false;
  const keys = Object.keys(gif).sort();
  const expected = ["height", "id", "provider", "title", "url", "width"];
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    isPinnedGifUrl(gif.provider, gif.id, gif.url) &&
    typeof gif.title === "string" &&
    gif.title === sanitizeTitle(gif.title, { stripAttribution: false }) &&
    [gif.width, gif.height].every((value) =>
      Number.isSafeInteger(value) && value >= 1 && value <= 4096);
}

/// The providers a send path accepts, as a set.
///
/// ADR-214 (option B): the send paths serve an ALLOW-SET rather than the one
/// provider the catalog searches, so YO Voice Originals (including every
/// recent) stay sendable while GIPHY results chosen client-side are sent too.
/// Accepts the legacy single `providerName` string or any iterable of names;
/// anything that is not a serving provider is dropped, so `none`, a blank
/// value or a typo can only narrow the set, never widen it.
function sendableGifProviders(value) {
  const names = typeof value === "string"
    ? [value]
    : (value && typeof value[Symbol.iterator] === "function" ? [...value] : []);
  const set = new Set();
  for (const name of names) {
    const trimmed = typeof name === "string" ? name.trim() : "";
    if (isServingProvider(trimmed)) set.add(trimmed);
  }
  return set;
}

async function resolveMessageGif({
  db,
  transaction,
  gif,
  providerName = process.env.GIF_PROVIDER,
  providerNames = null,
}) {
  if (!gif) return null;
  const allowed = sendableGifProviders(providerNames ?? providerName);
  if (!allowed.has(gif.provider) ||
      (gif.provider === GIF_PROVIDERS.fake && !isFixtureEnvironment())) {
    throw new HttpsError("failed-precondition", "GIFs are not available right now.", {
      code: "not_configured",
    });
  }

  // Unlike the discovery cache, publication observes the current kill switch
  // and fails on an unreadable/malformed value. The transaction prevents an
  // in-flight send from committing against a subsequently disabled config.
  const config = await transaction.get(db.doc("appConfig/gif"));
  const enabled = config.exists ? config.data()?.enabled : undefined;
  if (enabled !== undefined && enabled !== true) {
    throw new HttpsError("failed-precondition", "GIFs are not available right now.", {
      code: "disabled",
    });
  }

  const { resolveGifAsset } = require("../media/gif");
  const result = await resolveGifAsset({
    db,
    transaction,
    provider: gif.provider,
    gifId: gif.id,
  });
  if (!result.ok) {
    throw new HttpsError(
      "failed-precondition",
      "That GIF is no longer available. Search for it again.",
      { code: result.reason },
    );
  }
  return result.asset;
}

module.exports = {
  gifMessageFallback,
  isCanonicalMessageGif,
  messageInput,
  resolveMessageGif,
  sendableGifProviders,
};

// The GIF module's public face.
//
// Dependency direction is ONE WAY: messaging may require media/gif; media/gif
// must never require messaging. That is why `resolveGifAsset` lives here
// rather than inside the direct-message send path — the send path is a caller
// of the GIF module, not a peer of it, and the same helper serves the room and
// club paths when they land.

"use strict";

const { createGifFunctions, createGifRuntime } = require("./catalog");
const { createGifCache } = require("./cache");
const { createGifModeration } = require("./moderation");
const { sanitizeTitle } = require("./normalize");
const {
  GIF_PROVIDERS,
  GIF_RATING,
  MAX_GIF_TITLE_LENGTH,
  gifAssetDocumentId,
  gifCdnUrl,
  gifTargetId,
  isPinnedGifUrl,
  isServingProvider,
  isValidGifId,
  parseGifTargetId,
} = require("./gif_ref");

/// Resolve one asset for a SEND.
///
/// `gifAssets` first, the provider only on a non-transactional miss, and a refusal for anything
/// blocked or not rated `g`. This is the single authority every send path must
/// go through, so the four content-safety layers cannot be bypassed by a
/// modified client that knows an id.
///
/// Returns `{ ok: true, asset }` or `{ ok: false, reason }` where `reason` is
/// one of `invalid_target`, `invalid_record`, `unknown_asset`, `blocked`, `rating`. It never
/// throws an HttpsError, because the caller owns the refusal envelope its own
/// surface uses.
async function resolveGifAsset({
  db,
  provider,
  gifId,
  cache = null,
  gifProvider = null,
  transaction = null,
  now = () => Date.now(),
}) {
  if (!isServingProvider(provider) || !isValidGifId(gifId)) {
    return { ok: false, reason: "invalid_target" };
  }
  const url = gifCdnUrl(provider, gifId);
  if (url === null) return { ok: false, reason: "invalid_target" };

  // Message writers pass their publishing transaction: moderation must be
  // observed atomically with the message and its replay ledger. A send never
  // performs external provider I/O or asset writes inside that transaction.
  const store = transaction ? null : (cache ?? createGifCache({ db, now }));
  const snapshot = transaction
    ? await transaction.get(db.doc(`gifAssets/${gifAssetDocumentId(provider, gifId)}`))
    : null;
  let record = transaction
    ? (snapshot.exists ? (snapshot.data() ?? {}) : null)
    : await store.readAsset(provider, gifId);

  if (record === null && gifProvider && !transaction) {
    // Non-message callers may explicitly recover an absent record through
    // their provider adapter. Message sends never opt into this path: picker
    // results are persisted first, and an absent recent must be searched again.
    const page = await gifProvider.resolve({ id: gifId });
    const fetched = page.items[0] ?? null;
    if (fetched && fetched.provider === provider && fetched.id === gifId &&
        fetched.rating === GIF_RATING) {
      await store.writeAssets([fetched]);
      record = await store.readAsset(provider, gifId);
    }
  }

  if (record === null) return { ok: false, reason: "unknown_asset" };
  if (record.blocked === true) return { ok: false, reason: "blocked" };
  if (record.provider !== provider || record.gifId !== gifId ||
      record.blocked !== false || record.schemaVersion !== 1) {
    return { ok: false, reason: "invalid_record" };
  }
  if (record.rating !== GIF_RATING) return { ok: false, reason: "rating" };

  const title = sanitizeTitle(record.title);
  const dimension = (value) =>
    Number.isSafeInteger(value) && value >= 1 && value <= 4096 ? value : 200;

  return {
    ok: true,
    asset: {
      provider,
      id: gifId,
      title,
      // Recomputed from the pinned template rather than read back from the
      // document: the stored value and the rules' expectation must be the same
      // string, and only one of them can be the source of truth.
      url,
      width: dimension(record.width),
      height: dimension(record.height),
    },
  };
}

module.exports = {
  GIF_PROVIDERS,
  GIF_RATING,
  MAX_GIF_TITLE_LENGTH,
  createGifCache,
  createGifFunctions,
  createGifModeration,
  createGifRuntime,
  gifAssetDocumentId,
  gifCdnUrl,
  gifTargetId,
  isPinnedGifUrl,
  isServingProvider,
  isValidGifId,
  parseGifTargetId,
  resolveGifAsset,
};

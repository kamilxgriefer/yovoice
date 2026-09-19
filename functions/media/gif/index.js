// The GIF module's public face.
//
// Dependency direction is ONE WAY: messaging may require media/gif; media/gif
// must never require messaging. That is why `resolveGifAsset` lives in this
// module (resolve.js, re-exported here) rather than inside the send path — the send path is a caller
// of the GIF module, not a peer of it, and the same helper serves the room and
// club paths when they land.

"use strict";

const { createGifFunctions, createGifRuntime } = require("./catalog");
const { createGifCache } = require("./cache");
const { createGifModeration } = require("./moderation");
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

const { resolveGifAsset } = require("./resolve");

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

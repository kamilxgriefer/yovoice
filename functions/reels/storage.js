const { fail } = require("../integrity/guards");

const GENERATION_PATTERN = /^[0-9]{1,30}$/u;

function customMetadataOf(metadata) {
  const custom = metadata?.metadata;
  return custom && typeof custom === "object" && !Array.isArray(custom)
    ? custom
    : {};
}

/**
 * Private-media adapter for Reels.
 *
 * It never produces Firebase download-token URLs. Every read capability is a
 * short-lived V4 URL bound to the exact object generation, and revocation uses
 * an ifGenerationMatch precondition so a replaced object cannot be mutated.
 */
function createReelStorageAdapter(bucket) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  return Object.freeze({
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },

    async readHeader(path, maxBytes = 64) {
      if (!Number.isSafeInteger(maxBytes) || maxBytes < 12 || maxBytes > 4096) {
        throw new TypeError("maxBytes must be an integer from 12 to 4096.");
      }
      const [bytes] = await bucket.file(path).download({
        start: 0,
        end: maxBytes - 1,
      });
      return bytes;
    },

    async revokeDownloadTokens(path, metadata) {
      const custom = customMetadataOf(metadata);
      if (
        typeof custom.firebaseStorageDownloadTokens !== "string" ||
        custom.firebaseStorageDownloadTokens.length === 0
      ) {
        return metadata;
      }
      const generation = String(metadata?.generation ?? "");
      if (!GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The private Reel generation is malformed.");
      }
      const [updated] = await bucket.file(path).setMetadata(
        {
          metadata: {
            ...custom,
            firebaseStorageDownloadTokens: null,
          },
        },
        { ifGenerationMatch: generation },
      );
      return updated;
    },

    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      if (
        !Number.isSafeInteger(expiresAtMs) ||
        expiresAtMs <= Date.now() ||
        typeof generation !== "string" ||
        !GENERATION_PATTERN.test(generation)
      ) {
        fail("failed-precondition", "The private Reel grant is malformed.");
      }
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4",
        action: "read",
        expires: expiresAtMs,
        queryParams: { generation },
      });
      return url;
    },

    async deleteObject(path, { generation = null } = {}) {
      if (generation !== null && !GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The private Reel cleanup generation is malformed.");
      }
      await bucket.file(path).delete({
        ignoreNotFound: true,
        ...(generation === null ? {} : { ifGenerationMatch: generation }),
      });
    },
  });
}

module.exports = { createReelStorageAdapter };

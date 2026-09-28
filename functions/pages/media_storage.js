// The private-object adapter for Page post media (ADR-233 §1.10) over a
// (lazy) Cloud Storage bucket. Every method is bounded to the `page_posts/`
// prefix; reads and deletes are generation-bound, so a replaced object is
// never served or deleted under another object's authority.
//
// Bytes are never readable through Storage rules, the uploader included
// (no client could mint a durable download token). Viewers and staff get
// 90-second V4 URLs from getPagePostMediaAccessV1.

const { fail } = require("../integrity/guards");
const {
  GENERATION_PATTERN,
  PAGE_MEDIA_PREFIX,
} = require("./media_contract");

const MAX_LIST_PAGE = 1000;

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return custom && typeof custom === "object" && !Array.isArray(custom) ? custom : {};
}

function hasDownloadToken(metadata) {
  const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
  return typeof token === "string" && token.length > 0;
}

function isMissingObject(error) {
  return error?.code === 404 || error?.code === "404" || error?.code === "storage/object-not-found";
}

function requirePagePath(path) {
  if (typeof path !== "string" || !path.startsWith(`${PAGE_MEDIA_PREFIX}/`) || path.length > 1024) {
    throw new TypeError("A page_posts object path is required.");
  }
  return path;
}

function requireGeneration(generation) {
  if (typeof generation !== "string" || !GENERATION_PATTERN.test(generation)) {
    fail("data-loss", "The Page media generation is malformed.");
  }
  return generation;
}

function createPagesMediaStorageAdapter(bucket) {
  if (!bucket?.file || !bucket?.getFiles) throw new TypeError("A Storage bucket is required.");
  return Object.freeze({
    async getMetadata(path) {
      const [metadata] = await bucket.file(requirePagePath(path)).getMetadata();
      return metadata;
    },
    // Removes the durable download token the Firebase client mints on
    // upload, generation-guarded, and pins the canonical custom metadata.
    async hardenObject(path, metadata, requiredMetadata) {
      const generation = requireGeneration(String(metadata?.generation ?? ""));
      const custom = customMetadataOf(metadata);
      const canonical = Object.entries(requiredMetadata)
        .every(([key, value]) => custom[key] === value);
      if (canonical && !hasDownloadToken(metadata)) return metadata;
      const [updated] = await bucket.file(requirePagePath(path)).setMetadata({
        metadata: { ...custom, ...requiredMetadata, firebaseStorageDownloadTokens: null },
      }, { ifGenerationMatch: generation });
      return updated;
    },
    // The first `byteCount` bytes of exactly `generation`, or null when the
    // object is shorter.
    async readHead(path, { generation, byteCount }) {
      requireGeneration(generation);
      if (!Number.isSafeInteger(byteCount) || byteCount < 1) {
        throw new TypeError("byteCount must be a positive integer.");
      }
      const stream = bucket.file(requirePagePath(path), { generation }).createReadStream({
        start: 0,
        end: byteCount - 1,
        validation: false,
      });
      const chunks = [];
      let captured = 0;
      try {
        for await (const value of stream) {
          const chunk = Buffer.isBuffer(value) ? value : Buffer.from(value);
          const remaining = byteCount - captured;
          if (remaining <= 0) break;
          chunks.push(chunk.subarray(0, remaining));
          captured += Math.min(chunk.length, remaining);
          if (captured >= byteCount) break;
        }
      } finally {
        stream.destroy();
      }
      return captured === byteCount ? Buffer.concat(chunks, captured) : null;
    },
    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      requireGeneration(generation);
      if (!Number.isSafeInteger(expiresAtMs) || expiresAtMs <= 0) {
        fail("failed-precondition", "The Page media grant is malformed.");
      }
      const [url] = await bucket.file(requirePagePath(path)).getSignedUrl({
        version: "v4", action: "read", expires: expiresAtMs, queryParams: { generation },
      });
      return url;
    },
    async deleteObject(path, { generation }) {
      requireGeneration(generation);
      await bucket.file(requirePagePath(path), { generation }).delete({
        ignoreNotFound: true,
        ifGenerationMatch: generation,
      });
    },
    // One page of the page_posts/ listing: {objects:[{name, generation,
    // timeCreatedMs}], nextPageToken|null}.
    async listObjects({ maxResults, pageToken = null }) {
      if (!Number.isSafeInteger(maxResults) || maxResults < 1 || maxResults > MAX_LIST_PAGE) {
        throw new TypeError("maxResults must be 1-1000.");
      }
      const [files, nextQuery] = await bucket.getFiles({
        prefix: `${PAGE_MEDIA_PREFIX}/`,
        maxResults,
        autoPaginate: false,
        ...(pageToken ? { pageToken } : {}),
      });
      return {
        objects: files.map((file) => ({
          name: file.name,
          generation: String(file.generation ?? file.metadata?.generation ?? ""),
          timeCreatedMs: Date.parse(file.metadata?.timeCreated ?? ""),
        })),
        nextPageToken: typeof nextQuery?.pageToken === "string" && nextQuery.pageToken.length > 0
          ? nextQuery.pageToken
          : null,
      };
    },
  });
}

function safeGrantUrl(value) {
  if (typeof value !== "string" || value.length < 1 || value.length > 4096) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "storage.googleapis.com" &&
      url.username === "" && url.password === "" && url.port === "";
  } catch {
    return false;
  }
}

module.exports = {
  MAX_LIST_PAGE,
  createPagesMediaStorageAdapter,
  customMetadataOf,
  hasDownloadToken,
  isMissingObject,
  safeGrantUrl,
};

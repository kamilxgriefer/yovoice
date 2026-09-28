// A deterministic in-memory Cloud Storage bucket for the Premium Pages post
// suites (ADR-233 package B2). It implements exactly the bucket surface the
// REAL Pages Storage adapter (pages/media_storage.js) and the REAL trusted
// probe (reels/probe.js) use — file(path, {generation}) with getMetadata,
// setMetadata(ifGenerationMatch), createReadStream({start, end}),
// getSignedUrl and delete(ifGenerationMatch, ignoreNotFound), plus
// getFiles({prefix, maxResults, pageToken}) — so both run unmodified.
const fs = require("node:fs");
const path = require("node:path");
const { Readable } = require("node:stream");

const FIXTURES = path.join(__dirname, "..", "fixtures");
const GPS_JPEG = fs.readFileSync(path.join(FIXTURES, "pages_photo_gps.jpg"));
const STRIPPED_JPEG = fs.readFileSync(path.join(FIXTURES, "pages_photo_stripped.jpg"));
// A real 3 s AAC clip (afconvert, M4A brand); the trusted probe measures
// 3136 ms.
const VOICE_M4A = fs.readFileSync(path.join(FIXTURES, "pages_voice_3s.m4a"));
const VOICE_M4A_MS = 3136;
// A real PNG signature and a RIFF/WEBP header: only the sniff matters.
const PNG_BYTES = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(STRIPPED_JPEG.length - 8, 1),
]);
const WEBP_BYTES = Buffer.concat([
  Buffer.from("RIFF"), Buffer.from([0, 0, 0, 0]), Buffer.from("WEBPVP8 "),
  Buffer.alloc(STRIPPED_JPEG.length - 16, 2),
]);

function storageError(code, message) {
  return Object.assign(new Error(message), { code });
}

class FakeBucket {
  constructor({ nowMs = () => Date.now() } = {}) {
    this.name = "demo-yovoice.firebasestorage.app";
    this.objects = new Map();
    this.nextGeneration = 1_700_000_000_000_000;
    this.deleted = [];
    this.signed = [];
    this.failDelete = new Set();
    this.nowMs = nowMs;
  }

  /// A client upload: exact bytes, content type and custom metadata, with
  /// the download token Firebase clients mint.
  put(objectPath, bytes, {
    contentType, metadata = {}, token = true, createdAtMs = null, headers = {},
  } = {}) {
    this.nextGeneration += 1;
    const generation = String(this.nextGeneration);
    this.objects.set(objectPath, {
      bytes: Buffer.from(bytes),
      generation,
      contentType,
      // contentEncoding / cacheControl / contentDisposition, as GCS reports
      // them (absent when unset).
      headers: { ...headers },
      metadata: { ...metadata, ...(token ? { firebaseStorageDownloadTokens: `tok-${generation}` } : {}) },
      timeCreated: new Date(createdAtMs ?? this.nowMs()).toISOString(),
    });
    return generation;
  }

  metadataOf(objectPath) {
    const object = this.objects.get(objectPath);
    if (!object) return null;
    return {
      name: objectPath,
      generation: object.generation,
      size: String(object.bytes.length),
      contentType: object.contentType,
      ...object.headers,
      metadata: { ...object.metadata },
      timeCreated: object.timeCreated,
    };
  }

  file(objectPath, options = {}) {
    const bucket = this;
    const pinned = options.generation ?? null;
    return {
      name: objectPath,
      async getMetadata() {
        const metadata = bucket.metadataOf(objectPath);
        if (!metadata) throw storageError(404, "No such object");
        return [metadata];
      },
      async setMetadata({ metadata }, { ifGenerationMatch } = {}) {
        const object = bucket.objects.get(objectPath);
        if (!object) throw storageError(404, "No such object");
        if (ifGenerationMatch !== undefined && String(ifGenerationMatch) !== object.generation) {
          throw storageError(412, "Precondition failed");
        }
        const next = { ...object.metadata };
        for (const [key, value] of Object.entries(metadata ?? {})) {
          if (value === null) delete next[key];
          else next[key] = value;
        }
        object.metadata = next;
        return [bucket.metadataOf(objectPath)];
      },
      createReadStream({ start = 0, end } = {}) {
        const object = bucket.objects.get(objectPath);
        if (!object || (pinned !== null && pinned !== object.generation)) {
          const stream = new Readable({ read() {} });
          process.nextTick(() => stream.destroy(storageError(404, "No such object")));
          return stream;
        }
        return Readable.from([object.bytes.subarray(start, end === undefined ? undefined : end + 1)]);
      },
      async getSignedUrl({ expires, queryParams }) {
        bucket.signed.push({ objectPath, expires, generation: queryParams?.generation ?? null });
        return [`https://storage.googleapis.com/${bucket.name}/${encodeURIComponent(objectPath)}` +
          `?generation=${queryParams?.generation}&X-Goog-Expires=${expires}`];
      },
      async delete({ ignoreNotFound = false, ifGenerationMatch } = {}) {
        if (bucket.failDelete.has(objectPath)) throw storageError(503, "injected delete failure");
        const object = bucket.objects.get(objectPath);
        if (!object) {
          if (ignoreNotFound) return [];
          throw storageError(404, "No such object");
        }
        if (ifGenerationMatch !== undefined && String(ifGenerationMatch) !== object.generation) {
          throw storageError(412, "Precondition failed");
        }
        bucket.objects.delete(objectPath);
        bucket.deleted.push({ objectPath, generation: object.generation });
        return [];
      },
    };
  }

  async getFiles({ prefix = "", maxResults = 1000, pageToken } = {}) {
    // Like GCS, a page token continues AFTER a name, so objects deleted from
    // an earlier page never shift the next one.
    const names = [...this.objects.keys()]
      .filter((name) => name.startsWith(prefix) && (!pageToken || name > pageToken))
      .sort();
    const slice = names.slice(0, maxResults);
    const next = names.length > maxResults ? { pageToken: slice[slice.length - 1] } : null;
    return [
      slice.map((name) => ({
        name,
        generation: this.objects.get(name).generation,
        metadata: { generation: this.objects.get(name).generation, timeCreated: this.objects.get(name).timeCreated },
      })),
      next,
    ];
  }
}

module.exports = {
  FakeBucket,
  GPS_JPEG,
  PNG_BYTES,
  STRIPPED_JPEG,
  VOICE_M4A,
  VOICE_M4A_MS,
  WEBP_BYTES,
};

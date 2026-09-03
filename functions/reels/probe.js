const { fail } = require("../integrity/guards");
const { Readable } = require("node:stream");

const MAX_SNIFF_BYTES = 4096;
const IMAGE_CONTENT_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);
const TRUSTED_MEDIA_PROBE_CONTENT_TYPES = Object.freeze([
  "video/mp4",
  "video/quicktime",
  "video/webm",
  "audio/mpeg",
  "audio/mp4",
  "audio/wav",
]);
const SUPPORTED_TYPES = new Set(TRUSTED_MEDIA_PROBE_CONTENT_TYPES);

function supportsTrustedMediaProbeContentType(contentType) {
  return typeof contentType === "string" && SUPPORTED_TYPES.has(contentType);
}

function bytesAt(bytes, offset, expected) {
  return bytes.length >= offset + expected.length &&
    expected.every((byte, index) => bytes[offset + index] === byte);
}

function isoBmffMajorBrand(bytes) {
  let offset = 0;
  while (offset + 12 <= bytes.length && offset < MAX_SNIFF_BYTES) {
    const size = bytes.readUInt32BE(offset);
    const type = bytes.subarray(offset + 4, offset + 8).toString("ascii");
    if (type === "ftyp") return bytes.subarray(offset + 8, offset + 12).toString("ascii");
    if (size === 0 || size < 8) return null;
    if (size === 1) {
      if (offset + 16 > bytes.length) return null;
      const extended = bytes.readBigUInt64BE(offset + 8);
      if (extended < 16n || extended > BigInt(Number.MAX_SAFE_INTEGER)) return null;
      offset += Number(extended);
    } else {
      offset += size;
    }
  }
  return null;
}

/**
 * Identifies only the bounded container/signature needed by the server-side
 * media policy. It deliberately ignores filenames and client MIME metadata.
 */
function sniffTrustedMediaHeader(value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value ?? []);
  if (bytesAt(bytes, 0, [0xff, 0xd8, 0xff])) {
    return { family: "image", detectedContentType: "image/jpeg" };
  }
  if (bytesAt(bytes, 0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return { family: "image", detectedContentType: "image/png" };
  }
  if (bytesAt(bytes, 0, [0x52, 0x49, 0x46, 0x46]) &&
      bytesAt(bytes, 8, [0x57, 0x45, 0x42, 0x50])) {
    return { family: "image", detectedContentType: "image/webp" };
  }
  if (bytesAt(bytes, 0, [0x1a, 0x45, 0xdf, 0xa3])) {
    return { family: "webm", detectedContentType: null };
  }
  const majorBrand = isoBmffMajorBrand(bytes);
  if (majorBrand !== null) {
    return { family: "iso-bmff", detectedContentType: null, majorBrand };
  }
  if (bytesAt(bytes, 0, [0x49, 0x44, 0x33]) ||
      (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0)) {
    return { family: "audio", detectedContentType: "audio/mpeg" };
  }
  if (bytesAt(bytes, 0, [0x52, 0x49, 0x46, 0x46]) &&
      bytesAt(bytes, 8, [0x57, 0x41, 0x56, 0x45])) {
    return { family: "audio", detectedContentType: "audio/wav" };
  }
  return null;
}

async function readGenerationBoundHeader(file, size) {
  const byteCount = Math.min(size, MAX_SNIFF_BYTES);
  const stream = file.createReadStream({
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
    return Buffer.concat(chunks, captured);
  } catch (_) {
    fail("failed-precondition", "The uploaded media header could not be verified.");
  } finally {
    stream.destroy();
  }
}

function parserContentType(header) {
  if (header.family === "iso-bmff") {
    return header.majorBrand === "qt  " ? "video/quicktime" : "video/mp4";
  }
  if (header.family === "webm") return "video/webm";
  return header.detectedContentType;
}

function detectedContentType(header, format) {
  if (header.detectedContentType !== null) return header.detectedContentType;
  const hasAudio = format?.hasAudio === true;
  const hasVideo = format?.hasVideo === true;
  if (header.family === "webm") {
    return hasVideo ? "video/webm" : hasAudio ? "audio/webm" : null;
  }
  if (header.family === "iso-bmff") {
    if (hasVideo) {
      return header.majorBrand === "qt  " || header.majorBrand === "M4V "
        ? "video/quicktime"
        : "video/mp4";
    }
    if (hasAudio) {
      return header.majorBrand === "qt  " ? "audio/quicktime" : "audio/mp4";
    }
  }
  return null;
}

/**
 * Creates a trusted container/track/duration probe backed by music-metadata
 * and generation-bound GCS streams. The first stream sniffs an exact bounded
 * header without trusting the filename or declared MIME. Audio/video then use
 * a second stream of that same immutable generation to inspect tracks and
 * duration. Images need no optional parser and return after signature checks.
 *
 * Integration dependency (Functions runtime): `music-metadata`.
 */
function createTrustedGcsMediaProbe(bucket) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  return async function probeReelMedia({
    storagePath,
    generation,
    contentType,
    size,
  }) {
    const declaredTypeIsSupported =
      supportsTrustedMediaProbeContentType(contentType) ||
      IMAGE_CONTENT_TYPES.has(contentType) ||
      contentType === "audio/m4a" || contentType === "audio/x-m4a";
    if (
      typeof storagePath !== "string" ||
      typeof generation !== "string" ||
      !/^[0-9]{1,30}$/u.test(generation) ||
      !declaredTypeIsSupported ||
      !Number.isSafeInteger(size) ||
      size < 1
    ) {
      fail("failed-precondition", "The media probe request is malformed.");
    }
    const file = bucket.file(storagePath, { generation });
    const headerBytes = await readGenerationBoundHeader(file, size);
    const header = sniffTrustedMediaHeader(headerBytes);
    if (header === null) {
      fail("failed-precondition", "The uploaded media header is unsupported.");
    }
    if (header.family === "image") {
      return {
        detectedContentType: header.detectedContentType,
        durationMs: null,
        generation,
        hasAudio: false,
        hasVideo: false,
        size,
      };
    }
    let parseWebStream;
    try {
      ({ parseWebStream } = await import("music-metadata"));
    } catch (_) {
      fail(
        "failed-precondition",
        "The trusted video/audio probe is not installed on this build.",
      );
    }
    const stream = file.createReadStream({ validation: false });
    try {
      const metadata = await parseWebStream(
        Readable.toWeb(stream),
        { mimeType: parserContentType(header), size },
        { duration: true, skipCovers: true },
      );
      const seconds = metadata?.format?.duration;
      if (!Number.isFinite(seconds) || seconds <= 0) {
        fail("failed-precondition", "The uploaded media duration is unreadable.");
      }
      const actualContentType = detectedContentType(header, metadata?.format);
      if (actualContentType === null) {
        fail("failed-precondition", "The uploaded media tracks are unreadable.");
      }
      return {
        detectedContentType: actualContentType,
        durationMs: Math.round(seconds * 1000),
        generation,
        hasAudio: metadata.format.hasAudio === true,
        hasVideo: metadata.format.hasVideo === true,
        size,
      };
    } catch (error) {
      // Only preserve the intentionally generated callable error. Parser/GCS
      // error codes are implementation details and must not cross the trust
      // boundary or be mistaken for a Firebase callable status.
      if (error?.code === "failed-precondition") throw error;
      fail("failed-precondition", "The uploaded media could not be verified.");
    } finally {
      stream.destroy();
    }
  };
}

// Reels keeps a feature-local name for readability. The generic alias is safe
// for another server-owned media pipeline (for example DM video) provided
// that caller independently enforces its own MIME, byte and duration policy.
const createReelMediaProbe = createTrustedGcsMediaProbe;

module.exports = {
  TRUSTED_MEDIA_PROBE_CONTENT_TYPES,
  createReelMediaProbe,
  createTrustedGcsMediaProbe,
  sniffTrustedMediaHeader,
  supportsTrustedMediaProbeContentType,
};

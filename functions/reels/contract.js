const net = require("node:net");

const {
  fail,
  requireBoolean,
  requireExactInput,
  requireId,
  requireObject,
  requireSafeInteger,
} = require("../integrity/guards");

const REEL_SCHEMA_VERSION = 1;
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_VIDEO_BYTES = 100 * 1024 * 1024;
const MAX_AUDIO_BYTES = 15 * 1024 * 1024;
const MIN_MEDIA_BYTES = 128;
const MIN_AUDIO_BYTES = 512;
const MAX_DURATION_MS = 90 * 1000;
const MIN_DURATION_MS = 1000;
const MAX_CAPTION_LENGTH = 2200;
const MAX_TEXT_OVERLAYS = 8;
const MAX_LINK_OVERLAYS = 4;
const MAX_REEL_PAGE_SIZE = 20;

const MEDIA_TYPES = Object.freeze({
  image: Object.freeze({
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
  }),
  video: Object.freeze({
    "video/mp4": "mp4",
    "video/quicktime": "mov",
    "video/webm": "webm",
  }),
});
const AUDIO_TYPES = Object.freeze({
  "audio/mpeg": "mp3",
  "audio/mp4": "m4a",
  "audio/wav": "wav",
});
const FILTERS = new Set(["original", "vivid", "warm", "cool", "monochrome"]);
const OVERLAY_COLORS = new Set(["light", "dark", "accent", "cyan"]);
const REEL_REPORT_REASONS = Object.freeze([
  "spam",
  "harassment",
  "hate",
  "sexual",
  "violence",
  "selfHarm",
  "impersonation",
  "other",
]);
const REEL_REPORT_REASON_SET = new Set(REEL_REPORT_REASONS);
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const OVERLAY_ID_PATTERN = /^[A-Za-z0-9_-]{1,40}$/u;
const SORT_KEY_PATTERN = /^[0-9]{13}_[A-Za-z0-9_-]{1,128}$/u;

function exactObject(value, keys, label) {
  requireObject(value, label);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length ||
    actual.some((key, index) => key !== expected[index])
  ) {
    fail("invalid-argument", `${label} has an unsupported shape.`);
  }
  return value;
}

function exactStoredObject(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("data-loss", `${label} is malformed.`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length ||
    actual.some((key, index) => key !== expected[index])
  ) {
    fail("data-loss", `${label} is malformed.`);
  }
  return value;
}

function normalizedText(value, maxLength, label, { allowEmpty = false } = {}) {
  if (typeof value !== "string" || value !== value.trim()) {
    fail("invalid-argument", `${label} must be normalized text.`);
  }
  if ((!allowEmpty && value.length === 0) || value.length > maxLength) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function permille(value, label, { min = 0, max = 1000 } = {}) {
  return requireSafeInteger(value, label, { min, max });
}

function validateDraftPlan(data) {
  requireExactInput(
    data,
    [
      "requestId",
      "mediaKind",
      "mediaContentType",
      "mediaSize",
      "durationMs",
      "hasBackingAudio",
      "audioContentType",
      "audioSize",
      "audioDurationMs",
    ],
    [
      "requestId",
      "mediaKind",
      "mediaContentType",
      "mediaSize",
      "durationMs",
      "hasBackingAudio",
      "audioContentType",
      "audioSize",
      "audioDurationMs",
    ],
  );
  const mediaKind = data.mediaKind;
  if (mediaKind !== "image" && mediaKind !== "video") {
    fail("invalid-argument", "mediaKind is invalid.");
  }
  const supported = MEDIA_TYPES[mediaKind];
  if (typeof data.mediaContentType !== "string" || !supported[data.mediaContentType]) {
    fail("invalid-argument", "mediaContentType is unsupported.");
  }
  const mediaSize = requireSafeInteger(data.mediaSize, "mediaSize", {
    min: MIN_MEDIA_BYTES,
    max: mediaKind === "image" ? MAX_IMAGE_BYTES : MAX_VIDEO_BYTES,
  });
  const durationMs = requireSafeInteger(data.durationMs, "durationMs", {
    min: mediaKind === "image" ? 0 : MIN_DURATION_MS,
    max: mediaKind === "image" ? 0 : MAX_DURATION_MS,
  });
  const hasBackingAudio = requireBoolean(data.hasBackingAudio, "hasBackingAudio");
  let audioContentType = null;
  let audioSize = null;
  let audioDurationMs = null;
  if (hasBackingAudio) {
    if (typeof data.audioContentType !== "string" || !AUDIO_TYPES[data.audioContentType]) {
      fail("invalid-argument", "audioContentType is unsupported.");
    }
    audioContentType = data.audioContentType;
    audioSize = requireSafeInteger(data.audioSize, "audioSize", {
      min: MIN_AUDIO_BYTES,
      max: MAX_AUDIO_BYTES,
    });
    audioDurationMs = requireSafeInteger(data.audioDurationMs, "audioDurationMs", {
      min: MIN_DURATION_MS,
      max: MAX_DURATION_MS,
    });
  } else if (
    data.audioContentType !== null ||
    data.audioSize !== null ||
    data.audioDurationMs !== null
  ) {
    fail("invalid-argument", "Audio fields require hasBackingAudio.");
  }
  return {
    mediaKind,
    mediaContentType: data.mediaContentType,
    mediaSize,
    durationMs,
    hasBackingAudio,
    audioContentType,
    audioSize,
    audioDurationMs,
  };
}

function validateCrop(value) {
  const crop = exactObject(
    value,
    ["scalePermille", "offsetXPermille", "offsetYPermille"],
    "crop",
  );
  return {
    scalePermille: permille(crop.scalePermille, "crop.scalePermille", {
      min: 1000,
      max: 8000,
    }),
    offsetXPermille: permille(crop.offsetXPermille, "crop.offsetXPermille", {
      min: -1000,
      max: 1000,
    }),
    offsetYPermille: permille(crop.offsetYPermille, "crop.offsetYPermille", {
      min: -1000,
      max: 1000,
    }),
  };
}

function validateTextOverlay(value) {
  const overlay = exactObject(
    value,
    ["id", "text", "xPermille", "yPermille", "scalePermille", "color"],
    "text overlay",
  );
  const id = requireId(overlay.id, "text overlay id");
  if (!OVERLAY_ID_PATTERN.test(id)) {
    fail("invalid-argument", "text overlay id is invalid.");
  }
  if (!OVERLAY_COLORS.has(overlay.color)) {
    fail("invalid-argument", "text overlay color is invalid.");
  }
  return {
    id,
    text: normalizedText(overlay.text, 120, "text overlay text"),
    xPermille: permille(overlay.xPermille, "text overlay x"),
    yPermille: permille(overlay.yPermille, "text overlay y"),
    scalePermille: permille(overlay.scalePermille, "text overlay scale", {
      min: 750,
      max: 2000,
    }),
    color: overlay.color,
  };
}

function isPrivateIpv4(hostname) {
  if (net.isIP(hostname) !== 4) return false;
  const [first, second] = hostname.split(".").map(Number);
  return first === 0 ||
    first === 10 ||
    first === 127 ||
    first >= 224 ||
    (first === 100 && second >= 64 && second <= 127) ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168);
}

function isSafePublicHttpsUrl(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 2048) {
    return false;
  }
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.port ||
      url.hostname.length === 0 ||
      url.hostname === "localhost" ||
      url.hostname.endsWith(".localhost") ||
      url.hostname.endsWith(".local") ||
      !url.hostname.includes(".") ||
      net.isIP(url.hostname) === 6 ||
      isPrivateIpv4(url.hostname)
    ) {
      return false;
    }
    return /^[a-z0-9.-]+$/u.test(url.hostname);
  } catch (_) {
    return false;
  }
}

function validateLinkOverlay(value) {
  const overlay = exactObject(
    value,
    ["id", "label", "url", "xPermille", "yPermille"],
    "link overlay",
  );
  const id = requireId(overlay.id, "link overlay id");
  if (!OVERLAY_ID_PATTERN.test(id)) {
    fail("invalid-argument", "link overlay id is invalid.");
  }
  if (!isSafePublicHttpsUrl(overlay.url)) {
    fail("invalid-argument", "Use a public HTTPS link.");
  }
  return {
    id,
    label: normalizedText(overlay.label, 60, "link overlay label"),
    url: overlay.url,
    xPermille: permille(overlay.xPermille, "link overlay x"),
    yPermille: permille(overlay.yPermille, "link overlay y"),
  };
}

function validateComposition(value, plan) {
  const composition = exactObject(
    value,
    [
      "caption",
      "crop",
      "filter",
      "trimStartMs",
      "trimEndMs",
      "textOverlays",
      "linkOverlays",
      "originalAudioVolume",
      "backingAudioVolume",
      "audioTrimStartMs",
      "audioRightsAttested",
      "audioAttribution",
    ],
    "composition",
  );
  if (!FILTERS.has(composition.filter)) {
    fail("invalid-argument", "filter is invalid.");
  }
  if (!Array.isArray(composition.textOverlays) || composition.textOverlays.length > MAX_TEXT_OVERLAYS) {
    fail("invalid-argument", "textOverlays is invalid.");
  }
  if (!Array.isArray(composition.linkOverlays) || composition.linkOverlays.length > MAX_LINK_OVERLAYS) {
    fail("invalid-argument", "linkOverlays is invalid.");
  }
  const textOverlays = composition.textOverlays.map(validateTextOverlay);
  const linkOverlays = composition.linkOverlays.map(validateLinkOverlay);
  if (new Set(textOverlays.map(({ id }) => id)).size !== textOverlays.length) {
    fail("invalid-argument", "Text overlay ids must be unique.");
  }
  if (new Set(linkOverlays.map(({ id }) => id)).size !== linkOverlays.length) {
    fail("invalid-argument", "Link overlay ids must be unique.");
  }
  const trimStartMs = requireSafeInteger(composition.trimStartMs, "trimStartMs", {
    min: 0,
    max: MAX_DURATION_MS,
  });
  const trimEndMs = requireSafeInteger(composition.trimEndMs, "trimEndMs", {
    min: 0,
    max: MAX_DURATION_MS,
  });
  const originalAudioVolume = requireSafeInteger(
    composition.originalAudioVolume,
    "originalAudioVolume",
    { min: 0, max: 100 },
  );
  const backingAudioVolume = requireSafeInteger(
    composition.backingAudioVolume,
    "backingAudioVolume",
    { min: 0, max: 100 },
  );
  const audioTrimStartMs = requireSafeInteger(
    composition.audioTrimStartMs,
    "audioTrimStartMs",
    { min: 0, max: MAX_DURATION_MS },
  );
  const audioRightsAttested = requireBoolean(
    composition.audioRightsAttested,
    "audioRightsAttested",
  );
  if (plan.mediaKind === "image") {
    if (trimStartMs !== 0 || trimEndMs !== 0 || originalAudioVolume !== 0) {
      fail("invalid-argument", "Still images cannot carry video trim or original audio.");
    }
  } else if (
    trimEndMs <= trimStartMs ||
    trimEndMs > plan.durationMs ||
    trimEndMs - trimStartMs > MAX_DURATION_MS
  ) {
    fail("invalid-argument", "Video trim must select between 1 and 90 seconds.");
  }
  const audioAttribution = normalizedText(
    composition.audioAttribution,
    160,
    "audioAttribution",
    { allowEmpty: true },
  );
  if (plan.hasBackingAudio && !audioRightsAttested) {
    fail("failed-precondition", "Confirm that you may use the backing audio.");
  }
  if (!plan.hasBackingAudio && (
    backingAudioVolume !== 0 ||
    audioTrimStartMs !== 0 ||
    audioRightsAttested ||
    audioAttribution.length > 0
  )) {
    fail("invalid-argument", "Backing-audio settings require an audio upload.");
  }
  return {
    caption: normalizedText(composition.caption, MAX_CAPTION_LENGTH, "caption", {
      allowEmpty: true,
    }),
    crop: validateCrop(composition.crop),
    filter: composition.filter,
    trimStartMs,
    trimEndMs,
    textOverlays,
    linkOverlays,
    originalAudioVolume,
    backingAudioVolume,
    audioTrimStartMs,
    audioRightsAttested,
    audioAttribution,
  };
}

function sniffContentType(value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value ?? []);
  const at = (offset, expected) =>
    bytes.length >= offset + expected.length &&
    expected.every((byte, index) => bytes[offset + index] === byte);
  if (at(0, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) return "image/webp";
  if (at(0, [0x1a, 0x45, 0xdf, 0xa3])) return "video/webm";
  if (at(4, [0x66, 0x74, 0x79, 0x70])) {
    const brand = bytes.length >= 12 ? bytes.subarray(8, 12).toString("ascii") : "";
    if (brand === "M4A ") return "audio/mp4";
    if (brand === "qt  " || brand === "M4V ") return "video/quicktime";
    return "video/mp4";
  }
  if (at(0, [0x49, 0x44, 0x33]) || (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0)) {
    return "audio/mpeg";
  }
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x41, 0x56, 0x45])) return "audio/wav";
  return null;
}

function customMetadata(metadata) {
  const value = metadata?.metadata;
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function validateStoredAsset(metadata, header, expected) {
  const generation = String(metadata?.generation ?? "");
  const size = Number(metadata?.size);
  const custom = customMetadata(metadata);
  if (
    !GENERATION_PATTERN.test(generation) ||
    generation !== expected.generation ||
    !Number.isSafeInteger(size) ||
    size !== expected.size ||
    metadata?.contentType !== expected.contentType ||
    sniffContentType(header) !== expected.contentType ||
    custom.ownerId !== expected.ownerId ||
    custom.reelId !== expected.reelId ||
    custom.assetKind !== expected.assetKind
  ) {
    fail("failed-precondition", "The uploaded Reel asset is invalid.");
  }
  return { contentType: expected.contentType, generation, size };
}

function assetExtension(kind, contentType) {
  return kind === "backingAudio"
    ? AUDIO_TYPES[contentType]
    : MEDIA_TYPES[kind]?.[contentType];
}

function reelStoragePath(ownerId, reelId, kind, contentType) {
  const extension = assetExtension(kind, contentType);
  if (!extension) fail("invalid-argument", "Unsupported Reel asset type.");
  const basename = kind === "backingAudio" ? "backing-audio" : "media";
  return `reels/${ownerId}/${reelId}/${basename}.${extension}`;
}

function validateGeneration(value, label = "generation") {
  if (typeof value !== "string" || !GENERATION_PATTERN.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function validateSortKey(value) {
  if (typeof value !== "string" || !SORT_KEY_PATTERN.test(value)) {
    fail("invalid-argument", "cursor is invalid.");
  }
  return value;
}

function validateReelReportReason(value) {
  if (typeof value !== "string" || !REEL_REPORT_REASON_SET.has(value)) {
    fail("invalid-argument", "reason is invalid.");
  }
  return value;
}

module.exports = {
  AUDIO_TYPES,
  FILTERS,
  GENERATION_PATTERN,
  MAX_AUDIO_BYTES,
  MAX_DURATION_MS,
  MAX_IMAGE_BYTES,
  MAX_LINK_OVERLAYS,
  MAX_REEL_PAGE_SIZE,
  MAX_TEXT_OVERLAYS,
  MAX_VIDEO_BYTES,
  MEDIA_TYPES,
  MIN_DURATION_MS,
  REEL_REPORT_REASONS,
  REEL_SCHEMA_VERSION,
  assetExtension,
  exactStoredObject,
  isSafePublicHttpsUrl,
  reelStoragePath,
  sniffContentType,
  validateComposition,
  validateDraftPlan,
  validateGeneration,
  validateReelReportReason,
  validateSortKey,
  validateStoredAsset,
};

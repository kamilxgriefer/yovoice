// In-app bug reports: the shared, pure contract (ADR "In-app bug reports are
// server-written and owner-read").
//
// Every value a client may send is named here, with its bound, so the
// callable, the rules suites and the account-deletion sweep all agree on one
// shape. Nothing in this module performs I/O.
//
// What a report NEVER carries, by construction of the allowlist below: message
// or voice content (other than what the reporter types or chooses to show in
// the screenshot), other people's ids or names, tokens of any kind, signed
// URLs, the reporter's e-mail address, IP address or device identifiers.

const { digest, fail } = require("../integrity/guards");

const BUG_REPORTS = "bugReports";
const BUG_REPORT_RESERVATIONS = "bugReportUploadReservations";
const BUG_REPORT_STORAGE_PREFIX = "bug_reports";
const BUG_REPORT_CONFIG = Object.freeze({ collection: "appConfig", id: "bugReports" });

const BUG_REPORT_SCHEMA_VERSION = 1;
const REPORT_ID_PATTERN = /^br_[a-f0-9]{40}$/u;
const GENERATION_PATTERN = /^[0-9]{1,24}$/u;

const DESCRIPTION_MIN = 10;
const DESCRIPTION_MAX = 2000;

// One screenshot, JPEG only: the client re-encodes the captured frame, so a
// PNG/WebP/HEIC branch would be dead surface. 128 B is the Storage rules'
// image floor everywhere else; 1.5 MB is far above a 1280 px q70 frame.
const SCREENSHOT_CONTENT_TYPE = "image/jpeg";
const SCREENSHOT_MIN_BYTES = 128;
const SCREENSHOT_MAX_BYTES = 1_500_000;

const RESERVATION_TTL_MS = 15 * 60 * 1000;
const REPORT_RETENTION_MS = 180 * 24 * 60 * 60 * 1000;
const SCREENSHOT_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
const SCREENSHOT_ACCESS_TTL_MS = 5 * 60 * 1000;

// Per-reporter ceilings on the report itself, and project-wide ceilings on
// the optional alert channels only.
//
// There is deliberately NO project-wide ceiling on submitting a report: one
// fixed 24-hour bucket shared by every account let about fifteen throwaway
// accounts (20 a day each) lock every real tester out of reporting for a day.
// The shared buckets instead bound what reaches the paid or public alert
// channels (Resend quota, GitHub issues): a report over budget is still
// stored and listed in the Staff Center, it is only not announced. Their
// rate-limit documents are keyed by a sentinel that is not an Auth uid, so the
// account-deletion sweep can never mistake one for an account's.
const RATE_LIMITS = Object.freeze({
  burst: Object.freeze({ scope: "bugReport.submit.10m", maxEvents: 5, windowMs: 10 * 60 * 1000 }),
  daily: Object.freeze({ scope: "bugReport.submit.day", maxEvents: 20, windowMs: 24 * 60 * 60 * 1000 }),
  emailDelivery: Object.freeze({ scope: "bugReport.delivery.email.day", maxEvents: 200, windowMs: 24 * 60 * 60 * 1000 }),
  githubDelivery: Object.freeze({ scope: "bugReport.delivery.github.day", maxEvents: 50, windowMs: 24 * 60 * 60 * 1000 }),
});
const GLOBAL_RATE_LIMIT_SENTINEL = "bug-report-global-sentinel";

const PLATFORMS = Object.freeze(["ios", "android", "web", "macos", "windows", "linux", "fuchsia", "unknown"]);
const THEMES = Object.freeze(["system", "dark", "light"]);
const BRIGHTNESS = Object.freeze(["dark", "light"]);
const STATUSES = Object.freeze(["new", "triaged", "resolved", "dismissed"]);
// screenshot.status values. "refused": a banned account declared a screenshot;
// the report is stored, no upload reservation is issued (storage.rules'
// isActiveUser refuses a banned uploader anyway). "removed": the owner removed
// it (a rights request, or it shows something it should not).
const SCREENSHOT_STATUSES = Object.freeze([
  "reserved", "attached", "expired", "deleted", "refused", "removed", "missing",
]);

const CONTEXT_FIELDS = Object.freeze([
  "appVersion", "buildNumber", "platform", "osVersion", "locale", "theme",
  "brightness", "route", "routeDepth", "viewportWidth", "viewportHeight", "textScale",
]);

const APP_VERSION_PATTERN = /^[0-9A-Za-z.+_-]{1,32}$/u;
const BUILD_NUMBER_PATTERN = /^[0-9]{1,10}$/u;
const LOCALE_PATTERN = /^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,3}$/u;
// A screen or route NAME: Dart class names and named routes. No slashes with
// ids, no spaces with sentences — a route that carries an id is not a name.
const ROUTE_PATTERN = /^[A-Za-z_$][A-Za-z0-9_$<>.,:-]{0,79}$/u;
// Printable ASCII only, no control characters; an OS version string.
const OS_VERSION_PATTERN = /^[\x20-\x7e]{1,120}$/u;

function requireEnum(value, allowed, label) {
  if (typeof value !== "string" || !allowed.includes(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function requirePattern(value, pattern, label) {
  if (typeof value !== "string" || !pattern.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function requireIntegerIn(value, min, max, label) {
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

/** The reporter's words: trimmed, bounded, no control characters but newlines and tabs. */
function normalizeDescription(value) {
  if (typeof value !== "string") fail("invalid-argument", "description must be text.");
  // Normalize line endings, strip every C0/C1 control except \n and \t.
  const cleaned = value
    .replace(/\r\n?/gu, "\n")
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/gu, "")
    .trim();
  if (cleaned.length < DESCRIPTION_MIN || cleaned.length > DESCRIPTION_MAX) {
    fail("invalid-argument",
      `description must contain ${DESCRIPTION_MIN}-${DESCRIPTION_MAX} characters.`);
  }
  return cleaned;
}

/** The device context, exactly: every key required, every value bounded. */
function normalizeContext(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid-argument", "context must be an object.");
  }
  const keys = Object.keys(value);
  const unknown = keys.find((key) => !CONTEXT_FIELDS.includes(key));
  if (unknown !== undefined) fail("invalid-argument", `Unsupported context field: ${unknown}.`);
  const missing = CONTEXT_FIELDS.find((key) => !Object.prototype.hasOwnProperty.call(value, key));
  if (missing !== undefined) fail("invalid-argument", `context.${missing} is required.`);
  const textScale = value.textScale;
  if (typeof textScale !== "number" || !Number.isFinite(textScale) ||
      textScale < 0.5 || textScale > 5) {
    fail("invalid-argument", "context.textScale is invalid.");
  }
  return {
    appVersion: requirePattern(value.appVersion, APP_VERSION_PATTERN, "context.appVersion"),
    buildNumber: requirePattern(value.buildNumber, BUILD_NUMBER_PATTERN, "context.buildNumber"),
    platform: requireEnum(value.platform, PLATFORMS, "context.platform"),
    osVersion: requirePattern(value.osVersion, OS_VERSION_PATTERN, "context.osVersion"),
    locale: requirePattern(value.locale, LOCALE_PATTERN, "context.locale"),
    theme: requireEnum(value.theme, THEMES, "context.theme"),
    brightness: requireEnum(value.brightness, BRIGHTNESS, "context.brightness"),
    route: requirePattern(value.route, ROUTE_PATTERN, "context.route"),
    routeDepth: requireIntegerIn(value.routeDepth, 0, 64, "context.routeDepth"),
    viewportWidth: requireIntegerIn(value.viewportWidth, 0, 20000, "context.viewportWidth"),
    viewportHeight: requireIntegerIn(value.viewportHeight, 0, 20000, "context.viewportHeight"),
    textScale: Math.round(textScale * 100) / 100,
  };
}

/** null, or the one declared screenshot the reservation will bind. */
function normalizeScreenshotDeclaration(value) {
  if (value === null) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid-argument", "screenshot must be null or an object.");
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== 2 || keys[0] !== "contentType" || keys[1] !== "size") {
    fail("invalid-argument", "screenshot must declare exactly contentType and size.");
  }
  if (value.contentType !== SCREENSHOT_CONTENT_TYPE) {
    fail("invalid-argument", "The screenshot must be a JPEG image.");
  }
  return {
    contentType: SCREENSHOT_CONTENT_TYPE,
    size: requireIntegerIn(value.size, SCREENSHOT_MIN_BYTES, SCREENSHOT_MAX_BYTES, "screenshot.size"),
  };
}

function bugReportId(uid, requestId) {
  return `br_${digest("bugReport.v1", uid, requestId).slice(0, 40)}`;
}

function requireReportId(value) {
  if (typeof value !== "string" || !REPORT_ID_PATTERN.test(value)) {
    fail("invalid-argument", "reportId is invalid.");
  }
  return value;
}

function bugReportStoragePath(uid, reportId) {
  return `${BUG_REPORT_STORAGE_PREFIX}/${uid}/${reportId}.jpg`;
}

/** The exact custom metadata storage.rules accepts for one reserved object. */
function bugReportUploadMetadata(uid, reportId) {
  return { yovoiceOwnerUid: uid, yovoiceReportId: reportId };
}

/** Parses a stored path back into its owner and report id, or null. */
function parseBugReportStoragePath(value) {
  if (typeof value !== "string") return null;
  const parts = value.split("/");
  if (parts.length !== 3 || parts[0] !== BUG_REPORT_STORAGE_PREFIX) return null;
  const match = /^(br_[a-f0-9]{40})\.jpg$/u.exec(parts[2]);
  if (!match || parts[1].length < 1 || parts[1].length > 128) return null;
  return { ownerId: parts[1], reportId: match[1] };
}

module.exports = {
  APP_VERSION_PATTERN,
  BRIGHTNESS,
  BUG_REPORTS,
  BUG_REPORT_CONFIG,
  BUG_REPORT_RESERVATIONS,
  BUG_REPORT_SCHEMA_VERSION,
  BUG_REPORT_STORAGE_PREFIX,
  CONTEXT_FIELDS,
  DESCRIPTION_MAX,
  DESCRIPTION_MIN,
  GENERATION_PATTERN,
  GLOBAL_RATE_LIMIT_SENTINEL,
  PLATFORMS,
  RATE_LIMITS,
  REPORT_ID_PATTERN,
  REPORT_RETENTION_MS,
  RESERVATION_TTL_MS,
  SCREENSHOT_ACCESS_TTL_MS,
  SCREENSHOT_CONTENT_TYPE,
  SCREENSHOT_MAX_BYTES,
  SCREENSHOT_MIN_BYTES,
  SCREENSHOT_RETENTION_MS,
  SCREENSHOT_STATUSES,
  STATUSES,
  THEMES,
  bugReportId,
  bugReportStoragePath,
  bugReportUploadMetadata,
  normalizeContext,
  normalizeDescription,
  normalizeScreenshotDeclaration,
  parseBugReportStoragePath,
  requireReportId,
};

// The Page post write contract (ADR-233 §1.9, §2.4, package B2), pure: the
// JPEG metadata walk on real fixtures, reserve and publish input rules, the
// post-text character policy, deterministic ids, the storage.rules key list
// and the staff role set. No emulator needed.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

process.env.GCLOUD_PROJECT ||= "yovoice-pages-media-contract-test";
const { getApps, initializeApp } = require("firebase-admin/app");

if (getApps().length === 0) initializeApp();

const { assertNoImageMetadata, jpegFrameSize, jpegHeaderViolation } = require("../pages/media_probe");
const {
  PAGE_DAILY_BUDGET,
  PAGE_MEDIA_HEAD_BYTES,
  PAGE_MEDIA_RESERVATION_KEYS,
  PAGE_MEDIA_RESERVATION_TTL_MS,
  normalizePostText,
  pageBudgetDay,
  pageBudgetId,
  pageMediaDeletionJob,
  pageMediaIdFor,
  pagePostIdFor,
  pagePostOpenReports,
  parsePagePostObjectName,
  requireReserveItems,
} = require("../pages/media_contract");
const { PAGE_STAFF_ROLES } = require("../pages/media_access");
const { PAGES_SAFETY_ACTIONS } = require("../pages/activation");
const { PAGES_POST_RATE_LIMITS } = require("../pages/posts");
const { GPS_JPEG, PNG_BYTES, STRIPPED_JPEG, WEBP_BYTES } = require("./helpers/pages_media_fixture");

function segment(marker, payload) {
  const length = Buffer.alloc(2);
  length.writeUInt16BE(payload.length + 2);
  return Buffer.concat([Buffer.from([0xff, marker]), length, payload]);
}

/// STRIPPED_JPEG with `extra` segments inserted right after SOI + APP0.
function withSegments(...extra) {
  const app0Length = STRIPPED_JPEG.readUInt16BE(4);
  const headEnd = 4 + app0Length;
  return Buffer.concat([STRIPPED_JPEG.subarray(0, headEnd), ...extra, STRIPPED_JPEG.subarray(headEnd)]);
}

test("the real GPS-tagged JPEG is refused; its stripped copy passes", () => {
  assert.equal(jpegHeaderViolation(GPS_JPEG), "metadata");
  assert.throws(() => assertNoImageMetadata(GPS_JPEG), (error) => {
    assert.equal(error.code, "failed-precondition");
    assert.equal(error.details.reason, "pageMediaMetadata");
    return true;
  });
  assert.equal(jpegHeaderViolation(STRIPPED_JPEG), null);
  assert.doesNotThrow(() => assertNoImageMetadata(STRIPPED_JPEG));
});

test("every APP1-APP15 segment and COM are refused; APP0 is kept", () => {
  for (let marker = 0xe1; marker <= 0xef; marker += 1) {
    assert.equal(jpegHeaderViolation(withSegments(segment(marker, Buffer.from("x")))), "metadata",
      marker.toString(16));
  }
  assert.equal(jpegHeaderViolation(withSegments(segment(0xfe, Buffer.from("hello")))), "metadata");
  // ICC profile (APP2) and XMP (APP1) as real writers label them.
  assert.equal(jpegHeaderViolation(withSegments(segment(0xe2, Buffer.from("ICC_PROFILE\0")))), "metadata");
  assert.equal(jpegHeaderViolation(withSegments(
    segment(0xe1, Buffer.from("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta/>")))), "metadata");
  assert.equal(jpegHeaderViolation(withSegments(segment(0xe0, Buffer.from("JFXX\0")))), null);
});

test("non-JPEG, truncated, malformed or over-long headers are refused", () => {
  assert.equal(jpegHeaderViolation(PNG_BYTES), "notJpeg");
  assert.equal(jpegHeaderViolation(WEBP_BYTES), "notJpeg");
  assert.equal(jpegHeaderViolation(Buffer.alloc(0)), "notJpeg");
  const sos = STRIPPED_JPEG.indexOf(Buffer.from([0xff, 0xda]));
  assert.equal(jpegHeaderViolation(STRIPPED_JPEG.subarray(0, sos)), "truncated");
  assert.equal(jpegHeaderViolation(Buffer.from([0xff, 0xd8, 0xff, 0xd9])), "noScan");
  assert.equal(jpegHeaderViolation(Buffer.from([0xff, 0xd8, 0x00, 0x00, 0xff, 0xda])), "malformed");
  assert.equal(jpegHeaderViolation(Buffer.from([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x01, 0xff, 0xda])),
    "malformed");
  // A header that does not reach SOS within the first 256 KB: five maximal
  // APP0 segments. The server reads only PAGE_MEDIA_HEAD_BYTES of it.
  const big = withSegments(...Array.from({ length: 5 }, () => segment(0xe0, Buffer.alloc(65_533, 1))));
  assert.equal(big.length > PAGE_MEDIA_HEAD_BYTES, true);
  assert.equal(jpegHeaderViolation(big.subarray(0, PAGE_MEDIA_HEAD_BYTES)), "truncated");
});

/// A minimal header: SOI, the given segments, SOS, EOI.
function header(...segments) {
  return Buffer.concat([Buffer.from([0xff, 0xd8]), ...segments,
    Buffer.from([0xff, 0xda, 0x00, 0x02, 0xff, 0xd9])]);
}

function sof(marker, width, height) {
  const payload = Buffer.alloc(9);
  payload.writeUInt8(8, 0);
  payload.writeUInt16BE(height, 1);
  payload.writeUInt16BE(width, 3);
  payload.writeUInt8(1, 5);
  payload.writeUInt8(1, 6);
  payload.writeUInt8(0x11, 7);
  return segment(marker, payload);
}

test("the frame header: exactly one SOF, 1-8192 pixels a side, equal to the declared size", () => {
  assert.deepEqual(jpegFrameSize(STRIPPED_JPEG), { width: 32, height: 24 });
  // The pixel bomb: a tiny file declaring 65535 x 65535.
  assert.equal(jpegHeaderViolation(header(sof(0xc0, 65_535, 65_535))), "dimensions");
  assert.equal(jpegHeaderViolation(header(sof(0xc2, 8193, 10))), "dimensions");
  assert.equal(jpegHeaderViolation(header(sof(0xc0, 10, 0))), "dimensions", "a DNL height");
  assert.equal(jpegHeaderViolation(header(sof(0xc2, 8192, 8192))), null);
  assert.equal(jpegHeaderViolation(header(sof(0xcf, 1, 1))), null);
  assert.equal(jpegHeaderViolation(header()), "noFrame");
  // DHT / JPG / DAC are not frame headers.
  assert.equal(jpegHeaderViolation(header(segment(0xc4, Buffer.alloc(9)))), "noFrame");
  assert.equal(jpegHeaderViolation(header(sof(0xc0, 10, 10), sof(0xc2, 10, 10))), "malformed");
  assert.equal(jpegHeaderViolation(header(segment(0xc0, Buffer.from([8, 0, 1])))), "malformed");
  assert.throws(() => assertNoImageMetadata(header(sof(0xc0, 65_535, 65_535))),
    (error) => error.details.reason === "pageMediaMetadata");
  assert.doesNotThrow(() => assertNoImageMetadata(STRIPPED_JPEG, { width: 32, height: 24 }));
  for (const declared of [{ width: 24, height: 32 }, { width: 32, height: 25 }, { width: 8192, height: 8192 }]) {
    assert.throws(() => assertNoImageMetadata(STRIPPED_JPEG, declared),
      (error) => error.details.reason === "pageMediaInvalid", JSON.stringify(declared));
  }
});

test("reserve items are exact; ids are server-derived and stable per request", () => {
  const photo = { index: 0, contentType: "image/jpeg", size: 1000, width: 10, height: 10, durationMs: null };
  assert.equal(requireReserveItems("photo", [photo]).length, 1);
  const bad = (kind, items) => assert.throws(() => requireReserveItems(kind, items),
    (error) => error.code === "invalid-argument");
  bad("photo", []);
  bad("photo", Array.from({ length: 11 }, (_, index) => ({ ...photo, index })));
  bad("photo", [{ ...photo, index: 1 }]);
  bad("photo", [{ ...photo, postId: "pp_x" }]);
  bad("photo", [{ ...photo, size: 127 }]);
  bad("photo", [{ ...photo, width: 8193 }]);
  bad("photo", [{ ...photo, durationMs: 10 }]);
  bad("photo", [{ ...photo, contentType: "image/webp" }]);
  const voice = { index: 0, contentType: "audio/mp4", size: 600, width: null, height: null, durationMs: 60_000 };
  assert.equal(requireReserveItems("voice", [voice])[0].durationMs, 60_000);
  bad("voice", [voice, { ...voice, index: 1 }]);
  bad("voice", [{ ...voice, durationMs: 60_001 }]);
  bad("voice", [{ ...voice, size: 511 }]);
  bad("voice", [{ ...voice, contentType: "audio/mpeg" }]);
  bad("video", [voice]);

  assert.equal(pagePostIdFor("u1", "req-12345678", "media"), pagePostIdFor("u1", "req-12345678", "media"));
  assert.notEqual(pagePostIdFor("u1", "req-12345678", "media"), pagePostIdFor("u1", "req-12345678", "text"));
  assert.notEqual(pagePostIdFor("u1", "req-12345678", "media"), pagePostIdFor("u2", "req-12345678", "media"));
  assert.match(pagePostIdFor("u1", "req-12345678", "text"), /^pp_[a-f0-9]{40}$/u);
  assert.match(pageMediaIdFor("u1", "req-12345678", 3), /^pm_[a-f0-9]{40}$/u);
  assert.notEqual(pageMediaIdFor("u1", "r-12345678", 0), pageMediaIdFor("u1", "r-12345678", 1));
  assert.equal(pageBudgetDay(Date.UTC(2030, 0, 2, 23, 59)), "20300102");
  assert.equal(pageBudgetId("abc", Date.UTC(2030, 0, 2)), "abc_20300102");
  assert.deepEqual(parsePagePostObjectName(`page_posts/u1/pp_${"a".repeat(40)}/pm_${"b".repeat(40)}.jpg`),
    { pageId: "u1", postId: `pp_${"a".repeat(40)}`, mediaId: `pm_${"b".repeat(40)}`, extension: "jpg" });
  assert.equal(parsePagePostObjectName("page_posts/u1/x.jpg"), null);
  assert.equal(parsePagePostObjectName(`page_posts/u1/pp_${"a".repeat(40)}/pm_${"b".repeat(40)}.png`), null);
});

test("post text: NFC, LF, emoji sequences kept; bidi overrides and controls refused", () => {
  assert.equal(normalizePostText("  a\r\nb\rc  ", "text"), "a\nb\nc");
  assert.equal(normalizePostText("é", "text"), "é");
  // ZWJ family, a flag, a keycap and ZWNJ in Persian all survive.
  for (const sample of ["👨\u200d👩\u200d👧", "🏳\ufe0f\u200d🌈", "1\ufe0f⃣", "می\u200cخواهم"]) {
    assert.equal(normalizePostText(sample, "text"), sample.normalize("NFC"));
  }
  const refused = (value, kind = "text") => assert.throws(() => normalizePostText(value, kind),
    (error) => error.code === "invalid-argument");
  refused("abc\u202edef");
  refused("abc\u2066def");
  refused("tab\there");
  refused("nul\u0000");
  refused("line\u2028sep");
  refused("b\ufeffom");
  refused("\ud800 lone surrogate");
  refused(" \u200d \n ");
  refused("x".repeat(5001));
  refused(42);
  // Media posts may have no text at all.
  assert.equal(normalizePostText("", "photo"), "");
});

test("storage.rules requires exactly the reservation keys the server writes", () => {
  const rules = fs.readFileSync(path.join(__dirname, "..", "..", "storage.rules"), "utf8");
  const block = rules.slice(rules.indexOf("match /page_posts/{pageId}/{postId}/{fileName}"));
  const hasOnly = block.slice(block.indexOf("reservation.keys().hasOnly(["));
  const keys = hasOnly.slice(hasOnly.indexOf("[") + 1, hasOnly.indexOf("]"))
    .split(",").map((key) => key.trim().replace(/'/gu, "")).filter(Boolean).sort();
  assert.deepEqual(keys, [...PAGE_MEDIA_RESERVATION_KEYS]);
  assert.match(block, /size >= 128 && size <= 4 \* 1024 \* 1024/u);
  assert.match(block, /size >= 512 && size <= 4 \* 1024 \* 1024/u);
  assert.equal(PAGE_MEDIA_RESERVATION_TTL_MS, 15 * 60 * 1000);
});

test("budgets, rates, staff roles and safety actions are the spec's", () => {
  assert.deepEqual(PAGE_DAILY_BUDGET, { posts: 10, reservations: 30, bytes: 200 * 1024 * 1024 });
  assert.deepEqual(PAGES_POST_RATE_LIMITS["pages.reserve"], { maxEvents: 20, windowMs: 60_000 });
  assert.deepEqual(PAGES_POST_RATE_LIMITS["pages.publish"], { maxEvents: 3, windowMs: 600_000 });
  assert.deepEqual(PAGES_POST_RATE_LIMITS["pages.manage"], { maxEvents: 30, windowMs: 60_000 });
  const { REPORT_STAFF_ROLES } = require("../moderation/reports");
  assert.deepEqual([...PAGE_STAFF_ROLES].sort(), [...REPORT_STAFF_ROLES].sort());
  assert.equal(PAGES_SAFETY_ACTIONS.includes("managePagePostV1.delete"), true);
});

test("deletion jobs and the open-report record are validated", () => {
  const now = { toMillis: () => 1 };
  assert.throws(() => pageMediaDeletionJob({ storagePath: "p", generation: "x", reason: "r", heldBy: null, now }));
  assert.throws(() => pageMediaDeletionJob({ storagePath: "p", generation: "1", reason: "r", heldBy: "a/b", now }));
  assert.equal(pageMediaDeletionJob({ storagePath: "p", generation: "1", reason: "r", heldBy: "rep-1", now }).heldBy,
    "rep-1");
  const snapshot = (data) => ({ exists: data !== null, data: () => data });
  assert.deepEqual(pagePostOpenReports(snapshot(null), "pp_x"), { exists: false, count: 0, lastReportId: null });
  // A malformed record fails closed: reported, report unknown.
  const malformed = pagePostOpenReports(snapshot({ count: "1" }), "pp_x");
  assert.equal(malformed.count, 1);
  assert.equal(malformed.lastReportId, null);
});

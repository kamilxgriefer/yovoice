// assertNoImageMetadata (ADR-233 §2.4 step 3, SECURITY finding S-M4). Pure.
//
// Every Page photo is re-encoded on the client without metadata (the image
// sanitiser, spec §4.5). This is the server's independent check, so an old or
// modified client can never publish GPS coordinates, a camera serial or an
// embedded thumbnail: the JPEG header is walked segment by segment up to the
// first SOS (start of scan), and the photo is refused when it carries
//
//   * any APP1-APP15 segment (Exif, XMP, ICC profiles, Photoshop IRB, MPF,
//     Adobe, …), or
//   * any COM (comment) segment,
//
// or when the header is not a well-formed JPEG header, or does not reach SOS
// within the bytes given (at most the first 256 KB: a header that long is
// refused rather than read further). APP0 (JFIF / JFXX) is the one
// application segment kept: it carries density and nothing identifying.
//
// Refusal: failed-precondition "This photo couldn't be prepared. Try again."
// {reason:"pageMediaMetadata"}.
//
// The FRAME header is checked too (audit 2026-09-28, the "pixel bomb"): the
// header must carry exactly one SOF segment (SOF0-SOF15 except DHT, JPG and
// DAC) before SOS, whose width and height are 1-8192. A publish also requires
// them to EQUAL the reservation's declared width and height, so the layout
// size a follower's app trusts is the size it decodes. A small file that
// declares 65535 x 65535 pixels is refused (pageMediaInvalid).

const { PAGE_POST_MAX_DIMENSION } = require("./post_contract");
const { PAGE_POST_ERRORS } = require("./media_contract");

const SOI = 0xd8;
const EOI = 0xd9;
const SOS = 0xda;
const COM = 0xfe;
const APP0 = 0xe0;
const APP15 = 0xef;
const TEM = 0x01;
// SOF0-SOF15 minus DHT (C4), JPG (C8) and DAC (CC).
const SOF_MARKERS = new Set([
  0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
]);

function isStandalone(marker) {
  return marker === TEM || (marker >= 0xd0 && marker <= 0xd7);
}

/// {violation, width, height}: the first reason the header is refused (null
/// when it reaches SOS carrying no metadata and one valid frame header), and
/// the frame's dimensions when one was read.
function walkJpegHeader(value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value ?? []);
  const refuse = (violation) => ({ violation, width: null, height: null });
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== SOI) return refuse("notJpeg");
  let offset = 2;
  let frame = null;
  for (;;) {
    if (offset >= bytes.length) return refuse("truncated");
    if (bytes[offset] !== 0xff) return refuse("malformed");
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    if (offset >= bytes.length) return refuse("truncated");
    const marker = bytes[offset];
    offset += 1;
    if (marker === 0x00 || marker === SOI) return refuse("malformed");
    if (marker === EOI) return refuse("noScan");
    if (marker === SOS) {
      if (frame === null) return refuse("noFrame");
      if (frame.width < 1 || frame.height < 1 ||
          frame.width > PAGE_POST_MAX_DIMENSION || frame.height > PAGE_POST_MAX_DIMENSION) {
        return { violation: "dimensions", ...frame };
      }
      return { violation: null, ...frame };
    }
    if (isStandalone(marker)) continue;
    if ((marker > APP0 && marker <= APP15) || marker === COM) return refuse("metadata");
    if (offset + 2 > bytes.length) return refuse("truncated");
    const length = bytes.readUInt16BE(offset);
    if (length < 2) return refuse("malformed");
    if (SOF_MARKERS.has(marker)) {
      // length(2) precision(1) height(2) width(2) components(1) ...
      if (frame !== null) return refuse("malformed");
      if (length < 8) return refuse("malformed");
      if (offset + 7 > bytes.length) return refuse("truncated");
      frame = { height: bytes.readUInt16BE(offset + 3), width: bytes.readUInt16BE(offset + 5) };
    }
    offset += length;
  }
}

/**
 * The first reason `bytes` is refused, or null when the header reaches SOS
 * carrying no metadata segment and exactly one frame header of 1-8192 x
 * 1-8192 pixels. Exposed for tests.
 */
function jpegHeaderViolation(value) {
  return walkJpegHeader(value).violation;
}

/// The frame dimensions {width, height} of a JPEG header, or null.
function jpegFrameSize(value) {
  const { width, height } = walkJpegHeader(value);
  return width === null ? null : { width, height };
}

/**
 * Refuses a photo whose header carries metadata or a bad frame header
 * (pageMediaMetadata) and, when `declared` is given, one whose frame size is
 * not exactly the declared {width, height} (pageMediaInvalid).
 */
function assertNoImageMetadata(bytes, declared = null) {
  const header = walkJpegHeader(bytes);
  if (header.violation !== null) throw PAGE_POST_ERRORS.mediaMetadata();
  if (declared !== null &&
      (header.width !== declared.width || header.height !== declared.height)) {
    throw PAGE_POST_ERRORS.mediaInvalid();
  }
}

module.exports = {
  assertNoImageMetadata,
  jpegFrameSize,
  jpegHeaderViolation,
};

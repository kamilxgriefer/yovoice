const { fail } = require("../integrity/guards");
const { Readable } = require("node:stream");

const MAX_SNIFF_BYTES = 4096;
// The fallback parser never downloads `mdat`. It reads only atom headers and
// bounded metadata/sample tables needed to corroborate a movie duration and
// prove that every declared chunk points into an actual media-data payload.
// The read ceiling is high enough for a normal video+audio iOS MOV, but
// low enough that an attacker cannot turn atom traversal into unbounded GCS
// requests.
const MAX_ISO_BMFF_DURATION_RANGE_READS = 160;
const MAX_ISO_BMFF_TRACKS = 8;
const MAX_ISO_BMFF_STTS_ENTRIES = 8192;
const MAX_ISO_BMFF_CTTS_ENTRIES = 100000;
const MAX_ISO_BMFF_SAMPLE_DESCRIPTIONS = 32;
const MAX_ISO_BMFF_DATA_REFERENCES = 32;
const MAX_ISO_BMFF_STSC_ENTRIES = 65536;
const MAX_ISO_BMFF_CHUNKS = 100000;
const MAX_ISO_BMFF_SAMPLES = 500000;
const MAX_ISO_BMFF_DURATION_RANGE_BYTES = 2 * 1024 * 1024;
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
  while (offset + 8 <= bytes.length && offset < MAX_SNIFF_BYTES) {
    const size32 = bytes.readUInt32BE(offset);
    const type = bytes.subarray(offset + 4, offset + 8).toString("ascii");
    let atomSize = size32;
    let headerSize = 8;
    if (size32 === 1) {
      if (offset + 16 > bytes.length) return null;
      const extended = bytes.readBigUInt64BE(offset + 8);
      if (extended < 16n || extended > BigInt(Number.MAX_SAFE_INTEGER)) return null;
      atomSize = Number(extended);
      headerSize = 16;
    } else if (size32 === 0) {
      atomSize = bytes.length - offset;
    }
    if (atomSize < headerSize) return null;
    if (type === "ftyp") {
      return atomSize >= headerSize + 4 &&
          offset + headerSize + 4 <= bytes.length
        ? bytes.subarray(
          offset + headerSize,
          offset + headerSize + 4,
        ).toString("ascii")
        : null;
    }
    if (size32 === 0) return null;
    offset += atomSize;
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
  return readGenerationBoundRange(file, 0, Math.min(size, MAX_SNIFF_BYTES));
}

async function readGenerationBoundRange(file, start, byteCount, budget = null) {
  if (!Number.isSafeInteger(start) || start < 0 ||
      !Number.isSafeInteger(byteCount) || byteCount < 1) return null;
  if (budget !== null) {
    if (!Number.isSafeInteger(budget.remaining) || budget.remaining < 1) {
      return null;
    }
    if (!Number.isSafeInteger(budget.bytesRemaining) ||
        budget.bytesRemaining < byteCount) return null;
    budget.remaining -= 1;
    budget.bytesRemaining -= byteCount;
  }
  const stream = file.createReadStream({
    start,
    end: start + byteCount - 1,
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
    return captured === byteCount ? Buffer.concat(chunks, captured) : null;
  } catch (_) {
    fail("failed-precondition", "The uploaded media header could not be verified.");
  } finally {
    stream.destroy();
  }
}

function parseIsoBmffAtomHeader(bytes, absoluteOffset, containerEnd) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 8 ||
      !Number.isSafeInteger(absoluteOffset) || absoluteOffset < 0 ||
      !Number.isSafeInteger(containerEnd) || containerEnd <= absoluteOffset) {
    return null;
  }
  let headerSize = 8;
  let atomSize = bytes.readUInt32BE(0);
  if (atomSize === 1) {
    if (bytes.length < 16) return null;
    const extendedSize = bytes.readBigUInt64BE(8);
    if (extendedSize > BigInt(Number.MAX_SAFE_INTEGER)) return null;
    atomSize = Number(extendedSize);
    headerSize = 16;
  } else if (atomSize === 0) {
    atomSize = containerEnd - absoluteOffset;
  }
  const atomEnd = absoluteOffset + atomSize;
  if (atomSize < headerSize || !Number.isSafeInteger(atomEnd) ||
      atomEnd > containerEnd) {
    return null;
  }
  return {
    headerSize,
    size: atomSize,
    type: bytes.subarray(4, 8).toString("ascii"),
  };
}

async function listIsoBmffAtoms(file, start, size, budget) {
  const end = start + size;
  if (!Number.isSafeInteger(start) || start < 0 ||
      !Number.isSafeInteger(size) || size < 8 ||
      !Number.isSafeInteger(end)) return null;
  let offset = start;
  const atoms = [];
  while (offset + 8 <= end) {
    const available = Math.min(16, end - offset);
    const bytes = await readGenerationBoundRange(
      file,
      offset,
      available,
      budget,
    );
    const atom = parseIsoBmffAtomHeader(bytes, offset, end);
    if (atom === null) return null;
    atoms.push({ ...atom, offset });
    offset += atom.size;
  }
  return offset === end ? atoms : null;
}

function exactlyOneAtom(atoms, type) {
  if (!Array.isArray(atoms)) return null;
  const matches = atoms.filter((atom) => atom.type === type);
  return matches.length === 1 ? matches[0] : null;
}

async function readIsoBmffFullBoxPrefix(file, atom, byteCount, budget) {
  const payloadSize = atom.size - atom.headerSize;
  if (payloadSize < byteCount) return null;
  return readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    byteCount,
    budget,
  );
}

function scaledDurationMs(duration, timescale) {
  if (typeof duration !== "bigint" || duration <= 0n ||
      !Number.isSafeInteger(timescale) || timescale < 1) return null;
  const durationMs = Number(
    (duration * 1000n + BigInt(Math.floor(timescale / 2))) /
      BigInt(timescale),
  );
  return Number.isSafeInteger(durationMs) && durationMs > 0
    ? durationMs
    : null;
}

async function readIsoBmffTimescaleDuration(file, atom, budget) {
  const prefixLength = Math.min(32, atom.size - atom.headerSize);
  if (prefixLength < 20) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    prefixLength,
    budget,
  );
  if (bytes === null) return null;

  const version = bytes[0];
  let timescale;
  let duration;
  if (version === 0 && bytes.length >= 20) {
    timescale = bytes.readUInt32BE(12);
    duration = BigInt(bytes.readUInt32BE(16));
    if (duration === 0xffffffffn) return null;
  } else if (version === 1 && bytes.length >= 32) {
    timescale = bytes.readUInt32BE(20);
    duration = bytes.readBigUInt64BE(24);
    if (duration === 0xffffffffffffffffn) return null;
  } else {
    return null;
  }
  if (timescale < 1) return null;
  return { duration, timescale };
}

async function readIsoBmffTrackHeaderDuration(file, atom, budget) {
  const prefixLength = Math.min(36, atom.size - atom.headerSize);
  if (prefixLength < 24) return null;
  const bytes = await readIsoBmffFullBoxPrefix(
    file,
    atom,
    prefixLength,
    budget,
  );
  if (bytes === null) return null;
  if (bytes[0] === 0 && bytes.length >= 24) {
    const duration = BigInt(bytes.readUInt32BE(20));
    return duration === 0xffffffffn ? null : duration;
  }
  if (bytes[0] === 1 && bytes.length >= 36) {
    const duration = bytes.readBigUInt64BE(28);
    return duration === 0xffffffffffffffffn ? null : duration;
  }
  return null;
}

async function readIsoBmffHandlerType(file, atom, budget) {
  const bytes = await readIsoBmffFullBoxPrefix(file, atom, 12, budget);
  return bytes === null ? null : bytes.subarray(8, 12).toString("ascii");
}

async function readIsoBmffMajorBrand(file, atom, budget) {
  if (atom.size - atom.headerSize < 8) return null;
  const bytes = await readIsoBmffFullBoxPrefix(file, atom, 4, budget);
  return bytes === null ? null : bytes.toString("ascii");
}

function isZeroFullBoxHeader(bytes) {
  return Buffer.isBuffer(bytes) && bytes.length >= 4 &&
    bytes[0] === 0 && bytes.readUIntBE(1, 3) === 0;
}

async function readIsoBmffSampleDescriptions(
  file,
  atoms,
  handlerType,
  budget,
) {
  const atom = exactlyOneAtom(atoms, "stsd");
  if (atom === null) return null;
  const payloadSize = atom.size - atom.headerSize;
  if (payloadSize < 24 || payloadSize > budget.bytesRemaining) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || !isZeroFullBoxHeader(bytes)) return null;
  const entryCount = bytes.readUInt32BE(4);
  if (entryCount < 1 || entryCount > MAX_ISO_BMFF_SAMPLE_DESCRIPTIONS) {
    return null;
  }

  const dataReferenceIndexes = [];
  let offset = 8;
  for (let index = 0; index < entryCount; index += 1) {
    if (offset + 16 > bytes.length) return null;
    const entrySize = bytes.readUInt32BE(offset);
    const entryEnd = offset + entrySize;
    const minimumSize = handlerType === "vide" ? 86 : 36;
    if (entrySize < minimumSize || !Number.isSafeInteger(entryEnd) ||
        entryEnd > bytes.length) return null;
    const format = bytes.subarray(offset + 4, offset + 8);
    const dataReferenceIndex = bytes.readUInt16BE(offset + 14);
    if ([...format].some((value) => value < 0x20 || value > 0x7e) ||
        dataReferenceIndex < 1) return null;
    if (handlerType === "vide") {
      if (bytes.readUInt16BE(offset + 32) < 1 ||
          bytes.readUInt16BE(offset + 34) < 1 ||
          bytes.readUInt16BE(offset + 48) < 1) return null;
    } else if (isIsoBmffAudioHandler(handlerType)) {
      if (bytes.readUInt16BE(offset + 24) < 1 ||
          bytes.readUInt16BE(offset + 26) < 1 ||
          bytes.readUInt32BE(offset + 32) < 1) return null;
    }
    dataReferenceIndexes.push(dataReferenceIndex);
    offset = entryEnd;
  }
  return offset === bytes.length ? dataReferenceIndexes : null;
}

async function readIsoBmffDataReferences(
  file,
  minfAtoms,
  allowQuickTimeAlias,
  budget,
) {
  const dinf = exactlyOneAtom(minfAtoms, "dinf");
  if (dinf === null) return null;
  const dinfAtoms = await listIsoBmffAtoms(
    file,
    dinf.offset + dinf.headerSize,
    dinf.size - dinf.headerSize,
    budget,
  );
  const dref = exactlyOneAtom(dinfAtoms, "dref");
  if (dref === null) return null;
  const payloadSize = dref.size - dref.headerSize;
  if (payloadSize < 20) return null;
  const prefix = await readIsoBmffFullBoxPrefix(file, dref, 8, budget);
  if (prefix === null || !isZeroFullBoxHeader(prefix)) return null;
  const entryCount = prefix.readUInt32BE(4);
  if (entryCount < 1 || entryCount > MAX_ISO_BMFF_DATA_REFERENCES) {
    return null;
  }
  const entries = await listIsoBmffAtoms(
    file,
    dref.offset + dref.headerSize + 8,
    payloadSize - 8,
    budget,
  );
  if (!Array.isArray(entries) || entries.length !== entryCount) return null;

  const selfContained = [];
  for (const entry of entries) {
    const entryPayloadSize = entry.size - entry.headerSize;
    const supportedType = entry.type === "url " ||
      (allowQuickTimeAlias && entry.type === "alis");
    if (!supportedType || entryPayloadSize < 4) {
      selfContained.push(false);
      continue;
    }
    const fullBox = await readIsoBmffFullBoxPrefix(file, entry, 4, budget);
    if (fullBox === null || fullBox[0] !== 0) return null;
    selfContained.push(
      entryPayloadSize === 4 && fullBox.readUIntBE(1, 3) === 1,
    );
  }
  return selfContained;
}

async function readIsoBmffSampleSizes(file, atoms, budget) {
  const stsz = exactlyOneAtom(atoms, "stsz");
  const stz2 = exactlyOneAtom(atoms, "stz2");
  if ((stsz === null) === (stz2 === null)) return null;

  const atom = stsz ?? stz2;
  const payloadSize = atom.size - atom.headerSize;
  if (payloadSize < 12 || payloadSize > budget.bytesRemaining) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || !isZeroFullBoxHeader(bytes)) return null;
  const sampleCount = bytes.readUInt32BE(8);
  if (sampleCount < 1 || sampleCount > MAX_ISO_BMFF_SAMPLES ||
      sampleCount > budget.samplesRemaining) return null;
  budget.samplesRemaining -= sampleCount;

  if (stsz !== null) {
    const fixedSampleSize = bytes.readUInt32BE(4);
    const expectedPayloadSize = fixedSampleSize === 0
      ? 12 + sampleCount * 4
      : 12;
    if (payloadSize !== expectedPayloadSize) return null;
    if (fixedSampleSize > 0) {
      return { fixedSampleSize, sampleCount, sizes: null };
    }
    const sizes = new Uint32Array(sampleCount);
    for (let index = 0; index < sampleCount; index += 1) {
      const value = bytes.readUInt32BE(12 + index * 4);
      if (value < 1) return null;
      sizes[index] = value;
    }
    return { fixedSampleSize: 0, sampleCount, sizes };
  }

  const fieldSize = bytes[7];
  if (bytes.readUIntBE(4, 3) !== 0 ||
      (fieldSize !== 4 && fieldSize !== 8 && fieldSize !== 16)) return null;
  const expectedPayloadSize = 12 + Math.ceil((sampleCount * fieldSize) / 8);
  if (payloadSize !== expectedPayloadSize) return null;
  const sizes = new Uint32Array(sampleCount);
  for (let index = 0; index < sampleCount; index += 1) {
    let value;
    if (fieldSize === 4) {
      const packed = bytes[12 + Math.floor(index / 2)];
      value = index % 2 === 0 ? packed >>> 4 : packed & 0x0f;
    } else if (fieldSize === 8) {
      value = bytes[12 + index];
    } else {
      value = bytes.readUInt16BE(12 + index * 2);
    }
    if (value < 1) return null;
    sizes[index] = value;
  }
  return { fixedSampleSize: 0, sampleCount, sizes };
}

async function readIsoBmffSampleToChunk(
  file,
  atoms,
  descriptionCount,
  budget,
) {
  const atom = exactlyOneAtom(atoms, "stsc");
  if (atom === null) return null;
  const payloadSize = atom.size - atom.headerSize;
  const maxPayloadSize = 8 + MAX_ISO_BMFF_STSC_ENTRIES * 12;
  if (payloadSize < 20 || payloadSize > maxPayloadSize ||
      payloadSize > budget.bytesRemaining) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || !isZeroFullBoxHeader(bytes)) return null;
  const entryCount = bytes.readUInt32BE(4);
  if (entryCount < 1 || entryCount > MAX_ISO_BMFF_STSC_ENTRIES ||
      payloadSize !== 8 + entryCount * 12) return null;
  const entries = [];
  let priorFirstChunk = 0;
  for (let index = 0; index < entryCount; index += 1) {
    const offset = 8 + index * 12;
    const firstChunk = bytes.readUInt32BE(offset);
    const samplesPerChunk = bytes.readUInt32BE(offset + 4);
    const sampleDescriptionIndex = bytes.readUInt32BE(offset + 8);
    if (firstChunk < 1 || firstChunk <= priorFirstChunk ||
        samplesPerChunk < 1 || sampleDescriptionIndex < 1 ||
        sampleDescriptionIndex > descriptionCount) return null;
    entries.push({ firstChunk, sampleDescriptionIndex, samplesPerChunk });
    priorFirstChunk = firstChunk;
  }
  return entries[0].firstChunk === 1 ? entries : null;
}

async function readIsoBmffChunkOffsets(file, atoms, fileSize, budget) {
  const stco = exactlyOneAtom(atoms, "stco");
  const co64 = exactlyOneAtom(atoms, "co64");
  if ((stco === null) === (co64 === null)) return null;
  const atom = stco ?? co64;
  const payloadSize = atom.size - atom.headerSize;
  const entrySize = stco === null ? 8 : 4;
  if (payloadSize < 8 + entrySize || payloadSize > budget.bytesRemaining) {
    return null;
  }
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || !isZeroFullBoxHeader(bytes)) return null;
  const entryCount = bytes.readUInt32BE(4);
  if (entryCount < 1 || entryCount > MAX_ISO_BMFF_CHUNKS ||
      entryCount > budget.chunksRemaining ||
      payloadSize !== 8 + entryCount * entrySize) return null;
  budget.chunksRemaining -= entryCount;
  const offsets = [];
  for (let index = 0; index < entryCount; index += 1) {
    const position = 8 + index * entrySize;
    const value = entrySize === 4
      ? BigInt(bytes.readUInt32BE(position))
      : bytes.readBigUInt64BE(position);
    if (value >= BigInt(fileSize)) return null;
    offsets.push(value);
  }
  return offsets;
}

function findContainingMdat(rangeStart, rangeEnd, mdatRanges) {
  return mdatRanges.some((mdat) =>
    rangeStart >= mdat.start && rangeEnd <= mdat.end);
}

async function readIsoBmffSampleMap(
  file,
  atoms,
  handlerType,
  dataReferences,
  fileSize,
  mdatRanges,
  budget,
) {
  const sampleDescriptions = await readIsoBmffSampleDescriptions(
    file,
    atoms,
    handlerType,
    budget,
  );
  if (sampleDescriptions === null) return null;
  const sampleSizes = await readIsoBmffSampleSizes(file, atoms, budget);
  if (sampleSizes === null) return null;
  const sampleToChunk = await readIsoBmffSampleToChunk(
    file,
    atoms,
    sampleDescriptions.length,
    budget,
  );
  if (sampleToChunk === null) return null;
  const chunkOffsets = await readIsoBmffChunkOffsets(
    file,
    atoms,
    fileSize,
    budget,
  );
  if (chunkOffsets === null ||
      sampleToChunk.at(-1).firstChunk > chunkOffsets.length) return null;

  const ranges = [];
  let runIndex = 0;
  let sampleIndex = 0;
  for (let chunkIndex = 1; chunkIndex <= chunkOffsets.length; chunkIndex += 1) {
    while (runIndex + 1 < sampleToChunk.length &&
        sampleToChunk[runIndex + 1].firstChunk <= chunkIndex) {
      runIndex += 1;
    }
    const samplesInChunk = sampleToChunk[runIndex].samplesPerChunk;
    const descriptionIndex = sampleToChunk[runIndex].sampleDescriptionIndex;
    const dataReferenceIndex = sampleDescriptions[descriptionIndex - 1];
    if (dataReferences[dataReferenceIndex - 1] !== true) return null;
    if (sampleIndex + samplesInChunk > sampleSizes.sampleCount) return null;
    let chunkSize = 0n;
    if (sampleSizes.fixedSampleSize > 0) {
      chunkSize = BigInt(sampleSizes.fixedSampleSize) * BigInt(samplesInChunk);
    } else {
      for (let index = 0; index < samplesInChunk; index += 1) {
        chunkSize += BigInt(sampleSizes.sizes[sampleIndex + index]);
      }
    }
    if (chunkSize < 1n) return null;
    const start = chunkOffsets[chunkIndex - 1];
    const end = start + chunkSize;
    if (end > BigInt(fileSize) ||
        !findContainingMdat(start, end, mdatRanges)) return null;
    ranges.push({ start, end });
    sampleIndex += samplesInChunk;
  }
  return sampleIndex === sampleSizes.sampleCount
    ? { ranges, sampleCount: sampleSizes.sampleCount }
    : null;
}

async function readIsoBmffDecodeTimeline(file, atom, budget) {
  const payloadSize = atom.size - atom.headerSize;
  const maxPayloadSize = 8 + MAX_ISO_BMFF_STTS_ENTRIES * 8;
  if (payloadSize < 16 || payloadSize > maxPayloadSize) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null) return null;

  const entryCount = bytes.readUInt32BE(4);
  if (entryCount < 1 || entryCount > MAX_ISO_BMFF_STTS_ENTRIES ||
      payloadSize !== 8 + entryCount * 8) return null;

  let sampleCount = 0n;
  let duration = 0n;
  for (let index = 0; index < entryCount; index += 1) {
    const offset = 8 + index * 8;
    const runSampleCount = BigInt(bytes.readUInt32BE(offset));
    const sampleDelta = BigInt(bytes.readUInt32BE(offset + 4));
    if (runSampleCount < 1n || sampleDelta < 1n) return null;
    sampleCount += runSampleCount;
    duration += runSampleCount * sampleDelta;
  }
  return duration > 0n ? { duration, sampleCount } : null;
}

async function readIsoBmffCompositionTimeline(
  file,
  atoms,
  expectedSampleCount,
  signedVersionZeroOffsets,
  budget,
) {
  const matches = Array.isArray(atoms)
    ? atoms.filter((atom) => atom.type === "ctts")
    : [];
  if (matches.length === 0) return { maxOffset: 0n, minOffset: 0n };
  if (matches.length !== 1) return null;

  const atom = matches[0];
  const payloadSize = atom.size - atom.headerSize;
  const maxPayloadSize = 8 + MAX_ISO_BMFF_CTTS_ENTRIES * 8;
  if (payloadSize < 16 || payloadSize > maxPayloadSize) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || (bytes[0] !== 0 && bytes[0] !== 1) ||
      bytes.readUIntBE(1, 3) !== 0) return null;

  const entryCount = bytes.readUInt32BE(4);
  if (entryCount < 1 || entryCount > MAX_ISO_BMFF_CTTS_ENTRIES ||
      payloadSize !== 8 + entryCount * 8) return null;

  let sampleCount = 0n;
  let maxOffset = null;
  let minOffset = null;
  for (let index = 0; index < entryCount; index += 1) {
    const offset = 8 + index * 8;
    const runSampleCount = BigInt(bytes.readUInt32BE(offset));
    if (runSampleCount < 1n) return null;
    sampleCount += runSampleCount;
    const sampleOffset = bytes[0] === 0 && !signedVersionZeroOffsets
      ? BigInt(bytes.readUInt32BE(offset + 4))
      : BigInt(bytes.readInt32BE(offset + 4));
    if (maxOffset === null || sampleOffset > maxOffset) {
      maxOffset = sampleOffset;
    }
    if (minOffset === null || sampleOffset < minOffset) {
      minOffset = sampleOffset;
    }
  }
  return sampleCount === expectedSampleCount &&
      maxOffset !== null && minOffset !== null
    ? { maxOffset, minOffset }
    : null;
}

async function readIsoBmffCompositionSummary(file, atoms, budget) {
  const matches = Array.isArray(atoms)
    ? atoms.filter((atom) => atom.type === "cslg")
    : [];
  if (matches.length === 0) return {
    compositionEnd: 0n,
    compositionStart: 0n,
    compositionToDtsShift: 0n,
    greatestDelta: null,
    leastDelta: null,
    present: false,
  };
  if (matches.length !== 1) return null;

  const atom = matches[0];
  const payloadSize = atom.size - atom.headerSize;
  if (payloadSize !== 24 && payloadSize !== 44) return null;
  const bytes = await readGenerationBoundRange(
    file,
    atom.offset + atom.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || bytes.readUIntBE(1, 3) !== 0) return null;
  if (bytes[0] === 0 && payloadSize === 24) {
    const compositionToDtsShift = BigInt(bytes.readInt32BE(4));
    const compositionEnd = BigInt(bytes.readInt32BE(20));
    const compositionStart = BigInt(bytes.readInt32BE(16));
    const leastDelta = BigInt(bytes.readInt32BE(8));
    const greatestDelta = BigInt(bytes.readInt32BE(12));
    return compositionToDtsShift >= 0n && compositionEnd > compositionStart &&
        leastDelta <= greatestDelta
      ? {
        compositionEnd,
        compositionStart,
        compositionToDtsShift,
        greatestDelta,
        leastDelta,
        present: true,
      }
      : null;
  }
  if (bytes[0] === 1 && payloadSize === 44) {
    const compositionToDtsShift = bytes.readBigInt64BE(4);
    const compositionEnd = bytes.readBigInt64BE(36);
    const compositionStart = bytes.readBigInt64BE(28);
    const leastDelta = bytes.readBigInt64BE(12);
    const greatestDelta = bytes.readBigInt64BE(20);
    return compositionToDtsShift >= 0n && compositionEnd > compositionStart &&
        leastDelta <= greatestDelta
      ? {
        compositionEnd,
        compositionStart,
        compositionToDtsShift,
        greatestDelta,
        leastDelta,
        present: true,
      }
      : null;
  }
  return null;
}

async function readIsoBmffEditDuration(file, trakAtoms, budget) {
  const edits = Array.isArray(trakAtoms)
    ? trakAtoms.filter((atom) => atom.type === "edts")
    : [];
  if (edits.length === 0) return 0n;
  if (edits.length !== 1) return null;
  const edts = edits[0];
  const atoms = await listIsoBmffAtoms(
    file,
    edts.offset + edts.headerSize,
    edts.size - edts.headerSize,
    budget,
  );
  const elst = exactlyOneAtom(atoms, "elst");
  if (elst === null) return null;
  const payloadSize = elst.size - elst.headerSize;
  if (payloadSize < 20 || payloadSize > 8 + 64 * 20) return null;
  const bytes = await readGenerationBoundRange(
    file,
    elst.offset + elst.headerSize,
    payloadSize,
    budget,
  );
  if (bytes === null || (bytes[0] !== 0 && bytes[0] !== 1) ||
      bytes.readUIntBE(1, 3) !== 0) return null;
  const entryCount = bytes.readUInt32BE(4);
  const entrySize = bytes[0] === 0 ? 12 : 20;
  if (entryCount < 1 || entryCount > 64 ||
      payloadSize !== 8 + entryCount * entrySize) return null;

  let duration = 0n;
  for (let index = 0; index < entryCount; index += 1) {
    const offset = 8 + index * entrySize;
    const segmentDuration = bytes[0] === 0
      ? BigInt(bytes.readUInt32BE(offset))
      : bytes.readBigUInt64BE(offset);
    const mediaTime = bytes[0] === 0
      ? BigInt(bytes.readInt32BE(offset + 4))
      : bytes.readBigInt64BE(offset + 8);
    const rateOffset = offset + (bytes[0] === 0 ? 8 : 16);
    if (mediaTime < -1n || bytes.readInt16BE(rateOffset) !== 1 ||
        bytes.readInt16BE(rateOffset + 2) !== 0) return null;
    duration += segmentDuration;
  }
  return duration > 0n ? duration : null;
}

function isIsoBmffAudioHandler(handlerType) {
  // QuickTime historically used `audi`; ISO Base Media standardized `soun`.
  // music-metadata recognizes both, so the corroborator must do the same.
  return handlerType === "audi" || handlerType === "soun";
}

function isIsoBmffMediaHandler(handlerType) {
  return handlerType === "vide" || isIsoBmffAudioHandler(handlerType);
}

async function readIsoBmffMediaTrack(
  file,
  trak,
  movieTimescale,
  signedVersionZeroOffsets,
  fileSize,
  mdatRanges,
  budget,
) {
  const trakAtoms = await listIsoBmffAtoms(
    file,
    trak.offset + trak.headerSize,
    trak.size - trak.headerSize,
    budget,
  );
  const tkhd = exactlyOneAtom(trakAtoms, "tkhd");
  const mdia = exactlyOneAtom(trakAtoms, "mdia");
  if (tkhd === null || mdia === null) return null;

  const mdiaAtoms = await listIsoBmffAtoms(
    file,
    mdia.offset + mdia.headerSize,
    mdia.size - mdia.headerSize,
    budget,
  );
  const mdhd = exactlyOneAtom(mdiaAtoms, "mdhd");
  const hdlr = exactlyOneAtom(mdiaAtoms, "hdlr");
  const minf = exactlyOneAtom(mdiaAtoms, "minf");
  if (mdhd === null || hdlr === null || minf === null) return null;

  const handlerType = await readIsoBmffHandlerType(file, hdlr, budget);
  const isMediaTrack = isIsoBmffMediaHandler(handlerType);
  if (!isMediaTrack) {
    return { durationMs: 0, handlerType };
  }

  const trackHeaderDuration = await readIsoBmffTrackHeaderDuration(
    file,
    tkhd,
    budget,
  );
  const editDuration = await readIsoBmffEditDuration(file, trakAtoms, budget);
  if (trackHeaderDuration === null || editDuration === null) return null;

  const mediaHeader = await readIsoBmffTimescaleDuration(
    file,
    mdhd,
    budget,
  );
  if (mediaHeader === null) return null;

  const minfAtoms = await listIsoBmffAtoms(
    file,
    minf.offset + minf.headerSize,
    minf.size - minf.headerSize,
    budget,
  );
  const dataReferences = await readIsoBmffDataReferences(
    file,
    minfAtoms,
    signedVersionZeroOffsets,
    budget,
  );
  if (dataReferences === null) return null;
  const stbl = exactlyOneAtom(minfAtoms, "stbl");
  if (stbl === null) return null;
  const stblAtoms = await listIsoBmffAtoms(
    file,
    stbl.offset + stbl.headerSize,
    stbl.size - stbl.headerSize,
    budget,
  );
  const stts = exactlyOneAtom(stblAtoms, "stts");
  if (stts === null) return null;

  const decodeTimeline = await readIsoBmffDecodeTimeline(file, stts, budget);
  const sampleMap = await readIsoBmffSampleMap(
    file,
    stblAtoms,
    handlerType,
    dataReferences,
    fileSize,
    mdatRanges,
    budget,
  );
  if (decodeTimeline === null || sampleMap === null ||
      decodeTimeline.sampleCount !== BigInt(sampleMap.sampleCount)) return null;
  const compositionSummary = await readIsoBmffCompositionSummary(
    file,
    stblAtoms,
    budget,
  );
  const compositionTimeline = await readIsoBmffCompositionTimeline(
    file,
    stblAtoms,
    BigInt(sampleMap.sampleCount),
    signedVersionZeroOffsets,
    budget,
  );
  if (compositionTimeline === null || compositionSummary === null) return null;
  if (signedVersionZeroOffsets && compositionTimeline.minOffset < 0n &&
      !compositionSummary.present) return null;
  if (compositionSummary.leastDelta !== null &&
      (compositionSummary.leastDelta !== compositionTimeline.minOffset ||
        compositionSummary.greatestDelta !== compositionTimeline.maxOffset)) {
    return null;
  }

  const rawDurationCandidates = [
    { duration: trackHeaderDuration, timescale: movieTimescale },
    { duration: editDuration, timescale: movieTimescale },
    { duration: mediaHeader.duration, timescale: mediaHeader.timescale },
    { duration: decodeTimeline.duration, timescale: mediaHeader.timescale },
    {
      duration: decodeTimeline.duration +
        (compositionTimeline.maxOffset > 0n
          ? compositionTimeline.maxOffset
          : 0n),
      timescale: mediaHeader.timescale,
    },
    {
      duration: decodeTimeline.duration +
        (compositionTimeline.maxOffset - compositionTimeline.minOffset),
      timescale: mediaHeader.timescale,
    },
    {
      duration: decodeTimeline.duration +
        compositionSummary.compositionToDtsShift,
      timescale: mediaHeader.timescale,
    },
    {
      duration: compositionSummary.compositionEnd,
      timescale: mediaHeader.timescale,
    },
    {
      duration: compositionSummary.compositionEnd -
        compositionSummary.compositionStart,
      timescale: mediaHeader.timescale,
    },
  ];
  const durationCandidates = [];
  for (const candidate of rawDurationCandidates) {
    if (candidate.duration === 0n) continue;
    const durationMs = scaledDurationMs(
      candidate.duration,
      candidate.timescale,
    );
    // Every positive duration field/table is an attacker-controlled claim.
    // Silently dropping one that exceeds JS's safe integer range would let a
    // shorter sibling header become authoritative, so overflow fails closed.
    if (durationMs === null) return null;
    durationCandidates.push(durationMs);
  }
  if (durationCandidates.length < 1) return null;
  return {
    chunkRanges: sampleMap.ranges,
    durationMs: Math.max(...durationCandidates),
    handlerType,
  };
}

/**
 * Corroborates the movie duration against every playable track. In particular,
 * an uploaded `mvhd` value is not authority by itself: each audio/video track
 * must have a complete `mdhd` + `stts` timeline, a nonempty `stsd`, and a
 * coherent `stsc` + `stco`/`co64` + `stsz`/`stz2` sample map contained in an
 * `mdat`. The conservative maximum also includes `tkhd`, so changing one
 * convenient header cannot understate the media's playable duration.
 *
 * `music-metadata` currently recognizes Apple QuickTime/HEVC tracks but can
 * omit their duration, and for other ISO-BMFF files can report only one
 * track's duration. This bounded parser therefore corroborates every ISO-BMFF
 * result, whether the general parser supplied a duration or not. Malformed,
 * fragmented, ambiguous or unusually complex files fail closed and must be
 * re-encoded client-side.
 */
async function readTrustedIsoBmffTimeline(file, size) {
  if (!Number.isSafeInteger(size) || size < 8) return null;
  const budget = {
    chunksRemaining: MAX_ISO_BMFF_CHUNKS,
    remaining: MAX_ISO_BMFF_DURATION_RANGE_READS,
    bytesRemaining: MAX_ISO_BMFF_DURATION_RANGE_BYTES,
    samplesRemaining: MAX_ISO_BMFF_SAMPLES,
  };
  const rootAtoms = await listIsoBmffAtoms(file, 0, size, budget);
  if (!Array.isArray(rootAtoms) || rootAtoms.some(
    (atom) => atom.type === "moof" || atom.type === "mfra",
  )) return null;
  const moov = exactlyOneAtom(rootAtoms, "moov");
  const ftyp = exactlyOneAtom(rootAtoms, "ftyp");
  if (moov === null || ftyp === null) return null;
  const mdats = rootAtoms.filter((atom) => atom.type === "mdat");
  if (mdats.length < 1 || mdats.some(
    (atom) => atom.size <= atom.headerSize,
  )) return null;
  const mdatRanges = mdats.map((atom) => ({
    start: BigInt(atom.offset + atom.headerSize),
    end: BigInt(atom.offset + atom.size),
  }));
  const majorBrand = await readIsoBmffMajorBrand(file, ftyp, budget);
  if (majorBrand === null) return null;
  const moovAtoms = await listIsoBmffAtoms(
    file,
    moov.offset + moov.headerSize,
    moov.size - moov.headerSize,
    budget,
  );
  const mvhd = exactlyOneAtom(moovAtoms, "mvhd");
  if (!Array.isArray(moovAtoms) || moovAtoms.some(
    (atom) => atom.type === "mvex",
  )) return null;
  const tracks = Array.isArray(moovAtoms)
    ? moovAtoms.filter((atom) => atom.type === "trak")
    : [];
  if (mvhd === null || tracks.length < 1 || tracks.length > MAX_ISO_BMFF_TRACKS) {
    return null;
  }

  const movieHeader = await readIsoBmffTimescaleDuration(file, mvhd, budget);
  if (movieHeader === null) return null;
  const movieDurationMs = scaledDurationMs(
    movieHeader.duration,
    movieHeader.timescale,
  );
  if (movieDurationMs === null) return null;

  const parsedTracks = [];
  // Keep range-budget mutation sequential and deterministic. Parallel reads
  // could race the shared ceiling and make malformed inputs nondeterministic.
  for (const track of tracks) {
    const parsed = await readIsoBmffMediaTrack(
      file,
      track,
      movieHeader.timescale,
      majorBrand === "qt  ",
      size,
      mdatRanges,
      budget,
    );
    if (parsed === null) return null;
    parsedTracks.push(parsed);
  }
  const mediaTracks = parsedTracks.filter(
    (track) => isIsoBmffMediaHandler(track.handlerType),
  );
  if (mediaTracks.length < 1) return null;
  const chunkRanges = mediaTracks.flatMap((track) => track.chunkRanges);
  chunkRanges.sort((left, right) =>
    left.start < right.start ? -1 : left.start > right.start ? 1 : 0);
  for (let index = 1; index < chunkRanges.length; index += 1) {
    if (chunkRanges[index].start < chunkRanges[index - 1].end) return null;
  }
  return {
    durationMs: Math.max(
      movieDurationMs,
      ...mediaTracks.map((track) => track.durationMs),
    ),
    hasAudio: mediaTracks.some((track) =>
      isIsoBmffAudioHandler(track.handlerType)),
    hasVideo: mediaTracks.some((track) => track.handlerType === "vide"),
  };
}

async function readTrustedIsoBmffDurationMs(file, size) {
  const timeline = await readTrustedIsoBmffTimeline(file, size);
  return timeline?.durationMs ?? null;
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
function createTrustedGcsMediaProbe(bucket, dependencies = {}) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  const injectedParseWebStream = dependencies.parseWebStream;
  if (injectedParseWebStream !== undefined &&
      typeof injectedParseWebStream !== "function") {
    throw new TypeError("parseWebStream must be a function when provided.");
  }
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
    let parseWebStream = injectedParseWebStream;
    if (parseWebStream === undefined) {
      try {
        ({ parseWebStream } = await import("music-metadata"));
      } catch (_) {
        fail(
          "failed-precondition",
          "The trusted video/audio probe is not installed on this build.",
        );
      }
    }
    const stream = file.createReadStream({ validation: false });
    try {
      const metadata = await parseWebStream(
        Readable.toWeb(stream),
        { mimeType: parserContentType(header), size },
        { duration: true, skipCovers: true },
      );
      const seconds = metadata?.format?.duration;
      const isoBmffTimeline = header.family === "iso-bmff"
        ? await readTrustedIsoBmffTimeline(file, size)
        : null;
      if (header.family === "iso-bmff" && isoBmffTimeline === null) {
        fail("failed-precondition", "The uploaded media duration is unreadable.");
      }
      let verifiedHasAudio = metadata?.format?.hasAudio === true;
      let verifiedHasVideo = metadata?.format?.hasVideo === true;
      if (isoBmffTimeline !== null) {
        const allowsKnownIsoBmffAudioFalsePositive =
          verifiedHasAudio && !isoBmffTimeline.hasAudio &&
          verifiedHasVideo && isoBmffTimeline.hasVideo;
        if (verifiedHasVideo !== isoBmffTimeline.hasVideo ||
            (verifiedHasAudio !== isoBmffTimeline.hasAudio &&
              !allowsKnownIsoBmffAudioFalsePositive)) {
          fail("failed-precondition", "The uploaded media tracks are unreadable.");
        }
        // ISO-BMFF handler tracks are authoritative after the exact sample
        // tables above have been validated. music-metadata 11.15 can report
        // `hasAudio: true` for a video-only ISO-BMFF file, so keep only that
        // false-positive compatibility direction. Every omission or
        // hidden video direction fails above rather than becoming audio-only.
        verifiedHasAudio = isoBmffTimeline.hasAudio;
        verifiedHasVideo = isoBmffTimeline.hasVideo;
      }
      let parsedDurationMs = null;
      if (Number.isFinite(seconds) && seconds > 0) {
        parsedDurationMs = Math.round(seconds * 1000);
        if (!Number.isSafeInteger(parsedDurationMs) || parsedDurationMs < 1) {
          fail("failed-precondition", "The uploaded media duration is unreadable.");
        }
      }
      const durationCandidates = [
        parsedDurationMs,
        isoBmffTimeline?.durationMs,
      ].filter((value) => Number.isSafeInteger(value) && value > 0);
      const durationMs = durationCandidates.length > 0
        ? Math.max(...durationCandidates)
        : null;
      if (!Number.isSafeInteger(durationMs) || durationMs < 1) {
        fail("failed-precondition", "The uploaded media duration is unreadable.");
      }
      const actualContentType = detectedContentType(header, {
        hasAudio: verifiedHasAudio,
        hasVideo: verifiedHasVideo,
      });
      if (actualContentType === null) {
        fail("failed-precondition", "The uploaded media tracks are unreadable.");
      }
      return {
        detectedContentType: actualContentType,
        durationMs,
        generation,
        hasAudio: verifiedHasAudio,
        hasVideo: verifiedHasVideo,
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
  MAX_ISO_BMFF_DURATION_RANGE_READS,
  TRUSTED_MEDIA_PROBE_CONTENT_TYPES,
  createReelMediaProbe,
  createTrustedGcsMediaProbe,
  readTrustedIsoBmffDurationMs,
  sniffTrustedMediaHeader,
  supportsTrustedMediaProbeContentType,
};

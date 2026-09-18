const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { Readable } = require("node:stream");
const { test } = require("node:test");

const { fragmentedMp4 } = require("./fixtures/fragmented_mp4");

const {
  MAX_ISO_BMFF_DURATION_RANGE_READS,
  MAX_ISO_BMFF_FRAGMENTS,
  TRUSTED_MEDIA_PROBE_CONTENT_TYPES,
  createReelMediaProbe,
  createTrustedGcsMediaProbe,
  readTrustedIsoBmffDurationMs,
  sniffTrustedMediaHeader,
  supportsTrustedMediaProbeContentType,
} = require("../reels/probe");

function oneSecondWave() {
  const sampleRate = 8000;
  const dataLength = sampleRate * 2;
  const bytes = Buffer.alloc(44 + dataLength);
  bytes.write("RIFF", 0, "ascii");
  bytes.writeUInt32LE(36 + dataLength, 4);
  bytes.write("WAVE", 8, "ascii");
  bytes.write("fmt ", 12, "ascii");
  bytes.writeUInt32LE(16, 16);
  bytes.writeUInt16LE(1, 20);
  bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(sampleRate, 24);
  bytes.writeUInt32LE(sampleRate * 2, 28);
  bytes.writeUInt16LE(2, 32);
  bytes.writeUInt16LE(16, 34);
  bytes.write("data", 36, "ascii");
  bytes.writeUInt32LE(dataLength, 40);
  return bytes;
}

function atom(type, payload) {
  const value = Buffer.alloc(8 + payload.length);
  value.writeUInt32BE(value.length, 0);
  value.write(type, 4, 4, "ascii");
  payload.copy(value, 8);
  return value;
}

function sampleDescriptionAtom(handlerType, dataReferenceIndex = 1) {
  const isVideo = handlerType === "vide";
  const entry = Buffer.alloc(isVideo ? 86 : 36);
  entry.writeUInt32BE(entry.length, 0);
  entry.write(isVideo ? "hvc1" : "mp4a", 4, 4, "ascii");
  entry.writeUInt16BE(dataReferenceIndex, 14);
  if (isVideo) {
    entry.writeUInt16BE(16, 32);
    entry.writeUInt16BE(16, 34);
    entry.writeUInt32BE(0x00480000, 36);
    entry.writeUInt32BE(0x00480000, 40);
    entry.writeUInt16BE(1, 48);
    entry.writeUInt16BE(24, 82);
    entry.writeInt16BE(-1, 84);
  } else {
    entry.writeUInt16BE(2, 24);
    entry.writeUInt16BE(16, 26);
    entry.writeUInt32BE(48_000 * 65_536, 32);
  }
  const payload = Buffer.alloc(8 + entry.length);
  payload.writeUInt32BE(1, 4);
  entry.copy(payload, 8);
  return atom("stsd", payload);
}

function dataInformationAtom(mode = "self-contained") {
  if (mode === "missing") return null;
  const external = mode === "external" || mode === "external-alias";
  const urlPayload = external
    ? Buffer.concat([
      Buffer.alloc(4),
      Buffer.from("https://media.example.invalid/video.mov\0", "utf8"),
    ])
    : mode === "alias-not-self-contained"
      ? Buffer.alloc(4)
      : Buffer.from([0, 0, 0, 1]);
  const alias = mode === "quicktime-alias" ||
    mode === "alias-not-self-contained" || mode === "external-alias";
  const drefHeader = Buffer.alloc(8);
  drefHeader.writeUInt32BE(1, 4);
  return atom(
    "dinf",
    atom("dref", Buffer.concat([
      drefHeader,
      atom(alias ? "alis" : "url ", urlPayload),
    ])),
  );
}

function structuralSampleAtoms({
  dataReferenceIndex = 1,
  handlerType,
  sampleTableCount,
  chunkOffset,
}) {
  const stscPayload = Buffer.alloc(20);
  stscPayload.writeUInt32BE(1, 4);
  stscPayload.writeUInt32BE(1, 8);
  stscPayload.writeUInt32BE(sampleTableCount, 12);
  stscPayload.writeUInt32BE(1, 16);
  const stszPayload = Buffer.alloc(12);
  stszPayload.writeUInt32BE(1, 4);
  stszPayload.writeUInt32BE(sampleTableCount, 8);
  const stcoPayload = Buffer.alloc(12);
  stcoPayload.writeUInt32BE(1, 4);
  stcoPayload.writeUInt32BE(chunkOffset, 8);
  return [
    sampleDescriptionAtom(handlerType, dataReferenceIndex),
    atom("stsc", stscPayload),
    atom("stsz", stszPayload),
    atom("stco", stcoPayload),
  ];
}

function basicTimedTrackAtom({
  handlerType,
  trackDuration,
  mediaTimescale,
  mediaDuration,
  sampleCount,
  sampleTableCount = sampleCount,
  sampleDelta,
  chunkOffset = 0,
  dataReferenceIndex = 1,
  dataReferenceMode = "self-contained",
  trackId = 2,
}) {
  const tkhdPayload = Buffer.alloc(84);
  tkhdPayload.writeUInt32BE(trackId, 12);
  tkhdPayload.writeUInt32BE(trackDuration, 20);
  const mdhdPayload = Buffer.alloc(24);
  mdhdPayload.writeUInt32BE(mediaTimescale, 12);
  mdhdPayload.writeUInt32BE(mediaDuration, 16);
  const hdlrPayload = Buffer.alloc(28);
  hdlrPayload.write(handlerType, 8, 4, "ascii");
  const sttsPayload = Buffer.alloc(16);
  sttsPayload.writeUInt32BE(1, 4);
  sttsPayload.writeUInt32BE(sampleCount, 8);
  sttsPayload.writeUInt32BE(sampleDelta, 12);
  return atom(
    "trak",
    Buffer.concat([
      atom("tkhd", tkhdPayload),
      atom(
        "mdia",
        Buffer.concat([
          atom("mdhd", mdhdPayload),
          atom("hdlr", hdlrPayload),
          atom("minf", Buffer.concat([
            dataInformationAtom(dataReferenceMode),
            atom(
              "stbl",
              Buffer.concat([
                atom("stts", sttsPayload),
                ...structuralSampleAtoms({
                  chunkOffset,
                  dataReferenceIndex,
                  handlerType,
                  sampleTableCount,
                }),
              ]),
            ),
          ].filter(Boolean))),
        ]),
      ),
    ]),
  );
}

function quickTimeMovie({
  dataReferenceIndex = 1,
  dataReferenceMode = "self-contained",
  majorBrand = "qt  ",
  movieTimescale,
  movieDuration,
  trackDuration = movieDuration,
  trackHeaderVersion = 0,
  mediaTimescale = movieTimescale,
  mediaDuration = movieDuration,
  sampleTableCount = 1,
  sampleCount = 1,
  sampleDelta = mediaDuration,
  compositionOffset = null,
  compositionRuns = null,
  signedCompositionOffsets = false,
  editDuration = null,
  compositionEnd = null,
  compositionStart = 0,
  compositionToDtsShift = 0,
  fragmented = false,
  fragmentDefaults = false,
  additionalTracks = [],
} = {}) {
  const mvhdPayload = Buffer.alloc(100);
  mvhdPayload.writeUInt8(0, 0);
  mvhdPayload.writeUInt32BE(movieTimescale, 12);
  mvhdPayload.writeUInt32BE(movieDuration, 16);

  const tkhdPayload = Buffer.alloc(trackHeaderVersion === 1 ? 96 : 84);
  tkhdPayload.writeUInt8(trackHeaderVersion, 0);
  if (trackHeaderVersion === 1) {
    tkhdPayload.writeUInt32BE(1, 20);
    tkhdPayload.writeBigUInt64BE(BigInt(trackDuration), 28);
  } else {
    tkhdPayload.writeUInt32BE(1, 12);
    tkhdPayload.writeUInt32BE(trackDuration, 20);
  }

  const mdhdPayload = Buffer.alloc(24);
  mdhdPayload.writeUInt8(0, 0);
  mdhdPayload.writeUInt32BE(mediaTimescale, 12);
  mdhdPayload.writeUInt32BE(mediaDuration, 16);

  const hdlrPayload = Buffer.alloc(28);
  hdlrPayload.write("vide", 8, 4, "ascii");

  const sttsPayload = Buffer.alloc(16);
  sttsPayload.writeUInt32BE(1, 4);
  sttsPayload.writeUInt32BE(sampleCount, 8);
  sttsPayload.writeUInt32BE(sampleDelta, 12);

  const timingAtoms = [
    atom("stts", sttsPayload),
  ];
  const cttsRuns = compositionRuns ?? (compositionOffset === null
    ? null
    : [{ count: sampleCount, offset: compositionOffset }]);
  if (cttsRuns !== null) {
    const cttsPayload = Buffer.alloc(8 + cttsRuns.length * 8);
    cttsPayload.writeUInt32BE(cttsRuns.length, 4);
    cttsRuns.forEach((run, index) => {
      const offset = 8 + index * 8;
      cttsPayload.writeUInt32BE(run.count, offset);
      if (signedCompositionOffsets) {
        cttsPayload.writeInt32BE(run.offset, offset + 4);
      } else {
        cttsPayload.writeUInt32BE(run.offset, offset + 4);
      }
    });
    timingAtoms.push(atom("ctts", cttsPayload));
  }
  if (compositionEnd !== null) {
    const compositionValues = cttsRuns?.map((run) => run.offset) ?? [0];
    const cslgPayload = Buffer.alloc(24);
    cslgPayload.writeInt32BE(compositionToDtsShift, 4);
    cslgPayload.writeInt32BE(Math.min(...compositionValues), 8);
    cslgPayload.writeInt32BE(Math.max(...compositionValues), 12);
    cslgPayload.writeInt32BE(compositionStart, 16);
    cslgPayload.writeInt32BE(compositionEnd, 20);
    timingAtoms.push(atom("cslg", cslgPayload));
  }

  const trackAtoms = [atom("tkhd", tkhdPayload)];
  if (editDuration !== null) {
    const elstPayload = Buffer.alloc(20);
    elstPayload.writeUInt32BE(1, 4);
    elstPayload.writeUInt32BE(editDuration, 8);
    elstPayload.writeInt32BE(0, 12);
    elstPayload.writeInt16BE(1, 16);
    trackAtoms.push(atom("edts", atom("elst", elstPayload)));
  }
  const ftypPayload = Buffer.alloc(12);
  ftypPayload.write(majorBrand, 0, 4, "ascii");
  ftypPayload.write(majorBrand, 8, 4, "ascii");
  const ftyp = atom("ftyp", ftypPayload);
  const buildMoov = (chunkOffsets) => {
    const mainTrack = atom(
      "trak",
      Buffer.concat([
        ...trackAtoms,
        atom(
          "mdia",
          Buffer.concat([
            atom("mdhd", mdhdPayload),
            atom("hdlr", hdlrPayload),
            atom("minf", Buffer.concat([
              dataInformationAtom(dataReferenceMode),
              atom(
                "stbl",
                Buffer.concat([
                  ...timingAtoms,
                  ...structuralSampleAtoms({
                    chunkOffset: chunkOffsets[0],
                    dataReferenceIndex,
                    handlerType: "vide",
                    sampleTableCount,
                  }),
                ]),
              ),
            ].filter(Boolean))),
          ]),
        ),
      ]),
    );
    const moovAtoms = [
      atom("mvhd", mvhdPayload),
      mainTrack,
      ...additionalTracks.map((track, index) => basicTimedTrackAtom({
        ...track,
        chunkOffset: chunkOffsets[index + 1],
        trackId: index + 2,
      })),
    ];
    if (fragmentDefaults) moovAtoms.push(atom("mvex", Buffer.alloc(0)));
    return atom("moov", Buffer.concat(moovAtoms));
  };
  const placeholderMoov = buildMoov(
    Array.from({ length: 1 + additionalTracks.length }, () => 0),
  );
  let nextChunkOffset = ftyp.length + placeholderMoov.length + 8;
  const chunkOffsets = [];
  for (const count of [
    sampleTableCount,
    ...additionalTracks.map((track) => track.sampleTableCount ?? track.sampleCount),
  ]) {
    chunkOffsets.push(nextChunkOffset);
    nextChunkOffset += count;
  }
  const moov = buildMoov(chunkOffsets);
  const mdat = atom(
    "mdat",
    Buffer.alloc(nextChunkOffset - (ftyp.length + moov.length + 8), 0x01),
  );
  const rootAtoms = [
    ftyp,
    moov,
    mdat,
  ];
  if (fragmented) rootAtoms.push(atom("moof", atom("traf", Buffer.alloc(0))));
  return Buffer.concat(rootAtoms);
}

function handlerOnlyQuickTimeMovie() {
  const mvhdPayload = Buffer.alloc(100);
  mvhdPayload.writeUInt32BE(600, 12);
  mvhdPayload.writeUInt32BE(4_800, 16);
  const tkhdPayload = Buffer.alloc(84);
  tkhdPayload.writeUInt32BE(1, 12);
  tkhdPayload.writeUInt32BE(4_800, 20);
  const mdhdPayload = Buffer.alloc(24);
  mdhdPayload.writeUInt32BE(600, 12);
  mdhdPayload.writeUInt32BE(4_800, 16);
  const hdlrPayload = Buffer.alloc(28);
  hdlrPayload.write("vide", 8, 4, "ascii");
  const emptyStsdPayload = Buffer.alloc(8);
  const sttsPayload = Buffer.alloc(16);
  sttsPayload.writeUInt32BE(1, 4);
  sttsPayload.writeUInt32BE(8, 8);
  sttsPayload.writeUInt32BE(600, 12);
  const stszPayload = Buffer.alloc(12);
  stszPayload.writeUInt32BE(1, 4);
  stszPayload.writeUInt32BE(8, 8);
  const ftypPayload = Buffer.alloc(12);
  ftypPayload.write("qt  ", 0, 4, "ascii");
  ftypPayload.write("qt  ", 8, 4, "ascii");
  return Buffer.concat([
    atom("ftyp", ftypPayload),
    atom(
      "moov",
      Buffer.concat([
        atom("mvhd", mvhdPayload),
        atom(
          "trak",
          Buffer.concat([
            atom("tkhd", tkhdPayload),
            atom(
              "mdia",
              Buffer.concat([
                atom("mdhd", mdhdPayload),
                atom("hdlr", hdlrPayload),
                atom(
                  "minf",
                  atom(
                    "stbl",
                    Buffer.concat([
                      atom("stsd", emptyStsdPayload),
                      atom("stts", sttsPayload),
                      atom("stsz", stszPayload),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    atom("mdat", Buffer.alloc(8, 0x01)),
  ]);
}

function rangedFile(bytes, calls = []) {
  return {
    createReadStream(options = {}) {
      calls.push(options);
      const start = options.start ?? 0;
      const end = Math.min(options.end ?? bytes.length - 1, bytes.length - 1);
      return Readable.from([bytes.subarray(start, end + 1)]);
    },
  };
}

function atomTypeOffsets(bytes, type) {
  const offsets = [];
  let offset = 0;
  const needle = Buffer.from(type, "ascii");
  while ((offset = bytes.indexOf(needle, offset)) !== -1) {
    offsets.push(offset);
    offset += needle.length;
  }
  return offsets;
}

test("trusted probe streams the exact generation and measures duration", async () => {
  assert.equal(createReelMediaProbe, createTrustedGcsMediaProbe);
  const bytes = oneSecondWave();
  const calls = [];
  const bucket = {
    file(path, options) {
      calls.push({ path, options });
      return {
        createReadStream() {
          return Readable.from([bytes]);
        },
      };
    },
  };
  const probe = createReelMediaProbe(bucket);
  const result = await probe({
    storagePath: "reels/user/reel/backing-audio.wav",
    generation: "123",
    contentType: "audio/wav",
    size: bytes.length,
  });
  assert.ok(result.durationMs >= 990 && result.durationMs <= 1010);
  assert.deepEqual(calls, [
    {
      path: "reels/user/reel/backing-audio.wav",
      options: { generation: "123" },
    },
  ]);
});

test("trusted probe exposes the bounded video/audio contract for reuse", () => {
  assert.deepEqual(TRUSTED_MEDIA_PROBE_CONTENT_TYPES, [
    "video/mp4",
    "video/quicktime",
    "video/webm",
    "audio/mpeg",
    "audio/mp4",
    "audio/wav",
  ]);
  assert.equal(supportsTrustedMediaProbeContentType("video/webm"), true);
  assert.equal(supportsTrustedMediaProbeContentType("image/jpeg"), false);
  assert.equal(supportsTrustedMediaProbeContentType(null), false);
});

test("extended-size ftyp is sniffed from its real payload offset", () => {
  const bytes = Buffer.alloc(28);
  bytes.writeUInt32BE(1, 0);
  bytes.write("ftyp", 4, 4, "ascii");
  bytes.writeBigUInt64BE(28n, 8);
  bytes.write("qt  ", 16, 4, "ascii");
  bytes.write("qt  ", 24, 4, "ascii");

  assert.deepEqual(sniffTrustedMediaHeader(bytes), {
    family: "iso-bmff",
    detectedContentType: null,
    majorBrand: "qt  ",
  });
});

test("trusted ISO-BMFF duration fallback corroborates a valid QuickTime track", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 5_080,
    sampleCount: 254,
    sampleTableCount: 254,
    sampleDelta: 20,
  });
  const calls = [];

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes, calls),
    bytes.length,
  );

  assert.equal(durationMs, 8_467);
  assert.ok(calls.length >= 3);
  assert.ok(calls.every((options) => options.validation === false));
});

test("forged short mvhd cannot understate a longer media timeline", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    trackDuration: 72_000,
    mediaDuration: 72_000,
    sampleCount: 120,
    sampleTableCount: 120,
    sampleDelta: 600,
  });

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes),
    bytes.length,
  );

  assert.equal(durationMs, 120_000);
  assert.notEqual(durationMs, 1_000);
});

test("production probe corroborates even a positive short parser duration", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    trackDuration: 72_000,
    mediaDuration: 72_000,
    sampleCount: 120,
    sampleTableCount: 120,
    sampleDelta: 600,
  });
  const probe = createTrustedGcsMediaProbe(
    { file: () => rangedFile(bytes) },
    {
      parseWebStream: async () => ({
        format: {
          duration: 1,
          hasAudio: false,
          hasVideo: true,
        },
      }),
    },
  );

  const result = await probe({
    storagePath: "direct/alice/conversation/message/video.mov",
    generation: "123",
    contentType: "video/quicktime",
    size: bytes.length,
  });

  assert.equal(result.durationMs, 120_000);
  assert.equal(result.hasVideo, true);
});

test("an unsafe positive parser duration fails closed", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  });
  const probe = createTrustedGcsMediaProbe(
    { file: () => rangedFile(bytes) },
    {
      parseWebStream: async () => ({
        format: {
          duration: Number.MAX_VALUE,
          hasAudio: false,
          hasVideo: true,
        },
      }),
    },
  );

  await assert.rejects(
    probe({
      storagePath: "direct/alice/conversation/message/overflow.mov",
      generation: "123",
      contentType: "video/quicktime",
      size: bytes.length,
    }),
    (error) => error.code === "failed-precondition",
  );
});

test("legacy QuickTime audi tracks cannot hide a longer audio timeline", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    trackDuration: 600,
    mediaDuration: 600,
    sampleCount: 1,
    sampleTableCount: 1,
    sampleDelta: 600,
    additionalTracks: [
      {
        handlerType: "audi",
        trackDuration: 72_000,
        mediaTimescale: 600,
        mediaDuration: 72_000,
        sampleCount: 120,
        sampleDelta: 600,
      },
    ],
  });
  const probe = createTrustedGcsMediaProbe(
    { file: () => rangedFile(bytes) },
    {
      parseWebStream: async () => ({
        format: {
          duration: 1,
          hasAudio: true,
          hasVideo: true,
        },
      }),
    },
  );

  const result = await probe({
    storagePath: "direct/alice/conversation/message/legacy-audio.mov",
    generation: "123",
    contentType: "video/quicktime",
    size: bytes.length,
  });

  assert.equal(result.durationMs, 120_000);
  assert.equal(result.hasAudio, true);
  assert.equal(result.hasVideo, true);
});

test("ISO-BMFF track presence cannot be hidden by the general parser", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  });
  const probe = createTrustedGcsMediaProbe(
    { file: () => rangedFile(bytes) },
    {
      parseWebStream: async () => ({
        format: {
          duration: 1,
          hasAudio: true,
          hasVideo: false,
        },
      }),
    },
  );

  await assert.rejects(
    probe({
      storagePath: "direct/alice/conversation/message/hidden-video.mov",
      generation: "123",
      contentType: "video/quicktime",
      size: bytes.length,
    }),
    (error) => error.code === "failed-precondition",
  );
});

test("known QuickTime audio false-positive keeps video-only media compatible", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  });
  const probe = createTrustedGcsMediaProbe(
    { file: () => rangedFile(bytes) },
    {
      parseWebStream: async () => ({
        format: {
          duration: 1,
          hasAudio: true,
          hasVideo: true,
        },
      }),
    },
  );

  const result = await probe({
    storagePath: "direct/alice/conversation/message/video-only.mov",
    generation: "123",
    contentType: "video/quicktime",
    size: bytes.length,
  });

  assert.equal(result.detectedContentType, "video/quicktime");
  assert.equal(result.hasAudio, false);
  assert.equal(result.hasVideo, true);
});

test("production parser accepts a coherent video-only QuickTime sample map", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  });
  const probe = createTrustedGcsMediaProbe({ file: () => rangedFile(bytes) });

  const result = await probe({
    storagePath: "direct/alice/conversation/message/coherent.mov",
    generation: "123",
    contentType: "video/quicktime",
    size: bytes.length,
  });

  assert.equal(result.detectedContentType, "video/quicktime");
  assert.equal(result.durationMs, 1_000);
  assert.equal(result.hasAudio, false);
  assert.equal(result.hasVideo, true);
});

test("production parser accepts a coherent video-only MP4 sample map", async () => {
  const bytes = quickTimeMovie({
    majorBrand: "isom",
    movieTimescale: 600,
    movieDuration: 600,
  });
  const probe = createTrustedGcsMediaProbe({ file: () => rangedFile(bytes) });

  const result = await probe({
    storagePath: "direct/alice/conversation/message/coherent.mp4",
    generation: "123",
    contentType: "video/mp4",
    size: bytes.length,
  });

  assert.equal(result.detectedContentType, "video/mp4");
  assert.equal(result.durationMs, 1_000);
  assert.equal(result.hasAudio, false);
  assert.equal(result.hasVideo, true);
});

test("production parser accepts coherent interleaved QuickTime tracks", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    additionalTracks: [{
      handlerType: "soun",
      trackDuration: 600,
      mediaTimescale: 600,
      mediaDuration: 600,
      sampleCount: 1,
      sampleDelta: 600,
    }],
  });
  const probe = createTrustedGcsMediaProbe({ file: () => rangedFile(bytes) });

  const result = await probe({
    storagePath: "direct/alice/conversation/message/interleaved.mov",
    generation: "123",
    contentType: "video/quicktime",
    size: bytes.length,
  });

  assert.equal(result.durationMs, 1_000);
  assert.equal(result.hasAudio, true);
  assert.equal(result.hasVideo, true);
});

test("production parser rejects a handler-only movie with no sample map", async () => {
  const bytes = handlerOnlyQuickTimeMovie();
  const probe = createTrustedGcsMediaProbe({ file: () => rangedFile(bytes) });

  await assert.rejects(
    probe({
      storagePath: "direct/alice/conversation/message/forged.mov",
      generation: "123",
      contentType: "video/quicktime",
      size: bytes.length,
    }),
    (error) => error.code === "failed-precondition",
  );
});

test("sample chunks must be fully contained in an mdat payload", async () => {
  const bytes = Buffer.from(quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  }));
  const [stcoTypeOffset] = atomTypeOffsets(bytes, "stco");
  bytes.writeUInt32BE(bytes.length, stcoTypeOffset + 12);

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("sample chunks from different tracks cannot overlap", async () => {
  const bytes = Buffer.from(quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    additionalTracks: [{
      handlerType: "soun",
      trackDuration: 600,
      mediaTimescale: 600,
      mediaDuration: 600,
      sampleCount: 1,
      sampleDelta: 600,
    }],
  }));
  const [videoStco, audioStco] = atomTypeOffsets(bytes, "stco");
  bytes.writeUInt32BE(bytes.readUInt32BE(videoStco + 12), audioStco + 12);

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("a playable track without dinf/dref fails closed", async () => {
  const bytes = quickTimeMovie({
    dataReferenceMode: "missing",
    movieTimescale: 600,
    movieDuration: 600,
  });

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("an external media data reference fails closed", async () => {
  const bytes = quickTimeMovie({
    dataReferenceMode: "external",
    movieTimescale: 600,
    movieDuration: 600,
  });

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("an unbound sample-description data reference fails closed", async () => {
  const bytes = quickTimeMovie({
    dataReferenceIndex: 2,
    movieTimescale: 600,
    movieDuration: 600,
  });

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("Apple QuickTime self-contained alis references remain compatible", async () => {
  const bytes = quickTimeMovie({
    dataReferenceMode: "quicktime-alias",
    movieTimescale: 600,
    movieDuration: 600,
  });
  const probe = createTrustedGcsMediaProbe({ file: () => rangedFile(bytes) });

  const result = await probe({
    storagePath: "direct/alice/conversation/message/apple.mov",
    generation: "123",
    contentType: "video/quicktime",
    size: bytes.length,
  });

  assert.equal(result.detectedContentType, "video/quicktime");
  assert.equal(result.hasVideo, true);
});

test("QuickTime alis references are rejected outside a qt container", async () => {
  const bytes = quickTimeMovie({
    dataReferenceMode: "quicktime-alias",
    majorBrand: "isom",
    movieTimescale: 600,
    movieDuration: 600,
  });

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("QuickTime alis requires the exact self-contained flag", async () => {
  const bytes = quickTimeMovie({
    dataReferenceMode: "alias-not-self-contained",
    movieTimescale: 600,
    movieDuration: 600,
  });

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("QuickTime alis cannot carry an external payload", async () => {
  const bytes = quickTimeMovie({
    dataReferenceMode: "external-alias",
    movieTimescale: 600,
    movieDuration: 600,
  });

  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
    null,
  );
});

test("presentation edits and composition offsets cannot hide a longer timeline", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    trackDuration: 600,
    mediaDuration: 600,
    sampleCount: 1,
    sampleTableCount: 1,
    sampleDelta: 600,
    compositionOffset: 71_400,
    editDuration: 72_000,
    compositionEnd: 72_000,
  });

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes),
    bytes.length,
  );

  assert.equal(durationMs, 120_000);
});

test("negative QuickTime composition start cannot hide the presentation span", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 1_200,
    trackDuration: 1_200,
    mediaDuration: 1_200,
    sampleCount: 2,
    sampleTableCount: 2,
    sampleDelta: 600,
    compositionRuns: [
      { count: 1, offset: -71_400 },
      { count: 1, offset: -600 },
    ],
    signedCompositionOffsets: true,
    compositionToDtsShift: 71_400,
    compositionStart: -71_400,
    compositionEnd: 600,
  });

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes),
    bytes.length,
  );

  // The exact presentation span is 120 seconds. The corroborator is allowed
  // to overestimate by one decode interval, but must never return the forged
  // two-second header duration.
  assert.equal(durationMs, 121_000);
});

// RC-17. A browser MediaRecorder writes fragmented MP4. Before this round the
// probe returned null for every such upload, finalizeReelDraftV2 raised
// "The uploaded Reel tracks are invalid", and the client mistranslated that
// into "Check your media and audio rights".
test("a real Chromium MediaRecorder fMP4 probes to its recorded length",
  async () => {
    const bytes = fs.readFileSync(path.join(
      __dirname,
      "fixtures",
      "chromium_mediarecorder_fragmented.mp4",
    ));
    // Captured on this machine with Playwright's Chromium: canvas.captureStream
    // recorded as video/mp4. ftyp + moov(mvex/trex, empty stbl) + moof + mdat
    // + mfra, 45 samples at a 30000 timescale summing to 44228 ticks, with the
    // fragment's bytes exactly filling the mdat payload.
    assert.equal(
      await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
      1_475,
    );
  });

// The acceptance fixture the suite was missing: a REAL capture that is more
// than one fragment. A MediaRecorder driven with a timeslice emits one
// moof/mdat pair per slice, so every recording longer than a few seconds is a
// chain — 5 fragments for these 15 seconds, 18 for a 60-second capture. That is
// why "refuse anything with more than one moof" was not an option: it would
// have refused every real web recording RC-17 exists to accept.
test("a real multi-fragment Chromium capture probes to its recorded length",
  async () => {
    const bytes = fs.readFileSync(path.join(
      __dirname,
      "fixtures",
      "chromium_mediarecorder_multifragment.mp4",
    ));
    // Captured on this machine with Playwright's Chromium: canvas.captureStream
    // at 30 fps recorded as video/mp4;codecs=avc1.42E01E with a 1000 ms
    // timeslice, stopped after 15018 ms of wall clock.
    assert.equal(atomTypeOffsets(bytes, "moof").length, 5);
    assert.equal(
      await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
      15_002,
    );
  });

test("a synthetic fMP4 is measured from its moof timing, not its claim",
  async () => {
    const samples = Array.from(
      { length: 30 },
      () => ({ duration: 1_000, size: 64 }),
    );
    // 30 samples x 1000 ticks at a 30000 timescale is exactly one second, and
    // every container field is zero, so only the moof walk can produce it.
    const bytes = fragmentedMp4({ samples });
    assert.equal(
      await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
      1_000,
    );

    // A later decode time is part of the fragment's end, not ignored.
    const offsetFragment = fragmentedMp4({
      baseMediaDecodeTime: 15_000,
      samples,
    });
    assert.equal(
      await readTrustedIsoBmffDurationMs(
        rangedFile(offsetFragment),
        offsetFragment.length,
      ),
      1_500,
    );

    // A fragmented file with an `mdat` and no `trun` at all used to fall back
    // to the container duration. It no longer can: an `mdat` nothing describes
    // is media this parser did not measure, and `mehd` is a number the uploader
    // wrote — the same shape as G-2, one fragment wide. A file with neither was
    // already a refusal and stays one.
    const containerOnly = fragmentedMp4({
      fragmentDuration: 1_500,
      samples,
      withTrun: false,
    });
    assert.equal(
      await readTrustedIsoBmffDurationMs(
        rangedFile(containerOnly),
        containerOnly.length,
      ),
      null,
    );
    const nothing = fragmentedMp4({ samples, withTrun: false });
    assert.equal(
      await readTrustedIsoBmffDurationMs(rangedFile(nothing), nothing.length),
      null,
    );
  });

// Gate blocker G-2 (SEC-2). The fragmented branch opened only the LAST `moof`
// and returned `Math.max` over that one fragment and the container headers —
// every one of which the uploader wrote. Ten fragments of honest media probed
// as 10 s, and as 1 s once the final `tfdt` was zeroed in an otherwise
// byte-identical file; a 20 MB file declaring its media in fragment 1 probed as
// 1 ms. reels/service.js accepts any probe within tolerance of the client's own
// claim (reels/contract.js caps duration at 5 minutes) and
// messaging/direct_integrity.js accepts 1..60000 ms within +/-2 s, so minutes
// of media could publish as a 1-3 s Yeel or a "1-second voice note".
test("a multi-fragment fMP4 is measured across every fragment", async () => {
  const samples = Array.from(
    { length: 30 },
    () => ({ duration: 1_000, size: 64 }),
  );
  // Ten one-second fragments at a 30000 timescale: ten seconds of real media.
  const honest = fragmentedMp4({
    fragments: Array.from({ length: 10 }, (_, index) => ({
      samples,
      baseMediaDecodeTime: index * 30_000,
    })),
  });
  assert.equal(
    await readTrustedIsoBmffDurationMs(rangedFile(honest), honest.length),
    10_000,
  );

  // The same bytes with only the LAST fragment's decode time zeroed. Opening
  // just that fragment reported 1000; the maximum across fragments, and the
  // sum of every fragment's sample durations, both still say ten seconds.
  const lastFragmentLies = fragmentedMp4({
    fragments: Array.from({ length: 10 }, (_, index) => ({
      samples,
      baseMediaDecodeTime: index === 9 ? 0 : index * 30_000,
    })),
  });
  assert.equal(
    await readTrustedIsoBmffDurationMs(
      rangedFile(lastFragmentLies),
      lastFragmentLies.length,
    ),
    10_000,
  );

  // And with EVERY decode time zeroed, so the per-fragment maximum collapses to
  // one fragment: the summed sample durations are what hold the bound.
  const everyFragmentLies = fragmentedMp4({
    fragments: Array.from({ length: 10 }, () => ({
      samples,
      baseMediaDecodeTime: 0,
    })),
  });
  assert.equal(
    await readTrustedIsoBmffDurationMs(
      rangedFile(everyFragmentLies),
      everyFragmentLies.length,
    ),
    10_000,
  );

  // Twenty seconds of media declared in fragment 1, with a token final
  // fragment: the long fragment is opened and counted like any other.
  const hiddenInFirstFragment = fragmentedMp4({
    fragments: [
      {
        samples: Array.from(
          { length: 600 },
          () => ({ duration: 1_000, size: 16 }),
        ),
        baseMediaDecodeTime: 0,
      },
      { samples: [{ duration: 1, size: 4 }], baseMediaDecodeTime: 0 },
    ],
  });
  assert.equal(
    await readTrustedIsoBmffDurationMs(
      rangedFile(hiddenInFirstFragment),
      hiddenInFirstFragment.length,
    ),
    20_000,
  );
});

test("an mdat no trun accounts for is refused, however it is reached",
  async () => {
    const samples = Array.from(
      { length: 30 },
      () => ({ duration: 1_000, size: 64 }),
    );
    for (const bytes of [
      // Two fragments, the second one carrying an mdat of its own that no
      // `trun` describes. Before this round the walk never opened fragment 1
      // and never noticed fragment 2's unclaimed bytes.
      fragmentedMp4({
        fragments: [
          { samples, baseMediaDecodeTime: 0 },
          { samples, baseMediaDecodeTime: 30_000, withTrun: false },
        ],
      }),
      // A single fragment whose mdat holds far more than its run claims.
      fragmentedMp4({ mdatBytes: samples.length * 64 + 4_096, samples }),
    ]) {
      assert.equal(
        await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
        null,
      );
    }
  });

test("the fragment walk stays inside its read and fragment budgets", async () => {
  const samples = Array.from(
    { length: 30 },
    () => ({ duration: 1_000, size: 64 }),
  );
  const chain = (count) => fragmentedMp4({
    fragments: Array.from({ length: count }, (_, index) => ({
      samples,
      baseMediaDecodeTime: index * 30_000,
    })),
  });

  // An honest recording of MAX_ISO_BMFF_FRAGMENTS fragments is accepted and
  // measured — three range reads per fragment (its own header and its mdat's
  // while the root is listed, plus one read of the whole moof box) plus the
  // fixed init-segment cost, inside MAX_ISO_BMFF_DURATION_RANGE_READS. At the
  // 160-read ceiling this branch shipped with, an honest capture failed closed
  // at about 57 fragments with "The uploaded Reel tracks are invalid" — the
  // symptom RC-17 exists to remove.
  const accepted = chain(MAX_ISO_BMFF_FRAGMENTS);
  const acceptedCalls = [];
  assert.equal(
    await readTrustedIsoBmffDurationMs(
      rangedFile(accepted, acceptedCalls),
      accepted.length,
    ),
    MAX_ISO_BMFF_FRAGMENTS * 1_000,
  );
  assert.ok(
    acceptedCalls.length <= MAX_ISO_BMFF_DURATION_RANGE_READS,
    `${acceptedCalls.length} reads exceeds the budget`,
  );

  // One fragment more fails closed rather than spending an unbounded number of
  // reads on a crafted chain.
  const refused = chain(MAX_ISO_BMFF_FRAGMENTS + 1);
  const refusedCalls = [];
  assert.equal(
    await readTrustedIsoBmffDurationMs(
      rangedFile(refused, refusedCalls),
      refused.length,
    ),
    null,
  );
  assert.ok(refusedCalls.length <= MAX_ISO_BMFF_DURATION_RANGE_READS);
});

test("an fMP4 whose trun over-claims its own media data fails closed",
  async () => {
    const samples = Array.from(
      { length: 30 },
      () => ({ duration: 1_000, size: 64 }),
    );
    for (const bytes of [
      // The run says every sample is 4 KiB; the mdat holds 64 bytes each, so
      // the fragment's declared bytes run off the end of the uploaded media.
      fragmentedMp4({ declaredSampleSize: 4_096, samples }),
      // The mdat is short of what the run needs by a single byte.
      fragmentedMp4({
        mdatBytes: samples.length * 64 - 1,
        samples,
      }),
      // Neither cleanly progressive nor cleanly fragmented: mvex plus a
      // populated sample table stays refused, as it was before this round.
      fragmentedMp4({ populatedSampleTable: true, samples }),
      // An mvex that declares no track extends at all.
      fragmentedMp4({ samples, withTrex: false }),
    ]) {
      assert.equal(
        await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
        null,
      );
    }
  });

test("fragmented or hybrid ISO-BMFF timelines fail closed", async () => {
  const classic = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  });
  for (const bytes of [
    quickTimeMovie({
      movieTimescale: 600,
      movieDuration: 600,
      fragmented: true,
    }),
    quickTimeMovie({
      movieTimescale: 600,
      movieDuration: 600,
      fragmentDefaults: true,
    }),
    Buffer.concat([classic, atom("mfra", Buffer.alloc(0))]),
  ]) {
    assert.equal(
      await readTrustedIsoBmffDurationMs(rangedFile(bytes), bytes.length),
      null,
    );
  }
});

test("inconsistent timing and sample tables fail closed", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
    sampleCount: 60,
    sampleTableCount: 59,
    sampleDelta: 10,
  });

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes),
    bytes.length,
  );

  assert.equal(durationMs, null);
});

test("a present positive duration that overflows milliseconds fails closed", async () => {
  const bytes = quickTimeMovie({
    movieTimescale: 1,
    movieDuration: 1,
    trackHeaderVersion: 1,
    trackDuration: 0xfffffffffffffffen,
    mediaDuration: 1,
    sampleCount: 1,
    sampleTableCount: 1,
    sampleDelta: 1,
  });

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes),
    bytes.length,
  );

  assert.equal(durationMs, null);
});

test("malicious atom chains fail closed within the duration range-read budget", async () => {
  const freeAtoms = Array.from(
    { length: MAX_ISO_BMFF_DURATION_RANGE_READS + 4 },
    () => atom("free", Buffer.alloc(0)),
  );
  const validTail = quickTimeMovie({
    movieTimescale: 600,
    movieDuration: 600,
  });
  const bytes = Buffer.concat([
    ...freeAtoms,
    validTail.subarray(20),
  ]);
  const calls = [];

  const durationMs = await readTrustedIsoBmffDurationMs(
    rangedFile(bytes, calls),
    bytes.length,
  );

  assert.equal(durationMs, null);
  assert.equal(calls.length, MAX_ISO_BMFF_DURATION_RANGE_READS);
});

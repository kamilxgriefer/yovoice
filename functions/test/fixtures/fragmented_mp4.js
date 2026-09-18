// Synthetic fragmented-MP4 assembly for the RC-17 probe tests.
//
// A real Chromium `MediaRecorder` capture lives next to this file
// (`chromium_mediarecorder_fragmented.mp4`) and pins the shape the probe must
// accept. Synthetic bytes are what pins the shapes it must REFUSE: a recorder
// cannot be asked to emit a `trun` that over-claims its own media data, a
// half-populated sample table, or an `mvex` with no `trex`, and those are
// exactly the cases where the trust boundary matters.

function atom(type, payload) {
  const value = Buffer.alloc(8 + payload.length);
  value.writeUInt32BE(value.length, 0);
  value.write(type, 4, 4, "ascii");
  payload.copy(value, 8);
  return value;
}

function fullBox(version, flags, body) {
  const payload = Buffer.alloc(4 + body.length);
  payload.writeUInt8(version, 0);
  payload.writeUIntBE(flags, 1, 3);
  body.copy(payload, 4);
  return payload;
}

function sampleDescriptionAtom(handlerType) {
  const isVideo = handlerType === "vide";
  const entry = Buffer.alloc(isVideo ? 86 : 36);
  entry.writeUInt32BE(entry.length, 0);
  entry.write(isVideo ? "avc1" : "mp4a", 4, 4, "ascii");
  entry.writeUInt16BE(1, 14);
  if (isVideo) {
    entry.writeUInt16BE(160, 32);
    entry.writeUInt16BE(120, 34);
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
  const body = Buffer.alloc(4 + entry.length);
  body.writeUInt32BE(1, 0);
  entry.copy(body, 4);
  return atom("stsd", fullBox(0, 0, body));
}

function emptyTableAtom(type, entryCount = 0) {
  if (type === "stsz") {
    const body = Buffer.alloc(8);
    body.writeUInt32BE(0, 0);
    body.writeUInt32BE(entryCount, 4);
    return atom("stsz", fullBox(0, 0, body));
  }
  const body = Buffer.alloc(4);
  body.writeUInt32BE(entryCount, 0);
  return atom(type, fullBox(0, 0, body));
}

function populatedSampleTableAtoms(handlerType) {
  const stts = Buffer.alloc(12);
  stts.writeUInt32BE(1, 0);
  stts.writeUInt32BE(1, 4);
  stts.writeUInt32BE(1_000, 8);
  const stsc = Buffer.alloc(16);
  stsc.writeUInt32BE(1, 0);
  stsc.writeUInt32BE(1, 4);
  stsc.writeUInt32BE(1, 8);
  stsc.writeUInt32BE(1, 12);
  const stsz = Buffer.alloc(8);
  stsz.writeUInt32BE(4, 0);
  stsz.writeUInt32BE(1, 4);
  const stco = Buffer.alloc(8);
  stco.writeUInt32BE(1, 0);
  stco.writeUInt32BE(0, 4);
  return [
    sampleDescriptionAtom(handlerType),
    atom("stts", fullBox(0, 0, stts)),
    atom("stsc", fullBox(0, 0, stsc)),
    atom("stsz", fullBox(0, 0, stsz)),
    atom("stco", fullBox(0, 0, stco)),
  ];
}

function dataInformationAtom({ emptyLocationString = false } = {}) {
  const urlPayload = emptyLocationString
    ? Buffer.from([0, 0, 0, 1, 0])
    : Buffer.from([0, 0, 0, 1]);
  const drefBody = Buffer.concat([
    Buffer.alloc(4),
    atom("url ", urlPayload),
  ]);
  drefBody.writeUInt32BE(1, 0);
  return atom("dinf", atom("dref", fullBox(0, 0, drefBody)));
}

function trackAtom({
  emptyLocationString,
  handlerType,
  mediaDuration,
  mediaTimescale,
  populatedSampleTable,
  trackDuration,
  trackId,
}) {
  const tkhdBody = Buffer.alloc(80);
  tkhdBody.writeUInt32BE(trackId, 8);
  tkhdBody.writeUInt32BE(trackDuration, 16);
  const mdhdBody = Buffer.alloc(20);
  mdhdBody.writeUInt32BE(mediaTimescale, 8);
  mdhdBody.writeUInt32BE(mediaDuration, 12);
  const hdlrBody = Buffer.alloc(24);
  hdlrBody.write(handlerType, 4, 4, "ascii");
  const stblAtoms = populatedSampleTable
    ? populatedSampleTableAtoms(handlerType)
    : [
        sampleDescriptionAtom(handlerType),
        emptyTableAtom("stts"),
        emptyTableAtom("stsc"),
        emptyTableAtom("stsz"),
        emptyTableAtom("stco"),
      ];
  return atom(
    "trak",
    Buffer.concat([
      atom("tkhd", fullBox(0, 3, tkhdBody)),
      atom(
        "mdia",
        Buffer.concat([
          atom("mdhd", fullBox(0, 0, mdhdBody)),
          atom("hdlr", fullBox(0, 0, hdlrBody)),
          atom(
            "minf",
            Buffer.concat([
              dataInformationAtom({ emptyLocationString }),
              atom("stbl", Buffer.concat(stblAtoms)),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

/**
 * One movie fragment header: `moof` > `mfhd` + `traf`(`tfhd`/`tfdt`/`trun`).
 *
 * The `trun` data offset is relative to the first byte of the enclosing `moof`
 * (default-base-is-moof), so the box is position independent and can be
 * concatenated at any offset in a chain of fragments.
 */
function fragmentMoof({
  baseMediaDecodeTime,
  declaredSampleSize,
  samples,
  sequenceNumber,
  trackId,
  withTrun,
}) {
  const sampleSize = (sample) => declaredSampleSize ?? sample.size;
  const trunBody = Buffer.alloc(8 + samples.length * 8);
  trunBody.writeUInt32BE(samples.length, 0);
  // Patched below once the `moof` length is known.
  trunBody.writeInt32BE(0, 4);
  samples.forEach((sample, index) => {
    trunBody.writeUInt32BE(sample.duration, 8 + index * 8);
    trunBody.writeUInt32BE(sampleSize(sample), 12 + index * 8);
  });

  const mfhdBody = Buffer.alloc(4);
  mfhdBody.writeUInt32BE(sequenceNumber, 0);
  const tfhdBody = Buffer.alloc(4);
  tfhdBody.writeUInt32BE(trackId, 0);
  const tfdtBody = Buffer.alloc(8);
  tfdtBody.writeBigUInt64BE(BigInt(baseMediaDecodeTime), 0);
  const trafChildren = [
    // 0x020000 is default-base-is-moof: the fragment's data offsets are
    // relative to the first byte of this `moof`, which is what every browser
    // recorder writes.
    atom("tfhd", fullBox(0, 0x020000, tfhdBody)),
    atom("tfdt", fullBox(1, 0, tfdtBody)),
  ];
  // 0x000001 data-offset, 0x000100 sample-duration, 0x000200 sample-size.
  if (withTrun) {
    trafChildren.push(atom("trun", fullBox(1, 0x000301, trunBody)));
  }
  const moof = atom(
    "moof",
    Buffer.concat([
      atom("mfhd", fullBox(0, 0, mfhdBody)),
      atom("traf", Buffer.concat(trafChildren)),
    ]),
  );
  if (withTrun) {
    // The `trun` is the last child of the last `traf`; its data offset points
    // at the first byte of the `mdat` payload that follows this box.
    moof.writeInt32BE(moof.length + 8, moof.length - trunBody.length + 4);
  }
  return moof;
}

/**
 * Builds a fragmented MP4: `ftyp` + `moov` (with `mvex`/`trex` and empty sample
 * tables) + one or more `moof` (with `tfhd`/`tfdt`/`trun`) + `mdat` pairs.
 *
 * Every knob exists so a test can express one defect at a time. `mdatBytes`
 * and `declaredSampleSize` are the trust-boundary levers: the `trun` names how
 * many bytes its samples occupy, and those bytes have to be inside the `mdat`.
 */
function fragmentedMp4({
  baseMediaDecodeTime = 0,
  declaredSampleSize = null,
  emptyLocationString = false,
  fragmentDuration = null,
  // A list of {samples, baseMediaDecodeTime, mdatBytes, declaredSampleSize,
  // withTrun} — one entry per movie fragment. Omitted, the single-fragment
  // knobs above describe the one and only fragment.
  fragments = null,
  handlerType = "vide",
  majorBrand = "iso5",
  mdatBytes = null,
  mediaTimescale = 30_000,
  mediaDuration = 0,
  movieDuration = 0,
  movieTimescale = 1_000,
  populatedSampleTable = false,
  samples = [{ duration: 1_000, size: 64 }],
  trackDuration = 0,
  trackId = 1,
  trexDefaultSampleDuration = 0,
  trexDefaultSampleSize = 0,
  withMvex = true,
  withTrex = true,
  withTrun = true,
} = {}) {
  const ftypBody = Buffer.alloc(12);
  ftypBody.write(majorBrand, 0, 4, "ascii");
  ftypBody.write(majorBrand, 8, 4, "ascii");
  const ftyp = atom("ftyp", ftypBody);

  const mvhdBody = Buffer.alloc(96);
  mvhdBody.writeUInt32BE(movieTimescale, 8);
  mvhdBody.writeUInt32BE(movieDuration, 12);

  const trexBody = Buffer.alloc(20);
  trexBody.writeUInt32BE(trackId, 0);
  trexBody.writeUInt32BE(1, 4);
  trexBody.writeUInt32BE(trexDefaultSampleDuration, 8);
  trexBody.writeUInt32BE(trexDefaultSampleSize, 12);
  const mvexChildren = [];
  if (fragmentDuration !== null) {
    const mehdBody = Buffer.alloc(4);
    mehdBody.writeUInt32BE(fragmentDuration, 0);
    mvexChildren.push(atom("mehd", fullBox(0, 0, mehdBody)));
  }
  if (withTrex) mvexChildren.push(atom("trex", fullBox(0, 0, trexBody)));

  const moovChildren = [
    atom("mvhd", fullBox(0, 0, mvhdBody)),
    trackAtom({
      emptyLocationString,
      handlerType,
      mediaDuration,
      mediaTimescale,
      populatedSampleTable,
      trackDuration,
      trackId,
    }),
  ];
  if (withMvex) {
    moovChildren.push(atom("mvex", Buffer.concat(mvexChildren)));
  }
  const moov = atom("moov", Buffer.concat(moovChildren));

  // One `moof` + `mdat` pair per fragment. A recorder driven with a
  // `timeslice` emits one pair per slice, so a real capture of any length is a
  // CHAIN of these — which is exactly the shape a probe that opens only the
  // last `moof` cannot measure.
  const plan = fragments ?? [{
    baseMediaDecodeTime,
    declaredSampleSize,
    mdatBytes,
    samples,
    withTrun,
  }];
  const parts = [ftyp, moov];
  plan.forEach((fragment, index) => {
    const fragmentSamples = fragment.samples ?? samples;
    const moof = fragmentMoof({
      baseMediaDecodeTime: fragment.baseMediaDecodeTime ?? 0,
      declaredSampleSize: fragment.declaredSampleSize ?? null,
      samples: fragmentSamples,
      sequenceNumber: index + 1,
      trackId,
      withTrun: fragment.withTrun ?? true,
    });
    const payloadLength = fragment.mdatBytes ??
      fragmentSamples.reduce((total, sample) => total + sample.size, 0);
    parts.push(moof, atom("mdat", Buffer.alloc(payloadLength, 0x01)));
  });
  return Buffer.concat(parts);
}

module.exports = { atom, fragmentedMp4 };

const assert = require("node:assert/strict");
const { Readable } = require("node:stream");
const { test } = require("node:test");

const {
  TRUSTED_MEDIA_PROBE_CONTENT_TYPES,
  createReelMediaProbe,
  createTrustedGcsMediaProbe,
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

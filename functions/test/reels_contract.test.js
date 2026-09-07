const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  MAX_DURATION_MS,
  MAX_VIDEO_BYTES,
  MIN_DURATION_MS,
  isSafePublicHttpsUrl,
  reelStoragePath,
  sniffContentType,
  validateComposition,
  validateDraftPlan,
  validateReelReportReason,
  validateStoredAsset,
} = require("../reels/contract");

function validVideoPlan(overrides = {}) {
  return {
    requestId: "request-00000001",
    mediaKind: "video",
    mediaContentType: "video/mp4",
    mediaSize: 1_000_000,
    durationMs: 30_000,
    hasBackingAudio: false,
    audioContentType: null,
    audioSize: null,
    audioDurationMs: null,
    ...overrides,
  };
}

function validComposition(overrides = {}) {
  return {
    caption: "A real Reel",
    crop: {
      scalePermille: 1200,
      offsetXPermille: 0,
      offsetYPermille: -100,
    },
    filter: "vivid",
    trimStartMs: 1000,
    trimEndMs: 20_000,
    textOverlays: [
      {
        id: "title_1",
        text: "Hello",
        xPermille: 500,
        yPermille: 300,
        scalePermille: 1000,
        color: "light",
      },
    ],
    linkOverlays: [
      {
        id: "link_1",
        label: "Open site",
        url: "https://example.com/path",
        xPermille: 500,
        yPermille: 700,
      },
    ],
    originalAudioVolume: 100,
    backingAudioVolume: 0,
    audioTrimStartMs: 0,
    audioRightsAttested: false,
    audioAttribution: "",
    ...overrides,
  };
}

test("draft plans reject MIME, duration, audio-shape and extra-field attacks", () => {
  assert.deepEqual(validateDraftPlan(validVideoPlan()).mediaKind, "video");
  for (const input of [
    validVideoPlan({ mediaContentType: "text/html" }),
    validVideoPlan({ durationMs: 300_001 }),
    validVideoPlan({ hasBackingAudio: false, audioSize: 512 }),
    { ...validVideoPlan(), ownerId: "forged" },
  ]) {
    assert.throws(
      () => validateDraftPlan(input),
      (error) => error.code === "invalid-argument",
    );
  }
});

test("the five-minute duration cap is exact on both sides", () => {
  // Raised from 90 s on 2026-09-07. The cap had no boundary test at all: the
  // only coverage was a single `durationMs: 90_001` rejection, which proves a
  // value is refused but never that the cap itself sits where it is claimed.
  assert.equal(MAX_DURATION_MS, 5 * 60 * 1000);
  assert.equal(MIN_DURATION_MS, 1000);

  // Exactly at the cap is accepted, one millisecond over is refused, and the
  // accepted value survives validation unrounded.
  assert.equal(
    validateDraftPlan(validVideoPlan({ durationMs: MAX_DURATION_MS })).durationMs,
    MAX_DURATION_MS,
  );
  assert.equal(
    validateDraftPlan(validVideoPlan({ durationMs: MIN_DURATION_MS })).durationMs,
    MIN_DURATION_MS,
  );
  for (const durationMs of [MAX_DURATION_MS + 1, MIN_DURATION_MS - 1, -1]) {
    assert.throws(
      () => validateDraftPlan(validVideoPlan({ durationMs })),
      (error) => error.code === "invalid-argument",
    );
  }

  // Backing audio shares the cap, so a five-minute track can accompany a
  // five-minute video. Its 15 MB byte ceiling is unchanged and still binds:
  // 300 s at 320 kbps is ~12 MB, so a real MP3 fits.
  const audioPlan = (audioDurationMs) =>
    validVideoPlan({
      hasBackingAudio: true,
      audioContentType: "audio/mpeg",
      audioSize: 12_000_000,
      audioDurationMs,
    });
  assert.equal(
    validateDraftPlan(audioPlan(MAX_DURATION_MS)).audioDurationMs,
    MAX_DURATION_MS,
  );
  assert.throws(
    () => validateDraftPlan(audioPlan(MAX_DURATION_MS + 1)),
    (error) => error.code === "invalid-argument",
  );
});

test("a five-minute trim selection is accepted and the byte cap still binds", () => {
  // The trim window is validated against the same cap, so raising the duration
  // in one place and not the other would surface here rather than in the app.
  const plan = validateDraftPlan(
    validVideoPlan({ durationMs: MAX_DURATION_MS }),
  );
  assert.equal(
    validateComposition(
      validComposition({ trimStartMs: 0, trimEndMs: MAX_DURATION_MS }),
      plan,
    ).trimEndMs,
    MAX_DURATION_MS,
  );
  // A window longer than the cap, and one running past the media, are refused.
  for (const composition of [
    validComposition({ trimStartMs: 0, trimEndMs: MAX_DURATION_MS + 1 }),
    validComposition({ trimStartMs: 5000, trimEndMs: 5000 }),
  ]) {
    assert.throws(
      () => validateComposition(composition, plan),
      (error) => error.code === "invalid-argument",
    );
  }

  // The byte cap deliberately did NOT move with the duration: the client still
  // buffers the whole file in memory (`readAsBytes` -> `putData`), so raising
  // it would trade a clean rejection for an out-of-memory crash. This pins the
  // pairing so the two caps cannot drift apart unnoticed.
  assert.equal(MAX_VIDEO_BYTES, 100 * 1024 * 1024);
  assert.equal(
    validateDraftPlan(
      validVideoPlan({
        durationMs: MAX_DURATION_MS,
        mediaSize: MAX_VIDEO_BYTES,
      }),
    ).mediaSize,
    MAX_VIDEO_BYTES,
  );
  assert.throws(
    () =>
      validateDraftPlan(
        validVideoPlan({
          durationMs: MAX_DURATION_MS,
          mediaSize: MAX_VIDEO_BYTES + 1,
        }),
      ),
    (error) => error.code === "invalid-argument",
  );
});

test("composition is canonical and requires rights for uploaded audio", () => {
  const plan = validateDraftPlan(validVideoPlan());
  const composition = validateComposition(validComposition(), plan);
  assert.equal(composition.linkOverlays[0].url, "https://example.com/path");

  const audioPlan = validateDraftPlan(
    validVideoPlan({
      hasBackingAudio: true,
      audioContentType: "audio/mpeg",
      audioSize: 2048,
      audioDurationMs: 10_000,
    }),
  );
  assert.throws(
    () => validateComposition(validComposition(), audioPlan),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(
    validateComposition(
      validComposition({
        backingAudioVolume: 70,
        audioRightsAttested: true,
        audioAttribution: "Original track by the creator",
      }),
      audioPlan,
    ).audioRightsAttested,
    true,
  );
});

test("public HTTPS overlays reject SSRF and deceptive URL forms", () => {
  const rejected = [
    "http://example.com",
    "https://localhost/path",
    "https://api.local/path",
    "https://127.0.0.1/path",
    "https://2130706433/path",
    "https://10.1.2.3/path",
    "https://169.254.169.254/latest/meta-data",
    "https://[::1]/path",
    "https://user:pass@example.com/path",
    "https://example.com:8443/path",
    "https://intranet/path",
  ];
  for (const url of rejected) {
    assert.equal(isSafePublicHttpsUrl(url), false, url);
  }
  assert.equal(isSafePublicHttpsUrl("https://music.example.com/watch?v=1"), true);
});

test("header sniffing distinguishes supported media and ignores extensions", () => {
  assert.equal(sniffContentType(Buffer.from([0xff, 0xd8, 0xff, 0x00])), "image/jpeg");
  assert.equal(
    sniffContentType(Buffer.from([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20])),
    "audio/mp4",
  );
  assert.equal(sniffContentType(Buffer.from("<script>alert(1)</script>")), null);
});

test("stored asset validation binds generation, bytes and custom identity", () => {
  const metadata = {
    generation: "12345",
    size: "1000",
    contentType: "video/mp4",
    metadata: {
      ownerId: "creator-1",
      reelId: "reel_1",
      assetKind: "media",
    },
  };
  const header = Buffer.from([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d]);
  assert.deepEqual(
    validateStoredAsset(metadata, header, {
      ownerId: "creator-1",
      reelId: "reel_1",
      assetKind: "media",
      contentType: "video/mp4",
      size: 1000,
      generation: "12345",
    }),
    { contentType: "video/mp4", generation: "12345", size: 1000 },
  );
  assert.throws(
    () => validateStoredAsset(metadata, header, {
      ownerId: "attacker",
      reelId: "reel_1",
      assetKind: "media",
      contentType: "video/mp4",
      size: 1000,
      generation: "12345",
    }),
    (error) => error.code === "failed-precondition",
  );
});

test("canonical storage paths never use client-provided filenames", () => {
  assert.equal(
    reelStoragePath("opaque-user", "abc_123", "video", "video/mp4"),
    "reels/opaque-user/abc_123/media.mp4",
  );
  assert.equal(
    reelStoragePath("opaque-user", "abc_123", "backingAudio", "audio/mpeg"),
    "reels/opaque-user/abc_123/backing-audio.mp3",
  );
});

test("report reasons are a closed moderation vocabulary", () => {
  assert.equal(validateReelReportReason("harassment"), "harassment");
  for (const value of ["copyright", " custom reason ", "", null]) {
    assert.throws(
      () => validateReelReportReason(value),
      (error) => error.code === "invalid-argument",
    );
  }
});

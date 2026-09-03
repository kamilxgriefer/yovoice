const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  DEFAULT_LIMITS,
  RESERVATION_TTL_MS,
  createReelService,
} = require("../reels/service");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const AUTHOR = "reel-security-author";

function publicProfile(uid) {
  return {
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: "",
    displayName: "Security Creator",
    displayNameSearch: "security creator",
    followerCount: 0,
    followingCount: 0,
    friendCount: 0,
    learningLanguages: [],
    nativeLanguage: "",
    photoUrl: null,
    premiumIdentity: false,
    schemaVersion: 1,
    spokenLanguages: [],
    statusMessage: "",
    uid,
    updatedAt: new Date(NOW_MS),
    username: "securitycreator",
    usernameSearch: "securitycreator",
    website: null,
  };
}

function videoPlan(overrides = {}) {
  return {
    requestId: "reel-security-reserve-1",
    mediaKind: "video",
    mediaContentType: "video/mp4",
    mediaSize: 4096,
    durationMs: 12_000,
    hasBackingAudio: false,
    audioContentType: null,
    audioSize: null,
    audioDurationMs: null,
    ...overrides,
  };
}

function composition(plan) {
  return {
    caption: "Trusted bytes only",
    crop: {
      scalePermille: 1000,
      offsetXPermille: 0,
      offsetYPermille: 0,
    },
    filter: "original",
    trimStartMs: 0,
    trimEndMs: plan.mediaKind === "video" ? plan.durationMs : 0,
    textOverlays: [],
    linkOverlays: [],
    originalAudioVolume: plan.mediaKind === "video" ? 100 : 0,
    backingAudioVolume: plan.hasBackingAudio ? 70 : 0,
    audioTrimStartMs: 0,
    audioRightsAttested: plan.hasBackingAudio,
    audioAttribution: plan.hasBackingAudio ? "Original creator audio" : "",
  };
}

function headerFor(contentType) {
  if (contentType === "image/jpeg") {
    return Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
  }
  if (contentType === "audio/mpeg") {
    return Buffer.from("ID3trusted-audio", "ascii");
  }
  return Buffer.from([
    0x00, 0x00, 0x00, 0x18,
    0x66, 0x74, 0x79, 0x70,
    0x69, 0x73, 0x6f, 0x6d,
  ]);
}

function defaultProbe(plan, overrides = () => ({})) {
  return async (input) => {
    const isAudio = input.kind === "audio";
    const isImage = input.kind === "image";
    return {
      detectedContentType: input.contentType,
      durationMs: isImage
        ? null
        : isAudio ? plan.audioDurationMs : plan.durationMs,
      generation: input.generation,
      hasAudio: isAudio || input.kind === "video",
      hasVideo: input.kind === "video",
      size: input.size,
      ...overrides(input),
    };
  };
}

async function setupFinalize({
  plan = videoPlan(),
  probeOverrides,
  metadataOverride,
  limits = DEFAULT_LIMITS,
} = {}) {
  const db = new InMemoryFirestore();
  const clockState = { nowMs: NOW_MS };
  const metadata = new Map();
  const metadataReads = new Map();
  const probeStats = { calls: 0 };
  const trustedProbe = defaultProbe(plan, probeOverrides);
  const storage = {
    async getMetadata(path) {
      const reads = (metadataReads.get(path) ?? 0) + 1;
      metadataReads.set(path, reads);
      const value = structuredClone(metadata.get(path));
      return metadataOverride?.({ path, reads, value }) ?? value;
    },
    async readHeader(path) {
      return headerFor(metadata.get(path).contentType);
    },
    async revokeDownloadTokens() {},
    async getSignedReadUrl() {
      return "https://storage.googleapis.com/test/reel";
    },
    async deleteObject() {},
  };
  const service = createReelService({
    db,
    FieldPath: { documentId() {} },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage,
    clock: () => clockState.nowMs,
    limits,
    probeMedia: async (input) => {
      probeStats.calls += 1;
      return trustedProbe(input);
    },
  });
  db.seed(`users/${AUTHOR}`, { uid: AUTHOR, displayName: "Private Creator" });
  db.seed(`publicProfiles/${AUTHOR}`, publicProfile(AUTHOR));
  const reservation = await service.reserveReelDraft({
    auth: { uid: AUTHOR, token: { email_verified: true } },
    data: plan,
  });
  metadata.set(reservation.mediaStoragePath, {
    generation: "101",
    size: String(plan.mediaSize),
    contentType: plan.mediaContentType,
    metadata: {
      ownerId: AUTHOR,
      reelId: reservation.reelId,
      assetKind: "media",
    },
  });
  if (plan.hasBackingAudio) {
    metadata.set(reservation.backingAudioStoragePath, {
      generation: "202",
      size: String(plan.audioSize),
      contentType: plan.audioContentType,
      metadata: {
        ownerId: AUTHOR,
        reelId: reservation.reelId,
        assetKind: "backingAudio",
      },
    });
  }
  const request = {
    auth: { uid: AUTHOR, token: { email_verified: true } },
    data: {
      requestId: "reel-security-finalize-1",
      reelId: reservation.reelId,
      mediaGeneration: "101",
      backingAudioGeneration: plan.hasBackingAudio ? "202" : null,
      composition: composition(plan),
    },
  };
  return {
    clockState,
    db,
    metadataReads,
    probeStats,
    request,
    reservation,
    service,
  };
}

function retryTransaction(db, transactionNumber, betweenAttempts) {
  const original = db.runTransaction.bind(db);
  let calls = 0;
  db.runTransaction = async (callback) => {
    calls += 1;
    if (calls !== transactionNumber) return original(callback);
    const retry = new Error("synthetic Firestore retry");
    try {
      await original(async (transaction) => {
        await callback(transaction);
        throw retry;
      });
    } catch (error) {
      if (error !== retry) throw error;
    }
    await betweenAttempts();
    return original(callback);
  };
}

function rateState(db, scope) {
  return db.paths("privateRateLimits/")
    .map((path) => db.data(path))
    .find((value) => value.scope === scope);
}

test("finalize requires a trusted image probe, including exact byte facts",
  async () => {
    const plan = videoPlan({
      mediaKind: "image",
      mediaContentType: "image/jpeg",
      durationMs: 0,
    });
    const valid = await setupFinalize({ plan });
    assert.deepEqual(await valid.service.finalizeReelDraft(valid.request), {
      reelId: valid.reservation.reelId,
      published: true,
    });
    assert.equal(valid.probeStats.calls, 1);
    assert.deepEqual(await valid.service.finalizeReelDraft(valid.request), {
      reelId: valid.reservation.reelId,
      published: true,
    });
    assert.equal(valid.probeStats.calls, 1, "completed replay must skip probe");
    assert.equal(rateState(valid.db, "reel.finalize").count, 1);

    for (const probeOverrides of [
      () => ({ generation: "999" }),
      () => ({ size: plan.mediaSize + 1 }),
      () => ({ detectedContentType: "image/png" }),
      () => ({ durationMs: 1, hasAudio: true }),
    ]) {
      const scenario = await setupFinalize({ plan, probeOverrides });
      await assert.rejects(
        scenario.service.finalizeReelDraft(scenario.request),
        (error) => error.code === "failed-precondition",
      );
      assert.equal(
        scenario.db.data(`reels/${scenario.reservation.reelId}`),
        undefined,
      );
    }
  });

test("malformed composition and active restrictions fail before media probe",
  async () => {
    const malformed = await setupFinalize();
    malformed.request.data.composition.filter = "unsupported-filter";
    await assert.rejects(
      malformed.service.finalizeReelDraft(malformed.request),
      (error) => error.code === "invalid-argument",
    );
    assert.equal(malformed.probeStats.calls, 0);
    assert.equal(rateState(malformed.db, "reel.finalize"), undefined);

    const restricted = await setupFinalize();
    restricted.db.seed(`restrictions/${AUTHOR}`, {
      type: "communicationMute",
      expiresAt: null,
    });
    await assert.rejects(
      restricted.service.finalizeReelDraft(restricted.request),
      (error) => error.code === "permission-denied",
    );
    assert.equal(restricted.probeStats.calls, 0);
    assert.equal(rateState(restricted.db, "reel.finalize"), undefined);
  });

test("each failed trusted probe consumes the finalize attempt budget", async () => {
  const scenario = await setupFinalize({
    limits: {
      ...DEFAULT_LIMITS,
      finalize: { maxEvents: 2, windowMs: 60_000 },
    },
    probeOverrides: () => ({ detectedContentType: "video/webm" }),
  });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    await assert.rejects(
      scenario.service.finalizeReelDraft(scenario.request),
      (error) => error.code === "failed-precondition",
    );
  }
  await assert.rejects(
    scenario.service.finalizeReelDraft(scenario.request),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(scenario.probeStats.calls, 2);
  assert.equal(rateState(scenario.db, "reel.finalize").count, 2);
  assert.equal(scenario.db.paths("integrityPreflightLedgers/").length, 1);
});

test("a Firestore retry commits one preflight charge and one probe", async () => {
  const scenario = await setupFinalize();
  const retryMs = NOW_MS + 1_000;
  retryTransaction(scenario.db, 1, async () => {
    scenario.clockState.nowMs = retryMs;
  });

  await scenario.service.finalizeReelDraft(scenario.request);
  assert.equal(scenario.probeStats.calls, 1);
  assert.equal(rateState(scenario.db, "reel.finalize").count, 1);
  assert.equal(
    scenario.db.data(`reels/${scenario.reservation.reelId}`).publishedAt.getTime(),
    retryMs,
  );
});

test("finalize rejects MIME spoofing, duration drift and video without a track",
  async () => {
    for (const probeOverrides of [
      () => ({ detectedContentType: "video/webm" }),
      () => ({ durationMs: 15_000 }),
      () => ({ hasAudio: true, hasVideo: false }),
    ]) {
      const scenario = await setupFinalize({ probeOverrides });
      await assert.rejects(
        scenario.service.finalizeReelDraft(scenario.request),
        (error) => error.code === "failed-precondition",
      );
      assert.equal(
        scenario.db.data(`reels/${scenario.reservation.reelId}`),
        undefined,
      );
    }
  });

test("backing audio must be audio-only and match its reserved type", async () => {
  const plan = videoPlan({
    hasBackingAudio: true,
    audioContentType: "audio/mpeg",
    audioSize: 2048,
    audioDurationMs: 8_000,
  });
  for (const audioOverride of [
    { detectedContentType: "audio/mp4" },
    { hasAudio: false },
    { hasVideo: true },
    { generation: "999" },
    { size: 2049 },
  ]) {
    const scenario = await setupFinalize({
      plan,
      probeOverrides: (input) => input.kind === "audio" ? audioOverride : {},
    });
    await assert.rejects(
      scenario.service.finalizeReelDraft(scenario.request),
      (error) => error.code === "failed-precondition",
    );
    assert.equal(
      scenario.db.data(`reels/${scenario.reservation.reelId}`),
      undefined,
    );
  }
});

test("metadata replacement after the trusted probe cannot be published",
  async () => {
    const scenario = await setupFinalize({
      metadataOverride: ({ reads, value }) => reads === 2
        ? { ...value, generation: "999" }
        : value,
    });
    await assert.rejects(
      scenario.service.finalizeReelDraft(scenario.request),
      (error) => error.code === "failed-precondition",
    );
    assert.equal(scenario.metadataReads.values().next().value, 2);
    assert.equal(
      scenario.db.data(`reels/${scenario.reservation.reelId}`),
      undefined,
    );
  });

test("a changed reservation cannot reuse a prior trusted probe", async () => {
  const scenario = await setupFinalize();
  retryTransaction(scenario.db, 2, async () => {
    const path = `reelUploadReservations/${scenario.reservation.reelId}`;
    const reservation = scenario.db.data(path);
    scenario.db.seed(path, { ...reservation, durationMs: 11_000 });
  });
  await assert.rejects(
    scenario.service.finalizeReelDraft(scenario.request),
    (error) => error.code === "aborted",
  );
  assert.equal(
    scenario.db.data(`reels/${scenario.reservation.reelId}`),
    undefined,
  );
});

test("a transaction retry cannot publish after reservation expiry", async () => {
  const scenario = await setupFinalize();
  scenario.clockState.nowMs = NOW_MS + RESERVATION_TTL_MS - 1;
  retryTransaction(scenario.db, 2, async () => {
    scenario.clockState.nowMs = NOW_MS + RESERVATION_TTL_MS;
  });
  await assert.rejects(
    scenario.service.finalizeReelDraft(scenario.request),
    (error) => error.code === "aborted",
  );
  assert.equal(
    scenario.db.data(`reels/${scenario.reservation.reelId}`),
    undefined,
  );
  assert.notEqual(
    scenario.db.data(`reelUploadReservations/${scenario.reservation.reelId}`),
    undefined,
  );
});

test("a successful retry uses one fresh attempt time everywhere", async () => {
  const scenario = await setupFinalize();
  const secondAttemptMs = NOW_MS + 5_000;
  retryTransaction(scenario.db, 2, async () => {
    scenario.clockState.nowMs = secondAttemptMs;
  });
  await scenario.service.finalizeReelDraft(scenario.request);
  const reel = scenario.db.data(`reels/${scenario.reservation.reelId}`);
  assert.equal(reel.publishedAt.getTime(), secondAttemptMs);
  assert.equal(reel.updatedAt.getTime(), secondAttemptMs);
  assert.equal(
    reel.sortKey,
    `${String(secondAttemptMs).padStart(13, "0")}_${scenario.reservation.reelId}`,
  );
});

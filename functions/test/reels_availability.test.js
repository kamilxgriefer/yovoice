const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const {
  HOUR_MS,
  MAX_REEL_AVAILABILITY_HOURS,
  MIN_REEL_AVAILABILITY_HOURS,
  PERMANENT_AVAILABILITY,
  REEL_AVAILABILITY_SCHEMA_VERSION,
  validateAvailabilityHours,
  validateAvailabilitySnapshot,
} = require("../reels/availability");
const {
  MEDIA_GRANT_TTL_MS,
  REEL_CLEANUP_BASE_BACKOFF_MS,
  REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH,
  REEL_CLEANUP_LEASE_MS,
  REEL_CLEANUP_MAX_ATTEMPTS,
  REEL_EXPIRY_EVIDENCE_RETENTION_MS,
  RESERVATION_TTL_MS,
  createReelService,
} = require("../reels/service");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const AUTHOR = "availability-author";
const VIEWER = "availability-viewer";

function publicProfile(uid) {
  return {
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: "",
    displayName: `Creator ${uid}`,
    displayNameSearch: `creator ${uid}`,
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
    username: uid,
    usernameSearch: uid,
    website: null,
  };
}

function imagePlan(requestId = "availability-reserve-0001") {
  return {
    requestId,
    mediaKind: "image",
    mediaContentType: "image/jpeg",
    mediaSize: 1024,
    durationMs: 0,
    hasBackingAudio: false,
    audioContentType: null,
    audioSize: null,
    audioDurationMs: null,
  };
}

function composition() {
  return {
    caption: "Availability contract",
    crop: {
      scalePermille: 1000,
      offsetXPermille: 0,
      offsetYPermille: 0,
    },
    filter: "original",
    trimStartMs: 0,
    trimEndMs: 0,
    textOverlays: [],
    linkOverlays: [],
    originalAudioVolume: 0,
    backingAudioVolume: 0,
    audioTrimStartMs: 0,
    audioRightsAttested: false,
    audioAttribution: "",
  };
}

function publishedReel(reelId, { authorId = AUTHOR, publishedAtMs = NOW_MS } = {}) {
  return {
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId,
    authorName: `Creator ${authorId}`,
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "101",
      durationMs: 0,
      storagePath: `reels/${authorId}/${reelId}/media.jpg`,
    },
    backingAudio: null,
    composition: composition(),
    sortKey: `${String(publishedAtMs).padStart(13, "0")}_${reelId}`,
    publishedAt: new Date(publishedAtMs),
    updatedAt: new Date(publishedAtMs),
  };
}

function publishedAvailabilityDocument(
  reelId,
  {
    authorId = AUTHOR,
    availabilityHours = 24,
    createdAtMs = NOW_MS - 1000,
    publishedAtMs = NOW_MS,
  } = {},
) {
  return {
    schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
    status: "published",
    ownerId: authorId,
    reelId,
    availabilityHours,
    createdAt: new Date(createdAtMs),
    publishedAt: new Date(publishedAtMs),
    ...(availabilityHours === PERMANENT_AVAILABILITY
      ? {}
      : { expiresAt: new Date(createdAtMs + availabilityHours * HOUR_MS) }),
    updatedAt: new Date(publishedAtMs),
  };
}

function fixture({
  nowMs = NOW_MS,
  failFirstRevoke = false,
  failEveryRevoke = false,
  failEveryDelete = false,
  clock = null,
} = {}) {
  const db = new InMemoryFirestore();
  const clockState = { nowMs };
  const metadata = new Map();
  const grants = [];
  const revocations = [];
  const deletions = [];
  let revokeAttempts = 0;
  const storage = {
    async getMetadata(path) {
      return structuredClone(metadata.get(path));
    },
    async readHeader() {
      return Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
    },
    async revokeDownloadTokens(path) {
      revokeAttempts += 1;
      if (failEveryRevoke || (failFirstRevoke && revokeAttempts === 1)) {
        throw new Error("synthetic token revocation failure");
      }
      revocations.push(path);
    },
    async getSignedReadUrl(path, options) {
      grants.push({ path, ...options });
      return "https://storage.googleapis.com/yovoice-private/reel";
    },
    async deleteObject(path, options) {
      if (failEveryDelete) throw new Error("synthetic object deletion failure");
      deletions.push({ path, options });
    },
  };
  const service = createReelService({
    db,
    FieldPath: { documentId: () => "__name__" },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage,
    clock: clock ?? (() => clockState.nowMs),
    probeMedia: async (input) => ({
      detectedContentType: input.contentType,
      durationMs: input.kind === "image" ? null : 1000,
      generation: input.generation,
      hasAudio: input.kind === "audio",
      hasVideo: input.kind === "video",
      size: input.size,
    }),
  });
  for (const uid of [AUTHOR, VIEWER]) {
    db.seed(`users/${uid}`, { uid });
    db.seed(`publicProfiles/${uid}`, publicProfile(uid));
  }
  function seedPublished(
    reelId,
    availability = undefined,
    reelOptions = {},
  ) {
    const reel = publishedReel(reelId, reelOptions);
    db.seed(`reels/${reelId}`, reel);
    if (availability !== undefined) {
      db.seed(
        `reelAvailability/${reelId}`,
        publishedAvailabilityDocument(reelId, {
          authorId: reel.authorId,
          publishedAtMs: reel.publishedAt.getTime(),
          ...availability,
        }),
      );
    }
    metadata.set(reel.media.storagePath, {
      generation: reel.media.generation,
      size: String(reel.media.size),
      contentType: reel.media.contentType,
      metadata: {
        ownerId: reel.authorId,
        reelId,
        assetKind: "media",
      },
    });
    return reel;
  }
  return {
    clockState,
    db,
    deletions,
    grants,
    metadata,
    revocations,
    seedPublished,
    service,
  };
}

function auth(uid = AUTHOR, verified = true) {
  return { uid, token: { email_verified: verified } };
}

function listRequest() {
  return {
    auth: auth(VIEWER, false),
    data: { cursor: null, limit: 20 },
  };
}

test("independent publishers retain canonical ownership for every viewer", async () => {
  const scenario = fixture();
  const thirdViewer = "independent-viewer";
  scenario.db.seed(`users/${thirdViewer}`, { uid: thirdViewer });
  const sameRequestId = "multi-publisher-same-request";
  const first = await scenario.service.reserveReelDraftV2({
    auth: auth(AUTHOR),
    data: { ...imagePlan(sameRequestId), availabilityHours: 24 },
  });
  const second = await scenario.service.reserveReelDraftV2({
    auth: auth(VIEWER),
    data: { ...imagePlan(sameRequestId), availabilityHours: 24 },
  });
  assert.notEqual(first.reelId, second.reelId,
    "retry identity is scoped to the authenticated publisher, not global");
  const finalizeData = (reservation) => ({
    requestId: "multi-publisher-same-finalize",
    reelId: reservation.reelId,
    mediaGeneration: "123",
    backingAudioGeneration: null,
    composition: composition(),
  });
  await assert.rejects(scenario.service.finalizeReelDraftV2({
    auth: auth(VIEWER),
    data: finalizeData(first),
  }), (error) => error.code === "data-loss");

  async function publishReservation(uid, reservation, data = finalizeData(reservation)) {
    scenario.metadata.set(reservation.mediaStoragePath, {
      generation: "123",
      size: "1024",
      contentType: "image/jpeg",
      metadata: { ownerId: uid, reelId: reservation.reelId, assetKind: "media" },
    });
    await scenario.service.finalizeReelDraftV2({ auth: auth(uid), data });
    assert.equal(scenario.db.data(`reels/${reservation.reelId}`).authorId, uid);
  }
  await publishReservation(AUTHOR, first);
  await publishReservation(VIEWER, second);
  const another = await scenario.service.reserveReelDraftV2({
    auth: auth(VIEWER),
    data: { ...imagePlan("multi-publisher-second-reel"), availabilityHours: 24 },
  });
  await publishReservation(VIEWER, another, {
    ...finalizeData(another),
    requestId: "multi-publisher-second-finalize",
  });
  const expectedOwners = new Map([
    [first.reelId, AUTHOR],
    [second.reelId, VIEWER],
    [another.reelId, VIEWER],
  ]);
  for (const uid of [AUTHOR, VIEWER, thirdViewer]) {
    const page = await scenario.service.listReelsV2({
      auth: auth(uid, false),
      data: { limit: 10, cursor: null },
    });
    assert.equal(page.items.length, 3);
    for (const item of page.items) {
      assert.equal(item.authorId, expectedOwners.get(item.id));
      assert.equal(item.authorName, `Creator ${item.authorId}`);
    }
  }
  await assert.rejects(scenario.service.deleteReel({
    auth: auth(thirdViewer),
    data: { reelId: first.reelId, requestId: "multi-publisher-foreign-delete" },
  }), (error) => error.code === "permission-denied");
  await assert.rejects(scenario.service.reserveReelDraftV2({
    auth: auth(VIEWER),
    data: {
      ...imagePlan("multi-publisher-forged-owner"),
      availabilityHours: 24,
      ownerId: AUTHOR,
    },
  }), (error) => error.code === "invalid-argument");
});

test("availability accepts only 24-720 whole hours or permanent", () => {
  assert.equal(
    validateAvailabilityHours(MIN_REEL_AVAILABILITY_HOURS),
    MIN_REEL_AVAILABILITY_HOURS,
  );
  assert.equal(
    validateAvailabilityHours(MAX_REEL_AVAILABILITY_HOURS),
    MAX_REEL_AVAILABILITY_HOURS,
  );
  assert.equal(
    validateAvailabilityHours(PERMANENT_AVAILABILITY),
    PERMANENT_AVAILABILITY,
  );
  for (const value of [23, 721, 24.5, "24", null, undefined]) {
    assert.throws(
      () => validateAvailabilityHours(value),
      (error) => error.code === "invalid-argument",
    );
  }
});

test("expiry, feed and retry queries have production indexes and TTL", () => {
  const indexFile = JSON.parse(readFileSync(
    path.resolve(__dirname, "../../firestore.indexes.json"),
    "utf8",
  ));
  const availabilityIndexes = indexFile.indexes.filter(
    (index) => index.collectionGroup === "reelAvailability",
  );
  assert.equal(availabilityIndexes.length, 1);
  assert.equal(availabilityIndexes[0].queryScope, "COLLECTION");
  assert.deepEqual(availabilityIndexes[0].fields, [
    { fieldPath: "status", order: "ASCENDING" },
    { fieldPath: "expiresAt", order: "ASCENDING" },
  ]);
  assert.ok(indexFile.indexes.some((index) =>
    index.collectionGroup === "reels" &&
    JSON.stringify(index.fields) === JSON.stringify([
      { fieldPath: "status", order: "ASCENDING" },
      { fieldPath: "sortKey", order: "DESCENDING" },
    ])));
  for (const fieldPath of ["nextAttemptAt", "leaseUntil"]) {
    assert.ok(indexFile.indexes.some((index) =>
      index.collectionGroup === "reelCleanupOutbox" &&
      JSON.stringify(index.fields) === JSON.stringify([
        { fieldPath: "status", order: "ASCENDING" },
        { fieldPath, order: "ASCENDING" },
      ])));
  }
  assert.ok(indexFile.fieldOverrides.some((override) =>
    override.collectionGroup === "reelCleanupOutbox" &&
    override.fieldPath === "deleteAfter" &&
    override.ttl === true));
});

test("availability sidecars are exact and deadlines are derived from createdAt", () => {
  const reelId = "sidecar-exact";
  const data = publishedAvailabilityDocument(reelId);
  const snapshot = {
    id: reelId,
    exists: true,
    data: () => data,
  };
  const validated = validateAvailabilitySnapshot(snapshot, { required: true });
  assert.equal(validated.expiresAtMs, NOW_MS - 1000 + 24 * HOUR_MS);

  for (const malformed of [
    { ...data, forged: true },
    { ...data, expiresAt: new Date(data.expiresAt.getTime() + 1) },
    { ...data, updatedAt: new Date(data.publishedAt.getTime() - 1) },
    { ...data, ownerId: "" },
  ]) {
    assert.throws(
      () => validateAvailabilitySnapshot({ ...snapshot, data: () => malformed }),
      (error) => error.code === "data-loss",
    );
  }
});

test("v1 stays wire-exact and preserves Build 19 permanent semantics", async () => {
  const legacy = fixture();
  const legacyResult = await legacy.service.reserveReelDraft({
    auth: auth(),
    data: imagePlan("legacy-reserve-0001"),
  });
  assert.deepEqual(Object.keys(legacyResult).sort(), [
    "backingAudioStoragePath",
    "expiresAtMillis",
    "mediaStoragePath",
    "reelId",
  ]);
  assert.deepEqual(
    legacy.db.data(`reelAvailability/${legacyResult.reelId}`),
    {
      schemaVersion: 2,
      status: "reserved",
      ownerId: AUTHOR,
      reelId: legacyResult.reelId,
      availabilityHours: PERMANENT_AVAILABILITY,
      createdAt: new Date(NOW_MS),
      updatedAt: new Date(NOW_MS),
    },
  );
  await assert.rejects(
    legacy.service.reserveReelDraft({
      auth: auth(),
      data: { ...imagePlan("legacy-extra-0001"), availabilityHours: 24 },
    }),
    (error) => error.code === "invalid-argument",
  );

  const current = fixture();
  const result = await current.service.reserveReelDraftV2({
    auth: auth(),
    data: { ...imagePlan("current-reserve-0001"), availabilityHours: 24 },
  });
  assert.deepEqual(await current.service.reserveReelDraftV2({
    auth: auth(),
    data: { ...imagePlan("current-reserve-0001"), availabilityHours: 24 },
  }), result);
  assert.equal(result.schemaVersion, 2);
  assert.equal(result.contentExpiresAtMillis, NOW_MS + 24 * HOUR_MS);
  const reservation = current.db.data(`reelUploadReservations/${result.reelId}`);
  assert.equal(reservation.schemaVersion, 1);
  assert.equal(Object.hasOwn(reservation, "availabilityHours"), false);
  assert.deepEqual(
    current.db.data(`reelAvailability/${result.reelId}`),
    {
      schemaVersion: 2,
      status: "reserved",
      ownerId: AUTHOR,
      reelId: result.reelId,
      availabilityHours: 24,
      createdAt: new Date(NOW_MS),
      updatedAt: new Date(NOW_MS),
    },
  );
});

test("v2 finalization anchors expiry to reserve and old finalize honors v2", async () => {
  for (const useV2Finalize of [true, false]) {
    const scenario = fixture();
    const reserve = await scenario.service.reserveReelDraftV2({
      auth: auth(),
      data: {
        ...imagePlan(`mixed-reserve-${useV2Finalize ? "v2" : "v1"}`),
        availabilityHours: 24,
      },
    });
    scenario.metadata.set(reserve.mediaStoragePath, {
      generation: "101",
      size: "1024",
      contentType: "image/jpeg",
      metadata: { ownerId: AUTHOR, reelId: reserve.reelId, assetKind: "media" },
    });
    scenario.clockState.nowMs = NOW_MS + 5 * 60 * 1000;
    const request = {
      auth: auth(),
      data: {
        requestId: `mixed-finalize-${useV2Finalize ? "v2" : "v1"}`,
        reelId: reserve.reelId,
        mediaGeneration: "101",
        backingAudioGeneration: null,
        composition: composition(),
      },
    };
    const result = useV2Finalize
      ? await scenario.service.finalizeReelDraftV2(request)
      : await scenario.service.finalizeReelDraft(request);
    assert.equal(result.reelId, reserve.reelId);
    assert.equal(result.published, true);
    if (useV2Finalize) {
      assert.equal(result.expiresAtMillis, NOW_MS + 24 * HOUR_MS);
    } else {
      assert.deepEqual(Object.keys(result).sort(), ["published", "reelId"]);
    }
    const availability = scenario.db.data(`reelAvailability/${reserve.reelId}`);
    assert.equal(availability.status, "published");
    assert.equal(availability.expiresAt.getTime(), NOW_MS + 24 * HOUR_MS);
    assert.equal(
      scenario.db.data(`reels/${reserve.reelId}`).schemaVersion,
      1,
    );
    const replay = useV2Finalize
      ? await scenario.service.finalizeReelDraftV2(request)
      : await scenario.service.finalizeReelDraft(request);
    assert.deepEqual(replay, result);
  }
});

test("Build 19 reserve remains permanent through either finalize and v1/v2 reads", async () => {
  for (const useV2Finalize of [false, true]) {
    const scenario = fixture();
    const suffix = useV2Finalize ? "v2" : "v1";
    const reserve = await scenario.service.reserveReelDraft({
      auth: auth(),
      data: imagePlan(`build19-reserve-${suffix}`),
    });
    scenario.metadata.set(reserve.mediaStoragePath, {
      generation: "101",
      size: "1024",
      contentType: "image/jpeg",
      metadata: { ownerId: AUTHOR, reelId: reserve.reelId, assetKind: "media" },
    });
    const request = {
      auth: auth(),
      data: {
        requestId: `build19-finalize-${suffix}`,
        reelId: reserve.reelId,
        mediaGeneration: "101",
        backingAudioGeneration: null,
        composition: composition(),
      },
    };
    const finalized = useV2Finalize
      ? await scenario.service.finalizeReelDraftV2(request)
      : await scenario.service.finalizeReelDraft(request);
    if (useV2Finalize) {
      assert.equal(finalized.availabilityHours, PERMANENT_AVAILABILITY);
      assert.equal(finalized.expiresAtMillis, null);
    } else {
      assert.deepEqual(Object.keys(finalized).sort(), ["published", "reelId"]);
    }
    const availability = scenario.db.data(
      `reelAvailability/${reserve.reelId}`,
    );
    assert.equal(availability.status, "published");
    assert.equal(availability.availabilityHours, PERMANENT_AVAILABILITY);
    assert.equal(Object.hasOwn(availability, "expiresAt"), false);

    const legacyFeed = await scenario.service.listReels(listRequest());
    assert.ok(legacyFeed.items.some(({ id }) => id === reserve.reelId));
    const currentFeed = await scenario.service.listReelsV2(listRequest());
    const currentItem = currentFeed.items.find(({ id }) => id === reserve.reelId);
    assert.deepEqual(currentItem.availability, {
      schemaVersion: 2,
      availabilityHours: PERMANENT_AVAILABILITY,
      expiresAtMillis: null,
    });
    const legacyGrant = await scenario.service.getReelMediaAccess({
      auth: auth(VIEWER, false),
      data: { reelId: reserve.reelId, asset: "media" },
    });
    const currentGrant = await scenario.service.getReelMediaAccessV2({
      auth: auth(VIEWER, false),
      data: { reelId: reserve.reelId, asset: "media" },
    });
    assert.equal(legacyGrant.schemaVersion, 1);
    assert.equal(currentGrant.availabilityHours, PERMANENT_AVAILABILITY);
    assert.equal(currentGrant.contentExpiresAtMillis, null);
  }
});

test("v2 finalize grandfathers a pre-sidecar v1 reservation as permanent", async () => {
  const scenario = fixture();
  const reserve = await scenario.service.reserveReelDraft({
    auth: auth(),
    data: imagePlan("no-upgrade-reserve-0001"),
  });
  await scenario.db.runTransaction(async (transaction) => {
    transaction.delete(scenario.db.doc(`reelAvailability/${reserve.reelId}`));
  });
  scenario.metadata.set(reserve.mediaStoragePath, {
    generation: "101",
    size: "1024",
    contentType: "image/jpeg",
    metadata: { ownerId: AUTHOR, reelId: reserve.reelId, assetKind: "media" },
  });
  const result = await scenario.service.finalizeReelDraftV2({
    auth: auth(),
    data: {
      requestId: "no-upgrade-finalize-0001",
      reelId: reserve.reelId,
      mediaGeneration: "101",
      backingAudioGeneration: null,
      composition: composition(),
    },
  });
  assert.equal(result.availabilityHours, PERMANENT_AVAILABILITY);
  assert.equal(result.expiresAtMillis, null);
  assert.deepEqual(
    scenario.db.data(`reelAvailability/${reserve.reelId}`),
    {
      schemaVersion: 2,
      status: "published",
      ownerId: AUTHOR,
      reelId: reserve.reelId,
      availabilityHours: PERMANENT_AVAILABILITY,
      createdAt: new Date(NOW_MS),
      updatedAt: new Date(NOW_MS),
      publishedAt: new Date(NOW_MS),
    },
  );
});

test("both feeds fail closed at the exact deadline and v2 labels legacy", async () => {
  const scenario = fixture();
  scenario.seedPublished("legacy-reel");
  scenario.seedPublished("permanent-reel", {
    availabilityHours: PERMANENT_AVAILABILITY,
  });
  scenario.seedPublished("active-reel", { createdAtMs: NOW_MS - 1000 });
  scenario.seedPublished("deadline-reel", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });

  const legacy = await scenario.service.listReels(listRequest());
  assert.deepEqual(
    new Set(legacy.items.map(({ id }) => id)),
    new Set(["legacy-reel", "permanent-reel", "active-reel"]),
  );
  assert.equal(Object.hasOwn(legacy, "schemaVersion"), false);
  assert.equal(Object.hasOwn(legacy.items[0], "availability"), false);

  const current = await scenario.service.listReelsV2(listRequest());
  assert.equal(current.schemaVersion, 2);
  const legacyItem = current.items.find(({ id }) => id === "legacy-reel");
  assert.deepEqual(legacyItem.availability, {
    schemaVersion: 1,
    availabilityHours: PERMANENT_AVAILABILITY,
    expiresAtMillis: null,
  });
});

test("feed rechecks timed availability at response time", async () => {
  let clockReads = 0;
  const scenario = fixture({
    clock: () => {
      clockReads += 1;
      return clockReads < 3 ? NOW_MS : NOW_MS + 1;
    },
  });
  scenario.seedPublished("expires-during-list", {
    createdAtMs: NOW_MS - 24 * HOUR_MS + 1,
  });

  assert.deepEqual(
    (await scenario.service.listReels(listRequest())).items,
    [],
  );
  assert.equal(clockReads, 3);
});

test("feed and media access recheck restrictions and both block directions", async () => {
  for (const blockedPath of [
    `users/${VIEWER}/blocked/${AUTHOR}`,
    `users/${AUTHOR}/blocked/${VIEWER}`,
  ]) {
    const blocked = fixture();
    blocked.seedPublished("blocked-reel", { createdAtMs: NOW_MS - 1000 });
    blocked.db.seed(blockedPath, { createdAt: new Date(NOW_MS) });
    assert.deepEqual((await blocked.service.listReels(listRequest())).items, []);
    await assert.rejects(
      blocked.service.getReelMediaAccess({
        auth: auth(VIEWER, false),
        data: { reelId: "blocked-reel", asset: "media" },
      }),
      (error) => error.code === "failed-precondition",
    );
  }

  const restricted = fixture();
  restricted.seedPublished("restricted-reel", { createdAtMs: NOW_MS - 1000 });
  restricted.db.seed(`restrictions/${AUTHOR}`, {
    type: "communicationMute",
    expiresAt: null,
  });
  assert.deepEqual((await restricted.service.listReels(listRequest())).items, []);
  await assert.rejects(
    restricted.service.getReelMediaAccess({
      auth: auth(VIEWER, false),
      data: { reelId: "restricted-reel", asset: "media" },
    }),
    (error) => error.code === "permission-denied",
  );
});

test("media grants are capped by content expiry and denied at the boundary", async () => {
  const scenario = fixture();
  const createdAtMs = NOW_MS - 24 * HOUR_MS + 1000;
  scenario.seedPublished("grant-reel", { createdAtMs });
  const contentDeadline = createdAtMs + 24 * HOUR_MS;
  const result = await scenario.service.getReelMediaAccessV2({
    auth: auth(VIEWER, false),
    data: { reelId: "grant-reel", asset: "media" },
  });
  assert.equal(result.schemaVersion, 2);
  assert.equal(result.expiresAtMillis, contentDeadline);
  assert.equal(result.contentExpiresAtMillis, contentDeadline);
  assert.ok(result.expiresAtMillis < NOW_MS + MEDIA_GRANT_TTL_MS);
  assert.equal(scenario.grants[0].expiresAtMs, contentDeadline);
  const legacyResult = await scenario.service.getReelMediaAccess({
    auth: auth(VIEWER, false),
    data: { reelId: "grant-reel", asset: "media" },
  });
  assert.deepEqual(Object.keys(legacyResult).sort(), [
    "expiresAtMillis",
    "generation",
    "schemaVersion",
    "url",
  ]);
  assert.equal(legacyResult.schemaVersion, 1);

  scenario.clockState.nowMs = contentDeadline;
  await assert.rejects(
    scenario.service.getReelMediaAccess({
      auth: auth(VIEWER, false),
      data: { reelId: "grant-reel", asset: "media" },
    }),
    (error) => error.code === "failed-precondition",
  );
});

test("expired Reels remain reportable by id without granting media", async () => {
  const scenario = fixture();
  scenario.seedPublished("expired-report", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });
  const result = await scenario.service.createReelReport({
    auth: auth(VIEWER, false),
    data: {
      reelId: "expired-report",
      requestId: "expired-report-0001",
      reason: "spam",
      note: "",
    },
  });
  assert.equal(result.created, true);
  assert.equal(
    scenario.db.data(`reports/${result.reportId}`).reportedUserId,
    AUTHOR,
  );
  await assert.rejects(
    scenario.service.getReelMediaAccess({
      auth: auth(VIEWER, false),
      data: { reelId: "expired-report", asset: "media" },
    }),
    (error) => error.code === "failed-precondition",
  );
  assert.notEqual(scenario.db.data("reels/expired-report"), undefined);
});

test("expiry retries with backoff, then purges originals after retention", async () => {
  const scenario = fixture({ failFirstRevoke: true });
  scenario.seedPublished("sweep-reel", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });
  const firstSweep = await scenario.service.expirePublishedReels({ limit: 10 });
  assert.deepEqual(firstSweep.expired, ["sweep-reel"]);
  assert.deepEqual(firstSweep.failed, []);
  const availability = scenario.db.data("reelAvailability/sweep-reel");
  assert.equal(availability.status, "expired");
  assert.equal(scenario.db.data("reels/sweep-reel").status, "expired");
  assert.equal(Object.hasOwn(availability, "expiresAt"), false);
  const outboxPath = scenario.db.paths("reelCleanupOutbox/")[0];
  assert.equal(
    scenario.db.data(outboxPath).retentionPolicy,
    "retainOriginalsForModeration",
  );
  assert.deepEqual(
    (await scenario.service.expirePublishedReels({ limit: 10 })).expired,
    [],
  );

  await assert.rejects(
    scenario.service.processCleanupOutbox(outboxPath.split("/").at(-1)),
    /synthetic token revocation failure/u,
  );
  let outbox = scenario.db.data(outboxPath);
  assert.equal(outbox.status, "pending");
  assert.equal(outbox.attemptCount, 1);
  assert.equal(
    outbox.nextAttemptAt.getTime(),
    NOW_MS + REEL_CLEANUP_BASE_BACKOFF_MS,
  );
  assert.equal(
    (await scenario.service.processCleanupOutbox(
      outboxPath.split("/").at(-1),
    )).deferred,
    true,
  );

  scenario.clockState.nowMs += REEL_CLEANUP_BASE_BACKOFF_MS;
  const retained = await scenario.service.processCleanupOutbox(
    outboxPath.split("/").at(-1),
  );
  assert.equal(retained.retained, true);
  assert.equal(retained.originalsRetained, true);
  outbox = scenario.db.data(outboxPath);
  assert.equal(outbox.status, "pending");
  assert.equal(outbox.phase, "purge");
  assert.equal(scenario.deletions.length, 0);
  assert.equal(scenario.db.data("reels/sweep-reel").media.size, 1024);

  scenario.clockState.nowMs = outbox.purgeAt.getTime();
  const completed = await scenario.service.processCleanupOutbox(
    outboxPath.split("/").at(-1),
  );
  assert.equal(completed.completed, true);
  assert.equal(scenario.db.data(outboxPath).status, "completed");
  assert.equal(scenario.deletions.length, 1);
  assert.equal(scenario.db.data("reelAvailability/sweep-reel"), undefined);
  const evidence = scenario.db.data("reels/sweep-reel");
  assert.equal(evidence.status, "expired");
  assert.equal(Object.hasOwn(evidence, "media"), false);
  assert.match(
    evidence.moderationEvidence.metadataFingerprint,
    /^[a-f0-9]{64}$/u,
  );
  const report = await scenario.service.createReelReport({
    auth: auth(VIEWER, false),
    data: {
      reelId: "sweep-reel",
      requestId: "purged-report-0001",
      reason: "spam",
      note: "reported from history",
    },
  });
  assert.equal(report.created, true);
  assert.equal(
    scenario.db.data(`reports/${report.reportId}`).reportedUserId,
    AUTHOR,
  );
  await assert.rejects(
    scenario.service.getReelMediaAccess({
      auth: auth(VIEWER, false),
      data: { reelId: "sweep-reel", asset: "media" },
    }),
    (error) => error.code === "failed-precondition",
  );
  assert.deepEqual(await scenario.service.deleteReel({
    auth: auth(),
    data: {
      reelId: "sweep-reel",
      requestId: "purged-delete-0001",
    },
  }), { reelId: "sweep-reel", deleted: true });
  assert.equal(scenario.db.data("reels/sweep-reel").status, "deleted");
  assert.equal(scenario.deletions.length, 1);
});

test("expiry retention yields safely to author deletion cleanup", async () => {
  const scenario = fixture();
  scenario.seedPublished("expiry-delete-race", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });
  await scenario.service.expirePublishedReels({ limit: 10 });
  const expiryPath = scenario.db.paths("reelCleanupOutbox/")
    .find((path) =>
      scenario.db.data(path).kind === "reelExpiryEvidenceRetention");

  await scenario.service.deleteReel({
    auth: auth(),
    data: {
      reelId: "expiry-delete-race",
      requestId: "expiry-delete-race-0001",
    },
  });
  const deletePath = scenario.db.paths("reelCleanupOutbox/")
    .find((path) =>
      scenario.db.data(path).kind === "reelPublishedMediaCleanup");
  const retention = await scenario.service.processCleanupOutbox(
    expiryPath.split("/").at(-1),
  );
  assert.equal(retention.originalsRetained, false);
  assert.deepEqual(scenario.revocations, []);

  await scenario.service.processCleanupOutbox(deletePath.split("/").at(-1));
  assert.deepEqual(scenario.deletions, [{
    path: "reels/availability-author/expiry-delete-race/media.jpg",
    options: { generation: "101" },
  }]);
});

test("purged expiry evidence rejects an impossible publication chronology",
  async () => {
    const scenario = fixture();
    scenario.seedPublished("purged-chronology", {
      createdAtMs: NOW_MS - 24 * HOUR_MS,
    });
    await scenario.service.expirePublishedReels({ limit: 10 });
    const outboxPath = scenario.db.paths("reelCleanupOutbox/")[0];
    const outboxId = outboxPath.split("/").at(-1);
    await scenario.service.processCleanupOutbox(outboxId);
    scenario.clockState.nowMs = scenario.db.data(outboxPath).purgeAt.getTime();
    await scenario.service.processCleanupOutbox(outboxId);

    const evidencePath = "reels/purged-chronology";
    const evidence = scenario.db.data(evidencePath);
    scenario.db.seed(evidencePath, {
      ...evidence,
      moderationEvidence: {
        ...evidence.moderationEvidence,
        publishedAt: new Date(evidence.expiredAt.getTime() + 1),
      },
    });
    await assert.rejects(
      scenario.service.createReelReport({
        auth: auth(VIEWER, false),
        data: {
          reelId: "purged-chronology",
          requestId: "purged-chronology-report-0001",
          reason: "spam",
          note: "",
        },
      }),
      (error) => error.code === "data-loss",
    );
  });

test("cleanup failures back off and dead-letter after the bounded budget", async () => {
  const scenario = fixture({ failEveryRevoke: true });
  scenario.seedPublished("dead-letter-reel", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });
  await scenario.service.expirePublishedReels({ limit: 10 });
  const outboxPath = scenario.db.paths("reelCleanupOutbox/")[0];
  const outboxId = outboxPath.split("/").at(-1);

  for (let attempt = 1; attempt <= REEL_CLEANUP_MAX_ATTEMPTS; attempt += 1) {
    await assert.rejects(
      scenario.service.processCleanupOutbox(outboxId),
      /synthetic token revocation failure/u,
    );
    const state = scenario.db.data(outboxPath);
    assert.equal(state.attemptCount, attempt);
    if (attempt < REEL_CLEANUP_MAX_ATTEMPTS) {
      assert.equal(state.status, "pending");
      assert.ok(state.nextAttemptAt.getTime() > scenario.clockState.nowMs);
      scenario.clockState.nowMs = state.nextAttemptAt.getTime();
    } else {
      assert.equal(state.status, "deadLetter");
      assert.equal(state.lastErrorCode, "internal");
      assert.equal(Object.hasOwn(state, "deleteAfter"), false);
    }
  }
  assert.deepEqual(await scenario.service.processCleanupOutbox(outboxId), {
    outboxId,
    completed: false,
    deadLetter: true,
    code: "internal",
  });
});

test("cleanup lease makes concurrent delivery idempotent", async () => {
  const scenario = fixture();
  scenario.seedPublished("concurrent-cleanup");
  await scenario.service.deleteReel({
    auth: auth(),
    data: {
      reelId: "concurrent-cleanup",
      requestId: "concurrent-cleanup-delete-0001",
    },
  });
  const outboxPath = scenario.db.paths("reelCleanupOutbox/")[0];
  const outboxId = outboxPath.split("/").at(-1);
  const results = await Promise.all([
    scenario.service.processCleanupOutbox(outboxId),
    scenario.service.processCleanupOutbox(outboxId),
  ]);
  assert.equal(results.filter(({ completed }) => completed).length, 1);
  assert.equal(scenario.deletions.length, 1);
  assert.equal(scenario.db.data(outboxPath).status, "completed");
});

test("scheduled cleanup reclaims an expired processing lease", async () => {
  const scenario = fixture();
  scenario.seedPublished("expired-lease");
  await scenario.service.deleteReel({
    auth: auth(),
    data: {
      reelId: "expired-lease",
      requestId: "expired-lease-delete-0001",
    },
  });
  const outboxPath = scenario.db.paths("reelCleanupOutbox/")[0];
  const value = scenario.db.data(outboxPath);
  scenario.db.seed(outboxPath, {
    ...value,
    status: "processing",
    attemptCount: 1,
    leaseToken: "a".repeat(64),
    leaseUntil: new Date(NOW_MS - 1),
    nextAttemptAt: new Date(NOW_MS - REEL_CLEANUP_LEASE_MS),
  });
  const result = await scenario.service.processReadyCleanupOutbox({ limit: 10 });
  assert.equal(result.processed, 1);
  assert.equal(result.completed, 1);
  assert.equal(scenario.deletions.length, 1);
  assert.equal(scenario.db.data(outboxPath).attemptCount, 2);
});

test("bounded legacy cleanup cursor advances past future rows without starvation",
  async () => {
    const scenario = fixture();
    const paths = [];
    for (const reelId of ["legacy-scan-a", "legacy-scan-b", "legacy-scan-z"]) {
      const before = new Set(scenario.db.paths("reelCleanupOutbox/"));
      scenario.seedPublished(reelId);
      await scenario.service.deleteReel({
        auth: auth(),
        data: {
          reelId,
          requestId: `${reelId}-delete-0001`,
        },
      });
      paths.push(
        scenario.db.paths("reelCleanupOutbox/")
          .find((candidate) => !before.has(candidate)),
      );
    }
    paths.sort();
    for (const path of paths.slice(0, 2)) {
      scenario.db.seed(path, {
        ...scenario.db.data(path),
        nextAttemptAt: new Date(NOW_MS + HOUR_MS),
      });
    }
    const legacyPath = paths.at(-1);
    const { nextAttemptAt: _removed, ...legacy } = scenario.db.data(legacyPath);
    scenario.db.seed(legacyPath, legacy);

    const first = await scenario.service.processReadyCleanupOutbox({ limit: 2 });
    assert.deepEqual(first, {
      processed: 0,
      completed: 0,
      failed: [],
      hasMore: true,
    });
    assert.equal(
      scenario.db.data(REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH).cursor,
      paths[1].split("/").at(-1),
    );

    const second = await scenario.service.processReadyCleanupOutbox({ limit: 2 });
    assert.equal(second.processed, 1);
    assert.equal(second.completed, 1);
    assert.deepEqual(second.failed, []);
    assert.equal(second.hasMore, false);
    assert.equal(scenario.db.data(legacyPath).status, "completed");
    assert.equal(
      scenario.db.data(REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH).cursor,
      null,
    );
    assert.equal(scenario.deletions.length, 1);
  });

test("malformed ready cleanup is dead-lettered with an observable failure code",
  async () => {
    const scenario = fixture();
    scenario.seedPublished("malformed-ready-cleanup");
    await scenario.service.deleteReel({
      auth: auth(),
      data: {
        reelId: "malformed-ready-cleanup",
        requestId: "malformed-ready-delete-0001",
      },
    });
    const outboxPath = scenario.db.paths("reelCleanupOutbox/")[0];
    scenario.db.seed(outboxPath, {
      ...scenario.db.data(outboxPath),
      storageObjects: [{
        path: `reels/${AUTHOR}/foreign/media.jpg`,
        generation: "101",
      }],
    });

    const result = await scenario.service.processReadyCleanupOutbox({ limit: 10 });
    assert.equal(result.processed, 1);
    assert.equal(result.completed, 0);
    assert.deepEqual(result.failed, [{
      outboxId: outboxPath.split("/").at(-1),
      completed: false,
      deadLetter: true,
      code: "data-loss",
    }]);
    assert.equal(result.hasMore, false);
    assert.equal(scenario.db.data(outboxPath).status, "deadLetter");
    assert.equal(scenario.db.data(outboxPath).lastErrorCode, "data-loss");
    assert.deepEqual(scenario.deletions, []);
  });

test("malformed due availability is quarantined without starving valid expiry", async () => {
  const scenario = fixture();
  scenario.seedPublished("availability-poison", {
    createdAtMs: NOW_MS - 24 * HOUR_MS - 1,
  });
  scenario.seedPublished("availability-healthy", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });
  const poisonPath = "reelAvailability/availability-poison";
  scenario.db.seed(poisonPath, {
    ...scenario.db.data(poisonPath),
    forgedField: true,
  });

  const result = await scenario.service.expirePublishedReels({ limit: 10 });
  assert.deepEqual(result.expired, ["availability-healthy"]);
  assert.deepEqual(result.failed, [{
    reelId: "availability-poison",
    code: "data-loss",
    quarantined: true,
  }]);
  assert.equal(scenario.db.data(poisonPath).status, "quarantined");
  assert.equal(scenario.db.data("reels/availability-poison").status, "expired");
  assert.deepEqual(
    await scenario.service.expirePublishedReels({ limit: 10 }),
    { expired: [], failed: [], hasMore: false },
  );
});

test("authors can delete expired v2 Reels and abandoned v2 drafts cleanly", async () => {
  const published = fixture();
  published.seedPublished("delete-expired", {
    createdAtMs: NOW_MS - 24 * HOUR_MS,
  });
  assert.deepEqual(await published.service.deleteReel({
    auth: auth(),
    data: { reelId: "delete-expired", requestId: "delete-expired-0001" },
  }), { reelId: "delete-expired", deleted: true });
  assert.equal(published.db.data("reelAvailability/delete-expired"), undefined);
  assert.equal(published.db.data("reels/delete-expired").status, "deleted");

  const draft = fixture();
  const reserved = await draft.service.reserveReelDraftV2({
    auth: auth(),
    data: {
      ...imagePlan("abandoned-v2-reserve-0001"),
      availabilityHours: PERMANENT_AVAILABILITY,
    },
  });
  draft.clockState.nowMs = NOW_MS + RESERVATION_TTL_MS;
  const sweep = await draft.service.expireAbandonedReelDrafts({ limit: 10 });
  assert.deepEqual(sweep.expired, [reserved.reelId]);
  assert.equal(
    draft.db.data(`reelUploadReservations/${reserved.reelId}`),
    undefined,
  );
  assert.equal(
    draft.db.data(`reelAvailability/${reserved.reelId}`),
    undefined,
  );
});

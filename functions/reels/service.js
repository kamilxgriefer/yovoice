const {
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  canonicalPublicProfile,
  consumeRateLimit,
  digest,
  fail,
  incrementCanonicalCount,
  isValidOpaqueUid,
  ledgerData,
  normalizeText,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const {
  MAX_DURATION_MS,
  MAX_REEL_PAGE_SIZE,
  REEL_SCHEMA_VERSION,
  exactStoredObject,
  reelStoragePath,
  validateComposition,
  validateDraftPlan,
  validateGeneration,
  validateReelReportReason,
  validateSortKey,
  validateStoredAsset,
} = require("./contract");
const {
  MAX_REEL_COMMENT_LENGTH,
  MAX_REEL_THREAD_COMMENTS,
  REEL_COMMENT_SCHEMA_VERSION,
  REEL_LIKE_SCHEMA_VERSION,
  REEL_VIEW_SCHEMA_VERSION,
  decodeReelCommentCursor,
  encodeReelCommentCursor,
  reelCommentProjection,
  storedEngagementCount,
  validateReelComment,
  validateReelLike,
} = require("./engagement");
const {
  DEFAULT_REEL_AVAILABILITY_HOURS,
  PERMANENT_AVAILABILITY,
  REEL_AVAILABILITY_SCHEMA_VERSION,
  deadlineMillis,
  publishedAvailability,
  sameAvailability,
  validateAvailabilityHours,
  validateAvailabilitySnapshot,
} = require("./availability");

const RESERVATION_TTL_MS = 30 * 60 * 1000;
const MEDIA_GRANT_TTL_MS = 90 * 1000;
const MEDIA_DURATION_TOLERANCE_MS = 2 * 1000;
const REEL_EXPIRY_EVIDENCE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const REEL_CLEANUP_LEASE_MS = 2 * 60 * 1000;
const REEL_CLEANUP_BASE_BACKOFF_MS = 5 * 60 * 1000;
const REEL_CLEANUP_MAX_BACKOFF_MS = 6 * 60 * 60 * 1000;
const REEL_CLEANUP_MAX_ATTEMPTS = 8;
const REEL_CLEANUP_AUDIT_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH =
  "reelCleanupMaintenance/legacyPendingSweep";
// Feed authorization fans out to four current-state documents per distinct
// author (account, restriction and both block directions). Keep both the
// query batch and the total scan deliberately small so a caller cannot turn
// one list request into hundreds of Firestore reads.
const REEL_FEED_BATCH_SIZE = 4;
const MAX_REEL_SCAN_PER_REQUEST = 24;
const MAX_REEL_AUTHORS_PER_REQUEST = 8;
const DEFAULT_LIMITS = Object.freeze({
  reserve: Object.freeze({ maxEvents: 12, windowMs: 60 * 60 * 1000 }),
  finalize: Object.freeze({ maxEvents: 24, windowMs: 60 * 60 * 1000 }),
  list: Object.freeze({ maxEvents: 30, windowMs: 60 * 1000 }),
  mediaAccess: Object.freeze({ maxEvents: 120, windowMs: 60 * 1000 }),
  delete: Object.freeze({ maxEvents: 30, windowMs: 60 * 60 * 1000 }),
  report: Object.freeze({ maxEvents: 10, windowMs: 10 * 60 * 1000 }),
  // Engagement budgets match the deployed Voice Moment values, because the
  // abuse they bound is the same abuse: one authenticated account driving
  // counters, notifications and other people's threads. `commentDelete` is
  // deliberately its own scope rather than sharing `delete` — removing your
  // own comments must never consume the budget that lets you delete your
  // own Reel.
  like: Object.freeze({ maxEvents: 60, windowMs: 60 * 1000 }),
  comment: Object.freeze({ maxEvents: 20, windowMs: 60 * 1000 }),
  commentDelete: Object.freeze({ maxEvents: 30, windowMs: 10 * 60 * 1000 }),
  // The Reel author removing OTHER people's comments from their own Reel is
  // its own budget, deliberately separate from `commentDelete`. A brigaded
  // author clearing a raid must not exhaust the budget that lets them delete
  // their own words elsewhere, and a griefing author cannot borrow that
  // budget either. It is more generous than commentDelete because a raid is
  // exactly the case this exists for, and every removal it permits is
  // confined to a surface the caller already owns outright — the same
  // account can delete the entire Reel with one `deleteReel` call.
  commentRemove: Object.freeze({ maxEvents: 60, windowMs: 10 * 60 * 1000 }),
  view: Object.freeze({ maxEvents: 60, windowMs: 60 * 1000 }),
});

function createReelService({
  db,
  FieldPath,
  Timestamp,
  storage,
  clock = () => Date.now(),
  probeMedia = null,
  limits = DEFAULT_LIMITS,
} = {}) {
  if (
    !db?.doc ||
    !db?.collection ||
    !FieldPath?.documentId ||
    !Timestamp?.fromMillis ||
    !storage?.getMetadata ||
    !storage?.readHeader ||
    !storage?.revokeDownloadTokens ||
    !storage?.getSignedReadUrl ||
    !storage?.deleteObject
  ) {
    throw new TypeError(
      "db, FieldPath, Timestamp and the private Reel storage adapter are required.",
    );
  }
  if (probeMedia !== null && typeof probeMedia !== "function") {
    throw new TypeError("probeMedia must be a trusted server-side media probe.");
  }

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  function ledgerReference(identity) {
    return db.doc(`integrityOperationLedgers/${identity.id}`);
  }

  function limitReference(scope, uid) {
    return rateLimitReference(db, `reel.${scope}`, uid);
  }

  function consume(transaction, snapshot, reference, scope, uid, time) {
    const policy = limits[scope];
    if (!policy) throw new TypeError(`Missing reel.${scope} rate limit.`);
    consumeRateLimit(transaction, snapshot, {
      reference,
      scope: `reel.${scope}`,
      uid,
      ...time,
      ...policy,
    });
  }

  function reelIdFor(uid, requestId) {
    return digest("reel", uid, requestId).slice(0, 40);
  }

  function reservationReference(reelId) {
    return db.doc(`reelUploadReservations/${reelId}`);
  }

  function reelReference(reelId) {
    return db.doc(`reels/${reelId}`);
  }

  function availabilityReference(reelId) {
    return db.doc(`reelAvailability/${reelId}`);
  }

  function validateReservation(snapshot, expected = {}) {
    if (!snapshot?.exists) {
      fail("failed-precondition", "The Reel upload reservation is unavailable.");
    }
    const value = exactStoredObject(
      snapshot.data() ?? {},
      [
        "schemaVersion",
        "status",
        "ownerId",
        "authorName",
        "reelId",
        "mediaKind",
        "mediaContentType",
        "mediaSize",
        "durationMs",
        "hasBackingAudio",
        "audioContentType",
        "audioSize",
        "audioDurationMs",
        "mediaStoragePath",
        "backingAudioStoragePath",
        "createdAt",
        "expiresAt",
      ],
      "Reel upload reservation",
    );
    const plan = validateDraftPlan({
      requestId: "reservation-shape",
      mediaKind: value.mediaKind,
      mediaContentType: value.mediaContentType,
      mediaSize: value.mediaSize,
      durationMs: value.durationMs,
      hasBackingAudio: value.hasBackingAudio,
      audioContentType: value.audioContentType,
      audioSize: value.audioSize,
      audioDurationMs: value.audioDurationMs,
    });
    const createdAtMs = timestampMillis(value.createdAt);
    const expiresAtMs = timestampMillis(value.expiresAt);
    if (
      value.schemaVersion !== REEL_SCHEMA_VERSION ||
      value.status !== "uploading" ||
      !isValidOpaqueUid(value.ownerId) ||
      typeof value.authorName !== "string" ||
      value.authorName !== value.authorName.trim() ||
      value.authorName.length < 1 ||
      value.authorName.length > 80 ||
      requireId(value.reelId, "reelId") !== snapshot.id ||
      value.mediaStoragePath !== reelStoragePath(
        value.ownerId,
        value.reelId,
        value.mediaKind,
        value.mediaContentType,
      ) ||
      value.backingAudioStoragePath !== (
        value.hasBackingAudio
          ? reelStoragePath(
              value.ownerId,
              value.reelId,
              "backingAudio",
              value.audioContentType,
            )
          : null
      ) ||
      createdAtMs === null ||
      expiresAtMs === null ||
      expiresAtMs <= createdAtMs ||
      (expected.ownerId !== undefined && value.ownerId !== expected.ownerId) ||
      (expected.reelId !== undefined && value.reelId !== expected.reelId)
    ) {
      fail("data-loss", "The Reel upload reservation is malformed.");
    }
    return { ...value, ...plan, createdAtMs, expiresAtMs };
  }

  function sameReservation(first, second) {
    return [
      "schemaVersion",
      "status",
      "ownerId",
      "authorName",
      "reelId",
      "mediaKind",
      "mediaContentType",
      "mediaSize",
      "durationMs",
      "hasBackingAudio",
      "audioContentType",
      "audioSize",
      "audioDurationMs",
      "mediaStoragePath",
      "backingAudioStoragePath",
      "createdAtMs",
      "expiresAtMs",
    ].every((field) => first[field] === second[field]);
  }

  function reservationAvailability(
    snapshot,
    reservation,
    { required = false } = {},
  ) {
    const availability = validateAvailabilitySnapshot(snapshot, {
      ownerId: reservation.ownerId,
      reelId: reservation.reelId,
      required,
    });
    if (availability === null) return null;
    if (
      availability.status !== "reserved" ||
      availability.createdAtMs !== reservation.createdAtMs
    ) {
      fail("data-loss", "The Reel availability contract is malformed.");
    }
    return availability;
  }

  function legacyAvailabilityForReservation(reservation) {
    const value = {
      schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
      status: "reserved",
      ownerId: reservation.ownerId,
      reelId: reservation.reelId,
      availabilityHours: PERMANENT_AVAILABILITY,
      createdAt: reservation.createdAt,
      updatedAt: reservation.createdAt,
    };
    return {
      value,
      availability: validateAvailabilitySnapshot({
        id: reservation.reelId,
        exists: true,
        data: () => value,
      }, {
        ownerId: reservation.ownerId,
        reelId: reservation.reelId,
        required: true,
      }),
    };
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function storedMedia(value, label) {
    exactStoredObject(
      value,
      ["kind", "contentType", "size", "generation", "durationMs", "storagePath"],
      label,
    );
    if (
      (value.kind !== "image" && value.kind !== "video") ||
      typeof value.contentType !== "string" ||
      !Number.isSafeInteger(value.size) ||
      value.size < 128 ||
      !/^[0-9]{1,30}$/u.test(value.generation) ||
      !Number.isSafeInteger(value.durationMs) ||
      value.durationMs < 0 ||
      typeof value.storagePath !== "string"
    ) {
      fail("data-loss", `${label} is malformed.`);
    }
    return value;
  }

  function storedBackingAudio(value) {
    if (value === null) return null;
    exactStoredObject(
      value,
      ["contentType", "size", "generation", "durationMs", "storagePath"],
      "Reel backing audio",
    );
    if (
      typeof value.contentType !== "string" ||
      !Number.isSafeInteger(value.size) ||
      value.size < 512 ||
      !/^[0-9]{1,30}$/u.test(value.generation) ||
      !Number.isSafeInteger(value.durationMs) ||
      value.durationMs < 1000 ||
      value.durationMs > MAX_DURATION_MS ||
      typeof value.storagePath !== "string"
    ) {
      fail("data-loss", "Reel backing audio is malformed.");
    }
    return value;
  }

  function validatePublishedReel(
    snapshot,
    { allowHidden = false, allowExpiredStatus = false } = {},
  ) {
    if (!snapshot?.exists) fail("not-found", "The Reel does not exist.");
    const raw = snapshot.data() ?? {};
    // `likeCount` and `commentCount` are additive and lazily materialized:
    // every Reel published before the engagement contract carries neither
    // key, and the first like or comment writes the one it needs. Both are
    // therefore OPTIONAL in the exact-schema guard — but only optional, not
    // unchecked. A present counter must be a real non-negative integer
    // (storedEngagementCount below); absent is exactly zero. Listing them
    // unconditionally would reject every already-published Reel, which is
    // how an exact-schema rule becomes an outage instead of a boundary.
    const value = exactStoredObject(
      raw,
      [
        "schemaVersion",
        "status",
        "moderationStatus",
        "authorId",
        "authorName",
        "media",
        "backingAudio",
        "composition",
        "sortKey",
        "publishedAt",
        "updatedAt",
        ...(Object.prototype.hasOwnProperty.call(raw, "likeCount")
          ? ["likeCount"]
          : []),
        ...(Object.prototype.hasOwnProperty.call(raw, "commentCount")
          ? ["commentCount"]
          : []),
      ],
      "Reel",
    );
    const media = storedMedia(value.media, "Reel media");
    const backingAudio = storedBackingAudio(value.backingAudio);
    let canonicalStoragePaths = false;
    try {
      canonicalStoragePaths = media.storagePath === reelStoragePath(
        value.authorId,
        snapshot.id,
        media.kind,
        media.contentType,
      ) && (backingAudio === null ||
        backingAudio.storagePath === reelStoragePath(
          value.authorId,
          snapshot.id,
          "backingAudio",
          backingAudio.contentType,
        ));
    } catch (_) {
      canonicalStoragePaths = false;
    }
    let composition;
    try {
      composition = validateComposition(value.composition, {
        mediaKind: media.kind,
        durationMs: media.durationMs,
        hasBackingAudio: backingAudio !== null,
      });
    } catch (_) {
      fail("data-loss", "The Reel composition is malformed.");
    }
    if (
      value.schemaVersion !== REEL_SCHEMA_VERSION ||
      (value.status !== "published" &&
        !(allowExpiredStatus && value.status === "expired")) ||
      !canonicalStoragePaths ||
      (value.moderationStatus !== "visible" &&
        !(allowHidden && value.moderationStatus === "hidden")) ||
      !isValidOpaqueUid(value.authorId) ||
      typeof value.authorName !== "string" ||
      value.authorName !== value.authorName.trim() ||
      value.authorName.length < 1 ||
      value.authorName.length > 80 ||
      typeof value.sortKey !== "string" ||
      !/^[0-9]{13}_[A-Za-z0-9_-]{1,128}$/u.test(value.sortKey) ||
      timestampMillis(value.publishedAt) === null ||
      timestampMillis(value.updatedAt) === null
    ) {
      fail("data-loss", "The Reel is malformed.");
    }
    return {
      ...value,
      id: snapshot.id,
      media,
      backingAudio,
      composition,
      likeCount: storedEngagementCount(value.likeCount, "Reel likeCount"),
      commentCount: storedEngagementCount(
        value.commentCount,
        "Reel commentCount",
      ),
    };
  }

  async function reserveReelDraftInternal(request, { version }) {
    const auth = requireActor(request);
    let plan;
    // Build 19 only knows the v1 contract and promised content which remains
    // until the author deletes it. Keep that semantic contract even after the
    // v2 sidecar exists; only v2 callers opt into the 24-hour default.
    let availabilityHours = version === 1
      ? PERMANENT_AVAILABILITY
      : DEFAULT_REEL_AVAILABILITY_HOURS;
    if (version === 1) {
      plan = validateDraftPlan(request.data);
    } else {
      const data = requireExactInput(
        request.data,
        [
          "requestId",
          "mediaKind",
          "mediaContentType",
          "mediaSize",
          "durationMs",
          "hasBackingAudio",
          "audioContentType",
          "audioSize",
          "audioDurationMs",
          "availabilityHours",
        ],
        [
          "requestId",
          "mediaKind",
          "mediaContentType",
          "mediaSize",
          "durationMs",
          "hasBackingAudio",
          "audioContentType",
          "audioSize",
          "audioDurationMs",
          "availabilityHours",
        ],
      );
      availabilityHours = validateAvailabilityHours(data.availabilityHours);
      plan = validateDraftPlan({
        requestId: data.requestId,
        mediaKind: data.mediaKind,
        mediaContentType: data.mediaContentType,
        mediaSize: data.mediaSize,
        durationMs: data.durationMs,
        hasBackingAudio: data.hasBackingAudio,
        audioContentType: data.audioContentType,
        audioSize: data.audioSize,
        audioDurationMs: data.audioDurationMs,
      });
    }
    const requestId = requireRequestId(request?.data?.requestId);
    const input = version === 1
      ? { ...plan }
      : { ...plan, availabilityHours };
    const operationKind = version === 1 ? "reel.reserve" : "reel.reserve.v2";
    const identity = operationIdentity(operationKind, auth.uid, requestId, input);
    const reelId = reelIdFor(auth.uid, requestId);
    return db.runTransaction(async (transaction) => {
      // Firestore may retry this callback. Every attempt gets one coherent,
      // server-controlled clock value for restrictions, quotas and timestamps.
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("reserve", auth.uid);
      const reservationRef = reservationReference(reelId);
      const availabilityRef = availabilityReference(reelId);
      const [ledger, rate, actor, restriction, publicProfile] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          db.doc(`publicProfiles/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: operationKind,
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(actor, "Your");
      assertNotRestricted(restriction, "Your", attemptTime.nowMs);
      const publicIdentity = canonicalPublicProfile(publicProfile, auth.uid);
      consume(transaction, rate, rateRef, "reserve", auth.uid, attemptTime);
      const mediaStoragePath = reelStoragePath(
        auth.uid,
        reelId,
        plan.mediaKind,
        plan.mediaContentType,
      );
      const backingAudioStoragePath = plan.hasBackingAudio
        ? reelStoragePath(
            auth.uid,
            reelId,
            "backingAudio",
            plan.audioContentType,
          )
        : null;
      const expiresAtMillis = attemptTime.nowMs + RESERVATION_TTL_MS;
      transaction.create(reservationRef, {
        schemaVersion: REEL_SCHEMA_VERSION,
        status: "uploading",
        ownerId: auth.uid,
        authorName: publicIdentity.displayName,
        reelId,
        ...plan,
        mediaStoragePath,
        backingAudioStoragePath,
        createdAt: attemptTime.now,
        expiresAt: Timestamp.fromMillis(expiresAtMillis),
      });
      // The v1 wire response stays byte-for-byte compatible. Its sidecar is
      // explicitly permanent so mixed-version reads cannot reinterpret a
      // Build 19 publish as an invisible 24-hour Reel.
      transaction.create(availabilityRef, {
        schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
        status: "reserved",
        ownerId: auth.uid,
        reelId,
        availabilityHours,
        createdAt: attemptTime.now,
        updatedAt: attemptTime.now,
      });
      const legacyResult = {
        reelId,
        mediaStoragePath,
        backingAudioStoragePath,
        expiresAtMillis,
      };
      const result = version === 1
        ? legacyResult
        : {
            schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
            ...legacyResult,
            availabilityHours,
            contentExpiresAtMillis: deadlineMillis(
              attemptTime.nowMs,
              availabilityHours,
            ),
          };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: operationKind,
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  function reserveReelDraft(request) {
    return reserveReelDraftInternal(request, { version: 1 });
  }

  function reserveReelDraftV2(request) {
    return reserveReelDraftInternal(request, { version: 2 });
  }

  function validateTrustedProbe(probe, reservation, asset) {
    if (probeMedia === null) {
      fail(
        "failed-precondition",
        "Reel publishing needs the trusted media probe.",
      );
    }
    const isMedia = asset.assetKind === "media";
    const expectedKind = isMedia ? reservation.mediaKind : "audio";
    const expectedContentType = isMedia
      ? reservation.mediaContentType
      : reservation.audioContentType;
    const expectedDurationMs = isMedia
      ? reservation.durationMs
      : reservation.audioDurationMs;
    if (
      !isPlainObject(probe) ||
      probe.generation !== asset.generation ||
      probe.size !== asset.size ||
      probe.detectedContentType !== expectedContentType ||
      typeof probe.hasAudio !== "boolean" ||
      typeof probe.hasVideo !== "boolean"
    ) {
      fail("failed-precondition", "The uploaded Reel bytes do not match.");
    }
    if (expectedKind === "image") {
      if (probe.durationMs !== null || probe.hasAudio || probe.hasVideo) {
        fail("failed-precondition", "The uploaded Reel media is not an image.");
      }
      return 0;
    }
    if (
      !Number.isSafeInteger(probe.durationMs) ||
      probe.durationMs < 1000 ||
      probe.durationMs > MAX_DURATION_MS ||
      Math.abs(probe.durationMs - expectedDurationMs) >
        MEDIA_DURATION_TOLERANCE_MS ||
      (expectedKind === "video" && !probe.hasVideo) ||
      (expectedKind === "audio" && (!probe.hasAudio || probe.hasVideo))
    ) {
      fail("failed-precondition", "The uploaded Reel tracks are invalid.");
    }
    return probe.durationMs;
  }

  async function verifiedAsset({ reservation, generation, assetKind }) {
    const isMedia = assetKind === "media";
    const storagePath = isMedia
      ? reservation.mediaStoragePath
      : reservation.backingAudioStoragePath;
    const contentType = isMedia
      ? reservation.mediaContentType
      : reservation.audioContentType;
    const size = isMedia ? reservation.mediaSize : reservation.audioSize;
    const [metadata, header] = await Promise.all([
      storage.getMetadata(storagePath),
      storage.readHeader(storagePath, 64),
    ]);
    const verified = validateStoredAsset(metadata, header, {
      ownerId: reservation.ownerId,
      reelId: reservation.reelId,
      assetKind,
      contentType,
      size,
      generation,
    });
    if (probeMedia === null) {
      fail(
        "failed-precondition",
        "Reel publishing needs the trusted media probe.",
      );
    }
    const asset = { ...verified, storagePath, assetKind };
    const probe = await probeMedia({
      storagePath,
      generation: verified.generation,
      contentType: verified.contentType,
      size: verified.size,
      kind: isMedia ? reservation.mediaKind : "audio",
    });
    const durationMs = validateTrustedProbe(probe, reservation, asset);

    // The probe may stream for seconds. Re-read metadata afterwards so a
    // replacement cannot turn a stale observation into a canonical Reel.
    const finalMetadata = await storage.getMetadata(storagePath);
    const finalVerified = validateStoredAsset(finalMetadata, header, {
      ownerId: reservation.ownerId,
      reelId: reservation.reelId,
      assetKind,
      contentType,
      size,
      generation,
    });
    if (
      finalVerified.contentType !== verified.contentType ||
      finalVerified.generation !== verified.generation ||
      finalVerified.size !== verified.size
    ) {
      fail("aborted", "The uploaded Reel asset changed. Try again.");
    }
    await storage.revokeDownloadTokens(storagePath, finalMetadata);
    return { ...finalVerified, storagePath, assetKind, durationMs, probe };
  }

  async function finalizeReelDraftInternal(request, { version }) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      [
        "requestId",
        "reelId",
        "mediaGeneration",
        "backingAudioGeneration",
        "composition",
      ],
      [
        "requestId",
        "reelId",
        "mediaGeneration",
        "backingAudioGeneration",
        "composition",
      ],
    );
    const requestId = requireRequestId(data.requestId);
    const reelId = requireId(data.reelId, "reelId");
    const mediaGeneration = validateGeneration(data.mediaGeneration, "mediaGeneration");
    const rawInput = {
      reelId,
      mediaGeneration,
      backingAudioGeneration: data.backingAudioGeneration,
      composition: data.composition,
    };
    const operationKind = version === 1 ? "reel.finalize" : "reel.finalize.v2";
    const identity = operationIdentity(operationKind, auth.uid, requestId, rawInput);
    const priorLedger = await ledgerReference(identity).get();
    const priorReplay = assertLedgerReplay(priorLedger, {
      kind: operationKind,
      uid: auth.uid,
      inputHash: identity.inputHash,
    });
    if (priorReplay) return priorReplay;

    // Commit one cheap, transactional attempt charge before any Storage read
    // or trusted probe. An invalid composition/account state is rejected in
    // this transaction without touching media. Every non-finalized retry is
    // charged again; only a completed operation-ledger replay is free.
    const preflight = await db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const rateRef = limitReference("finalize", auth.uid);
      const reservationRef = reservationReference(reelId);
      const availabilityRef = availabilityReference(reelId);
      const [ledger, priorPreflight, rate, currentReservation, actor,
        restriction, publicProfile, currentAvailability] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        rateRef,
        reservationRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        availabilityRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: operationKind,
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      if (priorPreflight.exists) {
        const value = priorPreflight.data() ?? {};
        if (value.schemaVersion !== REEL_SCHEMA_VERSION ||
            value.kind !== operationKind ||
            value.ownerId !== auth.uid ||
            value.scope !== "finalize" ||
            value.inputHash !== identity.inputHash) {
          fail("already-exists", "requestId was reused for another operation.");
        }
      }
      const current = validateReservation(currentReservation, {
        ownerId: auth.uid,
        reelId,
      });
      let availability = reservationAvailability(
        currentAvailability,
        current,
        { required: false },
      );
      // Drafts reserved by a pre-v2 server have no sidecar. Grandfather them
      // transactionally as permanent: absence identifies a v1 reservation,
      // and a later v2 finalize must not silently change its lifetime.
      if (availability === null) {
        const migrated = legacyAvailabilityForReservation(current);
        transaction.create(availabilityRef, migrated.value);
        availability = migrated.availability;
      }
      if (current.expiresAtMs <= attemptTime.nowMs) {
        fail("deadline-exceeded", "The Reel upload reservation expired.");
      }
      activeProfile(actor, "Your");
      assertNotRestricted(restriction, "Your", attemptTime.nowMs);
      canonicalPublicProfile(publicProfile, auth.uid);
      // This is deliberately repeated after the trusted probe with the actual
      // durations. Here it keeps malformed composition requests away from the
      // expensive media boundary.
      validateComposition(data.composition, current);
      consume(transaction, rate, rateRef, "finalize", auth.uid, attemptTime);
      if (!priorPreflight.exists) {
        transaction.create(preflightRef, {
          schemaVersion: REEL_SCHEMA_VERSION,
          kind: operationKind,
          ownerId: auth.uid,
          requestId,
          scope: "finalize",
          inputHash: identity.inputHash,
          createdAt: attemptTime.now,
        });
      }
      return { replay: null, reservation: current, availability };
    });
    if (preflight.replay) return preflight.replay;
    const reservation = preflight.reservation;
    const reservedAvailability = preflight.availability;
    const backingAudioGeneration = reservation.hasBackingAudio
      ? validateGeneration(data.backingAudioGeneration, "backingAudioGeneration")
      : null;
    if (!reservation.hasBackingAudio && data.backingAudioGeneration !== null) {
      fail("invalid-argument", "backingAudioGeneration is unexpected.");
    }
    const media = await verifiedAsset({
      reservation,
      generation: mediaGeneration,
      assetKind: "media",
    });
    const backingAudio = reservation.hasBackingAudio
      ? await verifiedAsset({
          reservation,
          generation: backingAudioGeneration,
          assetKind: "backingAudio",
        })
      : null;
    const trustedPlan = {
      ...reservation,
      durationMs: media.durationMs,
      audioDurationMs: backingAudio?.durationMs ?? null,
    };
    const composition = validateComposition(data.composition, trustedPlan);
    return db.runTransaction(async (transaction) => {
      // This value is deliberately inside the callback: Firestore can rerun
      // it after contention, and an expired reservation must not inherit the
      // first attempt's earlier time.
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const reservationRef = reservationReference(reelId);
      const availabilityRef = availabilityReference(reelId);
      const [ledger, committedPreflight, currentReservation, actor,
        restriction, publicProfile, currentAvailability] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          preflightRef,
          reservationRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          db.doc(`publicProfiles/${auth.uid}`),
          availabilityRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: operationKind,
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightValue = committedPreflight.exists
        ? committedPreflight.data() ?? {}
        : {};
      if (preflightValue.schemaVersion !== REEL_SCHEMA_VERSION ||
          preflightValue.kind !== operationKind ||
          preflightValue.ownerId !== auth.uid ||
          preflightValue.scope !== "finalize" ||
          preflightValue.inputHash !== identity.inputHash) {
        fail("failed-precondition", "The Reel upload preflight is not canonical.");
      }
      const current = validateReservation(currentReservation, {
        ownerId: auth.uid,
        reelId,
      });
      const availability = reservationAvailability(
        currentAvailability,
        current,
        { required: true },
      );
      if (
        current.expiresAtMs <= attemptTime.nowMs ||
        !sameReservation(current, reservation) ||
        !sameAvailability(availability, reservedAvailability)
      ) {
        fail("aborted", "The Reel upload reservation changed. Try again.");
      }
      const committedMediaDuration = validateTrustedProbe(
        media.probe,
        current,
        media,
      );
      const committedAudioDuration = backingAudio === null
        ? null
        : validateTrustedProbe(backingAudio.probe, current, backingAudio);
      if (
        committedMediaDuration !== media.durationMs ||
        committedAudioDuration !== (backingAudio?.durationMs ?? null)
      ) {
        fail("aborted", "The uploaded Reel asset changed. Try again.");
      }
      activeProfile(actor, "Your");
      assertNotRestricted(restriction, "Your", attemptTime.nowMs);
      const publicIdentity = canonicalPublicProfile(publicProfile, auth.uid);
      const sortKey =
        `${String(attemptTime.nowMs).padStart(13, "0")}_${reelId}`;
      transaction.create(reelReference(reelId), {
        schemaVersion: REEL_SCHEMA_VERSION,
        status: "published",
        moderationStatus: "visible",
        authorId: auth.uid,
        authorName: publicIdentity.displayName,
        media: {
          kind: reservation.mediaKind,
          contentType: media.contentType,
          size: media.size,
          generation: media.generation,
          durationMs: media.durationMs,
          storagePath: media.storagePath,
        },
        backingAudio: backingAudio === null
          ? null
          : {
              contentType: backingAudio.contentType,
              size: backingAudio.size,
              generation: backingAudio.generation,
              durationMs: backingAudio.durationMs,
              storagePath: backingAudio.storagePath,
            },
        composition,
        sortKey,
        publishedAt: attemptTime.now,
        updatedAt: attemptTime.now,
      });
      let contentExpiresAtMillis = null;
      if (availability !== null) {
        contentExpiresAtMillis = deadlineMillis(
          availability.createdAtMs,
          availability.availabilityHours,
        );
        if (
          contentExpiresAtMillis !== null &&
          contentExpiresAtMillis <= attemptTime.nowMs
        ) {
          fail("deadline-exceeded", "The Reel availability window expired.");
        }
        transaction.set(availabilityRef, {
          schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
          status: "published",
          ownerId: auth.uid,
          reelId,
          availabilityHours: availability.availabilityHours,
          createdAt: availability.createdAt,
          publishedAt: attemptTime.now,
          ...(contentExpiresAtMillis === null
            ? {}
            : { expiresAt: Timestamp.fromMillis(contentExpiresAtMillis) }),
          updatedAt: attemptTime.now,
        });
      }
      transaction.delete(reservationRef);
      const result = version === 1
        ? { reelId, published: true }
        : {
            schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
            reelId,
            published: true,
            availabilityHours: availability.availabilityHours,
            expiresAtMillis: contentExpiresAtMillis,
          };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: operationKind,
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  function finalizeReelDraft(request) {
    return finalizeReelDraftInternal(request, { version: 1 });
  }

  function finalizeReelDraftV2(request) {
    return finalizeReelDraftInternal(request, { version: 2 });
  }

  async function consumeReadLimit(uid, scope) {
    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const rateRef = limitReference(scope, uid);
      const [rate, actor, restriction] = await transactionGetAll(
        transaction,
        rateRef,
        db.doc(`users/${uid}`),
        db.doc(`restrictions/${uid}`),
      );
      activeProfile(actor, "Your");
      assertNotRestricted(restriction, "Your", attemptTime.nowMs);
      consume(transaction, rate, rateRef, scope, uid, attemptTime);
      return attemptTime;
    });
  }

  async function getAll(...references) {
    if (typeof db.getAll === "function") return db.getAll(...references);
    return Promise.all(references.map((reference) => reference.get()));
  }

  // One projection shape for the feed and the single-Reel view, so a client
  // renders the same object from either call. v1 is byte-frozen for already
  // installed builds: availability and engagement are v2-only additions.
  function reelItemProjection(reel, availability, { version, callerLiked }) {
    const item = {
      id: reel.id,
      authorId: reel.authorId,
      // Published Reels already contain a server-captured, validated name.
      // Authorization still uses fresh account/restriction/block documents;
      // avoiding a fifth per-author read does not weaken that decision.
      authorName: reel.authorName,
      media: {
        kind: reel.media.kind,
        contentType: reel.media.contentType,
        size: reel.media.size,
        generation: reel.media.generation,
        durationMs: reel.media.durationMs,
      },
      backingAudio: reel.backingAudio === null
        ? null
        : {
            contentType: reel.backingAudio.contentType,
            size: reel.backingAudio.size,
            generation: reel.backingAudio.generation,
            durationMs: reel.backingAudio.durationMs,
          },
      composition: reel.composition,
      publishedAtMillis: timestampMillis(reel.publishedAt),
      sortKey: reel.sortKey,
    };
    if (version === 2) {
      item.availability = {
        schemaVersion: availability.schemaVersion,
        availabilityHours: availability.availabilityHours,
        expiresAtMillis: availability.expiresAtMs,
      };
      // Counters are aggregates over every engagement edge, including edges
      // whose author this viewer cannot see. They are deliberately NOT
      // recomputed per viewer: a filtered count would leak who is blocked.
      item.likeCount = reel.likeCount;
      item.commentCount = reel.commentCount;
      item.callerLiked = callerLiked;
    }
    return item;
  }

  async function visibleFeedItem(
    reel,
    viewerId,
    snapshotMap,
    nowMs,
    { version },
  ) {
    try {
      const author = snapshotMap.get(`users/${reel.authorId}`);
      const restriction = snapshotMap.get(`restrictions/${reel.authorId}`);
      const viewerBlock = snapshotMap.get(
        `users/${viewerId}/blocked/${reel.authorId}`,
      );
      const authorBlock = snapshotMap.get(
        `users/${reel.authorId}/blocked/${viewerId}`,
      );
      const availability = publishedAvailability(
        snapshotMap.get(`reelAvailability/${reel.id}`),
        reel,
        nowMs,
      );
      activeProfile(author, "The author");
      assertNotRestricted(restriction, "The author", nowMs);
      assertNotBlocked(viewerBlock, authorBlock);
      // A malformed like edge must never empty a viewer's whole feed page.
      // It is treated as "not liked" for this render; setReelLike still
      // refuses to transition from corrupt state.
      let callerLiked = false;
      if (version === 2) {
        try {
          callerLiked = validateReelLike(
            snapshotMap.get(`reels/${reel.id}/likes/${viewerId}`),
            reel.id,
            viewerId,
          );
        } catch (_) {
          callerLiked = false;
        }
      }
      const item = reelItemProjection(reel, availability, {
        version,
        callerLiked,
      });
      return { item, expiresAtMs: availability.expiresAtMs };
    } catch (_) {
      return null;
    }
  }

  async function listReelsInternal(request, { version }) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(request.data, ["cursor", "limit"], ["limit"]);
    const limit = requireSafeInteger(data.limit, "limit", {
      min: 1,
      max: MAX_REEL_PAGE_SIZE,
    });
    const cursor = data.cursor === null || data.cursor === undefined
      ? null
      : validateSortKey(data.cursor);
    await consumeReadLimit(auth.uid, "list");
    const visibleItems = [];
    // Cache authorization snapshots only for this request. Positive access is
    // never reused across calls, so account, restriction and block changes
    // take effect on the next feed request while repeated authors cost four
    // reads once instead of four reads per batch.
    const authorizationSnapshots = new Map();
    const loadedAuthorIds = new Set();
    let scanned = 0;
    let nextCursor = cursor;
    let exhausted = false;
    let authorizationBudgetReached = false;
    while (visibleItems.length < limit &&
        scanned < MAX_REEL_SCAN_PER_REQUEST &&
        !exhausted &&
        !authorizationBudgetReached) {
      const batchSize = Math.min(
        REEL_FEED_BATCH_SIZE,
        MAX_REEL_SCAN_PER_REQUEST - scanned,
      );
      // Terminal/expired roots are excluded by Firestore before they consume
      // the bounded scan budget. The equality + order query has a committed
      // production index in firestore.indexes.json.
      let query = db
        .collection("reels")
        .where("status", "==", "published")
        .orderBy("sortKey", "desc");
      if (nextCursor !== null) query = query.startAfter(nextCursor);
      const snapshot = await query.limit(batchSize).get();
      if (snapshot.empty) {
        exhausted = true;
        break;
      }

      const entries = [];
      let poisonedCursor = false;
      for (const document of snapshot.docs) {
        let sortKey;
        try {
          sortKey = validateSortKey(document.data()?.sortKey);
        } catch (_) {
          // A malformed ordered key cannot be represented by this API's
          // opaque scalar cursor. Stop safely instead of looping over it.
          poisonedCursor = true;
          break;
        }
        let candidate = null;
        try {
          candidate = validatePublishedReel(document);
        } catch (_) {
          // Other malformed/withdrawn state is skipped, but still advances the
          // cursor because its ordered key is canonical.
        }
        entries.push({ candidate, sortKey });
      }
      const processableEntries = [];
      const authorIds = new Set();
      for (const entry of entries) {
        const authorId = entry.candidate?.authorId;
        if (authorId !== undefined &&
            !loadedAuthorIds.has(authorId) &&
            !authorIds.has(authorId)) {
          if (loadedAuthorIds.size + authorIds.size >=
              MAX_REEL_AUTHORS_PER_REQUEST) {
            authorizationBudgetReached = true;
            break;
          }
          authorIds.add(authorId);
        }
        processableEntries.push(entry);
      }
      const availabilityReferences = processableEntries
        .filter(({ candidate }) => candidate !== null)
        .map(({ candidate }) => availabilityReference(candidate.id));
      // `callerLiked` costs one point-get per candidate, fetched in the batch
      // that already loads availability rather than in a second round trip,
      // and only for v2 callers. The bounded scan (MAX_REEL_SCAN_PER_REQUEST)
      // is what keeps this from turning one list call into hundreds of reads.
      const callerLikeReferences = version === 1
        ? []
        : processableEntries
            .filter(({ candidate }) => candidate !== null)
            .map(({ candidate }) =>
              reelReference(candidate.id).collection("likes").doc(auth.uid));
      const authorizationReferences = [...authorIds].flatMap((authorId) => [
        db.doc(`users/${authorId}`),
        db.doc(`restrictions/${authorId}`),
        db.doc(`users/${auth.uid}/blocked/${authorId}`),
        db.doc(`users/${authorId}/blocked/${auth.uid}`),
      ]);
      const references = [
        ...availabilityReferences,
        ...callerLikeReferences,
        ...authorizationReferences,
      ];
      const snapshots = references.length === 0
        ? []
        : await getAll(...references);
      references.forEach((reference, index) => {
        authorizationSnapshots.set(reference.path, snapshots[index]);
      });
      authorIds.forEach((authorId) => loadedAuthorIds.add(authorId));
      let processed = 0;
      for (const entry of processableEntries) {
        scanned += 1;
        processed += 1;
        nextCursor = entry.sortKey;
        if (entry.candidate !== null) {
          const visible = await visibleFeedItem(
            entry.candidate,
            auth.uid,
            authorizationSnapshots,
            timing().nowMs,
            { version },
          );
          if (visible !== null) visibleItems.push(visible);
        }
        if (
          visibleItems.length === limit ||
          scanned === MAX_REEL_SCAN_PER_REQUEST
        ) {
          break;
        }
      }
      if ((poisonedCursor && processed === entries.length) ||
          (processed === entries.length && snapshot.size < batchSize)) {
        exhausted = true;
      }
    }
    // A bounded scan can still cross a content deadline after an early item
    // was authorized. Filter once more against the response-time clock so an
    // item is never returned at `expiresAt` merely because the request began
    // a few milliseconds earlier. The cursor still advances past retired
    // content, which is both safe and prevents repeated scans of it.
    const responseTime = timing().nowMs;
    const items = visibleItems
      .filter(({ expiresAtMs }) =>
        expiresAtMs === null || expiresAtMs > responseTime)
      .map(({ item }) => item);
    const result = {
      items,
      nextCursor: exhausted || nextCursor === cursor ? null : nextCursor,
    };
    return version === 1
      ? result
      : { schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION, ...result };
  }

  function listReels(request) {
    return listReelsInternal(request, { version: 1 });
  }

  function listReelsV2(request) {
    return listReelsInternal(request, { version: 2 });
  }

  async function authorizeMediaAccess(uid, reelId, asset) {
    const time = timing();
    const [reelSnapshot, availabilitySnapshot] = await getAll(
      reelReference(reelId),
      availabilityReference(reelId),
    );
    if (isPurgedExpiredReelSnapshot(reelSnapshot)) {
      validatePurgedExpiredReel(reelSnapshot);
      fail("failed-precondition", "The Reel has expired.");
    }
    const reel = validatePublishedReel(reelSnapshot);
    const availability = publishedAvailability(
      availabilitySnapshot,
      reel,
      time.nowMs,
    );
    const [viewer, viewerRestriction, author, authorRestriction, viewerBlock, authorBlock] =
      await getAll(
        db.doc(`users/${uid}`),
        db.doc(`restrictions/${uid}`),
        db.doc(`users/${reel.authorId}`),
        db.doc(`restrictions/${reel.authorId}`),
        db.doc(`users/${uid}/blocked/${reel.authorId}`),
        db.doc(`users/${reel.authorId}/blocked/${uid}`),
      );
    activeProfile(viewer, "Your");
    assertNotRestricted(viewerRestriction, "Your", time.nowMs);
    activeProfile(author, "The author");
    assertNotRestricted(authorRestriction, "The author", time.nowMs);
    assertNotBlocked(viewerBlock, authorBlock);
    const descriptor = asset === "media" ? reel.media : reel.backingAudio;
    if (descriptor === null) fail("not-found", "This Reel has no backing audio.");
    return {
      authorId: reel.authorId,
      descriptor,
      checkedAtMs: time.nowMs,
      availability,
    };
  }

  async function getReelMediaAccessInternal(request, { version }) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["reelId", "asset"],
      ["reelId", "asset"],
    );
    const reelId = requireId(data.reelId, "reelId");
    if (data.asset !== "media" && data.asset !== "backingAudio") {
      fail("invalid-argument", "asset is invalid.");
    }
    await consumeReadLimit(auth.uid, "mediaAccess");
    const access = await authorizeMediaAccess(auth.uid, reelId, data.asset);
    const [metadata, header] = await Promise.all([
      storage.getMetadata(access.descriptor.storagePath),
      storage.readHeader(access.descriptor.storagePath, 64),
    ]);
    const verified = validateStoredAsset(metadata, header, {
      ownerId: access.authorId,
      reelId,
      assetKind: data.asset,
      contentType: access.descriptor.contentType,
      size: access.descriptor.size,
      generation: access.descriptor.generation,
    });
    await storage.revokeDownloadTokens(access.descriptor.storagePath, metadata);
    const grantTime = timing();
    const expiresAtMillis = Math.min(
      grantTime.nowMs + MEDIA_GRANT_TTL_MS,
      access.availability.expiresAtMs ?? Number.MAX_SAFE_INTEGER,
    );
    if (expiresAtMillis <= grantTime.nowMs) {
      fail("failed-precondition", "The Reel has expired.");
    }
    const url = await storage.getSignedReadUrl(access.descriptor.storagePath, {
      expiresAtMs: expiresAtMillis,
      generation: verified.generation,
    });
    let parsed;
    try {
      parsed = new URL(url);
    } catch (_) {
      fail("failed-precondition", "The private Reel grant is unavailable.");
    }
    if (
      parsed.protocol !== "https:" ||
      parsed.hostname !== "storage.googleapis.com" ||
      parsed.username ||
      parsed.password
    ) {
      fail("failed-precondition", "The private Reel grant is unavailable.");
    }
    const finalAccess = await authorizeMediaAccess(auth.uid, reelId, data.asset);
    if (
      finalAccess.checkedAtMs >= expiresAtMillis ||
      finalAccess.authorId !== access.authorId ||
      finalAccess.descriptor.storagePath !== access.descriptor.storagePath ||
      finalAccess.descriptor.generation !== access.descriptor.generation ||
      finalAccess.availability.schemaVersion !== access.availability.schemaVersion ||
      finalAccess.availability.availabilityHours !==
        access.availability.availabilityHours ||
      finalAccess.availability.expiresAtMs !== access.availability.expiresAtMs
    ) {
      fail("aborted", "Reel media authorization changed. Try again.");
    }
    const result = {
      schemaVersion: REEL_SCHEMA_VERSION,
      url,
      expiresAtMillis,
      generation: verified.generation,
    };
    return version === 1
      ? result
      : {
          ...result,
          schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
          availabilityHours: access.availability.availabilityHours,
          contentExpiresAtMillis: access.availability.expiresAtMs,
        };
  }

  function getReelMediaAccess(request) {
    return getReelMediaAccessInternal(request, { version: 1 });
  }

  function getReelMediaAccessV2(request) {
    return getReelMediaAccessInternal(request, { version: 2 });
  }

  // A Reel's root document survives deletion and expiry purge as a
  // moderation tombstone, so the engagement subcollections cannot be removed
  // by deleting the root — they are separate documents and would otherwise
  // outlive the content they describe, holding other people's comment text
  // indefinitely.
  //
  // THE ROOT'S CURRENT STATE IS THE AUTHORITY, NOT THE OUTBOX ROW. A cleanup
  // row names a reelId and nothing more, and this worker also drains
  // `reelMediaCleanup` rows written by the abandoned-draft sweep — whose
  // reservation id is derived from (uid, requestId) and is NOT bound to a
  // Reel's published state. Purging on the row's word alone therefore let an
  // engagement-carrying, still-published Reel be stripped of OTHER PEOPLE'S
  // comments with no author or moderator action, leaving likeCount and
  // commentCount permanently inflated above the surviving edges — fabricated
  // social proof that nothing reconciles. So the purge re-reads the root and
  // proceeds only when the content is genuinely gone: absent, a deletion
  // tombstone, or a purged-expiry tombstone. Anything else is refused, and
  // the refusal is reported rather than swallowed.
  //
  // It is idempotent, so the worker's existing backoff/retry path replays it
  // safely, and it is skipped when the injected database has no bulk delete
  // (unit tests), which costs nothing because those databases are discarded.
  async function purgeReelEngagement(reelId, { allowExpiredRoot = false } = {}) {
    if (typeof db.recursiveDelete !== "function") return "unsupported";
    const reelSnapshot = await reelReference(reelId).get();
    // `allowExpiredRoot` is granted only by the expiry purge, and only after
    // validateExpiryCleanupState has proven the root and its availability
    // sidecar are both expired. It is never passed on the generic path.
    const retiredByExpiry = allowExpiredRoot &&
      reelSnapshot.exists &&
      reelSnapshot.data()?.status === "expired";
    if (
      reelSnapshot.exists &&
      !retiredByExpiry &&
      !isDeletedReelSnapshot(reelSnapshot) &&
      !isPurgedExpiredReelSnapshot(reelSnapshot)
    ) {
      return "liveRoot";
    }
    const reelRef = reelReference(reelId);
    await db.recursiveDelete(reelRef.collection("likes"));
    await db.recursiveDelete(reelRef.collection("comments"));
    return "purged";
  }

  function cleanupOutboxId(reelId) {
    return digest("reel-cleanup", reelId).slice(0, 40);
  }

  function expiryOutboxId(reelId) {
    return digest("reel-expiry-retention", reelId).slice(0, 40);
  }

  function isCanonicalCleanupPath(path, ownerId, reelId, index) {
    if (typeof path !== "string") return false;
    const prefix = `reels/${ownerId}/${reelId}/`;
    if (!path.startsWith(prefix)) return false;
    const filename = path.slice(prefix.length);
    return index === 0
      ? /^media[.](jpg|png|webp|mp4|mov|webm)$/u.test(filename)
      : /^backing-audio[.](mp3|m4a|wav)$/u.test(filename);
  }

  function validGenerationBoundObjects(value, ownerId, reelId) {
    return Array.isArray(value) &&
      value.length >= 1 &&
      value.length <= 2 &&
      value.every((object, index) =>
        isPlainObject(object) &&
        Object.keys(object).length === 2 &&
        Object.prototype.hasOwnProperty.call(object, "path") &&
        Object.prototype.hasOwnProperty.call(object, "generation") &&
        isCanonicalCleanupPath(object.path, ownerId, reelId, index) &&
        typeof object.generation === "string" &&
        /^[0-9]{1,30}$/u.test(object.generation),
      );
  }

  function publishedStorageObjects(reel) {
    return [
      { path: reel.media.storagePath, generation: reel.media.generation },
      ...(reel.backingAudio === null ? [] : [{
        path: reel.backingAudio.storagePath,
        generation: reel.backingAudio.generation,
      }]),
    ];
  }

  async function deleteReel(request) {
    // Deletion is an account-safety/cleanup action, not content creation.
    // Keep it available to an authenticated active owner even if their email
    // is not verified yet or a communication mute is in force.
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["reelId", "requestId"],
      ["reelId", "requestId"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const requestId = requireRequestId(data.requestId);
    const identity = operationIdentity("reel.delete", auth.uid, requestId, { reelId });
    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("delete", auth.uid);
      const availabilityRef = availabilityReference(reelId);
      const [ledger, rate, actor, reelSnapshot, availabilitySnapshot] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          db.doc(`users/${auth.uid}`),
          reelReference(reelId),
          availabilityRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(actor, "Your");
      // A caller can lose the successful acknowledgement and later retry from
      // a fresh process with a new request id. Converge only from the exact,
      // owned tombstone written by this service; malformed or foreign state
      // remains fail-closed.
      if (isDeletedReelSnapshot(reelSnapshot)) {
        const deleted = validateDeletedReel(reelSnapshot);
        if (deleted.authorId !== auth.uid) {
          fail("permission-denied", "Only the author can delete this Reel.");
        }
        if (availabilitySnapshot.exists) {
          fail("data-loss", "The deleted Reel evidence is malformed.");
        }
        consume(transaction, rate, rateRef, "delete", auth.uid, attemptTime);
        const result = { reelId, deleted: true };
        transaction.create(
          ledgerRef,
          ledgerData({
            kind: "reel.delete",
            uid: auth.uid,
            requestId,
            inputHash: identity.inputHash,
            result,
            now: attemptTime.now,
          }),
        );
        return result;
      }
      if (isPurgedExpiredReelSnapshot(reelSnapshot)) {
        const evidence = validatePurgedExpiredReel(reelSnapshot);
        if (evidence.authorId !== auth.uid) {
          fail("permission-denied", "Only the author can delete this Reel.");
        }
        if (availabilitySnapshot.exists) {
          fail("data-loss", "The expired Reel evidence is malformed.");
        }
        consume(transaction, rate, rateRef, "delete", auth.uid, attemptTime);
        transaction.set(reelReference(reelId), {
          schemaVersion: REEL_SCHEMA_VERSION,
          status: "deleted",
          authorId: auth.uid,
          moderationStatusAtDeletion: evidence.moderationStatusAtExpiry,
          moderationEvidence: evidence.moderationEvidence,
          deletedAt: attemptTime.now,
          updatedAt: attemptTime.now,
        });
        const result = { reelId, deleted: true };
        transaction.create(
          ledgerRef,
          ledgerData({
            kind: "reel.delete",
            uid: auth.uid,
            requestId,
            inputHash: identity.inputHash,
            result,
            now: attemptTime.now,
          }),
        );
        return result;
      }
      const reel = validatePublishedReel(reelSnapshot, {
        allowHidden: true,
        allowExpiredStatus: true,
      });
      const availability = publishedAvailability(
        availabilitySnapshot,
        reel,
        attemptTime.nowMs,
        { allowExpired: true },
      );
      if (reel.authorId !== auth.uid) {
        fail("permission-denied", "Only the author can delete this Reel.");
      }
      consume(transaction, rate, rateRef, "delete", auth.uid, attemptTime);
      const outboxId = cleanupOutboxId(reelId);
      const storageObjects = publishedStorageObjects(reel);
      const moderationEvidence = {
        evidenceVersion: 1,
        publishedAt: reel.publishedAt,
        metadataFingerprint: digest("reel-deletion-evidence", {
          reelId,
          authorId: reel.authorId,
          moderationStatus: reel.moderationStatus,
          media: reel.media,
          backingAudio: reel.backingAudio,
          composition: reel.composition,
        }),
      };
      transaction.set(reelReference(reelId), {
        schemaVersion: REEL_SCHEMA_VERSION,
        status: "deleted",
        authorId: auth.uid,
        // Keep only the moderation fact needed for later report/audit review.
        // Public composition, captions and media descriptors are removed.
        moderationStatusAtDeletion: reel.moderationStatus,
        moderationEvidence,
        deletedAt: attemptTime.now,
        updatedAt: attemptTime.now,
      });
      transaction.set(db.doc(`reelCleanupOutbox/${outboxId}`), {
        schemaVersion: REEL_SCHEMA_VERSION,
        kind: "reelPublishedMediaCleanup",
        ownerId: auth.uid,
        reelId,
        storageObjects,
        status: "pending",
        attemptCount: 0,
        phase: "delete",
        nextAttemptAt: attemptTime.now,
        leaseToken: null,
        leaseUntil: null,
        lastErrorCode: null,
        createdAt: attemptTime.now,
        updatedAt: attemptTime.now,
      });
      if (availability.schemaVersion === REEL_AVAILABILITY_SCHEMA_VERSION) {
        transaction.delete(availabilityRef);
      }
      const result = { reelId, deleted: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.delete",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  async function createReelReport(request) {
    // Reporting remains available to an authenticated but not-yet-verified
    // person, matching blocking and the existing content-safety boundary.
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["reelId", "requestId", "reason", "note"],
      ["reelId", "requestId", "reason"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const requestId = requireRequestId(data.requestId);
    const reason = validateReelReportReason(data.reason);
    const note = data.note === null || data.note === undefined
      ? ""
      : normalizeText(data.note, 300, "note", { allowEmpty: true });
    const identity = operationIdentity(
      "reel.report",
      auth.uid,
      requestId,
      { reelId, reason, note },
    );
    // One immutable Reel can be reported once per reporter. A different
    // requestId cannot manufacture duplicate queue entries for the same
    // target, while the operation ledger still protects request retries.
    const reportId = digest("reel-report", auth.uid, reelId).slice(0, 40);
    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("report", auth.uid);
      const reportRef = db.doc(`reports/${reportId}`);
      const [ledger, rate, actor, reelSnapshot, availabilitySnapshot, existing] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          db.doc(`users/${auth.uid}`),
          reelReference(reelId),
          availabilityReference(reelId),
          reportRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.report",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(actor, "Your");
      let reel;
      if (isPurgedExpiredReelSnapshot(reelSnapshot)) {
        reel = validatePurgedExpiredReel(reelSnapshot);
        if (availabilitySnapshot.exists) {
          fail("data-loss", "The expired Reel evidence is malformed.");
        }
      } else {
        reel = validatePublishedReel(reelSnapshot, {
          allowHidden: reelSnapshot.data()?.status === "expired",
          allowExpiredStatus: true,
        });
        const availability = publishedAvailability(
          availabilitySnapshot,
          reel,
          attemptTime.nowMs,
          {
            allowExpired: true,
            required: reel.status === "expired",
          },
        );
        if (reel.status === "expired" && availability.isExpired !== true) {
          fail("data-loss", "The expired Reel evidence is malformed.");
        }
      }
      if (reel.authorId === auth.uid) {
        fail("failed-precondition", "You cannot report your own Reel.");
      }
      // A new requestId is a new attempt even when this reporter already has a
      // canonical report. Charge it before returning the deduplicated result;
      // only replay of the exact operation ledger remains free.
      consume(transaction, rate, rateRef, "report", auth.uid, attemptTime);
      if (existing.exists) {
        const result = { reportId, created: false };
        transaction.create(
          ledgerRef,
          ledgerData({
            kind: "reel.report",
            uid: auth.uid,
            requestId,
            inputHash: identity.inputHash,
            result,
            now: attemptTime.now,
          }),
        );
        return result;
      }
      transaction.create(reportRef, {
        reporterId: auth.uid,
        targetType: "reel",
        targetId: reelId,
        reportedUserId: reel.authorId,
        contextPath: `reels/${reelId}`,
        note,
        reason,
        status: "open",
        createdAt: attemptTime.now,
      });
      const result = { reportId, created: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.report",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  // A Reel comment report is a SIBLING of createReelReport, not a widening
  // of it, and that is deliberate.
  //
  // createReelReport is deployed. Its operation identity hashes exactly
  // { reelId, reason, note } and its report id is digest(uid, reelId), and
  // production already holds ledger entries and report documents keyed on
  // both. Folding an optional commentId into either derivation would re-key
  // every Reel report already filed — the next retry would stop replaying and
  // start answering `already-exists` on a safety path. functions/moments/
  // integrity.js learned that lesson first; see reportIdentityInput() there.
  // A separate entry point keeps that contract byte-identical and gives the
  // comment target its own ledger kind and its own report-id namespace, so
  // reporting a Reel and reporting a comment on it can never collide.
  //
  // The report budget IS shared with createReelReport (`report` scope): one
  // account gets one reporting allowance, the same way createContentReport
  // spends one `report` scope across Moments and Moment comments.
  async function createReelCommentReport(request) {
    // Reporting stays available to an authenticated but not-yet-verified
    // person, matching createReelReport, setUserBlock and the reports/ create
    // rule's own comment: a safety action is never gated on verification.
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentId", "note", "reason", "reelId", "requestId"],
      ["commentId", "reason", "reelId", "requestId"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const commentId = requireId(data.commentId, "commentId");
    const requestId = requireRequestId(data.requestId);
    const reason = validateReelReportReason(data.reason);
    const note = data.note === null || data.note === undefined
      ? ""
      : normalizeText(data.note, 300, "note", { allowEmpty: true });
    const identity = operationIdentity(
      "reel.comment.report",
      auth.uid,
      requestId,
      { commentId, reelId, reason, note },
    );
    // One comment can be reported once per reporter. A fresh requestId cannot
    // manufacture duplicate queue entries for the same target; the operation
    // ledger still makes an honest retry free.
    const reportId = digest("reel-comment-report", auth.uid, reelId, commentId)
      .slice(0, 40);
    // THE BUDGET IS CHARGED BEFORE THE TARGET IS READ, and that ordering is
    // the security property, not a detail. createReelReport charges after
    // its existence checks, which leaves every REFUSED report free: an
    // authenticated caller can then poll `(reelId, commentId)` pairs without
    // limit and read the answer off the refusal. Charging up front, exactly
    // as beginEngagementAttempt does for like/comment/delete/remove, means a
    // probe costs the same as a report. Only an exact operation-ledger replay
    // stays free, because a lost acknowledgement must never be more expensive
    // than the original call.
    const attempt = await beginEngagementAttempt({
      identity,
      kind: "reel.comment.report",
      uid: auth.uid,
      scope: "report",
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const reportRef = db.doc(`reports/${reportId}`);
      const [ledger, actor, reelSnapshot, commentSnapshot, existing] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          db.doc(`users/${auth.uid}`),
          reelReference(reelId),
          reelCommentReference(reelId, commentId),
          reportRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.comment.report",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(actor, "Your");
      // ONE refusal envelope for every "there is nothing here to report"
      // state — a Reel that never existed, a deletion or expiry tombstone
      // whose thread is already being purged, and a comment id that does not
      // resolve all answer `not-found` with the same sentence. Reel and
      // comment ids are 40-character server digests, so this is not a
      // guessing surface; keeping the envelope uniform means it cannot become
      // a differential oracle for which half of the pair exists either.
      const missing = () =>
        fail("not-found", "That Reel comment is no longer available.");
      if (
        !reelSnapshot.exists ||
        isDeletedReelSnapshot(reelSnapshot) ||
        isPurgedExpiredReelSnapshot(reelSnapshot) ||
        !commentSnapshot.exists
      ) {
        missing();
      }
      // allowHidden / allowExpiredStatus, exactly as deleteReelComment reads
      // it: expiry retires a Reel from the feed and moderation hides it, but
      // neither erases the words underneath. Somebody who saw the comment
      // before either happened must still be able to report it. Availability
      // is deliberately NOT read here — a missing or lapsed sidecar must
      // never be the reason a safety action is refused.
      const reel = validatePublishedReel(reelSnapshot, {
        allowHidden: true,
        allowExpiredStatus: true,
      });
      const comment = validateReelComment(commentSnapshot, reelId);
      if (comment.authorId === auth.uid) {
        fail("failed-precondition", "You cannot report your own comment.");
      }
      // THE REPORTER'S CURRENT VISIBILITY OF THIS COMMENT IS DELIBERATELY
      // NOT CHECKED, AND THAT IS A KNOWN DIVERGENCE FROM ADR-086.
      //
      // ADR-086 rule 2 says access is checked before existence for every
      // moderation target, and getReelViewV2 really does withhold a comment
      // per-viewer: reelView() resolves assertReelAuthorAudience() for each
      // distinct commenter, so a block in either direction hides that
      // person's comment from this reader. Applying the same rule here would
      // therefore be the consistent thing to do, and it is not done, because
      // on this target type it costs more safety than it buys:
      //
      //  - WITHOUT the check, somebody who can no longer see a comment can
      //    still name it. The cost is an existence signal for a pair of
      //    40-character server digests they must already hold, plus a
      //    staff-visible report naming an account that blocked them. Both
      //    are now metered — the budget above is charged before any of this
      //    runs — and every report carries its reporter's uid, so a
      //    bad-faith reporter is a detectable pattern rather than an
      //    anonymous one.
      //  - WITH the check and nothing else, a harasser immunises their own
      //    comment by blocking the person they harassed: the words stay up,
      //    the victim can no longer see them, staff cannot read
      //    `reels/{id}/comments/{id}` at all, and no report can ever be
      //    filed. That is the exact failure the Voice Moment path spends a
      //    whole receipt mechanism to avoid.
      //
      // The correct resolution is the receipt, not the bare check:
      // getReelViewV2 issues a short-lived, target-bound, timing-safe token
      // the way getVoiceMomentView does (issueVoiceReportReceipt in
      // functions/moments/integrity.js), and this endpoint accepts EITHER a
      // current audience or a valid receipt. That needs a change to the view
      // path and a new TTL collection, so it is named here rather than
      // half-built: until it exists, the block-race safety of the victim is
      // preferred over the oracle hardening, and this comment is the record
      // of that choice. Do not add the audience check on its own.
      if (existing.exists) {
        const result = { reportId, created: false };
        transaction.create(
          ledgerRef,
          ledgerData({
            kind: "reel.comment.report",
            uid: auth.uid,
            requestId,
            inputHash: identity.inputHash,
            result,
            now: attemptTime.now,
          }),
        );
        return result;
      }
      transaction.create(reportRef, {
        schemaVersion: 2,
        reporterId: auth.uid,
        targetType: "reelComment",
        targetId: commentId,
        reportedUserId: comment.authorId,
        contextPath: `reels/${reelId}/comments/${commentId}`,
        reelId,
        commentId,
        reelAuthorId: reel.authorId,
        // THE COMMENT TEXT IS COPIED INTO THE REPORT ON PURPOSE.
        //
        // reels/{id}/comments/{id} is `allow read, write: if false` for every
        // client including staff, so unlike a Voice Moment comment there is
        // no second path a moderator could read the reported words through.
        // Without this field a moderator would be deciding a harassment
        // report having never seen the harassment. It is also the only
        // evidence that survives the comment being removed, which is what an
        // appeal has to be judged against. It is bounded by the same
        // MAX_REEL_COMMENT_LENGTH the write path enforces, it is readable
        // only by active staff, and it is never shown to the reported
        // account. Retention follows the report, not the comment — see the
        // open decision recorded with this change.
        targetTextSnapshot: comment.text,
        note,
        reason,
        status: "open",
        createdAt: attemptTime.now,
      });
      const result = { reportId, created: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.comment.report",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  function reelCommentIdFor(uid, reelId, requestId) {
    return digest("reel-comment", uid, reelId, requestId).slice(0, 40);
  }

  function reelLikeReference(reelId, uid) {
    return reelReference(reelId).collection("likes").doc(uid);
  }

  function reelCommentReference(reelId, commentId) {
    return reelReference(reelId).collection("comments").doc(commentId);
  }

  // The per-user budget is charged in its own transaction BEFORE the
  // operation's graph reads, so a request that is later refused by
  // availability, a block or a malformed document has still cost the caller
  // something. Only an exact operation-ledger replay returns free: a lost
  // acknowledgement must not be more expensive than the original call.
  async function beginEngagementAttempt({ identity, kind, uid, scope }) {
    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference(scope, uid);
      const [ledger, rate] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      consume(transaction, rate, rateRef, scope, uid, attemptTime);
      return { replay: null };
    });
  }

  // Engagement is authorized by exactly the rule the Reels FEED already
  // applies to viewing (visibleFeedItem): the author is active and not
  // communication-muted, and neither side has blocked the other. It is
  // deliberately not the Voice Moment rule, which additionally consults
  // profileVisibility — Reels have no per-author audience concept anywhere
  // in the product today, and inventing one here would make engagement
  // narrower than the feed that offers it. If a Reel is visible to you, you
  // may like and comment on it; if it is not, you may do neither.
  function assertReelViewerState(viewerProfile, viewerRestriction, nowMs) {
    activeProfile(viewerProfile, "Your");
    assertNotRestricted(viewerRestriction, "Your", nowMs);
  }

  function assertReelAuthorAudience({
    viewerId,
    authorId,
    authorProfile,
    authorRestriction,
    viewerBlock,
    authorBlock,
    nowMs,
  }) {
    activeProfile(authorProfile, "The author");
    assertNotRestricted(authorRestriction, "The author", nowMs);
    if (viewerId === authorId) return;
    assertNotBlocked(viewerBlock, authorBlock);
  }

  function reelAudienceReferences(viewerId, authorId) {
    if (viewerId === authorId) {
      // Your own account state was already proven, and a block against
      // yourself is not expressible. Two reads saved, no check skipped.
      return [];
    }
    return [
      db.doc(`users/${authorId}`),
      db.doc(`restrictions/${authorId}`),
      db.doc(`users/${viewerId}/blocked/${authorId}`),
      db.doc(`users/${authorId}/blocked/${viewerId}`),
    ];
  }

  async function assertReelAudienceInTransaction(transaction, {
    viewerId,
    authorId,
    viewerProfile,
    viewerRestriction,
    nowMs,
  }) {
    assertReelViewerState(viewerProfile, viewerRestriction, nowMs);
    const references = reelAudienceReferences(viewerId, authorId);
    if (references.length === 0) return;
    const [authorProfile, authorRestriction, viewerBlock, authorBlock] =
      await transactionGetAll(transaction, ...references);
    assertReelAuthorAudience({
      viewerId,
      authorId,
      authorProfile,
      authorRestriction,
      viewerBlock,
      authorBlock,
      nowMs,
    });
  }

  // A live Reel: published, visible, and inside its availability window at
  // the server's request time. The ten-minute expiry sweep is the durable
  // transition, not a grace period, so engagement stops exactly at the
  // deadline even when the sweeper has not flipped `status` yet.
  function engageableReel(reelSnapshot, availabilitySnapshot, nowMs) {
    const reel = validatePublishedReel(reelSnapshot);
    const availability = publishedAvailability(
      availabilitySnapshot,
      reel,
      nowMs,
    );
    return { reel, availability };
  }

  async function setReelLike(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["liked", "reelId", "requestId"],
      ["liked", "reelId", "requestId"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const requestId = requireRequestId(data.requestId);
    const liked = requireBoolean(data.liked, "liked");
    const identity = operationIdentity(
      "reel.like",
      auth.uid,
      requestId,
      { liked, reelId },
    );
    const attempt = await beginEngagementAttempt({
      identity,
      kind: "reel.like",
      uid: auth.uid,
      scope: "like",
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const reelRef = reelReference(reelId);
      const likeRef = reelLikeReference(reelId, auth.uid);
      const [
        ledger,
        reelSnapshot,
        availabilitySnapshot,
        like,
        viewerProfile,
        viewerRestriction,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        reelRef,
        availabilityReference(reelId),
        likeRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.like",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const { reel } = engageableReel(
        reelSnapshot,
        availabilitySnapshot,
        attemptTime.nowMs,
      );
      await assertReelAudienceInTransaction(transaction, {
        viewerId: auth.uid,
        authorId: reel.authorId,
        viewerProfile,
        viewerRestriction,
        nowMs: attemptTime.nowMs,
      });
      const currentlyLiked = validateReelLike(like, reelId, auth.uid);
      const changed = currentlyLiked !== liked;
      let likeCount = reel.likeCount;
      if (changed && liked) {
        transaction.create(likeRef, {
          schemaVersion: REEL_LIKE_SCHEMA_VERSION,
          userId: auth.uid,
          reelId,
          createdAt: attemptTime.now,
        });
        likeCount = incrementCanonicalCount(likeCount, "Reel likeCount");
      } else if (changed) {
        // The edge and the counter move in one transaction, so this can only
        // be reached by out-of-band corruption. Refuse rather than write a
        // negative counter that every later reader would have to defend
        // against.
        if (likeCount === 0) {
          fail("data-loss", "Reel likeCount would become negative.");
        }
        transaction.delete(likeRef);
        likeCount -= 1;
      }
      if (changed) {
        // `update` (not `set`) is what makes the counter additive: it
        // materializes the field on a Reel published before this contract
        // without touching any other stored field.
        transaction.update(reelRef, { likeCount, updatedAt: attemptTime.now });
      }
      const result = { reelId, liked, changed, likeCount };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.like",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  async function createReelComment(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["reelId", "requestId", "text"],
      ["reelId", "requestId", "text"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const requestId = requireRequestId(data.requestId);
    const text = normalizeText(data.text, MAX_REEL_COMMENT_LENGTH, "text");
    const commentId = reelCommentIdFor(auth.uid, reelId, requestId);
    const identity = operationIdentity(
      "reel.comment",
      auth.uid,
      requestId,
      { reelId, text },
    );
    const attempt = await beginEngagementAttempt({
      identity,
      kind: "reel.comment",
      uid: auth.uid,
      scope: "comment",
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const reelRef = reelReference(reelId);
      const commentRef = reelCommentReference(reelId, commentId);
      const [
        ledger,
        reelSnapshot,
        availabilitySnapshot,
        existingComment,
        viewerProfile,
        publicProfile,
        viewerRestriction,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        reelRef,
        availabilityReference(reelId),
        commentRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.comment",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const { reel } = engageableReel(
        reelSnapshot,
        availabilitySnapshot,
        attemptTime.nowMs,
      );
      await assertReelAudienceInTransaction(transaction, {
        viewerId: auth.uid,
        authorId: reel.authorId,
        viewerProfile,
        viewerRestriction,
        nowMs: attemptTime.nowMs,
      });
      if (existingComment.exists) {
        fail("data-loss", "A Reel comment exists without its idempotency ledger.");
      }
      // The stored name is server-captured from the canonical public profile,
      // exactly as the Reel root captures its author's name. A client never
      // supplies display identity.
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(commentRef, {
        schemaVersion: REEL_COMMENT_SCHEMA_VERSION,
        type: "text",
        reelId,
        authorId: auth.uid,
        authorName: canonical.displayName,
        text,
        durationSeconds: null,
        createdAt: attemptTime.now,
      });
      const commentCount = incrementCanonicalCount(
        reel.commentCount,
        "Reel commentCount",
      );
      transaction.update(reelRef, {
        commentCount,
        updatedAt: attemptTime.now,
      });
      const result = { reelId, commentId, created: true, commentCount };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.comment",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  async function deleteReelComment(request) {
    // Removing your own words is a cleanup/safety action, not publication.
    // It stays available to an authenticated active account whose email is
    // not verified yet or whose communication is muted, matching deleteReel
    // and the Voice Moment comment-delete precedent.
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentId", "reelId", "requestId"],
      ["commentId", "reelId", "requestId"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const commentId = requireId(data.commentId, "commentId");
    const requestId = requireRequestId(data.requestId);
    const identity = operationIdentity(
      "reel.comment.delete",
      auth.uid,
      requestId,
      { commentId, reelId },
    );
    const attempt = await beginEngagementAttempt({
      identity,
      kind: "reel.comment.delete",
      uid: auth.uid,
      scope: "commentDelete",
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const reelRef = reelReference(reelId);
      const commentRef = reelCommentReference(reelId, commentId);
      const [ledger, reelSnapshot, comment, viewerProfile] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          reelRef,
          commentRef,
          db.doc(`users/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.comment.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(viewerProfile, "Your");
      // A deleted or purged Reel keeps only a moderation tombstone and no
      // counter to decrement; its engagement is already unreachable and the
      // cleanup worker removes it. Report that as absence, not corruption.
      if (
        isDeletedReelSnapshot(reelSnapshot) ||
        isPurgedExpiredReelSnapshot(reelSnapshot)
      ) {
        fail("not-found", "The Reel does not exist.");
      }
      // allowHidden / allowExpiredStatus: expiry retires a Reel from the feed
      // and moderation hides it, but neither freezes another person's words
      // in place. Your own comment stays removable.
      const reel = validatePublishedReel(reelSnapshot, {
        allowHidden: true,
        allowExpiredStatus: true,
      });
      const commentData = validateReelComment(comment, reelId);
      if (commentData.authorId !== auth.uid) {
        fail("permission-denied", "You can only delete your own comment.");
      }
      const currentCount = reel.commentCount;
      if (currentCount === 0) {
        fail("data-loss", "Reel commentCount would become negative.");
      }
      transaction.delete(commentRef);
      transaction.update(reelRef, {
        commentCount: currentCount - 1,
        updatedAt: attemptTime.now,
      });
      const result = {
        reelId,
        commentId,
        deleted: true,
        commentCount: currentCount - 1,
      };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.comment.delete",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  // THE REEL AUTHOR'S REMOVAL AUTHORITY, and a SEPARATE callable rather than
  // a widening of deleteReelComment. The choice was made deliberately.
  //
  // deleteReelComment's whole invariant is one provable sentence:
  // `commentData.authorId !== auth.uid` -> permission-denied. Folding a
  // second authority into it turns that into "the comment's author OR the
  // Reel's author", and every future bug in resolving the Reel's author
  // silently becomes the power to delete ANY comment on ANY Reel. Keeping
  // the narrow path narrow is the point.
  //
  // Three more things follow from the split, and none of them are cosmetic:
  //
  //  - AN AUTHOR REMOVING SOMEBODY ELSE'S WORDS IS NOT THE SAME EVENT AS
  //    SOMEBODY DELETING THEIR OWN. Trust and Safety has to be able to tell
  //    them apart after the fact — an author who clears every critical
  //    comment, or who deletes the exact comment that was about to be
  //    reported, is a pattern, and a pattern only exists if the two actions
  //    leave distinguishable traces. A separate ledger kind
  //    (`reel.comment.remove`) is that trace.
  //  - THE BUDGETS ARE DIFFERENT BY DESIGN. `commentRemove` is deliberately
  //    more generous than `commentDelete` (a brigaded author clearing a raid
  //    must not run out), and a shared entry point cannot charge two budgets
  //    without making replay ambiguous about which one was spent.
  //  - The refusal sentences differ, and a person deleting their own comment
  //    should never read a sentence about owning a Reel.
  //
  // Scope is exactly the Reel the caller owns. This grants nothing the caller
  // does not already hold: the same account can delete the whole Reel, and
  // its comments with it, in one `deleteReel` call. What it does NOT grant is
  // any reach into another author's thread.
  async function removeReelComment(request) {
    // Clearing abuse off your own Reel is a safety action, not publication:
    // available to an authenticated active account whose email is not
    // verified yet, exactly like deleteReel and deleteReelComment. A
    // communication mute is also not a reason to force somebody to keep
    // harassment under their own Reel — an account in that state can already
    // delete the entire Reel.
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentId", "reelId", "requestId"],
      ["commentId", "reelId", "requestId"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const commentId = requireId(data.commentId, "commentId");
    const requestId = requireRequestId(data.requestId);
    const identity = operationIdentity(
      "reel.comment.remove",
      auth.uid,
      requestId,
      { commentId, reelId },
    );
    const attempt = await beginEngagementAttempt({
      identity,
      kind: "reel.comment.remove",
      uid: auth.uid,
      scope: "commentRemove",
    });
    if (attempt.replay) return attempt.replay;

    return db.runTransaction(async (transaction) => {
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const reelRef = reelReference(reelId);
      const commentRef = reelCommentReference(reelId, commentId);
      const [ledger, reelSnapshot, comment, viewerProfile] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          reelRef,
          commentRef,
          db.doc(`users/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.comment.remove",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(viewerProfile, "Your");
      if (
        isDeletedReelSnapshot(reelSnapshot) ||
        isPurgedExpiredReelSnapshot(reelSnapshot)
      ) {
        fail("not-found", "The Reel does not exist.");
      }
      // allowHidden / allowExpiredStatus for the same reason deleteReelComment
      // reads it that way: expiry retires a Reel from the feed and moderation
      // hides it, but the thread underneath is still the author's to clear.
      const reel = validatePublishedReel(reelSnapshot, {
        allowHidden: true,
        allowExpiredStatus: true,
      });
      // AUTHORITY BEFORE COMMENT EXISTENCE. Whether a given commentId
      // resolves is only ever reported to somebody who already owns the
      // thread, so this endpoint is not a probe for comment ids.
      //
      // It DOES still distinguish a real Reel from an absent one for a
      // non-author — validatePublishedReel runs above and answers
      // `not-found` — which is stated rather than glossed. That is the same
      // disclosure deleteReel already makes, Reels are public content, and
      // unlike the report path every refusal here is metered, so it is not a
      // free enumeration surface. Do not reorder these two without also
      // rewriting this paragraph.
      if (reel.authorId !== auth.uid) {
        fail(
          "permission-denied",
          "Only the Reel's author can remove comments from it.",
        );
      }
      // The author's own comment on their own Reel is removable here too.
      // Routing it through deleteReelComment instead would mean an author
      // clearing a thread has to know which comments are theirs, and would
      // record half of one clean-up under a different kind.
      const commentData = validateReelComment(comment, reelId);
      const currentCount = reel.commentCount;
      if (currentCount === 0) {
        fail("data-loss", "Reel commentCount would become negative.");
      }
      transaction.delete(commentRef);
      transaction.update(reelRef, {
        commentCount: currentCount - 1,
        updatedAt: attemptTime.now,
      });
      const result = {
        reelId,
        commentId,
        removed: true,
        commentCount: currentCount - 1,
        // WHOSE WORDS WERE REMOVED, recorded on purpose.
        //
        // The ledger entry created below is the only durable trace that this
        // happened at all — `adminAuditLogs` is for staff actions and this is
        // not one. Without the subject's id the entry says "somebody removed
        // something", which is not an accountability record. The caller
        // already knows this uid (they were rendering the thread), so nothing
        // is disclosed; `integrityOperationLedgers` is `read, write: if false`
        // for every client, so nothing leaks either.
        removedAuthorId: commentData.authorId,
      };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.comment.remove",
          uid: auth.uid,
          requestId,
          inputHash: identity.inputHash,
          result,
          now: attemptTime.now,
        }),
      );
      return result;
    });
  }

  async function getReelViewV2(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentCursor", "commentLimit", "reelId"],
      ["reelId"],
    );
    const reelId = requireId(data.reelId, "reelId");
    const commentLimit = data.commentLimit === undefined ||
        data.commentLimit === null
      ? MAX_REEL_THREAD_COMMENTS
      : requireSafeInteger(data.commentLimit, "commentLimit", {
          min: 1,
          max: MAX_REEL_THREAD_COMMENTS,
        });
    const commentCursor = data.commentCursor === undefined ||
        data.commentCursor === null
      ? null
      : decodeReelCommentCursor(data.commentCursor, { reelId });
    // Also proves the viewer's own account is active and not muted.
    const attemptTime = await consumeReadLimit(auth.uid, "view");
    try {
      return await reelView(auth, reelId, {
        attemptTime,
        commentLimit,
        commentCursor,
      });
    } catch (error) {
      // One envelope for every refusal, mirroring getVoiceMomentViewV2.
      // Distinct codes here would turn this callable into a per-Reel oracle:
      // a caller banks ids from listReelsV2 while access is normal, then
      // polls to learn "did that author block me", "were they suspended or
      // muted", "did staff hide this". The rate-limit and input-validation
      // codes still propagate — they describe the caller's own request, not
      // somebody else's state.
      if (
        ["not-found", "failed-precondition", "permission-denied", "data-loss"]
          .includes(error?.code)
      ) {
        fail("permission-denied", "This Reel is unavailable.");
      }
      throw error;
    }
  }

  async function reelView(auth, reelId, {
    attemptTime,
    commentLimit,
    commentCursor,
  }) {
    const reelRef = reelReference(reelId);
    const [reelSnapshot, availabilitySnapshot, callerLike] = await getAll(
      reelRef,
      availabilityReference(reelId),
      reelLikeReference(reelId, auth.uid),
    );
    const { reel, availability } = engageableReel(
      reelSnapshot,
      availabilitySnapshot,
      attemptTime.nowMs,
    );
    const audienceReferences = reelAudienceReferences(auth.uid, reel.authorId);
    if (audienceReferences.length > 0) {
      const [authorProfile, authorRestriction, viewerBlock, authorBlock] =
        await getAll(...audienceReferences);
      assertReelAuthorAudience({
        viewerId: auth.uid,
        authorId: reel.authorId,
        authorProfile,
        authorRestriction,
        viewerBlock,
        authorBlock,
        nowMs: attemptTime.nowMs,
      });
    }

    let commentQuery = reelRef
      .collection("comments")
      .orderBy("createdAt", "asc")
      .orderBy(FieldPath.documentId(), "asc");
    if (commentCursor !== null) {
      commentQuery = commentQuery.startAfter(
        Timestamp.fromMillis(commentCursor.createdAtMillis),
        commentCursor.id,
      );
    }
    // MAX + 1 so a full page proves there is another one instead of being
    // silently truncated into "that was everything".
    const commentSnapshot = await commentQuery.limit(commentLimit + 1).get();
    const pageDocuments = commentSnapshot.docs.slice(0, commentLimit);
    const comments = [];
    for (const document of pageDocuments) {
      try {
        comments.push({
          id: document.id,
          data: validateReelComment(document, reelId),
        });
      } catch (_) {
        // A malformed child is never projected, and never fails the page.
      }
    }

    // Authorization for comment authors is the same audience rule the Reel
    // itself uses, resolved once per distinct commenter and bounded by
    // commentLimit. A comment from an account you blocked (or that blocked
    // you), a suspended account or a muted account is withheld — the
    // aggregate commentCount still includes it, because a per-viewer count
    // would leak exactly who is hidden.
    const commenterIds = [
      ...new Set(
        comments
          .map(({ data: value }) => value.authorId)
          .filter((authorId) => authorId !== auth.uid),
      ),
    ];
    const commenterReferences = commenterIds.flatMap((commenterId) => [
      db.doc(`users/${commenterId}`),
      db.doc(`restrictions/${commenterId}`),
      db.doc(`users/${auth.uid}/blocked/${commenterId}`),
      db.doc(`users/${commenterId}/blocked/${auth.uid}`),
    ]);
    const commenterSnapshots = commenterReferences.length === 0
      ? []
      : await getAll(...commenterReferences);
    const visibleCommenters = new Set([auth.uid]);
    commenterIds.forEach((commenterId, index) => {
      try {
        assertReelAuthorAudience({
          viewerId: auth.uid,
          authorId: commenterId,
          authorProfile: commenterSnapshots[index * 4],
          authorRestriction: commenterSnapshots[index * 4 + 1],
          viewerBlock: commenterSnapshots[index * 4 + 2],
          authorBlock: commenterSnapshots[index * 4 + 3],
          nowMs: attemptTime.nowMs,
        });
        visibleCommenters.add(commenterId);
      } catch (_) {
        // Withheld from this viewer only.
      }
    });

    // The bounded read above can cross the availability deadline. Re-check
    // against the response clock so a Reel is never served at `expiresAt`
    // merely because the request began a few milliseconds earlier.
    const responseTime = timing();
    if (
      availability.expiresAtMs !== null &&
      availability.expiresAtMs <= responseTime.nowMs
    ) {
      fail("failed-precondition", "The Reel has expired.");
    }
    let callerLiked = false;
    try {
      callerLiked = validateReelLike(callerLike, reelId, auth.uid);
    } catch (_) {
      callerLiked = false;
    }
    const lastDocument = pageDocuments.at(-1) ?? null;
    const commentsTruncated = commentSnapshot.size > commentLimit;
    // A corrupt document sitting exactly on the page boundary must not fail
    // the whole view — the caller chooses commentLimit, so it also chooses
    // which document lands there. `commentsTruncated` stays true, so the
    // client still knows the thread continues; only the cursor is withheld.
    let nextCommentCursor = null;
    if (commentsTruncated && lastDocument !== null) {
      try {
        nextCommentCursor = encodeReelCommentCursor({
          reelId,
          id: lastDocument.id,
          createdAtMillis: timestampMillis(lastDocument.data()?.createdAt),
        });
      } catch (_) {
        nextCommentCursor = null;
      }
    }
    return {
      schemaVersion: REEL_VIEW_SCHEMA_VERSION,
      reel: reelItemProjection(reel, availability, {
        version: 2,
        callerLiked,
      }),
      comments: comments
        .filter(({ data: value }) => visibleCommenters.has(value.authorId))
        .map(({ id, data: value }) => reelCommentProjection(id, value)),
      commentsTruncated,
      // The cursor advances past the last document actually scanned, not the
      // last one projected, so a withheld or malformed comment cannot pin a
      // thread's pagination in place.
      nextCommentCursor,
    };
  }

  function cleanupBackoffMs(attemptCount) {
    return Math.min(
      REEL_CLEANUP_MAX_BACKOFF_MS,
      REEL_CLEANUP_BASE_BACKOFF_MS * (2 ** Math.max(0, attemptCount - 1)),
    );
  }

  function cleanupErrorCode(error) {
    const code = typeof error?.code === "string" ? error.code : "internal";
    return /^[a-z0-9-]{1,64}$/u.test(code) ? code : "internal";
  }

  function validateCleanupOutbox(raw, outboxId) {
    if (
      !isPlainObject(raw) ||
      !isValidOpaqueUid(raw.ownerId) ||
      typeof raw.reelId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/u.test(raw.reelId) ||
      !Number.isSafeInteger(raw.attemptCount) ||
      raw.attemptCount < 0 ||
      timestampMillis(raw.createdAt) === null ||
      timestampMillis(raw.updatedAt) === null ||
      !["pending", "processing"].includes(raw.status)
    ) {
      fail("data-loss", "The Reel cleanup request is malformed.");
    }
    const isExpiry = raw.kind === "reelExpiryEvidenceRetention";
    let storageObjects;
    if (isExpiry) {
      if (
        raw.schemaVersion !== REEL_AVAILABILITY_SCHEMA_VERSION ||
        expiryOutboxId(raw.reelId) !== outboxId ||
        raw.retentionPolicy !== "retainOriginalsForModeration" ||
        !validGenerationBoundObjects(
          raw.storageObjects,
          raw.ownerId,
          raw.reelId,
        )
      ) {
        fail("data-loss", "The Reel expiry cleanup request is malformed.");
      }
      storageObjects = raw.storageObjects;
    } else if (raw.kind === "reelPublishedMediaCleanup") {
      if (
        raw.schemaVersion !== REEL_SCHEMA_VERSION ||
        cleanupOutboxId(raw.reelId) !== outboxId ||
        !validGenerationBoundObjects(
          raw.storageObjects,
          raw.ownerId,
          raw.reelId,
        )
      ) {
        fail("data-loss", "The Reel cleanup request is malformed.");
      }
      storageObjects = raw.storageObjects;
    } else if (raw.kind === "reelMediaCleanup") {
      if (
        raw.schemaVersion !== REEL_SCHEMA_VERSION ||
        cleanupOutboxId(raw.reelId) !== outboxId ||
        !Array.isArray(raw.storagePaths) ||
        raw.storagePaths.length < 1 ||
        raw.storagePaths.length > 2 ||
        !raw.storagePaths.every((path, index) =>
          isCanonicalCleanupPath(path, raw.ownerId, raw.reelId, index),
        )
      ) {
        fail("data-loss", "The Reel cleanup request is malformed.");
      }
      storageObjects = raw.storagePaths.map((path) => ({
        path,
        generation: null,
      }));
    } else {
      fail("data-loss", "The Reel cleanup request is malformed.");
    }

    const defaultPhase = isExpiry ? "retain" : "delete";
    const phase = raw.phase ?? defaultPhase;
    if (
      (isExpiry && phase !== "retain" && phase !== "purge") ||
      (!isExpiry && phase !== "delete")
    ) {
      fail("data-loss", "The Reel cleanup request is malformed.");
    }
    const createdAtMs = timestampMillis(raw.createdAt);
    const nextAttemptAtMs = raw.nextAttemptAt === undefined
      ? createdAtMs
      : timestampMillis(raw.nextAttemptAt);
    const purgeAtMs = isExpiry
      ? (raw.purgeAt === undefined
          ? createdAtMs + REEL_EXPIRY_EVIDENCE_RETENTION_MS
          : timestampMillis(raw.purgeAt))
      : null;
    const leaseUntilMs = raw.leaseUntil === undefined || raw.leaseUntil === null
      ? null
      : timestampMillis(raw.leaseUntil);
    if (
      nextAttemptAtMs === null ||
      (isExpiry && (purgeAtMs === null || purgeAtMs < createdAtMs)) ||
      (raw.status === "processing" &&
        (typeof raw.leaseToken !== "string" ||
          raw.leaseToken.length < 16 ||
          leaseUntilMs === null))
    ) {
      fail("data-loss", "The Reel cleanup request is malformed.");
    }
    return {
      ...raw,
      isExpiry,
      phase,
      storageObjects,
      createdAtMs,
      nextAttemptAtMs,
      purgeAtMs,
      leaseUntilMs,
    };
  }

  async function claimCleanupOutbox(reference, outboxId) {
    return db.runTransaction(async (transaction) => {
      const time = timing();
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        return { terminal: true, result: { outboxId, completed: true, missing: true } };
      }
      const raw = snapshot.data() ?? {};
      if (raw.status === "completed") {
        return { terminal: true, result: { outboxId, completed: true } };
      }
      if (raw.status === "deadLetter") {
        return {
          terminal: true,
          result: {
            outboxId,
            completed: false,
            deadLetter: true,
            code: cleanupErrorCode({ code: raw.lastErrorCode }),
          },
        };
      }
      let value;
      try {
        value = validateCleanupOutbox(raw, outboxId);
      } catch (_) {
        transaction.update(reference, {
          status: "deadLetter",
          attemptCount: Number.isSafeInteger(raw.attemptCount) &&
              raw.attemptCount >= 0
            ? raw.attemptCount + 1
            : 1,
          phase: typeof raw.phase === "string" ? raw.phase : "quarantine",
          nextAttemptAt: null,
          leaseToken: null,
          leaseUntil: null,
          lastErrorCode: "data-loss",
          deadLetterAt: time.now,
          updatedAt: time.now,
        });
        return {
          terminal: true,
          result: {
            outboxId,
            completed: false,
            deadLetter: true,
            code: "data-loss",
          },
        };
      }
      if (
        value.status === "pending" &&
        value.nextAttemptAtMs > time.nowMs
      ) {
        return {
          terminal: true,
          result: { outboxId, completed: false, deferred: true },
        };
      }
      if (
        value.status === "processing" &&
        value.leaseUntilMs > time.nowMs
      ) {
        return {
          terminal: true,
          result: { outboxId, completed: false, leased: true },
        };
      }
      const attemptCount = value.attemptCount + 1;
      const leaseToken = digest("reel-cleanup-lease", {
        outboxId,
        attemptCount,
        nowMs: time.nowMs,
      });
      transaction.update(reference, {
        status: "processing",
        attemptCount,
        phase: value.phase,
        purgeAt: value.isExpiry
          ? Timestamp.fromMillis(value.purgeAtMs)
          : null,
        nextAttemptAt: Timestamp.fromMillis(value.nextAttemptAtMs),
        leaseToken,
        leaseUntil: Timestamp.fromMillis(time.nowMs + REEL_CLEANUP_LEASE_MS),
        lastErrorCode: null,
        updatedAt: time.now,
      });
      return {
        terminal: false,
        value: { ...value, attemptCount },
        leaseToken,
      };
    });
  }

  async function recordCleanupFailure(reference, leaseToken, error) {
    return db.runTransaction(async (transaction) => {
      const time = timing();
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return { deadLetter: false, stale: true };
      const raw = snapshot.data() ?? {};
      if (raw.status !== "processing" || raw.leaseToken !== leaseToken) {
        return { deadLetter: false, stale: true };
      }
      const attemptCount = Number.isSafeInteger(raw.attemptCount)
        ? raw.attemptCount
        : REEL_CLEANUP_MAX_ATTEMPTS;
      const deadLetter = attemptCount >= REEL_CLEANUP_MAX_ATTEMPTS;
      transaction.update(reference, {
        status: deadLetter ? "deadLetter" : "pending",
        nextAttemptAt: deadLetter
          ? null
          : Timestamp.fromMillis(
              time.nowMs + cleanupBackoffMs(attemptCount),
            ),
        leaseToken: null,
        leaseUntil: null,
        lastErrorCode: cleanupErrorCode(error),
        ...(deadLetter
          ? {
              deadLetterAt: time.now,
            }
          : {}),
        updatedAt: time.now,
      });
      return { deadLetter, stale: false };
    });
  }

  async function completeCleanupOutbox(
    reference,
    leaseToken,
    { originalsRetained = undefined } = {},
  ) {
    return db.runTransaction(async (transaction) => {
      const time = timing();
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return false;
      const raw = snapshot.data() ?? {};
      if (raw.status !== "processing" || raw.leaseToken !== leaseToken) {
        return false;
      }
      transaction.update(reference, {
        status: "completed",
        nextAttemptAt: null,
        leaseToken: null,
        leaseUntil: null,
        lastErrorCode: null,
        updatedAt: time.now,
        completedAt: time.now,
        deleteAfter: Timestamp.fromMillis(
          time.nowMs + REEL_CLEANUP_AUDIT_TTL_MS,
        ),
        ...(originalsRetained === undefined ? {} : { originalsRetained }),
      });
      return true;
    });
  }

  function isPurgedExpiredReelSnapshot(snapshot) {
    return snapshot?.exists &&
      snapshot.data()?.status === "expired" &&
      Object.prototype.hasOwnProperty.call(snapshot.data() ?? {}, "purgedAt");
  }

  function isDeletedReelSnapshot(snapshot) {
    return snapshot?.exists && snapshot.data()?.status === "deleted";
  }

  function validateDeletedReel(snapshot) {
    if (!snapshot?.exists) fail("not-found", "The Reel does not exist.");
    const value = exactStoredObject(
      snapshot.data() ?? {},
      [
        "schemaVersion",
        "status",
        "authorId",
        "moderationStatusAtDeletion",
        "moderationEvidence",
        "deletedAt",
        "updatedAt",
      ],
      "Deleted Reel evidence",
    );
    const rawEvidence = value.moderationEvidence;
    const fromExpiry = isPlainObject(rawEvidence) &&
      Object.prototype.hasOwnProperty.call(rawEvidence, "expiredAt");
    const evidence = exactStoredObject(
      rawEvidence,
      fromExpiry
        ? [
            "evidenceVersion",
            "publishedAt",
            "expiredAt",
            "availabilityHours",
            "metadataFingerprint",
          ]
        : ["evidenceVersion", "publishedAt", "metadataFingerprint"],
      "Deleted Reel moderation evidence",
    );
    const publishedAtMs = timestampMillis(evidence.publishedAt);
    const deletedAtMs = timestampMillis(value.deletedAt);
    const updatedAtMs = timestampMillis(value.updatedAt);
    let expiryEvidenceValid = true;
    if (fromExpiry) {
      let availabilityHours;
      try {
        availabilityHours = validateAvailabilityHours(
          evidence.availabilityHours,
        );
      } catch (_) {
        availabilityHours = null;
      }
      const expiredAtMs = timestampMillis(evidence.expiredAt);
      expiryEvidenceValid =
        availabilityHours !== null &&
        availabilityHours !== PERMANENT_AVAILABILITY &&
        expiredAtMs !== null &&
        publishedAtMs !== null &&
        expiredAtMs >= publishedAtMs &&
        deletedAtMs !== null &&
        deletedAtMs >= expiredAtMs;
    }
    if (
      value.schemaVersion !== REEL_SCHEMA_VERSION ||
      value.status !== "deleted" ||
      !isValidOpaqueUid(value.authorId) ||
      (value.moderationStatusAtDeletion !== "visible" &&
        value.moderationStatusAtDeletion !== "hidden") ||
      evidence.evidenceVersion !== 1 ||
      publishedAtMs === null ||
      typeof evidence.metadataFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/u.test(evidence.metadataFingerprint) ||
      deletedAtMs === null ||
      updatedAtMs !== deletedAtMs ||
      deletedAtMs < publishedAtMs ||
      !expiryEvidenceValid
    ) {
      fail("data-loss", "The deleted Reel evidence is malformed.");
    }
    return { ...value, id: snapshot.id, moderationEvidence: evidence };
  }

  function validatePurgedExpiredReel(snapshot) {
    if (!snapshot?.exists) fail("not-found", "The Reel does not exist.");
    const value = exactStoredObject(
      snapshot.data() ?? {},
      [
        "schemaVersion",
        "status",
        "authorId",
        "moderationStatusAtExpiry",
        "moderationEvidence",
        "expiredAt",
        "purgedAt",
        "updatedAt",
      ],
      "Expired Reel evidence",
    );
    const evidence = exactStoredObject(
      value.moderationEvidence,
      [
        "evidenceVersion",
        "publishedAt",
        "expiredAt",
        "availabilityHours",
        "metadataFingerprint",
      ],
      "Expired Reel moderation evidence",
    );
    const expiredAtMs = timestampMillis(value.expiredAt);
    const purgedAtMs = timestampMillis(value.purgedAt);
    const publishedAtMs = timestampMillis(evidence.publishedAt);
    let availabilityHours = null;
    try {
      availabilityHours = validateAvailabilityHours(
        evidence.availabilityHours,
      );
    } catch (_) {
      fail("data-loss", "The expired Reel evidence is malformed.");
    }
    if (
      value.schemaVersion !== REEL_SCHEMA_VERSION ||
      value.status !== "expired" ||
      !isValidOpaqueUid(value.authorId) ||
      (value.moderationStatusAtExpiry !== "visible" &&
        value.moderationStatusAtExpiry !== "hidden") ||
      evidence.evidenceVersion !== 1 ||
      publishedAtMs === null ||
      timestampMillis(evidence.expiredAt) !== expiredAtMs ||
      availabilityHours === "permanent" ||
      typeof evidence.metadataFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/u.test(evidence.metadataFingerprint) ||
      expiredAtMs === null ||
      purgedAtMs === null ||
      publishedAtMs > expiredAtMs ||
      purgedAtMs < expiredAtMs ||
      timestampMillis(value.updatedAt) !== purgedAtMs
    ) {
      fail("data-loss", "The expired Reel evidence is malformed.");
    }
    return { ...value, id: snapshot.id, moderationEvidence: evidence };
  }

  function expiredEvidenceTombstone(reel, availability, time) {
    return {
      schemaVersion: REEL_SCHEMA_VERSION,
      status: "expired",
      authorId: reel.authorId,
      moderationStatusAtExpiry: reel.moderationStatus,
      moderationEvidence: {
        evidenceVersion: 1,
        publishedAt: reel.publishedAt,
        expiredAt: availability.expiredAt,
        availabilityHours: availability.availabilityHours,
        metadataFingerprint: digest("reel-expiry-evidence", {
          reelId: reel.id,
          authorId: reel.authorId,
          moderationStatus: reel.moderationStatus,
          media: reel.media,
          backingAudio: reel.backingAudio,
          composition: reel.composition,
        }),
      },
      expiredAt: availability.expiredAt,
      purgedAt: time.now,
      updatedAt: time.now,
    };
  }

  function validateExpiryCleanupState(value, reelSnapshot, availabilitySnapshot) {
    const reel = validatePublishedReel(reelSnapshot, {
      allowHidden: true,
      allowExpiredStatus: true,
    });
    const availability = publishedAvailability(
      availabilitySnapshot,
      reel,
      timing().nowMs,
      { allowExpired: true, required: true },
    );
    if (
      reel.status !== "expired" ||
      availability.status !== "expired" ||
      availability.ownerId !== value.ownerId ||
      JSON.stringify(publishedStorageObjects(reel)) !==
        JSON.stringify(value.storageObjects)
    ) {
      fail("data-loss", "The Reel expiry cleanup request is malformed.");
    }
    return { reel, availability };
  }

  async function retainExpiredReel(
    reference,
    outboxId,
    value,
    leaseToken,
  ) {
    const [reelSnapshot, availabilitySnapshot] = await getAll(
      reelReference(value.reelId),
      availabilityReference(value.reelId),
    );
    const reelState = reelSnapshot.exists ? reelSnapshot.data() ?? {} : null;
    const deletionOwnsCleanup =
      !availabilitySnapshot.exists &&
      (reelState === null || reelState.status === "deleted");
    if (!deletionOwnsCleanup) {
      validateExpiryCleanupState(value, reelSnapshot, availabilitySnapshot);
      for (let index = 0; index < value.storageObjects.length; index += 1) {
        const object = value.storageObjects[index];
        const metadata = await storage.getMetadata(object.path);
        const custom = metadata?.metadata ?? {};
        const expectedKind = index === 0 ? "media" : "backingAudio";
        if (
          String(metadata?.generation ?? "") !== object.generation ||
          custom.ownerId !== value.ownerId ||
          custom.reelId !== value.reelId ||
          custom.assetKind !== expectedKind
        ) {
          fail("data-loss", "The retained Reel object is malformed.");
        }
        await storage.revokeDownloadTokens(object.path, metadata);
      }
    }

    return db.runTransaction(async (transaction) => {
      const time = timing();
      const outboxSnapshot = await transaction.get(reference);
      if (!outboxSnapshot.exists) {
        return { outboxId, completed: false, stale: true };
      }
      const raw = outboxSnapshot.data() ?? {};
      if (raw.status !== "processing" || raw.leaseToken !== leaseToken) {
        return { outboxId, completed: false, stale: true };
      }
      const [currentReel, currentAvailability] = await transactionGetAll(
        transaction,
        reelReference(value.reelId),
        availabilityReference(value.reelId),
      );
      const currentState = currentReel.exists ? currentReel.data() ?? {} : null;
      const deletionNowOwnsCleanup =
        !currentAvailability.exists &&
        (currentState === null || currentState.status === "deleted");
      if (deletionNowOwnsCleanup) {
        transaction.update(reference, {
          status: "completed",
          nextAttemptAt: null,
          leaseToken: null,
          leaseUntil: null,
          lastErrorCode: null,
          originalsRetained: false,
          completedAt: time.now,
          deleteAfter: Timestamp.fromMillis(
            time.nowMs + REEL_CLEANUP_AUDIT_TTL_MS,
          ),
          updatedAt: time.now,
        });
        return { outboxId, completed: true, originalsRetained: false };
      }
      validateExpiryCleanupState(value, currentReel, currentAvailability);
      transaction.update(reference, {
        status: "pending",
        phase: "purge",
        purgeAt: Timestamp.fromMillis(value.purgeAtMs),
        nextAttemptAt: Timestamp.fromMillis(value.purgeAtMs),
        leaseToken: null,
        leaseUntil: null,
        lastErrorCode: null,
        originalsRetained: true,
        retainedAt: time.now,
        updatedAt: time.now,
      });
      return {
        outboxId,
        completed: false,
        retained: true,
        originalsRetained: true,
        purgeAtMillis: value.purgeAtMs,
      };
    });
  }

  async function purgeExpiredReel(
    reference,
    outboxId,
    value,
    leaseToken,
  ) {
    const [reelSnapshot, availabilitySnapshot] = await getAll(
      reelReference(value.reelId),
      availabilityReference(value.reelId),
    );
    const reelState = reelSnapshot.exists ? reelSnapshot.data() ?? {} : null;
    const deletionOwnsCleanup =
      !availabilitySnapshot.exists &&
      (reelState === null || reelState.status === "deleted");
    const alreadyPurged = isPurgedExpiredReelSnapshot(reelSnapshot);
    if (!deletionOwnsCleanup && !alreadyPurged) {
      // This proves far more than the outbox row does: the live root is
      // `expired`, the availability sidecar agrees and is itself expired, and
      // its storage objects match. Only that proof unlocks the expired-root
      // allowance below — a plain cleanup row never gets it, which is what
      // keeps a still-published Reel's engagement out of reach.
      validateExpiryCleanupState(value, reelSnapshot, availabilitySnapshot);
      // Engagement before media, for the same reason as the deletion path:
      // it is idempotent and Firestore-local, while object deletion can
      // dead-letter and strand other people's comment text.
      await purgeReelEngagement(value.reelId, { allowExpiredRoot: true });
      await Promise.all(value.storageObjects.map(({ path, generation }) =>
        storage.deleteObject(path, { generation })));
    } else if (alreadyPurged) {
      validatePurgedExpiredReel(reelSnapshot);
      // A retry after the tombstone landed still finishes the purge.
      await purgeReelEngagement(value.reelId);
    }

    return db.runTransaction(async (transaction) => {
      const time = timing();
      const [outboxSnapshot, currentReel, currentAvailability] =
        await transactionGetAll(
          transaction,
          reference,
          reelReference(value.reelId),
          availabilityReference(value.reelId),
        );
      if (!outboxSnapshot.exists) {
        return { outboxId, completed: false, stale: true };
      }
      const raw = outboxSnapshot.data() ?? {};
      if (raw.status !== "processing" || raw.leaseToken !== leaseToken) {
        return { outboxId, completed: false, stale: true };
      }
      const currentState = currentReel.exists ? currentReel.data() ?? {} : null;
      const deletionNowOwnsCleanup =
        !currentAvailability.exists &&
        (currentState === null || currentState.status === "deleted");
      let originalsRetained = false;
      if (isPurgedExpiredReelSnapshot(currentReel)) {
        validatePurgedExpiredReel(currentReel);
      } else if (!deletionNowOwnsCleanup) {
        const state = validateExpiryCleanupState(
          value,
          currentReel,
          currentAvailability,
        );
        transaction.set(
          reelReference(value.reelId),
          expiredEvidenceTombstone(state.reel, state.availability, time),
        );
        transaction.delete(availabilityReference(value.reelId));
      }
      transaction.update(reference, {
        status: "completed",
        nextAttemptAt: null,
        leaseToken: null,
        leaseUntil: null,
        lastErrorCode: null,
        originalsRetained,
        completedAt: time.now,
        deleteAfter: Timestamp.fromMillis(
          time.nowMs + REEL_CLEANUP_AUDIT_TTL_MS,
        ),
        updatedAt: time.now,
      });
      return { outboxId, completed: true, originalsRetained };
    });
  }

  async function processExpiryRetentionOutbox(
    reference,
    outboxId,
    value,
    leaseToken,
  ) {
    if (value.phase === "retain") {
      return retainExpiredReel(reference, outboxId, value, leaseToken);
    }
    return purgeExpiredReel(reference, outboxId, value, leaseToken);
  }

  async function processCleanupOutbox(outboxId) {
    requireId(outboxId, "outboxId");
    const reference = db.doc(`reelCleanupOutbox/${outboxId}`);
    const claim = await claimCleanupOutbox(reference, outboxId);
    if (claim.terminal) return claim.result;
    try {
      if (claim.value.isExpiry) {
        return await processExpiryRetentionOutbox(
          reference,
          outboxId,
          claim.value,
          claim.leaseToken,
        );
      }
      // Engagement first, media second. The purge is cheap, idempotent and
      // depends on nothing outside Firestore, while object deletion can fail
      // for eight attempts and then dead-letter terminally. Ordering it after
      // Storage made another person's comment text durably stored, with the
      // comment's own author already locked out of deleting it (the root is a
      // tombstone by then), on a failure that has nothing to do with them.
      const engagement = await purgeReelEngagement(claim.value.reelId);
      await Promise.all(claim.value.storageObjects.map(({ path, generation }) =>
        storage.deleteObject(
          path,
          generation === null ? undefined : { generation },
        )));
      const completed = await completeCleanupOutbox(
        reference,
        claim.leaseToken,
      );
      return { outboxId, completed, stale: !completed, engagement };
    } catch (error) {
      await recordCleanupFailure(reference, claim.leaseToken, error);
      throw error;
    }
  }

  async function quarantineExpiredAvailability(reelId, error) {
    return db.runTransaction(async (transaction) => {
      const time = timing();
      const availabilityRef = availabilityReference(reelId);
      const reelRef = reelReference(reelId);
      const [availabilitySnapshot, reelSnapshot] = await transactionGetAll(
        transaction,
        availabilityRef,
        reelRef,
      );
      if (!availabilitySnapshot.exists) return false;
      const raw = availabilitySnapshot.data() ?? {};
      const expiresAtMs = timestampMillis(raw.expiresAt);
      if (
        raw.status !== "published" ||
        (expiresAtMs !== null && expiresAtMs > time.nowMs)
      ) {
        return false;
      }
      // Poisoned due rows must not occupy every bounded sweep forever. The
      // canonical quarantine is fail-closed and intentionally contains no
      // media descriptor. Operators retain the root/evidence for repair.
      transaction.set(availabilityRef, {
        schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
        status: "quarantined",
        reelId,
        reason: cleanupErrorCode(error),
        quarantinedAt: time.now,
        updatedAt: time.now,
      });
      if (reelSnapshot.exists && reelSnapshot.data()?.status === "published") {
        transaction.update(reelRef, {
          status: "expired",
          updatedAt: time.now,
        });
      }
      return true;
    });
  }

  async function expirePublishedReels({ limit = 100 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 200 });
    const queryTime = timing();
    const snapshot = await db
      .collection("reelAvailability")
      .where("status", "==", "published")
      .where("expiresAt", "<=", queryTime.now)
      .orderBy("expiresAt")
      .limit(limit)
      .get();
    const expired = [];
    const failed = [];
    for (const document of snapshot.docs) {
      try {
        const candidate = validateAvailabilitySnapshot(document, {
          reelId: document.id,
          required: true,
        });
        if (
          candidate.status !== "published" ||
          candidate.expiresAtMs === null ||
          candidate.expiresAtMs > queryTime.nowMs
        ) {
          continue;
        }
        const didExpire = await db.runTransaction(async (transaction) => {
          const attemptTime = timing();
          const availabilityRef = availabilityReference(document.id);
          const reelRef = reelReference(document.id);
          const outboxRef = db.doc(
            `reelCleanupOutbox/${expiryOutboxId(document.id)}`,
          );
          const [currentAvailability, reelSnapshot, existingOutbox] =
            await transactionGetAll(
              transaction,
              availabilityRef,
              reelRef,
              outboxRef,
            );
          if (!currentAvailability.exists) return false;
          if (!reelSnapshot.exists || reelSnapshot.data()?.status !== "published") {
            fail("data-loss", "The expiring Reel root is malformed.");
          }
          const reel = validatePublishedReel(reelSnapshot, {
            allowHidden: true,
          });
          const availability = publishedAvailability(
            currentAvailability,
            reel,
            attemptTime.nowMs,
            { allowExpired: true, required: true },
          );
          if (
            availability.status !== "published" ||
            availability.expiresAtMs === null ||
            availability.expiresAtMs > attemptTime.nowMs
          ) {
            return false;
          }
          const storageObjects = publishedStorageObjects(reel);
          if (existingOutbox.exists) {
            const existing = existingOutbox.data() ?? {};
            if (
              existing.schemaVersion !== REEL_AVAILABILITY_SCHEMA_VERSION ||
              existing.kind !== "reelExpiryEvidenceRetention" ||
              existing.ownerId !== reel.authorId ||
              existing.reelId !== reel.id ||
              existing.retentionPolicy !== "retainOriginalsForModeration" ||
              !["pending", "processing"].includes(
                existing.status,
              ) ||
              JSON.stringify(existing.storageObjects) !==
                JSON.stringify(storageObjects)
            ) {
              fail("data-loss", "The Reel expiry cleanup request is malformed.");
            }
          } else {
            transaction.create(outboxRef, {
              schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
              kind: "reelExpiryEvidenceRetention",
              ownerId: reel.authorId,
              reelId: reel.id,
              storageObjects,
              retentionPolicy: "retainOriginalsForModeration",
              status: "pending",
              attemptCount: 0,
              phase: "retain",
              purgeAt: Timestamp.fromMillis(
                attemptTime.nowMs + REEL_EXPIRY_EVIDENCE_RETENTION_MS,
              ),
              nextAttemptAt: attemptTime.now,
              leaseToken: null,
              leaseUntil: null,
              lastErrorCode: null,
              createdAt: attemptTime.now,
              updatedAt: attemptTime.now,
            });
          }
          transaction.update(reelRef, {
            status: "expired",
            updatedAt: attemptTime.now,
          });
          transaction.set(availabilityRef, {
            schemaVersion: REEL_AVAILABILITY_SCHEMA_VERSION,
            status: "expired",
            ownerId: availability.ownerId,
            reelId: availability.reelId,
            availabilityHours: availability.availabilityHours,
            createdAt: availability.createdAt,
            publishedAt: availability.publishedAt,
            expiredAt: attemptTime.now,
            updatedAt: attemptTime.now,
          });
          return true;
        });
        if (didExpire) expired.push(document.id);
      } catch (error) {
        let quarantined = false;
        if (error?.code === "data-loss") {
          try {
            quarantined = await quarantineExpiredAvailability(document.id, error);
          } catch (_) {
            // A concurrent repair/delete may win; the next bounded sweep can
            // retry only if the due candidate is still queryable.
          }
        }
        failed.push({
          reelId: document.id,
          code: cleanupErrorCode(error),
          quarantined,
        });
      }
    }
    return {
      expired,
      failed,
      hasMore: snapshot.size === limit,
    };
  }

  async function expireAbandonedReelDrafts({ limit = 100 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 100 });
    const queryTime = timing();
    const snapshot = await db
      .collection("reelUploadReservations")
      .where("expiresAt", "<=", queryTime.now)
      .orderBy("expiresAt")
      .limit(limit)
      .get();
    const expired = [];
    for (const document of snapshot.docs) {
      try {
        const reservation = validateReservation(document);
        const outboxId = cleanupOutboxId(reservation.reelId);
        const didExpire = await db.runTransaction(async (transaction) => {
          const attemptTime = timing();
          const availabilityRef = availabilityReference(document.id);
          const [current, currentAvailability] = await transactionGetAll(
            transaction,
            document.ref,
            availabilityRef,
          );
          if (!current.exists) return false;
          const value = validateReservation(current);
          const availability = reservationAvailability(
            currentAvailability,
            value,
          );
          if (value.expiresAtMs > attemptTime.nowMs) return false;
          transaction.set(db.doc(`reelCleanupOutbox/${outboxId}`), {
            schemaVersion: REEL_SCHEMA_VERSION,
            kind: "reelMediaCleanup",
            ownerId: value.ownerId,
            reelId: value.reelId,
            storagePaths: [
              value.mediaStoragePath,
              ...(value.backingAudioStoragePath === null
                ? []
                : [value.backingAudioStoragePath]),
            ],
            status: "pending",
            attemptCount: 0,
            phase: "delete",
            nextAttemptAt: attemptTime.now,
            leaseToken: null,
            leaseUntil: null,
            lastErrorCode: null,
            createdAt: attemptTime.now,
            updatedAt: attemptTime.now,
          });
          transaction.delete(document.ref);
          if (availability !== null) transaction.delete(availabilityRef);
          return true;
        });
        if (didExpire) expired.push(reservation.reelId);
      } catch (_) {
        // Malformed state is preserved for explicit operator investigation.
      }
    }
    return { expired, hasMore: snapshot.size === limit };
  }

  async function processReadyCleanupOutbox({ limit = 20 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 50 });
    const time = timing();
    const collection = db.collection("reelCleanupOutbox");
    const legacyStateRef = db.doc(REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH);
    const legacyState = await legacyStateRef.get();
    const rawLegacyCursor = legacyState.exists
      ? legacyState.data()?.cursor ?? null
      : null;
    const legacyCursor = typeof rawLegacyCursor === "string" &&
        /^[A-Za-z0-9_-]{1,128}$/u.test(rawLegacyCursor)
      ? rawLegacyCursor
      : null;
    let legacyQuery = collection
      .where("status", "==", "pending")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (legacyCursor !== null) {
      legacyQuery = legacyQuery.startAfter(legacyCursor);
    }
    const [readyPending, expiredLeases, legacyPending] = await Promise.all([
      collection
        .where("status", "==", "pending")
        .where("nextAttemptAt", "<=", time.now)
        .orderBy("nextAttemptAt")
        .limit(limit)
        .get(),
      collection
        .where("status", "==", "processing")
        .where("leaseUntil", "<=", time.now)
        .orderBy("leaseUntil")
        .limit(limit)
        .get(),
      // Firestore cannot query for a missing field. Walk pending document ids
      // through a durable, server-only cursor so legacy rows without
      // nextAttemptAt cannot be hidden forever behind newer deferred rows.
      legacyQuery.get(),
    ]);
    const legacyScanHasMore = legacyPending.size === limit;
    const nextLegacyCursor = legacyScanHasMore
      ? legacyPending.docs.at(-1)?.id ?? null
      : null;
    // Canonicalize invalid state and wrap after the final short page. The
    // scheduler is single-instance, and this durable checkpoint also keeps
    // progress across cold starts and its bounded multi-page invocations.
    if (
      !legacyState.exists ||
      rawLegacyCursor !== nextLegacyCursor
    ) {
      await legacyStateRef.set({
        schemaVersion: 1,
        cursor: nextLegacyCursor,
        updatedAt: time.now,
      });
    }
    const documents = [];
    const seen = new Set();
    for (const document of [
      ...legacyPending.docs.filter((candidate) =>
        candidate.data()?.nextAttemptAt === undefined),
      ...readyPending.docs,
      ...expiredLeases.docs,
    ]) {
      if (documents.length >= limit) break;
      if (!seen.has(document.id)) {
        seen.add(document.id);
        documents.push(document);
      }
    }
    const results = await Promise.all(documents.map(async (document) => {
      try {
        return await processCleanupOutbox(document.id);
      } catch (error) {
        return {
          outboxId: document.id,
          completed: false,
          code: cleanupErrorCode(error),
        };
      }
    }));
    return {
      processed: results.length,
      completed: results.filter(({ completed }) => completed === true).length,
      failed: results.filter(({ code }) => code !== undefined),
      hasMore:
        readyPending.size === limit ||
        expiredLeases.size === limit ||
        legacyScanHasMore,
    };
  }

  return Object.freeze({
    createReelComment,
    createReelCommentReport,
    createReelReport,
    deleteReel,
    deleteReelComment,
    expireAbandonedReelDrafts,
    expirePublishedReels,
    finalizeReelDraft,
    finalizeReelDraftV2,
    getReelMediaAccess,
    getReelMediaAccessV2,
    getReelViewV2,
    listReels,
    listReelsV2,
    processCleanupOutbox,
    processReadyCleanupOutbox,
    removeReelComment,
    reserveReelDraft,
    reserveReelDraftV2,
    setReelLike,
  });
}

module.exports = {
  DEFAULT_LIMITS,
  MAX_REEL_AUTHORS_PER_REQUEST,
  MAX_REEL_SCAN_PER_REQUEST,
  MEDIA_GRANT_TTL_MS,
  REEL_CLEANUP_LEGACY_SWEEP_STATE_PATH,
  REEL_CLEANUP_BASE_BACKOFF_MS,
  REEL_CLEANUP_LEASE_MS,
  REEL_CLEANUP_MAX_ATTEMPTS,
  REEL_EXPIRY_EVIDENCE_RETENTION_MS,
  REEL_FEED_BATCH_SIZE,
  RESERVATION_TTL_MS,
  createReelService,
};

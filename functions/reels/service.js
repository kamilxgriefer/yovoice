const {
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  canonicalPublicProfile,
  consumeRateLimit,
  digest,
  fail,
  isValidOpaqueUid,
  ledgerData,
  normalizeText,
  operationIdentity,
  rateLimitReference,
  requireActor,
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
    const value = exactStoredObject(
      snapshot.data() ?? {},
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
    return { ...value, id: snapshot.id, media, backingAudio, composition };
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
      }
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
      const authorizationReferences = [...authorIds].flatMap((authorId) => [
        db.doc(`users/${authorId}`),
        db.doc(`restrictions/${authorId}`),
        db.doc(`users/${auth.uid}/blocked/${authorId}`),
        db.doc(`users/${authorId}/blocked/${auth.uid}`),
      ]);
      const references = [
        ...availabilityReferences,
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
      validateExpiryCleanupState(value, reelSnapshot, availabilitySnapshot);
      await Promise.all(value.storageObjects.map(({ path, generation }) =>
        storage.deleteObject(path, { generation })));
    } else if (alreadyPurged) {
      validatePurgedExpiredReel(reelSnapshot);
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
      await Promise.all(claim.value.storageObjects.map(({ path, generation }) =>
        storage.deleteObject(
          path,
          generation === null ? undefined : { generation },
        )));
      const completed = await completeCleanupOutbox(
        reference,
        claim.leaseToken,
      );
      return { outboxId, completed, stale: !completed };
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
    createReelReport,
    deleteReel,
    expireAbandonedReelDrafts,
    expirePublishedReels,
    finalizeReelDraft,
    finalizeReelDraftV2,
    getReelMediaAccess,
    getReelMediaAccessV2,
    listReels,
    listReelsV2,
    processCleanupOutbox,
    processReadyCleanupOutbox,
    reserveReelDraft,
    reserveReelDraftV2,
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

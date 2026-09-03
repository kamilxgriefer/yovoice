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

const RESERVATION_TTL_MS = 30 * 60 * 1000;
const MEDIA_GRANT_TTL_MS = 90 * 1000;
const MEDIA_DURATION_TOLERANCE_MS = 2 * 1000;
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

  function validatePublishedReel(snapshot, { allowHidden = false } = {}) {
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
      value.status !== "published" ||
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

  async function reserveReelDraft(request) {
    const auth = requireActor(request);
    const requestId = requireRequestId(request?.data?.requestId);
    const plan = validateDraftPlan(request.data);
    const input = { ...plan };
    const identity = operationIdentity("reel.reserve", auth.uid, requestId, input);
    const reelId = reelIdFor(auth.uid, requestId);
    return db.runTransaction(async (transaction) => {
      // Firestore may retry this callback. Every attempt gets one coherent,
      // server-controlled clock value for restrictions, quotas and timestamps.
      const attemptTime = timing();
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("reserve", auth.uid);
      const reservationRef = reservationReference(reelId);
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
        kind: "reel.reserve",
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
      const result = {
        reelId,
        mediaStoragePath,
        backingAudioStoragePath,
        expiresAtMillis,
      };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.reserve",
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

  async function finalizeReelDraft(request) {
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
    const identity = operationIdentity("reel.finalize", auth.uid, requestId, rawInput);
    const priorLedger = await ledgerReference(identity).get();
    const priorReplay = assertLedgerReplay(priorLedger, {
      kind: "reel.finalize",
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
      const [ledger, priorPreflight, rate, currentReservation, actor,
        restriction, publicProfile] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        rateRef,
        reservationRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      if (priorPreflight.exists) {
        const value = priorPreflight.data() ?? {};
        if (value.schemaVersion !== REEL_SCHEMA_VERSION ||
            value.kind !== "reel.finalize" ||
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
          kind: "reel.finalize",
          ownerId: auth.uid,
          requestId,
          scope: "finalize",
          inputHash: identity.inputHash,
          createdAt: attemptTime.now,
        });
      }
      return { replay: null, reservation: current };
    });
    if (preflight.replay) return preflight.replay;
    const reservation = preflight.reservation;
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
      const [ledger, committedPreflight, currentReservation, actor,
        restriction, publicProfile] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          preflightRef,
          reservationRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          db.doc(`publicProfiles/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightValue = committedPreflight.exists
        ? committedPreflight.data() ?? {}
        : {};
      if (preflightValue.schemaVersion !== REEL_SCHEMA_VERSION ||
          preflightValue.kind !== "reel.finalize" ||
          preflightValue.ownerId !== auth.uid ||
          preflightValue.scope !== "finalize" ||
          preflightValue.inputHash !== identity.inputHash) {
        fail("failed-precondition", "The Reel upload preflight is not canonical.");
      }
      const current = validateReservation(currentReservation, {
        ownerId: auth.uid,
        reelId,
      });
      if (
        current.expiresAtMs <= attemptTime.nowMs ||
        !sameReservation(current, reservation)
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
      transaction.delete(reservationRef);
      const result = { reelId, published: true };
      transaction.create(
        ledgerRef,
        ledgerData({
          kind: "reel.finalize",
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

  async function visibleFeedItem(reel, viewerId, snapshotMap, nowMs) {
    try {
      const author = snapshotMap.get(`users/${reel.authorId}`);
      const restriction = snapshotMap.get(`restrictions/${reel.authorId}`);
      const viewerBlock = snapshotMap.get(
        `users/${viewerId}/blocked/${reel.authorId}`,
      );
      const authorBlock = snapshotMap.get(
        `users/${reel.authorId}/blocked/${viewerId}`,
      );
      activeProfile(author, "The author");
      assertNotRestricted(restriction, "The author", nowMs);
      assertNotBlocked(viewerBlock, authorBlock);
      return {
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
    } catch (_) {
      return null;
    }
  }

  async function listReels(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(request.data, ["cursor", "limit"], ["limit"]);
    const limit = requireSafeInteger(data.limit, "limit", {
      min: 1,
      max: MAX_REEL_PAGE_SIZE,
    });
    const cursor = data.cursor === null || data.cursor === undefined
      ? null
      : validateSortKey(data.cursor);
    const readTime = await consumeReadLimit(auth.uid, "list");
    const items = [];
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
    while (items.length < limit &&
        scanned < MAX_REEL_SCAN_PER_REQUEST &&
        !exhausted &&
        !authorizationBudgetReached) {
      const batchSize = Math.min(
        REEL_FEED_BATCH_SIZE,
        MAX_REEL_SCAN_PER_REQUEST - scanned,
      );
      let query = db.collection("reels").orderBy("sortKey", "desc");
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
      const references = [...authorIds].flatMap((authorId) => [
        db.doc(`users/${authorId}`),
        db.doc(`restrictions/${authorId}`),
        db.doc(`users/${auth.uid}/blocked/${authorId}`),
        db.doc(`users/${authorId}/blocked/${auth.uid}`),
      ]);
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
          const item = await visibleFeedItem(
            entry.candidate,
            auth.uid,
            authorizationSnapshots,
            readTime.nowMs,
          );
          if (item !== null) items.push(item);
        }
        if (items.length === limit || scanned === MAX_REEL_SCAN_PER_REQUEST) {
          break;
        }
      }
      if ((poisonedCursor && processed === entries.length) ||
          (processed === entries.length && snapshot.size < batchSize)) {
        exhausted = true;
      }
    }
    return {
      items,
      nextCursor: exhausted || nextCursor === cursor ? null : nextCursor,
    };
  }

  async function authorizeMediaAccess(uid, reelId, asset) {
    const time = timing();
    const reelSnapshot = await reelReference(reelId).get();
    const reel = validatePublishedReel(reelSnapshot);
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
    return { authorId: reel.authorId, descriptor, checkedAtMs: time.nowMs };
  }

  async function getReelMediaAccess(request) {
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
    const expiresAtMillis = timing().nowMs + MEDIA_GRANT_TTL_MS;
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
      finalAccess.descriptor.generation !== access.descriptor.generation
    ) {
      fail("aborted", "Reel media authorization changed. Try again.");
    }
    return {
      schemaVersion: REEL_SCHEMA_VERSION,
      url,
      expiresAtMillis,
      generation: verified.generation,
    };
  }

  function cleanupOutboxId(reelId) {
    return digest("reel-cleanup", reelId).slice(0, 40);
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

  async function deleteReel(request) {
    const auth = requireActor(request);
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
      const [ledger, rate, actor, restriction, reelSnapshot] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          reelReference(reelId),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(actor, "Your");
      assertNotRestricted(restriction, "Your", attemptTime.nowMs);
      const reel = validatePublishedReel(reelSnapshot, { allowHidden: true });
      if (reel.authorId !== auth.uid) {
        fail("permission-denied", "Only the author can delete this Reel.");
      }
      consume(transaction, rate, rateRef, "delete", auth.uid, attemptTime);
      const outboxId = cleanupOutboxId(reelId);
      const storageObjects = [
        {
          path: reel.media.storagePath,
          generation: reel.media.generation,
        },
        ...(reel.backingAudio === null ? [] : [{
          path: reel.backingAudio.storagePath,
          generation: reel.backingAudio.generation,
        }]),
      ];
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
        createdAt: attemptTime.now,
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
      const [ledger, rate, actor, reelSnapshot, existing] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          db.doc(`users/${auth.uid}`),
          reelReference(reelId),
          reportRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "reel.report",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(actor, "Your");
      const reel = validatePublishedReel(reelSnapshot);
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

  async function processCleanupOutbox(outboxId) {
    requireId(outboxId, "outboxId");
    const reference = db.doc(`reelCleanupOutbox/${outboxId}`);
    const snapshot = await reference.get();
    if (!snapshot.exists) return { outboxId, completed: true, missing: true };
    const value = snapshot.data() ?? {};
    if (value.status === "completed") return { outboxId, completed: true };
    const commonIsMalformed =
      value.schemaVersion !== REEL_SCHEMA_VERSION ||
      value.status !== "pending" ||
      !isValidOpaqueUid(value.ownerId) ||
      typeof value.reelId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/u.test(value.reelId) ||
      cleanupOutboxId(value.reelId) !== outboxId ||
      !Number.isSafeInteger(value.attemptCount) ||
      value.attemptCount < 0;
    let storageObjects = null;
    if (!commonIsMalformed && value.kind === "reelPublishedMediaCleanup") {
      if (
        Array.isArray(value.storageObjects) &&
        value.storageObjects.length >= 1 &&
        value.storageObjects.length <= 2 &&
        value.storageObjects.every((object, index) =>
          isPlainObject(object) &&
          Object.keys(object).length === 2 &&
          Object.prototype.hasOwnProperty.call(object, "path") &&
          Object.prototype.hasOwnProperty.call(object, "generation") &&
          isCanonicalCleanupPath(
            object.path,
            value.ownerId,
            value.reelId,
            index,
          ) &&
          typeof object.generation === "string" &&
          /^[0-9]{1,30}$/u.test(object.generation),
        )
      ) {
        storageObjects = value.storageObjects;
      }
    } else if (!commonIsMalformed && value.kind === "reelMediaCleanup") {
      if (
        Array.isArray(value.storagePaths) &&
        value.storagePaths.length >= 1 &&
        value.storagePaths.length <= 2 &&
        value.storagePaths.every((path, index) =>
          isCanonicalCleanupPath(path, value.ownerId, value.reelId, index),
        )
      ) {
        storageObjects = value.storagePaths.map((path) => ({
          path,
          generation: null,
        }));
      }
    }
    if (commonIsMalformed || storageObjects === null) {
      fail("data-loss", "The Reel cleanup request is malformed.");
    }
    await Promise.all(storageObjects.map(({ path, generation }) =>
      storage.deleteObject(
        path,
        generation === null ? undefined : { generation },
      )));
    const time = timing();
    await reference.update({
      status: "completed",
      attemptCount: (Number.isSafeInteger(value.attemptCount) ? value.attemptCount : 0) + 1,
      updatedAt: time.now,
      completedAt: time.now,
    });
    return { outboxId, completed: true };
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
          const current = await transaction.get(document.ref);
          if (!current.exists) return false;
          const value = validateReservation(current);
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
            createdAt: attemptTime.now,
            updatedAt: attemptTime.now,
          });
          transaction.delete(document.ref);
          return true;
        });
        if (didExpire) expired.push(reservation.reelId);
      } catch (_) {
        // Malformed state is preserved for explicit operator investigation.
      }
    }
    return { expired, hasMore: snapshot.size === limit };
  }

  return Object.freeze({
    createReelReport,
    deleteReel,
    expireAbandonedReelDrafts,
    finalizeReelDraft,
    getReelMediaAccess,
    listReels,
    processCleanupOutbox,
    reserveReelDraft,
  });
}

module.exports = {
  DEFAULT_LIMITS,
  MAX_REEL_AUTHORS_PER_REQUEST,
  MAX_REEL_SCAN_PER_REQUEST,
  MEDIA_GRANT_TTL_MS,
  REEL_FEED_BATCH_SIZE,
  RESERVATION_TTL_MS,
  createReelService,
};

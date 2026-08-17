const {
  SAFE_ID,
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
  nonNegativeCount,
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

const DEFAULT_LIMITS = Object.freeze({
  uploadReserve: { maxEvents: 5, windowMs: 10 * 60_000 },
  finalize: { maxEvents: 10, windowMs: 10 * 60_000 },
  like: { maxEvents: 60, windowMs: 60_000 },
  comment: { maxEvents: 20, windowMs: 60_000 },
  delete: { maxEvents: 10, windowMs: 60_000 },
  report: { maxEvents: 10, windowMs: 10 * 60_000 },
});

const AUDIO_TYPES = new Set([
  "audio/mp4",
  "audio/m4a",
  "audio/x-m4a",
]);
const MAX_AUDIO_BYTES = 12 * 1024 * 1024;
const MIN_AUDIO_BYTES = 512;

function canonicalMomentId(uid, requestId) {
  return digest("voice-moment", uid, requestId).slice(0, 20);
}

function canonicalCommentId(uid, momentId, requestId) {
  return digest("voice-moment-comment", uid, momentId, requestId).slice(0, 20);
}

function momentStoragePath(uid, momentId) {
  return `voice_moments/${uid}/${momentId}.m4a`;
}

function voiceReplyStoragePath(uid, momentId, commentId) {
  return `voice_replies/${uid}/${momentId}/${commentId}.m4a`;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validateMoment(snapshot, momentId, { published = undefined } = {}) {
  if (!snapshot.exists) fail("not-found", "The Voice Moment does not exist.");
  const data = snapshot.data() ?? {};
  const expectedKeys = [
    "audioUrl",
    "authorId",
    "authorName",
    "authorPhotoUrl",
    "caption",
    "commentCount",
    "createdAt",
    "durationSeconds",
    "isDeleted",
    "isPublished",
    "likeCount",
    "mediaContentType",
    "mediaGeneration",
    "mediaSize",
    "publishedAt",
    "replyToMomentId",
    "schemaVersion",
    "status",
    "storagePath",
    "updatedAt",
  ];
  const keys = Object.keys(data).sort();
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      data.schemaVersion !== 2 || typeof data.authorId !== "string" ||
      data.storagePath !== momentStoragePath(data.authorId, momentId) ||
      !Number.isSafeInteger(data.durationSeconds) || data.durationSeconds < 1 ||
      data.durationSeconds > 60 || typeof data.caption !== "string" ||
      data.caption.length > 280 || typeof data.isPublished !== "boolean" ||
      typeof data.isDeleted !== "boolean") {
    fail("data-loss", "The Voice Moment schema is not canonical.");
  }
  if (typeof data.authorName !== "string" || !data.authorName.trim() ||
      data.authorName.length > 80 ||
      (data.authorPhotoUrl !== null &&
        (typeof data.authorPhotoUrl !== "string" ||
          data.authorPhotoUrl.length > 2048)) ||
      data.replyToMomentId !== null ||
      timestampMillis(data.createdAt) === null ||
      timestampMillis(data.updatedAt) === null) {
    fail("data-loss", "The Voice Moment identity or timestamps are malformed.");
  }
  if (data.isDeleted || data.status === "deleting") {
    if (data.isDeleted !== true || data.status !== "deleting" ||
        data.isPublished !== false) {
      fail("data-loss", "The Voice Moment deletion state is malformed.");
    }
    fail("failed-precondition", "The Voice Moment is being deleted.");
  }
  if (data.isPublished) {
    if (data.status !== "published" || typeof data.audioUrl !== "string" ||
        !data.audioUrl || data.audioUrl.length > 4096 ||
        typeof data.mediaGeneration !== "string" || !data.mediaGeneration ||
        !Number.isSafeInteger(data.mediaSize) || data.mediaSize < MIN_AUDIO_BYTES ||
        data.mediaSize > MAX_AUDIO_BYTES ||
        !AUDIO_TYPES.has(data.mediaContentType) ||
        timestampMillis(data.publishedAt) === null) {
      fail("data-loss", "The published Voice Moment media state is malformed.");
    }
  } else if (data.status !== "uploading" || data.audioUrl !== null ||
      data.mediaGeneration !== null || data.mediaSize !== null ||
      data.mediaContentType !== null || data.publishedAt !== null) {
    fail("data-loss", "The Voice Moment draft state is malformed.");
  }
  nonNegativeCount(data.likeCount, "Voice Moment likeCount");
  nonNegativeCount(data.commentCount, "Voice Moment commentCount");
  if (published !== undefined && data.isPublished !== published) {
    fail("failed-precondition", published
      ? "The Voice Moment is not published."
      : "The Voice Moment is already published.");
  }
  return data;
}

function validateComment(snapshot, momentId) {
  if (!snapshot.exists) fail("not-found", "The comment does not exist.");
  const data = snapshot.data() ?? {};
  const expectedKeys = [
    "audioUrl",
    "authorId",
    "authorName",
    "authorPhotoUrl",
    "createdAt",
    "durationSeconds",
    "mediaContentType",
    "mediaGeneration",
    "mediaSize",
    "schemaVersion",
    "storagePath",
    "text",
    "type",
  ];
  const keys = Object.keys(data).sort();
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      data.schemaVersion !== 2 || !["text", "voice"].includes(data.type) ||
      !isValidOpaqueUid(data.authorId) ||
      typeof data.authorName !== "string" || !data.authorName.trim() ||
      data.authorName.length > 80 ||
      (data.authorPhotoUrl !== null &&
        (typeof data.authorPhotoUrl !== "string" ||
          data.authorPhotoUrl.length > 2048)) ||
      typeof data.text !== "string" ||
      timestampMillis(data.createdAt) === null) {
    fail("data-loss", "The comment schema is not canonical.");
  }
  if (data.type === "text") {
    if (!data.text || data.text.length > 1000 || data.audioUrl !== null ||
        data.storagePath !== null || data.durationSeconds !== null ||
        data.mediaGeneration !== null || data.mediaSize !== null ||
        data.mediaContentType !== null) {
      fail("data-loss", "The text comment payload is malformed.");
    }
  } else if (data.storagePath !== voiceReplyStoragePath(
    data.authorId,
    momentId,
    snapshot.id,
  ) || !Number.isSafeInteger(data.durationSeconds) ||
      data.durationSeconds < 1 || data.durationSeconds > 60 ||
      typeof data.audioUrl !== "string" || !data.audioUrl ||
      data.audioUrl.length > 4096 || data.text.length > 140 ||
      typeof data.mediaGeneration !== "string" || !data.mediaGeneration ||
      !Number.isSafeInteger(data.mediaSize) || data.mediaSize < MIN_AUDIO_BYTES ||
      data.mediaSize > MAX_AUDIO_BYTES ||
      !AUDIO_TYPES.has(data.mediaContentType)) {
    fail("data-loss", "The voice comment payload is malformed.");
  }
  return data;
}

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return isPlainObject(custom) ? custom : {};
}

function validateStoredAudio(metadata, expected, requestedGeneration) {
  if (!metadata || typeof metadata !== "object") {
    fail("failed-precondition", "The uploaded audio object is missing.");
  }
  const size = Number(metadata.size);
  if (!Number.isSafeInteger(size) || size < MIN_AUDIO_BYTES ||
      size > MAX_AUDIO_BYTES || !AUDIO_TYPES.has(metadata.contentType)) {
    fail("failed-precondition", "The uploaded audio payload is invalid.");
  }
  const generation = String(metadata.generation ?? "");
  if (!generation || String(requestedGeneration) !== generation) {
    fail("failed-precondition", "The uploaded object generation does not match.");
  }
  const custom = customMetadataOf(metadata);
  const keys = Object.keys(custom).sort();
  const expectedKeys = Object.keys(expected).sort();
  const allowedKeys = [...expectedKeys, "firebaseStorageDownloadTokens"].sort();
  if (keys.some((key) => !allowedKeys.includes(key)) ||
      expectedKeys.some((key) => custom[key] !== expected[key])) {
    fail("failed-precondition", "The uploaded object identity is invalid.");
  }
  return {
    contentType: metadata.contentType,
    generation,
    size,
  };
}

function validateVoiceReservation(data, {
  ownerId,
  momentId,
  commentId,
  storagePath,
  nowMs,
}) {
  const expectedKeys = [
    "authorName",
    "authorPhotoUrl",
    "commentId",
    "createdAt",
    "durationSeconds",
    "expiresAt",
    "kind",
    "momentId",
    "ownerId",
    "schemaVersion",
    "status",
    "storagePath",
    "text",
  ];
  const keys = Object.keys(data).sort();
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      data.schemaVersion !== 1 || data.kind !== "voiceMomentComment" ||
      data.ownerId !== ownerId || data.momentId !== momentId ||
      data.commentId !== commentId || data.storagePath !== storagePath ||
      data.status !== "uploading" ||
      !Number.isSafeInteger(data.durationSeconds) ||
      data.durationSeconds < 1 || data.durationSeconds > 60 ||
      typeof data.text !== "string" || data.text.length > 140 ||
      typeof data.authorName !== "string" || !data.authorName.trim() ||
      data.authorName.length > 80 ||
      (data.authorPhotoUrl !== null &&
        (typeof data.authorPhotoUrl !== "string" ||
          data.authorPhotoUrl.length > 2048)) ||
      timestampMillis(data.createdAt) === null ||
      timestampMillis(data.expiresAt) === null ||
      timestampMillis(data.expiresAt) <= nowMs) {
    fail("failed-precondition", "The voice-comment reservation is invalid.");
  }
  return data;
}

function createMomentIntegrityService({
  db,
  FieldPath,
  Timestamp,
  storage,
  clock = () => Date.now(),
  cleanupPageSize = 100,
  limits = DEFAULT_LIMITS,
}) {
  if (!db || !FieldPath?.documentId || !Timestamp?.fromMillis ||
      !storage?.getMetadata || !storage?.getDownloadUrl) {
    throw new TypeError(
      "db, FieldPath, Timestamp and an injectable storage adapter are required.",
    );
  }
  requireSafeInteger(cleanupPageSize, "cleanupPageSize", { min: 1, max: 200 });

  function time() {
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
    return rateLimitReference(db, `moment.${scope}`, uid);
  }

  function consume(transaction, snapshot, reference, scope, uid, timing) {
    const config = limits[scope];
    if (!config) throw new TypeError(`Missing moment.${scope} rate limit.`);
    consumeRateLimit(transaction, snapshot, {
      reference,
      scope: `moment.${scope}`,
      uid,
      ...timing,
      ...config,
    });
  }

  async function beginStoragePreflight({
    identity,
    kind,
    uid,
    requestId,
    scope,
    timing,
  }) {
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const rateRef = limitReference(scope, uid);
      const [ledger, preflight, rate] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        rateRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      if (preflight.exists) {
        const existing = preflight.data() ?? {};
        if (existing.kind !== kind || existing.ownerId !== uid ||
            existing.inputHash !== identity.inputHash) {
          fail("already-exists", "requestId was reused for another upload.");
        }
        return { replay: null };
      }
      consume(transaction, rate, rateRef, scope, uid, timing);
      transaction.create(preflightRef, {
        schemaVersion: 1,
        kind,
        ownerId: uid,
        requestId,
        inputHash: identity.inputHash,
        createdAt: timing.now,
      });
      return { replay: null };
    });
  }

  async function reserveMomentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["caption", "durationSeconds", "requestId"],
      ["caption", "durationSeconds", "requestId"],
    );
    const requestId = requireRequestId(data.requestId);
    const caption = normalizeText(
      data.caption,
      280,
      "caption",
      { allowEmpty: true },
    ) || "Voice Moment";
    const durationSeconds = requireSafeInteger(
      data.durationSeconds,
      "durationSeconds",
      { min: 1, max: 60 },
    );
    const momentId = canonicalMomentId(auth.uid, requestId);
    const storagePath = momentStoragePath(auth.uid, momentId);
    const input = { caption, durationSeconds };
    const identity = operationIdentity("moment.reserve", auth.uid, requestId, input);
    const timing = time();

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("uploadReserve", auth.uid);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const [ledger, rate, existing, profileSnapshot, publicProfile, restriction] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          momentRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`publicProfiles/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.reserve",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profileSnapshot, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      consume(
        transaction,
        rate,
        rateRef,
        "uploadReserve",
        auth.uid,
        timing,
      );
      if (existing.exists) {
        fail("data-loss", "A Voice Moment exists without its reservation ledger.");
      }
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(momentRef, {
        schemaVersion: 2,
        authorId: auth.uid,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        caption,
        audioUrl: null,
        storagePath,
        durationSeconds,
        likeCount: 0,
        commentCount: 0,
        replyToMomentId: null,
        isPublished: false,
        isDeleted: false,
        status: "uploading",
        mediaGeneration: null,
        mediaSize: null,
        mediaContentType: null,
        createdAt: timing.now,
        updatedAt: timing.now,
        publishedAt: null,
      });
      const result = { momentId, storagePath, created: true };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.reserve",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function finalizeMomentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["momentId", "objectGeneration", "requestId"],
      ["momentId", "objectGeneration", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    if (!/^[a-f0-9]{20}$/u.test(momentId)) {
      fail("invalid-argument", "momentId is not a canonical reservation id.");
    }
    const requestId = requireRequestId(data.requestId);
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const input = { momentId, objectGeneration };
    const identity = operationIdentity("moment.finalize", auth.uid, requestId, input);
    const timing = time();
    const preflight = await beginStoragePreflight({
      identity,
      kind: "moment.finalize",
      uid: auth.uid,
      requestId,
      scope: "finalize",
      timing,
    });
    if (preflight.replay) return preflight.replay;
    const path = momentStoragePath(auth.uid, momentId);
    const metadata = await storage.getMetadata(path);
    const media = validateStoredAudio(
      metadata,
      { authorId: auth.uid, momentId },
      objectGeneration,
    );
    const downloadUrl = await storage.getDownloadUrl(path, metadata);
    if (typeof downloadUrl !== "string" || !downloadUrl ||
        downloadUrl.length > 4096) {
      fail("failed-precondition", "A canonical download URL is unavailable.");
    }

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const [ledger, preflightLedger, moment, profile, restriction] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          preflightRef,
          momentRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightData = preflightLedger.exists
        ? preflightLedger.data() ?? {}
        : {};
      if (preflightData.ownerId !== auth.uid ||
          preflightData.kind !== "moment.finalize" ||
          preflightData.inputHash !== identity.inputHash) {
        fail("failed-precondition", "The upload preflight is not canonical.");
      }
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const momentData = validateMoment(moment, momentId, { published: false });
      if (momentData.authorId !== auth.uid || momentData.status !== "uploading" ||
          momentData.audioUrl !== null || momentData.mediaGeneration !== null) {
        fail("permission-denied", "Only the canonical draft author can publish it.");
      }
      transaction.update(momentRef, {
        audioUrl: downloadUrl,
        isPublished: true,
        status: "published",
        mediaGeneration: media.generation,
        mediaSize: media.size,
        mediaContentType: media.contentType,
        publishedAt: timing.now,
        updatedAt: timing.now,
      });
      const result = { momentId, published: true };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.finalize",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function setMomentLike(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["liked", "momentId", "requestId"],
      ["liked", "momentId", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const liked = requireBoolean(data.liked, "liked");
    const input = { liked, momentId };
    const identity = operationIdentity("moment.like", auth.uid, requestId, input);
    const timing = time();

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("like", auth.uid);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const likeRef = momentRef.collection("likes").doc(auth.uid);
      const [ledger, rate, moment, like] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        momentRef,
        likeRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.like",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const momentData = validateMoment(moment, momentId, { published: true });
      const authorId = momentData.authorId;
      const [actorProfile, authorProfile, actorRestriction, authorRestriction,
        actorBlock, authorBlock] = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${authorId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${authorId}`),
        db.doc(`users/${auth.uid}/blocked/${authorId}`),
        db.doc(`users/${authorId}/blocked/${auth.uid}`),
      );
      activeProfile(actorProfile, "Your");
      activeProfile(authorProfile, "The author");
      assertNotRestricted(actorRestriction, "Your", timing.nowMs);
      assertNotRestricted(authorRestriction, "The author", timing.nowMs);
      assertNotBlocked(actorBlock, authorBlock);
      consume(transaction, rate, rateRef, "like", auth.uid, timing);

      const currentCount = nonNegativeCount(momentData.likeCount, "likeCount");
      const currentlyLiked = like.exists;
      if (currentlyLiked) {
        const likeData = like.data() ?? {};
        const likeKeys = Object.keys(likeData).sort();
        const expectedLikeKeys = [
          "createdAt",
          "momentId",
          "schemaVersion",
          "userId",
        ];
        if (likeKeys.length !== expectedLikeKeys.length ||
            likeKeys.some((key, index) => key !== expectedLikeKeys[index]) ||
            likeData.schemaVersion !== 1 || likeData.userId !== auth.uid ||
            likeData.momentId !== momentId ||
            timestampMillis(likeData.createdAt) === null) {
          fail("data-loss", "The like edge is not canonical.");
        }
      }
      const changed = currentlyLiked !== liked;
      let likeCount = currentCount;
      if (changed && liked) {
        transaction.create(likeRef, {
          schemaVersion: 1,
          userId: auth.uid,
          momentId,
          createdAt: timing.now,
        });
        likeCount = incrementCanonicalCount(likeCount, "likeCount");
      } else if (changed) {
        if (currentCount === 0) {
          fail("data-loss", "likeCount would become negative.");
        }
        transaction.delete(likeRef);
        likeCount -= 1;
      }
      if (changed) {
        transaction.update(momentRef, { likeCount, updatedAt: timing.now });
      }
      const result = { momentId, liked, changed, likeCount };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.like",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function reserveVoiceCommentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["durationSeconds", "momentId", "requestId", "text"],
      ["durationSeconds", "momentId", "requestId", "text"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const durationSeconds = requireSafeInteger(
      data.durationSeconds,
      "durationSeconds",
      { min: 1, max: 60 },
    );
    const text = normalizeText(data.text, 140, "text", { allowEmpty: true });
    const commentId = canonicalCommentId(auth.uid, momentId, requestId);
    const storagePath = voiceReplyStoragePath(auth.uid, momentId, commentId);
    const input = { durationSeconds, momentId, text };
    const identity = operationIdentity(
      "moment.voiceComment.reserve",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("uploadReserve", auth.uid);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const reservationRef = db.doc(`voiceMomentUploadReservations/${commentId}`);
      const [ledger, rate, moment, reservation, actorProfile, publicProfile,
        actorRestriction] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        momentRef,
        reservationRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.voiceComment.reserve",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const momentData = validateMoment(moment, momentId, { published: true });
      const authorId = momentData.authorId;
      const [authorProfile, authorRestriction, actorBlock, authorBlock] =
        await transactionGetAll(
          transaction,
          db.doc(`users/${authorId}`),
          db.doc(`restrictions/${authorId}`),
          db.doc(`users/${auth.uid}/blocked/${authorId}`),
          db.doc(`users/${authorId}/blocked/${auth.uid}`),
        );
      activeProfile(actorProfile, "Your");
      activeProfile(authorProfile, "The author");
      assertNotRestricted(actorRestriction, "Your", timing.nowMs);
      assertNotRestricted(authorRestriction, "The author", timing.nowMs);
      assertNotBlocked(actorBlock, authorBlock);
      consume(
        transaction,
        rate,
        rateRef,
        "uploadReserve",
        auth.uid,
        timing,
      );
      if (reservation.exists) {
        fail("data-loss", "A voice-comment reservation exists without its ledger.");
      }
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(reservationRef, {
        schemaVersion: 1,
        kind: "voiceMomentComment",
        ownerId: auth.uid,
        momentId,
        commentId,
        storagePath,
        durationSeconds,
        text,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        status: "uploading",
        createdAt: timing.now,
        expiresAt: Timestamp.fromMillis(timing.nowMs + 30 * 60_000),
      });
      const result = { momentId, commentId, storagePath, created: true };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.voiceComment.reserve",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function finalizeVoiceCommentDraft(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["commentId", "momentId", "objectGeneration", "requestId"],
      ["commentId", "momentId", "objectGeneration", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const commentId = requireId(data.commentId, "commentId");
    if (!/^[a-f0-9]{20}$/u.test(commentId)) {
      fail("invalid-argument", "commentId is not a canonical reservation id.");
    }
    const requestId = requireRequestId(data.requestId);
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const input = { commentId, momentId, objectGeneration };
    const identity = operationIdentity(
      "moment.voiceComment.finalize",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginStoragePreflight({
      identity,
      kind: "moment.voiceComment.finalize",
      uid: auth.uid,
      requestId,
      scope: "finalize",
      timing,
    });
    if (preflight.replay) return preflight.replay;

    const reservationRef = db.doc(`voiceMomentUploadReservations/${commentId}`);
    const reservationSnapshot = await reservationRef.get();
    const reservation = reservationSnapshot.exists
      ? reservationSnapshot.data() ?? {}
      : {};
    const storagePath = voiceReplyStoragePath(auth.uid, momentId, commentId);
    validateVoiceReservation(reservation, {
      ownerId: auth.uid,
      momentId,
      commentId,
      storagePath,
      nowMs: timing.nowMs,
    });
    const metadata = await storage.getMetadata(storagePath);
    const media = validateStoredAudio(
      metadata,
      { authorId: auth.uid, commentId, momentId },
      objectGeneration,
    );
    const downloadUrl = await storage.getDownloadUrl(storagePath, metadata);
    if (typeof downloadUrl !== "string" || !downloadUrl ||
        downloadUrl.length > 4096) {
      fail("failed-precondition", "A canonical download URL is unavailable.");
    }

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const commentRef = momentRef.collection("comments").doc(commentId);
      const [ledger, preflightLedger, moment, currentReservation, comment,
        actorProfile, publicProfile, actorRestriction] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        momentRef,
        reservationRef,
        commentRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.voiceComment.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightData = preflightLedger.exists
        ? preflightLedger.data() ?? {}
        : {};
      if (preflightData.ownerId !== auth.uid ||
          preflightData.kind !== "moment.voiceComment.finalize" ||
          preflightData.inputHash !== identity.inputHash) {
        fail("failed-precondition", "The upload preflight is not canonical.");
      }
      const momentData = validateMoment(moment, momentId, { published: true });
      const reservationData = currentReservation.exists
        ? currentReservation.data() ?? {}
        : {};
      validateVoiceReservation(reservationData, {
        ownerId: auth.uid,
        momentId,
        commentId,
        storagePath,
        nowMs: timing.nowMs,
      });
      if (comment.exists) {
        fail("data-loss", "A voice comment exists without its finalize ledger.");
      }
      const authorId = momentData.authorId;
      const [authorProfile, authorRestriction, actorBlock, authorBlock] =
        await transactionGetAll(
          transaction,
          db.doc(`users/${authorId}`),
          db.doc(`restrictions/${authorId}`),
          db.doc(`users/${auth.uid}/blocked/${authorId}`),
          db.doc(`users/${authorId}/blocked/${auth.uid}`),
        );
      activeProfile(actorProfile, "Your");
      activeProfile(authorProfile, "The author");
      assertNotRestricted(actorRestriction, "Your", timing.nowMs);
      assertNotRestricted(authorRestriction, "The author", timing.nowMs);
      assertNotBlocked(actorBlock, authorBlock);
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(commentRef, {
        schemaVersion: 2,
        type: "voice",
        authorId: auth.uid,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        text: reservationData.text,
        audioUrl: downloadUrl,
        storagePath,
        durationSeconds: reservationData.durationSeconds,
        mediaGeneration: media.generation,
        mediaSize: media.size,
        mediaContentType: media.contentType,
        createdAt: timing.now,
      });
      const commentCount = incrementCanonicalCount(
        momentData.commentCount,
        "commentCount",
      );
      transaction.update(momentRef, { commentCount, updatedAt: timing.now });
      transaction.delete(reservationRef);
      const result = { momentId, commentId, created: true, commentCount };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.voiceComment.finalize",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function createMomentComment(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["momentId", "requestId", "text"],
      ["momentId", "requestId", "text"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const text = normalizeText(data.text, 1000, "text");
    const commentId = canonicalCommentId(auth.uid, momentId, requestId);
    const input = { momentId, text };
    const identity = operationIdentity("moment.comment", auth.uid, requestId, input);
    const timing = time();

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("comment", auth.uid);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const commentRef = momentRef.collection("comments").doc(commentId);
      const [ledger, rate, moment, existingComment, actorProfile, publicProfile,
        actorRestriction] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        momentRef,
        commentRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`publicProfiles/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.comment",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const momentData = validateMoment(moment, momentId, { published: true });
      const authorId = momentData.authorId;
      const [authorProfile, authorRestriction, actorBlock, authorBlock] =
        await transactionGetAll(
          transaction,
          db.doc(`users/${authorId}`),
          db.doc(`restrictions/${authorId}`),
          db.doc(`users/${auth.uid}/blocked/${authorId}`),
          db.doc(`users/${authorId}/blocked/${auth.uid}`),
        );
      activeProfile(actorProfile, "Your");
      activeProfile(authorProfile, "The author");
      assertNotRestricted(actorRestriction, "Your", timing.nowMs);
      assertNotRestricted(authorRestriction, "The author", timing.nowMs);
      assertNotBlocked(actorBlock, authorBlock);
      consume(transaction, rate, rateRef, "comment", auth.uid, timing);
      if (existingComment.exists) {
        fail("data-loss", "A comment exists without its idempotency ledger.");
      }
      const canonical = canonicalPublicProfile(publicProfile, auth.uid);
      transaction.create(commentRef, {
        schemaVersion: 2,
        type: "text",
        authorId: auth.uid,
        authorName: canonical.displayName,
        authorPhotoUrl: canonical.photoUrl,
        text,
        audioUrl: null,
        storagePath: null,
        durationSeconds: null,
        mediaGeneration: null,
        mediaSize: null,
        mediaContentType: null,
        createdAt: timing.now,
      });
      const commentCount = incrementCanonicalCount(
        momentData.commentCount,
        "commentCount",
      );
      transaction.update(momentRef, { commentCount, updatedAt: timing.now });
      const result = { momentId, commentId, created: true, commentCount };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.comment",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function deleteMomentComment(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["commentId", "momentId", "requestId"],
      ["commentId", "momentId", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const commentId = requireId(data.commentId, "commentId");
    const requestId = requireRequestId(data.requestId);
    const input = { commentId, momentId };
    const identity = operationIdentity(
      "moment.comment.delete",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("delete", auth.uid);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const commentRef = momentRef.collection("comments").doc(commentId);
      const [ledger, rate, moment, comment, profile] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        momentRef,
        commentRef,
        db.doc(`users/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.comment.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      const momentData = validateMoment(moment, momentId);
      const commentData = validateComment(comment, momentId);
      if (commentData.authorId !== auth.uid) {
        fail("permission-denied", "You can only delete your own comment.");
      }
      const currentCount = nonNegativeCount(
        momentData.commentCount,
        "commentCount",
      );
      if (currentCount === 0) fail("data-loss", "commentCount would become negative.");
      consume(transaction, rate, rateRef, "delete", auth.uid, timing);
      transaction.delete(commentRef);
      transaction.update(momentRef, {
        commentCount: currentCount - 1,
        updatedAt: timing.now,
      });
      if (commentData.type === "voice") {
        const outboxId = digest("comment-cleanup", momentId, commentId);
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "voiceMomentComment",
          rootPath: `voiceMoments/${momentId}/comments/${commentId}`,
          objectPaths: [voiceReplyStoragePath(auth.uid, momentId, commentId)],
          status: "pending",
          attemptCount: 0,
          requestedBy: auth.uid,
          createdAt: timing.now,
          updatedAt: timing.now,
        });
      }
      const result = {
        momentId,
        commentId,
        deleted: true,
        commentCount: currentCount - 1,
      };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.comment.delete",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function deleteMoment(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["momentId", "requestId"],
      ["momentId", "requestId"],
    );
    const momentId = requireId(data.momentId, "momentId");
    const requestId = requireRequestId(data.requestId);
    const input = { momentId };
    const identity = operationIdentity("moment.delete", auth.uid, requestId, input);
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("delete", auth.uid);
      const momentRef = db.doc(`voiceMoments/${momentId}`);
      const [ledger, rate, moment, profile] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        momentRef,
        db.doc(`users/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "moment.delete",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      const momentData = validateMoment(moment, momentId);
      if (momentData.authorId !== auth.uid) {
        fail("permission-denied", "You can only delete your own Voice Moment.");
      }
      consume(transaction, rate, rateRef, "delete", auth.uid, timing);
      transaction.update(momentRef, {
        isDeleted: true,
        isPublished: false,
        status: "deleting",
        updatedAt: timing.now,
      });
      const outboxId = digest("moment-cleanup", momentId);
      transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
        schemaVersion: 1,
        kind: "voiceMoment",
        rootPath: `voiceMoments/${momentId}`,
        objectPaths: [momentStoragePath(auth.uid, momentId)],
        status: "pending",
        attemptCount: 0,
        requestedBy: auth.uid,
        createdAt: timing.now,
        updatedAt: timing.now,
      });
      const result = { momentId, outboxId, deletionQueued: true };
      transaction.create(ledgerRef, ledgerData({
        kind: "moment.delete",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function createContentReport(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["commentId", "conversationId", "messageId", "momentId", "reason", "requestId", "targetType"],
      ["reason", "requestId", "targetType"],
    );
    if (!["directMessage", "voiceMoment", "voiceMomentComment"].includes(
      data.targetType,
    )) {
      fail("invalid-argument", "targetType is invalid.");
    }
    const requestId = requireRequestId(data.requestId);
    const reason = normalizeText(data.reason, 500, "reason");
    const target = {
      targetType: data.targetType,
      conversationId: data.conversationId ?? null,
      messageId: data.messageId ?? null,
      momentId: data.momentId ?? null,
      commentId: data.commentId ?? null,
    };
    if (target.targetType === "directMessage") {
      requireId(target.conversationId, "conversationId");
      requireId(target.messageId, "messageId");
      if (target.momentId !== null || target.commentId !== null) {
        fail("invalid-argument", "The report target fields conflict.");
      }
    } else {
      requireId(target.momentId, "momentId");
      if (target.targetType === "voiceMomentComment") {
        requireId(target.commentId, "commentId");
      } else if (target.commentId !== null) {
        fail("invalid-argument", "The report target fields conflict.");
      }
      if (target.conversationId !== null || target.messageId !== null) {
        fail("invalid-argument", "The report target fields conflict.");
      }
    }
    const input = { reason, ...target };
    const identity = operationIdentity("content.report", auth.uid, requestId, input);
    const reportId = digest("content-report", auth.uid, requestId).slice(0, 40);
    const timing = time();

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("report", auth.uid);
      const reportRef = db.doc(`reports/${reportId}`);
      const targetRef = target.targetType === "directMessage"
        ? db.doc(`conversations/${target.conversationId}/messages/${target.messageId}`)
        : target.targetType === "voiceMoment"
          ? db.doc(`voiceMoments/${target.momentId}`)
          : db.doc(`voiceMoments/${target.momentId}/comments/${target.commentId}`);
      const [ledger, rate, existing, profile, targetSnapshot] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          rateRef,
          reportRef,
          db.doc(`users/${auth.uid}`),
          targetRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "content.report",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      if (!targetSnapshot.exists) fail("not-found", "The reported content is missing.");
      if (target.targetType === "directMessage") {
        const conversation = await transaction.get(
          db.doc(`conversations/${target.conversationId}`),
        );
        validateConversationForReport(conversation, auth.uid);
      }
      if (existing.exists) fail("data-loss", "A report exists without its ledger.");
      consume(transaction, rate, rateRef, "report", auth.uid, timing);
      transaction.create(reportRef, {
        schemaVersion: 2,
        reporterId: auth.uid,
        targetType: target.targetType,
        conversationId: target.conversationId,
        messageId: target.messageId,
        momentId: target.momentId,
        commentId: target.commentId,
        reason,
        status: "open",
        createdAt: timing.now,
        updatedAt: timing.now,
      });
      const result = { reportId, created: true };
      transaction.create(ledgerRef, ledgerData({
        kind: "content.report",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  function validateConversationForReport(snapshot, uid) {
    const participants = snapshot.exists ? snapshot.data()?.participantIds : null;
    if (!Array.isArray(participants) || participants.length !== 2 ||
        !participants.includes(uid)) {
      fail("permission-denied", "Only a conversation participant may report it.");
    }
  }

  async function processCleanupOutbox(outboxId) {
    requireId(outboxId, "outboxId");
    const outboxRef = db.doc(`contentCleanupOutbox/${outboxId}`);
    const outbox = await outboxRef.get();
    if (!outbox.exists) return { outboxId, skipped: true };
    const data = outbox.data() ?? {};
    if (!["voiceMoment", "voiceMomentComment", "voiceMomentCommentReservation",
      "directMessageAttachment", "directMessageAttachmentReservation"]
        .includes(data.kind) ||
        !Array.isArray(data.objectPaths) ||
        data.objectPaths.some((path) => typeof path !== "string")) {
      fail("data-loss", "The cleanup outbox entry is malformed.");
    }
    const rootParts = typeof data.rootPath === "string"
      ? data.rootPath.split("/")
      : [];
    if (!isValidOpaqueUid(data.requestedBy)) {
      fail("data-loss", "The cleanup owner is malformed.");
    }
    let expectedObjectPath;
    if (data.kind === "voiceMoment") {
      if (rootParts.length !== 2 || rootParts[0] !== "voiceMoments" ||
          !SAFE_ID.test(rootParts[1])) {
        fail("data-loss", "The Moment cleanup root is malformed.");
      }
      expectedObjectPath = momentStoragePath(data.requestedBy, rootParts[1]);
    } else if (data.kind === "voiceMomentComment") {
      if (rootParts.length !== 4 || rootParts[0] !== "voiceMoments" ||
          rootParts[2] !== "comments" || !SAFE_ID.test(rootParts[1]) ||
          !/^[A-Za-z0-9]{20}$/u.test(rootParts[3])) {
        fail("data-loss", "The comment cleanup root is malformed.");
      }
      expectedObjectPath = voiceReplyStoragePath(
        data.requestedBy,
        rootParts[1],
        rootParts[3],
      );
    } else if (data.kind === "voiceMomentCommentReservation") {
      if (rootParts.length !== 2 ||
          rootParts[0] !== "voiceMomentUploadReservations" ||
          !/^[A-Za-z0-9]{20}$/u.test(rootParts[1])) {
        fail("data-loss", "The reservation cleanup root is malformed.");
      }
      const reservationMomentId = data.objectPaths[0]?.split("/")[2];
      if (!reservationMomentId || !SAFE_ID.test(reservationMomentId)) {
        fail("data-loss", "The reservation cleanup path is malformed.");
      }
      expectedObjectPath = voiceReplyStoragePath(
        data.requestedBy,
        reservationMomentId,
        rootParts[1],
      );
    } else {
      const isReservation = data.kind === "directMessageAttachmentReservation";
      if (isReservation) {
        if (rootParts.length !== 2 ||
            rootParts[0] !== "directMessageUploadReservations" ||
            !/^m_[a-f0-9]{40}$/u.test(rootParts[1])) {
          fail("data-loss", "The direct reservation cleanup root is malformed.");
        }
      } else if (rootParts.length !== 4 || rootParts[0] !== "conversations" ||
          rootParts[2] !== "messages" || !SAFE_ID.test(rootParts[1]) ||
          !/^m_[a-f0-9]{40}$/u.test(rootParts[3])) {
        fail("data-loss", "The direct attachment cleanup root is malformed.");
      }
      const path = data.objectPaths[0];
      const segments = typeof path === "string" ? path.split("/") : [];
      const messageId = isReservation ? rootParts[1] : rootParts[3];
      const conversationId = isReservation ? segments[2] : rootParts[1];
      if (segments.length !== 4 || segments[0] !== "message_attachments" ||
          segments[1] !== data.requestedBy || segments[2] !== conversationId ||
          !SAFE_ID.test(conversationId) ||
          !new RegExp(`^${messageId}[.](jpg|png|webp|m4a)$`, "u")
            .test(segments[3])) {
        fail("data-loss", "The direct attachment cleanup path is malformed.");
      }
      expectedObjectPath = path;
    }
    if (data.objectPaths.length !== 1 ||
        data.objectPaths[0] !== expectedObjectPath) {
      fail("data-loss", "The cleanup object path is not canonical.");
    }
    if (data.status === "completed") return { outboxId, completed: true };
    const timing = time();
    const objectPaths = [...data.objectPaths];
    let commentPage = null;
    let nextCursor = null;
    const quarantined = [];
    if (data.kind === "voiceMoment") {
      const momentId = String(data.rootPath ?? "").split("/")[1] ?? "";
      requireId(momentId, "cleanup momentId");
      let query = db
        .collection(`voiceMoments/${momentId}/comments`)
        .orderBy(FieldPath.documentId())
        .limit(cleanupPageSize);
      if (typeof data.commentCursor === "string" && data.commentCursor) {
        query = query.startAfter(data.commentCursor);
      }
      commentPage = await query.get();
      for (const comment of commentPage.docs) {
        const commentData = comment.data() ?? {};
        if (commentData.type === "voice") {
          if (isValidOpaqueUid(commentData.authorId) &&
              /^[A-Za-z0-9]{20}$/u.test(comment.id)) {
            objectPaths.push(voiceReplyStoragePath(
              commentData.authorId,
              momentId,
              comment.id,
            ));
          } else {
            quarantined.push({
              commentId: comment.id.slice(0, 128),
              reason: "nonCanonicalVoiceReplyIdentity",
            });
          }
        }
      }
      nextCursor = commentPage.docs.at(-1)?.id ?? data.commentCursor ?? null;
    }
    for (const path of [...new Set(objectPaths)]) {
      await storage.deleteObject(path, { ignoreNotFound: true });
    }
    await Promise.all(quarantined.map((entry) =>
      db.doc(`contentCleanupQuarantine/${digest(
        "cleanup-quarantine",
        outboxId,
        entry.commentId,
      )}`).set({
        schemaVersion: 1,
        outboxId,
        rootPath: data.rootPath,
        ...entry,
        createdAt: timing.now,
      })));
    const needsAnotherPage = data.kind === "voiceMoment" &&
      commentPage.size === cleanupPageSize;
    if (!needsAnotherPage && data.kind === "voiceMoment" &&
        typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(db.doc(data.rootPath));
    }
    const attemptCount = incrementCanonicalCount(
      data.attemptCount ?? 0,
      "attemptCount",
    );
    if (needsAnotherPage) {
      const priorProcessed = nonNegativeCount(
        data.processedCommentCount ?? 0,
        "processedCommentCount",
      );
      if (priorProcessed > Number.MAX_SAFE_INTEGER - commentPage.size) {
        fail("data-loss", "processedCommentCount cannot be incremented safely.");
      }
      await outboxRef.update({
        status: "pending",
        commentCursor: nextCursor,
        processedCommentCount: priorProcessed + commentPage.size,
        attemptCount,
        updatedAt: timing.now,
      });
      return { outboxId, completed: false, nextCursor, quarantined };
    }
    await outboxRef.update({
      status: "completed",
      attemptCount,
      updatedAt: timing.now,
      completedAt: timing.now,
    });
    return { outboxId, completed: true, quarantined };
  }

  async function expireAbandonedMomentDrafts({
    olderThanMs = 24 * 60 * 60_000,
    limit = 100,
    cursor = null,
  } = {}) {
    requireSafeInteger(olderThanMs, "olderThanMs", { min: 60_000 });
    requireSafeInteger(limit, "limit", { min: 1, max: 200 });
    if (cursor !== null && (!isPlainObject(cursor) ||
        !Number.isSafeInteger(cursor.createdAtMs) || cursor.createdAtMs < 0 ||
        typeof cursor.id !== "string")) {
      fail("invalid-argument", "cursor is invalid.");
    }
    if (cursor !== null) requireId(cursor.id, "cursor.id");
    const timing = time();
    const cutoffMs = timing.nowMs - olderThanMs;
    let query = db
      .collection("voiceMoments")
      .where("status", "==", "uploading")
      .where("createdAt", "<=", Timestamp.fromMillis(cutoffMs))
      .orderBy("createdAt")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor) {
      query = query.startAfter(
        Timestamp.fromMillis(cursor.createdAtMs),
        cursor.id,
      );
    }
    const snapshot = await query.get();
    const expired = [];
    const malformed = [];
    for (const document of snapshot.docs) {
      const createdAtMs = timestampMillis(document.data()?.createdAt);
      if (createdAtMs === null) {
        malformed.push(document.id);
        continue;
      }
      const changed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return false;
        const currentData = current.data() ?? {};
        const currentCreatedAt = timestampMillis(currentData.createdAt);
        if (currentData.status !== "uploading" ||
            currentData.isPublished !== false || currentData.isDeleted === true ||
            currentCreatedAt === null || currentCreatedAt > cutoffMs ||
            typeof currentData.authorId !== "string" ||
            currentData.storagePath !== momentStoragePath(
              currentData.authorId,
              current.id,
            )) {
          return false;
        }
        transaction.update(current.ref, {
          isDeleted: true,
          status: "deleting",
          updatedAt: timing.now,
        });
        const outboxId = digest("moment-cleanup", current.id);
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "voiceMoment",
          rootPath: current.ref.path,
          objectPaths: [currentData.storagePath],
          status: "pending",
          attemptCount: 0,
          requestedBy: currentData.authorId,
          requestedReason: "abandonedUpload",
          createdAt: timing.now,
          updatedAt: timing.now,
        });
        return true;
      });
      if (changed) expired.push(document.id);
    }
    return {
      expired,
      malformed,
      nextCursor: snapshot.docs.length === 0
        ? null
        : {
            createdAtMs: timestampMillis(snapshot.docs.at(-1).data().createdAt),
            id: snapshot.docs.at(-1).id,
          },
      hasMore: snapshot.size === limit,
    };
  }

  async function expireAbandonedVoiceCommentDrafts({
    limit = 100,
    cursor = null,
  } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 200 });
    if (cursor !== null && (!isPlainObject(cursor) ||
        !Number.isSafeInteger(cursor.expiresAtMs) || cursor.expiresAtMs < 0 ||
        typeof cursor.id !== "string")) {
      fail("invalid-argument", "cursor is invalid.");
    }
    if (cursor !== null) requireId(cursor.id, "cursor.id");
    const timing = time();
    let query = db
      .collection("voiceMomentUploadReservations")
      .where("status", "==", "uploading")
      .where("expiresAt", "<=", timing.now)
      .orderBy("expiresAt")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor) {
      query = query.startAfter(
        Timestamp.fromMillis(cursor.expiresAtMs),
        cursor.id,
      );
    }
    const snapshot = await query.get();
    const expired = [];
    const malformed = [];
    for (const document of snapshot.docs) {
      const changed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return false;
        const reservation = current.data() ?? {};
        const expiresAtMs = timestampMillis(reservation.expiresAt);
        if (reservation.status !== "uploading" || expiresAtMs === null ||
            expiresAtMs > timing.nowMs) {
          return false;
        }
        const quarantine = () => {
          transaction.set(db.doc(`contentCleanupQuarantine/${digest(
            "expired-reservation-quarantine",
            current.id,
          )}`), {
            schemaVersion: 1,
            rootPath: current.ref.path,
            reason: "nonCanonicalExpiredVoiceCommentReservation",
            createdAt: timing.now,
          });
          transaction.delete(current.ref);
          return "malformed";
        };
        if (!isValidOpaqueUid(reservation.ownerId) ||
            typeof reservation.momentId !== "string" ||
            !SAFE_ID.test(reservation.momentId) ||
            !/^[A-Za-z0-9]{20}$/u.test(current.id)) {
          return quarantine();
        }
        const canonicalPath = voiceReplyStoragePath(
          reservation.ownerId,
          reservation.momentId,
          current.id,
        );
        if (reservation.commentId !== current.id ||
            reservation.storagePath !== canonicalPath) {
          return quarantine();
        }
        transaction.delete(current.ref);
        const outboxId = digest("voice-comment-reservation-cleanup", current.id);
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "voiceMomentCommentReservation",
          rootPath: current.ref.path,
          objectPaths: [canonicalPath],
          status: "pending",
          attemptCount: 0,
          requestedBy: reservation.ownerId,
          requestedReason: "expiredUploadReservation",
          createdAt: timing.now,
          updatedAt: timing.now,
        });
        return true;
      });
      if (changed === true) expired.push(document.id);
      else if (changed === "malformed") malformed.push(document.id);
    }
    return {
      expired,
      malformed,
      nextCursor: snapshot.docs.length === 0
        ? null
        : {
            expiresAtMs: timestampMillis(snapshot.docs.at(-1).data().expiresAt),
            id: snapshot.docs.at(-1).id,
          },
      hasMore: snapshot.size === limit,
    };
  }

  return {
    createContentReport,
    createMomentComment,
    deleteMoment,
    deleteMomentComment,
    expireAbandonedMomentDrafts,
    expireAbandonedVoiceCommentDrafts,
    finalizeVoiceCommentDraft,
    finalizeMomentDraft,
    processCleanupOutbox,
    reserveMomentDraft,
    reserveVoiceCommentDraft,
    setMomentLike,
  };
}

function createBucketStorageAdapter(bucket) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  return {
    getObjectReference(path) {
      if (typeof bucket.name !== "string" || !bucket.name) {
        fail("failed-precondition", "The Storage bucket name is unavailable.");
      }
      return `gs://${bucket.name}/${path}`;
    },
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },
    async getDownloadUrl(path, metadata) {
      const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
      if (!token || typeof bucket.name !== "string") {
        fail("failed-precondition", "The object has no canonical download token.");
      }
      return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(
        bucket.name,
      )}/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`;
    },
    async deleteObject(path, { ignoreNotFound = false } = {}) {
      await bucket.file(path).delete({ ignoreNotFound });
    },
  };
}

module.exports = {
  DEFAULT_LIMITS,
  canonicalCommentId,
  canonicalMomentId,
  createBucketStorageAdapter,
  createMomentIntegrityService,
  momentStoragePath,
  validateComment,
  validateMoment,
  validateStoredAudio,
  voiceReplyStoragePath,
};

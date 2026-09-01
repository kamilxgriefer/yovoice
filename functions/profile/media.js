const {
  assertLedgerReplay,
  assertNotBlocked,
  consumeRateLimit,
  fail,
  isValidOpaqueUid,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  transactionGetAll,
} = require("../integrity/guards");
const {
  PROFILE_MEDIA_ACCESS_TTL_MS,
  PROFILE_MEDIA_NEGATIVE_TTL_MS,
  PROFILE_MEDIA_SCHEMA_VERSION,
  PROFILE_MEDIA_UPLOAD_TTL_MS,
  activeProfileData,
  canonicalProfileMediaDocument,
  customMetadataOf,
  exactFriendshipGuard,
  hasExactKeys,
  parseProfileMediaStoragePath,
  profileMediaStoragePath,
  profileVisibilityOf,
  requireProfileMediaContentType,
  requireProfileMediaKind,
  requireProfileMediaSize,
  requireProfileMediaUploadId,
  validateStoredProfileMedia,
} = require("./media_contract");

const PROFILE_MEDIA_ACCESS_LIMIT = Object.freeze({
  maxEvents: 180,
  windowMs: 60_000,
});
const PROFILE_MEDIA_RESERVE_LIMIT = Object.freeze({
  maxEvents: 12,
  windowMs: 60_000,
});
const PROFILE_MEDIA_FINALIZE_LIMIT = Object.freeze({
  maxEvents: 20,
  windowMs: 60_000,
});
const PROFILE_MEDIA_DAILY_BYTE_LIMIT = 20 * 1024 * 1024;

function reservationReference(db, uid, uploadId) {
  return db.doc(`profileMediaUploadReservations/${uid}/uploads/${uploadId}`);
}

function finalizationReference(db, uid, uploadId) {
  return db.doc(`profileMediaFinalizations/${uid}/uploads/${uploadId}`);
}

function leaseReference(db, uid, kind) {
  return db.doc(`profileMediaUploadLeases/${uid}::${kind}`);
}

function budgetReference(db, uid, nowMs) {
  const day = new Date(nowMs).toISOString().slice(0, 10);
  return {
    day,
    reference: db.doc(`profileMediaUploadBudgets/${uid}/days/${day}`),
  };
}

function canonicalLease(snapshot, { ownerId, kind }) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  if (!hasExactKeys(data, [
    "createdAt",
    "expiresAt",
    "kind",
    "ownerId",
    "reservationPath",
    "schemaVersion",
    "storagePath",
    "uploadId",
  ]) ||
      data.schemaVersion !== 1 ||
      data.ownerId !== ownerId ||
      data.kind !== kind ||
      typeof data.createdAt?.toMillis !== "function" ||
      typeof data.expiresAt?.toMillis !== "function" ||
      data.reservationPath !==
        `profileMediaUploadReservations/${ownerId}/uploads/${data.uploadId}` ||
      parseProfileMediaStoragePath(data.storagePath)?.ownerId !== ownerId ||
      parseProfileMediaStoragePath(data.storagePath)?.kind !== kind ||
      parseProfileMediaStoragePath(data.storagePath)?.uploadId !==
        requireProfileMediaUploadId(data.uploadId)) {
    fail("data-loss", "The profile upload lease is malformed.");
  }
  return data;
}

function consumeDailyByteBudget(transaction, snapshot, {
  reference,
  ownerId,
  day,
  size,
  now,
}) {
  const data = snapshot?.exists ? snapshot.data() ?? {} : {};
  const previous = snapshot?.exists ? data.bytesReserved : 0;
  if (snapshot?.exists &&
      (!hasExactKeys(data, [
        "bytesReserved",
        "day",
        "ownerId",
        "schemaVersion",
        "updatedAt",
      ]) ||
        data.schemaVersion !== 1 ||
        data.ownerId !== ownerId ||
        data.day !== day ||
        !Number.isSafeInteger(previous) ||
        previous < 0 ||
        typeof data.updatedAt?.toMillis !== "function")) {
    fail("data-loss", "The profile upload byte budget is malformed.");
  }
  if (previous + size > PROFILE_MEDIA_DAILY_BYTE_LIMIT) {
    fail("resource-exhausted", "The daily profile image limit was reached.");
  }
  transaction.set(reference, {
    schemaVersion: 1,
    ownerId,
    day,
    bytesReserved: previous + size,
    updatedAt: now,
  });
}

function canonicalReservation(snapshot, { ownerId, uploadId, nowMs }) {
  if (!snapshot?.exists) {
    fail("failed-precondition", "The profile image upload expired.");
  }
  const data = snapshot.data() ?? {};
  if (!hasExactKeys(data, [
    "baseRevision",
    "contentType",
    "createdAt",
    "expiresAt",
    "kind",
    "ownerId",
    "schemaVersion",
    "size",
    "status",
    "storagePath",
    "uploadId",
  ]) ||
      data.schemaVersion !== 1 ||
      data.ownerId !== ownerId ||
      data.uploadId !== uploadId ||
      data.status !== "uploading" ||
      !Number.isSafeInteger(data.baseRevision) ||
      data.baseRevision < 0 ||
      typeof data.createdAt?.toMillis !== "function" ||
      typeof data.expiresAt?.toMillis !== "function" ||
      data.createdAt.toMillis() > nowMs ||
      data.expiresAt.toMillis() <= nowMs) {
    fail("failed-precondition", "The profile image upload is invalid.");
  }
  const kind = requireProfileMediaKind(data.kind);
  const contentType = requireProfileMediaContentType(data.contentType);
  const size = requireProfileMediaSize(data.size);
  const canonicalPath = profileMediaStoragePath(
    ownerId,
    kind,
    uploadId,
    contentType,
  );
  if (data.storagePath !== canonicalPath) {
    fail("data-loss", "The profile image reservation path is invalid.");
  }
  return { ...data, kind, contentType, size };
}

function canonicalFinalization(snapshot, {
  ownerId,
  uploadId,
  requestedGeneration,
}) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  if (!hasExactKeys(data, [
    "finalizedAt",
    "kind",
    "ownerId",
    "result",
    "schemaVersion",
    "uploadId",
  ]) ||
      data.schemaVersion !== 1 ||
      data.ownerId !== ownerId ||
      data.uploadId !== uploadId ||
      typeof data.finalizedAt?.toMillis !== "function" ||
      !hasExactKeys(data.result, [
        "contentType",
        "generation",
        "kind",
        "schemaVersion",
        "size",
        "userId",
      ]) ||
      data.result.schemaVersion !== PROFILE_MEDIA_SCHEMA_VERSION ||
      data.result.userId !== ownerId ||
      data.result.kind !== data.kind ||
      data.result.generation !== requestedGeneration) {
    fail("already-exists", "uploadId was already finalized differently.");
  }
  return data.result;
}

function createProfileMediaService({
  db,
  Timestamp,
  storage,
  clock = () => Date.now(),
}) {
  if (!db || !Timestamp?.fromMillis ||
      !storage?.getMetadata ||
      !storage?.getSignedReadUrl ||
      !storage?.hardenManagedImageMetadata ||
      !storage?.deleteObject) {
    throw new TypeError("db, Timestamp and profile-media storage are required.");
  }

  function time() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  function operationReferences(identity) {
    return {
      ledger: db.doc(`integrityOperationLedgers/${identity.id}`),
      preflight: db.doc(`integrityPreflightLedgers/${identity.id}`),
    };
  }

  function assertCanonicalPreflight(snapshot, {
    identity,
    kind,
    ownerId,
    requestId,
  }) {
    if (!canonicalPreflightMatches(snapshot, {
      identity,
      kind,
      ownerId,
      requestId,
    })) {
      fail("failed-precondition", "The media-operation preflight is invalid.");
    }
    return snapshot.data() ?? {};
  }

  function canonicalPreflightMatches(snapshot, {
    identity,
    kind,
    ownerId,
    requestId,
  }) {
    if (!snapshot?.exists) return false;
    const data = snapshot.data() ?? {};
    return data.schemaVersion === 1 &&
      data.kind === kind &&
      data.ownerId === ownerId &&
      data.requestId === requestId &&
      data.inputHash === identity.inputHash &&
      typeof data.createdAt?.toMillis === "function";
  }

  function operationLedgerState(snapshot, { identity, kind, ownerId }) {
    if (!snapshot?.exists) return { replay: null, conflict: null };
    const data = snapshot.data() ?? {};
    if (
      data.kind !== kind ||
      data.ownerId !== ownerId ||
      data.inputHash !== identity.inputHash ||
      !data.result ||
      typeof data.result !== "object"
    ) {
      return {
        replay: null,
        conflict: {
          code: "already-exists",
          message: "requestId was already used for another operation.",
        },
      };
    }
    return { replay: data.result, conflict: null };
  }

  // This transaction is deliberately actor-wide and commits before any
  // caller-selected profile, reservation or Storage object is read. Failed
  // target checks therefore still consume a bounded unit of work. Only a
  // fully committed operation-ledger replay is free; an unfinished retry
  // consumes again so one bad upload id cannot become a free read oracle.
  async function beginOperationAttempt({
    identity,
    kind,
    ownerId,
    requestId,
    scope,
    limit,
    timing,
    replayExpires = false,
    freeReplay = true,
  }) {
    const refs = operationReferences(identity);
    const rateRef = rateLimitReference(db, scope, ownerId);
    const outcome = await db.runTransaction(async (transaction) => {
      const [ledger, preflight, rate] = await transactionGetAll(
        transaction,
        refs.ledger,
        refs.preflight,
        rateRef,
      );
      const ledgerState = operationLedgerState(ledger, {
        identity,
        kind,
        ownerId,
      });
      let replay = ledgerState.replay;
      let conflict = ledgerState.conflict;
      if (replay && replayExpires) {
        if (!Number.isSafeInteger(replay.expiresAtMillis)) {
          conflict = {
            code: "data-loss",
            message: "The media-operation replay is malformed.",
          };
          replay = null;
        }
        if (replay && replay.expiresAtMillis <= timing.nowMs) {
          transaction.delete(refs.ledger);
          replay = null;
        }
      }
      if (replay && freeReplay) return { replay, refs };
      if (preflight.exists) {
        if (!canonicalPreflightMatches(preflight, {
          identity,
          kind,
          ownerId,
          requestId,
        })) {
          conflict ??= {
            code: "already-exists",
            message: "requestId was already used for another operation.",
          };
        }
      } else if (conflict === null) {
        transaction.create(refs.preflight, {
          schemaVersion: 1,
          kind,
          ownerId,
          requestId,
          inputHash: identity.inputHash,
          createdAt: timing.now,
        });
      }
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope,
        uid: ownerId,
        nowMs: timing.nowMs,
        now: timing.now,
        ...limit,
      });
      return { replay: null, refs, conflict };
    });
    if (outcome.conflict !== null && outcome.conflict !== undefined) {
      fail(outcome.conflict.code, outcome.conflict.message);
    }
    return outcome;
  }

  async function consumeCommittedAccessAttempt(ownerId, timing) {
    const scope = "profileMedia.access";
    const rateRef = rateLimitReference(db, scope, ownerId);
    await db.runTransaction(async (transaction) => {
      const rate = await transaction.get(rateRef);
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope,
        uid: ownerId,
        nowMs: timing.nowMs,
        now: timing.now,
        ...PROFILE_MEDIA_ACCESS_LIMIT,
      });
    });
  }

  async function authorizeMediaAccess({
    auth,
    userId,
    kind,
  }) {
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const mediaRef = db.doc(`profileMedia/${userId}`);
      if (auth.uid === userId) {
        const [profile, media] = await transactionGetAll(
          transaction,
          db.doc(`users/${auth.uid}`),
          mediaRef,
        );
        activeProfileData(profile, "Your");
        const canonical = canonicalProfileMediaDocument(media, userId);
        return {
          checkedAtMs: timing.nowMs,
          kind,
          media: canonical[kind],
          revision: canonical.revision,
          userId,
          visibility: "self",
        };
      }

      const references = [
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${userId}`),
        mediaRef,
        db.doc(`users/${auth.uid}/blocked/${userId}`),
        db.doc(`users/${userId}/blocked/${auth.uid}`),
        db.doc(`friendshipGuards/${auth.uid}/friends/${userId}`),
        db.doc(`friendshipGuards/${userId}/friends/${auth.uid}`),
      ];
      const [
        caller,
        target,
        media,
        callerBlock,
        targetBlock,
        forwardGuard,
        reverseGuard,
      ] = await transactionGetAll(transaction, ...references);
      activeProfileData(caller, "Your");
      const targetData = activeProfileData(target, "The selected");
      assertNotBlocked(callerBlock, targetBlock);
      const visibility = profileVisibilityOf(targetData);
      const admitted = visibility === "public" ||
        (visibility === "friends" &&
          exactFriendshipGuard(forwardGuard, auth.uid, userId) &&
          exactFriendshipGuard(reverseGuard, userId, auth.uid));
      if (!admitted) {
        fail("permission-denied", "This profile image is not available.");
      }
      const canonical = canonicalProfileMediaDocument(media, userId);
      return {
        checkedAtMs: timing.nowMs,
        kind,
        media: canonical[kind],
        revision: canonical.revision,
        userId,
        visibility,
      };
    });
  }

  function sameAccessState(first, second) {
    return first.userId === second.userId &&
      first.kind === second.kind &&
      first.revision === second.revision &&
      first.visibility === second.visibility &&
      first.media?.storagePath === second.media?.storagePath &&
      first.media?.generation === second.media?.generation &&
      first.media?.contentType === second.media?.contentType &&
      first.media?.size === second.media?.size;
  }

  async function getProfileMediaAccess(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["kind", "userId"],
      ["kind", "userId"],
    );
    const kind = requireProfileMediaKind(data.kind);
    if (!isValidOpaqueUid(data.userId)) {
      fail("invalid-argument", "userId is invalid.");
    }
    const timing = time();
    await consumeCommittedAccessAttempt(auth.uid, timing);
    const access = await authorizeMediaAccess({
      auth,
      userId: data.userId,
      kind,
    });
    if (access.media === null) {
      return {
        schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
        available: false,
        expiresAtMillis:
          access.checkedAtMs + PROFILE_MEDIA_NEGATIVE_TTL_MS,
      };
    }

    const metadata = await storage.getMetadata(access.media.storagePath);
    const stored = validateStoredProfileMedia(metadata, {
      ownerId: data.userId,
      kind,
      storagePath: access.media.storagePath,
      requestedGeneration: access.media.generation,
    });
    if (stored.contentType !== access.media.contentType ||
        stored.size !== access.media.size) {
      fail("data-loss", "The profile image no longer matches its record.");
    }
    const custom = customMetadataOf(metadata);
    if (typeof custom.firebaseStorageDownloadTokens === "string" &&
        custom.firebaseStorageDownloadTokens.length > 0) {
      await storage.hardenManagedImageMetadata(
        stored.storagePath,
        metadata,
        {
          ownerId: data.userId,
          profileKind: kind,
          uploadId: stored.uploadId,
        },
      );
    }

    const expiresAtMs = access.checkedAtMs + PROFILE_MEDIA_ACCESS_TTL_MS;
    const url = await storage.getSignedReadUrl(stored.storagePath, {
      expiresAtMs,
      generation: stored.generation,
    });
    if (typeof url !== "string" || !url || url.length > 4096) {
      fail("failed-precondition", "A profile-media grant is unavailable.");
    }
    const finalAccess = await authorizeMediaAccess({
      auth,
      userId: data.userId,
      kind,
    });
    if (finalAccess.checkedAtMs >= expiresAtMs ||
        !sameAccessState(access, finalAccess)) {
      fail("aborted", "Profile-media authorization changed. Try again.");
    }
    return {
      schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
      available: true,
      url,
      expiresAtMillis: expiresAtMs,
      generation: stored.generation,
      contentType: stored.contentType,
      size: stored.size,
    };
  }

  async function reserveProfileMediaUpload(request) {
    const auth = requireActor(request, { verified: true });
    const data = requireExactInput(
      request.data,
      ["contentType", "kind", "size", "uploadId"],
      ["contentType", "kind", "size", "uploadId"],
    );
    const kind = requireProfileMediaKind(data.kind);
    const contentType = requireProfileMediaContentType(data.contentType);
    const size = requireProfileMediaSize(data.size);
    const uploadId = requireProfileMediaUploadId(data.uploadId);
    const storagePath = profileMediaStoragePath(
      auth.uid,
      kind,
      uploadId,
      contentType,
    );
    const timing = time();
    const reserveIdentity = operationIdentity(
      "profileMedia.reserve",
      auth.uid,
      uploadId,
      { contentType, kind, size },
    );
    const preflight = await beginOperationAttempt({
      identity: reserveIdentity,
      kind: "profileMedia.reserve",
      ownerId: auth.uid,
      requestId: uploadId,
      scope: "profileMedia.reserve",
      limit: PROFILE_MEDIA_RESERVE_LIMIT,
      timing,
      replayExpires: true,
      freeReplay: false,
    });
    if (preflight.replay) return preflight.replay;
    const reservationRef = reservationReference(db, auth.uid, uploadId);
    const finalizedRef = finalizationReference(db, auth.uid, uploadId);
    const mediaRef = db.doc(`profileMedia/${auth.uid}`);
    const leaseRef = leaseReference(db, auth.uid, kind);
    const budget = budgetReference(db, auth.uid, timing.nowMs);

    const outcome = await db.runTransaction(async (transaction) => {
      const [ledger, admitted, profile, media, reservation, finalized,
        lease, bytes] =
        await transactionGetAll(
          transaction,
          preflight.refs.ledger,
          preflight.refs.preflight,
          db.doc(`users/${auth.uid}`),
          mediaRef,
          reservationRef,
          finalizedRef,
          leaseRef,
          budget.reference,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "profileMedia.reserve",
        uid: auth.uid,
        inputHash: reserveIdentity.inputHash,
      });
      assertCanonicalPreflight(admitted, {
        identity: reserveIdentity,
        kind: "profileMedia.reserve",
        ownerId: auth.uid,
        requestId: uploadId,
      });
      activeProfileData(profile, "Your");
      if (replay) return { response: replay, expiredStoragePath: null };
      const currentLease = canonicalLease(lease, {
        ownerId: auth.uid,
        kind,
      });
      if (finalized.exists) {
        fail("already-exists", "uploadId was already finalized.");
      }
      if (reservation.exists) {
        const existing = canonicalReservation(reservation, {
          ownerId: auth.uid,
          uploadId,
          nowMs: timing.nowMs,
        });
        if (existing.kind !== kind ||
            existing.contentType !== contentType ||
            existing.size !== size ||
            existing.storagePath !== storagePath) {
          fail("already-exists", "uploadId was reused for another image.");
        }
        if (currentLease === null ||
            currentLease.uploadId !== uploadId ||
            currentLease.expiresAt.toMillis() <= timing.nowMs) {
          fail("failed-precondition", "The profile upload lease expired.");
        }
        const response = {
          schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
          uploadId,
          storagePath,
          expiresAtMillis: existing.expiresAt.toMillis(),
        };
        transaction.create(preflight.refs.ledger, ledgerData({
          kind: "profileMedia.reserve",
          uid: auth.uid,
          requestId: uploadId,
          inputHash: reserveIdentity.inputHash,
          result: response,
          now: timing.now,
        }));
        transaction.delete(preflight.refs.preflight);
        return {
          response,
          expiredStoragePath: null,
        };
      }
      if (currentLease !== null &&
          currentLease.expiresAt.toMillis() > timing.nowMs) {
        fail(
          "already-exists",
          `An active ${kind} upload is already in progress.`,
        );
      }
      const canonical = canonicalProfileMediaDocument(media, auth.uid);
      consumeDailyByteBudget(transaction, bytes, {
        reference: budget.reference,
        ownerId: auth.uid,
        day: budget.day,
        size,
        now: timing.now,
      });
      const expiresAt = Timestamp.fromMillis(
        timing.nowMs + PROFILE_MEDIA_UPLOAD_TTL_MS,
      );
      if (currentLease !== null) {
        transaction.delete(db.doc(currentLease.reservationPath));
      }
      transaction.create(reservationRef, {
        schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
        ownerId: auth.uid,
        uploadId,
        kind,
        contentType,
        size,
        storagePath,
        baseRevision: canonical.revision,
        status: "uploading",
        createdAt: timing.now,
        expiresAt,
      });
      transaction.set(leaseRef, {
        schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
        ownerId: auth.uid,
        kind,
        uploadId,
        storagePath,
        reservationPath: reservationRef.path,
        createdAt: timing.now,
        expiresAt,
      });
      const response = {
        schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
        uploadId,
        storagePath,
        expiresAtMillis: expiresAt.toMillis(),
      };
      transaction.create(preflight.refs.ledger, ledgerData({
        kind: "profileMedia.reserve",
        uid: auth.uid,
        requestId: uploadId,
        inputHash: reserveIdentity.inputHash,
        result: response,
        now: timing.now,
      }));
      transaction.delete(preflight.refs.preflight);
      return {
        response,
        expiredStoragePath: currentLease?.storagePath ?? null,
      };
    });
    if (outcome.expiredStoragePath !== null) {
      await storage.deleteObject(outcome.expiredStoragePath, {
        ignoreNotFound: true,
      }).catch(() => {});
    }
    return outcome.response;
  }

  async function finalizeProfileMediaUpload(request) {
    const auth = requireActor(request, { verified: true });
    const data = requireExactInput(
      request.data,
      ["objectGeneration", "uploadId"],
      ["objectGeneration", "uploadId"],
    );
    const uploadId = requireProfileMediaUploadId(data.uploadId);
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const reservationRef = reservationReference(db, auth.uid, uploadId);
    const finalizedRef = finalizationReference(db, auth.uid, uploadId);
    const mediaRef = db.doc(`profileMedia/${auth.uid}`);
    const timing = time();
    const finalizeIdentity = operationIdentity(
      "profileMedia.finalize",
      auth.uid,
      uploadId,
      { objectGeneration },
    );
    const preflight = await beginOperationAttempt({
      identity: finalizeIdentity,
      kind: "profileMedia.finalize",
      ownerId: auth.uid,
      requestId: uploadId,
      scope: "profileMedia.finalize",
      limit: PROFILE_MEDIA_FINALIZE_LIMIT,
      timing,
    });
    if (preflight.replay) return preflight.replay;
    const reserveRefs = operationReferences(operationIdentity(
      "profileMedia.reserve",
      auth.uid,
      uploadId,
      {},
    ));

    const initial = await db.runTransaction(async (transaction) => {
      const [ledger, admitted, profile, reservation, finalized, media] =
        await transactionGetAll(
          transaction,
          preflight.refs.ledger,
          preflight.refs.preflight,
          db.doc(`users/${auth.uid}`),
          reservationRef,
          finalizedRef,
          mediaRef,
        );
      const operationReplay = assertLedgerReplay(ledger, {
        kind: "profileMedia.finalize",
        uid: auth.uid,
        inputHash: finalizeIdentity.inputHash,
      });
      if (operationReplay) return { replay: operationReplay };
      assertCanonicalPreflight(admitted, {
        identity: finalizeIdentity,
        kind: "profileMedia.finalize",
        ownerId: auth.uid,
        requestId: uploadId,
      });
      activeProfileData(profile, "Your");
      const replay = canonicalFinalization(finalized, {
        ownerId: auth.uid,
        uploadId,
        requestedGeneration: objectGeneration,
      });
      if (replay !== null) {
        transaction.create(preflight.refs.ledger, ledgerData({
          kind: "profileMedia.finalize",
          uid: auth.uid,
          requestId: uploadId,
          inputHash: finalizeIdentity.inputHash,
          result: replay,
          now: timing.now,
        }));
        transaction.delete(preflight.refs.preflight);
        transaction.delete(reserveRefs.ledger);
        transaction.delete(reserveRefs.preflight);
        return { replay };
      }
      const reserved = canonicalReservation(reservation, {
        ownerId: auth.uid,
        uploadId,
        nowMs: timing.nowMs,
      });
      const leaseRef = leaseReference(db, auth.uid, reserved.kind);
      const lease = await transaction.get(leaseRef);
      const currentLease = canonicalLease(lease, {
        ownerId: auth.uid,
        kind: reserved.kind,
      });
      if (currentLease === null ||
          currentLease.uploadId !== uploadId ||
          currentLease.storagePath !== reserved.storagePath ||
          currentLease.expiresAt.toMillis() <= timing.nowMs) {
        fail("failed-precondition", "The profile upload lease expired.");
      }
      const canonical = canonicalProfileMediaDocument(media, auth.uid);
      if (canonical.revision !== reserved.baseRevision) {
        fail("aborted", "Your profile image changed. Upload it again.");
      }
      return { replay: null, reserved, leaseRef };
    });
    if (initial.replay !== null) return initial.replay;

    const metadata = await storage.getMetadata(initial.reserved.storagePath);
    const stored = validateStoredProfileMedia(metadata, {
      ownerId: auth.uid,
      kind: initial.reserved.kind,
      storagePath: initial.reserved.storagePath,
      requestedGeneration: objectGeneration,
    });
    if (stored.contentType !== initial.reserved.contentType ||
        stored.size !== initial.reserved.size) {
      fail("failed-precondition", "The upload does not match its reservation.");
    }
    await storage.hardenManagedImageMetadata(stored.storagePath, metadata, {
      ownerId: auth.uid,
      profileKind: initial.reserved.kind,
      uploadId,
    });

    const result = {
      schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
      userId: auth.uid,
      kind: initial.reserved.kind,
      generation: stored.generation,
      contentType: stored.contentType,
      size: stored.size,
    };
    const committed = await db.runTransaction(async (transaction) => {
      const userRef = db.doc(`users/${auth.uid}`);
      const publicRef = db.doc(`publicProfiles/${auth.uid}`);
      const [ledger, admitted, profile, reservation, finalized, media,
        publicProfile, lease] =
        await transactionGetAll(
          transaction,
          preflight.refs.ledger,
          preflight.refs.preflight,
          userRef,
          reservationRef,
          finalizedRef,
          mediaRef,
          publicRef,
          initial.leaseRef,
        );
      const operationReplay = assertLedgerReplay(ledger, {
        kind: "profileMedia.finalize",
        uid: auth.uid,
        inputHash: finalizeIdentity.inputHash,
      });
      if (operationReplay) return operationReplay;
      assertCanonicalPreflight(admitted, {
        identity: finalizeIdentity,
        kind: "profileMedia.finalize",
        ownerId: auth.uid,
        requestId: uploadId,
      });
      activeProfileData(profile, "Your");
      const replay = canonicalFinalization(finalized, {
        ownerId: auth.uid,
        uploadId,
        requestedGeneration: objectGeneration,
      });
      if (replay !== null) {
        transaction.create(preflight.refs.ledger, ledgerData({
          kind: "profileMedia.finalize",
          uid: auth.uid,
          requestId: uploadId,
          inputHash: finalizeIdentity.inputHash,
          result: replay,
          now: timing.now,
        }));
        transaction.delete(preflight.refs.preflight);
        transaction.delete(reserveRefs.ledger);
        transaction.delete(reserveRefs.preflight);
        return replay;
      }
      const reserved = canonicalReservation(reservation, {
        ownerId: auth.uid,
        uploadId,
        nowMs: time().nowMs,
      });
      const currentLease = canonicalLease(lease, {
        ownerId: auth.uid,
        kind: reserved.kind,
      });
      if (reserved.kind !== initial.reserved.kind ||
          reserved.storagePath !== initial.reserved.storagePath ||
          reserved.contentType !== initial.reserved.contentType ||
          reserved.size !== initial.reserved.size ||
          reserved.baseRevision !== initial.reserved.baseRevision ||
          currentLease === null ||
          currentLease.uploadId !== uploadId ||
          currentLease.storagePath !== reserved.storagePath) {
        fail("aborted", "The profile image reservation changed.");
      }
      const canonical = canonicalProfileMediaDocument(media, auth.uid);
      if (canonical.revision !== reserved.baseRevision ||
          canonical.revision === Number.MAX_SAFE_INTEGER) {
        fail("aborted", "Your profile image changed. Upload it again.");
      }
      const descriptor = {
        storagePath: stored.storagePath,
        generation: stored.generation,
        contentType: stored.contentType,
        size: stored.size,
      };
      const next = {
        schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
        uid: auth.uid,
        revision: canonical.revision + 1,
        avatar: canonical.avatar,
        banner: canonical.banner,
        updatedAt: timing.now,
      };
      next[reserved.kind] = descriptor;
      transaction.set(mediaRef, next);
      const legacyField = reserved.kind === "avatar" ? "photoUrl" : "bannerUrl";
      transaction.set(userRef, {
        [legacyField]: null,
        profileUpdatedAt: timing.now,
      }, { merge: true });
      if (publicProfile.exists) {
        transaction.update(publicRef, {
          [legacyField]: null,
          updatedAt: timing.now,
        });
      }
      transaction.create(finalizedRef, {
        schemaVersion: PROFILE_MEDIA_SCHEMA_VERSION,
        ownerId: auth.uid,
        uploadId,
        kind: reserved.kind,
        result,
        finalizedAt: timing.now,
      });
      transaction.create(preflight.refs.ledger, ledgerData({
        kind: "profileMedia.finalize",
        uid: auth.uid,
        requestId: uploadId,
        inputHash: finalizeIdentity.inputHash,
        result,
        now: timing.now,
      }));
      transaction.delete(reservationRef);
      transaction.delete(initial.leaseRef);
      transaction.delete(preflight.refs.preflight);
      transaction.delete(reserveRefs.ledger);
      transaction.delete(reserveRefs.preflight);
      return result;
    });
    return committed;
  }

  return Object.freeze({
    finalizeProfileMediaUpload,
    getProfileMediaAccess,
    reserveProfileMediaUpload,
  });
}

module.exports = {
  PROFILE_MEDIA_DAILY_BYTE_LIMIT,
  PROFILE_MEDIA_ACCESS_LIMIT,
  PROFILE_MEDIA_FINALIZE_LIMIT,
  PROFILE_MEDIA_RESERVE_LIMIT,
  canonicalFinalization,
  canonicalLease,
  canonicalReservation,
  createProfileMediaService,
  finalizationReference,
  leaseReference,
  reservationReference,
};

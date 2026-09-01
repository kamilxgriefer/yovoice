const {
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  consumeRateLimit,
  digest,
  fail,
  isValidOpaqueUid,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  transactionGetAll,
} = require("../integrity/guards");

const COVER_ACCESS_TTL_MS = 90_000;
const MIN_COVER_BYTES = 128;
const MAX_COVER_BYTES = 8 * 1024 * 1024;
const COVER_TYPES = new Set(["image/jpeg", "image/png"]);
const CLUB_MEDIA_ROLES = new Set([
  "owner",
  "coOwner",
  "admin",
  "moderator",
  "member",
]);
const ACCESS_LIMIT = Object.freeze({ maxEvents: 120, windowMs: 60_000 });
const UPDATE_LIMIT = Object.freeze({ maxEvents: 12, windowMs: 60_000 });
const RESERVE_LIMIT = Object.freeze({ maxEvents: 12, windowMs: 60 * 60_000 });
const UPLOAD_LEASE_MS = 10 * 60_000;
const ROOM_COVER_DAILY_BYTES = 64 * 1024 * 1024;

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return custom && typeof custom === "object" && !Array.isArray(custom)
    ? custom
    : {};
}

function canonicalRoomCoverPath(path, { roomId, hostId }) {
  if (typeof path !== "string" || path.length > 1024) return false;
  const segments = path.split("/");
  if (
    segments.length !== 3 ||
    segments[0] !== "room_images" ||
    segments[1] !== roomId
  ) {
    return false;
  }
  const file = segments[2];
  const separator = file.lastIndexOf("_");
  const extension = file.endsWith(".jpg")
    ? ".jpg"
    : file.endsWith(".png")
      ? ".png"
      : null;
  if (separator < 1 || extension === null) return false;
  const owner = file.slice(0, separator);
  const revision = file.slice(separator + 1, -extension.length);
  return (
    owner === hostId &&
    (/^[0-9]{1,20}$/u.test(revision) || /^[a-f0-9]{32}$/u.test(revision))
  );
}

function parseManagedRoomCoverUrl(value, { roomId, bucketName = null } = {}) {
  if (typeof value !== "string" || value.length > 4096) return null;
  let uri;
  try {
    uri = new URL(value);
  } catch (_) {
    return null;
  }
  if (
    uri.protocol !== "https:" ||
    uri.hostname !== "firebasestorage.googleapis.com" ||
    uri.port !== "" ||
    uri.username !== "" ||
    uri.password !== ""
  ) {
    return null;
  }
  const segments = uri.pathname.split("/").filter(Boolean);
  if (
    segments.length !== 5 ||
    segments[0] !== "v0" ||
    segments[1] !== "b" ||
    segments[3] !== "o"
  ) {
    return null;
  }
  let path;
  try {
    path = decodeURIComponent(segments[4]);
  } catch (_) {
    return null;
  }
  if (
    bucketName !== null &&
    segments[2] !== bucketName
  ) {
    return null;
  }
  if (
    typeof roomId === "string" &&
    !path.startsWith(`room_images/${roomId}/`)
  ) {
    return null;
  }
  return { bucket: segments[2], path };
}

function validateStoredRoomCover(
  metadata,
  {
    roomId,
    hostId,
    requestedGeneration = null,
    reservationId = null,
    allowLegacyMetadata = false,
  },
) {
  if (!metadata || typeof metadata !== "object") {
    fail("failed-precondition", "The uploaded room cover is missing.");
  }
  const generation = String(metadata.generation ?? "");
  const size = Number(metadata.size);
  if (
    !/^[0-9]{1,30}$/u.test(generation) ||
    (requestedGeneration !== null &&
      String(requestedGeneration) !== generation) ||
    !Number.isSafeInteger(size) ||
    size < MIN_COVER_BYTES ||
    size > MAX_COVER_BYTES ||
    !COVER_TYPES.has(metadata.contentType)
  ) {
    fail("failed-precondition", "The uploaded room cover is invalid.");
  }
  const custom = customMetadataOf(metadata);
  const allowed = new Set([
    "firebaseStorageDownloadTokens",
    "ownerId",
    "reservationId",
    "roomId",
  ]);
  if (Object.keys(custom).some((key) => !allowed.has(key))) {
    fail("failed-precondition", "The room cover metadata is not canonical.");
  }
  if (
    (!allowLegacyMetadata || custom.ownerId !== undefined) &&
    custom.ownerId !== hostId
  ) {
    fail("failed-precondition", "The room cover owner is invalid.");
  }
  if (
    (!allowLegacyMetadata || custom.roomId !== undefined) &&
    custom.roomId !== roomId
  ) {
    fail("failed-precondition", "The room cover room id is invalid.");
  }
  if (reservationId !== null && custom.reservationId !== reservationId) {
    fail("failed-precondition", "The room cover reservation is invalid.");
  }
  return {
    contentType: metadata.contentType,
    generation,
    size,
  };
}

function validateUploadReservation(
  snapshot,
  { ownerId, roomId, reservationId, nowMs },
) {
  if (!snapshot?.exists) {
    fail("failed-precondition", "The room-cover upload reservation is missing.");
  }
  const data = snapshot.data() ?? {};
  const expiresAtMs = data.expiresAt?.toMillis?.();
  if (
    data.schemaVersion !== 1 ||
    data.ownerId !== ownerId ||
    data.roomId !== roomId ||
    data.reservationId !== reservationId ||
    data.status !== "uploading" ||
    !canonicalRoomCoverPath(data.storagePath, { roomId, hostId: ownerId }) ||
    !COVER_TYPES.has(data.contentType) ||
    !Number.isSafeInteger(data.size) ||
    data.size < MIN_COVER_BYTES ||
    data.size > MAX_COVER_BYTES ||
    !Number.isSafeInteger(expiresAtMs) ||
    expiresAtMs <= nowMs
  ) {
    fail("failed-precondition", "The room-cover upload reservation is invalid.");
  }
  return {
    contentType: data.contentType,
    expiresAtMs,
    path: data.storagePath,
    requestId: requireRequestId(data.requestId),
    size: data.size,
  };
}

function canonicalCoverRecord(data, roomId) {
  const path = data.coverStoragePath;
  const generation = data.coverGeneration;
  const contentType = data.coverContentType;
  const size = data.coverSize;
  const allNull =
    (path === null || path === undefined) &&
    (generation === null || generation === undefined) &&
    (contentType === null || contentType === undefined) &&
    (size === null || size === undefined);
  if (allNull) return null;
  if (
    !isValidOpaqueUid(data.hostId) ||
    !canonicalRoomCoverPath(path, { roomId, hostId: data.hostId }) ||
    typeof generation !== "string" ||
    !/^[0-9]{1,30}$/u.test(generation) ||
    !COVER_TYPES.has(contentType) ||
    !Number.isSafeInteger(size) ||
    size < MIN_COVER_BYTES ||
    size > MAX_COVER_BYTES
  ) {
    fail("data-loss", "The canonical room cover record is malformed.");
  }
  return { path, generation, contentType, size };
}

function validateRoom(snapshot, roomId, { requireCover = false } = {}) {
  if (!snapshot?.exists) fail("not-found", "The room does not exist.");
  const data = snapshot.data() ?? {};
  if (
    !isValidOpaqueUid(data.hostId) ||
    !["public", "private"].includes(data.visibility) ||
    !["active", "closed", "archived"].includes(data.status ?? "active") ||
    data.deletionInProgress === true
  ) {
    fail("failed-precondition", "The room is unavailable.");
  }
  const cover = canonicalCoverRecord(data, roomId);
  if (requireCover && cover === null) {
    fail("failed-precondition", "This room has no private cover media.");
  }
  return { data, cover };
}

function missingObject(error) {
  return (
    error?.code === 404 ||
    error?.code === "404" ||
    error?.code === "storage/object-not-found" ||
    /(?:no such object|not found|missing fake object)/iu.test(
      String(error?.message ?? ""),
    )
  );
}

function sameCoverState(left, right) {
  return (
    left.hostId === right.hostId &&
    left.visibility === right.visibility &&
    left.imageUrl === right.imageUrl &&
    left.cover?.path === right.cover?.path &&
    left.cover?.generation === right.cover?.generation &&
    left.cover?.contentType === right.cover?.contentType &&
    left.cover?.size === right.cover?.size
  );
}

function createRoomCoverService({
  db,
  Timestamp,
  storage,
  clock = () => Date.now(),
}) {
  if (
    !db ||
    !Timestamp?.fromMillis ||
    !storage?.getMetadata ||
    !storage?.hardenRoomCoverMetadata ||
    !storage?.getSignedReadUrl ||
    !storage?.revokeDownloadTokens ||
    !storage?.deleteObject
  ) {
    throw new TypeError("db, Timestamp and room-cover storage are required.");
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
      fail("failed-precondition", "The room-cover preflight is invalid.");
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

  // Commit the actor-wide budget before any caller-selected room,
  // reservation or Storage object is touched. Unfinished/denied retries pay
  // again; only a fully committed finalize ledger is a free replay.
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
            message: "The room-cover replay is malformed.",
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

  async function consumeCommittedAttempt(scope, ownerId, timing, limit) {
    const rateRef = rateLimitReference(db, scope, ownerId);
    await db.runTransaction(async (transaction) => {
      const rate = await transaction.get(rateRef);
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope,
        uid: ownerId,
        nowMs: timing.nowMs,
        now: timing.now,
        ...limit,
      });
    });
  }

  async function authorizeMediaAccess({ auth, roomId }) {
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const [room, caller, callerRestriction] = await transactionGetAll(
        transaction,
        roomRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      activeProfile(caller, "Your");
      assertNotRestricted(callerRestriction, "Your", timing.nowMs);
      const { data, cover } = validateRoom(room, roomId, {
        requireCover: true,
      });

      const hostReferences = data.hostId === auth.uid
        ? [
            db.doc(`users/${data.hostId}`),
            db.doc(`restrictions/${data.hostId}`),
          ]
        : [
            db.doc(`users/${data.hostId}`),
            db.doc(`restrictions/${data.hostId}`),
            db.doc(`users/${auth.uid}/blocked/${data.hostId}`),
            db.doc(`users/${data.hostId}/blocked/${auth.uid}`),
          ];
      const hostState = await transactionGetAll(transaction, ...hostReferences);
      activeProfile(hostState[0], "The host");
      assertNotRestricted(hostState[1], "The host", timing.nowMs);
      if (data.hostId !== auth.uid) {
        assertNotBlocked(hostState[2], hostState[3]);
      }

      let admitted = data.visibility === "public" || data.hostId === auth.uid;
      if (!admitted && data.visibility === "private") {
        const clubId = data.clubId;
        if (typeof clubId === "string" && clubId.length > 0) {
          const [club, member] = await transactionGetAll(
            transaction,
            db.doc(`clubs/${clubId}`),
            db.doc(`clubs/${clubId}/members/${auth.uid}`),
          );
          const clubData = club.exists ? club.data() ?? {} : {};
          const memberData = member.exists ? member.data() ?? {} : {};
          admitted =
            club.exists &&
            member.exists &&
            clubData.status === "active" &&
            clubData.deletionInProgress !== true &&
            memberData.userId === auth.uid &&
            CLUB_MEDIA_ROLES.has(memberData.role) &&
            memberData.banned !== true;
        } else {
          const [participant, member] = await transactionGetAll(
            transaction,
            roomRef.collection("participants").doc(auth.uid),
            roomRef.collection("roomMembers").doc(auth.uid),
          );
          const participantData = participant.exists
            ? participant.data() ?? {}
            : {};
          const memberData = member.exists ? member.data() ?? {} : {};
          admitted =
            (participant.exists && participantData.admittedBy === data.hostId) ||
            (member.exists && memberData.userId === auth.uid);
        }
      }
      if (!admitted) {
        fail("permission-denied", "You cannot access this private room cover.");
      }
      return {
        checkedAtMs: timing.nowMs,
        contentType: cover.contentType,
        generation: cover.generation,
        hostId: data.hostId,
        path: cover.path,
        size: cover.size,
        visibility: data.visibility,
      };
    });
  }

  async function getRoomCoverMediaAccess(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(request.data, ["roomId"], ["roomId"]);
    const roomId = requireId(data.roomId, "roomId");
    const timing = time();
    await consumeCommittedAttempt(
      "roomCover.access",
      auth.uid,
      timing,
      ACCESS_LIMIT,
    );
    const access = await authorizeMediaAccess({
      auth,
      roomId,
    });
    const metadata = await storage.getMetadata(access.path);
    const media = validateStoredRoomCover(metadata, {
      roomId,
      hostId: access.hostId,
      requestedGeneration: access.generation,
    });
    if (
      media.contentType !== access.contentType ||
      media.size !== access.size
    ) {
      fail("data-loss", "The room cover no longer matches its record.");
    }
    await storage.revokeDownloadTokens(access.path, metadata);
    const expiresAtMs = access.checkedAtMs + COVER_ACCESS_TTL_MS;
    const url = await storage.getSignedReadUrl(access.path, {
      expiresAtMs,
      generation: media.generation,
    });
    if (typeof url !== "string" || !url || url.length > 4096) {
      fail("failed-precondition", "A private room-cover grant is unavailable.");
    }
    const finalAccess = await authorizeMediaAccess({
      auth,
      roomId,
    });
    if (
      finalAccess.checkedAtMs >= expiresAtMs ||
      finalAccess.contentType !== access.contentType ||
      finalAccess.generation !== access.generation ||
      finalAccess.hostId !== access.hostId ||
      finalAccess.path !== access.path ||
      finalAccess.size !== access.size ||
      finalAccess.visibility !== access.visibility
    ) {
      fail("aborted", "Room-cover authorization changed. Try again.");
    }
    return {
      schemaVersion: 1,
      url,
      expiresAtMillis: expiresAtMs,
      coverGeneration: media.generation,
      coverContentType: media.contentType,
      coverSize: media.size,
    };
  }

  async function requireHostState({ auth, roomId }) {
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const [room, profile, restriction] = await transactionGetAll(
        transaction,
        db.doc(`rooms/${roomId}`),
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const { data, cover } = validateRoom(room, roomId);
      if (data.hostId !== auth.uid) {
        fail("permission-denied", "Only the room host can update its cover.");
      }
      return {
        cover,
        hostId: data.hostId,
        imageUrl: data.imageUrl ?? null,
        updateTime: room.updateTime,
        visibility: data.visibility,
      };
    });
  }

  async function reserveRoomCoverUpload(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["contentType", "requestId", "roomId", "size"],
      ["contentType", "requestId", "roomId", "size"],
    );
    const roomId = requireId(data.roomId, "roomId");
    const requestId = requireRequestId(data.requestId);
    const size = requireSafeInteger(data.size, "size", {
      min: MIN_COVER_BYTES,
      max: MAX_COVER_BYTES,
    });
    if (!COVER_TYPES.has(data.contentType)) {
      fail("invalid-argument", "contentType is invalid.");
    }
    const extension = data.contentType === "image/png" ? "png" : "jpg";
    const reservationId = digest(
      "room-cover-upload",
      auth.uid,
      requestId,
    ).slice(0, 40);
    const revision = digest(
      "room-cover-object",
      auth.uid,
      roomId,
      requestId,
    ).slice(0, 32);
    const storagePath =
      `room_images/${roomId}/${auth.uid}_${revision}.${extension}`;
    const timing = time();
    const reserveIdentity = operationIdentity(
      "roomCover.reserve",
      auth.uid,
      requestId,
      { contentType: data.contentType, roomId, size },
    );
    const preflight = await beginOperationAttempt({
      identity: reserveIdentity,
      kind: "roomCover.reserve",
      ownerId: auth.uid,
      requestId,
      scope: "roomCover.reserve",
      limit: RESERVE_LIMIT,
      timing,
      replayExpires: true,
      freeReplay: false,
    });
    const budgetDay = new Date(timing.nowMs).toISOString().slice(0, 10);

    return db.runTransaction(async (transaction) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const reservationRef = db.doc(
        `roomCoverUploadReservations/${reservationId}`,
      );
      const leaseRef = db.doc(`roomCoverUploadLeases/${auth.uid}`);
      const budgetRef = db.doc(
        `roomCoverUploadBudgets/${auth.uid}_${budgetDay}`,
      );
      const [ledger, admitted, room, profile, restriction, reservation, lease,
        budget] =
        await transactionGetAll(
          transaction,
          preflight.refs.ledger,
          preflight.refs.preflight,
          roomRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          reservationRef,
          leaseRef,
          budgetRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "roomCover.reserve",
        uid: auth.uid,
        inputHash: reserveIdentity.inputHash,
      });
      assertCanonicalPreflight(admitted, {
        identity: reserveIdentity,
        kind: "roomCover.reserve",
        ownerId: auth.uid,
        requestId,
      });
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      if (replay) return { ...replay, replayed: true };
      const { data: roomData } = validateRoom(room, roomId);
      if (roomData.hostId !== auth.uid) {
        fail("permission-denied", "Only the room host can upload its cover.");
      }

      if (reservation.exists) {
        const prior = reservation.data() ?? {};
        if (
          prior.schemaVersion === 1 &&
          prior.ownerId === auth.uid &&
          prior.roomId === roomId &&
          prior.requestId === requestId &&
          prior.storagePath === storagePath &&
          prior.contentType === data.contentType &&
          prior.size === size &&
          prior.status === "uploading" &&
          prior.expiresAt?.toMillis?.() > timing.nowMs
        ) {
          const ledgerResult = {
            schemaVersion: 1,
            reservationId,
            storagePath,
            contentType: data.contentType,
            size,
            expiresAtMillis: prior.expiresAt.toMillis(),
          };
          transaction.create(preflight.refs.ledger, ledgerData({
            kind: "roomCover.reserve",
            uid: auth.uid,
            requestId,
            inputHash: reserveIdentity.inputHash,
            result: ledgerResult,
            now: timing.now,
          }));
          transaction.delete(preflight.refs.preflight);
          return { ...ledgerResult, replayed: true };
        }
        fail("already-exists", "requestId was reused for another upload.");
      }

      if (lease.exists) {
        const active = lease.data() ?? {};
        if (
          active.status === "uploading" &&
          active.expiresAt?.toMillis?.() > timing.nowMs
        ) {
          fail(
            "resource-exhausted",
            "Finish or wait for the current room-cover upload.",
          );
        }
      }
      const budgetData = budget.exists ? budget.data() ?? {} : {};
      const usedBytes = budget.exists ? budgetData.bytes : 0;
      const reservations = budget.exists ? budgetData.reservations : 0;
      if (
        !Number.isSafeInteger(usedBytes) ||
        usedBytes < 0 ||
        !Number.isSafeInteger(reservations) ||
        reservations < 0 ||
        usedBytes + size > ROOM_COVER_DAILY_BYTES
      ) {
        fail("resource-exhausted", "The daily room-cover upload limit is reached.");
      }
      const expiresAt = Timestamp.fromMillis(timing.nowMs + UPLOAD_LEASE_MS);
      const record = {
        schemaVersion: 1,
        ownerId: auth.uid,
        roomId,
        requestId,
        reservationId,
        storagePath,
        contentType: data.contentType,
        size,
        status: "uploading",
        createdAt: timing.now,
        expiresAt,
      };
      transaction.create(reservationRef, record);
      transaction.set(leaseRef, record);
      transaction.set(budgetRef, {
        schemaVersion: 1,
        ownerId: auth.uid,
        day: budgetDay,
        bytes: usedBytes + size,
        reservations: reservations + 1,
        updatedAt: timing.now,
      });
      const ledgerResult = {
        schemaVersion: 1,
        reservationId,
        storagePath,
        contentType: data.contentType,
        size,
        expiresAtMillis: timing.nowMs + UPLOAD_LEASE_MS,
      };
      transaction.create(preflight.refs.ledger, ledgerData({
        kind: "roomCover.reserve",
        uid: auth.uid,
        requestId,
        inputHash: reserveIdentity.inputHash,
        result: ledgerResult,
        now: timing.now,
      }));
      transaction.delete(preflight.refs.preflight);
      return { ...ledgerResult, replayed: false };
    });
  }

  // The Storage metadata read/signing happens outside Firestore, but the
  // final authority check and pointer/visibility write must not. Comparing
  // the complete expected tuple inside the same transaction closes host
  // bans, room deletes and concurrent cover A -> B changes between the
  // second authorization read and an Admin SDK update.
  async function commitExpectedHostUpdate({
    auth,
    roomId,
    expected,
    buildUpdate,
  }) {
    const timing = time();
    return db.runTransaction(async (transaction) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const [room, profile, restriction] = await transactionGetAll(
        transaction,
        roomRef,
        db.doc(`users/${auth.uid}`),
        db.doc(`restrictions/${auth.uid}`),
      );
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const { data, cover } = validateRoom(room, roomId);
      if (data.hostId !== auth.uid) {
        fail("permission-denied", "Only the room host can update its cover.");
      }
      const current = {
        cover,
        hostId: data.hostId,
        imageUrl: data.imageUrl ?? null,
        visibility: data.visibility,
      };
      if (!sameCoverState(current, expected)) {
        fail("aborted", "The room cover changed. Try again.");
      }
      const update = buildUpdate({ current, now: timing.now });
      if (!update || typeof update !== "object" || Array.isArray(update)) {
        throw new TypeError("buildUpdate must return a Firestore update.");
      }
      transaction.update(roomRef, update);
      return current;
    });
  }

  async function finalizeRoomCoverUpload(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["objectGeneration", "reservationId", "roomId"],
      ["objectGeneration", "reservationId", "roomId"],
    );
    const roomId = requireId(data.roomId, "roomId");
    const reservationId = requireId(data.reservationId, "reservationId");
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const timing = time();
    const finalizeIdentity = operationIdentity(
      "roomCover.finalize",
      auth.uid,
      reservationId,
      { objectGeneration, roomId },
    );
    const preflight = await beginOperationAttempt({
      identity: finalizeIdentity,
      kind: "roomCover.finalize",
      ownerId: auth.uid,
      requestId: reservationId,
      scope: "roomCover.update",
      limit: UPDATE_LIMIT,
      timing,
    });
    if (preflight.replay) return preflight.replay;
    const state = await requireHostState({
      auth,
      roomId,
    });
    const reservationRef = db.doc(
      `roomCoverUploadReservations/${reservationId}`,
    );
    const reservation = validateUploadReservation(
      await reservationRef.get(),
      {
        ownerId: auth.uid,
        roomId,
        reservationId,
        nowMs: time().nowMs,
      },
    );
    const storagePath = reservation.path;
    const metadata = await storage.getMetadata(storagePath);
    const media = validateStoredRoomCover(metadata, {
      roomId,
      hostId: auth.uid,
      requestedGeneration: objectGeneration,
      reservationId,
    });
    if (
      media.contentType !== reservation.contentType ||
      media.size !== reservation.size
    ) {
      fail("failed-precondition", "The uploaded cover does not match its reservation.");
    }
    await storage.hardenRoomCoverMetadata(storagePath, metadata, {
      ownerId: auth.uid,
      roomId,
    });

    const result = {
      roomId,
      updated: true,
      coverStoragePath: storagePath,
      coverGeneration: media.generation,
      reservationId,
    };
    const reserveRefs = operationReferences(operationIdentity(
      "roomCover.reserve",
      auth.uid,
      reservation.requestId,
      {},
    ));
    const committed = await db.runTransaction(async (transaction) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const leaseRef = db.doc(`roomCoverUploadLeases/${auth.uid}`);
      const [ledger, admitted, room, profile, restriction,
        currentReservation, lease] =
        await transactionGetAll(
          transaction,
          preflight.refs.ledger,
          preflight.refs.preflight,
          roomRef,
          db.doc(`users/${auth.uid}`),
          db.doc(`restrictions/${auth.uid}`),
          reservationRef,
          leaseRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "roomCover.finalize",
        uid: auth.uid,
        inputHash: finalizeIdentity.inputHash,
      });
      if (replay) return replay;
      assertCanonicalPreflight(admitted, {
        identity: finalizeIdentity,
        kind: "roomCover.finalize",
        ownerId: auth.uid,
        requestId: reservationId,
      });
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const { data: roomData, cover } = validateRoom(room, roomId);
      if (roomData.hostId !== auth.uid) {
        fail("permission-denied", "Only the room host can update its cover.");
      }
      const currentState = {
        cover,
        hostId: roomData.hostId,
        imageUrl: roomData.imageUrl ?? null,
        visibility: roomData.visibility,
      };
      if (!sameCoverState(currentState, state)) {
        fail("aborted", "The room cover changed. Try again.");
      }
      validateUploadReservation(currentReservation, {
        ownerId: auth.uid,
        roomId,
        reservationId,
        nowMs: timing.nowMs,
      });
      const leaseData = lease.exists ? lease.data() ?? {} : {};
      if (
        leaseData.reservationId !== reservationId ||
        leaseData.ownerId !== auth.uid ||
        leaseData.roomId !== roomId ||
        leaseData.status !== "uploading"
      ) {
        fail("failed-precondition", "The room-cover upload lease is invalid.");
      }
      transaction.update(roomRef, {
        imageUrl: null,
        coverStoragePath: storagePath,
        coverGeneration: media.generation,
        coverContentType: media.contentType,
        coverSize: media.size,
        updatedAt: timing.now,
      });
      transaction.delete(reservationRef);
      transaction.delete(leaseRef);
      transaction.create(preflight.refs.ledger, ledgerData({
        kind: "roomCover.finalize",
        uid: auth.uid,
        requestId: reservationId,
        inputHash: finalizeIdentity.inputHash,
        result,
        now: timing.now,
      }));
      transaction.delete(preflight.refs.preflight);
      transaction.delete(reserveRefs.ledger);
      transaction.delete(reserveRefs.preflight);
      return result;
    });

    const previousPath = state.cover?.path ??
      parseManagedRoomCoverUrl(state.imageUrl, {
        roomId,
        bucketName: storage.bucketName ?? null,
      })?.path;
    if (
      typeof previousPath === "string" &&
      previousPath !== storagePath &&
      previousPath.startsWith(`room_images/${roomId}/`)
    ) {
      try {
        await storage.deleteObject(previousPath, { ignoreNotFound: true });
      } catch (_) {
        // The new canonical pointer already committed. Prefix cleanup during
        // room deletion/migration remains the retry boundary for old objects.
      }
    }
    return committed;
  }

  async function setRoomVisibilitySelf(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["roomId", "visibility"],
      ["roomId", "visibility"],
    );
    const roomId = requireId(data.roomId, "roomId");
    if (!["public", "private"].includes(data.visibility)) {
      fail("invalid-argument", "visibility must be public or private.");
    }
    const timing = time();
    await consumeCommittedAttempt(
      "roomCover.update",
      auth.uid,
      timing,
      UPDATE_LIMIT,
    );
    const state = await requireHostState({
      auth,
      roomId,
    });
    let recoveredCover = state.cover;
    if (data.visibility === "private") {
      let path = state.cover?.path ?? null;
      if (path === null) {
        path = parseManagedRoomCoverUrl(state.imageUrl, {
          roomId,
          bucketName: storage.bucketName ?? null,
        })?.path ?? null;
      }
      if (path !== null) {
        let metadata;
        try {
          metadata = await storage.getMetadata(path);
        } catch (error) {
          if (!missingObject(error)) throw error;
          metadata = null;
        }
        if (metadata !== null) {
          const media = validateStoredRoomCover(metadata, {
            roomId,
            hostId: auth.uid,
            requestedGeneration: state.cover?.generation ?? null,
            allowLegacyMetadata: true,
          });
          await storage.hardenRoomCoverMetadata(path, metadata, {
            ownerId: auth.uid,
            roomId,
          });
          recoveredCover = {
            path,
            generation: media.generation,
            contentType: media.contentType,
            size: media.size,
          };
        } else if (state.cover !== null) {
          fail("failed-precondition", "The canonical room cover is missing.");
        }
      }
    }

    await commitExpectedHostUpdate({
      auth,
      roomId,
      expected: state,
      buildUpdate: ({ now }) => {
        const update = {
          visibility: data.visibility,
          updatedAt: now,
        };
        if (data.visibility === "private") {
          update.imageUrl = null;
          if (recoveredCover !== null) {
            update.coverStoragePath = recoveredCover.path;
            update.coverGeneration = recoveredCover.generation;
            update.coverContentType = recoveredCover.contentType;
            update.coverSize = recoveredCover.size;
          }
        }
        return update;
      },
    });
    return { roomId, visibility: data.visibility };
  }

  async function expireRoomCoverUploadReservations({ limit = 50 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 100 });
    const timing = time();
    const snapshot = await db
      .collection("roomCoverUploadReservations")
      .where("expiresAt", "<=", timing.now)
      .limit(limit)
      .get();
    const expired = [];
    for (const document of snapshot.docs) {
      const reservationId = document.id;
      const data = document.data() ?? {};
      if (
        data.schemaVersion !== 1 ||
        !isValidOpaqueUid(data.ownerId) ||
        !isValidOpaqueUid(data.roomId) ||
        data.reservationId !== reservationId ||
        typeof data.storagePath !== "string" ||
        !["uploading", "expiring"].includes(data.status)
      ) {
        fail("data-loss", "A room-cover upload reservation is malformed.");
      }
      const reservationRef = document.ref;
      const leaseRef = db.doc(`roomCoverUploadLeases/${data.ownerId}`);
      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(reservationRef);
        if (!current.exists) return false;
        const currentData = current.data() ?? {};
        if (currentData.reservationId !== reservationId) {
          return false;
        }
        if (currentData.status === "expiring") {
          return true;
        }
        if (currentData.status !== "uploading") {
          fail("data-loss", "A room-cover upload reservation is malformed.");
        }
        transaction.update(reservationRef, {
          status: "expiring",
          updatedAt: timing.now,
        });
        return true;
      });
      if (!claimed) continue;
      await storage.deleteObject(data.storagePath, { ignoreNotFound: true });
      await db.runTransaction(async (transaction) => {
        const [current, lease] = await transactionGetAll(
          transaction,
          reservationRef,
          leaseRef,
        );
        if (
          current.exists &&
          (current.data() ?? {}).reservationId === reservationId
        ) {
          transaction.delete(reservationRef);
        }
        if (
          lease.exists &&
          (lease.data() ?? {}).reservationId === reservationId
        ) {
          transaction.delete(leaseRef);
        }
      });
      expired.push(reservationId);
    }
    return {
      expired,
      processed: snapshot.size,
      hasMore: snapshot.size === limit,
    };
  }

  return Object.freeze({
    expireRoomCoverUploadReservations,
    finalizeRoomCoverUpload,
    getRoomCoverMediaAccess,
    reserveRoomCoverUpload,
    setRoomVisibilitySelf,
  });
}

module.exports = {
  COVER_ACCESS_TTL_MS,
  MAX_COVER_BYTES,
  MIN_COVER_BYTES,
  UPLOAD_LEASE_MS,
  ROOM_COVER_DAILY_BYTES,
  canonicalCoverRecord,
  canonicalRoomCoverPath,
  createRoomCoverService,
  customMetadataOf,
  parseManagedRoomCoverUrl,
  validateStoredRoomCover,
};

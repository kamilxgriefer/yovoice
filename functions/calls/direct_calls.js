const { createHash, randomUUID } = require("node:crypto");

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions/v2");
const { AccessToken, TrackSource } = require("livekit-server-sdk");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  consumeRateLimit,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireRequestId,
  transactionGetAll,
} = require("../integrity/guards");
const {
  canonicalNotificationData,
  notificationReference,
  restrictionIsActive,
} = require("../notifications/canonical");
const {
  activeVoiceSessionReference,
  deleteActiveVoiceSessionsForRoom,
  writeActiveVoiceSession,
} = require("../livekit/sessions");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");

const REGION = "europe-west1";
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const RING_TTL_MS = 60 * 1000;
const ACTIVE_CALL_TTL_MS = 8 * 60 * 60 * 1000;
const TOKEN_TTL = "5m";
const TOKEN_TTL_SECONDS = 5 * 60;
const DIRECT_CALL_TOKEN_RATE_WINDOW_MS = 60 * 1000;
const DIRECT_CALL_TOKEN_RATE_LIMIT = 12;
const DIRECT_CALL_ATTEMPT_LIMITS = Object.freeze({
  start: Object.freeze({
    scope: "direct.call.start.attempt",
    windowMs: 10 * 60 * 1000,
    maxEvents: 10,
  }),
  token: Object.freeze({
    scope: "direct.call.token.attempt",
    windowMs: DIRECT_CALL_TOKEN_RATE_WINDOW_MS,
    maxEvents: DIRECT_CALL_TOKEN_RATE_LIMIT,
  }),
});
const DIRECT_CALL_MEDIA_TYPES = new Set(["audio", "video"]);
// Video was added after the original audio-only direct-call protocol. A
// recipient with even one registered legacy device must not receive a call
// that the device could silently present as audio while the caller publishes
// camera video. FCM device rows are the existing per-device registration
// boundary, so the client advertises the exact protocol it understands there.
const DIRECT_VIDEO_PROTOCOL_VERSION = 1;
const MAX_DIRECT_CALL_DEVICE_CAPABILITIES = 50;
const DIRECT_CALL_START_LIMITS = Object.freeze({
  caller: Object.freeze({
    windowMs: 10 * 60 * 1000,
    maxEvents: 10,
    cooldownMs: 3 * 1000,
  }),
  callee: Object.freeze({
    windowMs: 10 * 60 * 1000,
    maxEvents: 20,
    cooldownMs: 1000,
  }),
  pair: Object.freeze({
    windowMs: 10 * 60 * 1000,
    maxEvents: 4,
    cooldownMs: 10 * 1000,
  }),
});
const TERMINAL_STATUSES = new Set([
  "declined",
  "cancelled",
  "ended",
  "missed",
]);
const CALL_STATUSES = new Set(["ringing", "active", ...TERMINAL_STATUSES]);
const DEFERRED_REQUEST_ID_CONFLICT = Symbol("direct-call-request-id-conflict");

const livekitApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");
const livekitUrl = defineString("LIVEKIT_URL");

function directCallRoomName(callId) {
  const id = normalizeText(callId, 128);
  if (!SAFE_ID.test(id)) {
    throw new HttpsError("invalid-argument", "A valid call is required.");
  }
  return `call_${id}`;
}

function timestampMillis(value) {
  return value && typeof value.toMillis === "function"
    ? value.toMillis()
    : null;
}

function operationLedgerReference(identity) {
  return db.doc(`integrityOperationLedgers/${identity.id}`);
}

function directCallAttemptRateReference(kind, uid) {
  const config = DIRECT_CALL_ATTEMPT_LIMITS[kind];
  if (!config || typeof uid !== "string" || uid.length === 0) {
    throw new TypeError("A valid direct-call attempt scope is required.");
  }
  return rateLimitReference(db, config.scope, uid);
}

function completedOperationReplay(snapshot, {
  kind,
  uid,
  inputHashes,
  nowMs,
  tokenResult = false,
  deferRequestIdConflict = false,
}) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const result = data.result;
  const hashes = inputHashes instanceof Set
    ? inputHashes
    : new Set(inputHashes ?? []);
  const validResult = result && typeof result === "object" &&
    SAFE_ID.test(normalizeText(result.callId ?? result.roomName, 128));
  const requestIdConflict =
    data.schemaVersion !== 1 ||
    data.kind !== kind ||
    data.ownerId !== uid ||
    !hashes.has(data.inputHash);
  if (requestIdConflict && deferRequestIdConflict) {
    return DEFERRED_REQUEST_ID_CONFLICT;
  }
  if (requestIdConflict || !validResult) {
    throw new HttpsError(
      "already-exists",
      "requestId was already used for another call operation.",
    );
  }
  if (tokenResult) {
    if (
      typeof result.participantToken !== "string" ||
      result.participantToken.length === 0 ||
      !Number.isSafeInteger(result.expiresAtMillis)
    ) {
      throw new HttpsError("data-loss", "The private token ledger is invalid.");
    }
    if (result.expiresAtMillis <= nowMs) {
      throw new HttpsError(
        "already-exists",
        "This token request has expired. Start a new connection attempt.",
      );
    }
  } else if (
    !CALL_STATUSES.has(result.status) ||
    !(result.expiresAtMillis === null ||
      Number.isSafeInteger(result.expiresAtMillis))
  ) {
    throw new HttpsError("data-loss", "The private call ledger is invalid.");
  }
  return result;
}

async function consumeDirectCallAttempt({
  kind,
  uid,
  identity = null,
  operationKind = null,
  inputHashes = null,
  tokenResult = false,
  nowMs = Date.now(),
}) {
  const config = DIRECT_CALL_ATTEMPT_LIMITS[kind];
  if (!config) throw new TypeError(`Unknown direct-call attempt kind: ${kind}`);
  const now = Timestamp.fromMillis(nowMs);
  const rateReference = directCallAttemptRateReference(kind, uid);
  const ledgerReference = identity === null
    ? null
    : operationLedgerReference(identity);
  const outcome = await db.runTransaction(async (transaction) => {
    const snapshots = await transactionGetAll(
      transaction,
      ...(ledgerReference === null ? [] : [ledgerReference]),
      rateReference,
    );
    const rateSnapshot = snapshots.at(-1);
    if (ledgerReference !== null) {
      const replay = completedOperationReplay(snapshots[0], {
        kind: operationKind,
        uid,
        inputHashes,
        nowMs,
        tokenResult,
        deferRequestIdConflict: true,
      });
      if (replay && replay !== DEFERRED_REQUEST_ID_CONFLICT) return replay;
      if (replay === DEFERRED_REQUEST_ID_CONFLICT) {
        consumeRateLimit(transaction, rateSnapshot, {
          reference: rateReference,
          scope: config.scope,
          uid,
          nowMs,
          now,
          maxEvents: config.maxEvents,
          windowMs: config.windowMs,
        });
        return DEFERRED_REQUEST_ID_CONFLICT;
      }
    }
    consumeRateLimit(transaction, rateSnapshot, {
      reference: rateReference,
      scope: config.scope,
      uid,
      nowMs,
      now,
      maxEvents: config.maxEvents,
      windowMs: config.windowMs,
    });
    return null;
  });
  if (outcome === DEFERRED_REQUEST_ID_CONFLICT) {
    throw new HttpsError(
      "already-exists",
      "requestId was already used for another call operation.",
    );
  }
  return outcome;
}

function writeDirectCallStartLedger(transaction, callId, call, status, expiresAt) {
  const requestId = call?.startRequestId;
  const inputHash = call?.startInputHash;
  if (
    typeof requestId !== "string" ||
    !/^[A-Za-z0-9_-]{8,128}$/u.test(requestId) ||
    typeof inputHash !== "string" ||
    inputHash.length !== 64 ||
    typeof call?.callerId !== "string"
  ) {
    return;
  }
  const identity = operationIdentity(
    "direct.call.start",
    call.callerId,
    requestId,
    {},
  );
  const now = call.updatedAt instanceof Timestamp
    ? call.updatedAt
    : Timestamp.now();
  transaction.set(operationLedgerReference(identity), ledgerData({
    kind: "direct.call.start",
    uid: call.callerId,
    requestId,
    inputHash,
    result: {
      callId,
      status,
      expiresAtMillis: timestampMillis(expiresAt),
    },
    now: call.createdAt instanceof Timestamp ? call.createdAt : now,
  }));
}

function profileData(snapshot, label) {
  if (!snapshot?.exists) {
    throw new HttpsError("not-found", `${label} profile does not exist.`);
  }
  const profile = snapshot.data() ?? {};
  if (
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted"
  ) {
    throw new HttpsError(
      "permission-denied",
      `${label} account is not available for calls.`,
    );
  }
  return profile;
}

function canonicalIdentity(uid, profile) {
  return {
    userId: uid,
    displayName:
      normalizeText(profile.displayName || profile.username, 80) ||
      "YO Voice user",
    // Profile media is a viewer-authorized capability. Copying a durable or
    // external URL into call/LiveKit metadata would keep it reachable after
    // a visibility or block change. Clients resolve the participant uid via
    // getProfileMediaAccess instead.
    photoUrl: null,
  };
}

function exactFriendshipGuard(snapshot, ownerId, friendId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = ["establishedAt", "friendId", "ownerId", "schemaVersion"];
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    data.ownerId === ownerId &&
    data.friendId === friendId &&
    data.schemaVersion === 1 &&
    timestampMillis(data.establishedAt) !== null;
}

function assertCanonicalFriendship(first, second, firstId, secondId) {
  if (
    !exactFriendshipGuard(first, firstId, secondId) ||
    !exactFriendshipGuard(second, secondId, firstId)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Direct voice calls are available between confirmed friends.",
    );
  }
}

function assertNotBlocked(first, second) {
  if (first?.exists || second?.exists) {
    throw new HttpsError(
      "failed-precondition",
      "This call is unavailable because one of the accounts has blocked the other.",
    );
  }
}

function assertNotRestricted(snapshot, label, nowMillis) {
  if (restrictionIsActive(snapshot?.exists ? snapshot.data() : null, nowMillis)) {
    throw new HttpsError(
      "permission-denied",
      `${label} account cannot use voice calls right now.`,
    );
  }
}

function assertDirectConversation(snapshot, callerId, calleeId) {
  const participantIds = snapshot?.exists &&
      Array.isArray(snapshot.data()?.participantIds)
    ? snapshot.data().participantIds
    : [];
  if (
    participantIds.length !== 2 ||
    !participantIds.includes(callerId) ||
    !participantIds.includes(calleeId)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Start this call from your direct conversation.",
    );
  }
}

function lockIsActive(snapshot, nowMillis) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  return ["ringing", "active"].includes(data.status) &&
    (timestampMillis(data.expiresAt) ?? 0) > nowMillis;
}

function requireCallId(request) {
  const callId = normalizeText(request.data?.callId, 128);
  if (!SAFE_ID.test(callId)) {
    throw new HttpsError("invalid-argument", "A valid call is required.");
  }
  return callId;
}

function requireDirectCallMediaType(value) {
  // Calls created before video support have no mediaType and remain audio.
  const mediaType = value === undefined || value === null
    ? "audio"
    : normalizeText(value, 16);
  if (!DIRECT_CALL_MEDIA_TYPES.has(mediaType)) {
    throw new HttpsError(
      "invalid-argument",
      "Choose a supported call type.",
    );
  }
  return mediaType;
}

async function assertDirectVideoRecipientCompatible(transaction, userId) {
  const registeredDevices = await transaction.get(
    db.collection(`users/${userId}/fcmTokens`)
      .limit(MAX_DIRECT_CALL_DEVICE_CAPABILITIES + 1),
  );
  const hasTooManyDevices =
    registeredDevices.size > MAX_DIRECT_CALL_DEVICE_CAPABILITIES;
  const everyDeviceSupportsVideo = registeredDevices.size > 0 &&
    registeredDevices.docs.every((document) =>
      document.data()?.directVideoProtocol === DIRECT_VIDEO_PROTOCOL_VERSION,
    );
  if (hasTooManyDevices || !everyDeviceSupportsVideo) {
    throw new HttpsError(
      "failed-precondition",
      "Video calling is not available until your friend updates YO Voice on every active device.",
      {
        reason: "direct-video-capability-required",
        audioFallbackAvailable: true,
        requiredProtocol: DIRECT_VIDEO_PROTOCOL_VERSION,
      },
    );
  }
}

function callContext(callSnapshot, actorId) {
  if (!callSnapshot.exists) {
    throw new HttpsError("not-found", "This call is no longer available.");
  }
  const call = callSnapshot.data() ?? {};
  const participants = Array.isArray(call.participantIds)
    ? call.participantIds
    : [];
  if (
    participants.length !== 2 ||
    !participants.includes(actorId) ||
    ![call.callerId, call.calleeId].every((uid) => participants.includes(uid))
  ) {
    throw new HttpsError("permission-denied", "You cannot access this call.");
  }
  return { call, participants };
}

async function assertCallPairAvailable(transaction, call, nowMillis) {
  const firstId = call.callerId;
  const secondId = call.calleeId;
  const related = await transaction.getAll(
    db.doc(`users/${firstId}`),
    db.doc(`users/${secondId}`),
    db.doc(`restrictions/${firstId}`),
    db.doc(`restrictions/${secondId}`),
    db.doc(`users/${firstId}/blocked/${secondId}`),
    db.doc(`users/${secondId}/blocked/${firstId}`),
    db.doc(`friendshipGuards/${firstId}/friends/${secondId}`),
    db.doc(`friendshipGuards/${secondId}/friends/${firstId}`),
  );
  const firstProfile = profileData(related[0], "The caller");
  const secondProfile = profileData(related[1], "The recipient");
  assertNotRestricted(related[2], "The caller", nowMillis);
  assertNotRestricted(related[3], "The recipient", nowMillis);
  assertNotBlocked(related[4], related[5]);
  assertCanonicalFriendship(related[6], related[7], firstId, secondId);
  return { firstProfile, secondProfile };
}

function incomingCallReference(userId, callId) {
  return db.doc(`users/${userId}/incomingCalls/${callId}`);
}

function callLockReference(userId) {
  return db.doc(`directCallLocks/${userId}`);
}

function callControlReference(callId) {
  return db.doc(`directCallControlOutbox/${callId}`);
}

function directCallStartLimitReference(scope, ...subjectIds) {
  if (!Object.hasOwn(DIRECT_CALL_START_LIMITS, scope) ||
      subjectIds.length === 0 ||
      subjectIds.some((uid) => typeof uid !== "string" || uid.length === 0)) {
    throw new TypeError("A valid direct-call rate-limit scope is required.");
  }
  const subject = scope === "pair"
    ? [...subjectIds].sort().join("\u0000")
    : subjectIds.join("\u0000");
  const id = createHash("sha256")
    .update(`direct-call-start\u0000${scope}\u0000${subject}`)
    .digest("hex");
  return db.doc(`directCallStartLimits/${id}`);
}

function consumeDirectCallStartLimit({
  transaction,
  snapshot,
  reference,
  scope,
  now,
}) {
  const config = DIRECT_CALL_START_LIMITS[scope];
  if (!config) throw new TypeError(`Unknown direct-call limit scope: ${scope}`);
  const data = snapshot.exists ? snapshot.data() ?? {} : {};
  if (snapshot.exists &&
      (data.schemaVersion !== 1 || data.scope !== scope ||
       !Array.isArray(data.startedAt))) {
    throw new HttpsError(
      "data-loss",
      "The private direct-call rate-limit state is invalid.",
    );
  }
  const nowMillis = now.toMillis();
  const stored = Array.isArray(data.startedAt) ? data.startedAt : [];
  if (stored.length > 100 || stored.some((timestamp) => {
    const millis = timestampMillis(timestamp);
    return typeof timestamp?.toMillis !== "function" ||
      millis === null || millis > nowMillis;
  })) {
    throw new HttpsError(
      "data-loss",
      "The private direct-call rate-limit state is invalid.",
    );
  }
  const windowStart = nowMillis - config.windowMs;
  const recent = stored
    .filter((timestamp) => timestamp.toMillis() > windowStart)
    .sort((first, second) => first.toMillis() - second.toMillis());
  const latestMillis = recent.length === 0
    ? null
    : recent.at(-1).toMillis();
  if ((latestMillis !== null && nowMillis - latestMillis < config.cooldownMs) ||
      recent.length >= config.maxEvents) {
    throw new HttpsError(
      "resource-exhausted",
      "Voice calling is temporarily rate-limited. Try again later.",
    );
  }
  transaction.set(reference, {
    schemaVersion: 1,
    scope,
    startedAt: [...recent, now],
    updatedAt: now,
  });
}

function missedCallNotificationId(callId) {
  return `missedCall_${callId}`;
}

async function startDirectCallHandler(request) {
  const auth = requireAuthentication(request);
  if (auth.token?.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Verify your email before starting a voice call.",
    );
  }
  const calleeId = normalizeText(request.data?.calleeId, 128);
  const conversationId = normalizeText(request.data?.conversationId, 128);
  const mediaTypeWasProvided = Object.hasOwn(
    request.data && typeof request.data === "object" ? request.data : {},
    "mediaType",
  );
  const mediaType = requireDirectCallMediaType(request.data?.mediaType);
  if (!SAFE_ID.test(calleeId) || calleeId === auth.uid) {
    throw new HttpsError(
      "invalid-argument",
      "Choose another user to call.",
    );
  }
  if (!SAFE_ID.test(conversationId)) {
    throw new HttpsError(
      "invalid-argument",
      "The conversation is not valid.",
    );
  }
  const requestId = request.data?.requestId === undefined ||
      request.data?.requestId === null
    ? null
    : requireRequestId(request.data.requestId);
  const startIdentity = requestId === null
    ? null
    : operationIdentity(
      "direct.call.start",
      auth.uid,
      requestId,
      mediaTypeWasProvided
        ? { calleeId, conversationId, mediaType }
        : { calleeId, conversationId },
    );
  const canonicalStartIdentity = requestId === null
    ? null
    : operationIdentity(
      "direct.call.start",
      auth.uid,
      requestId,
      { calleeId, conversationId, mediaType },
    );
  const legacyAudioStartIdentity = requestId === null || mediaType !== "audio"
    ? null
    : operationIdentity(
      "direct.call.start",
      auth.uid,
      requestId,
      { calleeId, conversationId },
    );
  const compatibleInputHashes = new Set([
    startIdentity?.inputHash,
    canonicalStartIdentity?.inputHash,
    legacyAudioStartIdentity?.inputHash,
  ].filter(Boolean));

  const callRef = db.collection("directCalls").doc(
    startIdentity === null
      ? randomUUID().replaceAll("-", "")
      : `call_${startIdentity.id.slice(0, 40)}`,
  );
  const ledgerRef = startIdentity === null
    ? null
    : operationLedgerReference(startIdentity);

  // This transaction commits before any callee, conversation, friendship,
  // block, lock or per-target limiter read. Denied/random targets therefore
  // cannot turn a rolled-back transaction into an unbounded read bill. A
  // completed requestId is served from its private ledger without a charge.
  const preflightReplay = await consumeDirectCallAttempt({
    kind: "start",
    uid: auth.uid,
    identity: startIdentity,
    operationKind: "direct.call.start",
    inputHashes: compatibleInputHashes,
  });
  if (preflightReplay) return preflightReplay;

  const callerRef = db.doc(`users/${auth.uid}`);
  const calleeRef = db.doc(`users/${calleeId}`);
  const callerRestrictionRef = db.doc(`restrictions/${auth.uid}`);
  const calleeRestrictionRef = db.doc(`restrictions/${calleeId}`);
  const callerBlockRef = db.doc(`users/${auth.uid}/blocked/${calleeId}`);
  const calleeBlockRef = db.doc(`users/${calleeId}/blocked/${auth.uid}`);
  const callerFriendRef = db.doc(
    `friendshipGuards/${auth.uid}/friends/${calleeId}`,
  );
  const calleeFriendRef = db.doc(
    `friendshipGuards/${calleeId}/friends/${auth.uid}`,
  );
  const callerLockRef = callLockReference(auth.uid);
  const calleeLockRef = callLockReference(calleeId);
  const callerStartLimitRef = directCallStartLimitReference("caller", auth.uid);
  const calleeStartLimitRef = directCallStartLimitReference("callee", calleeId);
  const pairStartLimitRef = directCallStartLimitReference(
    "pair",
    auth.uid,
    calleeId,
  );
  const conversationRef = db.doc(`conversations/${conversationId}`);
  const signalRef = incomingCallReference(calleeId, callRef.id);
  const notificationRef = notificationReference(
    calleeId,
    `directCall_${callRef.id}`,
  );

  return db.runTransaction(async (transaction) => {
    const now = Timestamp.now();
    const nowMillis = now.toMillis();
    const operationSnapshots = await transactionGetAll(
      transaction,
      ...(ledgerRef === null ? [] : [ledgerRef]),
      callRef,
    );
    const existingCall = operationSnapshots.at(-1);
    if (ledgerRef !== null) {
      const replay = completedOperationReplay(operationSnapshots[0], {
        kind: "direct.call.start",
        uid: auth.uid,
        inputHashes: compatibleInputHashes,
        nowMs: nowMillis,
      });
      if (replay) return replay;
    }

    if (existingCall.exists) {
      const existing = existingCall.data() ?? {};
      const inputHashMatches = compatibleInputHashes.has(existing.startInputHash);
      if (startIdentity === null ||
          existing.startRequestId !== requestId ||
          !inputHashMatches ||
          existing.callerId !== auth.uid ||
          existing.calleeId !== calleeId ||
          existing.conversationId !== conversationId ||
          requireDirectCallMediaType(existing.mediaType) !== mediaType) {
        throw new HttpsError(
          "already-exists",
          "This call requestId was already used for another call.",
        );
      }
      const result = {
        callId: callRef.id,
        status: existing.status,
        expiresAtMillis: timestampMillis(existing.expiresAt),
      };
      // Backfill the cheap replay boundary for calls created by a previous
      // server revision, then every later lost-response retry is ledger-only.
      writeDirectCallStartLedger(
        transaction,
        callRef.id,
        existing,
        result.status,
        existing.expiresAt,
      );
      return result;
    }

    const [
      callerSnapshot,
      calleeSnapshot,
      callerRestriction,
      calleeRestriction,
      callerBlock,
      calleeBlock,
      callerFriend,
      calleeFriend,
      callerLock,
      calleeLock,
      conversation,
      callerStartLimit,
      calleeStartLimit,
      pairStartLimit,
    ] = await transaction.getAll(
      callerRef,
      calleeRef,
      callerRestrictionRef,
      calleeRestrictionRef,
      callerBlockRef,
      calleeBlockRef,
      callerFriendRef,
      calleeFriendRef,
      callerLockRef,
      calleeLockRef,
      conversationRef,
      callerStartLimitRef,
      calleeStartLimitRef,
      pairStartLimitRef,
    );

    const callerProfile = profileData(callerSnapshot, "Your");
    const calleeProfile = profileData(calleeSnapshot, "The selected");
    assertNotRestricted(callerRestriction, "Your", nowMillis);
    assertNotRestricted(calleeRestriction, "The selected", nowMillis);
    assertNotBlocked(callerBlock, calleeBlock);
    assertCanonicalFriendship(
      callerFriend,
      calleeFriend,
      auth.uid,
      calleeId,
    );
    assertDirectConversation(conversation, auth.uid, calleeId);
    if (mediaType === "video") {
      // Deliberately after friendship/conversation authorization: callers must
      // not be able to probe another account's private device inventory.
      await assertDirectVideoRecipientCompatible(transaction, calleeId);
    }
    if (lockIsActive(callerLock, nowMillis)) {
      throw new HttpsError(
        "already-exists",
        "You already have a voice call in progress.",
      );
    }
    if (lockIsActive(calleeLock, nowMillis)) {
      throw new HttpsError(
        "resource-exhausted",
        "This person is already on another call.",
      );
    }

    for (const [scope, snapshot, reference] of [
      ["caller", callerStartLimit, callerStartLimitRef],
      ["callee", calleeStartLimit, calleeStartLimitRef],
      ["pair", pairStartLimit, pairStartLimitRef],
    ]) {
      consumeDirectCallStartLimit({
        transaction,
        snapshot,
        reference,
        scope,
        now,
      });
    }

    const caller = canonicalIdentity(auth.uid, callerProfile);
    const callee = canonicalIdentity(calleeId, calleeProfile);
    const participantIds = [auth.uid, calleeId].sort();
    const expiresAt = Timestamp.fromMillis(nowMillis + RING_TTL_MS);
    const callData = {
      schemaVersion: 1,
      callerId: auth.uid,
      calleeId,
      participantIds,
      caller,
      callee,
      conversationId,
      mediaType,
      status: "ringing",
      createdAt: now,
      updatedAt: now,
      expiresAt,
      answeredAt: null,
      endedAt: null,
      endedBy: null,
      ...(startIdentity === null ? {} : {
        startRequestId: requestId,
        startInputHash: startIdentity.inputHash,
      }),
    };
    transaction.create(callRef, callData);
    writeDirectCallStartLedger(
      transaction,
      callRef.id,
      callData,
      "ringing",
      expiresAt,
    );
    transaction.create(signalRef, {
      callId: callRef.id,
      callerId: auth.uid,
      callerName: caller.displayName,
      callerPhotoUrl: caller.photoUrl,
      mediaType,
      status: "ringing",
      createdAt: now,
      updatedAt: now,
      expiresAt,
    });
    for (const [lockRef, userId] of [
      [callerLockRef, auth.uid],
      [calleeLockRef, calleeId],
    ]) {
      transaction.set(lockRef, {
        userId,
        callId: callRef.id,
        status: "ringing",
        expiresAt,
        updatedAt: now,
      });
    }
    transaction.create(
      notificationRef,
      canonicalNotificationData({
        actorId: auth.uid,
        actorProfile: callerProfile,
        type: "directCall",
        targetId: callRef.id,
        targetLabel: mediaType === "video"
          ? "Incoming video call"
          : "Incoming voice call",
        dedupeKey: `directCall_${callRef.id}`,
        bellSuppressed: true,
      }),
    );
    return {
      callId: callRef.id,
      status: "ringing",
      expiresAtMillis: expiresAt.toMillis(),
    };
  });
}

async function transitionDirectCall(request, action) {
  const auth = requireAuthentication(request);
  const callId = requireCallId(request);
  const callRef = db.doc(`directCalls/${callId}`);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(callRef);
    const { call, participants } = callContext(snapshot, auth.uid);
    const now = Timestamp.now();
    const expired = (timestampMillis(call.expiresAt) ?? 0) <= now.toMillis();
    let nextStatus;

    if (action === "accept") {
      if (auth.uid !== call.calleeId) {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be answered.",
        );
      }
      // A callable response may be lost after the transaction committed. The
      // desired state is therefore replay-safe for the same authorised actor.
      // `ended` also proves that this ringing call was accepted first.
      if (call.status === "active" || call.status === "ended") {
        return { callId, status: call.status };
      }
      if (call.status !== "ringing") {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be answered.",
        );
      }
      if (expired) {
        throw new HttpsError("deadline-exceeded", "This call has expired.");
      }
      await assertCallPairAvailable(transaction, call, now.toMillis());
      nextStatus = "active";
    } else if (action === "decline") {
      if (auth.uid !== call.calleeId) {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be declined.",
        );
      }
      if (call.status === "declined") return { callId, status: call.status };
      if (call.status !== "ringing") {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be declined.",
        );
      }
      nextStatus = "declined";
    } else if (action === "cancel") {
      if (auth.uid !== call.callerId) {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be cancelled.",
        );
      }
      if (call.status === "cancelled") return { callId, status: call.status };
      if (call.status !== "ringing") {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be cancelled.",
        );
      }
      nextStatus = "cancelled";
    } else if (action === "end") {
      if (call.status !== "active") {
        if (TERMINAL_STATUSES.has(call.status)) {
          return { callId, status: call.status };
        }
        throw new HttpsError(
          "failed-precondition",
          "This call is not active.",
        );
      }
      nextStatus = "ended";
    } else {
      throw new HttpsError("invalid-argument", "Unknown call action.");
    }

    const isActive = nextStatus === "active";
    const expiresAt = isActive
      ? Timestamp.fromMillis(now.toMillis() + ACTIVE_CALL_TTL_MS)
      : call.expiresAt;
    const signalReference = incomingCallReference(call.calleeId, callId);
    const lockReferences = isActive
      ? []
      : participants.map((userId) => callLockReference(userId));
    const transitionSnapshots = await transaction.getAll(
      signalReference,
      ...lockReferences,
    );
    const signalSnapshot = transitionSnapshots[0];
    const lockSnapshots = transitionSnapshots.slice(1);
    transaction.update(callRef, {
      status: nextStatus,
      updatedAt: now,
      expiresAt,
      ...(isActive ? { answeredAt: now } : {}),
      ...(!isActive ? { endedAt: now, endedBy: auth.uid } : {}),
    });
    writeDirectCallStartLedger(
      transaction,
      callId,
      { ...call, updatedAt: now },
      nextStatus,
      expiresAt,
    );
    // The inbox row is a disposable projection, not transition authority. A
    // cleanup or migration that removed it must never prevent hang-up, lock
    // release or LiveKit teardown from committing on the canonical call.
    if (signalSnapshot.exists) {
      transaction.update(signalReference, {
        status: nextStatus,
        updatedAt: now,
        expiresAt,
      });
    }
    transaction.delete(
      notificationReference(call.calleeId, `directCall_${callId}`),
    );

    if (isActive) {
      for (const userId of participants) {
        transaction.set(callLockReference(userId), {
          userId,
          callId,
          status: "active",
          expiresAt,
          updatedAt: now,
        });
      }
    } else {
      for (let index = 0; index < lockReferences.length; index += 1) {
        if (lockSnapshots[index]?.data()?.callId === callId) {
          transaction.delete(lockReferences[index]);
        }
      }
      if (call.status === "active") {
        transaction.set(callControlReference(callId), {
          callId,
          roomName: directCallRoomName(callId),
          participantIds: participants,
          status: "pending",
          attemptCount: 0,
          createdAt: now,
          updatedAt: now,
        });
      }
    }
    return { callId, status: nextStatus };
  });
}

async function authorizeDirectCallVoice(callId, authenticatedUser, transaction) {
  const callRef = db.doc(`directCalls/${callId}`);
  const callSnapshot = await transaction.get(callRef);
  const { call, participants } = callContext(callSnapshot, authenticatedUser.uid);
  if (call.status !== "active") {
    throw new HttpsError(
      "failed-precondition",
      "The other person must answer before voice connects.",
    );
  }
  if ((timestampMillis(call.expiresAt) ?? 0) <= Date.now()) {
    throw new HttpsError("deadline-exceeded", "This call has ended.");
  }
  const otherId = participants.find((uid) => uid !== authenticatedUser.uid);
  const references = [
    db.doc(`users/${authenticatedUser.uid}`),
    db.doc(`users/${otherId}`),
    db.doc(`restrictions/${authenticatedUser.uid}`),
    db.doc(`restrictions/${otherId}`),
    db.doc(`users/${authenticatedUser.uid}/blocked/${otherId}`),
    db.doc(`users/${otherId}/blocked/${authenticatedUser.uid}`),
    db.doc(`friendshipGuards/${authenticatedUser.uid}/friends/${otherId}`),
    db.doc(`friendshipGuards/${otherId}/friends/${authenticatedUser.uid}`),
  ];
  const related = await transaction.getAll(...references);
  const profile = profileData(related[0], "Your");
  profileData(related[1], "The other");
  assertNotRestricted(related[2], "Your", Date.now());
  assertNotRestricted(related[3], "The other", Date.now());
  assertNotBlocked(related[4], related[5]);
  assertCanonicalFriendship(
    related[6],
    related[7],
    authenticatedUser.uid,
    otherId,
  );
  return { call, participants, profile };
}

async function recordAuthorizedDirectCallSession({
  callId,
  authenticatedUser,
  expiresAt,
  nowMs = Date.now(),
  operation = null,
}) {
  const roomName = directCallRoomName(callId);
  return db.runTransaction(async (transaction) => {
    if (operation !== null) {
      const replay = completedOperationReplay(
        await transaction.get(operationLedgerReference(operation.identity)),
        {
          kind: operation.kind,
          uid: authenticatedUser.uid,
          inputHashes: new Set([operation.identity.inputHash]),
          nowMs,
          tokenResult: true,
        },
      );
      if (replay) return { access: null, replay };
    }
    const access = await authorizeDirectCallVoice(
      callId,
      authenticatedUser,
      transaction,
    );
    const sessionReference = activeVoiceSessionReference(
      authenticatedUser.uid,
      roomName,
    );
    const currentSession = await transaction.get(sessionReference);
    const currentWindowStart = currentSession.data()?.tokenWindowStartedAt;
    const currentWindowCount = currentSession.data()?.tokenIssueCount;
    const withinCurrentWindow =
      currentWindowStart instanceof Timestamp &&
      nowMs - currentWindowStart.toMillis() >= 0 &&
      nowMs - currentWindowStart.toMillis() <
        DIRECT_CALL_TOKEN_RATE_WINDOW_MS;
    const tokenIssueCount = withinCurrentWindow &&
        Number.isSafeInteger(currentWindowCount) &&
        currentWindowCount >= 0
      ? currentWindowCount + 1
      : 1;
    if (tokenIssueCount > DIRECT_CALL_TOKEN_RATE_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many call connection attempts. Wait a moment and retry.",
      );
    }
    const tokenWindowStartedAt = withinCurrentWindow
      ? currentWindowStart
      : Timestamp.fromMillis(nowMs);
    const currentExpiry = currentSession.data()?.expiresAt;
    const effectiveExpiry = currentExpiry instanceof Timestamp &&
        currentExpiry.toMillis() > expiresAt.toMillis()
      ? currentExpiry
      : expiresAt;
    writeActiveVoiceSession(transaction, {
      userId: authenticatedUser.uid,
      roomId: roomName,
      expiresAt: effectiveExpiry,
      roomKind: "directCall",
      tokenWindowStartedAt,
      tokenIssueCount,
      tokenLastIssuedAt: Timestamp.fromMillis(nowMs),
    });
    if (operation !== null) {
      transaction.create(
        operationLedgerReference(operation.identity),
        ledgerData({
          kind: operation.kind,
          uid: authenticatedUser.uid,
          requestId: operation.requestId,
          inputHash: operation.identity.inputHash,
          result: operation.result,
          now: Timestamp.fromMillis(nowMs),
        }),
      );
    }
    return { access, replay: null };
  });
}

async function createDirectCallTokenHandler(request, {
  AccessTokenClass = AccessToken,
  apiKey = () => livekitApiKey.value(),
  apiSecret = () => livekitApiSecret.value(),
  serverUrl = () => livekitUrl.value(),
  clock = () => Date.now(),
} = {}) {
  const auth = requireAuthentication(request);
  const callId = requireCallId(request);
  const roomName = directCallRoomName(callId);
  const requestId = request.data?.requestId === undefined ||
      request.data?.requestId === null
    ? null
    : requireRequestId(request.data.requestId);
  const tokenIdentity = requestId === null
    ? null
    : operationIdentity(
      "direct.call.token",
      auth.uid,
      requestId,
      { callId },
    );
  const nowMs = clock();

  try {
    const preflightReplay = await consumeDirectCallAttempt({
      kind: "token",
      uid: auth.uid,
      identity: tokenIdentity,
      operationKind: "direct.call.token",
      inputHashes: tokenIdentity === null
        ? null
        : new Set([tokenIdentity.inputHash]),
      tokenResult: true,
      nowMs,
    });
    if (preflightReplay) return preflightReplay;

    const access = await db.runTransaction((transaction) =>
      authorizeDirectCallVoice(callId, auth, transaction),
    );
    const identity = canonicalIdentity(auth.uid, access.profile);
    const mediaType = requireDirectCallMediaType(access.call.mediaType);
    const canPublishSources = mediaType === "video"
      ? [TrackSource.MICROPHONE, TrackSource.CAMERA]
      : [TrackSource.MICROPHONE];
    const permissions = {
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      hidden: false,
      recorder: false,
    };
    const token = new AccessTokenClass(
      apiKey(),
      apiSecret(),
      {
        identity: auth.uid,
        name: identity.displayName,
        metadata: JSON.stringify({
          uid: auth.uid,
          callId,
          kind: "directCall",
          username: identity.displayName,
          photoUrl: identity.photoUrl,
        }),
        ttl: TOKEN_TTL,
      },
    );
    token.addGrant({
      roomJoin: true,
      room: roomName,
      ...permissions,
      // Never grant screen share to a private call. Audio calls receive only
      // the microphone; video is an explicit server-authored capability.
      canPublishSources,
    });
    const participantToken = await token.toJwt();
    const expiresAt = Timestamp.fromMillis(nowMs + TOKEN_TTL_SECONDS * 1000);
    const result = {
      serverUrl: serverUrl(),
      participantToken,
      token: participantToken,
      roomName,
      participantIdentity: auth.uid,
      participantName: identity.displayName,
      expiresAtMillis: expiresAt.toMillis(),
      permissions: {
        ...permissions,
        canPublishSources: mediaType === "video"
          ? ["microphone", "camera"]
          : ["microphone"],
      },
    };

    // Revalidate the call in the same transaction that publishes the
    // moderation-revocation mirror. A block, sanction or hang-up racing token
    // issuance is observed before the JWT leaves the server.
    const recorded = await recordAuthorizedDirectCallSession({
      callId,
      authenticatedUser: auth,
      expiresAt,
      nowMs,
      operation: tokenIdentity === null ? null : {
        identity: tokenIdentity,
        kind: "direct.call.token",
        requestId,
        result,
      },
    });
    if (recorded.replay) return recorded.replay;

    return result;
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("Failed to create direct call token", {
      callId,
      code: error?.code ?? error?.name ?? "unknown",
    });
    throw new HttpsError(
      "internal",
      "The private voice connection could not be created.",
    );
  }
}

async function expireDirectCall(callDocument, now = Timestamp.now()) {
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(callDocument.ref);
    if (!current.exists) return false;
    const call = current.data() ?? {};
    if (
      !["ringing", "active"].includes(call.status) ||
      (timestampMillis(call.expiresAt) ?? Number.POSITIVE_INFINITY) >
        now.toMillis()
    ) {
      return false;
    }
    const wasRinging = call.status === "ringing";
    const participants = Array.isArray(call.participantIds)
      ? call.participantIds
      : [];
    const signalReference = incomingCallReference(call.calleeId, current.id);
    const lockReferences = participants.map((userId) =>
      callLockReference(userId),
    );
    const expirySnapshots = await transaction.getAll(
      signalReference,
      ...lockReferences,
    );
    const signalSnapshot = expirySnapshots[0];
    const lockSnapshots = expirySnapshots.slice(1);
    transaction.update(current.ref, {
      status: wasRinging ? "missed" : "ended",
      updatedAt: now,
      endedAt: now,
      endedBy: null,
    });
    writeDirectCallStartLedger(
      transaction,
      current.id,
      { ...call, updatedAt: now },
      wasRinging ? "missed" : "ended",
      call.expiresAt,
    );
    if (signalSnapshot.exists) {
      transaction.update(signalReference, {
        status: wasRinging ? "missed" : "ended",
        updatedAt: now,
      });
    }
    transaction.delete(
      notificationReference(call.calleeId, `directCall_${current.id}`),
    );
    if (wasRinging) {
      transaction.set(
        notificationReference(
          call.calleeId,
          missedCallNotificationId(current.id),
        ),
        canonicalNotificationData({
          actorId: call.callerId,
          actorProfile: {
            displayName: call.caller?.displayName,
            photoUrl: call.caller?.photoUrl,
          },
          type: "missedCall",
          targetId: current.id,
          targetLabel: requireDirectCallMediaType(call.mediaType) === "video"
            ? "Missed video call"
            : "Missed voice call",
          dedupeKey: missedCallNotificationId(current.id),
        }),
      );
    } else {
      // Token expiry does not disconnect an already-connected participant.
      // The durable outbox closes the external LiveKit room and session
      // mirrors after the eight-hour server ceiling.
      transaction.set(callControlReference(current.id), {
        callId: current.id,
        roomName: directCallRoomName(current.id),
        participantIds: participants,
        status: "pending",
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      });
    }
    for (let index = 0; index < lockReferences.length; index += 1) {
      if (lockSnapshots[index]?.data()?.callId === current.id) {
        transaction.delete(lockReferences[index]);
      }
    }
    return true;
  });
}

async function expireDirectCallBatch(
  documents,
  now = Timestamp.now(),
  expire = expireDirectCall,
) {
  const failures = [];
  let expired = 0;
  for (const document of documents) {
    try {
      if (await expire(document, now)) expired += 1;
    } catch (error) {
      failures.push({
        callId: normalizeText(document?.id, 128) || "unknown",
        code: normalizeText(error?.code || error?.name, 80) || "unknown",
      });
    }
  }
  return { scanned: documents.length, expired, failures };
}

const startDirectCall = onCall(
  {
    region: REGION,
    // TestFlight/Play internal builds in the current beta cohort were shipped
    // before App Check enforcement was enabled. Turning this on server-first
    // would reject every such install. The transactional caller/callee/pair
    // limiter below is the immediate abuse boundary; enforce App Check only
    // after an attested client build has reached the whole tester cohort.
    enforceAppCheck: false,
    maxInstances: 50,
    minInstances: 1,
  },
  startDirectCallHandler,
);
const acceptDirectCall = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => transitionDirectCall(request, "accept"),
);
const declineDirectCall = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => transitionDirectCall(request, "decline"),
);
const cancelDirectCall = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => transitionDirectCall(request, "cancel"),
);
const endDirectCall = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => transitionDirectCall(request, "end"),
);
const createDirectCallToken = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 50,
    minInstances: 1,
    secrets: [livekitApiKey, livekitApiSecret],
  },
  (request) => createDirectCallTokenHandler(request),
);

const expireDirectCallsSchedule = onSchedule(
  { region: REGION, schedule: "every 1 minutes", timeZone: "UTC" },
  async () => {
    const now = Timestamp.now();
    const snapshots = await Promise.all(
      ["ringing", "active"].map((status) => db.collection("directCalls")
        .where("status", "==", status)
        .where("expiresAt", "<=", now)
        .limit(100)
        .get()),
    );
    let expired = 0;
    let failed = 0;
    for (const snapshot of snapshots) {
      const result = await expireDirectCallBatch(snapshot.docs, now);
      expired += result.expired;
      failed += result.failures.length;
      for (const failure of result.failures) {
        logger.error("Failed to expire direct call", failure);
      }
    }
    logger.info("Expired direct calls", {
      scanned: snapshots.reduce((sum, snapshot) => sum + snapshot.size, 0),
      expired,
      failed,
    });
  },
);

const onDirectCallControlCreated = onDocumentCreated(
  {
    document: "directCallControlOutbox/{callId}",
    region: REGION,
    secrets: LIVEKIT_SECRETS,
    retry: true,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const current = await snapshot.ref.get();
    if (!current.exists || current.data()?.status === "completed") return;
    const data = current.data() ?? {};
    const roomName = normalizeText(data.roomName, 128);
    const participantIds = Array.isArray(data.participantIds)
      ? data.participantIds.filter((uid) => SAFE_ID.test(uid))
      : [];
    if (!roomName || participantIds.length !== 2) {
      await current.ref.set({
        status: "invalid",
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return;
    }
    try {
      await getProductionLiveKitControl().endRoom(roomName);
      await deleteActiveVoiceSessionsForRoom(roomName, participantIds);
      await current.ref.set({
        status: "completed",
        attemptCount: FieldValue.increment(1),
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (error) {
      await current.ref.set({
        status: "retrying",
        attemptCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
        lastErrorCode: normalizeText(error?.code || error?.name, 80) || "unknown",
      }, { merge: true });
      throw error;
    }
  },
);

module.exports = {
  ACTIVE_CALL_TTL_MS,
  DIRECT_CALL_ATTEMPT_LIMITS,
  DIRECT_VIDEO_PROTOCOL_VERSION,
  DIRECT_CALL_START_LIMITS,
  DIRECT_CALL_TOKEN_RATE_LIMIT,
  DIRECT_CALL_TOKEN_RATE_WINDOW_MS,
  MAX_DIRECT_CALL_DEVICE_CAPABILITIES,
  RING_TTL_MS,
  acceptDirectCall,
  assertDirectConversation,
  assertDirectVideoRecipientCompatible,
  authorizeDirectCallVoice,
  assertCanonicalFriendship,
  cancelDirectCall,
  createDirectCallToken,
  createDirectCallTokenHandler,
  consumeDirectCallAttempt,
  declineDirectCall,
  directCallRoomName,
  directCallAttemptRateReference,
  directCallStartLimitReference,
  endDirectCall,
  exactFriendshipGuard,
  expireDirectCall,
  expireDirectCallBatch,
  expireDirectCallsSchedule,
  lockIsActive,
  requireDirectCallMediaType,
  recordAuthorizedDirectCallSession,
  onDirectCallControlCreated,
  startDirectCall,
  startDirectCallHandler,
  transitionDirectCall,
};

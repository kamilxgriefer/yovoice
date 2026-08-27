const { randomUUID } = require("node:crypto");

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions/v2");
const { AccessToken } = require("livekit-server-sdk");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
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
const TERMINAL_STATUSES = new Set([
  "declined",
  "cancelled",
  "ended",
  "missed",
]);

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
    photoUrl: normalizeText(profile.photoUrl, 1000) || null,
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

  const callRef = db.collection("directCalls").doc(
    randomUUID().replaceAll("-", ""),
  );
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
  const conversationRef = db.doc(`conversations/${conversationId}`);
  const signalRef = incomingCallReference(calleeId, callRef.id);
  const notificationRef = notificationReference(
    calleeId,
    `directCall_${callRef.id}`,
  );

  return db.runTransaction(async (transaction) => {
    const now = Timestamp.now();
    const nowMillis = now.toMillis();
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
      status: "ringing",
      createdAt: now,
      updatedAt: now,
      expiresAt,
      answeredAt: null,
      endedAt: null,
      endedBy: null,
    };
    transaction.create(callRef, callData);
    transaction.create(signalRef, {
      callId: callRef.id,
      callerId: auth.uid,
      callerName: caller.displayName,
      callerPhotoUrl: caller.photoUrl,
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
        targetLabel: "Incoming voice call",
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
      if (auth.uid !== call.calleeId || call.status !== "ringing") {
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
      if (auth.uid !== call.calleeId || call.status !== "ringing") {
        throw new HttpsError(
          "failed-precondition",
          "This call cannot be declined.",
        );
      }
      nextStatus = "declined";
    } else if (action === "cancel") {
      if (auth.uid !== call.callerId || call.status !== "ringing") {
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
    transaction.update(callRef, {
      status: nextStatus,
      updatedAt: now,
      expiresAt,
      ...(isActive ? { answeredAt: now } : {}),
      ...(!isActive ? { endedAt: now, endedBy: auth.uid } : {}),
    });
    transaction.update(incomingCallReference(call.calleeId, callId), {
      status: nextStatus,
      updatedAt: now,
      expiresAt,
    });
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
      for (const userId of participants) {
        transaction.delete(callLockReference(userId));
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

async function createDirectCallTokenHandler(request) {
  const auth = requireAuthentication(request);
  const callId = requireCallId(request);
  const roomName = directCallRoomName(callId);

  try {
    const access = await db.runTransaction((transaction) =>
      authorizeDirectCallVoice(callId, auth, transaction),
    );
    const identity = canonicalIdentity(auth.uid, access.profile);
    const permissions = {
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      hidden: false,
      recorder: false,
    };
    const token = new AccessToken(
      livekitApiKey.value(),
      livekitApiSecret.value(),
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
    token.addGrant({ roomJoin: true, room: roomName, ...permissions });
    const participantToken = await token.toJwt();
    const expiresAt = Timestamp.fromMillis(
      Date.now() + TOKEN_TTL_SECONDS * 1000,
    );

    // Revalidate the call in the same transaction that publishes the
    // moderation-revocation mirror. A block, sanction or hang-up racing token
    // issuance is observed before the JWT leaves the server.
    await db.runTransaction(async (transaction) => {
      await authorizeDirectCallVoice(callId, auth, transaction);
      writeActiveVoiceSession(transaction, {
        userId: auth.uid,
        roomId: roomName,
        expiresAt,
        roomKind: "directCall",
      });
    });

    return {
      serverUrl: livekitUrl.value(),
      participantToken,
      token: participantToken,
      roomName,
      participantIdentity: auth.uid,
      participantName: identity.displayName,
      permissions,
    };
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
      call.status !== "ringing" ||
      (timestampMillis(call.expiresAt) ?? Number.POSITIVE_INFINITY) >
        now.toMillis()
    ) {
      return false;
    }
    const participants = Array.isArray(call.participantIds)
      ? call.participantIds
      : [];
    transaction.update(current.ref, {
      status: "missed",
      updatedAt: now,
      endedAt: now,
      endedBy: null,
    });
    transaction.update(incomingCallReference(call.calleeId, current.id), {
      status: "missed",
      updatedAt: now,
    });
    transaction.delete(
      notificationReference(call.calleeId, `directCall_${current.id}`),
    );
    transaction.set(
      notificationReference(call.calleeId, missedCallNotificationId(current.id)),
      canonicalNotificationData({
        actorId: call.callerId,
        actorProfile: {
          displayName: call.caller?.displayName,
          photoUrl: call.caller?.photoUrl,
        },
        type: "missedCall",
        targetId: current.id,
        targetLabel: "Missed voice call",
        dedupeKey: missedCallNotificationId(current.id),
      }),
    );
    for (const userId of participants) {
      transaction.delete(callLockReference(userId));
    }
    return true;
  });
}

const startDirectCall = onCall(
  { region: REGION, enforceAppCheck: false },
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
    secrets: [livekitApiKey, livekitApiSecret],
  },
  createDirectCallTokenHandler,
);

const expireDirectCallsSchedule = onSchedule(
  { region: REGION, schedule: "every 1 minutes", timeZone: "UTC" },
  async () => {
    const now = Timestamp.now();
    const snapshot = await db.collection("directCalls")
      .where("status", "==", "ringing")
      .where("expiresAt", "<=", now)
      .limit(100)
      .get();
    let expired = 0;
    for (const document of snapshot.docs) {
      if (await expireDirectCall(document, now)) expired += 1;
    }
    logger.info("Expired direct calls", { scanned: snapshot.size, expired });
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
  RING_TTL_MS,
  acceptDirectCall,
  assertDirectConversation,
  authorizeDirectCallVoice,
  assertCanonicalFriendship,
  cancelDirectCall,
  createDirectCallToken,
  createDirectCallTokenHandler,
  declineDirectCall,
  directCallRoomName,
  endDirectCall,
  exactFriendshipGuard,
  expireDirectCall,
  expireDirectCallsSchedule,
  lockIsActive,
  onDirectCallControlCreated,
  startDirectCall,
  startDirectCallHandler,
  transitionDirectCall,
};

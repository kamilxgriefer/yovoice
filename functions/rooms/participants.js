const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { randomUUID } = require("node:crypto");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText, roomIsActive } = require("../utils/firestore");
const {
  consumeRateLimit,
  rateLimitReference,
} = require("../integrity/guards");
const {
  canonicalNotificationData,
  notificationReference,
  restrictionIsActive,
} = require("../notifications/canonical");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const {
  activeVoiceSessionReference,
} = require("../livekit/sessions");
const { cleanupRoomMedia } = require("../media/cleanup");

const REGION = "europe-west1";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const ROOM_STATUSES = new Set(["active", "closed", "archived"]);
const ROOM_CONTROL_ATTEMPT_POLICY = Object.freeze({
  maxEvents: 60,
  windowMs: 60_000,
});
const MAX_ROOM_CONTROL_SESSION_MIRRORS = 500;
const MAX_ROOM_CONTROL_PARTICIPANTS = 500;
const CONTROL_PENDING_FIELD = "liveKitTeardownPending";
const CONTROL_COMPLETED_FIELD = "liveKitTeardownCompletedSessionId";
const PARTICIPANT_REVOCATION_FIELD = "roomControlRevocation";
const PARTICIPANT_PERMISSION_PENDING_FIELD = "liveKitPermissionPending";

async function requireActiveCaller(request, authenticated = null) {
  const auth = authenticated ?? requireAuthentication(request);
  const profile = await db.collection("users").doc(auth.uid).get();
  if (
    !profile.exists ||
    profile.data()?.banned === true ||
    profile.data()?.disabled === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active account is required for room control.",
    );
  }
  return { ...auth, profile: profile.data() ?? {} };
}

async function consumeRoomControlAttempt(uid, nowMs = Date.now()) {
  const scope = "room.control.attempt";
  const reference = rateLimitReference(db, scope, uid);
  const now = Timestamp.fromMillis(nowMs);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    consumeRateLimit(transaction, snapshot, {
      reference,
      scope,
      uid,
      nowMs,
      now,
      maxEvents: ROOM_CONTROL_ATTEMPT_POLICY.maxEvents,
      windowMs: ROOM_CONTROL_ATTEMPT_POLICY.windowMs,
    });
  });
}

function sessionGeneration(room) {
  const voiceSessionId = room?.voiceSessionId;
  if (typeof voiceSessionId === "string" && SAFE_DOCUMENT_ID.test(voiceSessionId)) {
    return voiceSessionId;
  }
  const startedAt = room?.voiceStartedAt;
  if (startedAt instanceof Timestamp) return `legacy_${startedAt.toMillis()}`;
  return "legacy";
}

function canonicalTeardownPending(value, roomId, ownerId) {
  if (value === null || value === undefined) return null;
  if (
    typeof value !== "object" ||
    Array.isArray(value) ||
    value.schemaVersion !== 1 ||
    value.roomId !== roomId ||
    value.ownerId !== ownerId ||
    typeof value.operationId !== "string" ||
    !SAFE_DOCUMENT_ID.test(value.operationId) ||
    typeof value.sessionId !== "string" ||
    value.sessionId.length > 160
  ) {
    throw new HttpsError(
      "data-loss",
      "The room control retry state is malformed.",
    );
  }
  return value;
}

function stageRoomTeardown(transaction, roomReference, room, ownerId) {
  const generation = sessionGeneration(room);
  const existing = canonicalTeardownPending(
    room?.[CONTROL_PENDING_FIELD],
    roomReference.id,
    ownerId,
  );
  if (existing?.sessionId === generation) return existing;
  const pending = {
    schemaVersion: 1,
    operationId: randomUUID(),
    ownerId,
    roomId: roomReference.id,
    sessionId: generation,
    createdAt: Timestamp.now(),
  };
  transaction.update(roomReference, {
    [CONTROL_PENDING_FIELD]: pending,
  });
  return pending;
}

async function completeRoomTeardown(roomReference, pending) {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(roomReference);
    if (!snapshot.exists) return;
    const room = snapshot.data() ?? {};
    const current = canonicalTeardownPending(
      room[CONTROL_PENDING_FIELD],
      roomReference.id,
      pending.ownerId,
    );
    if (current?.operationId !== pending.operationId) return;
    transaction.update(roomReference, {
      [CONTROL_PENDING_FIELD]: FieldValue.delete(),
      [CONTROL_COMPLETED_FIELD]: pending.sessionId,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

function canonicalParticipantRevocation(value, roomId, userId) {
  if (value === null || value === undefined) return null;
  if (
    typeof value !== "object" ||
    Array.isArray(value) ||
    value.schemaVersion !== 1 ||
    value.roomId !== roomId ||
    value.userId !== userId ||
    typeof value.operationId !== "string" ||
    !SAFE_DOCUMENT_ID.test(value.operationId) ||
    !["endRoom", "revokeParticipant"].includes(value.action)
  ) {
    throw new HttpsError(
      "data-loss",
      "The participant control retry state is malformed.",
    );
  }
  return value;
}

function stageParticipantRevocation(
  transaction,
  sessionReference,
  sessionSnapshot,
  { roomId, userId, action, hasParticipant },
) {
  const session = sessionSnapshot.exists ? (sessionSnapshot.data() ?? {}) : {};
  const existing = canonicalParticipantRevocation(
    session[PARTICIPANT_REVOCATION_FIELD],
    roomId,
    userId,
  );
  if (existing !== null) return existing;
  if (!hasParticipant && !sessionSnapshot.exists) return null;
  const pending = {
    schemaVersion: 1,
    operationId: randomUUID(),
    roomId,
    userId,
    action,
    createdAt: Timestamp.now(),
  };
  transaction.set(sessionReference, {
    userId,
    roomId,
    participantIdentity: userId,
    expiresAt: session.expiresAt instanceof Timestamp
      ? session.expiresAt
      : Timestamp.fromMillis(Date.now() + 5 * 60_000),
    [PARTICIPANT_REVOCATION_FIELD]: pending,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return pending;
}

async function completeParticipantRevocation(sessionReference, pending) {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionReference);
    if (!snapshot.exists) return;
    const current = canonicalParticipantRevocation(
      snapshot.data()?.[PARTICIPANT_REVOCATION_FIELD],
      pending.roomId,
      pending.userId,
    );
    // A newly-issued token replaces the whole active-session document and
    // therefore removes this marker. Never let an old completion delete that
    // newer session.
    if (current?.operationId !== pending.operationId) return;
    transaction.delete(sessionReference);
  });
}

function canonicalPermissionPending(value, roomId, userId) {
  if (value === null || value === undefined) return null;
  if (
    typeof value !== "object" ||
    Array.isArray(value) ||
    value.schemaVersion !== 1 ||
    value.roomId !== roomId ||
    value.userId !== userId ||
    typeof value.operationId !== "string" ||
    !SAFE_DOCUMENT_ID.test(value.operationId) ||
    typeof value.canPublish !== "boolean" ||
    typeof value.canPublishData !== "boolean"
  ) {
    throw new HttpsError(
      "data-loss",
      "The participant permission retry state is malformed.",
    );
  }
  return value;
}

function stagePermissionUpdate(
  transaction,
  participantReference,
  participant,
  { roomId, userId, permissions },
) {
  const existing = canonicalPermissionPending(
    participant[PARTICIPANT_PERMISSION_PENDING_FIELD],
    roomId,
    userId,
  );
  if (
    existing?.canPublish === permissions.canPublish &&
    existing?.canPublishData === permissions.canPublishData
  ) {
    return existing;
  }
  const pending = {
    schemaVersion: 1,
    operationId: randomUUID(),
    roomId,
    userId,
    canPublish: permissions.canPublish,
    canPublishData: permissions.canPublishData,
    createdAt: Timestamp.now(),
  };
  transaction.update(participantReference, {
    [PARTICIPANT_PERMISSION_PENDING_FIELD]: pending,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return pending;
}

async function completePermissionUpdate(participantReference, pending) {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(participantReference);
    if (!snapshot.exists) return;
    const current = canonicalPermissionPending(
      snapshot.data()?.[PARTICIPANT_PERMISSION_PENDING_FIELD],
      pending.roomId,
      pending.userId,
    );
    if (current?.operationId !== pending.operationId) return;
    transaction.update(participantReference, {
      [PARTICIPANT_PERMISSION_PENDING_FIELD]: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function prepareRoomCleanup(roomReference, roomId, userIds = []) {
  const identities = [...new Set(userIds)]
    .map((value) => normalizeText(value, 128))
    .filter((value) => SAFE_DOCUMENT_ID.test(value));
  if (identities.length > MAX_ROOM_CONTROL_SESSION_MIRRORS) {
    throw new HttpsError(
      "resource-exhausted",
      "The room voice-session graph exceeds the safe cleanup bound.",
    );
  }
  const [sessionSnapshot, participantSnapshot] = await Promise.all([
    db.collectionGroup("rooms")
      .where("roomId", "==", roomId)
      .limit(MAX_ROOM_CONTROL_SESSION_MIRRORS + 1)
      .get(),
    roomReference.collection("participants")
      .limit(MAX_ROOM_CONTROL_PARTICIPANTS + 1)
      .get(),
  ]);
  if (sessionSnapshot.size > MAX_ROOM_CONTROL_SESSION_MIRRORS) {
    throw new HttpsError(
      "resource-exhausted",
      "The room voice-session graph exceeds the safe cleanup bound.",
    );
  }
  if (participantSnapshot.size > MAX_ROOM_CONTROL_PARTICIPANTS) {
    throw new HttpsError(
      "resource-exhausted",
      "The room roster exceeds the safe cleanup bound.",
    );
  }
  const references = new Map();
  for (const userId of identities) {
    const reference = activeVoiceSessionReference(userId, roomId);
    references.set(reference.path, reference);
  }
  for (const document of sessionSnapshot.docs) {
    const segments = document.ref.path.split("/");
    const data = document.data() ?? {};
    if (
      segments.length === 4 &&
      segments[0] === "activeVoiceSessions" &&
      segments[2] === "rooms" &&
      document.id === roomId &&
      data.roomId === roomId &&
      data.userId === segments[1] &&
      data.participantIdentity === segments[1]
    ) {
      references.set(document.ref.path, document.ref);
    }
  }
  if (references.size > MAX_ROOM_CONTROL_SESSION_MIRRORS) {
    throw new HttpsError(
      "resource-exhausted",
      "The room voice-session graph exceeds the safe cleanup bound.",
    );
  }
  return {
    participantReferences: participantSnapshot.docs.map(
      (document) => document.ref,
    ),
    sessionReferences: [...references.values()],
  };
}

async function deleteReferencesBounded(references) {
  for (let index = 0; index < references.length; index += 450) {
    const batch = db.batch();
    for (const reference of references.slice(index, index + 450)) {
      batch.delete(reference);
    }
    await batch.commit();
  }
}

async function applyRoomCleanup(cleanup) {
  await deleteReferencesBounded(cleanup.sessionReferences);
  await deleteReferencesBounded(cleanup.participantReferences);
}

async function requireHostRoom(transaction, roomReference, uid) {
  const snapshot = await transaction.get(roomReference);
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "The room no longer exists.");
  }
  const room = snapshot.data() ?? {};
  if (room.hostId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the room host can manage this room.",
    );
  }
  return room;
}

async function recursiveDelete(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
    return;
  }
  const snapshot = await reference.limit(250).get();
  if (snapshot.empty) return;
  const batch = db.batch();
  for (const document of snapshot.docs) batch.delete(document.ref);
  await batch.commit();
  if (snapshot.size === 250) await recursiveDelete(reference);
}

/** Host-only participant removal with the roster and counter in one Admin
 * transaction. Rules can verify a self-leave by uid, but cannot discover an
 * arbitrary participant id changed elsewhere in a host batch, so this path is
 * the counter authority for moderation removals. */
async function executeRemoveRoomParticipant(
  request,
  roomControl = null,
) {
    const authenticated = requireAuthentication(request);
    const roomId = normalizeText(request.data?.roomId, 128);
    const participantId = normalizeText(request.data?.participantId, 128);
    if (!SAFE_DOCUMENT_ID.test(roomId) || !SAFE_DOCUMENT_ID.test(participantId)) {
      throw new HttpsError(
        "invalid-argument",
        "Valid roomId and participantId values are required.",
      );
    }
    if (participantId === authenticated.uid) {
      throw new HttpsError(
        "failed-precondition",
        "Use Leave Room to remove your own participant.",
      );
    }
    await consumeRoomControlAttempt(authenticated.uid);
    const auth = await requireActiveCaller(request, authenticated);

    const roomReference = db.collection("rooms").doc(roomId);
    const participantReference = roomReference
      .collection("participants")
      .doc(participantId);
    const sessionReference = activeVoiceSessionReference(
      participantId,
      roomId,
    );

    const outcome = await db.runTransaction(async (transaction) => {
      const [roomSnapshot, participantSnapshot, sessionSnapshot] =
        await transaction.getAll(
        roomReference,
        participantReference,
        sessionReference,
      );
      if (!roomSnapshot.exists) {
        throw new HttpsError("not-found", "The room no longer exists.");
      }
      const room = roomSnapshot.data() ?? {};
      if (room.hostId !== auth.uid) {
        throw new HttpsError(
          "permission-denied",
          "Only the room host can remove participants.",
        );
      }
      if (!roomIsActive(room) || room.isLive !== true ||
          room.deletionInProgress === true) {
        throw new HttpsError(
          "failed-precondition",
          "Participants can only be removed from a live active room.",
        );
      }
      const participant = participantSnapshot.exists
        ? (participantSnapshot.data() ?? {})
        : {};
      if (participantSnapshot.exists &&
          (participant.userId === room.hostId || participantId === room.hostId)) {
        throw new HttpsError(
          "failed-precondition",
          "The room host cannot be removed.",
        );
      }

      if (participantSnapshot.exists) {
        transaction.delete(participantReference);
        transaction.update(roomReference, {
          participantCount: Math.max(
            Number(room.participantCount ?? 0) - 1,
            0,
          ),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return {
        pending: stageParticipantRevocation(
          transaction,
          sessionReference,
          sessionSnapshot,
          {
            roomId,
            userId: participantId,
            action: "revokeParticipant",
            hasParticipant: participantSnapshot.exists,
          },
        ),
        removed: participantSnapshot.exists,
      };
    });

    if (outcome.pending !== null) {
      await (roomControl ?? getProductionLiveKitControl())
        .revokeParticipant(roomId, participantId);
      await completeParticipantRevocation(
        sessionReference,
        outcome.pending,
      );
    }

    return {
      success: true,
      roomId,
      participantId,
      removed: outcome.removed,
    };
}

const CALLABLE_OPTIONS = {
  region: REGION,
  enforceAppCheck: false,
  secrets: LIVEKIT_SECRETS,
  timeoutSeconds: 120,
};

// firebase-functions v2 invokes every onCall handler as handler(request,
// responseProxy). A multi-parameter execute* function must therefore never be
// registered directly: the streaming response proxy would land in its
// dependency-injection parameter and shadow the production LiveKit control.
// Register one-argument wrappers only; tests keep injecting explicitly.
const removeRoomParticipantSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeRemoveRoomParticipant(request),
);

/**
 * Participant self-leave is server-authoritative so deleting the Firestore
 * row cannot leave an already-issued LiveKit identity connected. The roster,
 * root counter and active-session mirror move atomically; control-plane
 * revocation happens immediately afterwards and is safe to retry.
 *
 * THE LAST PERSON OUT ENDS THE VOICE SESSION — IN EVERY ROOM, NOT ONLY A
 * LOUNGE. This used to drop `isLive` for `roomKind == 'clubLounge'` and for
 * nothing else, which was survivable only because nothing in the app ever
 * set `isLive: true` on an ordinary room. The moment the client can start
 * one, the omission becomes a permanent stuck state: a Community room whose
 * host opted into `membersCanStartVoice`, started by a MEMBER who then
 * leaves last, has no other exit — `endRoomVoiceSelf` is host-only and there
 * is no scheduled sweeper — so it stays `isLive: true, participantCount: 0`
 * and keeps advertising itself on `watchLivePublicRooms` (Home, Discover) as
 * a live room nobody is in.
 *
 * THE ROSTER, NOT THE COUNTER, IS WHAT PROVES A ROOM IS EMPTY on the new
 * branch. `participantCount` is a denormalised field maintained by several
 * writers, and a stale-LOW value would turn one person's leave into an
 * eviction of everyone still talking — `endRoom()` disconnects the LiveKit
 * room for all of them. Re-reading the roster inside the same transaction
 * costs one small query and removes that failure mode entirely; it is read
 * before any write in the transaction because the Admin SDK refuses a read
 * that follows one.
 *
 * THE LOUNGE BRANCH IS UNCHANGED, deliberately: `isClubLounge && nextCount
 * === 0` is character-for-character what it was, because the client's own
 * lounge leave path (`roomParticipantLeaveRootExists` in firestore.rules)
 * mirrors that exact transition and the two must not drift.
 */

/**
 * The single answer to "may this participant publish audio?", shared by the
 * moderation path and the self-mute path so the two cannot drift.
 *
 * Mirrors `deriveVoiceGrant` in ../livekit/token.js, which computes the same
 * thing when the token is minted. A participant's OWN mute is not an input:
 * only a moderator mute, a server mute or a sanction removes publishing.
 * Outside a broadcast room every participant may speak without promotion,
 * because self-service joins are pinned to `role: 'listener'` by the rules.
 */
function publishAllowed({
  role,
  room,
  hostMuted,
  serverMuted,
  communicationMuted,
}) {
  const experience = String(room?.experience ?? "community");
  const broadcast = experience === "broadcast" || experience === "podcast";
  const maySpeak = role === "host" || role === "speaker" || !broadcast;
  return maySpeak && !hostMuted && !serverMuted && !communicationMuted;
}

async function executeLeaveRoom(request, roomControl = null) {
  const authenticated = requireAuthentication(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A valid room is required.");
  }
  await consumeRoomControlAttempt(authenticated.uid);
  const auth = await requireActiveCaller(request, authenticated);
  const roomReference = db.collection("rooms").doc(roomId);
  const participantReference = roomReference
    .collection("participants")
    .doc(auth.uid);
  const sessionReference = activeVoiceSessionReference(auth.uid, roomId);
  // limit(2) is all the question needs: the caller's own row is still visible
  // to a transactional read, so "anyone else here?" is answered by the first
  // document that is not theirs.
  const rosterProbe = roomReference.collection("participants").limit(2);
  const outcome = await db.runTransaction(async (transaction) => {
    const [roomSnapshot, participantSnapshot, sessionSnapshot] =
      await transaction.getAll(
      roomReference,
      participantReference,
      sessionReference,
    );
    if (!roomSnapshot.exists) {
      if (participantSnapshot.exists) {
        const orphan = participantSnapshot.data() ?? {};
        if (orphan.userId !== auth.uid) {
          throw new HttpsError(
            "permission-denied",
            "The participant identity is not canonical.",
          );
        }
        transaction.delete(participantReference);
      }
      const pending = stageParticipantRevocation(
          transaction,
          sessionReference,
          sessionSnapshot,
          {
            roomId,
            userId: auth.uid,
            action: "revokeParticipant",
            hasParticipant: participantSnapshot.exists,
          },
        );
      return {
        endedVoiceSession: pending?.action === "endRoom",
        pending,
      };
    }
    const room = roomSnapshot.data() ?? {};
    if (
      room.hostId === auth.uid &&
      room.roomType === "temporary" &&
      !room.clubId
    ) {
      throw new HttpsError(
        "failed-precondition",
        "A temporary-room host must end the room for everyone.",
      );
    }

    const roster = participantSnapshot.exists
      ? await transaction.get(rosterProbe)
      : null;

    if (!participantSnapshot.exists) {
      const pending = stageParticipantRevocation(
          transaction,
          sessionReference,
          sessionSnapshot,
          {
            roomId,
            userId: auth.uid,
            action: "revokeParticipant",
            hasParticipant: false,
          },
        );
      return {
        endedVoiceSession: pending?.action === "endRoom",
        pending,
      };
    }
    const participant = participantSnapshot.data() ?? {};
    if (participant.userId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "The participant identity is not canonical.",
      );
    }

    const currentCount = Math.max(Number(room.participantCount ?? 0), 0);
    const nextCount = Math.max(currentCount - 1, 0);
    const isClubLounge = room.roomKind === "clubLounge" && !!room.clubId;
    // Legacy documents carry neither `status` nor `deletionInProgress`;
    // default them the way firestore.rules' own `.get(field, default)` reads
    // do, or 24 of the 45 production rooms would never qualify.
    const voiceIsRunning =
      room.isLive === true &&
      roomIsActive(room) &&
      room.deletionInProgress !== true;
    const rosterIsEmptyAfterLeave = !(roster?.docs ?? []).some(
      (document) => document.id !== auth.uid,
    );
    const endedVoiceSession =
      nextCount === 0 &&
      (isClubLounge || (voiceIsRunning && rosterIsEmptyAfterLeave));
    transaction.delete(participantReference);
    transaction.update(roomReference, {
      participantCount: nextCount,
      ...(endedVoiceSession
        ? {
            isLive: false,
            endedAt: FieldValue.serverTimestamp(),
          }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      endedVoiceSession,
      pending: stageParticipantRevocation(
        transaction,
        sessionReference,
        sessionSnapshot,
        {
          roomId,
          userId: auth.uid,
          action: endedVoiceSession ? "endRoom" : "revokeParticipant",
          hasParticipant: true,
        },
      ),
    };
  });

  if (outcome.pending !== null) {
    const control = roomControl ?? getProductionLiveKitControl();
    if (outcome.pending.action === "endRoom") {
      const cleanup = await prepareRoomCleanup(
        roomReference,
        roomId,
        [auth.uid],
      );
      await control.endRoom(roomId);
      await applyRoomCleanup(cleanup);
    } else {
      await control.revokeParticipant(roomId, auth.uid);
      await completeParticipantRevocation(sessionReference, outcome.pending);
    }
  }
  return {
    success: true,
    roomId,
    endedVoiceSession: outcome.endedVoiceSession,
  };
}

const leaveRoomSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeLeaveRoom(request),
);

async function executeSetRoomStatus(
  request,
  roomControl = null,
) {
  const authenticated = requireAuthentication(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const status = normalizeText(request.data?.status, 32);
  if (!SAFE_DOCUMENT_ID.test(roomId) || !ROOM_STATUSES.has(status)) {
    throw new HttpsError("invalid-argument", "A valid room and status are required.");
  }
  await consumeRoomControlAttempt(authenticated.uid);
  const auth = await requireActiveCaller(request, authenticated);
  const roomReference = db.collection("rooms").doc(roomId);
  const pending = await db.runTransaction(async (transaction) => {
    const room = await requireHostRoom(
      transaction,
      roomReference,
      auth.uid,
    );
    if (!ROOM_STATUSES.has(String(room.status ?? "active")) ||
        room.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "A moderated or deleting room cannot be restored by its host.",
      );
    }
    const existing = canonicalTeardownPending(
      room[CONTROL_PENDING_FIELD],
      roomId,
      auth.uid,
    );
    if (status === "active" && existing !== null) {
      throw new HttpsError(
        "failed-precondition",
        "The current voice teardown must finish before restoring the room.",
      );
    }
    const generation = sessionGeneration(room);
    const needsTeardown = status !== "active" && (
      existing !== null ||
      room.isLive === true ||
      Number(room.participantCount ?? 0) > 0 ||
      room[CONTROL_COMPLETED_FIELD] !== generation
    );
    const staged = needsTeardown
      ? stageRoomTeardown(transaction, roomReference, room, auth.uid)
      : null;
    transaction.update(roomReference, {
      status,
      ...(status === "active"
        ? {}
        : {
            isLive: false,
            participantCount: 0,
            endedAt: FieldValue.serverTimestamp(),
          }),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return staged;
  });
  if (pending !== null) {
    const cleanup = await prepareRoomCleanup(roomReference, roomId);
    await (roomControl ?? getProductionLiveKitControl()).endRoom(roomId);
    await applyRoomCleanup(cleanup);
    await completeRoomTeardown(roomReference, pending);
  }
  return { success: true, roomId, status };
}

const setRoomStatusSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeSetRoomStatus(request),
);

/**
 * The host's "end the session for everyone" control — and, when the caller
 * asks for it, the teardown a leave performs on its way out.
 *
 * DEFAULT BEHAVIOUR IS UNCHANGED AND DELIBERATE. A host ending their own room
 * ends it for the people in it; that is what the control means, and adding a
 * "somebody else is still here" refusal would break the one lever a host has
 * over their own room.
 *
 * `onlyIfEmpty` EXISTS BECAUSE THE CLIENT ALSO CALLS THIS ON LEAVE.
 * room_service.dart's `shouldEndVoiceOnLeaving()` reads `participantCount`,
 * concludes "I am the last one", and then calls this callable — so a join
 * landing in between, or a counter that is merely stale-low, silently evicts
 * a real participant from a live room and recursive-deletes their roster row.
 *
 * The reviewed suggestion was an `expectedParticipantCount` precondition.
 * That is rejected: it makes a CLIENT-SUPPLIED count authoritative, it adds
 * no authority the host does not already have, and it fails LOUDLY — a host
 * whose count moved would get `failed-precondition` from the one control that
 * ends a room, stranding it `isLive: true` with nobody in it, which is
 * precisely the defect `executeLeaveRoom` above exists to stop creating.
 *
 * What the caller actually means is "end this only if it is really empty",
 * and the server can answer that itself: re-read the roster inside the
 * transaction. An occupied room is then left exactly as it was and the call
 * returns `{ ended: false }` — a SUCCESS, because a leave must never surface
 * as a failure, and because the room is still live for a good reason rather
 * than being stranded.
 */
async function executeEndRoomVoice(
  request,
  roomControl = null,
) {
  const authenticated = requireAuthentication(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const onlyIfEmpty = request.data?.onlyIfEmpty === true;
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A valid room is required.");
  }
  await consumeRoomControlAttempt(authenticated.uid);
  const auth = await requireActiveCaller(request, authenticated);
  const roomReference = db.collection("rooms").doc(roomId);
  // Two rows are enough to distinguish "nobody but the caller" from "somebody
  // else is here". The caller's own row may or may not still exist: the client
  // leave path calls this AFTER `leaveRoomSelf` has removed it, while a direct
  // caller still holds one. Filtering the caller's own id below covers both,
  // so an empty roster and a roster holding only the caller read the same.
  const rosterProbe = roomReference.collection("participants").limit(2);
  const outcome = await db.runTransaction(async (transaction) => {
    const room = await requireHostRoom(transaction, roomReference, auth.uid);
    if (!roomIsActive(room) || room.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "Only an active room can end its voice session.",
      );
    }
    const existing = canonicalTeardownPending(
      room[CONTROL_PENDING_FIELD],
      roomId,
      auth.uid,
    );
    if (existing === null && room.isLive !== true) {
      return { ended: false, pending: null };
    }
    if (onlyIfEmpty && existing === null) {
      const roster = await transaction.get(rosterProbe);
      const othersRemain = roster.docs.some(
        (document) => document.id !== auth.uid,
      );
      if (othersRemain) return { ended: false, pending: null };
    }
    const pending = stageRoomTeardown(
      transaction,
      roomReference,
      room,
      auth.uid,
    );
    transaction.update(roomReference, {
      isLive: false,
      participantCount: 0,
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ended: true, pending };
  });
  if (!outcome.ended) return { success: true, roomId, ended: false };
  const cleanup = await prepareRoomCleanup(roomReference, roomId);
  await (roomControl ?? getProductionLiveKitControl()).endRoom(roomId);
  await applyRoomCleanup(cleanup);
  await completeRoomTeardown(roomReference, outcome.pending);
  return { success: true, roomId, ended: true };
}

const endRoomVoiceSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeEndRoomVoice(request),
);

async function executeDeleteRoom(
  request,
  roomControl = null,
  storageBucket = null,
) {
  const authenticated = requireAuthentication(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A valid room is required.");
  }
  await consumeRoomControlAttempt(authenticated.uid);
  const auth = await requireActiveCaller(request, authenticated);
  const roomReference = db.collection("rooms").doc(roomId);
  const pending = await db.runTransaction(async (transaction) => {
    const room = await requireHostRoom(transaction, roomReference, auth.uid);
    if (room.roomKind === "clubLounge" || room.clubId) {
      throw new HttpsError(
        "failed-precondition",
        "A Club Lounge is deleted through the Club lifecycle.",
      );
    }
    if (!ROOM_STATUSES.has(String(room.status ?? "active"))) {
      throw new HttpsError(
        "failed-precondition",
        "A moderated room cannot be deleted by its host.",
      );
    }
    const generation = sessionGeneration(room);
    const existing = canonicalTeardownPending(
      room[CONTROL_PENDING_FIELD],
      roomId,
      auth.uid,
    );
    const staged = existing !== null ||
      room[CONTROL_COMPLETED_FIELD] !== generation
      ? stageRoomTeardown(transaction, roomReference, room, auth.uid)
      : null;
    transaction.update(roomReference, {
      status: "closed",
      isLive: false,
      participantCount: 0,
      deletionInProgress: true,
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return staged;
  });
  if (pending !== null) {
    const cleanup = await prepareRoomCleanup(roomReference, roomId);
    await (roomControl ?? getProductionLiveKitControl()).endRoom(roomId);
    await applyRoomCleanup(cleanup);
    await completeRoomTeardown(roomReference, pending);
  }
  const mediaCleanup = await cleanupRoomMedia({
    roomId,
    bucket: storageBucket ?? getStorage().bucket(),
  });
  if (mediaCleanup.deleted !== true) {
    throw new HttpsError(
      "unavailable",
      "Room media cleanup did not complete. Retry the deletion.",
    );
  }
  await recursiveDelete(roomReference);
  return { success: true, roomId };
}

const deleteRoomSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeDeleteRoom(request),
);

async function executeModerateRoomParticipant(
  request,
  roomControl = null,
) {
  const authenticated = requireAuthentication(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const participantId = normalizeText(request.data?.participantId, 128);
  const hasMuted = typeof request.data?.isMuted === "boolean";
  const hasSpeaker = typeof request.data?.isSpeaker === "boolean";
  const lowerHand = request.data?.lowerHand === true;
  if (
    !SAFE_DOCUMENT_ID.test(roomId) ||
    !SAFE_DOCUMENT_ID.test(participantId) ||
    (!hasMuted && !hasSpeaker && !lowerHand)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "A room, participant and moderation action are required.",
    );
  }
  await consumeRoomControlAttempt(authenticated.uid);
  const auth = await requireActiveCaller(request, authenticated);
  const roomReference = db.collection("rooms").doc(roomId);
  const participantReference = roomReference
    .collection("participants")
    .doc(participantId);
  const restrictionReference = db.collection("restrictions").doc(participantId);
  const pending = await db.runTransaction(async (transaction) => {
    const [room, participantSnapshot, restrictionSnapshot] =
      await Promise.all([
        requireHostRoom(transaction, roomReference, auth.uid),
        transaction.get(participantReference),
        transaction.get(restrictionReference),
      ]);
    if (!participantSnapshot.exists) {
      throw new HttpsError("not-found", "The participant is no longer here.");
    }
    if (!roomIsActive(room) || room.isLive !== true ||
        room.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "Only a live active room can be moderated by its host.",
      );
    }
    if (participantId === room.hostId &&
        ((hasMuted && request.data.isMuted) ||
         (hasSpeaker && !request.data.isSpeaker))) {
      throw new HttpsError(
        "failed-precondition",
        "The room host must remain on stage and cannot be moderator-muted.",
      );
    }
    const participant = participantSnapshot.data() ?? {};
    const restriction = restrictionSnapshot.exists
      ? (restrictionSnapshot.data() ?? {})
      : {};
    const expiresAt = restriction.expiresAt;
    const communicationMuted = restriction.type === "communicationMute" &&
      (expiresAt == null ||
       (expiresAt instanceof Timestamp && expiresAt.toMillis() > Date.now()));
    const promotingToSpeaker = hasSpeaker &&
      request.data.isSpeaker === true &&
      participant.isSpeaker !== true &&
      participant.role !== "speaker" &&
      participant.role !== "host" &&
      participantId !== room.hostId;
    if (promotingToSpeaker) {
      const targetProfileReference = db.doc(`users/${participantId}`);
      const hostRestrictionReference = db.doc(`restrictions/${auth.uid}`);
      const hostBlockReference = db.doc(
        `users/${auth.uid}/blocked/${participantId}`,
      );
      const participantBlockReference = db.doc(
        `users/${participantId}/blocked/${auth.uid}`,
      );
      const notificationType = room.experience === "broadcast"
        ? "broadcastInvite"
        : "roomInvite";
      const inviteNotificationReference = notificationReference(
        participantId,
        `${notificationType}_${roomId}_${participantId}`,
      );
      const [
        targetProfile,
        hostRestriction,
        hostBlock,
        participantBlock,
        notification,
      ] =
        await transaction.getAll(
          targetProfileReference,
          hostRestrictionReference,
          hostBlockReference,
          participantBlockReference,
          inviteNotificationReference,
        );
      const target = targetProfile.exists ? (targetProfile.data() ?? {}) : {};
      if (
        !targetProfile.exists ||
        target.banned === true ||
        target.disabled === true ||
        restrictionIsActive(hostRestriction.data()) ||
        communicationMuted ||
        hostBlock.exists ||
        participantBlock.exists
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This participant cannot be invited to the stage.",
        );
      }
      if (!notification.exists) {
        transaction.set(
          inviteNotificationReference,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: auth.profile,
            type: notificationType,
            targetId: roomId,
            targetLabel:
              typeof room.name === "string" ? room.name : "Voice room",
            dedupeKey: `${notificationType}_${roomId}_${participantId}`,
          }),
        );
      }
    }
    const update = {};
    const muteChanged = hasMuted &&
      participant.hostMuted !== request.data.isMuted;
    if (muteChanged) {
      update.hostMuted = request.data.isMuted;
    }
    const requestedRole = participantId === room.hostId
      ? "host"
      : (request.data.isSpeaker ? "speaker" : "listener");
    const speakerChanged = hasSpeaker && (
      participant.role !== requestedRole ||
      participant.isSpeaker !== request.data.isSpeaker ||
      participant.isHandRaised === true
    );
    if (speakerChanged) {
      update.role = requestedRole;
      update.isSpeaker = request.data.isSpeaker;
      update.isHandRaised = false;
    }
    const handChanged = lowerHand && participant.isHandRaised === true;
    if (handChanged) update.isHandRaised = false;
    const stateChanged = muteChanged || speakerChanged || handChanged;
    const existingPending = canonicalPermissionPending(
      participant[PARTICIPANT_PERMISSION_PENDING_FIELD],
      roomId,
      participantId,
    );

    const role = update.role ?? participant.role ?? "listener";
    const hostMuted = update.hostMuted ?? (participant.hostMuted === true);
    const serverMuted = participant.serverMuted === true;
    const resulting = {
      // `isMuted` — the participant's OWN mute — is deliberately absent.
      // See deriveVoiceGrant in ../livekit/token.js: a self-mute is a track
      // state, and folding it into the permission is what left people unable
      // to unmute themselves. A MODERATOR mute is `hostMuted`, and that one
      // does revoke publishing, which is the whole point of this callable.
      canPublish: publishAllowed({
        role,
        room,
        hostMuted,
        serverMuted,
        communicationMuted,
      }),
      canPublishData: !communicationMuted,
    };
    if (!stateChanged && existingPending === null) return null;
    if (stateChanged) {
      transaction.update(participantReference, {
        ...update,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return stagePermissionUpdate(
      transaction,
      participantReference,
      participant,
      {
        roomId,
        userId: participantId,
        permissions: resulting,
      },
    );
  });

  if (pending === null) {
    return { success: true, roomId, participantId, updated: false };
  }
  const control = roomControl ?? getProductionLiveKitControl();
  if (typeof control.setParticipantPermissions === "function") {
    await control.setParticipantPermissions(roomId, participantId, {
      canPublish: pending.canPublish,
      canPublishData: pending.canPublishData,
    });
  } else {
    await control.setPublishingAllowed(
      roomId,
      participantId,
      pending.canPublish,
    );
  }
  await completePermissionUpdate(participantReference, pending);
  return { success: true, roomId, participantId, updated: true };
}

const moderateRoomParticipantSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeModerateRoomParticipant(request),
);

async function executeSetOwnParticipantMute(
  request,
  _roomControl = null,
) {
  const authenticated = requireAuthentication(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const isMuted = request.data?.isMuted;
  if (!SAFE_DOCUMENT_ID.test(roomId) || typeof isMuted !== "boolean") {
    throw new HttpsError(
      "invalid-argument",
      "A valid room and mute state are required.",
    );
  }
  const auth = await requireActiveCaller(request, authenticated);
  const roomReference = db.collection("rooms").doc(roomId);
  const participantReference = roomReference
    .collection("participants")
    .doc(auth.uid);
  await db.runTransaction(async (transaction) => {
    const [roomSnapshot, participantSnapshot] =
      await transaction.getAll(
        roomReference,
        participantReference,
      );
    if (!roomSnapshot.exists || !participantSnapshot.exists) {
      throw new HttpsError("not-found", "The room participant no longer exists.");
    }
    const room = roomSnapshot.data() ?? {};
    const participant = participantSnapshot.data() ?? {};
    if (!roomIsActive(room) || room.isLive !== true ||
        room.deletionInProgress === true || participant.userId !== auth.uid) {
      throw new HttpsError(
        "failed-precondition",
        "Mute can only change for your active voice participant.",
      );
    }
    transaction.update(participantReference, {
      isMuted,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  // Self-mute is a local track state, not a publishing permission. Calling
  // the LiveKit control plane here added a full extra network round trip to
  // every tap and could not make the local microphone any more muted. Host
  // and staff mutes keep their own permission-revocation path above.
  return { success: true, roomId, isMuted };
}

const setOwnRoomParticipantMute = onCall(CALLABLE_OPTIONS, (request) =>
  executeSetOwnParticipantMute(request),
);

module.exports = {
  ROOM_CONTROL_ATTEMPT_POLICY,
  deleteRoomSelf,
  endRoomVoiceSelf,
  executeDeleteRoom,
  executeEndRoomVoice,
  executeLeaveRoom,
  executeModerateRoomParticipant,
  executeRemoveRoomParticipant,
  executeSetOwnParticipantMute,
  executeSetRoomStatus,
  moderateRoomParticipantSelf,
  requireActiveCaller,
  leaveRoomSelf,
  removeRoomParticipantSelf,
  setOwnRoomParticipantMute,
  setRoomStatusSelf,
};

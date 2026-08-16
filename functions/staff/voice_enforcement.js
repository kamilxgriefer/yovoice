const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db, normalizeText } = require("../utils/firestore");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");

const REGION = "europe-west1";
const EVENT_COLLECTION = "moderationVoiceEnforcement";
const EVENT_TYPES = Object.freeze({
  BAN: "ban",
  COMMUNICATION_MUTE: "communicationMute",
});
const SUPPORTED_EVENT_TYPES = new Set(Object.values(EVENT_TYPES));
const CONTROL_BATCH_SIZE = 10;
const ACTIVE_VOICE_SESSIONS = "activeVoiceSessions";

function validTargetUid(value) {
  const uid = normalizeText(value, 128);
  return uid && !uid.includes("/") ? uid : null;
}

/**
 * Adds a trusted voice-revocation event to an existing Firestore batch.
 * The caller writes the ban/restriction in the same batch, so there is no
 * crash window where the durable sanction exists without a retryable
 * control-plane job (or the reverse).
 */
function enqueueVoiceEnforcement(
  batch,
  { targetUid, type, requestedBy, source },
) {
  const uid = validTargetUid(targetUid);
  if (!batch || typeof batch.set !== "function") {
    throw new Error("A Firestore WriteBatch is required.");
  }
  if (!uid || !SUPPORTED_EVENT_TYPES.has(type)) {
    throw new Error("A valid voice enforcement event is required.");
  }

  const reference = db.collection(EVENT_COLLECTION).doc();
  batch.set(reference, {
    targetUid: uid,
    type,
    requestedBy: normalizeText(requestedBy, 128) || null,
    source: normalizeText(source, 80) || null,
    status: "pending",
    attemptCount: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  return reference;
}

function canonicalParticipantRoomIds(snapshot, targetUid) {
  const roomIds = new Set();
  for (const document of snapshot.docs) {
    const segments = document.ref.path.split("/");
    const canonicalPath =
      segments.length === 4 &&
      segments[0] === "rooms" &&
      segments[2] === "participants";
    const data = document.data() ?? {};
    if (
      canonicalPath &&
      document.id === targetUid &&
      data.userId === targetUid
    ) {
      roomIds.add(segments[1]);
    }
  }
  return roomIds;
}

function canonicalActiveVoiceRoomIds(snapshot, targetUid) {
  const roomIds = new Set();
  for (const document of snapshot.docs) {
    const data = document.data() ?? {};
    const roomId = normalizeText(document.id, 128);
    if (
      roomId &&
      data.userId === targetUid &&
      data.participantIdentity === targetUid &&
      data.roomId === roomId
    ) {
      roomIds.add(roomId);
    }
  }
  return roomIds;
}

function safeErrorCode(error) {
  return normalizeText(
    error?.cause?.code ?? error?.code ?? error?.name ?? "unknown",
    80,
  ) || "unknown";
}

function restrictionIsActive(restriction, now = Date.now()) {
  if (restriction?.type !== EVENT_TYPES.COMMUNICATION_MUTE) return false;
  if (restriction.expiresAt == null) return true;
  const expiresAt = typeof restriction.expiresAt.toMillis === "function"
    ? restriction.expiresAt.toMillis()
    : new Date(restriction.expiresAt).getTime();
  return Number.isFinite(expiresAt) && expiresAt > now;
}

async function enforcementIsCurrent(eventId, event, targetUid) {
  if (event.type === EVENT_TYPES.BAN) {
    const profile = await db.collection("users").doc(targetUid).get();
    const data = profile.exists ? (profile.data() ?? {}) : {};
    return data.banned === true && data.banEnforcementEventId === eventId;
  }

  const restriction = await db.collection("restrictions").doc(targetUid).get();
  const data = restriction.exists ? (restriction.data() ?? {}) : {};
  return restrictionIsActive(data) &&
    data.voiceEnforcementEventId === eventId;
}

async function inBatches(values, size, action) {
  for (let index = 0; index < values.length; index += size) {
    await Promise.all(values.slice(index, index + size).map(action));
  }
}

async function deleteActiveVoiceSessionMirror(targetUid, roomId) {
  // Both ids came from canonical Firestore documents or a LiveKit room name.
  // LiveKit names are not guaranteed to be valid Firestore document ids, so
  // only attempt mirror cleanup when the derived path remains one segment.
  if (
    !targetUid || targetUid.includes("/") ||
    !roomId || roomId.includes("/")
  ) {
    return false;
  }
  await db.collection(ACTIVE_VOICE_SESSIONS)
    .doc(targetUid)
    .collection("rooms")
    .doc(roomId)
    .delete();
  return true;
}

/**
 * Converges one durable sanction event into LiveKit.
 *
 * Firestore participant rows are useful discovery mirrors, but a hostile
 * client can delete its own row while an already-issued LiveKit session is
 * still connected. We therefore union those rows with the participants
 * actually visible in LiveKit's active rooms before revoking the identity.
 * Every remote operation is idempotent, and any partial failure is rethrown
 * so the retrying event trigger never records a false success.
 */
async function executeVoiceEnforcementEvent(
  eventDocument,
  controlOverride = null,
) {
  if (!eventDocument?.ref) return { skipped: true, reason: "missing-event" };

  const current = await eventDocument.ref.get();
  if (!current.exists) return { skipped: true, reason: "deleted-event" };
  const event = current.data() ?? {};
  if (["completed", "invalid", "superseded"].includes(event.status)) {
    return { skipped: true, reason: event.status };
  }

  const targetUid = validTargetUid(event.targetUid);
  if (!targetUid || !SUPPORTED_EVENT_TYPES.has(event.type)) {
    logger.error("invalid moderation voice enforcement event", {
      eventId: current.id,
      type: normalizeText(event.type, 80) || null,
    });
    await current.ref.set({
      status: "invalid",
      processedAt: FieldValue.serverTimestamp(),
      lastErrorCode: "invalid-event",
    }, { merge: true });
    return { skipped: true, reason: "invalid" };
  }

  // A lift/new sanction supersedes the old event. Checking the event id as
  // well as the state prevents a delayed retry for sanction A from revoking
  // a session after sanction B (or an explicit lift) became authoritative.
  if (!await enforcementIsCurrent(current.id, event, targetUid)) {
    await current.ref.set({
      status: "superseded",
      processedAt: FieldValue.serverTimestamp(),
      lastErrorCode: null,
    }, { merge: true });
    return { skipped: true, reason: "superseded" };
  }

  const control = controlOverride ?? getProductionLiveKitControl();
  let discoveredRoomIds = new Set();
  let revokedCount = 0;

  try {
    const failures = [];
    const attemptedRoomIds = new Set();
    const revokeNewRooms = async (roomIds) => {
      const pending = [];
      for (const rawRoomId of roomIds) {
        const roomId = normalizeText(rawRoomId, 128);
        if (!roomId) continue;
        discoveredRoomIds.add(roomId);
        if (attemptedRoomIds.has(roomId)) continue;
        attemptedRoomIds.add(roomId);
        pending.push(roomId);
      }
      await inBatches(pending, CONTROL_BATCH_SIZE, async (roomId) => {
        try {
          await control.revokeParticipant(roomId, targetUid);
          // The remote session is now absent (or was already absent). Remove
          // its server-only discovery mirror as part of the same retry unit;
          // if Firestore cleanup fails, rethrow so an idempotent retry can
          // converge instead of leaving a permanently stale active session.
          await deleteActiveVoiceSessionMirror(targetUid, roomId);
          revokedCount += 1;
        } catch (error) {
          failures.push({ roomId, error });
        }
      });
    };

    // Primary, per-user server-only index maintained at token issuance and
    // lifecycle cleanup. Cost is O(this user's sessions), never O(all rooms).
    try {
      const activeSessions = await db
        .collection("activeVoiceSessions")
        .doc(targetUid)
        .collection("rooms")
        .get();
      await revokeNewRooms(
        canonicalActiveVoiceRoomIds(activeSessions, targetUid),
      );
    } catch (error) {
      failures.push({ roomId: null, error });
    }

    // Compatibility fallback for participant rows created before the session
    // index shipped. The explicit collection-group field index is deployed
    // with this function.
    try {
      const participants = await db
        .collectionGroup("participants")
        .where("userId", "==", targetUid)
        .get();
      await revokeNewRooms(
        canonicalParticipantRoomIds(participants, targetUid),
      );
    } catch (error) {
      failures.push({ roomId: null, error });
    }

    // Final legacy safety net: LiveKit itself catches a hostile client that
    // deleted both old Firestore mirrors while keeping its issued session.
    // The helper bounds this global scan and fails the event visibly when the
    // bound is exceeded; it is not the steady-state discovery mechanism.
    try {
      const activeLiveKitRooms = await control.findParticipantRooms(targetUid);
      await revokeNewRooms(activeLiveKitRooms);
    } catch (error) {
      failures.push({ roomId: null, error });
    }

    if (failures.length > 0) throw failures[0].error;

    await current.ref.set({
      status: "completed",
      attemptCount: FieldValue.increment(1),
      lastAttemptAt: FieldValue.serverTimestamp(),
      processedAt: FieldValue.serverTimestamp(),
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
      lastErrorCode: null,
    }, { merge: true });

    logger.info("moderation voice enforcement completed", {
      eventId: current.id,
      type: event.type,
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
    });
    return {
      completed: true,
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
    };
  } catch (error) {
    const errorCode = safeErrorCode(error);
    try {
      await current.ref.set({
        status: "retrying",
        attemptCount: FieldValue.increment(1),
        lastAttemptAt: FieldValue.serverTimestamp(),
        roomsDiscovered: discoveredRoomIds.size,
        roomsRevoked: revokedCount,
        lastErrorCode: errorCode,
      }, { merge: true });
    } catch (stateError) {
      logger.error("failed to persist voice enforcement retry state", {
        eventId: current.id,
        errorCode: safeErrorCode(stateError),
      });
    }
    logger.error("moderation voice enforcement will retry", {
      eventId: current.id,
      type: event.type,
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
      errorCode,
    });
    throw error;
  }
}

const onModerationVoiceEnforcementCreated = onDocumentCreated(
  {
    document: `${EVENT_COLLECTION}/{eventId}`,
    region: REGION,
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 300,
    memory: "512MiB",
    retry: true,
  },
  async (event) => executeVoiceEnforcementEvent(event.data),
);

module.exports = {
  EVENT_COLLECTION,
  EVENT_TYPES,
  canonicalActiveVoiceRoomIds,
  canonicalParticipantRoomIds,
  deleteActiveVoiceSessionMirror,
  enqueueVoiceEnforcement,
  executeVoiceEnforcementEvent,
  onModerationVoiceEnforcementCreated,
};

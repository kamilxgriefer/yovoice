const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db, normalizeText } = require("../utils/firestore");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const {
  RTC_BINDING_KINDS,
  hasUnboundLiveGeneration,
  mirrorBindsToSession,
  resolveRtcBindingForLiveKitRoom,
  resolveRtcBindingForRoom,
} = require("../servers/rtc_binding");

const REGION = "europe-west1";
const EVENT_COLLECTION = "moderationVoiceEnforcement";
const EVENT_TYPES = Object.freeze({
  BAN: "ban",
  COMMUNICATION_MUTE: "communicationMute",
});
const SUPPORTED_EVENT_TYPES = new Set(Object.values(EVENT_TYPES));
const CONTROL_BATCH_SIZE = 10;
const ACTIVE_VOICE_SESSIONS = "activeVoiceSessions";
// Skipped anchors and unbound provider rooms are recorded on the event for
// audit; each list is bounded so a pathological discovery set cannot grow
// the document without limit. The counts are always exact.
const MAX_AUDITED_BINDINGS = 20;
const CANDIDATE_SOURCES = Object.freeze({
  ANCHOR: "anchor",
  PROVIDER: "provider",
});
// Closed-set retry code: an anchor's retained generation is live or ending
// but did not bind, and the provider did not report it either, so the
// revocation owed under that generation is still outstanding.
const UNBOUND_LIVE_GENERATION = "unbound-live-generation";

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

function boundedAudit(entries) {
  return [...entries]
    .slice(0, MAX_AUDITED_BINDINGS)
    .map(([target, reason]) => ({ target, reason }));
}

/**
 * `skippedBindings` are anchor-derived candidates that were NOT revoked
 * because no live generation proved out. `unboundProviderRooms` are rooms
 * LiveKit itself reported the identity in that did not bind to a Firestore
 * generation: those WERE revoked, but no mirror was cleared for them.
 */
function auditedBindings(skippedBindings, unboundProviderRooms) {
  return {
    roomsSkipped: skippedBindings.size,
    skippedBindings: boundedAudit(skippedBindings),
    providerRoomsUnbound: unboundProviderRooms.size,
    unboundProviderRooms: boundedAudit(unboundProviderRooms),
  };
}

function unboundLiveGenerationError() {
  return Object.assign(
    new Error("A live server channel generation did not bind; the revocation will retry."),
    { code: UNBOUND_LIVE_GENERATION },
  );
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

/**
 * Removes the server-only discovery mirror for a session the provider has
 * just confirmed revoked. A legacy room's mirror is keyed by its room id and
 * is simply deleted. A V1 anchor's mirror is keyed by the anchor id but
 * belongs to one generation, so it is deleted only when it binds to the
 * generation that was actually revoked: a legacy-namespace revocation never
 * clears a V1 mirror, and a V1 revocation never clears a newer generation's
 * mirror. Both ids came from canonical Firestore documents or a LiveKit room
 * name; LiveKit names are not guaranteed to be valid document ids, so mirror
 * cleanup is only attempted when the derived path remains one segment.
 */
async function deleteActiveVoiceSessionMirror(targetUid, roomId, binding = null) {
  if (
    !targetUid || targetUid.includes("/") ||
    !roomId || roomId.includes("/")
  ) {
    return false;
  }
  const reference = db.collection(ACTIVE_VOICE_SESSIONS)
    .doc(targetUid)
    .collection("rooms")
    .doc(roomId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;
    const mirror = snapshot.data() ?? {};
    const versioned = mirror.serverSchemaVersion === 1;
    const deletable = binding?.kind === RTC_BINDING_KINDS.V1
      ? mirrorBindsToSession(mirror, binding, targetUid)
      : !versioned;
    if (!deletable) return false;
    transaction.delete(reference);
    return true;
  });
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
 *
 * Firestore-derived candidates are revoked only through a proven binding.
 * A V1 anchor whose retained generation is still live or ending but does
 * not bind keeps the event retrying unless the provider scan revoked that
 * generation's name in the same run: the skip is never a silent success.
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
  // Anchor-derived candidates without a live generation are never sent to
  // the provider by a name derived from Firestore alone; each skip is
  // audited. Provider-reported rooms that do not bind are still revoked and
  // audited separately.
  const skippedBindings = new Map();
  const unboundProviderRooms = new Map();

  try {
    const failures = [];
    const attemptedTargets = new Set();
    const revokedTargets = new Set();
    const resolvedCandidates = new Set();
    // Anchor candidates whose retained generation is still live or ending
    // but did not bind: a revocation is owed under that generation's name
    // until the provider (or a later, consistent retry) covers it.
    const owedGenerations = new Map();

    const revokeTarget = async (target, mirrorBinding) => {
      if (attemptedTargets.has(target)) return;
      attemptedTargets.add(target);
      try {
        await control.revokeParticipant(target, targetUid);
        revokedTargets.add(target);
        // The remote session is now absent (or was already absent). Remove
        // its server-only discovery mirror as part of the same retry unit;
        // if Firestore cleanup fails, rethrow so an idempotent retry can
        // converge instead of leaving a permanently stale active session.
        // A room that did not bind has no mirror this path may clear.
        if (mirrorBinding) {
          await deleteActiveVoiceSessionMirror(targetUid, mirrorBinding.roomId, mirrorBinding);
        }
        revokedCount += 1;
      } catch (error) {
        failures.push({ roomId: target, error });
      }
    };

    // A mirror or participant row names a media anchor room, whose binding
    // decides the namespace: a legacy room is its own namespace, a V1 anchor
    // is only ever revoked through its live generation's `srv_` name.
    const revokeAnchorCandidate = async (value) => {
      const binding = await resolveRtcBindingForRoom({ db, roomId: value });
      if (binding.bound) {
        await revokeTarget(binding.livekitRoomName, binding);
        return;
      }
      skippedBindings.set(value, binding.reason);
      if (hasUnboundLiveGeneration(binding)) {
        owedGenerations.set(value, binding.retained.livekitRoomName);
      }
    };

    // LiveKit itself reports the identity connected to this room, which is
    // authority enough to disconnect it: the name is always revoked, bound or
    // not, exactly as before V1 existed. The binding only decides which
    // server-only mirror, if any, may be cleared. Outside the `srv_`
    // namespace the name is a legacy-namespace room even when an anchor
    // shares the id; inside it the generation must prove out reciprocally.
    const revokeProviderCandidate = async (value) => {
      let binding = null;
      try {
        binding = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName: value });
      } catch (error) {
        failures.push({ roomId: value, error });
      }
      if (binding && !binding.bound) unboundProviderRooms.set(value, binding.reason);
      await revokeTarget(value, binding?.bound ? binding : null);
    };

    const revokeNewRooms = async (values, source) => {
      const pending = [];
      for (const rawValue of values) {
        const value = normalizeText(rawValue, 128);
        if (!value) continue;
        discoveredRoomIds.add(value);
        // Keyed by source as well as value: a provider room that shares an
        // anchor's id is a different candidate in a different namespace and
        // must still be resolved (and revoked) as a provider room.
        const key = `${source}:${value}`;
        if (resolvedCandidates.has(key)) continue;
        resolvedCandidates.add(key);
        pending.push(value);
      }
      await inBatches(pending, CONTROL_BATCH_SIZE, async (value) => {
        if (source === CANDIDATE_SOURCES.PROVIDER) {
          await revokeProviderCandidate(value);
          return;
        }
        try {
          await revokeAnchorCandidate(value);
        } catch (error) {
          failures.push({ roomId: value, error });
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
        CANDIDATE_SOURCES.ANCHOR,
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
        CANDIDATE_SOURCES.ANCHOR,
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
      await revokeNewRooms(activeLiveKitRooms, CANDIDATE_SOURCES.PROVIDER);
    } catch (error) {
      failures.push({ roomId: null, error });
    }

    if (failures.length > 0) throw failures[0].error;
    // A live or ending generation that did not bind may still hold this
    // identity. Completing here would make the skip terminal; retry instead,
    // unless the provider-reported name of that very generation was revoked.
    if ([...owedGenerations.values()].some((name) => !revokedTargets.has(name))) {
      throw unboundLiveGenerationError();
    }

    await current.ref.set({
      status: "completed",
      attemptCount: FieldValue.increment(1),
      lastAttemptAt: FieldValue.serverTimestamp(),
      processedAt: FieldValue.serverTimestamp(),
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
      ...auditedBindings(skippedBindings, unboundProviderRooms),
      lastErrorCode: null,
    }, { merge: true });

    logger.info("moderation voice enforcement completed", {
      eventId: current.id,
      type: event.type,
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
      roomsSkipped: skippedBindings.size,
      skipReasons: [...new Set(skippedBindings.values())],
      providerRoomsUnbound: unboundProviderRooms.size,
    });
    return {
      completed: true,
      roomsDiscovered: discoveredRoomIds.size,
      roomsRevoked: revokedCount,
      roomsSkipped: skippedBindings.size,
      providerRoomsUnbound: unboundProviderRooms.size,
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
        ...auditedBindings(skippedBindings, unboundProviderRooms),
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
      roomsSkipped: skippedBindings.size,
      providerRoomsUnbound: unboundProviderRooms.size,
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

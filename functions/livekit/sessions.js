const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const { db, normalizeText } = require("../utils/firestore");
const {
  RTC_BINDING_KINDS,
  hasUnboundLiveGeneration,
  mirrorIsVersionedForAnchor,
  resolveRtcBindingForRoom,
} = require("../servers/rtc_binding");

const ACTIVE_VOICE_SESSIONS = "activeVoiceSessions";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const WRITE_BATCH_SIZE = 450;

function activeVoiceSessionReference(userId, roomId) {
  const uid = normalizeText(userId, 128);
  const canonicalRoomId = normalizeText(roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(uid) || !SAFE_DOCUMENT_ID.test(canonicalRoomId)) {
    throw new Error("A canonical user and room are required for a voice session.");
  }
  return db.collection(ACTIVE_VOICE_SESSIONS)
    .doc(uid)
    .collection("rooms")
    .doc(canonicalRoomId);
}

function writeActiveVoiceSession(
  transaction,
  {
    userId,
    roomId,
    expiresAt,
    roomKind = null,
    clubId = null,
    tokenWindowStartedAt = null,
    tokenIssueCount = null,
    tokenLastIssuedAt = null,
  },
) {
  if (!transaction || typeof transaction.set !== "function") {
    throw new Error("A Firestore transaction is required.");
  }
  if (!(expiresAt instanceof Timestamp)) {
    throw new Error("A Firestore session expiry is required.");
  }
  const reference = activeVoiceSessionReference(userId, roomId);
  transaction.set(reference, {
    userId,
    roomId,
    participantIdentity: userId,
    expiresAt,
    issuedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(roomKind ? { roomKind } : {}),
    ...(clubId ? { clubId } : {}),
    ...(tokenWindowStartedAt instanceof Timestamp
      ? { tokenWindowStartedAt }
      : {}),
    ...(Number.isInteger(tokenIssueCount) && tokenIssueCount > 0
      ? { tokenIssueCount }
      : {}),
    ...(tokenLastIssuedAt instanceof Timestamp ? { tokenLastIssuedAt } : {}),
  });
  return reference;
}

function deleteActiveVoiceSession(transaction, userId, roomId) {
  if (!transaction || typeof transaction.delete !== "function") {
    throw new Error("A Firestore transaction is required.");
  }
  transaction.delete(activeVoiceSessionReference(userId, roomId));
}

/**
 * The generation fence for one mirror under a V1 anchor.
 *
 * A legacy-shaped mirror (no schema version) can only predate the anchor's
 * binding and never belongs to a V1 generation, so the legacy rule applies.
 * A V1 mirror is cleared only when it provably belongs to this anchor and
 * - is not the generation the anchor is currently bound to (`live` or
 *   `ending` — that generation is cleared by its own end worker, never by a
 *   cleanup keyed on the room id, even one that names it);
 * - is not a generation the anchor or its channel still names
 *   (`activeSessionId`, `voiceSessionId`, `serverSessionCleanupId`) unless
 *   the cleanup names that exact generation, so a graph that fails to prove
 *   out can never make its retained generation clearable by room id alone;
 * - when the cleanup names the generation it is ending, is that generation.
 * Anything foreign or malformed is left for reconciliation rather than
 * deleted on the strength of a room id.
 */
function mirrorIsClearable(mirror, userId, binding, generation) {
  if (mirror?.serverSchemaVersion !== 1) return true;
  if (!binding.anchor || !mirrorIsVersionedForAnchor(mirror, binding.anchor, userId)) return false;
  if (binding.bound && mirror.sessionId === binding.sessionId) return false;
  if (binding.pointers.includes(mirror.sessionId)) return mirror.sessionId === generation;
  return generation === null || mirror.sessionId === generation;
}

/**
 * A versioned anchor that does not bind while its retained generation is
 * still `live` or `ending` may have media connected under that generation's
 * `srv_` name. Nothing is deleted on the strength of the anchor id; the
 * warning carries only closed-set values.
 */
function deferredForUnboundLiveGeneration(binding) {
  if (!hasUnboundLiveGeneration(binding)) return false;
  logger.warn("voice-session cleanup deferred: a live server generation did not bind", {
    reason: binding.reason,
    status: binding.retained.status,
  });
  return true;
}

async function commitDeletes(references) {
  for (let index = 0; index < references.length; index += WRITE_BATCH_SIZE) {
    const batch = db.batch();
    for (const reference of references.slice(index, index + WRITE_BATCH_SIZE)) {
      batch.delete(reference);
    }
    await batch.commit();
  }
}

/**
 * Clears the server-only session mirrors of a room. For a legacy room this
 * is the unchanged blind cleanup keyed on the room id. For a V1 anchor the
 * same candidates are read and fenced per generation: a cleanup carrying an
 * older `sessionId` never clears a newer generation's mirror, and a cleanup
 * carrying no generation never clears the currently bound or retained one.
 * Each page is decided and deleted in one transaction that re-resolves the
 * binding, so a generation starting or ending between verdict and delete
 * retries the page instead of losing its mirror. An anchor that does not
 * bind while its retained generation is still live or ending is a no-op.
 */
async function deleteActiveVoiceSessionsForRoom(roomId, userIds, { sessionId = null } = {}) {
  const canonicalRoomId = normalizeText(roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(canonicalRoomId)) {
    throw new Error("A canonical room is required for voice-session cleanup.");
  }
  const generation = sessionId === null ? null : normalizeText(sessionId, 128);
  if (generation !== null && !SAFE_DOCUMENT_ID.test(generation)) {
    throw new Error("A canonical session generation is required for voice-session cleanup.");
  }
  const identities = [...new Set(userIds ?? [])]
    .map((value) => normalizeText(value, 128))
    .filter((value) => SAFE_DOCUMENT_ID.test(value));

  // A participant row is normally the companion discovery record, but an
  // older or hostile client may already have deleted it. Query the server-only
  // session mirror too, then validate the full path before deleting anything.
  const mirrorSnapshot = await db.collectionGroup("rooms")
    .where("roomId", "==", canonicalRoomId)
    .get();
  const references = new Map();
  for (const userId of identities) {
    const reference = activeVoiceSessionReference(userId, canonicalRoomId);
    references.set(reference.path, reference);
  }
  for (const document of mirrorSnapshot.docs) {
    const segments = document.ref.path.split("/");
    const data = document.data() ?? {};
    if (
      segments.length === 4 &&
      segments[0] === ACTIVE_VOICE_SESSIONS &&
      segments[2] === "rooms" &&
      document.id === canonicalRoomId &&
      data.roomId === canonicalRoomId &&
      data.userId === segments[1] &&
      data.participantIdentity === segments[1]
    ) {
      references.set(document.ref.path, document.ref);
    }
  }
  const sessionReferences = [...references.values()];
  if (sessionReferences.length === 0) return;

  const binding = await resolveRtcBindingForRoom({ db, roomId: canonicalRoomId });
  if (binding.kind === RTC_BINDING_KINDS.LEGACY) {
    await commitDeletes(sessionReferences);
    return;
  }
  if (deferredForUnboundLiveGeneration(binding)) return;

  for (let index = 0; index < sessionReferences.length; index += WRITE_BATCH_SIZE) {
    const page = sessionReferences.slice(index, index + WRITE_BATCH_SIZE);
    const deferred = await db.runTransaction(async (transaction) => {
      const current = await resolveRtcBindingForRoom({ db, transaction, roomId: canonicalRoomId });
      if (hasUnboundLiveGeneration(current)) return current;
      const snapshots = await transaction.getAll(...page);
      for (const snapshot of snapshots) {
        if (!snapshot.exists) continue;
        const userId = snapshot.ref.path.split("/")[1];
        // A room document deleted since the first verdict is back to the
        // legacy rule, exactly as a cleanup that started after it would be.
        if (current.kind === RTC_BINDING_KINDS.LEGACY ||
            mirrorIsClearable(snapshot.data(), userId, current, generation)) {
          transaction.delete(snapshot.ref);
        }
      }
      return null;
    });
    if (deferred && deferredForUnboundLiveGeneration(deferred)) return;
  }
}

module.exports = {
  ACTIVE_VOICE_SESSIONS,
  activeVoiceSessionReference,
  deleteActiveVoiceSession,
  deleteActiveVoiceSessionsForRoom,
  writeActiveVoiceSession,
};

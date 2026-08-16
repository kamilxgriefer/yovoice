const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db, normalizeText } = require("../utils/firestore");

const ACTIVE_VOICE_SESSIONS = "activeVoiceSessions";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;

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
  { userId, roomId, expiresAt, roomKind = null, clubId = null },
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
  });
  return reference;
}

function deleteActiveVoiceSession(transaction, userId, roomId) {
  if (!transaction || typeof transaction.delete !== "function") {
    throw new Error("A Firestore transaction is required.");
  }
  transaction.delete(activeVoiceSessionReference(userId, roomId));
}

async function deleteActiveVoiceSessionsForRoom(roomId, userIds) {
  const canonicalRoomId = normalizeText(roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(canonicalRoomId)) {
    throw new Error("A canonical room is required for voice-session cleanup.");
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

  for (let index = 0; index < sessionReferences.length; index += 450) {
    const batch = db.batch();
    for (const reference of sessionReferences.slice(index, index + 450)) {
      batch.delete(reference);
    }
    await batch.commit();
  }
}

module.exports = {
  ACTIVE_VOICE_SESSIONS,
  activeVoiceSessionReference,
  deleteActiveVoiceSession,
  deleteActiveVoiceSessionsForRoom,
  writeActiveVoiceSession,
};

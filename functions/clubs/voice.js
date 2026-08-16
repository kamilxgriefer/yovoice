const { FieldValue } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { deleteActiveVoiceSessionsForRoom } = require("../livekit/sessions");

async function deleteCollection(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
    return;
  }
  const snapshot = await reference.limit(250).get();
  if (snapshot.empty) return;
  const batch = db.batch();
  for (const document of snapshot.docs) batch.delete(document.ref);
  await batch.commit();
  if (snapshot.size === 250) await deleteCollection(reference);
}

/** Remove one Club identity from every associated room and its LiveKit
 * session. Membership is already denied before this runs, so retries cannot
 * regain access while control-plane convergence is in progress. */
async function revokeClubMemberVoice({ clubId, userId, control }) {
  const rooms = await db.collection("rooms").where("clubId", "==", clubId).get();
  for (const roomDocument of rooms.docs) {
    const participantReference = roomDocument.ref
      .collection("participants")
      .doc(userId);
    await db.runTransaction(async (transaction) => {
      const [roomSnapshot, participantSnapshot] = await transaction.getAll(
        roomDocument.ref,
        participantReference,
      );
      if (!roomSnapshot.exists || !participantSnapshot.exists) return;
      transaction.delete(participantReference);
      transaction.update(roomDocument.ref, {
        participantCount: Math.max(
          Number(roomSnapshot.data()?.participantCount ?? 0) - 1,
          0,
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    await control.revokeParticipant(roomDocument.id, userId);
    await deleteActiveVoiceSessionsForRoom(roomDocument.id, [userId]);
  }
  return rooms.size;
}

/** Complete the durable voice reset started in an ownership transaction.
 * The Club remains marked pending until LiveKit, session mirrors and roster
 * rows have all converged, making a lost callable response safely retryable. */
async function finishClubOwnershipVoiceReset({
  clubId,
  loungeRoomId,
  newOwnerId,
  control,
}) {
  if (loungeRoomId) {
    await control.endRoom(loungeRoomId);
    await deleteActiveVoiceSessionsForRoom(loungeRoomId);
    await deleteCollection(
      db.collection("rooms").doc(loungeRoomId).collection("participants"),
    );
  }
  await db.runTransaction(async (transaction) => {
    const clubReference = db.collection("clubs").doc(clubId);
    const snapshot = await transaction.get(clubReference);
    if (!snapshot.exists) return;
    const club = snapshot.data() ?? {};
    if (
      club.ownerId === newOwnerId &&
      club.ownershipVoiceResetForOwner === newOwnerId
    ) {
      transaction.set(clubReference, {
        ownershipVoiceResetPending: false,
        ownershipVoiceResetCompletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });
}

module.exports = {
  finishClubOwnershipVoiceReset,
  revokeClubMemberVoice,
};

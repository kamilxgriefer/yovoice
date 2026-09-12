const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const { db } = require("../utils/firestore");
const { deleteActiveVoiceSessionsForRoom } = require("../livekit/sessions");
const { isVersionedAnchor } = require("../servers/rtc_binding");

// The closed-set reason logged when a per-room boundary skips a document
// that is not this legacy path's room. One value, so the log is queryable.
const VERSIONED_ANCHOR_SKIP_REASON = "versioned-anchor";

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
    // NOT THIS PATH'S ROOM, AND NOT ONE BYTE OF IT. A V1 anchor's roster, its
    // participantCount, its session mirrors and its LiveKit room all belong to
    // the session runtime: `revokeParticipant(anchorId)` addresses a room that
    // does not exist (a silent alreadyAbsent that would leave this identity
    // connected to the live `srv_` room), and the roster transaction below
    // would mutate a live generation's state from a legacy Club path. Skipped
    // before any read or write, the way the liveness sweeper skips it.
    if (isVersionedAnchor(roomDocument.data())) {
      logger.warn("club voice revocation skipped a versioned room anchor", {
        reason: VERSIONED_ANCHOR_SKIP_REASON,
        clubId,
        roomId: roomDocument.id,
      });
      continue;
    }
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

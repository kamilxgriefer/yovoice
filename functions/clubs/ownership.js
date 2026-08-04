const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText, getDocumentOrThrow } = require("../utils/firestore");
const { writeClubAuditLog } = require("../utils/audit");

const REGION = "europe-west1";

// club_service.dart's updateClubDetails() deliberately throws "Club
// ownership transfer is not available yet." The only existing transfer
// path (functions/admin/clubs.js's transferClubOwnership) is gated to
// platform admin roles — a moderation tool, not something a regular club
// owner can call. This is the actual owner-initiated feature: the CURRENT
// owner hands their club to another existing member.
//
// firestore.rules deliberately blocks role:'owner' transitions on
// clubs/{id}/members/{id} from the normal role-update path
// (resource.data.role != 'owner' && request.resource.data.role != 'owner'),
// so a direct client write can't do this — it has to go through the Admin
// SDK, same as the admin version, just authorized differently (must BE the
// club's current owner, not a platform admin).
const transferClubOwnershipSelf = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    const clubId = normalizeText(request.data?.clubId, 128);
    const newOwnerId = normalizeText(request.data?.newOwnerId, 128);

    if (!clubId || !newOwnerId) {
      throw new HttpsError(
        "invalid-argument",
        "Both clubId and newOwnerId are required.",
      );
    }
    if (newOwnerId === auth.uid) {
      throw new HttpsError(
        "failed-precondition",
        "You are already the owner of this club.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);
    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );
    const club = clubSnapshot.data() ?? {};

    if (club.ownerId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "Only the current club owner can transfer ownership.",
      );
    }

    const newOwnerReference = clubReference.collection("members").doc(newOwnerId);
    const newOwnerSnapshot = await getDocumentOrThrow(
      newOwnerReference,
      HttpsError,
      "The new owner must already be a member of the club.",
    );
    const newOwner = newOwnerSnapshot.data() ?? {};

    const batch = db.batch();

    batch.set(
      clubReference.collection("members").doc(auth.uid),
      { role: "coOwner", updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    batch.set(
      newOwnerReference,
      { role: "owner", updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    batch.set(
      clubReference,
      {
        ownerId: newOwnerId,
        ownerName: newOwner.displayName ?? newOwner.name ?? "YoVoice user",
        ownershipTransferredBy: auth.uid,
        ownershipTransferredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await batch.commit();

    await writeClubAuditLog({
      caller: { uid: auth.uid, role: "owner" },
      action: "transfer_club_ownership_self",
      clubId,
      clubName: club.name ?? null,
      details: {
        previousOwnerId: auth.uid,
        newOwnerId,
        newOwnerName: newOwner.displayName ?? newOwner.name ?? null,
      },
    });

    return {
      success: true,
      clubId,
      previousOwnerId: auth.uid,
      newOwnerId,
    };
  },
);

module.exports = {
  transferClubOwnershipSelf,
};

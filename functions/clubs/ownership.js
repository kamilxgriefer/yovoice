const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const { writeClubAuditLog } = require("../utils/audit");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const { finishClubOwnershipVoiceReset } = require("./voice");
const {
  lockOwnershipGuards,
  requireCommunityClubCapacity,
  touchOwnershipGuards,
} = require("./quota");

const REGION = "europe-west1";
let ownershipLiveKitControlForTests = null;

function setOwnershipLiveKitControlForTests(control) {
  ownershipLiveKitControlForTests = control ?? null;
}

async function finishPendingReset(clubId, club, newOwnerId) {
  if (club.ownershipVoiceResetPending !== true) return;
  await finishClubOwnershipVoiceReset({
    clubId,
    loungeRoomId: club.loungeRoomId ?? `club_lounge_${clubId}`,
    newOwnerId,
    control:
      ownershipLiveKitControlForTests ?? getProductionLiveKitControl(),
  });
}

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
  {
    region: REGION,
    enforceAppCheck: false,
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
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
    const preflightSnapshot = await clubReference.get();
    if (!preflightSnapshot.exists) {
      throw new HttpsError("not-found", "The selected club was not found.");
    }
    const preflightClub = preflightSnapshot.data() ?? {};
    if (preflightClub.ownerId !== auth.uid) {
      if (
        preflightClub.ownerId === newOwnerId &&
        preflightClub.ownershipTransferredFrom === auth.uid
      ) {
        await finishPendingReset(clubId, preflightClub, newOwnerId);
        return {
          success: true,
          alreadyExisted: true,
          clubId,
          previousOwnerId: auth.uid,
          newOwnerId,
        };
      }
      throw new HttpsError(
        "permission-denied",
        "Only the current club owner can transfer ownership.",
      );
    }
    if (preflightClub.type === "family") {
      throw new HttpsError(
        "failed-precondition",
        "Family Room ownership cannot be transferred.",
      );
    }
    if (preflightClub.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "A Club being deleted cannot transfer ownership.",
      );
    }
    if (preflightClub.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "Only an active Club can transfer ownership.",
      );
    }
    if (preflightClub.ownershipVoiceResetPending === true) {
      throw new HttpsError(
        "failed-precondition",
        "A previous ownership voice reset is still in progress.",
      );
    }
    let club;
    let newOwner;
    let alreadyExisted = false;

    await db.runTransaction(async (transaction) => {
      // Every community ownership mutation acquires owner guards before Club
      // roots, matching createCommunityClub and avoiding inverse lock order.
      const guardReferences = await lockOwnershipGuards(transaction, [
        auth.uid,
        newOwnerId,
      ]);
      const clubSnapshot = await transaction.get(clubReference);
      if (!clubSnapshot.exists) {
        throw new HttpsError("not-found", "The selected club was not found.");
      }
      club = clubSnapshot.data() ?? {};

      if (club.ownerId !== auth.uid) {
        if (
          club.ownerId === newOwnerId &&
          club.ownershipTransferredFrom === auth.uid
        ) {
          alreadyExisted = true;
          return;
        }
        throw new HttpsError(
          "permission-denied",
          "Only the current club owner can transfer ownership.",
        );
      }
      if (club.type === "family") {
        throw new HttpsError(
          "failed-precondition",
          "Family Room ownership cannot be transferred.",
        );
      }
      if (club.deletionInProgress === true) {
        throw new HttpsError(
          "failed-precondition",
          "A Club being deleted cannot transfer ownership.",
        );
      }
      if (
        club.status !== "active" ||
        club.ownershipVoiceResetPending === true
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Only a stable active Club can transfer ownership.",
        );
      }

      const currentOwnerReference = clubReference
        .collection("members")
        .doc(auth.uid);
      const newOwnerReference = clubReference
        .collection("members")
        .doc(newOwnerId);
      const currentOwnerProfileReference = db.collection("users").doc(auth.uid);
      const [currentOwnerSnapshot, newOwnerSnapshot, currentOwnerProfile] =
        await transaction.getAll(
          currentOwnerReference,
          newOwnerReference,
          currentOwnerProfileReference,
        );

      if (!currentOwnerSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "The current owner membership is missing.",
        );
      }
      if (!newOwnerSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "The new owner must already be a member of the club.",
        );
      }
      const currentOwner = currentOwnerSnapshot.data() ?? {};
      newOwner = newOwnerSnapshot.data() ?? {};
      if (
        currentOwner.userId !== auth.uid ||
        currentOwner.role !== "owner" ||
        currentOwner.banned === true ||
        newOwner.userId !== newOwnerId ||
        newOwner.role === "owner"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Club ownership memberships are not canonical.",
        );
      }
      if (newOwner.banned === true) {
        throw new HttpsError(
          "permission-denied",
          "A banned Club member cannot receive ownership.",
        );
      }
      if (
        !currentOwnerProfile.exists ||
        currentOwnerProfile.data()?.banned === true ||
        currentOwnerProfile.data()?.disabled === true
      ) {
        throw new HttpsError(
          "permission-denied",
          "An active account is required to transfer Club ownership.",
        );
      }

      await requireCommunityClubCapacity(transaction, newOwnerId);
      const loungeReference = db.collection("rooms").doc(
        club.loungeRoomId ?? `club_lounge_${clubId}`,
      );
      const loungeSnapshot = await transaction.get(loungeReference);

      transaction.set(
        currentOwnerReference,
        { role: "coOwner", updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      transaction.set(
        newOwnerReference,
        { role: "owner", updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      transaction.set(
        db
          .collection("users")
          .doc(auth.uid)
          .collection("clubs")
          .doc(clubId),
        {
          clubId,
          name: club.name ?? "Untitled club",
          avatarUrl: club.avatarUrl ?? null,
          role: "coOwner",
          joinedAt:
            currentOwner.joinedAt ?? FieldValue.serverTimestamp(),
        },
      );
      transaction.set(
        db
          .collection("users")
          .doc(newOwnerId)
          .collection("clubs")
          .doc(clubId),
        {
          clubId,
          name: club.name ?? "Untitled club",
          avatarUrl: club.avatarUrl ?? null,
          role: "owner",
          joinedAt: newOwner.joinedAt ?? FieldValue.serverTimestamp(),
        },
      );
      transaction.set(
        clubReference,
        {
          ownerId: newOwnerId,
          ownerName:
            newOwner.displayName ?? newOwner.name ?? "YO Voice user",
          ownershipTransferredBy: auth.uid,
          ownershipTransferredFrom: auth.uid,
          ownershipTransferredAt: FieldValue.serverTimestamp(),
          ownershipVoiceResetPending: true,
          ownershipVoiceResetForOwner: newOwnerId,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      if (loungeSnapshot.exists) {
        transaction.update(loungeReference, {
          hostId: newOwnerId,
          hostName:
            newOwner.displayName ?? newOwner.name ?? "YO Voice user",
          hostPhotoUrl: newOwner.photoUrl ?? null,
          isLive: false,
          participantCount: 0,
          endedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      // Website publication consent belongs to the owner who granted it.
      // A transfer must never let the recipient inherit that public opt-in.
      transaction.delete(
        db.collection("clubMarketingConsents").doc(clubId),
      );
      touchOwnershipGuards(transaction, guardReferences);
    });

    if (alreadyExisted) {
      const currentClub = await clubReference.get();
      await finishPendingReset(clubId, currentClub.data() ?? {}, newOwnerId);
      return {
        success: true,
        alreadyExisted: true,
        clubId,
        previousOwnerId: auth.uid,
        newOwnerId,
      };
    }

    await finishPendingReset(clubId, {
      ...club,
      ownershipVoiceResetPending: true,
      loungeRoomId: club?.loungeRoomId,
    }, newOwnerId);

    await writeClubAuditLog({
      caller: { uid: auth.uid, role: "owner" },
      action: "transfer_club_ownership_self",
      clubId,
      clubName: club?.name ?? null,
      details: {
        previousOwnerId: auth.uid,
        newOwnerId,
        newOwnerName: newOwner?.displayName ?? newOwner?.name ?? null,
      },
    });

    return {
      success: true,
      alreadyExisted: false,
      clubId,
      previousOwnerId: auth.uid,
      newOwnerId,
    };
  },
);

module.exports = {
  setOwnershipLiveKitControlForTests,
  transferClubOwnershipSelf,
};

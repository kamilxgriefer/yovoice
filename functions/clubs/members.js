const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const { revokeClubMemberVoice } = require("./voice");

const REGION = "europe-west1";
const ROLE_POWER = Object.freeze({
  owner: 60,
  coOwner: 50,
  admin: 40,
  moderator: 30,
  member: 20,
  guest: 10,
});
const REMOVAL_ROLES = new Set(["owner", "coOwner", "admin", "moderator"]);
let memberLiveKitControlForTests = null;

function setMemberLiveKitControlForTests(control) {
  memberLiveKitControlForTests = control ?? null;
}

/**
 * Removes a lower-ranked Club member through one canonical Admin transaction.
 * A direct client root-counter update cannot prove which member disappeared,
 * so Firestore rules deny that old path entirely.
 */
const removeClubMemberSelf = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
  async (request) => {
    const auth = requireAuthentication(request);
    const clubId = normalizeText(request.data?.clubId, 128);
    const memberId = normalizeText(request.data?.memberId, 128);
    if (!clubId || !memberId) {
      throw new HttpsError(
        "invalid-argument",
        "Both clubId and memberId are required.",
      );
    }
    if (memberId === auth.uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot remove your own membership.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);
    const actorReference = clubReference.collection("members").doc(auth.uid);
    const targetReference = clubReference.collection("members").doc(memberId);
    const targetProjection = db
      .collection("users")
      .doc(memberId)
      .collection("clubs")
      .doc(clubId);
    const actorProfileReference = db.collection("users").doc(auth.uid);
    let alreadyRemoved = false;

    await db.runTransaction(async (transaction) => {
      const [clubSnapshot, actorSnapshot, targetSnapshot, actorProfile] =
        await transaction.getAll(
          clubReference,
          actorReference,
          targetReference,
          actorProfileReference,
        );
      if (!clubSnapshot.exists) {
        throw new HttpsError("not-found", "The Club no longer exists.");
      }
      if (!actorSnapshot.exists || !actorProfile.exists) {
        throw new HttpsError(
          "failed-precondition",
          "The acting account must be an active Club member.",
        );
      }

      const club = clubSnapshot.data() ?? {};
      const actor = actorSnapshot.data() ?? {};
      const profile = actorProfile.data() ?? {};
      if (
        club.status !== "active" ||
        club.deletionInProgress === true ||
        actor.userId !== auth.uid ||
        actor.banned === true ||
        profile.banned === true ||
        profile.disabled === true
      ) {
        throw new HttpsError(
          "permission-denied",
          "Only an active Club manager can remove members.",
        );
      }
      if (!targetSnapshot.exists) {
        alreadyRemoved = true;
        transaction.delete(targetProjection);
        return;
      }
      const target = targetSnapshot.data() ?? {};
      const actorRole = String(actor.role ?? "member");
      const targetRole = String(target.role ?? "member");
      if (
        target.userId !== memberId ||
        ((actorRole === "owner") !== (club.ownerId === auth.uid))
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Club membership authority is not canonical.",
        );
      }
      if (
        !REMOVAL_ROLES.has(actorRole) ||
        targetRole === "owner" ||
        (ROLE_POWER[actorRole] ?? 0) <= (ROLE_POWER[targetRole] ?? 0)
      ) {
        throw new HttpsError(
          "permission-denied",
          "Your Club role cannot remove this member.",
        );
      }
      if (club.ownerId === memberId) {
        throw new HttpsError(
          "failed-precondition",
          "The Club owner cannot be removed.",
        );
      }

      const memberCount = Math.max(Number(club.memberCount ?? 0) - 1, 0);
      const onlineCount = target.isOnline === true
        ? Math.max(Number(club.onlineCount ?? 0) - 1, 0)
        : Math.max(Number(club.onlineCount ?? 0), 0);
      transaction.delete(targetReference);
      transaction.delete(targetProjection);
      transaction.update(clubReference, {
        memberCount,
        onlineCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await revokeClubMemberVoice({
      clubId,
      userId: memberId,
      control:
        memberLiveKitControlForTests ?? getProductionLiveKitControl(),
    });

    return { success: true, alreadyExisted: alreadyRemoved, clubId, memberId };
  },
);

module.exports = {
  removeClubMemberSelf,
  ROLE_POWER,
  REMOVAL_ROLES,
  setMemberLiveKitControlForTests,
};

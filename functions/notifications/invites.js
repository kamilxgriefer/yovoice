const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions/v2");
const { FieldValue } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  createNotificationForEvent,
  restrictionIsActive,
} = require("./canonical");

const REGION = "europe-west1";
const INVITER_ROLES = new Set(["owner", "coOwner", "admin", "moderator"]);
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;

const sendClubInvite = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before sending invitations.",
      );
    }
    const clubId = normalizeText(request.data?.clubId, 128);
    const inviteeId = normalizeText(request.data?.inviteeId, 128);
    if (
      !SAFE_ID.test(clubId) ||
      !SAFE_ID.test(inviteeId) ||
      inviteeId === auth.uid
    ) {
      throw new HttpsError("invalid-argument", "A valid Club and invitee are required.");
    }

    const clubReference = db.doc(`clubs/${clubId}`);
    const inviterReference = db.doc(`users/${auth.uid}`);
    const inviteeReference = db.doc(`users/${inviteeId}`);
    const membershipReference = db.doc(`clubs/${clubId}/members/${auth.uid}`);
    const memberReference = db.doc(`clubs/${clubId}/members/${inviteeId}`);
    const inviteReference = db.doc(`clubs/${clubId}/invites/${inviteeId}`);
    const inviterRestrictionReference = db.doc(`restrictions/${auth.uid}`);
    const inviteeRestrictionReference = db.doc(`restrictions/${inviteeId}`);
    const inviterBlockReference = db.doc(`users/${auth.uid}/blocked/${inviteeId}`);
    const inviteeBlockReference = db.doc(`users/${inviteeId}/blocked/${auth.uid}`);
    const inviterFriendReference = db.doc(`users/${auth.uid}/friends/${inviteeId}`);
    const inviteeFriendReference = db.doc(`users/${inviteeId}/friends/${auth.uid}`);

    return db.runTransaction(async (transaction) => {
      const [
        club,
        inviter,
        invitee,
        membership,
        member,
        invite,
        inviterRestriction,
        inviteeRestriction,
        inviterBlock,
        inviteeBlock,
        inviterFriend,
        inviteeFriend,
      ] = await transaction.getAll(
        clubReference,
        inviterReference,
        inviteeReference,
        membershipReference,
        memberReference,
        inviteReference,
        inviterRestrictionReference,
        inviteeRestrictionReference,
        inviterBlockReference,
        inviteeBlockReference,
        inviterFriendReference,
        inviteeFriendReference,
      );
      if (!club.exists || !inviter.exists || !invitee.exists || !membership.exists) {
        throw new HttpsError("not-found", "The Club or selected account no longer exists.");
      }
      const clubData = club.data() ?? {};
      const inviterData = inviter.data() ?? {};
      const inviteeData = invitee.data() ?? {};
      if (
        clubData.status !== "active" ||
        clubData.deletionInProgress === true ||
        inviterData.banned === true ||
        inviterData.disabled === true ||
        inviteeData.banned === true ||
        inviteeData.disabled === true ||
        membership.data()?.userId !== auth.uid ||
        membership.data()?.banned === true ||
        !INVITER_ROLES.has(membership.data()?.role) ||
        restrictionIsActive(inviterRestriction.data()) ||
        restrictionIsActive(inviteeRestriction.data()) ||
        inviterBlock.exists ||
        inviteeBlock.exists ||
        !inviterFriend.exists ||
        !inviteeFriend.exists
      ) {
        throw new HttpsError(
          "permission-denied",
          "This Club invitation is not permitted.",
        );
      }
      if (member.exists) {
        throw new HttpsError("already-exists", "This person is already a Club member.");
      }
      if (invite.exists) return { changed: false, clubId, inviteeId };

      transaction.create(inviteReference, {
        clubId,
        clubName: normalizeText(clubData.name, 120) || "YO Voice club",
        clubAvatarUrl:
          typeof clubData.avatarUrl === "string" ? clubData.avatarUrl : null,
        inviteeId,
        inviterId: auth.uid,
        inviterName:
          normalizeText(inviterData.displayName || inviterData.username, 80) ||
          "YO Voice user",
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
      });
      return { changed: true, clubId, inviteeId };
    });
  },
);

const onClubInviteCreated = onDocumentCreated(
  {
    document: "clubs/{clubId}/invites/{inviteeId}",
    region: REGION,
  },
  async (event) => {
    const source = event.data;
    if (!source?.exists) return;
    const invite = source.data() ?? {};
    const { clubId, inviteeId } = event.params;
    const inviterId = invite.inviterId;
    if (
      invite.status !== "pending" ||
      invite.inviteeId !== inviteeId ||
      typeof inviterId !== "string" ||
      !inviterId
    ) {
      logger.warn("Ignoring non-canonical Club invite", { clubId, inviteeId });
      return;
    }

    const clubReference = db.doc(`clubs/${clubId}`);
    const inviterMembership = db.doc(
      `clubs/${clubId}/members/${inviterId}`,
    );
    const clubSnapshot = await clubReference.get();
    const clubLabel = typeof clubSnapshot.data()?.name === "string"
      ? clubSnapshot.data().name.trim().slice(0, 120)
      : "YO Voice club";
    const outcome = await createNotificationForEvent({
      eventId: event.id,
      recipientId: inviteeId,
      actorId: inviterId,
      type: "clubInvite",
      notificationId: `clubInvite_${clubId}_${inviteeId}`,
      targetId: clubId,
      targetLabel: clubLabel || "YO Voice club",
      sourcePath: source.ref.path,
      validate: async (transaction) => {
        const [club, membership, currentInvite, member] =
          await transaction.getAll(
            clubReference,
            inviterMembership,
            source.ref,
            db.doc(`clubs/${clubId}/members/${inviteeId}`),
          );
        if (!club.exists || !membership.exists || !currentInvite.exists) {
          return false;
        }
        const clubData = club.data() ?? {};
        const role = membership.data()?.role;
        if (
          clubData.status !== "active" ||
          clubData.deletionInProgress === true ||
          membership.data()?.userId !== inviterId ||
          membership.data()?.banned === true ||
          !INVITER_ROLES.has(role) ||
          member.exists
        ) {
          return false;
        }
        return true;
      },
    });
    logger.info("Club invite notification", { clubId, inviteeId, outcome });
  },
);

const onClubMemberCreated = onDocumentCreated(
  {
    document: "clubs/{clubId}/members/{memberId}",
    region: REGION,
  },
  async (event) => {
    const source = event.data;
    if (!source?.exists) return;
    const member = source.data() ?? {};
    const { clubId, memberId } = event.params;
    const inviterId = member.invitedBy;
    if (
      member.userId !== memberId ||
      member.role !== "member" ||
      typeof inviterId !== "string" ||
      !inviterId
    ) {
      return;
    }

    const clubReference = db.doc(`clubs/${clubId}`);
    const club = await clubReference.get();
    const label = typeof club.data()?.name === "string"
      ? club.data().name.trim().slice(0, 120)
      : "YO Voice club";
    const outcome = await createNotificationForEvent({
      eventId: event.id,
      recipientId: inviterId,
      actorId: memberId,
      type: "clubInviteAccepted",
      notificationId: `clubInviteAccepted_${clubId}_${memberId}`,
      targetId: clubId,
      targetLabel: label || "YO Voice club",
      sourcePath: source.ref.path,
      validate: async (transaction) => {
        const [canonicalClub, canonicalMember, outstandingInvite] =
          await transaction.getAll(
            clubReference,
            source.ref,
            db.doc(`clubs/${clubId}/invites/${memberId}`),
          );
        return canonicalClub.exists &&
          canonicalClub.data()?.status === "active" &&
          canonicalClub.data()?.deletionInProgress !== true &&
          canonicalMember.exists &&
          canonicalMember.data()?.userId === memberId &&
          canonicalMember.data()?.invitedBy === inviterId &&
          !outstandingInvite.exists;
      },
    });
    logger.info("Club invite acceptance notification", {
      clubId,
      memberId,
      inviterId,
      outcome,
    });
  },
);

module.exports = {
  sendClubInvite,
  onClubInviteCreated,
  onClubMemberCreated,
};

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { restrictionIsActive } = require("../notifications/canonical");
const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  CLUB_ACTION_RATE_LIMITS,
  consumeClubActionAttempt,
} = require("./quota");

const REGION = "europe-west1";
const MINUTE_LIMIT =
  CLUB_ACTION_RATE_LIMITS.moderateClubMessage.minute.maxEvents;
const HOUR_LIMIT = CLUB_ACTION_RATE_LIMITS.moderateClubMessage.hour.maxEvents;
const ROLE_POWER = Object.freeze({
  guest: 0,
  member: 1,
  moderator: 2,
  admin: 3,
  coOwner: 4,
  owner: 5,
});

function safeId(value, field) {
  const id = normalizeText(value, 128);
  if (!id || id.includes("/") || id === "." || id === "..") {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return id;
}

function exactInput(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "A moderation target is required.");
  }
  const expected = ["channelId", "clubId", "messageId"];
  const keys = Object.keys(value).sort();
  if (
    keys.length !== expected.length ||
    keys.some((key, index) => key !== expected[index])
  ) {
    throw new HttpsError("invalid-argument", "The moderation target is invalid.");
  }
  return {
    channelId: safeId(value.channelId, "channelId"),
    clubId: safeId(value.clubId, "clubId"),
    messageId: safeId(value.messageId, "messageId"),
  };
}

function activeAccount(snapshot) {
  if (!snapshot.exists) return false;
  const data = snapshot.data() ?? {};
  return data.banned !== true &&
    data.disabled !== true &&
    data.deleted !== true &&
    data.status !== "deleted";
}

function rolePower(value) {
  return ROLE_POWER[value] ?? -1;
}

function activeCanonicalMember(snapshot, expectedUserId) {
  if (!snapshot.exists) return null;
  const member = snapshot.data() ?? {};
  if (
    member.userId !== expectedUserId ||
    member.banned === true ||
    !Object.hasOwn(ROLE_POWER, member.role)
  ) {
    return null;
  }
  return member;
}

const moderateClubMessage = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 50,
  },
  async (request) => {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email address before moderating club chat.",
      );
    }
    const { clubId, channelId, messageId } = exactInput(request.data);
    // Commit the actor-wide attempt before reading any caller-selected Club,
    // channel, message or author state. A denied target therefore consumes
    // the same budget as a successful redaction.
    await consumeClubActionAttempt(auth.uid, "moderateClubMessage");
    const accountRef = db.doc(`users/${auth.uid}`);
    const restrictionRef = db.doc(`restrictions/${auth.uid}`);
    const clubRef = db.doc(`clubs/${clubId}`);
    const memberRef = clubRef.collection("members").doc(auth.uid);
    const channelRef = clubRef.collection("channels").doc(channelId);
    const messageRef = channelRef.collection("messages").doc(messageId);
    const auditRef = db.collection("adminAuditLogs").doc();
    const now = Timestamp.now();

    return db.runTransaction(async (transaction) => {
      const [account, restriction, club, member, channel, message] =
        await transaction.getAll(
          accountRef,
          restrictionRef,
          clubRef,
          memberRef,
          channelRef,
          messageRef,
        );
      if (!activeAccount(account)) {
        throw new HttpsError("permission-denied", "The account is not active.");
      }
      if (restrictionIsActive(restriction.exists ? restriction.data() : null)) {
        throw new HttpsError(
          "permission-denied",
          "This account cannot moderate club chat right now.",
        );
      }
      const clubData = club.exists ? (club.data() ?? {}) : null;
      if (
        !clubData ||
        clubData.status !== "active" ||
        clubData.deletionInProgress === true ||
        !channel.exists ||
        !member.exists
      ) {
        throw new HttpsError("permission-denied", "Club moderation is unavailable.");
      }
      const actorMember = activeCanonicalMember(member, auth.uid);
      if (!actorMember) {
        throw new HttpsError(
          "permission-denied",
          "Your Club membership is not active.",
        );
      }
      const actorRole = actorMember.role;
      const actorPower = rolePower(actorRole);
      if (actorPower < ROLE_POWER.moderator) {
        throw new HttpsError(
          "permission-denied",
          "Your club role cannot moderate messages.",
        );
      }
      if (!message.exists) {
        throw new HttpsError("not-found", "This message no longer exists.");
      }
      const messageData = message.data() ?? {};
      if (
        messageData.clubId !== clubId ||
        messageData.channelId !== channelId
      ) {
        throw new HttpsError("data-loss", "The club message binding is invalid.");
      }
      const authorId = safeId(messageData.senderId, "senderId");
      if (authorId === auth.uid) {
        throw new HttpsError(
          "failed-precondition",
          "Delete your own message with the normal chat action.",
        );
      }
      if (messageData.isDeleted === true) {
        return { outcome: "alreadyRemoved", redacted: false };
      }
      if (authorId === clubData.ownerId) {
        throw new HttpsError(
          "permission-denied",
          "The club owner's messages can only be removed by YO Voice staff.",
        );
      }

      const authorMember = await transaction.get(
        clubRef.collection("members").doc(authorId),
      );
      const authorPower = authorMember.exists
        ? rolePower(authorMember.data()?.role)
        : ROLE_POWER.guest;
      if (authorPower >= actorPower) {
        throw new HttpsError(
          "permission-denied",
          "You cannot remove a message from an equal or higher club role.",
        );
      }

      transaction.update(messageRef, {
        content: "",
        isDeleted: true,
        editedAt: now,
        deletedBy: auth.uid,
        deletedByRole: actorRole,
        deletedAt: now,
        moderationRemoved: true,
      });
      transaction.create(auditRef, {
        actorId: auth.uid,
        actorEmail: auth.token?.email ?? null,
        actorRole: `club:${actorRole}`,
        action: "moderateClubMessage",
        targetType: "clubMessage",
        targetId: messageId,
        targetLabel: null,
        details: {
          authorId,
          channelId,
          clubId,
          outcome: "redacted",
        },
        createdAt: FieldValue.serverTimestamp(),
      });
      return { outcome: "redacted", redacted: true };
    });
  },
);

module.exports = {
  HOUR_LIMIT,
  MINUTE_LIMIT,
  ROLE_POWER,
  moderateClubMessage,
};

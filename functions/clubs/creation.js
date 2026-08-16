const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  lockOwnershipGuards,
  requireCommunityClubCapacity,
  touchOwnershipGuards,
} = require("./quota");

const REGION = "europe-west1";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const CLUB_PRIVACY = new Set(["public", "private", "inviteOnly"]);

function optionalHttpsUrl(value, fieldName) {
  if (value === null || value === undefined || value === "") return null;
  const normalized = String(value).trim();
  if (normalized.length > 2048) {
    throw new HttpsError("invalid-argument", `${fieldName} is too long.`);
  }
  try {
    const url = new URL(normalized);
    if (url.protocol !== "https:") throw new Error("not https");
  } catch {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} must be a valid HTTPS URL.`,
    );
  }
  return normalized;
}

function validatedCreationInput(data) {
  const clubId = normalizeText(data?.clubId, 128);
  const name = normalizeText(data?.name, 41);
  const description = normalizeText(data?.description, 221);
  const privacy = normalizeText(data?.privacy, 32);
  const defaultLanguage = normalizeText(data?.defaultLanguage, 64) || "English";

  if (!SAFE_DOCUMENT_ID.test(clubId) || clubId.startsWith("family_")) {
    throw new HttpsError("invalid-argument", "The Club id is invalid.");
  }
  if (name.length < 3 || name.length > 40) {
    throw new HttpsError(
      "invalid-argument",
      "Club name must contain 3 to 40 characters.",
    );
  }
  if (description.length > 220) {
    throw new HttpsError(
      "invalid-argument",
      "Club description cannot exceed 220 characters.",
    );
  }
  if (!CLUB_PRIVACY.has(privacy)) {
    throw new HttpsError("invalid-argument", "The Club privacy is invalid.");
  }

  return {
    clubId,
    name,
    description,
    privacy,
    defaultLanguage,
    avatarUrl: optionalHttpsUrl(data?.avatarUrl, "avatarUrl"),
    bannerUrl: optionalHttpsUrl(data?.bannerUrl, "bannerUrl"),
  };
}

function profileName(profile, auth) {
  const displayName = normalizeText(profile?.displayName, 80);
  if (displayName) return displayName;
  const tokenName = normalizeText(auth.token?.name, 80);
  if (tokenName) return tokenName;
  const email = normalizeText(auth.token?.email, 320);
  return email ? email.split("@")[0] : "YO Voice user";
}

/**
 * The only ordinary-community Club creation path. Firestore rules reject the
 * equivalent direct client root write; Admin transaction + per-owner guard
 * makes the Premium limit authoritative under concurrent sessions.
 */
const createCommunityClub = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before creating a Club.",
      );
    }
    const input = validatedCreationInput(request.data);

    const clubReference = db.collection("clubs").doc(input.clubId);
    const generalReference = clubReference.collection("channels").doc();
    const announcementsReference = clubReference.collection("channels").doc();
    const loungeReference = clubReference.collection("channels").doc();
    const loungeRoomReference = db
      .collection("rooms")
      .doc(`club_lounge_${input.clubId}`);
    const memberReference = clubReference.collection("members").doc(auth.uid);
    const userClubReference = db
      .collection("users")
      .doc(auth.uid)
      .collection("clubs")
      .doc(input.clubId);
    const profileReference = db.collection("users").doc(auth.uid);

    const result = await db.runTransaction(async (transaction) => {
      const guardReferences = await lockOwnershipGuards(transaction, [auth.uid]);
      const [existingClub, profileSnapshot] = await transaction.getAll(
        clubReference,
        profileReference,
      );

      if (existingClub.exists) {
        const existing = existingClub.data() ?? {};
        if (
          existing.ownerId === auth.uid &&
          existing.type !== "family" &&
          existing.deletionInProgress !== true
        ) {
          return { clubId: input.clubId, alreadyExisted: true };
        }
        if (existing.deletionInProgress === true) {
          throw new HttpsError(
            "failed-precondition",
            "This Club is being deleted and cannot be recovered.",
          );
        }
        throw new HttpsError("already-exists", "That Club id is unavailable.");
      }

      const profile = profileSnapshot.exists
        ? (profileSnapshot.data() ?? {})
        : {};
      if (profile.banned === true) {
        throw new HttpsError(
          "permission-denied",
          "This account cannot create Clubs.",
        );
      }

      const capacity = await requireCommunityClubCapacity(
        transaction,
        auth.uid,
      );
      const ownerName = profileName(profile, auth);
      const ownerPhotoUrl =
        typeof profile.photoUrl === "string" ? profile.photoUrl : null;

      transaction.create(clubReference, {
        name: input.name,
        description: input.description,
        ownerId: auth.uid,
        ownerName,
        avatarUrl: input.avatarUrl,
        bannerUrl: input.bannerUrl,
        privacy: input.privacy,
        type: "community",
        status: "active",
        defaultLanguage: input.defaultLanguage,
        memberCount: 1,
        onlineCount: 1,
        defaultChatChannelId: generalReference.id,
        defaultVoiceChannelId: loungeReference.id,
        loungeRoomId: loungeRoomReference.id,
        announcementChannelId: announcementsReference.id,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(memberReference, {
        userId: auth.uid,
        displayName: ownerName,
        photoUrl: ownerPhotoUrl,
        role: "owner",
        isOnline: true,
        joinedAt: FieldValue.serverTimestamp(),
        invitedBy: null,
      });
      transaction.create(userClubReference, {
        clubId: input.clubId,
        name: input.name,
        avatarUrl: input.avatarUrl,
        role: "owner",
        joinedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(generalReference, {
        name: "general",
        type: "chat",
        position: 0,
        isPrivate: false,
        createdBy: auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(announcementsReference, {
        name: "announcements",
        type: "announcement",
        position: 1,
        isPrivate: false,
        createdBy: auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(loungeReference, {
        name: "Club Lounge",
        type: "voice",
        position: 2,
        isPrivate: false,
        createdBy: auth.uid,
        roomId: loungeRoomReference.id,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(loungeRoomReference, {
        hostId: auth.uid,
        hostName: ownerName,
        hostPhotoUrl: ownerPhotoUrl,
        name: `${input.name} Lounge`,
        description: input.description ||
          `Private voice lounge for ${input.name} members.`,
        category: "club",
        visibility: "private",
        language: input.defaultLanguage,
        maxParticipants: null,
        participantCount: 0,
        memberCount: 1,
        isLive: false,
        roomType: "community",
        status: "active",
        imageUrl: input.avatarUrl,
        approvalRequired: false,
        slowModeSeconds: 0,
        autoMuteNewUsers: false,
        membersCanStartVoice: true,
        experience: "community",
        clubId: input.clubId,
        roomKind: "clubLounge",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      touchOwnershipGuards(transaction, guardReferences);

      return {
        clubId: input.clubId,
        alreadyExisted: false,
        ownedCommunityClubs: capacity.ownedCommunityClubs + 1,
        maxOwnedClubs: capacity.limit,
      };
    });

    return result;
  },
);

module.exports = {
  createCommunityClub,
  optionalHttpsUrl,
  profileName,
  validatedCreationInput,
};

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  consumeClubActionAttempt,
  lockOwnershipGuards,
  requireCommunityClubCapacity,
  touchOwnershipGuards,
} = require("./quota");

const REGION = "europe-west1";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const CLUB_PRIVACY = new Set(["public", "private", "inviteOnly"]);
const CLUB_MEDIA_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const CLUB_MEDIA_MIN_BYTES = 128;
const CLUB_MEDIA_MAX_BYTES = 8 * 1024 * 1024;

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
  if (
    (data?.avatarUrl !== null && data?.avatarUrl !== undefined) ||
    (data?.bannerUrl !== null && data?.bannerUrl !== undefined)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Club media must be finalized from verified Storage objects.",
    );
  }

  return {
    clubId,
    name,
    description,
    privacy,
    defaultLanguage,
    avatarUrl: null,
    bannerUrl: null,
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
    await consumeClubActionAttempt(auth.uid, "createCommunityClub");

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
      const guardReferences = await lockOwnershipGuards(transaction, [
        auth.uid,
      ]);
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
        {
          tokenRole: auth.token?.role,
          requireTokenRole: true,
        },
      );
      const ownerName = profileName(profile, auth);
      const ownerPhotoUrl = null;

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
        description:
          input.description ||
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

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validatedMediaDescriptor(value, kind, uid, clubId) {
  if (value === null || value === undefined) return null;
  if (
    !plainObject(value) ||
    Object.keys(value).sort().join(",") !== "generation,path"
  ) {
    throw new HttpsError("invalid-argument", `${kind} upload is invalid.`);
  }
  const expectedPath = `clubs/${uid}/${clubId}/${kind}`;
  if (
    value.path !== expectedPath ||
    typeof value.generation !== "string" ||
    !/^[1-9][0-9]*$/u.test(value.generation)
  ) {
    throw new HttpsError("invalid-argument", `${kind} upload is invalid.`);
  }
  return { path: expectedPath, generation: value.generation };
}

function metadataCustomFields(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return plainObject(custom) ? custom : {};
}

async function verifiedClubMedia(bucket, descriptor, kind) {
  if (descriptor === null) return null;
  let metadata;
  try {
    [metadata] = await bucket.file(descriptor.path).getMetadata();
  } catch (error) {
    if (error?.code === 404 || error?.code === 5) {
      throw new HttpsError("failed-precondition", `${kind} upload is missing.`);
    }
    throw error;
  }
  const size = Number(metadata?.size);
  const generation = String(metadata?.generation ?? "");
  if (
    !Number.isSafeInteger(size) ||
    size < CLUB_MEDIA_MIN_BYTES ||
    size > CLUB_MEDIA_MAX_BYTES ||
    !CLUB_MEDIA_TYPES.has(metadata?.contentType) ||
    generation !== descriptor.generation
  ) {
    throw new HttpsError(
      "failed-precondition",
      `${kind} upload could not be verified.`,
    );
  }
  const tokenValue =
    metadataCustomFields(metadata).firebaseStorageDownloadTokens;
  const token =
    typeof tokenValue === "string"
      ? tokenValue
          .split(",")
          .map((value) => value.trim())
          .find(Boolean)
      : null;
  if (!token || typeof bucket.name !== "string" || !bucket.name) {
    throw new HttpsError(
      "failed-precondition",
      `${kind} upload has no canonical download token.`,
    );
  }
  return {
    generation,
    path: descriptor.path,
    url: `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(
      bucket.name,
    )}/o/${encodeURIComponent(descriptor.path)}?alt=media&generation=${encodeURIComponent(
      generation,
    )}&token=${encodeURIComponent(token)}`,
  };
}

function createFinalizeClubMediaHandler({ firestore = db, bucket } = {}) {
  return async (request) => {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before adding Club media.",
      );
    }
    if (
      !plainObject(request.data) ||
      Object.keys(request.data).sort().join(",") !== "avatar,banner,clubId"
    ) {
      throw new HttpsError("invalid-argument", "Club media input is invalid.");
    }
    const clubId = normalizeText(request.data.clubId, 128);
    if (!SAFE_DOCUMENT_ID.test(clubId)) {
      throw new HttpsError("invalid-argument", "The Club id is invalid.");
    }
    const avatarDescriptor = validatedMediaDescriptor(
      request.data.avatar,
      "avatar",
      auth.uid,
      clubId,
    );
    const bannerDescriptor = validatedMediaDescriptor(
      request.data.banner,
      "banner",
      auth.uid,
      clubId,
    );
    if (avatarDescriptor === null && bannerDescriptor === null) {
      throw new HttpsError("invalid-argument", "No Club media was provided.");
    }
    await consumeClubActionAttempt(auth.uid, "finalizeClubMedia", {
      firestore,
    });

    const clubReference = firestore.collection("clubs").doc(clubId);
    const memberReference = clubReference.collection("members").doc(auth.uid);
    const profileReference = firestore.collection("users").doc(auth.uid);
    const projectionReference = profileReference
      .collection("clubs")
      .doc(clubId);

    function requireCurrentAuthority(
      clubSnapshot,
      memberSnapshot,
      profileSnapshot,
    ) {
      const club = clubSnapshot.data() ?? {};
      const member = memberSnapshot.data() ?? {};
      const profile = profileSnapshot.data() ?? {};
      if (
        !clubSnapshot.exists ||
        club.ownerId !== auth.uid ||
        club.type !== "community" ||
        club.status !== "active" ||
        club.deletionInProgress === true ||
        !memberSnapshot.exists ||
        member.userId !== auth.uid ||
        member.role !== "owner" ||
        member.banned === true ||
        !profileSnapshot.exists ||
        profile.banned === true ||
        profile.disabled === true
      ) {
        throw new HttpsError(
          "permission-denied",
          "Only the active Club owner can finalize its media.",
        );
      }
      return club;
    }

    // Authorize before touching Storage so arbitrary callers cannot use this
    // callable as an object-existence or metadata oracle.
    const [preflightClub, preflightMember, preflightProfile] =
      await Promise.all([
        clubReference.get(),
        memberReference.get(),
        profileReference.get(),
      ]);
    requireCurrentAuthority(preflightClub, preflightMember, preflightProfile);
    const storageBucket = bucket ?? getStorage().bucket();
    // Storage is an external system. Verify each immutable generation once,
    // after authorization and outside the retryable Firestore callback.
    // The transaction below rechecks the full authority/binding graph before
    // it publishes these already-verified, generation-pinned URLs.
    const [verifiedAvatar, verifiedBanner] = await Promise.all([
      verifiedClubMedia(storageBucket, avatarDescriptor, "avatar"),
      verifiedClubMedia(storageBucket, bannerDescriptor, "banner"),
    ]);

    const finalized = await firestore.runTransaction(async (transaction) => {
      const [
        clubSnapshot,
        memberSnapshot,
        profileSnapshot,
        projectionSnapshot,
      ] = await transaction.getAll(
        clubReference,
        memberReference,
        profileReference,
        projectionReference,
      );
      const club = requireCurrentAuthority(
        clubSnapshot,
        memberSnapshot,
        profileSnapshot,
      );
      if (
        !projectionSnapshot.exists ||
        projectionSnapshot.data()?.clubId !== clubId ||
        projectionSnapshot.data()?.role !== "owner"
      ) {
        throw new HttpsError(
          "data-loss",
          "The Club owner projection is invalid.",
        );
      }

      const avatar = verifiedAvatar;
      const banner = verifiedBanner;

      let loungeReference = null;
      if (avatar !== null) {
        const loungeRoomId = normalizeText(club.loungeRoomId, 128);
        if (!SAFE_DOCUMENT_ID.test(loungeRoomId)) {
          throw new HttpsError("data-loss", "The Club lounge is invalid.");
        }
        loungeReference = firestore.collection("rooms").doc(loungeRoomId);
        const loungeSnapshot = await transaction.get(loungeReference);
        const lounge = loungeSnapshot.data() ?? {};
        if (
          !loungeSnapshot.exists ||
          lounge.clubId !== clubId ||
          lounge.hostId !== auth.uid ||
          lounge.roomKind !== "clubLounge"
        ) {
          throw new HttpsError("data-loss", "The Club lounge is invalid.");
        }
      }

      transaction.update(clubReference, {
        ...(avatar === null
          ? {}
          : {
              avatarUrl: avatar.url,
              avatarGeneration: avatar.generation,
            }),
        ...(banner === null
          ? {}
          : {
              bannerUrl: banner.url,
              bannerGeneration: banner.generation,
            }),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (avatar !== null) {
        transaction.update(projectionReference, { avatarUrl: avatar.url });
        transaction.update(loungeReference, {
          imageUrl: avatar.url,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return { avatar, banner };
    });

    const { avatar, banner } = finalized;

    return {
      clubId,
      avatarUrl: avatar?.url ?? null,
      avatarGeneration: avatar?.generation ?? null,
      bannerUrl: banner?.url ?? null,
      bannerGeneration: banner?.generation ?? null,
    };
  };
}

const finalizeClubMedia = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => createFinalizeClubMediaHandler()(request),
);

module.exports = {
  createCommunityClub,
  createFinalizeClubMediaHandler,
  finalizeClubMedia,
  optionalHttpsUrl,
  profileName,
  verifiedClubMedia,
  validatedCreationInput,
};

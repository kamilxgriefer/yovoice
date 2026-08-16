const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { AccessToken } = require("livekit-server-sdk");
const { Timestamp } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");

const { db, normalizeText } = require("../utils/firestore");
const {
  activeVoiceSessionReference,
  writeActiveVoiceSession,
} = require("./sessions");

const REGION = "europe-west1";

const livekitApiKey = defineSecret("LIVEKIT_API_KEY");

const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");

// Not a secret — this is the public WebSocket endpoint every client needs
// to connect, the same way a hostname would be. Set via `functions/.env`
// (LIVEKIT_URL=wss://your-project.livekit.cloud) or `firebase functions:config`.
const livekitUrl = defineString("LIVEKIT_URL");

const SPEAKING_ROLES = new Set(["host", "speaker"]);
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const VOICE_TOKEN_TTL = "5m";
const VOICE_TOKEN_TTL_SECONDS = 5 * 60;

function buildParticipantName(participant, profile, authenticatedUser) {
  const profileName = normalizeText(profile.displayName, 120);
  if (profileName) return profileName;

  const tokenName = normalizeText(authenticatedUser.token.name, 120);
  if (tokenName) return tokenName;

  const participantName = normalizeText(participant.displayName, 120);
  if (participantName) return participantName;

  const tokenEmail = normalizeText(authenticatedUser.token.email, 160);

  if (tokenEmail) {
    return tokenEmail;
  }

  return "YoVoice user";
}

function restrictionIsActive(restriction, now = Date.now()) {
  if (restriction?.type !== "communicationMute") return false;
  if (restriction.expiresAt == null) return true;
  const expiresAt = typeof restriction.expiresAt.toMillis === "function"
    ? restriction.expiresAt.toMillis()
    : new Date(restriction.expiresAt).getTime();
  return Number.isFinite(expiresAt) && expiresAt > now;
}

function buildParticipantMetadata(participant, profile, authenticatedUser) {
  return JSON.stringify({
    uid: authenticatedUser.uid,
    role: participant.role ?? "listener",
    username: normalizeText(profile.displayName, 80) || null,
    photoUrl: normalizeText(profile.photoUrl, 1000) || null,
  });
}

async function readSnapshots(references, transaction = null) {
  if (transaction && typeof transaction.getAll === "function") {
    return transaction.getAll(...references);
  }
  if (transaction) {
    const snapshots = [];
    for (const reference of references) {
      snapshots.push(await transaction.get(reference));
    }
    return snapshots;
  }
  return Promise.all(references.map((reference) => reference.get()));
}

/**
 * Resolves voice authority from canonical server state. Kept separate from
 * JWT signing so emulator tests can prove denial/allowance without loading
 * production LiveKit secrets.
 */
async function authorizeRoomVoiceAccess(
  roomId,
  authenticatedUser,
  transaction = null,
) {
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A room ID is required.");
  }

  const roomRef = db.collection("rooms").doc(roomId);
  const [roomSnapshot] = await readSnapshots([roomRef], transaction);
  if (!roomSnapshot.exists) {
    throw new HttpsError("not-found", "This room does not exist.");
  }
  const room = roomSnapshot.data() ?? {};
  if (room.status !== "active" || room.isLive !== true) {
    throw new HttpsError(
      "failed-precondition",
      "This room is not currently live.",
    );
  }

  const participantRef = roomRef
    .collection("participants")
    .doc(authenticatedUser.uid);
  const [participantSnapshot, profileSnapshot, restrictionSnapshot] =
    await readSnapshots([
      participantRef,
      db.collection("users").doc(authenticatedUser.uid),
      db.collection("restrictions").doc(authenticatedUser.uid),
    ], transaction);
  if (!participantSnapshot.exists) {
    throw new HttpsError(
      "permission-denied",
      "You must join this room before requesting voice access.",
    );
  }

  const participant = participantSnapshot.data() ?? {};
  const profile = profileSnapshot.exists ? (profileSnapshot.data() ?? {}) : {};
  const restriction = restrictionSnapshot.exists
    ? (restrictionSnapshot.data() ?? {})
    : {};
  if (
    participant.userId !== authenticatedUser.uid ||
    participant.banned === true ||
    !profileSnapshot.exists ||
    profile.banned === true ||
    profile.disabled === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "This account does not have voice access to the room.",
    );
  }

  const clubId = normalizeText(room.clubId, 128);
  if (clubId) {
    const [clubSnapshot, membershipSnapshot] = await readSnapshots([
      db.collection("clubs").doc(clubId),
      db
        .collection("clubs")
        .doc(clubId)
        .collection("members")
        .doc(authenticatedUser.uid),
    ], transaction);
    const club = clubSnapshot.exists ? (clubSnapshot.data() ?? {}) : {};
    const membership = membershipSnapshot.exists
      ? (membershipSnapshot.data() ?? {})
      : {};
    if (
      !clubSnapshot.exists ||
      club.status !== "active" ||
      club.deletionInProgress === true ||
      !membershipSnapshot.exists ||
      membership.userId !== authenticatedUser.uid ||
      membership.banned === true
    ) {
      throw new HttpsError(
        "permission-denied",
        "Only active Club members may join this lounge.",
      );
    }
  } else if (
    room.visibility !== "public" &&
    room.hostId !== authenticatedUser.uid &&
    participant.admittedBy !== room.hostId
  ) {
    // Participant existence alone is not authority: before the matching
    // Rules hardening, any signed-in user could create this row. Private
    // non-Club rooms require a durable host-admission marker, so legacy
    // forged rows fail closed.
    throw new HttpsError(
      "permission-denied",
      "The room host has not admitted this participant.",
    );
  }

  return {
    room,
    participant,
    profile,
    communicationMuted: restrictionIsActive(restriction),
  };
}

function deriveVoiceGrant(access, authenticatedUser) {
  const { room, participant, profile, communicationMuted } = access;
  const isHost = room.hostId === authenticatedUser.uid;
  const isSpeaker = SPEAKING_ROLES.has(participant.role);
  const canPublish =
    !communicationMuted &&
    (isHost || isSpeaker) &&
    participant.isMuted !== true &&
    participant.hostMuted !== true &&
    participant.serverMuted !== true;
  const participantName = buildParticipantName(
    participant,
    profile,
    authenticatedUser,
  );
  return {
    participantName,
    participantMetadata: buildParticipantMetadata(
      participant,
      profile,
      authenticatedUser,
    ),
    permissions: {
      canPublish,
      canSubscribe: true,
      canPublishData: !communicationMuted,
      hidden: false,
      recorder: false,
    },
  };
}

function voiceGrantMatches(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

/**
 * Last authority check before a signed JWT is returned. The same transaction
 * reads every durable gate and writes the per-user session mirror. A ban,
 * mute, room close or membership removal racing token issuance changes one of
 * those read documents, forces a retry, and then fails closed.
 */
async function recordAuthorizedVoiceSession({
  roomId,
  authenticatedUser,
  expectedGrant,
  expiresAt,
}) {
  return db.runTransaction(async (transaction) => {
    const currentAccess = await authorizeRoomVoiceAccess(
      roomId,
      authenticatedUser,
      transaction,
    );
    const currentGrant = deriveVoiceGrant(currentAccess, authenticatedUser);
    if (!voiceGrantMatches(currentGrant, expectedGrant)) {
      throw new HttpsError(
        "aborted",
        "Voice access changed while the token was being issued. Retry.",
      );
    }
    const sessionReference = activeVoiceSessionReference(
      authenticatedUser.uid,
      roomId,
    );
    const currentSession = await transaction.get(sessionReference);
    const currentExpiry = currentSession.data()?.expiresAt;
    const effectiveExpiry =
      currentExpiry instanceof Timestamp &&
      currentExpiry.toMillis() > expiresAt.toMillis()
        ? currentExpiry
        : expiresAt;
    writeActiveVoiceSession(transaction, {
      userId: authenticatedUser.uid,
      roomId,
      expiresAt: effectiveExpiry,
      roomKind: normalizeText(currentAccess.room.roomKind, 80) || null,
      clubId: normalizeText(currentAccess.room.clubId, 128) || null,
    });
    return currentAccess;
  });
}

const createLiveKitToken = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    secrets: [livekitApiKey, livekitApiSecret],
  },
  async (request) => {
    const authenticatedUser = requireAuthentication(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const access = await authorizeRoomVoiceAccess(
      roomId,
      authenticatedUser,
    );
    const grant = deriveVoiceGrant(access, authenticatedUser);
    const { participantName, participantMetadata, permissions } = grant;
    const {
      canPublish,
      canSubscribe,
      canPublishData,
      hidden,
      recorder,
    } = permissions;

    try {
      const accessToken = new AccessToken(
        livekitApiKey.value(),
        livekitApiSecret.value(),
        {
          identity: authenticatedUser.uid,
          name: participantName,
          metadata: participantMetadata,
          ttl: VOICE_TOKEN_TTL,
        },
      );

      accessToken.addGrant({
        roomJoin: true,
        room: roomId,
        canPublish,
        canSubscribe,
        canPublishData,
        hidden,
        recorder,
      });

      const participantToken = await accessToken.toJwt();

      // Mint first, then perform the final transactional revalidation and
      // mirror write. If a sanction commits before this transaction it is
      // observed and denied; if it commits afterwards, its retryable outbox
      // discovers this mirror and revokes the already-minted identity.
      await recordAuthorizedVoiceSession({
        roomId,
        authenticatedUser,
        expectedGrant: grant,
        expiresAt: Timestamp.fromMillis(
          Date.now() + VOICE_TOKEN_TTL_SECONDS * 1000,
        ),
      });

      return {
        serverUrl: livekitUrl.value(),
        participantToken,
        token: participantToken,
        roomName: roomId,
        participantIdentity: authenticatedUser.uid,
        participantName,
        permissions,
      };
    } catch (error) {
      console.error("Failed to create LiveKit token:", error);

      if (error instanceof HttpsError) throw error;

      throw new HttpsError(
        "internal",
        "The LiveKit access token could not be created.",
      );
    }
  },
);

module.exports = {
  authorizeRoomVoiceAccess,
  buildParticipantMetadata,
  buildParticipantName,
  createLiveKitToken,
  deriveVoiceGrant,
  recordAuthorizedVoiceSession,
  restrictionIsActive,
  VOICE_TOKEN_TTL,
  VOICE_TOKEN_TTL_SECONDS,
};

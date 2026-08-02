const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { AccessToken } = require("livekit-server-sdk");

const { requireAuthentication } = require("../utils/auth");

const { db, normalizeText } = require("../utils/firestore");

const REGION = "europe-west1";

const livekitApiKey = defineSecret("LIVEKIT_API_KEY");

const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");

// Not a secret — this is the public WebSocket endpoint every client needs
// to connect, the same way a hostname would be. Set via `functions/.env`
// (LIVEKIT_URL=wss://your-project.livekit.cloud) or `firebase functions:config`.
const livekitUrl = defineString("LIVEKIT_URL");

const SPEAKING_ROLES = new Set(["host", "speaker"]);

function buildParticipantName(request, authenticatedUser) {
  const requestedName = normalizeText(request.data?.participantName, 120);

  if (requestedName) {
    return requestedName;
  }

  const tokenName = normalizeText(authenticatedUser.token.name, 120);

  if (tokenName) {
    return tokenName;
  }

  const tokenEmail = normalizeText(authenticatedUser.token.email, 160);

  if (tokenEmail) {
    return tokenEmail;
  }

  return "YoVoice user";
}

function buildParticipantMetadata(participant, authenticatedUser) {
  return JSON.stringify({
    uid: authenticatedUser.uid,
    role: participant.role ?? "listener",
    username: normalizeText(participant.displayName, 80) || null,
    photoUrl: normalizeText(participant.photoUrl, 1000) || null,
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

    if (!roomId) {
      throw new HttpsError("invalid-argument", "A room ID is required.");
    }

    const roomRef = db.collection("rooms").doc(roomId);
    const roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      throw new HttpsError("not-found", "This room does not exist.");
    }

    const room = roomSnapshot.data();

    const participantRef = roomRef
      .collection("participants")
      .doc(authenticatedUser.uid);
    const participantSnapshot = await participantRef.get();

    if (!participantSnapshot.exists) {
      throw new HttpsError(
        "permission-denied",
        "You must join this room before requesting voice access.",
      );
    }

    const participant = participantSnapshot.data();

    const isHost = room.hostId === authenticatedUser.uid;
    const isSpeaker = SPEAKING_ROLES.has(participant.role);

    // Every permission below is computed from Firestore, never from what
    // the client asked for — the client only ever supplies the room it
    // wants to join.
    const canPublish = (isHost || isSpeaker) && participant.isMuted !== true;
    const canSubscribe = true;
    const canPublishData = true;
    const hidden = false;
    const recorder = false;

    const participantName = buildParticipantName(request, authenticatedUser);

    const participantMetadata = buildParticipantMetadata(
      participant,
      authenticatedUser,
    );

    try {
      const accessToken = new AccessToken(
        livekitApiKey.value(),
        livekitApiSecret.value(),
        {
          identity: authenticatedUser.uid,
          name: participantName,
          metadata: participantMetadata,
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

      return {
        serverUrl: livekitUrl.value(),
        participantToken,
        token: participantToken,
        roomName: roomId,
        participantIdentity: authenticatedUser.uid,
        participantName,
        permissions: {
          canPublish,
          canSubscribe,
          canPublishData,
          hidden,
          recorder,
        },
      };
    } catch (error) {
      console.error("Failed to create LiveKit token:", error);

      throw new HttpsError(
        "internal",
        "The LiveKit access token could not be created.",
      );
    }
  },
);

module.exports = {
  createLiveKitToken,
};

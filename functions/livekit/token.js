const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { AccessToken } = require("livekit-server-sdk");

const { requireAuthentication } = require("../utils/auth");

const { normalizeText } = require("../utils/firestore");

const REGION = "europe-west1";

const livekitApiKey = defineSecret("LIVEKIT_API_KEY");

const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");

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

function buildParticipantMetadata(request, authenticatedUser) {
  const role = normalizeText(authenticatedUser.token.role, 40);

  const username = normalizeText(request.data?.username, 80);

  const photoUrl = normalizeText(request.data?.photoUrl, 1000);

  return JSON.stringify({
    uid: authenticatedUser.uid,
    role: role || "user",
    username: username || null,
    photoUrl: photoUrl || null,
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

    const roomName = normalizeText(request.data?.roomName, 128);

    if (!roomName) {
      throw new HttpsError(
        "invalid-argument",
        "A LiveKit room name is required.",
      );
    }

    const canPublish = request.data?.canPublish !== false;

    const canSubscribe = request.data?.canSubscribe !== false;

    const canPublishData = request.data?.canPublishData !== false;

    const hidden = request.data?.hidden === true;

    const recorder = request.data?.recorder === true;

    const participantName = buildParticipantName(request, authenticatedUser);

    const participantMetadata = buildParticipantMetadata(
      request,
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
        room: roomName,
        canPublish,
        canSubscribe,
        canPublishData,
        hidden,
        recorder,
      });

      const token = await accessToken.toJwt();

      return {
        token,
        roomName,
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

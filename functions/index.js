const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { AccessToken } = require("livekit-server-sdk");

initializeApp();

const liveKitUrl = defineSecret("LIVEKIT_URL");
const liveKitApiKey = defineSecret("LIVEKIT_API_KEY");
const liveKitApiSecret = defineSecret("LIVEKIT_API_SECRET");

exports.createLiveKitToken = onCall(
  {
    region: "europe-west1",
    secrets: [liveKitUrl, liveKitApiKey, liveKitApiSecret],
    enforceAppCheck: false
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to join voice chat."
      );
    }

    const roomId = String(request.data?.roomId ?? "").trim();
    const requestedName = String(
      request.data?.participantName ?? ""
    ).trim();

    if (!roomId || roomId.length > 128) {
      throw new HttpsError(
        "invalid-argument",
        "A valid roomId is required."
      );
    }

    const roomSnapshot = await getFirestore()
      .collection("rooms")
      .doc(roomId)
      .get();

    if (!roomSnapshot.exists) {
      throw new HttpsError("not-found", "The room does not exist.");
    }

    const roomData = roomSnapshot.data() ?? {};
    if (roomData.status === "archived" || roomData.status === "suspended") {
      throw new HttpsError(
        "failed-precondition",
        "Voice chat is unavailable in this room."
      );
    }

    const identity = request.auth.uid;
    const fallbackName =
      request.auth.token.name ||
      request.auth.token.email ||
      "YoVoice user";
    const participantName =
      requestedName.slice(0, 80) || String(fallbackName).slice(0, 80);
    const liveKitRoomName = `yovoice_${roomId}`;

    const token = new AccessToken(
      liveKitApiKey.value(),
      liveKitApiSecret.value(),
      {
        identity,
        name: participantName,
        ttl: "1h",
        metadata: JSON.stringify({
          firebaseUid: identity,
          yovoiceRoomId: roomId
        })
      }
    );

    token.addGrant({
      roomJoin: true,
      room: liveKitRoomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true
    });

    return {
      serverUrl: liveKitUrl.value(),
      participantToken: await token.toJwt()
    };
  }
);

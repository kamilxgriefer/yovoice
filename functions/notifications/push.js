const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");

const REGION = "europe-west1";

// One title-builder per client-creatable NotificationType
// (app_notification.dart's `title` getter, mirrored server-side so push
// copy matches the in-app copy). 'system'/'moderation' are included even
// though clients can never create them — the Admin SDK bypasses
// firestore.rules, so a future admin/audit trigger writing one of these
// still gets a push.
const PUSH_TITLES = {
  friendRequest: (actor) => `${actor} sent you a friend request`,
  friendAccepted: (actor) => `${actor} accepted your friend request`,
  follow: (actor) => `${actor} started following you`,
  clubInvite: (actor, label) =>
    label ? `${actor} invited you to ${label}` : `${actor} invited you to a club`,
  clubInviteAccepted: (actor, label) =>
    label ? `${actor} joined ${label}` : `${actor} accepted your club invitation`,
  roomInvite: (actor, label) =>
    label ? `${actor} invited you to ${label}` : `${actor} invited you to a room`,
  broadcastInvite: (actor, label) =>
    label ? `${actor} invited you to ${label}` : `${actor} invited you to a broadcast`,
  directMessage: (actor) => `${actor} sent you a message`,
  mention: (actor, label) =>
    label ? `${actor} mentioned you in ${label}` : `${actor} mentioned you`,
  reply: (actor, label) =>
    label ? `${actor} replied to you in ${label}` : `${actor} replied to you`,
  achievementUnlocked: (_actor, label) =>
    label ? `Achievement unlocked: ${label}` : "Achievement unlocked",
  moderation: (_actor, label) => label || "A moderator took action on your account",
  system: (_actor, label) => label || "YoVoice",
};

// notification_service.dart writes the Firestore doc directly from the
// client (see firestore.rules) — there is no Cloud Function in that path.
// This trigger is what turns "a notification doc exists" into "a push
// actually goes out," so it has to run for every notification type,
// client- or Admin-SDK-created.
exports.onNotificationCreated = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: REGION,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notification = snapshot.data();
    const { userId, notificationId } = event.params;
    const type = notification.type;

    const buildTitle = PUSH_TITLES[type];
    if (!buildTitle) {
      logger.warn(`Skipping push for unknown notification type: ${type}`);
      return;
    }

    try {
      const userDoc = await db.collection("users").doc(userId).get();
      const preferences = userDoc.data()?.notificationPreferences || {};
      // Preferences are opt-out: absent/undefined means enabled. Marketing-
      // style types aren't part of this trigger at all yet, so there is no
      // "off by default" category here — every type here is transactional.
      if (preferences[type] === false) return;

      const tokensSnap = await db
        .collection("users")
        .doc(userId)
        .collection("fcmTokens")
        .get();
      if (tokensSnap.empty) return;

      const actorName = notification.actorName || "YoVoice user";
      const title = buildTitle(actorName, notification.targetLabel || null);
      const tokens = tokensSnap.docs.map((doc) => doc.id);

      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: { title },
        data: {
          type: String(type),
          targetId: notification.targetId ? String(notification.targetId) : "",
          actorId: notification.actorId ? String(notification.actorId) : "",
          notificationId,
        },
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
      });

      const staleTokens = [];
      response.responses.forEach((result, index) => {
        if (result.success) return;
        const code = result.error?.code;
        if (
          code === "messaging/invalid-registration-token" ||
          code === "messaging/registration-token-not-registered"
        ) {
          staleTokens.push(tokens[index]);
        } else {
          logger.error("FCM send failed", { code, message: result.error?.message });
        }
      });

      if (staleTokens.length > 0) {
        const batch = db.batch();
        const tokensRef = db.collection("users").doc(userId).collection("fcmTokens");
        staleTokens.forEach((token) => batch.delete(tokensRef.doc(token)));
        await batch.commit();
      }
    } catch (error) {
      // A push-delivery failure must never surface as a retried, crashing
      // trigger — the notification doc itself already exists and is
      // correct; push is best-effort on top of it.
      logger.error("onNotificationCreated failed", error);
    }
  },
);

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const { buildPushMessage } = require("./push_payload");
const { isCurrentNotificationGeneration } = require("./push_generation");
const {
  isLegacySocialNotificationId,
  socialNotificationSourceIsCurrent: sourceIsCurrent,
} = require("./social_source");
const {
  FIRESTORE_CLEANUP_BATCH_SIZE,
  MAX_FCM_TOKEN_DOCUMENT_READS,
  planTokenDocuments,
  sendMulticastInChunks,
} = require("./push_delivery");

const REGION = "europe-west1";

// One title-builder per server-created NotificationType
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
  liveStarted: (actor, label) =>
    label ? `${actor} is live: ${label}` : `${actor} is live now`,
  directMessage: (actor) => `${actor} sent you a message`,
  directCall: (actor) => `${actor} is calling you`,
  missedCall: (actor) => `Missed call from ${actor}`,
  mention: (actor, label) =>
    label ? `${actor} mentioned you in ${label}` : `${actor} mentioned you`,
  reply: (actor, label) =>
    label ? `${actor} replied to you in ${label}` : `${actor} replied to you`,
  achievementUnlocked: (_actor, label) =>
    label ? `Achievement unlocked: ${label}` : "Achievement unlocked",
  moderation: (_actor, label) => label || "A moderator took action on your account",
  system: (_actor, label) => label || "YoVoice",
};

async function deleteTokenReferences(references) {
  const unique = new Map();
  for (const reference of references) {
    if (reference?.path) unique.set(reference.path, reference);
  }
  const bounded = [...unique.values()];
  for (let index = 0; index < bounded.length;
    index += FIRESTORE_CLEANUP_BATCH_SIZE) {
    const batch = db.batch();
    for (const reference of bounded.slice(
      index,
      index + FIRESTORE_CLEANUP_BATCH_SIZE,
    )) {
      batch.delete(reference);
    }
    await batch.commit();
  }
}

async function socialNotificationSourceIsCurrent(args) {
  return sourceIsCurrent({
    ...args,
    firestore: args.firestore ?? db,
  });
}

// Authoritative callables/triggers create the Firestore notification row.
// Rules deny client creates. This trigger turns that durable in-app event
// into a best-effort push for every supported type.
exports.onNotificationCreated = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: REGION,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notification = snapshot.data();
    // Firestore onCreate supplies data in production. The local emulator can
    // still drain an incomplete queued CloudEvent during shutdown; treat that
    // as a non-event instead of crashing the Functions worker.
    if (!notification) return;
    const { userId, notificationId } = event.params;
    const type = notification.type;

    const buildTitle = PUSH_TITLES[type];
    if (!buildTitle) {
      logger.warn(`Skipping push for unknown notification type: ${type}`);
      return;
    }

    try {
      // Cleanup is an inbox-integrity responsibility, not a push-eligibility
      // decision. Run it before preferences/token early returns so an opted-
      // out user or a user with no registered device cannot retain a legacy
      // duplicate or a source-less actionable row.
      let currentNotification = await snapshot.ref.get();
      if (!isCurrentNotificationGeneration(snapshot, currentNotification)) {
        return;
      }
      let currentData = currentNotification.data();
      if (
        !(await socialNotificationSourceIsCurrent({
          recipientId: userId,
          notificationId,
          notification: currentData,
        }))
      ) {
        await snapshot.ref
          .delete({ lastUpdateTime: currentNotification.updateTime })
          .catch((error) => {
            logger.info("Skipped stale social notification cleanup", {
              notificationId,
              code: error?.code ?? "unknown",
            });
          });
        return;
      }

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
        // Security Rules require this to equal request.time, so a client
        // cannot forge a future timestamp to crowd out real devices.
        .orderBy("updatedAt", "desc")
        // Bound both Firestore cost and cleanup work even if a modified
        // client previously created an excessive number of token docs.
        .limit(MAX_FCM_TOKEN_DOCUMENT_READS)
        .get();
      if (tokensSnap.empty) return;

      // Re-check both document generation and exact graph generation as the
      // final operation before the network send. Cleanup above is durable;
      // this second read narrows cancel/unfollow-vs-FCM TOCTOU.
      currentNotification = await snapshot.ref.get();
      if (!isCurrentNotificationGeneration(snapshot, currentNotification)) {
        return;
      }
      currentData = currentNotification.data();
      if (
        !(await socialNotificationSourceIsCurrent({
          recipientId: userId,
          notificationId,
          notification: currentData,
        }))
      ) {
        return;
      }

      const actorName = currentData.actorName || "YoVoice user";
      const title = buildTitle(actorName, currentData.targetLabel || null);
      const plan = planTokenDocuments(tokensSnap.docs);
      const delivery = await sendMulticastInChunks({
        tokens: plan.tokens,
        messaging: getMessaging(),
        buildMessage: (tokens) => buildPushMessage({
          tokens,
          type,
          targetId: currentData.targetId,
          actorId: currentData.actorId,
          notificationId,
          title,
        }),
      });

      for (const failure of delivery.failures) {
        logger.error("FCM send failed", { code: failure.code });
      }
      for (const failure of delivery.batchErrors) {
        logger.error("FCM multicast batch failed", failure);
      }

      const staleReferences = delivery.staleTokens
        .map((token) => plan.tokenReferences.get(token))
        .filter(Boolean);
      await deleteTokenReferences([
        ...plan.overflowReferences,
        ...staleReferences,
      ]);

      if (plan.overflowReferences.length > 0) {
        logger.warn("Pruned FCM tokens above the per-user cap", {
          userId,
          pruned: plan.overflowReferences.length,
          readLimitReached:
            tokensSnap.size === MAX_FCM_TOKEN_DOCUMENT_READS,
        });
      }
    } catch (error) {
      // A push-delivery failure must never surface as a retried, crashing
      // trigger — the notification doc itself already exists and is
      // correct; push is best-effort on top of it.
      logger.error("onNotificationCreated failed", error);
    }
  },
);

module.exports = {
  onNotificationCreated: exports.onNotificationCreated,
  deleteTokenReferences,
  isCurrentNotificationGeneration,
  isLegacySocialNotificationId,
  socialNotificationSourceIsCurrent,
};

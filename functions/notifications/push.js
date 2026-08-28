const crypto = require("node:crypto");

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const { buildPushMessage } = require("./push_payload");
const { isCurrentNotificationGeneration } = require("./push_generation");
const {
  isLegacySocialNotificationId,
  notificationSourceIsCurrent: sourceIsCurrent,
  socialNotificationSourceIsCurrent: socialSourceIsCurrent,
} = require("./social_source");
const {
  FIRESTORE_CLEANUP_BATCH_SIZE,
  MAX_FCM_TOKEN_DOCUMENT_READS,
  planTokenDocuments,
  sendMulticastInChunks,
} = require("./push_delivery");

const REGION = "europe-west1";
const TERMINAL_PUSH_DELIVERY_STATUSES = new Set([
  "sent",
  "skipped",
  "permanent-failure",
]);

function pushDeliveryAttemptId({
  userId,
  notificationId,
  notificationSnapshot,
}) {
  const createdAt = notificationSnapshot?.createTime;
  const generation = Number.isSafeInteger(createdAt?.seconds) &&
      Number.isSafeInteger(createdAt?.nanoseconds)
    ? `${createdAt.seconds}:${createdAt.nanoseconds}`
    : typeof createdAt?.toMillis === "function"
      ? `${createdAt.toMillis()}:0`
      : "unknown";
  // Eventarc can redeliver one Firestore generation with a different envelope
  // id. Platform collapse identifiers therefore bind to the durable document
  // generation rather than the transport event.
  const identity = `${userId}\u0000${notificationId}\u0000${generation}`;
  return crypto.createHash("sha256").update(identity).digest("hex");
}

/**
 * Claims one notification generation immediately before the external FCM
 * operation. The claim is deliberately terminal: after this transaction
 * commits, no retry may send again, even if the worker crashes or loses FCM's
 * response. This chooses at-most-once delivery over duplicate audible pushes.
 * Failures before the claim still bubble to Eventarc and remain retryable.
 */
async function claimPushDelivery(args, {
  now = Timestamp.now(),
  validate = null,
  firestore = db,
} = {}) {
  const claimId = pushDeliveryAttemptId(args);
  const reference = args.notificationSnapshot?.ref;
  if (!reference) return { state: "terminal", reason: "missing-reference" };
  if (typeof now?.toMillis !== "function") {
    throw new TypeError("A Firestore Timestamp is required for a push claim.");
  }
  return firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    if (!isCurrentNotificationGeneration(args.notificationSnapshot, current)) {
      return { state: "terminal", reason: "stale-generation" };
    }
    const data = current.data() ?? {};
    const status = data.pushDeliveryStatus;
    // `dispatching` is the durable uncertainty boundary: FCM may already have
    // accepted the message. Legacy leased/retryable states are also fail-closed
    // during rollout because reclaiming them could duplicate an earlier send.
    if (status !== undefined || typeof data.pushClaimEventId === "string") {
      return { state: "terminal", reason: status };
    }
    if (validate && !(await validate(transaction, data))) {
      transaction.update(reference, {
        pushDeliveryStatus: "skipped",
        pushSkipReason: "invalid-source",
        pushCompletedAt: now,
      });
      return { state: "terminal", reason: "invalid-source" };
    }
    transaction.update(reference, {
      pushDeliveryStatus: "dispatching",
      pushClaimEventId: claimId,
      pushClaimedAt: now,
      pushAttemptCount: 1,
      pushLeaseExpiresAt: FieldValue.delete(),
      pushLastErrorCode: FieldValue.delete(),
    });
    return {
      state: "claimed",
      claim: { claimId, collapseId: claimId },
    };
  });
}

async function completePushDelivery(args, claim, {
  status = "sent",
  now = Timestamp.now(),
} = {}) {
  if (!TERMINAL_PUSH_DELIVERY_STATUSES.has(status)) {
    throw new TypeError("Push completion must be terminal.");
  }
  const reference = args.notificationSnapshot?.ref;
  if (!reference || !claim?.claimId) return false;
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    if (!isCurrentNotificationGeneration(args.notificationSnapshot, current) ||
        current.data()?.pushDeliveryStatus !== "dispatching" ||
        current.data()?.pushClaimEventId !== claim.claimId) {
      return false;
    }
    transaction.update(reference, {
      pushDeliveryStatus: status,
      pushLeaseExpiresAt: FieldValue.delete(),
      pushLastErrorCode: FieldValue.delete(),
      pushCompletedAt: now,
      ...(status === "sent" ? { pushSentAt: now } : {}),
    });
    return true;
  });
}

async function skipPushDelivery(args, reason, now = Timestamp.now()) {
  const reference = args.notificationSnapshot?.ref;
  if (!reference) return false;
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    if (!isCurrentNotificationGeneration(args.notificationSnapshot, current)) {
      return false;
    }
    const status = current.data()?.pushDeliveryStatus;
    if (status !== undefined ||
        typeof current.data()?.pushClaimEventId === "string") return false;
    transaction.update(reference, {
      pushDeliveryStatus: "skipped",
      pushSkipReason: String(reason || "not-eligible").slice(0, 120),
      pushCompletedAt: now,
    });
    return true;
  });
}

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

async function notificationSourceIsCurrent(args) {
  return sourceIsCurrent({
    ...args,
    firestore: args.firestore ?? db,
  });
}

async function socialNotificationSourceIsCurrent(args) {
  return socialSourceIsCurrent({
    ...args,
    firestore: args.firestore ?? db,
  });
}

async function cleanupInvalidSource({
  snapshot,
  currentNotification,
  notificationId,
}) {
  if (!currentNotification?.exists) return;
  await snapshot.ref
    .delete({ lastUpdateTime: currentNotification.updateTime })
    .catch((error) => {
      logger.info("Skipped stale notification cleanup", {
        notificationId,
        code: error?.code ?? "unknown",
      });
    });
}

// Authoritative callables/triggers create the Firestore notification row.
// Rules deny client creates. This trigger turns that durable in-app event
// into a best-effort push for every supported type.
async function handleNotificationCreated(event, {
  messaging = getMessaging(),
  afterExternalSend = null,
  beforeDispatchClaim = null,
} = {}) {
  const snapshot = event.data;
  if (!snapshot) return;

  const notification = snapshot.data();
  // Firestore onCreate supplies data in production. The local emulator can
  // still drain an incomplete queued CloudEvent during shutdown; treat that
  // as a non-event instead of crashing the Functions worker.
  if (!notification) return;
  const { userId, notificationId } = event.params;
  const type = notification.type;
  const deliveryArgs = {
    eventId: event.id,
    userId,
    notificationId,
    notificationSnapshot: snapshot,
  };

  const buildTitle = PUSH_TITLES[type];
  if (!buildTitle) {
    logger.warn(`Skipping push for unknown notification type: ${type}`);
    await skipPushDelivery(deliveryArgs, "unknown-type");
    return;
  }

  let claimed = false;
  try {
    // All reads, cleanup and payload construction happen before the terminal
    // dispatch claim. An exception in this section remains safe to retry.
    let currentNotification = await snapshot.ref.get();
    if (!isCurrentNotificationGeneration(snapshot, currentNotification)) return;
    let currentData = currentNotification.data();
    if (!(await notificationSourceIsCurrent({
      recipientId: userId,
      notificationId,
      notification: currentData,
    }))) {
      await skipPushDelivery(deliveryArgs, "invalid-source");
      currentNotification = await snapshot.ref.get();
      await cleanupInvalidSource({
        snapshot,
        currentNotification,
        notificationId,
      });
      return;
    }

    const userDoc = await db.collection("users").doc(userId).get();
    const preferences = userDoc.data()?.notificationPreferences || {};
    // `bellSuppressed` controls the in-app bell only. A direct-message push is
    // still expected while the app is backgrounded; active-conversation
    // foreground suppression is a client concern and does not alter delivery.
    if (preferences[type] === false) {
      await skipPushDelivery(deliveryArgs, "preference-disabled");
      return;
    }

    const tokensSnap = await db
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .orderBy("updatedAt", "desc")
      .limit(MAX_FCM_TOKEN_DOCUMENT_READS)
      .get();
    if (tokensSnap.empty) {
      await skipPushDelivery(deliveryArgs, "no-token");
      return;
    }

    currentNotification = await snapshot.ref.get();
    if (!isCurrentNotificationGeneration(snapshot, currentNotification)) return;
    currentData = currentNotification.data();
    const actorName = currentData.actorName || "YoVoice user";
    const title = buildTitle(actorName, currentData.targetLabel || null);
    const plan = planTokenDocuments(tokensSnap.docs);
    if (plan.tokens.length === 0) {
      await skipPushDelivery(deliveryArgs, "no-usable-token");
      return;
    }

    // This transaction revalidates the source and notification generation,
    // then writes the irreversible claim. Firestore retries the transaction if
    // the message/conversation/room changes before commit.
    if (beforeDispatchClaim) await beforeDispatchClaim();
    const acquisition = await claimPushDelivery(deliveryArgs, {
      validate: (transaction, data) => notificationSourceIsCurrent({
        recipientId: userId,
        notificationId,
        notification: data,
        reader: transaction,
      }),
    });
    if (acquisition.state !== "claimed") {
      if (acquisition.reason === "invalid-source") {
        currentNotification = await snapshot.ref.get();
        await cleanupInvalidSource({
          snapshot,
          currentNotification,
          notificationId,
        });
      }
      return;
    }
    claimed = true;
    const claim = acquisition.claim;

    const delivery = await sendMulticastInChunks({
      tokens: plan.tokens,
      messaging,
      buildMessage: (tokens) => buildPushMessage({
        tokens,
        type,
        targetId: currentData.targetId,
        actorId: currentData.actorId,
        notificationId,
        title,
        collapseId: claim.collapseId,
      }),
    });
    if (afterExternalSend) await afterExternalSend(delivery);

    for (const failure of delivery.failures) {
      logger.error("FCM send failed", { code: failure.code });
    }
    for (const failure of delivery.batchErrors) {
      logger.error("FCM multicast batch failed", failure);
    }

    const terminalStatus = delivery.successCount > 0
      ? "sent"
      : delivery.attempted === 0 ||
          delivery.staleTokens.length === delivery.attempted
        ? "skipped"
        : "permanent-failure";
    await completePushDelivery(deliveryArgs, claim, {
      status: terminalStatus,
    });

    const staleReferences = delivery.staleTokens
      .map((token) => plan.tokenReferences.get(token))
      .filter(Boolean);
    await deleteTokenReferences([
      ...plan.overflowReferences,
      ...staleReferences,
    ]).catch((error) => {
      logger.error("FCM token cleanup failed after terminal delivery", {
        code: error?.code ?? "unknown",
      });
    });

    if (plan.overflowReferences.length > 0) {
      logger.warn("Pruned FCM tokens above the per-user cap", {
        userId,
        pruned: plan.overflowReferences.length,
        readLimitReached: tokensSnap.size === MAX_FCM_TOKEN_DOCUMENT_READS,
      });
    }
  } catch (error) {
    logger.error("onNotificationCreated failed", error);
    if (claimed) {
      // Never throw after the claim. The network operation may have succeeded
      // even when its response or the following Firestore write was lost.
      // Leaving `dispatching` is an honest durable uncertain state, and a
      // redelivery will not send a second audible notification.
      return;
    }
    throw error;
  }
}

exports.onNotificationCreated = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: REGION,
    retry: true,
  },
  handleNotificationCreated,
);

module.exports = {
  onNotificationCreated: exports.onNotificationCreated,
  claimPushDelivery,
  completePushDelivery,
  deleteTokenReferences,
  handleNotificationCreated,
  isCurrentNotificationGeneration,
  isLegacySocialNotificationId,
  notificationSourceIsCurrent,
  pushDeliveryAttemptId,
  skipPushDelivery,
  socialNotificationSourceIsCurrent,
};

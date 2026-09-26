const crypto = require("node:crypto");

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const { eventLedgerReference } = require("./canonical");
const { buildPushMessage } = require("./push_payload");
const { isCurrentNotificationGeneration } = require("./push_generation");
const {
  isLegacySocialNotificationId,
  isRegisteredNotificationType,
  notificationSourceIsCurrent: sourceIsCurrent,
  socialNotificationSourceIsCurrent: socialSourceIsCurrent,
} = require("./social_source");
const {
  FIRESTORE_CLEANUP_BATCH_SIZE,
  MAX_FCM_TOKEN_DOCUMENT_READS,
  planTokenDocuments,
  registrationsNotBeforeEpoch,
  sendMulticastInChunks,
} = require("./push_delivery");

const REGION = "europe-west1";
const TERMINAL_PUSH_DELIVERY_STATUSES = new Set([
  "sent",
  "skipped",
  "permanent-failure",
]);

// Actionable rows are deleted the moment they are answered: a friend request
// row disappears on accept, decline, cancel or block, and with it the
// pushDeliveryStatus / pushSkipReason that said whether a system notification
// was ever sent. For these types the same decision is also kept on a
// short-lived receipt in notificationDeliveryEvents (already TTL-managed on
// expiresAt), so "I never got a notification" can still be answered after
// the request was resolved. It records only the decision — no token, no
// title, no body — and it never changes who receives a push.
const PUSH_DECISION_LEDGER_TYPES = new Set(["friendRequest"]);
const PUSH_DECISION_RETENTION_MS = 14 * 24 * 60 * 60 * 1000;

function pushDecisionLedgerReference(userId, notificationId, firestore = db) {
  return eventLedgerReference(
    `pushDecision\u0000${userId}\u0000${notificationId}`,
    firestore,
  );
}

function notificationDigest(userId, notificationId) {
  return crypto
    .createHash("sha256")
    .update(`${userId}\u0000${notificationId}`)
    .digest("hex")
    .slice(0, 16);
}

/**
 * Keeps the push decision for an actionable type on its short-lived receipt.
 *
 * Written only after the row itself recorded the same decision, and never
 * allowed to fail delivery: it is evidence, not part of the send. A lost
 * receipt write is logged and the push path carries on unchanged.
 */
async function recordPushDecision({
  userId,
  notificationId,
  type,
  pushDeliveryStatus,
  pushSkipReason = null,
  now = Timestamp.now(),
  firestore = db,
}) {
  if (!PUSH_DECISION_LEDGER_TYPES.has(type)) return false;
  if (!userId || !notificationId) return false;
  const notification = notificationDigest(userId, notificationId);
  // Structured and uid-free: the digest joins a log line to its receipt.
  logger.info("Push decision", {
    type,
    pushDeliveryStatus,
    pushSkipReason,
    notification,
  });
  try {
    await pushDecisionLedgerReference(userId, notificationId, firestore).set(
      {
        kind: "pushDecision",
        recipientId: userId,
        notificationId: String(notificationId).slice(0, 320),
        type,
        pushDeliveryStatus,
        pushSkipReason,
        decidedAt: now,
        expiresAt: Timestamp.fromMillis(
          now.toMillis() + PUSH_DECISION_RETENTION_MS,
        ),
      },
      { merge: true },
    );
    return true;
  } catch (error) {
    logger.warn("Push decision receipt was not written", {
      type,
      notification,
      code: error?.code ?? null,
    });
    return false;
  }
}

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
    label ? `${actor} invited you to ${label}` : `${actor} invited you to a server`,
  clubInviteAccepted: (actor, label) =>
    label ? `${actor} joined ${label}` : `${actor} accepted your server invitation`,
  roomInvite: (actor, label) =>
    label ? `${actor} invited you to ${label}` : `${actor} invited you to a conversation`,
  broadcastInvite: (actor, label) =>
    label ? `${actor} invited you to ${label}` : `${actor} invited you to a broadcast`,
  liveStarted: (actor, label) =>
    label ? `${actor} is live: ${label}` : `${actor} is live now`,
  directMessage: (actor) => `${actor} sent you a message`,
  directCall: (actor, label) => label === "Incoming video call"
    ? `${actor} is video calling you`
    : `${actor} is calling you`,
  missedCall: (actor, label) => label === "Missed video call"
    ? `Missed video call from ${actor}`
    : `Missed call from ${actor}`,
  mention: (actor, label) =>
    label ? `${actor} mentioned you in ${label}` : `${actor} mentioned you`,
  reply: (actor, label) =>
    label ? `${actor} replied to you in ${label}` : `${actor} replied to you`,
  // Engagement and Server types (2026-09-19). The lock-screen body stays the
  // generic "Tap to open YO Voice": a comment's words never enter a push.
  momentComment: (actor) => `${actor} commented on your Moment`,
  reelComment: (actor) => `${actor} commented on your Yeel`,
  commentMention: (actor) => `${actor} mentioned you in a comment`,
  serverEventReminder: (_actor, label) =>
    label ? `Starting soon: ${label}` : "An event is starting soon",
  serverRole: (actor, label) =>
    label ? `${actor} promoted you in ${label}` : `${actor} promoted you in a server`,
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
  // Seam, like the three above: every shipped type currently has both a push
  // title and a source validator, so the "unregistered type" branch cannot
  // be reached with real data. A test injects the registry to prove the
  // branch keeps the recipient's row instead of deleting it.
  isRegisteredType = isRegisteredNotificationType,
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
  // The receipt mirrors a decision the row has just recorded, so it is
  // written only when that row write happened.
  const skip = async (reason) => {
    if (await skipPushDelivery(deliveryArgs, reason)) {
      await recordPushDecision({
        userId,
        notificationId,
        type,
        pushDeliveryStatus: "skipped",
        pushSkipReason: reason,
      });
    }
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
      // Two different refusals arrive here. A row whose source is genuinely
      // gone is cleaned up. A row of a type nobody registered a validator
      // for is only SKIPPED: "we do not know how to revalidate this" must
      // degrade to no push, never to destroying the recipient's bell row.
      if (!isRegisteredType(currentData?.type)) {
        logger.warn("Skipping push for an unregistered notification type", {
          notificationId,
          type: typeof currentData?.type === "string"
            ? currentData.type.slice(0, 64)
            : null,
        });
        await skipPushDelivery(deliveryArgs, "unregistered-type");
        return;
      }
      await skip("invalid-source");
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
      await skip("preference-disabled");
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
      await skip("no-token");
      return;
    }

    currentNotification = await snapshot.ref.get();
    if (!isCurrentNotificationGeneration(snapshot, currentNotification)) return;
    currentData = currentNotification.data();
    const actorName = currentData.actorName || "YoVoice user";
    const title = buildTitle(actorName, currentData.targetLabel || null);
    const plan = planTokenDocuments(registrationsNotBeforeEpoch(
      tokensSnap.docs,
      userDoc.data()?.authSessionEpoch,
    ));
    if (plan.tokens.length === 0) {
      await skip("no-usable-token");
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
        await recordPushDecision({
          userId,
          notificationId,
          type,
          pushDeliveryStatus: "skipped",
          pushSkipReason: "invalid-source",
        });
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
    // "dispatching" first: if the completion write is lost, the receipt
    // still says FCM was about to be called.
    await recordPushDecision({
      userId,
      notificationId,
      type,
      pushDeliveryStatus: "dispatching",
    });

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
        targetSubId: currentData.targetSubId ?? null,
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
    if (await completePushDelivery(deliveryArgs, claim, {
      status: terminalStatus,
    })) {
      await recordPushDecision({
        userId,
        notificationId,
        type,
        pushDeliveryStatus: terminalStatus,
      });
    }

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
    // Firebase Messaging errors may carry provider response details. Keep
    // logs useful without persisting registration tokens or payload content.
    logger.error("onNotificationCreated failed", {
      errorName: error?.name ?? null,
      errorCode: error?.code ?? null,
    });
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
  PUSH_DECISION_LEDGER_TYPES,
  PUSH_DECISION_RETENTION_MS,
  PUSH_TITLES,
  claimPushDelivery,
  completePushDelivery,
  deleteTokenReferences,
  handleNotificationCreated,
  isCurrentNotificationGeneration,
  isLegacySocialNotificationId,
  notificationSourceIsCurrent,
  pushDecisionLedgerReference,
  pushDeliveryAttemptId,
  recordPushDecision,
  skipPushDelivery,
  socialNotificationSourceIsCurrent,
};

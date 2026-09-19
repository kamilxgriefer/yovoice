/**
 * Comment notifications for Voice Moments and Yeels (ADR-212).
 *
 * The producer is a Firestore trigger on the comment subcollection, not a
 * change to the four comment callables: `createMomentComment`,
 * `finalizeVoiceCommentDraft`, `createReelComment` and
 * `finalizeReelVoiceCommentDraft` are transactional, idempotency-ledgered
 * and heavily tested, and a notification is derived from the COMMITTED
 * comment rather than from a second best-effort write. One create trigger
 * therefore covers both the text and the voice path of each surface.
 *
 * Two rows can come out of one comment:
 *   - `momentComment` / `reelComment` to the parent's author (never to the
 *     commenter, and never a second row when the author is also mentioned);
 *   - `commentMention` to every id the server-only mention record names,
 *     minus the commenter and the author.
 *
 * The matching delete trigger retires both, so a comment that is removed —
 * by its author, by the Yeel's author, or by a parent's deletion cascade —
 * takes its notifications with it. Retirement is driven by the delivery
 * ledger written in the same transaction as each row, which is the only
 * place that records WHICH recipient and WHICH document id a comment
 * produced.
 */
const { onDocumentCreated, onDocumentDeleted } = require(
  "firebase-functions/v2/firestore",
);
const { logger } = require("firebase-functions/v2");
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  consumeRateLimit,
  rateLimitReference,
} = require("../integrity/guards");
const {
  createNotificationForEvent,
  eventLedgerReference,
} = require("./canonical");
const {
  commentMentionReference,
  exactCommentMentions,
} = require("./comment_mentions");
const {
  commentMentionSourceIsCurrent,
  commentNotificationSourceIsCurrent,
  commentSourcePath,
} = require("./engagement_source");
const { documentGeneration } = require("./social_source");

const REGION = "europe-west1";
// The same bound the direct-message notification uses: a comment row that
// lands more than half an hour late is noise, not delivery.
const COMMENT_RETRY_WINDOW_MS = 30 * 60_000;
// Per-actor mention budget, charged once per intended recipient. Five
// mentions per comment multiplied by the callables' comment budget is a
// real fan-out surface, so mentions get their own sustained ceiling; the
// comment row itself is never throttled.
const MENTION_BUDGET = Object.freeze({
  maxEvents: 30,
  windowMs: 60 * 60_000,
});

const SURFACES = Object.freeze({
  moment: Object.freeze({
    kind: "moment",
    rootCollection: "voiceMoments",
    parentParam: "momentId",
    type: "momentComment",
    idPrefix: "momentComment",
    eventPrefix: "moment-comment",
  }),
  reel: Object.freeze({
    kind: "reel",
    rootCollection: "reels",
    parentParam: "reelId",
    type: "reelComment",
    idPrefix: "reelComment",
    eventPrefix: "reel-comment",
  }),
});

function eventIsTooOldToNotify(event, nowMs = Date.now()) {
  const raw = event?.time;
  if (typeof raw !== "string" || raw.length === 0) return false;
  const emittedMs = Date.parse(raw);
  if (!Number.isFinite(emittedMs)) return false;
  return nowMs - emittedMs > COMMENT_RETRY_WINDOW_MS;
}

function commentEventId(surface, parentId, commentId) {
  return `${surface.eventPrefix}:${parentId}:${commentId}`;
}

function mentionEventId(surface, parentId, commentId, recipientId) {
  return `comment-mention:${surface.kind}:${parentId}:${commentId}:${recipientId}`;
}

function commentNotificationId(surface, commentId) {
  return `${surface.idPrefix}_${commentId}`;
}

function mentionNotificationId(commentId) {
  return `commentMention_${commentId}`;
}

async function parentAuthorId(firestore, surface, parentId) {
  const snapshot = await firestore
    .doc(`${surface.rootCollection}/${parentId}`)
    .get();
  const authorId = snapshot.exists ? snapshot.data()?.authorId : null;
  return typeof authorId === "string" && authorId.length > 0 ? authorId : null;
}

/**
 * Charges one mention against the actor's hourly budget. Returns false when
 * the budget is spent, which drops the remaining mentions of this comment
 * silently — an @-flood must cost the recipient nothing.
 */
async function chargeMentionBudget(firestore, actorId, { now, nowMs }) {
  const reference = rateLimitReference(
    firestore,
    "notification.commentMention",
    actorId,
  );
  try {
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      consumeRateLimit(transaction, snapshot, {
        reference,
        scope: "notification.commentMention",
        uid: actorId,
        now,
        nowMs,
        ...MENTION_BUDGET,
      });
    });
    return true;
  } catch (error) {
    if (error?.code === "resource-exhausted" || error?.code === "data-loss") {
      return false;
    }
    throw error;
  }
}

async function handleCommentCreated(surface, event, {
  firestore = db,
  nowMs = Date.now(),
} = {}) {
  if (eventIsTooOldToNotify(event, nowMs)) {
    logger.warn("Abandoning a stale comment notification", {
      surface: surface.kind,
      commentId: event.params?.commentId,
    });
    return { outcome: "skipped:stale-event" };
  }
  const snapshot = event.data;
  const comment = snapshot?.data();
  const parentId = event.params?.[surface.parentParam];
  const commentId = event.params?.commentId;
  const actorId = comment?.authorId;
  if (!comment || typeof parentId !== "string" ||
      typeof commentId !== "string" || typeof actorId !== "string" ||
      actorId.length === 0) {
    return { outcome: "skipped:malformed" };
  }

  const authorId = await parentAuthorId(firestore, surface, parentId);
  if (!authorId) return { outcome: "skipped:missing-parent" };

  const sourcePath = commentSourcePath(surface.kind, parentId, commentId);
  const sourceGeneration = documentGeneration(snapshot, "createTime");
  const now = Timestamp.fromMillis(nowMs);
  const shapeFor = (type) => ({
    type,
    actorId,
    targetId: parentId,
    targetSubId: commentId,
    sourcePath,
    sourceGeneration,
  });

  let outcome = "skipped:self";
  if (authorId !== actorId) {
    outcome = await createNotificationForEvent({
      eventId: commentEventId(surface, parentId, commentId),
      recipientId: authorId,
      actorId,
      type: surface.type,
      notificationId: commentNotificationId(surface, commentId),
      targetId: parentId,
      targetSubId: commentId,
      sourcePath,
      sourceGeneration,
      firestore,
      validate: (transaction) => commentNotificationSourceIsCurrent({
        recipientId: authorId,
        notification: shapeFor(surface.type),
        reader: transaction,
        firestore,
        nowMs,
      }),
    });
  }

  const mentions = await deliverMentions(surface, {
    actorId,
    authorId,
    commentId,
    firestore,
    now,
    nowMs,
    parentId,
    sourceGeneration,
    sourcePath,
    shape: shapeFor("commentMention"),
  });

  logger.info("comment notification", {
    surface: surface.kind,
    parentId,
    commentId,
    outcome,
    mentions: mentions.written,
    mentionsConsidered: mentions.considered,
  });
  return { outcome, mentions };
}

async function deliverMentions(surface, {
  actorId,
  authorId,
  commentId,
  firestore,
  now,
  nowMs,
  parentId,
  shape,
  sourceGeneration,
  sourcePath,
}) {
  const record = exactCommentMentions(
    await commentMentionReference(
      firestore,
      surface.kind,
      parentId,
      commentId,
    ).get(),
    { kind: surface.kind, parentId, commentId },
  );
  if (!record || record.actorId !== actorId) {
    return { considered: 0, written: 0, throttled: false };
  }
  // The author already receives the comment row; a second row for the same
  // comment would be the same news twice.
  const recipients = record.mentionUserIds.filter(
    (uid) => uid !== actorId && uid !== authorId,
  );
  let written = 0;
  let throttled = false;
  for (const recipientId of recipients) {
    if (!(await chargeMentionBudget(firestore, actorId, { now, nowMs }))) {
      throttled = true;
      break;
    }
    const outcome = await createNotificationForEvent({
      eventId: mentionEventId(surface, parentId, commentId, recipientId),
      recipientId,
      actorId,
      type: "commentMention",
      notificationId: mentionNotificationId(commentId),
      targetId: parentId,
      targetSubId: commentId,
      sourcePath,
      sourceGeneration,
      firestore,
      validate: (transaction) => commentMentionSourceIsCurrent({
        recipientId,
        notification: shape,
        reader: transaction,
        firestore,
        nowMs,
      }),
    });
    if (outcome === "written") written += 1;
  }
  return { considered: recipients.length, written, throttled };
}

/**
 * Retires one row, but only when it is still the row this comment produced.
 * The generation precondition is deliberate: a recipient who deleted the row
 * and a later unrelated writer must both survive this.
 */
async function retireNotification(firestore, {
  recipientId,
  notificationId,
  sourcePath,
}) {
  if (typeof recipientId !== "string" || typeof notificationId !== "string") {
    return false;
  }
  const reference = firestore.doc(
    `users/${recipientId}/notifications/${notificationId}`,
  );
  const snapshot = await reference.get();
  if (!snapshot.exists || snapshot.data()?.sourcePath !== sourcePath) {
    return false;
  }
  try {
    await reference.delete({ lastUpdateTime: snapshot.updateTime });
    return true;
  } catch (error) {
    logger.info("Skipped a stale comment notification retirement", {
      code: error?.code ?? "unknown",
    });
    return false;
  }
}

async function retireForEvent(firestore, eventId, sourcePath) {
  const ledger = await eventLedgerReference(eventId, firestore).get();
  if (!ledger.exists || ledger.data()?.outcome !== "written") return false;
  return retireNotification(firestore, {
    recipientId: ledger.data()?.recipientId,
    notificationId: ledger.data()?.notificationId,
    sourcePath,
  });
}

async function handleCommentDeleted(surface, event, { firestore = db } = {}) {
  const parentId = event.params?.[surface.parentParam];
  const commentId = event.params?.commentId;
  if (typeof parentId !== "string" || typeof commentId !== "string") {
    return { retired: 0 };
  }
  const sourcePath = commentSourcePath(surface.kind, parentId, commentId);
  let retired = 0;
  if (await retireForEvent(
    firestore,
    commentEventId(surface, parentId, commentId),
    sourcePath,
  )) {
    retired += 1;
  }
  const mentionsReference = commentMentionReference(
    firestore,
    surface.kind,
    parentId,
    commentId,
  );
  const record = exactCommentMentions(await mentionsReference.get(), {
    kind: surface.kind,
    parentId,
    commentId,
  });
  if (record) {
    for (const recipientId of record.mentionUserIds) {
      if (await retireForEvent(
        firestore,
        mentionEventId(surface, parentId, commentId, recipientId),
        sourcePath,
      )) {
        retired += 1;
      }
    }
  }
  // The mention record exists only to serve these two triggers. Removing it
  // with the comment keeps the collection bounded by live comments.
  await mentionsReference.delete().catch((error) => {
    logger.info("Skipped a comment mention record cleanup", {
      code: error?.code ?? "unknown",
    });
  });
  logger.info("comment notification retirement", {
    surface: surface.kind,
    parentId,
    commentId,
    retired,
  });
  return { retired };
}

const handleMomentCommentCreated = (event, options) =>
  handleCommentCreated(SURFACES.moment, event, options);
const handleMomentCommentDeleted = (event, options) =>
  handleCommentDeleted(SURFACES.moment, event, options);
const handleReelCommentCreated = (event, options) =>
  handleCommentCreated(SURFACES.reel, event, options);
const handleReelCommentDeleted = (event, options) =>
  handleCommentDeleted(SURFACES.reel, event, options);

// `retry: true` is safe because every write is keyed on the comment's own
// identity through the delivery ledger, so a redelivery is a no-op. The
// handler bounds the retry chain itself (COMMENT_RETRY_WINDOW_MS).
const triggerOptions = (document) => ({
  document,
  region: REGION,
  memory: "512MiB",
  timeoutSeconds: 120,
  maxInstances: 50,
  retry: true,
});

const onMomentCommentCreated = onDocumentCreated(
  triggerOptions("voiceMoments/{momentId}/comments/{commentId}"),
  (event) => handleMomentCommentCreated(event),
);

const onMomentCommentDeleted = onDocumentDeleted(
  triggerOptions("voiceMoments/{momentId}/comments/{commentId}"),
  (event) => handleMomentCommentDeleted(event),
);

const onReelCommentCreated = onDocumentCreated(
  triggerOptions("reels/{reelId}/comments/{commentId}"),
  (event) => handleReelCommentCreated(event),
);

const onReelCommentDeleted = onDocumentDeleted(
  triggerOptions("reels/{reelId}/comments/{commentId}"),
  (event) => handleReelCommentDeleted(event),
);

module.exports = {
  COMMENT_RETRY_WINDOW_MS,
  MENTION_BUDGET,
  SURFACES,
  chargeMentionBudget,
  commentEventId,
  commentNotificationId,
  eventIsTooOldToNotify,
  handleCommentCreated,
  handleCommentDeleted,
  handleMomentCommentCreated,
  handleMomentCommentDeleted,
  handleReelCommentCreated,
  handleReelCommentDeleted,
  mentionEventId,
  mentionNotificationId,
  onMomentCommentCreated,
  onMomentCommentDeleted,
  onReelCommentCreated,
  onReelCommentDeleted,
  retireNotification,
};

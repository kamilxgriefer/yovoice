const crypto = require("node:crypto");

const { FieldValue } = require("firebase-admin/firestore");

const { db, normalizeText } = require("../utils/firestore");

const MAX_NAME = 80;
const MAX_LABEL = 120;

function publicIdentity(uid, profile = {}) {
  const displayName = normalizeText(
    profile.displayName || profile.username,
    MAX_NAME,
  );
  return {
    actorId: uid,
    actorName: displayName || "YO Voice user",
    actorPhotoUrl:
      typeof profile.photoUrl === "string" ? profile.photoUrl : null,
  };
}

function canonicalNotificationData({
  actorId,
  actorProfile,
  type,
  targetId = null,
  targetLabel = null,
  dedupeKey,
  bellSuppressed = false,
}) {
  return {
    type,
    ...publicIdentity(actorId, actorProfile),
    targetId: targetId || null,
    targetLabel: targetLabel
      ? normalizeText(targetLabel, MAX_LABEL) || null
      : null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    dedupeKey,
    bellSuppressed,
  };
}

function notificationReference(recipientId, notificationId) {
  return db.doc(`users/${recipientId}/notifications/${notificationId}`);
}

function eventLedgerReference(eventId) {
  const digest = crypto.createHash("sha256").update(String(eventId)).digest("hex");
  return db.doc(`notificationDeliveryEvents/${digest}`);
}

function restrictionIsActive(restriction, nowMillis = Date.now()) {
  if (!restriction || restriction.type !== "communicationMute") return false;
  const expiresAt = restriction.expiresAt;
  if (expiresAt == null) return true;
  if (typeof expiresAt.toMillis !== "function") return true;
  return expiresAt.toMillis() > nowMillis;
}

function activeProfile(snapshot) {
  if (!snapshot?.exists) return false;
  const profile = snapshot.data() ?? {};
  return profile.banned !== true && profile.disabled !== true;
}

/**
 * Creates one canonical notification for one CloudEvent. The event ledger and
 * inbox document commit atomically, so an at-least-once trigger retry cannot
 * duplicate or resurrect a notification the recipient already deleted.
 */
async function createNotificationForEvent({
  eventId,
  recipientId,
  actorId,
  type,
  notificationId,
  targetId = null,
  targetLabel = null,
  sourcePath,
  validate,
}) {
  if (!eventId || !recipientId || !actorId || recipientId === actorId) {
    return "skipped:invalid-parties";
  }

  const actorReference = db.doc(`users/${actorId}`);
  const recipientReference = db.doc(`users/${recipientId}`);
  const actorRestrictionReference = db.doc(`restrictions/${actorId}`);
  const recipientRestrictionReference = db.doc(`restrictions/${recipientId}`);
  const actorBlockReference = db.doc(`users/${actorId}/blocked/${recipientId}`);
  const recipientBlockReference = db.doc(
    `users/${recipientId}/blocked/${actorId}`,
  );
  const notification = notificationReference(recipientId, notificationId);
  const ledger = eventLedgerReference(eventId);

  return db.runTransaction(async (transaction) => {
    const [
      delivered,
      actor,
      recipient,
      actorRestriction,
      recipientRestriction,
      actorBlock,
      recipientBlock,
      existingNotification,
    ] = await transaction.getAll(
      ledger,
      actorReference,
      recipientReference,
      actorRestrictionReference,
      recipientRestrictionReference,
      actorBlockReference,
      recipientBlockReference,
      notification,
    );

    if (delivered.exists) return "skipped:replay";
    if (!activeProfile(actor) || !activeProfile(recipient)) {
      return "skipped:inactive";
    }
    if (
      restrictionIsActive(actorRestriction.data()) ||
      restrictionIsActive(recipientRestriction.data())
    ) {
      return "skipped:restricted";
    }
    if (actorBlock.exists || recipientBlock.exists) return "skipped:blocked";
    if (validate && !(await validate(transaction))) {
      return "skipped:invalid-source";
    }

    transaction.create(ledger, {
      eventId: String(eventId).slice(0, 512),
      sourcePath: normalizeText(sourcePath, 512) || null,
      recipientId,
      notificationId,
      createdAt: FieldValue.serverTimestamp(),
    });
    if (existingNotification.exists) return "skipped:already-written";
    transaction.set(
      notification,
      canonicalNotificationData({
        actorId,
        actorProfile: actor.data(),
        type,
        targetId,
        targetLabel,
        dedupeKey: notificationId,
      }),
    );
    return "written";
  });
}

module.exports = {
  activeProfile,
  canonicalNotificationData,
  createNotificationForEvent,
  eventLedgerReference,
  notificationReference,
  publicIdentity,
  restrictionIsActive,
};

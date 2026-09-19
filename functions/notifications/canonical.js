const crypto = require("node:crypto");

const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db, normalizeText } = require("../utils/firestore");

const MAX_NAME = 80;
const MAX_LABEL = 120;
// Eventarc redelivery is useful for short outages, but an eternal receipt per
// message would turn the highest-volume notification path into an unbounded
// operational collection. Thirty days is deliberately much longer than the
// delivery retry horizon while still allowing Firestore TTL to bound storage.
const EVENT_LEDGER_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

function publicIdentity(uid, profile = {}) {
  const displayName = normalizeText(
    profile.displayName || profile.username,
    MAX_NAME,
  );
  return {
    actorId: uid,
    actorName: displayName || "YO Voice user",
    actorPhotoUrl: null,
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
  targetSubId = null,
}) {
  const data = {
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
  // Additive and optional (2026-09-19): the secondary deep-link identity a
  // newer client uses to land on the exact comment or channel. Absent for
  // every type written before it existed, so no legacy row changes shape.
  if (typeof targetSubId === "string" && targetSubId.length > 0) {
    data.targetSubId = targetSubId.slice(0, 128);
  }
  return data;
}

function notificationReference(recipientId, notificationId, firestore = db) {
  return firestore.doc(`users/${recipientId}/notifications/${notificationId}`);
}

function eventLedgerReference(eventId, firestore = db) {
  const digest = crypto.createHash("sha256").update(String(eventId)).digest("hex");
  return firestore.doc(`notificationDeliveryEvents/${digest}`);
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
  bellSuppressed = false,
  sourcePath,
  sourceGeneration = null,
  validate,
  targetSubId = null,
  // A reminder the recipient asked for about their OWN event has no second
  // party. Only such a writer opts in; every social writer keeps the
  // self-notification refusal.
  allowSelf = false,
  firestore = db,
}) {
  if (!eventId || !recipientId || !actorId ||
      (recipientId === actorId && allowSelf !== true)) {
    return "skipped:invalid-parties";
  }

  const actorReference = firestore.doc(`users/${actorId}`);
  const recipientReference = firestore.doc(`users/${recipientId}`);
  const actorRestrictionReference = firestore.doc(`restrictions/${actorId}`);
  const recipientRestrictionReference = firestore.doc(
    `restrictions/${recipientId}`,
  );
  const actorBlockReference = firestore.doc(
    `users/${actorId}/blocked/${recipientId}`,
  );
  const recipientBlockReference = firestore.doc(
    `users/${recipientId}/blocked/${actorId}`,
  );
  const notification = notificationReference(
    recipientId,
    notificationId,
    firestore,
  );
  const ledger = eventLedgerReference(eventId, firestore);
  const receiptCreatedAt = Timestamp.now();
  const receiptExpiresAt = Timestamp.fromMillis(
    receiptCreatedAt.toMillis() + EVENT_LEDGER_RETENTION_MS,
  );

  return firestore.runTransaction(async (transaction) => {
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
    let outcome = "written";
    if (!activeProfile(actor) || !activeProfile(recipient)) {
      outcome = "skipped:inactive";
    } else if (
      restrictionIsActive(actorRestriction.data()) ||
      restrictionIsActive(recipientRestriction.data())
    ) {
      outcome = "skipped:restricted";
    } else if (actorBlock.exists || recipientBlock.exists) {
      outcome = "skipped:blocked";
    } else if (validate && !(await validate(transaction))) {
      outcome = "skipped:invalid-source";
    } else if (existingNotification.exists) {
      outcome = "skipped:already-written";
    }

    transaction.create(ledger, {
      eventId: String(eventId).slice(0, 512),
      sourcePath: normalizeText(sourcePath, 512) || null,
      recipientId,
      notificationId,
      outcome,
      createdAt: receiptCreatedAt,
      expiresAt: receiptExpiresAt,
    });
    if (outcome !== "written") return outcome;
    const notificationData = canonicalNotificationData({
      actorId,
      actorProfile: actor.data(),
      type,
      targetId,
      targetLabel,
      dedupeKey: notificationId,
      bellSuppressed,
      targetSubId,
    });
    const normalizedSourcePath = normalizeText(sourcePath, 512);
    if (normalizedSourcePath) notificationData.sourcePath = normalizedSourcePath;
    if (typeof sourceGeneration === "string" && sourceGeneration) {
      notificationData.sourceGeneration = sourceGeneration.slice(0, 128);
    }
    transaction.set(
      notification,
      notificationData,
    );
    return outcome;
  });
}

module.exports = {
  EVENT_LEDGER_RETENTION_MS,
  activeProfile,
  canonicalNotificationData,
  createNotificationForEvent,
  eventLedgerReference,
  notificationReference,
  publicIdentity,
  restrictionIsActive,
};

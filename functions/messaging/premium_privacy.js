const { paidPremiumIsActive } = require("../utils/premium_access");

const PREMIUM_MESSAGING_PREFERENCES = Object.freeze([
  "hideReadReceipts",
  "hideTyping",
]);

const DEFAULT_PREMIUM_MESSAGING_PRIVACY = Object.freeze({
  hideReadReceipts: false,
  hideTyping: false,
});

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function timestampMillis(value) {
  if (value === null || value === undefined) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

/**
 * Parses the owner-readable, server-written preference projection.
 *
 * Missing means the backwards-compatible public-presence default. A malformed
 * document is different: while a paid entitlement is active, both privacy
 * controls fail safe to hidden until the next settings write repairs the exact
 * document. Without a live entitlement, no stored bit can activate Premium.
 */
function premiumMessagingPrivacy(
  snapshot,
  entitlementSnapshot,
  nowMs,
  expectedOwnerId,
) {
  const entitlement = entitlementSnapshot?.exists
    ? entitlementSnapshot.data() ?? {}
    : null;
  const premiumActive = paidPremiumIsActive(entitlement, new Date(nowMs));
  if (!premiumActive) {
    return {
      ...DEFAULT_PREMIUM_MESSAGING_PRIVACY,
      malformed: false,
      premiumActive: false,
    };
  }
  if (!snapshot?.exists) {
    return {
      ...DEFAULT_PREMIUM_MESSAGING_PRIVACY,
      malformed: false,
      premiumActive: true,
    };
  }
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = [
    "hideReadReceipts",
    "hideTyping",
    "ownerId",
    "schemaVersion",
    "updatedAt",
  ];
  const canonical = keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    data.schemaVersion === 1 &&
    data.ownerId === expectedOwnerId &&
    typeof data.hideReadReceipts === "boolean" &&
    typeof data.hideTyping === "boolean" &&
    timestampMillis(data.updatedAt) !== null;
  if (!canonical) {
    return {
      hideReadReceipts: true,
      hideTyping: true,
      malformed: true,
      premiumActive: true,
    };
  }
  return {
    hideReadReceipts: data.hideReadReceipts,
    hideTyping: data.hideTyping,
    malformed: false,
    premiumActive: true,
  };
}

function storedPremiumMessagingPrivacy(snapshot, ownerId) {
  if (!snapshot?.exists) return { ...DEFAULT_PREMIUM_MESSAGING_PRIVACY };
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = [
    "hideReadReceipts",
    "hideTyping",
    "ownerId",
    "schemaVersion",
    "updatedAt",
  ];
  if (keys.length !== expected.length ||
      keys.some((key, index) => key !== expected[index]) ||
      data.schemaVersion !== 1 || data.ownerId !== ownerId ||
      typeof data.hideReadReceipts !== "boolean" ||
      typeof data.hideTyping !== "boolean" ||
      timestampMillis(data.updatedAt) === null) {
    return { ...DEFAULT_PREMIUM_MESSAGING_PRIVACY };
  }
  return {
    hideReadReceipts: data.hideReadReceipts,
    hideTyping: data.hideTyping,
  };
}

function canonicalPremiumMessagingPrivacy({
  ownerId,
  hideReadReceipts,
  hideTyping,
  updatedAt,
}) {
  if (typeof ownerId !== "string" || ownerId.length === 0 ||
      typeof hideReadReceipts !== "boolean" ||
      typeof hideTyping !== "boolean" ||
      timestampMillis(updatedAt) === null) {
    throw new TypeError("Canonical Premium messaging privacy is required.");
  }
  return {
    schemaVersion: 1,
    ownerId,
    hideReadReceipts,
    hideTyping,
    updatedAt,
  };
}

function validatePrivateReadState(snapshot, ownerId, conversationId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = [
    "conversationId",
    "hiddenThroughSequence",
    "ownerId",
    "processedThroughSequence",
    "schemaVersion",
    "updatedAt",
  ];
  if (keys.length !== expected.length ||
      keys.some((key, index) => key !== expected[index]) ||
      data.schemaVersion !== 1 || data.ownerId !== ownerId ||
      data.conversationId !== conversationId ||
      !Number.isSafeInteger(data.processedThroughSequence) ||
      data.processedThroughSequence < 0 ||
      !Number.isSafeInteger(data.hiddenThroughSequence) ||
      data.hiddenThroughSequence < 0 ||
      data.hiddenThroughSequence > data.processedThroughSequence ||
      timestampMillis(data.updatedAt) === null) {
    const error = new Error("The private direct-message read cursor is malformed.");
    error.code = "data-loss";
    throw error;
  }
  return {
    processedThroughSequence: data.processedThroughSequence,
    hiddenThroughSequence: data.hiddenThroughSequence,
  };
}

function validatePrivateUnreadState(snapshot, ownerId, conversationId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = [
    "conversationId",
    "ownerId",
    "schemaVersion",
    "unreadCount",
    "updatedAt",
  ];
  if (keys.length !== expected.length ||
      keys.some((key, index) => key !== expected[index]) ||
      data.schemaVersion !== 1 || data.ownerId !== ownerId ||
      data.conversationId !== conversationId ||
      !Number.isSafeInteger(data.unreadCount) || data.unreadCount < 0 ||
      timestampMillis(data.updatedAt) === null) {
    const error = new Error(
      "The private direct-message unread projection is malformed.",
    );
    error.code = "data-loss";
    throw error;
  }
  return { unreadCount: data.unreadCount };
}

module.exports = {
  DEFAULT_PREMIUM_MESSAGING_PRIVACY,
  PREMIUM_MESSAGING_PREFERENCES,
  canonicalPremiumMessagingPrivacy,
  premiumMessagingPrivacy,
  storedPremiumMessagingPrivacy,
  validatePrivateReadState,
  validatePrivateUnreadState,
};

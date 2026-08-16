const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");

const ACTIVE_PREMIUM_STATUSES = new Set(["active", "trialing", "grace"]);
const DEFAULT_MAX_OWNED_CLUBS = 3;

function ownershipGuardReference(uid) {
  return db.collection("clubOwnershipGuards").doc(uid);
}

/**
 * Serializes every operation that can add/remove a community Club from an
 * owner's set. The document is a lock/revision only; the authoritative count
 * is always recomputed from root Club documents, so legacy Clubs, deletion and
 * admin repairs require no fragile counter backfill.
 */
async function lockOwnershipGuards(transaction, userIds) {
  const references = [...new Set(userIds)]
    .sort()
    .map(ownershipGuardReference);
  if (references.length > 0) await transaction.getAll(...references);
  return references;
}

function touchOwnershipGuards(transaction, references) {
  for (const reference of references) {
    transaction.set(
      reference,
      {
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

function activeClubEntitlement(data, now = Timestamp.now()) {
  if (!data || !ACTIVE_PREMIUM_STATUSES.has(data.status)) return false;
  if (data.premiumIdentityEnabled !== true || data.canCreateClubs !== true) {
    return false;
  }
  const periodEnd = data.currentPeriodEnd;
  return (
    periodEnd instanceof Timestamp && periodEnd.toMillis() > now.toMillis()
  );
}

function maxOwnedClubs(data) {
  const value = Number(data?.maxOwnedClubs);
  return Number.isSafeInteger(value) && value > 0
    ? Math.min(value, 100)
    : DEFAULT_MAX_OWNED_CLUBS;
}

/**
 * Checks a prospective community-Club owner against trusted entitlement data
 * and a live query of canonical Club roots. Missing `type` means community for
 * backwards compatibility, matching the Flutter model and Firestore rules.
 * Callers must acquire this uid's ownership guard before invoking it.
 */
async function requireCommunityClubCapacity(transaction, uid) {
  const entitlementReference = db.collection("entitlements").doc(uid);
  const profileReference = db.collection("users").doc(uid);
  const [entitlementSnapshot, profileSnapshot] = await transaction.getAll(
    entitlementReference,
    profileReference,
  );
  const entitlement = entitlementSnapshot.exists
    ? (entitlementSnapshot.data() ?? {})
    : null;

  const profile = profileSnapshot.exists ? (profileSnapshot.data() ?? {}) : {};
  if (
    !profileSnapshot.exists ||
    profile.banned === true ||
    profile.disabled === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active account profile is required to own a community Club.",
    );
  }

  if (!activeClubEntitlement(entitlement)) {
    throw new HttpsError(
      "failed-precondition",
      "An active Premium Clubs entitlement is required.",
    );
  }

  const ownedSnapshot = await transaction.get(
    db.collection("clubs").where("ownerId", "==", uid),
  );
  const ownedCommunityClubs = ownedSnapshot.docs.filter(
    (document) => document.data().type !== "family",
  ).length;
  const limit = maxOwnedClubs(entitlement);

  if (ownedCommunityClubs >= limit) {
    throw new HttpsError(
      "resource-exhausted",
      `Premium includes up to ${limit} owned Clubs.`,
    );
  }

  return { ownedCommunityClubs, limit };
}

module.exports = {
  DEFAULT_MAX_OWNED_CLUBS,
  activeClubEntitlement,
  lockOwnershipGuards,
  maxOwnedClubs,
  ownershipGuardReference,
  requireCommunityClubCapacity,
  touchOwnershipGuards,
};

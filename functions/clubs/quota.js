const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  DEFAULT_MAX_OWNED_CLUBS,
  boundedClubLimit,
  deriveEffectivePremiumAccess,
  isActiveAccountProfile,
  paidPremiumIsActive,
} = require("../utils/premium_access");

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
  if (!paidPremiumIsActive(data, now)) return false;
  if (data.premiumIdentityEnabled !== true || data.canCreateClubs !== true) {
    return false;
  }
  return true;
}

function maxOwnedClubs(data) {
  return boundedClubLimit(data?.maxOwnedClubs);
}

/**
 * Checks a prospective community-Club owner against trusted entitlement data
 * and a live query of canonical Club roots. Missing `type` means community for
 * backwards compatibility, matching the Flutter model and Firestore rules.
 * Callers must acquire this uid's ownership guard before invoking it.
 */
async function requireCommunityClubCapacity(
  transaction,
  uid,
  { tokenRole = null, requireTokenRole = false, now = Timestamp.now() } = {},
) {
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
  if (!profileSnapshot.exists || !isActiveAccountProfile(profile)) {
    throw new HttpsError(
      "permission-denied",
      "An active account profile is required to own a community Club.",
    );
  }

  const access = deriveEffectivePremiumAccess({
    user: profile,
    tokenRole,
    entitlement,
    now,
    requireTokenRole,
  });
  if (!access.canCreateClubs) {
    throw new HttpsError(
      "failed-precondition",
      "Active Premium Clubs access is required.",
    );
  }

  const ownedSnapshot = await transaction.get(
    db.collection("clubs").where("ownerId", "==", uid),
  );
  const ownedCommunityClubs = ownedSnapshot.docs.filter(
    (document) => document.data().type !== "family",
  ).length;
  const limit = access.maxOwnedClubs;

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

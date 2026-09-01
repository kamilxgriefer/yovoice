const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  consumeRateLimit,
  rateLimitReference,
  transactionGetAll,
} = require("../integrity/guards");
const {
  DEFAULT_MAX_OWNED_CLUBS,
  boundedClubLimit,
  deriveEffectivePremiumAccess,
  isActiveAccountProfile,
  paidPremiumIsActive,
} = require("../utils/premium_access");

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const CLUB_ACTION_RATE_LIMITS = Object.freeze({
  createCommunityClub: Object.freeze({
    minute: Object.freeze({ maxEvents: 10, windowMs: MINUTE_MS }),
    hour: Object.freeze({ maxEvents: 60, windowMs: HOUR_MS }),
  }),
  deleteClub: Object.freeze({
    minute: Object.freeze({ maxEvents: 20, windowMs: MINUTE_MS }),
    hour: Object.freeze({ maxEvents: 200, windowMs: HOUR_MS }),
  }),
  finalizeClubMedia: Object.freeze({
    minute: Object.freeze({ maxEvents: 20, windowMs: MINUTE_MS }),
    hour: Object.freeze({ maxEvents: 200, windowMs: HOUR_MS }),
  }),
  moderateClubMessage: Object.freeze({
    minute: Object.freeze({ maxEvents: 20, windowMs: MINUTE_MS }),
    hour: Object.freeze({ maxEvents: 200, windowMs: HOUR_MS }),
  }),
  removeClubMember: Object.freeze({
    minute: Object.freeze({ maxEvents: 20, windowMs: MINUTE_MS }),
    hour: Object.freeze({ maxEvents: 200, windowMs: HOUR_MS }),
  }),
  transferClubOwnership: Object.freeze({
    minute: Object.freeze({ maxEvents: 10, windowMs: MINUTE_MS }),
    hour: Object.freeze({ maxEvents: 60, windowMs: HOUR_MS }),
  }),
});

function clubActionRateReferences(
  firestore,
  uid,
  action,
) {
  if (!CLUB_ACTION_RATE_LIMITS[action]) {
    throw new TypeError(`Unknown Club action rate limit: ${action}.`);
  }
  const prefix = `club.${action}.attempt`;
  return Object.freeze({
    minute: rateLimitReference(firestore, `${prefix}.minute`, uid),
    hour: rateLimitReference(firestore, `${prefix}.hour`, uid),
    minuteScope: `${prefix}.minute`,
    hourScope: `${prefix}.hour`,
  });
}

/**
 * Commits a target-independent attempt budget before any caller-selected
 * Club/member/message or external Storage/LiveKit state is read. Keeping this
 * in its own transaction is load-bearing: a later authorization, integrity or
 * capacity refusal must not roll the throttle back and become a free
 * denial-of-wallet loop.
 */
async function consumeClubActionAttempt(
  uid,
  action,
  {
    firestore = db,
    nowMs = Date.now(),
    limits = CLUB_ACTION_RATE_LIMITS[action],
  } = {},
) {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("nowMs must be epoch milliseconds.");
  }
  if (!limits?.minute || !limits?.hour) {
    throw new TypeError(`Missing Club action rate limit: ${action}.`);
  }
  const references = clubActionRateReferences(firestore, uid, action);
  const now = Timestamp.fromMillis(nowMs);
  await firestore.runTransaction(async (transaction) => {
    const [minute, hour] = await transactionGetAll(
      transaction,
      references.minute,
      references.hour,
    );
    consumeRateLimit(transaction, minute, {
      reference: references.minute,
      scope: references.minuteScope,
      uid,
      nowMs,
      now,
      ...limits.minute,
    });
    consumeRateLimit(transaction, hour, {
      reference: references.hour,
      scope: references.hourScope,
      uid,
      nowMs,
      now,
      ...limits.hour,
    });
  });
}

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

  // Read at most limit + 1 roots. A malformed legacy account with enough
  // Family-shaped rows to obscure the community count fails closed rather
  // than turning every creation/transfer attempt into an unbounded scan.
  const ownedSnapshot = await transaction.get(
    db
      .collection("clubs")
      .where("ownerId", "==", uid)
      .limit(access.maxOwnedClubs + 1),
  );
  const ownedCommunityClubs = ownedSnapshot.docs.filter(
    (document) => document.data().type !== "family",
  ).length;
  const limit = access.maxOwnedClubs;

  if (
    ownedCommunityClubs >= limit ||
    (ownedSnapshot.size > limit && ownedCommunityClubs < limit)
  ) {
    throw new HttpsError(
      "resource-exhausted",
      `Premium includes up to ${limit} owned Clubs.`,
    );
  }

  return { ownedCommunityClubs, limit };
}

module.exports = {
  CLUB_ACTION_RATE_LIMITS,
  DEFAULT_MAX_OWNED_CLUBS,
  activeClubEntitlement,
  clubActionRateReferences,
  consumeClubActionAttempt,
  lockOwnershipGuards,
  maxOwnedClubs,
  ownershipGuardReference,
  requireCommunityClubCapacity,
  touchOwnershipGuards,
};

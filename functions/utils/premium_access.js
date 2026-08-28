// Effective Premium product access without rewriting billing truth.
//
// `entitlements/{uid}` remains exclusively the verified paid lifecycle. The
// moderator preview below is a derived, revocable overlay sourced from the
// server-written users/{uid}.role mirror. Acting callables additionally pass
// the signed token role, so both authorities must agree; background cleanup
// and target-user checks have no target token and use the trusted mirror only.

const { STAFF_PREVIEW_ROLES } = require("./roles");

const ACTIVE_PREMIUM_STATUSES = new Set(["active", "trialing", "grace"]);
const DEFAULT_MAX_OWNED_CLUBS = 3;
const MAX_OWNED_CLUBS_LIMIT = 100;

function epochMillis(value) {
  if (value && typeof value.toMillis === "function") {
    const millis = value.toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function nowMillis(value = new Date()) {
  const millis = epochMillis(value);
  if (millis === null) throw new TypeError("now must be a valid time value.");
  return millis;
}

function isActiveAccountProfile(user) {
  return Boolean(user) && typeof user === "object" &&
    user.banned !== true &&
    user.disabled !== true &&
    user.deleted !== true &&
    user.status !== "deleted";
}

function hasStaffPreviewAccess({
  user,
  tokenRole = null,
  requireTokenRole = false,
} = {}) {
  if (!isActiveAccountProfile(user)) return false;
  const mirrorRole = typeof user.role === "string" ? user.role : "";
  if (!STAFF_PREVIEW_ROLES.has(mirrorRole)) return false;
  if (!requireTokenRole) return true;
  return typeof tokenRole === "string" &&
    tokenRole === mirrorRole &&
    STAFF_PREVIEW_ROLES.has(tokenRole);
}

function paidPremiumIsActive(entitlement, now = new Date()) {
  if (!entitlement || typeof entitlement !== "object") return false;
  if (entitlement.isPremium !== true) return false;
  if (!ACTIVE_PREMIUM_STATUSES.has(entitlement.status)) return false;
  // Canonical server-owned entitlements use a Firestore Timestamp. Accepting
  // a Date or raw number here would make Functions grant data that Rules and
  // Flutter reject under the same malformed document.
  if (typeof entitlement.currentPeriodEnd?.toMillis !== "function") {
    return false;
  }
  const periodEnd = epochMillis(entitlement.currentPeriodEnd);
  return periodEnd !== null && periodEnd > nowMillis(now);
}

function boundedClubLimit(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0
    ? Math.min(parsed, MAX_OWNED_CLUBS_LIMIT)
    : DEFAULT_MAX_OWNED_CLUBS;
}

function deriveEffectivePremiumAccess({
  user = null,
  tokenRole = null,
  entitlement = null,
  now = new Date(),
  requireTokenRole = false,
} = {}) {
  const paidActive = paidPremiumIsActive(entitlement, now);
  const staffComplimentary = hasStaffPreviewAccess({
    user,
    tokenRole,
    requireTokenRole,
  });
  const paidIdentity = paidActive &&
    entitlement.premiumIdentityEnabled === true;
  const paidCreator = paidIdentity && entitlement.creatorEnabled === true;
  const paidClubs = paidIdentity && entitlement.canCreateClubs === true;
  const paidClubLimit = paidClubs
    ? boundedClubLimit(entitlement.maxOwnedClubs)
    : 0;

  return Object.freeze({
    paidActive,
    staffComplimentary,
    hasPremiumAccess: paidActive || staffComplimentary,
    premiumIdentityEnabled: paidIdentity || staffComplimentary,
    creatorEnabled: paidCreator || staffComplimentary,
    canCreateClubs: paidClubs || staffComplimentary,
    maxOwnedClubs: Math.max(
      paidClubLimit,
      staffComplimentary ? DEFAULT_MAX_OWNED_CLUBS : 0,
    ),
    source:
      paidActive && staffComplimentary
        ? "paidAndStaffPreview"
        : paidActive
          ? "paid"
          : staffComplimentary
            ? "staffPreview"
            : null,
  });
}

module.exports = {
  ACTIVE_PREMIUM_STATUSES,
  DEFAULT_MAX_OWNED_CLUBS,
  MAX_OWNED_CLUBS_LIMIT,
  boundedClubLimit,
  deriveEffectivePremiumAccess,
  epochMillis,
  hasStaffPreviewAccess,
  isActiveAccountProfile,
  paidPremiumIsActive,
};

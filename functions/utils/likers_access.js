// "See who liked" authorization (ADR-230).
//
// Pure: no SDK import, beside premium_access.js. The capability is granted by
// exactly three authorities, in this precedence:
//
//   1. paid Premium   - entitlements/{uid} active AND premiumIdentityEnabled
//                       (ADR-053: the only paid authority);
//   2. vipGrant       - a CANONICAL vipGrants/{uid} document (below). This is
//                       an ADR-053 amendment for this one capability only;
//   3. staffPreview   - the ADR-119 moderator preview, which requires the
//                       signed token role to equal the server-written mirror.
//
// Nothing client-visible (users.premiumIdentity, a badge, a "vip" field) is
// ever authority here. `effectiveVip` (premium/entitlements.js) is not used:
// it trusts the lagging users.premiumIdentity mirror.

const {
  deriveEffectivePremiumAccess,
  epochMillis,
  isActiveAccountProfile,
} = require("./premium_access");

const LIKERS_VIP_GRANT_SOURCES = Object.freeze([
  "testerProgram",
  "legacyRoleMigration",
  "admin",
]);
const LIKERS_VIP_GRANT_REQUIRED_KEYS = Object.freeze([
  "expiresAt",
  "revoked",
  "source",
]);
const LIKERS_VIP_GRANT_OPTIONAL_KEYS = Object.freeze([
  "active",
  "grantedAt",
  "grantedBy",
]);
const LIKERS_ACCESS_SOURCES = Object.freeze([
  "paid",
  "vipGrant",
  "staffPreview",
]);

function requireNowMillis(now) {
  const millis = epochMillis(now);
  if (millis === null) throw new TypeError("now must be a valid time value.");
  return millis;
}

// FAIL CLOSED. `grantIsActive` (premium/entitlements.js) fails OPEN for a
// privacy capability: {} is active, {revoked: "true"} is active and a string
// expiresAt goes through new Date(). It stays as it is for the badge; this
// predicate is the one that authorizes seeing other people's likes.
//
// Known production shapes it accepts:
//   tester grants        {source: "testerProgram", expiresAt: null,
//                         revoked: false, grantedBy}
//   legacy-role grants   {source: "legacyRoleMigration", grantedAt,
//                         expiresAt: null, revoked: false}
// A non-canonical grant is repaired by the operator, never by widening this.
function canonicalLikersVipGrant(grant, now) {
  const nowMs = requireNowMillis(now);
  if (!grant || typeof grant !== "object" || Array.isArray(grant)) return false;
  const keys = Object.keys(grant);
  if (!LIKERS_VIP_GRANT_REQUIRED_KEYS.every((key) => keys.includes(key))) {
    return false;
  }
  if (!keys.every((key) =>
    LIKERS_VIP_GRANT_REQUIRED_KEYS.includes(key) ||
    LIKERS_VIP_GRANT_OPTIONAL_KEYS.includes(key))) {
    return false;
  }
  if (!LIKERS_VIP_GRANT_SOURCES.includes(grant.source)) return false;
  if (grant.revoked !== false) return false;
  if ("active" in grant && grant.active !== true) return false;
  if (
    "grantedBy" in grant &&
    (typeof grant.grantedBy !== "string" ||
      grant.grantedBy.length === 0 ||
      grant.grantedBy.length > 200)
  ) {
    return false;
  }
  if ("grantedAt" in grant && typeof grant.grantedAt?.toMillis !== "function") {
    return false;
  }
  if (grant.expiresAt === null) return true;
  // A Firestore Timestamp only: a string or number never goes through Date.
  if (typeof grant.expiresAt?.toMillis !== "function") return false;
  const expiresAtMs = grant.expiresAt.toMillis();
  return Number.isFinite(expiresAtMs) && expiresAtMs > nowMs;
}

// The caller's own three authority documents, in the order
// deriveLikersAccessFromSnapshots expects them.
function likersAccessReferences(db, uid) {
  return [
    db.doc(`users/${uid}`),
    db.doc(`entitlements/${uid}`),
    db.doc(`vipGrants/${uid}`),
  ];
}

function likersAccountIsActive(user) {
  return isActiveAccountProfile(user) &&
    (user.authDeletedAt === null || user.authDeletedAt === undefined);
}

function deriveLikersAccess({
  user = null,
  tokenRole = null,
  entitlement = null,
  grant = null,
  now,
} = {}) {
  const nowMs = requireNowMillis(now);
  if (!likersAccountIsActive(user)) {
    return Object.freeze({ allowed: false, source: null });
  }
  const premium = deriveEffectivePremiumAccess({
    user,
    tokenRole,
    entitlement,
    now: nowMs,
    requireTokenRole: true,
  });
  // premium.premiumIdentityEnabled also folds in the staff preview; the paid
  // authority is the entitlement's own flag, so the reported source is exact.
  const paid = premium.paidActive &&
    entitlement?.premiumIdentityEnabled === true;
  const vip = canonicalLikersVipGrant(grant, nowMs);
  const staff = premium.staffComplimentary === true;
  const source = paid
    ? "paid"
    : vip
      ? "vipGrant"
      : staff
        ? "staffPreview"
        : null;
  return Object.freeze({ allowed: source !== null, source });
}

function snapshotData(snapshot) {
  return snapshot?.exists ? (snapshot.data() ?? null) : null;
}

function deriveLikersAccessFromSnapshots({
  userSnapshot,
  entitlementSnapshot,
  grantSnapshot,
  tokenRole = null,
  now,
}) {
  return deriveLikersAccess({
    user: snapshotData(userSnapshot),
    tokenRole: typeof tokenRole === "string" ? tokenRole : null,
    entitlement: snapshotData(entitlementSnapshot),
    grant: snapshotData(grantSnapshot),
    now,
  });
}

module.exports = {
  LIKERS_ACCESS_SOURCES,
  LIKERS_VIP_GRANT_OPTIONAL_KEYS,
  LIKERS_VIP_GRANT_REQUIRED_KEYS,
  LIKERS_VIP_GRANT_SOURCES,
  canonicalLikersVipGrant,
  deriveLikersAccess,
  deriveLikersAccessFromSnapshots,
  likersAccessReferences,
  likersAccountIsActive,
};

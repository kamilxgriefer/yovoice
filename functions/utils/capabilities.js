// The capability matrix — the ONE place that says what each role may do.
//
// Functions enforce capabilities; Flutter renders them. Neither side ever
// compares role strings on its own, because scattered comparisons are how
// one surface forgets that superModerator lost permanent delete.
//
// OWNERSHIP is stricter than role. Full destructive control belongs only
// to the account whose uid matches the YOVOICE_PROTECTED_OWNER_UID
// secret. A `superAdmin` role WITHOUT that uid match receives the
// super-moderation tier and a security audit event — never ownership.
// This is the inverse of the owner GUARD's fail-closed rule, and the
// distinction matters: when the secret is unavailable,
// isProtectedOwnerUid() answers true for everyone so that nobody can be
// demoted or banned. Granting on that answer would hand ownership to
// every superAdmin the moment the secret binding broke. Capabilities
// therefore require the secret to be PRESENT and MATCHED — fail closed in
// both directions.

const {
  USER_ROLES,
  STAFF_ROLES,
  isProtectedOwnerUid,
  protectedOwnerConfigured,
} = require("./roles");
const { effectiveVip } = require("./entitlements");

/// Suspension ceilings, in hours. `null` means unbounded — including a
/// permanent ban (duration 0 = indefinite) — and belongs to the owner
/// alone.
const SUSPENSION_LIMIT_HOURS = Object.freeze({
  owner: null,
  superModerator: 30 * 24,
  moderator: 24,
});

/// True ONLY when the secret is present and this uid is the owner.
/// Never use the bare guard function to GRANT anything.
function isConfirmedOwner(uid) {
  return protectedOwnerConfigured() && isProtectedOwnerUid(uid);
}

/// Derives the full capability set from authoritative inputs. Pure: the
/// caller supplies the user document and grant, so the same derivation
/// serves the callable, every mutation Function and the tests.
function deriveCapabilities({ uid, user = {}, grant = null, now = new Date() }) {
  const rawRole = String(user.role ?? USER_ROLES.USER).trim();
  const staffRole = STAFF_ROLES.has(rawRole) ? rawRole : USER_ROLES.USER;
  const banned = user.banned === true;
  const { vip } = effectiveVip({ user, grant, now });

  const ownerConfirmed =
    !banned && staffRole === USER_ROLES.SUPER_ADMIN && isConfirmedOwner(uid);

  // A superAdmin that is NOT the confirmed owner. The caller decides how
  // loudly to react (the callable writes a security audit event); the
  // matrix simply refuses to treat it as ownership.
  const unconfirmedSuperAdmin =
    !banned && staffRole === USER_ROLES.SUPER_ADMIN && !ownerConfirmed;

  // Moderation tiers. A non-owner superAdmin falls into the
  // super-moderation tier: fail SAFELY, not into a dead account.
  const superModTier =
    !banned &&
    (ownerConfirmed ||
      unconfirmedSuperAdmin ||
      staffRole === USER_ROLES.SUPER_MODERATOR);
  const modTier = superModTier || (!banned && staffRole === USER_ROLES.MODERATOR);

  const suspensionLimitHours = ownerConfirmed
    ? SUSPENSION_LIMIT_HOURS.owner
    : superModTier
      ? SUSPENSION_LIMIT_HOURS.superModerator
      : modTier
        ? SUSPENSION_LIMIT_HOURS.moderator
        : 0;

  return {
    staffRole,
    isVip: vip,
    isOwner: ownerConfirmed,
    unconfirmedSuperAdmin,

    // ------------------------------------------------ owner only
    permanentDeleteSpaces: ownerConfirmed,
    deleteAnyMessage: ownerConfirmed,
    permanentBan: ownerConfirmed,
    manageRoles: ownerConfirmed,
    fullAuditAccess: ownerConfirmed,

    // ------------------------------------------------ super moderation
    viewAllQueues: superModTier,
    quarantineSpaces: superModTier,
    endAnyRoom: superModTier,

    // ------------------------------------------------ moderation
    handleAssignedReports: modTier,
    removeReportedContent: modTier,
    warnUsers: modTier,
    endPublicRoomWithReason: modTier,
    suspendUsers: suspensionLimitHours === null || suspensionLimitHours > 0,
    suspensionLimitHours,

    /// Lifting a suspension is a super-moderation act; a moderator's
    /// 24-hour timeout expires on its own terms.
    liftSuspensions: superModTier,

    /// Sanctioning a STAFF account of any tier is the owner's alone —
    /// staff discipline is an ownership question, not a moderation one.
    sanctionStaff: ownerConfirmed,

    // ------------------------------------------------ non-moderation roles
    // Flags only: their surfaces ship separately, and until they do no
    // UI is rendered for them — a capability is not a promise of a
    // button.
    readAuditLogs: !banned && (ownerConfirmed || staffRole === USER_ROLES.AUDITOR),
    supportLookup: !banned && (ownerConfirmed || staffRole === USER_ROLES.SUPPORT),
    guideMode:
      !banned && (ownerConfirmed || staffRole === USER_ROLES.GUIDE_MASTER),
  };
}

module.exports = {
  SUSPENSION_LIMIT_HOURS,
  isConfirmedOwner,
  deriveCapabilities,
};

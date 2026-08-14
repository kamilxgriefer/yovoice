// Effective VIP, decided in ONE place.
//
// VIP is an entitlement, not a staff role: it coexists with every role in
// the staff vocabulary. It can arrive from three sources, and the source
// must stay distinguishable — a complimentary grant is not a paid
// subscription, and billing, support and the badge all need to tell them
// apart.
//
//   subscription  active premiumIdentity (the server-written mirror of a
//                 real paid entitlement)
//   legacyRole    role == "vip", the pre-migration representation. Kept
//                 ONLY until the migration converts these accounts; it is
//                 what guarantees nobody loses VIP in the meantime.
//   adminGrant    a server-managed complimentary grant
//
// Absence of a grant is safe: no document means no entitlement from that
// source, never an error and never a default-true.

const { LEGACY_ROLES, normalizeRole } = require("./roles");

const VIP_SOURCES = Object.freeze({
  SUBSCRIPTION: "subscription",
  LEGACY_ROLE: "legacyRole",
  ADMIN_GRANT: "adminGrant",
});

/// A complimentary grant is active when it exists, is not revoked, and
/// either never expires or has not expired yet.
function grantIsActive(grant, now = new Date()) {
  if (!grant || typeof grant !== "object") return false;
  if (grant.revoked === true) return false;
  if (grant.active === false) return false;

  const expires = grant.expiresAt;
  if (expires === null || expires === undefined) return true; // non-expiring

  const expiryDate =
    typeof expires?.toDate === "function" ? expires.toDate() : new Date(expires);
  if (Number.isNaN(expiryDate.getTime())) return false; // unparseable: closed
  return expiryDate.getTime() > now.getTime();
}

/// Decides effective VIP from already-loaded documents.
///
/// Pure and synchronous on purpose: callers that already hold the user
/// document and its grant must not trigger another read, and the rule is
/// far easier to test as a function of its inputs.
///
/// Returns `{ vip, sources }` — plural, because an account can legitimately
/// hold more than one at once (a paying subscriber who also received a
/// complimentary grant), and collapsing that to one would lose the
/// distinction billing needs.
function effectiveVip({ user = {}, grant = null, now = new Date() } = {}) {
  const sources = [];

  if (user.premiumIdentity === true) {
    sources.push(VIP_SOURCES.SUBSCRIPTION);
  }
  if (normalizeRole(user.role) === LEGACY_ROLES.VIP) {
    sources.push(VIP_SOURCES.LEGACY_ROLE);
  }
  if (grantIsActive(grant, now)) {
    sources.push(VIP_SOURCES.ADMIN_GRANT);
  }

  return {
    vip: sources.length > 0,
    sources,
    // The single source to attribute it to when only one label fits.
    // A paid subscription outranks a complimentary grant, which outranks
    // the legacy representation.
    primarySource: sources.includes(VIP_SOURCES.SUBSCRIPTION)
      ? VIP_SOURCES.SUBSCRIPTION
      : sources.includes(VIP_SOURCES.ADMIN_GRANT)
        ? VIP_SOURCES.ADMIN_GRANT
        : sources.includes(VIP_SOURCES.LEGACY_ROLE)
          ? VIP_SOURCES.LEGACY_ROLE
          : null,
  };
}

module.exports = {
  VIP_SOURCES,
  effectiveVip,
  grantIsActive,
};

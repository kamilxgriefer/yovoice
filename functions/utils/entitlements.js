// Effective VIP, decided in ONE place.
//
// VIP is an identity benefit, not an authorization role: it coexists with
// every role in the staff vocabulary. It has three sources, and the source must
// stay distinguishable — a complimentary grant is not a paid
// subscription, and billing, support and the badge all need to tell them
// apart.
//
//   subscription  active premiumIdentity (the server-written mirror of a
//                 real paid entitlement)
//   adminGrant    a server-managed complimentary grant in vipGrants/{uid}
//   staffPreview  active moderator/superModerator server-role mirror
//
// The retired source — `role == "vip"` — was removed after the
// 2026-08 production dry run found zero accounts still carrying it. Only the
// two explicit preview roles above confer the new derived identity benefit.
//
// Absence of a grant is safe: no document means no entitlement from that
// source, never an error and never a default-true.

const VIP_SOURCES = Object.freeze({
  SUBSCRIPTION: "subscription",
  ADMIN_GRANT: "adminGrant",
  STAFF_PREVIEW: "staffPreview",
});

const { hasStaffPreviewAccess } = require("./premium_access");

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
/// Returns `{ vip, sources, primarySource }` — sources is plural because
/// an account can legitimately hold both at once (a paying subscriber who
/// also received a complimentary grant), and collapsing that would lose
/// the distinction billing needs.
function effectiveVip({ user = {}, grant = null, now = new Date() } = {}) {
  const sources = [];

  if (user.premiumIdentity === true) {
    sources.push(VIP_SOURCES.SUBSCRIPTION);
  }
  if (grantIsActive(grant, now)) {
    sources.push(VIP_SOURCES.ADMIN_GRANT);
  }
  if (hasStaffPreviewAccess({ user })) {
    sources.push(VIP_SOURCES.STAFF_PREVIEW);
  }

  return {
    vip: sources.length > 0,
    sources,
    // A paid subscription outranks derived/complimentary access when one
    // private support label has to be chosen.
    primarySource: sources.includes(VIP_SOURCES.SUBSCRIPTION)
      ? VIP_SOURCES.SUBSCRIPTION
      : sources.includes(VIP_SOURCES.STAFF_PREVIEW)
        ? VIP_SOURCES.STAFF_PREVIEW
        : sources.includes(VIP_SOURCES.ADMIN_GRANT)
          ? VIP_SOURCES.ADMIN_GRANT
          : null,
  };
}

module.exports = {
  VIP_SOURCES,
  effectiveVip,
  grantIsActive,
};

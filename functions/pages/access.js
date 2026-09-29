// Who may RUN a Premium Page (ADR-233 §2.2, decision D3; ADR-234).
//
// Pure: no SDK import beyond the error type. The capability reuses the
// ADR-230 "See who liked" derivation (utils/likers_access.js) so there is one
// definition of "canonical VIP grant" in the backend, with two narrowings:
//
//   * staffPreview is REFUSED. A moderator preview is a way to look at a paid
//     surface, not a way to publish to the public under YO Voice's trust.
//   * paid Premium COUNTS (PAGES_ALLOW_PAID_SOURCE = true). Owner decision
//     2026-09-29 (ADR-234) overrides ADR-233's condition (automated image
//     screening plus the Moderation Center, Roadmap 0o), with the accepted
//     risk recorded there. "Paid" is entitlements/{uid} with isPremium,
//     status active | trialing | grace, a Firestore Timestamp
//     currentPeriodEnd in the future, and premiumIdentityEnabled: Stripe and
//     adminSetPremiumEntitlements (source "admin") alike. The lapse rules
//     (§2.8) do not care where the capability came from, so a paid expiry
//     takes the same 30-day read-only-then-hidden path as a VIP lapse.
//
// The grant is checked INDEPENDENTLY of deriveLikersAccess's precedence:
// that function reports source "paid" for an account holding both a paid
// entitlement and a canonical grant, and a literal `source === "vipGrant"`
// test would then refuse a VIP tester who also pays. The account-active rule
// is the likers one (users active and not Auth-deleted).
//
// Nothing client-visible (users.premiumIdentity, publicBadges.isVip) is ever
// authority here. The three documents are read on the server, on every write
// and inside every transition transaction.

const { HttpsError } = require("firebase-functions/v2/https");

const {
  canonicalLikersVipGrant,
  deriveLikersAccess,
  likersAccessReferences,
  likersAccountIsActive,
} = require("../utils/likers_access");

// ADR-234 (owner decision 2026-09-29): paid and admin-granted Premium run a
// Page too. Read by every capability consumer; deploy them together.
const PAGES_ALLOW_PAID_SOURCE = true;

const PAGE_ACCESS_REQUIRED_MESSAGE = "YO Voice VIP is required to run a Page.";
const PAGE_ACCESS_REQUIRED_REASON = "pageAccessRequired";

const REFUSED = Object.freeze({ allowed: false, source: null });

function snapshotData(snapshot) {
  return snapshot?.exists ? (snapshot.data() ?? null) : null;
}

/**
 * The Pages capability from already-read documents.
 * `allowPaid` exists for the test that proves the constant is the switch
 * for paid Premium; production callers never pass it.
 */
function derivePagesCapabilityFromData({
  user = null,
  entitlement = null,
  grant = null,
  tokenRole = null,
  now,
  allowPaid = PAGES_ALLOW_PAID_SOURCE,
} = {}) {
  if (!likersAccountIsActive(user)) return REFUSED;
  if (canonicalLikersVipGrant(grant, now)) {
    return Object.freeze({ allowed: true, source: "vipGrant" });
  }
  if (allowPaid === true) {
    const access = deriveLikersAccess({ user, entitlement, grant, tokenRole, now });
    if (access.source === "paid") {
      return Object.freeze({ allowed: true, source: "paid" });
    }
  }
  return REFUSED;
}

function derivePagesCapability(
  { userSnapshot, entitlementSnapshot, grantSnapshot },
  { tokenRole = null, now, allowPaid = PAGES_ALLOW_PAID_SOURCE } = {},
) {
  return derivePagesCapabilityFromData({
    user: snapshotData(userSnapshot),
    entitlement: snapshotData(entitlementSnapshot),
    grant: snapshotData(grantSnapshot),
    tokenRole: typeof tokenRole === "string" ? tokenRole : null,
    now,
    allowPaid,
  });
}

/// users/{uid}, entitlements/{uid}, vipGrants/{uid}, in that order.
function pagesCapabilityReferences(db, uid) {
  return likersAccessReferences(db, uid);
}

function pageAccessRequiredError() {
  return new HttpsError(
    "failed-precondition",
    PAGE_ACCESS_REQUIRED_MESSAGE,
    { reason: PAGE_ACCESS_REQUIRED_REASON },
  );
}

module.exports = {
  PAGES_ALLOW_PAID_SOURCE,
  PAGE_ACCESS_REQUIRED_MESSAGE,
  PAGE_ACCESS_REQUIRED_REASON,
  derivePagesCapability,
  derivePagesCapabilityFromData,
  pageAccessRequiredError,
  pagesCapabilityReferences,
};

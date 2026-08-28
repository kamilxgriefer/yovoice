const { HttpsError } = require("firebase-functions/v2/https");

const { USER_ROLES } = require("./roles");

function requireAuthentication(request) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to perform this action.",
    );
  }

  return request.auth;
}

function getCurrentRole(request) {
  const auth = requireAuthentication(request);

  return {
    auth,
    role: String(auth.token.role ?? USER_ROLES.USER),
  };
}

/// The strongest gate this codebase has, for privileged destruction.
///
/// Requires BOTH the signed claim and the server-written mirror on
/// `users/{uid}`, and refuses a restricted account — the same pair
/// firestore.rules' isActiveStaff() insists on, and for the same reason:
/// the claim cannot be forged, but it CAN be stale, so a super admin
/// whose role was revoked minutes ago must not still be able to delete
/// with the token in their hand. A freshly promoted admin whose token has
/// not refreshed fails closed rather than open.
async function requireActiveSuperAdmin(request) {
  const { auth, role } = getCurrentRole(request);

  // Lazily required: utils/firestore initialises the Admin app, and
  // importing it at module load would drag that into every caller.
  const { db } = require("./firestore");
  const snapshot = await db.collection("users").doc(auth.uid).get();
  const profile = snapshot.exists ? (snapshot.data() ?? {}) : {};

  const claimIsSuperAdmin = role === USER_ROLES.SUPER_ADMIN;
  const recordIsSuperAdmin = profile.role === USER_ROLES.SUPER_ADMIN;

  if (
    !claimIsSuperAdmin ||
    !recordIsSuperAdmin ||
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted"
  ) {
    throw new HttpsError(
      "permission-denied",
      "Only a super administrator can perform this action.",
    );
  }

  return { ...auth, role };
}

/// The gate for DESTRUCTIVE ownership: permanent deletion, permanent
/// bans, role management. Stricter than requireActiveSuperAdmin — the
/// uid must match the protected-owner secret, and the secret must be
/// PRESENT. A superAdmin that is not the owner is refused AND recorded:
/// that combination is either a forged role or a compromised assignment,
/// and silence would be the worst possible response.
async function requireProtectedOwner(request) {
  const actor = await requireActiveSuperAdmin(request);

  const {
    isProtectedOwnerUid,
    protectedOwnerConfigured,
  } = require("./roles");

  if (!protectedOwnerConfigured()) {
    throw new HttpsError(
      "failed-precondition",
      "Owner protection is not configured.",
    );
  }

  if (!isProtectedOwnerUid(actor.uid)) {
    // Lazily required to avoid a load-order cycle (audit → firestore).
    const { writeAuditLog } = require("./audit");
    await writeAuditLog({
      caller: actor,
      action: "security_alert_non_owner_super_admin",
      targetType: "account",
      targetId: actor.uid,
      details: { attempted: "ownerCapability" },
    });
    throw new HttpsError(
      "permission-denied",
      "This action is reserved for the application owner.",
    );
  }

  return actor;
}

/// Claim + server record + not banned, generalised to a role set. The
/// same double-check requireActiveSuperAdmin performs, for the tiers
/// below ownership. Returns the profile so callers can derive
/// capabilities without a second read.
async function requireVerifiedStaff(request, allowedRoles, message) {
  const { auth, role } = getCurrentRole(request);
  const { db } = require("./firestore");
  const snapshot = await db.collection("users").doc(auth.uid).get();
  const profile = snapshot.exists ? (snapshot.data() ?? {}) : {};

  if (
    !allowedRoles.has(role) ||
    profile.role !== role ||
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted"
  ) {
    throw new HttpsError("permission-denied", message);
  }

  return { ...auth, role, profile };
}

module.exports = {
  requireVerifiedStaff,
  requireProtectedOwner,
  requireActiveSuperAdmin,
  requireAuthentication,
  getCurrentRole,
};

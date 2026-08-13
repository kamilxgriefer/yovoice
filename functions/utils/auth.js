const { HttpsError } = require("firebase-functions/v2/https");

const {
  USER_ROLES,
  ADMIN_CENTER_ROLES,
  USER_MANAGEMENT_ROLES,
  ROOM_MANAGEMENT_ROLES,
} = require("./roles");

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

function requireRole(request, allowedRoles, message) {
  const { auth, role } = getCurrentRole(request);

  if (!allowedRoles.has(role)) {
    throw new HttpsError("permission-denied", message);
  }

  return {
    ...auth,
    role,
  };
}

function requireSuperAdmin(request) {
  return requireRole(
    request,
    new Set([USER_ROLES.SUPER_ADMIN]),
    "Only a super administrator can perform this action.",
  );
}

function requireAdmin(request) {
  return requireRole(
    request,
    new Set([USER_ROLES.ADMIN, USER_ROLES.SUPER_ADMIN]),
    "Only an administrator can perform this action.",
  );
}

function requireModerator(request) {
  return requireRole(
    request,
    new Set([USER_ROLES.MODERATOR, USER_ROLES.ADMIN, USER_ROLES.SUPER_ADMIN]),
    "Only a moderator can perform this action.",
  );
}

function requireAdminCenterAccess(request) {
  return requireRole(
    request,
    ADMIN_CENTER_ROLES,
    "You do not have permission to access Admin Center.",
  );
}

function requireUserManager(request) {
  return requireRole(
    request,
    USER_MANAGEMENT_ROLES,
    "You do not have permission to manage users.",
  );
}

function requireRoomManager(request) {
  return requireRole(
    request,
    ROOM_MANAGEMENT_ROLES,
    "You do not have permission to manage rooms.",
  );
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

  if (!claimIsSuperAdmin || !recordIsSuperAdmin || profile.banned === true) {
    throw new HttpsError(
      "permission-denied",
      "Only a super administrator can perform this action.",
    );
  }

  return { ...auth, role };
}

module.exports = {
  requireActiveSuperAdmin,
  requireAuthentication,
  getCurrentRole,
  requireRole,
  requireSuperAdmin,
  requireAdmin,
  requireModerator,
  requireAdminCenterAccess,
  requireUserManager,
  requireRoomManager,
};

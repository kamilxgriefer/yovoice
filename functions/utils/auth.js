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

module.exports = {
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

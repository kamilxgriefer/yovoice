const SUPER_ADMIN_EMAIL = "grieferxgriefer@gmail.com";

const USER_ROLES = Object.freeze({
  USER: "user",
  VIP: "vip",
  MODERATOR: "moderator",
  ADMIN: "admin",
  SUPER_ADMIN: "superAdmin",
});

const ALLOWED_ROLES = new Set(Object.values(USER_ROLES));

const ADMIN_CENTER_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

const USER_MANAGEMENT_ROLES = new Set([
  USER_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

const ROOM_MANAGEMENT_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

const PERMANENT_DELETE_ROLES = new Set([
  USER_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

function normalizeRole(value) {
  return String(value ?? "").trim();
}

function normalizeEmail(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase();
}

function isAllowedRole(value) {
  return ALLOWED_ROLES.has(normalizeRole(value));
}

function isSuperAdminRole(value) {
  return normalizeRole(value) === USER_ROLES.SUPER_ADMIN;
}

function isProtectedOwnerEmail(value) {
  return normalizeEmail(value) === SUPER_ADMIN_EMAIL;
}

module.exports = {
  SUPER_ADMIN_EMAIL,
  USER_ROLES,
  ALLOWED_ROLES,
  ADMIN_CENTER_ROLES,
  USER_MANAGEMENT_ROLES,
  ROOM_MANAGEMENT_ROLES,
  PERMANENT_DELETE_ROLES,
  normalizeRole,
  normalizeEmail,
  isAllowedRole,
  isSuperAdminRole,
  isProtectedOwnerEmail,
};

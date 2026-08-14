// The protected owner is identified by an IMMUTABLE Auth uid held in
// Secret Manager, never by email. An email is mutable, is user-facing,
// and ends up in logs and git history; a uid is none of those. The value
// is read from the environment the secret is bound to, and is never
// logged or returned to a client.
//
// FAILS CLOSED. If the secret is unavailable the owner guard cannot be
// evaluated, so every owner-protected operation is refused rather than
// silently allowed. There is deliberately NO production fallback — a
// fallback here would be an unprotected owner the day the binding breaks.
let injectedProtectedOwnerUid = null;

/// Test-only injection. Never called in production code paths.
function setProtectedOwnerUidForTests(uid) {
  injectedProtectedOwnerUid = uid ?? null;
}

function protectedOwnerUid() {
  const value =
    injectedProtectedOwnerUid ?? process.env.YOVOICE_PROTECTED_OWNER_UID ?? "";
  const uid = String(value).trim();
  return uid.length > 0 ? uid : null;
}

function isProtectedOwnerUid(uid) {
  const owner = protectedOwnerUid();
  if (!owner) {
    // Fail closed: without the secret nothing may be treated as safe to
    // change, so every candidate is reported as protected.
    return true;
  }
  const candidate = String(uid ?? "").trim();
  return candidate.length > 0 && candidate === owner;
}

/// True only when the guard can actually be evaluated.
function protectedOwnerConfigured() {
  return protectedOwnerUid() !== null;
}

// The final single-valued staff vocabulary. VIP is deliberately absent:
// it is an ENTITLEMENT that coexists with any staff role, not a role.
const USER_ROLES = Object.freeze({
  USER: "user",
  GUIDE_MASTER: "guideMaster",
  SUPPORT: "support",
  AUDITOR: "auditor",
  MODERATOR: "moderator",
  SUPER_MODERATOR: "superModerator",
  SUPER_ADMIN: "superAdmin",
});

// Values that still exist in production and must keep working until the
// migration runs. `vip` becomes `user` + a complimentary grant; `admin`
// becomes `superModerator`, which is an intentional permission reduction
// (it loses permanent delete). Neither mapping is applied to data in this
// pass — this set only keeps them ACCEPTED.
const LEGACY_ROLES = Object.freeze({
  VIP: "vip",
  ADMIN: "admin",
});

/// What the target vocabulary will be once the migration has run.
const STAFF_ROLES = new Set(Object.values(USER_ROLES));

/// What is accepted right now: the target vocabulary plus the two legacy
/// values still present in production documents and Auth claims.
const ALLOWED_ROLES = new Set([
  ...STAFF_ROLES,
  ...Object.values(LEGACY_ROLES),
]);

/// Where a legacy value lands once migrated. Used by the migration script
/// in a later pass, and by the compatibility helpers below so that a
/// legacy value is reasoned about in exactly one place.
const LEGACY_ROLE_MIGRATION = Object.freeze({
  [LEGACY_ROLES.VIP]: USER_ROLES.USER,
  [LEGACY_ROLES.ADMIN]: USER_ROLES.SUPER_MODERATOR,
});

// Each set keeps `admin` for now so a live admin's access is BYTE-FOR-BYTE
// unchanged by this pass. The permission reduction happens with the
// migration, not here.
const ADMIN_CENTER_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.SUPER_MODERATOR,
  LEGACY_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

const USER_MANAGEMENT_ROLES = new Set([
  LEGACY_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

const ROOM_MANAGEMENT_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.SUPER_MODERATOR,
  LEGACY_ROLES.ADMIN,
  USER_ROLES.SUPER_ADMIN,
]);

// Permanent deletion stays with superAdmin and, until migration, the
// legacy admin who has it today. superModerator is deliberately NOT here:
// the reduction is the point of the admin→superModerator mapping.
const PERMANENT_DELETE_ROLES = new Set([
  LEGACY_ROLES.ADMIN,
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

module.exports = {
  USER_ROLES,
  LEGACY_ROLES,
  LEGACY_ROLE_MIGRATION,
  STAFF_ROLES,
  ALLOWED_ROLES,
  ADMIN_CENTER_ROLES,
  USER_MANAGEMENT_ROLES,
  ROOM_MANAGEMENT_ROLES,
  PERMANENT_DELETE_ROLES,
  normalizeRole,
  normalizeEmail,
  isAllowedRole,
  isSuperAdminRole,
  isProtectedOwnerUid,
  protectedOwnerConfigured,
  setProtectedOwnerUidForTests,
};

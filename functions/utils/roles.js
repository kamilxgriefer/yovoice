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

// The vocabulary is STRICT: the 2026-08 production dry run found zero
// `vip` and zero `admin` documents (32 scanned: 1 protected owner + 31
// already on the final vocabulary), so legacy acceptance ended with it.
// The historical mapping lives in scripts/migrate_roles.js, which remains
// as the audit record of how those values were retired.
const STAFF_ROLES = new Set(Object.values(USER_ROLES));

/// Identical to STAFF_ROLES now that nothing legacy is accepted. Kept as
/// its own export because every consumer asks the question "is this an
/// assignable role" through this name.
const ALLOWED_ROLES = STAFF_ROLES;

const ADMIN_CENTER_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.SUPER_MODERATOR,
  USER_ROLES.SUPER_ADMIN,
]);

// User management (role listing, bans, entitlement grants) is a
// superAdmin capability alone: the legacy admin tier that shared it was
// retired, and superModerator deliberately does not inherit it.
const USER_MANAGEMENT_ROLES = new Set([USER_ROLES.SUPER_ADMIN]);

const ROOM_MANAGEMENT_ROLES = new Set([
  USER_ROLES.MODERATOR,
  USER_ROLES.SUPER_MODERATOR,
  USER_ROLES.SUPER_ADMIN,
]);

// Global room deletion is reserved for the two senior room-authority tiers.
// A regular moderator can end a public live session, but cannot permanently
// erase a room or its history.
const PERMANENT_DELETE_ROLES = new Set([
  USER_ROLES.SUPER_MODERATOR,
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

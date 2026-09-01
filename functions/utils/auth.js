const { HttpsError } = require("firebase-functions/v2/https");

const { USER_ROLES } = require("./roles");

// A stolen Firebase ID token remains valid until it expires. Destructive staff
// operations therefore require proof that the underlying sign-in itself is
// recent; checking `iat` would be insufficient because Firebase refreshes it
// without asking the user to authenticate again.
const PRIVILEGED_AUTH_MAX_AGE_SECONDS = 5 * 60;
const PRIVILEGED_MFA_MODES = Object.freeze({
  OPTIONAL: "optional",
  REQUIRED: "required",
});

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

function resolvePrivilegedMfaMode(
  value = process.env.YOVOICE_PRIVILEGED_MFA_MODE,
) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized) return PRIVILEGED_MFA_MODES.OPTIONAL;
  if (Object.values(PRIVILEGED_MFA_MODES).includes(normalized)) {
    return normalized;
  }

  // A misspelled security policy must never silently turn MFA off.
  throw new HttpsError(
    "failed-precondition",
    "Privileged authentication policy is not configured correctly.",
    { reason: "privileged-authentication-policy-invalid" },
  );
}

function requireRecentPrivilegedAuthentication(
  auth,
  {
    nowSeconds = Math.floor(Date.now() / 1000),
    maxAgeSeconds = PRIVILEGED_AUTH_MAX_AGE_SECONDS,
  } = {},
) {
  const authTime = auth?.token?.auth_time;
  if (
    !Number.isSafeInteger(nowSeconds) ||
    !Number.isSafeInteger(maxAgeSeconds) ||
    maxAgeSeconds <= 0 ||
    !Number.isSafeInteger(authTime) ||
    authTime < 0 ||
    authTime > nowSeconds ||
    nowSeconds - authTime > maxAgeSeconds
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Sign in again before performing this sensitive action.",
      {
        reason: "recent-authentication-required",
        maxAgeSeconds,
      },
    );
  }

  return authTime;
}

/// Step-up authentication for every destructive staff/owner mutation.
///
/// `request.auth.token` is produced by Firebase after signature verification,
/// so both `auth_time` and the reserved `firebase.sign_in_second_factor` claim
/// are server-authored. The default deployment requires a five-minute sign-in
/// but leaves MFA in rollout mode so existing staff are not locked out before
/// enrollment is confirmed. Production can switch atomically to fail-closed
/// MFA with `YOVOICE_PRIVILEGED_MFA_MODE=required`.
function requirePrivilegedAuthentication(auth) {
  const authTime = requireRecentPrivilegedAuthentication(auth);
  const resolvedMfaMode = resolvePrivilegedMfaMode();
  const secondFactor = auth?.token?.firebase?.sign_in_second_factor;
  const secondFactorVerified =
    typeof secondFactor === "string" && secondFactor.trim().length > 0;

  if (
    resolvedMfaMode === PRIVILEGED_MFA_MODES.REQUIRED &&
    !secondFactorVerified
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Sign in with your second factor before performing this "
        + "sensitive action.",
      {
        reason: "multi-factor-authentication-required",
        mfaRequired: true,
      },
    );
  }

  return Object.freeze({
    authTime,
    mfaMode: resolvedMfaMode,
    secondFactorVerified,
  });
}

/// The live-role gate for super-administrator access.
///
/// Requires BOTH the signed claim and the server-written mirror on
/// `users/{uid}`, and refuses a restricted account — the same pair
/// firestore.rules' isActiveStaff() insists on, and for the same reason:
/// the claim cannot be forged, but it CAN be stale, so a super admin
/// whose role was revoked minutes ago must not still be able to delete
/// with the token in their hand. A freshly promoted admin whose token has
/// not refreshed fails closed rather than open. Mutating callers pass
/// `{ privileged: true }` to add the recent-auth/MFA step-up.
async function requireActiveSuperAdmin(request, { privileged = false } = {}) {
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

  return {
    ...auth,
    role,
    privilegedAuthentication: privileged
      ? requirePrivilegedAuthentication(auth)
      : null,
  };
}

/// The protected-owner identity gate. Stricter than
/// requireActiveSuperAdmin — the
/// uid must match the protected-owner secret, and the secret must be
/// PRESENT. A superAdmin that is not the owner is refused AND recorded:
/// that combination is either a forged role or a compromised assignment,
/// and silence would be the worst possible response. Destructive callers
/// must pass `{ privileged: true }`.
async function requireProtectedOwner(request, { privileged = false } = {}) {
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

  return {
    ...actor,
    privilegedAuthentication: privileged
      ? requirePrivilegedAuthentication(actor)
      : null,
  };
}

/// Claim + server record + not banned, generalised to a role set. The
/// same double-check requireActiveSuperAdmin performs, for the tiers
/// below ownership. Returns the profile so callers can derive
/// capabilities without a second read.
async function requireVerifiedStaff(
  request,
  allowedRoles,
  message,
  { privileged = false } = {},
) {
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

  return {
    ...auth,
    role,
    profile,
    privilegedAuthentication: privileged
      ? requirePrivilegedAuthentication(auth)
      : null,
  };
}

module.exports = {
  PRIVILEGED_AUTH_MAX_AGE_SECONDS,
  PRIVILEGED_MFA_MODES,
  requirePrivilegedAuthentication,
  requireRecentPrivilegedAuthentication,
  resolvePrivilegedMfaMode,
  requireVerifiedStaff,
  requireProtectedOwner,
  requireActiveSuperAdmin,
  requireAuthentication,
  getCurrentRole,
};

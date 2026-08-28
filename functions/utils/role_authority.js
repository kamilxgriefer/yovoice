// Cross-service role changes cannot be atomic: the Firestore role mirror and
// Firebase Auth custom claim are written by different systems. The safe order
// therefore depends on the direction of the authority change:
//
//  - demotion writes the client-immutable mirror first, immediately making an
//    old privileged token mismatch;
//  - promotion writes Auth first and the mirror last, so neither a current
//    ordinary token nor a historical still-valid privileged token can match a
//    newly promoted mirror when the Auth write fails.
//
// A lateral change or a demotion to another privileged role uses a neutral
// `user` mirror interlock before Auth changes. That closes both sides of the
// ABA window: neither the old role token nor a historical token for the target
// role can match after a partial failure. Re-running the same operation
// converges because every write is idempotent.

const ROLE_AUTHORITY_LEVEL = Object.freeze({
  user: 0,
  guideMaster: 1,
  support: 1,
  auditor: 1,
  moderator: 2,
  superModerator: 3,
  superAdmin: 4,
});

const PRIVILEGED_ROLES = new Set(
  Object.keys(ROLE_AUTHORITY_LEVEL).filter(
    (role) => ROLE_AUTHORITY_LEVEL[role] > 0,
  ),
);

function roleAuthorityLevel(role) {
  return ROLE_AUTHORITY_LEVEL[role] ?? 0;
}

async function persistRoleAuthoritySafely({
  uid,
  email = null,
  role,
  previousRole = "user",
  assignedBy,
  existingClaims = {},
  writeMirror,
  writeClaims,
}) {
  if (typeof writeMirror !== "function" || typeof writeClaims !== "function") {
    throw new TypeError("writeMirror and writeClaims are required.");
  }

  const mirrorWrite = (
    nextRole = role,
    roleTransitionInProgress = false,
  ) => writeMirror({
    uid,
    email,
    role: nextRole,
    assignedBy,
    roleTransitionInProgress,
  });
  const claimWrite = () => writeClaims(uid, { ...existingClaims, role });
  const sameRole = role === previousRole;
  const promotion =
    roleAuthorityLevel(role) > roleAuthorityLevel(previousRole);

  if (sameRole || promotion) {
    await claimWrite();
    await mirrorWrite();
    return { uid, role, writeOrder: "claimsFirst" };
  }

  if (!PRIVILEGED_ROLES.has(role)) {
    await mirrorWrite();
    await claimWrite();
    return { uid, role, writeOrder: "mirrorFirst" };
  }

  // A direct mirror-first lateral/demotion could reactivate a still-valid
  // historical token for the requested privileged role when Auth fails. A
  // direct claim-first write would leave the old role usable when the mirror
  // fails. The ordinary-user mirror is the fail-closed interlock for both.
  // The server-only marker tells cleanup/publication consumers that `user`
  // is an interlock, not the requested role. It never grants access: every
  // authorization gate still requires an exact claim/mirror match. The final
  // mirror write clears it and retriggers normal convergence.
  await mirrorWrite("user", true);
  await claimWrite();
  await mirrorWrite();
  return { uid, role, writeOrder: "neutralMirrorClaimsMirror" };
}

module.exports = {
  ROLE_AUTHORITY_LEVEL,
  PRIVILEGED_ROLES,
  persistRoleAuthoritySafely,
  roleAuthorityLevel,
};

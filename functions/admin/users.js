const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const {
  SUPER_ADMIN_EMAIL,
  USER_ROLES,
  ALLOWED_ROLES,
  normalizeEmail,
  normalizeRole,
  isProtectedOwnerEmail,
} = require("../utils/roles");

const {
  requireAuthentication,
  requireSuperAdmin,
  requireUserManager,
} = require("../utils/auth");

const {
  db,
  normalizeText,
  positiveInteger,
  timestampToIso,
} = require("../utils/firestore");

const { writeUserAuditLog } = require("../utils/audit");

const auth = getAuth();

async function saveRoleProfile({ uid, email, role, assignedBy }) {
  await db
    .collection("users")
    .doc(uid)
    .set(
      {
        email: email || null,
        role,
        roleAssignedBy: assignedBy,
        roleAssignedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

async function getAuthUser({ uid, email }) {
  try {
    if (uid) {
      return await auth.getUser(uid);
    }

    return await auth.getUserByEmail(email);
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "The selected user was not found.");
    }

    throw error;
  }
}

function isAdministrativeRole(role) {
  return (
    role === USER_ROLES.MODERATOR ||
    role === USER_ROLES.ADMIN ||
    role === USER_ROLES.SUPER_ADMIN
  );
}

exports.bootstrapSuperAdmin = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
  },
  async (request) => {
    const authenticatedUser = requireAuthentication(request);
    const callerEmail = normalizeEmail(authenticatedUser.token.email);

    if (callerEmail !== SUPER_ADMIN_EMAIL) {
      throw new HttpsError(
        "permission-denied",
        "This account is not allowed to become the application owner.",
      );
    }

    if (authenticatedUser.token.email_verified !== true) {
      throw new HttpsError(
        "permission-denied",
        "Verify your e-mail address before becoming the application owner.",
      );
    }

    const callerRecord = await auth.getUser(authenticatedUser.uid);

    const existingClaims = callerRecord.customClaims ?? {};

    await auth.setCustomUserClaims(callerRecord.uid, {
      ...existingClaims,
      role: USER_ROLES.SUPER_ADMIN,
    });

    await saveRoleProfile({
      uid: callerRecord.uid,
      email: callerRecord.email,
      role: USER_ROLES.SUPER_ADMIN,
      assignedBy: callerRecord.uid,
    });

    await writeUserAuditLog({
      caller: {
        ...authenticatedUser,
        role: USER_ROLES.SUPER_ADMIN,
      },
      action: "bootstrap_super_admin",
      userId: callerRecord.uid,
      userEmail: callerRecord.email,
      details: {
        role: USER_ROLES.SUPER_ADMIN,
      },
    });

    return {
      success: true,
      uid: callerRecord.uid,
      email: callerRecord.email,
      role: USER_ROLES.SUPER_ADMIN,
      message:
        "Super administrator access granted. Refresh the session to receive the new permissions.",
    };
  },
);

exports.assignUserRole = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireSuperAdmin(request);

    const targetUid = normalizeText(request.data?.uid, 128);

    const targetEmail = normalizeEmail(request.data?.email);

    const requestedRole = normalizeRole(request.data?.role);

    if (!targetUid && !targetEmail) {
      throw new HttpsError(
        "invalid-argument",
        "Provide either the target user's uid or email.",
      );
    }

    if (!ALLOWED_ROLES.has(requestedRole)) {
      throw new HttpsError(
        "invalid-argument",
        "Role must be user, vip, moderator, admin or superAdmin.",
      );
    }

    if (requestedRole === USER_ROLES.SUPER_ADMIN) {
      throw new HttpsError(
        "permission-denied",
        "Additional super administrators cannot be assigned from the app.",
      );
    }

    const targetUser = await getAuthUser({
      uid: targetUid,
      email: targetEmail,
    });

    if (isProtectedOwnerEmail(targetUser.email)) {
      throw new HttpsError(
        "failed-precondition",
        "The application owner's role cannot be changed.",
      );
    }

    const previousRole = targetUser.customClaims?.role ?? USER_ROLES.USER;

    const existingClaims = targetUser.customClaims ?? {};

    await auth.setCustomUserClaims(targetUser.uid, {
      ...existingClaims,
      role: requestedRole,
    });

    await saveRoleProfile({
      uid: targetUser.uid,
      email: targetUser.email,
      role: requestedRole,
      assignedBy: caller.uid,
    });

    await writeUserAuditLog({
      caller,
      action: "assign_user_role",
      userId: targetUser.uid,
      userEmail: targetUser.email,
      details: {
        previousRole,
        newRole: requestedRole,
      },
    });

    return {
      success: true,
      uid: targetUser.uid,
      email: targetUser.email,
      role: requestedRole,
      message: "The role was updated successfully.",
    };
  },
);

exports.getUserRole = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
  },
  async (request) => {
    requireSuperAdmin(request);

    const targetUid = normalizeText(request.data?.uid, 128);

    const targetEmail = normalizeEmail(request.data?.email);

    if (!targetUid && !targetEmail) {
      throw new HttpsError(
        "invalid-argument",
        "Provide either the target user's uid or email.",
      );
    }

    const targetUser = await getAuthUser({
      uid: targetUid,
      email: targetEmail,
    });

    const profileSnapshot = await db
      .collection("users")
      .doc(targetUser.uid)
      .get();

    const profile = profileSnapshot.data() ?? {};

    return {
      uid: targetUser.uid,
      email: targetUser.email ?? profile.email ?? null,
      displayName: profile.displayName ?? targetUser.displayName ?? null,
      username: profile.username ?? null,
      photoUrl: profile.photoUrl ?? targetUser.photoURL ?? null,
      disabled: targetUser.disabled,
      banned: profile.banned === true || targetUser.disabled,
      role: targetUser.customClaims?.role ?? profile.role ?? USER_ROLES.USER,
    };
  },
);

exports.listAdminUsers = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
  },
  async (request) => {
    requireUserManager(request);

    const limit = positiveInteger(request.data?.limit, 50, 100);

    const pageToken = normalizeText(request.data?.pageToken, 2048) || undefined;

    const search = normalizeText(request.data?.search, 120).toLowerCase();

    const result = await auth.listUsers(limit, pageToken);

    const filteredUsers = search
      ? result.users.filter((user) => {
          const searchable = [
            user.uid,
            user.email,
            user.displayName,
            user.phoneNumber,
          ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase();

          return searchable.includes(search);
        })
      : result.users;

    const profiles = await Promise.all(
      filteredUsers.map((user) => db.collection("users").doc(user.uid).get()),
    );

    const users = filteredUsers.map((user, index) => {
      const profile = profiles[index]?.data() ?? {};

      const role = user.customClaims?.role ?? profile.role ?? USER_ROLES.USER;

      return {
        uid: user.uid,
        email: user.email ?? profile.email ?? null,
        displayName: profile.displayName ?? user.displayName ?? "YoVoice user",
        username: profile.username ?? "",
        photoUrl: profile.photoUrl ?? user.photoURL ?? null,
        role,
        isAdministrative: isAdministrativeRole(role),
        disabled: user.disabled,
        banned: profile.banned === true || user.disabled,
        banReason: profile.banReason ?? null,
        bannedUntil: timestampToIso(profile.bannedUntil),
        createdAt: user.metadata.creationTime ?? null,
        lastSignInAt: user.metadata.lastSignInTime ?? null,
      };
    });

    return {
      users,
      nextPageToken: result.pageToken ?? null,
    };
  },
);

exports.setUserBan = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireUserManager(request);

    const targetUid = normalizeText(request.data?.uid, 128);

    const banned = request.data?.banned === true;

    const reason = normalizeText(request.data?.reason, 500);

    const durationHours = banned
      ? positiveInteger(request.data?.durationHours, 0, 24 * 365 * 10)
      : 0;

    if (!targetUid) {
      throw new HttpsError("invalid-argument", "A user uid is required.");
    }

    if (targetUid === caller.uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot ban your own account.",
      );
    }

    const targetUser = await auth.getUser(targetUid);

    if (isProtectedOwnerEmail(targetUser.email)) {
      throw new HttpsError(
        "failed-precondition",
        "The application owner cannot be banned.",
      );
    }

    const targetRole = targetUser.customClaims?.role ?? USER_ROLES.USER;

    if (
      caller.role !== USER_ROLES.SUPER_ADMIN &&
      (targetRole === USER_ROLES.ADMIN || targetRole === USER_ROLES.SUPER_ADMIN)
    ) {
      throw new HttpsError(
        "permission-denied",
        "Only the super administrator can ban administrators.",
      );
    }

    const bannedUntil =
      banned && durationHours > 0
        ? Timestamp.fromMillis(Date.now() + durationHours * 60 * 60 * 1000)
        : null;

    await auth.updateUser(targetUid, {
      disabled: banned,
    });

    // Disabling an account stops it minting NEW ID tokens, but one the
    // client already holds stays cryptographically valid until it
    // expires — up to an hour of continued access on a banned account.
    // Revoking refresh tokens invalidates every outstanding session, so
    // the client cannot renew, and Firestore rules additionally read the
    // `banned` field written below, which takes effect on the very next
    // request rather than at token expiry. See docs/SECURITY.md.
    if (banned) {
      await auth.revokeRefreshTokens(targetUid);
    }

    await db
      .collection("users")
      .doc(targetUid)
      .set(
        {
          banned,
          banReason: banned ? reason || "Administrative action" : null,
          bannedAt: banned ? FieldValue.serverTimestamp() : null,
          bannedUntil,
          bannedBy: banned ? caller.uid : null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    await writeUserAuditLog({
      caller,
      action: banned ? "ban_user" : "unban_user",
      userId: targetUid,
      userEmail: targetUser.email,
      details: {
        reason: banned ? reason || "Administrative action" : null,
        durationHours,
      },
    });

    return {
      success: true,
      uid: targetUid,
      banned,
      bannedUntil: timestampToIso(bannedUntil),
    };
  },
);

module.exports = {
  bootstrapSuperAdmin: exports.bootstrapSuperAdmin,
  assignUserRole: exports.assignUserRole,
  getUserRole: exports.getUserRole,
  listAdminUsers: exports.listAdminUsers,
  setUserBan: exports.setUserBan,
};

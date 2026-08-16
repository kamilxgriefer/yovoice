const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const {
  USER_ROLES,
  ALLOWED_ROLES,
  normalizeEmail,
  normalizeRole,
  isProtectedOwnerUid,
  protectedOwnerConfigured,
} = require("../utils/roles");

const { deriveCapabilities } = require("../utils/capabilities");

const {
  requireAuthentication,
  requireVerifiedStaff,
  requireProtectedOwner,
} = require("../utils/auth");

const {
  db,
  normalizeText,
  positiveInteger,
  timestampToIso,
} = require("../utils/firestore");

const { writeUserAuditLog } = require("../utils/audit");
const {
  EVENT_TYPES,
  enqueueVoiceEnforcement,
} = require("../staff/voice_enforcement");

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
    role === USER_ROLES.SUPER_MODERATOR ||
    role === USER_ROLES.SUPER_ADMIN
  );
}

exports.bootstrapSuperAdmin = onCall(
  {
    region: "europe-west1",
    // Bound only where the owner guard is evaluated.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    const authenticatedUser = requireAuthentication(request);

    // Fail closed: without the secret the owner cannot be identified, so
    // nobody may claim ownership. Never report WHICH uid is expected.
    if (!protectedOwnerConfigured()) {
      throw new HttpsError(
        "failed-precondition",
        "Owner protection is not configured.",
      );
    }

    if (!isProtectedOwnerUid(authenticatedUser.uid)) {
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
    const callerProfile = await db
      .collection("users")
      .doc(authenticatedUser.uid)
      .get();

    // Bootstrap is the one owner path that cannot use
    // requireProtectedOwner yet (the role does not exist yet). The
    // immutable uid is therefore necessary but not sufficient: reject a
    // disabled Auth record, a server-side ban, or a stale verification
    // claim before writing the ownership role.
    if (
      callerRecord.disabled === true ||
      callerProfile.data()?.banned === true
    ) {
      throw new HttpsError(
        "permission-denied",
        "This account is not allowed to become the application owner.",
      );
    }

    if (callerRecord.emailVerified !== true) {
      throw new HttpsError(
        "permission-denied",
        "Verify your e-mail address before becoming the application owner.",
      );
    }

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
    // Bound only where the owner guard is evaluated.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    // Role assignment is an OWNERSHIP capability: claim + server record +
    // the protected-owner uid. A superAdmin that is not the owner is
    // refused and recorded by the guard itself.
    const caller = await requireProtectedOwner(request);

    const targetUid = normalizeText(request.data?.uid, 128);

    const targetEmail = normalizeEmail(request.data?.email);

    const requestedRole = normalizeRole(request.data?.role);

    // Every assignment carries its justification into the audit log.
    const reason = normalizeText(request.data?.reason, 500);

    // Stale-result guard: the client says which role it BELIEVED the
    // target held. If the truth moved between lookup and submit, refuse
    // rather than silently overwrite a newer assignment.
    const expectedRole = normalizeRole(request.data?.expectedRole);

    if (reason.length < 3) {
      throw new HttpsError(
        "invalid-argument",
        "A reason for the role change is required.",
      );
    }

    if (!targetUid && !targetEmail) {
      throw new HttpsError(
        "invalid-argument",
        "Provide either the target user's uid or email.",
      );
    }

    if (!ALLOWED_ROLES.has(requestedRole)) {
      throw new HttpsError(
        "invalid-argument",
        "Role must be user, guideMaster, support, auditor, moderator, "
          + "superModerator or superAdmin.",
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

    // Identified by immutable uid. With the secret missing this returns
    // true for every candidate, so the owner guard refuses rather than
    // waving everything through.
    if (isProtectedOwnerUid(targetUser.uid)) {
      throw new HttpsError(
        "failed-precondition",
        "The application owner's role cannot be changed.",
      );
    }

    const previousRole = targetUser.customClaims?.role ?? USER_ROLES.USER;

    if (expectedRole && expectedRole !== previousRole) {
      throw new HttpsError(
        "failed-precondition",
        "This user's role changed since you looked it up. Search again "
          + "and retry.",
      );
    }

    // A super administrator may not demote themselves. Locking yourself
    // out is not a recoverable mistake from inside the app — there is no
    // remaining account with the authority to undo it.
    if (targetUser.uid === caller.uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot change your own role.",
      );
    }

    // ...and the last super administrator may not be demoted by anyone.
    //
    // Counted inside a TRANSACTION over the sentinel document rather than
    // with a bare query: two concurrent demotions each reading "there are
    // two of us" would both proceed and leave zero. The transaction
    // serialises them, so the second sees the first's effect and fails.
    if (previousRole === USER_ROLES.SUPER_ADMIN) {
      const sentinel = db.collection("adminGuards").doc("superAdminCount");
      await db.runTransaction(async (transaction) => {
        // Read inside the transaction so the count is part of its
        // snapshot and a concurrent demotion invalidates it.
        await transaction.get(sentinel);
        const supers = await db
          .collection("users")
          .where("role", "==", USER_ROLES.SUPER_ADMIN)
          .count()
          .get();
        const remaining = (supers.data().count ?? 0) - 1;
        if (remaining < 1) {
          throw new HttpsError(
            "failed-precondition",
            "The final super administrator cannot be demoted.",
          );
        }
        // Touching the sentinel is what gives the transaction something
        // to conflict on; the value itself is incidental.
        transaction.set(
          sentinel,
          { updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      });
    }

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
        reason,
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
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    await requireProtectedOwner(request);

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
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    await requireProtectedOwner(request);

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
    // Bound only where the owner guard is evaluated.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    // Tiered sanctions, straight from the capability matrix:
    //  - the OWNER may do anything here, permanent bans included;
    //  - a super moderator may suspend for up to 30 days, and lift
    //    suspensions;
    //  - a moderator may time out for up to 24 hours;
    //  - nobody below ownership may sanction a staff account.
    const caller = await requireVerifiedStaff(
      request,
      new Set([
        USER_ROLES.MODERATOR,
        USER_ROLES.SUPER_MODERATOR,
        USER_ROLES.SUPER_ADMIN,
      ]),
      "You do not have permission to sanction users.",
    );
    const caps = deriveCapabilities({ uid: caller.uid, user: caller.profile });

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

    if (!banned && !caps.liftSuspensions) {
      throw new HttpsError(
        "permission-denied",
        "Only super moderation can lift a suspension.",
      );
    }

    if (banned && durationHours === 0 && !caps.permanentBan) {
      // A permanent ban attempted by a superAdmin that is not the owner
      // is the forged-role scenario — recorded, then refused.
      if (caps.unconfirmedSuperAdmin) {
        await writeUserAuditLog({
          caller,
          action: "security_alert_non_owner_super_admin",
          userId: caller.uid,
          details: { attempted: "permanentBan" },
        });
      }
      throw new HttpsError(
        "permission-denied",
        "Only the application owner can ban permanently.",
      );
    }

    if (
      banned &&
      caps.suspensionLimitHours !== null &&
      (durationHours === 0 || durationHours > caps.suspensionLimitHours)
    ) {
      throw new HttpsError(
        "invalid-argument",
        `Your role can suspend for at most ${caps.suspensionLimitHours} hours.`,
      );
    }

    const targetUser = await auth.getUser(targetUid);

    if (isProtectedOwnerUid(targetUser.uid)) {
      throw new HttpsError(
        "failed-precondition",
        "The application owner cannot be banned.",
      );
    }

    const targetProfileSnapshot = await db
      .collection("users")
      .doc(targetUid)
      .get();
    const targetProfile = targetProfileSnapshot.data() ?? {};
    const targetClaimRole = targetUser.customClaims?.role ?? USER_ROLES.USER;
    const targetMirrorRole = targetProfile.role ?? USER_ROLES.USER;

    // Either authoritative source saying "staff" is enough to protect
    // the account. This fails closed during the short claim/mirror
    // convergence window and under manual data drift instead of letting
    // a moderator sanction a staff account by catching the stale side.
    const targetIsStaff =
      targetClaimRole !== USER_ROLES.USER ||
      targetMirrorRole !== USER_ROLES.USER;

    if (targetIsStaff && !caps.sanctionStaff) {
      throw new HttpsError(
        "permission-denied",
        "Only the application owner can sanction staff accounts.",
      );
    }

    const bannedUntil =
      banned && durationHours > 0
        ? Timestamp.fromMillis(Date.now() + durationHours * 60 * 60 * 1000)
        : null;

    const targetReference = db.collection("users").doc(targetUid);
    const banState = {
      banned,
      banReason: banned ? reason || "Administrative action" : null,
      bannedAt: banned ? FieldValue.serverTimestamp() : null,
      bannedUntil,
      bannedBy: banned ? caller.uid : null,
      updatedAt: FieldValue.serverTimestamp(),
    };
    let enforcementEvent = null;

    if (banned) {
      // State + outbox are one atomic commit. Once it succeeds, rules and
      // token issuance fail closed immediately, and a retrying trigger owns
      // every already-issued LiveKit session even if this callable crashes.
      const batch = db.batch();
      enforcementEvent = enqueueVoiceEnforcement(batch, {
        targetUid,
        type: EVENT_TYPES.BAN,
        requestedBy: caller.uid,
        source: "setUserBan",
      });
      batch.set(targetReference, {
        ...banState,
        banEnforcementEventId: enforcementEvent.id,
      }, { merge: true });
      await batch.commit();

      // Disabling an account stops it minting NEW ID tokens, but one the
      // client already holds stays cryptographically valid until expiry.
      // Refresh-token revocation plus the server-side banned mirror closes
      // both paths; the durable event independently removes voice sessions.
      await auth.updateUser(targetUid, { disabled: true });
      await auth.revokeRefreshTokens(targetUid);
    } else {
      // Enabling Auth before clearing Firestore remains fail-closed: rules
      // and token issuance still see banned=true during this short window.
      // A lift deliberately does not guess at LiveKit permissions; a fresh
      // join derives them from the current canonical room state.
      await auth.updateUser(targetUid, { disabled: false });
      await targetReference.set({
        ...banState,
        banEnforcementEventId: null,
      }, { merge: true });
    }

    await writeUserAuditLog({
      caller,
      action: banned ? "ban_user" : "unban_user",
      userId: targetUid,
      userEmail: targetUser.email,
      details: {
        reason: banned ? reason || "Administrative action" : null,
        durationHours,
        voiceEnforcementEventId: enforcementEvent?.id ?? null,
      },
    });

    return {
      success: true,
      uid: targetUid,
      banned,
      bannedUntil: timestampToIso(bannedUntil),
      voiceEnforcement: enforcementEvent
        ? { status: "queued", eventId: enforcementEvent.id }
        : null,
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

// applySanction — warnings and staff communication mutes.
//
// The third leg of the sanction system: setUserBan already owns
// suspensions and permanent bans with the same tier ceilings, and this
// callable owns the communication-level actions. One capability matrix
// decides both, so the tiers can never drift apart.
//
//   warn               moderation tier and up; a record plus an audit
//   communicationMute  bounded by the tier's ceiling; owner may make it
//                      indefinite; enforced by firestore.rules on every
//                      public communication write path
//   liftMute           super-moderation tier and up
//
// Every DENIED privileged attempt is itself audited: a moderator probing
// for a permanent mute, or a forged superAdmin probing for staff
// targets, is a fact worth keeping.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const { requireVerifiedStaff } = require("../utils/auth");
const { deriveCapabilities } = require("../utils/capabilities");
const { USER_ROLES, isProtectedOwnerUid } = require("../utils/roles");
const { db, normalizeText, positiveInteger } = require("../utils/firestore");
const { writeAuditLog } = require("../utils/audit");
const {
  EVENT_TYPES,
  enqueueVoiceEnforcement,
} = require("./voice_enforcement");

const SANCTION_ACTIONS = new Set(["warn", "communicationMute", "liftMute"]);
const auth = getAuth();

async function getTargetClaimRole(targetUid) {
  try {
    const target = await auth.getUser(targetUid);
    return String(target.customClaims?.role ?? USER_ROLES.USER).trim();
  } catch (error) {
    // A deleted Auth account can leave a profile/audit trail behind. It is
    // still safe to sanction that record based on the server mirror; every
    // other Auth failure is operational and must fail closed.
    if (error?.code === "auth/user-not-found") return USER_ROLES.USER;
    throw error;
  }
}

async function auditDeniedAttempt({ caller, action, targetUid, detail }) {
  await writeAuditLog({
    caller,
    action: "denied_sanction_attempt",
    targetType: "account",
    targetId: targetUid,
    details: { attempted: action, reason: detail },
  });
}

const applySanction = onCall(
  {
    region: "europe-west1",
    // Owner confirmation is part of the capability derivation.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (request) => {
    const caller = await requireVerifiedStaff(
      request,
      new Set([
        USER_ROLES.MODERATOR,
        USER_ROLES.SUPER_MODERATOR,
        USER_ROLES.SUPER_ADMIN,
      ]),
      "You do not have permission to sanction users.",
      { privileged: true },
    );
    const caps = deriveCapabilities({ uid: caller.uid, user: caller.profile });

    const action = String(request.data?.action ?? "");
    if (!SANCTION_ACTIONS.has(action)) {
      throw new HttpsError("invalid-argument", "Unsupported sanction action.");
    }

    const targetUid = normalizeText(request.data?.uid, 128);
    if (!targetUid || targetUid.includes("/")) {
      throw new HttpsError("invalid-argument", "A target uid is required.");
    }

    const reason = normalizeText(request.data?.reason, 500);
    if (reason.length < 3) {
      throw new HttpsError("invalid-argument", "A reason is required.");
    }

    if (targetUid === caller.uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot sanction your own account.",
      );
    }

    // Nobody sanctions the protected owner — including the owner
    // themselves (self-sanction is already refused above).
    if (isProtectedOwnerUid(targetUid)) {
      await auditDeniedAttempt({
        caller,
        action,
        targetUid,
        detail: "protectedOwnerTarget",
      });
      throw new HttpsError(
        "failed-precondition",
        "The application owner cannot be sanctioned.",
      );
    }

    // Staff targets are the owner's alone, whatever the action.
    const targetSnapshot = await db.collection("users").doc(targetUid).get();
    const target = targetSnapshot.exists ? (targetSnapshot.data() ?? {}) : {};
    const targetMirrorRole = String(target.role ?? USER_ROLES.USER).trim();
    const targetClaimRole = await getTargetClaimRole(targetUid);
    // Either side saying staff protects the target. Manual role drift and
    // stale Auth claims therefore fail closed instead of creating a brief
    // moderator-on-staff sanction window.
    const targetIsStaff =
      targetMirrorRole !== USER_ROLES.USER ||
      targetClaimRole !== USER_ROLES.USER;
    if (targetIsStaff && !caps.sanctionStaff) {
      await auditDeniedAttempt({
        caller,
        action,
        targetUid,
        detail: "staffTarget",
      });
      throw new HttpsError(
        "permission-denied",
        "Only the application owner can sanction staff accounts.",
      );
    }

    const restrictionRef = db.collection("restrictions").doc(targetUid);
    const previous = await restrictionRef.get();
    const previousState = previous.exists
      ? { type: previous.data().type ?? null }
      : { type: null };

    if (action === "warn") {
      if (!caps.warnUsers) {
        throw new HttpsError("permission-denied", "You cannot warn users.");
      }
      // The record the target can see, and the audit the log keeps.
      await db
        .collection("userWarnings")
        .doc(targetUid)
        .collection("entries")
        .add({
          reason,
          issuedBy: caller.uid,
          issuedByRole: caller.role,
          createdAt: FieldValue.serverTimestamp(),
        });
      await writeAuditLog({
        caller,
        action: "warn_user",
        targetType: "account",
        targetId: targetUid,
        details: { reason, previousState },
      });
      return { outcome: "warned" };
    }

    if (action === "communicationMute") {
      if (!caps.suspendUsers) {
        throw new HttpsError("permission-denied", "You cannot mute users.");
      }
      const durationHours = positiveInteger(
        request.data?.durationHours,
        0,
        24 * 365,
      );

      if (durationHours === 0 && caps.suspensionLimitHours !== null) {
        // An indefinite mute is the owner's alone; a probe for it below
        // that tier is recorded like every other denied attempt.
        await auditDeniedAttempt({
          caller,
          action,
          targetUid,
          detail: "indefiniteMuteBelowOwner",
        });
        throw new HttpsError(
          "permission-denied",
          "Only the application owner can mute indefinitely.",
        );
      }
      if (
        caps.suspensionLimitHours !== null &&
        durationHours > caps.suspensionLimitHours
      ) {
        throw new HttpsError(
          "invalid-argument",
          `Your role can mute for at most ${caps.suspensionLimitHours} hours.`,
        );
      }

      const expiresAt =
        durationHours > 0
          ? Timestamp.fromMillis(Date.now() + durationHours * 3600 * 1000)
          : null;

      const batch = db.batch();
      const enforcementEvent = enqueueVoiceEnforcement(batch, {
        targetUid,
        type: EVENT_TYPES.COMMUNICATION_MUTE,
        requestedBy: caller.uid,
        source: "applySanction",
      });
      batch.set(restrictionRef, {
        type: "communicationMute",
        reason,
        scope: "platform",
        expiresAt,
        appliedBy: caller.uid,
        appliedByRole: caller.role,
        voiceEnforcementEventId: enforcementEvent.id,
        createdAt: FieldValue.serverTimestamp(),
      });
      // Restriction + outbox are inseparable: after this commit every new
      // token is publish/data-denied, and the retrying trigger owns every
      // already-issued LiveKit session.
      await batch.commit();
      await writeAuditLog({
        caller,
        action: "communication_mute",
        targetType: "account",
        targetId: targetUid,
        details: {
          reason,
          scope: "platform",
          durationHours,
          expiresAt: expiresAt ? expiresAt.toDate().toISOString() : null,
          previousState,
          voiceEnforcementEventId: enforcementEvent.id,
        },
      });
      return {
        outcome: "muted",
        expiresAt: expiresAt ? expiresAt.toDate().toISOString() : null,
        voiceEnforcement: {
          status: "queued",
          eventId: enforcementEvent.id,
        },
      };
    }

    // liftMute
    if (!caps.liftSuspensions) {
      await auditDeniedAttempt({
        caller,
        action,
        targetUid,
        detail: "liftBelowTier",
      });
      throw new HttpsError(
        "permission-denied",
        "Only super moderation can lift a restriction.",
      );
    }
    await restrictionRef.delete();
    await writeAuditLog({
      caller,
      action: "lift_communication_mute",
      targetType: "account",
      targetId: targetUid,
      details: { reason, previousState },
    });
    return { outcome: "lifted" };
  },
);

module.exports = { applySanction, SANCTION_ACTIONS };

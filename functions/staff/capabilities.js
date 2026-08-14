// getMyStaffCapabilities — what the signed-in account may do, decided
// server-side and rendered client-side.
//
// Flutter shows ONLY what this returns, and every mutation Function
// re-enforces the same matrix independently — a hidden button is
// convenience, never authorization. Nothing here exposes the protected
// uid, the VIP source, or anyone else's state.

const { onCall } = require("firebase-functions/v2/https");

const { requireAuthentication } = require("../utils/auth");
const { deriveCapabilities } = require("../utils/capabilities");
const { writeAuditLog } = require("../utils/audit");
const { db } = require("../utils/firestore");

const getMyStaffCapabilities = onCall(
  {
    region: "europe-west1",
    // The owner check is part of the derivation.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (request) => {
    const auth = requireAuthentication(request);

    const [userSnapshot, grantSnapshot] = await db.getAll(
      db.collection("users").doc(auth.uid),
      db.collection("vipGrants").doc(auth.uid),
    );

    const capabilities = deriveCapabilities({
      uid: auth.uid,
      user: userSnapshot.exists ? userSnapshot.data() : {},
      grant: grantSnapshot.exists ? grantSnapshot.data() : null,
    });

    // A superAdmin role on a uid that is not the protected owner is a
    // security event, not a display nuance. Recorded every time it is
    // observed — repetition in the log is the signal.
    if (capabilities.unconfirmedSuperAdmin) {
      await writeAuditLog({
        caller: { uid: auth.uid, role: capabilities.staffRole },
        action: "security_alert_non_owner_super_admin",
        targetType: "account",
        targetId: auth.uid,
        details: { attempted: "capabilityDerivation" },
      });
    }

    // The response never carries the internal marker; the client only
    // needs what it may render.
    const { unconfirmedSuperAdmin, ...visible } = capabilities;
    return { capabilities: visible };
  },
);

module.exports = { getMyStaffCapabilities };

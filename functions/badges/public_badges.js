// The public badge mirror: publicBadges/{uid}.
//
// A DERIVED document, never an authority. It exists so that chat surfaces
// can show "moderator" or "VIP" beside a name without reading the user's
// private document — and nothing here may ever flow the other way:
// authorization decisions read the authoritative role and effectiveVip(),
// never this mirror and never an Auth claim.
//
// The whole schema is four fields:
//
//   staffRole      one of the final staff vocabulary
//   isVip          effectiveVip() at derivation time
//   schemaVersion  for future migrations of this mirror
//   updatedAt      server time of the derivation
//
// Deliberately ABSENT: email, the VIP source (paid vs complimentary is
// private billing information), assignment reasons, audit anything.
// Colours and labels are client concerns and live in Dart, not here.
//
// An ordinary account (role user, no VIP) has NO document — absence is
// the common case, and it keeps the collection from being a mirror of the
// entire user base.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue } = require("firebase-admin/firestore");

const { STAFF_ROLES, USER_ROLES } = require("../utils/roles");
const { isConfirmedOwner } = require("../utils/capabilities");
const { effectiveVip } = require("../utils/entitlements");
const { isActiveAccountProfile } = require("../utils/premium_access");
const { requireAuthentication } = require("../utils/auth");
const { writeAuditLog } = require("../utils/audit");
const { db, normalizeText } = require("../utils/firestore");

const BADGE_SCHEMA_VERSION = 1;
const MAX_BATCH_UIDS = 50;

/// The role the mirror may PUBLISH for this account — which is not always
/// the role the user document claims. `superAdmin` is the owner's badge,
/// and the owner is a uid held in Secret Manager, not a Firestore field:
/// a forged or stale `superAdmin` on any other uid is published as the
/// tier the capability matrix actually grants it (super moderation),
/// exactly mirroring deriveCapabilities()' fail-safe. Same rule when the
/// secret is unavailable: with no way to confirm the owner, nobody is
/// published as the owner.
function derivePublicRole(uid, user) {
  const rawRole = String(user.role ?? USER_ROLES.USER);
  // The mirror must never publish a value outside the vocabulary. An
  // unknown role is treated as `user` FOR THE BADGE ONLY — the backfill
  // reports it as invalid so it gets fixed at the source, but the public
  // mirror fails to the least-claiming value rather than repeating an
  // anomaly to every signed-in reader.
  const staffRole = STAFF_ROLES.has(rawRole) ? rawRole : USER_ROLES.USER;

  if (staffRole !== USER_ROLES.SUPER_ADMIN) {
    return { staffRole, unconfirmedSuperAdmin: false };
  }
  if (isConfirmedOwner(uid)) {
    return { staffRole, unconfirmedSuperAdmin: false };
  }
  return {
    staffRole: USER_ROLES.SUPER_MODERATOR,
    unconfirmedSuperAdmin: true,
  };
}

/// Derives the badge that SHOULD exist for this user, from already-loaded
/// documents. Pure, so the whole decision is unit-testable and the
/// backfill can reuse it byte-for-byte.
///
/// Returns null when no document should exist.
function deriveBadge({ uid = null, user = null, grant = null, now = new Date() } = {}) {
  // The caller passes null when either the private profile or the Auth
  // identity is absent/inactive. In every one of those cases no public badge
  // may survive, whatever grant documents might linger.
  if (!isActiveAccountProfile(user)) return null;

  const { staffRole } = derivePublicRole(uid, user);

  const { vip } = effectiveVip({ user, grant, now });

  if (staffRole === USER_ROLES.USER && !vip) return null;

  return {
    staffRole,
    isVip: vip,
    schemaVersion: BADGE_SCHEMA_VERSION,
  };
}

/// Firebase Auth is authoritative for whether the identity still exists and
/// is enabled. A lingering users/{uid} document after Auth deletion must never
/// recreate a public role/VIP projection. Injectable because the Functions
/// unit suite intentionally runs against the Firestore emulator alone.
async function fetchAuthUserOrNull(uid) {
  try {
    return await getAuth().getUser(uid);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return null;
    throw error;
  }
}

/// Synchronises publicBadges/{uid} with the authoritative state.
///
/// Idempotent and CONVERGENT: it derives from the CURRENT user and grant
/// documents, never from an event payload, so repeated or out-of-order
/// trigger deliveries all land on the same final document. A failure is
/// retried by the trigger machinery, and the next successful run reads
/// fresh state — a stale badge cannot survive a later write.
async function syncPublicBadgeForUser(
  uid,
  {
    database = db,
    fetchAuthUser = fetchAuthUserOrNull,
  } = {},
) {
  const cleanUid = String(uid ?? "").trim();
  if (!cleanUid || cleanUid.includes("/")) return { outcome: "invalidUid" };

  const [[userSnapshot, grantSnapshot], authUser] = await Promise.all([
    database.getAll(
      database.collection("users").doc(cleanUid),
      database.collection("vipGrants").doc(cleanUid),
    ),
    fetchAuthUser(cleanUid),
  ]);

  const authActive = authUser !== null && authUser?.disabled !== true;
  const user = authActive && userSnapshot.exists ? userSnapshot.data() : null;

  // A superAdmin role on a uid that is not the protected owner is a
  // security event, not a display nuance — same alert the capability
  // callable raises, so both derivations light up the one log. The badge
  // itself fails safe below regardless of whether this write lands.
  if (user !== null && derivePublicRole(cleanUid, user).unconfirmedSuperAdmin) {
    await writeAuditLog({
      caller: { uid: cleanUid, role: String(user.role ?? USER_ROLES.USER) },
      action: "security_alert_non_owner_super_admin",
      targetType: "account",
      targetId: cleanUid,
      details: { attempted: "badgeDerivation" },
    });
  }

  const badge = deriveBadge({
    uid: cleanUid,
    user,
    grant: grantSnapshot.exists ? grantSnapshot.data() : null,
  });

  const ref = database.collection("publicBadges").doc(cleanUid);

  if (badge === null) {
    // Delete is idempotent: removing an absent document is a no-op, so a
    // retried revocation event is harmless.
    await ref.delete();
    return { outcome: "removed" };
  }

  // set() WITHOUT merge, on purpose: the mirror is fully derived, so any
  // field not in the derivation must not survive a sync. This is also
  // what heals a document that somehow acquired extra fields.
  await ref.set({ ...badge, updatedAt: FieldValue.serverTimestamp() });
  return { outcome: "written", staffRole: badge.staffRole, isVip: badge.isVip };
}

// ---------------------------------------------------------------- triggers
//
// Two triggers cover every path that can change what a badge derives
// from: users/{uid} carries the authoritative role AND premiumIdentity
// (so role assignment, bootstrap, premium changes and account deletion
// all land here), and vipGrants/{uid} carries the complimentary grant
// (grant, revoke, and expiry-as-a-write).
//
// The one thing a write-trigger cannot see is a grant lapsing by pure
// passage of time. Every grant that exists today is non-expiring
// (source legacyRoleMigration would have been, and none were created);
// when expiring grants ship, their creation flow must come with a
// scheduled sweep. Until then this is a documented non-case, not a gap.

// Both triggers bind the owner secret: derivePublicRole() needs it to
// confirm — never to grant — the owner badge. Without it every superAdmin
// would fail safe to superModerator, including the real owner.
const onUserBadgeSourceChanged = onDocumentWritten(
  {
    document: "users/{uid}",
    region: "europe-west1",
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (event) => {
    // Only the uid is taken from the event; state is re-read inside the
    // sync so out-of-order deliveries converge instead of racing.
    await syncPublicBadgeForUser(event.params.uid);
  },
);

const onVipGrantChanged = onDocumentWritten(
  {
    document: "vipGrants/{uid}",
    region: "europe-west1",
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (event) => {
    await syncPublicBadgeForUser(event.params.uid);
  },
);

// ---------------------------------------------------------------- batch read
//
// Chat surfaces resolve the badges for a screenful of messages in ONE
// call instead of a get per sender — the N+1 this endpoint exists to
// prevent. Bounded, deduplicated, authenticated, and it returns only the
// four public fields whatever the stored document contains.

const getPublicBadges = onCall(
  {
    region: "europe-west1",
    // Defense in depth: a STORED superAdmin row that predates the owner
    // guard (or was planted by anything that slips past the rules) is
    // demoted in the response until a sync or backfill heals the
    // document itself. Confirming the owner needs the secret.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (request) => {
  requireAuthentication(request);

  const rawUids = request.data?.uids;
  if (!Array.isArray(rawUids)) {
    throw new HttpsError("invalid-argument", "uids must be an array.");
  }
  if (rawUids.length === 0) {
    return { badges: {} };
  }
  if (rawUids.length > MAX_BATCH_UIDS) {
    throw new HttpsError(
      "invalid-argument",
      `At most ${MAX_BATCH_UIDS} uids per request.`,
    );
  }

  const uids = [];
  const seen = new Set();
  for (const raw of rawUids) {
    if (typeof raw !== "string") {
      throw new HttpsError("invalid-argument", "Every uid must be a string.");
    }
    const uid = normalizeText(raw, 128);
    if (!uid || uid.includes("/") || uid === "." || uid === "..") {
      throw new HttpsError("invalid-argument", "A uid is not valid.");
    }
    if (seen.has(uid)) continue;
    seen.add(uid);
    uids.push(uid);
  }

  const snapshots = await db.getAll(
    ...uids.map((uid) => db.collection("publicBadges").doc(uid)),
  );

  const badges = {};
  for (const snapshot of snapshots) {
    if (!snapshot.exists) continue;
    const data = snapshot.data() ?? {};
    // Explicit field picking: whatever the stored document holds, the
    // response carries exactly the public schema and nothing else. The
    // stored role passes through the same owner confirmation as the
    // derivation, so a stale superAdmin row cannot badge a non-owner.
    const { staffRole } = derivePublicRole(snapshot.id, {
      role: data.staffRole,
    });
    badges[snapshot.id] = {
      staffRole,
      isVip: data.isVip === true,
      schemaVersion: Number(data.schemaVersion ?? BADGE_SCHEMA_VERSION),
      updatedAt:
        typeof data.updatedAt?.toDate === "function"
          ? data.updatedAt.toDate().toISOString()
          : null,
    };
  }

  return { badges };
  },
);

module.exports = {
  BADGE_SCHEMA_VERSION,
  MAX_BATCH_UIDS,
  deriveBadge,
  derivePublicRole,
  fetchAuthUserOrNull,
  syncPublicBadgeForUser,
  onUserBadgeSourceChanged,
  onVipGrantChanged,
  getPublicBadges,
};

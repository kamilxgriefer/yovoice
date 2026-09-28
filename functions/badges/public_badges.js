// The public badge mirror: publicBadges/{uid}.
//
// A DERIVED document, never an authority. It exists so that chat surfaces
// can show "moderator" or "VIP" beside a name without reading the user's
// private document — and nothing here may ever flow the other way:
// authorization decisions read the authoritative role and effectiveVip(),
// never this mirror and never an Auth claim.
//
// The whole schema is five fields:
//
//   staffRole      one of the final staff vocabulary
//   isVip          the paid mirror or the staff preview (effectiveVip), or
//                  a CANONICAL vipGrant checked with its expiresAt (the
//                  ADR-230 predicate, canonicalLikersVipGrant): the rosette
//                  never trusts a grant shape the capability would refuse
//                  (ADR-233 §2.8)
//   page           "business" | "community" | null: the account runs a
//                  visible Premium Page (ADR-233 §1.11). Presentation only:
//                  it authorizes nothing, and every Pages callable re-reads
//                  pages/{uid} itself
//   schemaVersion  for future migrations of this mirror
//   updatedAt      server time of the derivation
//
// Deliberately ABSENT: email, the VIP source (paid vs complimentary is
// private billing information), assignment reasons, audit anything.
// Colours and labels are client concerns and live in Dart, not here.
//
// An ordinary account (role user, no VIP, no visible Page) has NO document —
// absence is the common case, and it keeps the collection from being a
// mirror of the entire user base.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { STAFF_ROLES, USER_ROLES } = require("../utils/roles");
const { isConfirmedOwner } = require("../utils/capabilities");
const { effectiveVip } = require("../utils/entitlements");
const { canonicalLikersVipGrant } = require("../utils/likers_access");
const { isActiveAccountProfile } = require("../utils/premium_access");
const { requireAuthentication } = require("../utils/auth");
const { writeAuditLog } = require("../utils/audit");
const { canonicalPageOrNull } = require("../pages/contract");
const { db, normalizeText } = require("../utils/firestore");
const {
  consumeRateLimit,
  rateLimitReference,
  transactionGetAll,
} = require("../integrity/guards");

const BADGE_SCHEMA_VERSION = 1;
const MAX_BATCH_UIDS = 20;
const BADGE_CACHE_TTL_MS = 30_000;
const BADGE_CACHE_MAX_ENTRIES = 2_000;
const BADGE_RATE_LIMITS = Object.freeze({
  minute: Object.freeze({ maxEvents: 30, windowMs: 60_000 }),
  hour: Object.freeze({ maxEvents: 200, windowMs: 60 * 60_000 }),
});
const publicBadgeCache = new Map();

function clearPublicBadgeCacheForTests() {
  publicBadgeCache.clear();
}

function cacheBadge(uid, value, nowMs) {
  if (publicBadgeCache.size >= BADGE_CACHE_MAX_ENTRIES) {
    const oldestKey = publicBadgeCache.keys().next().value;
    if (oldestKey !== undefined) publicBadgeCache.delete(oldestKey);
  }
  publicBadgeCache.set(uid, { expiresAt: nowMs + BADGE_CACHE_TTL_MS, value });
}

async function consumeBadgeReadAttempt(uid, nowMs = Date.now()) {
  const now = Timestamp.fromMillis(nowMs);
  const minuteScope = "public.badges.read.minute";
  const hourScope = "public.badges.read.hour";
  const minuteRef = rateLimitReference(db, minuteScope, uid);
  const hourRef = rateLimitReference(db, hourScope, uid);
  await db.runTransaction(async (transaction) => {
    const [minute, hour] = await transactionGetAll(
      transaction,
      minuteRef,
      hourRef,
    );
    consumeRateLimit(transaction, minute, {
      reference: minuteRef,
      scope: minuteScope,
      uid,
      nowMs,
      now,
      ...BADGE_RATE_LIMITS.minute,
    });
    consumeRateLimit(transaction, hour, {
      reference: hourRef,
      scope: hourScope,
      uid,
      nowMs,
      now,
      ...BADGE_RATE_LIMITS.hour,
    });
  });
}

async function readBadgeDocuments(uids, nowMs = Date.now()) {
  const values = new Map();
  const misses = [];
  for (const uid of uids) {
    const cached = publicBadgeCache.get(uid);
    if (cached && cached.expiresAt > nowMs) {
      values.set(uid, cached.value);
    } else {
      if (cached) publicBadgeCache.delete(uid);
      misses.push(uid);
    }
  }
  if (misses.length > 0) {
    const snapshots = await db.getAll(
      ...misses.map((uid) => db.collection("publicBadges").doc(uid)),
    );
    for (const snapshot of snapshots) {
      const value = snapshot.exists ? (snapshot.data() ?? {}) : null;
      values.set(snapshot.id, value);
      cacheBadge(snapshot.id, value, nowMs);
    }
  }
  return values;
}

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

const PAGE_BADGE_KINDS = Object.freeze(["business", "community"]);

/// The Page kind a badge publishes (ADR-233 §1.11): non-null only for a
/// canonical Page whose stored status is active or readOnly and which is
/// neither owner-paused nor suspended. A malformed Page publishes nothing.
/// The stored status is used (not the read-time 30-day boundary): the lapse
/// sweep writes `hidden`, and that write re-derives the badge.
function derivePageBadge(page) {
  if (!page) return null;
  if (!["active", "readOnly"].includes(page.status)) return null;
  if (page.ownerPaused === true || page.suspended === true) return null;
  return PAGE_BADGE_KINDS.includes(page.kind) ? page.kind : null;
}

/// The badge's VIP bit (the rosette, ADR-233 §2.8 / §4.6). The paid mirror
/// and the staff preview come from effectiveVip exactly as before; the
/// complimentary grant counts only when it is CANONICAL and unexpired
/// (canonicalLikersVipGrant, the predicate the Pages capability itself
/// uses), never through the fail-open grantIsActive. A grant that expires by
/// time is picked up by the next derivation: a Page's lapse transition
/// writes pages/{uid}, which re-derives the badge.
function deriveBadgeVip({ user, grant, now }) {
  const { vip } = effectiveVip({ user, grant: null, now });
  return vip || canonicalLikersVipGrant(grant, now);
}

/// Derives the badge that SHOULD exist for this user, from already-loaded
/// documents. Pure, so the whole decision is unit-testable and the
/// backfill can reuse it byte-for-byte. `page` is the CANONICAL Page (or
/// null); callers load it with canonicalPageOrNull.
///
/// Returns null when no document should exist.
function deriveBadge({
  uid = null,
  user = null,
  grant = null,
  page = null,
  now = new Date(),
} = {}) {
  // The caller passes null when either the private profile or the Auth
  // identity is absent/inactive. In every one of those cases no public badge
  // may survive, whatever grant documents might linger.
  if (!isActiveAccountProfile(user)) return null;

  const { staffRole } = derivePublicRole(uid, user);

  const vip = deriveBadgeVip({ user, grant, now });

  const pageKind = derivePageBadge(page);

  if (staffRole === USER_ROLES.USER && !vip && pageKind === null) return null;

  return {
    staffRole,
    isVip: vip,
    page: pageKind,
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

  // pages/{uid} is read HERE, in the one derivation every trigger (users,
  // vipGrants, pages) runs, so the merge-free set() below can never drop a
  // `page` another trigger wrote.
  const [[userSnapshot, grantSnapshot, pageSnapshot], authUser] = await Promise.all([
    database.getAll(
      database.collection("users").doc(cleanUid),
      database.collection("vipGrants").doc(cleanUid),
      database.collection("pages").doc(cleanUid),
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
    page: canonicalPageOrNull(pageSnapshot, cleanUid),
  });

  const ref = database.collection("publicBadges").doc(cleanUid);
  publicBadgeCache.delete(cleanUid);

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
  return {
    outcome: "written",
    staffRole: badge.staffRole,
    isVip: badge.isVip,
    page: badge.page,
  };
}

// ---------------------------------------------------------------- triggers
//
// Three triggers cover every path that can change what a badge derives
// from: users/{uid} carries the authoritative role AND premiumIdentity
// (so role assignment, bootstrap, premium changes and account deletion
// all land here), vipGrants/{uid} carries the complimentary grant
// (grant, revoke, and expiry-as-a-write), and pages/{uid} carries the
// Premium Page state (onPageBadgeSourceChanged, defined just before the
// batch reader).
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

// The Premium Pages source (ADR-233 §1.11). A Page write re-derives the
// badge ONLY when something the badge shows can change: existence, kind,
// stored status, ownerPaused or suspended. Counter, name-mirror and profile
// edits (postCount, lastPostAt, listed, description, ...) return early, so a
// publishing Page does not rewrite its badge on every post.
function pageBadgeSourceChanged(before, after) {
  const beforeData = before?.exists ? (before.data() ?? {}) : null;
  const afterData = after?.exists ? (after.data() ?? {}) : null;
  if ((beforeData === null) !== (afterData === null)) return true;
  if (beforeData === null) return false;
  return ["kind", "status", "ownerPaused", "suspended"].some(
    (key) => beforeData[key] !== afterData[key],
  );
}

const onPageBadgeSourceChanged = onDocumentWritten(
  {
    document: "pages/{uid}",
    region: "europe-west1",
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (event) => {
    if (!pageBadgeSourceChanged(event.data?.before, event.data?.after)) return;
    await syncPublicBadgeForUser(event.params.uid);
  },
);

// ---------------------------------------------------------------- batch read
//
// Chat surfaces resolve the badges for a screenful of messages in ONE
// call instead of a get per sender — the N+1 this endpoint exists to
// prevent. Bounded, deduplicated, authenticated, and it returns only the
// five public fields whatever the stored document contains.

const getPublicBadges = onCall(
  {
    region: "europe-west1",
    maxInstances: 20,
    // Defense in depth: a STORED superAdmin row that predates the owner
    // guard (or was planted by anything that slips past the rules) is
    // demoted in the response until a sync or backfill heals the
    // document itself. Confirming the owner needs the secret.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (request) => {
  const auth = requireAuthentication(request);

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

  // This quota commits before any target document reads. A rejected or
  // cache-miss-heavy request therefore cannot roll its own throttle back.
  await consumeBadgeReadAttempt(auth.uid);
  const badgeDocuments = await readBadgeDocuments(uids);

  const badges = {};
  for (const uid of uids) {
    const data = badgeDocuments.get(uid);
    if (data === null || data === undefined) continue;
    // Explicit field picking: whatever the stored document holds, the
    // response carries exactly the public schema and nothing else. The
    // stored role passes through the same owner confirmation as the
    // derivation, so a stale superAdmin row cannot badge a non-owner.
    const { staffRole } = derivePublicRole(uid, {
      role: data.staffRole,
    });
    badges[uid] = {
      staffRole,
      isVip: data.isVip === true,
      page: PAGE_BADGE_KINDS.includes(data.page) ? data.page : null,
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
  BADGE_CACHE_TTL_MS,
  BADGE_RATE_LIMITS,
  MAX_BATCH_UIDS,
  PAGE_BADGE_KINDS,
  clearPublicBadgeCacheForTests,
  deriveBadge,
  deriveBadgeVip,
  derivePageBadge,
  derivePublicRole,
  pageBadgeSourceChanged,
  fetchAuthUserOrNull,
  syncPublicBadgeForUser,
  onUserBadgeSourceChanged,
  onVipGrantChanged,
  onPageBadgeSourceChanged,
  getPublicBadges,
};

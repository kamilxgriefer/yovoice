// The staff user directory: userDirectory/{uid}.
//
// A DERIVED, server-only search index — never an authority, and never
// client-readable. It exists because Firestore cannot answer "find
// Sieeema whatever the casing" against `users` (usernames are stored as
// typed, equality is case-sensitive, and display names were never
// searchable at all — the exact production lookup failure). The
// directory carries NORMALIZED search fields the owner's callable can
// range-query, plus the flags the Staff Center filters on.
//
// Access model, deliberately narrow:
//   * documents: no client read or write, ever (firestore.rules denies;
//     this collection would otherwise be a user-enumeration oracle);
//   * search: the searchUserDirectory callable, PROTECTED-OWNER-ONLY —
//     a superAdmin claim alone is not enough, and a forged one is
//     audited by requireProtectedOwner on its way to permission-denied.
//
// Schema (schemaVersion 1):
//   displayName, username, email, photoUrl   as stored / from Auth
//   displayNameLower, usernameLower,
//   emailLower                               normalized (NFKC, trimmed,
//                                            whitespace-collapsed,
//                                            lowercased)
//   staffRole                                the PUBLIC effective role —
//                                            derivePublicRole, so a
//                                            forged superAdmin can never
//                                            wear the owner label here
//   isStaff, isVip, banned, restricted      filter flags
//   createdAt                                Auth account creation time
//   updatedAt, schemaVersion                 bookkeeping
//
// The email lives here because the OWNER legitimately searches by it;
// the collection is unreadable by clients and the callable is owner-only,
// so nothing public ever carries it.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const { USER_ROLES } = require("../utils/roles");
const { derivePublicRole } = require("../badges/public_badges");
const { effectiveVip } = require("../utils/entitlements");
const { requireProtectedOwner } = require("../utils/auth");
const { db, normalizeText, positiveInteger, timestampToIso } = require("../utils/firestore");

const DIRECTORY_SCHEMA_VERSION = 1;
const MAX_PAGE_SIZE = 20;
const MIN_NAME_QUERY_LENGTH = 2;

// Range-query upper bound for prefix search: everything that starts
// with the prefix sorts before prefix + this sentinel.
const PREFIX_END = "";

const FILTERS = Object.freeze([
  "all",
  "staff",
  "vip",
  "restricted",
  "banned",
  "recent",
]);

/// One normalization for every search-facing string, applied identically
/// at WRITE time (directory fields) and at QUERY time (the input), which
/// is the whole trick: two values match when their normal forms match.
/// NFKC folds Unicode compatibility forms; the regex collapses interior
/// whitespace runs; lowercase is locale-independent.
function normalizeSearchText(raw) {
  return String(raw ?? "")
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

/// An active restriction, mirroring firestore.rules' canCommunicate():
/// the document exists, and either never expires or has not expired.
function restrictionIsActive(restriction, now = new Date()) {
  if (!restriction || typeof restriction !== "object") return false;
  const expires = restriction.expiresAt;
  if (expires === null || expires === undefined) return true;
  const expiry =
    typeof expires?.toDate === "function" ? expires.toDate() : new Date(expires);
  if (Number.isNaN(expiry.getTime())) return false;
  return expiry.getTime() > now.getTime();
}

/// Derives the directory entry that SHOULD exist, from already-loaded
/// documents. Pure — the trigger sync, the callable's on-the-fly
/// derivation and the backfill all share it byte-for-byte.
///
/// Auth is authoritative for EXISTENCE: no auth user means no entry,
/// whatever documents linger. A profile document is optional — an
/// account that never wrote one is still discoverable through its Auth
/// identity, which is the "missing optional profile field" guarantee.
function deriveDirectoryEntry({
  uid,
  authUser = null,
  user = null,
  grant = null,
  restriction = null,
  now = new Date(),
} = {}) {
  if (!authUser) return null;

  const profile = user ?? {};
  const displayName = String(
    profile.displayName ?? authUser.displayName ?? "",
  ).trim();
  const username = String(profile.username ?? "").trim();
  const email = authUser.email ?? profile.email ?? null;

  const { staffRole } = derivePublicRole(uid, profile);
  const { vip } = effectiveVip({ user: profile, grant, now });

  const createdAtMillis = authUser.metadata?.creationTime
    ? Date.parse(authUser.metadata.creationTime)
    : NaN;

  return {
    displayName,
    username,
    email,
    photoUrl: profile.photoUrl ?? authUser.photoURL ?? null,
    displayNameLower: normalizeSearchText(displayName),
    usernameLower: normalizeSearchText(username),
    emailLower: normalizeSearchText(email ?? ""),
    staffRole,
    isStaff: staffRole !== USER_ROLES.USER,
    isVip: vip,
    banned: profile.banned === true || authUser.disabled === true,
    restricted: restrictionIsActive(restriction, now),
    createdAt: Number.isNaN(createdAtMillis)
      ? null
      : Timestamp.fromMillis(createdAtMillis),
    schemaVersion: DIRECTORY_SCHEMA_VERSION,
  };
}

/// The default Auth lookup, injectable for tests (the Functions test
/// suite runs against the Firestore emulator alone).
async function fetchAuthUserOrNull(uid) {
  try {
    return await getAuth().getUser(uid);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return null;
    throw error;
  }
}

/// Synchronises userDirectory/{uid} with authoritative state. Idempotent
/// and convergent for the same reason the badge sync is: state is
/// re-read on every run, never taken from an event payload.
async function syncUserDirectoryForUser(uid, { fetchAuthUser = fetchAuthUserOrNull } = {}) {
  const cleanUid = String(uid ?? "").trim();
  if (!cleanUid || cleanUid.includes("/")) return { outcome: "invalidUid" };

  const [userSnapshot, grantSnapshot, restrictionSnapshot, authUser] =
    await Promise.all([
      db.collection("users").doc(cleanUid).get(),
      db.collection("vipGrants").doc(cleanUid).get(),
      db.collection("restrictions").doc(cleanUid).get(),
      fetchAuthUser(cleanUid),
    ]);

  const entry = deriveDirectoryEntry({
    uid: cleanUid,
    authUser,
    user: userSnapshot.exists ? userSnapshot.data() : null,
    grant: grantSnapshot.exists ? grantSnapshot.data() : null,
    restriction: restrictionSnapshot.exists ? restrictionSnapshot.data() : null,
  });

  const ref = db.collection("userDirectory").doc(cleanUid);
  if (entry === null) {
    await ref.delete();
    return { outcome: "removed" };
  }

  // set() WITHOUT merge: fully derived, foreign fields must not survive.
  await ref.set({ ...entry, updatedAt: FieldValue.serverTimestamp() });
  return { outcome: "written" };
}

// ---------------------------------------------------------------- triggers
//
// Three sources can change what an entry derives from: the user document
// (role, names, ban, premium), the VIP grant, and the restriction. All
// three bind the owner secret because derivePublicRole confirms — never
// grants — the owner badge inside the derivation.

const DIRECTORY_TRIGGER_OPTIONS = (document) => ({
  document,
  region: "europe-west1",
  secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
});

const onDirectoryUserChanged = onDocumentWritten(
  DIRECTORY_TRIGGER_OPTIONS("users/{uid}"),
  async (event) => {
    await syncUserDirectoryForUser(event.params.uid);
  },
);

const onDirectoryVipGrantChanged = onDocumentWritten(
  DIRECTORY_TRIGGER_OPTIONS("vipGrants/{uid}"),
  async (event) => {
    await syncUserDirectoryForUser(event.params.uid);
  },
);

const onDirectoryRestrictionChanged = onDocumentWritten(
  DIRECTORY_TRIGGER_OPTIONS("restrictions/{uid}"),
  async (event) => {
    await syncUserDirectoryForUser(event.params.uid);
  },
);

// ---------------------------------------------------------------- search

/// Explicit field picking for every row that leaves the server, with the
/// stored role passed through the owner confirmation once more — the
/// same defense-in-depth getPublicBadges applies.
function mapDirectoryRow(uid, data) {
  const { staffRole } = derivePublicRole(uid, { role: data.staffRole });
  return {
    uid,
    displayName: String(data.displayName ?? ""),
    username: String(data.username ?? ""),
    email: data.email ?? null,
    photoUrl: data.photoUrl ?? null,
    staffRole,
    isVip: data.isVip === true,
    banned: data.banned === true,
    restricted: data.restricted === true,
    createdAt: timestampToIso(data.createdAt) ?? null,
  };
}

function filterFlagMatches(filter, row) {
  switch (filter) {
    case "staff":
      return row.staffRole !== USER_ROLES.USER;
    case "vip":
      return row.isVip === true;
    case "restricted":
      return row.restricted === true;
    case "banned":
      return row.banned === true;
    default:
      return true;
  }
}

// A name search fetches at most this many candidates per branch before
// merging. Two branches make the whole operation bounded at twice this,
// which is plenty for a human-typed admin prefix and never a scan of
// the collection.
const NAME_BRANCH_LIMIT = 100;

/// Prefix range on one normalized field.
async function prefixQuery(field, prefix) {
  return db
    .collection("userDirectory")
    .orderBy(field)
    .startAt(prefix)
    .endAt(prefix + PREFIX_END)
    .limit(NAME_BRANCH_LIMIT)
    .get();
}

function decodeCursor(raw) {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(Buffer.from(raw, "base64url").toString("utf8"));
    return typeof parsed === "object" && parsed !== null ? parsed : null;
  } catch (_) {
    return null;
  }
}

function encodeCursor(cursor) {
  if (!cursor) return null;
  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

/// The one search endpoint. PROTECTED-OWNER-ONLY: user enumeration is an
/// ownership capability until a narrower staff search capability is
/// deliberately defined. requireProtectedOwner double-checks the claim
/// against the server record, confirms the uid against the secret, and
/// AUDITS a forged superAdmin on its way out.
///
/// Modes, decided from the normalized input:
///   uid      exact document / Auth id (case-sensitive, raw trimmed)
///   email    contains '@' beyond position 0 — Auth first (authoritative,
///            case-insensitive), directory emailLower second
///   name     ≥2 chars — case-insensitive PREFIX over usernameLower and
///            displayNameLower (leading '@' stripped), merged, exact
///            matches first; display names are not unique so this is
///            always a LIST
///   browse   empty query — the filter tabs, newest accounts first
const searchUserDirectory = onCall(
  {
    region: "europe-west1",
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    await requireProtectedOwner(request);

    const rawQuery = String(request.data?.query ?? "");
    const trimmedRaw = rawQuery.normalize("NFKC").trim().replace(/\s+/g, " ");
    const filter = normalizeText(request.data?.filter, 20) || "all";
    if (!FILTERS.includes(filter)) {
      throw new HttpsError("invalid-argument", "Unknown filter.");
    }
    const limit = positiveInteger(request.data?.limit, MAX_PAGE_SIZE, MAX_PAGE_SIZE);
    const cursor = decodeCursor(normalizeText(request.data?.cursor, 2048));

    // ------------------------------------------------ browse (no query)
    if (trimmedRaw.length === 0) {
      let query = db.collection("userDirectory");
      if (filter === "staff") query = query.where("isStaff", "==", true);
      else if (filter === "vip") query = query.where("isVip", "==", true);
      else if (filter === "restricted") query = query.where("restricted", "==", true);
      else if (filter === "banned") query = query.where("banned", "==", true);
      // "all" and "recent" browse the same way: newest accounts first.
      // Ties resolve on the implicit __name__ ordering, which the
      // document-snapshot cursor below respects.
      query = query.orderBy("createdAt", "desc").limit(limit);
      if (cursor?.browse) {
        const cursorSnapshot = await db
          .collection("userDirectory")
          .doc(String(cursor.browse))
          .get();
        if (cursorSnapshot.exists) query = query.startAfter(cursorSnapshot);
      }
      const snapshot = await query.get();
      const users = snapshot.docs.map((doc) => mapDirectoryRow(doc.id, doc.data()));
      return {
        mode: "browse",
        users,
        nextCursor:
          snapshot.size === limit
            ? encodeCursor({ browse: snapshot.docs[snapshot.size - 1].id })
            : null,
      };
    }

    // ------------------------------------------------ exact uid
    // Tried on the RAW trimmed input — uids are case-sensitive and never
    // normalized. A directory hit answers directly; an Auth hit for an
    // account the directory has not mirrored yet is derived on the fly,
    // read-only.
    if (!trimmedRaw.includes(" ")) {
      const uidCandidate = trimmedRaw;
      const directoryHit = await db
        .collection("userDirectory")
        .doc(uidCandidate)
        .get();
      if (directoryHit.exists) {
        return {
          mode: "uid",
          users: [mapDirectoryRow(directoryHit.id, directoryHit.data())],
          nextCursor: null,
        };
      }
    }

    const normalized = normalizeSearchText(trimmedRaw);

    // ------------------------------------------------ email
    if (normalized.includes("@") && !normalized.startsWith("@")) {
      let authUser = null;
      try {
        authUser = await getAuth().getUserByEmail(normalized);
      } catch (error) {
        if (error?.code !== "auth/user-not-found") throw error;
      }
      if (authUser) {
        const entrySnapshot = await db
          .collection("userDirectory")
          .doc(authUser.uid)
          .get();
        if (entrySnapshot.exists) {
          return {
            mode: "email",
            users: [mapDirectoryRow(entrySnapshot.id, entrySnapshot.data())],
            nextCursor: null,
          };
        }
        // Not mirrored yet: merge Auth identity with the profile the
        // way the derivation would, so the account is still findable.
        const [userSnapshot, grantSnapshot, restrictionSnapshot] =
          await Promise.all([
            db.collection("users").doc(authUser.uid).get(),
            db.collection("vipGrants").doc(authUser.uid).get(),
            db.collection("restrictions").doc(authUser.uid).get(),
          ]);
        const entry = deriveDirectoryEntry({
          uid: authUser.uid,
          authUser,
          user: userSnapshot.exists ? userSnapshot.data() : null,
          grant: grantSnapshot.exists ? grantSnapshot.data() : null,
          restriction: restrictionSnapshot.exists
            ? restrictionSnapshot.data()
            : null,
        });
        return {
          mode: "email",
          users: entry ? [mapDirectoryRow(authUser.uid, entry)] : [],
          nextCursor: null,
        };
      }
      const byEmail = await db
        .collection("userDirectory")
        .where("emailLower", "==", normalized)
        .limit(limit)
        .get();
      return {
        mode: "email",
        users: byEmail.docs.map((doc) => mapDirectoryRow(doc.id, doc.data())),
        nextCursor: null,
      };
    }

    // ------------------------------------------------ name / username
    const nameQuery = normalized.startsWith("@")
      ? normalized.slice(1).trim()
      : normalized;
    if (nameQuery.length < MIN_NAME_QUERY_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Type at least ${MIN_NAME_QUERY_LENGTH} characters to search by name.`,
      );
    }

    const [byUsername, byDisplayName] = await Promise.all([
      prefixQuery("usernameLower", nameQuery),
      prefixQuery("displayNameLower", nameQuery),
    ]);

    const merged = new Map();
    for (const doc of [...byUsername.docs, ...byDisplayName.docs]) {
      if (!merged.has(doc.id)) merged.set(doc.id, doc.data());
    }

    const rows = [...merged.entries()]
      .map(([uid, data]) => ({ uid, data, row: mapDirectoryRow(uid, data) }))
      .filter(({ row }) => filterFlagMatches(filter, row));

    // Exact normalized matches outrank prefix matches; ties sort by the
    // normalized username, then uid, so the order is deterministic and
    // an offset cursor pages it stably.
    rows.sort((a, b) => {
      const aExact =
        a.data.usernameLower === nameQuery || a.data.displayNameLower === nameQuery
          ? 0
          : 1;
      const bExact =
        b.data.usernameLower === nameQuery || b.data.displayNameLower === nameQuery
          ? 0
          : 1;
      if (aExact !== bExact) return aExact - bExact;
      const byName = a.data.usernameLower.localeCompare(b.data.usernameLower);
      return byName !== 0 ? byName : a.uid.localeCompare(b.uid);
    });

    // Offset pagination over the bounded, deterministically-ordered
    // candidate set: each page re-runs the same two range queries and
    // slices further in. Honest about its bound — a prefix matching
    // more than NAME_BRANCH_LIMIT accounts per branch needs more typed
    // characters, which the UI's result count makes obvious.
    const offset = Number.isInteger(cursor?.offset) && cursor.offset > 0
      ? cursor.offset
      : 0;
    const page = rows.slice(offset, offset + limit);
    const nextCursor =
      offset + limit < rows.length
        ? encodeCursor({ offset: offset + limit })
        : null;

    return {
      mode: "name",
      users: page.map(({ row }) => row),
      nextCursor,
    };
  },
);

module.exports = {
  DIRECTORY_SCHEMA_VERSION,
  MAX_PAGE_SIZE,
  MIN_NAME_QUERY_LENGTH,
  normalizeSearchText,
  restrictionIsActive,
  deriveDirectoryEntry,
  syncUserDirectoryForUser,
  onDirectoryUserChanged,
  onDirectoryVipGrantChanged,
  onDirectoryRestrictionChanged,
  searchUserDirectory,
};

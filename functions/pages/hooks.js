// Page-side effects of EXISTING profile callables (ADR-233 §2.2 "Hooks").
//
// A leaf module: it depends on the Pages contract and visibility index only,
// never on profile/public_profiles.js, so the profile modules can require it
// without a cycle.
//
//   * updateMyDisplayName: whenever pages/{uid} exists, paused or not, the new
//     name must pass name_safety, and the Page's displayName / nameSearch
//     mirror and nameChangedAt move in the same transaction.
//   * setMyProfileVisibility: leaving "public" while the Page is not paused
//     PAUSES it in the same transaction. Never a refusal: going private is a
//     safety action (D5).
//   * setCreatorAudienceEnabled: enabling it while pages/{uid} exists is
//     refused, because every Page follower's edge would become listable.
//     managePageV1 create switches an enabled Creator audience OFF in its
//     own transaction (ADR-234), so a Page never starts with one; this
//     refusal keeps it off.
//   * managePageV1 {op:"pause"} uses the same pause change.

const defaultLogger = require("firebase-functions/logger");

const { canonicalPage, derivePageListed, pageDisplayNameMirror, pageNameSearch,
  pageMalformedReason, PAGE_ERRORS, PAGE_STATUSES } = require("./contract");
const { pageNameViolation } = require("../profile/name_safety");
const {
  applyPageVisibilityInTransaction,
  pageVisibilityReference,
} = require("./visibility");

function pageReference(db, uid) {
  return db.doc(`pages/${uid}`);
}

/**
 * The Page a SAFETY action (an owner pause, going private) acts on. A
 * canonical Page is returned as is. A malformed one is logged and read in the
 * most hiding way possible instead of refusing: the safety action must still
 * pause it. Null when there is no Page.
 */
function pageForSafetyAction(snapshot, uid, logger = defaultLogger) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const reason = pageMalformedReason(data, uid);
  if (reason === null) return canonicalPage(snapshot, uid);
  logger.error("pages malformed page on a safety action", { reason });
  return Object.freeze({
    ...data,
    pageId: uid,
    status: PAGE_STATUSES.includes(data.status) ? data.status : "hidden",
    ownerPaused: data.ownerPaused === true,
    suspended: data.suspended === true,
    postCount: 0,
  });
}

/// The Page after an owner pause, or null when it is already paused.
function pausedPage(page, now) {
  if (!page || page.ownerPaused === true) return null;
  const next = { ...page, ownerPaused: true, updatedAt: now };
  next.listed = derivePageListed(next);
  return next;
}

/**
 * Pauses `page` inside `transaction`: pages/{uid} and pageVisibility/v1
 * together. `visibilitySnapshot` must have been read in the same transaction
 * before any write. Returns the paused Page, or null when nothing changed.
 */
function applyPagePauseInTransaction(transaction, {
  db,
  uid,
  page,
  visibilitySnapshot,
  now,
  logger = undefined,
}) {
  const next = pausedPage(page, now);
  if (next === null) return null;
  transaction.update(pageReference(db, uid), {
    ownerPaused: true,
    listed: next.listed,
    updatedAt: now,
  });
  applyPageVisibilityInTransaction(transaction, {
    db,
    snapshot: visibilitySnapshot,
    pageId: uid,
    page: next,
    now,
    safetyAction: true,
    ...(logger ? { logger } : {}),
  });
  return next;
}

/// Throws the Pages `pageNameReserved` refusal unless `name` is allowed.
function assertPageNameAllowed(name) {
  if (pageNameViolation(name) !== null) throw PAGE_ERRORS.nameReserved();
}

/**
 * The pages/{uid} update for a rename to `displayName` (the raw private
 * users.displayName). Refuses a reserved or look-alike name. The mirror is
 * the value publicProfiles will project for that name.
 */
function pageRenameUpdate(displayName, now) {
  const mirror = pageDisplayNameMirror(displayName);
  if (mirror === null) throw PAGE_ERRORS.nameReserved();
  assertPageNameAllowed(mirror);
  return {
    displayName: mirror,
    nameSearch: pageNameSearch(mirror),
    nameChangedAt: now,
    updatedAt: now,
  };
}

module.exports = {
  applyPagePauseInTransaction,
  pageForSafetyAction,
  assertPageNameAllowed,
  canonicalPage,
  pageReference,
  pageRenameUpdate,
  pageVisibilityReference,
  pausedPage,
};

// Who may SEE and who may FOLLOW a Premium Page (ADR-233 §2.3, §2.5). Pure:
// no SDK import beyond the error type; callers read the documents.
//
// canViewPage(V, P) (§2.5): V passes readAccess (the caller's activation
// check); users/{V} and users/{P} are active; pages/{P} is canonical; there is
// no block in either direction; P is not in pageVisibility.notViewable; its
// read-time status (stored status with the 30-day boundary) is active or
// readOnly; it is neither owner-paused nor suspended. Or V == P: the owner
// always sees their own Page, in every state. Every failure is the ONE
// uniform refusal `pageUnavailable`, so a caller cannot tell a block from a
// pause from a missing Page.
//
// pageAcceptsFollowers (§2.3, D14): readAccess allows the caller, the Page is
// canonical, not paused, not suspended, and its LIVE effective status is
// `active` (capability re-derived from the Page owner's own users /
// entitlements / vipGrants, so a grant that expired by time refuses follows
// before any sweep runs). A readOnly Page keeps its followers but takes no
// new ones.

const { HttpsError } = require("firebase-functions/v2/https");

const { likersAccountIsActive } = require("../utils/likers_access");
const { derivePagesCapabilityFromData } = require("./access");
const { pagesReadAllowed } = require("./activation");
const { effectivePageStatus, PAGE_READ_ONLY_WINDOW_MS, readTimePageStatus } =
  require("./lapse");

const PAGE_UNAVAILABLE_MESSAGE = "This Page is unavailable.";
const PAGE_UNAVAILABLE_REASON = "pageUnavailable";
// Per Page, per read: pages/{P}, users/{P}, users/{V}/blocked/{P},
// users/{P}/blocked/{V}, users/{V}/following/{P}.
const PAGE_CONTEXT_READS = 5;

function pageUnavailableError() {
  return new HttpsError("permission-denied", PAGE_UNAVAILABLE_MESSAGE, {
    reason: PAGE_UNAVAILABLE_REASON,
  });
}

function snapshotData(snapshot) {
  return snapshot?.exists ? (snapshot.data() ?? null) : null;
}

/// The five per-Page references, in PAGE_CONTEXT_READS order.
function pageContextReferences(db, viewerId, pageId) {
  return [
    db.doc(`pages/${pageId}`),
    db.doc(`users/${pageId}`),
    db.doc(`users/${viewerId}/blocked/${pageId}`),
    db.doc(`users/${pageId}/blocked/${viewerId}`),
    db.doc(`users/${viewerId}/following/${pageId}`),
  ];
}

/// A follow edge users/{V}/following/{P} as setFollow writes it.
function followingEdgeExists(snapshot, pageId) {
  return snapshot?.exists === true && snapshotData(snapshot)?.uid === pageId;
}

/// A visibility index entry that already hides `pageId` before any query:
/// notViewable, or readOnly for 30 days or more (lapseEnabled only).
function visibilityHides(visibility, pageId, nowMs, lapseEnabled) {
  if (!visibility) return false;
  if (visibility.notViewable.has(pageId)) return true;
  const since = visibility.readOnlySince.get(pageId);
  return lapseEnabled === true && Number.isSafeInteger(since) &&
    nowMs - since >= PAGE_READ_ONLY_WINDOW_MS;
}

/**
 * The view decision for V looking at P. `page` is the canonical Page or null
 * (missing or malformed: callers use canonicalPageOrNull). Returns
 * {viewable, isOwner, status} where status is the read-time status.
 */
function pageViewDecision({
  viewerId,
  pageId,
  page,
  pageUser,
  viewerUser,
  viewerBlocksPage = false,
  pageBlocksViewer = false,
  visibility = null,
  nowMs,
  lapseEnabled,
}) {
  const refused = { viewable: false, isOwner: false, status: null };
  if (!page || page.pageId !== pageId) return refused;
  if (!likersAccountIsActive(viewerUser)) return refused;
  const status = readTimePageStatus(page, nowMs, lapseEnabled);
  if (viewerId === pageId) return { viewable: true, isOwner: true, status };
  if (!likersAccountIsActive(pageUser)) return refused;
  if (viewerBlocksPage || pageBlocksViewer) return refused;
  if (visibilityHides(visibility, pageId, nowMs, lapseEnabled)) return refused;
  if (page.ownerPaused === true || page.suspended === true) return refused;
  if (status !== "active" && status !== "readOnly") return refused;
  return { viewable: true, isOwner: false, status };
}

/// The live capability of the Page's OWNER (for follows and the header).
function livePageCapability({ pageUser, pageEntitlement, pageGrant, nowMs }) {
  return derivePagesCapabilityFromData({
    user: pageUser,
    entitlement: pageEntitlement,
    grant: pageGrant,
    tokenRole: null,
    now: nowMs,
  });
}

/// The live effective status of `page` (capability re-derived).
function livePageStatus({ page, pageUser, pageEntitlement, pageGrant, nowMs, lapseEnabled }) {
  const capability = livePageCapability({ pageUser, pageEntitlement, pageGrant, nowMs });
  return effectivePageStatus(page, capability.allowed, nowMs, lapseEnabled);
}

/// Whether `callerId` may start following `page` right now (§2.3 pageOk).
function pageAcceptsFollowers({
  callerId,
  activation,
  page,
  pageUser,
  pageEntitlement,
  pageGrant,
  nowMs,
}) {
  if (!page || !pagesReadAllowed(activation, callerId)) return false;
  if (page.ownerPaused === true || page.suspended === true) return false;
  return livePageStatus({
    page,
    pageUser,
    pageEntitlement,
    pageGrant,
    nowMs,
    lapseEnabled: activation.lapseEnabled,
  }) === "active";
}

module.exports = {
  PAGE_CONTEXT_READS,
  PAGE_UNAVAILABLE_MESSAGE,
  PAGE_UNAVAILABLE_REASON,
  followingEdgeExists,
  livePageCapability,
  livePageStatus,
  pageAcceptsFollowers,
  pageContextReferences,
  pageUnavailableError,
  pageViewDecision,
  visibilityHides,
};

// pageFollowIndex/{uid} and the Page branch of setFollow (ADR-233 §1.6,
// §2.3). Pure: no SDK import.
//
// The follow EDGES are the existing users/{a}/following/{p} and
// users/{p}/followers/{a}, written only by setFollow; their shape does not
// change. pageFollowIndex/{uid} is a server-only HINT of the Pages the viewer
// follows, in follow order:
//
//   { schemaVersion: 1, pageIds: [<= 1000 uids, oldest first], updatedAt }
//
// The feed verifies users/{V}/following/{P} for every Page it returns and
// prunes stale ids, so the index may lag a block (setUserBlock is unchanged)
// or an account deletion without ever showing anything it should not. Every
// transactional writer reads the index in its transaction and writes the full
// canonical document (a malformed one is repaired, never trusted); the feed's
// best-effort prune is a plain arrayRemove update.
//
// Follow churn: `pages.followToggle` allows 3 follows of the same Page per
// caller per 24 h, keyed by (caller, Page). It is charged on FOLLOW only (the
// direction that notifies the owner): an unfollow is a safety action and is
// never refused.

const { digest, timestampMillis } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");

const PAGE_FOLLOW_INDEX_KEYS = Object.freeze(["pageIds", "schemaVersion", "updatedAt"]);
const PAGE_FOLLOW_INDEX_MAX = 1000;
const PAGES_FOLLOW_TOGGLE_SCOPE = "pages.followToggle";
const PAGES_FOLLOW_TOGGLE_LIMIT = Object.freeze({
  maxEvents: 3,
  windowMs: 24 * 60 * 60 * 1000,
});

function pageFollowIndexReference(db, uid) {
  return db.doc(`pageFollowIndex/${uid}`);
}

/// The per-(caller, Page) privateRateLimits row of pages.followToggle.
function pageFollowToggleReference(db, callerId, pageId) {
  return db.doc(`privateRateLimits/${digest("rate", PAGES_FOLLOW_TOGGLE_SCOPE, callerId, pageId)}`);
}

/**
 * The canonical index in `snapshot` for `uid`: {exists, malformed, pageIds}.
 * A malformed document yields its valid, de-duplicated uids (the most recent
 * occurrence wins) so a repair keeps every usable hint; it never throws.
 */
function canonicalPageFollowIndex(snapshot, uid) {
  if (!snapshot?.exists) {
    return Object.freeze({ exists: false, malformed: false, pageIds: Object.freeze([]) });
  }
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const rawIds = Array.isArray(data.pageIds) ? data.pageIds : [];
  const seen = new Set();
  const ids = [];
  for (let index = rawIds.length - 1; index >= 0; index -= 1) {
    const id = rawIds[index];
    if (!isValidOpaqueUid(id) || id === uid || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  ids.reverse();
  const exact = keys.length === PAGE_FOLLOW_INDEX_KEYS.length &&
    keys.every((key, index) => key === PAGE_FOLLOW_INDEX_KEYS[index]) &&
    data.schemaVersion === 1 &&
    Array.isArray(data.pageIds) &&
    data.pageIds.length <= PAGE_FOLLOW_INDEX_MAX &&
    ids.length === data.pageIds.length &&
    timestampMillis(data.updatedAt) !== null;
  const bounded = ids.length > PAGE_FOLLOW_INDEX_MAX
    ? ids.slice(ids.length - PAGE_FOLLOW_INDEX_MAX)
    : ids;
  return Object.freeze({ exists: true, malformed: !exact, pageIds: Object.freeze(bounded) });
}

/// The ids after following `pageId`: moved to the newest end; the oldest
/// hints drop past the cap (the feed reads only the newest 300 anyway).
function pageIdsAfterFollow(pageIds, pageId) {
  const next = pageIds.filter((id) => id !== pageId);
  next.push(pageId);
  return next.length > PAGE_FOLLOW_INDEX_MAX
    ? next.slice(next.length - PAGE_FOLLOW_INDEX_MAX)
    : next;
}

function pageIdsAfterUnfollow(pageIds, pageId) {
  return pageIds.filter((id) => id !== pageId);
}

function pageFollowIndexDocument(pageIds, updatedAt) {
  return { schemaVersion: 1, pageIds: [...pageIds], updatedAt };
}

module.exports = {
  PAGES_FOLLOW_TOGGLE_LIMIT,
  PAGES_FOLLOW_TOGGLE_SCOPE,
  PAGE_FOLLOW_INDEX_KEYS,
  PAGE_FOLLOW_INDEX_MAX,
  canonicalPageFollowIndex,
  pageFollowIndexDocument,
  pageFollowIndexReference,
  pageFollowToggleReference,
  pageIdsAfterFollow,
  pageIdsAfterUnfollow,
};

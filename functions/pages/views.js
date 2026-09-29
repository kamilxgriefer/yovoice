// The Premium Pages READ wire contract (ADR-233 §2.5, §2.7). Pure: no SDK
// import beyond the error type. This is "the feed contract" the Flutter lane
// (C2) codes against from day one; server tests pin every key set below.
//
// Parsing rule (spec §2.5): the server's output is EXACT (these key sets and
// nothing else); clients require every known key and IGNORE unknown keys, and
// skip an item whose enum value they do not know. A v1.1 key therefore never
// breaks a v1 client.
//
//   PostView      {postId, pageId, pageName, pageKind, kind, text,
//                  media:[MediaView], createdAtMs, likeCount, commentCount,
//                  callerLiked, commentsEnabled, state, pinned}
//   MediaView     {mediaId, type, contentType, width|null, height|null,
//                  durationMs|null}          (bytes: getPagePostMediaAccessV1)
//   PageCard      {pageId, displayName, kind, category, followerCount,
//                  onYoVoiceSinceMs, viewerFollows, lastPostAtMs|null}
//   PageHeader    {pageId, displayName, kind, category, description,
//                  followerCount, postCount, onYoVoiceSinceMs, about, state}
//   about         {business: {website,email,phone,address,hours,legalNotice}|null,
//                  community: {rules, linkedServer:{serverId,name,serverType}|null}|null}
//   viewer        {isOwner, following, canFollow, canMessage}
//   CommentView   {commentId, authorId, authorName, text, createdAtMs, isOwnPage}
//
// `onYoVoiceSinceMs` is the Page's server-written creation time
// (pages.createdAt), never the client-written users.createdAt.
// `followerCount` is read from users/{P} at read time: the account's own
// counter, SHARED with its Page, because a Page shares its follow edges with
// the account (existing followers are carried over at creation,
// follow_carry.js, ADR-234; Creator audience is switched off at creation and
// cannot be re-enabled while pages/{P} exists). It is exact only as far as
// that counter is: pre-existing drift is not repaired (ADR-234), and
// followers the carry-over skips (a blocked legacy pair, a gone account, a
// mismatched mirror) are still counted.
// A PostView's `state` is "held" only for the owner; readers see "published".
// A PageHeader's `state` is "active" | "readOnly" for visitors and one of
// "suspended" > "hidden" > "paused" > "readOnly" > "active" (first match) for
// the owner.
//
// Cursors are base64url JSON, validated before any read:
//   posts     {v:1, t:<createdAtMs>, id:"pp_…"}          feed, wall, photos
//   comments  {v:1, t:<createdAtMs>, id:"pc_…"}          post detail
//   find      {v:1, m:"suggest", t:<lastPostAtMs>, id:<pageId>}
//             {v:1, m:"search",  s:<nameSearch>,   id:<pageId>}
//             {v:1, m:"following", n:<ids consumed>, id:<pageId>}

const { fail, timestampMillis } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const {
  PAGE_COMMENT_ID_PATTERN,
  PAGE_LIMITS,
  PAGE_POST_ID_PATTERN,
} = require("./contract");
const { pageCount } = require("./post_contract");

const PAGE_POST_VIEW_KEYS = Object.freeze([
  "callerLiked",
  "commentCount",
  "commentsEnabled",
  "createdAtMs",
  "kind",
  "likeCount",
  "media",
  "pageId",
  "pageKind",
  "pageName",
  "pinned",
  "postId",
  "state",
  "text",
]);
const PAGE_MEDIA_VIEW_KEYS = Object.freeze([
  "contentType",
  "durationMs",
  "height",
  "mediaId",
  "type",
  "width",
]);
const PAGE_CARD_KEYS = Object.freeze([
  "category",
  "displayName",
  "followerCount",
  "kind",
  "lastPostAtMs",
  "onYoVoiceSinceMs",
  "pageId",
  "viewerFollows",
]);
const PAGE_HEADER_KEYS = Object.freeze([
  "about",
  "category",
  "description",
  "displayName",
  "followerCount",
  "kind",
  "onYoVoiceSinceMs",
  "pageId",
  "postCount",
  "state",
]);
const PAGE_ABOUT_KEYS = Object.freeze(["business", "community"]);
const PAGE_ABOUT_COMMUNITY_KEYS = Object.freeze(["linkedServer", "rules"]);
const PAGE_LINKED_SERVER_KEYS = Object.freeze(["name", "serverId", "serverType"]);
const PAGE_VIEWER_KEYS = Object.freeze(["canFollow", "canMessage", "following", "isOwner"]);
const PAGE_COMMENT_VIEW_KEYS = Object.freeze([
  "authorId",
  "authorName",
  "commentId",
  "createdAtMs",
  "isOwnPage",
  "text",
]);
const PAGES_FEED_RESPONSE_KEYS = Object.freeze([
  "hasMore",
  "nextCursor",
  "posts",
  "schemaVersion",
  "suggestions",
]);
const PAGE_RESPONSE_KEYS = Object.freeze([
  "hasMore",
  "nextCursor",
  "page",
  "pinned",
  "posts",
  "schemaVersion",
  "viewer",
]);
const PAGE_POST_RESPONSE_KEYS = Object.freeze([
  "comments",
  "hasMoreComments",
  "nextCommentCursor",
  "post",
  "schemaVersion",
]);
const FIND_PAGES_RESPONSE_KEYS = Object.freeze([
  "hasMore",
  "nextCursor",
  "pages",
  "schemaVersion",
]);
const PAGE_HEADER_STATES = Object.freeze([
  "active",
  "readOnly",
  "hidden",
  "paused",
  "suspended",
]);
const PAGE_POST_VIEW_STATES = Object.freeze(["published", "held"]);
const FIND_PAGES_MODES = Object.freeze(["suggest", "search", "following"]);

const CURSOR_MAX_LENGTH = 512;
const CURSOR_PATTERN = /^[A-Za-z0-9_-]+$/u;
const CURSOR_INVALID_MESSAGE = "cursor is invalid.";

// ------------------------------------------------------------- projections

function mediaView(entry) {
  const image = entry.type === "image";
  return {
    mediaId: entry.mediaId,
    type: entry.type,
    contentType: entry.contentType,
    width: image ? entry.width : null,
    height: image ? entry.height : null,
    durationMs: image ? null : entry.durationMs,
  };
}

/**
 * One PostView from a canonical post and its canonical Page. `state` is the
 * post's stored status; the caller has already decided the viewer may see
 * it ("held" only reaches the owner).
 */
function postView(post, page, { callerLiked = false } = {}) {
  if (!PAGE_POST_VIEW_STATES.includes(post.status)) {
    throw new TypeError("Only published or held posts have a PostView.");
  }
  return {
    postId: post.postId,
    pageId: post.pageId,
    pageName: page.displayName,
    pageKind: page.kind,
    kind: post.kind,
    text: post.text,
    media: post.media.map(mediaView),
    createdAtMs: timestampMillis(post.createdAt),
    likeCount: pageCount(post.likeCount),
    commentCount: pageCount(post.commentCount),
    callerLiked: callerLiked === true,
    commentsEnabled: post.commentsEnabled,
    state: post.status,
    pinned: page.pinnedPostId === post.postId,
  };
}

function millisOrNull(value) {
  return timestampMillis(value);
}

function pageCard(page, pageUser, { viewerFollows = false } = {}) {
  return {
    pageId: page.pageId,
    displayName: page.displayName,
    kind: page.kind,
    category: page.category,
    followerCount: pageCount(pageUser?.followerCount),
    onYoVoiceSinceMs: millisOrNull(page.createdAt),
    viewerFollows: viewerFollows === true,
    lastPostAtMs: millisOrNull(page.lastPostAt),
  };
}

/**
 * The owner-facing or visitor-facing state of a Page. `effectiveStatus` is
 * the lapse state machine's value (lapse.js). Visitors only ever reach a Page
 * whose state is active or readOnly (audience.js), so the precedence only
 * matters to the owner.
 */
function pageHeaderState(page, effectiveStatus) {
  if (page.suspended === true) return "suspended";
  if (effectiveStatus === "hidden") return "hidden";
  if (page.ownerPaused === true) return "paused";
  if (effectiveStatus === "readOnly") return "readOnly";
  return "active";
}

function linkedServerView(serverId, server) {
  if (!server) return null;
  return {
    serverId,
    name: typeof server.name === "string" && server.name.trim().length > 0
      ? server.name.trim().slice(0, 120)
      : null,
    serverType: server.serverType,
  };
}

/**
 * `linkedServer` is the CURRENT server (already checked active and public by
 * the caller) or null; a Page's stored link is never shown on its own.
 */
function pageHeader(page, pageUser, { effectiveStatus, linkedServer = null }) {
  return {
    pageId: page.pageId,
    displayName: page.displayName,
    kind: page.kind,
    category: page.category,
    description: page.description,
    followerCount: pageCount(pageUser?.followerCount),
    postCount: pageCount(page.postCount),
    onYoVoiceSinceMs: millisOrNull(page.createdAt),
    about: {
      business: page.kind === "business" && page.business
        ? {
            website: page.business.website,
            email: page.business.email,
            phone: page.business.phone,
            address: page.business.address,
            hours: page.business.hours,
            legalNotice: page.business.legalNotice,
          }
        : null,
      community: page.kind === "community" && page.community
        ? {
            rules: page.community.rules,
            linkedServer: page.community.linkedServerId === null
              ? null
              : linkedServerView(page.community.linkedServerId, linkedServer),
          }
        : null,
    },
    state: pageHeaderState(page, effectiveStatus),
  };
}

function viewerView({ isOwner, following, canFollow, canMessage }) {
  return {
    isOwner: isOwner === true,
    following: following === true,
    canFollow: canFollow === true,
    canMessage: canMessage === true,
  };
}

function commentView(comment, { authorName, pageId }) {
  return {
    commentId: comment.commentId,
    authorId: comment.authorId,
    authorName,
    text: comment.text,
    createdAtMs: timestampMillis(comment.createdAt),
    isOwnPage: comment.authorId === pageId,
  };
}

// ------------------------------------------------------------------ cursors

function cursorInvalid() {
  fail("invalid-argument", CURSOR_INVALID_MESSAGE);
}

function encodeCursor(payload) {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

function decodeCursorObject(value) {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > CURSOR_MAX_LENGTH || !CURSOR_PATTERN.test(value)) {
    cursorInvalid();
  }
  let parsed;
  try {
    const text = Buffer.from(value, "base64url").toString("utf8");
    // A non-canonical encoding (padding bits, trailing garbage) is refused:
    // one cursor has exactly one spelling.
    if (Buffer.from(text, "utf8").toString("base64url") !== value) cursorInvalid();
    parsed = JSON.parse(text);
  } catch (error) {
    if (error?.code === "invalid-argument") throw error;
    cursorInvalid();
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || parsed.v !== 1) {
    cursorInvalid();
  }
  return parsed;
}

function exactCursorKeys(parsed, keys) {
  const actual = Object.keys(parsed).sort();
  if (actual.length !== keys.length || actual.some((key, index) => key !== keys[index])) {
    cursorInvalid();
  }
}

function validMillis(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

/// A post or comment position {t, id}. `kind` is "post" or "comment".
function encodeItemCursor(position) {
  return encodeCursor({ v: 1, t: position.t, id: position.id });
}

/// null for null/undefined (first page); else the validated position. The
/// id MUST match the item pattern and t MUST be a safe integer, or the
/// request fails with invalid-argument before any read (§2.5).
function decodeItemCursor(value, kind) {
  if (value === null || value === undefined) return null;
  const parsed = decodeCursorObject(value);
  exactCursorKeys(parsed, ["id", "t", "v"]);
  const pattern = kind === "comment" ? PAGE_COMMENT_ID_PATTERN : PAGE_POST_ID_PATTERN;
  if (!validMillis(parsed.t) || typeof parsed.id !== "string" || !pattern.test(parsed.id)) {
    cursorInvalid();
  }
  return Object.freeze({ t: parsed.t, id: parsed.id });
}

function storableItemPosition(position, kind) {
  const pattern = kind === "comment" ? PAGE_COMMENT_ID_PATTERN : PAGE_POST_ID_PATTERN;
  return Boolean(position) && validMillis(position.t) &&
    typeof position.id === "string" && pattern.test(position.id);
}

function encodeFindCursor(mode, position) {
  if (mode === "suggest") return encodeCursor({ v: 1, m: mode, t: position.t, id: position.id });
  if (mode === "search") return encodeCursor({ v: 1, m: mode, s: position.s, id: position.id });
  return encodeCursor({ v: 1, m: mode, n: position.n, id: position.id });
}

function storableFindPosition(mode, position) {
  if (!position || !isValidOpaqueUid(position.id)) return false;
  if (mode === "suggest") return validMillis(position.t);
  if (mode === "search") {
    return typeof position.s === "string" && position.s.length <= PAGE_LIMITS.nameSearch;
  }
  return Number.isSafeInteger(position.n) && position.n >= 1;
}

/// null for the first page; else the validated position for `mode`. A
/// cursor of another mode is invalid.
function decodeFindCursor(value, mode) {
  if (value === null || value === undefined) return null;
  const parsed = decodeCursorObject(value);
  if (parsed.m !== mode) cursorInvalid();
  const key = mode === "suggest" ? "t" : mode === "search" ? "s" : "n";
  exactCursorKeys(parsed, ["id", key, "m", "v"].sort());
  const position = { id: parsed.id, [key]: parsed[key] };
  if (!storableFindPosition(mode, position)) cursorInvalid();
  return Object.freeze(position);
}

// ------------------------------------------------------------- responses

function feedResponse({ posts, nextCursor, suggestions }) {
  return {
    schemaVersion: 1,
    posts,
    nextCursor,
    hasMore: nextCursor !== null,
    suggestions,
  };
}

function pageResponse({ page, viewer, pinned, posts, nextCursor }) {
  return {
    schemaVersion: 1,
    page,
    viewer,
    pinned,
    posts,
    nextCursor,
    hasMore: nextCursor !== null,
  };
}

function postResponse({ post, comments, nextCommentCursor }) {
  return {
    schemaVersion: 1,
    post,
    comments,
    nextCommentCursor,
    hasMoreComments: nextCommentCursor !== null,
  };
}

function findResponse({ pages, nextCursor }) {
  return {
    schemaVersion: 1,
    pages,
    nextCursor,
    hasMore: nextCursor !== null,
  };
}

module.exports = {
  CURSOR_INVALID_MESSAGE,
  FIND_PAGES_MODES,
  FIND_PAGES_RESPONSE_KEYS,
  PAGES_FEED_RESPONSE_KEYS,
  PAGE_ABOUT_COMMUNITY_KEYS,
  PAGE_ABOUT_KEYS,
  PAGE_CARD_KEYS,
  PAGE_COMMENT_VIEW_KEYS,
  PAGE_HEADER_KEYS,
  PAGE_HEADER_STATES,
  PAGE_LINKED_SERVER_KEYS,
  PAGE_MEDIA_VIEW_KEYS,
  PAGE_POST_RESPONSE_KEYS,
  PAGE_POST_VIEW_KEYS,
  PAGE_POST_VIEW_STATES,
  PAGE_RESPONSE_KEYS,
  PAGE_VIEWER_KEYS,
  commentView,
  decodeFindCursor,
  decodeItemCursor,
  encodeFindCursor,
  encodeItemCursor,
  feedResponse,
  findResponse,
  pageCard,
  pageHeader,
  pageHeaderState,
  pageResponse,
  postResponse,
  postView,
  storableFindPosition,
  storableItemPosition,
  viewerView,
};

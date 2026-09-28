// The Page post engagement contract (ADR-233 §1.4, §1.5, §2.6, package B4).
// Pure: no SDK import beyond the error type.
//
//   likes     pagePosts/{postId}/likes/{uid}
//             {schemaVersion:1, userId, postId, createdAt}      (the Reels shape)
//   comments  pagePostComments/{commentId}
//             {schemaVersion:1, commentId, postId, pageId, authorId, text,
//              createdAt}                         (post_contract.js, exact)
//   bell row  users/{pageId}/notifications/pagePostComment_{commentId}
//             type "pagePostComment", targetId postId, targetSubId commentId,
//             sourcePath "pagePostComments/{commentId}", and a human-readable
//             English targetLabel ("Ada commented on your Page post"), so the
//             installed builds that render an unknown type as `system` show a
//             sensible sentence.
//
// The comment link filter (§2.6) refuses `http(s)://`, `www.` and
// domain-shaped tokens ending in one of the listed top-level domains. It runs
// on the NFKC fold of the text (full-width letters and dots fold to ASCII);
// the stored text stays NFC. The spaced form ("example . com", "example .com")
// needs whitespace BEFORE the dot: a dot followed by a space is how every
// sentence ends, and the unrestricted spec pattern refused ordinary Polish
// ("itp. Co dalej?") and English ("Loved it. Me too"). "example. com" is the
// accepted residual bypass (ADR-233).

const { HttpsError } = require("firebase-functions/v2/https");

const {
  digest,
  fail,
  isValidOpaqueUid,
  requireRequestId,
  timestampMillis,
} = require("../integrity/guards");
const { PAGE_COMMENT_ID_PATTERN, PAGE_POST_ID_PATTERN } = require("./contract");
const { PAGE_INVISIBLE_TEXT, PAGE_UNSAFE_TEXT } = require("./media_contract");
const { PAGE_COMMENT_TEXT_MAX } = require("./post_contract");

const PAGE_LIKE_KEYS = Object.freeze(["createdAt", "postId", "schemaVersion", "userId"]);
const PAGE_ENGAGEMENT_OPS = Object.freeze(["like", "unlike", "comment", "deleteComment"]);
const PAGE_ENGAGEMENT_INPUT = Object.freeze({
  like: Object.freeze(["requestId", "op", "postId"]),
  unlike: Object.freeze(["requestId", "op", "postId"]),
  comment: Object.freeze(["requestId", "op", "postId", "text"]),
  deleteComment: Object.freeze(["requestId", "op", "commentId"]),
});
// The exact response of each op (pinned by pages_engagement.test.js).
const PAGE_LIKE_RESPONSE_KEYS = Object.freeze([
  "changed",
  "likeCount",
  "liked",
  "op",
  "postId",
  "schemaVersion",
]);
const PAGE_COMMENT_RESPONSE_KEYS = Object.freeze([
  "comment",
  "commentCount",
  "op",
  "postId",
  "schemaVersion",
]);
const PAGE_DELETE_COMMENT_RESPONSE_KEYS = Object.freeze([
  "commentId",
  "deleted",
  "op",
  "postId",
  "schemaVersion",
]);

const PAGE_COMMENT_NOTIFICATION_TYPE = "pagePostComment";
// An Auth account younger than this gets the new-account comment limit.
const PAGE_NEW_ACCOUNT_MS = 7 * 24 * 60 * 60 * 1000;

const PAGE_COMMENT_LINK_TLDS = Object.freeze([
  "com", "pl", "net", "org", "io", "ly", "me", "co", "app", "xyz", "info",
  "eu", "de", "uk", "gg", "tv", "link", "site", "online", "shop",
]);
const TLD = `(?:${PAGE_COMMENT_LINK_TLDS.join("|")})`;
const PAGE_COMMENT_LINK_PATTERNS = Object.freeze([
  /https?:\/\//iu,
  /www\./iu,
  // Tight: "bit.ly/x", "example.com", "example。com".
  new RegExp(`[\\p{L}\\p{N}-]{2,}[.。]${TLD}\\b`, "iu"),
  // Spaced: whitespace before the dot ("example . com", "example .com").
  new RegExp(`[\\p{L}\\p{N}-]{2,}\\s+[.。]\\s*${TLD}\\b`, "iu"),
]);

function pagesEngagementError(code, message, reason) {
  return new HttpsError(code, message, { reason });
}

const PAGE_ENGAGEMENT_ERRORS = Object.freeze({
  commentLinks: () => pagesEngagementError("invalid-argument",
    "Links can't be posted in comments.", "commentLinks"),
  commentsOff: () => pagesEngagementError("failed-precondition",
    "Comments are turned off for this post.", "pageCommentsOff"),
  readOnly: () => pagesEngagementError("failed-precondition",
    "This Page isn't publishing right now.", "pageReadOnly"),
});

/// True when `text` carries a link the comment filter refuses.
function commentHasLink(text) {
  if (typeof text !== "string") return false;
  const folded = text.normalize("NFKC");
  return PAGE_COMMENT_LINK_PATTERNS.some((pattern) => pattern.test(folded));
}

/// Normalised comment text (NFC, LF line breaks, trimmed, 1-1000 UTF-16
/// units, at least one visible character, no links). Control and format
/// characters are refused exactly as in post text.
function normalizeCommentText(value) {
  if (typeof value !== "string") fail("invalid-argument", "text must be a string.");
  if (!value.isWellFormed()) fail("invalid-argument", "text contains unsupported characters.");
  const text = value.normalize("NFC").replace(/\r\n?/gu, "\n").trim();
  if (PAGE_UNSAFE_TEXT.test(text)) {
    fail("invalid-argument", "text contains unsupported characters.");
  }
  if (text.replace(PAGE_INVISIBLE_TEXT, "").length === 0) {
    fail("invalid-argument", "A comment needs some text.");
  }
  if (text.length > PAGE_COMMENT_TEXT_MAX) {
    fail("invalid-argument", `text must be at most ${PAGE_COMMENT_TEXT_MAX} characters.`);
  }
  if (commentHasLink(text)) throw PAGE_ENGAGEMENT_ERRORS.commentLinks();
  return text;
}

/// The exact input of one pagePostEngagementV1 call. The op is checked
/// first, then the exact keys of that op, then each value.
function requireEngagementInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    fail("invalid-argument", "data must be an object.");
  }
  if (typeof data.op !== "string" || !PAGE_ENGAGEMENT_OPS.includes(data.op)) {
    fail("invalid-argument", "op is invalid.");
  }
  const fields = PAGE_ENGAGEMENT_INPUT[data.op];
  const unknown = Object.keys(data).filter((key) => !fields.includes(key));
  if (unknown.length > 0) fail("invalid-argument", `Unsupported field: ${unknown[0]}.`);
  for (const field of fields) {
    if (!Object.prototype.hasOwnProperty.call(data, field)) {
      fail("invalid-argument", `${field} is required.`);
    }
  }
  const requestId = requireRequestId(data.requestId);
  if (data.op === "deleteComment") {
    if (typeof data.commentId !== "string" || !PAGE_COMMENT_ID_PATTERN.test(data.commentId)) {
      fail("invalid-argument", "commentId is invalid.");
    }
    return { requestId, op: data.op, commentId: data.commentId, postId: null, text: null };
  }
  if (typeof data.postId !== "string" || !PAGE_POST_ID_PATTERN.test(data.postId)) {
    fail("invalid-argument", "postId is invalid.");
  }
  return {
    requestId,
    op: data.op,
    postId: data.postId,
    commentId: null,
    text: data.op === "comment" ? normalizeCommentText(data.text) : null,
  };
}

/// The server-allocated comment id of one (caller, requestId).
function pageCommentIdFor(uid, requestId) {
  return `pc_${digest("pages.comment.id.v1", uid, requestId).slice(0, 40)}`;
}

/// Whether `snapshot` is the exact like edge of `userId` on `postId`. A
/// missing edge is false; so is a malformed one (callers treat it as absent
/// for the list and as corruption for the counter).
function validPageLike(snapshot, postId, userId = snapshot?.id) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data();
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const keys = Object.keys(data).sort();
  return keys.length === PAGE_LIKE_KEYS.length &&
    keys.every((key, index) => key === PAGE_LIKE_KEYS[index]) &&
    data.schemaVersion === 1 &&
    isValidOpaqueUid(userId) &&
    data.userId === userId &&
    data.postId === postId &&
    timestampMillis(data.createdAt) !== null;
}

function pageLikeDocument({ userId, postId, now }) {
  return { schemaVersion: 1, userId, postId, createdAt: now };
}

function pageCommentNotificationId(commentId) {
  return `${PAGE_COMMENT_NOTIFICATION_TYPE}_${commentId}`;
}

function pageCommentSourcePath(commentId) {
  return `pagePostComments/${commentId}`;
}

/// Parses `pagePostComments/{pc_…}`; null for anything else.
function parsePageCommentSourcePath(path) {
  if (typeof path !== "string") return null;
  const parts = path.split("/");
  if (parts.length !== 2 || parts[0] !== "pagePostComments" ||
      !PAGE_COMMENT_ID_PATTERN.test(parts[1])) {
    return null;
  }
  return { commentId: parts[1] };
}

const PAGE_COMMENT_LABEL_NAME_MAX = 40;

/// The English sentence old clients show as the row's title (§2.6). Builds
/// 36-39 render an unknown type as a `system` row with this label VERBATIM,
/// so the server-authored attribution comes FIRST and the commenter's free
/// display name is capped at 40 characters after it (audit 2026-09-28): a
/// name written to read as a YO Voice notice can neither push the
/// attribution past the 120-character label cut nor stand on its own.
function pageCommentTargetLabel(actorName) {
  const trimmed = typeof actorName === "string" ? actorName.trim() : "";
  const characters = Array.from(trimmed);
  const name = characters.length === 0
    ? "someone"
    : characters.length > PAGE_COMMENT_LABEL_NAME_MAX
      ? `${characters.slice(0, PAGE_COMMENT_LABEL_NAME_MAX - 1).join("").trimEnd()}…`
      : trimmed;
  return `New comment on your Page post from ${name}`;
}

function likeResponse({ op, postId, liked, changed, likeCount }) {
  return { schemaVersion: 1, op, postId, liked, changed, likeCount };
}

function commentResponse({ postId, comment, commentCount }) {
  return { schemaVersion: 1, op: "comment", postId, comment, commentCount };
}

function deleteCommentResponse({ postId, commentId }) {
  return { schemaVersion: 1, op: "deleteComment", postId, commentId, deleted: true };
}

module.exports = {
  PAGE_COMMENT_LINK_PATTERNS,
  PAGE_COMMENT_LABEL_NAME_MAX,
  PAGE_COMMENT_LINK_TLDS,
  PAGE_COMMENT_NOTIFICATION_TYPE,
  PAGE_COMMENT_RESPONSE_KEYS,
  PAGE_DELETE_COMMENT_RESPONSE_KEYS,
  PAGE_ENGAGEMENT_ERRORS,
  PAGE_ENGAGEMENT_INPUT,
  PAGE_ENGAGEMENT_OPS,
  PAGE_LIKE_KEYS,
  PAGE_LIKE_RESPONSE_KEYS,
  PAGE_NEW_ACCOUNT_MS,
  commentHasLink,
  commentResponse,
  deleteCommentResponse,
  likeResponse,
  normalizeCommentText,
  pageCommentIdFor,
  pageCommentNotificationId,
  pageCommentSourcePath,
  pageCommentTargetLabel,
  pageLikeDocument,
  parsePageCommentSourcePath,
  requireEngagementInput,
  validPageLike,
};

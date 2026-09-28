// The Premium Pages REPORT, MODERATION and NOTICE contract (ADR-233 §2.8,
// §2.10). Pure: no SDK import beyond the error type.
//
//   createPageReportV1 {requestId, targetType, pageId, postId|null,
//                       commentId|null, reason, note|null}
//     targetType  page            postId null,  commentId null
//                 pagePost        postId,       commentId null
//                 pagePostComment postId,       commentId (comment.postId == postId)
//
//   reports/{reportId}   reportId = sha256("page-report", reporter,
//                        targetType, targetId)[0..40]: one report per
//                        reporter per target. It carries NO uid prefix, so
//                        the account-deletion re-key (account/retention.js)
//                        anonymises reporterId in place and keeps the id that
//                        pagePostOpenReports.lastReportId and heldBy name.
//     {schemaVersion:2, reporterId, targetType, targetId, reportedUserId,
//      contextPath, pageId, postId, commentId, pageKind, pageDisplayName,
//      targetPostKind, targetTextSnapshot, targetMedia:[{mediaId, type}],
//      recentPosts:[{postId, kind, status, text, media:[{mediaId, type}]}],
//      note, reason, status:"open", createdAt, updatedAt}
//
//     recentPosts is filled for a `page` report only (empty otherwise): the
//     Page's newest published or held posts (at most 5, text capped at 500)
//     at report time, so the owner hard-deleting every post after a Page
//     report does not leave staff with the description alone (audit
//     2026-09-28).
//
//     The SNAPSHOT is the moderator's only view of the content: every Pages
//     collection is `allow read, write: if false` for every client,
//     staff included (the reel-comment precedent, moderation/reports.js).
//     Post text is capped at 2000 characters, comment text at 1000, the Page
//     description at 300; media is named by id and type only (staff open the
//     bytes through the audited getPagePostMediaAccessV1 staff branch).
//
//   Notices (users/{uid}/notifications/{id}), system rows in the achievement
//   shape (actorId "yovoice-system", actorName "YO Voice"), each with a
//   HUMAN-READABLE English targetLabel: builds 36-38 show an unknown type as
//   `system` with that label, so a raw reason key must never reach it.
//     pageModeration  the statement of reasons (DSA Art. 17) for a staff
//                     action on a Page, a post or a comment
//     pageLapse       Day 0 (read-only) and Day 23 (hidden in 7 days)

const { digest, fail, timestampMillis } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const {
  PAGE_COMMENT_ID_PATTERN,
  PAGE_POST_ID_PATTERN,
  pagesError,
} = require("./contract");

const PAGE_REPORT_TARGET_TYPES = Object.freeze(["page", "pagePost", "pagePostComment"]);
const PAGE_REPORT_INPUT_KEYS = Object.freeze([
  "commentId",
  "note",
  "pageId",
  "postId",
  "reason",
  "requestId",
  "targetType",
]);
// The report reasons of every other surface (the rules' closed list), plus
// three a business Page needs: a restricted category (catalog.js lists what
// is excluded), a scam and an intellectual-property claim.
const PAGE_REPORT_REASONS = Object.freeze([
  "spam",
  "harassment",
  "hate",
  "sexual",
  "violence",
  "selfHarm",
  "impersonation",
  "restrictedCategory",
  "scam",
  "intellectualProperty",
  "other",
]);
// The statement-of-reasons wording (English; old builds show it verbatim).
const PAGE_REASON_LABELS = Object.freeze({
  spam: "spam",
  harassment: "harassment",
  hate: "hate speech",
  sexual: "sexual content",
  violence: "violence",
  selfHarm: "self-harm",
  impersonation: "impersonation",
  restrictedCategory: "restricted category",
  scam: "scam or fraud",
  intellectualProperty: "intellectual property",
  other: "breaking the rules",
});
const PAGE_REPORT_NOTE_MAX = 300;
const PAGE_REPORT_SNAPSHOT_LIMITS = Object.freeze({
  post: 2000,
  comment: 1000,
  page: 300,
  recentPosts: 5,
  recentPostText: 500,
});
const PAGE_REPORT_ID_PATTERN = /^[a-f0-9]{40}$/u;

// The moderateReport actions that exist only for Page reports. The classic
// actions (claim, release, resolve, removeAndResolve, dismiss) keep their
// meaning; on a Page report removeAndResolve removes the post or comment,
// or SUSPENDS the Page for a `page` report.
const PAGE_MODERATION_ACTIONS = Object.freeze({
  HOLD_POST: "holdPagePost",
  RESTORE_POST: "restorePagePost",
  SUSPEND_PAGE: "suspendPage",
  LIFT_SUSPENSION: "liftPageSuspension",
});

const SYSTEM_ACTOR = Object.freeze({ actorId: "yovoice-system", actorName: "YO Voice" });
const PAGE_MODERATION_NOTICE_TYPE = "pageModeration";
const PAGE_LAPSE_NOTICE_TYPE = "pageLapse";

const PAGE_MODERATION_NOTICES = Object.freeze({
  postRemoved: (label) => `Your Page post was removed: ${label}`,
  postHeld: (label) => `Your Page post is hidden while we review it: ${label}`,
  postRestored: () => "Your Page post is visible again",
  commentRemoved: (label) => `Your comment on a Page was removed: ${label}`,
  pageSuspended: (label) => `Your Page was suspended: ${label}`,
  pageSuspensionLifted: () => "Your Page is no longer suspended",
});
const PAGE_LAPSE_NOTICES = Object.freeze({
  readOnly: "Your Page is read-only because YO Voice VIP ended. Nothing is deleted.",
  hidingSoon: "Your Page will be hidden in 7 days. Nothing is deleted; it returns with VIP.",
});
// Day 23 of the 30-day read-only window (§2.8, R12).
const PAGE_LAPSE_WARNING_AFTER_MS = 23 * 24 * 60 * 60 * 1000;

// ------------------------------------------------------------------ input

function nullableId(value, pattern, label) {
  if (value === null) return null;
  if (typeof value !== "string" || !pattern.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

/**
 * The exact createPageReportV1 input, format-checked before any read (§2.10
 * "the ids in the input are format-checked"). Returns the normalized input
 * and the target id the report is about.
 */
function requirePageReportInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    fail("invalid-argument", "data must be an object.");
  }
  const keys = Object.keys(data).sort();
  if (keys.length !== PAGE_REPORT_INPUT_KEYS.length ||
      keys.some((key, index) => key !== PAGE_REPORT_INPUT_KEYS[index])) {
    fail("invalid-argument", `data must contain exactly ${PAGE_REPORT_INPUT_KEYS.join(", ")}.`);
  }
  const { targetType } = data;
  if (!PAGE_REPORT_TARGET_TYPES.includes(targetType)) {
    fail("invalid-argument", "targetType is invalid.");
  }
  if (!isValidOpaqueUid(data.pageId)) fail("invalid-argument", "pageId is invalid.");
  const postId = nullableId(data.postId, PAGE_POST_ID_PATTERN, "postId");
  const commentId = nullableId(data.commentId, PAGE_COMMENT_ID_PATTERN, "commentId");
  if ((targetType === "page" && (postId !== null || commentId !== null)) ||
      (targetType === "pagePost" && (postId === null || commentId !== null)) ||
      (targetType === "pagePostComment" && (postId === null || commentId === null))) {
    fail("invalid-argument", "The report target ids do not match targetType.");
  }
  if (typeof data.reason !== "string" || !PAGE_REPORT_REASONS.includes(data.reason)) {
    fail("invalid-argument", "reason is invalid.");
  }
  let note = "";
  if (data.note !== null) {
    if (typeof data.note !== "string") fail("invalid-argument", "note must be text or null.");
    note = data.note.normalize("NFC").trim();
    if (note.length > PAGE_REPORT_NOTE_MAX ||
        /[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/u.test(note)) {
      fail("invalid-argument", `note must be at most ${PAGE_REPORT_NOTE_MAX} characters.`);
    }
  }
  const targetId = targetType === "page"
    ? data.pageId
    : targetType === "pagePost" ? postId : commentId;
  return Object.freeze({
    requestId: data.requestId,
    targetType,
    pageId: data.pageId,
    postId,
    commentId,
    targetId,
    reason: data.reason,
    note,
  });
}

function pageReportId(reporterId, targetType, targetId) {
  return digest("page-report", reporterId, targetType, targetId).slice(0, 40);
}

function pageReportContextPath(targetType, targetId) {
  if (targetType === "page") return `pages/${targetId}`;
  if (targetType === "pagePost") return `pagePosts/${targetId}`;
  return `pagePostComments/${targetId}`;
}

function cap(text, max) {
  if (typeof text !== "string") return "";
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const last = cut.charCodeAt(cut.length - 1);
  return last >= 0xd800 && last <= 0xdbff ? cut.slice(0, -1) : cut;
}

/**
 * The reports/{id} document of a Page report. `page`, `post` and `comment`
 * are the raw stored data the report transaction read (any may be null for
 * the target types that do not need it; a malformed Page still yields a
 * report, with nulls where its fields are unreadable).
 */
function mediaSnapshot(post) {
  return (Array.isArray(post?.media) ? post.media : [])
    .map((entry) => ({ mediaId: entry.mediaId, type: entry.type }));
}

function pageReportDocument({ reporterId, input, page, post, comment, now, recentPosts = [] }) {
  const pageKind = page?.kind === "business" || page?.kind === "community" ? page.kind : null;
  const pageDisplayName = typeof page?.displayName === "string"
    ? cap(page.displayName, 120)
    : null;
  let reportedUserId = input.pageId;
  let targetTextSnapshot = "";
  let targetMedia = [];
  let targetPostKind = null;
  if (input.targetType === "page") {
    targetTextSnapshot = cap(page?.description, PAGE_REPORT_SNAPSHOT_LIMITS.page);
  } else if (input.targetType === "pagePost") {
    targetTextSnapshot = cap(post.text, PAGE_REPORT_SNAPSHOT_LIMITS.post);
    targetPostKind = post.kind;
    targetMedia = mediaSnapshot(post);
  } else {
    reportedUserId = comment.authorId;
    targetTextSnapshot = cap(comment.text, PAGE_REPORT_SNAPSHOT_LIMITS.comment);
  }
  return {
    schemaVersion: 2,
    reporterId,
    targetType: input.targetType,
    targetId: input.targetId,
    reportedUserId,
    contextPath: pageReportContextPath(input.targetType, input.targetId),
    pageId: input.pageId,
    postId: input.postId,
    commentId: input.commentId,
    pageKind,
    pageDisplayName,
    targetPostKind,
    targetTextSnapshot,
    targetMedia,
    recentPosts: input.targetType === "page"
      ? recentPosts.slice(0, PAGE_REPORT_SNAPSHOT_LIMITS.recentPosts).map((recent) => ({
        postId: recent.postId,
        kind: recent.kind,
        status: recent.status,
        text: cap(recent.text, PAGE_REPORT_SNAPSHOT_LIMITS.recentPostText),
        media: mediaSnapshot(recent),
      }))
      : [],
    note: input.note,
    reason: input.reason,
    status: "open",
    createdAt: now,
    updatedAt: now,
  };
}

/**
 * The target of a stored Page report, for moderation. A report that does not
 * carry its full, consistent target identity is refused, never partially
 * trusted (the reel-comment rule, moderation/reports.js).
 */
function canonicalPageReportTarget(report) {
  const invalid = () => fail("failed-precondition", "The reported Page reference is invalid.");
  if (!report || typeof report !== "object" || report.schemaVersion !== 2 ||
      !PAGE_REPORT_TARGET_TYPES.includes(report.targetType) ||
      !isValidOpaqueUid(report.pageId) || !isValidOpaqueUid(report.reportedUserId) ||
      timestampMillis(report.createdAt) === null) {
    invalid();
  }
  const { targetType, pageId } = report;
  const postId = report.postId ?? null;
  const commentId = report.commentId ?? null;
  if (targetType === "page") {
    if (postId !== null || commentId !== null || report.targetId !== pageId ||
        report.reportedUserId !== pageId) invalid();
  } else if (targetType === "pagePost") {
    if (typeof postId !== "string" || !PAGE_POST_ID_PATTERN.test(postId) || commentId !== null ||
        report.targetId !== postId || report.reportedUserId !== pageId) invalid();
  } else if (typeof postId !== "string" || !PAGE_POST_ID_PATTERN.test(postId) ||
      typeof commentId !== "string" || !PAGE_COMMENT_ID_PATTERN.test(commentId) ||
      report.targetId !== commentId) {
    invalid();
  }
  if (report.contextPath !== pageReportContextPath(targetType, report.targetId)) invalid();
  return Object.freeze({
    targetType,
    pageId,
    postId,
    commentId,
    reportedUserId: report.reportedUserId,
  });
}

function isPageReportTargetType(targetType) {
  return PAGE_REPORT_TARGET_TYPES.includes(targetType);
}

/// The reason key a moderation action records: the moderator's explicit
/// key, else the report's own reason, else "other".
function pageModerationReason(explicit, reportReason) {
  if (explicit !== null && explicit !== undefined) {
    if (typeof explicit !== "string" || !PAGE_REPORT_REASONS.includes(explicit)) {
      fail("invalid-argument", "moderationReason is invalid.");
    }
    return explicit;
  }
  return PAGE_REPORT_REASONS.includes(reportReason) ? reportReason : "other";
}

function pageReasonLabel(reason) {
  return PAGE_REASON_LABELS[reason] ?? PAGE_REASON_LABELS.other;
}

// ---------------------------------------------------------------- notices

/// A system notification row (the achievement shape plus additive keys).
function pageSystemNotice({ type, targetId, targetSubId = null, targetLabel, dedupeKey, now, extra = {} }) {
  const row = {
    type,
    ...SYSTEM_ACTOR,
    actorPhotoUrl: null,
    targetId,
    targetLabel: cap(targetLabel, 120),
    isRead: false,
    createdAt: now,
    dedupeKey,
    bellSuppressed: false,
    ...extra,
  };
  if (typeof targetSubId === "string" && targetSubId.length > 0) row.targetSubId = targetSubId;
  return row;
}

/**
 * A pageModeration row. `action` is a PAGE_MODERATION_NOTICES key; the id is
 * derived from the report and the action, so a replayed decision rewrites
 * the same row.
 */
function pageModerationNotice({ action, reason, reportId, pageId, subjectId = null, now }) {
  const build = PAGE_MODERATION_NOTICES[action];
  if (!build) throw new TypeError(`Unknown Page moderation notice: ${action}`);
  const id = `${PAGE_MODERATION_NOTICE_TYPE}_${digest("page-moderation-notice", reportId, action).slice(0, 40)}`;
  return {
    id,
    data: pageSystemNotice({
      type: PAGE_MODERATION_NOTICE_TYPE,
      targetId: pageId,
      targetSubId: subjectId,
      targetLabel: build(pageReasonLabel(reason)),
      dedupeKey: id,
      now,
      extra: { moderationAction: action, moderationReason: reason ?? null },
    }),
  };
}

/// A pageLapse row: `phase` "readOnly" (Day 0) or "hidingSoon" (Day 23).
/// One row per phase per lapse (the id carries lapsedAt).
function pageLapseNotice({ phase, pageId, lapsedAtMs, now }) {
  const label = PAGE_LAPSE_NOTICES[phase];
  if (!label || !Number.isSafeInteger(lapsedAtMs)) {
    throw new TypeError("A lapse phase and lapsedAt are required.");
  }
  const id = `${PAGE_LAPSE_NOTICE_TYPE}_${phase}_${lapsedAtMs}`;
  return {
    id,
    data: pageSystemNotice({
      type: PAGE_LAPSE_NOTICE_TYPE,
      targetId: pageId,
      targetLabel: label,
      dedupeKey: id,
      now,
      extra: { lapsePhase: phase },
    }),
  };
}

// ------------------------------------------------------ evidence retention
//
// pageEvidenceRetention/{postId} (server-only): the 90-day cap on a Page
// post kept as a TOMBSTONE (§2.4, §2.11). Two writers:
//   reason "accountDeleted"  account deletion kept the post because a report
//                            on it (or its comments) was open;
//   reason "ownerDelete"     the owner deleted a held, removed or reported
//                            post of a LIVE account (audit 2026-09-28: a
//                            tombstone never outlives 90 days, the same cap
//                            as a deleted account's).
// It is purged (the post, its likes and comments, its media) when the last
// open report on the post resolves (moderation sets purgeAt to now) or when
// purgeAt passes, whichever comes first.
//   {schemaVersion:1, postId, pageId, reason, purgeAt, createdAt}

const PAGE_EVIDENCE_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
const PAGE_EVIDENCE_RETENTION_REASONS = Object.freeze(["accountDeleted", "ownerDelete"]);
const PAGE_EVIDENCE_RETENTION_KEYS = Object.freeze([
  "createdAt",
  "pageId",
  "postId",
  "purgeAt",
  "reason",
  "schemaVersion",
]);

function pageEvidenceRetentionDocument({ postId, pageId, now, purgeAt, reason = "accountDeleted" }) {
  if (!PAGE_EVIDENCE_RETENTION_REASONS.includes(reason)) {
    throw new TypeError("An evidence retention reason is required.");
  }
  return { schemaVersion: 1, postId, pageId, reason, purgeAt, createdAt: now };
}

/// The canonical retention row, or null when missing. A malformed row is
/// read as due now (staff kept the report snapshot).
function canonicalPageEvidenceRetention(snapshot) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  const keys = Object.keys(value).sort();
  const exact = keys.length === PAGE_EVIDENCE_RETENTION_KEYS.length &&
    keys.every((key, index) => key === PAGE_EVIDENCE_RETENTION_KEYS[index]);
  if (!exact || value.schemaVersion !== 1 || value.postId !== snapshot.id ||
      !PAGE_POST_ID_PATTERN.test(snapshot.id) || !isValidOpaqueUid(value.pageId) ||
      !PAGE_EVIDENCE_RETENTION_REASONS.includes(value.reason) ||
      timestampMillis(value.purgeAt) === null ||
      timestampMillis(value.createdAt) === null) {
    return Object.freeze({
      postId: snapshot.id, pageId: null, reason: "evidencePurge", purgeAtMs: 0, malformed: true,
    });
  }
  return Object.freeze({
    postId: value.postId,
    pageId: value.pageId,
    reason: value.reason,
    purgeAtMs: timestampMillis(value.purgeAt),
    malformed: false,
  });
}

// ----------------------------------------------------------------- errors

const PAGE_REPORT_ERRORS = Object.freeze({
  missing: () => pagesError("not-found",
    "That content is no longer available.", "pageReportTargetMissing"),
  own: () => pagesError("failed-precondition",
    "You can't report your own content.", "pageReportOwnContent"),
});

module.exports = {
  PAGE_EVIDENCE_RETENTION_KEYS,
  PAGE_EVIDENCE_RETENTION_MS,
  PAGE_EVIDENCE_RETENTION_REASONS,
  canonicalPageEvidenceRetention,
  pageEvidenceRetentionDocument,
  PAGE_LAPSE_NOTICES,
  PAGE_LAPSE_NOTICE_TYPE,
  PAGE_LAPSE_WARNING_AFTER_MS,
  PAGE_MODERATION_ACTIONS,
  PAGE_MODERATION_NOTICES,
  PAGE_MODERATION_NOTICE_TYPE,
  PAGE_REASON_LABELS,
  PAGE_REPORT_ERRORS,
  PAGE_REPORT_ID_PATTERN,
  PAGE_REPORT_INPUT_KEYS,
  PAGE_REPORT_NOTE_MAX,
  PAGE_REPORT_REASONS,
  PAGE_REPORT_SNAPSHOT_LIMITS,
  PAGE_REPORT_TARGET_TYPES,
  canonicalPageReportTarget,
  isPageReportTargetType,
  pageLapseNotice,
  pageModerationNotice,
  pageModerationReason,
  pageReasonLabel,
  pageReportContextPath,
  pageReportDocument,
  pageReportId,
  pageSystemNotice,
  requirePageReportInput,
};

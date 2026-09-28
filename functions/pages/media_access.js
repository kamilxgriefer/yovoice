// getPagePostMediaAccessV1 (ADR-233 §2.5): 90-second, generation-bound V4
// read URLs for the photos and the voice clip of ONE Page post.
// europe-west1, enforceAppCheck:false.
//
//   request  {postId, mediaIds:[1..10]}
//   response {schemaVersion:1, grants:[{mediaId, url, expiresAtMs}]}
//
// mediaId -> storagePath comes ONLY from the post document: every mediaId
// must match ^pm_[a-f0-9]{40}$ and appear in post.media, so a caller can
// never name an object.
//
// Two branches, and every other caller gets the uniform `pageUnavailable`:
//
//   * viewer  readAccess admits the caller (appConfig/pagesV1), canViewPage
//             (audience.js) passes, and the post is `published` — or the
//             caller is the owner and it is `held`.
//   * staff   the caller holds an active report-staff role, checked on BOTH
//             halves (the signed claim and the users/{uid}.role mirror, so a
//             revocation is immediate), and the post is held, removed or
//             deleted (a tombstone) with a report on it
//             (pagePostOpenReports/{postId}), or is PUBLISHED with an OPEN
//             report on it (count > 0). Every grant writes a
//             pageStaffMediaAudit row {staffUid, postId, mediaId, reportId,
//             at} BEFORE any URL is returned. The staff branch does not
//             need readAccess: evidence review must work with the kill
//             switch on.
//
// Rate `pages.media`: 60/min, 600/h, 3000/day per caller (bounds scraping of
// public Pages, SECURITY finding S-m7). URLs are memoised per instance for
// (postId, mediaId, generation) for 60 s (best effort): a memoised URL still
// has at least 30 s to live, and the authorization is re-run on every call.

const { Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  consumeRateLimit,
  fail,
  rateLimitReference,
  requireActor,
  requireExactInput,
  transactionGetAll,
} = require("../integrity/guards");
const { likersAccountIsActive } = require("../utils/likers_access");
const { USER_ROLES } = require("../utils/roles");
const {
  pagesNotEnabledError,
  pagesReadAllowed,
  readPagesActivation,
} = require("./activation");
const { pageUnavailableError, pageViewDecision } = require("./audience");
const {
  PAGE_MEDIA_ID_PATTERN,
  PAGE_POST_ID_PATTERN,
  canonicalPageOrNull,
} = require("./contract");
const { pagePostOpenReports } = require("./media_contract");
const { safeGrantUrl } = require("./media_storage");
const { PAGE_POST_MAX_PHOTOS, canonicalPagePostData } = require("./post_contract");

const REGION = "europe-west1";
const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;
const PAGE_MEDIA_GRANT_TTL_MS = 90_000;
const PAGE_MEDIA_MEMO_TTL_MS = 60_000;
const PAGE_MEDIA_MEMO_MAX = 500;

// The report staff (moderation/reports.js REPORT_STAFF_ROLES).
const PAGE_STAFF_ROLES = Object.freeze([
  USER_ROLES.MODERATOR,
  USER_ROLES.SUPER_MODERATOR,
  USER_ROLES.SUPER_ADMIN,
]);
const PAGES_MEDIA_RATE_LIMITS = Object.freeze({
  "pages.media": Object.freeze({ maxEvents: 60, windowMs: MINUTE_MS }),
  "pages.mediaHourly": Object.freeze({ maxEvents: 600, windowMs: HOUR_MS }),
  "pages.mediaDaily": Object.freeze({ maxEvents: 3000, windowMs: DAY_MS }),
});
const MEDIA_SCOPES = Object.freeze(Object.keys(PAGES_MEDIA_RATE_LIMITS));
const STAFF_STATUSES = Object.freeze(["held", "removed", "deleted"]);
const PAGE_MEDIA_ACCESS_RESPONSE_KEYS = Object.freeze(["grants", "schemaVersion"]);
const PAGE_MEDIA_GRANT_KEYS = Object.freeze(["expiresAtMs", "mediaId", "url"]);

function accessInput(data) {
  const fields = ["postId", "mediaIds"];
  requireExactInput(data, fields, fields);
  if (typeof data.postId !== "string" || !PAGE_POST_ID_PATTERN.test(data.postId)) {
    fail("invalid-argument", "postId is invalid.");
  }
  if (!Array.isArray(data.mediaIds) || data.mediaIds.length < 1 ||
      data.mediaIds.length > PAGE_POST_MAX_PHOTOS ||
      data.mediaIds.some((id) => typeof id !== "string" || !PAGE_MEDIA_ID_PATTERN.test(id)) ||
      new Set(data.mediaIds).size !== data.mediaIds.length) {
    fail("invalid-argument", "mediaIds must list 1-10 distinct media ids.");
  }
  return { postId: data.postId, mediaIds: [...data.mediaIds] };
}

function createPagesMediaAccessService({
  firestore,
  storage,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimits = PAGES_MEDIA_RATE_LIMITS,
}) {
  if (!firestore?.doc || !storage?.getSignedReadUrl ||
      typeof TimestampImpl?.fromMillis !== "function" || typeof clock !== "function") {
    throw new TypeError("firestore, storage, Timestamp and clock are required.");
  }
  const memo = new Map();

  function timing() {
    const nowMs = clock();
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  function dataOf(snapshot) {
    return snapshot?.exists ? (snapshot.data() ?? null) : null;
  }

  /// The caller's staff role when BOTH halves agree, else null.
  async function staffRole(auth) {
    const role = typeof auth.token?.role === "string" ? auth.token.role : null;
    if (role === null || !PAGE_STAFF_ROLES.includes(role)) return null;
    const profile = dataOf(await firestore.doc(`users/${auth.uid}`).get());
    if (profile?.role !== role || !likersAccountIsActive(profile) ||
        profile.banned === true || profile.disabled === true || profile.deleted === true) {
      return null;
    }
    return role;
  }

  async function chargeRates(uid, { nowMs, now }) {
    await firestore.runTransaction(async (transaction) => {
      const references = MEDIA_SCOPES.map((scope) => rateLimitReference(firestore, scope, uid));
      const snapshots = await transactionGetAll(transaction, ...references);
      MEDIA_SCOPES.forEach((scope, index) => {
        consumeRateLimit(transaction, snapshots[index], {
          reference: references[index], scope, uid, nowMs, now, ...rateLimits[scope],
        });
      });
    });
  }

  function remember(key, grant, nowMs) {
    if (memo.size >= PAGE_MEDIA_MEMO_MAX) memo.delete(memo.keys().next().value);
    memo.set(key, { ...grant, signedAtMs: nowMs });
  }

  async function grantFor(postId, entry, nowMs) {
    const key = `${postId}/${entry.mediaId}/${entry.generation}`;
    const cached = memo.get(key);
    if (cached && nowMs - cached.signedAtMs < PAGE_MEDIA_MEMO_TTL_MS &&
        cached.expiresAtMs > nowMs) {
      return { mediaId: entry.mediaId, url: cached.url, expiresAtMs: cached.expiresAtMs };
    }
    const expiresAtMs = nowMs + PAGE_MEDIA_GRANT_TTL_MS;
    const url = await storage.getSignedReadUrl(entry.storagePath, {
      expiresAtMs, generation: entry.generation,
    });
    if (!safeGrantUrl(url)) fail("failed-precondition", "A Page media grant is unavailable.");
    remember(key, { url, expiresAtMs }, nowMs);
    return { mediaId: entry.mediaId, url, expiresAtMs };
  }

  async function viewerMayRead(auth, post, viewerUser, activation, nowMs) {
    const viewerId = auth.uid;
    const pageId = post.pageId;
    const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock] = await firestore.getAll(
      firestore.doc(`pages/${pageId}`),
      firestore.doc(`users/${pageId}`),
      firestore.doc(`users/${viewerId}/blocked/${pageId}`),
      firestore.doc(`users/${pageId}/blocked/${viewerId}`),
    );
    const decision = pageViewDecision({
      viewerId,
      pageId,
      page: canonicalPageOrNull(pageSnapshot, pageId),
      pageUser: dataOf(pageUserSnapshot),
      viewerUser,
      viewerBlocksPage: viewerBlock.exists,
      pageBlocksViewer: pageBlock.exists,
      nowMs,
      lapseEnabled: activation.lapseEnabled,
    });
    const statuses = decision.isOwner ? ["published", "held"] : ["published"];
    return decision.viewable && statuses.includes(post.status);
  }

  async function getPagePostMediaAccessV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = accessInput(request.data);
    const timed = timing();
    const role = await staffRole(auth);
    const activation = await readPagesActivation({ db: firestore, logger });
    const readAllowed = pagesReadAllowed(activation, auth.uid);
    if (!readAllowed && role === null) throw pagesNotEnabledError();
    await chargeRates(auth.uid, timed);

    const [postSnapshot, viewerSnapshot, reportsSnapshot] = await firestore.getAll(
      firestore.doc(`pagePosts/${input.postId}`),
      firestore.doc(`users/${auth.uid}`),
      firestore.doc(`pagePostOpenReports/${input.postId}`),
    );
    const post = canonicalPagePostData(postSnapshot);
    if (post === null) throw pageUnavailableError();
    const viewerUser = dataOf(viewerSnapshot);

    let reportId = null;
    let allowed = readAllowed &&
      await viewerMayRead(auth, post, viewerUser, activation, timed.nowMs);
    if (!allowed && role !== null) {
      // Staff open the bytes of a post a report names: a held, removed or
      // deleted one, or a PUBLISHED one while a report on it is still open
      // (audit 2026-09-28: judging a reported photo must not require holding
      // it first, and must not depend on testerUids or on the Page's blocks).
      const reports = pagePostOpenReports(reportsSnapshot, post.postId);
      const reviewable = STAFF_STATUSES.includes(post.status) ||
        (post.status === "published" && reports.count > 0);
      if (reviewable && reports.exists && reports.lastReportId !== null) {
        allowed = true;
        reportId = reports.lastReportId;
      }
    }
    if (!allowed) throw pageUnavailableError();

    // Only now, for an authorized caller: every id must be one of the post's.
    const byId = new Map(post.media.map((entry) => [entry.mediaId, entry]));
    if (input.mediaIds.some((id) => !byId.has(id))) {
      fail("invalid-argument", "mediaIds must belong to the post.");
    }
    if (reportId !== null) {
      const batch = firestore.batch();
      input.mediaIds.forEach((mediaId) => {
        batch.set(firestore.collection("pageStaffMediaAudit").doc(), {
          staffUid: auth.uid,
          postId: post.postId,
          mediaId,
          reportId,
          at: timed.now,
        });
      });
      await batch.commit();
    }
    const grants = [];
    for (const mediaId of input.mediaIds) {
      grants.push(await grantFor(post.postId, byId.get(mediaId), clock()));
    }
    return { schemaVersion: 1, grants };
  }

  return Object.freeze({ getPagePostMediaAccessV1 });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    const { defaultPagesMediaDependencies } = require("./media_runtime");
    defaultService = createPagesMediaAccessService({
      firestore: db,
      storage: defaultPagesMediaDependencies().storage,
    });
  }
  return defaultService;
}

const getPagePostMediaAccessV1 = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => service().getPagePostMediaAccessV1(request),
);

module.exports = {
  PAGE_MEDIA_ACCESS_RESPONSE_KEYS,
  PAGE_MEDIA_GRANT_KEYS,
  PAGE_MEDIA_GRANT_TTL_MS,
  PAGE_STAFF_ROLES,
  PAGES_MEDIA_RATE_LIMITS,
  createPagesMediaAccessService,
  getPagePostMediaAccessV1,
};

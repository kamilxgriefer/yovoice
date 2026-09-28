// Premium Pages reports and staff moderation (ADR-233 §2.10, package B5)
// against the Firestore emulator: createPageReportV1 (a safety action: no
// switch, no audience check, unverified and muted callers allowed), the
// report snapshot and evidence hold, the moderateReport Page arms (remove,
// hold, restore, remove comment, suspend, lift, resolve) with the open-report
// count and held-media release, and the owner-guarded operator script.
const assert = require("node:assert/strict");
const { beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
// Its own Firestore namespace (the account_deletion.test.js pattern): the
// suites share one emulator, and these seed listed Pages, open reports and
// whole-collection sweeps that must neither see nor disturb a neighbour's.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const SUITE_PROJECT = `${BASE_PROJECT}-pages-reports`;
process.env.GCLOUD_PROJECT = SUITE_PROJECT;

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: SUITE_PROJECT });

const { createPagesReportService, PAGE_REPORT_RESPONSE_KEYS } = require("../pages/reports");
const { PAGE_REPORT_SNAPSHOT_LIMITS, pageReportId } = require("../pages/report_contract");
const { moderateReport, handleModerateReport } = require("../moderation/reports");
const { createPagesPostService } = require("../pages/posts");
const { createPagesMediaStorageAdapter } = require("../pages/media_storage");
const { setProtectedOwnerUidForTests } = require("../utils/roles");
const pagesModerationScript = require("../scripts/pages_moderation");
const {
  DAY_MS,
  clearActivation,
  commentDoc,
  freshUid,
  newCommentId,
  newPostId,
  photoMedia,
  postDoc,
  request,
  seedAccount,
  seedPage,
  setActivation,
  silentLogger,
} = require("./helpers/pages_fixture");
const { FakeBucket } = require("./helpers/pages_media_fixture");
const { createPagesMaintenanceService } = require("../pages/maintenance");

const db = getFirestore();
const runModerate = moderateReport.run ?? moderateReport;
let nowMs = 1_900_000_000_000;

beforeEach(async () => {
  nowMs += DAY_MS;
  // Reporting is a safety action: the suite runs with NO activation document.
  await clearActivation(db);
});

function reports({ logger = silentLogger(), firestore = db } = {}) {
  return createPagesReportService({
    firestore,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger,
  });
}

async function dataOf(pathName) {
  const snapshot = await db.doc(pathName).get();
  return snapshot.exists ? snapshot.data() : null;
}

function reportInput(overrides = {}) {
  return {
    requestId: `req-${freshUid()}`,
    targetType: "pagePost",
    pageId: null,
    postId: null,
    commentId: null,
    reason: "spam",
    note: null,
    ...overrides,
  };
}

async function expectError(promise, code, reason = undefined) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, error.message);
    if (reason !== undefined) assert.equal(error.details?.reason, reason);
    return true;
  });
}

/// A running Page with one published photo post, pinned, plus a reporter.
async function scene({ postOverrides = {} } = {}) {
  const pageId = freshUid("rpage");
  const reporter = freshUid("rrep");
  const postId = newPostId();
  const media = photoMedia(pageId, postId, 2);
  await seedPage(db, pageId, nowMs, { page: {
    postCount: 1, listed: true, pinnedPostId: postId,
    lastPostAt: Timestamp.fromMillis(nowMs - 1000),
  } });
  await db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, nowMs - 1000, {
    kind: "photo", media, text: "Our menu", ...postOverrides,
  }));
  await seedAccount(db, reporter, nowMs);
  return { pageId, reporter, postId, media };
}

async function seedModerator() {
  const uid = freshUid("rmod");
  await db.doc(`users/${uid}`).set({ uid, role: "moderator", status: "active" });
  return uid;
}

function moderatorRequest(uid, data) {
  return {
    auth: {
      uid,
      token: {
        role: "moderator",
        email: "moderator@example.invalid",
        email_verified: true,
        auth_time: Math.floor(Date.now() / 1000),
      },
    },
    data: { requestId: `mod-${freshUid()}`, moderatorNote: "", ...data },
  };
}

// ------------------------------------------------------------ reporting

test("input: exact keys, id formats and target consistency are refused before any read", async () => {
  let touched = false;
  const untouchable = new Proxy({}, { get(_, property) {
    if (property === "doc") return () => ({});
    touched = true;
    throw new Error(`unexpected ${String(property)}`);
  } });
  const service = reports({ firestore: untouchable });
  const pageId = freshUid("rpage");
  const cases = [
    { ...reportInput({ pageId, postId: newPostId() }), extra: true },
    reportInput({ pageId: "a/b", postId: newPostId() }),
    reportInput({ pageId, postId: "pp_123" }),
    reportInput({ pageId, postId: null }),
    reportInput({ targetType: "page", pageId, postId: newPostId() }),
    reportInput({ targetType: "pagePostComment", pageId, postId: newPostId(), commentId: "pc_x" }),
    reportInput({ targetType: "pagePostComment", pageId, postId: null, commentId: newCommentId() }),
    reportInput({ pageId, postId: newPostId(), reason: "rude" }),
    reportInput({ pageId, postId: newPostId(), note: "x".repeat(301) }),
    reportInput({ targetType: "reel", pageId }),
  ];
  for (const data of cases) {
    await expectError(service.createPageReportV1(request(freshUid(), data, { verified: false })),
      "invalid-argument");
  }
  assert.equal(touched, false);
});

test("a post report stores the snapshot, holds the evidence and counts the open report", async () => {
  const { pageId, reporter, postId, media } = await scene();
  const service = reports();
  const data = reportInput({ pageId, postId, note: "  selling fake tickets " });
  const result = await service.createPageReportV1(request(reporter, data));
  assert.deepEqual(Object.keys(result).sort(), [...PAGE_REPORT_RESPONSE_KEYS]);
  assert.equal(result.created, true);
  assert.equal(result.reportId, pageReportId(reporter, "pagePost", postId));
  const stored = await dataOf(`reports/${result.reportId}`);
  assert.deepEqual(Object.keys(stored).sort(), [
    "commentId", "contextPath", "createdAt", "note", "pageDisplayName", "pageId", "pageKind",
    "postId", "reason", "recentPosts", "reportedUserId", "reporterId", "schemaVersion", "status",
    "targetId", "targetMedia", "targetPostKind", "targetTextSnapshot", "targetType", "updatedAt",
  ]);
  assert.deepEqual(stored.recentPosts, [], "only a Page report snapshots recent posts");
  assert.equal(stored.schemaVersion, 2);
  assert.equal(stored.status, "open");
  assert.equal(stored.reportedUserId, pageId);
  assert.equal(stored.contextPath, `pagePosts/${postId}`);
  assert.equal(stored.targetTextSnapshot, "Our menu");
  assert.equal(stored.note, "selling fake tickets");
  assert.deepEqual(stored.targetMedia, media.map((entry) => ({ mediaId: entry.mediaId, type: "image" })));
  assert.equal(stored.pageDisplayName, "Kawiarnia Pod Lipą");
  assert.equal(stored.pageKind, "business");
  assert.equal((await dataOf(`pagePosts/${postId}`)).evidenceHold, true);
  const open = await dataOf(`pagePostOpenReports/${postId}`);
  assert.equal(open.count, 1);
  assert.equal(open.lastReportId, result.reportId);

  // An exact retry replays; a new attempt by the same reporter dedupes.
  assert.deepEqual(await service.createPageReportV1(request(reporter, data)), result);
  const again = await service.createPageReportV1(request(reporter, { ...data, requestId: `req-${freshUid()}` }));
  assert.equal(again.created, false);
  assert.equal((await dataOf(`pagePostOpenReports/${postId}`)).count, 1);
  // A second reporter counts.
  const second = freshUid("rrep");
  await seedAccount(db, second, nowMs);
  await service.createPageReportV1(request(second, reportInput({ pageId, postId })));
  assert.equal((await dataOf(`pagePostOpenReports/${postId}`)).count, 2);
});

test("snapshots are capped: post text 2000, comment 1000", async () => {
  const { pageId, reporter, postId } = await scene({ postOverrides: { text: "a".repeat(4999) } });
  const commentId = newCommentId();
  const author = freshUid("rcom");
  await seedAccount(db, author, nowMs);
  await db.doc(`pagePostComments/${commentId}`).set(commentDoc(
    { postId, pageId }, commentId, author, nowMs, { text: "b".repeat(1000) }));
  const service = reports();
  const post = await service.createPageReportV1(request(reporter, reportInput({ pageId, postId })));
  assert.equal((await dataOf(`reports/${post.reportId}`)).targetTextSnapshot.length,
    PAGE_REPORT_SNAPSHOT_LIMITS.post);
  const comment = await service.createPageReportV1(request(reporter, reportInput({
    targetType: "pagePostComment", pageId, postId, commentId, reason: "harassment" })));
  const stored = await dataOf(`reports/${comment.reportId}`);
  assert.equal(stored.targetTextSnapshot.length, PAGE_REPORT_SNAPSHOT_LIMITS.comment);
  assert.equal(stored.reportedUserId, author);
  assert.equal(stored.contextPath, `pagePostComments/${commentId}`);
  assert.equal((await dataOf(`pagePostOpenReports/${postId}`)).count, 2,
    "a comment report counts on its parent post");
});

test("a Page that blocked the reporter is still reportable; unverified, muted and with the kill switch on", async () => {
  const { pageId, reporter } = await scene();
  await db.doc(`users/${pageId}/blocked/${reporter}`).set({ uid: reporter });
  await db.doc(`restrictions/${reporter}`).set({ type: "communicationMute", expiresAt: null });
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled", lapseEnabled: false });
  const result = await reports().createPageReportV1(request(reporter, reportInput({
    targetType: "page", pageId, reason: "impersonation" }), { verified: false }));
  assert.equal(result.created, true);
  const stored = await dataOf(`reports/${result.reportId}`);
  assert.equal(stored.targetTextSnapshot, "Coffee and cake.");
  assert.equal(stored.contextPath, `pages/${pageId}`);
  assert.equal(await dataOf(`pagePostOpenReports/${pageId}`), null);
  assert.equal(stored.recentPosts.length, 1);
  assert.equal(stored.recentPosts[0].text, "Our menu");
});

test("a Page report snapshots the newest published or held posts (5, text 500)", async () => {
  const { pageId, reporter, postId } = await scene({ postOverrides: { text: "c".repeat(900) } });
  const ids = [];
  for (let index = 1; index <= 7; index += 1) {
    const id = newPostId();
    ids.push(id);
    const status = index === 7 ? "removed" : index === 6 ? "held" : "published";
    await db.doc(`pagePosts/${id}`).set(postDoc(pageId, id, nowMs + index * 1000, {
      text: `post ${index}`,
      status,
      ...(status === "held" ? { heldAt: Timestamp.fromMillis(nowMs) } : {}),
      ...(status === "removed"
        ? { removedAt: Timestamp.fromMillis(nowMs), removedReason: "spam" }
        : {}),
    }));
  }
  const result = await reports().createPageReportV1(request(reporter, reportInput({
    targetType: "page", pageId, reason: "scam" })));
  const stored = await dataOf(`reports/${result.reportId}`);
  // Newest first; the removed one is skipped; at most five.
  assert.deepEqual(stored.recentPosts.map((entry) => entry.postId), [ids[5], ids[4], ids[3], ids[2], ids[1]]);
  assert.equal(stored.recentPosts[0].status, "held");
  for (const entry of stored.recentPosts) {
    assert.deepEqual(Object.keys(entry).sort(), ["kind", "media", "postId", "status", "text"]);
  }
  assert.equal(stored.recentPosts.some((entry) => entry.postId === postId), false);
  // The owner can now hard-delete every post; the words stay in the report.
  const second = freshUid("rrep");
  await seedAccount(db, second, nowMs);
  await db.doc(`pagePosts/${postId}`).update({ createdAt: Timestamp.fromMillis(nowMs + 99_000) });
  const again = await reports().createPageReportV1(request(second, reportInput({
    targetType: "page", pageId, reason: "scam" })));
  const long = (await dataOf(`reports/${again.reportId}`)).recentPosts[0];
  assert.equal(long.postId, postId);
  assert.equal(long.text.length, PAGE_REPORT_SNAPSHOT_LIMITS.recentPostText);
  assert.equal(long.media.length, 2);
});

test("existence only, one uniform refusal; own content refused", async () => {
  const { pageId, reporter, postId } = await scene();
  const service = reports();
  const missing = [
    reportInput({ targetType: "page", pageId: freshUid("nopage") }),
    reportInput({ pageId, postId: newPostId() }),
    reportInput({ targetType: "pagePostComment", pageId, postId, commentId: newCommentId() }),
  ];
  for (const data of missing) {
    await expectError(service.createPageReportV1(request(reporter, data)), "not-found",
      "pageReportTargetMissing");
  }
  // A post of another Page is not this Page's post.
  const other = await scene();
  await expectError(service.createPageReportV1(request(reporter, reportInput({
    pageId, postId: other.postId }))), "not-found", "pageReportTargetMissing");
  // A removed post has nothing left to report.
  await db.doc(`pagePosts/${postId}`).update({ status: "removed", removedAt: Timestamp.fromMillis(nowMs),
    removedReason: "spam" });
  await expectError(service.createPageReportV1(request(reporter, reportInput({ pageId, postId }))),
    "not-found", "pageReportTargetMissing");
  await expectError(service.createPageReportV1(request(pageId, reportInput({
    targetType: "page", pageId }))), "failed-precondition", "pageReportOwnContent");
});

test("the report budget is charged before the target read (10 per 10 minutes)", async () => {
  const { pageId, reporter } = await scene();
  const service = reports();
  for (let index = 0; index < 10; index += 1) {
    await expectError(service.createPageReportV1(request(reporter, reportInput({
      pageId, postId: newPostId() }))), "not-found");
  }
  await expectError(service.createPageReportV1(request(reporter, reportInput({
    targetType: "page", pageId }))), "resource-exhausted");
});

// ------------------------------------------------------------ moderation

async function fileReport(reporter, data) {
  return (await reports().createPageReportV1(request(reporter, data))).reportId;
}

test("removeAndResolve on a post: removed with its reason, counters, pin, notice, evidence released", async () => {
  const { pageId, reporter, postId } = await scene();
  const reportId = await fileReport(reporter, reportInput({ pageId, postId, reason: "scam" }));
  const moderator = await seedModerator();
  const outcome = await runModerate(moderatorRequest(moderator, {
    reportId, action: "removeAndResolve", resolution: "contentRemoved" }));
  assert.equal(outcome.status, "resolved");
  assert.equal(outcome.contentRemoved, true);
  const post = await dataOf(`pagePosts/${postId}`);
  assert.equal(post.status, "removed");
  assert.equal(post.removedReason, "scam");
  assert.equal(post.evidenceHold, false, "the only open report is resolved");
  const page = await dataOf(`pages/${pageId}`);
  assert.equal(page.postCount, 0);
  assert.equal(page.pinnedPostId, null);
  assert.equal(page.listed, false);
  assert.equal((await dataOf(`pagePostOpenReports/${postId}`)).count, 0);
  const notices = (await db.collection(`users/${pageId}/notifications`).get()).docs.map((d) => d.data());
  const removed = notices.find((row) => row.type === "pageModeration");
  assert.equal(removed.targetLabel, "Your Page post was removed: scam or fraud");
  assert.equal(removed.moderationAction, "postRemoved");
  assert.equal(removed.targetId, pageId);
  assert.equal(removed.targetSubId, postId);
  // Replay: no second decrement, no second notice.
  const replay = await runModerate(moderatorRequest(moderator, {
    reportId, action: "removeAndResolve", resolution: "contentRemoved",
    requestId: (await dataOf(`reports/${reportId}`)).lastRequestId }));
  assert.equal(replay.replayed, true);
  assert.equal((await dataOf(`pagePostOpenReports/${postId}`)).count, 0);
});

test("hold and restore: the report stays open for the decision; counters move both ways", async () => {
  const { pageId, reporter, postId } = await scene();
  const reportId = await fileReport(reporter, reportInput({ pageId, postId }));
  const moderator = await seedModerator();
  const held = await runModerate(moderatorRequest(moderator, {
    reportId, action: "holdPagePost", moderationReason: "restrictedCategory" }));
  assert.equal(held.status, "inReview");
  let report = await dataOf(`reports/${reportId}`);
  assert.equal(report.assignedTo, moderator);
  assert.equal(report.resolution, undefined);
  let post = await dataOf(`pagePosts/${postId}`);
  assert.equal(post.status, "held");
  assert.equal((await dataOf(`pages/${pageId}`)).postCount, 0);
  await runModerate(moderatorRequest(moderator, { reportId, action: "restorePagePost" }));
  post = await dataOf(`pagePosts/${postId}`);
  assert.equal(post.status, "published");
  assert.equal(post.heldAt, null);
  assert.equal(post.evidenceHold, true, "still under an open report");
  assert.equal((await dataOf(`pages/${pageId}`)).postCount, 1);
  await runModerate(moderatorRequest(moderator, {
    reportId, action: "resolve", resolution: "notAViolation" }));
  report = await dataOf(`reports/${reportId}`);
  assert.equal(report.status, "resolved");
  assert.equal((await dataOf(`pagePosts/${postId}`)).evidenceHold, false);
  const labels = (await db.collection(`users/${pageId}/notifications`).get()).docs
    .map((d) => d.data().targetLabel).sort();
  assert.deepEqual(labels, [
    "Your Page post is hidden while we review it: restricted category",
    "Your Page post is visible again",
  ]);
});

test("Page-only actions are refused on other reports; hold needs a post report", async () => {
  const moderator = await seedModerator();
  const reportId = `rother-${freshUid()}`;
  await db.doc(`reports/${reportId}`).set({
    reporterId: freshUid(), targetType: "user", targetId: freshUid(), reportedUserId: freshUid(),
    contextPath: null, reason: "spam", note: "", status: "open", createdAt: Timestamp.fromMillis(nowMs),
  });
  await expectError(runModerate(moderatorRequest(moderator, { reportId, action: "suspendPage" })),
    "failed-precondition");
  const { pageId, reporter } = await scene();
  const pageReport = await fileReport(reporter, reportInput({ targetType: "page", pageId }));
  await expectError(runModerate(moderatorRequest(moderator, {
    reportId: pageReport, action: "holdPagePost" })), "failed-precondition");
  await expectError(runModerate(moderatorRequest(moderator, {
    reportId: pageReport, action: "suspendPage", moderationReason: "rude" })), "invalid-argument");
});

test("removeAndResolve on a comment: gone with its counter and bell row; the author is told", async () => {
  const { pageId, reporter, postId } = await scene({ postOverrides: { commentCount: 1 } });
  const author = freshUid("rcom");
  await seedAccount(db, author, nowMs);
  const commentId = newCommentId();
  await db.doc(`pagePostComments/${commentId}`).set(commentDoc({ postId, pageId }, commentId, author, nowMs));
  await db.doc(`users/${pageId}/notifications/pagePostComment_${commentId}`).set({
    type: "pagePostComment", sourcePath: `pagePostComments/${commentId}` });
  const reportId = await fileReport(reporter, reportInput({
    targetType: "pagePostComment", pageId, postId, commentId, reason: "harassment" }));
  const moderator = await seedModerator();
  const outcome = await runModerate(moderatorRequest(moderator, {
    reportId, action: "removeAndResolve", resolution: "contentRemoved" }));
  assert.equal(outcome.contentRemoved, true);
  assert.equal(await dataOf(`pagePostComments/${commentId}`), null);
  const post = await dataOf(`pagePosts/${postId}`);
  assert.equal(post.commentCount, 0);
  assert.equal(post.evidenceHold, false);
  assert.equal(await dataOf(`users/${pageId}/notifications/pagePostComment_${commentId}`), null);
  const notice = (await db.collection(`users/${author}/notifications`).get()).docs[0].data();
  assert.equal(notice.targetLabel, "Your comment on a Page was removed: harassment");
  // The words survive in the report.
  assert.equal((await dataOf(`reports/${reportId}`)).targetTextSnapshot, "Looks great!");
});

test("suspend and lift: pages, the visibility index, listed and both notices; lift after resolution", async () => {
  const { pageId, reporter } = await scene();
  const reportId = await fileReport(reporter, reportInput({ targetType: "page", pageId,
    reason: "impersonation" }));
  const moderator = await seedModerator();
  await runModerate(moderatorRequest(moderator, {
    reportId, action: "removeAndResolve", resolution: "contentRemoved" }));
  let page = await dataOf(`pages/${pageId}`);
  assert.equal(page.suspended, true);
  assert.equal(page.suspensionReason, "impersonation");
  assert.equal(page.listed, false);
  assert.equal((await dataOf("pageVisibility/v1")).notViewable[pageId], "suspended");
  // The report is closed; lifting is an appeal outcome and still works.
  const lifted = await runModerate(moderatorRequest(moderator, { reportId, action: "liftPageSuspension" }));
  assert.equal(lifted.status, "resolved", "lift keeps the report's status");
  page = await dataOf(`pages/${pageId}`);
  assert.equal(page.suspended, false);
  assert.equal(page.suspendedAt, null);
  assert.equal(page.listed, true);
  assert.equal((await dataOf("pageVisibility/v1")).notViewable[pageId], undefined);
  const labels = (await db.collection(`users/${pageId}/notifications`).get()).docs
    .map((d) => d.data().targetLabel).sort();
  assert.deepEqual(labels, ["Your Page is no longer suspended", "Your Page was suspended: impersonation"]);
  // Any other closed-report action is still refused.
  await expectError(runModerate(moderatorRequest(moderator, { reportId, action: "suspendPage" })),
    "failed-precondition");
});

test("owner delete while reported leaves a tombstone with held media; the last resolution releases it", async () => {
  const { pageId, reporter, postId, media } = await scene();
  const second = freshUid("rrep");
  await seedAccount(db, second, nowMs);
  const first = await fileReport(reporter, reportInput({ pageId, postId }));
  const other = await fileReport(second, reportInput({ pageId, postId, reason: "hate" }));
  const posts = createPagesPostService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(new FakeBucket({ nowMs: () => nowMs })),
    probeMedia: async () => { throw new Error("unused"); },
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  await posts.managePagePostV1(request(pageId, {
    requestId: `req-${freshUid()}`, postId, op: "delete" }, { verified: false }));
  const tombstone = await dataOf(`pagePosts/${postId}`);
  assert.equal(tombstone.status, "deleted");
  assert.equal(tombstone.text, "Our menu", "the evidence is kept");
  for (const entry of media) {
    assert.equal((await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`)).heldBy, other);
  }
  const moderator = await seedModerator();
  await runModerate(moderatorRequest(moderator, { reportId: first, action: "dismiss",
    resolution: "notAViolation" }));
  for (const entry of media) {
    assert.equal((await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`)).heldBy, other,
      "one report is still open");
  }
  // The second removal finds the owner already removed it, and resolving
  // releases the bytes.
  const outcome = await runModerate(moderatorRequest(moderator, { reportId: other,
    action: "removeAndResolve", resolution: "contentRemoved" }));
  assert.equal(outcome.contentRemoved, true);
  const audit = await db.collection("adminAuditLogs").where("targetId", "==", other).get();
  assert.equal(audit.docs[0].data().details.contentAlreadyRemoved, true);
  for (const entry of media) {
    const job = await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`);
    assert.equal(job.heldBy, null);
    assert.equal(job.nextAttemptAt.toMillis() <= Date.now() + 60_000, true);
  }
  assert.equal((await dataOf(`pagePosts/${postId}`)).evidenceHold, false);
  // The last resolution also makes the tombstone due (audit 2026-09-28): the
  // owner's text, likes and comments do not outlive the review.
  const retention = await dataOf(`pageEvidenceRetention/${postId}`);
  assert.equal(retention.reason, "ownerDelete");
  assert.equal(retention.purgeAt.toMillis() <= Date.now() + 60_000, true);
  const maintenance = createPagesMaintenanceService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(new FakeBucket({ nowMs: () => nowMs })),
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  await maintenance.purgeDueEvidence({ limit: 50 });
  assert.equal(await dataOf(`pagePosts/${postId}`), null, "the tombstone and its text are gone");
  assert.equal(await dataOf(`pageEvidenceRetention/${postId}`), null);
  assert.equal((await dataOf(`pagePostCleanupJobs/${postId}`)).reason, "ownerDelete");
});

test("a hold ends with its review: dismiss or resolve of the last open report restores the post", async () => {
  const { pageId, reporter, postId } = await scene();
  const second = freshUid("rrep");
  await seedAccount(db, second, nowMs);
  const first = await fileReport(reporter, reportInput({ pageId, postId }));
  const other = await fileReport(second, reportInput({ pageId, postId, reason: "hate" }));
  const moderator = await seedModerator();
  await runModerate(moderatorRequest(moderator, { reportId: first, action: "holdPagePost" }));
  assert.equal((await dataOf(`pagePosts/${postId}`)).status, "held");
  assert.equal((await dataOf(`pages/${pageId}`)).postCount, 0);
  // One report still open: the hold stays.
  await runModerate(moderatorRequest(moderator, { reportId: first, action: "dismiss",
    resolution: "notAViolation" }));
  assert.equal((await dataOf(`pagePosts/${postId}`)).status, "held");
  // The last one closes without removal: the post is published again.
  await runModerate(moderatorRequest(moderator, { reportId: other, action: "resolve",
    resolution: "warningIssued" }));
  const post = await dataOf(`pagePosts/${postId}`);
  assert.equal(post.status, "published");
  assert.equal(post.heldAt, null);
  assert.equal(post.evidenceHold, false);
  const page = await dataOf(`pages/${pageId}`);
  assert.equal(page.postCount, 1);
  assert.equal(page.listed, true);
  const labels = (await db.collection(`users/${pageId}/notifications`).get()).docs
    .map((d) => d.data().targetLabel).sort();
  assert.deepEqual(labels, [
    "Your Page post is hidden while we review it: spam",
    "Your Page post is visible again",
  ]);
});

test("REPRO: hold, dismiss, then the owner deletes a held post: nothing is left held forever", async () => {
  const { pageId, reporter, postId, media } = await scene();
  const reportId = await fileReport(reporter, reportInput({ pageId, postId }));
  const moderator = await seedModerator();
  await runModerate(moderatorRequest(moderator, { reportId, action: "holdPagePost" }));
  await runModerate(moderatorRequest(moderator, { reportId, action: "dismiss",
    resolution: "notAViolation" }));
  assert.equal((await dataOf(`pagePosts/${postId}`)).status, "published");
  // Even a legacy held post with no open report left gets UNHELD jobs.
  await db.doc(`pagePosts/${postId}`).update({ status: "held", heldAt: Timestamp.fromMillis(nowMs) });
  const posts = createPagesPostService({
    firestore: db,
    storage: createPagesMediaStorageAdapter(new FakeBucket({ nowMs: () => nowMs })),
    probeMedia: async () => { throw new Error("unused"); },
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  await posts.managePagePostV1(request(pageId, {
    requestId: `req-${freshUid()}`, postId, op: "delete" }, { verified: false }));
  assert.equal((await dataOf(`pagePosts/${postId}`)).status, "deleted");
  for (const entry of media) {
    const job = await dataOf(`pagePostMediaDeletionJobs/${entry.mediaId}`);
    assert.equal(job === null || job.heldBy === null, true, "no job is held by a closed report");
  }
  assert.equal((await dataOf(`pageEvidenceRetention/${postId}`)).reason, "ownerDelete");
});

test("hiding is a safety write: a malformed visibility index never keeps reported content up", async () => {
  const visibilityRef = db.doc("pageVisibility/v1");
  const saved = await visibilityRef.get();
  try {
    await visibilityRef.set({ schemaVersion: 1, broken: true });
    const moderator = await seedModerator();
    // removeAndResolve on a post.
    const one = await scene();
    const removal = await fileReport(one.reporter, reportInput({ pageId: one.pageId, postId: one.postId }));
    await runModerate(moderatorRequest(moderator, { reportId: removal, action: "removeAndResolve",
      resolution: "contentRemoved" }));
    assert.equal((await dataOf(`pagePosts/${one.postId}`)).status, "removed");
    // holdPagePost, then restore fails closed on the broken index.
    const two = await scene();
    const hold = await fileReport(two.reporter, reportInput({ pageId: two.pageId, postId: two.postId }));
    await runModerate(moderatorRequest(moderator, { reportId: hold, action: "holdPagePost" }));
    assert.equal((await dataOf(`pagePosts/${two.postId}`)).status, "held");
    await expectError(runModerate(moderatorRequest(moderator, { reportId: hold,
      action: "restorePagePost" })), "data-loss");
    assert.equal((await dataOf(`pagePosts/${two.postId}`)).status, "held");
    // suspendPage.
    const three = await scene();
    const suspension = await fileReport(three.reporter, reportInput({ targetType: "page",
      pageId: three.pageId, reason: "impersonation" }));
    await runModerate(moderatorRequest(moderator, { reportId: suspension, action: "suspendPage" }));
    assert.equal((await dataOf(`pages/${three.pageId}`)).suspended, true);
  } finally {
    if (saved.exists) await visibilityRef.set(saved.data());
    else await visibilityRef.delete();
  }
});

// --------------------------------------------------------------- script

test("the operator script: owner guard, list, show, media grants with audit, dry run and apply", async () => {
  const { pageId, reporter, postId, media } = await scene();
  const reportId = await fileReport(reporter, reportInput({ pageId, postId, reason: "sexual" }));
  const parse = (argv) => pagesModerationScript.parseArgs(argv);
  assert.throws(() => pagesModerationScript.assertProject(parse(["list"]), null), /--project/);
  assert.throws(() => parse(["--project", "yovoice-ec54a", "nuke", reportId]), /command/);
  assert.throws(() => parse(["--project", "yovoice-ec54a", "remove"]), /reportId/);
  assert.throws(() => parse(["--project", "yovoice-ec54a", "remove", reportId, "--reason", "x"]),
    /--reason/);

  setProtectedOwnerUidForTests(null);
  const previous = process.env.YOVOICE_PROTECTED_OWNER_UID;
  delete process.env.YOVOICE_PROTECTED_OWNER_UID;
  await assert.rejects(pagesModerationScript.run({ db, args: parse(["--project", "yovoice-ec54a", "list"]) }),
    /YOVOICE_PROTECTED_OWNER_UID/);
  const owner = freshUid("rowner");
  setProtectedOwnerUidForTests(owner);
  try {
    const listed = await pagesModerationScript.run({ db, args: parse(["--project", "yovoice-ec54a", "list"]) });
    const row = listed.open.find((entry) => entry.reportId === reportId);
    assert.equal(row.targetTextSnapshot, "Our menu");
    assert.equal(JSON.stringify(listed).includes(reporter), false, "the reporter is never printed");

    const signed = [];
    const storage = { async getSignedReadUrl(path, options) {
      signed.push({ path, ...options });
      return `https://storage.googleapis.com/signed/${signed.length}`;
    } };
    const dry = await pagesModerationScript.run({ db, storage,
      args: parse(["--project", "yovoice-ec54a", "show", reportId, "--media"]) });
    assert.deepEqual(dry.media, media.map((entry) => entry.mediaId));
    assert.equal(signed.length, 0);
    const shown = await pagesModerationScript.run({ db, storage, clock: () => nowMs,
      args: parse(["--project", "yovoice-ec54a", "show", reportId, "--media", "--apply"]) });
    assert.equal(shown.media.length, 2);
    assert.equal(shown.media[0].expiresAtMs, nowMs + 5 * 60 * 1000);
    assert.equal(signed[0].generation, media[0].generation);
    const audits = await db.collection("pageStaffMediaAudit").where("reportId", "==", reportId).get();
    assert.equal(audits.size, 2);
    assert.equal(audits.docs[0].data().staffUid, owner);

    const planned = await pagesModerationScript.run({ db,
      args: parse(["--project", "yovoice-ec54a", "remove", reportId]) });
    assert.match(planned.mode, /DRY RUN/);
    assert.equal((await dataOf(`pagePosts/${postId}`)).status, "published");
    const applied = await pagesModerationScript.run({ db,
      args: parse(["--project", "yovoice-ec54a", "remove", reportId, "--apply"]) });
    assert.equal(applied.outcome.status, "resolved");
    assert.equal((await dataOf(`pagePosts/${postId}`)).status, "removed");
    const audit = await db.collection("adminAuditLogs").where("targetId", "==", reportId).get();
    assert.equal(audit.docs[0].data().actorId, owner);
    assert.equal(audit.docs[0].data().actorRole, "superAdmin");
    // The same function the callable runs.
    assert.equal(typeof handleModerateReport, "function");
  } finally {
    setProtectedOwnerUidForTests(null);
    if (previous !== undefined) process.env.YOVOICE_PROTECTED_OWNER_UID = previous;
  }
});

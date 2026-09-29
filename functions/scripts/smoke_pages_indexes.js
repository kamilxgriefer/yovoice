#!/usr/bin/env node
//
// Read-only index smoke for the Premium Pages reads (ADR-233 §1.12, package
// B3) and the pagesMaintenance worker queries (package B2). A HARD GATE
// between the index deploy and testers mode
// (docs/DEPLOYMENT.md, "Premium Pages"): the emulator serves every query
// without an index, so no local suite can prove a production index exists.
//
//   node scripts/smoke_pages_indexes.js --project yovoice-ec54a \
//     [--page <uid>] [--post <pp_…>]
//
// It runs the EXACT query builders of the read callables
// (pages/reads.js PAGES_READ_QUERIES): the feed chunk (`pageId in`), the
// visitor wall, the owner wall (`status in`), the Zdjęcia tab (visitor and
// owner), a post's comments, Find suggest and Find search; and the worker's
// reservation expiry, media deletion job and post cleanup job queries
// (pages/maintenance.js PAGES_MAINTENANCE_QUERIES); and (B4) the Page post
// likers list through the ADR-230 candidate fetcher itself
// (pages/engagement.js PAGES_ENGAGEMENT_QUERIES + queryCandidateFetcher,
// createdAt desc, __name__ desc: the automatic single-field index); and (B5)
// the hourly lapse sweep (pages/lapse_service.js PAGES_LAPSE_QUERIES, both
// its null-lapsedAt and its timestamp cursor), the account-deletion queries
// (pages/account_deletion.js PAGES_DELETION_QUERIES), the evidence-retention
// slice, the Page report's recent-posts snapshot (pages/reports.js
// PAGES_REPORT_QUERIES) and the operator moderation list; and (ADR-234) the
// follower carry-over worker's due-job and followers queries
// (pages/follow_carry.js PAGE_FOLLOW_CARRY_QUERIES). Each shape runs a
// first page and a startAfter page. The ids need not exist: Firestore
// refuses a query with no serving index with FAILED_PRECONDITION whatever
// the data, so a synthetic id still proves the index. It needs no activation
// document, never writes, and prints counts and PASS/FAIL only (no uid, name
// or document id).

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldPath, Timestamp } = require("firebase-admin/firestore");

const { isValidOpaqueUid } = require("../achievements/identity");
const { PAGE_POST_ID_PATTERN } = require("../pages/contract");
const { PAGES_FEED_QUERY_LIMIT, PAGES_READ_QUERIES } = require("../pages/reads");
const { PAGES_MAINTENANCE_QUERIES } = require("../pages/maintenance");
const { PAGES_ENGAGEMENT_QUERIES } = require("../pages/engagement");
const { queryCandidateFetcher } = require("../engagement/likers_paging");
const { PAGES_LAPSE_QUERIES } = require("../pages/lapse_service");
const { PAGES_DELETION_QUERIES } = require("../pages/account_deletion");
const { PAGE_REPORT_TARGET_TYPES } = require("../pages/report_contract");
const { PAGES_REPORT_QUERIES } = require("../pages/reports");
const { PAGE_FOLLOW_CARRY_QUERIES } = require("../pages/follow_carry");

const EXPECTED_PROJECT = "yovoice-ec54a";
const SYNTHETIC_PAGE = "pages-index-smoke-synthetic";
const SYNTHETIC_POST = `pp_${"0".repeat(40)}`;

function parseArgs(argv) {
  const args = { project: null, page: null, post: null };
  const flags = { "--project": "project", "--page": "page", "--post": "post" };
  for (let index = 0; index < argv.length; index += 1) {
    const key = flags[argv[index]];
    if (key === undefined) throw new Error(`Unknown argument: ${argv[index]}`);
    const value = argv[++index];
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${argv[index - 1]} needs a value.`);
    }
    args[key] = value;
  }
  if (args.page !== null && !isValidOpaqueUid(args.page)) {
    throw new Error("--page is not a valid uid.");
  }
  if (args.post !== null && !PAGE_POST_ID_PATTERN.test(args.post)) {
    throw new Error("--post is not a Page post id.");
  }
  return args;
}

function assertProject(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(
      `--project must be ${EXPECTED_PROJECT} (received: ${args.project ?? "none"}).`,
    );
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error(`Runtime project is ${resolvedProject}, refusing to run against it.`);
  }
}

// First page, then a startAfter page: after the first page's last document
// when there is one, else after synthetic values (same shape, same index).
async function pageTwice(query, syntheticAfter) {
  const first = await query.limit(PAGES_FEED_QUERY_LIMIT).get();
  const next = first.docs.length > 0
    ? query.startAfter(first.docs[first.docs.length - 1])
    : query.startAfter(...syntheticAfter);
  const second = await next.limit(PAGES_FEED_QUERY_LIMIT).get();
  return { firstPage: first.size, secondPage: second.size };
}

// The same two pages through an ADR-230 candidate fetcher (the exact
// production ordering), after a synthetic position when the first is empty.
async function fetchTwice(fetcher, syntheticAfter) {
  const first = await fetcher(null, PAGES_FEED_QUERY_LIMIT);
  const after = first.length > 0 ? first[first.length - 1].position : syntheticAfter;
  const second = await fetcher(after, PAGES_FEED_QUERY_LIMIT);
  return { firstPage: first.length, secondPage: second.length };
}

function smokeTargets(args) {
  const id = FieldPath.documentId();
  const pageId = args.page ?? SYNTHETIC_PAGE;
  const postId = args.post ?? SYNTHETIC_POST;
  const at = Timestamp.fromMillis(Date.now());
  return [
    ["feed chunk (pageId in, status ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.feedChunk(db, id, [pageId]), [at, SYNTHETIC_POST])],
    ["wall visitor (pageId ==, status ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.wall(db, id, pageId, ["published"], "wall"),
        [at, SYNTHETIC_POST])],
    ["wall owner (pageId ==, status in, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.wall(db, id, pageId, ["published", "held"], "wall"),
        [at, SYNTHETIC_POST])],
    ["photos visitor (pageId, status ==, kind ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.wall(db, id, pageId, ["published"], "photos"),
        [at, SYNTHETIC_POST])],
    ["photos owner (pageId, status in, kind ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.wall(db, id, pageId, ["published", "held"], "photos"),
        [at, SYNTHETIC_POST])],
    ["comments (postId ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.comments(db, id, postId), [at, `pc_${"0".repeat(40)}`])],
    ["find suggest (listed ==, lastPostAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_READ_QUERIES.suggest(db, id), [at, SYNTHETIC_PAGE])],
    ["find search (listed ==, nameSearch range, nameSearch asc, __name__ asc)",
      (db) => pageTwice(PAGES_READ_QUERIES.search(db, id, "yo"), ["yo", SYNTHETIC_PAGE])],
    // B2: the pagesMaintenance worker queries.
    ["reservation expiry (expiresAt <=, expiresAt asc)",
      (db) => pageTwice(PAGES_MAINTENANCE_QUERIES.expiredReservations(db, at), [at])],
    ["media deletion jobs (heldBy == null, nextAttemptAt <=, nextAttemptAt asc)",
      (db) => pageTwice(PAGES_MAINTENANCE_QUERIES.dueDeletionJobs(db, at), [at])],
    ["post cleanup jobs (nextAttemptAt <=, nextAttemptAt asc)",
      (db) => pageTwice(PAGES_MAINTENANCE_QUERIES.dueCleanupJobs(db, at), [at])],
    // B4: listPagePostLikersV1's candidates.
    ["post likers (likes: createdAt desc, __name__ desc)",
      (db) => fetchTwice(queryCandidateFetcher({
        query: PAGES_ENGAGEMENT_QUERIES.postLikes(db, postId),
        documentIdField: id,
        toLikerId: () => null,
      }), { createdAt: at, id: SYNTHETIC_PAGE })],
    // B5: the lapse sweep, account deletion, evidence retention, moderation.
    ["lapse sweep active (status ==, lapsedAt asc, __name__ asc; null cursor)",
      (db) => pageTwice(PAGES_LAPSE_QUERIES.byStatus(db, "active"), [null, SYNTHETIC_PAGE])],
    ["lapse sweep readOnly (status ==, lapsedAt asc, __name__ asc)",
      (db) => pageTwice(PAGES_LAPSE_QUERIES.byStatus(db, "readOnly"), [at, SYNTHETIC_PAGE])],
    ["deletion posts (authorId ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_DELETION_QUERIES.authorPosts(db, pageId), [at, SYNTHETIC_POST])],
    ["deletion comments (authorId ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_DELETION_QUERIES.authorComments(db, pageId),
        [at, `pc_${"0".repeat(40)}`])],
    ["deletion media jobs (heldBy == null, storagePath range, storagePath asc)",
      (db) => pageTwice(PAGES_DELETION_QUERIES.unheldJobsUnder(db, pageId),
        [`page_posts/${pageId}/`])],
    ["deletion reservations (ownerId ==)",
      (db) => pageTwice(PAGES_DELETION_QUERIES.ownerReservations(db, pageId).orderBy(id),
        [SYNTHETIC_PAGE])],
    ["deletion budgets (pageId ==)",
      (db) => pageTwice(PAGES_DELETION_QUERIES.pageBudgets(db, pageId).orderBy(id),
        [SYNTHETIC_PAGE])],
    ["evidence retention (purgeAt <=, purgeAt asc)",
      (db) => pageTwice(PAGES_MAINTENANCE_QUERIES.dueEvidenceRetention(db, at), [at])],
    ["page report recent posts (authorId ==, createdAt desc, __name__ desc)",
      (db) => pageTwice(PAGES_REPORT_QUERIES.recentPosts(db, pageId), [at, SYNTHETIC_POST])],
    ["moderation list (reports: targetType in)",
      (db) => pageTwice(db.collection("reports")
        .where("targetType", "in", [...PAGE_REPORT_TARGET_TYPES]).orderBy(id), [SYNTHETIC_PAGE])],
    // ADR-234: the follower carry-over worker.
    ["follow carry-over jobs (nextAttemptAt <=, nextAttemptAt asc)",
      (db) => pageTwice(PAGE_FOLLOW_CARRY_QUERIES.dueJobs(db, at), [at])],
    ["follow carry-over followers (users/{P}/followers, __name__ asc)",
      (db) => pageTwice(PAGE_FOLLOW_CARRY_QUERIES.followers(db, pageId), [SYNTHETIC_PAGE])],
  ];
}

async function smoke({ db, args }) {
  const results = [];
  for (const [label, run] of smokeTargets(args)) {
    try {
      results.push({ query: label, result: "PASS", ...(await run(db)) });
    } catch (error) {
      // FAILED_PRECONDITION (code 9) with an index link is the failure this
      // exists to catch. Only the code and the first line are printed.
      results.push({
        query: label,
        result: "FAIL",
        code: error?.code ?? null,
        message: String(error?.message ?? error).split("\n")[0].slice(0, 300),
      });
    }
  }
  return {
    ok: results.length > 0 && results.every((row) => row.result === "PASS"),
    results,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertProject(args, process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null);
  if (getApps().length === 0) {
    initializeApp({ credential: applicationDefault(), projectId: EXPECTED_PROJECT });
  }
  const report = await smoke({ db: getFirestore(), args });
  console.log("MODE: READ ONLY (no writes)");
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exit(1);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(String(error.message ?? error));
    process.exit(1);
  });
}

module.exports = {
  EXPECTED_PROJECT,
  assertProject,
  parseArgs,
  smoke,
  smokeTargets,
};

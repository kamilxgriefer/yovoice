#!/usr/bin/env node
//
// Tester-phase moderation of Premium Pages (ADR-233 §2.10). The Moderation
// Center does not render Page reports yet (Roadmap 0o gates flipping
// PAGES_ALLOW_PAID_SOURCE, not the tester launch), so the owner works the
// queue from here. Every decision goes through handleModerateReport, the
// SAME function the moderateReport callable runs after its staff check: one
// transaction moves the report, writes the adminAuditLogs row and acts on
// the Page, the post or the comment (functions/pages/moderation.js).
//
//   node scripts/pages_moderation.js --project yovoice-ec54a list
//   node scripts/pages_moderation.js --project yovoice-ec54a show <reportId>
//   node scripts/pages_moderation.js --project yovoice-ec54a show <reportId> --media --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a remove  <reportId> [--reason key] --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a hold    <reportId> [--reason key] --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a restore <reportId> --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a suspend <reportId> [--reason key] --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a lift    <reportId> --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a resolve <reportId> [--resolution key] --apply
//   node scripts/pages_moderation.js --project yovoice-ec54a dismiss <reportId> [--resolution key] --apply
//
// OWNER-GUARDED like backfill_badges.js: YOVOICE_PROTECTED_OWNER_UID must be
// exported (the Secret Manager value); the audit row names that uid with the
// superAdmin role. The project is pinned. Without --apply nothing is written:
// an action prints the report it would act on, and `show` prints the
// snapshot; `show --media --apply` issues 5-minute signed URLs for the
// reported post's media and writes one pageStaffMediaAudit row per URL
// BEFORE printing it. `--reason` is a PAGE_REPORT_REASONS key (default: the
// report's own reason); `--note` is the moderator note.
//
// Output never contains the reporter's uid or e-mail.

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { randomUUID } = require("node:crypto");

const { protectedOwnerUid } = require("../utils/roles");
const {
  PAGE_REPORT_REASONS,
  PAGE_REPORT_TARGET_TYPES,
  canonicalPageReportTarget,
} = require("../pages/report_contract");
const { canonicalPagePostData } = require("../pages/post_contract");

const EXPECTED_PROJECT = "yovoice-ec54a";
const LIST_SCAN_LIMIT = 500;
const MEDIA_URL_TTL_MS = 5 * 60 * 1000;
const COMMANDS = Object.freeze({
  list: null,
  show: null,
  remove: "removeAndResolve",
  hold: "holdPagePost",
  restore: "restorePagePost",
  suspend: "suspendPage",
  lift: "liftPageSuspension",
  resolve: "resolve",
  dismiss: "dismiss",
});
const DEFAULT_RESOLUTIONS = Object.freeze({
  removeAndResolve: "contentRemoved",
  resolve: "warningIssued",
  dismiss: "notAViolation",
});

function parseArgs(argv) {
  const args = {
    project: null,
    command: null,
    reportId: null,
    apply: false,
    media: false,
    reason: null,
    resolution: null,
    note: null,
  };
  const positional = [];
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--project") args.project = argv[++index] ?? null;
    else if (arg === "--apply") args.apply = true;
    else if (arg === "--media") args.media = true;
    else if (arg === "--reason") args.reason = argv[++index] ?? null;
    else if (arg === "--resolution") args.resolution = argv[++index] ?? null;
    else if (arg === "--note") args.note = argv[++index] ?? null;
    else if (arg.startsWith("--")) throw new Error(`Unknown argument: ${arg}`);
    else positional.push(arg);
  }
  [args.command = null, args.reportId = null] = positional;
  if (!Object.prototype.hasOwnProperty.call(COMMANDS, args.command)) {
    throw new Error(`The command must be one of ${Object.keys(COMMANDS).join(", ")}.`);
  }
  if (args.command !== "list" && (typeof args.reportId !== "string" || args.reportId.length === 0)) {
    throw new Error("A reportId is required.");
  }
  if (args.reason !== null && !PAGE_REPORT_REASONS.includes(args.reason)) {
    throw new Error(`--reason must be one of ${PAGE_REPORT_REASONS.join(", ")}.`);
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

function assertOwnerGuard() {
  const owner = protectedOwnerUid();
  if (owner === null) {
    throw new Error("YOVOICE_PROTECTED_OWNER_UID is not set; refusing to moderate without the owner guard.");
  }
  return owner;
}

function millis(value) {
  return typeof value?.toMillis === "function" ? value.toMillis() : null;
}

/// What an operator sees of a report: never the reporter.
function describeReport(id, report) {
  return {
    reportId: id,
    status: report.status ?? "open",
    targetType: report.targetType,
    reason: report.reason,
    note: report.note ?? "",
    pageId: report.pageId ?? null,
    postId: report.postId ?? null,
    commentId: report.commentId ?? null,
    pageKind: report.pageKind ?? null,
    pageDisplayName: report.pageDisplayName ?? null,
    targetPostKind: report.targetPostKind ?? null,
    targetTextSnapshot: report.targetTextSnapshot ?? "",
    targetMedia: Array.isArray(report.targetMedia) ? report.targetMedia : [],
    recentPosts: Array.isArray(report.recentPosts) ? report.recentPosts : [],
    createdAtMs: millis(report.createdAt),
    resolution: report.resolution ?? null,
  };
}

async function listReports(db) {
  const snapshot = await db.collection("reports")
    .where("targetType", "in", [...PAGE_REPORT_TARGET_TYPES])
    .limit(LIST_SCAN_LIMIT)
    .get();
  const open = snapshot.docs
    .map((document) => ({ id: document.id, data: document.data() ?? {} }))
    .filter((entry) => ["open", "inReview", undefined].includes(entry.data.status))
    .map((entry) => describeReport(entry.id, entry.data))
    .sort((a, b) => (a.createdAtMs ?? 0) - (b.createdAtMs ?? 0));
  return { scanned: snapshot.size, truncated: snapshot.size >= LIST_SCAN_LIMIT, open };
}

async function readPageReport(db, reportId) {
  const snapshot = await db.doc(`reports/${reportId}`).get();
  if (!snapshot.exists) throw new Error("That report does not exist.");
  const report = snapshot.data() ?? {};
  if (!PAGE_REPORT_TARGET_TYPES.includes(report.targetType)) {
    throw new Error("That report is not a Page report.");
  }
  canonicalPageReportTarget(report);
  return report;
}

async function showReport({ db, args, owner, storage, clock }) {
  const report = await readPageReport(db, args.reportId);
  const shown = describeReport(args.reportId, report);
  if (!args.media) return { report: shown };
  if (report.targetType !== "pagePost") throw new Error("--media needs a pagePost report.");
  const post = canonicalPagePostData(await db.doc(`pagePosts/${report.postId}`).get());
  if (post === null) return { report: shown, media: [], note: "The post is gone." };
  if (!args.apply) {
    return { report: shown, media: post.media.map((entry) => entry.mediaId), mode: "pass --apply to issue URLs" };
  }
  const nowMs = clock();
  const now = Timestamp.fromMillis(nowMs);
  // The audit rows commit BEFORE any URL exists (the staff-branch rule).
  const batch = db.batch();
  for (const entry of post.media) {
    batch.set(db.collection("pageStaffMediaAudit").doc(), {
      staffUid: owner,
      postId: post.postId,
      mediaId: entry.mediaId,
      reportId: args.reportId,
      at: now,
    });
  }
  await batch.commit();
  const media = [];
  for (const entry of post.media) {
    media.push({
      mediaId: entry.mediaId,
      type: entry.type,
      expiresAtMs: nowMs + MEDIA_URL_TTL_MS,
      url: await storage.getSignedReadUrl(entry.storagePath, {
        expiresAtMs: nowMs + MEDIA_URL_TTL_MS,
        generation: entry.generation,
      }),
    });
  }
  return { report: shown, media };
}

async function moderate({ db, args, owner }) {
  const action = COMMANDS[args.command];
  const report = await readPageReport(db, args.reportId);
  if (!args.apply) {
    return {
      mode: "DRY RUN (pass --apply to act)",
      action,
      report: describeReport(args.reportId, report),
    };
  }
  // Loaded only now: the moderation module resolves Firestore at load.
  const { handleModerateReport } = require("../moderation/reports");
  const resolution = args.resolution ?? DEFAULT_RESOLUTIONS[action] ?? null;
  const outcome = await handleModerateReport(
    { uid: owner, role: "superAdmin", token: { email: null }, email: null },
    {
      reportId: args.reportId,
      requestId: `pm-${randomUUID()}`,
      action,
      resolution,
      moderatorNote: args.note ?? "",
      moderationReason: args.reason,
    },
  );
  return { mode: "APPLIED", action, outcome };
}

async function run({ db, args, storage = null, clock = () => Date.now() }) {
  const owner = assertOwnerGuard();
  if (args.command === "list") return listReports(db);
  if (args.command === "show") {
    return showReport({ db, args, owner, storage: storage ?? defaultStorage(), clock });
  }
  return moderate({ db, args, owner });
}

function defaultStorage() {
  const { defaultPagesMediaDependencies } = require("../pages/media_runtime");
  return defaultPagesMediaDependencies().storage;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertProject(args, process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? null);
  assertOwnerGuard();
  if (getApps().length === 0) {
    initializeApp({
      credential: applicationDefault(),
      projectId: EXPECTED_PROJECT,
      storageBucket: `${EXPECTED_PROJECT}.firebasestorage.app`,
    });
  }
  console.log(JSON.stringify(await run({ db: getFirestore(), args }), null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(String(error.message ?? error));
    process.exit(1);
  });
}

module.exports = {
  COMMANDS,
  EXPECTED_PROJECT,
  assertProject,
  parseArgs,
  run,
};

#!/usr/bin/env node
//
// Read-only index smoke for "See who liked" (ADR-230). A HARD GATE between
// the functions deploy and any client release (docs/DEPLOYMENT.md, "See who
// liked"): the emulator creates indexes on demand, so no local suite can
// prove a production index exists.
//
//   node scripts/smoke_likers_indexes.js --project yovoice-ec54a \
//     --moment <momentId> --reel <reelId> \
//     --moment-comment <momentId>/<commentId> \
//     --reel-comment <reelId>/<commentId> \
//     --viewer <uid>
//
// Every flag except --project is optional, and the ids need not have any
// likes: Firestore refuses a query that has no serving index with
// FAILED_PRECONDITION whatever the data, so an empty target still proves
// the index. Real targets with more than one page of likes additionally prove
// the startAfter tiebreak against production data.
//
// It runs the EXACT query builders of the list callables (the shared
// queryCandidateFetcher over `likes` and `commentLikes`), the comment-like
// view queries (loadCommentLikeStates: counters `commentKey in`, caller edges
// `userId == viewer AND commentKey in`) and the comment-delete purge query.
// It needs no activation document and no Premium account, and it never
// writes. Output is counts and PASS/FAIL per query only: no uid, name or
// document id is printed (a like edge's id IS the liker's uid).

const { getApps, initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldPath, Timestamp } = require("firebase-admin/firestore");

const {
  COMMENT_LIKES_COLLECTION,
  COMMENT_LIKE_PURGE_BATCH_SIZE,
  commentLikeKey,
  loadCommentLikeStates,
} = require("../engagement/comment_likes");
const { LIKERS_CHUNK, queryCandidateFetcher } = require("../engagement/likers_paging");
const { SAFE_ID, isValidOpaqueUid } = require("../integrity/guards");

const EXPECTED_PROJECT = "yovoice-ec54a";

function parseArgs(argv) {
  const args = {
    project: null,
    moment: null,
    reel: null,
    momentComment: null,
    reelComment: null,
    viewer: null,
  };
  const flags = {
    "--project": "project",
    "--moment": "moment",
    "--reel": "reel",
    "--moment-comment": "momentComment",
    "--reel-comment": "reelComment",
    "--viewer": "viewer",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const key = flags[argv[index]];
    if (key === undefined) throw new Error(`Unknown argument: ${argv[index]}`);
    const value = argv[++index];
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${argv[index - 1]} needs a value.`);
    }
    args[key] = value;
  }
  for (const key of ["moment", "reel"]) {
    if (args[key] !== null && !SAFE_ID.test(args[key])) {
      throw new Error(`--${key} is not a safe id.`);
    }
  }
  for (const key of ["momentComment", "reelComment"]) {
    if (args[key] === null) continue;
    const parts = args[key].split("/");
    if (parts.length !== 2 || !parts.every((part) => SAFE_ID.test(part))) {
      throw new Error(`--${key === "momentComment" ? "moment-comment" : "reel-comment"} must be <parentId>/<commentId>.`);
    }
    args[key] = { parentId: parts[0], commentId: parts[1] };
  }
  if (args.viewer !== null && !isValidOpaqueUid(args.viewer)) {
    throw new Error("--viewer is not a valid uid.");
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

// Two pages through the production fetcher. The second page always runs a
// startAfter: after the first page's last edge when there is one, else after
// a synthetic position (the query shape, and so its index, is the same).
async function pageTwice(fetch) {
  const first = await fetch(null, LIKERS_CHUNK);
  const after = first.length > 0
    ? first[first.length - 1].position
    : { createdAt: Timestamp.fromMillis(Date.now()), id: "~" };
  const second = await fetch(after, LIKERS_CHUNK);
  return { firstPage: first.length, secondPage: second.length };
}

function smokeTargets(args) {
  const targets = [];
  const noUid = () => null;
  if (args.moment !== null) {
    targets.push(["voiceMoment likes (createdAt desc, __name__ desc)", (db) =>
      pageTwice(queryCandidateFetcher({
        query: db.collection("voiceMoments").doc(args.moment).collection("likes"),
        documentIdField: FieldPath.documentId(),
        toLikerId: noUid,
      }))]);
  }
  if (args.reel !== null) {
    targets.push(["reel likes (createdAt desc, __name__ desc)", (db) =>
      pageTwice(queryCandidateFetcher({
        query: db.collection("reels").doc(args.reel).collection("likes"),
        documentIdField: FieldPath.documentId(),
        toLikerId: noUid,
      }))]);
  }
  for (const [label, parentKind, target] of [
    ["voiceMomentComment", "voiceMoment", args.momentComment],
    ["reelComment", "reel", args.reelComment],
  ]) {
    if (target === null) continue;
    const commentKey = commentLikeKey(parentKind, target.parentId, target.commentId);
    targets.push([`${label} commentLikes (commentKey, createdAt desc, __name__ desc)`, (db) =>
      pageTwice(queryCandidateFetcher({
        query: db.collection(COMMENT_LIKES_COLLECTION).where("commentKey", "==", commentKey),
        documentIdField: FieldPath.documentId(),
        toLikerId: noUid,
      }))]);
    targets.push([`${label} purge (commentKey ==)`, async (db) => {
      const snapshot = await db.collection(COMMENT_LIKES_COLLECTION)
        .where("commentKey", "==", commentKey)
        .limit(COMMENT_LIKE_PURGE_BATCH_SIZE)
        .get();
      return { edges: snapshot.size };
    }]);
    if (args.viewer !== null) {
      targets.push([`${label} view state (counters in; userId, commentKey in)`, async (db) => {
        const states = await loadCommentLikeStates({
          db,
          parentKind,
          parentId: target.parentId,
          commentIds: [target.commentId],
          viewerId: args.viewer,
        });
        const state = states[target.commentId];
        return { likeCount: state.likeCount, callerLiked: state.callerLiked };
      }]);
    }
  }
  return targets;
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
};

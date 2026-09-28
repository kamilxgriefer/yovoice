// appConfig/pagesV1, the Premium Pages kill switch (ADR-233 §2.1), and the
// operator script that writes it. The parser runs pure; the reads, the
// script and the safety-action matrix run against the Firestore emulator.
const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-pages-activation-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  PAGES_ACTIVATION_PATH,
  PAGES_DISABLED_ACTIVATION,
  PAGES_SAFETY_ACTIONS,
  assertPagesReadEnabled,
  assertPagesWriteEnabled,
  canonicalPagesActivation,
  pagesReadAllowed,
  pagesWriteAllowed,
  readPagesActivation,
} = require("../pages/activation");
const activationScript = require("../scripts/set_pages_activation");
const { createPagesLifecycleService } = require("../pages/lifecycle");
const { createProfileVisibilityService } = require("../profile/profile_visibility");
const {
  clearActivation,
  createInput,
  freshUid,
  pageDoc,
  pagesActivation,
  request,
  seedOwner,
  setActivation,
  silentLogger,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const NOW_MS = 1_900_000_000_000;
const snapshot = (data) => ({ exists: data !== null, data: () => data });

beforeEach(() => clearActivation(db));
after(() => clearActivation(db));

test("only the exact document enables anything; everything else is disabled", () => {
  assert.deepEqual(canonicalPagesActivation(snapshot(null)), PAGES_DISABLED_ACTIVATION);
  assert.equal(PAGES_DISABLED_ACTIVATION.lapseEnabled, false);
  const exact = canonicalPagesActivation(snapshot(pagesActivation()));
  assert.equal(exact.readAccess, "all");
  assert.equal(exact.writeAccess, "all");
  assert.equal(exact.lapseEnabled, true);
  const malformed = [
    { extra: true },
    { schemaVersion: 2 },
    { readAccess: "everyone" },
    { writeAccess: true },
    { lapseEnabled: "true" },
    { revision: 0 },
    { revision: 1.5 },
    { testerUids: "uid" },
    { readAccess: "testers", writeAccess: "testers", testerUids: ["a", "a"] },
    { readAccess: "testers", writeAccess: "testers", testerUids: ["a/b"] },
    { readAccess: "testers", writeAccess: "testers",
      testerUids: Array.from({ length: 101 }, (_, i) => `t${i}`) },
    { testerUids: ["a"] }, // tester uids outside tester mode
    { readAccess: "testers", writeAccess: "all", testerUids: ["a"] }, // write wider than read
    { readAccess: "disabled", writeAccess: "testers", testerUids: ["a"] },
  ];
  for (const overrides of malformed) {
    const data = { ...pagesActivation(), ...overrides };
    assert.deepEqual(canonicalPagesActivation(snapshot(data)), PAGES_DISABLED_ACTIVATION,
      JSON.stringify(overrides));
  }
  const { revision: _dropped, ...missing } = pagesActivation();
  assert.deepEqual(canonicalPagesActivation(snapshot(missing)), PAGES_DISABLED_ACTIVATION);
});

test("tester mode admits exactly the listed uids; read-only mode refuses writes", () => {
  const testers = canonicalPagesActivation(snapshot(pagesActivation({
    readAccess: "testers",
    writeAccess: "testers",
    testerUids: ["alice"],
  })));
  assert.equal(pagesReadAllowed(testers, "alice"), true);
  assert.equal(pagesWriteAllowed(testers, "alice"), true);
  assert.equal(pagesReadAllowed(testers, "bob"), false);
  const readAllWriteTesters = canonicalPagesActivation(snapshot(pagesActivation({
    readAccess: "all",
    writeAccess: "testers",
    testerUids: ["alice"],
  })));
  assert.equal(pagesReadAllowed(readAllWriteTesters, "bob"), true);
  assert.equal(pagesWriteAllowed(readAllWriteTesters, "bob"), false);
  assert.equal(pagesWriteAllowed(readAllWriteTesters, "alice"), true);
  const readOnly = canonicalPagesActivation(snapshot(pagesActivation({ writeAccess: "disabled" })));
  assert.equal(pagesReadAllowed(readOnly, "bob"), true);
  assert.equal(pagesWriteAllowed(readOnly, "bob"), false);
  // A hand-built object cannot write wider than it reads.
  assert.equal(pagesWriteAllowed({ readAccess: "disabled", writeAccess: "all", testerUids: [] }, "bob"), false);
});

test("reads are uncached; a missing or unreadable document is pagesNotEnabled", async () => {
  await assert.rejects(
    assertPagesReadEnabled({ db, uid: "u1" }),
    (error) => error.code === "failed-precondition" &&
      error.details?.reason === "pagesNotEnabled" &&
      error.message === "Pages are not available yet.",
  );
  await setActivation(db);
  await assertPagesReadEnabled({ db, uid: "u1" });
  await assertPagesWriteEnabled({ db, uid: "u1" });
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });
  await assert.rejects(assertPagesReadEnabled({ db, uid: "u1" }), /not available/);

  const logger = silentLogger();
  const broken = { doc: () => ({ get: async () => { throw Object.assign(new Error("x"), { code: 14 }); } }) };
  assert.deepEqual(await readPagesActivation({ db: broken, logger }), PAGES_DISABLED_ACTIVATION);
  assert.equal(logger.entries[0].args[0], "pages activation unreadable");

  await db.doc(PAGES_ACTIVATION_PATH).set({ ...pagesActivation(), extra: 1 });
  const malformedLogger = silentLogger();
  assert.deepEqual(await readPagesActivation({ db, logger: malformedLogger }), PAGES_DISABLED_ACTIVATION);
  assert.deepEqual(malformedLogger.entries[0].args, ["pages activation malformed", { reason: "keys" }]);
});

test("the operator script plans, writes exactly, bumps the revision and reads back", async () => {
  assert.throws(() => activationScript.parseArgs(["--read", "all"]), /required/);
  assert.throws(() => activationScript.parseArgs(["--read", "x", "--write", "all", "--lapse", "true"]), /--read/);
  assert.throws(() => activationScript.assertProject({ project: "other" }, null), /--project/);
  const args = activationScript.parseArgs([
    "--project", "yovoice-ec54a", "--read", "testers", "--write", "testers",
    "--testers", "alice, bob", "--lapse", "true",
  ]);
  const dry = await activationScript.run({ db, args });
  assert.match(dry.mode, /READ ONLY/);
  assert.equal((await db.doc(PAGES_ACTIVATION_PATH).get()).exists, false);

  const applied = await activationScript.run({ db, args: { ...args, apply: true } });
  assert.equal(applied.mode, "APPLIED");
  assert.deepEqual((await db.doc(PAGES_ACTIVATION_PATH).get()).data(), {
    schemaVersion: 1,
    readAccess: "testers",
    writeAccess: "testers",
    testerUids: ["alice", "bob"],
    lapseEnabled: true,
    revision: 1,
  });
  const again = await activationScript.run({ db, args: { ...args, apply: true } });
  assert.equal(again.after.revision, 2);

  await assert.rejects(
    activationScript.run({ db, args: { ...args, writeAccess: "all", apply: true } }),
    /invalid \(writeWiderThanRead\)/,
  );
});

// The B1 half of the §2.1 safety matrix: with readAccess "disabled" an owner
// can still pause, and anybody can still make their profile private (which
// pauses their Page). Every other Pages op answers pagesNotEnabled.
test("with the kill switch on, pause and go-private still work", async () => {
  assert.ok(PAGES_SAFETY_ACTIONS.includes("managePageV1.pause"));
  assert.ok(PAGES_SAFETY_ACTIONS.includes("setMyProfileVisibility"));
  const nowMs = NOW_MS;
  const lifecycle = createPagesLifecycleService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  const visibility = createProfileVisibilityService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
  });
  const first = freshUid("pgact");
  const second = freshUid("pgact");
  for (const uid of [first, second]) {
    await seedOwner(db, uid, { nowMs });
    await db.doc(`pages/${uid}`).set(pageDoc(uid, nowMs));
  }
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });

  for (const data of [
    createInput(),
    { requestId: "req-update-1", op: "update", category: "shop", description: "",
      business: createInput().business, community: null },
    { requestId: "req-resume-1", op: "resume" },
  ]) {
    await assert.rejects(
      lifecycle.managePageV1(request(first, data)),
      (error) => error.details?.reason === "pagesNotEnabled",
      data.op,
    );
  }

  const paused = await lifecycle.managePageV1(request(first, { requestId: "req-pause-1", op: "pause" }));
  assert.deepEqual(paused, { pageId: first, kind: "business", status: "active", ownerPaused: true });
  assert.equal((await db.doc(`pages/${first}`).get()).data().ownerPaused, true);

  const privateResult = await visibility.setMyProfileVisibility({
    auth: { uid: second, token: {} },
    data: { visibility: "private" },
  });
  assert.deepEqual(privateResult, { visibility: "private", changed: true });
  assert.equal((await db.doc(`pages/${second}`).get()).data().ownerPaused, true);
  const index = (await db.doc("pageVisibility/v1").get()).data();
  assert.equal(index.notViewable[first], "paused");
  assert.equal(index.notViewable[second], "paused");
});

// The B3 half: with readAccess "disabled" every read callable answers
// pagesNotEnabled, a follow of a Page is refused like any follow of an
// account that takes no followers, and an UNFOLLOW still works (a safety
// action: setFollow never reads the switch on that path).
test("with the kill switch on, reads are off and unfollow still works", async () => {
  assert.ok(PAGES_SAFETY_ACTIONS.includes("setFollow.unfollow"));
  const { createPagesReadService } = require("../pages/reads");
  const { setFollow } = require("../friends/social_graph");
  const runFollow = setFollow.run ?? setFollow;
  const nowMs = Date.now();
  const reads = createPagesReadService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  const owner = freshUid("pgact");
  const viewer = freshUid("pgact");
  await seedOwner(db, owner, { nowMs });
  await db.doc(`pages/${owner}`).set(pageDoc(owner, nowMs));
  await seedOwner(db, viewer, { nowMs, grant: null });
  await setActivation(db);
  assert.equal((await runFollow(request(viewer, { targetUserId: owner, following: true })))
    .changed, true);

  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });
  for (const [name, data] of [
    ["getPagesFeedV1", { cursor: null }],
    ["getPageV1", { pageId: owner, tab: "wall", cursor: null }],
    ["getPagePostV1", { postId: `pp_${"a".repeat(40)}`, commentCursor: null }],
    ["findPagesV1", { mode: "suggest", query: null, cursor: null }],
  ]) {
    await assert.rejects(reads[name](request(viewer, data)),
      (error) => error.details?.reason === "pagesNotEnabled", name);
  }
  assert.deepEqual(
    await runFollow(request(viewer, { targetUserId: owner, following: false })),
    { changed: true, following: false },
  );
  await assert.rejects(runFollow(request(viewer, { targetUserId: owner, following: true })),
    (error) => error.code === "failed-precondition");
});

// The B2 half: with readAccess "disabled" reserve, publish, pin and the media
// grants answer pagesNotEnabled, and an owner's post DELETE still works — a
// safety action that never reads the switch, allowed while muted and
// unverified.
test("with the kill switch on, posting is off and an owner's delete still works", async () => {
  assert.ok(PAGES_SAFETY_ACTIONS.includes("managePagePostV1.delete"));
  const { createPagesPostService } = require("../pages/posts");
  const { createPagesMediaAccessService } = require("../pages/media_access");
  const { createPagesMediaStorageAdapter } = require("../pages/media_storage");
  const { FakeBucket } = require("./helpers/pages_media_fixture");
  const { newPostId, postDoc } = require("./helpers/pages_fixture");
  const nowMs = Date.now();
  const storage = createPagesMediaStorageAdapter(new FakeBucket({ nowMs: () => nowMs }));
  const posts = createPagesPostService({
    firestore: db,
    storage,
    probeMedia: async () => { throw new Error("never probed"); },
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
  });
  const access = createPagesMediaAccessService({
    firestore: db, storage, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
  const owner = freshUid("pgact");
  await seedOwner(db, owner, { nowMs, mute: true });
  await db.doc(`pages/${owner}`).set(pageDoc(owner, nowMs, { postCount: 1, listed: true }));
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(owner, postId, nowMs));
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });

  for (const [name, data] of [
    ["reservePagePostMediaV1", { requestId: "req-reserve-1", kind: "photo", items: [{
      index: 0, contentType: "image/jpeg", size: 1000, width: 1, height: 1, durationMs: null,
    }] }],
    ["publishPagePostV1", { requestId: "req-publish-1", postId: null, kind: "text",
      text: "Hi", mediaIds: [], commentsEnabled: true }],
    ["managePagePostV1", { requestId: "req-pin-1", postId, op: "pin" }],
  ]) {
    await assert.rejects(posts[name](request(owner, data)),
      (error) => error.details?.reason === "pagesNotEnabled", name);
  }
  await assert.rejects(access.getPagePostMediaAccessV1(request(owner,
    { postId, mediaIds: [`pm_${"a".repeat(40)}`] })),
  (error) => error.details?.reason === "pagesNotEnabled");

  const deleted = await posts.managePagePostV1(request(owner,
    { requestId: "req-delete-1", postId, op: "delete" }, { verified: false }));
  assert.equal(deleted.deleted, true);
  assert.equal((await db.doc(`pagePosts/${postId}`).get()).exists, false);
  assert.equal((await db.doc(`pages/${owner}`).get()).data().postCount, 0);
});

// The B4 half: with readAccess "disabled" like, unlike, comment and the
// likers list answer pagesNotEnabled, and a comment DELETE (author or Page
// owner) still works — a safety action that never reads the switch, allowed
// while muted and unverified.
test("with the kill switch on, engagement is off and a comment delete still works", async () => {
  assert.ok(PAGES_SAFETY_ACTIONS.includes("pagePostEngagementV1.deleteComment"));
  const { createPagesEngagementService } = require("../pages/engagement");
  const { commentDoc, newCommentId, newPostId, postDoc, seedAccount } =
    require("./helpers/pages_fixture");
  const nowMs = Date.now();
  const engagement = createPagesEngagementService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    logger: silentLogger(),
    authAdmin: { getUser: async () => { throw new Error("never read"); } },
  });
  const owner = freshUid("pgact");
  const visitor = freshUid("pgact");
  await seedOwner(db, owner, { nowMs, mute: true });
  await db.doc(`pages/${owner}`).set(pageDoc(owner, nowMs, { postCount: 1, listed: true }));
  await seedAccount(db, visitor, nowMs);
  const postId = newPostId();
  const post = postDoc(owner, postId, nowMs, { commentCount: 2 });
  await db.doc(`pagePosts/${postId}`).set(post);
  const byVisitor = newCommentId();
  const other = newCommentId();
  await db.doc(`pagePostComments/${byVisitor}`).set(commentDoc(post, byVisitor, visitor, nowMs));
  await db.doc(`pagePostComments/${other}`).set(commentDoc(post, other, visitor, nowMs));
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled" });

  for (const data of [
    { requestId: "req-like-1", op: "like", postId },
    { requestId: "req-unlike-1", op: "unlike", postId },
    { requestId: "req-comment-1", op: "comment", postId, text: "Hi" },
  ]) {
    await assert.rejects(engagement.pagePostEngagementV1(request(visitor, data)),
      (error) => error.details?.reason === "pagesNotEnabled", data.op);
  }
  await assert.rejects(engagement.listPagePostLikersV1(request(visitor, { postId, cursor: null })),
    (error) => error.details?.reason === "pagesNotEnabled");

  await engagement.pagePostEngagementV1(request(visitor,
    { requestId: "req-delete-1", op: "deleteComment", commentId: byVisitor }, { verified: false }));
  await engagement.pagePostEngagementV1(request(owner,
    { requestId: "req-delete-2", op: "deleteComment", commentId: other }, { verified: false }));
  assert.equal((await db.doc(`pagePostComments/${byVisitor}`).get()).exists, false);
  assert.equal((await db.doc(`pagePostComments/${other}`).get()).exists, false);
  assert.equal((await db.doc(`pagePosts/${postId}`).get()).data().commentCount, 0);
});

// Package B5: a report is a safety action (no switch read, unverified and
// muted allowed), and lapseEnabled false freezes every downgrade while a
// restore still runs.
test("with the kill switch on, reporting still works and the lapse brake only restores", async () => {
  assert.ok(PAGES_SAFETY_ACTIONS.includes("createPageReportV1"));
  const { createPagesReportService } = require("../pages/reports");
  const { createPagesLapseService } = require("../pages/lapse_service");
  const { newPostId, postDoc, seedAccount, testerGrant } = require("./helpers/pages_fixture");
  const nowMs = Date.now();
  const owner = freshUid("pgact");
  const reporter = freshUid("pgact");
  await seedOwner(db, owner, { nowMs });
  await db.doc(`pages/${owner}`).set(pageDoc(owner, nowMs, { postCount: 1, listed: true }));
  await seedAccount(db, reporter, nowMs);
  await db.doc(`restrictions/${reporter}`).set({ type: "communicationMute", expiresAt: null });
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(owner, postId, nowMs));
  await setActivation(db, { readAccess: "disabled", writeAccess: "disabled", lapseEnabled: false });

  const reports = createPagesReportService({
    firestore: db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
  const filed = await reports.createPageReportV1(request(reporter, {
    requestId: `req-${freshUid()}`, targetType: "pagePost", pageId: owner, postId,
    commentId: null, reason: "spam", note: null,
  }, { verified: false }));
  assert.equal(filed.created, true);
  assert.equal((await db.doc(`pagePosts/${postId}`).get()).data().evidenceHold, true);

  const lapse = createPagesLapseService({
    firestore: db, TimestampImpl: Timestamp, clock: () => nowMs, logger: silentLogger(),
  });
  await db.doc(`vipGrants/${owner}`).set(testerGrant({ revoked: true }));
  assert.deepEqual(await lapse.reconcilePage(owner), { outcome: "frozen" });
  assert.equal((await db.doc(`pages/${owner}`).get()).data().status, "active");
  await db.doc(`pages/${owner}`).update({ status: "readOnly", lapsedAt: Timestamp.fromMillis(nowMs - 1000),
    listed: false });
  await db.doc(`vipGrants/${owner}`).set(testerGrant());
  assert.deepEqual(await lapse.reconcilePage(owner), { outcome: "restored" });
});

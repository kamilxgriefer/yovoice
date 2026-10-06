/**
 * "A Page you follow published a post" (ADR-237): the source validator, the
 * paged fan-out outbox, the bell row's exact shape and the per-Page daily
 * push cap. Runs against the Firestore emulator, like every other
 * notification suite:
 *
 *   firebase emulators:exec --only firestore --project demo-yovoice \
 *     "cd functions && node --test --test-concurrency=1 test/page_post_notifications.test.js"
 */
const assert = require("node:assert/strict");
const { after, before, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { PAGES_ACTIVATION_PATH } = require("../pages/activation");
const { pageBudgetDay } = require("../pages/media_contract");
const {
  CANONICAL_NOTIFICATION_KEYS,
  createNotificationForEvent,
  eventLedgerReference,
} = require("../notifications/canonical");
const {
  ENGAGEMENT_NOTIFICATION_TYPES,
  pagePostPublishedSourceIsCurrent,
} = require("../notifications/engagement_source");
const {
  PAGE_POST_FOLLOWER_PAGE_SIZE,
  PAGE_POST_NOTIFICATION_TYPE,
  PAGE_POST_OUTBOX_RETENTION_MS,
  PAGE_POST_RETRY_WINDOW_MS,
  ensurePagePostFanoutOutbox,
  handlePagePostCreated,
  handlePagePostFanoutOutboxWritten,
  pagePostEventId,
  pagePostFanoutOutboxReference,
  pagePostNotificationId,
  pagePostPreview,
  pagePostTargetLabel,
  processPagePostFanoutOutbox,
} = require("../notifications/page_posts");
const {
  PAGE_POST_PUSH_CAP_SKIP_REASON,
  PUSH_TITLES,
  handleNotificationCreated,
  pagePostPushCapDay,
  pagePostPushCapReference,
  pushPreferenceDisabled,
} = require("../notifications/push");
const {
  documentGeneration,
  isRegisteredNotificationType,
  notificationSourceIsCurrent,
} = require("../notifications/social_source");
const {
  freshUid,
  newPostId,
  pagesActivation,
  photoMedia,
  postDoc,
  seedAccount,
  seedFollowEdge,
  seedPage,
} = require("./helpers/pages_fixture");

const NOW = Date.now();
let previousActivation = null;

before(async () => {
  const snapshot = await db.doc(PAGES_ACTIVATION_PATH).get();
  previousActivation = snapshot.exists ? snapshot.data() : null;
  await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation());
});

after(async () => {
  if (previousActivation) {
    await db.doc(PAGES_ACTIVATION_PATH).set(previousActivation);
  } else {
    await db.doc(PAGES_ACTIVATION_PATH).delete();
  }
});

/** A running Page with one published post and `followers` followers. */
async function scene({ followers = 1, post = {}, page = {} } = {}) {
  const pageId = freshUid("pg");
  const postId = newPostId();
  await seedPage(db, pageId, NOW, {
    page: { displayName: "Pracownia Glina", ...page },
    user: { displayName: "Pracownia Glina" },
  });
  await db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, NOW, {
    text: "Nowe kubki już w pracowni",
    ...(typeof post === "function" ? post(pageId, postId) : post),
  }));
  const followerIds = [];
  for (let index = 0; index < followers; index += 1) {
    const followerId = freshUid("fl");
    followerIds.push(followerId);
    await seedAccount(db, followerId, NOW, { displayName: `Follower ${index}` });
    await seedFollowEdge(db, followerId, pageId, NOW);
  }
  const snapshot = await db.doc(`pagePosts/${postId}`).get();
  return {
    pageId,
    postId,
    followerIds,
    snapshot,
    sourceGeneration: documentGeneration(snapshot, "createTime"),
  };
}

function rowShape(current) {
  return {
    type: PAGE_POST_NOTIFICATION_TYPE,
    actorId: current.pageId,
    targetId: current.postId,
    sourcePath: `pagePosts/${current.postId}`,
    sourceGeneration: current.sourceGeneration,
  };
}

function validate(current, recipientId, overrides = {}) {
  return pagePostPublishedSourceIsCurrent({
    recipientId,
    notification: { ...rowShape(current), ...overrides },
    reader: db,
    firestore: db,
  });
}

function postCreatedEvent(current, time = new Date().toISOString()) {
  return { id: `evt-${current.postId}`, time, params: { postId: current.postId }, data: current.snapshot };
}

async function outboxEvent(reference) {
  const snapshot = await reference.get();
  return { params: { outboxId: reference.id }, data: { after: snapshot } };
}

/** Drives the outbox trigger the way Eventarc does: once per committed write. */
async function drain(reference, options = {}) {
  const runs = [];
  for (let guard = 0; guard < 20; guard += 1) {
    const result = await handlePagePostFanoutOutboxWritten(
      await outboxEvent(reference),
      options,
    );
    if (result === null) break;
    runs.push(result);
  }
  return runs;
}

// ------------------------------------------------------------- registry

test("the type is registered, has a title and its own preference key", () => {
  assert.equal(PAGE_POST_NOTIFICATION_TYPE, "pagePostPublished");
  assert.ok(ENGAGEMENT_NOTIFICATION_TYPES.includes("pagePostPublished"));
  assert.equal(isRegisteredNotificationType("pagePostPublished"), true);
  assert.equal(PUSH_TITLES.pagePostPublished("Pracownia Glina"),
    "Pracownia Glina published a post");
  // A separate switch: only its own key silences it, and it silences nothing
  // else. Absent means on (the opt-out model of every other switch).
  assert.equal(pushPreferenceDisabled({}, "pagePostPublished"), false);
  assert.equal(pushPreferenceDisabled(undefined, "pagePostPublished"), false);
  assert.equal(pushPreferenceDisabled({ pagePostPublished: false }, "pagePostPublished"), true);
  assert.equal(pushPreferenceDisabled({ liveStarted: false }, "pagePostPublished"), false);
  assert.equal(pushPreferenceDisabled({ momentComment: false }, "pagePostPublished"), false);
  assert.equal(pushPreferenceDisabled({ pagePostPublished: false }, "liveStarted"), false);
});

test("preview and old-client label are bounded and attribution-first", () => {
  assert.equal(pagePostPreview("  Nowe kubki\n\njuż w   pracowni "), "Nowe kubki już w pracowni");
  assert.equal(pagePostPreview(""), "");
  assert.equal(pagePostPreview(null), "");
  const long = pagePostPreview("a".repeat(500));
  assert.equal(Array.from(long).length, 120);
  assert.ok(long.endsWith("…"));
  // Bidi and zero-width controls never reach a lock screen.
  assert.equal(pagePostPreview("Hej‮​świat"), "Hej świat");
  // A whole emoji is never cut in half.
  const emoji = pagePostPreview("🎉".repeat(200));
  assert.equal(Array.from(emoji).length, 120);
  assert.equal(emoji.isWellFormed(), true);

  assert.equal(pagePostTargetLabel("Pracownia Glina"),
    "New post from a Page you follow: Pracownia Glina");
  assert.equal(pagePostTargetLabel("  "), "New post from a Page you follow: a Page");
  const impostor = pagePostTargetLabel(`YO Voice: your account is suspended, tap here ${"!".repeat(80)}`);
  assert.ok(impostor.startsWith("New post from a Page you follow: "));
  assert.ok(impostor.length <= 120);
});

// ------------------------------------------------------------ validator

test("validator: a follower of a running Page with a published post", async () => {
  const current = await scene();
  const [follower] = current.followerIds;
  assert.equal(await validate(current, follower), true);
  // The shared registry reaches the same validator.
  assert.equal(await notificationSourceIsCurrent({
    recipientId: follower,
    notificationId: pagePostNotificationId(current.postId),
    notification: rowShape(current),
    firestore: db,
  }), true);
  // Inside a transaction too (the writer and the push claim both use one).
  assert.equal(await db.runTransaction((transaction) =>
    pagePostPublishedSourceIsCurrent({
      recipientId: follower,
      notification: rowShape(current),
      reader: transaction,
      firestore: db,
    })), true);
});

test("validator: malformed rows are refused before any read", async () => {
  const neverRead = {
    doc: () => {
      throw new Error("a malformed row must never read Firestore");
    },
    getAll: () => {
      throw new Error("a malformed row must never read Firestore");
    },
  };
  const good = {
    type: "pagePostPublished",
    actorId: "page-owner",
    targetId: `pp_${"a".repeat(40)}`,
    sourcePath: `pagePosts/pp_${"a".repeat(40)}`,
    sourceGeneration: "1:2",
  };
  const cases = [
    { ...good, targetId: "not-a-post" },
    { ...good, sourcePath: "pagePosts/pp_other" },
    { ...good, sourcePath: undefined },
    { ...good, actorId: "" },
    { ...good, actorId: "a/b" },
  ];
  for (const notification of cases) {
    assert.equal(await pagePostPublishedSourceIsCurrent({
      recipientId: "follower",
      notification,
      reader: neverRead,
      firestore: neverRead,
    }), false, JSON.stringify(notification));
  }
  // The Page never notifies itself.
  assert.equal(await pagePostPublishedSourceIsCurrent({
    recipientId: "page-owner",
    notification: good,
    reader: neverRead,
    firestore: neverRead,
  }), false);
});

test("validator: post gone, held, or another generation", async () => {
  const current = await scene();
  const [follower] = current.followerIds;
  assert.equal(await validate(current, follower, { sourceGeneration: "1:1" }), false);
  assert.equal(await validate(current, follower, { sourceGeneration: undefined }), false);
  const post = db.doc(`pagePosts/${current.postId}`);
  await post.update({ status: "held", heldAt: Timestamp.fromMillis(NOW) });
  assert.equal(await validate(current, follower), false);
  await post.update({ status: "published", heldAt: null });
  assert.equal(await validate(current, follower), true);
  await post.delete();
  assert.equal(await validate(current, follower), false);
});

test("validator: the Page must still be running", async () => {
  for (const change of [
    { ownerPaused: true },
    {
      suspended: true,
      suspendedAt: Timestamp.fromMillis(NOW),
      suspensionReason: "spam",
    },
    { status: "hidden", lapsedAt: Timestamp.fromMillis(NOW - 40 * 86_400_000), listed: false },
  ]) {
    const current = await scene();
    const [follower] = current.followerIds;
    assert.equal(await validate(current, follower), true);
    await db.doc(`pages/${current.pageId}`).update(change);
    assert.equal(await validate(current, follower), false, JSON.stringify(Object.keys(change)));
  }
  const gone = await scene();
  await db.doc(`pages/${gone.pageId}`).delete();
  assert.equal(await validate(gone, gone.followerIds[0]), false);
  const banned = await scene();
  await db.doc(`users/${banned.pageId}`).update({ banned: true });
  assert.equal(await validate(banned, banned.followerIds[0]), false);
});

test("validator: follow edge, blocks, mutes and the recipient's account", async () => {
  const current = await scene({ followers: 6 });
  const [unfollowed, blocksPage, blockedByPage, muted, disabled, stranger] = current.followerIds;
  for (const id of current.followerIds) assert.equal(await validate(current, id), true, id);

  await db.doc(`users/${unfollowed}/following/${current.pageId}`).delete();
  assert.equal(await validate(current, unfollowed), false);

  await db.doc(`users/${blocksPage}/blocked/${current.pageId}`).set({ at: NOW });
  assert.equal(await validate(current, blocksPage), false);

  await db.doc(`users/${current.pageId}/blocked/${blockedByPage}`).set({ at: NOW });
  assert.equal(await validate(current, blockedByPage), false);

  await db.doc(`restrictions/${muted}`).set({ type: "communicationMute", expiresAt: null });
  assert.equal(await validate(current, muted), false);

  await db.doc(`users/${disabled}`).update({ disabled: true });
  assert.equal(await validate(current, disabled), false);

  // An edge that names somebody else is not a follow of this Page.
  await db.doc(`users/${stranger}/following/${current.pageId}`).set({ uid: "someone-else" });
  assert.equal(await validate(current, stranger), false);

  // Somebody who never followed at all.
  const outsider = freshUid("out");
  await seedAccount(db, outsider, NOW);
  assert.equal(await validate(current, outsider), false);
});

test("validator: the Pages kill switch and tester mode silence it", async () => {
  const current = await scene({ followers: 2 });
  const [tester, other] = current.followerIds;
  try {
    await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation({
      readAccess: "disabled",
      writeAccess: "disabled",
    }));
    assert.equal(await validate(current, tester), false);
    await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation({
      readAccess: "testers",
      writeAccess: "testers",
      testerUids: [tester],
    }));
    assert.equal(await validate(current, tester), true);
    assert.equal(await validate(current, other), false);
    await db.doc(PAGES_ACTIVATION_PATH).delete();
    assert.equal(await validate(current, tester), false);
  } finally {
    await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation());
  }
});

// ------------------------------------------------- additive row fields

test("extraFields can add, never override, and are validated before any read", async () => {
  const neverRead = {
    doc: () => ({}),
    runTransaction: () => {
      throw new Error("a refused extraFields must never open a transaction");
    },
  };
  const base = {
    eventId: "extra-fields-probe",
    recipientId: "recipient",
    actorId: "actor",
    type: "pagePostPublished",
    notificationId: "row",
    firestore: neverRead,
  };
  for (const extraFields of [
    ...CANONICAL_NOTIFICATION_KEYS.map((key) => ({ [key]: "x" })),
    { pushDeliveryStatus: "sent" },
    { pushClaimEventId: "forged" },
    { "bad key": "x" },
    { Upper: "x" },
    { postPreview: "" },
    { postPreview: "x".repeat(241) },
    { postPreview: 7 },
    { postPreview: { nested: true } },
    ["array"],
    "string",
  ]) {
    await assert.rejects(
      createNotificationForEvent({ ...base, extraFields }),
      TypeError,
      JSON.stringify(extraFields),
    );
  }
  assert.ok(CANONICAL_NOTIFICATION_KEYS.includes("actorId"));
  assert.ok(CANONICAL_NOTIFICATION_KEYS.includes("isRead"));
});

// ---------------------------------------------------------------- outbox

test("a published post opens ONE outbox; held and stale posts open none", async () => {
  const current = await scene();
  const path = await handlePagePostCreated(postCreatedEvent(current));
  const reference = pagePostFanoutOutboxReference(current.postId);
  assert.equal(path, reference.path);
  const first = (await reference.get()).data();
  assert.equal(first.schemaVersion, 1);
  assert.equal(first.postId, current.postId);
  assert.equal(first.pageId, current.pageId);
  assert.equal(first.sourcePath, `pagePosts/${current.postId}`);
  assert.equal(first.sourceGeneration, current.sourceGeneration);
  assert.equal(first.targetLabel, "New post from a Page you follow: Pracownia Glina");
  assert.equal(first.postPreview, "Nowe kubki już w pracowni");
  assert.equal(first.pageKind, "business");
  assert.equal(first.status, "pending");
  assert.equal(first.afterId, null);
  assert.equal(first.stoppedReason, null);
  assert.deepEqual([first.followers, first.pages, first.written], [0, 0, 0]);
  assert.ok(first.expiresAt.toMillis() > first.createdAt.toMillis());

  // Eventarc redelivers: the same event changes nothing.
  await handlePagePostCreated(postCreatedEvent(current));
  assert.deepEqual((await reference.get()).data().createdAt, first.createdAt);

  // A different identity under the same post id is refused, not merged.
  await assert.rejects(
    ensurePagePostFanoutOutbox({
      postId: current.postId,
      pageId: "somebody-else",
      sourceGeneration: current.sourceGeneration,
      targetLabel: first.targetLabel,
      postPreview: first.postPreview,
      pageKind: "business",
    }),
    /identity conflict/u,
  );

  const held = await scene({ post: { status: "held", heldAt: Timestamp.fromMillis(NOW) } });
  assert.equal(await handlePagePostCreated(postCreatedEvent(held)), null);
  assert.equal((await pagePostFanoutOutboxReference(held.postId).get()).exists, false);

  const stale = await scene();
  const longAgo = new Date(Date.now() - PAGE_POST_RETRY_WINDOW_MS - 60_000).toISOString();
  assert.equal(await handlePagePostCreated(postCreatedEvent(stale, longAgo)), null);
  assert.equal((await pagePostFanoutOutboxReference(stale.postId).get()).exists, false);

  const malformed = await scene();
  await db.doc(`pagePosts/${malformed.postId}`).update({ unexpected: true });
  const malformedSnapshot = await db.doc(`pagePosts/${malformed.postId}`).get();
  assert.equal(await handlePagePostCreated(
    postCreatedEvent({ ...malformed, snapshot: malformedSnapshot }),
  ), null);
});

test("fan-out writes the exact row once per follower and is idempotent", async () => {
  const current = await scene({ followers: 3 });
  await handlePagePostCreated(postCreatedEvent(current));
  const reference = pagePostFanoutOutboxReference(current.postId);
  const runs = await drain(reference);
  assert.equal(runs.length, 1);
  assert.equal(runs[0].state, "complete");
  assert.equal(runs[0].followers, 3);
  assert.equal(runs[0].written, 3);

  const notificationId = pagePostNotificationId(current.postId);
  for (const follower of current.followerIds) {
    const row = (await db.doc(`users/${follower}/notifications/${notificationId}`).get()).data();
    assert.deepEqual(Object.keys(row).sort(), [
      "actorId", "actorName", "actorPhotoUrl", "bellSuppressed", "createdAt",
      "dedupeKey", "isRead", "pageKind", "postPreview", "sourceGeneration",
      "sourcePath", "targetId", "targetLabel", "type",
    ]);
    assert.equal(row.type, "pagePostPublished");
    assert.equal(row.actorId, current.pageId);
    assert.equal(row.actorName, "Pracownia Glina");
    assert.equal(row.actorPhotoUrl, null);
    assert.equal(row.targetId, current.postId);
    assert.equal(row.targetLabel, "New post from a Page you follow: Pracownia Glina");
    assert.equal(row.postPreview, "Nowe kubki już w pracowni");
    assert.equal(row.pageKind, "business");
    assert.equal(row.sourcePath, `pagePosts/${current.postId}`);
    assert.equal(row.sourceGeneration, current.sourceGeneration);
    assert.equal(row.isRead, false);
    assert.equal(row.bellSuppressed, false);
    assert.equal(row.dedupeKey, notificationId);
    assert.equal((await eventLedgerReference(pagePostEventId(current.postId, follower)).get())
      .data().outcome, "written");
  }
  const done = (await reference.get()).data();
  assert.equal(done.status, "complete");
  assert.deepEqual([done.followers, done.pages, done.written], [3, 1, 3]);
  // A finished fan-out keeps ids and counters, not what somebody wrote.
  assert.equal(done.postPreview, "");
  assert.equal(done.targetLabel, "New post from a Page you follow: a Page");
  assert.equal(done.postId, current.postId);
  assert.equal(done.expiresAt.toMillis() - done.createdAt.toMillis(), PAGE_POST_OUTBOX_RETENTION_MS);
  assert.equal(PAGE_POST_OUTBOX_RETENTION_MS, 7 * 24 * 60 * 60 * 1000);
  // The create event redelivered after completion finds the outbox done.
  assert.equal(await handlePagePostCreated(postCreatedEvent(current)), reference.path);
  assert.equal((await reference.get()).data().status, "complete");
  await assert.rejects(
    ensurePagePostFanoutOutbox({
      postId: current.postId,
      pageId: "somebody-else",
      sourceGeneration: current.sourceGeneration,
      targetLabel: "x",
      postPreview: "",
      pageKind: "business",
    }),
    /identity conflict/u,
  );

  // A follower deletes the row; a replayed page must not bring it back.
  const [first] = current.followerIds;
  await db.doc(`users/${first}/notifications/${notificationId}`).delete();
  await reference.update({ status: "pending", afterId: null });
  const replay = await drain(reference);
  assert.equal(replay.at(-1).state, "complete");
  assert.equal(replay.reduce((sum, run) => sum + run.written, 0), 0);
  assert.equal((await db.doc(`users/${first}/notifications/${notificationId}`).get()).exists, false);
});

test("a photo post with no caption carries no preview field", async () => {
  const current = await scene({
    post: (pageId, postId) => ({
      kind: "photo",
      text: "",
      media: photoMedia(pageId, postId, 2),
    }),
  });
  assert.notEqual(await handlePagePostCreated(postCreatedEvent(current)), null);
  assert.equal((await pagePostFanoutOutboxReference(current.postId).get()).data().postPreview, "");
  await drain(pagePostFanoutOutboxReference(current.postId));
  const row = (await db.doc(
    `users/${current.followerIds[0]}/notifications/${pagePostNotificationId(current.postId)}`,
  ).get()).data();
  assert.equal(Object.hasOwn(row, "postPreview"), false);
  assert.equal(row.pageKind, "business");
});

test("fan-out pages 200 at a time, one page per invocation, resumably", async () => {
  assert.equal(PAGE_POST_FOLLOWER_PAGE_SIZE, 200);
  const current = await scene({ followers: 0 });
  await handlePagePostCreated(postCreatedEvent(current));
  const reference = pagePostFanoutOutboxReference(current.postId);
  const ids = Array.from({ length: 450 }, (_, index) => `f-${String(index).padStart(4, "0")}`);
  const requested = [];
  const notified = [];
  const pageLoader = async ({ afterId, pageSize, hostId }) => {
    assert.equal(hostId, current.pageId);
    assert.equal(pageSize, 200);
    requested.push(afterId);
    const start = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    return ids.slice(start, start + pageSize);
  };
  const notify = async (id) => {
    notified.push(id);
    return "written";
  };

  // Page one.
  const one = await handlePagePostFanoutOutboxWritten(await outboxEvent(reference), { pageLoader, notify });
  assert.equal(one.state, "pending");
  assert.equal(one.followers, 200);
  let state = (await reference.get()).data();
  assert.equal(state.afterId, "f-0199");
  assert.deepEqual([state.followers, state.pages, state.written], [200, 1, 200]);

  // Page two crashes half-way: the cursor does NOT move.
  let crashed = false;
  await assert.rejects(
    handlePagePostFanoutOutboxWritten(await outboxEvent(reference), {
      pageLoader,
      notify: async (id) => {
        if (!crashed && id === "f-0300") {
          crashed = true;
          throw new Error("simulated worker death");
        }
        return notify(id);
      },
    }),
    /simulated worker death/u,
  );
  state = (await reference.get()).data();
  assert.equal(state.afterId, "f-0199");
  assert.equal(state.status, "pending");

  // The retry resumes from the committed cursor, never from page zero.
  const rest = await drain(reference, { pageLoader, notify });
  assert.deepEqual(rest.map((run) => run.state), ["pending", "complete"]);
  state = (await reference.get()).data();
  assert.equal(state.status, "complete");
  assert.equal(state.afterId, "f-0449");
  assert.deepEqual([state.followers, state.pages], [450, 3]);
  assert.deepEqual(requested, [null, "f-0199", "f-0199", "f-0399"]);
  assert.equal(new Set(notified).size, 450);

  // A completed outbox is inert.
  assert.equal(await handlePagePostFanoutOutboxWritten(await outboxEvent(reference), {
    pageLoader,
    notify,
  }), null);
  assert.deepEqual(await processPagePostFanoutOutbox(reference, { pageLoader, notify }),
    { state: "complete" });
});

test("two workers on the same cursor: one commits, the other is stale", async () => {
  const current = await scene({ followers: 0 });
  await handlePagePostCreated(postCreatedEvent(current));
  const reference = pagePostFanoutOutboxReference(current.postId);
  const ids = Array.from({ length: 250 }, (_, index) => `r-${String(index).padStart(4, "0")}`);
  const pageLoader = async ({ afterId, pageSize }) => {
    const start = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    return ids.slice(start, start + pageSize);
  };
  const [left, right] = await Promise.all([
    processPagePostFanoutOutbox(reference, { pageLoader, notify: async () => "written" }),
    processPagePostFanoutOutbox(reference, { pageLoader, notify: async () => "skipped:replay" }),
  ]);
  assert.deepEqual([left.state, right.state].sort(), ["pending", "stale"]);
  const state = (await reference.get()).data();
  assert.equal(state.afterId, "r-0199");
  assert.equal(state.pages, 1);
  assert.equal(state.followers, 200);
});

test("a deleted post, a disabled product and an old outbox stop the fan-out", async () => {
  const deleted = await scene({ followers: 2 });
  await handlePagePostCreated(postCreatedEvent(deleted));
  await db.doc(`pagePosts/${deleted.postId}`).delete();
  const deletedRuns = await drain(pagePostFanoutOutboxReference(deleted.postId));
  assert.equal(deletedRuns.length, 1);
  assert.equal(deletedRuns[0].stoppedReason, "source-gone");
  assert.equal(deletedRuns[0].state, "complete");
  for (const follower of deleted.followerIds) {
    assert.equal((await db.collection(`users/${follower}/notifications`).get()).size, 0);
  }
  assert.equal((await pagePostFanoutOutboxReference(deleted.postId).get()).data().stoppedReason,
    "source-gone");

  const off = await scene({ followers: 1 });
  await handlePagePostCreated(postCreatedEvent(off));
  try {
    await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation({
      readAccess: "disabled",
      writeAccess: "disabled",
    }));
    const offRuns = await drain(pagePostFanoutOutboxReference(off.postId));
    assert.equal(offRuns[0].stoppedReason, "pages-disabled");
  } finally {
    await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation());
  }
  assert.equal((await db.collection(`users/${off.followerIds[0]}/notifications`).get()).size, 0);

  const old = await scene({ followers: 1 });
  await handlePagePostCreated(postCreatedEvent(old));
  const oldRuns = await drain(pagePostFanoutOutboxReference(old.postId), {
    nowMs: Date.now() + PAGE_POST_RETRY_WINDOW_MS + 60_000,
  });
  assert.equal(oldRuns[0].stoppedReason, "expired");
  assert.equal((await db.collection(`users/${old.followerIds[0]}/notifications`).get()).size, 0);

  // A malformed outbox is reported and left alone instead of retried.
  const broken = db.doc("pagePostFanoutOutbox/broken-outbox-probe");
  await broken.set({ status: "pending", schemaVersion: 7 });
  const result = await handlePagePostFanoutOutboxWritten(await outboxEvent(broken));
  assert.equal(result.state, "malformed");
});

test("only followers who may read the post get a row", async () => {
  const current = await scene({ followers: 4 });
  const [ok, blocker, unfollowedMirror, muted] = current.followerIds;
  await db.doc(`users/${blocker}/blocked/${current.pageId}`).set({ at: NOW });
  // The Page's follower mirror still lists them; their own edge is gone.
  await db.doc(`users/${unfollowedMirror}/following/${current.pageId}`).delete();
  await db.doc(`restrictions/${muted}`).set({ type: "communicationMute", expiresAt: null });
  await handlePagePostCreated(postCreatedEvent(current));
  const runs = await drain(pagePostFanoutOutboxReference(current.postId));
  assert.equal(runs[0].followers, 4);
  assert.equal(runs[0].written, 1);
  const id = pagePostNotificationId(current.postId);
  assert.equal((await db.doc(`users/${ok}/notifications/${id}`).get()).exists, true);
  for (const refused of [blocker, unfollowedMirror, muted]) {
    assert.equal((await db.doc(`users/${refused}/notifications/${id}`).get()).exists, false, refused);
  }
});

// ------------------------------------------------------------- daily cap

function messagingSpy() {
  const messages = [];
  return {
    messages,
    sendEachForMulticast: async (message) => {
      messages.push(message);
      return { responses: message.tokens.map(() => ({ success: true })) };
    },
  };
}

async function publishAndFanOut(pageId, text) {
  const postId = newPostId();
  await db.doc(`pagePosts/${postId}`).set(postDoc(pageId, postId, Date.now(), { text }));
  const snapshot = await db.doc(`pagePosts/${postId}`).get();
  const current = { postId, pageId, snapshot };
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(postId));
  return postId;
}

async function pushRow(recipientId, postId, messaging, claimAtMs) {
  const reference = db.doc(
    `users/${recipientId}/notifications/${pagePostNotificationId(postId)}`,
  );
  const snapshot = await reference.get();
  assert.equal(snapshot.exists, true, "the bell row must exist");
  await handleNotificationCreated({
    id: `push-${postId}`,
    params: { userId: recipientId, notificationId: reference.id },
    data: snapshot,
  }, {
    messaging,
    claimClock: () => Timestamp.fromMillis(claimAtMs),
  });
  return (await reference.get()).data();
}

test("the cap day is the Page budget day", () => {
  for (const at of [0, NOW, Date.UTC(2026, 9, 3, 23, 59, 59), Date.UTC(2026, 9, 4, 0, 0, 0)]) {
    assert.equal(pagePostPushCapDay(at), pageBudgetDay(at));
  }
  assert.equal(pagePostPushCapDay(Date.UTC(2026, 9, 3, 23, 59, 59)), "20261003");
  assert.equal(pagePostPushCapDay(Date.UTC(2026, 9, 4, 0, 0, 0)), "20261004");
});

test("one push per Page per day; later posts only land in the bell", async () => {
  const current = await scene({ followers: 1 });
  const [follower] = current.followerIds;
  await db.doc(`users/${follower}/fcmTokens/token-cap`).set({ updatedAt: Timestamp.now() });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));

  const messaging = messagingSpy();
  const dayOne = Date.UTC(2026, 9, 3, 9, 0, 0);
  const first = await pushRow(follower, current.postId, messaging, dayOne);
  assert.equal(first.pushDeliveryStatus, "sent");
  assert.equal(messaging.messages.length, 1);
  assert.equal(messaging.messages[0].notification.title, "Pracownia Glina published a post");
  assert.equal(messaging.messages[0].notification.body, "Nowe kubki już w pracowni");
  assert.equal(messaging.messages[0].data.type, "pagePostPublished");
  assert.equal(messaging.messages[0].data.targetId, current.postId);
  assert.equal(messaging.messages[0].data.actorId, current.pageId);
  const receipt = (await pagePostPushCapReference(follower, current.pageId, "20261003").get()).data();
  assert.equal(receipt.kind, "pagePostPushCap");
  assert.equal(receipt.recipientId, follower);
  assert.equal(receipt.pageId, current.pageId);
  assert.ok(receipt.expiresAt.toMillis() > dayOne);

  // The second post of the same day: a bell row, no push.
  const second = await publishAndFanOut(current.pageId, "Drugi post tego dnia");
  const capped = await pushRow(follower, second, messaging, dayOne + 6 * 3_600_000);
  assert.equal(capped.pushDeliveryStatus, "skipped");
  assert.equal(capped.pushSkipReason, PAGE_POST_PUSH_CAP_SKIP_REASON);
  assert.equal(capped.pushSkipReason, "daily-cap");
  assert.equal(messaging.messages.length, 1);
  assert.equal(capped.type, "pagePostPublished");
  assert.equal(capped.postPreview, "Drugi post tego dnia");

  // The next day rings again.
  const third = await publishAndFanOut(current.pageId, "Post następnego dnia");
  const next = await pushRow(follower, third, messaging, Date.UTC(2026, 9, 4, 0, 5, 0));
  assert.equal(next.pushDeliveryStatus, "sent");
  assert.equal(messaging.messages.length, 2);
  assert.equal(messaging.messages[1].notification.body, "Post następnego dnia");
});

test("the cap is per Page: another followed Page still rings the same day", async () => {
  const one = await scene({ followers: 1 });
  const [follower] = one.followerIds;
  const otherPage = freshUid("pg");
  await seedPage(db, otherPage, NOW, {
    page: { displayName: "Studio Fala" },
    user: { displayName: "Studio Fala" },
  });
  await seedFollowEdge(db, follower, otherPage, NOW);
  await db.doc(`users/${follower}/fcmTokens/token-two-pages`).set({ updatedAt: Timestamp.now() });
  await handlePagePostCreated(postCreatedEvent(one));
  await drain(pagePostFanoutOutboxReference(one.postId));
  const otherPost = await publishAndFanOut(otherPage, "Rozmowy o muzyce");

  const messaging = messagingSpy();
  const at = Date.UTC(2026, 9, 5, 12, 0, 0);
  assert.equal((await pushRow(follower, one.postId, messaging, at)).pushDeliveryStatus, "sent");
  assert.equal((await pushRow(follower, otherPost, messaging, at)).pushDeliveryStatus, "sent");
  assert.deepEqual(messaging.messages.map((message) => message.notification.title), [
    "Pracownia Glina published a post",
    "Studio Fala published a post",
  ]);
});

test("a switched-off preference skips the push, keeps the row and spends no cap", async () => {
  const current = await scene({ followers: 1 });
  const [follower] = current.followerIds;
  await db.doc(`users/${follower}/fcmTokens/token-pref`).set({ updatedAt: Timestamp.now() });
  await db.doc(`users/${follower}`).update({
    notificationPreferences: { pagePostPublished: false },
  });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const messaging = messagingSpy();
  const at = Date.UTC(2026, 9, 6, 8, 0, 0);
  const row = await pushRow(follower, current.postId, messaging, at);
  // The settings screen promises it: in-app activity is always recorded.
  assert.equal(row.type, "pagePostPublished");
  assert.equal(row.pushDeliveryStatus, "skipped");
  assert.equal(row.pushSkipReason, "preference-disabled");
  assert.equal(messaging.messages.length, 0);
  assert.equal((await pagePostPushCapReference(follower, current.pageId, "20261006").get()).exists,
    false);

  // Turned back on: today's first push is still available.
  await db.doc(`users/${follower}`).update({
    notificationPreferences: { pagePostPublished: true },
  });
  const second = await publishAndFanOut(current.pageId, "Znów z powiadomieniem");
  assert.equal((await pushRow(follower, second, messaging, at + 60_000)).pushDeliveryStatus, "sent");
  assert.equal(messaging.messages.length, 1);
});

test("a post deleted before the push: no push, the row is retired, no cap spent", async () => {
  const current = await scene({ followers: 1 });
  const [follower] = current.followerIds;
  await db.doc(`users/${follower}/fcmTokens/token-gone`).set({ updatedAt: Timestamp.now() });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const reference = db.doc(
    `users/${follower}/notifications/${pagePostNotificationId(current.postId)}`,
  );
  const snapshot = await reference.get();
  await db.doc(`pagePosts/${current.postId}`).delete();
  const messaging = messagingSpy();
  const at = Date.UTC(2026, 9, 7, 8, 0, 0);
  await handleNotificationCreated({
    id: "push-after-delete",
    params: { userId: follower, notificationId: reference.id },
    data: snapshot,
  }, { messaging, claimClock: () => Timestamp.fromMillis(at) });
  assert.equal(messaging.messages.length, 0);
  assert.equal((await reference.get()).exists, false);
  assert.equal((await pagePostPushCapReference(follower, current.pageId, "20261007").get()).exists,
    false);
});

test("two posts racing the claim ring once", async () => {
  const current = await scene({ followers: 1 });
  const [follower] = current.followerIds;
  await db.doc(`users/${follower}/fcmTokens/token-race`).set({ updatedAt: Timestamp.now() });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const second = await publishAndFanOut(current.pageId, "Wyścig");
  const messaging = messagingSpy();
  const at = Date.UTC(2026, 9, 8, 8, 0, 0);
  const [left, right] = await Promise.all([
    pushRow(follower, current.postId, messaging, at),
    pushRow(follower, second, messaging, at),
  ]);
  assert.deepEqual([left.pushDeliveryStatus, right.pushDeliveryStatus].sort(), ["sent", "skipped"]);
  assert.equal(messaging.messages.length, 1);
});

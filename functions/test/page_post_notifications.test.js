/**
 * "A Page you follow published a post" (ADR-237): the source validator, the
 * paged fan-out outbox, the bell row's exact shape, the per-Page daily push
 * cap, the "client too old" push gate and the retirement of rows when a post
 * stops being published or a block lands. Runs against the Firestore
 * emulator, like every other notification suite:
 *
 *   firebase emulators:exec --only firestore --project demo-yovoice \
 *     "cd functions && node --test --test-concurrency=1 test/page_post_notifications.test.js"
 */
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { after, before, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { PAGES_ACTIVATION_PATH } = require("../pages/activation");
const { pageNameSearch } = require("../pages/contract");
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
  handlePagePostUnpublished,
  pagePostEventId,
  pagePostFanoutOutboxReference,
  pagePostNotificationId,
  pagePostPreview,
  pagePostTargetLabel,
  processPagePostFanoutOutbox,
} = require("../notifications/page_posts");
const {
  pagePostNotificationsQuery,
  retirePagePostNotifications,
  retirePagePostNotificationsBetween,
} = require("../notifications/page_post_rows");
const {
  PAGE_POST_PUSH_CAP_SKIP_REASON,
  PAGE_POST_PUSH_MIN_GAP_MS,
  PUSH_CLIENT_TOO_OLD_SKIP_REASON,
  PUSH_REQUIRES_CURRENT_CLIENT,
  PUSH_TITLES,
  handleNotificationCreated,
  pagePostPushCapDay,
  pagePostPushCapReference,
  pushNeedsNewerClient,
  pushPreferenceDisabled,
} = require("../notifications/push");
const { setUserBlock } = require("../friends/social_graph");
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
  request,
  seedAccount,
  seedFollowEdge,
  seedPage,
} = require("./helpers/pages_fixture");

const NOW = Date.now();
const runBlock = setUserBlock.run ?? setUserBlock;
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
    // `appLanguage` marks an account that has opened build 42 or later: the
    // only accounts a followed Page's post is PUSHED to.
    await seedAccount(db, followerId, NOW, {
      displayName: `Follower ${index}`,
      user: { appLanguage: "en" },
    });
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
  // Bidi and invisible controls never reach a lock screen.
  assert.equal(pagePostPreview("Hej\u202e\u200b\u015bwiat"), "Hej \u015bwiat");
  assert.equal(pagePostPreview("a\u2066b\u2069c\ufeffd\u200ee\u0000f"), "a b c d e f");
  // The two format characters the publish path allows survive: Persian
  // needs the zero-width non-joiner and emoji sequences need the joiner.
  const persian = "\u0645\u06cc\u200c\u062e\u0648\u0627\u0647\u0645";
  assert.equal(pagePostPreview(persian), persian);
  const family = "\u{1F468}\u200d\u{1F469}\u200d\u{1F467}";
  assert.equal(pagePostPreview(`Rodzina ${family}`), `Rodzina ${family}`);
  // ... but joiners alone are not a preview, and a cut never ends on one.
  assert.equal(pagePostPreview("\u200d \u200c"), "");
  const cut = pagePostPreview(`${"x".repeat(118)}${family}`);
  assert.equal(Array.from(cut).length, 120);
  assert.equal(/[\u200c\u200d]\u2026$/u.test(cut), false);
  assert.ok(cut.endsWith("\u2026"));
  assert.ok(cut.length <= 240);
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

  // Redelivered AFTER the owner renamed the Page and changed its kind: the
  // label and kind are rebuilt from the current Page, and that used to be an
  // "identity conflict" retried with errors for six hours. It is the same
  // post: nothing changes and the outbox keeps the first delivery's words.
  await db.doc(`pages/${current.pageId}`).update({
    displayName: "Glina i Ogie\u0144",
    nameSearch: pageNameSearch("Glina i Ogie\u0144"),
  });
  assert.equal(pagePostTargetLabel("Glina i Ogie\u0144") === first.targetLabel, false);
  assert.equal(await handlePagePostCreated(postCreatedEvent(current)), reference.path);
  const afterRename = (await reference.get()).data();
  assert.equal(afterRename.targetLabel, first.targetLabel);
  assert.equal(afterRename.pageKind, "business");
  assert.deepEqual(afterRename.createdAt, first.createdAt);
  await ensurePagePostFanoutOutbox({
    postId: current.postId,
    pageId: current.pageId,
    sourceGeneration: current.sourceGeneration,
    targetLabel: "New post from a Page you follow: somebody renamed",
    postPreview: "other words",
    pageKind: "community",
  });
  assert.equal((await reference.get()).data().postPreview, first.postPreview);

  // A different identity under the same post id is refused, not merged.
  for (const forged of [
    { pageId: "somebody-else" },
    { sourceGeneration: "1:1" },
  ]) {
    await assert.rejects(
      ensurePagePostFanoutOutbox({
        postId: current.postId,
        pageId: current.pageId,
        sourceGeneration: current.sourceGeneration,
        targetLabel: first.targetLabel,
        postPreview: first.postPreview,
        pageKind: "business",
        ...forged,
      }),
      /identity conflict/u,
      JSON.stringify(forged),
    );
  }

  const held = await scene({ post: { status: "held", heldAt: Timestamp.fromMillis(NOW) } });
  assert.equal(await handlePagePostCreated(postCreatedEvent(held)), null);
  assert.equal((await pagePostFanoutOutboxReference(held.postId).get()).exists, false);

  const stale = await scene();
  const longAgo = new Date(Date.now() - PAGE_POST_RETRY_WINDOW_MS - 60_000).toISOString();
  assert.equal(await handlePagePostCreated(postCreatedEvent(stale, longAgo)), null);
  assert.equal((await pagePostFanoutOutboxReference(stale.postId).get()).exists, false);

  // A fresh EVENT for an old POST: a restore, an import or a migration
  // script wrote the document again. It was published long ago and is not
  // announced as new.
  const restored = await scene({
    post: { createdAt: Timestamp.fromMillis(NOW - PAGE_POST_RETRY_WINDOW_MS - 60_000) },
  });
  assert.equal(await handlePagePostCreated(postCreatedEvent(restored)), null);
  assert.equal((await pagePostFanoutOutboxReference(restored.postId).get()).exists, false);
  // Just inside the window it still is.
  const recent = await scene({
    post: { createdAt: Timestamp.fromMillis(NOW - PAGE_POST_RETRY_WINDOW_MS + 600_000) },
  });
  assert.notEqual(await handlePagePostCreated(postCreatedEvent(recent)), null);

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

test("two posts either side of UTC midnight ring once", async () => {
  assert.equal(PAGE_POST_PUSH_MIN_GAP_MS, 6 * 60 * 60 * 1000);
  const current = await scene({ followers: 1 });
  const [follower] = current.followerIds;
  await db.doc(`users/${follower}/fcmTokens/token-midnight`).set({ updatedAt: Timestamp.now() });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const messaging = messagingSpy();
  const lateEvening = Date.UTC(2026, 9, 10, 23, 58, 0);
  assert.equal((await pushRow(follower, current.postId, messaging, lateEvening))
    .pushDeliveryStatus, "sent");

  // Four minutes later it is "tomorrow" in UTC. Still the same evening.
  const second = await publishAndFanOut(current.pageId, "Dwie minuty po północy");
  const straddle = await pushRow(follower, second, messaging, Date.UTC(2026, 9, 11, 0, 2, 0));
  assert.equal(straddle.pushDeliveryStatus, "skipped");
  assert.equal(straddle.pushSkipReason, "daily-cap");
  assert.equal(messaging.messages.length, 1);
  // A withheld push spends nothing: the new day's push is still available…
  assert.equal((await pagePostPushCapReference(follower, current.pageId, "20261011").get()).exists,
    false);
  // …and rings once six hours have passed since the last one.
  const third = await publishAndFanOut(current.pageId, "Rano");
  const stillClose = await pushRow(
    follower, third, messaging, lateEvening + PAGE_POST_PUSH_MIN_GAP_MS - 1_000);
  assert.equal(stillClose.pushSkipReason, "daily-cap");
  const fourth = await publishAndFanOut(current.pageId, "Rano, drugi raz");
  const morning = await pushRow(
    follower, fourth, messaging, lateEvening + PAGE_POST_PUSH_MIN_GAP_MS + 1_000);
  assert.equal(morning.pushDeliveryStatus, "sent");
  assert.equal(messaging.messages.length, 2);
  assert.equal((await pagePostPushCapReference(follower, current.pageId, "20261011").get()).exists,
    true);
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

// ------------------------------------------- builds that predate the type

test("an account that never opened build 42 gets the row, not the push", async () => {
  assert.deepEqual([...PUSH_REQUIRES_CURRENT_CLIENT], ["pagePostPublished"]);
  assert.equal(PUSH_CLIENT_TOO_OLD_SKIP_REASON, "client-too-old");
  assert.equal(pushNeedsNewerClient({}, "pagePostPublished"), true);
  assert.equal(pushNeedsNewerClient(undefined, "pagePostPublished"), true);
  assert.equal(pushNeedsNewerClient({ appLanguage: "system" }, "pagePostPublished"), true);
  assert.equal(pushNeedsNewerClient({ appLanguage: "pl" }, "pagePostPublished"), false);
  assert.equal(pushNeedsNewerClient({ appLanguage: "en" }, "pagePostPublished"), false);
  // Every type that existed before keeps pushing to every build.
  for (const type of ["follow", "friendRequest", "pagePostComment", "liveStarted", "system"]) {
    assert.equal(pushNeedsNewerClient({}, type), false, type);
  }

  const current = await scene({ followers: 1 });
  const [follower] = current.followerIds;
  // Builds 40/41: a token, no switch for this type, no stored language.
  await db.doc(`users/${follower}`).update({ appLanguage: null });
  await db.doc(`users/${follower}/fcmTokens/token-old-build`).set({ updatedAt: Timestamp.now() });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const messaging = messagingSpy();
  const at = Date.UTC(2026, 9, 9, 8, 0, 0);
  const row = await pushRow(follower, current.postId, messaging, at);
  assert.equal(row.type, "pagePostPublished");
  assert.equal(row.targetLabel, "New post from a Page you follow: Pracownia Glina");
  assert.equal(row.pushDeliveryStatus, "skipped");
  assert.equal(row.pushSkipReason, "client-too-old");
  assert.equal(messaging.messages.length, 0);
  // Nothing was spent: once the account opens build 42, today still rings.
  assert.equal((await pagePostPushCapReference(follower, current.pageId, "20261009").get()).exists,
    false);
  await db.doc(`users/${follower}`).update({ appLanguage: "pl" });
  const second = await publishAndFanOut(current.pageId, "Po aktualizacji");
  const pushed = await pushRow(follower, second, messaging, at + 60_000);
  assert.equal(pushed.pushDeliveryStatus, "sent");
  assert.equal(messaging.messages.length, 1);
  assert.equal(messaging.messages[0].notification.title, "Pracownia Glina dodaje post");
  assert.equal(messaging.messages[0].notification.body, "Po aktualizacji");
});

// --------------------------------------------------------------- retiring

function unpublishEvent(postId, before, after) {
  return { params: { postId }, data: { before, after } };
}

async function rowExists(uid, postId) {
  return (await db.doc(`users/${uid}/notifications/${pagePostNotificationId(postId)}`).get())
    .exists;
}

test("the retirement query's COLLECTION_GROUP index is declared", () => {
  // ADR-007: automatic single-field indexes are COLLECTION scope only, and
  // the emulator enforces neither. Without this override production answers
  // the trigger's query with FAILED_PRECONDITION and no row is ever retired.
  const config = JSON.parse(readFileSync(
    path.resolve(__dirname, "../../firestore.indexes.json"),
    "utf8",
  ));
  const overrides = config.fieldOverrides.filter((override) =>
    override.collectionGroup === "notifications" && override.fieldPath === "sourcePath");
  assert.equal(overrides.length, 1);
  assert.ok(overrides[0].indexes.some((index) =>
    index.queryScope === "COLLECTION_GROUP" && index.order === "ASCENDING"));
  // A fieldOverride REPLACES automatic indexing: the collection-scope
  // entries every other field keeps by default are declared again.
  for (const expected of [
    { order: "ASCENDING", queryScope: "COLLECTION" },
    { order: "DESCENDING", queryScope: "COLLECTION" },
    { arrayConfig: "CONTAINS", queryScope: "COLLECTION" },
  ]) {
    assert.ok(overrides[0].indexes.some((index) =>
      Object.entries(expected).every(([key, value]) => index[key] === value)),
    JSON.stringify(expected));
  }
  assert.notEqual(overrides[0].ttl, true);
});

test("a post that stops being published takes every follower's row with it", async () => {
  const current = await scene({ followers: 5 });
  const [reader, unfollowed, deletedOwn, ...others] = current.followerIds;
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const kept = await publishAndFanOut(current.pageId, "Ten post zostaje");
  for (const follower of current.followerIds) {
    assert.equal(await rowExists(follower, current.postId), true);
    assert.equal(await rowExists(follower, kept), true);
  }
  // Rows that are NOT this post's row, in the same inboxes.
  await db.doc(`users/${reader}/notifications/follow_someone`).set({
    type: "follow",
    actorId: "someone",
    isRead: false,
  });
  // Unfollowing later keeps the row (it was earned) but removes the edge the
  // fan-out walked: retirement must not depend on the follower list.
  await db.doc(`users/${unfollowed}/following/${current.pageId}`).delete();
  await db.doc(`users/${current.pageId}/followers/${unfollowed}`).delete();
  // A row the follower already deleted is simply not there.
  await db.doc(`users/${deletedOwn}/notifications/${pagePostNotificationId(current.postId)}`)
    .delete();
  // Something else that happens to carry the same sourcePath is left alone:
  // only the row this feature wrote, under its own id, in a user inbox.
  const lookalikes = [
    db.doc(`users/${reader}/notifications/other_id`),
    db.doc(`clubs/some-server/notifications/${pagePostNotificationId(current.postId)}`),
  ];
  await lookalikes[0].set({ type: "system", sourcePath: `pagePosts/${current.postId}` });
  await lookalikes[1].set({
    type: "pagePostPublished",
    sourcePath: `pagePosts/${current.postId}`,
  });

  // The real collection-group query sees exactly the rows of this post.
  const found = await pagePostNotificationsQuery(current.postId).get();
  assert.equal(found.size, 4 + lookalikes.length);

  const before = current.snapshot;
  // A like, a comment or a pin: published before and after. Nothing is read.
  const neverRead = {
    collectionGroup: () => {
      throw new Error("an ordinary post write must not query anything");
    },
  };
  await db.doc(`pagePosts/${current.postId}`).update({ likeCount: 3 });
  const liked = await db.doc(`pagePosts/${current.postId}`).get();
  assert.equal(await handlePagePostUnpublished(
    unpublishEvent(current.postId, before, liked), { firestore: neverRead }), null);
  // A create is not an unpublish, and neither is a hold being lifted.
  assert.equal(await handlePagePostUnpublished(
    unpublishEvent(current.postId, { exists: false }, liked), { firestore: neverRead }), null);
  assert.equal(await handlePagePostUnpublished(unpublishEvent(
    current.postId,
    { exists: true, id: current.postId, data: () => ({ status: "held" }) },
    liked,
  ), { firestore: neverRead }), null);
  assert.equal(await rowExists(reader, current.postId), true);

  // The owner deletes the post (a hard delete): two batches of 3 and 1.
  await db.doc(`pagePosts/${current.postId}`).delete();
  const gone = await db.doc(`pagePosts/${current.postId}`).get();
  const retired = await handlePagePostUnpublished(
    unpublishEvent(current.postId, liked, gone), { batchSize: 3 });
  assert.deepEqual(retired, { deleted: 4, done: true });
  for (const follower of current.followerIds) {
    assert.equal(await rowExists(follower, current.postId), false, follower);
    // Another post of the same Page keeps its rows.
    assert.equal(await rowExists(follower, kept), true, follower);
  }
  assert.equal((await db.doc(`users/${reader}/notifications/follow_someone`).get()).exists, true);
  for (const lookalike of lookalikes) assert.equal((await lookalike.get()).exists, true);
  // Redelivered: nothing left, still done.
  assert.deepEqual(await handlePagePostUnpublished(
    unpublishEvent(current.postId, liked, gone)), { deleted: 0, done: true });
  // A replayed fan-out page cannot bring a retired row back.
  await pagePostFanoutOutboxReference(current.postId).update({ status: "pending", afterId: null });
  await drain(pagePostFanoutOutboxReference(current.postId));
  assert.equal(await rowExists(others[0], current.postId), false);
  await Promise.all(lookalikes.map((lookalike) => lookalike.delete()));
});

test("a hold, a moderator's removal and a tombstone retire rows too", async () => {
  for (const change of [
    { status: "held", heldAt: Timestamp.fromMillis(NOW) },
    { status: "removed", removedAt: Timestamp.fromMillis(NOW), removedReason: "spam" },
    { status: "deleted", deletedAt: Timestamp.fromMillis(NOW) },
  ]) {
    const current = await scene({ followers: 2 });
    await handlePagePostCreated(postCreatedEvent(current));
    await drain(pagePostFanoutOutboxReference(current.postId));
    await db.doc(`pagePosts/${current.postId}`).update(change);
    const after = await db.doc(`pagePosts/${current.postId}`).get();
    const retired = await handlePagePostUnpublished(
      unpublishEvent(current.postId, current.snapshot, after));
    assert.deepEqual(retired, { deleted: 2, done: true }, change.status);
    for (const follower of current.followerIds) {
      assert.equal(await rowExists(follower, current.postId), false, change.status);
    }
  }
});

test("retirement that runs out of budget asks to be run again", async () => {
  const current = await scene({ followers: 3 });
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  assert.deepEqual(
    await retirePagePostNotifications(current.postId, { batchSize: 1, maxBatches: 2 }),
    { deleted: 2, done: false },
  );
  await db.doc(`pagePosts/${current.postId}`).delete();
  const gone = await db.doc(`pagePosts/${current.postId}`).get();
  // The trigger turns "not finished" into a retry of the event.
  await assert.rejects(
    handlePagePostUnpublished(unpublishEvent(current.postId, current.snapshot, gone), {
      budgetMs: -1,
    }),
    /not finished/u,
  );
  assert.deepEqual(await handlePagePostUnpublished(
    unpublishEvent(current.postId, current.snapshot, gone)), { deleted: 1, done: true });
  await assert.rejects(retirePagePostNotifications("a/b"), TypeError);
  await assert.rejects(retirePagePostNotifications(""), TypeError);
});

test("a block in either direction retires the blocked Page's rows", async () => {
  const current = await scene({ followers: 3 });
  const [blocksPage, blockedByPage, bystander] = current.followerIds;
  await handlePagePostCreated(postCreatedEvent(current));
  await drain(pagePostFanoutOutboxReference(current.postId));
  const second = await publishAndFanOut(current.pageId, "Drugi post");
  // Another Page the first follower also follows: its rows are not touched.
  const otherPage = freshUid("pg");
  await seedPage(db, otherPage, NOW, {
    page: { displayName: "Studio Fala" },
    user: { displayName: "Studio Fala" },
  });
  await seedFollowEdge(db, blocksPage, otherPage, NOW);
  const otherPost = await publishAndFanOut(otherPage, "Inna strona");
  // A row of another type that names the same actor is not this helper's.
  await db.doc(`users/${blocksPage}/notifications/pagePostComment_probe`).set({
    type: "pagePostComment",
    actorId: current.pageId,
    isRead: false,
  });

  // The follower blocks the Page.
  await runBlock(request(blocksPage, { targetUserId: current.pageId, blocked: true }));
  assert.equal(await rowExists(blocksPage, current.postId), false);
  assert.equal(await rowExists(blocksPage, second), false);
  assert.equal(await rowExists(blocksPage, otherPost), true);
  assert.equal(
    (await db.doc(`users/${blocksPage}/notifications/pagePostComment_probe`).get()).exists,
    true,
  );
  // The Page's owner blocks a follower.
  await runBlock(request(current.pageId, { targetUserId: blockedByPage, blocked: true }));
  assert.equal(await rowExists(blockedByPage, current.postId), false);
  assert.equal(await rowExists(blockedByPage, second), false);
  // Nobody else's inbox changed.
  assert.equal(await rowExists(bystander, current.postId), true);
  assert.equal(await rowExists(bystander, second), true);

  // Bounded and refusing nonsense.
  assert.deepEqual(await retirePagePostNotificationsBetween(bystander, bystander),
    { deleted: 0, done: true });
  assert.deepEqual(await retirePagePostNotificationsBetween("a/b", current.pageId),
    { deleted: 0, done: true });
  assert.deepEqual(
    await retirePagePostNotificationsBetween(bystander, current.pageId, {
      batchSize: 1,
      maxBatches: 1,
    }),
    { deleted: 1, done: false },
  );
});

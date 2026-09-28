// The Premium Pages READ contract (ADR-233 §2.5, §2.7), pure: the exact wire
// key sets the Flutter lane codes against, the stored post / comment shape,
// the cursor codec, the audience predicate and the follow-index helpers.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const { Timestamp } = require("firebase-admin/firestore");

const {
  FIND_PAGES_RESPONSE_KEYS,
  PAGES_FEED_RESPONSE_KEYS,
  PAGE_ABOUT_COMMUNITY_KEYS,
  PAGE_ABOUT_KEYS,
  PAGE_CARD_KEYS,
  PAGE_COMMENT_VIEW_KEYS,
  PAGE_HEADER_KEYS,
  PAGE_LINKED_SERVER_KEYS,
  PAGE_MEDIA_VIEW_KEYS,
  PAGE_POST_RESPONSE_KEYS,
  PAGE_POST_VIEW_KEYS,
  PAGE_RESPONSE_KEYS,
  PAGE_VIEWER_KEYS,
  commentView,
  decodeFindCursor,
  decodeItemCursor,
  encodeFindCursor,
  encodeItemCursor,
  feedResponse,
  findResponse,
  pageCard,
  pageHeader,
  pageHeaderState,
  pageResponse,
  postResponse,
  postView,
  viewerView,
} = require("../pages/views");
const {
  PAGE_POST_KEYS,
  canonicalPageCommentData,
  canonicalPagePostData,
  pageCount,
  pagePostMalformedReason,
} = require("../pages/post_contract");
const {
  pageAcceptsFollowers,
  pageViewDecision,
  visibilityHides,
} = require("../pages/audience");
const { readTimePageStatus } = require("../pages/lapse");
const {
  PAGE_FOLLOW_INDEX_MAX,
  canonicalPageFollowIndex,
  pageIdsAfterFollow,
  pageIdsAfterUnfollow,
} = require("../pages/follows");
const {
  DAY_MS,
  commentDoc,
  newCommentId,
  newPostId,
  pageDoc,
  pagesActivation,
  photoMedia,
  postDoc,
  testerGrant,
  voiceMedia,
} = require("./helpers/pages_fixture");
const { canonicalPagesActivation } = require("../pages/activation");

const NOW = 1_900_000_000_000;
const PAGE = "page-owner-views";
const VIEWER = "page-viewer-views";
const snap = (id, data) => ({ id, exists: data !== null, data: () => data });
const sorted = (value) => Object.keys(value).sort();

function invalidCursor(error) {
  assert.equal(error.code, "invalid-argument");
  assert.equal(error.message, "cursor is invalid.");
  return true;
}

// ------------------------------------------------------------- wire shapes

test("PostView is exact for text, photo and voice posts", () => {
  const page = pageDoc(PAGE, NOW);
  for (const [kind, media] of [
    ["text", () => []],
    ["photo", (postId) => photoMedia(PAGE, postId, 3)],
    ["voice", (postId) => voiceMedia(PAGE, postId)],
  ]) {
    const postId = newPostId();
    const post = canonicalPagePostData(snap(postId, postDoc(PAGE, postId, NOW, {
      kind,
      media: media(postId),
      likeCount: 4,
      commentCount: -3, // a broken counter reads as 0 (§1.7)
    })));
    assert.ok(post, kind);
    const view = postView(post, page, { callerLiked: true });
    assert.deepEqual(sorted(view), [...PAGE_POST_VIEW_KEYS]);
    assert.equal(view.pageName, page.displayName);
    assert.equal(view.pageKind, "business");
    assert.equal(view.createdAtMs, NOW);
    assert.equal(view.likeCount, 4);
    assert.equal(view.commentCount, 0);
    assert.equal(view.callerLiked, true);
    assert.equal(view.state, "published");
    assert.equal(view.pinned, false);
    for (const entry of view.media) {
      assert.deepEqual(sorted(entry), [...PAGE_MEDIA_VIEW_KEYS]);
      // No storage path, size or generation ever reaches a client.
      assert.equal("storagePath" in entry, false);
    }
    if (kind === "photo") {
      assert.deepEqual(view.media.map((entry) => [entry.width, entry.height, entry.durationMs]),
        [[1600, 1200, null], [1600, 1200, null], [1600, 1200, null]]);
    }
    if (kind === "voice") {
      assert.deepEqual([view.media[0].width, view.media[0].durationMs], [null, 12_000]);
    }
  }
});

test("PostView refuses removed and deleted posts; pinned follows the Page", () => {
  const postId = newPostId();
  const page = pageDoc(PAGE, NOW, { pinnedPostId: postId });
  const post = canonicalPagePostData(snap(postId, postDoc(PAGE, postId, NOW)));
  assert.equal(postView(post, page).pinned, true);
  for (const status of ["removed", "deleted"]) {
    const stamp = { removed: "removedAt", deleted: "deletedAt" }[status];
    const hidden = canonicalPagePostData(snap(postId, postDoc(PAGE, postId, NOW, {
      status,
      [stamp]: Timestamp.fromMillis(NOW),
    })));
    assert.ok(hidden);
    assert.throws(() => postView(hidden, page), TypeError);
  }
});

test("PageCard, PageHeader, viewer and CommentView are exact", () => {
  const business = pageDoc(PAGE, NOW, { postCount: 7, lastPostAt: Timestamp.fromMillis(NOW) });
  const card = pageCard(business, { followerCount: 12 }, { viewerFollows: true });
  assert.deepEqual(sorted(card), [...PAGE_CARD_KEYS]);
  assert.deepEqual([card.followerCount, card.lastPostAtMs, card.onYoVoiceSinceMs,
    card.viewerFollows], [12, NOW, NOW, true]);

  const header = pageHeader(business, { followerCount: "12" }, { effectiveStatus: "active" });
  assert.deepEqual(sorted(header), [...PAGE_HEADER_KEYS]);
  assert.deepEqual(sorted(header.about), [...PAGE_ABOUT_KEYS]);
  assert.equal(header.followerCount, 0);
  assert.equal(header.postCount, 7);
  assert.equal(header.about.community, null);
  assert.deepEqual(sorted(header.about.business),
    ["address", "email", "hours", "legalNotice", "phone", "website"]);

  const community = pageDoc(PAGE, NOW, {
    kind: "community",
    category: "fan_club",
    business: null,
    community: { rules: "Be kind.", linkedServerId: "srv_1" },
  });
  const unlinked = pageHeader(community, {}, { effectiveStatus: "active" });
  assert.deepEqual(sorted(unlinked.about.community), [...PAGE_ABOUT_COMMUNITY_KEYS]);
  assert.equal(unlinked.about.community.linkedServer, null, "a stored link alone is never shown");
  const linked = pageHeader(community, {}, {
    effectiveStatus: "active",
    linkedServer: { name: " Fans ", serverType: "community" },
  });
  assert.deepEqual(sorted(linked.about.community.linkedServer), [...PAGE_LINKED_SERVER_KEYS]);
  assert.deepEqual(linked.about.community.linkedServer,
    { serverId: "srv_1", name: "Fans", serverType: "community" });

  assert.deepEqual(sorted(viewerView({ isOwner: false })), [...PAGE_VIEWER_KEYS]);
  const post = canonicalPagePostData(snap(newPostId(), null));
  assert.equal(post, null);
  const parent = { postId: newPostId(), pageId: PAGE };
  const commentId = newCommentId();
  const comment = canonicalPageCommentData(snap(commentId, commentDoc(parent, commentId, PAGE, NOW)));
  const row = commentView(comment, { authorName: "Kawiarnia", pageId: PAGE });
  assert.deepEqual(sorted(row), [...PAGE_COMMENT_VIEW_KEYS]);
  assert.equal(row.isOwnPage, true);
});

test("responses are exact and hasMore mirrors nextCursor", () => {
  assert.deepEqual(sorted(feedResponse({ posts: [], nextCursor: null, suggestions: null })),
    [...PAGES_FEED_RESPONSE_KEYS]);
  assert.deepEqual(sorted(pageResponse({ page: null, viewer: null, pinned: null, posts: [],
    nextCursor: "x" })), [...PAGE_RESPONSE_KEYS]);
  assert.deepEqual(sorted(postResponse({ post: {}, comments: [], nextCommentCursor: null })),
    [...PAGE_POST_RESPONSE_KEYS]);
  assert.deepEqual(sorted(findResponse({ pages: [], nextCursor: null })),
    [...FIND_PAGES_RESPONSE_KEYS]);
  assert.equal(feedResponse({ posts: [], nextCursor: "c", suggestions: [] }).hasMore, true);
  assert.equal(pageResponse({ page: null, viewer: null, pinned: null, posts: [],
    nextCursor: null }).hasMore, false);
});

test("the owner sees the most severe state first; visitors only active or readOnly", () => {
  const base = pageDoc(PAGE, NOW);
  assert.equal(pageHeaderState(base, "active"), "active");
  assert.equal(pageHeaderState(base, "readOnly"), "readOnly");
  assert.equal(pageHeaderState({ ...base, ownerPaused: true }, "readOnly"), "paused");
  assert.equal(pageHeaderState({ ...base, ownerPaused: true }, "hidden"), "hidden");
  assert.equal(pageHeaderState({ ...base, suspended: true, ownerPaused: true }, "hidden"),
    "suspended");
});

// ---------------------------------------------------------------- stored

test("a post must be exact; one bad field makes it unreadable, never an error", () => {
  const postId = newPostId();
  const good = postDoc(PAGE, postId, NOW);
  assert.deepEqual(Object.keys(good).sort(), [...PAGE_POST_KEYS]);
  assert.equal(pagePostMalformedReason(good, postId), null);
  const photoId = newPostId();
  const cases = [
    [{ ...good, extra: 1 }, "keys"],
    [{ ...good, postId: newPostId() }, "postId"],
    [{ ...good, authorId: "someone-else" }, "identity"],
    [{ ...good, kind: "video" }, "kind"],
    [{ ...good, text: "   " }, "text"],
    [{ ...good, text: "x".repeat(5001) }, "text"],
    [{ ...good, kind: "photo" }, "media"],
    [{ ...good, status: "held" }, "heldAt"],
    [{ ...good, removedReason: "has spaces" }, "removedReason"],
    [{ ...good, createdAt: NOW }, "createdAt"],
  ];
  for (const [data, reason] of cases) {
    assert.equal(pagePostMalformedReason(data, postId), reason, reason);
    assert.equal(canonicalPagePostData(snap(postId, data)), null);
  }
  // Media binds to its own post path; PNG, a foreign path or 11 photos fail.
  const photos = photoMedia(PAGE, photoId, 1);
  const photo = postDoc(PAGE, photoId, NOW, { kind: "photo", media: photos });
  assert.equal(pagePostMalformedReason(photo, photoId), null);
  assert.equal(pagePostMalformedReason({ ...photo, media: [{ ...photos[0],
    contentType: "image/png" }] }, photoId), "media");
  assert.equal(pagePostMalformedReason({ ...photo, media: [{ ...photos[0],
    storagePath: `page_posts/${PAGE}/${newPostId()}/${photos[0].mediaId}.jpg` }] }, photoId),
  "media");
  assert.equal(pagePostMalformedReason({ ...photo, media: photoMedia(PAGE, photoId, 11) },
    photoId), "media");
  assert.equal(pageCount(-1), 0);
  assert.equal(pageCount(1.5), 0);
  assert.equal(pageCount(3), 3);
});

// ---------------------------------------------------------------- cursors

test("post and comment cursors round-trip and anything else is refused", () => {
  const postId = newPostId();
  const token = encodeItemCursor({ t: NOW, id: postId });
  assert.deepEqual(decodeItemCursor(token, "post"), { t: NOW, id: postId });
  assert.equal(decodeItemCursor(null, "post"), null);
  const commentId = newCommentId();
  assert.deepEqual(
    decodeItemCursor(encodeItemCursor({ t: 5, id: commentId }), "comment"),
    { t: 5, id: commentId },
  );
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  for (const bad of [
    "",
    "a b",
    "not base64 !!",
    7,
    {},
    "x".repeat(600),
    encode({ v: 1, t: NOW, id: "../../pages/other" }),
    encode({ v: 1, t: NOW, id: `pp_${"A".repeat(40)}` }),
    encode({ v: 1, t: -1, id: postId }),
    encode({ v: 1, t: 1.5, id: postId }),
    encode({ v: 1, t: "1", id: postId }),
    encode({ v: 2, t: NOW, id: postId }),
    encode({ v: 1, t: NOW, id: postId, extra: true }),
    encode([1, 2]),
    encode({ v: 1, t: NOW, id: commentId }),
    `${token}=`,
  ]) {
    assert.throws(() => decodeItemCursor(bad, "post"), invalidCursor, JSON.stringify(bad));
  }
  assert.throws(() => decodeItemCursor(token, "comment"), invalidCursor);
});

test("find cursors are bound to their mode", () => {
  const suggest = encodeFindCursor("suggest", { t: NOW, id: PAGE });
  assert.deepEqual(decodeFindCursor(suggest, "suggest"), { t: NOW, id: PAGE });
  assert.throws(() => decodeFindCursor(suggest, "search"), invalidCursor);
  const search = encodeFindCursor("search", { s: "kawiarnia", id: PAGE });
  assert.deepEqual(decodeFindCursor(search, "search"), { s: "kawiarnia", id: PAGE });
  const following = encodeFindCursor("following", { n: 20, id: PAGE });
  assert.deepEqual(decodeFindCursor(following, "following"), { n: 20, id: PAGE });
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  assert.throws(() => decodeFindCursor(encode({ v: 1, m: "following", n: 0, id: PAGE }),
    "following"), invalidCursor);
  assert.throws(() => decodeFindCursor(encode({ v: 1, m: "suggest", t: NOW, id: "a/b" }),
    "suggest"), invalidCursor);
});

// ---------------------------------------------------------------- audience

test("canViewPage: owner always; visitors only an active or readOnly, unpaused, unsuspended, unblocked Page", () => {
  const page = pageDoc(PAGE, NOW);
  const active = { status: "active" };
  const base = {
    viewerId: VIEWER,
    pageId: PAGE,
    page,
    pageUser: active,
    viewerUser: active,
    nowMs: NOW,
    lapseEnabled: true,
  };
  assert.deepEqual(pageViewDecision(base), { viewable: true, isOwner: false, status: "active" });
  const readOnly = { ...page, status: "readOnly", lapsedAt: Timestamp.fromMillis(NOW - DAY_MS) };
  assert.equal(pageViewDecision({ ...base, page: readOnly }).status, "readOnly");
  const expired = { ...readOnly, lapsedAt: Timestamp.fromMillis(NOW - 30 * DAY_MS) };
  assert.equal(readTimePageStatus(expired, NOW, true), "hidden");
  assert.equal(readTimePageStatus(expired, NOW, false), "readOnly", "lapseEnabled:false freezes");
  const refused = [
    { page: null },
    { page: expired },
    { page: { ...page, status: "hidden", lapsedAt: Timestamp.fromMillis(NOW) } },
    { page: { ...page, ownerPaused: true } },
    { page: { ...page, suspended: true } },
    { pageUser: { status: "deleted" } },
    { pageUser: null },
    { viewerUser: { banned: true } },
    { viewerBlocksPage: true },
    { pageBlocksViewer: true },
    { visibility: { notViewable: new Map([[PAGE, "paused"]]), readOnlySince: new Map() } },
  ];
  for (const change of refused) {
    assert.equal(pageViewDecision({ ...base, ...change }).viewable, false, JSON.stringify(change));
  }
  // The owner sees every state of their own Page.
  const ownerView = pageViewDecision({
    ...base,
    viewerId: PAGE,
    page: { ...page, suspended: true, ownerPaused: true },
  });
  assert.deepEqual(ownerView, { viewable: true, isOwner: true, status: "active" });
  assert.equal(visibilityHides({
    notViewable: new Map(),
    readOnlySince: new Map([[PAGE, NOW - 31 * DAY_MS]]),
  }, PAGE, NOW, true), true);
  assert.equal(visibilityHides({
    notViewable: new Map(),
    readOnlySince: new Map([[PAGE, NOW - 31 * DAY_MS]]),
  }, PAGE, NOW, false), false);
});

test("a Page accepts followers only while readable, running and live-active (D14)", () => {
  const activation = canonicalPagesActivation({ exists: true, data: () => pagesActivation() });
  const base = {
    callerId: VIEWER,
    activation,
    page: pageDoc(PAGE, NOW),
    pageUser: { status: "active" },
    pageEntitlement: null,
    pageGrant: testerGrant(),
    nowMs: NOW,
  };
  assert.equal(pageAcceptsFollowers(base), true);
  for (const change of [
    { activation: canonicalPagesActivation({ exists: false }) },
    { activation: canonicalPagesActivation({ exists: true,
      data: () => pagesActivation({ readAccess: "testers", writeAccess: "testers",
        testerUids: [PAGE] }) }) },
    { page: { ...base.page, ownerPaused: true } },
    { page: { ...base.page, suspended: true } },
    { pageGrant: null },
    { pageGrant: testerGrant({ expiresAt: Timestamp.fromMillis(NOW - 1) }) },
    { pageGrant: testerGrant({ revoked: true }) },
    { page: null },
  ]) {
    assert.equal(pageAcceptsFollowers({ ...base, ...change }), false, JSON.stringify(change));
  }
  // lapseEnabled:false freezes the downgrade: a stored-active Page keeps
  // taking follows until an operator re-enables lapse.
  const frozen = canonicalPagesActivation({ exists: true,
    data: () => pagesActivation({ lapseEnabled: false }) });
  assert.equal(pageAcceptsFollowers({ ...base, activation: frozen, pageGrant: null }), true);
});

// ---------------------------------------------------------------- index

test("the follow index is repaired, bounded and ordered oldest first", () => {
  const at = Timestamp.fromMillis(NOW);
  const exact = canonicalPageFollowIndex(snap(VIEWER, {
    schemaVersion: 1,
    pageIds: ["a", "b"],
    updatedAt: at,
  }), VIEWER);
  assert.deepEqual([exact.exists, exact.malformed, [...exact.pageIds]], [true, false, ["a", "b"]]);
  const broken = canonicalPageFollowIndex(snap(VIEWER, {
    schemaVersion: 1,
    pageIds: ["a", "a/b", VIEWER, "b", "a", 7],
    updatedAt: at,
    stray: true,
  }), VIEWER);
  assert.deepEqual([broken.malformed, [...broken.pageIds]], [true, ["b", "a"]]);
  assert.deepEqual(canonicalPageFollowIndex(snap(VIEWER, null), VIEWER).pageIds, []);
  assert.deepEqual(pageIdsAfterFollow(["a", "b", "c"], "a"), ["b", "c", "a"]);
  assert.deepEqual(pageIdsAfterUnfollow(["a", "b"], "a"), ["b"]);
  const full = Array.from({ length: PAGE_FOLLOW_INDEX_MAX }, (_, index) => `p${index}`);
  const after = pageIdsAfterFollow(full, "new");
  assert.equal(after.length, PAGE_FOLLOW_INDEX_MAX);
  assert.deepEqual([after[0], after.at(-1)], ["p1", "new"]);
});

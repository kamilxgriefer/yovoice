// Server-side feed ranking, exercised through the real callable.
//
// The three properties this file exists to pin:
//   1. Ranking decides ORDER, never eligibility. No ranking signal, however
//      strong, can surface a Reel the viewer is not entitled to see.
//   2. Paging shows no duplicates and skips nothing, with ranking on.
//   3. Two opens by the same viewer give different orders, while one paging
//      session stays stable.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const { FEED_CURSOR_PATTERN } = require("../reels/contract");
const { FEED_RANKING } = require("../reels/ranking");
const { createReelService } = require("../reels/service");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const HOUR_MS = 60 * 60 * 1000;
const VIEWER = "viewer-1";

function composition() {
  return {
    caption: "A real Reel",
    crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
    filter: "original",
    trimStartMs: 0,
    trimEndMs: 0,
    textOverlays: [],
    linkOverlays: [],
    originalAudioVolume: 0,
    backingAudioVolume: 0,
    audioTrimStartMs: 0,
    audioRightsAttested: false,
    audioAttribution: "",
  };
}

function sortKeyFor(rank, id) {
  return `${String(NOW_MS - rank).padStart(13, "0")}_${id}`;
}

// A fixture with an injectable seed sequence. Feed ranking without a seam on
// the randomness is flaky by construction — every ordering assertion below
// depends on knowing exactly which seed a request was built with.
function fixture({ seeds = ["0000000000000001"] } = {}) {
  const db = new InMemoryFirestore();
  db.seed(`users/${VIEWER}`, { uid: VIEWER, displayName: "Viewer" });
  const minted = [];
  let index = 0;
  const storage = {
    getMetadata: async () => ({}),
    readHeader: async () => Buffer.alloc(0),
    revokeDownloadTokens: async () => {},
    getSignedReadUrl: async () => "https://storage.googleapis.com/bucket/file",
    deleteObject: async () => {},
  };
  const service = createReelService({
    db,
    FieldPath: { documentId: () => "__name__" },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage,
    clock: () => NOW_MS,
    randomSeed: () => {
      const seed = seeds[Math.min(index, seeds.length - 1)];
      index += 1;
      minted.push(seed);
      return seed;
    },
  });

  function seedAuthor(authorId, profile = {}) {
    db.seed(`users/${authorId}`, { uid: authorId, ...profile });
  }

  function seedReel({
    id,
    authorId,
    rank = 0,
    publishedAtMs = NOW_MS,
    likeCount,
    commentCount,
  }) {
    seedAuthor(authorId);
    db.seed(`reels/${id}`, {
      schemaVersion: 1,
      status: "published",
      moderationStatus: "visible",
      authorId,
      authorName: `Creator ${authorId}`,
      media: {
        kind: "image",
        contentType: "image/jpeg",
        size: 1024,
        generation: "123",
        durationMs: 0,
        storagePath: `reels/${authorId}/${id}/media.jpg`,
      },
      backingAudio: null,
      composition: composition(),
      sortKey: sortKeyFor(rank, id),
      publishedAt: new Date(publishedAtMs),
      updatedAt: new Date(publishedAtMs),
      ...(likeCount === undefined ? {} : { likeCount }),
      ...(commentCount === undefined ? {} : { commentCount }),
    });
    return id;
  }

  function seedSeen(reelId, viewedAtMs) {
    db.seed(`users/${VIEWER}/reelViews/${reelId}`, {
      viewedAt: new Date(viewedAtMs),
      expiresAt: new Date(viewedAtMs + 90 * 24 * HOUR_MS),
    });
  }

  return { db, service, minted, seedAuthor, seedReel, seedSeen };
}

function request({ cursor = null, limit = 20, ...rest } = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: { cursor, limit, ...rest },
  };
}

async function drain(service, { limit, ...rest }) {
  const pages = [];
  let cursor = null;
  for (let page = 0; page < 40; page += 1) {
    const result = await service.listReelsV2(request({ cursor, limit, ...rest }));
    pages.push(result);
    cursor = result.nextCursor;
    if (cursor === null) return pages;
  }
  throw new Error("feed paging did not terminate");
}

test("ranking is enabled by default so these assertions mean something", () => {
  assert.equal(FEED_RANKING.enabled, true);
  assert.equal(FEED_RANKING.version, "feed-ranking-v1");
});

test("no ranking signal can surface a Reel the viewer may not see", async () => {
  const scenario = fixture();
  // Every hidden author below gets the MAXIMUM ranking treatment a viewer can
  // produce: a friend edge, a follow edge, saturating counters and the
  // freshest possible timestamp. If ranking were an authorization path, these
  // are exactly the Reels that would leak.
  const hidden = [
    { id: "hidden-viewer-blocked", authorId: "author-viewer-blocked" },
    { id: "hidden-author-blocked", authorId: "author-author-blocked" },
    { id: "hidden-restricted", authorId: "author-restricted" },
    { id: "hidden-disabled", authorId: "author-disabled" },
  ];
  hidden.forEach(({ id, authorId }, index) => {
    scenario.seedReel({
      id,
      authorId,
      rank: index,
      likeCount: 5000,
      commentCount: 5000,
    });
    scenario.db.seed(`users/${VIEWER}/friends/${authorId}`, {
      userId: authorId,
    });
    scenario.db.seed(`users/${VIEWER}/following/${authorId}`, {
      userId: authorId,
    });
  });
  scenario.db.seed(`users/${VIEWER}/blocked/author-viewer-blocked`, {
    createdAt: new Date(NOW_MS),
  });
  scenario.db.seed("users/author-author-blocked/blocked/" + VIEWER, {
    createdAt: new Date(NOW_MS),
  });
  scenario.db.seed("restrictions/author-restricted", {
    type: "communicationMute",
    expiresAt: null,
  });
  scenario.db.seed("users/author-disabled", {
    uid: "author-disabled",
    disabled: true,
  });
  // The one entitled Reel is deliberately the WEAKEST ranking candidate:
  // three weeks old, no engagement, no edges.
  scenario.seedReel({
    id: "visible",
    authorId: "plain-author",
    rank: 9,
    publishedAtMs: NOW_MS - 21 * 24 * HOUR_MS,
  });

  const page = await scenario.service.listReelsV2(request({ limit: 20 }));
  assert.deepEqual(page.items.map(({ id }) => id), ["visible"]);
  assert.equal(page.schemaVersion, 2);
});

test("a viewer's own seen ledger cannot promote or reveal anything", async () => {
  const scenario = fixture();
  scenario.seedReel({ id: "blocked-reel", authorId: "blocked-author", rank: 0 });
  scenario.db.seed(`users/${VIEWER}/blocked/blocked-author`, {
    createdAt: new Date(NOW_MS),
  });
  // A forged/corrupt seen row on an unauthorized Reel changes nothing: the
  // ranking snapshot is never consulted for eligibility, and a malformed one
  // contributes no weight at all.
  scenario.db.seed(`users/${VIEWER}/reelViews/blocked-reel`, {
    viewedAt: "not-a-timestamp",
    expiresAt: null,
    forged: true,
  });
  scenario.seedReel({ id: "open-reel", authorId: "open-author", rank: 1 });
  scenario.db.seed(`users/${VIEWER}/reelViews/open-reel`, {
    viewedAt: "not-a-timestamp",
  });

  const page = await scenario.service.listReelsV2(request({ limit: 20 }));
  // The corrupt row on open-reel must NOT suppress it — suppression may only
  // act on a successfully read, valid, recent record.
  assert.deepEqual(page.items.map(({ id }) => id), ["open-reel"]);
});

test("only a complete, current seen row matching the real retention contract can suppress", async () => {
  const recent = new Date(NOW_MS - 1000);
  const expiry = new Date(NOW_MS + 90 * 24 * HOUR_MS);
  for (const row of [
    { viewedAt: recent },
    { viewedAt: recent, expiresAt: null },
    { viewedAt: recent, expiresAt: expiry, forged: true },
    { viewedAt: new Date(NOW_MS + HOUR_MS), expiresAt: expiry },
    { viewedAt: recent, expiresAt: new Date(NOW_MS - 1) },
    { viewedAt: recent, expiresAt: new Date(NOW_MS + 365 * 24 * HOUR_MS) },
    { viewedAt: recent, expiresAt: new Date(NOW_MS + HOUR_MS) },
  ]) {
    const scenario = fixture();
    scenario.seedReel({ id: "invalid-seen", authorId: "seen-author" });
    scenario.db.seed(`users/${VIEWER}/reelViews/invalid-seen`, row);
    const page = await scenario.service.listReelsV2(request());
    assert.deepEqual(page.items.map(({ id }) => id), ["invalid-seen"]);
  }
});

test("paging with ranking on shows no duplicates and skips nothing", async () => {
  const scenario = fixture({ seeds: ["00000000000000aa"] });
  const expected = [];
  // Four authors keeps every page inside MAX_REEL_AUTHORS_PER_REQUEST while
  // still forcing several batches through MAX_REEL_SCAN_PER_REQUEST.
  for (let index = 0; index < 12; index += 1) {
    const id = `paged-${String(index).padStart(2, "0")}`;
    expected.push(scenario.seedReel({
      id,
      authorId: `paged-author-${index % 4}`,
      rank: index,
      publishedAtMs: NOW_MS - index * HOUR_MS,
      likeCount: index * 3,
      commentCount: index % 5,
    }));
  }

  const pages = await drain(scenario.service, { limit: 3 });
  const seen = pages.flatMap(({ items }) => items.map(({ id }) => id));
  assert.equal(new Set(seen).size, seen.length, "no Reel appears twice");
  assert.deepEqual(new Set(seen), new Set(expected), "no Reel is skipped");
  assert.equal(seen.length, 12);
  assert.equal(pages.at(-1).nextCursor, null);
  // Every emitted cursor is the new opaque grammar, and every page after the
  // first carries the seed the session was minted with.
  const seeds = new Set();
  for (const { nextCursor } of pages) {
    if (nextCursor === null) continue;
    assert.match(nextCursor, FEED_CURSOR_PATTERN);
    seeds.add(nextCursor.split(".")[2]);
  }
  assert.deepEqual([...seeds], ["00000000000000aa"]);
  assert.deepEqual(scenario.minted, ["00000000000000aa"]);
});

test("ranking actually reorders the page away from pure recency", async () => {
  const scenario = fixture({ seeds: ["00000000000000aa"] });
  const chronological = [];
  for (let index = 0; index < 12; index += 1) {
    const id = `paged-${String(index).padStart(2, "0")}`;
    chronological.push(scenario.seedReel({
      id,
      authorId: `paged-author-${index % 4}`,
      rank: index,
      publishedAtMs: NOW_MS - index * HOUR_MS,
    }));
  }
  const page = await scenario.service.listReelsV2(request({ limit: 12 }));
  assert.equal(page.items.length, 12);
  assert.notDeepEqual(page.items.map(({ id }) => id), chronological);
  assert.deepEqual(
    new Set(page.items.map(({ id }) => id)),
    new Set(chronological),
  );
});

test("two opens give different orders while one paging session stays stable",
  async () => {
    // Same author, same instant, no engagement: recency, engagement and
    // affinity all tie exactly, so the seeded jitter alone decides the order.
    // That isolates the property under test instead of hiding it behind the
    // other four terms.
    function seeded(seed) {
      const scenario = fixture({ seeds: [seed] });
      for (let index = 0; index < 10; index += 1) {
        scenario.seedReel({
          id: `shuffle-${String(index).padStart(2, "0")}`,
          authorId: "shuffle-author",
          rank: index,
        });
      }
      return scenario;
    }

    const firstOpen = seeded("1111111111111111");
    const secondOpen = seeded("2222222222222222");
    const firstPage = await firstOpen.service.listReelsV2(request({ limit: 10 }));
    const secondPage = await secondOpen.service.listReelsV2(request({ limit: 10 }));
    assert.equal(firstPage.items.length, 10);
    assert.equal(secondPage.items.length, 10);
    assert.notDeepEqual(
      firstPage.items.map(({ id }) => id),
      secondPage.items.map(({ id }) => id),
      "a fresh open must mint a fresh seed and reshuffle",
    );
    assert.deepEqual(
      new Set(firstPage.items.map(({ id }) => id)),
      new Set(secondPage.items.map(({ id }) => id)),
      "a reshuffle is a permutation, never a different candidate set",
    );

    // Within one session the order is reproducible: replaying the same cursor
    // replays the same seed, so a retry after a dropped response cannot
    // silently reorder the feed under the reader.
    const session = seeded("3333333333333333");
    const page1 = await session.service.listReelsV2(request({ limit: 4 }));
    assert.match(page1.nextCursor, FEED_CURSOR_PATTERN);
    const page2a = await session.service.listReelsV2(
      request({ cursor: page1.nextCursor, limit: 4 }),
    );
    const page2b = await session.service.listReelsV2(
      request({ cursor: page1.nextCursor, limit: 4 }),
    );
    assert.deepEqual(
      page2a.items.map(({ id }) => id),
      page2b.items.map(({ id }) => id),
    );
    assert.equal(page1.nextCursor.split(".")[2], "3333333333333333");
    assert.equal(page2a.nextCursor.split(".")[2], "3333333333333333");
    // One seed for the whole session, minted once.
    assert.deepEqual(session.minted, ["3333333333333333"]);
    const across = [
      ...page1.items.map(({ id }) => id),
      ...page2a.items.map(({ id }) => id),
    ];
    assert.equal(new Set(across).size, across.length);
  });

test("a legacy in-flight cursor keeps paging instead of restarting", async () => {
  const scenario = fixture({ seeds: ["4444444444444444"] });
  for (let index = 0; index < 6; index += 1) {
    scenario.seedReel({
      id: `legacy-${index}`,
      authorId: `legacy-author-${index % 3}`,
      rank: index,
    });
  }
  const first = await scenario.service.listReelsV2(request({ limit: 2 }));
  const position = first.nextCursor.split(".")[3];
  // Exactly what an app that was mid-session across an update replays.
  const resumed = await scenario.service.listReelsV2(
    request({ cursor: position, limit: 2 }),
  );
  assert.equal(resumed.items.length, 2);
  assert.match(resumed.nextCursor, FEED_CURSOR_PATTERN);
  for (const { id } of resumed.items) {
    assert.ok(!first.items.some((item) => item.id === id));
  }
  // No new session was minted for the resumed page: the seed is derived.
  assert.deepEqual(scenario.minted, ["4444444444444444"]);
});

test("a recently seen Reel is suppressed, and includeSeen brings it back",
  async () => {
    function seeded() {
      const scenario = fixture({ seeds: ["5555555555555555"] });
      for (let index = 0; index < 5; index += 1) {
        scenario.seedReel({
          id: `seen-${index}`,
          authorId: "seen-author",
          rank: index,
        });
      }
      // Two watched an hour ago (inside SEEN_HIDE_MS), one watched twelve
      // hours ago (outside it — kept, merely ranked down).
      scenario.seedSeen("seen-0", NOW_MS - HOUR_MS);
      scenario.seedSeen("seen-1", NOW_MS - HOUR_MS);
      scenario.seedSeen("seen-4", NOW_MS - 12 * HOUR_MS);
      return scenario;
    }

    const suppressed = await seeded().service.listReelsV2(request({ limit: 10 }));
    assert.deepEqual(
      new Set(suppressed.items.map(({ id }) => id)),
      new Set(["seen-2", "seen-3", "seen-4"]),
    );
    // Suppression is a viewer preference, not an eligibility decision: the
    // scan still consumed those entries, so the page is simply shorter.
    assert.equal(suppressed.items.length, 3);

    const everything = await seeded().service.listReelsV2(
      request({ limit: 10, includeSeen: true }),
    );
    assert.equal(everything.items.length, 5);
    assert.equal(everything.nextCursor, null);
    // "Show everything again" is its own session mode, so its cursor cannot
    // be replayed against the suppressing one.
    const includeSeenPage = await seeded().service.listReelsV2(
      request({ limit: 2, includeSeen: true }),
    );
    assert.equal(includeSeenPage.nextCursor.split(".")[1], "s");
    await assert.rejects(
      seeded().service.listReelsV2(
        request({ cursor: includeSeenPage.nextCursor, limit: 2 }),
      ),
      (error) =>
        error.code === "invalid-argument" &&
        error.message === "cursor is invalid.",
    );
  });

test("a Reel seen long ago is kept but ranked below an unseen sibling",
  async () => {
    const scenario = fixture({ seeds: ["6666666666666666"] });
    for (let index = 0; index < 8; index += 1) {
      scenario.seedReel({
        id: `decay-${index}`,
        authorId: "decay-author",
        rank: index,
      });
    }
    // Just outside the suppression window, so the penalty is nearly maximal
    // while the row is still emitted.
    for (let index = 0; index < 4; index += 1) {
      scenario.seedSeen(`decay-${index}`, NOW_MS - 7 * HOUR_MS);
    }
    const page = await scenario.service.listReelsV2(request({ limit: 8 }));
    assert.equal(page.items.length, 8);
    const positions = new Map(
      page.items.map(({ id }, position) => [id, position]),
    );
    const worstUnseen = Math.max(
      ...[4, 5, 6, 7].map((index) => positions.get(`decay-${index}`)),
    );
    const bestSeen = Math.min(
      ...[0, 1, 2, 3].map((index) => positions.get(`decay-${index}`)),
    );
    assert.ok(
      worstUnseen < bestSeen,
      "W_SEEN must dominate jitter for an all-else-equal page",
    );
  });

test("Your Reels is server-filtered, complete and deliberately not shuffled",
  async () => {
    const scenario = fixture({ seeds: ["7777777777777777"] });
    const own = [];
    for (let index = 0; index < 5; index += 1) {
      own.push(scenario.seedReel({
        id: `own-${index}`,
        authorId: VIEWER,
        rank: index * 2,
      }));
      scenario.seedReel({
        id: `other-${index}`,
        authorId: `other-author-${index}`,
        rank: index * 2 + 1,
      });
    }
    // Even a Reel of your own that you just watched stays in your library.
    scenario.seedSeen("own-0", NOW_MS - 60 * 1000);

    const page = await scenario.service.listReelsV2(
      request({ limit: 10, scope: "own" }),
    );
    assert.deepEqual(page.items.map(({ id }) => id), own);
    assert.equal(page.items.length, 5);
    assert.equal(page.nextCursor, null);
    for (const item of page.items) assert.equal(item.authorId, VIEWER);

    const paged = await drain(scenario.service, { limit: 2, scope: "own" });
    assert.deepEqual(paged.flatMap(({ items }) => items.map(({ id }) => id)), own);
    for (const { nextCursor } of paged) {
      if (nextCursor !== null) assert.equal(nextCursor.split(".")[1], "o");
    }
  });

test("Your Reels rejects includeSeen instead of quietly ignoring it", async () => {
  const scenario = fixture();
  await assert.rejects(
    scenario.service.listReelsV2(
      request({ limit: 5, scope: "own", includeSeen: true }),
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    scenario.service.listReelsV2(request({ limit: 5, scope: "everyone" })),
    (error) =>
      error.code === "invalid-argument" && error.message === "scope is invalid.",
  );
  await assert.rejects(
    scenario.service.listReelsV2(request({ limit: 5, includeSeen: "yes" })),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    scenario.service.listReelsV2(request({ limit: 5, feedSession: "x" })),
    (error) =>
      error.code === "invalid-argument" &&
      error.message === "Unsupported field: feedSession.",
  );
});

test("a discover cursor cannot be replayed against Your Reels", async () => {
  const scenario = fixture({ seeds: ["8888888888888888"] });
  for (let index = 0; index < 4; index += 1) {
    scenario.seedReel({ id: `mix-${index}`, authorId: VIEWER, rank: index });
  }
  const discover = await scenario.service.listReelsV2(request({ limit: 2 }));
  assert.equal(discover.nextCursor.split(".")[1], "d");
  await assert.rejects(
    scenario.service.listReelsV2(
      request({ cursor: discover.nextCursor, limit: 2, scope: "own" }),
    ),
    (error) =>
      error.code === "invalid-argument" && error.message === "cursor is invalid.",
  );
});

test("v1 stays byte-frozen: pure recency, bare cursor, two-key input", async () => {
  const scenario = fixture({ seeds: ["9999999999999999"] });
  const chronological = [];
  for (let index = 0; index < 6; index += 1) {
    chronological.push(scenario.seedReel({
      id: `frozen-${index}`,
      authorId: `frozen-author-${index % 3}`,
      rank: index,
      likeCount: index * 7,
    }));
  }
  const page = await scenario.service.listReels(request({ limit: 4 }));
  assert.deepEqual(page.items.map(({ id }) => id), chronological.slice(0, 4));
  assert.equal(page.nextCursor, sortKeyFor(3, "frozen-3"));
  assert.equal(Object.hasOwn(page, "schemaVersion"), false);
  assert.equal(FEED_CURSOR_PATTERN.test(page.nextCursor), false);
  // v1 never mints a session seed, and never reads a ranking document.
  assert.deepEqual(scenario.minted, []);
  assert.equal(
    scenario.db.paths(`users/${VIEWER}/reelViews`).length,
    0,
  );
  await assert.rejects(
    scenario.service.listReels(request({ limit: 4, scope: "own" })),
    (error) =>
      error.code === "invalid-argument" &&
      error.message === "Unsupported field: scope.",
  );
  await assert.rejects(
    scenario.service.listReels(
      request({ limit: 4, cursor: `f1.d.9999999999999999.${sortKeyFor(0, "x")}` }),
    ),
    (error) => error.code === "invalid-argument",
  );
});

test("Your Reels and v1 read no ranking documents at all", async () => {
  const scenario = fixture({ seeds: ["aaaaaaaaaaaaaaaa"] });
  for (let index = 0; index < 4; index += 1) {
    scenario.seedReel({ id: `cost-${index}`, authorId: VIEWER, rank: index });
  }
  const before = scenario.db.metrics.getAllDocumentReads;
  await scenario.service.listReelsV2(request({ limit: 4, scope: "own" }));
  const ownReads = scenario.db.metrics.getAllDocumentReads - before;
  await scenario.service.listReelsV2(request({ limit: 4 }));
  const discoverReads =
    scenario.db.metrics.getAllDocumentReads - before - ownReads;
  // Discover adds one reelViews document per candidate plus two social-graph
  // documents per distinct author. Your Reels pays none of that.
  assert.equal(discoverReads - ownReads, 4 + 2);
});

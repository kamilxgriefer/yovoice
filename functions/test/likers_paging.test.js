// ADR-230 §3.0: the normative likers scan loop, exact input and response.
const assert = require("node:assert/strict");
const { describe, test } = require("node:test");
const { HttpsError } = require("firebase-functions/v2/https");

const { ALLOWED_DIRECT_REACTIONS } = require("../messaging/direct_integrity");
const { likerResolver } = require("../engagement/liker_audience");
const { likersTargetKey } = require("../engagement/liker_cursors");
const {
  LIKERS_MAX_FETCHED,
  LIKERS_PAGE_SIZE,
  LIKERS_RESPONSE_KEYS,
  LIKERS_SCAN_CAP,
  LIKER_ROW_KEYS,
  inMemoryCandidateFetcher,
  likersPageResponse,
  queryCandidateFetcher,
  requireLikersListInput,
  runLikersPage,
  scanLikersPage,
  serverReactionCandidates,
} = require("../engagement/likers_paging");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");
const { tracked } = require("./helpers/read_tracker");

const NOW_MS = 1_820_000_000_000;
const VIEWER = "viewer-uid";
const Timestamp = Object.freeze({ fromMillis: (millis) => new Date(millis) });
const timing = Object.freeze({ nowMs: NOW_MS, now: new Date(NOW_MS) });

// `pattern` is a string of "v" (visible) and "h" (hidden) in list order.
function candidates(pattern) {
  return [...pattern].map((kind, index) => ({
    position: index,
    likerId: `${kind === "v" ? "visible" : "hidden"}-${String(index).padStart(3, "0")}`,
    reaction: null,
  }));
}

function fetcherOf(list, calls = []) {
  const inner = inMemoryCandidateFetcher(list, (left, right) => left - right);
  return async (after, want) => {
    calls.push({ after, want });
    return inner(after, want);
  };
}

async function resolveStub(take) {
  return take.map((candidate) =>
    candidate.likerId !== null && candidate.likerId.startsWith("visible")
      ? { userId: candidate.likerId, displayName: "N", photoUrl: null, reaction: null }
      : null);
}

async function page(list, after = null, calls = []) {
  return scanLikersPage({
    after,
    fetchCandidates: fetcherOf(list, calls),
    resolveVisible: resolveStub,
  });
}

async function allPages(list) {
  const pages = [];
  let after = null;
  for (let guard = 0; guard < 50; guard += 1) {
    const result = await page(list, after);
    pages.push(result);
    if (!result.hasMore) return pages;
    after = result.lastConsumed;
  }
  throw new Error("pagination did not terminate");
}

describe("the scan loop", () => {
  test("25 visible among 30: page 2 starts at the 21st visible", async () => {
    // Hidden likers interleaved: positions 3, 9, 14, 22, 27.
    const pattern = [..."v".repeat(30)].map((kind, index) =>
      [3, 9, 14, 22, 27].includes(index) ? "h" : kind).join("");
    const list = candidates(pattern);
    const visible = list.filter((c) => c.likerId.startsWith("visible")).map((c) => c.likerId);
    assert.equal(visible.length, 25);
    const first = await page(list);
    assert.deepEqual(first.likers.map((row) => row.userId), visible.slice(0, 20));
    assert.equal(first.hasMore, true);
    // The cursor sits on the last CONSUMED candidate (the 20th visible),
    // never after fetched-but-unconsumed ones.
    assert.equal(list[first.lastConsumed].likerId, visible[19]);
    const second = await page(list, first.lastConsumed);
    assert.deepEqual(second.likers.map((row) => row.userId), visible.slice(20));
    assert.equal(second.hasMore, false);
  });

  test("hidden runs: a short page only at >= 41 hidden within 60", async () => {
    for (const hidden of [10, 40, 41, 59, 60, 61]) {
      const list = candidates("h".repeat(hidden) + "v".repeat(30));
      const first = await page(list);
      const expected = Math.max(0, Math.min(LIKERS_PAGE_SIZE, LIKERS_SCAN_CAP - hidden));
      assert.equal(first.likers.length, expected, `hidden ${hidden}`);
      assert.equal(first.hasMore, true, `hidden ${hidden}`);
      assert.ok(first.consumed <= LIKERS_SCAN_CAP, `hidden ${hidden}`);
      assert.ok(first.fetched <= LIKERS_MAX_FETCHED, `hidden ${hidden}`);
      if (hidden >= 41) assert.equal(first.consumed, LIKERS_SCAN_CAP, `hidden ${hidden}`);
      // Every visible liker is listed exactly once across all pages.
      const listed = (await allPages(list)).flatMap((result) =>
        result.likers.map((row) => row.userId));
      assert.deepEqual(
        listed,
        list.filter((c) => c.likerId.startsWith("visible")).map((c) => c.likerId),
        `hidden ${hidden}`,
      );
    }
  });

  test("hasMore is exact at chunk edges and with the sentinel", async () => {
    const cases = [
      ["", 0, false],
      ["v".repeat(19), 19, false],
      ["v".repeat(20), 20, false],
      ["v".repeat(21), 20, true],
      ["h".repeat(20), 0, false],
      ["h".repeat(40), 0, false],
      ["h".repeat(60), 0, false],
      ["h".repeat(61), 0, true],
      ["h".repeat(20) + "v".repeat(20), 20, false],
      ["h".repeat(20) + "v".repeat(21), 20, true],
      ["h".repeat(40) + "v".repeat(20), 20, false],
      ["h".repeat(40) + "v".repeat(21), 20, true],
      ["v".repeat(20) + "h", 20, true],
    ];
    for (const [pattern, listed, hasMore] of cases) {
      const result = await page(candidates(pattern));
      assert.equal(result.likers.length, listed, pattern.length + pattern.slice(-1));
      assert.equal(result.hasMore, hasMore, `${pattern.length}:${pattern}`);
    }
  });

  test("fetches in chunks of 21 with the MAX+1 sentinel, never past the cap", async () => {
    const calls = [];
    await page(candidates("h".repeat(100)), null, calls);
    assert.deepEqual(calls.map((call) => call.want), [21, 21, 21]);
    assert.deepEqual(calls.map((call) => call.after), [null, 19, 39]);
  });

  test("a malformed edge is skipped but consumed", async () => {
    const list = candidates("v".repeat(25));
    list[0].likerId = null;
    list[5].likerId = null;
    const first = await page(list);
    assert.equal(first.likers.length, 20);
    assert.equal(first.lastConsumed, 21);
    const second = await page(list, first.lastConsumed);
    assert.equal(second.likers.length, 3);
    assert.equal(second.hasMore, false);
  });
});

describe("exact input", () => {
  test("a `limit` key is invalid-argument on every family", () => {
    const bases = {
      voiceMoment: { momentId: "moment-1" },
      reel: { reelId: "reel-1" },
      serverMessage: { serverId: "s", channelId: "c", messageId: "m" },
    };
    for (const [family, data] of Object.entries(bases)) {
      assert.throws(
        () => requireLikersListInput(family, { ...data, limit: 5 }),
        (error) => error instanceof HttpsError && error.code === "invalid-argument",
        family,
      );
      assert.doesNotThrow(() => requireLikersListInput(family, data), family);
    }
  });

  test("targets, comment ids, emoji and cursors are normalized", () => {
    assert.deepEqual(requireLikersListInput("voiceMoment", { momentId: "m1" }), {
      targetType: "voiceMoment",
      ids: ["m1"],
      emoji: null,
      cursor: null,
      momentId: "m1",
      commentId: null,
    });
    assert.equal(
      requireLikersListInput("voiceMoment", { momentId: "m1", commentId: null }).targetType,
      "voiceMoment",
    );
    assert.deepEqual(
      requireLikersListInput("reel", { reelId: "r1", commentId: "c1" }).ids,
      ["r1", "c1"],
    );
    assert.equal(
      requireLikersListInput("reel", { reelId: "r1", commentId: "c1" }).targetType,
      "reelComment",
    );
    const server = requireLikersListInput("serverMessage", {
      serverId: "s", channelId: "c", messageId: "m", emoji: "🔥", cursor: "A".repeat(43),
    });
    assert.equal(server.emoji, "🔥");
    assert.equal(server.cursor, "A".repeat(43));
    const invalid = [
      ["voiceMoment", {}],
      ["voiceMoment", { momentId: "a/b" }],
      ["voiceMoment", { momentId: "m", commentId: 7 }],
      ["voiceMoment", { momentId: "m", cursor: "short" }],
      ["voiceMoment", { momentId: "m", cursor: 12 }],
      ["reel", { reelId: "r", emoji: "❤️" }],
      ["serverMessage", { serverId: "s", channelId: "c", messageId: "m", emoji: "🍕" }],
      ["serverMessage", { serverId: "s", channelId: "c" }],
      ["serverMessage", null],
    ];
    for (const [family, data] of invalid) {
      assert.throws(
        () => requireLikersListInput(family, data),
        (error) => error instanceof HttpsError && error.code === "invalid-argument",
        `${family} ${JSON.stringify(data)}`,
      );
    }
  });
});

describe("response", () => {
  test("exact keys, null photo, hasMore === (nextCursor !== null)", () => {
    const withMore = likersPageResponse({
      likers: [{ userId: "u", displayName: "N", photoUrl: "https://x", reaction: undefined }],
      nextCursor: "A".repeat(43),
    });
    assert.deepEqual(Object.keys(withMore).sort(), [...LIKERS_RESPONSE_KEYS]);
    assert.deepEqual(Object.keys(withMore.likers[0]).sort(), [...LIKER_ROW_KEYS]);
    assert.equal(withMore.likers[0].photoUrl, null);
    assert.equal(withMore.likers[0].reaction, null);
    assert.equal(withMore.hasMore, true);
    assert.equal(likersPageResponse({ likers: [], nextCursor: null }).hasMore, false);
    assert.throws(() => likersPageResponse({
      likers: Array.from({ length: 21 }, () => ({})), nextCursor: null,
    }), TypeError);
  });
});

describe("server reactor order", () => {
  test("emoji picker order, then uid in code-unit order; emoji filter", () => {
    const reactions = {
      zed: "❤️",
      Alpha: "🔥",
      alpha: "❤️",
      beta: "👍",
      Beta: "❤️",
    };
    const ordered = serverReactionCandidates(reactions);
    assert.deepEqual(ordered.map((c) => c.likerId), ["Beta", "alpha", "zed", "Alpha", "beta"]);
    assert.deepEqual(ordered.map((c) => c.position.emojiIndex), [0, 0, 0, 2, 5]);
    assert.deepEqual(ordered.map((c) => c.reaction), ["❤️", "❤️", "❤️", "🔥", "👍"]);
    assert.deepEqual(
      serverReactionCandidates(reactions, { emoji: "❤️" }).map((c) => c.likerId),
      ["Beta", "alpha", "zed"],
    );
    assert.equal(ALLOWED_DIRECT_REACTIONS.indexOf("👍"), 5);
  });

  test("resuming after a map mutation neither repeats nor skips", async () => {
    const reactions = {};
    for (let index = 0; index < 30; index += 1) {
      reactions[`u${String(index).padStart(2, "0")}`] = index < 15 ? "❤️" : "😂";
    }
    const visibleAll = async (take) => take.map((c) =>
      ({ userId: c.likerId, displayName: "N", photoUrl: null, reaction: c.reaction }));
    const first = await scanLikersPage({
      fetchCandidates: inMemoryCandidateFetcher(serverReactionCandidates(reactions)),
      resolveVisible: visibleAll,
    });
    assert.equal(first.likers.length, 20);
    assert.deepEqual(first.lastConsumed, { emojiIndex: 1, uid: "u19" });
    // Between pages: the last consumed reactor leaves, one before the
    // cursor and one after it arrive, and one after it changes emoji.
    delete reactions.u19;
    reactions.a00 = "❤️";
    reactions.u99 = "😂";
    reactions.u25 = "❤️";
    const second = await scanLikersPage({
      after: first.lastConsumed,
      fetchCandidates: inMemoryCandidateFetcher(serverReactionCandidates(reactions)),
      resolveVisible: visibleAll,
    });
    assert.deepEqual(second.likers.map((row) => row.userId),
      ["u20", "u21", "u22", "u23", "u24", "u26", "u27", "u28", "u29", "u99"]);
  });
});

describe("runLikersPage (content likes, in-memory Firestore)", () => {
  function seedWorld(visibleCount, hiddenCount) {
    const db = new InMemoryFirestore();
    db.seed(`users/${VIEWER}`, { role: "user" });
    const total = visibleCount + hiddenCount;
    for (let index = 0; index < total; index += 1) {
      const uid = `liker-${String(index).padStart(3, "0")}`;
      const hidden = index % Math.ceil(total / Math.max(hiddenCount, 1)) === 1 &&
        hiddenCount > 0;
      db.seed(`users/${uid}`, { role: "user", ...(hidden ? { likesHidden: true } : {}) });
      db.seed(`publicProfiles/${uid}`, {
        accountType: "personal", bannerUrl: null, bio: "", country: null,
        creatorAudienceVisible: false, displayName: `Name ${uid}`,
        displayNameSearch: "n", followerCount: 0, followingCount: 0, friendCount: 0,
        learningLanguages: [], nativeLanguage: null, photoUrl: null, premiumIdentity: null,
        schemaVersion: 1, spokenLanguages: [], statusMessage: "", uid,
        updatedAt: new Date(NOW_MS), username: null, usernameSearch: null, website: null,
      });
      // Several likes share one createdAt: the doc id breaks the tie.
      db.seed(`voiceMoments/m1/likes/${uid}`, {
        schemaVersion: 1,
        userId: uid,
        momentId: "m1",
        createdAt: new Date(NOW_MS - 60_000 * Math.floor(index / 4)),
      });
    }
    return db;
  }

  function run(db, cursor, extra = {}) {
    const targetKey = likersTargetKey({ targetType: "voiceMoment", ids: ["m1"] });
    return runLikersPage({
      db,
      Timestamp,
      viewerId: VIEWER,
      targetType: "voiceMoment",
      targetKey,
      cursor,
      timing,
      fetchCandidates: queryCandidateFetcher({
        query: db.collection("voiceMoments/m1/likes"),
        documentIdField: "__name__",
        toLikerId: (doc) => doc.data()?.userId === doc.id ? doc.id : null,
      }),
      resolveVisible: likerResolver({
        getAll: (...references) => db.getAll(...references),
        db,
        viewerId: VIEWER,
        nowMs: NOW_MS,
      }),
      ...extra,
    });
  }

  test("pages newest first with the id tiebreak and no duplicates or gaps", async () => {
    const db = seedWorld(45, 5);
    const listed = [];
    let cursor = null;
    let pages = 0;
    do {
      const { response } = await run(db, cursor);
      assert.deepEqual(Object.keys(response).sort(), [...LIKERS_RESPONSE_KEYS]);
      assert.equal(response.hasMore, response.nextCursor !== null);
      listed.push(...response.likers.map((row) => row.userId));
      cursor = response.nextCursor;
      pages += 1;
    } while (cursor !== null && pages < 10);
    const expected = db.paths("voiceMoments/m1/likes/")
      .map((path) => path.split("/").at(-1))
      .filter((uid) => db.data(`users/${uid}`).likesHidden !== true)
      .sort((left, right) => {
        const a = db.data(`voiceMoments/m1/likes/${left}`).createdAt.getTime();
        const b = db.data(`voiceMoments/m1/likes/${right}`).createdAt.getTime();
        return b - a || (left < right ? 1 : -1);
      });
    assert.equal(expected.length, 45);
    assert.deepEqual(listed, expected);
    assert.equal(new Set(listed).size, listed.length);
  });

  test("a replayed cursor returns the identical page", async () => {
    const db = seedWorld(45, 0);
    const first = await run(db, null);
    const once = await run(db, first.response.nextCursor);
    const twice = await run(db, first.response.nextCursor);
    assert.deepEqual(twice.response.likers, once.response.likers);
    assert.equal(twice.response.hasMore, once.response.hasMore);
  });

  test("no transaction; the cursor is created after the re-check, and only with more", async () => {
    const db = seedWorld(25, 0);
    const probe = tracked(db);
    const events = [];
    const created = () => db.paths("likerPageCursors/").length;
    const { response } = await run(probe.db, null, {
      recheck: async () => events.push(["recheck", created()]),
    });
    events.push(["done", created()]);
    assert.equal(probe.transactionCount(), 0);
    assert.deepEqual(events, [["recheck", 0], ["done", 1]]);
    assert.match(response.nextCursor, /^[A-Za-z0-9_-]{43}$/u);

    const last = await run(db, response.nextCursor);
    assert.equal(last.response.nextCursor, null);
    assert.equal(db.paths("likerPageCursors/").length, 1);
  });

  test("a failed re-check stores no cursor", async () => {
    const db = seedWorld(25, 0);
    await assert.rejects(run(db, null, {
      recheck: async () => {
        throw new HttpsError("permission-denied", "This content is unavailable.");
      },
    }), (error) => error.code === "permission-denied");
    assert.equal(db.paths("likerPageCursors/").length, 0);
  });

  test("a cursor for another target is invalid-argument", async () => {
    const db = seedWorld(25, 0);
    const { response } = await run(db, null);
    await assert.rejects(runLikersPage({
      db,
      Timestamp,
      viewerId: VIEWER,
      targetType: "voiceMomentComment",
      targetKey: likersTargetKey({ targetType: "voiceMomentComment", ids: ["m1", "c1"] }),
      cursor: response.nextCursor,
      timing,
      fetchCandidates: async () => [],
      resolveVisible: async () => [],
    }), (error) => error.code === "invalid-argument");
  });
});

// A position the cursor cannot store (a createdAt that is a map, array,
// bytes, geopoint or reference) must never refuse or strand the list: the
// page is cut back to the last storable consumed position, and only a page
// that consumed nothing storable ends the list.
describe("unstorable positions (malformed server data)", () => {
  const MALFORMED = Object.freeze({ x: 1 });

  // `pattern`: "v" visible, "h" hidden, "m" malformed (hidden, map createdAt).
  function contentCandidates(pattern) {
    return [...pattern].map((kind, index) => ({
      position: {
        createdAt: kind === "m" ? MALFORMED : new Date(NOW_MS - index * 1000),
        id: `like-${String(index).padStart(3, "0")}`,
      },
      likerId: kind === "m"
        ? null
        : `${kind === "v" ? "visible" : "hidden"}-${String(index).padStart(3, "0")}`,
      reaction: null,
    }));
  }

  function byId(list) {
    const order = new Map(list.map((candidate, index) => [candidate.position.id, index]));
    return inMemoryCandidateFetcher(list, (left, right) =>
      order.get(left.id) - order.get(right.id));
  }

  function runContent(db, list, cursor) {
    return runLikersPage({
      db,
      Timestamp,
      viewerId: VIEWER,
      targetType: "voiceMoment",
      targetKey: likersTargetKey({ targetType: "voiceMoment", ids: ["m1"] }),
      cursor,
      timing,
      fetchCandidates: byId(list),
      resolveVisible: resolveStub,
    });
  }

  test("a malformed edge as the last consumed candidate rewinds, never refuses", async () => {
    // 19 visible, 40 hidden, then the malformed edge is the 60th consumed
    // (scan cap) candidate, then 10 more visible.
    const list = contentCandidates(
      `${"v".repeat(19)}${"h".repeat(40)}m${"v".repeat(10)}`);
    const db = new InMemoryFirestore();
    const first = await runContent(db, list, null);
    assert.equal(first.scan.unstorable, "rewound");
    assert.equal(first.response.likers.length, 19);
    assert.equal(first.response.hasMore, true);
    assert.equal(first.scan.lastConsumed.id, "like-058");
    const second = await runContent(db, list, first.response.nextCursor);
    assert.equal(second.scan.unstorable, null);
    assert.equal(second.response.hasMore, false);
    const listed = [...first.response.likers, ...second.response.likers]
      .map((row) => row.userId);
    assert.deepEqual(listed, list
      .filter((candidate) => candidate.likerId?.startsWith("visible"))
      .map((candidate) => candidate.likerId));
  });

  test("a page that consumed nothing storable ends the list instead of throwing", async () => {
    const list = contentCandidates(`${"m".repeat(LIKERS_SCAN_CAP)}${"v".repeat(5)}`);
    const db = new InMemoryFirestore();
    const { response, scan } = await runContent(db, list, null);
    assert.equal(scan.unstorable, "stranded");
    assert.deepEqual(response.likers, []);
    assert.equal(response.hasMore, false);
    assert.equal(response.nextCursor, null);
    assert.equal(db.paths("likerPageCursors/").length, 0);
  });

  test("rewinding past an unstorable visible row lists it on the next page, once", async () => {
    // Defence in depth: even a visible row at an unstorable position is
    // never lost or duplicated.
    const list = candidates("v".repeat(30));
    const isStorable = (position) => position !== 19;
    const first = await scanLikersPage({
      fetchCandidates: fetcherOf(list),
      resolveVisible: resolveStub,
      isStorable,
    });
    assert.equal(first.unstorable, "rewound");
    assert.equal(first.likers.length, 19);
    assert.equal(first.lastConsumed, 18);
    assert.equal(first.hasMore, true);
    const second = await scanLikersPage({
      after: first.lastConsumed,
      fetchCandidates: fetcherOf(list),
      resolveVisible: resolveStub,
      isStorable,
    });
    assert.equal(second.unstorable, null);
    assert.deepEqual(
      [...first.likers, ...second.likers].map((row) => row.userId),
      list.map((candidate) => candidate.likerId),
    );
  });

  test("an unstorable last candidate with nothing after it is simply the end", async () => {
    const list = contentCandidates("vvm");
    const { response, scan } = await runContent(new InMemoryFirestore(), list, null);
    assert.equal(scan.unstorable, null);
    assert.equal(response.likers.length, 2);
    assert.equal(response.hasMore, false);
  });
});

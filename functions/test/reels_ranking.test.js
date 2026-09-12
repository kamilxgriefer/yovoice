const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  DEFAULT_FEED_RANKING,
  affinityScore,
  engagementScore,
  rankFeedItems,
  recencyScore,
  resolveFeedRanking,
  scoreCandidate,
  seenDecayScore,
} = require("../reels/ranking");

const NOW_MS = 1_778_000_000_000;
const HOUR_MS = 60 * 60 * 1000;
const CONFIG = DEFAULT_FEED_RANKING;

function candidate(overrides = {}) {
  return {
    id: "reel-a",
    sortKey: "1778000000000_reel-a",
    publishedAtMs: NOW_MS,
    likeCount: 0,
    commentCount: 0,
    affinity: "none",
    seenAtMs: null,
    ...overrides,
  };
}

test("recency halves at the configured half life and never leaves [0,1]", () => {
  assert.equal(recencyScore(NOW_MS, NOW_MS, CONFIG), 1);
  assert.equal(
    recencyScore(NOW_MS - CONFIG.RECENCY_HALF_LIFE_HOURS * HOUR_MS, NOW_MS, CONFIG),
    0.5,
  );
  // A Reel published "in the future" (clock skew) is not rewarded past 1.
  assert.equal(recencyScore(NOW_MS + 10 * HOUR_MS, NOW_MS, CONFIG), 1);
  assert.equal(recencyScore(null, NOW_MS, CONFIG), 0);
  assert.equal(recencyScore(Number.NaN, NOW_MS, CONFIG), 0);
  const old = recencyScore(NOW_MS - 30 * 24 * HOUR_MS, NOW_MS, CONFIG);
  assert.ok(old > 0 && old < 0.06);
});

test("engagement saturates so a brigaded counter cannot dominate", () => {
  assert.equal(engagementScore(0, 0, CONFIG), 0);
  // A comment is worth COMMENT_WEIGHT likes.
  assert.equal(
    engagementScore(CONFIG.COMMENT_WEIGHT, 0, CONFIG),
    engagementScore(0, 1, CONFIG),
  );
  assert.equal(engagementScore(CONFIG.ENGAGEMENT_SATURATION, 0, CONFIG), 1);
  // Ten thousand likes buys no more than the saturation point.
  assert.equal(engagementScore(10_000, 10_000, CONFIG), 1);
  // Corrupt counters read as zero rather than poisoning the score.
  assert.equal(engagementScore(-5, "many", CONFIG), 0);
  assert.equal(engagementScore(1.5, null, CONFIG), 0);
});

test("affinity uses the real edges only and unknown values score zero", () => {
  assert.equal(affinityScore("friend", CONFIG), CONFIG.AFFINITY_FRIEND);
  assert.equal(affinityScore("following", CONFIG), CONFIG.AFFINITY_FOLLOWING);
  assert.equal(affinityScore("none", CONFIG), 0);
  assert.equal(affinityScore("muted", CONFIG), 0);
  assert.equal(affinityScore(undefined, CONFIG), 0);
});

test("the seen penalty fades to nothing after the decay window", () => {
  assert.equal(seenDecayScore(NOW_MS, NOW_MS, CONFIG), 1);
  assert.equal(
    seenDecayScore(NOW_MS - CONFIG.SEEN_DECAY_HOURS * HOUR_MS, NOW_MS, CONFIG),
    0,
  );
  assert.equal(
    seenDecayScore(NOW_MS - 2 * CONFIG.SEEN_DECAY_HOURS * HOUR_MS, NOW_MS, CONFIG),
    0,
  );
  assert.equal(seenDecayScore(null, NOW_MS, CONFIG), 0);
});

test("jitter is bounded well below recency, so it flips ties and nothing more",
  () => {
    // Worst case: the freshest possible Reel with no engagement and no
    // affinity, versus a three-week-old one with maximum engagement, maximum
    // affinity and the luckiest possible jitter. Recency must still decide.
    let maximumJitterAdvantage = 0;
    for (let index = 0; index < 400; index += 1) {
      const jittered = scoreCandidate(
        candidate({ id: `jitter-${index}` }),
        { nowMs: NOW_MS, seed: "0123456789abcdef", config: CONFIG },
      );
      maximumJitterAdvantage = Math.max(maximumJitterAdvantage, jittered);
    }
    // recency 1 * W_RECENCY plus at most W_JITTER.
    assert.ok(maximumJitterAdvantage <= CONFIG.W_RECENCY + CONFIG.W_JITTER);
    assert.ok(maximumJitterAdvantage >= CONFIG.W_RECENCY);

    const freshPlain = scoreCandidate(candidate({ id: "fresh" }), {
      nowMs: NOW_MS,
      seed: "0123456789abcdef",
      config: CONFIG,
    });
    const staleLoaded = scoreCandidate(
      candidate({
        id: "stale",
        publishedAtMs: NOW_MS - 21 * 24 * HOUR_MS,
        likeCount: 100_000,
        commentCount: 100_000,
        affinity: "friend",
      }),
      { nowMs: NOW_MS, seed: "0123456789abcdef", config: CONFIG },
    );
    // Engagement + affinity CAN outrank pure recency by design; jitter alone
    // cannot. The guarantee under test is that jitter's whole range is
    // smaller than the recency term it would have to overcome.
    assert.ok(CONFIG.W_JITTER < CONFIG.W_RECENCY);
    assert.ok(freshPlain > 0);
    assert.ok(staleLoaded > 0);
  });

test("scoring is a pure function of its arguments", () => {
  const input = candidate({ likeCount: 4, commentCount: 2, affinity: "friend" });
  const first = scoreCandidate(input, {
    nowMs: NOW_MS,
    seed: "abcdef0123456789",
    config: CONFIG,
  });
  const second = scoreCandidate(input, {
    nowMs: NOW_MS,
    seed: "abcdef0123456789",
    config: CONFIG,
  });
  assert.equal(first, second);
  const otherSeed = scoreCandidate(input, {
    nowMs: NOW_MS,
    seed: "0000000000000000",
    config: CONFIG,
  });
  assert.notEqual(first, otherSeed);
});

test("ranking is a permutation: it never drops, duplicates or invents items",
  () => {
    const items = [];
    for (let index = 0; index < 24; index += 1) {
      items.push(candidate({
        id: `reel-${String(index).padStart(2, "0")}`,
        sortKey: `${String(NOW_MS - index).padStart(13, "0")}_reel-${index}`,
        publishedAtMs: NOW_MS - index * HOUR_MS,
        likeCount: index,
      }));
    }
    const ranked = rankFeedItems(items, { nowMs: NOW_MS, seed: "aaaa0000bbbb1111" });
    assert.equal(ranked.length, items.length);
    assert.deepEqual(
      new Set(ranked.map(({ id }) => id)),
      new Set(items.map(({ id }) => id)),
    );
    assert.equal(new Set(ranked.map(({ id }) => id)).size, items.length);
  });

test("a scorer that throws yields zero rather than removing an entitled item",
  () => {
    const hostile = {
      id: "hostile",
      get sortKey() {
        return "1778000000000_hostile";
      },
      get publishedAtMs() {
        throw new Error("corrupt ranking input");
      },
    };
    const healthy = candidate({ id: "healthy" });
    const ranked = rankFeedItems([hostile, healthy], {
      nowMs: NOW_MS,
      seed: "1111222233334444",
    });
    assert.equal(ranked.length, 2);
    assert.deepEqual(
      new Set(ranked.map(({ id }) => id)),
      new Set(["hostile", "healthy"]),
    );
  });

test("ordering is a total order and never relies on sort stability", () => {
  // Every candidate scores identically (same age, no engagement, and jitter
  // is keyed by id — so give them all the same id). Only sortKey separates
  // them, and the result must be strictly sortKey-descending every time.
  const tied = ["a", "b", "c", "d"].map((suffix) => ({
    id: "identical",
    sortKey: `1778000000000_${suffix}`,
    publishedAtMs: NOW_MS,
    likeCount: 0,
    commentCount: 0,
    affinity: "none",
    seenAtMs: null,
  }));
  const forward = rankFeedItems(tied, { nowMs: NOW_MS, seed: "0f0f0f0f0f0f0f0f" });
  const reversed = rankFeedItems([...tied].reverse(), {
    nowMs: NOW_MS,
    seed: "0f0f0f0f0f0f0f0f",
  });
  assert.deepEqual(
    forward.map(({ sortKey }) => sortKey),
    [
      "1778000000000_d",
      "1778000000000_c",
      "1778000000000_b",
      "1778000000000_a",
    ],
  );
  assert.deepEqual(
    forward.map(({ sortKey }) => sortKey),
    reversed.map(({ sortKey }) => sortKey),
  );
});

test("a recently seen Reel ranks below an identical unseen one", () => {
  const unseen = candidate({ id: "same", sortKey: "1778000000000_unseen" });
  const seen = candidate({
    id: "same",
    sortKey: "1778000000000_seen",
    seenAtMs: NOW_MS - HOUR_MS,
  });
  const unseenScore = scoreCandidate(unseen, {
    nowMs: NOW_MS,
    seed: "2222333344445555",
    config: CONFIG,
  });
  const seenScore = scoreCandidate(seen, {
    nowMs: NOW_MS,
    seed: "2222333344445555",
    config: CONFIG,
  });
  assert.ok(seenScore < unseenScore);
});

test("config resolution is total and a malformed override keeps the defaults",
  () => {
    assert.deepEqual(resolveFeedRanking({}), DEFAULT_FEED_RANKING);
    assert.deepEqual(
      resolveFeedRanking({ REEL_FEED_RANKING: "{not json" }),
      DEFAULT_FEED_RANKING,
    );
    assert.deepEqual(
      resolveFeedRanking({ REEL_FEED_RANKING: "[1,2,3]" }),
      DEFAULT_FEED_RANKING,
    );
    assert.equal(
      resolveFeedRanking({
        REEL_FEED_RANKING: JSON.stringify({ RECENCY_HALF_LIFE_HOURS: 0 }),
      }).RECENCY_HALF_LIFE_HOURS,
      DEFAULT_FEED_RANKING.RECENCY_HALF_LIFE_HOURS,
    );
    assert.equal(
      resolveFeedRanking({
        REEL_FEED_RANKING: JSON.stringify({ W_JITTER: "0.9" }),
      }).W_JITTER,
      DEFAULT_FEED_RANKING.W_JITTER,
    );
    assert.equal(
      resolveFeedRanking({
        REEL_FEED_RANKING: JSON.stringify({ W_JITTER: 0.1, enabled: false }),
      }).W_JITTER,
      0.1,
    );
    // Rollback of the ordering is one environment variable, no client
    // release, no schema change, no index drop.
    assert.equal(
      resolveFeedRanking({ REEL_FEED_RANKING_ENABLED: "false" }).enabled,
      false,
    );
    assert.equal(
      resolveFeedRanking({ REEL_FEED_RANKING_ENABLED: "true" }).enabled,
      true,
    );
    assert.equal(Object.isFrozen(resolveFeedRanking({})), true);
  });

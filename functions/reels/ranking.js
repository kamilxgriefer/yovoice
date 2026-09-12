// Reel feed ranking — pure scoring, ordering and cursor codec.
//
// This module deliberately owns NO Firestore handle, no clock and no
// randomness of its own beyond the one explicit seed minter: `nowMs`, `seed`
// and every ranking input arrive as arguments. That is what makes the ranker
// unit-testable without fakes, and — more importantly — what makes it
// structurally impossible for a scoring change to reach an authorization
// decision. Ranking decides ORDER. Eligibility is decided exclusively by
// `visibleFeedItem` in service.js, which this module never calls and whose
// snapshots it never sees.
//
// Safety invariant, pinned by tests: no ranking failure may remove an
// entitled item. `rankFeedItems` is a map/sort/map over its input, a scorer
// that throws contributes 0, and a missing or malformed ranking snapshot
// contributes 0.
const crypto = require("node:crypto");

const { digest, fail } = require("../integrity/guards");
const { FEED_CURSOR_PATTERN, validateFeedCursor } = require("./contract");

const HOUR_MS = 60 * 60 * 1000;

// Feed cursor modes. The mode travels inside the (client-opaque) cursor so a
// page-2 request cannot silently change the retrieval scope or the seen
// policy that page 1 was built under.
const FEED_MODES = Object.freeze({
  discover: "d",
  discoverIncludingSeen: "s",
  own: "o",
});
const FEED_MODE_VALUES = Object.freeze(new Set(Object.values(FEED_MODES)));
const FEED_SEED_PATTERN = /^[0-9a-f]{16}$/u;

// FEED_RANKING v1. These weights are informed guesses: this project has no
// offline evaluation data and none can be manufactured honestly, so "is this
// ordering good" is unanswerable before it ships. That is exactly why they
// live in one frozen object, are emitted with every request's log line, and
// are flippable through an environment variable without a client release.
const DEFAULT_FEED_RANKING = Object.freeze({
  // Emitted in the per-request log line so a reported ordering can at least
  // be attributed to a weight set, even though the seed deliberately is not
  // logged (a (viewer, reel) pair is viewing history).
  version: "feed-ranking-v1",
  // Stage 1 of the rollout deploys with this false: the new cursor grammar is
  // still emitted and decoded, so the codec is exercised in production while
  // ordering is provably unchanged. Stage 2 flips it on.
  enabled: true,
  // Score halves in a day and a half — fresh stays above old without a cliff.
  RECENCY_HALF_LIFE_HOURS: 36,
  // A comment costs more than a like. Both counters are server-transactional.
  COMMENT_WEIGHT: 3,
  // Log-saturates so a brigaded counter cannot dominate the page.
  ENGAGEMENT_SATURATION: 25,
  // Suppression window for a Reel this viewer has already watched. Discover
  // only, and only ever applied to a successfully read, valid, recent record.
  SEEN_HIDE_MS: 6 * HOUR_MS,
  // The seen penalty fades to nothing after a week.
  SEEN_DECAY_HOURS: 168,
  AFFINITY_FRIEND: 1,
  AFFINITY_FOLLOWING: 0.6,
  W_RECENCY: 1,
  W_ENGAGE: 0.7,
  W_AFFINITY: 0.45,
  W_SEEN: 0.6,
  // Deliberately smaller than W_RECENCY: jitter flips near-ties so two opens
  // differ, it cannot lift a three-week-old Reel above a one-hour-old one.
  W_JITTER: 0.35,
});

const POSITIVE_NUMBER_KEYS = Object.freeze([
  "RECENCY_HALF_LIFE_HOURS",
  "COMMENT_WEIGHT",
  "ENGAGEMENT_SATURATION",
  "SEEN_HIDE_MS",
  "SEEN_DECAY_HOURS",
]);
const WEIGHT_KEYS = Object.freeze([
  "AFFINITY_FRIEND",
  "AFFINITY_FOLLOWING",
  "W_RECENCY",
  "W_ENGAGE",
  "W_AFFINITY",
  "W_SEEN",
  "W_JITTER",
]);

// Config resolution is total: any malformed override falls back to the frozen
// default for that key rather than throwing at module load. A typo in a
// deploy-time environment variable must not take the feed down; it must at
// worst leave the shipped weights in place.
function resolveFeedRanking(env = {}) {
  const resolved = { ...DEFAULT_FEED_RANKING };
  let override = {};
  if (typeof env.REEL_FEED_RANKING === "string" &&
      env.REEL_FEED_RANKING.trim() !== "") {
    try {
      const parsed = JSON.parse(env.REEL_FEED_RANKING);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        override = parsed;
      }
    } catch (_) {
      override = {};
    }
  }
  for (const key of POSITIVE_NUMBER_KEYS) {
    const value = override[key];
    if (typeof value === "number" && Number.isFinite(value) && value > 0) {
      resolved[key] = value;
    }
  }
  for (const key of WEIGHT_KEYS) {
    const value = override[key];
    if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
      resolved[key] = value;
    }
  }
  if (typeof override.enabled === "boolean") resolved.enabled = override.enabled;
  if (typeof override.version === "string" &&
      /^[A-Za-z0-9._-]{1,64}$/u.test(override.version)) {
    resolved.version = override.version;
  }
  // The single-switch form, so a rollback of the ordering is one environment
  // variable rather than a JSON edit.
  const flag = env.REEL_FEED_RANKING_ENABLED;
  if (flag === "false" || flag === "0") resolved.enabled = false;
  if (flag === "true" || flag === "1") resolved.enabled = true;
  return Object.freeze(resolved);
}

const FEED_RANKING = resolveFeedRanking(process.env);

function clamp01(value) {
  if (!Number.isFinite(value)) return 0;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

function countOrZero(value) {
  return Number.isSafeInteger(value) && value > 0 ? value : 0;
}

function recencyScore(publishedAtMs, nowMs, config) {
  if (!Number.isFinite(publishedAtMs) || !Number.isFinite(nowMs)) return 0;
  const ageHours = Math.max(0, (nowMs - publishedAtMs) / HOUR_MS);
  return clamp01(1 / (1 + ageHours / config.RECENCY_HALF_LIFE_HOURS));
}

function engagementScore(likeCount, commentCount, config) {
  const weighted =
    countOrZero(likeCount) + config.COMMENT_WEIGHT * countOrZero(commentCount);
  return clamp01(
    Math.log1p(weighted) / Math.log1p(config.ENGAGEMENT_SATURATION),
  );
}

// `affinity` is one of "friend", "following" or "none". It is derived from
// real, server-written social-graph edges (users/{viewer}/friends/{author},
// users/{viewer}/following/{author}) and is used ONLY as a score term — it
// never grants or withholds access to anything.
function affinityScore(affinity, config) {
  if (affinity === "friend") return config.AFFINITY_FRIEND;
  if (affinity === "following") return config.AFFINITY_FOLLOWING;
  return 0;
}

function seenDecayScore(seenAtMs, nowMs, config) {
  if (!Number.isFinite(seenAtMs) || !Number.isFinite(nowMs)) return 0;
  const seenAgeHours = Math.max(0, (nowMs - seenAtMs) / HOUR_MS);
  return clamp01(1 - seenAgeHours / config.SEEN_DECAY_HOURS);
}

// The per-session shuffle. `digest` is the existing audited SHA-256 helper —
// no new crypto surface. Domain-separated so a seed can never collide with
// another digest use of the same strings.
function jitterScore(seed, reelId) {
  const hex = digest("reelFeedJitter", String(seed), String(reelId)).slice(0, 8);
  return Number.parseInt(hex, 16) / 2 ** 32;
}

function scoreCandidate(candidate, { nowMs, seed, config = FEED_RANKING } = {}) {
  const recency = recencyScore(candidate?.publishedAtMs, nowMs, config);
  const engagement = engagementScore(
    candidate?.likeCount,
    candidate?.commentCount,
    config,
  );
  const affinity = affinityScore(candidate?.affinity, config);
  const seen = seenDecayScore(candidate?.seenAtMs, nowMs, config);
  const jitter = jitterScore(seed, candidate?.id);
  const score =
    config.W_RECENCY * recency +
    config.W_ENGAGE * engagement +
    config.W_AFFINITY * affinity -
    config.W_SEEN * seen +
    config.W_JITTER * jitter;
  return Number.isFinite(score) ? score : 0;
}

function safeScore(candidate, options) {
  try {
    return scoreCandidate(candidate, options);
  } catch (_) {
    // A scorer that throws yields 0. It must never remove an entitled item.
    return 0;
  }
}

// Total order: descending score, then descending sortKey, then the incoming
// position as the final tiebreak. JS sort stability is never relied upon — a
// given (seed, candidate set, nowMs) must produce exactly one order or the
// tests are flaky by construction and support can never reproduce a report.
//
// The return value is a permutation of the input. Never a filter.
function rankFeedItems(candidates, { nowMs, seed, config = FEED_RANKING } = {}) {
  if (!Array.isArray(candidates) || candidates.length < 2) {
    return Array.isArray(candidates) ? [...candidates] : [];
  }
  const scored = candidates.map((candidate, index) => ({
    candidate,
    index,
    score: safeScore(candidate, { nowMs, seed, config }),
    sortKey: String(candidate?.sortKey ?? ""),
  }));
  scored.sort((left, right) => {
    if (left.score !== right.score) return right.score - left.score;
    if (left.sortKey !== right.sortKey) {
      return left.sortKey < right.sortKey ? 1 : -1;
    }
    return left.index - right.index;
  });
  return scored.map(({ candidate }) => candidate);
}

function randomFeedSeed() {
  return crypto.randomBytes(8).toString("hex");
}

function mintFeedSeed(randomSeed = randomFeedSeed) {
  const seed = typeof randomSeed === "function" ? randomSeed() : null;
  if (typeof seed !== "string" || !FEED_SEED_PATTERN.test(seed)) {
    throw new TypeError("randomSeed must return 16 lowercase hex characters.");
  }
  return seed;
}

// A legacy bare-sortKey cursor arriving mid-session across an app update
// still has to rank, and it must rank the same way on every retry. Deriving
// the seed from (uid, position) keeps that page deterministic without
// inventing a session that was never minted.
function deriveFeedSeed(uid, position) {
  return digest("reelFeedSeed", String(uid), String(position)).slice(0, 16);
}

function encodeFeedCursor({ mode, seed, position }) {
  if (!FEED_MODE_VALUES.has(mode)) {
    throw new TypeError(`Unsupported feed cursor mode: ${mode}`);
  }
  if (typeof seed !== "string" || !FEED_SEED_PATTERN.test(seed)) {
    throw new TypeError("A feed cursor seed must be 16 lowercase hex chars.");
  }
  const cursor = `f1.${mode}.${seed}.${position}`;
  if (!FEED_CURSOR_PATTERN.test(cursor)) {
    throw new TypeError("A feed cursor position must be a canonical sortKey.");
  }
  return cursor;
}

// `null` means "mint a fresh session". A legacy cursor yields position only
// and a derived seed. An `f1.` cursor whose mode disagrees with the request's
// scope/includeSeen is rejected with the EXISTING client-visible message, so
// no new user-facing string appears on this path.
function decodeFeedCursor(value, { mode, uid }) {
  if (value === null || value === undefined) return null;
  const cursor = validateFeedCursor(value);
  if (!FEED_CURSOR_PATTERN.test(cursor)) {
    return { seed: deriveFeedSeed(uid, cursor), position: cursor, legacy: true };
  }
  const parts = cursor.split(".");
  const cursorMode = parts[1];
  const seed = parts[2];
  const position = parts[3];
  if (cursorMode !== mode) fail("invalid-argument", "cursor is invalid.");
  return { seed, position, legacy: false };
}

function feedModeFor({ scope, includeSeen }) {
  if (scope === "own") return FEED_MODES.own;
  return includeSeen === true
    ? FEED_MODES.discoverIncludingSeen
    : FEED_MODES.discover;
}

module.exports = {
  DEFAULT_FEED_RANKING,
  FEED_MODES,
  FEED_RANKING,
  FEED_SEED_PATTERN,
  affinityScore,
  decodeFeedCursor,
  deriveFeedSeed,
  encodeFeedCursor,
  engagementScore,
  feedModeFor,
  jitterScore,
  mintFeedSeed,
  randomFeedSeed,
  rankFeedItems,
  recencyScore,
  resolveFeedRanking,
  scoreCandidate,
  seenDecayScore,
};

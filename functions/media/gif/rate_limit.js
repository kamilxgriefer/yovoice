// Independent limits protect provider usage and safety-reporting capacity.
//
//  - `gifRateLimits/{uid}` — a token bucket protecting the PROVIDER'S QUOTA
//    and our bill from one account. Burst 10 so a person typing normally never
//    meets it, refill one token every two seconds, plus hard ceilings per ten
//    minutes and per day so a scripted client cannot spend the hour's budget.
//  - `gifProviderBudget/{yyyymmddhh}` — a GLOBAL hourly ceiling on actual
//    provider calls. This is the mechanism that keeps a beta key from being
//    throttled by our own aggregate traffic. When it is spent, misses degrade
//    to the freshest cached trending page rather than erroring.
//  - `privateRateLimits/{digest}` — separate report-attempt and new-report
//    limits. Refusals cannot bypass the attempt budget; replay never creates
//    another moderation vote or consumes another new-report allowance.
//
// Both collections are Admin-SDK-written and `allow read, write: if false` for
// every client, matching the posture `billingRateLimits` already has: a limit
// a client can read is a limit a client can plan around, and one it can write
// is not a limit.

"use strict";

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { consumeRateLimit, rateLimitReference } = require("../../integrity/guards");

const BUCKET_CAPACITY = 10;
const REFILL_INTERVAL_MS = 2000;
const WINDOW_LIMIT = 120;
const WINDOW_MS = 10 * 60 * 1000;
const DAILY_LIMIT = 800;
const DAY_MS = 24 * 60 * 60 * 1000;
const REPORT_ATTEMPT_LIMIT = 30;
const REPORT_ATTEMPT_WINDOW_MS = 60 * 1000;
const REPORT_DAILY_LIMIT = 20;

/// Deliberately conservative. Read the real number off the GIPHY developer
/// portal at signup and record it in docs/DEPENDENCIES.md — this default is
/// what the system runs on until somebody does, and it is set low on purpose:
/// tripping a beta key's cap gets the whole feature throttled, while an
/// over-tight budget only degrades to cached trending with `degraded: true`.
const DEFAULT_HOURLY_PROVIDER_BUDGET = 400;

function hourKey(nowMs) {
  const date = new Date(nowMs);
  const pad = (value) => String(value).padStart(2, "0");
  return (
    `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}` +
    `${pad(date.getUTCDate())}${pad(date.getUTCHours())}`
  );
}

function millis(value, fallback) {
  if (value instanceof Timestamp) return value.toMillis();
  return fallback;
}

/// Pure token-bucket arithmetic, separated from Firestore so it is testable
/// without an emulator and reviewable without reading a transaction.
function nextBucketState(previous, nowMs) {
  const lastMs = Number.isFinite(previous?.lastRefillMs)
    ? previous.lastRefillMs
    : nowMs;
  const elapsed = Math.max(0, nowMs - lastMs);
  const restored = Math.floor(elapsed / REFILL_INTERVAL_MS);
  const priorTokens = Number.isFinite(previous?.tokens)
    ? previous.tokens
    : BUCKET_CAPACITY;
  const tokens = Math.min(BUCKET_CAPACITY, priorTokens + restored);
  // Advancing by whole refill intervals rather than to `nowMs` is what stops
  // sub-interval calls from silently discarding the fraction of a token they
  // had already earned.
  const lastRefillMs =
    restored > 0 ? lastMs + restored * REFILL_INTERVAL_MS : lastMs;
  return { tokens, lastRefillMs };
}

/// A fixed window: it either still contains `nowMs`, or it restarts at
/// `nowMs` with a zero count. A clock that has gone backwards restarts the
/// window too, which is the safe direction — it cannot be used to make a
/// stale count look fresh.
function windowState({ startedMs, count }, nowMs, spanMs) {
  const started = Number.isFinite(startedMs) ? startedMs : nowMs;
  const withinWindow = nowMs >= started && nowMs - started < spanMs;
  return {
    startedMs: withinWindow ? started : nowMs,
    count: withinWindow && Number.isSafeInteger(count) ? count : 0,
  };
}

function retryAfterSeconds(state, nowMs) {
  if (state.tokens > 0) return 1;
  const waitMs = Math.max(
    0,
    state.lastRefillMs + REFILL_INTERVAL_MS - nowMs,
  );
  return Math.max(1, Math.ceil(waitMs / 1000));
}

function createGifRateLimiter({
  db,
  now = () => Date.now(),
  hourlyProviderBudget = DEFAULT_HOURLY_PROVIDER_BUDGET,
} = {}) {
  if (!db) throw new TypeError("A Firestore handle is required.");

  const bucketDoc = (uid) => db.collection("gifRateLimits").doc(uid);
  const budgetDoc = (key) => db.collection("gifProviderBudget").doc(key);

  /// Charge one request against the caller's bucket.
  ///
  /// Charged BEFORE the cache is consulted, deliberately: the limit exists to
  /// bound how much work one account can ask this service to do, and a cache
  /// hit still costs a Firestore read and an instance. Charging only on a miss
  /// would let an attacker discover which queries are cached by measuring
  /// which ones are free.
  async function consume(uid) {
    const nowMs = now();
    const reference = bucketDoc(uid);
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const previous = snapshot.exists ? (snapshot.data() ?? {}) : {};
      const bucket = nextBucketState(
        {
          tokens: previous.tokens,
          lastRefillMs: millis(previous.lastRefillAt, nowMs),
        },
        nowMs,
      );
      const window = windowState(
        {
          startedMs: millis(previous.windowStartedAt, nowMs),
          count: previous.windowCount,
        },
        nowMs,
        WINDOW_MS,
      );
      const day = windowState(
        {
          startedMs: millis(previous.dayStartedAt, nowMs),
          count: previous.dayCount,
        },
        nowMs,
        DAY_MS,
      );

      const overBurst = bucket.tokens < 1;
      const overWindow = window.count >= WINDOW_LIMIT;
      const overDay = day.count >= DAILY_LIMIT;
      if (overBurst || overWindow || overDay) {
        return {
          allowed: false,
          retryAfterSeconds: overDay
            ? Math.max(
                1,
                Math.ceil((day.startedMs + DAY_MS - nowMs) / 1000),
              )
            : overWindow
              ? Math.max(
                  1,
                  Math.ceil((window.startedMs + WINDOW_MS - nowMs) / 1000),
                )
              : retryAfterSeconds(bucket, nowMs),
        };
      }

      transaction.set(reference, {
        schemaVersion: 1,
        ownerId: uid,
        tokens: bucket.tokens - 1,
        lastRefillAt: Timestamp.fromMillis(bucket.lastRefillMs),
        windowStartedAt: Timestamp.fromMillis(window.startedMs),
        windowCount: window.count + 1,
        dayStartedAt: Timestamp.fromMillis(day.startedMs),
        dayCount: day.count + 1,
        updatedAt: Timestamp.fromMillis(nowMs),
      });
      return { allowed: true, retryAfterSeconds: 0 };
    });
  }

  // Separate from search: browsing cannot exhaust the safety-report budget.
  // This commits before asset/profile reads so missing or refused targets do
  // not roll the quota back. Replays spend an attempt but no second daily
  // report allowance; that allowance is bound to report creation atomically.
  async function consumeReport(uid) {
    const nowMs = now();
    const scope = "gif.report.attempt";
    const reference = rateLimitReference(db, scope, uid);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      consumeRateLimit(transaction, snapshot, {
        reference,
        scope,
        uid,
        nowMs,
        now: Timestamp.fromMillis(nowMs),
        maxEvents: REPORT_ATTEMPT_LIMIT,
        windowMs: REPORT_ATTEMPT_WINDOW_MS,
      });
    });
  }

  /// Claim one slot in this hour's provider budget.
  ///
  /// Incremented ONLY when a real provider call is about to happen, so a cache
  /// hit costs nothing here. Returns `false` when the hour is spent, and the
  /// caller then serves stale cache with `degraded: true` instead of erroring
  /// — a degraded picker is a working picture, a 500 is not.
  async function claimProviderCall() {
    const nowMs = now();
    const reference = budgetDoc(hourKey(nowMs));
    try {
      return await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        const used = snapshot.exists
          ? (snapshot.data() ?? {}).calls
          : 0;
        const spent = Number.isSafeInteger(used) ? used : 0;
        if (spent >= hourlyProviderBudget) return false;
        transaction.set(
          reference,
          {
            schemaVersion: 1,
            calls: FieldValue.increment(1),
            budget: hourlyProviderBudget,
            updatedAt: Timestamp.fromMillis(nowMs),
          },
          { merge: true },
        );
        return true;
      });
    } catch (_) {
      // The budget is a cost guard, not a security control. If Firestore
      // cannot answer, allowing the call is the behaviour that keeps search
      // working; the per-account limit above is the one that must fail closed,
      // and it does — its transaction error propagates.
      return true;
    }
  }

  return {
    BUCKET_CAPACITY,
    DAILY_LIMIT,
    WINDOW_LIMIT,
    bucketDoc,
    budgetDoc,
    claimProviderCall,
    consume,
    consumeReport,
    hourlyProviderBudget,
  };
}

module.exports = {
  BUCKET_CAPACITY,
  DAILY_LIMIT,
  DAY_MS,
  DEFAULT_HOURLY_PROVIDER_BUDGET,
  REFILL_INTERVAL_MS,
  REPORT_ATTEMPT_LIMIT,
  REPORT_ATTEMPT_WINDOW_MS,
  REPORT_DAILY_LIMIT,
  WINDOW_LIMIT,
  WINDOW_MS,
  createGifRateLimiter,
  hourKey,
  nextBucketState,
};

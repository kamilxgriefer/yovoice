// Public statistics — the three real numbers the marketing site publishes.
//
// One server-owned document, `publicStats/live`, written only from here
// through the Admin SDK on a schedule. It would be the project's first
// publicly readable document, so it deliberately carries nothing except the
// aggregates and the time they were computed: no uids, no room ids, no
// per-room breakdown, nothing that could be joined back to a person.
//
// WHAT `peopleTalkingNow` ACTUALLY MEANS — read this before trusting it.
//
// The only server-authoritative voice source is `activeVoiceSessions`
// (`allow read, write: if false`). It is written exclusively by
// `recordAuthorizedVoiceSession` (../livekit/token.js) and removed only by a
// server-mediated leave, room end or moderation action (../livekit/sessions.js,
// ../rooms/participants.js, ../admin/rooms.js, ../staff/voice_enforcement.js).
// NOTHING removes a row when a client crashes, drops its network or closes the
// tab, and no scheduled sweep or TTL policy exists in this repository. An
// unbounded count would therefore report people who left hours ago — the same
// fiction this feature exists to replace.
//
// Each row carries `expiresAt` = token issuance + VOICE_TOKEN_TTL_SECONDS. A
// row whose `expiresAt` is still in the future is backed by voice authority
// granted less than that TTL ago and not yet surrendered. That is the only
// freshness bound this data supports, and it fails toward silence rather than
// invention. Stated precisely, `peopleTalkingNow` is:
//
//   the number of DISTINCT accounts that were granted voice authority within
//   the last VOICE_TOKEN_TTL_SECONDS and have not since left,
//
// which is a LOWER BOUND on the true concurrent population, not an estimate of
// it. The Flutter client mints exactly one token per join and never refreshes
// it (`VoiceCallService.join` is the sole caller of `createLiveKitToken`, and
// LiveKit's own reconnects reuse the original JWT), so a participant who stays
// in a room longer than the TTL stops being counted. Closing that gap needs a
// presence heartbeat — either a periodic client re-mint or the already-written
// but currently unexported signed LiveKit webhook
// (`receiveLiveKitAchievementWebhook`, ../achievements/livekit_http.js), whose
// `participant_left` / `participant_connection_aborted` events are emitted by
// the SFU on a crash and therefore describe real presence. Until one of those
// lands, this number is honest but systematically low, and the presentation
// layer must treat a small value as "not enough signal to show" rather than as
// a measurement.
//
// `accountsCreated` and `roomsCreated` are real `count()` aggregates over the
// live `users` and `rooms` collections, following the Staff Center pattern in
// ../staff/overview.js. They are CURRENT TOTALS, not monotonic lifetime
// creation counters: deleting an account or a room lowers them. See the ADR
// for why that is a product decision, not a bug in this function.

const { logger } = require("firebase-functions/v2");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { ACTIVE_VOICE_SESSIONS } = require("../livekit/sessions");
const { VOICE_TOKEN_TTL_SECONDS } = require("../livekit/token");

const REGION = "europe-west1";

const PUBLIC_STATS_COLLECTION = "publicStats";
const PUBLIC_STATS_DOCUMENT = "live";
const PUBLIC_STATS_SCHEMA_VERSION = 1;

// The freshness bound IS the token TTL. Deriving it rather than restating it
// means the two can never drift apart in a way that silently invents presence.
const LIVE_SESSION_FRESHNESS_SECONDS = VOICE_TOKEN_TTL_SECONDS;

// A hard ceiling on documents read per run. Exceeding it means either genuine
// scale this approach no longer fits, or a cleanup regression leaking rows;
// both must fail loudly and keep the previous published values rather than
// publish a silently truncated number or run up an unbounded read bill.
const MAX_LIVE_SESSION_SCAN = 2000;

const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;

class PublicStatsError extends Error {
  constructor(message) {
    super(message);
    this.name = "PublicStatsError";
  }
}

/**
 * `collectionGroup("rooms")` matches the root `rooms` collection as well as
 * `activeVoiceSessions/{uid}/rooms`, so the full path is validated before a
 * document is allowed to contribute a person — the same defensive shape
 * `deleteActiveVoiceSessionsForRoom` uses. Returns the owning uid, or null if
 * the document is not a canonical voice-session mirror.
 */
function canonicalSessionUser(document) {
  const segments = String(document?.ref?.path ?? "").split("/");
  if (segments.length !== 4) return null;
  const [collection, userId, subcollection, roomId] = segments;
  if (collection !== ACTIVE_VOICE_SESSIONS || subcollection !== "rooms") {
    return null;
  }
  if (!SAFE_DOCUMENT_ID.test(userId) || !SAFE_DOCUMENT_ID.test(roomId)) {
    return null;
  }
  const data = typeof document?.data === "function"
    ? document.data() ?? {}
    : {};
  if (
    data.userId !== userId ||
    data.participantIdentity !== userId ||
    data.roomId !== roomId
  ) {
    return null;
  }
  return userId;
}

/**
 * People, not sessions. `activeVoiceSessions` is keyed per (user, room), so one
 * account in two rooms owns two documents and would otherwise be counted twice;
 * two devices in the SAME room share one document id and already collapse.
 * De-duplication is on the owning uid, which is why this cannot be a `count()`
 * aggregate — an aggregate counts index entries, and index entries are sessions.
 */
function distinctLiveSpeakers(
  documents,
  { maxSessions = MAX_LIVE_SESSION_SCAN } = {},
) {
  const rows = Array.isArray(documents) ? documents : [];
  if (rows.length > maxSessions) {
    throw new PublicStatsError(
      `The live voice session scan exceeded its ${maxSessions} document bound.`,
    );
  }
  const speakers = new Set();
  for (const document of rows) {
    const userId = canonicalSessionUser(document);
    if (userId !== null) speakers.add(userId);
  }
  return speakers.size;
}

/**
 * Reads one document per fresh session row. Deliberately bounded at
 * `maxSessions + 1` so truncation is detectable rather than silent.
 */
async function fetchFreshVoiceSessions({
  now = Date.now(),
  maxSessions = MAX_LIVE_SESSION_SCAN,
  database = db,
} = {}) {
  const snapshot = await database
    .collectionGroup("rooms")
    .where("expiresAt", ">", Timestamp.fromMillis(now))
    .limit(maxSessions + 1)
    .get();
  return snapshot.docs;
}

/**
 * A real `count()` aggregate, billed per up-to-1000 index entries scanned
 * rather than per document. A missing or malformed count is an error, never a
 * zero — a zero here would be published as "no accounts exist".
 */
async function countCollection(name, database = db) {
  const snapshot = await database.collection(name).count().get();
  const value = Number(snapshot?.data?.()?.count);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new PublicStatsError(
      `The ${name} count aggregate did not return a usable total.`,
    );
  }
  return value;
}

/**
 * All three sources must succeed. A partial run would mix one fresh number with
 * one missing number, and a missing number written as zero would read as
 * "nobody is here" — a lie, and a worse one than the hardcoded value it
 * replaces. Every source is settled so a second rejection cannot escape as an
 * unhandled promise, then the first real failure is rethrown.
 */
async function computePublicStats({
  now = Date.now(),
  maxSessions = MAX_LIVE_SESSION_SCAN,
  fetchSessions = fetchFreshVoiceSessions,
  countAccounts = () => countCollection("users"),
  countRooms = () => countCollection("rooms"),
} = {}) {
  const outcomes = await Promise.allSettled([
    fetchSessions({ now, maxSessions }),
    countAccounts(),
    countRooms(),
  ]);
  const failure = outcomes.find((outcome) => outcome.status === "rejected");
  if (failure) throw failure.reason;

  const [sessions, accountsCreated, roomsCreated] = outcomes
    .map((outcome) => outcome.value);
  return {
    schemaVersion: PUBLIC_STATS_SCHEMA_VERSION,
    peopleTalkingNow: distinctLiveSpeakers(sessions, { maxSessions }),
    accountsCreated,
    roomsCreated,
  };
}

/**
 * Computes first, writes once, and writes nothing at all if any source failed.
 * The previously published document therefore survives a failed run untouched,
 * and its `updatedAt` is what exposes the staleness to the website.
 */
async function publishPublicStats({
  now = Date.now(),
  maxSessions = MAX_LIVE_SESSION_SCAN,
  fetchSessions = fetchFreshVoiceSessions,
  countAccounts = () => countCollection("users"),
  countRooms = () => countCollection("rooms"),
  writeStats = null,
  updatedAt = null,
} = {}) {
  const stats = await computePublicStats({
    now,
    maxSessions,
    fetchSessions,
    countAccounts,
    countRooms,
  });
  const document = {
    ...stats,
    // Server commit time, not this instance's clock: `updatedAt` is the
    // staleness signal the presentation layer trusts.
    updatedAt: updatedAt ?? FieldValue.serverTimestamp(),
  };
  const write = writeStats ?? ((payload) => db
    .collection(PUBLIC_STATS_COLLECTION)
    .doc(PUBLIC_STATS_DOCUMENT)
    .set(payload));
  await write(document);
  return document;
}

/**
 * Every 5 minutes, matching the freshness window the data itself supports.
 * A slower cadence could publish a figure whose entire evidence window has
 * already rolled over; a faster one multiplies the per-run read cost for a
 * number that cannot become more truthful than its 5-minute source.
 *
 * A thrown failure is the intended outcome of an unavailable source: it is
 * visible in Cloud Scheduler and leaves the last good document in place.
 */
const publishPublicStatsSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 5 minutes",
    timeZone: "UTC",
    maxInstances: 1,
    timeoutSeconds: 120,
  },
  async () => {
    const stats = await publishPublicStats();
    logger.info("public stats published", {
      peopleTalkingNow: stats.peopleTalkingNow,
      accountsCreated: stats.accountsCreated,
      roomsCreated: stats.roomsCreated,
    });
  },
);

module.exports = {
  LIVE_SESSION_FRESHNESS_SECONDS,
  MAX_LIVE_SESSION_SCAN,
  PUBLIC_STATS_COLLECTION,
  PUBLIC_STATS_DOCUMENT,
  PUBLIC_STATS_SCHEMA_VERSION,
  PublicStatsError,
  REGION,
  canonicalSessionUser,
  computePublicStats,
  countCollection,
  distinctLiveSpeakers,
  fetchFreshVoiceSessions,
  publishPublicStats,
  publishPublicStatsSchedule,
};

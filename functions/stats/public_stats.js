// Public statistics — the real numbers the marketing site publishes.
//
// One server-owned document, `publicStats/live`, written only from here
// through the Admin SDK on a schedule. It is one of the project's two pinned,
// publicly readable documents (`publicShowcase/live` is the other). This
// aggregate document deliberately carries nothing except totals and the time
// they were computed: no uids, no room ids, no per-room breakdown, nothing
// that could be joined back to a person.
//
// WHAT IS PUBLISHED, AND WHY EACH NAME IS THE NAME IT IS.
//
// Both figures are `count()` aggregates over a live collection. That makes
// them CURRENT TOTALS, not lifetime creation counters, and both can go DOWN.
// The field names say so, because the previous names did not: `accountsCreated`
// and `roomsCreated` describe monotonic counters this function has never
// computed and cannot compute from a collection whose documents are deleted.
// A public number called "created" that shrinks is a quieter version of the
// same lie as a hardcoded "2,481 people talking right now".
//
//   activeAccounts — count() over `publicProfiles`, NOT over `users`.
//
//     `users` is the wrong source and would overstate the product by roughly
//     two to one. It is private account state, it retains rows for banned and
//     disabled accounts, and on 2026-08-16 a production sweep found 18 of its
//     33 documents were Auth orphans with no Firebase Auth account behind them
//     at all (docs/Decisions.md, ADR-055). `publicProfiles/{uid}` is the exact
//     server-owned projection maintained by `onUserPrivacySourceChanged`
//     (../profile/public_profiles.js), which treats Firebase Auth as the
//     existence authority and deletes the projection for a banned, disabled or
//     deleted account. Counting it answers "how many accounts exist and are
//     usable right now", which is the only account number this project can
//     state truthfully.
//
//     Its error direction is deliberate: during the projection trigger's short
//     consistency window a real account may not be counted yet, so the figure
//     can lag LOW. It cannot lag high, because a projection cannot exist for an
//     account Auth does not have.
//
//   existingRooms — count() over `rooms`.
//
//     Every room document that exists, live or ended, public or private. Rooms
//     are genuinely hard-deleted, so this figure visibly shrinks; "existing" is
//     chosen over "created" precisely so that is unsurprising rather than a
//     bug report. It is not filtered to `isLive`, because nothing reliably
//     clears `isLive` after a crash and a filtered figure would inherit that
//     staleness while sounding more precise than it is.
//
// WHAT IS NOT PUBLISHED: `peopleTalkingNow`.
//
// There is no honest live-presence number to publish yet, so this document
// carries no field for one. The reasoning, because the code for it is still
// below and somebody will be tempted:
//
// The only server-authoritative voice source today is `activeVoiceSessions`
// (`allow read, write: if false`), written by `recordAuthorizedVoiceSession`
// (../livekit/token.js) and removed only by a server-mediated leave, room end
// or moderation action. NOTHING removes a row when a client crashes, drops its
// network or closes the tab. Each row carries `expiresAt` = token issuance +
// VOICE_TOKEN_TTL_SECONDS, and the client mints exactly one token per join and
// never refreshes it, so bounding by that expiry is the only freshness signal
// the data supports — and it drops everyone who has been in a room longer than
// five minutes. A busy room of twelve people an hour into a conversation
// publishes ZERO. That is not a conservative lower bound, it is an error that
// grows with the very thing being measured, and it is at its worst exactly
// when the number would matter. Counting without the bound is worse: it
// reports people who left hours ago, which is the fiction this feature exists
// to delete.
//
// The replacement is not a refinement of the code below; it is a different
// query over a different collection. `receiveLiveKitAchievementWebhook`
// (../achievements/livekit_http.js, wired in fe82755) maintains
// `achievementVoiceSessions`, whose rows are closed by LiveKit's own
// `participant_left` / `participant_connection_aborted` / `room_finished`
// events — real presence, including after a crash. A live count from that
// source is `collection('achievementVoiceSessions').where('status','==','open')`
// de-duplicated on `userId`: a top-level collection, served by the automatic
// single-field index, needing no index deploy at all.
//
// So `peopleTalkingNow` is introduced ONCE, when it can be defined correctly,
// rather than published now with one meaning and silently redefined later.
// Until then the marketing site simply renders no live line — its LiveStats
// component already treats a missing field as "do not show", so nothing there
// has to change to accommodate the absence.
//
// The `activeVoiceSessions` scan is kept below, exported and tested, but is
// deliberately NOT called by the publisher. READ THE WARNING ON
// fetchFreshVoiceSessions BEFORE RECONNECTING IT.

const { logger } = require("firebase-functions/v2");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { ACTIVE_VOICE_SESSIONS } = require("../livekit/sessions");
const { VOICE_TOKEN_TTL_SECONDS } = require("../livekit/token");

const REGION = "europe-west1";

const PUBLIC_STATS_COLLECTION = "publicStats";
const PUBLIC_STATS_DOCUMENT = "live";
// Version 2 is the first version ever published. Version 1 —
// { peopleTalkingNow, accountsCreated, roomsCreated } — was committed in
// cb4651a and deliberately never deployed, so no reader has ever seen it and
// no compatibility path is owed to it. The bump exists so that document shape
// and version number cannot be confused with each other later.
const PUBLIC_STATS_SCHEMA_VERSION = 2;

// The exact server-owned projection of accounts that currently exist and are
// usable. See the header for why this is not `users`.
const ACTIVE_ACCOUNTS_COLLECTION = "publicProfiles";
const ROOMS_COLLECTION = "rooms";

// The freshness bound IS the token TTL. Deriving it rather than restating it
// means the two can never drift apart in a way that silently invents presence.
// Unused by the publisher today; see the header.
const LIVE_SESSION_FRESHNESS_SECONDS = VOICE_TOKEN_TTL_SECONDS;

// A hard ceiling on documents read per run of the dormant live-session scan.
// Exceeding it means either genuine scale this approach no longer fits, or a
// cleanup regression leaking rows; both must fail loudly rather than publish a
// silently truncated number or run up an unbounded read bill.
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
 *
 * Part of the dormant live-presence path; see the header.
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
 *
 * Part of the dormant live-presence path; see the header.
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
 * DORMANT — NOT CALLED BY THE PUBLISHER, AND NOT SAFE TO CALL WITHOUT AN INDEX
 * DEPLOY.
 *
 * Two independent reasons to read the header before wiring this back in:
 *
 * 1. The number it produces is wrong in the way described there — a busy room
 *    reports zero. The fix is `achievementVoiceSessions`, not this.
 * 2. `collectionGroup(...).where(...)` is NOT served by Firestore's automatic
 *    single-field indexes: those are maintained at COLLECTION scope only. This
 *    query needs a COLLECTION_GROUP single-field index on `rooms.expiresAt`,
 *    declared as a `fieldOverrides` entry in firestore.indexes.json AND
 *    deployed. Without it every scheduled run throws FAILED_PRECONDITION —
 *    the same failure that silently stopped Premium from ever expiring
 *    (docs/DEPLOYMENT.md). The emulator does not require indexes, so no test
 *    in this repository will warn you.
 *
 *    That entry must ALSO re-declare the two COLLECTION-scope orders. A
 *    `fieldOverrides` entry REPLACES automatic indexing for the field rather
 *    than adding to it; the live project shows this plainly — the deployed
 *    `rooms.roomId` override carries only its COLLECTION_GROUP index and the
 *    automatic collection-scope ones are gone.
 *
 * Reads one document per fresh session row, bounded at `maxSessions + 1` so
 * truncation is detectable rather than silent.
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
 * rather than per document, and needing no index of its own. A missing or
 * malformed count is an error, never a zero — a zero here would be published
 * as "no accounts exist".
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
 * Both sources must succeed. A partial run would mix one fresh number with one
 * missing number, and a missing number written as zero would read as "nobody is
 * here" — a lie, and a worse one than the hardcoded value it replaces. Every
 * source is settled so a second rejection cannot escape as an unhandled
 * promise, then the first real failure is rethrown.
 */
async function computePublicStats({
  countAccounts = () => countCollection(ACTIVE_ACCOUNTS_COLLECTION),
  countRooms = () => countCollection(ROOMS_COLLECTION),
} = {}) {
  const outcomes = await Promise.allSettled([countAccounts(), countRooms()]);
  const failure = outcomes.find((outcome) => outcome.status === "rejected");
  if (failure) throw failure.reason;

  const [activeAccounts, existingRooms] = outcomes
    .map((outcome) => outcome.value);
  return {
    schemaVersion: PUBLIC_STATS_SCHEMA_VERSION,
    activeAccounts,
    existingRooms,
  };
}

/**
 * Computes first, writes once, and writes nothing at all if any source failed.
 * The previously published document therefore survives a failed run untouched,
 * and its `updatedAt` is what exposes the staleness to the website.
 *
 * `set` without merge is deliberate: the published document is exactly what
 * this function computed, so a field removed here disappears from the world
 * rather than lingering at its last value forever.
 */
async function publishPublicStats({
  countAccounts = () => countCollection(ACTIVE_ACCOUNTS_COLLECTION),
  countRooms = () => countCollection(ROOMS_COLLECTION),
  writeStats = null,
  updatedAt = null,
} = {}) {
  const stats = await computePublicStats({ countAccounts, countRooms });
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
 * Every 5 minutes. The cadence is set by the CONSUMER, not by how fast the
 * numbers move: the website discards this document as stale after 15 minutes
 * and then renders nothing, so a 15-minute cadence would leave no margin and a
 * single missed run would blank the line. Five minutes tolerates two
 * consecutive failures before a visitor sees anything change, and two `count()`
 * aggregates every five minutes is a few hundred reads a day.
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
      activeAccounts: stats.activeAccounts,
      existingRooms: stats.existingRooms,
    });
  },
);

module.exports = {
  ACTIVE_ACCOUNTS_COLLECTION,
  LIVE_SESSION_FRESHNESS_SECONDS,
  MAX_LIVE_SESSION_SCAN,
  PUBLIC_STATS_COLLECTION,
  PUBLIC_STATS_DOCUMENT,
  PUBLIC_STATS_SCHEMA_VERSION,
  PublicStatsError,
  REGION,
  ROOMS_COLLECTION,
  canonicalSessionUser,
  computePublicStats,
  countCollection,
  distinctLiveSpeakers,
  fetchFreshVoiceSessions,
  publishPublicStats,
  publishPublicStatsSchedule,
};

const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { timestampMillis } = require("../integrity/guards");
const {
  momentCapacityLedgerReference,
  touchMomentCapacityLedger,
} = require("./capacity");

const REGION = "europe-west1";

/**
 * The scan bound, and a real bound rather than a formality: candidates are
 * published Moments whose chosen deadline has already passed, and the
 * product caps every author at 10 simultaneously live Moments, so a backlog
 * of 200 means twenty authors' complete story shelves all expired inside
 * one 10-minute cadence — already far beyond current production volume. If
 * the ceiling is ever reached the sweep reports `truncated: true` and says
 * so in the log rather than quietly covering a prefix; the next run picks
 * up the remainder, because expiring Moments only ever shrinks the
 * candidate set.
 */
const MAX_EXPIRED_MOMENT_SCAN = 200;

/**
 * THE SWEEP THAT TAKES A STORY OFF THE SHELF ONCE ITS DEADLINE PASSES.
 *
 * finalizeMomentDraft (./integrity.js) stamps every EXPIRING published
 * Voice Moment with `expiresAt = createdAt + availability` — the
 * operator-chosen availability window, 24 hours by default. Expiry
 * enforcement is two-layer by design: this schedule is the SERVER truth
 * that actually retires the document, and the client feed additionally
 * filters `expiresAt > now` (missing = permanent = visible) so the
 * at-most-10-minute gap between deadline and sweep never shows a dead
 * Moment to anybody. Neither layer alone is the feature — without this
 * sweep "expiry" would be a frontend pretence a modified client ignores;
 * without the client filter every Moment would linger publicly for up to
 * one cadence past its deadline.
 *
 * THE FLIP IS EXACTLY `{ isPublished: false, status: "expired", updatedAt }`
 * AND NOTHING ELSE. An expired Moment is retired, not destroyed: its audio,
 * caption, likes, comments and reports all stay where they are, the author
 * can still delete it (deleteMoment passes `allowExpired`), moderation can
 * still act on it, and `validateMoment` recognises the expired shape and
 * refuses NEW likes and comments with a clean failed-precondition. Deletion
 * remains the only path that queues storage cleanup.
 *
 * A MOMENT WITH NO `expiresAt` IS SKIPPED, DELIBERATELY — THAT IS WHAT
 * "PERMANENT" MEANS. finalizeMomentDraft's operator-chosen availability
 * (2026-08, amending ADR-101) writes no deadline at all for a "permanent"
 * publish, and the legacy pre-expiry documents production still holds
 * share the exact same shape. Both mean published-until-deleted: the
 * client shows them with no countdown, the active cap counts them, and
 * this sweep must never touch them. Firestore range filters never match a
 * document missing the filtered field, so they are structurally invisible
 * to the query below — and the per-document transaction independently
 * refuses a null deadline besides. Nothing here backfills deadlines onto
 * documents published without one.
 *
 * WHY `expiresAt <= now` RATHER THAN AN AGE HEURISTIC. The deadline was
 * written by a transaction that derived it from the same createdAt the
 * client renders countdowns from, so the query condition and the product
 * promise are the same fact. There is no grace period: unlike the room
 * liveness sweep, nothing legitimate ever lives past this deadline, and
 * the client filter has already hidden the Moment by the time this runs.
 *
 * THE QUERY NEEDS THE (isPublished ASC, expiresAt ASC) COMPOSITE from
 * firestore.indexes.json — deployed, not merely committed. The emulator
 * serves every query unindexed, so no suite can prove the index exists;
 * docs/DEPLOYMENT.md records how exactly this failure mode once left
 * Premium expiry silently dead (and see ADR-007). Run the production query
 * once after deploying.
 */
async function expireVoiceMoments({
  now = () => Timestamp.now(),
  maxMoments = MAX_EXPIRED_MOMENT_SCAN,
  expireOne = expireMomentIfStillPastDeadline,
} = {}) {
  const boundedMax = Math.max(
    1,
    Math.min(Number(maxMoments) || 0, MAX_EXPIRED_MOMENT_SCAN),
  );
  const startedAt = now();

  const snapshot = await db
    .collection("voiceMoments")
    .where("isPublished", "==", true)
    .where("expiresAt", "<=", startedAt)
    .orderBy("expiresAt", "asc")
    .limit(boundedMax + 1)
    .get();

  const truncated = snapshot.size > boundedMax;
  const candidates = snapshot.docs.slice(0, boundedMax);

  const expired = [];
  let skippedChanged = 0;
  const failures = [];

  for (const document of candidates) {
    try {
      const outcome = await expireOne(
        document.ref,
        startedAt,
        document.data()?.authorId,
      );
      if (outcome === "expired") {
        expired.push(document.id);
      } else {
        skippedChanged += 1;
      }
    } catch (error) {
      failures.push({ momentId: document.id, error });
      // The Error goes in as its own argument rather than folded into the
      // payload — `entryFromArgs` in firebase-functions overwrites a
      // `message` key on the payload object with a synthetic stack unless
      // one of the arguments is a real Error (same lesson as the room
      // liveness sweep).
      logger.error("voice moment expiry failed for one moment", error, {
        momentId: document.id,
      });
    }
  }

  const outcome = {
    scanned: candidates.length,
    expired: expired.length,
    expiredMomentIds: expired,
    skippedChanged,
    failed: failures.length,
    truncated,
  };

  if (truncated) {
    logger.warn("voice moment expiry sweep reached its scan bound", outcome);
  }
  if (failures.length > 0) {
    const aggregate = new Error(
      `Voice Moment expiry failed for ${failures.length} of ` +
        `${candidates.length} moments.`,
    );
    aggregate.cause = failures[0].error;
    aggregate.outcome = outcome;
    throw aggregate;
  }

  return outcome;
}

/**
 * Re-decides the whole question inside a transaction and writes only if the
 * answer still holds.
 *
 * THE SCAN ABOVE IS A HINT, NOT A VERDICT. Between the query and this
 * transaction the author can delete the Moment (status "deleting" must not
 * be overwritten back to "expired" — that would orphan the queued storage
 * cleanup's terminal state), a previous run can already have expired it,
 * or the document can be gone entirely. Only a Moment that is STILL a
 * published, non-deleted document with a still-passed deadline is flipped;
 * anything else reports "changed" and is left exactly as it is.
 */
async function expireMomentIfStillPastDeadline(
  momentReference,
  cutoff,
  expectedAuthorId = null,
) {
  const cutoffMillis = cutoff.toMillis();
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(momentReference);
    if (!snapshot.exists) return "changed";

    const moment = snapshot.data() ?? {};
    const expiresAtMillis = timestampMillis(moment.expiresAt);
    if (moment.isPublished !== true || moment.status !== "published" ||
        moment.isDeleted === true || expiresAtMillis === null ||
        expiresAtMillis > cutoffMillis) {
      return "changed";
    }
    if (expectedAuthorId !== null && moment.authorId !== expectedAuthorId) {
      return "changed";
    }

    // Expiry and finalization affect the same per-author capacity shelf even
    // though they update different Moment documents. Reading and advancing
    // the shared mutex in this transaction makes a finalize racing the sweep
    // retry against the post-expiry truth instead of making a stale decision.
    const capacityRef = momentCapacityLedgerReference(db, moment.authorId);
    const capacity = await transaction.get(capacityRef);

    // The whole flip. Everything else on the document — audio, caption,
    // counters, expiresAt itself — stays untouched; see the header.
    touchMomentCapacityLedger(
      transaction,
      capacityRef,
      capacity,
      moment.authorId,
      cutoff,
    );
    transaction.update(momentReference, {
      isPublished: false,
      status: "expired",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "expired";
  });
}

/**
 * Every 10 minutes: one indexed query plus one tiny transaction per newly
 * passed deadline, and a Moment outlives its chosen availability by at most
 * one cadence — during which the client filter already hides it.
 * `maxInstances: 1` keeps two runs from racing each other onto the same
 * Moment; the per-document transaction would make that correct anyway, but
 * not free.
 */
const expireVoiceMomentsSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 10 minutes",
    timeZone: "UTC",
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    const outcome = await expireVoiceMoments();
    if (outcome.expired > 0) {
      logger.info("voice moments expired", outcome);
    }
  },
);

module.exports = {
  MAX_EXPIRED_MOMENT_SCAN,
  REGION,
  expireMomentIfStillPastDeadline,
  expireVoiceMoments,
  expireVoiceMomentsSchedule,
};

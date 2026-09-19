/**
 * Server event reminders (ADR-212).
 *
 * Family calendar entries and Podcast program entries already let a member
 * tap "remind me": `respondToServerEventV1` stores `reminderRequested` on
 * the member's response and counts it on the event. Nothing ever delivered
 * that reminder (docs/Servers.md: "This stores reminder intent only"), which
 * is a promise the product was making and not keeping. This worker keeps it.
 *
 * Shape:
 *   - every five minutes, a `collectionGroup("events")` query finds the
 *     scheduled, reminder-capable events starting inside the next fifteen
 *     minutes. That query needs a COLLECTION_GROUP composite index
 *     (firestore.indexes.json); automatic single-field indexes are
 *     COLLECTION scope only and the emulator never enforces either, so
 *     ADR-007 applies: the index is declared, asserted by a test, and the
 *     real query is exercised against the emulator.
 *   - the query is PAGED with a `startsAt`/`__name__` cursor until the due
 *     set is exhausted or the run's wall-clock budget is spent. A single
 *     `limit(EVENT_SCAN_LIMIT)` page was a silent, permanent cliff: the
 *     hundred-and-first event in a fifteen-minute window never got a
 *     reminder on any run, and the cap was global across every server, so
 *     one account's events could bury another server's. The same paging
 *     applies to an event's opted-in responses, which were previously cut
 *     at five hundred with no cursor and no log.
 *   - for each event, the opted-in responses are read and one row per member
 *     is written through the canonical writer. The notification id carries
 *     the event's REVISION, so rescheduling an event re-arms its reminder
 *     while a redelivery of the same revision is a no-op.
 *   - a delivered event is STAMPED (`reminderDeliveredAt`,
 *     `reminderDeliveredStartsAt`, `reminderDeliveredRevision`; additive,
 *     server-written only). Because `updateServerEventV1` bumps the revision
 *     for any patch — a description-only edit included — the revision alone
 *     made every edit a fresh reminder id, so an event manager could park an
 *     event just inside the horizon and re-edit it between runs to push a new
 *     lock-screen line at every opted-in member every five minutes. The stamp
 *     re-arms a reminder only for a real reschedule (the start moves further
 *     than the whole horizon) and never more than once per cooldown.
 *   - cancelling an event removes it from the query, and the source
 *     validator refuses a row whose event is no longer scheduled at that
 *     revision — at write time and again at push time.
 *
 * The event's author is the notification's actor: a reminder still passes
 * through blocks, restrictions and account state like every other row. A
 * member reminded about their own event is the one case where recipient and
 * actor are the same account, which is why the canonical writer takes an
 * explicit `allowSelf`.
 */
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions/v2");
const { FieldPath, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { timestampMillis } = require("../integrity/guards");
const { createNotificationForEvent, eventLedgerReference } = require("./canonical");
const {
  channelReadable,
  parseServerEventPath,
  serverEventReminderSourceIsCurrent,
} = require("./engagement_source");

const REGION = "europe-west1";
// How far ahead a reminder is sent. Three scheduler runs cover the window,
// so one missed run still delivers.
const REMINDER_HORIZON_MS = 15 * 60_000;
// Page sizes, not caps: both queries are followed by a cursor until the set
// is exhausted.
const EVENT_SCAN_LIMIT = 100;
const RESPONSE_SCAN_LIMIT = 500;
// A run stops paging at this point and leaves the rest to the next one,
// which is five minutes away and inside a fifteen-minute horizon. The
// function's own timeout is 300 s, so this is the bound that produces a log
// line instead of a killed invocation.
const REMINDER_RUN_BUDGET_MS = 240_000;
// The shortest interval at which one event may remind the same audience
// twice. A genuine reschedule still has to move the start further than the
// whole horizon before this is even consulted.
const REMINDER_REARM_COOLDOWN_MS = 60 * 60_000;
const MAX_LABEL = 120;

/**
 * THE production query. Kept in one exported place so the index-declaration
 * test and the emulator test cannot drift from what the worker runs.
 *
 * `startAfter` takes the last document of the previous page, which carries
 * both ordered values (`startsAt` and `__name__`) and therefore needs no
 * extra index beyond the declared composite.
 */
function dueReminderEventsQuery(database, { now, horizon, limit, startAfter = null }) {
  const query = database.collectionGroup("events")
    .where("reminderOptInEnabled", "==", true)
    .where("status", "==", "scheduled")
    .where("startsAt", ">", now)
    .where("startsAt", "<=", horizon)
    .orderBy("startsAt", "asc");
  return (startAfter ? query.startAfter(startAfter) : query).limit(limit);
}

/**
 * The opted-in responses of one event, ordered by document id so the pages
 * are a stable, complete traversal rather than an arbitrary subset. An
 * equality filter ordered by `__name__` is served by the automatic
 * single-field index, so this needs no declaration.
 */
function optedInResponsesQuery(eventReference, limit, startAfter = null) {
  const query = eventReference.collection("responses")
    .where("reminderRequested", "==", true)
    .orderBy(FieldPath.documentId());
  return (startAfter ? query.startAfter(startAfter) : query).limit(limit);
}

function reminderNotificationId(eventId, revision) {
  return `eventReminder_${eventId}_${revision}`;
}

function reminderEventId(source, revision, recipientId) {
  return [
    "server-event-reminder",
    source.serverId,
    source.channelId,
    source.eventId,
    revision,
    recipientId,
  ].join(":");
}

/** The event fields a reminder depends on, or null when it is not one. */
function remindableEvent(snapshot, nowMs) {
  const source = parseServerEventPath(snapshot?.ref?.path);
  const event = snapshot?.exists ? snapshot.data() ?? {} : null;
  const startsAtMs = timestampMillis(event?.startsAt);
  if (!source || !event || event.schemaVersion !== 1 ||
      event.status !== "scheduled" || event.reminderOptInEnabled !== true ||
      event.serverId !== source.serverId ||
      event.channelId !== source.channelId ||
      event.eventId !== source.eventId ||
      typeof event.authorId !== "string" || event.authorId.length === 0 ||
      !Number.isSafeInteger(event.revision) || event.revision < 1 ||
      !Number.isSafeInteger(event.reminderCount) || event.reminderCount < 1 ||
      startsAtMs === null || startsAtMs <= nowMs ||
      typeof event.title !== "string") {
    return null;
  }
  return { ...source, event, startsAtMs };
}

/**
 * True when this event may remind its audience now.
 *
 * An event that has never been reminded always may. One that has is refused
 * unless BOTH of these hold, which is what separates a reschedule from an
 * edit:
 *   - the start moved further than the entire reminder horizon, so the
 *     earlier reminder no longer describes when the event begins (a title or
 *     description edit, or a nudge of a few minutes, moves nothing);
 *   - the cooldown since the last delivery has passed, so even a genuine
 *     series of reschedules cannot become a per-run push channel.
 */
function reminderIsRearmed(event, startsAtMs, nowMs) {
  const deliveredAtMs = timestampMillis(event?.reminderDeliveredAt);
  if (deliveredAtMs === null) return true;
  const deliveredStartsAtMs = timestampMillis(event?.reminderDeliveredStartsAt);
  if (deliveredStartsAtMs === null) return false;
  if (Math.abs(startsAtMs - deliveredStartsAtMs) <= REMINDER_HORIZON_MS) {
    return false;
  }
  return nowMs - deliveredAtMs >= REMINDER_REARM_COOLDOWN_MS;
}

/**
 * Records that this event reminded its audience. Additive and server-written
 * only: clients cannot write anything under `events/`, and the three fields
 * are absent on every event created before this worker existed.
 */
async function stampReminderDelivery(reference, { event, nowMs }) {
  await reference.update({
    reminderDeliveredAt: Timestamp.fromMillis(nowMs),
    reminderDeliveredStartsAt: event.startsAt,
    reminderDeliveredRevision: event.revision,
  }).catch((error) => {
    // The event may have been cancelled or removed mid-run. The reminders
    // already delivered stand; the stamp is an optimisation, not a receipt.
    logger.info("Skipped a server event reminder stamp", {
      path: reference.path,
      code: error?.code ?? "unknown",
    });
  });
}

async function remindOneEvent(snapshot, {
  firestore,
  nowMs,
  deadlineMs = Number.POSITIVE_INFINITY,
  clock = Date.now,
}) {
  const remindable = remindableEvent(snapshot, nowMs);
  if (!remindable) return { considered: 0, written: 0, skipped: "not-due" };
  const { event, serverId, channelId, eventId, startsAtMs } = remindable;
  if (!reminderIsRearmed(event, startsAtMs, nowMs)) {
    return { considered: 0, written: 0, skipped: "already-reminded" };
  }
  const revision = event.revision;
  const sourcePath = snapshot.ref.path;
  const targetLabel = event.title.trim().slice(0, MAX_LABEL) || null;
  let considered = 0;
  let written = 0;
  let truncated = false;
  let cursor = null;
  while (!truncated) {
    const responses = await optedInResponsesQuery(
      snapshot.ref,
      RESPONSE_SCAN_LIMIT,
      cursor,
    ).get();
    if (responses.empty) break;
    for (const response of responses.docs) {
      considered += 1;
      const recipientId = response.id;
      const data = response.data() ?? {};
      if (data.userId !== recipientId || data.reminderRequested !== true) continue;
      const eventLedgerId = reminderEventId(remindable, revision, recipientId);
      // One get before anything expensive. A recipient already decided for
      // this (event, revision) costs a single read on every later run inside
      // the horizon instead of an ACL read plus an eight-read transaction.
      if ((await eventLedgerReference(eventLedgerId, firestore).get()).exists) {
        continue;
      }
      // Cheap fail-fast before an eight-read transaction: membership and the
      // channel ACL are rechecked inside the writer's transaction anyway.
      if (!(await channelReadable(firestore, firestore, {
        uid: recipientId,
        serverId,
        channelId,
      }))) {
        continue;
      }
      const notification = {
        type: "serverEventReminder",
        actorId: event.authorId,
        targetId: serverId,
        targetSubId: channelId,
        sourcePath,
        sourceGeneration: String(revision),
      };
      const outcome = await createNotificationForEvent({
        eventId: eventLedgerId,
        recipientId,
        actorId: event.authorId,
        type: "serverEventReminder",
        notificationId: reminderNotificationId(eventId, revision),
        targetId: serverId,
        targetSubId: channelId,
        targetLabel,
        sourcePath,
        sourceGeneration: String(revision),
        allowSelf: true,
        firestore,
        validate: (transaction) => serverEventReminderSourceIsCurrent({
          recipientId,
          notification,
          reader: transaction,
          firestore,
          nowMs,
        }),
      });
      if (outcome === "written") written += 1;
      if (clock() >= deadlineMs) {
        truncated = true;
        break;
      }
    }
    if (truncated || responses.size < RESPONSE_SCAN_LIMIT) break;
    cursor = responses.docs[responses.docs.length - 1];
  }
  // A run that did not reach the end of the audience must not stamp: the
  // next run has to finish the tail, and the per-recipient ledger keeps the
  // members already reminded from being reminded twice.
  if (!truncated) {
    await stampReminderDelivery(snapshot.ref, { event, nowMs });
  }
  return { considered, written, truncated };
}

async function sendDueServerEventReminders({
  firestore = db,
  now = Timestamp.now(),
  limit = EVENT_SCAN_LIMIT,
  budgetMs = REMINDER_RUN_BUDGET_MS,
  clock = Date.now,
} = {}) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > EVENT_SCAN_LIMIT) {
    throw new TypeError(`limit must be 1-${EVENT_SCAN_LIMIT}.`);
  }
  const nowMs = timestampMillis(now);
  if (nowMs === null) throw new TypeError("A Firestore Timestamp is required.");
  const horizon = Timestamp.fromMillis(nowMs + REMINDER_HORIZON_MS);
  const deadlineMs = clock() + budgetMs;
  let events = 0;
  let pages = 0;
  let notified = 0;
  let considered = 0;
  let truncatedEvents = 0;
  let budgetExhausted = false;
  let cursor = null;
  const failures = [];
  for (;;) {
    const snapshot = await dueReminderEventsQuery(firestore, {
      now,
      horizon,
      limit,
      startAfter: cursor,
    }).get();
    if (snapshot.empty) break;
    pages += 1;
    for (const document of snapshot.docs) {
      events += 1;
      try {
        const outcome = await remindOneEvent(document, {
          firestore,
          nowMs,
          deadlineMs,
          clock,
        });
        notified += outcome.written;
        considered += outcome.considered;
        if (outcome.truncated) truncatedEvents += 1;
      } catch (error) {
        failures.push({ path: document.ref.path, code: error?.code ?? "unknown" });
      }
      if (clock() >= deadlineMs) {
        budgetExhausted = true;
        break;
      }
    }
    if (budgetExhausted || snapshot.size < limit) break;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
  return {
    events,
    pages,
    considered,
    notified,
    failed: failures.length,
    failures,
    truncatedEvents,
    budgetExhausted,
    // Retained name, honest meaning: the due set was NOT finished on this
    // run. It is now a wall-clock outcome rather than "the page was full".
    hasMore: budgetExhausted || truncatedEvents > 0,
    nowMs,
  };
}

const sendServerEventRemindersSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 5 minutes",
    timeZone: "UTC",
    maxInstances: 1,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const outcome = await sendDueServerEventReminders();
    // An unfinished run is an operational signal, not a statistic: the
    // earlier version computed it and threw it away.
    if (outcome.hasMore || outcome.failed > 0) {
      logger.warn("Server event reminders did not finish the due set", outcome);
      return;
    }
    logger.info("Server event reminders delivered", outcome);
  },
);

module.exports = {
  EVENT_SCAN_LIMIT,
  REMINDER_HORIZON_MS,
  REMINDER_REARM_COOLDOWN_MS,
  REMINDER_RUN_BUDGET_MS,
  RESPONSE_SCAN_LIMIT,
  dueReminderEventsQuery,
  optedInResponsesQuery,
  remindOneEvent,
  remindableEvent,
  reminderEventId,
  reminderIsRearmed,
  reminderNotificationId,
  sendDueServerEventReminders,
  sendServerEventRemindersSchedule,
};

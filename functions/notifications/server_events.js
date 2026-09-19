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
 *   - every five minutes, one `collectionGroup("events")` query finds the
 *     scheduled, reminder-capable events starting inside the next fifteen
 *     minutes. That query needs a COLLECTION_GROUP composite index
 *     (firestore.indexes.json); automatic single-field indexes are
 *     COLLECTION scope only and the emulator never enforces either, so
 *     ADR-007 applies: the index is declared, asserted by a test, and the
 *     real query is exercised against the emulator.
 *   - for each event, the opted-in responses are read and one row per member
 *     is written through the canonical writer. The notification id carries
 *     the event's REVISION, so rescheduling an event re-arms its reminder
 *     while a redelivery of the same revision is a no-op.
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
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { timestampMillis } = require("../integrity/guards");
const { createNotificationForEvent } = require("./canonical");
const {
  channelReadable,
  parseServerEventPath,
  serverEventReminderSourceIsCurrent,
} = require("./engagement_source");

const REGION = "europe-west1";
// How far ahead a reminder is sent. Three scheduler runs cover the window,
// so one missed run still delivers.
const REMINDER_HORIZON_MS = 15 * 60_000;
const EVENT_SCAN_LIMIT = 100;
const RESPONSE_SCAN_LIMIT = 500;
const MAX_LABEL = 120;

/**
 * THE production query. Kept in one exported place so the index-declaration
 * test and the emulator test cannot drift from what the worker runs.
 */
function dueReminderEventsQuery(database, { now, horizon, limit }) {
  return database.collectionGroup("events")
    .where("reminderOptInEnabled", "==", true)
    .where("status", "==", "scheduled")
    .where("startsAt", ">", now)
    .where("startsAt", "<=", horizon)
    .orderBy("startsAt", "asc")
    .limit(limit);
}

function optedInResponsesQuery(eventReference, limit) {
  return eventReference.collection("responses")
    .where("reminderRequested", "==", true)
    .limit(limit);
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

async function remindOneEvent(snapshot, { firestore, nowMs }) {
  const remindable = remindableEvent(snapshot, nowMs);
  if (!remindable) return { considered: 0, written: 0, skipped: "not-due" };
  const { event, serverId, channelId, eventId } = remindable;
  const revision = event.revision;
  const sourcePath = snapshot.ref.path;
  const targetLabel = event.title.trim().slice(0, MAX_LABEL) || null;
  const responses = await optedInResponsesQuery(
    snapshot.ref,
    RESPONSE_SCAN_LIMIT,
  ).get();
  let written = 0;
  for (const response of responses.docs) {
    const recipientId = response.id;
    const data = response.data() ?? {};
    if (data.userId !== recipientId || data.reminderRequested !== true) continue;
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
      eventId: reminderEventId(remindable, revision, recipientId),
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
  }
  return {
    considered: responses.size,
    written,
    truncated: responses.size === RESPONSE_SCAN_LIMIT,
  };
}

async function sendDueServerEventReminders({
  firestore = db,
  now = Timestamp.now(),
  limit = EVENT_SCAN_LIMIT,
} = {}) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > EVENT_SCAN_LIMIT) {
    throw new TypeError(`limit must be 1-${EVENT_SCAN_LIMIT}.`);
  }
  const nowMs = timestampMillis(now);
  if (nowMs === null) throw new TypeError("A Firestore Timestamp is required.");
  const snapshot = await dueReminderEventsQuery(firestore, {
    now,
    horizon: Timestamp.fromMillis(nowMs + REMINDER_HORIZON_MS),
    limit,
  }).get();
  let notified = 0;
  let considered = 0;
  const failures = [];
  for (const document of snapshot.docs) {
    try {
      const outcome = await remindOneEvent(document, { firestore, nowMs });
      notified += outcome.written;
      considered += outcome.considered;
    } catch (error) {
      failures.push({ path: document.ref.path, code: error?.code ?? "unknown" });
    }
  }
  return {
    events: snapshot.size,
    considered,
    notified,
    failed: failures.length,
    failures,
    hasMore: snapshot.size === limit,
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
    logger.info("Server event reminders delivered", outcome);
  },
);

module.exports = {
  EVENT_SCAN_LIMIT,
  REMINDER_HORIZON_MS,
  RESPONSE_SCAN_LIMIT,
  dueReminderEventsQuery,
  optedInResponsesQuery,
  remindOneEvent,
  remindableEvent,
  reminderEventId,
  reminderNotificationId,
  sendDueServerEventReminders,
  sendServerEventRemindersSchedule,
};

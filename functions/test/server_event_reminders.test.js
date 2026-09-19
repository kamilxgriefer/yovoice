/**
 * Server event reminders (ADR-212), the half of the promise the product was
 * already making: Family calendar entries and Podcast program entries accept
 * "remind me" and, until now, delivered nothing.
 *
 * ADR-007 applies in full, and both halves below are required:
 *
 *   1. the declaration test asserts `firestore.indexes.json` carries the
 *      COLLECTION_GROUP composite the production query needs. The emulator
 *      never enforces index requirements, so no emulator run can catch a
 *      missing one — only a FAILED_PRECONDITION in production would;
 *   2. the emulator tests run the REAL `collectionGroup("events")` query and
 *      the real worker across two different parent channels, which a
 *      declaration test cannot do.
 */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice-event-reminders";

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
// The worker module binds the DEFAULT app's Firestore for its production
// default argument, so the default app has to exist even though every
// assertion below drives an isolated, explicitly named app.
const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp(
    { projectId: "demo-yovoice-event-reminders" },
    `event-reminders-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const { createServerEventService } = require("../servers/events");
const {
  REMINDER_HORIZON_MS,
  dueReminderEventsQuery,
  reminderNotificationId,
  sendDueServerEventReminders,
} = require("../notifications/server_events");
const {
  serverEventReminderSourceIsCurrent,
} = require("../notifications/engagement_source");

const START_MS = 1_920_000_000_000;
const request = (uid, data) => ({
  auth: { uid, token: { email_verified: true } },
  data,
});
const emulatorTest = (name, fn) => test(
  `Server event reminders: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);

after(async () => {
  if (app) await require("firebase-admin/app").deleteApp(app);
});

test("the reminder query's COLLECTION_GROUP index is declared", () => {
  const declared = JSON.parse(readFileSync(
    path.resolve(__dirname, "..", "..", "firestore.indexes.json"),
    "utf8",
  ));
  // Exactly the fields dueReminderEventsQuery filters and orders on, in
  // order: two equalities, then the range/order field.
  const expected = [
    { fieldPath: "reminderOptInEnabled", order: "ASCENDING" },
    { fieldPath: "status", order: "ASCENDING" },
    { fieldPath: "startsAt", order: "ASCENDING" },
  ];
  const match = declared.indexes.find((index) =>
    index.collectionGroup === "events" &&
    index.queryScope === "COLLECTION_GROUP" &&
    JSON.stringify(index.fields) === JSON.stringify(expected));
  assert.ok(
    match,
    "firestore.indexes.json must declare the COLLECTION_GROUP events index " +
      "(reminderOptInEnabled, status, startsAt); automatic single-field " +
      "indexes are COLLECTION scope only.",
  );
});

async function user(prefix = "reminder-user") {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${uid}`,
    status: "active",
  });
  return uid;
}

async function fixture(serverType = "family") {
  const ownerId = await user(`reminder-${serverType}-owner`);
  const clock = { nowMs: START_MS };
  const dependencies = { db, Timestamp, clock: () => clock.nowMs };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerEventService(dependencies),
  };
  const created = await service.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType,
    templateVersion: 1,
    name: `${serverType} reminders`,
    description: "",
    privacy: "inviteOnly",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const channels = await db.doc(`clubs/${created.serverId}`)
    .collection("channels").get();
  const kind = serverType === "family" ? "calendar" : "events";
  const channel = channels.docs.find((doc) => doc.data().kind === kind);
  assert.ok(channel, `${serverType} servers need a ${kind} channel`);

  async function addMember(role = "member") {
    const uid = await user(`reminder-${role}`);
    await db.doc(`clubs/${created.serverId}/members/${uid}`).set({
      userId: uid,
      displayName: `Canonical ${uid}`,
      photoUrl: null,
      role,
      isOnline: false,
      joinedAt: Timestamp.fromMillis(clock.nowMs),
      invitedBy: ownerId,
      authorizationRevision: 1,
    });
    return uid;
  }

  async function scheduleEvent({ startsInMs = 10 * 60_000 } = {}) {
    const result = await service.createServerEventV1(request(ownerId, {
      serverId: created.serverId,
      channelId: channel.id,
      requestId: randomUUID(),
      title: "Sunday call",
      description: "Grandma is joining.",
      startsAtMillis: clock.nowMs + startsInMs,
      endsAtMillis: clock.nowMs + startsInMs + 60 * 60_000,
      timeZone: "Europe/Warsaw",
    }));
    return result;
  }

  return {
    ...created,
    ...service,
    channelId: channel.id,
    clock,
    ownerId,
    addMember,
    scheduleEvent,
    eventReference: (eventId) => db.doc(
      `clubs/${created.serverId}/channels/${channel.id}/events/${eventId}`,
    ),
  };
}

const inbox = async (uid) =>
  (await db.collection(`users/${uid}/notifications`).get()).docs;

emulatorTest("an opted-in member is reminded once per event revision",
  async () => {
    const value = await fixture();
    const member = await value.addMember();
    const event = await value.scheduleEvent();
    await value.respondToServerEventV1(request(member, {
      serverId: value.serverId,
      channelId: value.channelId,
      eventId: event.eventId,
      requestId: randomUUID(),
      expectedRevision: event.revision,
      response: "going",
      reminderRequested: true,
    }));

    const now = Timestamp.fromMillis(value.clock.nowMs);
    const first = await sendDueServerEventReminders({ firestore: db, now });
    assert.equal(first.notified, 1);
    const rows = await inbox(member);
    assert.equal(rows.length, 1);
    const row = rows[0].data();
    assert.equal(rows[0].id, reminderNotificationId(event.eventId, 1));
    assert.equal(row.type, "serverEventReminder");
    assert.equal(row.targetId, value.serverId);
    assert.equal(row.targetSubId, value.channelId);
    assert.equal(row.targetLabel, "Sunday call");
    assert.equal(row.actorId, value.ownerId);
    assert.equal(row.sourceGeneration, "1");

    // The next scheduler run five minutes later is a no-op: the event is
    // still inside the window, and the ledger refuses the second write.
    const second = await sendDueServerEventReminders({ firestore: db, now });
    assert.equal(second.notified, 0);
    assert.equal((await inbox(member)).length, 1);
  });

emulatorTest("a member who did not opt in, and one outside the window, get nothing",
  async () => {
    const value = await fixture();
    const silent = await value.addMember();
    const event = await value.scheduleEvent();
    await value.respondToServerEventV1(request(silent, {
      serverId: value.serverId,
      channelId: value.channelId,
      eventId: event.eventId,
      requestId: randomUUID(),
      expectedRevision: event.revision,
      response: "going",
      reminderRequested: false,
    }));
    const now = Timestamp.fromMillis(value.clock.nowMs);
    assert.equal(
      (await sendDueServerEventReminders({ firestore: db, now })).notified,
      0,
    );
    assert.equal((await inbox(silent)).length, 0);

    // An event further out than the horizon is not due yet.
    const distant = await fixture();
    const waiting = await distant.addMember();
    const later = await distant.scheduleEvent({
      startsInMs: REMINDER_HORIZON_MS + 60 * 60_000,
    });
    await distant.respondToServerEventV1(request(waiting, {
      serverId: distant.serverId,
      channelId: distant.channelId,
      eventId: later.eventId,
      requestId: randomUUID(),
      expectedRevision: later.revision,
      response: "going",
      reminderRequested: true,
    }));
    assert.equal(
      (await sendDueServerEventReminders({
        firestore: db,
        now: Timestamp.fromMillis(distant.clock.nowMs),
      })).notified,
      0,
    );
    assert.equal((await inbox(waiting)).length, 0);
  });

emulatorTest("someone who is not a member is never reminded", async () => {
  const value = await fixture();
  const outsider = await user("reminder-outsider");
  const event = await value.scheduleEvent();
  // The opt-in row is forged directly: a client cannot write one (rules deny
  // every write under events/), and the worker must still refuse it.
  await value.eventReference(event.eventId)
    .collection("responses").doc(outsider).set({
      schemaVersion: 1,
      serverId: value.serverId,
      channelId: value.channelId,
      eventId: event.eventId,
      userId: outsider,
      response: "going",
      reminderRequested: true,
      eventRevision: event.revision,
      operationId: randomUUID(),
      createdAt: Timestamp.fromMillis(value.clock.nowMs),
      updatedAt: Timestamp.fromMillis(value.clock.nowMs),
    });
  assert.equal(
    (await sendDueServerEventReminders({
      firestore: db,
      now: Timestamp.fromMillis(value.clock.nowMs),
    })).notified,
    0,
  );
  assert.equal((await inbox(outsider)).length, 0);
});

emulatorTest("cancelling suppresses the reminder; rescheduling re-arms it",
  async () => {
    const cancelled = await fixture();
    const member = await cancelled.addMember();
    const event = await cancelled.scheduleEvent();
    await cancelled.respondToServerEventV1(request(member, {
      serverId: cancelled.serverId,
      channelId: cancelled.channelId,
      eventId: event.eventId,
      requestId: randomUUID(),
      expectedRevision: event.revision,
      response: "going",
      reminderRequested: true,
    }));
    await cancelled.cancelServerEventV1(request(cancelled.ownerId, {
      serverId: cancelled.serverId,
      channelId: cancelled.channelId,
      eventId: event.eventId,
      requestId: randomUUID(),
      expectedRevision: event.revision,
    }));
    const now = Timestamp.fromMillis(cancelled.clock.nowMs);
    assert.equal(
      (await sendDueServerEventReminders({ firestore: db, now })).notified,
      0,
    );
    assert.equal((await inbox(member)).length, 0);
    // The push boundary refuses a row whose event was cancelled after it was
    // written, too.
    assert.equal(
      await serverEventReminderSourceIsCurrent({
        recipientId: member,
        notification: {
          type: "serverEventReminder",
          actorId: cancelled.ownerId,
          targetId: cancelled.serverId,
          targetSubId: cancelled.channelId,
          sourcePath: cancelled.eventReference(event.eventId).path,
          sourceGeneration: "1",
        },
        reader: db,
        firestore: db,
        nowMs: cancelled.clock.nowMs,
      }),
      false,
    );

    // A rescheduled event is a NEW revision, so its reminder is a new row.
    const moved = await fixture();
    const attendee = await moved.addMember();
    const original = await moved.scheduleEvent({ startsInMs: 60 * 60_000 });
    await moved.respondToServerEventV1(request(attendee, {
      serverId: moved.serverId,
      channelId: moved.channelId,
      eventId: original.eventId,
      requestId: randomUUID(),
      expectedRevision: original.revision,
      response: "going",
      reminderRequested: true,
    }));
    const update = await moved.updateServerEventV1(request(moved.ownerId, {
      serverId: moved.serverId,
      channelId: moved.channelId,
      eventId: original.eventId,
      requestId: randomUUID(),
      expectedRevision: original.revision,
      patch: {
        startsAtMillis: moved.clock.nowMs + 10 * 60_000,
        endsAtMillis: moved.clock.nowMs + 70 * 60_000,
      },
    }));
    assert.equal(update.revision, 2);
    const outcome = await sendDueServerEventReminders({
      firestore: db,
      now: Timestamp.fromMillis(moved.clock.nowMs),
    });
    assert.equal(outcome.notified, 1);
    const rows = await inbox(attendee);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].id, reminderNotificationId(original.eventId, 2));
  });

emulatorTest("the real collectionGroup query spans different parent channels",
  async () => {
    const first = await fixture("family");
    const second = await fixture("podcast");
    const dueFirst = await first.scheduleEvent();
    const dueSecond = await second.scheduleEvent();
    const now = Timestamp.fromMillis(START_MS);
    const snapshot = await dueReminderEventsQuery(db, {
      now,
      horizon: Timestamp.fromMillis(START_MS + REMINDER_HORIZON_MS),
      limit: 50,
    }).get();
    const ids = snapshot.docs.map((document) => document.id);
    assert.ok(ids.includes(dueFirst.eventId));
    assert.ok(ids.includes(dueSecond.eventId));
    // Different parents, one query: this is the property a direct-path test
    // cannot prove (ADR-007).
    const parents = new Set(
      snapshot.docs.map((document) => document.ref.parent.parent.path),
    );
    assert.ok(parents.size >= 2);
    for (const document of snapshot.docs) {
      assert.equal(document.data().status, "scheduled");
      assert.equal(document.data().reminderOptInEnabled, true);
    }
  });

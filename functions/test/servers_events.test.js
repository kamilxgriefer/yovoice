// Server events/calendar/program + RSVP: real Firestore transactions against
// the production factory registered only by the exact Servers V1 boundary.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp(
    { projectId: "demo-yovoice-servers-events" },
    `server-events-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const {
  EVENT_PROFILES,
  canonicalEventId,
  createServerEventService,
} = require("../servers/events");

const START_MS = 1_900_000_000_000;
const request = (uid, data) => ({
  auth: { uid, token: { email_verified: true } },
  data,
});
const rejection = (promise, code) => assert.rejects(
  promise,
  (error) => error.code === code,
);
const emulatorTest = (name, fn) => test(
  `Server events: ${name}`,
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

async function user(prefix = "event-user") {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${uid}`,
    status: "active",
  });
  return uid;
}

async function fixture(serverType = "friends") {
  const ownerId = await user(`event-${serverType}-owner`);
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
    name: `${serverType} events`,
    description: "",
    privacy: serverType === "community" ? "public" : "inviteOnly",
    defaultLanguage: "English",
  }));
  // Direct factories deliberately seed held graphs. Only the exact registered
  // runtime may create a brand-new graph active; this test exercises the raw
  // service in isolation and therefore activates its fixture explicitly.
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const channels = await db.doc(`clubs/${created.serverId}`)
    .collection("channels").get();
  const eventChannelKind = serverType === "family" ? "calendar" : "events";
  const eventChannel = channels.docs.find((doc) => doc.data().kind === eventChannelKind);
  const textChannel = channels.docs.find((doc) => doc.data().kind === "text");
  if (Object.hasOwn(EVENT_PROFILES, `${serverType}:${eventChannelKind}`)) {
    assert.ok(eventChannel);
  }
  assert.ok(textChannel);

  async function addMember(role = "member") {
    const uid = await user(`event-${role}`);
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

  const eventData = (overrides = {}) => ({
    serverId: created.serverId,
    channelId: eventChannel?.id ?? textChannel.id,
    requestId: randomUUID(),
    title: "Friday dinner",
    description: "Meet at seven.",
    startsAtMillis: clock.nowMs + 60 * 60_000,
    endsAtMillis: clock.nowMs + 3 * 60 * 60_000,
    timeZone: "Europe/Amsterdam",
    ...overrides,
  });
  const eventReference = (eventId) => db.doc(
    `clubs/${created.serverId}/channels/${eventChannel?.id ?? textChannel.id}/events/${eventId}`,
  );

  return {
    ...created,
    ...service,
    ownerId,
    serverType,
    clock,
    eventChannelId: eventChannel?.id ?? null,
    textChannelId: textChannel.id,
    addMember,
    eventData,
    eventReference,
  };
}

emulatorTest("creation is canonical, exact and replay-safe", async () => {
  const value = await fixture();
  const data = value.eventData();
  const result = await value.createServerEventV1(request(value.ownerId, data));
  assert.equal(result.eventId, canonicalEventId(value.ownerId, data.requestId));
  assert.equal(result.revision, 1);
  assert.equal(result.status, "scheduled");

  const stored = (await value.eventReference(result.eventId).get()).data();
  assert.equal(stored.eventKind, "friendsEvent");
  assert.equal(stored.serverType, "friends");
  assert.equal(stored.channelKind, "events");
  assert.equal(stored.rsvpEnabled, true);
  assert.equal(stored.reminderOptInEnabled, false);
  assert.equal(stored.reminderCount, 0);
  assert.equal(stored.authorId, value.ownerId);
  assert.equal(stored.startsAt.toMillis(), data.startsAtMillis);
  assert.equal(stored.endsAt.toMillis(), data.endsAtMillis);
  assert.deepEqual(stored.responseCounts, { going: 0, maybe: 0, declined: 0 });
  assert.deepEqual(
    await value.createServerEventV1(request(value.ownerId, data)),
    result,
  );

  await rejection(value.createServerEventV1(request(value.ownerId, {
    ...value.eventData(),
    unsupported: true,
  })), "invalid-argument");
  await rejection(value.createServerEventV1(request(value.ownerId, value.eventData({
    timeZone: "Mars/Olympus",
  }))), "invalid-argument");
  await rejection(value.createServerEventV1(request(value.ownerId, value.eventData({
    endsAtMillis: value.clock.nowMs + 60 * 60_000,
  }))), "invalid-argument");
  await rejection(value.createServerEventV1(request(value.ownerId, {
    ...data,
    title: "Different input",
  })), "already-exists");
});

emulatorTest("all four supported template modules derive canonical profiles", async () => {
  const profiles = [
    ["friends", "events", "friendsEvent", false],
    ["community", "events", "communityEvent", false],
    ["family", "calendar", "familyCalendarEvent", true],
    ["podcast", "events", "podcastProgramEvent", true],
  ];
  assert.deepEqual(Object.keys(EVENT_PROFILES).sort(), [
    "community:events", "family:calendar", "friends:events", "podcast:events",
  ]);
  for (const [serverType, channelKind, eventKind, reminderOptInEnabled] of profiles) {
    const value = await fixture(serverType);
    const result = await value.createServerEventV1(request(
      value.ownerId,
      value.eventData({ title: `${serverType} module event` }),
    ));
    const stored = (await value.eventReference(result.eventId).get()).data();
    assert.equal(stored.serverType, serverType);
    assert.equal(stored.channelKind, channelKind);
    assert.equal(stored.eventKind, eventKind);
    assert.equal(stored.rsvpEnabled, true);
    assert.equal(stored.reminderOptInEnabled, reminderOptInEnabled);
    assert.equal(stored.reminderCount, 0);
  }
});

emulatorTest("only a supported module with write capability accepts creation", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const outsiderId = await user("event-outsider");

  const created = await value.createServerEventV1(request(
    memberId,
    value.eventData({ title: "Member event" }),
  ));
  assert.equal(
    (await value.eventReference(created.eventId).get()).data().authorId,
    memberId,
  );
  await rejection(value.createServerEventV1(request(
    outsiderId,
    value.eventData({ title: "Outsider event" }),
  )), "permission-denied");
  await rejection(value.createServerEventV1(request(
    value.ownerId,
    value.eventData({ channelId: value.textChannelId }),
  )), "permission-denied");

  const company = await fixture("company");
  await rejection(company.createServerEventV1(request(
    company.ownerId,
    company.eventData({ channelId: company.textChannelId }),
  )), "permission-denied");
});

emulatorTest("author or moderator may update; stale revisions and foreign authors fail", async () => {
  const value = await fixture();
  const authorId = await value.addMember();
  const peerId = await value.addMember();
  const moderatorId = await value.addMember("moderator");
  const created = await value.createServerEventV1(request(
    authorId,
    value.eventData({ title: "Original" }),
  ));

  const update = {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 1,
    patch: { title: "Updated by author" },
  };
  const updated = await value.updateServerEventV1(request(authorId, update));
  assert.equal(updated.revision, 2);
  assert.deepEqual(
    await value.updateServerEventV1(request(authorId, update)),
    updated,
  );

  await rejection(value.updateServerEventV1(request(peerId, {
    ...update,
    requestId: randomUUID(),
    expectedRevision: 2,
  })), "permission-denied");
  await rejection(value.updateServerEventV1(request(authorId, {
    ...update,
    requestId: randomUUID(),
  })), "aborted");

  const moderated = await value.updateServerEventV1(request(moderatorId, {
    ...update,
    requestId: randomUUID(),
    expectedRevision: 2,
    patch: { description: "Moderator correction" },
  }));
  assert.equal(moderated.revision, 3);
  assert.equal(
    (await value.eventReference(created.eventId).get()).data().description,
    "Moderator correction",
  );
});

emulatorTest("RSVP switching and concurrent responses keep canonical counts", async () => {
  const value = await fixture();
  const firstId = await value.addMember();
  const secondId = await value.addMember();
  const created = await value.createServerEventV1(request(
    value.ownerId,
    value.eventData(),
  ));
  const respond = (uid, response, requestId = randomUUID(), expectedRevision = 1) =>
    value.respondToServerEventV1(request(uid, {
      serverId: value.serverId,
      channelId: value.eventChannelId,
      eventId: created.eventId,
      requestId,
      expectedRevision,
      response,
    }));

  const firstRequest = randomUUID();
  const first = await respond(firstId, "going", firstRequest);
  assert.equal(first.changed, true);
  assert.equal(first.reminderRequested, false);
  assert.equal(first.reminderCount, 0);
  assert.deepEqual(first.responseCounts, { going: 1, maybe: 0, declined: 0 });
  assert.deepEqual(await respond(firstId, "going", firstRequest), first);

  const [switched, second] = await Promise.all([
    respond(firstId, "maybe"),
    respond(secondId, "going"),
  ]);
  assert.equal(switched.response, "maybe");
  assert.equal(second.response, "going");
  const stored = (await value.eventReference(created.eventId).get()).data();
  assert.equal(stored.revision, 1);
  assert.deepEqual(stored.responseCounts, { going: 1, maybe: 1, declined: 0 });

  const firstResponse = (await value.eventReference(created.eventId)
    .collection("responses").doc(firstId).get()).data();
  assert.equal(firstResponse.response, "maybe");
  assert.equal(firstResponse.reminderRequested, false);
  assert.equal(firstResponse.eventRevision, 1);

  const updated = await value.updateServerEventV1(request(value.ownerId, {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 1,
    patch: { title: "New details" },
  }));
  assert.equal(updated.revision, 2);
  await rejection(respond(firstId, "declined", randomUUID(), 1), "aborted");
  const current = await respond(firstId, "declined", randomUUID(), 2);
  assert.deepEqual(current.responseCounts, { going: 1, maybe: 0, declined: 1 });
});

emulatorTest("Family and Podcast reminders are exact, counted and replay-safe", async () => {
  for (const serverType of ["family", "podcast"]) {
    const value = await fixture(serverType);
    const memberId = await value.addMember();
    const created = await value.createServerEventV1(request(
      value.ownerId,
      value.eventData(),
    ));
    const requestId = randomUUID();
    const response = {
      serverId: value.serverId,
      channelId: value.eventChannelId,
      eventId: created.eventId,
      requestId,
      expectedRevision: 1,
      response: "going",
      reminderRequested: true,
    };
    const optedIn = await value.respondToServerEventV1(request(memberId, response));
    assert.equal(optedIn.reminderRequested, true);
    assert.equal(optedIn.reminderCount, 1);
    assert.deepEqual(
      await value.respondToServerEventV1(request(memberId, response)),
      optedIn,
    );
    assert.equal(
      (await value.eventReference(created.eventId).get()).data().reminderCount,
      1,
    );
    assert.equal(
      (await value.eventReference(created.eventId)
        .collection("responses").doc(memberId).get()).data().reminderRequested,
      true,
    );

    const optedOut = await value.respondToServerEventV1(request(memberId, {
      ...response,
      requestId: randomUUID(),
      reminderRequested: false,
    }));
    assert.equal(optedOut.changed, true);
    assert.equal(optedOut.reminderCount, 0);
    assert.deepEqual(optedOut.responseCounts, { going: 1, maybe: 0, declined: 0 });
  }
});

emulatorTest("unsupported reminders and malformed response input fail closed", async () => {
  const value = await fixture("friends");
  const memberId = await value.addMember();
  const created = await value.createServerEventV1(request(
    value.ownerId,
    value.eventData(),
  ));
  const data = {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 1,
    response: "going",
  };
  await rejection(value.respondToServerEventV1(request(memberId, {
    ...data,
    reminderRequested: true,
  })), "invalid-argument");
  await rejection(value.respondToServerEventV1(request(memberId, {
    ...data,
    requestId: randomUUID(),
    reminderRequested: "true",
  })), "invalid-argument");
  await rejection(value.respondToServerEventV1(request(memberId, {
    ...data,
    requestId: randomUUID(),
    unexpected: false,
  })), "invalid-argument");
  const stored = (await value.eventReference(created.eventId).get()).data();
  assert.equal(stored.reminderCount, 0);
  assert.deepEqual(stored.responseCounts, { going: 0, maybe: 0, declined: 0 });
});

emulatorTest("cancellation is author/moderator scoped, replay-safe and closes RSVP", async () => {
  const value = await fixture();
  const authorId = await value.addMember();
  const peerId = await value.addMember();
  const created = await value.createServerEventV1(request(
    authorId,
    value.eventData(),
  ));
  const cancel = {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 1,
  };
  await rejection(value.cancelServerEventV1(request(peerId, cancel)), "permission-denied");

  // Cancellation narrows state and remains available during a communication
  // restriction, matching invite revocation and other safety exits.
  await db.doc(`restrictions/${authorId}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  const cancelled = await value.cancelServerEventV1(request(authorId, cancel));
  assert.equal(cancelled.cancelled, true);
  assert.equal(cancelled.revision, 2);
  assert.deepEqual(
    await value.cancelServerEventV1(request(authorId, cancel)),
    cancelled,
  );
  await rejection(value.respondToServerEventV1(request(peerId, {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 2,
    response: "going",
  })), "failed-precondition");
});

emulatorTest("an event stops accepting edits and responses once it starts", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const created = await value.createServerEventV1(request(
    memberId,
    value.eventData(),
  ));
  value.clock.nowMs += 61 * 60_000;
  await rejection(value.updateServerEventV1(request(memberId, {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 1,
    patch: { title: "Too late" },
  })), "failed-precondition");
  await rejection(value.respondToServerEventV1(request(memberId, {
    serverId: value.serverId,
    channelId: value.eventChannelId,
    eventId: created.eventId,
    requestId: randomUUID(),
    expectedRevision: 1,
    response: "going",
  })), "failed-precondition");
});

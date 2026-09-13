// Company Whiteboard V1: real Firestore transactions against the production
// factory. Rules, registration and bounded deletion have separate gates.
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
    { projectId: "demo-yovoice-server-whiteboard" },
    `server-whiteboard-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const {
  createServerContentCleanupService,
  deletionCleanupState,
} = require("../servers/content_cleanup");
const {
  canonicalStrokeId,
  createServerWhiteboardService,
} = require("../servers/whiteboard");

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
  `Server whiteboard: ${name}`,
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

async function user(prefix = "whiteboard-user") {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${uid}`,
    status: "active",
  });
  return uid;
}

async function fixture() {
  const ownerId = await user("whiteboard-owner");
  const clock = { nowMs: START_MS };
  const dependencies = { db, Timestamp, clock: () => clock.nowMs };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerWhiteboardService(dependencies),
  };
  const created = await service.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType: "company",
    templateVersion: 1,
    name: "Persistent whiteboard",
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
  const whiteboard = channels.docs.find((document) =>
    document.data().kind === "whiteboard");
  const general = channels.docs.find((document) => document.data().kind === "text");
  assert.ok(whiteboard);
  assert.ok(general);

  async function addMember(role = "member") {
    const uid = await user(`whiteboard-${role}`);
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

  const strokeData = (overrides = {}) => ({
    serverId: created.serverId,
    channelId: whiteboard.id,
    requestId: randomUUID(),
    color: "blue",
    lineWidth: 4,
    points: [
      { x: 0.125, y: 0.25 },
      { x: 0.75, y: 0.875 },
    ],
    ...overrides,
  });
  const stateReference = whiteboard.ref.collection("whiteboardState").doc("main");
  const strokes = whiteboard.ref.collection("whiteboardStrokes");

  return {
    ...created,
    ...service,
    ownerId,
    clock,
    whiteboardChannelId: whiteboard.id,
    generalChannelId: general.id,
    stateReference,
    strokes,
    addMember,
    strokeData,
  };
}

emulatorTest("a member creates one canonical immutable polyline", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const guestId = await value.addMember("guest");
  const outsiderId = await user("whiteboard-outsider");
  const data = value.strokeData();

  const created = await value.createServerWhiteboardStrokeV1(request(memberId, data));
  assert.equal(created.strokeId, canonicalStrokeId(memberId, data.requestId));
  assert.equal(created.generation, 1);
  assert.equal(created.sequence, 1);
  assert.equal(created.revision, 1);
  assert.equal(created.boardRevision, 1);
  assert.deepEqual(
    await value.createServerWhiteboardStrokeV1(request(memberId, data)),
    created,
  );
  const stroke = (await value.strokes.doc(created.strokeId).get()).data();
  assert.equal(stroke.authorId, memberId);
  assert.equal(stroke.strokeKind, "polyline");
  assert.deepEqual(stroke.points, data.points);
  assert.equal(stroke.color, "blue");
  assert.equal(stroke.lineWidth, 4);
  const state = (await value.stateReference.get()).data();
  assert.equal(state.generation, 1);
  assert.equal(state.revision, 1);
  assert.equal(state.strokeCount, 1);
  assert.equal(state.nextSequence, 2);

  await rejection(value.createServerWhiteboardStrokeV1(request(memberId, {
    ...value.strokeData(),
    unsupported: true,
  })), "invalid-argument");
  await rejection(value.createServerWhiteboardStrokeV1(request(memberId, value.strokeData({
    points: [{ x: 0, y: 0 }, { x: 1.01, y: 1 }],
  }))), "invalid-argument");
  await rejection(value.createServerWhiteboardStrokeV1(request(memberId, value.strokeData({
    color: "#123456",
  }))), "invalid-argument");
  await rejection(value.createServerWhiteboardStrokeV1(request(memberId, value.strokeData({
    lineWidth: 17,
  }))), "invalid-argument");
  await rejection(value.createServerWhiteboardStrokeV1(request(memberId, value.strokeData({
    channelId: value.generalChannelId,
  }))), "permission-denied");
  await rejection(value.createServerWhiteboardStrokeV1(request(guestId, value.strokeData())),
    "permission-denied");
  await rejection(value.createServerWhiteboardStrokeV1(request(outsiderId, value.strokeData())),
    "permission-denied");
  await rejection(value.createServerWhiteboardStrokeV1(request(memberId, {
    ...data,
    color: "red",
  })), "already-exists");
});

emulatorTest("concurrent strokes receive unique ordered sequences", async () => {
  const value = await fixture();
  const members = await Promise.all([
    value.addMember(),
    value.addMember(),
    value.addMember(),
    value.addMember(),
  ]);
  const created = await Promise.all(members.map((uid, index) => {
    const data = value.strokeData({
      color: index % 2 === 0 ? "ink" : "purple",
    });
    return value.createServerWhiteboardStrokeV1(request(uid, data));
  }));
  assert.deepEqual(created.map((entry) => entry.sequence).sort((a, b) => a - b), [1, 2, 3, 4]);
  const state = (await value.stateReference.get()).data();
  assert.equal(state.strokeCount, 4);
  assert.equal(state.revision, 4);
  assert.equal(state.nextSequence, 5);
  const rows = await value.strokes.orderBy("sequence").get();
  assert.deepEqual(rows.docs.map((row) => row.data().sequence), [1, 2, 3, 4]);
});

emulatorTest("undo removes only the caller's stroke and replays exactly", async () => {
  const value = await fixture();
  const firstId = await value.addMember();
  const secondId = await value.addMember();
  const first = await value.createServerWhiteboardStrokeV1(
    request(firstId, value.strokeData()),
  );
  const second = await value.createServerWhiteboardStrokeV1(
    request(secondId, value.strokeData({ color: "green" })),
  );
  const foreignUndo = {
    serverId: value.serverId,
    channelId: value.whiteboardChannelId,
    strokeId: second.strokeId,
    requestId: randomUUID(),
    expectedRevision: second.revision,
  };
  await rejection(value.undoServerWhiteboardStrokeV1(request(firstId, foreignUndo)),
    "permission-denied");
  await rejection(value.undoServerWhiteboardStrokeV1(request(value.ownerId, {
    ...foreignUndo,
    requestId: randomUUID(),
  })), "permission-denied");

  const ownUndo = {
    serverId: value.serverId,
    channelId: value.whiteboardChannelId,
    strokeId: first.strokeId,
    requestId: randomUUID(),
    expectedRevision: first.revision,
  };
  const undone = await value.undoServerWhiteboardStrokeV1(request(firstId, ownUndo));
  assert.equal(undone.undone, true);
  assert.equal(undone.boardRevision, 3);
  assert.equal((await value.strokes.doc(first.strokeId).get()).exists, false);
  assert.equal((await value.strokes.doc(second.strokeId).get()).exists, true);
  assert.equal((await value.stateReference.get()).data().strokeCount, 1);
  assert.deepEqual(
    await value.undoServerWhiteboardStrokeV1(request(firstId, ownUndo)),
    undone,
  );
});

emulatorTest("a manager clears the observed revision and replay never erases newer ink", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const memberStroke = await value.createServerWhiteboardStrokeV1(
    request(memberId, value.strokeData()),
  );
  await value.createServerWhiteboardStrokeV1(
    request(value.ownerId, value.strokeData({ color: "red" })),
  );
  const before = (await value.stateReference.get()).data();
  const clear = {
    serverId: value.serverId,
    channelId: value.whiteboardChannelId,
    requestId: randomUUID(),
    expectedRevision: before.revision,
  };
  await rejection(value.clearServerWhiteboardV1(request(memberId, clear)),
    "permission-denied");
  await rejection(value.clearServerWhiteboardV1(request(value.ownerId, {
    ...clear,
    requestId: randomUUID(),
    expectedRevision: before.revision - 1,
  })), "aborted");

  const cleared = await value.clearServerWhiteboardV1(request(value.ownerId, clear));
  assert.equal(cleared.cleared, true);
  assert.equal(cleared.deletedCount, 2);
  assert.equal(cleared.generation, 2);
  assert.equal(cleared.revision, 3);
  assert.equal((await value.strokes.get()).size, 0);
  assert.equal((await value.stateReference.get()).data().strokeCount, 0);

  const newer = await value.createServerWhiteboardStrokeV1(
    request(memberId, value.strokeData({ color: "orange" })),
  );
  assert.equal(newer.generation, 2);
  assert.deepEqual(
    await value.clearServerWhiteboardV1(request(value.ownerId, clear)),
    cleared,
  );
  assert.equal((await value.strokes.doc(newer.strokeId).get()).exists, true);
  assert.equal((await value.strokes.doc(memberStroke.strokeId).get()).exists, false);
});

emulatorTest("channel cleanup drains strokes and state before deleting the board", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  await value.createServerWhiteboardStrokeV1(
    request(memberId, value.strokeData()),
  );
  await value.createServerWhiteboardStrokeV1(
    request(value.ownerId, value.strokeData({ color: "purple" })),
  );

  const channelReference = db.doc(
    `clubs/${value.serverId}/channels/${value.whiteboardChannelId}`,
  );
  const channel = (await channelReference.get()).data();
  const operationId = randomUUID();
  const deletionRevision = channel.revision + 1;
  await channelReference.update({
    status: "deleting",
    deletionOperationId: operationId,
    revision: deletionRevision,
  });
  await db.doc(`serverControlOutbox/${operationId}`).set({
    kind: "channelDelete",
    operationId,
    serverId: value.serverId,
    channelId: value.whiteboardChannelId,
    roomId: channel.roomId,
    requestedBy: value.ownerId,
    status: "pending",
    grantStatus: "completed",
    rtcStatus: "completed",
    rtcTargets: [],
    rtcTargetIndex: 0,
    bridgeLeaseId: null,
    contentCleanupPending: true,
    ...deletionCleanupState("channelDelete", {
      deletionRevision,
      ownerId: value.ownerId,
      roomId: channel.roomId,
    }),
  });

  const cleanup = createServerContentCleanupService({
    db,
    Timestamp,
    clock: () => value.clock.nowMs,
  });
  let outcome;
  for (let page = 0; page < 40; page += 1) {
    outcome = await cleanup.processServerContentCleanupPage({
      operationId,
      pageSize: 1,
    });
    if (!outcome.contentCleanupPending) break;
  }
  assert.equal(outcome.contentCleanupPending, false);
  assert.equal((await channelReference.get()).exists, false);
  assert.equal((await value.strokes.get()).size, 0);
  assert.equal((await value.stateReference.get()).exists, false);
  const job = (await db.doc(`serverControlOutbox/${operationId}`).get()).data();
  assert.equal(job.status, "completed");
});

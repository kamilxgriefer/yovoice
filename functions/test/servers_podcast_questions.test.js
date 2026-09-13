// Podcast Questions/Q&A: real Firestore transactions against the production
// service factory. Registration and Rules have their own boundary tests.
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
    { projectId: "demo-yovoice-server-podcast-questions" },
    `server-podcast-questions-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const {
  createServerContentCleanupService,
  deletionCleanupState,
} = require("../servers/content_cleanup");
const {
  canonicalQuestionId,
  createServerPodcastQuestionService,
} = require("../servers/podcast_questions");

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
  `Server podcast questions: ${name}`,
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

async function user(prefix = "podcast-question-user") {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${uid}`,
    status: "active",
  });
  return uid;
}

async function fixture() {
  const ownerId = await user("podcast-question-owner");
  const clock = { nowMs: START_MS };
  const dependencies = { db, Timestamp, clock: () => clock.nowMs };
  const service = {
    ...createServerCreationService(dependencies),
    ...createServerPodcastQuestionService(dependencies),
  };
  const created = await service.createServerV1(request(ownerId, {
    requestId: randomUUID(),
    serverType: "podcast",
    templateVersion: 1,
    name: "Podcast questions",
    description: "",
    privacy: "public",
    defaultLanguage: "English",
  }));
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const channels = await db.doc(`clubs/${created.serverId}`)
    .collection("channels").get();
  const questions = channels.docs.find((doc) => doc.data().kind === "questions");
  const discussion = channels.docs.find((doc) => doc.data().kind === "text");
  assert.ok(questions);
  assert.ok(discussion);

  async function addMember(role = "member") {
    const uid = await user(`podcast-question-${role}`);
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

  const questionData = (overrides = {}) => ({
    serverId: created.serverId,
    channelId: questions.id,
    requestId: randomUUID(),
    body: "How did this episode begin?",
    ...overrides,
  });
  const questionReference = (questionId) => questions.ref
    .collection("questions").doc(questionId);

  return {
    ...created,
    ...service,
    ownerId,
    clock,
    questionsChannelId: questions.id,
    discussionChannelId: discussion.id,
    addMember,
    questionData,
    questionReference,
  };
}

async function createQuestion(value, uid = value.ownerId, overrides = {}) {
  const data = value.questionData(overrides);
  const result = await value.createServerPodcastQuestionV1(request(uid, data));
  return { data, result };
}

emulatorTest("creation is canonical, exact, authorized and replay-safe", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const guestId = await value.addMember("guest");
  const outsiderId = await user("podcast-question-outsider");
  const data = value.questionData({ body: "  How do you prepare a guest?  " });

  const result = await value.createServerPodcastQuestionV1(request(memberId, data));
  assert.equal(result.questionId, canonicalQuestionId(memberId, data.requestId));
  assert.equal(result.status, "queued");
  assert.equal(result.revision, 1);
  assert.deepEqual(
    await value.createServerPodcastQuestionV1(request(memberId, data)),
    result,
  );
  const stored = (await value.questionReference(result.questionId).get()).data();
  assert.equal(stored.questionKind, "podcastQuestion");
  assert.equal(stored.authorId, memberId);
  assert.equal(stored.authorName, `Canonical ${memberId}`);
  assert.equal(stored.body, "How do you prepare a guest?");
  assert.equal(stored.voteCount, 0);
  assert.equal(stored.status, "queued");
  assert.equal(stored.onAirAt, null);
  assert.equal(stored.onAirById, null);

  await rejection(value.createServerPodcastQuestionV1(request(memberId, {
    ...value.questionData(),
    unsupported: true,
  })), "invalid-argument");
  await rejection(value.createServerPodcastQuestionV1(request(memberId, value.questionData({
    body: "\u0000invalid",
  }))), "invalid-argument");
  await rejection(value.createServerPodcastQuestionV1(request(memberId, value.questionData({
    channelId: value.discussionChannelId,
  }))), "permission-denied");
  await rejection(value.createServerPodcastQuestionV1(request(guestId, value.questionData())),
    "permission-denied");
  await rejection(value.createServerPodcastQuestionV1(request(outsiderId, value.questionData())),
    "permission-denied");
  await rejection(value.createServerPodcastQuestionV1(request(memberId, {
    ...data,
    body: "A different replay",
  })), "already-exists");
});

emulatorTest("one UID owns one vote and the aggregate remains exact", async () => {
  const value = await fixture();
  const firstId = await value.addMember();
  const secondId = await value.addMember();
  const { result: question } = await createQuestion(value);
  const vote = (voted, overrides = {}) => ({
    serverId: value.serverId,
    channelId: value.questionsChannelId,
    questionId: question.questionId,
    requestId: randomUUID(),
    expectedRevision: question.revision,
    voted,
    ...overrides,
  });

  const firstVote = vote(true);
  const first = await value.setServerPodcastQuestionVoteV1(request(firstId, firstVote));
  assert.equal(first.changed, true);
  assert.equal(first.voteCount, 1);
  assert.deepEqual(
    await value.setServerPodcastQuestionVoteV1(request(firstId, firstVote)),
    first,
  );
  const duplicate = await value.setServerPodcastQuestionVoteV1(
    request(firstId, vote(true)),
  );
  assert.equal(duplicate.changed, false);
  assert.equal(duplicate.voteCount, 1);

  const second = await value.setServerPodcastQuestionVoteV1(
    request(secondId, vote(true)),
  );
  assert.equal(second.voteCount, 2);
  const removed = await value.setServerPodcastQuestionVoteV1(
    request(firstId, vote(false)),
  );
  assert.equal(removed.changed, true);
  assert.equal(removed.voteCount, 1);
  const unchangedRemoval = await value.setServerPodcastQuestionVoteV1(
    request(firstId, vote(false)),
  );
  assert.equal(unchangedRemoval.changed, false);
  assert.equal(unchangedRemoval.voteCount, 1);

  const stored = (await value.questionReference(question.questionId).get()).data();
  assert.equal(stored.voteCount, 1);
  const votes = await value.questionReference(question.questionId).collection("votes").get();
  assert.equal(votes.size, 2);
  assert.equal(votes.docs.find((doc) => doc.id === firstId).data().active, false);
  assert.equal(votes.docs.find((doc) => doc.id === secondId).data().active, true);
});

emulatorTest("concurrent member votes serialize without losing a count", async () => {
  const value = await fixture();
  const members = await Promise.all([
    value.addMember(),
    value.addMember(),
    value.addMember(),
    value.addMember(),
  ]);
  const { result: question } = await createQuestion(value);
  await Promise.all(members.map((uid) => value.setServerPodcastQuestionVoteV1(request(uid, {
    serverId: value.serverId,
    channelId: value.questionsChannelId,
    questionId: question.questionId,
    requestId: randomUUID(),
    expectedRevision: question.revision,
    voted: true,
  }))));
  const stored = (await value.questionReference(question.questionId).get()).data();
  assert.equal(stored.voteCount, members.length);
});

emulatorTest("moderators alone select or clear the one on-air question", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const moderatorId = await value.addMember("moderator");
  const { result: first } = await createQuestion(value, memberId, { body: "First?" });
  const { result: second } = await createQuestion(value, value.ownerId, { body: "Second?" });
  const input = (question, onAir, overrides = {}) => ({
    serverId: value.serverId,
    channelId: value.questionsChannelId,
    questionId: question.questionId,
    requestId: randomUUID(),
    expectedRevision: question.revision,
    onAir,
    ...overrides,
  });

  await rejection(value.setServerPodcastQuestionOnAirV1(
    request(memberId, input(first, true)),
  ), "permission-denied");
  const selectedFirst = await value.setServerPodcastQuestionOnAirV1(
    request(moderatorId, input(first, true)),
  );
  assert.equal(selectedFirst.onAir, true);
  assert.equal(selectedFirst.revision, 2);
  const selectedSecond = await value.setServerPodcastQuestionOnAirV1(
    request(moderatorId, input(second, true)),
  );
  assert.equal(selectedSecond.previousQuestionId, first.questionId);
  assert.equal(selectedSecond.revision, 2);
  const firstStored = (await value.questionReference(first.questionId).get()).data();
  const secondStored = (await value.questionReference(second.questionId).get()).data();
  assert.equal(firstStored.status, "queued");
  assert.equal(firstStored.revision, 3);
  assert.equal(secondStored.status, "onAir");
  assert.equal(secondStored.onAirById, moderatorId);
  assert.equal(secondStored.onAirAt.toMillis(), START_MS);

  await rejection(value.setServerPodcastQuestionOnAirV1(request(moderatorId, input(
    { ...second, revision: 1 }, false,
  ))), "aborted");
  const cleared = await value.setServerPodcastQuestionOnAirV1(request(moderatorId, input(
    { ...second, revision: 2 }, false,
  )));
  assert.equal(cleared.onAir, false);
  assert.equal(cleared.revision, 3);
  assert.equal((await value.questionReference(second.questionId).get()).data().status, "queued");
  assert.equal((await value.questionReference(second.questionId).get()).data().onAirAt, null);
});

emulatorTest("question revision fences votes after an on-air transition", async () => {
  const value = await fixture();
  const memberId = await value.addMember();
  const moderatorId = await value.addMember("moderator");
  const { result: question } = await createQuestion(value);
  await value.setServerPodcastQuestionOnAirV1(request(moderatorId, {
    serverId: value.serverId,
    channelId: value.questionsChannelId,
    questionId: question.questionId,
    requestId: randomUUID(),
    expectedRevision: question.revision,
    onAir: true,
  }));
  await rejection(value.setServerPodcastQuestionVoteV1(request(memberId, {
    serverId: value.serverId,
    channelId: value.questionsChannelId,
    questionId: question.questionId,
    requestId: randomUUID(),
    expectedRevision: question.revision,
    voted: true,
  })), "aborted");
});

emulatorTest("channel cleanup drains every private vote before its question", async () => {
  const value = await fixture();
  const members = await Promise.all([value.addMember(), value.addMember()]);
  const { result: question } = await createQuestion(value);
  for (const uid of members) {
    await value.setServerPodcastQuestionVoteV1(request(uid, {
      serverId: value.serverId,
      channelId: value.questionsChannelId,
      questionId: question.questionId,
      requestId: randomUUID(),
      expectedRevision: question.revision,
      voted: true,
    }));
  }

  const channelReference = db.doc(
    `clubs/${value.serverId}/channels/${value.questionsChannelId}`,
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
    channelId: value.questionsChannelId,
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
  for (let page = 0; page < 30; page += 1) {
    outcome = await cleanup.processServerContentCleanupPage({
      operationId,
      pageSize: 1,
    });
    if (!outcome.contentCleanupPending) break;
  }
  assert.equal(outcome.contentCleanupPending, false);
  assert.equal((await channelReference.get()).exists, false);
  assert.equal((await value.questionReference(question.questionId).get()).exists, false);
  assert.equal(
    (await value.questionReference(question.questionId).collection("votes").get()).size,
    0,
  );
  const storedJob = (await db.doc(`serverControlOutbox/${operationId}`).get()).data();
  assert.equal(storedJob.status, "completed");
  assert.equal(storedJob.contentCleanupPending, false);
});
